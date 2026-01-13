class Standard
  # @!group AirTerminalSingleDuctParallelPIUReheat

  # Sets the fan power of a PIU fan based on the W/cfm specified in the standard.
  #
  # @param air_terminal_single_duct_parallel_piu_reheat [OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat] air terminal object
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_parallel_piu_reheat_apply_prm_baseline_fan_power(air_terminal_single_duct_parallel_piu_reheat)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirTerminalSingleDuctParallelPIUReheat', "Setting PIU fan power for #{air_terminal_single_duct_parallel_piu_reheat.name}.")

    # Determine the fan sizing flow rate, min flow rate,
    # and W/cfm
    sec_flow_frac = 0.5
    min_flow_frac = air_terminal_single_duct_parallel_reheat_piu_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat)
    fan_efficacy_w_per_cfm = 0.35

    # Set the fan on flow fraction
    unless air_terminal_single_duct_parallel_piu_reheat_fan_on_flow_fraction.nil?
      air_terminal_single_duct_parallel_piu_reheat.setFanOnFlowFraction(air_terminal_single_duct_parallel_piu_reheat_fan_on_flow_fraction)
    end

    # Convert efficacy to metric
    # 1 cfm = 0.0004719 m^3/s
    fan_efficacy_w_per_m3_per_s = fan_efficacy_w_per_cfm / 0.0004719

    # Get the maximum flow rate through the terminal
    max_primary_air_flow_rate = nil
    if air_terminal_single_duct_parallel_piu_reheat.maximumPrimaryAirFlowRate.is_initialized
      max_primary_air_flow_rate = air_terminal_single_duct_parallel_piu_reheat.maximumPrimaryAirFlowRate.get
    elsif air_terminal_single_duct_parallel_piu_reheat.autosizedMaximumPrimaryAirFlowRate.is_initialized
      max_primary_air_flow_rate = air_terminal_single_duct_parallel_piu_reheat.autosizedMaximumPrimaryAirFlowRate.get
    end

    # Set the max secondary air flow rate
    max_sec_flow_rate_m3_per_s = max_primary_air_flow_rate * sec_flow_frac
    air_terminal_single_duct_parallel_piu_reheat.setMaximumSecondaryAirFlowRate(max_sec_flow_rate_m3_per_s)
    max_sec_flow_rate_cfm = OpenStudio.convert(max_sec_flow_rate_m3_per_s, 'm^3/s', 'ft^3/min').get

    # Set the minimum flow fraction
    air_terminal_single_duct_parallel_piu_reheat.setMinimumPrimaryAirFlowFraction(min_flow_frac)

    # Get the fan
    fan = air_terminal_single_duct_parallel_piu_reheat.fan.to_FanConstantVolume.get

    # Set the impeller efficiency
    fan_change_impeller_efficiency(fan, fan_baseline_impeller_efficiency(fan))

    # Set the motor efficiency, preserving the impeller efficency.
    # For terminal fans, a bhp lookup of 0.5bhp is always used because
    # they are assumed to represent a series of small fans in reality.
    fan_apply_standard_minimum_motor_efficiency(fan, fan_brake_horsepower(fan))

    # Calculate a new pressure rise to hit the target W/cfm
    fan_tot_eff = fan.fanEfficiency
    fan_rise_new_pa = fan_efficacy_w_per_m3_per_s * fan_tot_eff
    fan.setPressureRise(fan_rise_new_pa)

    # Calculate the newly set efficacy
    fan_power_new_w = fan_rise_new_pa * max_sec_flow_rate_m3_per_s / fan_tot_eff
    fan_efficacy_new_w_per_cfm = fan_power_new_w / max_sec_flow_rate_cfm
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirTerminalSingleDuctParallelPIUReheat', "For #{air_terminal_single_duct_parallel_piu_reheat.name}: fan efficacy set to #{fan_efficacy_new_w_per_cfm.round(2)} W/cfm.")

    return true
  end

  # Return the fan on flow fraction for a parallel PIU terminal.
  #
  # When returning nil, the fan on flow fraction will be set to
  # be autosize in the EnergyPlus model; OpenStudio assumes that
  # the default is "autosize". When autosized, this input is set
  # to be the same as the minimum primary air flow fraction which
  # means that the secondary fan will be on when the primary air
  # flow is at the minimum flow fraction.
  #
  # @return [Double] returns nil or a float representing the fraction
  def air_terminal_single_duct_parallel_piu_reheat_fan_on_flow_fraction
    return nil
  end

  # Specifies the minimum primary air flow fraction for PFB boxes.
  #
  # @param air_terminal_single_duct_parallel_piu_reheat [OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat] air terminal object
  # @return [Double] minimum primaru air flow fraction
  def air_terminal_single_duct_parallel_reheat_piu_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat)
    min_primary_airflow_fraction = 0.3
    return min_primary_airflow_fraction
  end

  # Set the minimum primary air flow fraction based on OA rate of the space and the template.
  #
  # @param air_terminal_single_duct_parallel_piu_reheat [OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat] the air terminal object
  # @param zone_min_oa [Double] the zone outdoor air flow rate, in m^3/s.
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_parallel_piu_reheat_apply_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat, zone_min_oa = nil)
    # Minimum primary air flow
    min_primary_airflow_frac = air_terminal_single_duct_parallel_reheat_piu_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat)
    air_terminal_single_duct_parallel_piu_reheat.setMinimumPrimaryAirFlowFraction(min_primary_airflow_frac)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirTerminalSingleDuctParallelPIUReheat', "For #{air_terminal_single_duct_parallel_piu_reheat.name}: set minimum primary air flow fraction to #{min_primary_airflow_frac}.")

    # Minimum OA flow rate
    # If specified, set the primary air flow fraction as
    unless zone_min_oa.nil?
      min_primary_airflow_frac = [min_primary_airflow_frac, zone_min_oa / air_terminal_single_duct_parallel_piu_reheat.autosizedMaximumPrimaryAirFlowRate.get].max
      air_terminal_single_duct_parallel_piu_reheat.setMinimumPrimaryAirFlowFraction(min_primary_airflow_frac)
    end

    return true
  end
end
