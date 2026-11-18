class ASHRAE9012022 < ASHRAE901
  # @!group FanOnOff

  # Determine the prototype fan pressure rise for an on off fan on an AirLoopHVAC or inside a unitary system based on system airflow.
  # Defaults to the logic from ASHRAE 90.1-2004 prototypes.
  #
  # @param fan_on_off [OpenStudio::Model::FanOnOff] on off fan object
  # @return [Double] pressure rise in inches H20
  def fan_on_off_airloop_or_unitary_fan_pressure_rise(fan_on_off)
    # Get the max flow rate from the fan.
    maximum_flow_rate_m3_per_s = nil
    if fan_on_off.maximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan_on_off.maximumFlowRate.get
    elsif fan_on_off.autosizedMaximumFlowRate.is_initialized
      maximum_flow_rate_m3_per_s = fan_on_off.autosizedMaximumFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.FanOnOff', "For #{fan_on_off.name} max flow rate is not available, cannot apply prototype assumptions.")
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
