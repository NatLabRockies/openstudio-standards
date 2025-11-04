class NECB2011
  def add_all_spacetypes_to_model(model)
    # Get the space Type data from @standards data
    spacetype_data = nil
    if @standards_data['space_types'].is_a?(Hash) == true
      spacetype_data = @standards_data['space_types']['table']
    else
      spacetype_data = @standards_data['space_types']
    end
    spacetype_data.each do |spacedata|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsSpaceType(spacedata['space_type'])
      space_type.setStandardsBuildingType(spacedata['building_type'])
      space_type.setName("#{spacedata['building_type']} #{spacedata['space_type']}")
      # Loads
      space_type_apply_internal_loads(space_type: space_type)

      # Schedules
      space_type_apply_internal_load_schedules(space_type)
    end
  end

  # Sets the selected internal loads to standards-based or typical values.
  # For each category that is selected get all load instances. Remove all
  # but the first instance if multiple instances.  Add a new instance/definition
  # if no instance exists. Modify the definition for the remaining instance
  # to have the specified values. This method does not alter any
  # loads directly assigned to spaces.  This method skips plenums.
  #
  # @param set_people [Boolean] if true, set the people density.
  # Also, assign reasonable clothing, air velocity, and work efficiency inputs
  # to allow reasonable thermal comfort metrics to be calculated.
  # @param set_lights [Boolean] if true, set the lighting density, lighting fraction
  # to return air, fraction radiant, and fraction visible.
  # @param set_electric_equipment [Boolean] if true, set the electric equipment density
  # @param set_gas_equipment [Boolean] if true, set the gas equipment density
  # @param set_ventilation [Boolean] if true, set the ventilation rates (per-person and per-area)
  # @param set_infiltration [Boolean] if true, set the infiltration rates
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_internal_loads(space_type:,
                                      set_people: true,
                                      set_lights: true,
                                      set_electric_equipment: true,
                                      set_gas_equipment: true,
                                      set_ventilation: true,
                                      set_infiltration: true,
                                      lights_type: 'NECB_Default',
                                      lights_scale: 1.0)

    # Skip plenums
    # Check if the space type name
    # contains the word plenum.
    if space_type.name.get.to_s.downcase.include?('plenum')
      return false
    end

    if space_type.standardsSpaceType.is_initialized
      if space_type.standardsSpaceType.get.downcase.include?('plenum')
        return false
      end
    end

    # Get the space Type data from @standards data
    spacetype_data = @standards_data['tables']['space_types']['table']

    standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
    standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
    space_type_properties = spacetype_data.detect { |s| (s['building_type'] == standards_building_type) && (s['space_type'] == standards_space_type) }

    # Need to add a check, or it'll crash on space_type_properties['occupancy_per_area'].to_f below
    if space_type_properties.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} was not found in the standards data.")
      return false
    end

    # People
    people_have_info = false
    occupancy_per_area = space_type_properties['occupancy_per_area'].to_f
    people_have_info = true unless occupancy_per_area.zero?

    if set_people && people_have_info

      # Remove all but the first instance
      instances = space_type.people.sort
      if instances.empty?
        # Create a new definition and instance
        definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
        definition.setName("#{space_type.name} People Definition")
        instance = OpenStudio::Model::People.new(definition)
        instance.setName("#{space_type.name} People")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no people, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance
      space_type.people.sort.each do |inst|
        definition = inst.peopleDefinition
        unless occupancy_per_area.zero?
          definition.setPeopleperSpaceFloorArea(OpenStudio.convert(occupancy_per_area / 1000, 'people/ft^2', 'people/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set occupancy to #{occupancy_per_area} people/1000 ft^2.")
        end

        # set fraction radiant  ##
        definition.setFractionRadiant(0.3)

        # Clothing schedule for thermal comfort metrics
        clothing_sch = space_type.model.getScheduleRulesetByName('Clothing Schedule')
        if clothing_sch.is_initialized
          clothing_sch = clothing_sch.get
        else
          clothing_sch = OpenStudio::Model::ScheduleRuleset.new(space_type.model)
          clothing_sch.setName('Clothing Schedule')
          clothing_sch.defaultDaySchedule.setName('Clothing Schedule Default Winter Clothes')
          clothing_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
          sch_rule = OpenStudio::Model::ScheduleRule.new(clothing_sch)
          sch_rule.daySchedule.setName('Clothing Schedule Summer Clothes')
          sch_rule.daySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.5)
          sch_rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(5), 1))
          sch_rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(9), 30))
        end
        inst.setClothingInsulationSchedule(clothing_sch)

        # Air velocity schedule for thermal comfort metrics
        air_velo_sch = space_type.model.getScheduleRulesetByName('Air Velocity Schedule')
        if air_velo_sch.is_initialized
          air_velo_sch = air_velo_sch.get
        else
          air_velo_sch = OpenStudio::Model::ScheduleRuleset.new(space_type.model)
          air_velo_sch.setName('Air Velocity Schedule')
          air_velo_sch.defaultDaySchedule.setName('Air Velocity Schedule Default')
          air_velo_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.2)
        end
        inst.setAirVelocitySchedule(air_velo_sch)

        # Work efficiency schedule for thermal comfort metrics
        work_efficiency_sch = space_type.model.getScheduleRulesetByName('Work Efficiency Schedule')
        if work_efficiency_sch.is_initialized
          work_efficiency_sch = work_efficiency_sch.get
        else
          work_efficiency_sch = OpenStudio::Model::ScheduleRuleset.new(space_type.model)
          work_efficiency_sch.setName('Work Efficiency Schedule')
          work_efficiency_sch.defaultDaySchedule.setName('Work Efficiency Schedule Default')
          work_efficiency_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        end
        inst.setWorkEfficiencySchedule(work_efficiency_sch)
      end

    end

    # Lights
    apply_standard_lights(set_lights: set_lights,
                          space_type: space_type,
                          space_type_properties: space_type_properties,
                          lights_type: lights_type,
                          lights_scale: lights_scale)

    # Electric Equipment
    elec_equip_have_info = false
    elec_equip_per_area = space_type_properties['electric_equipment_per_area'].to_f
    elec_equip_frac_latent = space_type_properties['electric_equipment_fraction_latent'].to_f
    elec_equip_frac_radiant = space_type_properties['electric_equipment_fraction_radiant'].to_f
    elec_equip_frac_lost = space_type_properties['electric_equipment_fraction_lost'].to_f
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
        unless elec_equip_frac_latent.zero?
          definition.setFractionLatent(elec_equip_frac_latent)
        end
        unless elec_equip_frac_radiant.zero?
          definition.setFractionRadiant(elec_equip_frac_radiant)
        end
        unless elec_equip_frac_lost.zero?
          definition.setFractionLost(elec_equip_frac_lost)
        end
      end

    end

    # Gas Equipment
    gas_equip_have_info = false
    gas_equip_per_area = space_type_properties['gas_equipment_per_area'].to_f
    gas_equip_frac_latent = space_type_properties['gas_equipment_fraction_latent'].to_f
    gas_equip_frac_radiant = space_type_properties['gas_equipment_fraction_radiant'].to_f
    gas_equip_frac_lost = space_type_properties['gas_equipment_fraction_lost'].to_f
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
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set gas EPD to #{elec_equip_per_area} Btu/hr*ft^2.")
        end
        unless gas_equip_frac_latent.zero?
          definition.setFractionLatent(gas_equip_frac_latent)
        end
        unless gas_equip_frac_radiant.zero?
          definition.setFractionRadiant(gas_equip_frac_radiant)
        end
        unless gas_equip_frac_lost.zero?
          definition.setFractionLost(gas_equip_frac_lost)
        end
      end

    end

    # Ventilation
    ventilation_have_info = false
    ventilation_per_area = space_type_properties['ventilation_per_area'].to_f
    ventilation_per_person = space_type_properties['ventilation_per_person'].to_f
    ventilation_ach = space_type_properties['ventilation_air_changes'].to_f
    ventilation_occupancy_per_area = space_type_properties['ventilation_occupancy_rate_people_per_1000ft2'].to_f
    ventilation_have_info = true unless ventilation_per_area.zero?
    ventilation_have_info = true unless ventilation_per_person.zero?
    ventilation_have_info = true unless ventilation_ach.zero?

    # Get the design OA or create a new one if none exists
    ventilation = space_type.designSpecificationOutdoorAir
    if ventilation.is_initialized
      ventilation = ventilation.get
    else
      ventilation = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
      ventilation.setName("#{space_type.name} Ventilation")
      space_type.setDesignSpecificationOutdoorAir(ventilation)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no ventilation specification, one has been created.")
    end

    if set_ventilation && ventilation_have_info

      # Modify the ventilation properties
      ventilation.setOutdoorAirMethod('Sum')
      unless ventilation_per_area.zero?
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(ventilation_per_area.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation per area to #{ventilation_per_area} cfm/ft^2.")
      end
      unless ventilation_per_person.zero?
        # The occupancy per area rate for ventilation is different from the occupancy used for other loads as the occupancy assumption in the applicable  
        # ventilation standard is followed.  The mod_ventilation_per_person rate adjusts the per person ventilation rate (from the standard) so that the
        # correct ventilation rate (per the standard) is calculated when using the NECB occupant density (defined as occupancy_per_area in the space_types.json file)
        # Later the method thermal_zone_convert_outdoor_air_to_per_area (in standards) uses the space occupancy which is the NECB figure to get the total vent rate.
        mod_ventilation_per_person = ventilation_per_person * ventilation_occupancy_per_area / occupancy_per_area
        ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(mod_ventilation_per_person.to_f, 'ft^3/min*person', 'm^3/s*person').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation per person to #{mod_ventilation_per_person} cfm/person.")
      end
      unless ventilation_ach.zero?
        ventilation.setOutdoorAirFlowAirChangesperHour(ventilation_ach)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation to #{ventilation_ach} ACH.")
      end
      
      # Add information about the source to an additional properties object. Used in unit testing but could be useful elsewhere.
      notes = ventilation.additionalProperties
      notes.setFeature("Ref OA per area", space_type_properties['ventilation_per_area'].to_f)
      notes.setFeature("Ref OA per person", space_type_properties['ventilation_per_person'].to_f)
      notes.setFeature("Ref OA ach", space_type_properties['ventilation_air_changes'].to_f)
      notes.setFeature("Ref occupancy per 1000ft2", space_type_properties['ventilation_occupancy_rate_people_per_1000ft2'].to_f)
      notes.setFeature("Ref standard", space_type_properties['ventilation_occupancy_standard'].to_s)
      notes.setFeature("Ref space type", space_type_properties['ventilation_standard_space_type'].to_s)
    elsif set_ventilation && !ventilation_have_info

      # All space types must have a design spec OA
      # object for ventilation controls to work correctly,
      # even if the values are all zero.
      ventilation.setOutdoorAirFlowperFloorArea(0)
      ventilation.setOutdoorAirFlowperPerson(0)
      ventilation.setOutdoorAirFlowAirChangesperHour(0)

    end

    # Infiltration
    infiltration_have_info = false
    infiltration_per_area_ext = space_type_properties['infiltration_per_exterior_area'].to_f
    infiltration_per_area_ext_wall = space_type_properties['infiltration_per_exterior_wall_area'].to_f
    infiltration_ach = space_type_properties['infiltration_air_changes'].to_f
    unless infiltration_per_area_ext.zero? && infiltration_per_area_ext_wall.zero? && infiltration_ach.zero?
      infiltration_have_info = true
    end

    return unless set_infiltration && infiltration_have_info

    # Remove all but the first instance
    instances = space_type.spaceInfiltrationDesignFlowRates.sort
    if instances.empty?
      instance = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space_type.model)
      instance.setName("#{space_type.name} Infiltration")
      instance.setSpaceType(space_type)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no infiltration objects, one has been created.")
      instances << instance
    elsif instances.size > 1
      instances.each_with_index do |inst, i|
        next if i.zero?

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
        inst.remove
      end
    end

    # Modify each instance
    space_type.spaceInfiltrationDesignFlowRates.sort.each do |inst|
      unless infiltration_per_area_ext.zero?
        inst.setFlowperExteriorSurfaceArea(OpenStudio.convert(infiltration_per_area_ext.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration to #{ventilation_ach} per ft^2 exterior surface area.")
      end
      unless infiltration_per_area_ext_wall.zero?
        inst.setFlowperExteriorWallArea(OpenStudio.convert(infiltration_per_area_ext_wall.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration to #{infiltration_per_area_ext_wall} per ft^2 exterior wall area.")
      end
      unless infiltration_ach.zero?
        inst.setAirChangesperHour(infiltration_ach)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration to #{ventilation_ach} ACH.")
      end
    end
  end
end
