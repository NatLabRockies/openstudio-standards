class ACM179dASHRAE9012007
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
    # If specified, set the MDP as the larger of the two
    unless zone_min_oa.nil?
      min_oa_damp_position = [zone_min_oa / air_terminal_single_duct_vav_reheat.autosizedMaximumAirFlowRate.get, min_damper_position].max
      air_terminal_single_duct_vav_reheat.setConstantMinimumAirFlowFraction(min_oa_damp_position)
    end

    return min_damper_position
  end
end
