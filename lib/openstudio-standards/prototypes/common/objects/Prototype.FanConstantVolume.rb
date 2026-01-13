class Standard
  # @!group FanConstantVolume

  include PrototypeFan
  # Sets the fan pressure rise based on the Prototype buildings inputs
  # which are governed by the flow rate coming through the fan
  # and whether the fan lives inside a unit heater, PTAC, etc.
  #
  # @param fan_constant_volume [OpenStudio::Model::FanConstantVolume] constant volume fan object
  # @return [Boolean] returns true if successful, false if not
  def fan_constant_volume_apply_prototype_fan_pressure_rise(fan_constant_volume)
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

    # Pressure rise will be determined based on the following logic.
    pressure_rise_in_h2o = 0.0

    # If the fan lives inside of a zone hvac equipment
    if fan_constant_volume.containingZoneHVACComponent.is_initialized
      zone_hvac = fan_constant_volume.containingZoneHVACComponent.get
      if zone_hvac.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized || zone_hvac.to_ZoneHVACFourPipeFanCoil.is_initialized
        pressure_rise_in_h2o = 1.33
      elsif zone_hvac.to_ZoneHVACUnitHeater.is_initialized
        pressure_rise_in_h2o = 0.2
      else # This type of fan should not exist in the prototype models
        return false
      end
    # If the fan lives on an airloop
    elsif fan_constant_volume.airLoopHVAC.is_initialized
      pressure_rise_in_h2o = fan_constant_volume_airloop_fan_pressure_rise(fan_constant_volume)
    end

    # Set the fan pressure rise
    pressure_rise_pa = OpenStudio.convert(pressure_rise_in_h2o, 'inH_{2}O', 'Pa').get
    fan_constant_volume.setPressureRise(pressure_rise_pa)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.FanConstantVolume', "For Prototype: #{fan_constant_volume.name}: #{maximum_flow_rate_cfm.round}cfm; Pressure Rise = #{pressure_rise_in_h2o}in w.c.")

    return true
  end

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
                           elsif maximum_flow_rate_cfm >= 7437 && maximum_flow_rate_cfm < 20_000
                             4.46
                           else # Over 20,000 cfm
                             4.09
                           end

    return pressure_rise_in_h2o
  end
end
