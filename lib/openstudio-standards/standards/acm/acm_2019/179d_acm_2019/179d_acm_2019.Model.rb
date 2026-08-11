require 'date'

module ACM179dPRMFanPowerMetadata
  PRM_FAN_POWER_FEATURE_METHODS = {
    'supply_fan_w' => :air_loop_hvac_get_supply_fan_power,
    'return_fan_w' => :air_loop_hvac_get_return_fan_power,
    'relief_fan_w' => :air_loop_hvac_get_relief_fan_power,
  }.freeze

  def ensure_prm_fan_power_features(air_loop_hvac, prm_standard)
    fan_power_by_feature = PRM_FAN_POWER_FEATURE_METHODS.transform_values do |method_name|
      prm_standard.send(method_name, air_loop_hvac).to_f
    end
    ensure_prm_fan_power_features_for_zones(air_loop_hvac.thermalZones.sort, air_loop_hvac.name, fan_power_by_feature)
  end

  def ensure_prm_fan_power_features_for_zones(thermal_zones, object_name, fan_power_by_feature)
    repaired_zones = []
    thermal_zones.each do |zone|
      additional = zone.additionalProperties
      missing_features = fan_power_by_feature.keys.reject do |feature|
        additional.hasFeature(feature) && additional.getFeatureAsDouble(feature).is_initialized
      end
      next if missing_features.empty?

      missing_features.each do |feature|
        additional.setFeature(feature, fan_power_by_feature[feature])
      end
      repaired_zones << zone.nameString
    end

    unless repaired_zones.empty?
      OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model',
                         "Added missing PRM fan-power metadata for #{repaired_zones.size} zone(s) on #{object_name}.")
    end

    repaired_zones
  end
end

module ACM179dWinterSolarDesignDay
  WINTER_SOLAR_DESIGN_DAY_CLIMATE_ZONES = ['0A', '0B', '1A', '1B', '2A', '2B'].freeze
  WINTER_SOLAR_DESIGN_DAY_NAME = '179D hot-climate winter solar cooling design day'.freeze

  # Adds the winter EPW day with the highest exterior-window solar exposure.
  def model_add_hot_climate_winter_solar_design_day(model, climate_zone)
    return unless WINTER_SOLAR_DESIGN_DAY_CLIMATE_ZONES.include?(climate_zone.to_s.split('-')[-1].to_s.upcase)
    return if model.getDesignDays.any? { |design_day| design_day.nameString == WINTER_SOLAR_DESIGN_DAY_NAME }
    return unless model.getWeatherFile.path.is_initialized

    epw_path = model.getWeatherFile.path.get.to_s
    return unless File.file?(epw_path)

    window_planes = exterior_window_planes(model)
    return if window_planes.empty?

    location, records = read_epw_records(epw_path)
    selected_day = winter_window_solar_day(location, records, window_planes)
    return if selected_day.nil?

    add_winter_solar_design_day(model, location, selected_day)
  rescue StandardError => e
    OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model',
                       "Could not add winter solar cooling design day: #{e.message}")
  end

  def exterior_window_planes(model)
    model.getSubSurfaces.filter_map do |sub_surface|
      parent_surface = sub_surface.surface
      next unless parent_surface.is_initialized

      surface = parent_surface.get
      next unless sub_surface.subSurfaceType.downcase.include?('window')
      next unless surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'

      [sub_surface.netArea, surface.azimuth, surface.tilt]
    end
  end

  def read_epw_records(epw_path)
    lines = File.foreach(epw_path)
    location = parse_epw_location(lines.next)
    7.times { lines.next }
    records = lines.filter_map { |line| parse_epw_record(line) }
    [location, records]
  end

  def parse_epw_location(line)
    fields = line.split(',')
    {
      latitude_rad: fields[6].to_f * Math::PI / 180.0,
      latitude_deg: fields[6].to_f,
      longitude_deg: fields[7].to_f,
      time_zone: fields[8].to_f,
    }
  end

  def parse_epw_record(line)
    fields = line.split(',')
    return nil if fields.size < 22

    month = fields[1].to_i
    day = fields[2].to_i
    hour = fields[3].to_i
    return nil unless month.between?(1, 12) && day.between?(1, 31) && hour.between?(1, 24)

    {
      month:,
      day:,
      hour:,
      dry_bulb_c: fields[6].to_f,
      dew_point_c: fields[7].to_f,
      pressure_pa: fields[9].to_f,
      direct_normal_w_per_m2: fields[14].to_f,
      diffuse_horizontal_w_per_m2: fields[15].to_f,
      wind_direction_deg: fields[20].to_f,
      wind_speed_m_per_s: fields[21].to_f,
    }
  end

  def winter_window_solar_day(location, records, window_planes)
    winter_months = location[:latitude_deg].negative? ? [4, 5, 6, 7, 8, 9] : [10, 11, 12, 1, 2, 3]
    day_scores = Hash.new(0.0)

    records.each do |record|
      next unless winter_months.include?(record[:month])

      day_scores[[record[:month], record[:day]]] += window_solar_score(location, record, window_planes)
    end

    date = day_scores.max_by { |_day, score| score }&.first
    return nil if date.nil?

    selected_records = records.select { |record| record[:month] == date[0] && record[:day] == date[1] }
    selected_records.size == 24 ? selected_records : nil
  end

  def window_solar_score(location, record, window_planes)
    direct_normal = record[:direct_normal_w_per_m2]
    diffuse_horizontal = record[:diffuse_horizontal_w_per_m2]
    return 0.0 if direct_normal <= 0.0 && diffuse_horizontal <= 0.0

    hour_angle, declination = epw_solar_angles(record[:month], record[:day], record[:hour] - 0.5,
                                               location[:longitude_deg], location[:time_zone])
    sin_altitude = (Math.sin(location[:latitude_rad]) * Math.sin(declination)) +
                   (Math.cos(location[:latitude_rad]) * Math.cos(declination) * Math.cos(hour_angle))
    return 0.0 if sin_altitude <= 0.0

    altitude = Math.asin(sin_altitude)
    solar_azimuth = Math.atan2(Math.sin(hour_angle),
                               (Math.cos(hour_angle) * Math.sin(location[:latitude_rad])) -
                               (Math.tan(declination) * Math.cos(location[:latitude_rad]))) + Math::PI

    window_planes.sum do |area, azimuth, tilt|
      cosine_incidence = (Math.sin(altitude) * Math.cos(tilt)) +
                         (Math.cos(altitude) * Math.sin(tilt) * Math.cos(solar_azimuth - azimuth))
      (direct_normal * [cosine_incidence, 0.0].max * area) +
        (diffuse_horizontal * (1.0 + Math.cos(tilt)) * 0.5 * area)
    end
  end

  def epw_solar_angles(month, day, local_hour, longitude_deg, time_zone)
    day_of_year = Date.new(2000, month, day).yday
    gamma = 2.0 * Math::PI * (day_of_year - 1) / 365.0
    declination = [0.006918, -(0.399912 * Math.cos(gamma)), 0.070257 * Math.sin(gamma),
                   -(0.006758 * Math.cos(2.0 * gamma)), 0.000907 * Math.sin(2.0 * gamma),
                   -(0.002697 * Math.cos(3.0 * gamma)), 0.00148 * Math.sin(3.0 * gamma)].sum
    equation_of_time = 229.18 * (0.000075 + (0.001868 * Math.cos(gamma)) - (0.032077 * Math.sin(gamma)) -
                                 (0.014615 * Math.cos(2.0 * gamma)) - (0.040849 * Math.sin(2.0 * gamma)))
    minutes = (local_hour * 60.0) + equation_of_time + (4.0 * (longitude_deg - (15.0 * time_zone))) - 720.0
    [minutes * Math::PI / 180.0, declination]
  end

  def add_winter_solar_design_day(model, _location, records)
    max_dry_bulb = records.map { |record| record[:dry_bulb_c] }.max
    min_dry_bulb = records.map { |record| record[:dry_bulb_c] }.min
    dry_bulb_range = max_dry_bulb - min_dry_bulb
    max_record = records.max_by { |record| record[:dry_bulb_c] }

    design_day = OpenStudio::Model::DesignDay.new(model)
    design_day.setName(WINTER_SOLAR_DESIGN_DAY_NAME)
    design_day.setMonth(records.first[:month])
    design_day.setDayOfMonth(records.first[:day])
    design_day.setDayType('SummerDesignDay')
    design_day.setMaximumDryBulbTemperature(max_dry_bulb)
    design_day.setDailyDryBulbTemperatureRange(dry_bulb_range)
    design_day.setDryBulbTemperatureRangeModifierType('MultiplierSchedule')
    design_day.setDryBulbTemperatureRangeModifierDaySchedule(epw_day_schedule(model, 'Drybulb Range Modifier', records) do |record|
      dry_bulb_range.positive? ? (max_dry_bulb - record[:dry_bulb_c]) / dry_bulb_range : 0.0
    end)
    design_day.setHumidityConditionType('DewPoint')
    design_day.setWetBulbOrDewPointAtMaximumDryBulb(max_record[:dew_point_c])
    design_day.setBarometricPressure(max_record[:pressure_pa])
    design_day.setWindSpeed(max_record[:wind_speed_m_per_s])
    design_day.setWindDirection(max_record[:wind_direction_deg])
    design_day.setRainIndicator(false)
    design_day.setSnowIndicator(false)
    design_day.setDaylightSavingTimeIndicator(false)
    design_day.setSolarModelIndicator('Schedule')
    design_day.setBeamSolarDaySchedule(epw_day_schedule(model, 'Beam Solar', records) { |record| record[:direct_normal_w_per_m2] })
    design_day.setDiffuseSolarDaySchedule(epw_day_schedule(model, 'Diffuse Solar', records) { |record| record[:diffuse_horizontal_w_per_m2] })

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model',
                       "Added #{WINTER_SOLAR_DESIGN_DAY_NAME} for #{records.first[:month]}/#{records.first[:day]}.")
  end

  def epw_day_schedule(model, label, records)
    schedule = OpenStudio::Model::ScheduleDay.new(model)
    schedule.setName("#{WINTER_SOLAR_DESIGN_DAY_NAME} #{label}")
    records.sort_by { |record| record[:hour] }.each do |record|
      schedule.addValue(OpenStudio::Time.new(0, record[:hour], 0, 0), yield(record))
    end
    schedule
  end

  module_function :model_add_hot_climate_winter_solar_design_day,
                  :exterior_window_planes,
                  :read_epw_records,
                  :parse_epw_location,
                  :parse_epw_record,
                  :winter_window_solar_day,
                  :window_solar_score,
                  :epw_solar_angles,
                  :add_winter_solar_design_day,
                  :epw_day_schedule
end

class ACM179dACM2019
  include ACM179dPRMFanPowerMetadata

  HOT_CLIMATE_ZONES = ['0A', '0B', '1A', '1B', '2A', '2B', '3A'].freeze

  ACM_BUILDING_TYPE_BY_PROTOTYPE = {
    'SmallOffice' => 'Office',
    'MediumOffice' => 'Office',
    'LargeOffice' => 'Office',
    'RetailStandalone' => 'Retail',
    'RetailStripmall' => 'StripMall',
  }.freeze

  ACM_HVAC_OPERATION_SCHEDULE_FEATURE = 'acm_hvac_operation_schedule'.freeze
  PRM_2019_TEMPLATE = '90.1-PRM-2019'.freeze

  ACM_EXHAUST_HIGH_REHEAT_DESIGN_SAT_C = 50.0
  ACM_EXHAUST_SPACE_TYPES_PRM_2019 = ['Kitchen', 'Restroom', 'Cafeteria'].freeze
  ACM_INFILTRATION_RATE_CFM_PER_FT2 = 0.0448
  NON_ACM_REHEAT_MAX_AIR_TEMPERATURE_C = 43.3
  REHEAT_HIGH_OCC_MIN_DENSITY_PPL_PER_M2 = 0.269
  REHEAT_HIGH_OCC_MIN_PEOPLE = 50.0

  PROTOTYPE_TO_PRM_LPD_SPACE_TYPE = {
    'WholeBuilding - Sm Office' => 'office - whole building',
    'WholeBuilding - Md Office' => 'office - whole building',
    'WholeBuilding - Lg Office' => 'office - whole building',
    'Classroom' => 'classroom/lecture/training - preschool to 12th',
    'Corridor' => 'corridor - all other',
    'Cafeteria' => 'dining - cafeteria/fast food',
    'ComputerRoom' => 'computer room',
    'Gym' => 'gymnasium playing area',
    'Kitchen' => 'kitchen',
    'Library' => 'library - whole building',
    'Lobby' => 'lobby - all other',
    'Auditorium' => 'audience seating - auditorium',
    'Mechanical' => 'electrical/mechanical',
    'Office' => 'office - whole building',
    'Restroom' => 'restroom - all other',
    'Stair' => 'stairwell',
    'PublicRestroom' => 'restroom - all other',
    'Storage' => 'storage 50 to 1000 sf - all other',
    'Bulk' => 'warehouse - bulk storage',
    'Fine' => 'warehouse - fine storage',
    'Strip mall - type 1' => 'retail - whole building',
    'Strip mall - type 2' => 'retail - whole building',
    'Strip mall - type 3' => 'retail - whole building',
    'Retail' => 'retail - whole building',
    'Point_of_Sale' => 'sales',
    'Back_Space' => 'storage 50 to 1000 sf - all other',
    'Entry' => 'lobby - all other',
    'GuestRoom123Occ' => 'guest room',
    'GuestRoom123Vac' => 'guest room',
    'GuestLounge' => 'lobby - hotel',
    'StaffLounge' => 'lounge/breakroom - all other',
    'Exercise' => 'exercise center - whole building',
    'Meeting' => 'conference/meeting/multipurpose',
    'Laundry' => 'laundry/washing',
    'ElevatorCore' => 'elevator core',
    'Elec/MechRoom' => 'electrical/mechanical',
  }.freeze

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
    'FanZoneExhaust' => [
      [:availabilitySchedule, :setAvailabilitySchedule],
      [:flowFractionSchedule, :setFlowFractionSchedule]
    ],
    'AirLoopHVACUnitarySystem' => [[:supplyAirFanOperatingModeSchedule, :setSupplyAirFanOperatingModeSchedule]],
  }.freeze

  ACM_PEOPLE_FIELDS = [
    'occupancy_per_area',
    'occupancy_schedule',
    'occupancy_activity_schedule',
    'occupancy_fraction_sensible'
  ].freeze

  ACM_SWH_FIELDS = [
    'service_water_heating_peak_flow_per_area',
    'service_water_heating_schedule'
  ].freeze

  ACM_EQUIPMENT_FIELDS = [
    'electric_equipment_per_area',
    'electric_equipment_schedule',
    'gas_equipment_schedule'
  ].freeze

  ACM_ELECTRIC_EQUIPMENT_EXCLUDED_NAME_FRAGMENTS = [
    'elevator',
    'fuel equipment'
  ].freeze

  PRM_WHOLE_BUILDING_ACM_SPACE_TYPE = {
    'school/university - whole building' => 'Classroom',
    'warehouse - whole building' => 'Bulk',
  }.freeze

  ACM_WHOLE_BUILDING_SPACE_TYPE_FALLBACK = {
    'Retail' => 'Retail',
    'StripMall' => 'Strip mall - type 1',
    'Warehouse' => 'Bulk',
  }.freeze

  def model_get_acm_standards_data(model, throw_if_not_found: false, building_type: nil)
    lookup_building_type = building_type || model_get_primary_building_type(model, remap_office: false)
    standards_building_type = acm_building_type_for_lookup(lookup_building_type, throw_if_not_found: false)
    return acm_lookup_failure([], throw_if_not_found) if standards_building_type.nil?

    criteria = acm_space_type_candidates(standards_building_type, whole_building_space_type_name(model, standards_building_type)).map do |space_type_name|
      acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    space_type_properties = acm_find_space_type_properties(criteria, throw_if_not_found: false, log_failure: false)
    if space_type_properties.empty?
      candidate_space_type = model.getSpaceTypes.select do |space_type|
        next false unless space_type.standardsBuildingType.is_initialized

        acm_building_type_for_lookup(space_type.standardsBuildingType.get, throw_if_not_found: false) == standards_building_type
      end.max_by(&:floorArea)
      space_type_properties = space_type_get_acm_standards_data(candidate_space_type) unless candidate_space_type.nil?
    end

    return space_type_properties unless space_type_properties.empty?

    schedule_properties = acm_hvac_operation_schedule_properties(standards_building_type)
    return schedule_properties unless schedule_properties.empty?

    acm_lookup_failure(criteria, throw_if_not_found)
  end

  def model_get_standards_data(model, throw_if_not_found: false, building_type: nil)
    model_get_acm_standards_data(model, throw_if_not_found:, building_type:)
  end

  def model_apply_common_acm_assumptions(model, apply_hvac_operation_schedule: true, building_type: nil)
    model_apply_acm_hvac_availability_schedule(model, building_type:) if apply_hvac_operation_schedule
    true
  end

  def model_apply_acm_people(model, building_type: nil)
    count_people = 0

    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      people_objects = space_type.people.sort_by(&:nameString)
      next if people_objects.empty? && space_type.floorArea.zero?

      acm_data = acm_people_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_PEOPLE_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM people data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      if people_objects.empty?
        next unless acm_data['occupancy_per_area'].to_f.positive?

        people_definition = OpenStudio::Model::PeopleDefinition.new(model)
        people_definition.setName("#{space_type.nameString} ACM People Definition")
        new_people = OpenStudio::Model::People.new(people_definition)
        new_people.setName("#{space_type.nameString} ACM People")
        new_people.setSpaceType(space_type)
        people_objects = [new_people]
      end

      occupancy_schedule = model_add_schedule(model, acm_data['occupancy_schedule'])
      activity_schedule = model_add_schedule(model, acm_data['occupancy_activity_schedule'])

      people_objects.each do |people_object|
        people_definition = people_object.peopleDefinition
        people_definition.setPeopleperSpaceFloorArea(acm_occupancy_per_area_si(acm_data['occupancy_per_area']))
        people_definition.setSensibleHeatFraction(acm_data['occupancy_fraction_sensible'].to_f)
        people_object.setNumberofPeopleSchedule(occupancy_schedule)
        people_object.setActivityLevelSchedule(activity_schedule)
        count_people += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM people fields to #{count_people} People object(s).")
    count_people.positive?
  end

  def acm_people_data_for_space_type(space_type, building_type: nil)
    return space_type_get_acm_standards_data(space_type, throw_if_not_found: true) if building_type.nil?

    standards_building_type = acm_building_type_for_lookup(building_type, throw_if_not_found: true)
    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found: true)
  end

  def acm_occupancy_per_area_si(occupancy_per_1000_ft2)
    OpenStudio.convert(occupancy_per_1000_ft2.to_f / 1000.0, '1/ft^2', '1/m^2').get
  end

  def model_apply_acm_equipment_loads(model, building_type: nil)
    count_electric = 0
    count_gas = 0

    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      electric_objects = space_type.electricEquipment.sort_by(&:nameString)
      gas_objects = space_type.gasEquipment.sort_by(&:nameString)
      space_type.spaces.sort_by(&:nameString).each do |space|
        electric_objects.concat(space.electricEquipment.sort_by(&:nameString))
        gas_objects.concat(space.gasEquipment.sort_by(&:nameString))
      end
      electric_objects.reject! { |equipment| acm_excluded_electric_equipment?(equipment) }
      next if electric_objects.empty? && gas_objects.empty? && space_type.floorArea.zero?

      acm_data = acm_equipment_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_EQUIPMENT_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM equipment data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      electric_density_w_per_m2 = acm_electric_equipment_per_area_si(acm_data['electric_equipment_per_area'])
      if electric_objects.empty? && acm_data['electric_equipment_per_area'].to_f.positive? && space_type.floorArea.positive?
        definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
        definition.setName("#{space_type.nameString} ACM Electric Equipment Definition")
        new_equipment = OpenStudio::Model::ElectricEquipment.new(definition)
        new_equipment.setName("#{space_type.nameString} ACM Electric Equipment")
        new_equipment.setSpaceType(space_type)
        electric_objects = [new_equipment]
      end

      unless electric_objects.empty?
        electric_schedule = model_add_schedule(model, acm_data['electric_equipment_schedule'])
        electric_objects.each do |equipment_object|
          equipment_object.electricEquipmentDefinition.setWattsperSpaceFloorArea(electric_density_w_per_m2)
          equipment_object.setSchedule(electric_schedule)
          count_electric += 1
        end
      end

      next if gas_objects.empty?

      gas_schedule = model_add_schedule(model, acm_data['gas_equipment_schedule'])
      gas_objects.each do |equipment_object|
        equipment_object.setSchedule(gas_schedule)
        count_gas += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM equipment fields to #{count_electric} ElectricEquipment object(s) and #{count_gas} GasEquipment object(s).")
    count_electric.positive? || count_gas.positive?
  end

  def acm_equipment_data_for_space_type(space_type, building_type: nil)
    lookup_building_type = building_type
    lookup_building_type ||= space_type.standardsBuildingType.get if space_type.standardsBuildingType.is_initialized
    lookup_building_type ||= model_get_primary_building_type(space_type.model, remap_office: false)
    standards_building_type = acm_building_type_for_lookup(lookup_building_type, throw_if_not_found: true)

    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found: true)
  end

  def acm_electric_equipment_per_area_si(w_per_ft2)
    OpenStudio.convert(w_per_ft2.to_f, 'W/ft^2', 'W/m^2').get
  end

  def acm_excluded_electric_equipment?(equipment)
    definition = equipment.electricEquipmentDefinition
    name_values = [equipment.nameString, definition.nameString]
    end_use = equipment.respond_to?(:endUseSubcategory) ? equipment.endUseSubcategory.to_s : ''
    return false if end_use != 'Elevators' && name_values.any? { |value| value.to_s.downcase.include?('acm electric equipment') }

    values = name_values + [end_use]
    values.any? do |value|
      ACM_ELECTRIC_EQUIPMENT_EXCLUDED_NAME_FRAGMENTS.any? { |fragment| value.to_s.downcase.include?(fragment) }
    end
  end

  def model_apply_acm_service_water_heating(model, building_type: nil)
    water_use_by_space_type = acm_water_use_equipment_by_space_type(model)
    space_type_floor_area = model_create_space_type_hash(model, false).transform_values { |values| values[:floor_area].to_f }
    count = 0

    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      next if water_use_by_space_type.key?(space_type.handle.to_s)

      floor_area_m2 = space_type_floor_area[space_type]
      next if floor_area_m2.nil? || floor_area_m2.zero?

      acm_data = acm_swh_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_SWH_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM service water heating data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      next unless acm_data['service_water_heating_peak_flow_per_area'].to_f.positive?

      definition = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)
      definition.setName("#{space_type.nameString} ACM Service Water Use Definition")
      equipment = OpenStudio::Model::WaterUseEquipment.new(definition)
      equipment.setName("#{space_type.nameString} ACM Service Water Use")
      spaces = model.getSpaces.select { |space| space.spaceType.is_initialized && space.spaceType.get == space_type }
      equipment.setSpace(spaces.max_by(&:floorArea)) unless spaces.empty?
      water_use_by_space_type[space_type.handle.to_s] = { space_type:, water_use_equipment: [equipment] }
    end

    water_use_by_space_type.each_value do |entry|
      space_type = entry[:space_type]
      water_use_equipment = entry[:water_use_equipment]
      acm_data = acm_swh_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_SWH_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM service water heating data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      floor_area_m2 = space_type_floor_area[space_type]
      if floor_area_m2.nil? || floor_area_m2.zero?
        OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "Skipping ACM SWH for '#{space_type.nameString}' because its floor area is zero.")
        next
      end

      schedule = model_add_schedule(model, acm_data['service_water_heating_schedule'])
      peak_flow_rate_m3_per_s = acm_swh_peak_flow_rate_si(acm_data['service_water_heating_peak_flow_per_area'], floor_area_m2)
      existing_peak_flow_rate_m3_per_s = water_use_equipment.sum { |equipment| equipment.waterUseEquipmentDefinition.peakFlowRate }
      fallback_split = 1.0 / water_use_equipment.size

      water_use_equipment.each do |equipment|
        ratio = existing_peak_flow_rate_m3_per_s.positive? ? equipment.waterUseEquipmentDefinition.peakFlowRate / existing_peak_flow_rate_m3_per_s : fallback_split
        equipment.waterUseEquipmentDefinition.setPeakFlowRate(peak_flow_rate_m3_per_s * ratio)
        equipment.setFlowRateFractionSchedule(schedule)
        count += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM service water heating fields to #{count} WaterUseEquipment object(s).")
    count.positive?
  end

  def acm_swh_data_for_space_type(space_type, building_type: nil)
    return space_type_get_acm_standards_data(space_type, throw_if_not_found: true) if building_type.nil?

    lookup_building_type = building_type
    lookup_building_type ||= space_type.standardsBuildingType.get if space_type.standardsBuildingType.is_initialized
    lookup_building_type ||= model_get_primary_building_type(space_type.model, remap_office: false)
    standards_building_type = acm_building_type_for_lookup(lookup_building_type, throw_if_not_found: true)

    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    acm_space_type_candidates(standards_building_type, space_type.nameString).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found: true)
  end

  def acm_swh_peak_flow_rate_si(peak_flow_rate_gal_per_hr_per_ft2, floor_area_m2)
    floor_area_ft2 = OpenStudio.convert(floor_area_m2, 'm^2', 'ft^2').get
    OpenStudio.convert(peak_flow_rate_gal_per_hr_per_ft2.to_f * floor_area_ft2, 'gal/hr', 'm^3/s').get
  end

  def acm_water_use_equipment_by_space_type(model)
    water_use_by_space_type = {}
    model.getWaterUseEquipments.sort_by(&:nameString).each do |equipment|
      space_type = acm_space_type_for_water_use_equipment(equipment)
      if space_type.nil?
        OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "Skipping ACM SWH for '#{equipment.nameString}' because its source SpaceType could not be found.")
        next
      end

      key = space_type.handle.to_s
      water_use_by_space_type[key] ||= { space_type:, water_use_equipment: [] }
      water_use_by_space_type[key][:water_use_equipment] << equipment
    end

    water_use_by_space_type
  end

  def acm_space_type_for_water_use_equipment(equipment)
    model = equipment.model
    if equipment.space.is_initialized
      space = equipment.space.get
      return space.spaceType.get if space.spaceType.is_initialized
    end
    return equipment.spaceType.get if equipment.spaceType.is_initialized

    equipment_name = equipment.nameString.delete_prefix('Booster ').sub(/\s+\d+\s+units\z/, '')
    model.getSpaceTypes.find { |candidate| candidate.nameString == equipment_name } ||
      model.getSpaceTypes.find { |candidate| equipment_name.start_with?(candidate.nameString) }
  end

  def model_apply_acm_hvac_availability_schedule(model, building_type: nil)
    acm_data = model_get_acm_standards_data(model, throw_if_not_found: true, building_type:)
    schedule_name = acm_data['hvac_operation_schedule']
    return false if schedule_name.nil? || schedule_name.empty?

    schedule = nil
    count_availability = 0
    HVAC_AVAILABILITY_SCHEDULE_MAP.each do |hvac_type, methods|
      objects = model.respond_to?(:"get#{hvac_type}s") ? model.send(:"get#{hvac_type}s") : []
      next if objects.empty?

      schedule ||= model_add_schedule(model, schedule_name)
      model.getBuilding.additionalProperties.setFeature(ACM_HVAC_OPERATION_SCHEDULE_FEATURE, schedule_name)
      objects.each do |object|
        methods.each do |_getter, setter|
          raise "HVAC_AVAILABILITY_SCHEDULE_MAP is out of date, #{object.briefDescription} does not respond to #{setter}" unless object.respond_to?(setter)

          count_availability += 1 if object.send(setter, schedule)
        end
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM HVAC availability schedule '#{schedule_name}' to #{count_availability} objects.")
    count_availability.positive?
  end

  # Attaches each space type's ACM lighting_schedule to its Lights objects.
  # Only the schedule is changed; lighting power (LPD) is left untouched.
  def model_apply_acm_lighting_schedule(model)
    count = 0
    model.getSpaceTypes.sort.each do |space_type|
      lights = space_type.lights
      next if lights.empty?

      schedule_name = space_type_get_acm_standards_data(space_type, throw_if_not_found: false)['lighting_schedule']
      next if schedule_name.nil? || schedule_name.empty?

      schedule = model_add_schedule(model, schedule_name)
      next if schedule.nil?

      lights.each { |light| count += 1 if light.setSchedule(schedule) }
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM lighting schedule to #{count} Lights object(s).")
    count.positive?
  end

  # Attaches each space type's ACM heating/cooling setpoint schedules to the
  # thermostats of the thermal zones its spaces occupy. Only the setpoint
  # schedules change; thermostats created by create_typical are reused.
  def model_apply_acm_thermostat_setpoint_schedules(model)
    count = 0
    model.getSpaceTypes.sort.each do |space_type|
      acm_data = space_type_get_acm_standards_data(space_type, throw_if_not_found: false)
      heating_schedule = acm_add_setpoint_schedule(model, acm_data['heating_setpoint_schedule'])
      cooling_schedule = acm_add_setpoint_schedule(model, acm_data['cooling_setpoint_schedule'])
      next if heating_schedule.nil? && cooling_schedule.nil?

      space_type.spaces.each do |space|
        next unless space.thermalZone.is_initialized

        thermostat = space.thermalZone.get.thermostatSetpointDualSetpoint
        next unless thermostat.is_initialized

        thermostat = thermostat.get
        count += 1 if heating_schedule && thermostat.setHeatingSetpointTemperatureSchedule(heating_schedule)
        count += 1 if cooling_schedule && thermostat.setCoolingSetpointTemperatureSchedule(cooling_schedule)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM thermostat setpoint schedules to #{count} schedule slot(s).")
    count.positive?
  end

  # Adds the named ACM setpoint schedule to the model, returning nil for a
  # blank name so callers can skip a missing heating or cooling column.
  def acm_add_setpoint_schedule(model, schedule_name)
    return nil if schedule_name.nil? || schedule_name.empty?

    model_add_schedule(model, schedule_name)
  end

  # Attaches each space type's ACM infiltration_schedule to the
  # SpaceInfiltrationDesignFlowRate objects on its spaces. Runs after
  # model_apply_standard_infiltration, which rebuilds space-level infiltration
  # at the ACM rate; this only sets the schedule.
  def model_apply_acm_infiltration_schedule(model)
    count = 0
    model.getSpaceTypes.sort.each do |space_type|
      schedule_name = space_type_get_acm_standards_data(space_type, throw_if_not_found: false)['infiltration_schedule']
      next if schedule_name.nil? || schedule_name.empty?

      schedule = model_add_schedule(model, schedule_name)
      next if schedule.nil?

      space_type.spaces.each do |space|
        space.spaceInfiltrationDesignFlowRates.each do |infiltration|
          count += 1 if infiltration.setSchedule(schedule)
        end
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM infiltration schedule to #{count} SpaceInfiltrationDesignFlowRate object(s).")
    count.positive?
  end

  # Why: the PRM baseline generator needs 179D inputs captured before it
  # rebuilds the model.
  # What: stamps PRM-valid lighting space types and saves proposed design OA.
  # How: uses vanilla PRM data for LPD names, then reads current air-loop OA.
  # Used by: the create-179D-baseline measure before vanilla PRM generation.
  def model_prepare_179d_prm_baseline_overrides(model, prm_standard: Standard.build(PRM_2019_TEMPLATE))
    building_type = nil
    if model.getBuilding.standardsBuildingType.is_initialized || model.getSpaceTypes.any? { |space_type| space_type.standardsBuildingType.is_initialized }
      building_type = model_get_primary_building_type(model, remap_office: true, remap_retail: true)
    end
    prepare_space_types_for_prm_lighting(model, prm_standard:)
    { building_type:, proposed_total_oa_m3s: compute_total_design_oa_m3_per_s(model) }
  end

  # Why: the vanilla PRM baseline pass omits 179D-only post-processing.
  # What: adds heated-only ventilation and adjusts baseline OA/reheat behavior.
  # How: applies the saved pre-baseline state after PRM has rebuilt HVAC.
  # Used by: the create-179D-baseline measure after vanilla PRM generation.
  def model_apply_179d_prm_baseline_overrides(model, state = {})
    state_hash = state.is_a?(Hash) ? state : {}
    proposed_total_oa_m3s = state.is_a?(Hash) ? state[:proposed_total_oa_m3s] : state
    add_heated_only_zone_ventilation(model)
    apply_179d_baseline_post_steps(model, proposed_total_oa_m3s)
    apply_non_acm_reheat_max_air_temperature_headroom(model)
    model_apply_acm_equipment_loads(model, building_type: state_hash[:building_type])
    true
  end

  # Why: the ACM overlay should own 179D decisions without replacing the PRM rule engine.
  # What: installs ACM infiltration, building-type, lighting, and fan-power hooks.
  # How: uses singleton methods so the pinned PRM class stays untouched.
  # Used by: the baseline and HVAC-control measures on PRM-2019 paths.
  def prepare_prm_standard_for_acm_overrides(prm_standard)
    acm_standard = self
    prm_fan_power_method = prm_standard.method(:air_loop_hvac_apply_prm_baseline_fan_power)
    prm_get_airloop_design_oa = prm_standard.method(:get_airloop_hvac_design_oa_from_sql)

    prm_standard.define_singleton_method(:baseline_thermal_zone_demand_control_ventilation_required?) do |thermal_zone|
      prm_standard.send(:user_model_zone_demand_control_ventilation_required?, thermal_zone)
    end
    prm_standard.define_singleton_method(:baseline_air_loop_hvac_demand_control_ventilation_required?) do |air_loop_hvac|
      prm_standard.send(:user_model_air_loop_hvac_demand_control_ventilation_required?, air_loop_hvac)
    end
    prm_standard.define_singleton_method(:get_airloop_hvac_design_oa_from_sql) do |air_loop_hvac|
      acm_standard.acm_airloop_design_oa_with_sizing_fallback(air_loop_hvac, prm_get_airloop_design_oa)
    end
    prm_standard.define_singleton_method(:space_type_light_sch_change) do |model|
      acm_standard.space_type_light_sch_change(model)
    end
    prm_standard.define_singleton_method(:model_get_infiltration_coefficients) do |model|
      acm_standard.model_get_infiltration_coefficients(model)
    end
    prm_standard.define_singleton_method(:model_apply_standard_infiltration) do |model, infiltration_rate: nil|
      acm_standard.model_apply_standard_infiltration(model, infiltration_rate:, prm_standard:)
    end
    prm_standard.define_singleton_method(:__model_get_primary_building_type) do |model|
      acm_standard.__model_get_primary_building_type(model)
    end
    prm_standard.define_singleton_method(:model_get_primary_building_type) do |model, remap_office: false, remap_retail: false|
      acm_standard.model_get_primary_building_type(model, remap_office:, remap_retail:)
    end
    prm_standard.define_singleton_method(:model_remap_office) do |model, floor_area|
      acm_standard.model_remap_office(model, floor_area)
    end
    prm_standard.define_singleton_method(:air_loop_hvac_apply_prm_baseline_fan_power) do |air_loop_hvac|
      acm_standard.ensure_prm_fan_power_features(air_loop_hvac, prm_standard)
      prm_fan_power_method.call(air_loop_hvac)
    end

    prm_standard
  end

  # EnergyPlus only fills the Standard 62.1 Summary Vot when Sizing:System OA is
  # autosized; a hard-set design OA (proposed normalization) leaves it 0 and the
  # DCV air-loop gate wrongly drops DCV. Fall back to the Sizing:System (or OA
  # controller) design OA when the 62.1 read is non-positive.
  def acm_airloop_design_oa_with_sizing_fallback(air_loop_hvac, prm_get_airloop_design_oa)
    oa_m3_per_s = prm_get_airloop_design_oa.call(air_loop_hvac)
    return oa_m3_per_s if oa_m3_per_s.is_a?(Numeric) && oa_m3_per_s > 0.0

    sizing_system = air_loop_hvac.sizingSystem
    return sizing_system.designOutdoorAirFlowRate.get if sizing_system.designOutdoorAirFlowRate.is_initialized
    return sizing_system.autosizedDesignOutdoorAirFlowRate.get if sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized

    return 0.0 unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized

    controller_oa = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
    return controller_oa.minimumOutdoorAirFlowRate.get if controller_oa.minimumOutdoorAirFlowRate.is_initialized
    return controller_oa.autosizedMinimumOutdoorAirFlowRate.get if controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized

    0.0
  end

  # Why: proposed models must keep claimed equipment/LPD choices while matching
  # baseline-grade neutral HVAC controls.
  # What: normalizes retained proposed HVAC without rebuilding it or applying
  # standard equipment efficiency.
  # How: calls vanilla PRM methods through prm_standard, with ACM hooks around
  # infiltration, DCV, exhaust makeup, heated-only ventilation, and reheat fixes.
  # Used by: the HVAC-control measure for PRM-2019 proposed normalization.
  def model_create_179d_proposed_normalization(model, climate_zone, hvac_building_type = 'other nonresidential', sizing_run_dir = Dir.pwd, _debug: false, prm_standard: Standard.build(PRM_2019_TEMPLATE))
    prm_standard = prepare_prm_standard_for_acm_overrides(prm_standard)
    prm_standard.instance_variable_set(:@sizing_run_dir, sizing_run_dir)
    ensure_baseline_system_type_tags(model, climate_zone, hvac_building_type)

    prm_call(prm_standard, :model_identify_non_mechanically_cooled_systems, model)
    if prm_call(prm_standard, :model_get_fan_power_breakdown)
      model.getAirLoopHVACs.sort.each do |air_loop|
        supply_fan_w = prm_call(prm_standard, :air_loop_hvac_get_supply_fan_power, air_loop)
        return_fan_w = prm_call(prm_standard, :air_loop_hvac_get_return_fan_power, air_loop)
        relief_fan_w = prm_call(prm_standard, :air_loop_hvac_get_relief_fan_power, air_loop)
        air_loop.thermalZones.sort.each do |zone|
          zone.additionalProperties.setFeature('supply_fan_w', supply_fan_w.to_f)
          zone.additionalProperties.setFeature('return_fan_w', return_fan_w.to_f)
          zone.additionalProperties.setFeature('relief_fan_w', relief_fan_w.to_f)
        end
      end
    end

    unless model.sqlFile.is_initialized || prm_call(prm_standard, :model_run_sizing_run, model, "#{sizing_run_dir}/PROP-DCV-PREPASS")
      OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model',
                         'PROP-DCV-PREPASS sizing run failed; DCV requirements will be evaluated without sizing SQL.')
    end
    prm_call(prm_standard, :model_evaluate_dcv_requirements, model)

    model_apply_standard_infiltration(model, prm_standard:)

    model.getThermalZones.each { |zone| prm_call(prm_standard, :thermal_zone_apply_prm_baseline_supply_temperatures, zone) }
    apply_acm_exhaust_higher_reheat_design_sat(model)
    model.getAirLoopHVACs.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_prm_sizing_temperatures, air_loop) }
    prm_call(prm_standard, :model_apply_prm_baseline_sizing_schedule, model)
    prm_call(prm_standard, :model_apply_prm_sizing_parameters, model).tap { ACM179dWinterSolarDesignDay.model_add_hot_climate_winter_solar_design_day(model, climate_zone) }

    model.getAirLoopHVACs.sort.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_prm_baseline_controls, air_loop, climate_zone) }
    apply_heated_only_storage_economizer_override(model, hvac_building_type)
    each_non_swh_plant_loop(model, prm_standard:) do |plant_loop|
      prm_call(prm_standard, :plant_loop_apply_prm_baseline_temperatures, plant_loop)
    end

    return false unless prm_call(prm_standard, :model_run_sizing_run, model, "#{sizing_run_dir}/PROP-SR1")

    model.getAirLoopHVACs.sort.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_minimum_vav_damper_positions, air_loop, false) }
    apply_acm_exhaust_fixed_minimum_airflow(model)
    prm_call(prm_standard, :model_apply_multizone_vav_outdoor_air_sizing, model)

    model.getAirLoopHVACs.sort.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_prm_baseline_fan_power, air_loop) }
    model.getZoneHVACComponents.sort.each { |zone_hvac| prm_call(prm_standard, :zone_hvac_component_apply_prm_baseline_fan_power, zone_hvac) }

    each_non_swh_plant_loop(model, prm_standard:) do |plant_loop|
      prm_call(prm_standard, :plant_loop_apply_prm_number_of_boilers, plant_loop)
      prm_call(prm_standard, :plant_loop_apply_prm_number_of_chillers, plant_loop)
      prm_call(prm_standard, :plant_loop_apply_prm_number_of_cooling_towers, plant_loop)
    end

    return false unless prm_call(prm_standard, :model_run_sizing_run, model, "#{sizing_run_dir}/PROP-SR2")

    each_non_swh_plant_loop(model, prm_standard:) do |plant_loop|
      prm_call(prm_standard, :plant_loop_apply_prm_baseline_pump_power, plant_loop)
      prm_call(prm_standard, :plant_loop_apply_prm_baseline_pumping_type, plant_loop)
    end

    prm_call(prm_standard, :model_set_baseline_demand_control_ventilation, model, climate_zone)
    prm_call(prm_standard, :model_refine_size_dependent_values, model, sizing_run_dir)
    prm_call(prm_standard, :model_temp_fix_ems_references, model)
    prm_call(prm_standard, :model_remove_unused_resource_objects, model)
    prm_call(prm_standard, :model_add_reporting_tolerances, model)
    apply_heated_only_storage_economizer_override(model, hvac_building_type)
    apply_acm_exhaust_reheat_coil_capacity_floor(model)
    apply_non_acm_reheat_max_air_temperature_headroom(model)
    apply_non_acm_reheat_max_flow_during_reheat(model)
    add_heated_only_zone_ventilation(model)

    true
  end

  # Why: both proposed and baseline need the same wind-driven infiltration
  # coefficients for 179D ACM comparisons.
  # What: returns the PRM manual coefficient set.
  # How: keeps the coefficient lookup deterministic and independent of model data.
  # Used by: ACM infiltration on create-typical, baseline, and HVAC-control paths.
  def model_get_infiltration_coefficients(_model)
    [0.0, 0.0, 0.224, 0.0]
  end

  # Why: ACM 2019 sets infiltration by exterior wall area at a fixed design rate.
  # What: removes space-type infiltration and applies space infiltration objects.
  # How: computes total conditioned exterior wall area, then delegates object
  # creation to the vanilla PRM space helper.
  # Used by: create-typical directly and HVAC-control proposed normalization.
  def model_apply_standard_infiltration(model, infiltration_rate: nil, prm_standard: Standard.build(PRM_2019_TEMPLATE))
    unless infiltration_rate.nil?
      OpenStudio.logFree(OpenStudio::Debug, '179d.acm.Model', "Ignoring upstream infiltration_rate #{infiltration_rate}; ACM 2019 rate is fixed.")
    end

    ela = model.getSpaceInfiltrationEffectiveLeakageAreas.sort.size
    if ela.positive?
      OpenStudio.logFree(OpenStudio::Warn, 'prm.log', 'The current model cannot include SpaceInfiltrationEffectiveLeakageArea. These objects will be skipped in modeling infiltration according to the 90.1-PRM rules.')
    end

    acm_infil_rate_m3_per_s_per_m2 = OpenStudio.convert(ACM_INFILTRATION_RATE_CFM_PER_FT2, 'cfm/ft^2', 'm^3/s*m^2').get
    total_exterior_wall_area_m2 = 0.0
    model.getSpaces.sort_by(&:nameString).each do |space|
      next if prm_call(prm_standard, :space_conditioning_category, space) == 'Unconditioned'

      total_exterior_wall_area_m2 += space.exteriorWallArea * space.multiplier
    end
    prm_log_dir = prm_standard.instance_variable_get(:@sizing_run_dir) || Dir.pwd
    prm_call(prm_standard, :prm_raise, total_exterior_wall_area_m2.positive?, prm_log_dir, 'Total exterior wall area in the model is 0 m2, Please check model inputs.')

    tot_infil_m3_per_s = acm_infil_rate_m3_per_s_per_m2 * total_exterior_wall_area_m2
    infiltration_coefficients = model_get_infiltration_coefficients(model)
    model.getSpaces.sort_by(&:nameString).each do |space|
      prm_call(prm_standard, :space_apply_infiltration_rate, space, tot_infil_m3_per_s, 'Flow/ExteriorWallArea', infiltration_coefficients)
    end
    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      space_type.spaceInfiltrationDesignFlowRates.each(&:remove)
    end

    true
  end

  # Why: ACM exhaust zones should be balanced by transfer air, not extra outdoor
  # infiltration.
  # What: adds ZoneMixing from an adjacent conditioned zone to each ACM exhaust
  # zone and marks exhaust fans as balanced.
  # How: sizes mixing to each fan maximum flow and schedules it with ACM HVAC
  # operation hours.
  # Used by: create-typical after ACM infiltration is applied.
  def apply_acm_exhaust_makeup_zone_mixing(model, building_type: nil)
    fans = model.getFanZoneExhausts
    return if fans.empty?

    schedule_name = model_get_acm_standards_data(model, throw_if_not_found: true, building_type:)['hvac_operation_schedule']
    schedule = model_add_schedule(model, schedule_name)
    return if schedule.nil?

    fans.each do |fan|
      next unless fan.thermalZone.is_initialized
      next unless fan.maximumFlowRate.is_initialized

      zone = fan.thermalZone.get
      next unless zone.spaces.any? do |space|
        space_type = space.spaceType
        space_type.is_initialized && ACM_EXHAUST_SPACE_TYPES_PRM_2019.include?(space_type.get.standardsSpaceType.to_s)
      end

      source_zone = acm_exhaust_makeup_source_zone(zone)
      if source_zone.nil?
        OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "No adjacent conditioned zone found to supply makeup air for exhaust zone '#{zone.name}'.")
        next
      end

      fan.setBalancedExhaustFractionSchedule(model.alwaysOnDiscreteSchedule)
      mixing_name = "#{fan.name} Makeup mixing"
      next if model.getZoneMixings.any? { |zone_mixing| zone_mixing.nameString == mixing_name }

      max_flow_m3s = fan.maximumFlowRate.get
      mixing = OpenStudio::Model::ZoneMixing.new(zone)
      mixing.setName(mixing_name)
      mixing.setSourceZone(source_zone)
      mixing.setDesignFlowRate(max_flow_m3s)
      mixing.setSchedule(schedule)

      OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Added makeup ZoneMixing '#{mixing.name}' drawing from '#{source_zone.name}' into '#{zone.name}'.")
    end
  end

  # Why: exhaust makeup transfer air needs a plausible conditioned source zone.
  # What: selects the largest conditioned neighboring zone.
  # How: walks matched interior surfaces and filters neighbors with thermostats.
  # Used by: apply_acm_exhaust_makeup_zone_mixing.
  def acm_exhaust_makeup_source_zone(zone)
    neighbors = {}
    zone.spaces.each do |space|
      space.surfaces.each do |surface|
        adjacent_surface = surface.adjacentSurface
        next unless adjacent_surface.is_initialized

        adjacent_space = adjacent_surface.get.space
        next unless adjacent_space.is_initialized

        candidate = adjacent_space.get.thermalZone
        next unless candidate.is_initialized

        candidate_zone = candidate.get
        next if candidate_zone.handle == zone.handle
        next unless candidate_zone.thermostat.is_initialized

        neighbors[candidate_zone.handle] = candidate_zone
      end
    end
    neighbors.values.max_by(&:floorArea)
  end

  # Why: heated-only zones served only by unit heaters can otherwise lose design
  # outdoor air in both baseline and proposed paths.
  # What: adds equivalent ZoneVentilation to those heated-only zones.
  # How: finds unit-heater zones without air loops or existing zone ventilation.
  # Used by: baseline post-overrides and proposed normalization.
  def add_heated_only_zone_ventilation(model)
    heated_only_zones = model.getThermalZones.select do |zone|
      next false unless zone.airLoopHVACs.empty?
      next false if zone.equipment.any? { |equipment| equipment.to_ZoneVentilationDesignFlowRate.is_initialized }

      zone.equipment.any? { |equipment| equipment.to_ZoneHVACUnitHeater.is_initialized }
    end
    return if heated_only_zones.empty?

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Adding ZoneVentilationDesignFlowRate to #{heated_only_zones.size} heated-only zone(s).")
    model_add_equivalent_zone_ventilation_for_heated_only_zones_with_dsoa(model, heated_only_zones, ventilation_type: 'Exhaust')
  end

  # Why: heated-only ventilation needs explicit fan and sizing support.
  # What: creates ZoneVentilation and optional design-day infiltration per zone.
  # How: converts each zone DSOA rate to flow per floor area and assigns fan
  # pressure based on the selected ventilation type.
  # Used by: add_heated_only_zone_ventilation.
  def model_add_equivalent_zone_ventilation_for_heated_only_zones_with_dsoa(model, zones, ventilation_type: 'Natural', ensure_ddy_infiltration: true)
    zones.sort.each do |zone|
      total_oa_m3_per_s = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
      total_oa_m3_per_m2s = total_oa_m3_per_s / zone.floorArea
      next unless total_oa_m3_per_s.positive?

      ventilation = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
      ventilation.setName("#{zone.name} Ventilation")
      ventilation.setSchedule(model.alwaysOnDiscreteSchedule)
      ventilation.setFlowRateperZoneFloorArea(total_oa_m3_per_m2s)
      ventilation.setConstantTermCoefficient(1.0)
      ventilation.setVelocityTermCoefficient(0.0)
      ventilation.setTemperatureTermCoefficient(0.0)
      ventilation.setMinimumIndoorTemperature(-73.3333352760033)
      ventilation.setMaximumIndoorTemperature(100.0)
      ventilation.setDeltaTemperature(-100.0)

      case ventilation_type
      when 'Natural'
        pressure_rise_pa = 0.0
        fan_total_eff = 1.0
      when 'Intake'
        target_w_per_m3_per_s = OpenStudio.convert(0.3, 'W/CFM', 'W*s/m^3').get
        fan_total_eff = 0.6
        pressure_rise_pa = fan_total_eff * target_w_per_m3_per_s
      when 'Exhaust'
        target_w_per_m3_per_s = OpenStudio.convert(0.054, 'W/CFM', 'W*s/m^3').get
        fan_total_eff = 0.6
        pressure_rise_pa = fan_total_eff * target_w_per_m3_per_s
      else
        raise "ventilation_type must be one of ['Natural', 'Intake', 'Exhaust']"
      end

      ventilation.setVentilationType(ventilation_type)
      ventilation.setFanPressureRise(pressure_rise_pa)
      ventilation.setFanTotalEfficiency(fan_total_eff)
      ventilation.addToThermalZone(zone)
      zone.setHeatingPriority(ventilation, 0)
      zone.setCoolingPriority(ventilation, 0)

      next unless ensure_ddy_infiltration

      zone.spaces.each do |space|
        next if space.infiltrationDesignAirChangesPerHour > 0.001

        infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        infiltration.setName("#{space.nameString} Design Day Only Infiltration")
        infiltration.setSpace(space)
        infiltration.setSchedule(ddy_only_infiltration_schedule(model))
        if space.designSpecificationOutdoorAir.is_initialized
          infiltration.setFlowperSpaceFloorArea(space_get_outdoor_airflow_rate(space) / space.floorArea)
        else
          infiltration.setAirChangesperHour(0.01)
        end
      end
    end
  end

  # Why: the rebuilt PRM baseline can change total design outdoor air from the
  # proposed model used for the 179D comparison.
  # What: scales baseline air-loop design OA to match the captured proposed total.
  # How: compares total OA after rebuild and scales each baseline air loop when
  # the difference is larger than one percent.
  # Used by: model_apply_179d_prm_baseline_overrides.
  def apply_179d_baseline_post_steps(model, proposed_total_oa_m3s = nil)
    return if proposed_total_oa_m3s.nil?

    baseline_total_oa_m3s = compute_total_design_oa_m3_per_s(model)
    pct_diff = if baseline_total_oa_m3s.zero?
                 proposed_total_oa_m3s.zero? ? 0.0 : 100.0
               else
                 (proposed_total_oa_m3s - baseline_total_oa_m3s) / baseline_total_oa_m3s * 100.0
               end
    return if pct_diff.abs <= 1.0

    if baseline_total_oa_m3s.zero?
      OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "Baseline total OA is 0 m^3/s but proposed is #{proposed_total_oa_m3s.round(3)} m^3/s; skipping baseline OA scale step.")
      return
    end

    scaling_factor = proposed_total_oa_m3s / baseline_total_oa_m3s
    model.getAirLoopHVACs.sort.each do |air_loop|
      sizing_system = air_loop.sizingSystem
      old_value = if sizing_system.designOutdoorAirFlowRate.is_initialized
                    sizing_system.designOutdoorAirFlowRate.get
                  elsif sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized
                    sizing_system.autosizedDesignOutdoorAirFlowRate.get
                  end

      if old_value
        sizing_system.setDesignOutdoorAirFlowRate(old_value * scaling_factor)
      else
        raise "Cannot adjust baseline design outdoor airflow rate; no existing value found on air loop '#{air_loop.nameString}'."
      end
    end
  end

  # Why: baseline OA scaling needs a simple model-level design OA total.
  # What: sums design OA on air loops with outdoor-air systems.
  # How: prefers explicit Sizing:System OA and falls back to autosized OA.
  # Used by: baseline pre/post override state capture.
  def compute_total_design_oa_m3_per_s(model)
    total = 0.0
    model.getAirLoopHVACs.each do |air_loop|
      next if air_loop.airLoopHVACOutdoorAirSystem.empty?

      sizing_system = air_loop.sizingSystem
      total += if sizing_system.designOutdoorAirFlowRate.is_initialized
                 sizing_system.designOutdoorAirFlowRate.get
               elsif sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized
                 sizing_system.autosizedDesignOutdoorAirFlowRate.get
               else
                 0.0
               end
    end
    total
  end

  # Why: ACM exhaust VAV zones need enough reheat temperature for pinned minimum
  # airflow.
  # What: raises zone heating design SAT for ACM exhaust VAV:Reheat zones.
  # How: sets the sizing-zone heating design supply temperature before PRM sizing.
  # Used by: proposed normalization before sizing runs.
  def apply_acm_exhaust_higher_reheat_design_sat(model)
    model.getThermalZones.each do |zone|
      next unless acm_exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      zone.sizingZone.setZoneHeatingDesignSupplyAirTemperature(ACM_EXHAUST_HIGH_REHEAT_DESIGN_SAT_C)
    end
  end

  # Raises exterior non-ACM VAV:Reheat terminal caps after PRM sizing without lowering existing caps.
  def apply_non_acm_reheat_max_air_temperature_headroom(model)
    model.getThermalZones.each do |zone|
      next if acm_exhaust_zone?(zone)
      next unless zone.spaces.any? { |space| space.exteriorWallArea > 0.0 }

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      next if vav_terminal.maximumReheatAirTemperature >= NON_ACM_REHEAT_MAX_AIR_TEMPERATURE_C

      vav_terminal.setMaximumReheatAirTemperature(NON_ACM_REHEAT_MAX_AIR_TEMPERATURE_C)
    end
  end

  # Why: PRM minimum-damper logic can undo exhaust-matched VAV minimum airflow.
  # What: pins ACM exhaust VAV minimum flow to the zone exhaust design flow.
  # How: sets FixedFlowRate on VAV:Reheat terminals serving ACM exhaust zones.
  # Used by: proposed normalization after PRM minimum-damper adjustment.
  def apply_acm_exhaust_fixed_minimum_airflow(model)
    model.getThermalZones.each do |zone|
      next unless acm_exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      exhaust_m3s = zone_exhaust_maximum_flow_rate(zone)
      next if exhaust_m3s <= 0.0

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      vav_terminal.setZoneMinimumAirFlowInputMethod('FixedFlowRate')
      vav_terminal.setFixedMinimumAirFlowRate(exhaust_m3s)
    end
  end

  # Why: autosized reheat coils can be too small for ACM exhaust minimum supply.
  # What: floors hot-water reheat coil capacity for ACM exhaust VAV terminals.
  # How: computes a capacity floor from exhaust flow, air heat capacity, and SAT
  # lift, then raises capacity and water flow only when needed.
  # Used by: proposed normalization after sizing runs.
  def apply_acm_exhaust_reheat_coil_capacity_floor(model)
    rho_air = 1.2
    cp_air = 1005.0
    cooling_sat_c = 12.8889
    sizing_factor = 1.25

    model.getThermalZones.each do |zone|
      next unless acm_exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      exhaust_m3s = zone_exhaust_maximum_flow_rate(zone)
      next if exhaust_m3s <= 0.0

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      heating_coil = vav_terminal.reheatCoil.to_CoilHeatingWater
      next unless heating_coil.is_initialized

      coil = heating_coil.get
      target_capacity_w = exhaust_m3s * rho_air * cp_air * (ACM_EXHAUST_HIGH_REHEAT_DESIGN_SAT_C - cooling_sat_c) * sizing_factor
      current_capacity_w = if coil.ratedCapacity.is_initialized
                             coil.ratedCapacity.get
                           elsif coil.autosizedRatedCapacity.is_initialized
                             coil.autosizedRatedCapacity.get
                           end
      next unless current_capacity_w.nil? || current_capacity_w < target_capacity_w

      coil.setRatedCapacity(target_capacity_w)
      next unless current_capacity_w&.positive?

      current_water_m3s = if coil.maximumWaterFlowRate.is_initialized
                            coil.maximumWaterFlowRate.get
                          elsif coil.autosizedMaximumWaterFlowRate.is_initialized
                            coil.autosizedMaximumWaterFlowRate.get
                          end
      coil.setMaximumWaterFlowRate(current_water_m3s * target_capacity_w / current_capacity_w) if current_water_m3s
    end
  end

  # Why: high-occupancy non-ACM zones may need full damper opening during reheat
  # recovery.
  # What: sets MaximumFlowFractionDuringReheat to 1.0 on qualifying terminals.
  # How: filters to non-ACM VAV:Reheat hot-water terminals with high people load.
  # Used by: proposed normalization near final cleanup.
  def apply_non_acm_reheat_max_flow_during_reheat(model)
    model.getThermalZones.each do |zone|
      next if acm_exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      next unless vav_terminal.reheatCoil.to_CoilHeatingWater.is_initialized
      next unless zone.floorArea.positive?

      people_density = zone.numberOfPeople / zone.floorArea
      next unless people_density >= REHEAT_HIGH_OCC_MIN_DENSITY_PPL_PER_M2 && zone.numberOfPeople >= REHEAT_HIGH_OCC_MIN_PEOPLE

      vav_terminal.setMaximumFlowFractionDuringReheat(1.0)
    end
  end

  # Why: PRM baseline lighting lookup needs PRM-valid space type names.
  # What: maps prototype space type names to PRM LPD table names.
  # How: leaves already-valid PRM names alone and stamps only known prototype
  # names.
  # Used by: model_prepare_179d_prm_baseline_overrides.
  def prepare_space_types_for_prm_lighting(model, prm_standard: Standard.build(PRM_2019_TEMPLATE))
    valid_lpd = (prm_standard.standards_data['prm_interior_lighting'] || []).filter_map { |row| row['lpd_space_type'] }.uniq
    model.getSpaceTypes.each do |space_type|
      next unless space_type.standardsSpaceType.is_initialized

      current = space_type.standardsSpaceType.get
      next if valid_lpd.include?(current)

      mapped = PROTOTYPE_TO_PRM_LPD_SPACE_TYPE[current]
      if mapped.nil?
        OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "No PRM lpd_space_type mapping for '#{current}'; baseline lighting may be zero.")
        next
      end
      space_type.setStandardsSpaceType(mapped)
    end
  end

  # Preserve ACM lighting schedules during PRM baseline generation.
  def space_type_light_sch_change(_model)
    true
  end

  # Why: PRM apply methods expect baseline_system_type tags on retained HVAC.
  # What: writes one inferred baseline system type to air loops and zones.
  # How: selects the type from PRM-2019 climate, area, story, and building-type
  # rules.
  # Used by: proposed normalization before vanilla PRM HVAC apply calls.
  def ensure_baseline_system_type_tags(model, climate_zone, hvac_building_type)
    system_type = select_baseline_system_type(hvac_building_type, model, climate_zone)
    model.getAirLoopHVACs.each { |air_loop| air_loop.additionalProperties.setFeature('baseline_system_type', system_type) }
    model.getThermalZones.each { |zone| zone.additionalProperties.setFeature('baseline_system_type', system_type) }
    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Tagged retained HVAC with inferred baseline_system_type='#{system_type}'.")
  end

  # Why: proposed normalization keeps real HVAC but still needs PRM baseline type
  # tags for downstream control/fan rules.
  # What: returns the PRM-2019 baseline_system_type string.
  # How: applies the compact Appendix G selection logic from building category,
  # climate zone, floor area, and story count.
  # Used by: ensure_baseline_system_type_tags.
  def select_baseline_system_type(hvac_building_type, model, climate_zone)
    climate_zone_code = climate_zone.to_s.split('-')[-1].to_s.upcase
    warm = HOT_CLIMATE_ZONES.include?(climate_zone_code)
    area_ft2 = OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get
    floors = [model.getBuildingStorys.size, 1].max

    case hvac_building_type
    when 'residential'
      warm ? 'PTHP' : 'PTAC'
    when 'public assembly'
      if area_ft2 < 120_000
        warm ? 'PSZ_HP' : 'PSZ_AC'
      else
        warm ? 'SZ_CV_ER' : 'SZ_CV_HW'
      end
    when 'heated-only storage'
      warm ? 'Electric_Furnace' : 'Gas_Furnace'
    when 'retail'
      warm ? 'PSZ_HP' : 'PSZ_AC'
    when 'hospital'
      area_ft2 > 150_000 ? 'VAV_Reheat' : 'PVAV_Reheat'
    else
      if floors <= 3 && area_ft2 < 25_000
        warm ? 'PSZ_HP' : 'PSZ_AC'
      elsif (floors.between?(4, 5) && area_ft2 < 25_000) || (floors <= 5 && area_ft2.between?(25_000, 150_000))
        warm ? 'PVAV_PFP_Boxes' : 'PVAV_Reheat'
      else
        warm ? 'VAV_PFP_Boxes' : 'VAV_Reheat'
      end
    end
  end

  # Why: proposed normalization adjusts HVAC plant loops but should leave service
  # water heating loops alone.
  # What: yields only non-SWH plant loops.
  # How: delegates the SWH-loop test to the vanilla PRM standard.
  # Used by: proposed normalization plant temperature/count/pump steps.
  def each_non_swh_plant_loop(model, prm_standard: Standard.build(PRM_2019_TEMPLATE))
    model.getPlantLoops.sort.each do |plant_loop|
      next if prm_call(prm_standard, :plant_loop_swh_loop?, plant_loop)

      yield plant_loop
    end
  end

  # Why: heated-only storage baseline type should not retain economizer controls.
  # What: disables economizers on air loops when the inferred HVAC category is
  # heated-only storage.
  # How: sets each outdoor-air controller economizer control type to NoEconomizer.
  # Used by: proposed normalization before and after PRM control/refinement steps.
  def apply_heated_only_storage_economizer_override(model, hvac_building_type)
    return unless hvac_building_type == 'heated-only storage'

    model.getAirLoopHVACs.sort.each do |air_loop|
      next if air_loop.airLoopHVACOutdoorAirSystem.empty?

      air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.setEconomizerControlType('NoEconomizer')
    end
  end

  # Why: heated-only zones may need sizing-only infiltration support.
  # What: returns a schedule that is on only for design days.
  # How: creates or reuses a ScheduleRuleset with winter/summer design days at 1.
  # Used by: heated-only equivalent ventilation helper.
  def ddy_only_infiltration_schedule(model)
    schedule_name = 'Infiltration Schedule Only One on Design Days'
    existing = model.getScheduleRulesetByName(schedule_name)
    return existing.get if existing.is_initialized

    schedule = OpenStudio::Model::ScheduleRuleset.new(model, 0.0)
    schedule.setName(schedule_name)
    schedule.defaultDaySchedule.setName("#{schedule_name} Default Day")
    winter_day = OpenStudio::Model::ScheduleDay.new(model)
    schedule.setWinterDesignDaySchedule(winter_day)
    winter_day.remove
    schedule.winterDesignDaySchedule.setName("#{schedule_name} Winter Design Day")
    schedule.winterDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
    summer_day = OpenStudio::Model::ScheduleDay.new(model)
    schedule.setSummerDesignDaySchedule(summer_day)
    summer_day.remove
    schedule.summerDesignDaySchedule.setName("#{schedule_name} Summer Design Day")
    schedule.summerDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
    schedule
  end

  # Why: design-day infiltration for heated-only ventilation needs each space OA.
  # What: calculates total outdoor airflow from a space DSOA object.
  # How: combines per-person, per-area, fixed, and ACH terms using sum or max.
  # Used by: heated-only equivalent ventilation helper.
  def space_get_outdoor_airflow_rate(space)
    return 0.0 if space.designSpecificationOutdoorAir.empty?

    outdoor_air = space.designSpecificationOutdoorAir.get
    values = [
      space.numberOfPeople * outdoor_air.outdoorAirFlowperPerson,
      space.floorArea * outdoor_air.outdoorAirFlowperFloorArea,
      outdoor_air.outdoorAirFlowRate,
      space.volume * outdoor_air.outdoorAirFlowAirChangesperHour / 3600.0
    ]
    outdoor_air.outdoorAirMethod.casecmp('sum').zero? ? values.sum : values.max
  end

  def acm_exhaust_zone?(zone)
    zone.spaces.any? do |space|
      space_type = space.spaceType
      space_type.is_initialized && ACM_EXHAUST_SPACE_TYPES_PRM_2019.include?(space_type.get.standardsSpaceType.to_s)
    end
  end

  def zone_exhaust_maximum_flow_rate(zone)
    zone.equipment.sum do |equipment|
      next 0.0 unless equipment.to_FanZoneExhaust.is_initialized

      fan = equipment.to_FanZoneExhaust.get
      fan.maximumFlowRate.is_initialized ? fan.maximumFlowRate.get : 0.0
    end
  end

  def prm_call(prm_standard, method_name, *args)
    prm_standard.send(method_name, *args)
  end

  def acm_building_type_for_lookup(building_type, throw_if_not_found: true)
    acm_building_type = ACM_BUILDING_TYPE_BY_PROTOTYPE.fetch(building_type, model_get_lookup_name(building_type))
    rows = model_find_objects(
      standards_data['space_types'] || [],
      'template' => template,
      'building_type' => acm_building_type
    )
    return acm_building_type unless rows.empty?

    msg = "No 179D ACM space-type rows for building type '#{building_type}' (resolved as '#{acm_building_type}')."
    if throw_if_not_found
      OpenStudio.logFree(OpenStudio::Error, '179d.acm.Model', msg)
      raise msg
    end

    OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', msg)
    nil
  end

  def acm_hvac_operation_schedule_properties(standards_building_type)
    rows = model_find_objects(
      standards_data['space_types'] || [],
      'template' => template,
      'building_type' => standards_building_type
    )
    rows.find { |row| !row['hvac_operation_schedule'].to_s.empty? } || {}
  end

  def __model_get_primary_building_type(model)
    building_types = {}

    building = model.getBuilding
    building_level_type = nil
    if building.standardsBuildingType.is_initialized
      building_level_type = model_get_lookup_name(building.standardsBuildingType.get)
      OpenStudio.logFree(OpenStudio::Debug, '179d.acm.Model', "found Building level standardsBuildingType = '#{building_level_type}'")
    end

    model.getSpaceTypes.sort.each do |space_type|
      next unless space_type.standardsBuildingType.is_initialized

      building_type = model_get_lookup_name(space_type.standardsBuildingType.get)
      building_types[building_type] ||= 0.0
      building_types[building_type] += space_type.floorArea
    end

    if building_types.empty?
      if building_level_type.nil?
        msg = "Cannot identify a single building type in model, none of your #{model.getSpaceTypes.size} SpaceTypes have a standardsBuildingType assigned and neither does the Building"
        OpenStudio.logFree(OpenStudio::Error, '179d.acm.Model', msg)
        raise 'No Primary Building Type found'
      end
      return building_level_type
    end

    building_types.max_by { |_building_type, floor_area| floor_area }.first
  end

  def model_get_primary_building_type(model, remap_office: false, remap_retail: false)
    @primary_building_types_memoized ||= {}
    @primary_building_types_memoized[model] ||= __model_get_primary_building_type(model)

    building_type = @primary_building_types_memoized[model]
    building_type = model_remap_office(model, model.getBuilding.floorArea) if remap_office && building_type == 'Office'
    if remap_retail
      return 'RetailStripmall' if building_type == 'StripMall'
      return 'RetailStandalone' if building_type == 'Retail'
    end
    building_type
  end

  def model_remap_office(model, floor_area)
    floor_area_sqft = OpenStudio.convert(floor_area, 'm^2', 'ft^2').get
    num_floors = model.getBuilding.buildingStories.size
    if floor_area_sqft < 25_000
      num_floors <= 3 ? 'SmallOffice' : 'MediumOffice'
    elsif floor_area_sqft < 150_000
      num_floors <= 5 ? 'MediumOffice' : 'LargeOffice'
    else
      'LargeOffice'
    end
  end

  def get_exterior_fenestration_value(sub_surface, column_name)
    known_columns = [
      'Construction',
      'Frame and Divider',
      'Glass Area',
      'Frame Area',
      'Divider Area',
      'Area of One Opening',
      'Area of Multiplied Openings',
      'Glass U-Factor',
      'Glass SHGC',
      'Glass Visible Transmittance',
      'Frame Conductance',
      'Divider Conductance',
      'NFRC Product Type',
      'Assembly U-Factor',
      'Assembly SHGC',
      'Assembly Visible Transmittance',
      'Shade Control',
      'Parent Surface',
      'Azimuth',
      'Tilt',
      'Cardinal Direction'
    ]
    raise "Unknown column '#{column_name}'. Available: #{known_columns}" unless known_columns.include?(column_name)

    sql_query = <<~SQL
      SELECT Value FROM TabularDataWithStrings
        WHERE ReportName='EnvelopeSummary'
          AND ReportForString='Entire Facility'
          AND TableName='Exterior Fenestration'
          AND RowName='#{sub_surface.nameString.upcase}'
          AND ColumnName='#{column_name}'
    SQL

    val_ = sub_surface.model.sqlFile.get.execAndReturnFirstDouble(sql_query)
    raise "Query failed: #{sql_query}" if val_.empty?

    val_.get
  end

  def get_exterior_fenestration_value_with_fallback(sub_surface, metric)
    get_exterior_fenestration_value(sub_surface, "Glass #{metric}")
  rescue RuntimeError
    get_exterior_fenestration_value(sub_surface, "Assembly #{metric}")
  end

  def sub_surface_get_window_property(sub_surface)
    sql_file = sub_surface.model.sqlFile
    if !sql_file.is_initialized
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SubSurface', 'Model has no sql file containing results, cannot lookup data.')
      return nil
    end

    window_type = sub_surface.subSurfaceType
    unless ['window', 'skylight'].any? { |x| window_type.downcase.include?(x) }
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SubSurface', 'SubSurface is a not a window or skylight.')
      return nil
    end

    sub_surface_name = sub_surface.name.to_s

    window_shgc = get_exterior_fenestration_value_with_fallback(sub_surface, 'SHGC')
    window_u_value = get_exterior_fenestration_value_with_fallback(sub_surface, 'U-Factor')
    window_area = get_exterior_fenestration_value(sub_surface, 'Area of Multiplied Openings')

    surface_type = nil
    surface_ = sub_surface.surface
    surface_type = surface_.get.surfaceType if surface_.is_initialized

    {
      'name' => sub_surface_name,
      'window_type' => window_type,
      'surface_type' => surface_type,
      'area_m2' => window_area,
      'shgc' => window_shgc,
      'u_value' => window_u_value,
    }
  end
end
