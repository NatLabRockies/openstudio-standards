# A variety of fan calculation methods that are the same regardless of fan type.
# These methods are available to FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
module Fan
  # @!group Fan

  # Applies the minimum motor efficiency for this fan based on the motor's brake horsepower.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param allowed_bhp [Double] allowable brake horsepower
  # @return [Boolean] returns true if successful, false if not
  def fan_apply_standard_minimum_motor_efficiency(fan, allowed_bhp)
    # Find the motor efficiency
    motor_eff, nominal_hp = fan_standard_minimum_motor_efficiency_and_size(fan, allowed_bhp)

    # Change the motor efficiency
    # but preserve the existing fan impeller
    # efficiency.
    fan_change_motor_efficiency(fan, motor_eff)

    # Calculate the total motor HP
    motor_hp = fan_motor_horsepower(fan)

    # Exception for small fans, including
    # zone exhaust, fan coil, and fan powered terminals.
    # In this case, 0.5 HP is used for the lookup.
    if fan_small_fan?(fan)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: motor eff = #{(motor_eff * 100).round(2)}%; assumed to represent several less than 1 HP motors.")
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: motor nameplate = #{nominal_hp}HP, motor eff = #{(motor_eff * 100).round(2)}%.")
    end

    return true
  end

  # Adjust the fan pressure rise to hit the target fan power (W).
  # Keep the fan impeller and motor efficiencies static.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param target_fan_power [Double] the target fan power in watts
  # @return [Boolean] returns true if successful, false if not
  def fan_adjust_pressure_rise_to_meet_fan_power(fan, target_fan_power)
    # Get design supply air flow rate (whether autosized or hard-sized)
    dsn_air_flow_m3_per_s = 0
    dsn_air_flow_m3_per_s = if fan.maximumFlowRate.is_initialized
                              fan.maximumFlowRate.get
                            elsif fan.autosizedMaximumFlowRate.is_initialized
                              fan.autosizedMaximumFlowRate.get
                            end

    # Get the current fan power
    current_fan_power_w = fan_fanpower(fan)

    # Get the current pressure rise (Pa)
    pressure_rise_pa = fan.pressureRise

    # Get the total fan efficiency
    fan_total_eff = fan.fanEfficiency

    # Calculate the new fan pressure rise (Pa)
    new_pressure_rise_pa = target_fan_power * fan_total_eff / dsn_air_flow_m3_per_s
    new_pressure_rise_in_h2o = OpenStudio.convert(new_pressure_rise_pa, 'Pa', 'inH_{2}O').get

    # Set the new pressure rise
    fan.setPressureRise(new_pressure_rise_pa)

    # Calculate the new power
    new_power_w = fan_fanpower(fan)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: pressure rise = #{new_pressure_rise_in_h2o.round(1)} in w.c., power = #{fan_motor_horsepower(fan).round(2)}HP.")

    return true
  end

  # Determines the design fan flow (m3/s)
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] design fan flow
  def fan_design_air_flow(fan)
    # Get design supply air flow rate (whether autosized or hard-sized)
    dsn_air_flow_m3_per_s = if fan.to_FanZoneExhaust.empty?
                              if fan.maximumFlowRate.is_initialized
                                fan.maximumFlowRate.get
                              elsif fan.autosizedMaximumFlowRate.is_initialized
                                fan.autosizedMaximumFlowRate.get
                              else
                                OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "The maximum flow rate for fan '#{fan.name}' was neither specified nor set to Autosize.")
                              end
                            else
                              if fan.maximumFlowRate.is_initialized
                                fan.maximumFlowRate.get
                              else
                                OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "The maximum flow rate for exhaust fan '#{fan.name}' was not specified.")
                              end
                            end
    return dsn_air_flow_m3_per_s
  end

  # Determines the fan power (W) based on
  # flow rate, pressure rise, and total fan efficiency(impeller eff * motor eff)
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] fan power in watts
  def fan_fanpower(fan)
    # Get the total fan efficiency,
    # which in E+ includes both motor and
    # impeller efficiency.
    fan_total_eff = fan.fanEfficiency

    # Get the pressure rise (Pa)
    pressure_rise_pa = fan.pressureRise

    # Calculate the fan power (W)
    fan_power_w = pressure_rise_pa * fan_design_air_flow(fan) / fan_total_eff

    return fan_power_w
  end

  # Determines the brake horsepower of the fan based on fan power and fan motor efficiency.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] brake horsepower
  def fan_brake_horsepower(fan)
    # Get the fan motor efficiency
    existing_motor_eff = 0.7
    if fan.to_FanZoneExhaust.empty?
      existing_motor_eff = fan.motorEfficiency
    end

    # Get the fan power (W)
    fan_power_w = fan_fanpower(fan)

    # Calculate the brake horsepower (bhp)
    fan_bhp = fan_power_w * existing_motor_eff / 746

    return fan_bhp
  end

  # Determines the horsepower of the fan motor, including motor efficiency and fan impeller efficiency.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] motor horsepower
  def fan_motor_horsepower(fan)
    # Get the fan power
    fan_power_w = fan_fanpower(fan)

    # Convert to HP
    fan_hp = fan_power_w / 745.7 # 745.7 W/HP

    return fan_hp
  end

  # Changes the fan motor efficiency and also the fan total efficiency
  # at the same time, preserving the impeller efficiency.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param motor_eff [Double] motor efficiency (0.0 to 1.0)
  # @return [Boolean] returns true if successful, false if not
  def fan_change_motor_efficiency(fan, motor_eff)
    # Calculate the existing impeller efficiency
    existing_motor_eff = 0.7
    if fan.to_FanZoneExhaust.empty?
      existing_motor_eff = fan.motorEfficiency
    end
    existing_total_eff = fan.fanEfficiency
    existing_impeller_eff = existing_total_eff / existing_motor_eff

    # Calculate the new total efficiency
    new_total_eff = motor_eff * existing_impeller_eff

    # Set the revised motor and total fan efficiencies
    if fan.to_FanZoneExhaust.is_initialized
      fan.setFanEfficiency(new_total_eff)
    else
      fan.setFanEfficiency(new_total_eff)
      fan.setMotorEfficiency(motor_eff)
    end
    return true
  end

  # Changes the fan impeller efficiency and also the fan total efficiency
  # at the same time, preserving the motor efficiency.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param impeller_eff [Double] impeller efficiency (0.0 to 1.0)
  # @return [Boolean] returns true if successful, false if not
  def fan_change_impeller_efficiency(fan, impeller_eff)
    # Get the existing motor efficiency
    existing_motor_eff = 0.7
    if fan.to_FanZoneExhaust.empty?
      existing_motor_eff = fan.motorEfficiency
    end

    # Calculate the new total efficiency
    new_total_eff = existing_motor_eff * impeller_eff

    # Set the revised motor and total fan efficiencies
    fan.setFanEfficiency(new_total_eff)
    return true
  end

  # Determines the baseline fan impeller efficiency based on the specified fan type.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] impeller efficiency (0.0 to 1.0)
  # @todo Add fan type to data model and modify this method
  def fan_baseline_impeller_efficiency(fan)
    # Assume that the fan efficiency is 65% for normal fans
    # and 55% for small fans (like exhaust fans).
    # @todo add fan type to fan data model
    # and infer impeller efficiency from that?
    # or do we always assume a certain type of
    # fan impeller for the baseline system?
    # @todo check COMNET and T24 ACM and PNNL 90.1 doc
    fan_impeller_eff = 0.65

    if fan_small_fan?(fan)
      fan_impeller_eff = 0.55
    end

    return fan_impeller_eff
  end

  # Determines the minimum fan motor efficiency and nominal size for a given motor bhp.
  # This should be the total brake horsepower with any desired safety factor already included.
  # This method picks the next nominal motor category larger than the required brake horsepower,
  # and the efficiency is based on that size.
  # For example, if the bhp = 6.3, the nominal size will be 7.5HP and the efficiency
  # for 90.1-2010 will be 91.7% from Table 10.8B.
  # This method assumes 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)
    fan_motor_eff = 0.85
    # Calculate the allowed fan brake horsepower
    # per method used in PNNL prototype buildings.
    # Assumes that the fan brake horsepower is 90%
    # of the fan nameplate rated motor power.
    # Source: Thornton et al. (2011), Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010, Section 4.5.4
    nominal_hp = motor_bhp * 1.1

    # Don't attempt to look up motor efficiency
    # for zero-hp fans, which may occur when there is no
    # airflow required for a particular system, typically
    # heated-only spaces with high internal gains
    # and no OA requirements such as elevator shafts.
    return [fan_motor_eff, 0] if motor_bhp < 0.0001

    # Lookup the minimum motor efficiency
    motors = standards_data['motors']

    # Assuming all fan motors are 4-pole ODP
    search_criteria = {
      'template' => template,
      'number_of_poles' => 4.0,
      'type' => 'Enclosed'
    }

    # Exception for small fans, including
    # zone exhaust, fan coil, and fan powered terminals.
    # In this case, use the 0.5 HP for the lookup.
    if fan_small_fan?(fan)
      nominal_hp = 0.5

      # Get the efficiency based on the nominal horsepower
      motor_type = motor_type(nominal_hp)
      motor_properties = motor_fractional_hp_efficiencies(nominal_hp, motor_type = motor_type)

      if motor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
        return [fan_motor_eff, nominal_hp]
      end
    else
      # Use the efficiency largest motor efficiency when BHP is greater than the largest size for which a requirement is provided
      data = model_find_objects(motors, search_criteria)
      maximum_capacity = model_find_maximum_value(data, 'maximum_capacity')
      if motor_bhp > maximum_capacity
        motor_bhp = maximum_capacity
      end

      motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = Date.today, area = nil, num_floors = nil, fan_motor_bhp = motor_bhp)
      if motor_properties.nil?
        # Retry without the date
        motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = nil, area = nil, num_floors = nil, fan_motor_bhp = motor_bhp)
        if motor_properties.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
          return [fan_motor_eff, nominal_hp]
        end
      end
    end

    nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    fan_motor_eff = motor_properties['nominal_full_load_efficiency']

    return [fan_motor_eff, nominal_hp]
  end

  # Zone exhaust fans, fan coil unit fans, and powered VAV terminal fans all count
  # as small fans and get different impeller efficiencies and motor efficiencies than other fans
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Boolean] returns true if it is a small fan, false if not
  def fan_small_fan?(fan)
    is_small = false

    # Exhaust fan
    if fan.to_FanZoneExhaust.is_initialized
      is_small = true
    # Fan coil unit, unit heater, PTAC, PTHP, VRF terminals, WSHP, ERV
    elsif fan.containingZoneHVACComponent.is_initialized
      zone_hvac = fan.containingZoneHVACComponent.get
      if zone_hvac.to_ZoneHVACFourPipeFanCoil.is_initialized
        is_small = true
      # elsif zone_hvac.to_ZoneHVACUnitHeater.is_initialized
      #   is_small = true
      elsif zone_hvac.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized || zone_hvac.to_ZoneHVACPackagedTerminalHeatPump.is_initialized || zone_hvac.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized || zone_hvac.to_ZoneHVACWaterToAirHeatPump.is_initialized || zone_hvac.to_ZoneHVACEnergyRecoveryVentilator.is_initialized
        is_small = true
      end
    # Powered VAV terminal
    elsif fan.containingHVACComponent.is_initialized
      zone_hvac = fan.containingHVACComponent.get
      if zone_hvac.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized || zone_hvac.to_AirTerminalSingleDuctSeriesPIUReheat.is_initialized
        is_small = true
      end
    end

    return is_small
  end

  # Find the actual rated fan power per flow (W/CFM) by querying the sql file
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] rated power consumption per flow in watters per cfm, W*min/ft^3
  def fan_rated_w_per_cfm(fan)
    # Get design power (whether autosized or hard-sized)
    rated_power_w = fan_fanpower(fan)

    if fan.maximumFlowRate.is_initialized
      max_m3_per_s = fan.ratedFlowRate.get
    elsif fan.autosizedMaximumFlowRate.is_initialized
      max_m3_per_s = fan.autosizedMaximumFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find fan Maximum Flow Rate, cannot determine w per cfm correctly.")
      return false
    end

    rated_w_per_m3s = rated_power_w / max_m3_per_s

    rated_w_per_cfm = OpenStudio.convert(rated_w_per_m3s, 'W*s/m^3', 'W*min/ft^3').get

    return rated_w_per_cfm
  end
end
