class Standard
  # @!group SpaceType

  # Returns standards data for selected space type and template
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @return [Hash] hash of internal loads for different load types
  def space_type_get_standards_data(space_type)
    standards_building_type = if space_type.standardsBuildingType.is_initialized
                                space_type.standardsBuildingType.get
                              end
    standards_space_type = if space_type.standardsSpaceType.is_initialized
                             space_type.standardsSpaceType.get
                           end

    # populate search hash
    search_criteria = {
      'template' => template,
      'building_type' => standards_building_type,
      'space_type' => standards_space_type
    }

    # lookup space type properties
    space_type_properties = model_find_object(standards_data['space_types'], search_criteria)

    if space_type_properties.nil? || space_type_properties.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', "Space type properties lookup failed: #{search_criteria}.")
      space_type_properties = {}
    end

    return space_type_properties
  end

  def interior_lighting_get_prm_data(space_type)
    standards_space_type = if space_type.is_a? String
                             space_type
                           elsif space_type.standardsSpaceType.is_initialized
                             space_type.standardsSpaceType.get
                           end

    # populate search hash
    search_criteria = {
      'template' => template,
      'lpd_space_type' => standards_space_type
    }

    # lookup space type properties
    interior_lighting_properties = model_find_object(standards_data['prm_interior_lighting'], search_criteria)

    if interior_lighting_properties.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', "Interior lighting PRM properties lookup failed: #{search_criteria}. Trying to search with primary_space_type. It is highly recommended to update the standard space type to one of the lighting types listed in: https://pnnl.github.io/BEM-for-PRM/user_guide/model_requirements/standards_space_type/")
      search_criteria = {
        'template' => template,
        'primary_space_type' => standards_space_type
      }
      interior_lighting_properties = model_find_object(standards_data['prm_interior_lighting'], search_criteria)
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SpaceType', "Interior Lighting PRM properties lookup failed: #{search_criteria}")
      interior_lighting_properties = {}
    end

    return interior_lighting_properties
  end

  # Sets the color for the space types as shown in the SketchUp plugin using render by space type.
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_rendering_color(space_type)
    # Get the standards data
    space_type_properties = space_type_get_standards_data(space_type)

    # Set the rendering color of the space type
    rgb = space_type_properties['rgb']
    if rgb.nil?
      return false
    end

    rgb = rgb.split('_')
    r = rgb[0].to_i
    g = rgb[1].to_i
    b = rgb[2].to_i
    rendering_color = OpenStudio::Model::RenderingColor.new(space_type.model)
    rendering_color.setName(space_type.name.get)
    rendering_color.setRenderingRedValue(r)
    rendering_color.setRenderingGreenValue(g)
    rendering_color.setRenderingBlueValue(b)
    space_type.setRenderingColor(rendering_color)

    return true
  end

  # Sets the selected internal loads to standards-based or typical values.
  # For each category that is selected get all load instances. Remove all
  # but the first instance if multiple instances.  Add a new instance/definition
  # if no instance exists. Modify the definition for the remaining instance
  # to have the specified values. This method does not alter any
  # loads directly assigned to spaces.  This method skips plenums.
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @param set_people [Boolean] if true, set the people density. occupancy values are in the ventilation standard.
  #   Also, assign reasonable clothing, air velocity, and work efficiency inputs
  #   to allow reasonable thermal comfort metrics to be calculated.
  # @param set_lights [Boolean] if true, set the lighting density, lighting fraction
  #   to return air, fraction radiant, and fraction visible.
  # @param set_electric_equipment [Boolean] if true, set the electric equipment density
  # @param set_gas_equipment [Boolean] if true, set the gas equipment density
  # @param set_ventilation [Boolean] if true, set the ventilation rates (per-person and per-area)
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_internal_loads(space_type, set_people: true, set_lights: true, set_electric_equipment: true, set_gas_equipment: true, set_ventilation: true)
    # Skip plenums
    if space_type.name.get.to_s.downcase.include?('plenum')
      return false
    end

    if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')
      return false
    end

    # Get the standards data
    space_type_properties = space_type_get_standards_data(space_type)

    # Need to add a check, or it'll crash on space_type_properties['occupancy_per_area'].to_f below
    if space_type_properties.nil? || space_type_properties.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} was not found in the standards data.")
      return false
    end

    # People
    space_type_apply_people(space_type) if set_people

    # Lights
    lights_have_info = false
    lighting_per_area = space_type_properties['lighting_per_area'].to_f
    lighting_per_person = space_type_properties['lighting_per_person'].to_f
    lights_frac_to_return_air = space_type_properties['lighting_fraction_to_return_air']
    lights_frac_radiant = space_type_properties['lighting_fraction_radiant']
    lights_frac_visible = space_type_properties['lighting_fraction_visible']
    lights_frac_replaceable = space_type_properties['lighting_fraction_replaceable'].to_f
    lights_frac_linear_fluorescent = space_type_properties['lpd_fraction_linear_fluorescent']
    lights_frac_compact_fluorescent = space_type_properties['lpd_fraction_compact_fluorescent']
    lights_frac_high_bay = space_type_properties['lpd_fraction_high_bay']
    lights_frac_specialty_lighting = space_type_properties['lpd_fraction_specialty_lighting']
    lights_frac_exit_lighting = space_type_properties['lpd_fraction_exit_lighting']
    lights_have_info = true unless lighting_per_area.zero? && lighting_per_person.zero?

    if set_lights && lights_have_info

      # Remove all but the first instance
      instances = space_type.lights.sort
      if instances.empty?
        definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        definition.setName("#{space_type.name} Lights Definition")
        instance = OpenStudio::Model::Lights.new(definition)
        instance.setName("#{space_type.name} Lights")
        instance.setSpaceType(space_type)
        instance.setFractionReplaceable(lights_frac_replaceable)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no lights, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance
      space_type.lights.sort.each do |inst|
        inst.setFractionReplaceable(lights_frac_replaceable)
        definition = inst.lightsDefinition
        unless lighting_per_area.zero?
          occ_sens_lpd_factor = 1.0
          definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area.to_f * occ_sens_lpd_factor, 'W/ft^2', 'W/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area} W/ft^2.")
        end
        unless lighting_per_person.zero?
          definition.setWattsperPerson(OpenStudio.convert(lighting_per_person.to_f, 'W/person', 'W/person').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set lighting to #{lighting_per_person} W/person.")
        end
        definition.setReturnAirFraction(lights_frac_to_return_air.to_f) if lights_frac_to_return_air
        definition.setFractionRadiant(lights_frac_radiant.to_f) if lights_frac_radiant
        definition.setFractionVisible(lights_frac_visible.to_f) if lights_frac_visible
        # definition.setFractionReplaceable(lights_frac_replaceable) if lights_frac_replaceable
        definition.additionalProperties.setFeature('lpd_fraction_linear_fluorescent', lights_frac_linear_fluorescent.to_f) if lights_frac_linear_fluorescent
        definition.additionalProperties.setFeature('lpd_fraction_compact_fluorescent', lights_frac_compact_fluorescent.to_f) if lights_frac_compact_fluorescent
        definition.additionalProperties.setFeature('lpd_fraction_high_bay', lights_frac_high_bay.to_f) if lights_frac_high_bay
        definition.additionalProperties.setFeature('lpd_fraction_specialty_lighting', lights_frac_specialty_lighting.to_f) if lights_frac_specialty_lighting
        definition.additionalProperties.setFeature('lpd_fraction_exit_lighting', lights_frac_exit_lighting.to_f) if lights_frac_exit_lighting
      end

      # If additional lights are specified, add those too
      additional_lighting_per_area = space_type_properties['additional_lighting_per_area'].to_f
      unless additional_lighting_per_area.zero?
        # Create the lighting definition
        additional_lights_def = OpenStudio::Model::LightsDefinition.new(space_type.model)
        additional_lights_def.setName("#{space_type.name} Additional Lights Definition")
        additional_lights_def.setWattsperSpaceFloorArea(OpenStudio.convert(additional_lighting_per_area.to_f, 'W/ft^2', 'W/m^2').get)
        additional_lights_def.setReturnAirFraction(lights_frac_to_return_air)
        additional_lights_def.setFractionRadiant(lights_frac_radiant)
        additional_lights_def.setFractionVisible(lights_frac_visible)

        # By default, all additional lighting is specialty lighting
        additional_lights_def.additionalProperties.setFeature('lpd_fraction_linear_fluorescent', 0.0)
        additional_lights_def.additionalProperties.setFeature('lpd_fraction_compact_fluorescent', 0.0)
        additional_lights_def.additionalProperties.setFeature('lpd_fraction_high_bay', 0.0)
        additional_lights_def.additionalProperties.setFeature('lpd_fraction_specialty_lighting', 1.0)
        additional_lights_def.additionalProperties.setFeature('lpd_fraction_exit_lighting', 0.0)

        # Create the lighting instance and hook it up to the space type
        additional_lights = OpenStudio::Model::Lights.new(additional_lights_def)
        additional_lights.setName("#{space_type.name} Additional Lights")
        additional_lights.setSpaceType(space_type)
      end

    end

    # Electric Equipment
    elec_equip_have_info = false
    elec_equip_per_area = space_type_properties['electric_equipment_per_area'].to_f
    elec_equip_frac_latent = space_type_properties['electric_equipment_fraction_latent']
    elec_equip_frac_radiant = space_type_properties['electric_equipment_fraction_radiant']
    elec_equip_frac_lost = space_type_properties['electric_equipment_fraction_lost']
    elec_equip_have_info = true unless elec_equip_per_area.zero?

    if set_electric_equipment && elec_equip_have_info

      # Remove all but the first instance
      instances = space_type.electricEquipment.sort
      if instances.empty?
        definition = OpenStudio::Model::ElectricEquipmentDefinition.new(space_type.model)
        definition.setName("#{space_type.name} Elec Equip Definition")
        instance = OpenStudio::Model::ElectricEquipment.new(definition)
        instance.setName("#{space_type.name} Elec Equip")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no electric equipment, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance
      space_type.electricEquipment.sort.each do |inst|
        definition = inst.electricEquipmentDefinition
        unless elec_equip_per_area.zero?
          definition.setWattsperSpaceFloorArea(OpenStudio.convert(elec_equip_per_area.to_f, 'W/ft^2', 'W/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set electric EPD to #{elec_equip_per_area} W/ft^2.")
        end
        definition.resetFractionLatent unless definition.isFractionLatentDefaulted
        definition.resetFractionRadiant unless definition.isFractionRadiantDefaulted
        definition.resetFractionLost unless definition.isFractionLostDefaulted
        definition.setFractionLatent(elec_equip_frac_latent.to_f) if elec_equip_frac_latent
        definition.setFractionRadiant(elec_equip_frac_radiant.to_f) if elec_equip_frac_radiant
        definition.setFractionLost(elec_equip_frac_lost.to_f) if elec_equip_frac_lost
      end

    end

    # Gas Equipment
    gas_equip_have_info = false
    gas_equip_per_area = space_type_properties['gas_equipment_per_area'].to_f
    gas_equip_frac_latent = space_type_properties['gas_equipment_fraction_latent']
    gas_equip_frac_radiant = space_type_properties['gas_equipment_fraction_radiant']
    gas_equip_frac_lost = space_type_properties['gas_equipment_fraction_lost']
    gas_equip_have_info = true unless gas_equip_per_area.zero?

    if set_gas_equipment && gas_equip_have_info

      # Remove all but the first instance
      instances = space_type.gasEquipment.sort
      if instances.empty?
        definition = OpenStudio::Model::GasEquipmentDefinition.new(space_type.model)
        definition.setName("#{space_type.name} Gas Equip Definition")
        instance = OpenStudio::Model::GasEquipment.new(definition)
        instance.setName("#{space_type.name} Gas Equip")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no gas equipment, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance
      space_type.gasEquipment.sort.each do |inst|
        definition = inst.gasEquipmentDefinition
        unless gas_equip_per_area.zero?
          definition.setWattsperSpaceFloorArea(OpenStudio.convert(gas_equip_per_area.to_f, 'Btu/hr*ft^2', 'W/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set gas EPD to #{gas_equip_per_area} Btu/hr*ft^2.")
        end
        definition.resetFractionLatent unless definition.isFractionLatentDefaulted
        definition.resetFractionRadiant unless definition.isFractionRadiantDefaulted
        definition.resetFractionLost unless definition.isFractionLostDefaulted
        definition.setFractionLatent(gas_equip_frac_latent.to_f) if gas_equip_frac_latent
        definition.setFractionRadiant(gas_equip_frac_radiant.to_f) if gas_equip_frac_radiant
        definition.setFractionLost(gas_equip_frac_lost.to_f) if gas_equip_frac_lost
      end

    end

    # Ventilation
    space_type_apply_ventilation(space_type) if set_ventilation

    return true
  end

  # Sets the internal loads for Appendix G PRM for 2016 and later
  # Initially, only lighting power density will be set
  # Possibly infiltration will also be set from here
  #
  # @param space_type [OpenStudio::Model::SpaceType] OpenStudio space type object
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_int_loads_prm(space_type, model)
    # Skip plenums
    # Check if the space type name
    # contains the word plenum.
    if space_type.name.get.to_s.downcase.include?('plenum')
      return false
    end

    if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')
      return false
    end

    # Get the standards data
    space_type_properties = interior_lighting_get_prm_data(space_type)

    # Need to add a check, or it'll crash on space_type_properties['occupancy_per_area'].to_f below
    if space_type_properties.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} was not found in the standards data.")
      return false
    end

    # Lights
    lights_have_info = false
    lighting_per_area = space_type_properties['w/ft^2'].to_f
    lighting_per_length = space_type_properties['w/ft'].to_f
    lights_have_info = true unless lighting_per_area.zero? && lighting_per_length.zero?
    multiple_lpd_value_check = false

    if lighting_per_length > 0
      if space_type.spaces.size == 1
        # Space height
        space = space_type.spaces[0]
        space_volume = space.volume
        space_area = space.floorArea
        space_height = space_volume / space_area
        # New lpd value
        lighting_per_area += lighting_per_length * space_height
      else
        lighting_per_area_hash = {}
        multiple_lpd_value_check = true
        space_type.spaces.each do |space_type_space|
          # Space height
          space_volume = space_type_space.volume
          space_area = space_type_space.floorArea
          space_height = space_volume / space_area
          # New lpd values
          lighting_per_area_new = lighting_per_area + (lighting_per_length * space_height)
          lighting_per_area_hash[space_type_space.name.to_s] = lighting_per_area_new
        end
      end
    end

    if lights_have_info
      # Remove all but the first instance
      instances = space_type.lights.sort
      if instances.empty?
        definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        definition.setName("#{space_type.name} Lights Definition")
        instance = OpenStudio::Model::Lights.new(definition)
        instance.setName("#{space_type.name} Lights")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no lights, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end
      # Modify the definition of the instance
      if multiple_lpd_value_check == false
        space_type.lights.sort.each do |inst|
          definition = inst.lightsDefinition
          unless lighting_per_area.zero?
            occ_sens_lpd_factor = 1.0
            definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area.to_f * occ_sens_lpd_factor, 'W/ft^2', 'W/m^2').get)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area} W/ft^2.")
          end
        end
      else
        space_type.spaces.each do |space_type_space|
          new_space_type = space_type.clone.to_SpaceType.get
          space_type_space.setSpaceType(new_space_type)
          lighting_per_area = lighting_per_area_hash[space_type_space.name.to_s]
          new_space_type.lights.sort.each do |inst|
            definition = inst.lightsDefinition
            unless lighting_per_area.zero?
              occ_sens_lpd_factor = 1.0
              definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area.to_f * occ_sens_lpd_factor, 'W/ft^2', 'W/m^2').get)
              OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area} W/ft^2.")
            end
          end
        end
        space_type.remove
      end
    end
    return true
  end

  # Modify the lighting schedules for Appendix G PRM for 2016 and later
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def space_type_light_sch_change(model)
    return true
  end

  # Sets the schedules for the selected internal loads to typical schedules.
  # Get the default schedule set for this space type if one exists or make
  # one if none exists. For each category that is selected, add the typical
  # schedule for this category to the default schedule set.
  # This method does not alter any schedules of any internal loads that
  # does not inherit from the default schedule set.
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @param set_people [Boolean] if true, set the occupancy and activity schedules
  # @param set_lights [Boolean] if true, set the lighting schedule
  # @param set_electric_equipment [Boolean] if true, set the electric schedule schedule
  # @param set_gas_equipment [Boolean] if true, set the gas equipment density
  # @param make_thermostat [Boolean] if true, makes a thermostat for this space type from the
  #   schedules listed for the space type.  This thermostat is not hooked to any zone by this method,
  #   but may be found and used later.
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_internal_load_schedules(space_type, set_people: true, set_lights: true, set_electric_equipment: true, set_gas_equipment: true, set_ventilation: true, make_thermostat: true)
    # Get the standards data
    space_type_properties = space_type_get_standards_data(space_type)

    # Get the default schedule set
    # or create a new one if none exists.
    default_sch_set = nil
    if space_type.defaultScheduleSet.is_initialized
      default_sch_set = space_type.defaultScheduleSet.get
    else
      default_sch_set = OpenStudio::Model::DefaultScheduleSet.new(space_type.model)
      default_sch_set.setName("#{space_type.name} Schedule Set")
      space_type.setDefaultScheduleSet(default_sch_set)
    end

    # People
    if set_people
      occupancy_sch = space_type_properties['occupancy_schedule']
      unless occupancy_sch.nil?
        default_sch_set.setNumberofPeopleSchedule(model_add_schedule(space_type.model, occupancy_sch))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set occupancy schedule to #{occupancy_sch}.")
      end

      occupancy_activity_sch = space_type_properties['occupancy_activity_schedule']
      unless occupancy_activity_sch.nil?
        default_sch_set.setPeopleActivityLevelSchedule(model_add_schedule(space_type.model, occupancy_activity_sch))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set occupant activity schedule to #{occupancy_activity_sch}.")
      end

    end

    # Lights
    if set_lights
      apply_lighting_schedule(space_type, space_type_properties, default_sch_set)
    end

    # Electric Equipment
    if set_electric_equipment
      elec_equip_sch = space_type_properties['electric_equipment_schedule']
      unless elec_equip_sch.nil?
        default_sch_set.setElectricEquipmentSchedule(model_add_schedule(space_type.model, elec_equip_sch))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set electric equipment schedule to #{elec_equip_sch}.")
      end
    end

    # Gas Equipment
    if set_gas_equipment
      gas_equip_sch = space_type_properties['gas_equipment_schedule']
      unless gas_equip_sch.nil?
        default_sch_set.setGasEquipmentSchedule(model_add_schedule(space_type.model, gas_equip_sch))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set gas equipment schedule to #{gas_equip_sch}.")
      end
    end

    # Thermostat
    if make_thermostat
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(space_type.model)
      thermostat.setName("#{space_type.name} Thermostat")

      heating_setpoint_sch = space_type_properties['heating_setpoint_schedule']
      unless heating_setpoint_sch.nil?
        thermostat.setHeatingSetpointTemperatureSchedule(model_add_schedule(space_type.model, heating_setpoint_sch))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set heating setpoint schedule to #{heating_setpoint_sch}.")
      end

      cooling_setpoint_sch = space_type_properties['cooling_setpoint_schedule']
      unless cooling_setpoint_sch.nil?
        thermostat.setCoolingSetpointTemperatureSchedule(model_add_schedule(space_type.model, cooling_setpoint_sch))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set cooling setpoint schedule to #{cooling_setpoint_sch}.")
      end
    end

    return true
  end

  # applies a lighting schedule to a space type
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @param space_type_properties [Hash] hash of space type properties
  # @param default_sch_set [OpenStudio::Model::DefaultScheduleSet] default schedule set
  # @return [Boolean] returns true if successful, false if not
  def apply_lighting_schedule(space_type, space_type_properties, default_sch_set)
    lighting_sch = space_type_properties['lighting_schedule']
    return false if lighting_sch.nil?

    default_sch_set.setLightingSchedule(model_add_schedule(space_type.model, lighting_sch))
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set lighting schedule to #{lighting_sch}.")
    return true
  end

  # Returns standards data for selected construction
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @param intended_surface_type [String] the type of surface
  # @param standards_construction_type [String] the type of construction
  # @return [Hash] hash of construction properties
  def space_type_get_construction_properties(space_type, intended_surface_type, standards_construction_type)
    # get building_category value
    building_category = if !space_type_get_standards_data(space_type).nil? && space_type_get_standards_data(space_type)['is_residential'] == 'Yes'
                          'Residential'
                        else
                          'Nonresidential'
                        end

    # get climate_zone_set
    climate_zone = model_get_building_properties(space_type.model)['climate_zone']
    climate_zone_set = model_find_climate_zone_set(space_type.model, climate_zone)

    # populate search hash
    search_criteria = {
      'template' => template,
      'climate_zone_set' => climate_zone_set,
      'intended_surface_type' => intended_surface_type,
      'standards_construction_type' => standards_construction_type,
      'building_category' => building_category
    }

    # switch to use this but update test in standards and measures to load this outside of the method
    construction_properties = model_find_object(standards_data['construction_properties'], search_criteria)

    if !construction_properties
      # Search again use climate zone (e.g. 3) instead of sub-climate zone (3A)
      search_criteria['climate_zone_set'] = climate_zone_set[0..-2]
      construction_properties = model_find_object(standards_data['construction_properties'], search_criteria)
    end

    return construction_properties
  end
end
