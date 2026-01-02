class Standard
  # @!group FanOnOff

  include PrototypeFan

  # Sets the fan pressure rise based on the Prototype buildings inputs
  # which are governed by the flow rate coming through the fan
  # and whether the fan lives inside a unit heater, PTAC, etc.
  #
  # @param fan_on_off [OpenStudio::Model::FanOnOff] on off fan object
  # @return [Boolean] returns true if successful, false if not
  def fan_on_off_apply_prototype_fan_pressure_rise(fan_on_off)
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

    # Pressure rise will be determined based on the following logic.
    pressure_rise_in_h2o = 0.0

    # If the fan lives inside of a zone hvac equipment
    if fan_on_off.containingZoneHVACComponent.is_initialized
      zone_hvac = fan_on_off.containingZoneHVACComponent.get
      if zone_hvac.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
        pressure_rise_in_h2o = 1.33
      elsif zone_hvac.to_ZoneHVACFourPipeFanCoil.is_initialized
        pressure_rise_in_h2o = 1.087563267
      elsif zone_hvac.to_ZoneHVACUnitHeater.is_initialized
        pressure_rise_in_h2o = 0.2
      else # This type of fan should not exist in the prototype models
        return false
      end
    end

    # If the fan lives on an airloop
    if fan_on_off.airLoopHVAC.is_initialized
      pressure_rise_in_h2o = fan_on_off_airloop_or_unitary_fan_pressure_rise(fan_on_off)
    end

    # If the fan lives inside a unitary system
    if fan_on_off.airLoopHVAC.empty? && fan_on_off.containingZoneHVACComponent.empty?
      pressure_rise_in_h2o = fan_on_off_airloop_or_unitary_fan_pressure_rise(fan_on_off)
    end

    # Set the fan pressure rise
    pressure_rise_pa = OpenStudio.convert(pressure_rise_in_h2o, 'inH_{2}O', 'Pa').get
    fan_on_off.setPressureRise(pressure_rise_pa)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.FanOnOff', "For Prototype: #{fan_on_off.name}: #{maximum_flow_rate_cfm.round}cfm; Pressure Rise = #{pressure_rise_in_h2o}in w.c.")

    return true
  end

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
                           elsif maximum_flow_rate_cfm >= 7437 && maximum_flow_rate_cfm < 20_000
                             4.46
                           else # Over 20,000 cfm
                             4.09
                           end

    return pressure_rise_in_h2o
  end
end
