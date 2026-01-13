class Standard
  # These EnergyPlus objects implement a proportional control for a single thermal zone with a radiant system.
  # @ref [References::CBERadiantSystems]
  # @param zone [OpenStudio::Model::ThermalZone>] zone to add radiant controls
  # @param radiant_loop [OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow>] radiant loop in thermal zone
  # @param radiant_temperature_control_type [String] determines the controlled temperature for the radiant system
  #   options are 'SurfaceFaceTemperature', 'SurfaceInteriorTemperature'
  # @param use_zone_occupancy_for_control [Boolean] Set to true if radiant system is to use specific zone occupancy objects
  #   for CBE control strategy. If false, then it will use values in model_occ_hr_start and model_occ_hr_end
  #   for all radiant zones. default to true.
  # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
  #   if this parameter is set, the returned ScheduleRuleset will be 0 = unoccupied, 1 = occupied
  #   otherwise the ScheduleRuleset will be the weighted fractional occupancy schedule
  # @param model_occ_hr_start [Double] Starting decimal hour of whole building occupancy
  # @param model_occ_hr_end [Double] Ending decimal hour of whole building occupancy
  # @todo model_occ_hr_start and model_occ_hr_end from zone occupancy schedules
  # @param proportional_gain [Double] Proportional gain constant (recommended 0.3 or less).
  # @param switch_over_time [Double] Time limitation for when the system can switch between heating and cooling
  def model_add_radiant_proportional_controls(model, zone, radiant_loop,
                                              radiant_temperature_control_type: 'SurfaceFaceTemperature',
                                              use_zone_occupancy_for_control: true,
                                              occupied_percentage_threshold: 0.10,
                                              model_occ_hr_start: 6.0,
                                              model_occ_hr_end: 18.0,
                                              proportional_gain: 0.3,
                                              switch_over_time: 24.0)

    zone_name = OpenstudioStandards::HVAC.ems_friendly_name(zone.name)
    zone_timestep = model.getTimestep.numberOfTimestepsPerHour

    if model.version < OpenStudio::VersionString.new('3.1.1')
      coil_cooling_radiant = radiant_loop.coolingCoil.to_CoilCoolingLowTempRadiantVarFlow.get
      coil_heating_radiant = radiant_loop.heatingCoil.to_CoilHeatingLowTempRadiantVarFlow.get
    else
      coil_cooling_radiant = radiant_loop.coolingCoil.get.to_CoilCoolingLowTempRadiantVarFlow.get
      coil_heating_radiant = radiant_loop.heatingCoil.get.to_CoilHeatingLowTempRadiantVarFlow.get
    end

    #####
    # Define radiant system parameters
    ####
    # set radiant system temperature and setpoint control type
    unless ['surfacefacetemperature', 'surfaceinteriortemperature'].include? radiant_temperature_control_type.downcase
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model',
                         "Control sequences not compatible with '#{radiant_temperature_control_type}' radiant system control. Defaulting to 'SurfaceFaceTemperature'.")
      radiant_temperature_control_type = 'SurfaceFaceTemperature'
    end

    radiant_loop.setTemperatureControlType(radiant_temperature_control_type)

    #####
    # List of schedule objects used to hold calculation results
    ####

    # get existing switchover time schedule or create one if needed
    sch_radiant_switchover = model.getScheduleRulesetByName('Radiant System Switchover')
    if sch_radiant_switchover.is_initialized
      sch_radiant_switchover = sch_radiant_switchover.get
    else
      sch_radiant_switchover = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                               switch_over_time,
                                                                                               name: 'Radiant System Switchover',
                                                                                               schedule_type_limit: 'Dimensionless')
    end

    # set radiant system switchover schedule
    radiant_loop.setChangeoverDelayTimePeriodSchedule(sch_radiant_switchover.to_Schedule.get)

    # Calculated active slab heating and cooling temperature setpoint.
    # radiant system cooling control actuator
    sch_radiant_clgsetp = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                          26.0,
                                                                                          name: "#{zone_name}_Sch_Radiant_ClgSetP",
                                                                                          schedule_type_limit: 'Temperature')
    coil_cooling_radiant.setCoolingControlTemperatureSchedule(sch_radiant_clgsetp)
    cmd_cold_water_ctrl = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_radiant_clgsetp,
                                                                                'Schedule:Year',
                                                                                'Schedule Value')
    cmd_cold_water_ctrl.setName("#{zone_name}_cmd_cold_water_ctrl")

    # radiant system heating control actuator
    sch_radiant_htgsetp = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                          20.0,
                                                                                          name: "#{zone_name}_Sch_Radiant_HtgSetP",
                                                                                          schedule_type_limit: 'Temperature')
    coil_heating_radiant.setHeatingControlTemperatureSchedule(sch_radiant_htgsetp)
    cmd_hot_water_ctrl = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_radiant_htgsetp,
                                                                               'Schedule:Year',
                                                                               'Schedule Value')
    cmd_hot_water_ctrl.setName("#{zone_name}_cmd_hot_water_ctrl")

    # Calculated cooling setpoint error. Calculated from upper comfort limit minus setpoint offset and 'measured' controlled zone temperature.
    sch_csp_error = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                    0.0,
                                                                                    name: "#{zone_name}_Sch_CSP_Error",
                                                                                    schedule_type_limit: 'Temperature')
    cmd_csp_error = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_csp_error,
                                                                          'Schedule:Year',
                                                                          'Schedule Value')
    cmd_csp_error.setName("#{zone_name}_cmd_csp_error")

    # Calculated heating setpoint error. Calculated from lower comfort limit plus setpoint offset and 'measured' controlled zone temperature.
    sch_hsp_error = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                    0.0,
                                                                                    name: "#{zone_name}_Sch_HSP_Error",
                                                                                    schedule_type_limit: 'Temperature')
    cmd_hsp_error = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_hsp_error,
                                                                          'Schedule:Year',
                                                                          'Schedule Value')
    cmd_hsp_error.setName("#{zone_name}_cmd_hsp_error")

    #####
    # List of global variables used in EMS scripts
    ####

    # Proportional  gain constant (recommended 0.3 or less).
    prp_k = model.getEnergyManagementSystemGlobalVariableByName('prp_k')
    if prp_k.is_initialized
      prp_k = prp_k.get
    else
      prp_k = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, 'prp_k')
    end

    # Upper slab temperature setpoint limit (recommended no higher than 29C (84F))
    upper_slab_sp_lim = model.getEnergyManagementSystemGlobalVariableByName('upper_slab_sp_lim')
    if upper_slab_sp_lim.is_initialized
      upper_slab_sp_lim = upper_slab_sp_lim.get
    else
      upper_slab_sp_lim = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, 'upper_slab_sp_lim')
    end

    # Lower slab temperature setpoint limit (recommended no lower than 19C (66F))
    lower_slab_sp_lim = model.getEnergyManagementSystemGlobalVariableByName('lower_slab_sp_lim')
    if lower_slab_sp_lim.is_initialized
      lower_slab_sp_lim = lower_slab_sp_lim.get
    else
      lower_slab_sp_lim = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, 'lower_slab_sp_lim')
    end

    # Temperature offset used as a safety factor for thermal control (recommend 0.5C (1F)).
    ctrl_temp_offset = model.getEnergyManagementSystemGlobalVariableByName('ctrl_temp_offset')
    if ctrl_temp_offset.is_initialized
      ctrl_temp_offset = ctrl_temp_offset.get
    else
      ctrl_temp_offset = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, 'ctrl_temp_offset')
    end

    # Hour where slab setpoint is to be changed
    hour_of_slab_sp_change = model.getEnergyManagementSystemGlobalVariableByName('hour_of_slab_sp_change')
    if hour_of_slab_sp_change.is_initialized
      hour_of_slab_sp_change = hour_of_slab_sp_change.get
    else
      hour_of_slab_sp_change = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, 'hour_of_slab_sp_change')
    end

    #####
    # List of zone specific variables used in EMS scripts
    ####

    # Maximum 'measured' temperature in zone during occupied times. Default setup uses mean air temperature.
    # Other possible choices are operative and mean radiant temperature.
    zone_max_ctrl_temp = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, "#{zone_name}_max_ctrl_temp")

    # Minimum 'measured' temperature in zone during occupied times. Default setup uses mean air temperature.
    # Other possible choices are operative and mean radiant temperature.
    zone_min_ctrl_temp = OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(model, "#{zone_name}_min_ctrl_temp")

    #####
    # List of 'sensors' used in the EMS programs
    ####

    # Controlled zone temperature for the zone.
    zone_ctrl_temperature = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Zone Air Temperature')
    zone_ctrl_temperature.setName("#{zone_name}_ctrl_temperature")
    zone_ctrl_temperature.setKeyName(zone.name.get)

    # check for zone thermostat and replace heat/cool schedules for radiant system control
    # if there is no zone thermostat, then create one
    zone_thermostat = zone.thermostatSetpointDualSetpoint

    if zone_thermostat.is_initialized
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Replacing thermostat schedules in zone #{zone.name} for radiant system control.")
      zone_thermostat = zone.thermostatSetpointDualSetpoint.get
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Zone #{zone.name} does not have a thermostat. Creating a thermostat for radiant system control.")
      zone_thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      zone_thermostat.setName("#{zone_name}_Thermostat_DualSetpoint")
    end

    # create new heating and cooling schedules to be used with all radiant systems
    zone_htg_thermostat = model.getScheduleRulesetByName('Radiant System Heating Setpoint')
    if zone_htg_thermostat.is_initialized
      zone_htg_thermostat = zone_htg_thermostat.get
    else
      zone_htg_thermostat = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                            20.0,
                                                                                            name: 'Radiant System Heating Setpoint',
                                                                                            schedule_type_limit: 'Temperature')
    end

    zone_clg_thermostat = model.getScheduleRulesetByName('Radiant System Cooling Setpoint')
    if zone_clg_thermostat.is_initialized
      zone_clg_thermostat = zone_clg_thermostat.get
    else
      zone_clg_thermostat = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                            26.0,
                                                                                            name: 'Radiant System Cooling Setpoint',
                                                                                            schedule_type_limit: 'Temperature')
    end

    # implement new heating and cooling schedules
    zone_thermostat.setHeatingSetpointTemperatureSchedule(zone_htg_thermostat)
    zone_thermostat.setCoolingSetpointTemperatureSchedule(zone_clg_thermostat)

    # Upper comfort limit for the zone. Taken from existing thermostat schedules in the zone.
    zone_upper_comfort_limit = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
    zone_upper_comfort_limit.setName("#{zone_name}_upper_comfort_limit")
    zone_upper_comfort_limit.setKeyName(zone_clg_thermostat.name.get)

    # Lower comfort limit for the zone. Taken from existing thermostat schedules in the zone.
    zone_lower_comfort_limit = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
    zone_lower_comfort_limit.setName("#{zone_name}_lower_comfort_limit")
    zone_lower_comfort_limit.setKeyName(zone_htg_thermostat.name.get)

    # Radiant system water flow rate used to determine if there is active hydronic cooling in the radiant system.
    zone_rad_cool_operation = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'System Node Mass Flow Rate')
    zone_rad_cool_operation.setName("#{zone_name}_rad_cool_operation")
    zone_rad_cool_operation.setKeyName(coil_cooling_radiant.to_StraightComponent.get.inletModelObject.get.name.get)

    # Radiant system water flow rate used to determine if there is active hydronic heating in the radiant system.
    zone_rad_heat_operation = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'System Node Mass Flow Rate')
    zone_rad_heat_operation.setName("#{zone_name}_rad_heat_operation")
    zone_rad_heat_operation.setKeyName(coil_heating_radiant.to_StraightComponent.get.inletModelObject.get.name.get)

    # Radiant system switchover delay time period schedule
    # used to determine if there is active hydronic cooling/heating in the radiant system.
    zone_rad_switch_over = model.getEnergyManagementSystemSensorByName('radiant_switch_over_time')

    unless zone_rad_switch_over.is_initialized
      zone_rad_switch_over = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
      zone_rad_switch_over.setName('radiant_switch_over_time')
      zone_rad_switch_over.setKeyName(sch_radiant_switchover.name.get)
    end

    # Last 24 hours trend for radiant system in cooling mode.
    zone_rad_cool_operation_trend = OpenStudio::Model::EnergyManagementSystemTrendVariable.new(model, zone_rad_cool_operation)
    zone_rad_cool_operation_trend.setName("#{zone_name}_rad_cool_operation_trend")
    zone_rad_cool_operation_trend.setNumberOfTimestepsToBeLogged(zone_timestep * 48)

    # Last 24 hours trend for radiant system in heating mode.
    zone_rad_heat_operation_trend = OpenStudio::Model::EnergyManagementSystemTrendVariable.new(model, zone_rad_heat_operation)
    zone_rad_heat_operation_trend.setName("#{zone_name}_rad_heat_operation_trend")
    zone_rad_heat_operation_trend.setNumberOfTimestepsToBeLogged(zone_timestep * 48)

    # use zone occupancy objects for radiant system control if selected
    if use_zone_occupancy_for_control

      # get annual occupancy schedule for zone
      occ_schedule_ruleset = OpenstudioStandards::ThermalZone.thermal_zone_get_occupancy_schedule(zone,
                                                                                                  sch_name: "#{zone.name} Radiant System Occupied Schedule",
                                                                                                  occupied_percentage_threshold: occupied_percentage_threshold)
    else

      occ_schedule_ruleset = model.getScheduleRulesetByName('Whole Building Radiant System Occupied Schedule')
      if occ_schedule_ruleset.is_initialized
        occ_schedule_ruleset = occ_schedule_ruleset.get
      else
        # create occupancy schedules
        occ_schedule_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
        occ_schedule_ruleset.setName('Whole Building Radiant System Occupied Schedule')

        start_hour = model_occ_hr_end.to_i
        start_minute = ((model_occ_hr_end % 1) * 60).to_i
        end_hour = model_occ_hr_start.to_i
        end_minute = ((model_occ_hr_start % 1) * 60).to_i

        if end_hour > start_hour
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, start_hour, start_minute, 0), 1.0)
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, end_hour, end_minute, 0), 0.0)
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0) if end_hour < 24
        elsif start_hour > end_hour
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, end_hour, end_minute, 0), 0.0)
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, start_hour, start_minute, 0), 1.0)
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.0) if start_hour < 24
        else
          occ_schedule_ruleset.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
        end
      end
    end

    # create ems sensor for zone occupied status
    zone_occupied_status = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
    zone_occupied_status.setName("#{zone_name}_occupied_status")
    zone_occupied_status.setKeyName(occ_schedule_ruleset.name.get)

    # Last 24 hours trend for zone occupied status
    zone_occupied_status_trend = OpenStudio::Model::EnergyManagementSystemTrendVariable.new(model, zone_occupied_status)
    zone_occupied_status_trend.setName("#{zone_name}_occupied_status_trend")
    zone_occupied_status_trend.setNumberOfTimestepsToBeLogged(zone_timestep * 48)

    #####
    # List of EMS programs to implement the proportional control for the radiant system.
    ####

    # Initialize global constant values used in EMS programs.
    set_constant_values_prg_body = <<-EMS
      SET prp_k              = #{proportional_gain},
      SET ctrl_temp_offset   = 0.5,
      SET upper_slab_sp_lim  = 29,
      SET lower_slab_sp_lim  = 19,
      SET hour_of_slab_sp_change = 18
    EMS

    set_constant_values_prg = model.getEnergyManagementSystemProgramByName('Set_Constant_Values')
    if set_constant_values_prg.is_initialized
      set_constant_values_prg = set_constant_values_prg.get
    else
      set_constant_values_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
      set_constant_values_prg.setName('Set_Constant_Values')
      set_constant_values_prg.setBody(set_constant_values_prg_body)
    end

    # Initialize zone specific constant values used in EMS programs.
    set_constant_zone_values_prg_body = <<-EMS
      SET #{zone_name}_max_ctrl_temp      = #{zone_name}_lower_comfort_limit,
      SET #{zone_name}_min_ctrl_temp      = #{zone_name}_upper_comfort_limit,
      SET #{zone_name}_cmd_csp_error      = 0,
      SET #{zone_name}_cmd_hsp_error      = 0,
      SET #{zone_name}_cmd_cold_water_ctrl = #{zone_name}_upper_comfort_limit,
      SET #{zone_name}_cmd_hot_water_ctrl  = #{zone_name}_lower_comfort_limit
    EMS

    set_constant_zone_values_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    set_constant_zone_values_prg.setName("#{zone_name}_Set_Constant_Values")
    set_constant_zone_values_prg.setBody(set_constant_zone_values_prg_body)

    # Calculate maximum and minimum 'measured' controlled temperature in the zone
    calculate_minmax_ctrl_temp_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    calculate_minmax_ctrl_temp_prg.setName("#{zone_name}_Calculate_Extremes_In_Zone")
    calculate_minmax_ctrl_temp_prg_body = <<-EMS
      IF (#{zone_name}_occupied_status == 1),
          IF #{zone_name}_ctrl_temperature > #{zone_name}_max_ctrl_temp,
              SET #{zone_name}_max_ctrl_temp = #{zone_name}_ctrl_temperature,
          ENDIF,
          IF #{zone_name}_ctrl_temperature < #{zone_name}_min_ctrl_temp,
              SET #{zone_name}_min_ctrl_temp = #{zone_name}_ctrl_temperature,
          ENDIF,
      ELSE,
        SET #{zone_name}_max_ctrl_temp = #{zone_name}_lower_comfort_limit,
        SET #{zone_name}_min_ctrl_temp = #{zone_name}_upper_comfort_limit,
      ENDIF
    EMS
    calculate_minmax_ctrl_temp_prg.setBody(calculate_minmax_ctrl_temp_prg_body)

    # Calculate errors from comfort zone limits and 'measured' controlled temperature in the zone.
    calculate_errors_from_comfort_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    calculate_errors_from_comfort_prg.setName("#{zone_name}_Calculate_Errors_From_Comfort")
    calculate_errors_from_comfort_prg_body = <<-EMS
      IF (CurrentTime == (hour_of_slab_sp_change - ZoneTimeStep)),
          SET #{zone_name}_cmd_csp_error = (#{zone_name}_upper_comfort_limit - ctrl_temp_offset) - #{zone_name}_max_ctrl_temp,
          SET #{zone_name}_cmd_hsp_error = (#{zone_name}_lower_comfort_limit + ctrl_temp_offset) - #{zone_name}_min_ctrl_temp,
      ENDIF
    EMS
    calculate_errors_from_comfort_prg.setBody(calculate_errors_from_comfort_prg_body)

    # Calculate the new active slab temperature setpoint for heating and cooling
    calculate_slab_ctrl_setpoint_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    calculate_slab_ctrl_setpoint_prg.setName("#{zone_name}_Calculate_Slab_Ctrl_Setpoint")
    calculate_slab_ctrl_setpoint_prg_body = <<-EMS
      SET #{zone_name}_cont_cool_oper = @TrendSum #{zone_name}_rad_cool_operation_trend radiant_switch_over_time/ZoneTimeStep,
      SET #{zone_name}_cont_heat_oper = @TrendSum #{zone_name}_rad_heat_operation_trend radiant_switch_over_time/ZoneTimeStep,
      SET #{zone_name}_occupied_hours = @TrendSum #{zone_name}_occupied_status_trend 24/ZoneTimeStep,
      IF (#{zone_name}_cont_cool_oper > 0) && (#{zone_name}_occupied_hours > 0) && (CurrentTime == hour_of_slab_sp_change),
        SET #{zone_name}_cmd_hot_water_ctrl = #{zone_name}_cmd_hot_water_ctrl + (#{zone_name}_cmd_csp_error*prp_k),
      ELSEIF (#{zone_name}_cont_heat_oper > 0) && (#{zone_name}_occupied_hours > 0) && (CurrentTime == hour_of_slab_sp_change),
        SET #{zone_name}_cmd_hot_water_ctrl = #{zone_name}_cmd_hot_water_ctrl + (#{zone_name}_cmd_hsp_error*prp_k),
      ELSE,
        SET #{zone_name}_cmd_hot_water_ctrl = #{zone_name}_cmd_hot_water_ctrl,
      ENDIF,
      IF (#{zone_name}_cmd_hot_water_ctrl < lower_slab_sp_lim),
        SET #{zone_name}_cmd_hot_water_ctrl = lower_slab_sp_lim,
      ELSEIF (#{zone_name}_cmd_hot_water_ctrl > upper_slab_sp_lim),
        SET #{zone_name}_cmd_hot_water_ctrl = upper_slab_sp_lim,
      ENDIF,
      SET #{zone_name}_cmd_cold_water_ctrl = #{zone_name}_cmd_hot_water_ctrl + 0.01
    EMS
    calculate_slab_ctrl_setpoint_prg.setBody(calculate_slab_ctrl_setpoint_prg_body)

    #####
    # List of EMS program manager objects
    ####

    initialize_constant_parameters = model.getEnergyManagementSystemProgramCallingManagerByName('Initialize_Constant_Parameters')
    if initialize_constant_parameters.is_initialized
      initialize_constant_parameters = initialize_constant_parameters.get
      # add program if it does not exist in manager
      existing_program_names = initialize_constant_parameters.programs.collect { |prg| prg.name.get.downcase }
      unless existing_program_names.include? set_constant_values_prg.name.get.downcase
        initialize_constant_parameters.addProgram(set_constant_values_prg)
      end
    else
      initialize_constant_parameters = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
      initialize_constant_parameters.setName('Initialize_Constant_Parameters')
      initialize_constant_parameters.setCallingPoint('BeginNewEnvironment')
      initialize_constant_parameters.addProgram(set_constant_values_prg)
    end

    initialize_constant_parameters_after_warmup = model.getEnergyManagementSystemProgramCallingManagerByName('Initialize_Constant_Parameters_After_Warmup')
    if initialize_constant_parameters_after_warmup.is_initialized
      initialize_constant_parameters_after_warmup = initialize_constant_parameters_after_warmup.get
      # add program if it does not exist in manager
      existing_program_names = initialize_constant_parameters_after_warmup.programs.collect { |prg| prg.name.get.downcase }
      unless existing_program_names.include? set_constant_values_prg.name.get.downcase
        initialize_constant_parameters_after_warmup.addProgram(set_constant_values_prg)
      end
    else
      initialize_constant_parameters_after_warmup = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
      initialize_constant_parameters_after_warmup.setName('Initialize_Constant_Parameters_After_Warmup')
      initialize_constant_parameters_after_warmup.setCallingPoint('AfterNewEnvironmentWarmUpIsComplete')
      initialize_constant_parameters_after_warmup.addProgram(set_constant_values_prg)
    end

    zone_initialize_constant_parameters = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    zone_initialize_constant_parameters.setName("#{zone_name}_Initialize_Constant_Parameters")
    zone_initialize_constant_parameters.setCallingPoint('BeginNewEnvironment')
    zone_initialize_constant_parameters.addProgram(set_constant_zone_values_prg)

    zone_initialize_constant_parameters_after_warmup = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    zone_initialize_constant_parameters_after_warmup.setName("#{zone_name}_Initialize_Constant_Parameters_After_Warmup")
    zone_initialize_constant_parameters_after_warmup.setCallingPoint('AfterNewEnvironmentWarmUpIsComplete')
    zone_initialize_constant_parameters_after_warmup.addProgram(set_constant_zone_values_prg)

    average_building_temperature = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    average_building_temperature.setName("#{zone_name}_Average_Building_Temperature")
    average_building_temperature.setCallingPoint('EndOfZoneTimestepAfterZoneReporting')
    average_building_temperature.addProgram(calculate_minmax_ctrl_temp_prg)
    average_building_temperature.addProgram(calculate_errors_from_comfort_prg)

    programs_at_beginning_of_timestep = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    programs_at_beginning_of_timestep.setName("#{zone_name}_Programs_At_Beginning_Of_Timestep")
    programs_at_beginning_of_timestep.setCallingPoint('BeginTimestepBeforePredictor')
    programs_at_beginning_of_timestep.addProgram(calculate_slab_ctrl_setpoint_prg)

    #####
    # List of variables for output.
    ####

    zone_max_ctrl_temp_output = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, zone_max_ctrl_temp)
    zone_max_ctrl_temp_output.setName("#{zone_name} Maximum occupied temperature in zone")
    zone_min_ctrl_temp_output = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, zone_min_ctrl_temp)
    zone_min_ctrl_temp_output.setName("#{zone_name} Minimum occupied temperature in zone")
  end

  # Native EnergyPlus objects implement a control for a single thermal zone with a radiant system.
  # @param zone [OpenStudio::Model::ThermalZone>] zone to add radiant controls
  # @param radiant_loop [OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow>] radiant loop in thermal zone
  # @param radiant_temperature_control_type [String] determines the controlled temperature for the radiant system
  #   options are 'SurfaceFaceTemperature', 'SurfaceInteriorTemperature'
  # @param slab_setpoint_oa_control [Bool] True if slab setpoint is to be varied based on outdoor air temperature
  # @param switch_over_time [Double] Time limitation for when the system can switch between heating and cooling
  # @param slab_sp_at_oat_low [Double] radiant slab temperature setpoint, in F, at the outdoor high temperature.
  # @param slab_oat_low [Double] outdoor drybulb air temperature, in F, for low radiant slab setpoint.
  # @param slab_sp_at_oat_high [Double] radiant slab temperature setpoint, in F, at the outdoor low temperature.
  # @param slab_oat_high [Double] outdoor drybulb air temperature, in F, for high radiant slab setpoint.
  def model_add_radiant_basic_controls(model, zone, radiant_loop,
                                       radiant_temperature_control_type: 'SurfaceFaceTemperature',
                                       slab_setpoint_oa_control: false,
                                       switch_over_time: 24.0,
                                       slab_sp_at_oat_low: 73,
                                       slab_oat_low: 65,
                                       slab_sp_at_oat_high: 68,
                                       slab_oat_high: 80)

    zone_name = zone.name.to_s.gsub(/[ +-.]/, '_')

    if model.version < OpenStudio::VersionString.new('3.1.1')
      coil_cooling_radiant = radiant_loop.coolingCoil.to_CoilCoolingLowTempRadiantVarFlow.get
      coil_heating_radiant = radiant_loop.heatingCoil.to_CoilHeatingLowTempRadiantVarFlow.get
    else
      coil_cooling_radiant = radiant_loop.coolingCoil.get.to_CoilCoolingLowTempRadiantVarFlow.get
      coil_heating_radiant = radiant_loop.heatingCoil.get.to_CoilHeatingLowTempRadiantVarFlow.get
    end

    #####
    # Define radiant system parameters
    ####
    # set radiant system temperature and setpoint control type
    unless ['surfacefacetemperature', 'surfaceinteriortemperature'].include? radiant_temperature_control_type.downcase
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model',
                         "Control sequences not compatible with '#{radiant_temperature_control_type}' radiant system control. Defaulting to 'SurfaceFaceTemperature'.")
      radiant_temperature_control_type = 'SurfaceFaceTemperature'
    end

    radiant_loop.setTemperatureControlType(radiant_temperature_control_type)

    # get existing switchover time schedule or create one if needed
    sch_radiant_switchover = model.getScheduleRulesetByName('Radiant System Switchover')
    if sch_radiant_switchover.is_initialized
      sch_radiant_switchover = sch_radiant_switchover.get
    else
      sch_radiant_switchover = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                               switch_over_time,
                                                                                               name: 'Radiant System Switchover',
                                                                                               schedule_type_limit: 'Dimensionless')
    end

    # set radiant system switchover schedule
    radiant_loop.setChangeoverDelayTimePeriodSchedule(sch_radiant_switchover.to_Schedule.get)

    if slab_setpoint_oa_control
      # get weather file from model
      weather_file = model.getWeatherFile
      if weather_file.initialized
        # get annual outdoor dry bulb temperature
        annual_oat = weather_file.file.get.data.collect { |dat| dat.dryBulbTemperature.get }

        # calculate a nhrs rolling average from annual outdoor dry bulb temperature
        nhrs = 24
        last_nhrs_oat_in_year = annual_oat.last(nhrs - 1)
        combined_oat = last_nhrs_oat_in_year + annual_oat
        oat_rolling_average = combined_oat.each_cons(nhrs).map { |e| e.reduce(&:+).fdiv(nhrs).round(2) }

        # use rolling average to calculate slab setpoint temperature

        # convert temperature from IP to SI units
        slab_sp_at_oat_low_si = OpenStudio.convert(slab_sp_at_oat_low, 'F', 'C').get
        slab_oat_low_si = OpenStudio.convert(slab_oat_low, 'F', 'C').get
        slab_sp_at_oat_high_si = OpenStudio.convert(slab_sp_at_oat_high, 'F', 'C').get
        slab_oat_high_si = OpenStudio.convert(slab_oat_high, 'F', 'C').get

        # calculate relationship between slab setpoint and slope
        slope_num = slab_sp_at_oat_high_si - slab_sp_at_oat_low_si
        slope_den = slab_oat_high_si - slab_oat_low_si
        sp_and_oat_slope = slope_num.fdiv(slope_den).round(4)

        slab_setpoint = oat_rolling_average.map { |e| (slab_sp_at_oat_low_si + ((e - slab_oat_low_si) * sp_and_oat_slope)).round(1) }

        # input upper limits on slab setpoint
        slab_sp_upper_limit = [slab_sp_at_oat_high_si, slab_sp_at_oat_low_si].max
        slab_sp_lower_limit = [slab_sp_at_oat_high_si, slab_sp_at_oat_low_si].min
        slab_setpoint.map! { |e| e > slab_sp_upper_limit ? slab_sp_upper_limit.round(1) : e }

        # input lower limits on slab setpoint
        slab_setpoint.map! { |e| e < slab_sp_lower_limit ? slab_sp_lower_limit.round(1) : e }

        # convert to timeseries
        yd = model.getYearDescription
        start_date = yd.makeDate(1, 1)
        interval = OpenStudio::Time.new(1.0 / 24.0)
        time_series = OpenStudio::TimeSeries.new(start_date, interval, OpenStudio.createVector(slab_setpoint), 'C')

        # check for pre-existing schedule in model
        schedule_interval = model.getScheduleByName('Sch_Radiant_SlabSetP_Based_On_Rolling_Mean_OAT')
        if schedule_interval.is_initialized && schedule_interval.get.to_ScheduleFixedInterval.is_initialized
          schedule_interval = schedule_interval.get.to_ScheduleFixedInterval.get
          schedule_interval.setTimeSeries(time_series)
        else
          # create fixed interval schedule for slab setpoint
          schedule_interval = OpenStudio::Model::ScheduleFixedInterval.new(model)
          schedule_interval.setName('Sch_Radiant_SlabSetP_Based_On_Rolling_Mean_OAT')
          schedule_interval.setTimeSeries(time_series)
          sch_type_limits_obj = OpenstudioStandards::Schedules.create_schedule_type_limits(model, standard_schedule_type_limit: 'Temperature')
          schedule_interval.setScheduleTypeLimits(sch_type_limits_obj)
        end

        # assign slab setpoint schedule
        coil_heating_radiant.setHeatingControlTemperatureSchedule(sch_radiant_slab_setp)
        coil_cooling_radiant.setCoolingControlTemperatureSchedule(sch_radiant_slab_setp)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model',
                           'Model does not have a weather file associated with it. Define to implement slab setpoint based on outdoor weather.')
      end
    else
      # radiant system cooling control setpoint
      slab_setpoint = 22
      sch_radiant_clgsetp = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                            slab_setpoint + 0.1,
                                                                                            name: "#{zone_name}_Sch_Radiant_ClgSetP",
                                                                                            schedule_type_limit: 'Temperature')
      coil_cooling_radiant.setCoolingControlTemperatureSchedule(sch_radiant_clgsetp)

      # radiant system heating control setpoint
      sch_radiant_htgsetp = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                            slab_setpoint,
                                                                                            name: "#{zone_name}_Sch_Radiant_HtgSetP",
                                                                                            schedule_type_limit: 'Temperature')
      coil_heating_radiant.setHeatingControlTemperatureSchedule(sch_radiant_htgsetp)
    end
  end
end
