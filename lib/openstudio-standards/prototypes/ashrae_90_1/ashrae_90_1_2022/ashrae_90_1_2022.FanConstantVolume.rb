class ASHRAE9012022 < ASHRAE901
  # @!group FanConstantVolume

  # Determine the prototype fan pressure rise for a constant volume fan on an AirLoopHVAC based on system airflow.
  # Defaults to the logic from ASHRAE 90.1-2004 prototypes.
  #
  # @param fan_constant_volume [OpenStudio::Model::FanConstantVolume] constant volume fan object
  # @return [Double] pressure rise in inches H20
  def fan_constant_volume_airloop_fan_pressure_rise(fan_constant_volume)
    # Get the max flow rate from the fan.
    maximum_flow_rate_m3_per_s = nil
    if fan_constant_volume.maximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan_constant_volume.maximumFlowRate.get
    elsif fan_constant_volume.autosizedMaximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan_constant_volume.autosizedMaximumFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.FanConstantVolume', "For #{fan_constant_volume.name} max flow rate is not available, cannot apply prototype assumptions.")
      return false
    end

    # Convert max flow rate to cfm
    maximum_flow_rate_cfm = OpenStudio.convert(maximum_flow_rate_m3_per_s, 'm^3/s', 'cfm').get

    # Determine the pressure rise
    pressure_rise_in_h2o = if maximum_flow_rate_cfm < 7437
                             2.5
                           else # Over 7,437 cfm
                             4.09
                           end

    return pressure_rise_in_h2o
  end
end
