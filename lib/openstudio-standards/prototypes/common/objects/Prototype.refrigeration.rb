class Standard
  # @!group refrigeration

  # Adds a refrigerated case to the model.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone where the case is located,
  #   and which will be impacted by the case's thermal load.
  # @param case_type [String] the case type/name. For valid choices
  #   refer to the ""Refrigerated Cases" tab on the OpenStudio_Standards spreadsheet.
  #   This parameter is used also by the "Refrigeration System Lineup" tab.
  # @param size_category [String] size category of the building area. Valid choices are:
  #   "<35k ft2", "35k - 50k ft2", ">50k ft2"
  # @return [OpenStudio::Model::RefrigerationCase] the refrigeration case
  def model_add_refrigeration_case(model, thermal_zone, case_type, size_category)
    # Get the case properties
    #

    search_criteria = {
      'template' => template,
      'case_type' => case_type,
      'size_category' => size_category
    }

    props = model_find_object(standards_data['refrigerated_cases'], search_criteria)
    if props.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Could not find refrigerated case properties for: #{search_criteria}.")
      return nil
    end

    # Capacity, defrost, anti-sweat
    case_length = OpenStudio.convert(props['case_length'], 'ft', 'm').get
    case_temp = OpenStudio.convert(props['case_temp'], 'F', 'C').get
    cooling_capacity_per_length = OpenStudio.convert(props['cooling_capacity_per_length'], 'Btu/hr*ft', 'W/m').get
    evap_fan_power_per_length = OpenStudio.convert(props['evap_fan_power_per_length'], 'W/ft', 'W/m').get
    if props['evap_temp']
      evap_temp_c = OpenStudio.convert(props['evap_temp'], 'F', 'C').get
    end
    lighting_w_per_m = OpenStudio.convert(props['lighting_per_ft'], 'W/ft', 'W/m').get
    if props['lighting_schedule']
      case_lighting_schedule = model_add_schedule(model, props['lighting_schedule'])
    else
      case_lighting_schedule = model.alwaysOnDiscreteSchedule
    end
    fraction_of_lighting_energy_to_case = props['fraction_of_lighting_energy_to_case']
    if props['latent_case_credit_curve_name']
      latent_case_credit_curve = model_add_curve(model, props['latent_case_credit_curve_name'])
    end
    defrost_power_per_length = OpenStudio.convert(props['defrost_power_per_length'], 'W/ft', 'W/m').get
    defrost_type = props['defrost_type']
    if props['defrost_correction_type']
      defrost_correction_type = props['defrost_correction_type']
    end
    if props['defrost_correction_curve_name']
      defrost_correction_curve_name = model_add_curve(model, props['defrost_correction_curve_name'])
    end
    if props['anti_sweat_power']
      anti_sweat_power = OpenStudio.convert(props['anti_sweat_power'], 'W/ft', 'W/m').get
    end
    if props['minimum_anti_sweat_heater_power_per_unit_length']
      minimum_anti_sweat_heater_power_per_unit_length = OpenStudio.convert(props['minimum_anti_sweat_heater_power_per_unit_length'], 'W/ft', 'W/m').get
    end
    if props['anti_sweat_heater_control']
      if props['anti_sweat_heater_control'] == 'RelativeHumidity'
        anti_sweat_heater_control = 'Linear'
      else
        anti_sweat_heater_control = props['anti_sweat_heater_control']
      end
    end
    if props['under_case_hvac_return_air_fraction']
      under_case_hvac_return_air_fraction = props['under_case_hvac_return_air_fraction']
    end
    if props['fractionofantisweatheaterenergytocase']
      fractionofantisweatheaterenergytocase = props['fractionofantisweatheaterenergytocase']
    end

    # Case
    ref_case = OpenStudio::Model::RefrigerationCase.new(model, model.alwaysOnDiscreteSchedule)
    ref_case.setName(case_type)
    ref_case.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    ref_case.setThermalZone(thermal_zone)
    ref_case.setRatedAmbientTemperature(OpenStudio.convert(75, 'F', 'C').get)
    ref_case.setRatedLatentHeatRatio(props['latent_heat_ratio']) if props['latent_heat_ratio']
    ref_case.setRatedRuntimeFraction(props['rated_runtime_fraction']) if props['rated_runtime_fraction']
    ref_case.setCaseLength(case_length)
    ref_case.setCaseOperatingTemperature(case_temp)
    ref_case.setRatedTotalCoolingCapacityperUnitLength(cooling_capacity_per_length)
    cooling_capacity_w = ref_case.caseLength * ref_case.ratedTotalCoolingCapacityperUnitLength
    cooling_capacity_btu_per_hr = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get
    ref_case.setStandardCaseFanPowerperUnitLength(evap_fan_power_per_length)
    ref_case.setOperatingCaseFanPowerperUnitLength(evap_fan_power_per_length)
    if props['evap_temp']
      ref_case.setDesignEvaporatorTemperatureorBrineInletTemperature(evap_temp_c)
    end
    ref_case.setStandardCaseLightingPowerperUnitLength(lighting_w_per_m)
    ref_case.setInstalledCaseLightingPowerperUnitLength(lighting_w_per_m)
    ref_case.setCaseLightingSchedule(case_lighting_schedule)

    if props['latent_case_credit_curve_name']
      ref_case.setLatentCaseCreditCurve(latent_case_credit_curve)
    end
    ref_case.setCaseDefrostPowerperUnitLength(defrost_power_per_length)
    if props['defrost_type']
      ref_case.setCaseDefrostType(defrost_type)
    end
    ref_case.setDefrostEnergyCorrectionCurveType(defrost_correction_type)
    if props['defrost_correction_curve_name']
      ref_case.setDefrostEnergyCorrectionCurve(defrost_correction_curve_name)
    end
    if props['anti_sweat_power']
      ref_case.setCaseAntiSweatHeaterPowerperUnitLength(anti_sweat_power)
    end
    ref_case.setFractionofAntiSweatHeaterEnergytoCase(fractionofantisweatheaterenergytocase)
    if props['fraction_of_lighting_energy_to_case']
      ref_case.setFractionofLightingEnergytoCase(fraction_of_lighting_energy_to_case)
    end
    if props['minimum_anti_sweat_heater_power_per_unit_length']
      ref_case.setMinimumAntiSweatHeaterPowerperUnitLength(minimum_anti_sweat_heater_power_per_unit_length)
    end
    if props['anti_sweat_heater_control']
      ref_case.setAntiSweatHeaterControlType(anti_sweat_heater_control)
    end
    ref_case.setHumidityatZeroAntiSweatHeaterEnergy(0)
    if props['under_case_hvac_return_air_fraction']
      ref_case.setUnderCaseHVACReturnAirFraction(under_case_hvac_return_air_fraction)
    else
      ref_case.setUnderCaseHVACReturnAirFraction(0)
    end
    if props['restocking_schedule']
      if props['restocking_schedule'].downcase == 'always off'
        # restocking_sch = model.alwaysOffDiscreteSchedule
        ref_case.resetRefrigeratedCaseRestockingSchedule
      else
        restocking_sch = model_add_schedule(model, props['restocking_schedule'])
        ref_case.setRefrigeratedCaseRestockingSchedule(restocking_sch)
      end
    else
      ref_case.resetRefrigeratedCaseRestockingSchedule
    end

    if props['case_category']
      ref_case_addprops = ref_case.additionalProperties
      ref_case_addprops.setFeature('case_category', props['case_category'])
    end

    length_ft = OpenStudio.convert(case_length, 'm', 'ft').get
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Added #{length_ft.round} ft display case called #{case_type} with a cooling capacity of #{cooling_capacity_btu_per_hr.round} Btu/hr to #{thermal_zone.name}.")

    return ref_case
  end

  # Adds a refrigerated walkin unit to the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone where the walkin is located,
  #   and which will be impacted by the walkin's thermal load.
  # @param size_category [String] size category of the building area. Valid choices are:
  #   "<35k ft2", "35k - 50k ft2", ">50k ft2"
  # @param walkin_type [String] the walkin type/name. For valid choices,
  #   refer to the "Refrigerated Walkins" tab on the OpenStudio_Standards spreadsheet.
  #   This parameter is used also by the "Refrigeration System Lineup" tab.
  # @return [OpenStudio::Model::RefrigerationWalkIn] the walk in refrigerator
  def model_add_refrigeration_walkin(model, thermal_zone, size_category, walkin_type)
    # Get the walkin properties
    search_criteria = {
      'template' => template,
      'size_category' => size_category,
      'walkin_type' => walkin_type
    }

    props = model_find_object(standards_data['refrigeration_walkins'], search_criteria)
    if props.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Prototype.refrigeration', "Could not find walkin properties for: #{search_criteria}.")
      return nil
    end

    # Capacity, defrost, lighting
    walkin_type = props['walkin_type']
    if props['rated_cooling_capacity']
      rated_cooling_capacity = OpenStudio.convert(props['rated_cooling_capacity'], 'Btu/h', 'W').get
    end
    if props['cooling_capacity_c0']
      cooling_capacity_c0 = OpenStudio.convert(OpenStudio.convert(props['cooling_capacity_c0'], 'Btu/h', 'W').get, 'W/ft', 'W/m').get
    end
    if props['cooling_capacity_c1']
      cooling_capacity_c1 = OpenStudio.convert(OpenStudio.convert(props['cooling_capacity_c1'], 'Btu/h', 'W').get, 'W/ft', 'W/m').get
    end
    if props['cooling_capacity_c2']
      cooling_capacity_c2 = OpenStudio.convert(OpenStudio.convert(props['cooling_capacity_c2'], 'Btu/h', 'W').get, 'W/ft', 'W/m').get
    end
    if props['fan_power_mult']
      fan_power_mult = props['fan_power_mult']
    end
    if props['lighting_power_mult']
      lighting_power_mult = props['lighting_power_mult']
    end
    if props['reachin_door_area_mult']
      reachin_door_area_mult = OpenStudio.convert(props['reachin_door_area_mult'], 'ft^2', 'm^2').get
    end
    operating_temp = OpenStudio.convert(props['operating_temp'], 'F', 'C').get
    if props['source_temp']
      source_temp = OpenStudio.convert(props['source_temp'], 'F', 'C').get
    end
    if props['defrost_control_type']
      defrost_control_type = props['defrost_control_type']
    end
    defrost_type = props['defrost_type']
    defrost_power_mult = props['defrost_power_mult']
    defrost_power = props['defrost_power']
    ratedtotalheatingpower = props['ratedtotalheatingpower']
    ratedcirculationfanpower = props['ratedcirculationfanpower']
    fan_power = props['fan_power']
    lighting_power = props['lighting_power']
    # lighting_power_mult = props_ref_system['lighting_power_mult']
    if props['insulated_floor_u']
      insulated_floor_u = OpenStudio.convert(props['insulated_floor_u'], 'Btu/ft^2*h*R', 'W/m^2*K').get
    end
    if props['insulated_surface_u']
      insulated_surface_u = OpenStudio.convert(props['insulated_surface_u'], 'Btu/ft^2*h*R', 'W/m^2*K').get
    end
    if props['stocking_door_u']
      insulated_door_u = OpenStudio.convert(props['stocking_door_u'], 'Btu/ft^2*h*R', 'W/m^2*K').get
    end
    if props['glass_reachin_door_u_value']
      glass_reachin_door_u_value = OpenStudio.convert(props['glass_reachin_door_u_value'], 'Btu/ft^2*h*R', 'W/m^2*K').get
    end
    if props['reachin_door_area']
      reachin_door_area = OpenStudio.convert(props['reachin_door_area'], 'ft^2', 'm^2').get
    else
      reachin_door_area = 0.0
    end
    if props['total_insulated_surface_area']
      total_insulated_surface_area = OpenStudio.convert(props['total_insulated_surface_area'], 'ft^2', 'm^2').get
    end
    if props['height_of_glass_reachin_doors']
      height_of_glass_reachin_doors = OpenStudio.convert(props['height_of_glass_reachin_doors'], 'ft', 'm').get
    end
    if props['area_of_stocking_doors']
      area_of_stocking_doors = OpenStudio.convert(props['area_of_stocking_doors'], 'ft^2', 'm^2').get
    end
    if props['floor_surface_area']
      floor_surface_area = OpenStudio.convert(props['floor_surface_area'], 'ft^2', 'm^2').get
    end
    if props['height_of_stocking_doors']
      height_of_stocking_doors = OpenStudio.convert(props['height_of_stocking_doors'], 'ft', 'm').get
    end
    lightingschedule = props['lighting_schedule']
    temperatureterminationdefrostfractiontoice = props['temperatureterminationdefrostfractiontoice']

    # Calculated properties
    if rated_cooling_capacity.nil?
      rated_cooling_capacity = (cooling_capacity_c2 * (floor_surface_area ^ 2)) + (cooling_capacity_c1 * floor_surface_area) + cooling_capacity_c0
    end
    if defrost_power.nil?
      defrost_power = defrost_power_mult * rated_cooling_capacity
    end
    if total_insulated_surface_area.nil?
      total_insulated_surface_area = (1.7226 * floor_surface_area) + 28.653
    end
    if fan_power.nil?
      fan_power = fan_power_mult * rated_cooling_capacity
    end
    if lighting_power.nil?
      lighting_power = lighting_power_mult * floor_surface_area
    end

    # Check validity of thermal zone
    if OpenstudioStandards::ThermalZone.thermal_zone_plenum?(thermal_zone)
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Prototype.refrigeration', "Thermal zone #{thermal_zone.name} is a plenum; cannot add walkins to a plenum.")
      return nil
    end

    # Walk-In
    ref_walkin = OpenStudio::Model::RefrigerationWalkIn.new(model, model.alwaysOnDiscreteSchedule)
    ref_walkin.setName(walkin_type.to_s)
    ref_walkin.setZoneBoundaryThermalZone(thermal_zone)
    ref_walkin.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    ref_walkin.setRatedCoilCoolingCapacity(rated_cooling_capacity)
    rated_cooling_capacity_btu_per_hr = OpenStudio.convert(rated_cooling_capacity, 'W', 'Btu/hr').get
    ref_walkin.setOperatingTemperature(operating_temp)
    if props['source_temp']
      ref_walkin.setRatedCoolingSourceTemperature(source_temp)
    end
    if props['defrost_control_type']
      ref_walkin.setDefrostControlType(defrost_control_type)
    end
    ref_walkin.setDefrostType(defrost_type)
    ref_walkin.setDefrostPower(defrost_power)
    if props['ratedtotalheatingpower']
      ref_walkin.setRatedTotalHeatingPower(ratedtotalheatingpower)
    end
    if props['ratedcirculationfanpower']
      ref_walkin.setRatedCirculationFanPower(ratedcirculationfanpower)
    end
    ref_walkin.setRatedCoolingCoilFanPower(fan_power)
    ref_walkin.setRatedTotalLightingPower(lighting_power)
    if props['insulated_floor_u']
      ref_walkin.setInsulatedFloorUValue(insulated_floor_u)
    end
    if props['insulated_surface_u']
      ref_walkin.setZoneBoundaryInsulatedSurfaceUValueFacingZone(insulated_surface_u)
    end
    if props['stocking_door_u']
      ref_walkin.setZoneBoundaryStockingDoorUValueFacingZone(insulated_door_u)
    end
    if props['reachin_door_area']
      ref_walkin.setZoneBoundaryAreaofGlassReachInDoorsFacingZone(reachin_door_area)
    end
    if props['total_insulated_surface_area']
      ref_walkin.setZoneBoundaryTotalInsulatedSurfaceAreaFacingZone(total_insulated_surface_area)
    end
    if props['area_of_stocking_doors']
      ref_walkin.setZoneBoundaryAreaofStockingDoorsFacingZone(area_of_stocking_doors)
    end
    if props['floor_surface_area']
      ref_walkin.setInsulatedFloorSurfaceArea(floor_surface_area)
    end
    if props['height_of_glass_reachin_doors']
      ref_walkin.setZoneBoundaryHeightofGlassReachInDoorsFacingZone(height_of_glass_reachin_doors)
    end
    if props['height_of_stocking_doors']
      ref_walkin.setZoneBoundaryHeightofStockingDoorsFacingZone(height_of_stocking_doors)
    end
    if props['glass_reachin_door_u_value']
      ref_walkin.setZoneBoundaryGlassReachInDoorUValueFacingZone(glass_reachin_door_u_value)
    end
    if props['temperatureterminationdefrostfractiontoice']
      ref_walkin.setTemperatureTerminationDefrostFractiontoIce(temperatureterminationdefrostfractiontoice)
    end

    if props['restocking_schedule']
      if props['restocking_schedule'].downcase == 'always off'
        # restocking_sch = model.alwaysOffDiscreteSchedule
        ref_walkin.resetRestockingSchedule
      else
        restocking_sch = model_add_schedule(model, props['restocking_schedule'])
        ref_walkin.setRestockingSchedule(restocking_sch)
      end
    else
      ref_walkin.resetRestockingSchedule
    end

    ref_walkin.setLightingSchedule(model_add_schedule(model, lightingschedule))
    ref_walkin.setZoneBoundaryStockingDoorOpeningScheduleFacingZone(model_add_schedule(model, 'door_wi_sched'))

    ref_walkin_addprops = ref_walkin.additionalProperties
    ref_walkin_addprops.setFeature('motor_category', props['motor_category'])

    # Add doorway protection
    if props['doorway_protection_type']
      ref_walkin.zoneBoundaries.each do |zb|
        zb.setStockingDoorOpeningProtectionTypeFacingZone(props['doorway_protection_type'])
      end
    end

    insulated_floor_area_ft2 = OpenStudio.convert(floor_surface_area, 'm^2', 'ft^2').get
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Added #{insulated_floor_area_ft2.round} ft2 walkin called #{walkin_type} with a capacity of #{rated_cooling_capacity_btu_per_hr.round} Btu/hr to #{thermal_zone.name}.")

    return ref_walkin
  end

  # Adds a refrigeration compressor to the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [OpenStudio::Model::RefrigerationCompressor] the refrigeration compressor
  def model_add_refrigeration_compressor(model, compressor_name)
    # Get the compressor properties
    search_criteria = {
      'template' => template,
      'compressor_name' => compressor_name
    }

    props = model_find_object(standards_data['refrigeration_compressors'], search_criteria)
    if props.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Could not find refrigeration compressor properties for: #{search_criteria}.")
      return nil
    end

    # Performance curves
    pwr_curve_name = props['power_curve']
    cap_curve_name = props['capacity_curve']

    # Make the compressor
    compressor = OpenStudio::Model::RefrigerationCompressor.new(model)
    compressor.setRefrigerationCompressorPowerCurve(model_add_curve(model, pwr_curve_name))
    compressor.setRefrigerationCompressorCapacityCurve(model_add_curve(model, cap_curve_name))

    return compressor
  end

  # Adds a full commercial refrigeration rack to the model, as would be found in a supermarket
  # @todo Move refrigeration compressors to spreadsheet
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param compressor_type [String] the system temperature range
  #   valid choices are Low Temp, Med Temp
  # @param system_name [String] the name of the refrigeration system
  # @param cases [Array<Hash>] an array of cases with keys: case_type and space_names
  # @param walkins [Array<Hashs>] an array of walkins with keys:
  #   walkin_type, space_names, and number_of_walkins
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone where the refrigeration piping is located
  # @return [Boolean] returns true if successful, false if not
  def model_add_refrigeration_system(model,
                                     compressor_type,
                                     system_name,
                                     cases,
                                     walkins,
                                     thermal_zone)

    # Refrigeration system
    ref_sys = OpenStudio::Model::RefrigerationSystem.new(model)
    ref_sys.setName(system_name.to_s)
    ref_sys.setSuctionPipingZone(thermal_zone)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model',
                       "Adding #{compressor_type} refrigeration system called #{system_name} with #{cases.size} cases and #{walkins.size} walkins.")

    # Compressors (20 for each system)
    for i in 0...20
      compressor = model_add_refrigeration_compressor(model, compressor_type)
      ref_sys.addCompressor(compressor)
    end

    size_category = 'Any'
    # Cases
    cooling_cap = 0
    i = 0
    cases.each do |case_|
      zone = model_get_zones_from_spaces_on_system(model, case_)[0]
      ref_case = model_add_refrigeration_case(model, zone, case_['case_type'], size_category)
      return false if ref_case.nil?

      ########################################
      # Defrost schedule
      defrost_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      defrost_sch.setName("#{ref_case.name} Defrost")
      defrost_sch.defaultDaySchedule.setName("#{ref_case.name} Defrost Default")
      defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 0, 0), 0)
      defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 59, 0), 1)
      defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
      # Dripdown schedule
      dripdown_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      dripdown_sch.setName("#{ref_case.name} Defrost")
      dripdown_sch.defaultDaySchedule.setName("#{ref_case.name} Defrost Default")
      dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 0, 0), 0)
      dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 59, 0), 1)
      dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
      # Case Credit Schedule
      case_credit_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      case_credit_sch.setName("#{ref_case.name} Case Credit")
      case_credit_sch.defaultDaySchedule.setName("#{ref_case.name} Case Credit Default")
      case_credit_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 7, 0, 0), 0.2)
      case_credit_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 21, 0, 0), 0.4)
      case_credit_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.2)
      ref_case.setCaseDefrostSchedule(defrost_sch)
      ref_case.setCaseDefrostDripDownSchedule(dripdown_sch)
      ref_case.setCaseCreditFractionSchedule(case_credit_sch)
      ########################################
      ref_sys.addCase(ref_case)
      i += 1
    end

    # Walkins
    walkins.each do |walkin|
      for i in 0...walkin['number_of_walkins']

        zone = model_get_zones_from_spaces_on_system(model, walkin)[0]
        ref_walkin = model_add_refrigeration_walkin(model, zone, size_category, walkin['walkin_type'])
        return false if ref_walkin.nil?

        ########################################
        # Defrost schedule
        defrost_sch = OpenStudio::Model::ScheduleRuleset.new(model)
        defrost_sch.setName("#{ref_walkin.name} Defrost")
        defrost_sch.defaultDaySchedule.setName("#{ref_walkin.name} Defrost Default")
        defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 0, 0), 0)
        defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 59, 0), 1)
        defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i + 10, 0, 0), 0)
        defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i + 10, 59, 0), 1)
        defrost_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        # Dripdown schedule
        dripdown_sch = OpenStudio::Model::ScheduleRuleset.new(model)
        dripdown_sch.setName("#{ref_walkin.name} Defrost")
        dripdown_sch.defaultDaySchedule.setName("#{ref_walkin.name} Defrost Default")
        dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 0, 0), 0)
        dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i, 59, 0), 1)
        dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i + 10, 0, 0), 0)
        dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, i + 10, 59, 0), 1)
        dripdown_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        ref_walkin.setDefrostSchedule(defrost_sch)
        ref_walkin.setDefrostDripDownSchedule(dripdown_sch)
        ref_sys.addWalkin(ref_walkin)
        ########################################
        cooling_cap += ref_walkin.ratedCoilCoolingCapacity # calculate total cooling capacity of the cases + walkins
      end
    end

    # Condenser capacity
    # The heat rejection rate from the condenser is equal to the rated capacity of all the display cases and walk-ins connected to the compressor rack
    # plus the power rating of the compressors making up the compressor rack.
    # Assuming a COP of 1.3 for low-temperature compressor racks and a COP of 2.0 for medium-temperature compressor racks,
    # the required condenser capacity is approximated as follows:
    # Note the factor 1.2 has been included to over-estimate the condenser size.  The total capacity of the display cases can be calculated
    # from their rated cooling capacity times the length of the cases.  The capacity of each of the walk-ins is specified directly.
    condensor_cap = if compressor_type == 'Low Temp'
                      1.2 * cooling_cap * (1 + (1 / 1.3))
                    else
                      1.2 * cooling_cap * (1 + (1 / 2.0))
                    end
    condenser_coefficient_2 = condensor_cap / 5.6
    condenser_curve = OpenStudio::Model::CurveLinear.new(model)
    condenser_curve.setCoefficient1Constant(0)
    condenser_curve.setCoefficient2x(condenser_coefficient_2)
    condenser_curve.setMinimumValueofx(1.4)
    condenser_curve.setMaximumValueofx(33.3)

    # Condenser fan power
    # The condenser fan power can be estimated from the heat rejection capacity of the condenser as follows:
    condenser_fan_pwr = (0.0441 * condensor_cap) + 695

    # Condenser
    condenser = OpenStudio::Model::RefrigerationCondenserAirCooled.new(model)
    condenser.setRatedFanPower(condenser_fan_pwr)
    condenser.setRatedEffectiveTotalHeatRejectionRateCurve(condenser_curve)
    condenser.setCondenserFanSpeedControlType('Fixed')
    condenser.setMinimumFanAirFlowRatio(0.1)

    ref_sys.setRefrigerationCondenser(condenser)

    return true
  end
end
