class ACM179dASHRAE901PRM2019
  HVAC_AVAILABILITY_SCHEDULE_MAP = {
    'AirLoopHVAC' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardConvectiveElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardRadiantConvectiveElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardRadiantConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACCoolingPanelRadiantConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACDehumidifierDX' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACEnergyRecoveryVentilator' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACFourPipeFanCoil' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACHighTemperatureRadiant' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACIdealLoadsAirSystem' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTemperatureRadiantElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTempRadiantConstFlow' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTempRadiantVarFlow' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACPackagedTerminalAirConditioner' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACPackagedTerminalHeatPump' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACUnitHeater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACUnitVentilator' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACWaterToAirHeatPump' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'AirLoopHVACUnitarySystem' => [[:supplyAirFanOperatingModeSchedule, :setSupplyAirFanOperatingModeSchedule]]
  }.freeze

  def __model_get_primary_building_type(model)
    building_types = {}

    building = model.getBuilding
    building_level_type = nil
    if building.standardsBuildingType.is_initialized
      building_level_type = model_get_lookup_name(building.standardsBuildingType.get)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "found Building level standardsBuildingType = '#{building_level_type}'")
    end

    model.getSpaceTypes.sort.each do |space_type|
      next unless space_type.standardsBuildingType.is_initialized

      original_building_type = space_type.standardsBuildingType.get
      building_type = model_get_lookup_name(original_building_type)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "found building type for Space Type '#{space_type.name}' = '#{building_type}'")
      if original_building_type != building_type
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Space Type '#{space_type.name}' has actual Building Type '#{original_building_type}' but sanitizing as '#{building_type}' for aggregation")
      end
      building_types[building_type] ||= 0.0
      building_types[building_type] += space_type.floorArea
    end

    if building_types.empty?
      if building_level_type.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot identify a single building type in model, none of your #{model.getSpaceTypes.size} SpaceTypes have a standardsBuildingType assigned and neither does the Building")
        raise 'No Primary Building Type found'
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "No area determination based on space types found, using Building level standardsBuildingType = '#{building_level_type}'")
      return building_level_type
    end

    space_type_level_type = building_types.max_by { |_building_type, floor_area| floor_area }.first
    if !building_level_type.nil?
      if building_level_type != space_type_level_type
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "The Building has standardsBuildingType '#{building_level_type}' while the area determination based on space types has '#{space_type_level_type}'. Preferring the Space Type one")
      end
      return space_type_level_type
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Building doesn't have a standardsBuildingType, using the area determination based on space types = '#{space_type_level_type}'")
    return space_type_level_type
  end

  def model_get_primary_building_type(model, remap_office: false, remap_retail: false)
    @primary_building_types_memoized ||= {}
    @primary_building_types_memoized[model] ||= __model_get_primary_building_type(model)

    building_type = @primary_building_types_memoized[model]
    if remap_office && building_type == 'Office'
      building_type = model_remap_office(model, model.getBuilding.floorArea)
    end
    if remap_retail
      return 'RetailStripmall' if building_type == 'StripMall'
      return 'RetailStandalone' if building_type == 'Retail'
    end
    return building_type
  end

  def model_remap_office(model, floor_area)
    floor_area_sqft = OpenStudio.convert(floor_area, 'm^2', 'ft^2').get
    num_floors = model.getBuilding.buildingStories.size
    if floor_area_sqft < 25_000
      return 'SmallOffice' if num_floors <= 3

      return 'MediumOffice'
    elsif floor_area_sqft < 150_000
      return 'MediumOffice' if num_floors <= 5

      return 'LargeOffice'
    else
      return 'LargeOffice'
    end
  end

  def model_get_building_properties(model, remap_office: true)
    climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)
    building_type = model_get_primary_building_type(model, remap_office: remap_office)
    standards_template = model.getBuilding.standardsTemplate.get if model.getBuilding.standardsTemplate.is_initialized

    results = {}
    results['climate_zone'] = climate_zone
    results['building_type'] = building_type
    results['standards_template'] = standards_template

    return results
  end

  def model_get_standards_data(model, throw_if_not_found: false)
    standards_building_type = model_get_primary_building_type(model, remap_office: false)
    search_criteria_list = [
      {
        'template' => template,
        'building_type' => standards_building_type,
        'space_type' => whole_building_space_type_name(model, standards_building_type)
      },
      {
        'template' => template,
        'building_type' => standards_building_type,
        'space_type' => '- undefined -'
      }
    ]

    found_search_criteria = nil
    space_type_properties = nil
    search_criteria_list.each do |search_criteria|
      space_type_properties = model_find_object(standards_data['space_types'], search_criteria)
      unless space_type_properties.nil?
        found_search_criteria = search_criteria
        break
      end
    end

    if space_type_properties.nil?
      candidate_space_type = model.getSpaceTypes.select do |space_type|
        next false unless space_type.standardsBuildingType.is_initialized

        model_get_lookup_name(space_type.standardsBuildingType.get) == standards_building_type
      end.max_by(&:floorArea)
      unless candidate_space_type.nil?
        space_type_properties = space_type_get_standards_data(candidate_space_type)
      end
    end

    if space_type_properties.nil? || space_type_properties.empty?
      msg = "Space type properties lookup failed: #{search_criteria_list}."
      if throw_if_not_found
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SpaceType', msg)
        raise msg
      end
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', msg)
      space_type_properties = {}
    else
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.SpaceType', "Model space type properties lookup succeeded: #{found_search_criteria || space_type_properties['space_type']}.")
    end

    return space_type_properties
  end

  def model_apply_acm_hvac_availability_schedule(model)
    begin
      data = model_get_standards_data(model, throw_if_not_found: false)
    rescue StandardError => e
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model_apply_acm_hvac_availability_schedule', "Skipping ACM HVAC availability schedule: #{e.message}")
      return false
    end
    acm_fan_schedule_name = data['hvac_operation_schedule']
    return false if acm_fan_schedule_name.nil?

    acm_fan_schedule = nil
    count_availability = 0
    HVAC_AVAILABILITY_SCHEDULE_MAP.each do |hvac_type, methods|
      getter = "get#{hvac_type}s"
      next unless model.respond_to?(getter)

      objects = model.send(getter)
      next if objects.empty?

      if acm_fan_schedule.nil?
        acm_fan_schedule = model_add_schedule(model, acm_fan_schedule_name)
        model.getBuilding.additionalProperties.setFeature('acm_fan_sch', acm_fan_schedule_name)
      end

      objects.each do |object|
        methods.each do |_getter_method, setter_method|
          raise "HVAC_AVAILABILITY_SCHEDULE_MAP is out of date, #{object.briefDescription} does not respond to #{setter_method}" unless object.respond_to?(setter_method)

          if object.send(setter_method, acm_fan_schedule)
            count_availability += 1
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model_apply_acm_hvac_availability_schedule', "Failed to apply availability schedule via #{setter_method} for #{object.briefDescription}")
          end
        end
      end
    end

    ventilation_objects = model.getZoneVentilationDesignFlowRates.select do |zone_ventilation|
      next false unless zone_ventilation.nameString.end_with?(' Ventilation')
      next false unless zone_ventilation.thermalZone.is_initialized

      zone_ventilation.thermalZone.get.airLoopHVAC.empty?
    end
    unless ventilation_objects.empty?
      if acm_fan_schedule.nil?
        acm_fan_schedule = model_add_schedule(model, acm_fan_schedule_name)
        model.getBuilding.additionalProperties.setFeature('acm_fan_sch', acm_fan_schedule_name)
      end
      ventilation_objects.each do |zone_ventilation|
        zone_ventilation.setSchedule(acm_fan_schedule)
        count_availability += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model_apply_acm_hvac_availability_schedule', "Applied availability schedule '#{acm_fan_schedule_name}' to #{count_availability} objects.")
    return count_availability > 0
  end

  def model_apply_hvac_efficiency_standard(model, climate_zone, apply_controls: true, sql_db_vars_map: nil)
    result = super(model, climate_zone, apply_controls: apply_controls, sql_db_vars_map: sql_db_vars_map)
    model_apply_acm_hvac_availability_schedule(model)
    return result
  end
end
