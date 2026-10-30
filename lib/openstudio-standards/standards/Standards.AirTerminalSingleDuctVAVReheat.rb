class Standard
  # @!group AirTerminalSingleDuctVAVReheat

  # Set the minimum damper position based on OA rate of the space and the template.
  # Zones with low OA per area get lower initial guesses.
  # Final position will be adjusted upward as necessary by Standards.AirLoopHVAC.adjust_minimum_vav_damper_positions
  #
  # EnergyPlus enforces only the input its Zone Minimum Air Flow Input Method selects - the
  # constant fraction under 'Constant', the fixed rate under 'FixedFlowRate' - and warns
  # that the other is ignored. There is no larger-of-the-two behavior. So when a zone
  # minimum OA rate is supplied, this compares it against the damper-position minimum using
  # the terminal's design flow (available once a sizing run has been done, which is how the
  # baseline path calls this) and sets the method so the larger one is the one EnergyPlus
  # enforces. Without a design flow to compare against, the OA rate wins the method, since
  # a supplied ventilation floor that is silently ignored is the worse failure.
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @param zone_min_oa [Double] the zone outdoor air flow rate, in m^3/s.
  #   If supplied, the terminal minimum is the larger of this and the minimum damper
  #   position, imposed through the input method EnergyPlus will actually read.
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
    unless zone_min_oa.nil?
      air_terminal_single_duct_vav_reheat.setFixedMinimumAirFlowRate(zone_min_oa)

      max_flow = air_terminal_single_duct_vav_reheat.maximumAirFlowRate
      max_flow = air_terminal_single_duct_vav_reheat.autosizedMaximumAirFlowRate unless max_flow.is_initialized
      if !max_flow.is_initialized || (min_damper_position * max_flow.get) < zone_min_oa
        air_terminal_single_duct_vav_reheat.setZoneMinimumAirFlowInputMethod('FixedFlowRate')
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirTerminalSingleDuctVAVReheat', "For #{air_terminal_single_duct_vav_reheat.name}: the zone minimum OA of #{zone_min_oa.round(4)} m^3/s governs; using the FixedFlowRate input method.")
      else
        air_terminal_single_duct_vav_reheat.setZoneMinimumAirFlowInputMethod('Constant')
      end
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
