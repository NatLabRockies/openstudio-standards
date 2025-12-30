class ASHRAE901PRM < Standard
  # @!group ZoneHVACComponent

  # Sets the fan power of zone level HVAC equipment
  # (Fan coils, Unit Heaters, PTACs, PTHPs, VRF Terminals, WSHPs, ERVs)
  # based on the W/cfm specified in the standard.
  #
  # @return [Boolean] returns true if successful, false if not
  def zone_hvac_component_apply_prm_baseline_fan_power(zone_hvac_component)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.ashrae_90_1_prm.ZoneHVACComponent', "Setting fan power for #{zone_hvac_component.name}.")

    # Convert this to the actual class type
    zone_hvac = if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
                  zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
                elsif zone_hvac_component.to_ZoneHVACUnitHeater.is_initialized
                  zone_hvac_component.to_ZoneHVACUnitHeater.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
                elsif zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
                  zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
                elsif zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.get
                elsif zone_hvac_component.to_ZoneHVACEnergyRecoveryVentilator.is_initialized
                  zone_hvac_component.to_ZoneHVACEnergyRecoveryVentilator.get
                end

    # Do nothing for other types of zone HVAC equipment
    return false if zone_hvac.nil?

    # Do nothing if zone hav component isn't assigned to thermal zone
    return false unless zone_hvac.thermalZone.is_initialized

    # Get baseline system type
    system_type = zone_hvac.thermalZone.get.additionalProperties.getFeatureAsString('baseline_system_type').get

    # Get non-mechanically cooled flag
    if zone_hvac.thermalZone.get.additionalProperties.hasFeature('non_mechanically_cooled')
      nmc_flag = zone_hvac.thermalZone.get.additionalProperties.getFeatureAsString('non_mechanically_cooled')
    else
      nmc_flag = false
    end

    # Get the fan
    fan = if zone_hvac.supplyAirFan.to_FanConstantVolume.is_initialized
            zone_hvac.supplyAirFan.to_FanConstantVolume.get
          elsif zone_hvac.supplyAirFan.to_FanVariableVolume.is_initialized
            zone_hvac.supplyAirFan.to_FanVariableVolume.get
          elsif zone_hvac.supplyAirFan.to_FanOnOff.is_initialized
            zone_hvac.supplyAirFan.to_FanOnOff.get
          elsif zone_hvac.supplyAirFan.to_FanSystemModel.is_initialized
            zone_hvac.supplyAirFan.to_FanSystemModel.get
          end

    if system_type == 'SZ_CV' # System 12, 13
      # Get design supply air flow rate (whether autosized or hard-sized)
      dsn_air_flow_m3_per_s = 0
      dsn_air_flow_cfm = 0
      if fan.maximumFlowRate.is_initialized
        dsn_air_flow_m3_per_s = fan.maximumFlowRate.get
      elsif fan.isMaximumFlowRateAutosized
        dsn_air_flow_m3_per_s = fan.autosizedMaximumFlowRate.get
      end
      dsn_air_flow_cfm = OpenStudio.convert(dsn_air_flow_m3_per_s, 'm^3/s', 'cfm').get

      # Determine allowable fan BHP and power
      allowable_fan_bhp = (0.00094 * dsn_air_flow_cfm) + thermal_zone_get_fan_power_limitations(zone_hvac.thermalZone.get, false)
      fan_apply_standard_minimum_motor_efficiency(fan, allowable_fan_bhp)
      allowable_power_w = (allowable_fan_bhp * 746) / fan.motorEfficiency

      # Modify fan pressure rise to match target fan power
      fan_adjust_pressure_rise_to_meet_fan_power(fan, allowable_power_w)
    else # System 1, 2
      # Determine the W/cfm
      fan_efficacy_w_per_cfm = 0.0
      case system_type
      when 'PTAC', 'PTHP'
        fan_efficacy_w_per_cfm = 0.3 # System 9, 10
      when 'Gas_Furnace', 'Electric_Furnace'
        # Zone heater cannot provide cooling
        if nmc_flag && !zone_hvac_component.to_ZoneHVACUnitHeater.is_initialized
          fan_efficacy_w_per_cfm = 0.054
        else
          fan_efficacy_w_per_cfm = 0.3
        end
      else OpenStudio.logFree(OpenStudio::Error, 'openstudio.ashrae_90_1_prm.ZoneHVACComponent', 'Zone HVAC system fan power lookup missing.')
      end

      # Convert efficacy to metric
      fan_efficacy_w_per_m3_per_s = OpenStudio.convert(fan_efficacy_w_per_cfm, 'm^3/s', 'cfm').get

      # Get the maximum flow rate through the fan
      max_air_flow_rate = nil
      if fan.maximumFlowRate.is_initialized
        max_air_flow_rate = fan.maximumFlowRate.get
      elsif fan.autosizedMaximumFlowRate.is_initialized
        max_air_flow_rate = fan.autosizedMaximumFlowRate.get
      end
      max_air_flow_rate_cfm = OpenStudio.convert(max_air_flow_rate, 'm^3/s', 'ft^3/min').get

      # Set the impeller efficiency
      fan_change_impeller_efficiency(fan, fan_baseline_impeller_efficiency(fan))

      # Get fan BHP
      fan_bhp = OpenstudioStandards::HVAC.fan_brake_horsepower(fan)

      # Set the motor efficiency, preserving the impeller efficiency.
      # For zone HVAC fans, a bhp lookup of 0.5bhp is always used because
      # they are assumed to represent a series of small fans in reality.
      fan_apply_standard_minimum_motor_efficiency(fan, fan_bhp)

      # Calculate a new pressure rise to hit the target W/cfm
      fan_tot_eff = fan.fanEfficiency
      fan_rise_new_pa = fan_efficacy_w_per_m3_per_s * fan_tot_eff
      fan.setPressureRise(fan_rise_new_pa)

      # Calculate the newly set efficacy
      fan_power_new_w = fan_rise_new_pa * max_air_flow_rate / fan_tot_eff
      fan_efficacy_new_w_per_cfm = fan_power_new_w / max_air_flow_rate_cfm
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.ashrae_90_1_prm.ZoneHVACComponent', "For #{zone_hvac_component.name}: fan efficacy set to #{fan_efficacy_new_w_per_cfm.round(2)} W/cfm.")
    end
    return true
  end

  # Default occupancy fraction threshold for determining if the spaces served by the zone hvac are occupied
  #
  # @return [Double] unoccupied threshold
  def zone_hvac_unoccupied_threshold
    # Use 10% based on PRM-RM
    return 0.10
  end
end
