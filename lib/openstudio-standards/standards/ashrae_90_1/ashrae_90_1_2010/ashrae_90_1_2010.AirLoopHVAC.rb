class ASHRAE9012010 < ASHRAE901
  # @!group AirLoopHVAC

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
    return [nil, nil, nil] unless oa_sys.is_initialized # No OA system

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
        'template' => template,
        'climate_zone' => climate_zone
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

  # Determine if the system economizer must be integrated or not.
  # All economizers must be integrated in 90.1-2010
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_integrated_economizer_required?(air_loop_hvac, climate_zone)
    return true
  end

  # Check the economizer type currently specified in the ControllerOutdoorAir object on this air loop
  # is acceptable per the standard.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] Returns true if allowable, if the system has no economizer or no OA system.
  #   Returns false if the economizer type is not allowable.
  def air_loop_hvac_economizer_type_allowable?(air_loop_hvac, climate_zone)
    # EnergyPlus economizer types
    # 'NoEconomizer'
    # 'FixedDryBulb'
    # 'FixedEnthalpy'
    # 'DifferentialDryBulb'
    # 'DifferentialEnthalpy'
    # 'FixedDewPointAndDryBulb'
    # 'ElectronicEnthalpy'
    # 'DifferentialDryBulbAndEnthalpy'

    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    return true unless oa_sys.is_initialized

    oa_sys = oa_sys.get
    oa_control = oa_sys.getControllerOutdoorAir
    economizer_type = oa_control.getEconomizerControlType

    # Return true if no economizer is present
    if economizer_type == 'NoEconomizer'
      return true
    end

    # Determine the prohibited types
    prohibited_types = []
    case climate_zone
    when 'ASHRAE 169-2006-0B',
         'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2006-4B',
         'ASHRAE 169-2006-4C',
         'ASHRAE 169-2006-5B',
         'ASHRAE 169-2006-6B',
         'ASHRAE 169-2006-7A',
         'ASHRAE 169-2006-7B',
         'ASHRAE 169-2006-8A',
         'ASHRAE 169-2006-8B',
         'ASHRAE 169-2013-0B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C',
         'ASHRAE 169-2013-4B',
         'ASHRAE 169-2013-4C',
         'ASHRAE 169-2013-5B',
         'ASHRAE 169-2013-6B',
         'ASHRAE 169-2013-7A',
         'ASHRAE 169-2013-7B',
         'ASHRAE 169-2013-8A',
         'ASHRAE 169-2013-8B'
      prohibited_types = ['FixedEnthalpy']
    when 'ASHRAE 169-2006-0A',
         'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-4A',
         'ASHRAE 169-2013-0A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-4A'
      prohibited_types = ['FixedDryBulb', 'DifferentialDryBulb']
    when 'ASHRAE 169-2006-5A',
         'ASHRAE 169-2006-6A',
         'ASHRAE 169-2013-5A',
         'ASHRAE 169-2013-6A'
      prohibited_types = []
    end

    # Check if the specified type is allowed
    economizer_type_allowed = true
    if prohibited_types.include?(economizer_type)
      economizer_type_allowed = false
    end

    return economizer_type_allowed
  end

  # Determine if multizone vav optimization is required.
  # @note code_sections [90.1-2010_6.5.3.3]
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if required, false if not
  # @todo Add exception logic for systems with AIA healthcare ventilation requirements dual duct systems
  def air_loop_hvac_multizone_vav_optimization_required?(air_loop_hvac, climate_zone)
    multizone_opt_required = false

    # Not required for systems with fan-powered terminals
    num_fan_powered_terminals = 0
    air_loop_hvac.demandComponents.each do |comp|
      if comp.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized || comp.to_AirTerminalSingleDuctSeriesPIUReheat.is_initialized
        num_fan_powered_terminals += 1
      end
    end
    if num_fan_powered_terminals > 0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, multizone vav optimization is not required because the system has #{num_fan_powered_terminals} fan-powered terminals.")
      return multizone_opt_required
    end

    # Not required for systems that require an ERV
    # Exception 2 to Section 6.5.3.3
    if air_loop_hvac_energy_recovery?(air_loop_hvac)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: multizone vav optimization is not required because the system has Energy Recovery.")
      return multizone_opt_required
    end

    # Get the OA intake
    controller_oa = nil
    controller_mv = nil
    oa_system = nil
    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      controller_mv = controller_oa.controllerMechanicalVentilation
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, multizone optimization is not applicable because system has no OA intake.")
      return multizone_opt_required
    end

    # Get the AHU design supply air flow rate
    dsn_flow_m3_per_s = nil
    if air_loop_hvac.designSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
    elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} design supply air flow rate is not available, cannot apply efficiency standard.")
      return multizone_opt_required
    end
    dsn_flow_cfm = OpenStudio.convert(dsn_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Get the minimum OA flow rate
    min_oa_flow_m3_per_s = nil
    if controller_oa.minimumOutdoorAirFlowRate.is_initialized
      min_oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
    elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
      min_oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{controller_oa.name}: minimum OA flow rate is not available, cannot apply efficiency standard.")
      return multizone_opt_required
    end
    min_oa_flow_cfm = OpenStudio.convert(min_oa_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Calculate the percent OA at design airflow
    pct_oa = min_oa_flow_m3_per_s / dsn_flow_m3_per_s

    # Not required for systems where
    # exhaust is more than 70% of the total OA intake.
    if pct_oa > 0.7
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{controller_oa.name}: multizone optimization is not applicable because system is more than 70% OA.")
      return multizone_opt_required
    end

    # @todo Not required for dual-duct systems
    # if self.isDualDuct
    # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.AirLoopHVAC", "For #{controller_oa.name}: multizone optimization is not applicable because it is a dual duct system")
    # return multizone_opt_required
    # end

    # If here, multizone vav optimization is required
    multizone_opt_required = true

    return multizone_opt_required
  end

  # Determines the OA flow rates above which an economizer is required.
  # Two separate rates, one for systems with an economizer and another for systems without.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Array<Double>] [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  def air_loop_hvac_demand_control_ventilation_limits(air_loop_hvac)
    min_oa_without_economizer_cfm = 3000
    min_oa_with_economizer_cfm = 1200
    return [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  end

  # Determine the air flow and number of story limits for whether motorized OA damper is required.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Array<Double>] [minimum_oa_flow_cfm, maximum_stories]. If both nil, never required
  def air_loop_hvac_motorized_oa_damper_limits(air_loop_hvac, climate_zone)
    case climate_zone
    when 'ASHRAE 169-2006-0A',
         'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-0B',
         'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2013-0A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-0B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C'
      minimum_oa_flow_cfm = 0
      maximum_stories = 999 # Any number of stories
    else
      minimum_oa_flow_cfm = 0
      maximum_stories = 0
    end

    return [minimum_oa_flow_cfm, maximum_stories]
  end

  # Determine the number of stages that should be used as controls for single zone DX systems.
  # 90.1-2010 depends on the cooling capacity of the system.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Integer] the number of stages: 0, 1, 2
  def air_loop_hvac_single_zone_controls_num_stages(air_loop_hvac, climate_zone)
    min_clg_cap_btu_per_hr = 65_000
    clg_cap_btu_per_hr = OpenStudio.convert(air_loop_hvac_total_cooling_capacity(air_loop_hvac), 'W', 'Btu/hr').get
    if clg_cap_btu_per_hr >= min_clg_cap_btu_per_hr
      num_stages = 2
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: two-stage control is required since cooling capacity of #{clg_cap_btu_per_hr.round} Btu/hr exceeds the minimum of #{min_clg_cap_btu_per_hr.round} Btu/hr .")
    else
      num_stages = 1
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: two-stage control is not required since cooling capacity of #{clg_cap_btu_per_hr.round} Btu/hr is less than the minimum of #{min_clg_cap_btu_per_hr.round} Btu/hr .")
    end

    return num_stages
  end

  # Determine if the system required supply air temperature
  # (SAT) reset. For 90.1-2010, SAT reset requirements are based on climate zone.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_supply_air_temperature_reset_required?(air_loop_hvac, climate_zone)
    is_sat_reset_required = false

    # Only required for multizone VAV systems
    unless air_loop_hvac_multizone_vav_system?(air_loop_hvac)
      return is_sat_reset_required
    end

    case climate_zone
    when 'ASHRAE 169-2006-0A',
         'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2013-0A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-3A'
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Supply air temperature reset is not required per 6.5.3.4 Exception 1, the system is located in climate zone #{climate_zone}.")
      return is_sat_reset_required
    when 'ASHRAE 169-2006-0B',
         'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2006-4A',
         'ASHRAE 169-2006-4B',
         'ASHRAE 169-2006-4C',
         'ASHRAE 169-2006-5A',
         'ASHRAE 169-2006-5B',
         'ASHRAE 169-2006-5C',
         'ASHRAE 169-2006-6A',
         'ASHRAE 169-2006-6B',
         'ASHRAE 169-2006-7A',
         'ASHRAE 169-2006-7B',
         'ASHRAE 169-2006-8A',
         'ASHRAE 169-2006-8B',
         'ASHRAE 169-2013-0B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C',
         'ASHRAE 169-2013-4A',
         'ASHRAE 169-2013-4B',
         'ASHRAE 169-2013-4C',
         'ASHRAE 169-2013-5A',
         'ASHRAE 169-2013-5B',
         'ASHRAE 169-2013-5C',
         'ASHRAE 169-2013-6A',
         'ASHRAE 169-2013-6B',
         'ASHRAE 169-2013-7A',
         'ASHRAE 169-2013-7B',
         'ASHRAE 169-2013-8A',
         'ASHRAE 169-2013-8B'
      is_sat_reset_required = true
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Supply air temperature reset is required.")
      return is_sat_reset_required
    end
  end

  # Determine the airflow limits that govern whether or not an ERV is required.
  # Based on climate zone and % OA.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param pct_oa [Double] percentage of outdoor air
  # @return [Double] the flow rate above which an ERV is required. if nil, ERV is never required.
  def air_loop_hvac_energy_recovery_ventilator_flow_limit(air_loop_hvac, climate_zone, pct_oa)
    # Process climate zone:
    # Moisture regime is not needed for climate zone 8
    climate_zone = climate_zone.split('-')[-1]
    climate_zone = '8' if climate_zone.include?('8')

    # Table 6.5.6.1
    search_criteria = {
      'template' => template,
      'climate_zone' => climate_zone
    }
    energy_recovery_limits = model_find_object(standards_data['energy_recovery'], search_criteria)
    if energy_recovery_limits.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.ashrae_90_1_2010.AirLoopHVAC', "Cannot find energy recovery limits for template '#{template}', climate zone '#{climate_zone}', assuming no energy recovery required.")
      return nil
    end

    if pct_oa < 0.2
      erv_cfm = nil
    elsif pct_oa >= 0.2 && pct_oa < 0.3
      erv_cfm = energy_recovery_limits['percent_oa_20_to_30']
    elsif pct_oa >= 0.3 && pct_oa < 0.4
      erv_cfm = energy_recovery_limits['percent_oa_30_to_40']
    elsif pct_oa >= 0.4 && pct_oa < 0.5
      erv_cfm = energy_recovery_limits['percent_oa_40_to_50']
    elsif pct_oa >= 0.5 && pct_oa < 0.6
      erv_cfm = energy_recovery_limits['percent_oa_50_to_60']
    elsif pct_oa >= 0.6 && pct_oa < 0.7
      erv_cfm = energy_recovery_limits['percent_oa_60_to_70']
    elsif pct_oa >= 0.7 && pct_oa < 0.8
      erv_cfm = energy_recovery_limits['percent_oa_70_to_80']
    elsif pct_oa >= 0.8
      erv_cfm = energy_recovery_limits['percent_oa_greater_than_80']
    end

    return erv_cfm
  end
end
