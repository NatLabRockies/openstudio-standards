class ASHRAE901PRM < Standard
  # @!group AirLoopHVAC

  # Shut off the system during unoccupied periods.
  # During these times, systems will cycle on briefly if temperature drifts below setpoint.
  # If the system already has a schedule other than Always-On, no change will be made.
  # If the system has an Always-On schedule assigned, a new schedule will be created.
  # In this case, occupied is defined as the total percent occupancy for the loop for all zones served.
  # For stable baseline, schedule is Always-On for computer rooms and when health and safety exception is used
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param min_occ_pct [Double] the fractional value below which the system will be considered unoccupied.
  # @return [Boolean] returns true if successful, false if not
  def air_loop_hvac_enable_unoccupied_fan_shutoff(air_loop_hvac, min_occ_pct = 0.05)
    if air_loop_hvac.additionalProperties.hasFeature('zone_group_type')
      zone_group_type = air_loop_hvac.additionalProperties.getFeatureAsString('zone_group_type').get
    else
      zone_group_type = 'None'
    end

    if zone_group_type == 'computer_zones'
      # Computer rooms are exempt from night cycle control
      return false
    end

    # Check for user data exceptions for night cycling
    # If any zone has the exception, then system will not cycle
    health_safety_exception = false
    air_loop_hvac.thermalZones.each do |thermal_zone|
      if thermal_zone.additionalProperties.hasFeature('has_health_safety_night_cycle_exception')
        exception = thermal_zone.additionalProperties.getFeatureAsBoolean('has_health_safety_night_cycle_exception').get
        return false if exception == true
      end
    end

    # Set the system to night cycle
    # The fan of a parallel PIU terminal are set to only cycle during heating operation
    # This is achieved using the CycleOnAnyCoolingOrHeatingZone; During cooling operation
    # the load is met by running the central system which stays off during heating
    # operation
    air_loop_hvac.setNightCycleControlType('CycleOnAny')
    if air_loop_hvac_has_parallel_piu_air_terminals?(air_loop_hvac)
      avail_mgrs = air_loop_hvac.availabilityManagers
      if !avail_mgrs.nil?
        avail_mgrs.each do |avail_mgr|
          if avail_mgr.to_AvailabilityManagerNightCycle.is_initialized
            avail_mgr_nc = avail_mgr.to_AvailabilityManagerNightCycle.get
            avail_mgr_nc.setControlType('CycleOnAnyCoolingOrHeatingZone')
            zones = air_loop_hvac.thermalZones
            avail_mgr_nc.setCoolingControlThermalZones(zones)
            avail_mgr_nc.setHeatingZoneFansOnlyThermalZones(zones)
          end
        end
      end
    end

    model = air_loop_hvac.model
    # Check if schedule was stored in an additionalProperties field of the air loop
    air_loop_name = air_loop_hvac.name
    if air_loop_hvac.hasAdditionalProperties && air_loop_hvac.additionalProperties.hasFeature('fan_sched_name')
      fan_sched_name = air_loop_hvac.additionalProperties.getFeatureAsString('fan_sched_name').get
      fan_sched = model.getScheduleRulesetByName(fan_sched_name).get
      air_loop_hvac.setAvailabilitySchedule(fan_sched)
      return true
    end

    # Check if already using a schedule other than always on
    avail_sch = air_loop_hvac.availabilitySchedule
    unless avail_sch == air_loop_hvac.model.alwaysOnDiscreteSchedule
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Availability schedule is already set to #{avail_sch.name}.  Will assume this includes unoccupied shut down; no changes will be made.")
      return true
    end

    # Get the airloop occupancy schedule
    loop_occ_sch = air_loop_hvac_get_occupancy_schedule(air_loop_hvac, occupied_percentage_threshold: min_occ_pct)
    flh = OpenstudioStandards::Schedules.schedule_get_equivalent_full_load_hours(loop_occ_sch)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Annual occupied hours = #{flh.round} hr/yr, assuming a #{min_occ_pct} occupancy threshold.  This schedule will be used as the HVAC operation schedule.")

    # Set HVAC availability schedule to follow occupancy
    air_loop_hvac.setAvailabilitySchedule(loop_occ_sch)
    air_loop_hvac.supplyComponents.each do |comp|
      if comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized
        comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get.setSupplyAirFanOperatingModeSchedule(loop_occ_sch)
      elsif comp.to_AirLoopHVACUnitarySystem.is_initialized
        comp.to_AirLoopHVACUnitarySystem.get.setSupplyAirFanOperatingModeSchedule(loop_occ_sch)
      end
    end

    return true
  end

  # Determine if the system is a multizone VAV system
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] Returns true if required, false if not.
  def air_loop_hvac_multizone_vav_system?(air_loop_hvac)
    return true if air_loop_hvac.name.to_s.include?('Sys5') || air_loop_hvac.name.to_s.include?('Sys6') || air_loop_hvac.name.to_s.include?('Sys7') || air_loop_hvac.name.to_s.include?('Sys8')

    return false
  end

  # Determine whether the VAV damper control is single maximum or dual maximum control.
  # Defaults to Single Maximum for stable baseline.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [String] the damper control type: Single Maximum, Dual Maximum
  def air_loop_hvac_vav_damper_action(air_loop_hvac)
    damper_action = 'Single Maximum'
    return damper_action
  end

  # Default occupancy fraction threshold for determining if the spaces on the air loop are occupied
  def air_loop_hvac_unoccupied_threshold
    # Use 10% based on PRM-RM
    return 0.10
  end

  # Determine if the system economizer must be integrated or not.
  # Always required for stable baseline if there is an economizer
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_integrated_economizer_required?(air_loop_hvac, climate_zone)
    return true
  end

  # Determine the economizer type and limits for the the PRM
  # Defaults to 90.1-2007 logic.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Array<Double>] [economizer_type, drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  def air_loop_hvac_prm_economizer_type_and_limits(air_loop_hvac, climate_zone)
    economizer_type = 'NoEconomizer'
    drybulb_limit_f = nil
    enthalpy_limit_btu_per_lb = nil
    dewpoint_limit_f = nil
    climate_zone_code = climate_zone.split('-')[-1]

    if ['0B', '1B', '2B', '3B', '3C', '4B', '4C', '5B', '5C', '6B', '7A', '7B', '8A', '8B'].include? climate_zone_code
      economizer_type = 'FixedDryBulb'
      drybulb_limit_f = 75
    elsif ['5A', '6A'].include? climate_zone_code
      economizer_type = 'FixedDryBulb'
      drybulb_limit_f = 70
    end

    return [economizer_type, drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  end

  # Determine if an economizer is required per the PRM.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_prm_baseline_economizer_required?(air_loop_hvac, climate_zone)
    economizer_required = false
    baseline_system_type = air_loop_hvac.additionalProperties.getFeatureAsString('baseline_system_type').get
    climate_zone_code = climate_zone.split('-')[-1]
    # System type 3 through 8 and 11, 12 and 13
    if ['SZ_AC', 'PSZ_AC', 'PVAV_Reheat', 'VAV_Reheat', 'SZ_VAV', 'PSZ_HP', 'SZ_CV', 'PSZ_HP', 'PVAV_PFP_Boxes', 'VAV_PFP_Boxes'].include? baseline_system_type
      unless ['0A', '0B', '1A', '1B', '2A', '3A', '4A'].include? climate_zone_code
        economizer_required = true
      end
    end

    # System type 3 and 4 in computer rooms are subject to exceptions
    if baseline_system_type == 'PSZ_AC' || baseline_system_type == 'PSZ_HP'
      if air_loop_hvac.additionalProperties.hasFeature('zone_group_type') && air_loop_hvac.additionalProperties.getFeatureAsString('zone_group_type').get == 'computer_zones'
        economizer_required = false
      end
    end

    # Check user_data in the zones
    gas_phase_exception = false
    open_refrigeration_exception = false
    air_loop_hvac.thermalZones.each do |thermal_zone|
      if thermal_zone.additionalProperties.hasFeature('economizer_exception_for_gas_phase_air_cleaning')
        gas_phase_exception = true
      end
      if thermal_zone.additionalProperties.hasFeature('economizer_exception_for_open_refrigerated_cases')
        open_refrigeration_exception = true
      end
    end
    if gas_phase_exception || open_refrigeration_exception
      economizer_required = false
    end
    return economizer_required
  end

  # Set fan curve for stable baseline to be VSD with fixed static pressure setpoint
  # @return [String name of appropriate curve for this code version
  def air_loop_hvac_set_vsd_curve_type
    return 'Multi Zone VAV with Fixed Static Pressure Setpoint'
  end

  # Determines if optimum start control is required.
  # PRM does not require optimum start - override it to false.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_optimum_start_required?(air_loop_hvac)
    return false
  end

  # Calculate and apply the performance rating method
  # baseline fan power to this air loop based on the
  # system type that it represents.
  #
  # Fan motor efficiency will be set, and then
  # fan pressure rise adjusted so that the
  # fan power is the maximum allowable.
  #
  # Also adjusts the fan power and flow rates
  # of any parallel PIU terminals on the system.
  #
  # return [Boolean] true if successful, false if not.
  def air_loop_hvac_apply_prm_baseline_fan_power(air_loop_hvac)
    # Get system type associated with air loop
    system_type = air_loop_hvac.additionalProperties.getFeatureAsString('baseline_system_type').get

    # Find out if air loop represents a non mechanically cooled system
    is_nmc = false
    is_nmc = true if air_loop_hvac.additionalProperties.hasFeature('non_mechanically_cooled')

    # Get all air loop fans
    all_fans = air_loop_hvac_supply_return_exhaust_relief_fans(air_loop_hvac)

    allowable_fan_bhp = 0.0
    allowable_power_w = 0.0
    fan_efficacy_w_per_cfm = 0.0
    supply_fan_power_fraction = 0.0
    return_fan_power_fraction = 0.0
    relief_fan_power_fraction = 0.0
    if system_type == 'PSZ_AC' ||
       system_type == 'PSZ_HP' ||
       system_type == 'PVAV_Reheat' ||
       system_type == 'PVAV_PFP_Boxes' ||
       system_type == 'VAV_Reheat' ||
       system_type == 'VAV_PFP_Boxes' ||
       system_type == 'SZ_VAV' ||
       system_type == 'SZ_CV'

      # Calculate the allowable fan motor bhp for the air loop
      allowable_fan_bhp = air_loop_hvac_allowable_system_brake_horsepower(air_loop_hvac)

      # Divide the allowable power based
      # individual zone air flow
      air_loop_total_zone_design_airflow = 0
      air_loop_hvac.thermalZones.sort.each do |zone|
        # error if zone design air flow rate is not available
        if zone.model.version < OpenStudio::VersionString.new('3.6.0')
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.ashrae_90_1_prm.AirLoopHVAC', 'Required ThermalZone method .autosizedDesignAirFlowRate is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
        end

        zone_air_flow = zone.autosizedDesignAirFlowRate.to_f
        air_loop_total_zone_design_airflow += zone_air_flow
        # Fractions variables are actually power at that point
        supply_fan_power_fraction += zone_air_flow * zone.additionalProperties.getFeatureAsDouble('supply_fan_w').get
        return_fan_power_fraction += zone_air_flow * zone.additionalProperties.getFeatureAsDouble('return_fan_w').get
        relief_fan_power_fraction += zone_air_flow * zone.additionalProperties.getFeatureAsDouble('relief_fan_w').get
      end
      if air_loop_total_zone_design_airflow > 0
        # Get average power for each category of fan
        supply_fan_power_fraction /= air_loop_total_zone_design_airflow
        return_fan_power_fraction /= air_loop_total_zone_design_airflow
        relief_fan_power_fraction /= air_loop_total_zone_design_airflow
        # Convert to power fraction
        total_fan_avg_fan_w = (supply_fan_power_fraction + return_fan_power_fraction + relief_fan_power_fraction)
        supply_fan_power_fraction /= total_fan_avg_fan_w
        return_fan_power_fraction /= total_fan_avg_fan_w
        relief_fan_power_fraction /= total_fan_avg_fan_w
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.ashrae_90_1_prm.AirLoopHVAC', "Total zone design airflow for #{air_loop_hvac.name} is 0.")
      end
    elsif system_type == 'PTAC' ||
          system_type == 'PTHP' ||
          system_type == 'Gas_Furnace' ||
          system_type == 'Electric_Furnace'

      # Determine allowable fan power
      if is_nmc
        fan_efficacy_w_per_cfm = 0.054
      else
        fan_efficacy_w_per_cfm = 0.3
      end

      # Configuration is supply fan only
      supply_fan_power_fraction = 1.0
    end

    supply_fan = air_loop_hvac_get_supply_fan(air_loop_hvac)
    if supply_fan.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.ashrae_90_1_prm.AirLoopHVAC', "Supply not found on #{airloop.name}.")
    end
    supply_fan_max_flow = if supply_fan.maximumFlowRate.is_initialized
                            supply_fan.maximumFlowRate.get
                          elsif supply_fan.autosizedMaximumFlowRate.is_initialized
                            supply_fan.autosizedMaximumFlowRate.get
                          end

    # Check that baseline system has the same
    # types of fans as the proposed model, if
    # not, create them. We assume that the
    # system has at least a supply fan.
    if return_fan_power_fraction > 0.0 && !air_loop_hvac.returnFan.is_initialized
      # Create return fan
      return_fan = supply_fan.clone(air_loop_hvac.model)
      if return_fan.to_FanConstantVolume.is_initialized
        return_fan = return_fan.to_FanConstantVolume.get
      elsif return_fan.to_FanVariableVolume.is_initialized
        return_fan = return_fan.to_FanVariableVolume.get
      elsif return_fan.to_FanOnOff.is_initialized
        return_fan = return_fan.to_FanOnOff.get
      elsif return_fan.to_FanSystemModel.is_initialized
        return_fan = return_fan.to_FanSystemModel.get
      end
      return_fan.setName("#{air_loop_hvac.name} Return Fan")
      return_fan.addToNode(air_loop_hvac.returnAirNode.get)
      return_fan.setMaximumFlowRate(supply_fan_max_flow)
    end
    if relief_fan_power_fraction > 0.0 && !air_loop_hvac.reliefFan.is_initialized
      # Create return fan
      relief_fan = supply_fan.clone(air_loop_hvac.model)
      if relief_fan.to_FanConstantVolume.is_initialized
        relief_fan = relief_fan.to_FanConstantVolume.get
      elsif relief_fan.to_FanVariableVolume.is_initialized
        relief_fan = relief_fan.to_FanVariableVolume.get
      elsif relief_fan.to_FanOnOff.is_initialized
        relief_fan = relief_fan.to_FanOnOff.get
      elsif relief_fan.to_FanSystemModel.is_initialized
        relief_fan = relief_fan.to_FanSystemModel.get
      end
      relief_fan.setName("#{air_loop_hvac.name} Relief Fan")
      relief_fan.addToNode(air_loop_hvac.reliefAirNode.get)
      relief_fan.setMaximumFlowRate(supply_fan_max_flow)
    end

    # Get all air loop fans
    all_fans = air_loop_hvac_supply_return_exhaust_relief_fans(air_loop_hvac)

    # Set the motor efficiencies
    # for all fans based on the calculated
    # allowed brake hp.  Then calculate the allowable
    # fan power for each fan and adjust
    # the fan pressure rise accordingly
    all_fans.each do |fan|
      # Efficacy requirement
      if fan_efficacy_w_per_cfm > 0
        # Convert efficacy to metric
        fan_efficacy_w_per_m3_per_s = OpenStudio.convert(fan_efficacy_w_per_cfm, 'm^3/s', 'cfm').get
        fan_change_impeller_efficiency(fan, fan_baseline_impeller_efficiency(fan))

        # Get fan BHP
        fan_bhp = fan_brake_horsepower(fan)

        # Set the motor efficiency, preserving the impeller efficiency.
        # For zone HVAC fans, a bhp lookup of 0.5bhp is always used because
        # they are assumed to represent a series of small fans in reality.
        fan_apply_standard_minimum_motor_efficiency(fan, fan_bhp)

        # Calculate a new pressure rise to hit the target W/cfm
        fan_tot_eff = fan.fanEfficiency
        fan_rise_new_pa = fan_efficacy_w_per_m3_per_s * fan_tot_eff
        fan.setPressureRise(fan_rise_new_pa)
      end

      # BHP requirements
      if allowable_fan_bhp > 0
        fan_apply_standard_minimum_motor_efficiency(fan, allowable_fan_bhp)
        allowable_power_w = allowable_fan_bhp * 746 / fan.motorEfficiency

        # Breakdown fan power based on fan type
        if supply_fan.name.to_s == fan.name.to_s
          allowable_power_w *= supply_fan_power_fraction
        elsif fan.airLoopHVAC.is_initialized
          if fan.airLoopHVAC.get.returnFan.is_initialized && fan.airLoopHVAC.get.returnFan.get.name.to_s == fan.name.to_s
            allowable_power_w *= return_fan_power_fraction
          end
          if fan.airLoopHVAC.get.reliefFan.is_initialized && fan.airLoopHVAC.get.reliefFan.get.name.to_s == fan.name.to_s
            allowable_power_w *= relief_fan_power_fraction
          end
        end
        fan_adjust_pressure_rise_to_meet_fan_power(fan, allowable_power_w)
      end
    end

    return true unless system_type == 'PVAV_PFP_Boxes' || system_type == 'VAV_PFP_Boxes'

    # Adjust fan powered terminal fans power
    air_loop_hvac.demandComponents.each do |dc|
      next if dc.to_AirTerminalSingleDuctParallelPIUReheat.empty?

      pfp_term = dc.to_AirTerminalSingleDuctParallelPIUReheat.get
      air_terminal_single_duct_parallel_piu_reheat_apply_prm_baseline_fan_power(pfp_term)
    end

    return true
  end

  # Determine the allowable fan system brake horsepower
  # Per Section G3.1.2.9
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC]
  # @return [Double] allowable fan system brake horsepower
  #   units = horsepower
  def air_loop_hvac_allowable_system_brake_horsepower(air_loop_hvac)
    # Get design supply air flow rate (whether autosized or hard-sized)
    dsn_air_flow_m3_per_s = 0
    dsn_air_flow_cfm = 0
    if air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
      dsn_air_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
      dsn_air_flow_cfm = OpenStudio.convert(dsn_air_flow_m3_per_s, 'm^3/s', 'cfm').get
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.ashrae_90_1_prm.AirLoopHVAC', "* #{dsn_air_flow_cfm.round} cfm = Autosized Design Supply Air Flow Rate.")
    else
      dsn_air_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
      dsn_air_flow_cfm = OpenStudio.convert(dsn_air_flow_m3_per_s, 'm^3/s', 'cfm').get
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.ashrae_90_1_prm.AirLoopHVAC', "* #{dsn_air_flow_cfm.round} cfm = Hard sized Design Supply Air Flow Rate.")
    end

    # Get the fan limitation pressure drop adjustment bhp
    fan_pwr_adjustment_bhp = air_loop_hvac_fan_power_limitation_pressure_drop_adjustment_brake_horsepower(air_loop_hvac)

    # Get system type associated with air loop
    system_type = air_loop_hvac.additionalProperties.getFeatureAsString('baseline_system_type').get

    # Calculate the Allowable Fan System brake horsepower per Table G3.1.2.9
    allowable_fan_bhp = 0.0
    case system_type
      when 'PSZ_HP', 'PSZ_AC', 'SZ_CV' # 3, 4, 12, 13
        allowable_fan_bhp = (dsn_air_flow_cfm * 0.00094) + fan_pwr_adjustment_bhp
      when 'PVAV_Reheat', 'PVAV_PFP_Boxes', 'VAV_Reheat', 'VAV_PFP_Boxes', 'SZ_VAV' # 5, 6, 7, 8, 11
        allowable_fan_bhp = (dsn_air_flow_cfm * 0.0013) + fan_pwr_adjustment_bhp
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.ashrae_90_1_prm.AirLoopHVAC', "Air loop #{air_loop_hvac.name} is not associated with a baseline system.")
    end

    return allowable_fan_bhp
  end

  # Check if an air loop in user model needs to have DCV per air loop related requiremends in ASHRAE 90.1-2019 6.4.3.8
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] flag of whether air loop in user model is required to have DCV
  def user_model_air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac)
    # all zones in the same airloop in user model are set with the same value, so use the first zone under the loop
    dcv_airloop_user_exception = air_loop_hvac.thermalZones[0].additionalProperties.getFeatureAsBoolean('airloop user specified DCV exception').get
    return false if dcv_airloop_user_exception

    # check the following conditions at airloop level
    # has air economizer OR design outdoor airflow > 3000 cfm

    has_economizer = air_loop_hvac_economizer?(air_loop_hvac)

    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_flow_m3_per_s = get_airloop_hvac_design_oa_from_sql(air_loop_hvac)
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, DCV not applicable because it has no OA intake.")
      return false
    end
    oa_flow_cfm = OpenStudio.convert(oa_flow_m3_per_s, 'm^3/s', 'cfm').get

    any_zones_req_dcv = false
    air_loop_hvac.thermalZones.sort.each do |zone|
      if user_model_zone_demand_control_ventilation_required?(zone)
        any_zones_req_dcv = true
        break
      end
    end

    return true if any_zones_req_dcv && (has_economizer || (oa_flow_cfm > 3000))

    return false
  end

  # Check if a zone in user model needs to have DCV per zone related requiremends in ASHRAE 90.1-2019 6.4.3.8
  # @author Xuechen (Jerry) Lei, PNNL
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
  # @return [Boolean] flag of whether thermal zone in user model is required to have DCV
  def user_model_zone_demand_control_ventilation_required?(thermal_zone)
    dcv_zone_user_exception = thermal_zone.additionalProperties.getFeatureAsBoolean('zone user specified DCV exception').get
    return false if dcv_zone_user_exception

    # check the following conditions at zone level
    # zone > 500 sqft AND design occ > 25 ppl/ksqft

    area_served_m2 = 0
    num_people = 0
    thermal_zone.spaces.each do |space|
      area_served_m2 += space.floorArea
      num_people += space.numberOfPeople
    end
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get
    occ_per_1000_ft2 = num_people / area_served_ft2 * 1000

    return true if (area_served_ft2 > 500) && (occ_per_1000_ft2 > 25)

    return false
  end

  # Check if the air loop in baseline model needs to have DCV
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] flag of whether the air loop in baseline is required to have DCV
  def baseline_air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac)
    any_zone_req_dcv = false
    air_loop_hvac.thermalZones.each do |zone|
      if baseline_thermal_zone_demand_control_ventilation_required?(zone)
        any_zone_req_dcv = true
      end
    end
    return any_zone_req_dcv # baseline airloop needs dcv if any zone it serves needs dcv
  end

  # Check if the thermal zone in baseline model needs to have DCV
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
  # @return [Boolean] flag of whether thermal zone in baseline is required to have DCV
  def baseline_thermal_zone_demand_control_ventilation_required?(thermal_zone)
    # zone needs dcv if user model has dcv and baseline does not meet apxg exception
    if thermal_zone.additionalProperties.hasFeature('apxg no need to have DCV')
      # meaning it was served by an airloop in the user model, does not mean much here, conditional as a safeguard
      # in case it was not served by an airloop in the user model
      if !thermal_zone.additionalProperties.getFeatureAsBoolean('apxg no need to have DCV').get && # does not meet apxg exception (need to have dcv if user model has it
         thermal_zone.additionalProperties.getFeatureAsBoolean('zone DCV implemented in user model').get
        return true
      end
    end
    return false
  end

  # Get the air loop HVAC design outdoor air flow rate by reading Standard 62.1 Summary from the sizing sql
  # @author Xuechen (Jerry) Lei, PNNL
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Double] Design outdoor air flow rate (m^3/s)
  def get_airloop_hvac_design_oa_from_sql(air_loop_hvac)
    return false unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized

    cooling_oa = air_loop_hvac.model.sqlFile.get.execAndReturnFirstDouble(
      "SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName = 'System Ventilation Requirements for Cooling' AND ColumnName LIKE 'Outdoor Air Intake Flow%Vot' AND RowName='#{air_loop_hvac.name.to_s.upcase}'"
    )
    heating_oa = air_loop_hvac.model.sqlFile.get.execAndReturnFirstDouble(
      "SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName = 'System Ventilation Requirements for Heating' AND ColumnName LIKE 'Outdoor Air Intake Flow%Vot' AND RowName='#{air_loop_hvac.name.to_s.upcase}'"
    )
    return [cooling_oa.to_f, heating_oa.to_f].max
  end

  # Set the minimum VAV damper positions.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param has_ddc [Boolean] if true, will assume that there is DDC control of vav terminals.
  #   If false, assumes otherwise.
  # @return [Boolean] returns true if successful, false if not
  def air_loop_hvac_apply_minimum_vav_damper_positions(air_loop_hvac, has_ddc = true)
    air_loop_hvac.thermalZones.each do |zone|
      zone.equipment.each do |equip|
        if equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
          zone_oa = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
          vav_terminal = equip.to_AirTerminalSingleDuctVAVReheat.get
          air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(vav_terminal, zone_oa, has_ddc)
        elsif equip.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized
          zone_oa = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
          fp_vav_terminal = equip.to_AirTerminalSingleDuctParallelPIUReheat.get
          air_terminal_single_duct_parallel_piu_reheat_apply_minimum_primary_airflow_fraction(fp_vav_terminal, zone_oa)
        end
      end
    end

    return true
  end

  # Determine the limits for the type of economizer present on the AirLoopHVAC, if any.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Array<Double>] [drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  def air_loop_hvac_economizer_limits(air_loop_hvac, climate_zone)
    drybulb_limit_f = nil
    enthalpy_limit_btu_per_lb = nil
    dewpoint_limit_f = nil

    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    return [nil, nil, nil] unless oa_sys.is_initialized

    oa_sys = oa_sys.get
    oa_control = oa_sys.getControllerOutdoorAir
    economizer_type = oa_control.getEconomizerControlType

    case economizer_type
    when 'NoEconomizer'
      return [nil, nil, nil]
    when 'FixedDryBulb'
      # Process climate zone:
      # Moisture regime is not needed for climate zone 8
      climate_zone = climate_zone.split('-')[-1]
      climate_zone = '8' if climate_zone.include?('8')

      search_criteria = {
        'climate_zone' => climate_zone,
        'data_center' => false,
      }
      econ_limits = model_find_object(standards_data['economizers'], search_criteria)
      drybulb_limit_f = econ_limits['fixed_dry_bulb_high_limit_shutoff_temp']
    when 'FixedEnthalpy'
      enthalpy_limit_btu_per_lb = 28.0
    when 'FixedDewPointAndDryBulb'
      drybulb_limit_f = 75.0
      dewpoint_limit_f = 55.0
    end

    return [drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  end

  # Determine the fan power limitation pressure drop adjustment
  # Per Table 6.5.3.1-2 (90.1-2019)
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Double] fan power limitation pressure drop adjustment, in units of horsepower
  def air_loop_hvac_fan_power_limitation_pressure_drop_adjustment_brake_horsepower(air_loop_hvac)
    # Calculate Fan Power Limitation Pressure Drop Adjustment
    fan_pwr_adjustment_bhp = 0

    # Retrieve climate zone
    climate_zone = air_loop_hvac.model.getClimateZones.getClimateZone(0)

    # Check if energy recovery is required
    is_energy_recovery_required = air_loop_hvac_energy_recovery_ventilator_required?(air_loop_hvac, climate_zone)

    system_type = ''
    # Get baseline system type if applicable
    if air_loop_hvac.additionalProperties.hasFeature('baseline_system_type')
      system_type = air_loop_hvac.additionalProperties.getFeatureAsString('baseline_system_type').to_s
    end

    air_loop_hvac.thermalZones.each do |zone|
      # Take fan power deductions into account;
      # Deductions are calculated based on the
      # baseline model design.
      # The only deduction that's applicable
      # is the "System with central electric
      # resistance heat" for system 6 and 8
      if system_type == 'PVAV_PFP_Boxes' || system_type == 'VAV_PFP_Boxes'
        if zone.additionalProperties.hasFeature('has_fan_power_deduction_system_with_central_electric_resistance_heat')
          current_value = zone.additionalProperties.getFeatureAsDouble('has_fan_power_deduction_system_with_central_electric_resistance_heat')
          zone.additionalProperties.setFeature('has_fan_power_deduction_system_with_central_electric_resistance_heat', current_value + 1.0)
        else
          zone.additionalProperties.setFeature('has_fan_power_deduction_system_with_central_electric_resistance_heat', 1.0)
        end
      end

      # Determine fan power adjustment
      fan_pwr_adjustment_bhp += thermal_zone_get_fan_power_limitations(zone, is_energy_recovery_required)
    end

    return fan_pwr_adjustment_bhp
  end

  # Set effectiveness value of an ERV's heat exchanger
  #
  # @param erv [OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent] ERV to apply efficiency values
  # @param erv_type [String] ERV type: ERV or HRV
  # @param heat_exchanger_type [String] Heat exchanger type: Rotary or Plate
  # @return [OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent] ERV to apply efficiency values
  def air_loop_hvac_apply_energy_recovery_ventilator_efficiency(erv, erv_type: 'ERV', heat_exchanger_type: 'Rotary')
    heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness(erv)

    return erv
  end

  # Determine the airflow limits that govern whether or not an ERV is required.
  # Based on climate zone and % OA.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param pct_oa [Double] percentage of outdoor air
  # @return [Double] the flow rate above which an ERV is required. if nil, ERV is never required.
  def air_loop_hvac_energy_recovery_ventilator_flow_limit(air_loop_hvac, climate_zone, pct_oa)
    if pct_oa < 0.7
      erv_cfm = nil
    else
      # Heating thermostat setpoint threshold
      temp_c = OpenStudio.convert(60, 'F', 'C').get

      # Check for exceptions for each zone
      air_loop_hvac.thermalZones.each do |thermal_zone|
        # Get heating thermosat setpoint and comparing to heating thermostat setpoint threshold
        tstat = thermal_zone.thermostat.get
        if tstat.to_ThermostatSetpointDualSetpoint
          tstat = tstat.to_ThermostatSetpointDualSetpoint.get
          htg_sch = tstat.getHeatingSchedule
          if htg_sch.is_initialized
            htg_sch = htg_sch.get
            if htg_sch.to_ScheduleRuleset.is_initialized
              htg_sch = htg_sch.to_ScheduleRuleset.get
              max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(htg_sch)['max']
              if max_c > temp_c
                htd = true
              end
            elsif htg_sch.to_ScheduleConstant.is_initialized
              htg_sch = htg_sch.to_ScheduleConstant.get
              max_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(htg_sch)['max']
              if max_c > temp_c
                htd = true
              end
            elsif htg_sch.to_ScheduleCompact.is_initialized
              htg_sch = htg_sch.to_ScheduleCompact.get
              max_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(htg_sch)['max']
              if max_c > temp_c
                htd = true
              end
            else
              OpenStudio.logFree(OpenStudio::Error, 'prm.log', "Zone #{thermal_zone.name} used an unknown schedule type for the heating setpoint; assuming heated.")
              htd = true
            end
          end
        elsif tstat.to_ZoneControlThermostatStagedDualSetpoint
          tstat = tstat.to_ZoneControlThermostatStagedDualSetpoint.get
          htg_sch = tstat.heatingTemperatureSetpointSchedule
          if htg_sch.is_initialized
            htg_sch = htg_sch.get
            if htg_sch.to_ScheduleRuleset.is_initialized
              htg_sch = htg_sch.to_ScheduleRuleset.get
              max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(htg_sch)['max']
              if max_c > temp_c
                htd = true
              end
            end
          end
        end

        # Exception 1 - Systems heated to less than 60F since all baseline system provide cooling
        if !htd
          return nil
        end

        # Exception 2 - System exhausting toxic fumes
        if thermal_zone.additionalProperties.hasFeature('exhaust_energy_recovery_exception_for_toxic_fumes_etc') && thermal_zone.additionalProperties.getFeatureAsBoolean('exhaust_energy_recovery_exception_for_toxic_fumes_etc')
          return nil
        end

        # Exception 3 - Commercial kitchen hoods
        if thermal_zone.additionalProperties.hasFeature('exhaust_energy_recovery_exception_for_type1_kitchen_hoods') && thermal_zone.additionalProperties.getFeatureAsBoolean('exhaust_energy_recovery_exception_for_type1_kitchen_hoods')
          return nil
        end

        # Exception 6 - Distributed exhaust
        if thermal_zone.additionalProperties.hasFeature('exhaust_energy_recovery_exception_for_type_distributed_exhaust') && thermal_zone.additionalProperties.getFeatureAsBoolean('exhaust_energy_recovery_exception_for_type_distributed_exhaust')
          return nil
        end

        # Exception 7 - Dehumidification
        if thermal_zone.additionalProperties.hasFeature('exhaust_energy_recovery_exception_for_dehumidifcation_with_series_cooling_recovery') && thermal_zone.additionalProperties.getFeatureAsBoolean('exhaust_energy_recovery_exception_for_dehumidifcation_with_series_cooling_recovery')
          return nil
        end
      end

      # Exception 4 - Heating systems in certain climate zones
      if ['ASHRAE 169-2006-0A', 'ASHRAE 169-2006-0B', 'ASHRAE 169-2006-1A', 'ASHRAE 169-2006-1B', 'ASHRAE 169-2006-2A', 'ASHRAE 169-2006-2B', 'ASHRAE 169-2006-3A', 'ASHRAE 169-2006-3B', 'ASHRAE 169-2006-3C', 'ASHRAE 169-2013-0A', 'ASHRAE 169-2013-0B', 'ASHRAE 169-2013-1A', 'ASHRAE 169-2013-1B', 'ASHRAE 169-2013-2A', 'ASHRAE 169-2013-2B', 'ASHRAE 169-2013-3A', 'ASHRAE 169-2013-3B', 'ASHRAE 169-2013-3C'].include?(climate_zone) && air_loop_hvac.additionalProperties.hasFeature('baseline_system_type')
        system_type = air_loop_hvac.additionalProperties.getFeatureAsString('baseline_system_type').get
        if system_type == 'Gas_Furnace' || system_type == 'Electric_Furnace'
          return nil
        end
      end

      erv_cfm = 5000
    end

    return erv_cfm
  end
end
