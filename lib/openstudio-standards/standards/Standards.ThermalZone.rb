class Standard
  # @!group ThermalZone

  # for 2013 and prior, baseline fuel = proposed fuel
  # @param thermal_zone
  # @return [String with applicable DistrictHeating and/or DistrictCooling
  def thermal_zone_get_zone_fuels_for_occ_and_fuel_type(thermal_zone)
    zone_fuels = thermal_zone_fossil_or_electric_type(thermal_zone, '')
    return zone_fuels
  end

  # Determine if the thermal zone's fuel type category.
  # Options are:
  #   fossil, electric, unconditioned
  # If a customization is passed, additional categories may be returned.
  # If 'Xcel Energy CO EDA', the type fossilandelectric is added.
  # DistrictHeating is considered a fossil fuel since it is typically created by natural gas boilers.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @param custom [String] string for custom case statement
  # @return [String] the fuel type category
  def thermal_zone_fossil_or_electric_type(thermal_zone, custom)
    # error if HVACComponent heating fuels method is not available
    if thermal_zone.model.version < OpenStudio::VersionString.new('3.6.0')
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.ThermalZone', 'Required HVACComponent methods .heatingFuelTypes and .coolingFuelTypes are not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
    end

    # Cooling fuels, for determining unconditioned zones
    htg_fuels = thermal_zone.heatingFuelTypes.map(&:valueName)
    clg_fuels = thermal_zone.coolingFuelTypes.map(&:valueName)
    fossil = OpenstudioStandards::ThermalZone.thermal_zone_fossil_heat?(thermal_zone)
    district = OpenstudioStandards::ThermalZone.thermal_zone_district_heat?(thermal_zone)
    electric = OpenstudioStandards::ThermalZone.thermal_zone_electric_heat?(thermal_zone)

    # Categorize
    fuel_type = nil
    if fossil || district
      # If uses any fossil, counts as fossil even if electric is present too
      fuel_type = 'fossil'
    elsif electric
      fuel_type = 'electric'
    elsif htg_fuels.empty? && clg_fuels.empty?
      fuel_type = 'unconditioned'
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}, could not determine fuel type, assuming fossil.  Heating fuels = #{htg_fuels.join(', ')}; cooling fuels = #{clg_fuels.join(', ')}.")
      fuel_type = 'fossil'
    end

    # Customization for Xcel.
    # Likely useful for other utility
    # programs where fuel switching is important.
    # This is primarily for systems where Gas is
    # used at the central AHU and electric is
    # used at the terminals/zones.  Examples
    # include zone VRF/PTHP with gas-heated DOAS,
    # and gas VAV with electric reheat
    case custom
    when 'Xcel Energy CO EDA'
      if fossil && electric
        fuel_type = 'fossilandelectric'
      end
    end

    return fuel_type
  end

  # Infers the baseline system type based on the equipment serving the zone and their heating/cooling fuels.
  # Only does a high-level inference; does not look for the presence/absence of required controls, etc.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [String] system type. Possible system types are:
  #   PTHP, PTAC, PSZ_AC, PSZ_HP, PVAV_Reheat, PVAV_PFP_Boxes,
  #   VAV_Reheat, VAV_PFP_Boxes, Gas_Furnace, Electric_Furnace
  def thermal_zone_infer_system_type(thermal_zone)
    # Determine the characteristics
    # of the equipment serving the zone
    has_air_loop = false
    air_loop_num_zones = 0
    air_loop_is_vav = false
    air_loop_has_chw = false
    has_ptac = false
    has_pthp = false
    has_unitheater = false
    thermal_zone.equipment.each do |equip|
      # Skip HVAC components
      next unless equip.to_HVACComponent.is_initialized

      equip = equip.to_HVACComponent.get
      if equip.airLoopHVAC.is_initialized
        has_air_loop = true
        air_loop = equip.airLoopHVAC.get
        air_loop_num_zones = air_loop.thermalZones.size
        air_loop.supplyComponents.each do |sc|
          if sc.to_FanVariableVolume.is_initialized
            air_loop_is_vav = true
          elsif sc.to_CoilCoolingWater.is_initialized
            air_loop_has_chw = true
          end
        end
      elsif equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
        has_ptac = true
      elsif equip.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
        has_pthp = true
      elsif equip.to_ZoneHVACUnitHeater.is_initialized
        has_unitheater = true
      end
    end

    # error if HVACComponent heating fuels method is not available
    if thermal_zone.model.version < OpenStudio::VersionString.new('3.6.0')
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.ThermalZone', 'Required HVACComponent methods .heatingFuelTypes and .coolingFuelTypes are not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
    end

    # Get the zone heating and cooling fuels
    htg_fuels = thermal_zone.heatingFuelTypes.map(&:valueName)
    clg_fuels = thermal_zone.coolingFuelTypes.map(&:valueName)
    is_fossil = OpenstudioStandards::ThermalZone.thermal_zone_fossil_heat?(thermal_zone) || OpenstudioStandards::ThermalZone.thermal_zone_district_heat?(thermal_zone)

    # Infer the HVAC type
    sys_type = 'Unknown'

    # Single zone
    if air_loop_num_zones < 2
      # Gas
      if is_fossil
        # Air Loop
        if has_air_loop
          # Gas_Furnace (as air loop)
          sys_type = if clg_fuels.empty?
                       'Gas_Furnace'
                     # PSZ_AC
                     else
                       'PSZ_AC'
                     end
        # Zone Equipment
        else
          # Gas_Furnace (as unit heater)
          if has_unitheater
            sys_type = 'Gas_Furnace'
          end
          # PTAC
          if has_ptac
            sys_type = 'PTAC'
          end
        end
      # Electric
      else
        # Air Loop
        if has_air_loop
          # Electric_Furnace (as air loop)
          sys_type = if clg_fuels.empty?
                       'Electric_Furnace'
                     # PSZ_HP
                     else
                       'PSZ_HP'
                     end
        # Zone Equipment
        else
          # Electric_Furnace (as unit heater)
          if has_unitheater
            sys_type = 'Electric_Furnace'
          end
          # PTHP
          if has_pthp
            sys_type = 'PTHP'
          end
        end
      end
    # Multi-zone
    else
      # Gas
      if is_fossil
        # VAV_Reheat
        if air_loop_has_chw && air_loop_is_vav
          sys_type = 'VAV_Reheat'
        end
        # PVAV_Reheat
        if !air_loop_has_chw && air_loop_is_vav
          sys_type = 'PVAV_Reheat'
        end
      # Electric
      else
        # VAV_PFP_Boxes
        if air_loop_has_chw && air_loop_is_vav
          sys_type = 'VAV_PFP_Boxes'
        end
        # PVAV_PFP_Boxes
        if !air_loop_has_chw && air_loop_is_vav
          sys_type = 'PVAV_PFP_Boxes'
        end
      end
    end

    # Report out the characteristics for debugging if
    # the system type cannot be inferred.
    if sys_type == 'Unknown'
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}, the baseline system type could not be inferred.")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "***#{thermal_zone.name}***")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "system type = #{sys_type}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "has_air_loop = #{has_air_loop}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "air_loop_num_zones = #{air_loop_num_zones}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "air_loop_is_vav = #{air_loop_is_vav}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "air_loop_has_chw = #{air_loop_has_chw}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "has_ptac = #{has_ptac}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "has_pthp = #{has_pthp}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "has_unitheater = #{has_unitheater}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "htg_fuels = #{htg_fuels}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "clg_fuels = #{clg_fuels}")
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "is_fossil = #{is_fossil}")
    end

    return sys_type
  end

  # Determines whether the zone is conditioned per 90.1, which is based on heating and cooling loads.
  # Logic to detect indirectly-conditioned spaces cannot be implemented
  # as part of this measure as it would need to call itself.
  # It is implemented as part of space_conditioning_category().
  # @todo Add addendum db rules to 90.1-2019 for 90.1-2022 (use stable baseline value for zones designated as semiheated using proposed sizing run)
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] NonResConditioned, ResConditioned, Semiheated, Unconditioned
  def thermal_zone_conditioning_category(thermal_zone, climate_zone)
    # error if zone design load methods are not available
    if thermal_zone.model.version < OpenStudio::VersionString.new('3.6.0')
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.ThermalZone', 'Required ThermalZone methods .autosizedHeatingDesignLoad and .autosizedCoolingDesignLoad are not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
    end

    # Get the heating load
    htg_load_btu_per_ft2 = 0.0
    htg_load_w = thermal_zone.autosizedHeatingDesignLoad
    if htg_load_w.is_initialized
      htg_load_w_per_m2 = thermal_zone.autosizedHeatingDesignLoad.get / thermal_zone.floorArea
      htg_load_btu_per_ft2 = OpenStudio.convert(htg_load_w_per_m2, 'W/m^2', 'Btu/hr*ft^2').get
    end

    # Get the cooling load
    clg_load_btu_per_ft2 = 0.0
    clg_load_w = thermal_zone.autosizedCoolingDesignLoad
    if clg_load_w.is_initialized
      clg_load_w_per_m2 = thermal_zone.autosizedCoolingDesignLoad.get / thermal_zone.floorArea
      clg_load_btu_per_ft2 = OpenStudio.convert(clg_load_w_per_m2, 'W/m^2', 'Btu/hr*ft^2').get
    end

    # Determine the heating limit based on climate zone
    # From Table 3.1 Heated Space Criteria
    htg_lim_btu_per_ft2 = 0.0
    climate_zone_code = climate_zone.split('-')[-1]
    if ['0A', '0B', '1A', '1B', '2A', '2B'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 5
      stable_htg_lim_btu_per_ft2 = 5
    elsif ['3A', '3B'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 9
      stable_htg_lim_btu_per_ft2 = 10
    elsif climate_zone_code == '3C'
      htg_lim_btu_per_ft2 = 7
      stable_htg_lim_btu_per_ft2 = 10
    elsif ['4A', '4B'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 10
      stable_htg_lim_btu_per_ft2 = 15
    elsif climate_zone_code == '4C'
      htg_lim_btu_per_ft2 = 8
      stable_htg_lim_btu_per_ft2 = 15
    elsif ['5A', '5B', '5C'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 12
      stable_htg_lim_btu_per_ft2 = 15
    elsif ['6A', '6B'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 14
      stable_htg_lim_btu_per_ft2 = 20
    elsif ['7A', '7B'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 16
      stable_htg_lim_btu_per_ft2 = 20
    elsif ['8A', '8B'].include? climate_zone_code
      htg_lim_btu_per_ft2 = 19
      stable_htg_lim_btu_per_ft2 = 25
    end

    # for older code versions use stable baseline value as primary target
    if ['90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013'].include? template
      htg_lim_btu_per_ft2 = stable_htg_lim_btu_per_ft2
    end

    # Cooling limit is climate-independent
    case template
    when '90.1-2016', '90.1-PRM-2019'
      clg_lim_btu_per_ft2 = 3.4
    else
      clg_lim_btu_per_ft2 = 5
    end

    # Semiheated limit is climate-independent
    semihtd_lim_btu_per_ft2 = 3.4

    # Determine if residential
    res = false
    if OpenstudioStandards::ThermalZone.thermal_zone_residential?(thermal_zone)
      res = true
    end

    cond_cat = 'Unconditioned'
    if htg_load_btu_per_ft2 > htg_lim_btu_per_ft2
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "Zone #{thermal_zone.name} is conditioned because heating load of #{htg_load_btu_per_ft2.round} Btu/hr*ft^2 exceeds minimum of #{htg_lim_btu_per_ft2.round} Btu/hr*ft^2.")
      cond_cat = if res
                   'ResConditioned'
                 else
                   'NonResConditioned'
                 end
    elsif clg_load_btu_per_ft2 > clg_lim_btu_per_ft2
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "Zone #{thermal_zone.name} is conditioned because cooling load of #{clg_load_btu_per_ft2.round} Btu/hr*ft^2 exceeds minimum of #{clg_lim_btu_per_ft2.round} Btu/hr*ft^2.")
      cond_cat = if res
                   'ResConditioned'
                 else
                   'NonResConditioned'
                 end
    elsif htg_load_btu_per_ft2 > semihtd_lim_btu_per_ft2
      cond_cat = 'Semiheated'
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "Zone #{thermal_zone.name} is semiheated because heating load of #{htg_load_btu_per_ft2.round} Btu/hr*ft^2 exceeds minimum of #{semihtd_lim_btu_per_ft2.round} Btu/hr*ft^2.")
    end

    return cond_cat
  end

  # Calculate the heating supply temperature based on the# specified delta-T.
  # Delta-T is calculated based on the highest value found in the heating setpoint schedule.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [Double] the design heating supply temperature, in degrees Celsius
  # @todo Exception: 17F delta-T for labs
  def thermal_zone_prm_baseline_heating_design_supply_temperature(thermal_zone)
    unit_heater_sup_temp = thermal_zone_prm_unitheater_design_supply_temperature(thermal_zone)
    unless unit_heater_sup_temp.nil?
      return unit_heater_sup_temp
    end

    setpoint_c = nil

    # Setpoint schedule
    tstat = thermal_zone.thermostatSetpointDualSetpoint
    if tstat.is_initialized
      tstat = tstat.get
      setpoint_sch = tstat.heatingSetpointTemperatureSchedule
      if setpoint_sch.is_initialized
        setpoint_sch = setpoint_sch.get
        if setpoint_sch.to_ScheduleRuleset.is_initialized
          setpoint_sch = setpoint_sch.to_ScheduleRuleset.get
          setpoint_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(setpoint_sch)['max']
        elsif setpoint_sch.to_ScheduleConstant.is_initialized
          setpoint_sch = setpoint_sch.to_ScheduleConstant.get
          setpoint_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(setpoint_sch)['max']
        elsif setpoint_sch.to_ScheduleCompact.is_initialized
          setpoint_sch = setpoint_sch.to_ScheduleCompact.get
          setpoint_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(setpoint_sch)['max']
        end
      end
    end

    # If the heating setpoint could not be determined
    # return the current design heating temperature
    if setpoint_c.nil?
      setpoint_c = thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperature
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}: could not determine max heating setpoint.  Design heating SAT will be #{OpenStudio.convert(setpoint_c, 'C', 'F').get.round} F from proposed model.")
      return setpoint_c
    end

    # If the heating setpoint was set very low so that
    # heating equipment never comes on
    # return the current design heating temperature
    if setpoint_c < OpenStudio.convert(41, 'F', 'C').get
      setpoint_f = OpenStudio.convert(setpoint_c, 'C', 'F').get
      new_setpoint_c = thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperature
      new_setpoint_f = OpenStudio.convert(new_setpoint_c, 'C', 'F').get
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}: max heating setpoint in proposed model was #{setpoint_f.round} F.  20 F SAT delta-T from this point is unreasonable. Design heating SAT will be #{new_setpoint_f.round} F from proposed model.")
      return new_setpoint_c
    end

    # Add 20F delta-T
    delta_t_r = 20

    new_delta_t = thermal_zone_prm_lab_delta_t(thermal_zone)
    unless new_delta_t.nil?
      delta_t_r = new_delta_t
    end

    delta_t_k = OpenStudio.convert(delta_t_r, 'R', 'K').get

    sat_c = setpoint_c + delta_t_k # Add for heating

    return sat_c
  end

  # Calculate the cooling supply temperature based on the specified delta-T.
  # Delta-T is calculated based on the highest value found in the cooling setpoint schedule.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [Double] the design heating supply temperature, in degrees Celsius
  # @todo Exception: 17F delta-T for labs
  def thermal_zone_prm_baseline_cooling_design_supply_temperature(thermal_zone)
    setpoint_c = nil

    # Setpoint schedule
    tstat = thermal_zone.thermostatSetpointDualSetpoint
    if tstat.is_initialized
      tstat = tstat.get
      setpoint_sch = tstat.coolingSetpointTemperatureSchedule
      if setpoint_sch.is_initialized
        setpoint_sch = setpoint_sch.get
        if setpoint_sch.to_ScheduleRuleset.is_initialized
          setpoint_sch = setpoint_sch.to_ScheduleRuleset.get
          setpoint_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(setpoint_sch)['min']
        elsif setpoint_sch.to_ScheduleConstant.is_initialized
          setpoint_sch = setpoint_sch.to_ScheduleConstant.get
          setpoint_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(setpoint_sch)['min']
        elsif setpoint_sch.to_ScheduleCompact.is_initialized
          setpoint_sch = setpoint_sch.to_ScheduleCompact.get
          setpoint_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(setpoint_sch)['min']
        end
      end
    end

    # If the cooling setpoint could not be determined
    # return the current design cooling temperature
    if setpoint_c.nil?
      setpoint_c = thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperature
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}: could not determine min cooling setpoint.  Design cooling SAT will be #{OpenStudio.convert(setpoint_c, 'C', 'F').get.round} F from proposed model.")
      return setpoint_c
    end

    # If the cooling setpoint was set very high so that
    # cooling equipment never comes on
    # return the current design cooling temperature
    if setpoint_c > OpenStudio.convert(91, 'F', 'C').get
      setpoint_f = OpenStudio.convert(setpoint_c, 'C', 'F').get
      new_setpoint_c = thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperature
      new_setpoint_f = OpenStudio.convert(new_setpoint_c, 'C', 'F').get
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}: max cooling setpoint in proposed model was #{setpoint_f.round} F.  20 F SAT delta-T from this point is unreasonable. Design cooling SAT will be #{new_setpoint_f.round} F from proposed model.")
      return new_setpoint_c
    end

    # Subtract 20F delta-T
    delta_t_r = 20
    if /prm/i =~ template # avoid affecting previous PRM tests
      # For labs, substract 17 delta-T; otherwise, substract 20 delta-T
      thermal_zone.spaces.each do |space|
        space_std_type = space.spaceType.get.standardsSpaceType.get
        if space_std_type == 'laboratory'
          delta_t_r = 17
        end
      end
    end

    delta_t_k = OpenStudio.convert(delta_t_r, 'R', 'K').get

    sat_c = setpoint_c - delta_t_k # Subtract for cooling

    return sat_c
  end

  # Set the design delta-T for zone heating and cooling sizing supply air temperatures.
  # This value determines zone air flows, which will be summed during system design airflow calculation.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [Boolean] returns true if successful, false if not
  def thermal_zone_apply_prm_baseline_supply_temperatures(thermal_zone)
    # Skip spaces that aren't heated or cooled
    return true unless OpenstudioStandards::ThermalZone.thermal_zone_heated?(thermal_zone) || OpenstudioStandards::ThermalZone.thermal_zone_cooled?(thermal_zone)

    # Heating
    htg_sat_c = thermal_zone_prm_baseline_heating_design_supply_temperature(thermal_zone)
    htg_success = thermal_zone.sizingZone.setZoneHeatingDesignSupplyAirTemperature(htg_sat_c)

    # Cooling
    clg_sat_c = thermal_zone_prm_baseline_cooling_design_supply_temperature(thermal_zone)
    clg_success = thermal_zone.sizingZone.setZoneCoolingDesignSupplyAirTemperature(clg_sat_c)

    htg_sat_f = OpenStudio.convert(htg_sat_c, 'C', 'F').get
    clg_sat_f = OpenStudio.convert(clg_sat_c, 'C', 'F').get
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}, Htg SAT = #{htg_sat_f.round(1)}F, Clg SAT = #{clg_sat_f.round(1)}F.")

    result = false
    if htg_success && clg_success
      result = true
    end

    return result
  end

  # Determine the peak internal load (W) for
  # this zone without space multipliers.
  # This includes People, Lights, and all equipment types
  # in all spaces in this zone.
  # @author Doug Maddox, PNNL
  # @return [Double] the design internal load, in W
  def thermal_zone_peak_internal_load(model, thermal_zone, use_noncoincident_value: true)
    load_w = 0.0
    load_hrs_sum = Array.new(8760, 0)

    if use_noncoincident_value
      # Get the non-coincident sum of peak internal gains
      thermal_zone.spaces.each do |space|
        load_w += space_internal_load_annual_array(model, space, use_noncoincident_value)
      end
    else
      # Get array of coincident internal gain
      thermal_zone.spaces.each do |space|
        load_hrs = space_internal_load_annual_array(model, space, use_noncoincident_value)
        (0..8759).each do |ihr|
          load_hrs_sum[ihr] += load_hrs[ihr]
        end
      end
      load_w = load_hrs_sum.max
    end

    return load_w
  end

  # This is the operating hours for calulating EFLH which is used for determining whether a zone
  # should be included in a multizone system or isolated to a separate PSZ system
  # Based on the occupancy schedule for that zone
  # @author Doug Maddox, PNNL
  # @return [Array] 8760 array with 1 = operating, 0 = not operating
  def thermal_zone_get_annual_operating_hours(model, zone, zone_fan_sched)
    zone_ppl_sch = Array.new(8760, 0)     # merged people schedule for zone
    zone_op_sch = Array.new(8760, 0)      # intersection of fan and people scheds

    unoccupied_threshold = air_loop_hvac_unoccupied_threshold
    # Need composite occupant schedule for spaces in the zone
    zone.spaces.each do |space|
      space_ppl_sch = space_occupancy_annual_array(model, space)
      # If any space is occupied, make zone occupied
      (0..8759).each do |ihr|
        zone_ppl_sch[ihr] = 1 if space_ppl_sch[ihr] > 0
      end
    end

    zone_op_sch = zone_ppl_sch

    return zone_op_sch
  end

  # This is the EFLH for determining whether a zone should be included in a multizone system
  # or isolated to a separate PSZ system
  # Based on the intersection of the fan schedule for that zone and the occupancy schedule for that zone
  # @author Doug Maddox, PNNL
  # @return [Double] the design internal load, in W
  def thermal_zone_occupancy_eflh(zone, zone_op_sch)
    eflhs = [] # weekly array of eflh values

    # Convert 8760 array to weekly eflh values
    hr_of_yr = -1
    (0..51).each do |iweek|
      eflh = 0
      (0..6).each do |iday|
        (0..23).each do |ihr|
          hr_of_yr += 1
          eflh += zone_op_sch[hr_of_yr]
        end
      end
      eflhs << eflh
    end

    # Choose the most used weekly schedule as the representative eflh
    # This is the statistical mode of the array of values
    eflh_mode_list = eflhs.mode

    if eflh_mode_list.size > 1
      # Mode is an array of multiple values, take the largest value
      eflh = eflh_mode_list.max
    else
      eflh = eflh_mode_list[0]
    end
    return eflh
  end

  # Determine the thermal zone's occupancy type category.
  # Options are: residential, nonresidential
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [String] the occupancy type category
  # @todo Add public assembly building types
  def thermal_zone_occupancy_type(thermal_zone)
    occ_type = if OpenstudioStandards::ThermalZone.thermal_zone_residential?(thermal_zone)
                 'residential'
               else
                 'nonresidential'
               end

    # OpenStudio::logFree(OpenStudio::Info, "openstudio.Standards.ThermalZone", "For #{self.name}, occupancy type = #{occ_type}.")

    return occ_type
  end

  # Determine if demand control ventilation (DCV) is
  # required for this zone based on area and occupant density.
  # Does not account for System requirements like ERV, economizer, etc.
  # Those are accounted for in the AirLoopHVAC method of the same name.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] Returns true if required, false if not
  # @todo Add exception logic for 90.1-2013
  #   for cells, sickrooms, labs, barbers, salons, and bowling alleys
  def thermal_zone_demand_control_ventilation_required?(thermal_zone, climate_zone)
    dcv_required = false

    # Get the limits
    min_area_m2, min_area_m2_per_occ = thermal_zone_demand_control_ventilation_limits(thermal_zone)

    # Not required if both limits nil
    if min_area_m2.nil? && min_area_m2_per_occ.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: DCV is not required due to lack of minimum area requirements.")
      return dcv_required
    end

    # Get the area served and the number of occupants
    area_served_m2 = 0
    num_people = 0
    thermal_zone.spaces.each do |space|
      area_served_m2 += space.floorArea
      num_people += space.numberOfPeople
    end
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

    # Check the minimum area if there is a limit
    if min_area_m2
      # Convert limit to IP
      min_area_ft2 = OpenStudio.convert(min_area_m2, 'm^2', 'ft^2').get
      # Check the limit
      if area_served_ft2 < min_area_ft2
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: DCV is not required since the area is #{area_served_ft2.round} ft2, but the minimum size is #{min_area_ft2.round} ft2.")
        return dcv_required
      end
    end

    # Check the minimum occupancy density if there is a limit
    if min_area_m2_per_occ
      # Convert limit to IP
      min_area_ft2_per_occ = OpenStudio.convert(min_area_m2_per_occ, 'm^2', 'ft^2').get
      min_occ_per_ft2 = 1.0 / min_area_ft2_per_occ
      min_occ_per_1000_ft2 = min_occ_per_ft2 * 1000
      # Check the limit
      occ_per_ft2 = num_people / area_served_ft2
      occ_per_1000_ft2 = occ_per_ft2 * 1000
      if occ_per_1000_ft2 < min_occ_per_1000_ft2
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: DCV is not required since the occupant density is #{occ_per_1000_ft2.round} people/1000 ft2, but the minimum occupant density is #{min_occ_per_1000_ft2.round} people/1000 ft2.")
        return dcv_required
      end
    end

    # If here, DCV is required
    if min_area_m2 && min_area_m2_per_occ
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: DCV is required since the occupant density of #{occ_per_1000_ft2.round} people/1000 ft2 is above minimum occupant density of #{min_occ_per_1000_ft2.round} people/1000 ft2 and the area of #{area_served_ft2.round} ft2 is above the minimum size of #{min_area_ft2.round} ft2.")
    elsif min_area_m2
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: DCV is required since the area of #{area_served_ft2.round} ft2 is above the minimum size of #{min_area_ft2.round} ft2.")
    elsif min_area_m2_per_occ
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: DCV is required since the occupant density of #{occ_per_1000_ft2.round} people/1000 ft2 is above minimum occupant density of #{min_occ_per_1000_ft2.round} people/1000 ft2.")
    end

    dcv_required = true

    return dcv_required
  end

  # Determine the area and occupancy level limits for demand control ventilation.
  # No DCV requirements by default.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [Array<Double>] the minimum area, in m^2 and the minimum occupancy density in m^2/person.
  #   Returns nil if there is no requirement.
  def thermal_zone_demand_control_ventilation_limits(thermal_zone)
    min_area_m2 = nil
    min_area_per_occ = nil
    return [min_area_m2, min_area_per_occ]
  end

  # returns true if DCV is required for exhaust fan for specified tempate
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @return [Boolean] returns true if DCV is required for exhaust fan for specified template, false if not
  def thermal_zone_exhaust_fan_dcv_required?(thermal_zone); end

  # Add DCV to exhaust fan and if requsted to related objects
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @param change_related_objects [Boolean] change related objects
  # @param zone_mixing_objects [Array<OpenStudio::Model::ZoneMixing>] array of zone mixing objects
  # @param transfer_air_source_zones [Array<OpenStudio::Model::ThermalZone>] array thermal zones that transfer air
  # @return [Boolean] returns true if successful, false if not
  # @todo this method is currently empty
  def thermal_zone_add_exhaust_fan_dcv(thermal_zone, change_related_objects = true, zone_mixing_objects = [], transfer_air_source_zones = [])
    # set flow fraction schedule for all zone exhaust fans and then set zone mixing schedule to the intersection of exhaust availability and exhaust fractional schedule

    # are there associated zone mixing or dummy exhaust objects that need to change when this changes?
    # How are these objects identified?
    # If this is run directly after create_exhaust_fan(thermal_zone)  it will return a hash where each key is an exhaust object and hash is a hash of related zone mixing and dummy exhaust from the source zone
    return true
  end

  # Specify supply air temperature setpoint for unit heaters based on 90.1 Appendix G G3.1.2.8.2 (implementation in PRM subclass)
  def thermal_zone_prm_unitheater_design_supply_temperature(thermal_zone)
    return nil
  end

  # Specify supply to room delta for laboratory spaces based on 90.1 Appendix G Exception to G3.1.2.8.1 (implementation in PRM subclass)
  def thermal_zone_prm_lab_delta_t(thermal_zone)
    return nil
  end
end
