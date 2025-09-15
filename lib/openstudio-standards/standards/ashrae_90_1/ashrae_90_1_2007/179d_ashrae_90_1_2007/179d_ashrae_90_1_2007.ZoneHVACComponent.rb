# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Sustainable Energy, LLC.
# See also https://openstudio.net/license
# *******************************************************************************

class ACM179dASHRAE9012007
  # @!group ZoneHVACComponent

  # If the supply air fan operating mode schedule is always off (to follow load),
  # and the zone requires ventilation, override it to follow the zone occupancy schedule
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Bool] returns true if successful, false if not
  def zone_hvac_component_occupancy_ventilation_control(zone_hvac_component)
    ventilation = false
    # Zone HVAC operating schedule if providing ventilation
    # Zone HVAC components return an OptionalSchedule object for supplyAirFanOperatingModeSchedule
    # except for ZoneHVACTerminalUnitVariableRefrigerantFlow which returns a Schedule
    # and starting at 3.5.0, PTAC / PTHP also return a Schedule, optional before that
    existing_sch = nil
    if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
      zone_hvac_component = zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
      if zone_hvac_component.maximumOutdoorAirFlowRate.is_initialized
        oa_rate = zone_hvac_component.maximumOutdoorAirFlowRate.get
        ventilation = true if oa_rate > 0.0
      end
      ventilation = true if zone_hvac_component.isMaximumOutdoorAirFlowRateAutosized
      fan_op_sch = zone_hvac_component.supplyAirFanOperatingModeSchedule
      existing_sch = fan_op_sch.get if fan_op_sch.is_initialized
    elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
      zone_hvac_component = zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
      if zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
        oa_rate = zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
        ventilation = true if oa_rate > 0.0
      end
      ventilation = true if zone_hvac_component.isOutdoorAirFlowRateWhenNoCoolingorHeatingisNeededAutosized
      fan_op_sch = OpenStudio::Model::OptionalSchedule.new(zone_hvac_component.supplyAirFanOperatingModeSchedule)
      existing_sch = fan_op_sch.get if fan_op_sch.is_initialized
    elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
      zone_hvac_component = zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
      if zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
        oa_rate = zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
        ventilation = true if oa_rate > 0.0
      end
      ventilation = true if zone_hvac_component.isOutdoorAirFlowRateWhenNoCoolingorHeatingisNeededAutosized
      fan_op_sch = OpenStudio::Model::OptionalSchedule.new(zone_hvac_component.supplyAirFanOperatingModeSchedule)
      existing_sch = fan_op_sch.get if fan_op_sch.is_initialized
    elsif zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
      zone_hvac_component = zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
      if zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
        oa_rate = zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
        ventilation = true if oa_rate > 0.0
      end
      ventilation = true if zone_hvac_component.isOutdoorAirFlowRateWhenNoCoolingorHeatingisNeededAutosized
      existing_sch = zone_hvac_component.supplyAirFanOperatingModeSchedule
    elsif zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.is_initialized
      zone_hvac_component = zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.get
      if zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
        oa_rate = zone_hvac_component.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
        ventilation = true if oa_rate > 0.0
      end
      ventilation = true if zone_hvac_component.isOutdoorAirFlowRateWhenNoCoolingorHeatingisNeededAutosized
      fan_op_sch = zone_hvac_component.supplyAirFanOperatingModeSchedule
      existing_sch = fan_op_sch.get if fan_op_sch.is_initialized
    end
    return false unless ventilation

    # if supply air fan operating schedule is always off,
    # override to provide ventilation during occupied hours
    # NOTE: 179D disable due to override with acm schedule
    # unless existing_sch.nil?
    #   if existing_sch.name.is_initialized
    #     OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ZoneHVACComponent', "#{zone_hvac_component.name} has ventilation, and schedule is set to always on; keeping always on schedule.")
    #     return false if existing_sch.name.get.to_s.downcase.include?('always on discrete') || existing_sch.name.get.to_s.downcase.include?('guestroom_vent_ctrl_sch')
    #   end
    # end

    # thermal_zone = zone_hvac_component.thermalZone.get
    # occ_threshold = zone_hvac_unoccupied_threshold
    # occ_sch = thermal_zones_get_occupancy_schedule([thermal_zone],
    #                                                sch_name: "#{zone_hvac_component.name} Occ Sch",
    #                                                occupied_percentage_threshold: occ_threshold)
    ## NOTE: using 179d acm schedule
    data = model_get_standards_data(zone_hvac_component.model, throw_if_not_found: true)
    acm_fan_sch_name = data['hvac_operation_schedule']
    zone_hvac_component.model.getBuilding.additionalProperties.setFeature('acm_fan_sch', acm_fan_sch_name)
    acm_fan_sch = model_add_schedule(zone_hvac_component.model, acm_fan_sch_name)
    zone_hvac_component.setSupplyAirFanOperatingModeSchedule(acm_fan_sch)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ZoneHVACComponent', "#{zone_hvac_component.name} has ventilation.  Setting fan operating mode schedule to ACM schedule '#{acm_fan_sch_name}'.")

    return true
  end

  # Apply all standard required controls to the zone equipment
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Bool] returns true if successful, false if not
  def zone_hvac_component_apply_standard_controls(zone_hvac_component)
    # Vestibule heating control
    if zone_hvac_component_vestibule_heating_control_required?(zone_hvac_component)
      zone_hvac_component_apply_vestibule_heating_control(zone_hvac_component)
    end

    # Convert to objects
    zone_hvac_component = if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
                            zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
                          elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                            zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
                          elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                            zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
                          end

    # Do nothing for other types of zone HVAC equipment
    if zone_hvac_component.nil?
      return true
    end

    # Standby mode occupancy control - NOTE: overriding because there was a
    # logic error, cf https://github.com/NREL/openstudio-standards/issues/1753
    return true if zone_hvac_component.thermalZone.empty?

    thermal_zone = zone_hvac_component.thermalZone.get

    standby_mode_spaces = []
    thermal_zone.spaces.sort.each do |space|
      if space_occupancy_standby_mode_required?(space)
        standby_mode_spaces << space
      end
    end
    if !standby_mode_spaces.empty?
      zone_hvac_model_standby_mode_occupancy_control(zone_hvac_component)
    end

    # zone ventilation occupancy control for systems with ventilation
    zone_hvac_component_occupancy_ventilation_control(zone_hvac_component)

    return true
  end
end
