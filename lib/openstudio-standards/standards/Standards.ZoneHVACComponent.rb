class Standard
  # @!group ZoneHVACComponent

  # default fan efficiency for small zone hvac fans, in watts per cfm
  #
  # @return [Double] fan efficiency in watts per cfm
  def zone_hvac_component_prm_baseline_fan_efficacy
    fan_efficacy_w_per_cfm = 0.3
    return fan_efficacy_w_per_cfm
  end

  # Sets the fan power of zone level HVAC equipment
  # (Fan coils, Unit Heaters, PTACs, PTHPs, VRF Terminals, WSHPs, ERVs)
  # based on the W/cfm specified in the standard.
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Boolean] returns true if successful, false if not
  def zone_hvac_component_apply_prm_baseline_fan_power(zone_hvac_component)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ZoneHVACComponent', "Setting fan power for #{zone_hvac_component.name}.")

    # Convert this to the actual class type
    zone_hvac = if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
                  zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
                elsif zone_hvac_component.to_ZoneHVACUnitHeater.is_initialized
                  zone_hvac_component.to_ZoneHVACUnitHeater.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
                elsif zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
                  zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
                elsif zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.get
                elsif zone_hvac_component.to_ZoneHVACEnergyRecoveryVentilator.is_initialized
                  zone_hvac_component.to_ZoneHVACEnergyRecoveryVentilator.get
                end

    # Do nothing for other types of zone HVAC equipment
    if zone_hvac.nil?
      return false
    end

    # Determine the W/cfm
    fan_efficacy_w_per_cfm = zone_hvac_component_prm_baseline_fan_efficacy

    # Convert efficacy to metric
    # 1 cfm = 0.0004719 m^3/s
    fan_efficacy_w_per_m3_per_s = fan_efficacy_w_per_cfm / 0.0004719

    # Get the fan
    fan = if zone_hvac.supplyAirFan.to_FanConstantVolume.is_initialized
            zone_hvac.supplyAirFan.to_FanConstantVolume.get
          elsif zone_hvac.supplyAirFan.to_FanVariableVolume.is_initialized
            zone_hvac.supplyAirFan.to_FanVariableVolume.get
          elsif zone_hvac.supplyAirFan.to_FanOnOff.is_initialized
            zone_hvac.supplyAirFan.to_FanOnOff.get
          end

    # Get the maximum flow rate through the fan
    max_air_flow_rate = nil
    if fan.maximumFlowRate.is_initialized
      max_air_flow_rate = fan.maximumFlowRate.get
    elsif fan.autosizedMaximumFlowRate.is_initialized
      max_air_flow_rate = fan.autosizedMaximumFlowRate.get
    end
    max_air_flow_rate_cfm = OpenStudio.convert(max_air_flow_rate, 'm^3/s', 'ft^3/min').get

    # Set the impeller efficiency
    fan_change_impeller_efficiency(fan, fan_baseline_impeller_efficiency(fan))

    # Set the motor efficiency, preserving the impeller efficency.
    # For zone HVAC fans, a bhp lookup of 0.5bhp is always used because
    # they are assumed to represent a series of small fans in reality.
    fan_apply_standard_minimum_motor_efficiency(fan, fan_brake_horsepower(fan))

    # Calculate a new pressure rise to hit the target W/cfm
    fan_tot_eff = fan.fanEfficiency
    fan_rise_new_pa = fan_efficacy_w_per_m3_per_s * fan_tot_eff
    fan.setPressureRise(fan_rise_new_pa)

    # Calculate the newly set efficacy
    fan_power_new_w = fan_rise_new_pa * max_air_flow_rate / fan_tot_eff
    fan_efficacy_new_w_per_cfm = fan_power_new_w / max_air_flow_rate_cfm
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ZoneHVACComponent', "For #{zone_hvac_component.name}: fan efficacy set to #{fan_efficacy_new_w_per_cfm.round(2)} W/cfm.")

    return true
  end

  # Get the supply fan object for a zone equipment component
  # @author Doug Maddox, PNNL
  # @param zone_hvac_component [object]
  # @return [object] supply fan of zone equipment component
  def zone_hvac_get_fan_object(zone_hvac_component)
    zone_hvac = nil
    # Check for any zone equipment type that has a supply fan
    # except EnergyRecoveryVentilator, which is not a primary conditioning system
    zone_hvac = if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
                  zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
                elsif zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
                  zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
                elsif zone_hvac_component.to_ZoneHVACUnitHeater.is_initialized
                  zone_hvac_component.to_ZoneHVACUnitHeater.get
                elsif zone_hvac_component.to_ZoneHVACUnitVentilator.is_initialized
                  zone_hvac_component.to_ZoneHVACUnitVentilator.get
                elsif zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.get
                end

    # Get the fan
    return nil if zone_hvac.nil?

    fan_obj = if zone_hvac.supplyAirFan.to_FanConstantVolume.is_initialized
                zone_hvac.supplyAirFan.to_FanConstantVolume.get
              elsif zone_hvac.supplyAirFan.to_FanVariableVolume.is_initialized
                zone_hvac.supplyAirFan.to_FanVariableVolume.get
              elsif zone_hvac.supplyAirFan.to_FanOnOff.is_initialized
                zone_hvac.supplyAirFan.to_FanOnOff.get
              elsif zone_hvac.supplyAirFan.to_FanSystemModel.is_initialized
                zone_hvac.supplyAirFan.to_FanSystemModel.get
              end

    return fan_obj
  end

  # Default occupancy fraction threshold for determining if the spaces served by the zone hvac are occupied
  #
  # @return [Double] unoccupied threshold
  def zone_hvac_unoccupied_threshold
    return 0.15
  end

  # If the supply air fan operating mode schedule is always off (to follow load),
  # and the zone requires ventilation, override it to follow the zone occupancy schedule
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Boolean] returns true if successful, false if not
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
    if !existing_sch.nil? && existing_sch.name.is_initialized
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ZoneHVACComponent', "#{zone_hvac_component.name} has ventilation, and schedule is set to always on; keeping always on schedule.")
      return false if existing_sch.name.get.to_s.downcase.include?('always on discrete') || existing_sch.name.get.to_s.downcase.include?('guestroom_vent_ctrl_sch')
    end

    thermal_zone = zone_hvac_component.thermalZone.get
    occ_threshold = zone_hvac_unoccupied_threshold
    occ_sch = OpenstudioStandards::ThermalZone.thermal_zone_get_occupancy_schedule(thermal_zone,
                                                                                   sch_name: "#{zone_hvac_component.name} Occ Sch",
                                                                                   occupied_percentage_threshold: occ_threshold)
    zone_hvac_component.setSupplyAirFanOperatingModeSchedule(occ_sch)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ZoneHVACComponent', "#{zone_hvac_component.name} has ventilation.  Setting fan operating mode schedule to align with zone occupancy schedule.")

    return true
  end

  # Apply all standard required controls to the zone equipment
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Boolean] returns true if successful, false if not
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

    # Standby mode occupancy control
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

  # Determine if vestibule heating control is required.
  # Defaults to 90.1-2004 through 2010, not required.
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Boolean] returns true if successful, false if not
  def zone_hvac_component_vestibule_heating_control_required?(zone_hvac_component)
    vest_htg_control_required = false
    return vest_htg_control_required
  end

  # Add occupant standby controls to zone equipment
  # Currently, the controls consists of cycling the
  # fan during the occupant standby mode hours
  #
  # @param zone_hvac_component OpenStudio zonal equipment object
  # @return [Boolean] true if sucessful, false otherwise
  def zone_hvac_model_standby_mode_occupancy_control(zone_hvac_component)
    return true
  end

  # Turns off vestibule heating below 45F
  #
  # @param zone_hvac_component [OpenStudio::Model::ZoneHVACComponent] zone hvac component
  # @return [Boolean] returns true if successful, false if not
  def zone_hvac_component_apply_vestibule_heating_control(zone_hvac_component)
    # Ensure that the equipment is assigned to a thermal zone
    if zone_hvac_component.thermalZone.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.ZoneHVACComponent', "For #{zone_hvac_component.name}: equipment is not assigned to a thermal zone, cannot apply vestibule heating control.")
      return true
    end

    # Convert this to the actual class type
    zone_hvac = if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
                  zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
                elsif zone_hvac_component.to_ZoneHVACUnitHeater.is_initialized
                  zone_hvac_component.to_ZoneHVACUnitHeater.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
                end

    # Do nothing for other types of zone HVAC equipment
    if zone_hvac.nil?
      return true
    end

    # Get the heating coil and fan
    htg_coil = zone_hvac.heatingCoil
    htg_coil = if htg_coil.to_CoilHeatingGas.is_initialized
                 htg_coil.to_CoilHeatingGas.get
               elsif htg_coil.to_CoilHeatingElectric.is_initialized
                 htg_coil.to_CoilHeatingElectric.get
               elsif htg_coil.to_CoilHeatingWater.is_initialized
                 htg_coil.to_CoilHeatingWater.get
               elsif htg_coil.to_CoilHeatingDXSingleSpeed.is_initialized
                 htg_coil.to_CoilHeatingDXSingleSpeed.get
               end

    fan = zone_hvac.supplyAirFan
    fan = if fan.to_FanOnOff.is_initialized
            fan.to_FanOnOff.get
          elsif fan.to_FanConstantVolume.is_initialized
            fan.to_FanConstantVolume.get
          elsif fan.to_FanVariableVolume.is_initialized
            fan.to_FanVariableVolume.get
          end

    # Get existing heater availability schedule if present
    # or create a new one
    avail_sch = nil
    avail_sch_name = 'VestibuleHeaterAvailSch'
    if zone_hvac_component.model.getScheduleConstantByName(avail_sch_name).is_initialized
      avail_sch = zone_hvac_component.model.getScheduleConstantByName(avail_sch_name).get
    else
      avail_sch = OpenStudio::Model::ScheduleConstant.new(zone_hvac_component.model)
      avail_sch.setName(avail_sch_name)
      avail_sch.setValue(1)
    end

    # Replace the existing availabilty schedule with the one
    # that will be controlled via EMS
    htg_coil.setAvailabilitySchedule(avail_sch)
    fan.setAvailabilitySchedule(avail_sch)

    # Clean name of zone HVAC
    equip_name_clean = OpenstudioStandards::HVAC.ems_friendly_name(zone_hvac.name)

    # Sensors
    # Get existing OAT sensor if present
    oat_db_c_sen = nil
    if zone_hvac_component.model.getEnergyManagementSystemSensorByName('OATVestibule').is_initialized
      oat_db_c_sen = zone_hvac_component.model.getEnergyManagementSystemSensorByName('OATVestibule').get
    else
      oat_db_c_sen = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Site Outdoor Air Drybulb Temperature')
      oat_db_c_sen.setName('OATVestibule')
      oat_db_c_sen.setKeyName('Environment')
    end

    # Actuators
    avail_sch_act = OpenStudio::Model::EnergyManagementSystemActuator.new(avail_sch, 'Schedule:Constant', 'Schedule Value')
    avail_sch_act.setName("#{equip_name_clean}_VestHtgAvailSch")

    # Programs
    htg_lim_f = 45
    vestibule_htg_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    vestibule_htg_prg.setName("#{equip_name_clean}_VestHtgPrg")
    vestibule_htg_prg_body = <<-EMS
    IF #{oat_db_c_sen.handle} > #{OpenStudio.convert(htg_lim_f, 'F', 'C').get}
      SET #{avail_sch_act.handle} = 0
    ENDIF
    EMS
    vestibule_htg_prg.setBody(vestibule_htg_prg_body)

    # Program Calling Managers
    vestibule_htg_mgr = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    vestibule_htg_mgr.setName("#{equip_name_clean}_VestHtgMgr")
    vestibule_htg_mgr.setCallingPoint('BeginTimestepBeforePredictor')
    vestibule_htg_mgr.addProgram(vestibule_htg_prg)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ZoneHVACComponent', "For #{zone_hvac_component.name}: Vestibule heating control applied, heating disabled below #{htg_lim_f} F.")

    return true
  end
end
