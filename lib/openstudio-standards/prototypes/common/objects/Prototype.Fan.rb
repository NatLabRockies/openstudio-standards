# Prototype fan calculation methods that are the same regardless of fan type.
# These methods are available to FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
module PrototypeFan
  # @!group Fan

  # Sets the fan motor efficiency using the Prototype
  # model assumptions for fan impeller efficiency,
  # motor type, and a 10% safety factor on brake horsepower.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object of type:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Boolean] returns true if successful, false if not
  def prototype_fan_apply_prototype_fan_efficiency(fan)
    # Do not modify dummy exhaust fans
    return true if fan.name.to_s.downcase.include? 'dummy'

    # Get the max flow rate from the fan.
    maximum_flow_rate_m3_per_s = nil
    if fan.maximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan.maximumFlowRate.get
    elsif fan.autosizedMaximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan.autosizedMaximumFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Fan', "For #{fan.name} max flow rate is not hard sized, cannot apply efficiency standard.")
      return false
    end

    # Convert max flow rate to cfm
    maximum_flow_rate_cfm = OpenStudio.convert(maximum_flow_rate_m3_per_s, 'm^3/s', 'cfm').get

    # Get the pressure rise from the fan
    pressure_rise_pa = fan.pressureRise
    pressure_rise_in_h2o = OpenStudio.convert(pressure_rise_pa, 'Pa', 'inH_{2}O').get

    # Get the default impeller efficiency
    fan_impeller_eff = fan_baseline_impeller_efficiency(fan)

    # Calculate the Brake Horsepower
    brake_hp = (pressure_rise_in_h2o * maximum_flow_rate_cfm) / (fan_impeller_eff * 6356)
    allowed_hp = brake_hp * 1.1 # Per PNNL document
    # @todo add reference
    if allowed_hp > 0.1
      allowed_hp = allowed_hp.round(2) + 0.0001
    elsif allowed_hp < 0.01
      allowed_hp = 0.01
    end

    # Find the motor efficiency
    motor_eff, nominal_hp = fan_standard_minimum_motor_efficiency_and_size(fan, allowed_hp)

    # Calculate the total fan efficiency
    total_fan_eff = fan_impeller_eff * motor_eff

    # Set the total fan efficiency and the motor efficiency
    if fan.to_FanZoneExhaust.is_initialized
      fan.setFanEfficiency(total_fan_eff)
    else
      fan.setFanEfficiency(total_fan_eff)
      fan.setMotorEfficiency(motor_eff)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: allowed_hp = #{allowed_hp.round(2)}HP; motor eff = #{(motor_eff * 100).round(2)}%; total fan eff = #{(total_fan_eff * 100).round}% based on #{maximum_flow_rate_cfm.round} cfm.")

    return true
  end
end
