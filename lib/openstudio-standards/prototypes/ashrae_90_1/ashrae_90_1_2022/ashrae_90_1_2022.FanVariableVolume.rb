class ASHRAE9012022 < ASHRAE901
  # @!group FanVariableVolume

  # Determine the prototype fan pressure rise for a variable volume fan on an AirLoopHVAC based on system airflow.
  # Defaults to the logic from ASHRAE 90.1-2004 prototypes.
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [Double] pressure rise in inches H20
  def fan_variable_volume_airloop_fan_pressure_rise(fan_variable_volume)
    # Get the max flow rate from the fan.
    maximum_flow_rate_m3_per_s = nil
    if fan_variable_volume.maximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan_variable_volume.maximumFlowRate.get
    elsif fan_variable_volume.autosizedMaximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan_variable_volume.autosizedMaximumFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.FanVariableVolume', "For #{fan_variable_volume.name} max flow rate is not available, cannot apply prototype assumptions.")
      return false
    end

    # Convert max flow rate to cfm
    maximum_flow_rate_cfm = OpenStudio.convert(maximum_flow_rate_m3_per_s, 'm^3/s', 'cfm').get

    # Determine the pressure rise
    pressure_rise_in_h2o = if maximum_flow_rate_cfm < 4648
                             4.0
                           else # Over 7,437 cfm
                             5.58
                           end

    return pressure_rise_in_h2o
  end
end
