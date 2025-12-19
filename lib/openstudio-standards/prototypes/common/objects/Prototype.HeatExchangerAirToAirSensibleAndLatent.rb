class Standard
  # @!group HeatExchangerAirToAirSensibleAndLatent

  # Default fan efficiency assumption for the prm added fan power
  #
  # @return [Double] default fan efficiency
  def heat_exchanger_air_to_air_sensible_and_latent_prototype_default_fan_efficiency
    default_fan_efficiency = 0.5
    return default_fan_efficiency
  end

  # Sets the motor power to account for the extra fan energy from the increase in fan total static pressure
  #
  # @return [Boolean] returns true if successful, false if not
  def heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_nominal_electric_power(heat_exchanger_air_to_air_sensible_and_latent)
    # Get the nominal supply air flow rate
    supply_air_flow_m3_per_s = nil
    if heat_exchanger_air_to_air_sensible_and_latent.nominalSupplyAirFlowRate.is_initialized
      supply_air_flow_m3_per_s = heat_exchanger_air_to_air_sensible_and_latent.nominalSupplyAirFlowRate.get
    elsif heat_exchanger_air_to_air_sensible_and_latent.autosizedNominalSupplyAirFlowRate.is_initialized
      supply_air_flow_m3_per_s = heat_exchanger_air_to_air_sensible_and_latent.autosizedNominalSupplyAirFlowRate.get
    else
      # Get the min OA flow rate from the OA
      # system if the ERV was not on the system during sizing.
      # This prevents us from having to perform a second sizing run.
      controller_oa = nil
      oa_system = nil
      # Get the air loop
      air_loop = heat_exchanger_air_to_air_sensible_and_latent.airLoopHVAC
      if air_loop.empty?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.HeatExchangerAirToAirSensibleAndLatent', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}, cannot get the air loop and therefore cannot get the min OA flow.")
        return false
      end
      air_loop = air_loop.get
      # Get the OA system
      if air_loop.airLoopHVACOutdoorAirSystem.is_initialized
        oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
        controller_oa = oa_system.getControllerOutdoorAir
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.HeatExchangerAirToAirSensibleAndLatent', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}, cannot find the min OA flow because it has no OA intake.")
        return false
      end
      # Get the min OA flow rate from the OA
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        supply_air_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        supply_air_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.HeatExchangerAirToAirSensibleAndLatent', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}, ERV minimum OA flow rate is not available, cannot apply prototype nominal power assumption.")
        return false
      end
    end

    # Convert the flow rate to cfm
    supply_air_flow_cfm = OpenStudio.convert(supply_air_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Calculate the motor power for the rotary wheel per:
    # Power (W) = (Nominal Supply Air Flow Rate (CFM) * 0.3386) + 49.5
    # power = (supply_air_flow_cfm * 0.3386) + 49.5

    # Calculate the motor power for the rotary wheel per:
    # Power (W) = (Minimum Outdoor Air Flow Rate (m^3/s) * 212.5 / 0.5) + (Minimum Outdoor Air Flow Rate (m^3/s) * 162.5 / 0.5) + 50
    # This power is largely the added fan power from the extra static pressure drop from the enthalpy wheel.
    # It is included as motor power so it is only added when the enthalpy wheel is active, rather than a universal increase to the fan total static pressure.
    # From p.96 of https://www.pnnl.gov/main/publications/external/technical_reports/PNNL-20405.pdf
    default_fan_efficiency = heat_exchanger_air_to_air_sensible_and_latent_prototype_default_fan_efficiency
    power = (supply_air_flow_m3_per_s * 212.5 / default_fan_efficiency) + (supply_air_flow_m3_per_s * 0.9 * 162.5 / default_fan_efficiency) + 50
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.HeatExchangerAirToAirSensibleAndLatent', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}, ERV power is calculated to be #{power.round} W, based on a min OA flow of #{supply_air_flow_cfm.round} cfm.  This power represents mostly the added fan energy from the extra static pressure, and is active only when the ERV is operating.")

    # Set the power for the HX
    heat_exchanger_air_to_air_sensible_and_latent.setNominalElectricPower(power)

    return true
  end

  # Sets the minimum effectiveness of the heat exchanger per the DOE prototype assumptions,
  # which assume that an enthalpy wheel is used, which exceeds the 50% effectiveness minimum actually defined by 90.1.
  #
  # @param heat_exchanger_air_to_air_sensible_and_latent [OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent] hx
  # @return [Boolean] returns true if successful, false if not
  def heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency(heat_exchanger_air_to_air_sensible_and_latent)
    if heat_exchanger_air_to_air_sensible_and_latent.model.version < OpenStudio::VersionString.new('3.8.0')
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100HeatingAirFlow(0.7)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100HeatingAirFlow(0.6)
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75HeatingAirFlow(0.7)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75HeatingAirFlow(0.6)
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100CoolingAirFlow(0.75)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100CoolingAirFlow(0.6)
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75CoolingAirFlow(0.75)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75CoolingAirFlow(0.6)
    else
      values = Hash.new{|hash, key| hash[key] = Hash.new}
      values['Sensible Heating'][0.75] = 0.7
      values['Sensible Heating'][1.0] = 0.7
      values['Latent Heating'][0.75] = 0.6
      values['Latent Heating'][1.0] = 0.6
      values['Sensible Cooling'][0.75] = 0.75
      values['Sensible Cooling'][1.0] = 0.75
      values['Latent Cooling'][0.75] = 0.6
      values['Latent Cooling'][1.0] = 0.6
      OpenstudioStandards::HVAC.heat_exchanger_air_to_air_set_effectiveness_values(heat_exchanger_air_to_air_sensible_and_latent, defaults: false, values: values)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HeatExchangerAirToAirSensibleAndLatent', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}: Changed sensible and latent effectiveness to ~70% per DOE Prototype assumptions for an enthalpy wheel.")

    return true
  end

  # Set sensible and latent effectiveness at 100 and 75 heating and cooling airflow;
  # The values are calculated by using ERR, which is introduced in 90.1-2016 Addendum CE
  #
  # This function is only used for nontransient dwelling units (Mid-rise and High-rise Apartment)
  # @param heat_exchanger_air_to_air_sensible_and_latent [OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent] heat exchanger air to air sensible and latent
  # @param enthalpy_recovery_ratio [String] enthalpy recovery ratio
  # @param design_conditions [String] enthalpy recovery ratio design conditions: 'heating' or 'cooling'
  # @param climate_zone [String] climate zone
  def heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency_enthalpy_recovery_ratio(heat_exchanger_air_to_air_sensible_and_latent, enthalpy_recovery_ratio, design_conditions, climate_zone)
    # Assumed to be sensible and latent at all flow
    if enthalpy_recovery_ratio.nil?
      full_htg_sens_eff = 0.0
      full_htg_lat_eff = 0.0
      part_htg_sens_eff = 0.0
      part_htg_lat_eff = 0.0
      full_cool_sens_eff = 0.0
      full_cool_lat_eff = 0.0
      part_cool_sens_eff = 0.0
      part_cool_lat_eff = 0.0
    else
      enthalpy_recovery_ratio = enthalpy_recovery_ratio_design_to_typical_adjustment(enthalpy_recovery_ratio, climate_zone)
      full_htg_sens_eff, full_htg_lat_eff, part_htg_sens_eff, part_htg_lat_eff, full_cool_sens_eff, full_cool_lat_eff, part_cool_sens_eff, part_cool_lat_eff = heat_exchanger_air_to_air_sensible_and_latent_enthalpy_recovery_ratio_to_effectiveness(enthalpy_recovery_ratio, design_conditions)
    end
    if heat_exchanger_air_to_air_sensible_and_latent.model.version < OpenStudio::VersionString.new('3.8.0')
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100HeatingAirFlow(full_htg_sens_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100HeatingAirFlow(full_htg_lat_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100CoolingAirFlow(full_cool_sens_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100CoolingAirFlow(full_cool_lat_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75HeatingAirFlow(part_htg_sens_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75HeatingAirFlow(part_htg_lat_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75CoolingAirFlow(part_cool_sens_eff)
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75CoolingAirFlow(part_cool_lat_eff)
    else
      values = Hash.new{|hash, key| hash[key] = Hash.new}
      values['Sensible Heating'][0.75] = part_htg_sens_eff
      values['Sensible Heating'][1.0] = full_htg_sens_eff
      values['Latent Heating'][0.75] = part_htg_lat_eff
      values['Latent Heating'][1.0] = full_htg_lat_eff
      values['Sensible Cooling'][0.75] = part_cool_sens_eff
      values['Sensible Cooling'][1.0] = full_cool_sens_eff
      values['Latent Cooling'][0.75] = part_cool_lat_eff
      values['Latent Cooling'][1.0] = full_cool_lat_eff
      OpenstudioStandards::HVAC.heat_exchanger_air_to_air_set_effectiveness_values(heat_exchanger_air_to_air_sensible_and_latent, defaults: false, values: values)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HeatExchangerSensLat', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}: Set sensible and latent effectiveness calculated by using Enthalpy Recovery Ratio.")
    return true
  end
end
