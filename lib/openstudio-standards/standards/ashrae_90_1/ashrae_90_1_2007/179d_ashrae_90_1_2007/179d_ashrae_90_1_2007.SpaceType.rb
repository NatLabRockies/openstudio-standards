class ACM179dASHRAE9012007
  # @!group SpaceType

  OFFICE_SPACE_TYPES_NAMES_MAP = {
    'SmallOffice' => 'WholeBuilding - Sm Office',
    'MediumOffice' => 'WholeBuilding - Md Office',
    'LargeOffice' => 'WholeBuilding - Lg Office'
  }

  def whole_building_space_type_name(model, primary_building_type)
    unless ['Office', 'SmallOffice', 'MediumOffice', 'LargeOffice'].include?(primary_building_type)
      return 'WholeBuilding'
    end

    floor_area_m2 = model.getBuilding.floorArea
    # This turns Office in SmallOffice, MediumOffice, LargeOffice
    granular_bt = model_remap_office(model, floor_area_m2)
    return OFFICE_SPACE_TYPES_NAMES_MAP[granular_bt]
  end

  # Returns standards data for selected space type and template
  # This will check the building primary type instead
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @param extend_with_2007 [default True] whether to add anything we do not
  #        define (ventilation, exhaust, lighting control) from ASHRAE9012007
  # @return [hash] hash of internal loads for different load types
  def space_type_get_standards_data(space_type, extend_with_2007: true, throw_if_not_found: false)
    space_type_properties = model_get_standards_data(space_type.model, throw_if_not_found: throw_if_not_found)

    if !extend_with_2007
      return space_type_properties
    end

    # This merges the ventilation, exhaust and lighting controls
    data2007 = @std_2007.space_type_get_standards_data(space_type)
    if data2007.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', 'Space type properties from ASHRAE 90.1-2007 lookup failed')
    else
      space_type_properties = data2007.merge(space_type_properties)
      space_type_properties['space_type_2007'] = data2007['space_type']
    end

    return space_type_properties
  end

  # NOTE: 179D overrides it to set the people fraction sensible per ACM rules instead of letting E+ AutoCalculate it
  def space_type_apply_internal_loads(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation)
    super(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation)

    if set_people
      data = space_type_get_standards_data(space_type, extend_with_2007: false, throw_if_not_found: true)
      people_frac_sensible = data['occupancy_fraction_sensible']
      space_type.people.sort.each do |inst|
        definition = inst.peopleDefinition
        definition.setSensibleHeatFraction(people_frac_sensible)
      end
    end
  end

  # NOTE: 179D overrides it for Warehouse - Office only, so that the Thermostat
  # Cooling schedule is not Warehouse_Cool_Sch (which is 110F), but the Nonres_Cool_Sch
  # Otherwise, these spaces get a UnitHeater because they are deemed 'heatedonly'
  def space_type_apply_internal_load_schedules(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, make_thermostat)
    primary_building_type = model_get_primary_building_type(space_type.model)
    standards_space_type = if space_type.standardsSpaceType.is_initialized
                             space_type.standardsSpaceType.get
                           end
    if !make_thermostat || primary_building_type != 'Warehouse' || standards_space_type != 'Office'
      return super(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, make_thermostat)
    end

    # Do the super one, Except the make_thermostat
    super(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, false)

    # Make thermostat
    space_type_properties = space_type_get_standards_data(space_type)

    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(space_type.model)
    thermostat.setName("#{space_type.name} Thermostat")

    heating_setpoint_sch = space_type_properties['heating_setpoint_schedule']
    unless heating_setpoint_sch.nil?
      thermostat.setHeatingSetpointTemperatureSchedule(model_add_schedule(space_type.model, heating_setpoint_sch))
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set heating setpoint schedule to #{heating_setpoint_sch}.")
    end

    cooling_setpoint_sch = 'Nonres_Cool_Sch'
    thermostat.setCoolingSetpointTemperatureSchedule(model_add_schedule(space_type.model, cooling_setpoint_sch))
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set cooling setpoint schedule to #{cooling_setpoint_sch}, which is 179D override.")

    return true
  end

  def space_type_apply_standard_infiltration(space_type)
    if space_type.name.get.to_s.downcase.include?('plenum')
      return false
    end

    if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')
      return false
    end

    # Get the standards data
    space_type_properties = space_type_get_standards_data(space_type)

    infiltration_have_info = false
    infiltration_per_area_ext = space_type_properties['infiltration_per_exterior_area'].to_f
    infiltration_per_area_ext_wall = space_type_properties['infiltration_per_exterior_wall_area'].to_f
    infiltration_ach = space_type_properties['infiltration_air_changes'].to_f
    if infiltration_per_area_ext.zero? && infiltration_per_area_ext_wall.zero? && infiltration_ach.zero?
      return
    end

    # Remove all but the first instance
    instances = space_type.spaceInfiltrationDesignFlowRates.sort
    if instances.size.zero?
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
        inst.setFlowperExteriorSurfaceArea(OpenStudio.convert(infiltration_per_area_ext.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get.round(13))
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

  def space_type_apply_standard_infiltration_schedule(space_type)
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
    infiltration_sch = space_type_properties['infiltration_schedule']
    unless infiltration_sch.nil?
      default_sch_set.setInfiltrationSchedule(model_add_schedule(space_type.model, infiltration_sch))
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration schedule to #{infiltration_sch}.")
    end
  end

end
