# A variety of pump calculation methods that are the same regardless of pump type.
# These methods are available to PumpConstantSpeed, PumpVariableSpeed
module Pump
  # @!group Pump

  # Set the pressure rise that corresponds to the target power per flow number,
  # given the standard pump efficiency and the default EnergyPlus pump impeller efficiency of 0.78.
  #
  # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
  #   PumpConstantSpeed, PumpVariableSpeed
  # @param target_w_per_gpm [Double] the target power per flow, in W/gpm
  # @return [Boolean] returns true if successful, false if not
  # @author jmarrec
  def pump_apply_prm_pressure_rise_and_motor_efficiency(pump, target_w_per_gpm)
    # Eplus assumes an impeller efficiency of 0.78 to determine the total efficiency
    # http://bigladdersoftware.com/epx/docs/8-4/engineering-reference/component-sizing.html#pump-sizing
    # Rated_Power_Use = Rated_Volume_Flow_Rate * Rated_Pump_Head / Total_Efficiency
    # Rated_Power_Use / Rated_Volume_Flow_Rate =  Rated_Pump_Head / Total_Efficiency
    # Total_Efficiency = Motor_Efficiency * Impeler_Efficiency
    impeller_efficiency = 0.78

    # Get flow rate (whether autosized or hard-sized)
    flow_m3_per_s = 0
    flow_m3_per_s = if pump.to_PumpVariableSpeed.is_initialized || pump.to_PumpConstantSpeed.is_initialized
                      if pump.ratedFlowRate.is_initialized
                        pump.ratedFlowRate.get
                      elsif pump.autosizedRatedFlowRate.is_initialized
                        pump.autosizedRatedFlowRate.get
                      end
                    elsif pump.to_HeaderedPumpsVariableSpeed.is_initialized || pump.to_HeaderedPumpsConstantSpeed.is_initialized
                      if pump.totalRatedFlowRate.is_initialized
                        pump.totalRatedFlowRate.get / pump.numberofPumpsinBank
                      elsif pump.autosizedTotalRatedFlowRate.is_initialized
                        pump.autosizedTotalRatedFlowRate.get / pump.numberofPumpsinBank
                      end
                    end

    flow_gpm = OpenStudio.convert(flow_m3_per_s, 'm^3/s', 'gal/min').get

    # Calculate the target total pump motor power consumption
    target_motor_power_cons_w = target_w_per_gpm * flow_gpm
    target_motor_power_cons_hp = target_motor_power_cons_w / 745.7 # 745.7 W/HP

    # Find the motor efficiency using total power consumption
    # Note that this hp is ~5-10% high because it is being looked
    # up based on the motor consumption, which is always actually higher
    # than the brake horsepower.  This will bound the possible motor efficiency
    # values.  If a motor is just above a nominal size, and the next size
    # down has a lower efficiency value, later motor efficiency setting
    # methods can mess up the W/gpm.  All this nonsense avoids that.
    mot_eff_hi_end, nom_hp_hi_end = pump_standard_minimum_motor_efficiency_and_size(pump, target_motor_power_cons_hp)

    # Calculate the actual brake horsepower using this efficiency
    target_motor_bhp = target_motor_power_cons_hp * mot_eff_hi_end

    # Find the motor efficiency using actual bhp
    mot_eff_lo_end, nom_hp_lo_end = pump_standard_minimum_motor_efficiency_and_size(pump, target_motor_bhp)

    # If the efficiency drops you down into a lower band with
    # a lower efficiency value, use that for the motor efficiency.
    motor_efficiency = [mot_eff_lo_end, mot_eff_hi_end].min
    nominal_hp = [nom_hp_lo_end, nom_hp_hi_end].min

    # Calculate the brake horsepower that was assumed
    target_brake_power_hp = target_motor_power_cons_hp * motor_efficiency

    # Change the motor efficiency
    pump.setMotorEfficiency(motor_efficiency)

    total_efficiency = impeller_efficiency * motor_efficiency

    desired_power_per_m3_s = OpenStudio.convert(target_w_per_gpm, 'W*min/gal', 'W*s/m^3').get

    pressure_rise_pa = desired_power_per_m3_s * total_efficiency
    pressure_rise_ft_h2o = OpenStudio.convert(pressure_rise_pa, 'Pa', 'ftH_{2}O').get

    # Change pressure rise
    pump.setRatedPumpHead(pressure_rise_pa)

    # Report
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Pump', "For #{pump.name}: motor nameplate = #{nominal_hp}HP, motor eff = #{(motor_efficiency * 100).round(2)}%; #{target_w_per_gpm.round} W/gpm translates to a pressure rise of #{pressure_rise_ft_h2o.round(2)} ftH2O.")

    # Calculate the W/gpm for verification
    calculated_w = OpenstudioStandards::HVAC.pump_get_power(pump)

    calculated_w_per_gpm = calculated_w / flow_gpm

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Pump', "For #{pump.name}: calculated W/gpm = #{calculated_w_per_gpm.round(1)}.")

    return true
  end

  # Applies the minimum motor efficiency for this pump based on the motor's brake horsepower.
  #
  # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
  #   PumpConstantSpeed, PumpVariableSpeed
  # @return [Boolean] returns true if successful, false if not
  def pump_apply_standard_minimum_motor_efficiency(pump)
    # Get the horsepower
    bhp = OpenstudioStandards::HVAC.pump_get_brake_horsepower(pump)

    # Find the motor efficiency
    motor_eff, nominal_hp = pump_standard_minimum_motor_efficiency_and_size(pump, bhp)

    # Change the motor efficiency
    pump.setMotorEfficiency(motor_eff)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Pump', "For #{pump.name}: brake hp = #{bhp.round(2)}HP, motor nameplate = #{nominal_hp.round(2)}HP, motor eff = #{(motor_eff * 100).round(2)}%.")

    return true
  end

  # Determines the minimum pump motor efficiency and nominal size
  # for a given motor bhp.  This should be the total brake horsepower with
  # any desired safety factor already included.  This method picks
  # the next nominal motor category larger than the required brake
  # horsepower, and the efficiency is based on that size.  For example,
  # if the bhp = 6.3, the nominal size will be 7.5HP and the efficiency
  # for 90.1-2010 will be 91.7% from Table 10.8B.  This method assumes
  # 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
  #   PumpConstantSpeed, PumpVariableSpeed
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)
    motor_eff = 0.85
    # Calculate the allowed fan brake horsepower
    # per method used in PNNL prototype buildings.
    # Assumes that the fan brake horsepower is 90%
    # of the fan nameplate rated motor power.
    # Source: Thornton et al. (2011), Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010, Section 4.5.4
    nominal_hp = motor_bhp * 1.1

    # Don't attempt to look up motor efficiency
    # for zero-hp pumps (required for circulation-pump-free
    # service water heating systems).
    return [1.0, 0] if motor_bhp < 0.0001 # under 1 watt

    if nominal_hp <= 0.75
      motor_type = motor_type(nominal_hp)
      motor_properties = motor_fractional_hp_efficiencies(nominal_hp, motor_type = motor_type)
    else
      # Lookup the minimum motor efficiency
      motors = standards_data['motors']

      # Assuming all pump motors are 4-pole ODP
      search_criteria = {
        'template' => template,
        'number_of_poles' => 4.0,
        'type' => 'Enclosed'
      }

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
      end
    end

    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Pump', "For #{pump.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
      return [motor_eff, nominal_hp]
    end

    motor_eff = motor_properties['nominal_full_load_efficiency']
    nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    return [motor_eff, nominal_hp]
  end
end
