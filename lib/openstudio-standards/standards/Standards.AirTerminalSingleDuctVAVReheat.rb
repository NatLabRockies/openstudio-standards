class Standard
  # @!group AirTerminalSingleDuctVAVReheat

  # Set the minimum damper position based on OA rate of the space and the template.
  # Zones with low OA per area get lower initial guesses.
  # Final position will be adjusted upward as necessary by Standards.AirLoopHVAC.adjust_minimum_vav_damper_positions
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @param zone_min_oa [Double] the zone outdoor air flow rate, in m^3/s.
  #   If supplied, this will be set as a minimum limit in addition to the minimum
  #   damper position.  EnergyPlus will use the larger of the two values during sizing.
  # @param has_ddc [Boolean] whether or not there is DDC control of the VAV terminal,
  #   which impacts the minimum damper position requirement.
  # @return [Boolean] returns true if successful, false if not
  # @todo remove exception where older vintages don't have minimum positions adjusted.
  def air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(air_terminal_single_duct_vav_reheat, zone_min_oa = nil, has_ddc = true)
    # Minimum damper position
    min_damper_position = air_terminal_single_duct_vav_reheat_minimum_damper_position(air_terminal_single_duct_vav_reheat, has_ddc)
    air_terminal_single_duct_vav_reheat.setConstantMinimumAirFlowFraction(min_damper_position)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirTerminalSingleDuctVAVReheat', "For #{air_terminal_single_duct_vav_reheat.name}: set minimum damper position to #{min_damper_position}.")

    # Minimum OA flow rate
    # If specified, will also add this limit
    # and the larger of the two will be used
    # for sizing.
    unless zone_min_oa.nil?
      air_terminal_single_duct_vav_reheat.setFixedMinimumAirFlowRate(zone_min_oa)
    end

    return true
  end

  # Specifies the minimum damper position for VAV dampers.
  # Defaults to 30%
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @param has_ddc [Boolean] whether or not there is DDC control of the VAV terminal in question
  # @return [Double] minimum damper position
  def air_terminal_single_duct_vav_reheat_minimum_damper_position(air_terminal_single_duct_vav_reheat, has_ddc = false)
    min_damper_position = 0.3
    return min_damper_position
  end

  # Sets the capacity of the reheat coil based on the minimum flow fraction, and the maximum flow rate.
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_vav_reheat_set_heating_cap(air_terminal_single_duct_vav_reheat)
    flow_rate_fraction = 0.0
    if air_terminal_single_duct_vav_reheat.constantMinimumAirFlowFraction.is_initialized
      flow_rate_fraction = air_terminal_single_duct_vav_reheat.constantMinimumAirFlowFraction.get
    end
    return false unless air_terminal_single_duct_vav_reheat.reheatCoil.to_CoilHeatingWater.is_initialized

    reheat_coil = air_terminal_single_duct_vav_reheat.reheatCoil.to_CoilHeatingWater.get
    if reheat_coil.autosizedRatedCapacity.to_f < 1.0e-6
      cap = 1.2 * 1000.0 * flow_rate_fraction * air_terminal_single_duct_vav_reheat.autosizedMaximumAirFlowRate.to_f * (18.0 - 13.0)
      reheat_coil.setPerformanceInputMethod('NominalCapacity')
      reheat_coil.setRatedCapacity(cap)
      air_terminal_single_duct_vav_reheat.setMaximumReheatAirTemperature(18.0)
    end
    return true
  end
end
