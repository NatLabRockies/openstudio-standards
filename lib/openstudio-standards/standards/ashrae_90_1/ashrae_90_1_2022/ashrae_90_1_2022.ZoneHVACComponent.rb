class ASHRAE9012022 < ASHRAE901
  # @!group ZoneHVACComponent

  # Determine if vestibule heating control is required.
  # Required for 90.1-2019 per 6.4.3.9.
  #
  # @ref [References::ASHRAE9012019] 6.4.3.9
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Boolean] returns true if successful, false if not
  def zone_hvac_component_vestibule_heating_control_required?(zone_hvac_component)
    # Ensure that the equipment is assigned to a thermal zone
    if zone_hvac_component.thermalZone.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.ZoneHVACComponent', "For #{zone_hvac_component.name}: equipment is not assigned to a thermal zone, cannot apply vestibule heating control.")
      return false
    end

    # Only applies to equipment that is in vestibule zones
    return true if OpenstudioStandards::ThermalZone.thermal_zone_vestibule?(zone_hvac_component.thermalZone.get)

    # If here, vestibule heating control not required
    return false
  end

  # Add occupant standby controls to zone equipment
  # Currently, the controls consists of cycling the
  # fan during the occupant standby mode hours
  #
  # @param zone_hvac_component OpenStudio zonal equipment object
  # @return [Boolean] true if sucessful, false otherwise
  def zone_hvac_model_standby_mode_occupancy_control(zone_hvac_component)
    # Ensure that the equipment is assigned to a thermal zone
    if zone_hvac_component.thermalZone.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.ZoneHVACComponent', "For #{zone_hvac_component.name}: equipment is not assigned to a thermal zone, cannot apply vestibule heating control.")
      return true
    end

    # Get supply fan
    # Only Fan:OnOff can cycle
    fan = zone_hvac_component.supplyAirFan
    return true unless fan.to_FanOnOff.is_initialized

    fan = fan.to_FanOnOff.get
    # Set fan operating schedule during assumed occupant standby mode time to 0 so the fan can cycle
    # ZoneHVACFourPipeFanCoil has it optional, PTAC/PTHP starting a 3.5.0 is required
    new_sch = model_set_schedule_value(OpenStudio::Model::OptionalSchedule.new(zone_hvac_component.supplyAirFanOperatingModeSchedule).get, '12' => 0)
    zone_hvac_component.setSupplyAirFanOperatingModeSchedule(new_sch) unless new_sch == true

    return true
  end
end

