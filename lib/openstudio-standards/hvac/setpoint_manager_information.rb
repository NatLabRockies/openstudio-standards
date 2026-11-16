module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Setpoint Managers:Information
    # Methods to get information about setpoint managers

    # Get the min and max setpoint values for a setpoint manager
    #
    # @param spm [<OpenStudio::Model::SetpointManager>] OpenStudio SetpointManager object
    # @return [Hash] returns as hash with 'min_temp' and 'max_temp' in degrees Fahrenheit
    def self.setpoint_manager_min_max_temperature(spm)
      # use @standard to not build each time
      std = Standard.build('90.1-2013') # unused; just to access methods
      # Determine the min and max design temperatures
      loop_op_min_f = nil
      loop_op_max_f = nil
      obj_type = spm.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_SetpointManager_Scheduled'
        sch = spm.to_SetpointManagerScheduled.get.schedule
        if sch.to_ScheduleRuleset.is_initialized
          min_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(sch.to_ScheduleRuleset.get)['min']
          max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(sch.to_ScheduleRuleset.get)['max']
        elsif sch.to_ScheduleConstant.is_initialized
          min_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(sch.to_ScheduleConstant.get)['min']
          max_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(sch.to_ScheduleConstant.get)['max']
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC', "Could not find min and max values for #{obj_type} Setpoint Manager.")
        end
        loop_op_min_f = OpenStudio.convert(min_c, 'C', 'F').get
        loop_op_max_f = OpenStudio.convert(max_c, 'C', 'F').get
      when 'OS_SetpointManager_SingleZone_Reheat'
        spm = spm.to_SetpointManagerSingleZoneReheat.get
        loop_op_min_f = OpenStudio.convert(spm.minimumSupplyAirTemperature, 'C', 'F').get
        loop_op_max_f = OpenStudio.convert(spm.maximumSupplyAirTemperature, 'C', 'F').get
      when 'OS_SetpointManager_Warmest'
        spm = spm.to_SetpointManagerWarmest.get
        loop_op_min_f = OpenStudio.convert(spm.minimumSetpointTemperature, 'C', 'F').get
        loop_op_max_f = OpenStudio.convert(spm.maximumSetpointTemperature, 'C', 'F').get
      when 'OS_SetpointManager_WarmestTemperatureFlow'
        spm = spm.to_SetpointManagerWarmestTemperatureFlow.get
        loop_op_min_f = OpenStudio.convert(spm.minimumSetpointTemperature, 'C', 'F').get
        loop_op_max_f = OpenStudio.convert(spm.maximumSetpointTemperature, 'C', 'F').get
      when 'OS_SetpointManager_Scheduled_DualSetpoint'
        spm = spm.to_SetpointManagerScheduledDualSetpoint.get
        # Lowest setpoint is minimum of low schedule
        low_sch = spm.lowSetpointSchedule
        unless low_sch.empty?
          low_sch = low_sch.get
          min_c = nil
          if low_sch.to_ScheduleRuleset.is_initialized
            min_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(low_sch.to_ScheduleRuleset.get)['min']
          elsif low_sch.to_ScheduleConstant.is_initialized
            min_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(low_sch.to_ScheduleConstant.get)['min']
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC', "Could not find min and max values for #{obj_type} Setpoint Manager.")
          end
          loop_op_min_f = OpenStudio.convert(min_c, 'C', 'F').get unless min_c.nil?
        end

        # highest setpoint it maximum of high schedule
        high_sch = spm.highSetpointSchedule
        unless high_sch.empty?
          high_sch = high_sch.get
          max_c = nil
          if high_sch.to_ScheduleRuleset.is_initialized
            max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(high_sch.to_ScheduleRuleset.get)['max']
          elsif high_sch.to_ScheduleConstant.is_initialized
            max_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(high_sch.to_ScheduleConstant.get)['max']
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC', "Could not find min and max values for #{obj_type} Setpoint Manager.")
          end
          loop_op_max_f = OpenStudio.convert(max_c, 'C', 'F').get unless max_c.nil?
        end
      when 'OS_SetpointManager_OutdoorAirReset'
        spm = spm.to_SetpointManagerOutdoorAirReset.get
        temp_1_f = OpenStudio.convert(spm.setpointatOutdoorHighTemperature, 'C', 'F').get
        temp_2_f = OpenStudio.convert(spm.setpointatOutdoorLowTemperature, 'C', 'F').get
        loop_op_min_f = [temp_1_f, temp_2_f].min
        loop_op_max_f = [temp_1_f, temp_2_f].max
      when 'OS_SetpointManager_FollowOutdoorAirTemperature'
        spm = spm.to_SetpointManagerFollowOutdoorAirTemperature.get
        loop_op_min_f = OpenStudio.convert(spm.minimumSetpointTemperature, 'C', 'F').get
        loop_op_max_f = OpenStudio.convert(spm.maximumSetpointTemperature, 'C', 'F').get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC', "Could not find min and max values for #{obj_type} Setpoint Manager.")
      end

      return { 'min_temp' => loop_op_min_f, 'max_temp' => loop_op_max_f }
    end
  end
end
