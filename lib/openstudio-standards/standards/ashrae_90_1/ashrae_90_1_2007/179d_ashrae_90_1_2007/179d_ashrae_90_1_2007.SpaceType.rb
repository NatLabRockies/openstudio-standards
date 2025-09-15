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
  def space_type_apply_internal_loads(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration)
    super(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration)

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
  def space_type_apply_internal_load_schedules(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration, make_thermostat)
    primary_building_type = model_get_primary_building_type(space_type.model)
    standards_space_type = if space_type.standardsSpaceType.is_initialized
                             space_type.standardsSpaceType.get
                           end
    if !make_thermostat || primary_building_type != 'Warehouse' || standards_space_type != 'Office'
      return super(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration, make_thermostat)
    end

    # Do the super one, Except the make_thermostat
    super(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration, false)

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
end
