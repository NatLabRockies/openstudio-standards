# Methods to create and modify parametric schedules
module OpenstudioStandards
  module Schedules
    # @!group Parametric

    # @!group Parametric:Model

    # This method looks at occupancy profiles for the building as a whole and generates an hours of operation default
    # schedule for the building. It also clears out any higher level hours of operation schedule assignments.
    # Spaces are organized by res and non_res. Whichever of the two groups has higher design level of people is used for building hours of operation
    # Resulting hours of operation can have as many rules as necessary to describe the operation.
    # Each ScheduleDay should be an on/off schedule with only values of 0 and 1. There should not be more than one on/off cycle per day.
    # In future this could create different hours of operation for residential vs. non-residential, by building type, story, or space type.
    # However this measure is a stop gap to convert old generic schedules to parametric schedules.
    # Future new schedules should be designed as paramtric from the start and would not need to run through this inference process
    #
    # @author David Goldwasser
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param fraction_of_daily_occ_range [Double] fraction above/below daily min range required to start and end hours of operation
    # @param invert_res [Boolean] if true will reverse hours of operation for residential space types
    # @param gen_occ_profile [Boolean] if true creates a merged occupancy schedule for diagnostic purposes. This schedule is added to the model but no specifically returned by this method
    # @return [ScheduleRuleset] schedule that is assigned to the building as default hours of operation
    def self.model_infer_hours_of_operation_building(model, fraction_of_daily_occ_range: 0.25, invert_res: true, gen_occ_profile: false)
      # create an array of non-residential and residential spaces
      res_spaces = []
      non_res_spaces = []
      res_people_design = 0
      non_res_people_design = 0
      model.getSpaces.sort.each do |space|
        if OpenstudioStandards::Space.space_residential?(space)
          res_spaces << space
          res_people_design += space.numberOfPeople * space.multiplier
        else
          non_res_spaces << space
          non_res_people_design += space.numberOfPeople * space.multiplier
        end
      end
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Parametric.Model', "Model has design level of #{non_res_people_design.round(2)} people in non residential spaces and #{res_people_design.round(2)} people in residential spaces.")

      # # create merged schedule for prevalent type (not used but can be generated for diagnostics)
      # if gen_occ_profile
      #   res_prevalent = false
      #   if res_people_design > non_res_people_design
      #     occ_merged = OpenstudioStandards::Space.spaces_get_occupancy_schedule(res_spaces, sch_name: 'Calculated Occupancy Fraction Residential Merged')
      #     res_prevalent = true
      #   else
      #     occ_merged = OpenstudioStandards::Space.spaces_get_occupancy_schedule(non_res_spaces, sch_name: 'Calculated Occupancy Fraction NonResidential Merged')
      #   end
      # end

      # re-run spaces_get_occupancy_schedule with x above min occupancy to create on/off schedule
      if res_people_design > non_res_people_design
        hours_of_operation = OpenstudioStandards::Space.spaces_get_occupancy_schedule(res_spaces,
                                                                                      sch_name: 'Building Hours of Operation Residential',
                                                                                      occupied_percentage_threshold: fraction_of_daily_occ_range,
                                                                                      threshold_calc_method: 'normalized_daily_range')
        res_prevalent = true
      else
        hours_of_operation = OpenstudioStandards::Space.spaces_get_occupancy_schedule(non_res_spaces,
                                                                                      sch_name: 'Building Hours of Operation NonResidential',
                                                                                      occupied_percentage_threshold: fraction_of_daily_occ_range,
                                                                                      threshold_calc_method: 'normalized_daily_range')
      end

      # remove gaps resulting in multiple on off cycles for each rule in schedule so it will be valid hours of operation
      profiles = []
      profiles << hours_of_operation.defaultDaySchedule
      hours_of_operation.scheduleRules.each do |rule|
        profiles << rule.daySchedule
      end
      profiles.sort.each do |profile|
        times = profile.times
        values = profile.values
        next if times.size <= 3 # length of 1-3 should produce valid hours_of_operation profiles

        # Find the latest time where the value == 1
        latest_time = nil
        times.zip(values).each do |time, value|
          if value > 0
            latest_time = time
          end
        end
        # Skip profiles that are zero all the time
        next if latest_time.nil?

        # Calculate the duration from this point to midnight
        wrap_dur_left_hr = 0
        if values.first == 0 && values.last == 0
          wrap_dur_left_hr = 24.0 - latest_time.totalHours
        end

        # calculate time at first start
        first_start_time = times[values.index(0)].totalHours

        occ_gap_hash = {}
        prev_time = 0
        prev_val = nil
        times.each_with_index do |time, i|
          next if time.totalHours == 0.0 # should not see this
          next if values[i] == prev_val # check if two 0 until time next to each other

          if values[i] == 0 # only store vacant segments
            if time.totalHours == 24
              occ_gap_hash[prev_time] = wrap_dur_left_hr + first_start_time
            else
              occ_gap_hash[prev_time] = time.totalHours - prev_time
            end
          end
          prev_time = time.totalHours
          prev_val = values[i]
        end
        profile.clearValues
        max_occ_gap_start = occ_gap_hash.key(occ_gap_hash.values.max)
        max_occ_gap_end_hr = max_occ_gap_start + occ_gap_hash[max_occ_gap_start] # can't add time and duration in hours
        if max_occ_gap_end_hr > 24.0 then max_occ_gap_end_hr -= 24.0 end

        # time for gap start
        target_start_hr = max_occ_gap_start.truncate
        target_start_min = ((max_occ_gap_start - target_start_hr) * 60.0).truncate
        max_occ_gap_start = OpenStudio::Time.new(0, target_start_hr, target_start_min, 0)

        # time for gap end
        target_end_hr = max_occ_gap_end_hr.truncate
        target_end_min = ((max_occ_gap_end_hr - target_end_hr) * 60.0).truncate
        max_occ_gap_end = OpenStudio::Time.new(0, target_end_hr, target_end_min, 0)

        profile.addValue(max_occ_gap_start, 1)
        profile.addValue(max_occ_gap_end, 0)
        os_time_24 = OpenStudio::Time.new(0, 24, 0, 0)
        if max_occ_gap_start > max_occ_gap_end
          profile.addValue(os_time_24, 0)
        else
          profile.addValue(os_time_24, 1)
        end
      end

      # reverse 1 and 0 values for res_prevalent building
      # currently spaces_get_occupancy_schedule doesn't use defaultDayProflie, so only inspecting rules for now.
      if invert_res && res_prevalent
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Parametric.Model', 'Per argument passed in, hours of operation are being inverted for buildings with more people in residential versus non-residential spaces.')
        hours_of_operation.scheduleRules.each do |rule|
          profile = rule.daySchedule
          times = profile.times
          values = profile.values
          profile.clearValues
          times.each_with_index do |time, i|
            orig_val = values[i]
            new_value = nil
            if orig_val == 0 then new_value = 1 end
            if orig_val == 1 then new_value = 0 end
            profile.addValue(time, new_value)
          end
        end
      end

      # set hours of operation for building level hours of operation
      model.getDefaultScheduleSets.each(&:resetHoursofOperationSchedule)
      if model.getBuilding.defaultScheduleSet.is_initialized
        default_sch_set = model.getBuilding.defaultScheduleSet.get
      else
        default_sch_set = OpenStudio::Model::DefaultScheduleSet.new(model)
        default_sch_set.setName('Building Default Schedule Set')
        model.getBuilding.setDefaultScheduleSet(default_sch_set)
      end
      default_sch_set.setHoursofOperationSchedule(hours_of_operation)

      return hours_of_operation
    end

    # This method users the hours of operation for a space and the existing ScheduleRuleset profiles to setup parametric schedule
    # inputs. Inputs include one or more load profile formulas. Data is stored in model attributes for downstream
    # application. This should impact all ScheduleRuleset objects in the model. Plant and Air loop hours of operations
    # should be traced back to a space or spaces.
    #
    # @author David Goldwasser
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param step_ramp_logic [String] type of step logic to use - @TODO: this is currently not used
    # @param infer_hoo_for_non_assigned_objects [Boolean] attempt to get hours of operation for objects like swh with and exterior lighting
    # @param gather_data_only [Boolean] false (stops method before changes made if true)
    # @param hoo_var_method [String] accepts 'hours' or 'fractional'. Any other value value will result in hour of operation variables not being applied
    #   Options are 'hours', 'fractional'
    # @return [Hash] schedule is key, value is hash of number of objects
    def self.model_setup_parametric_schedules(model,
                                              step_ramp_logic: nil,
                                              infer_hoo_for_non_assigned_objects: true,
                                              gather_data_only: false,
                                              hoo_var_method: 'hours')
      parametric_inputs = {}
      default_sch_type = OpenStudio::Model::DefaultScheduleType.new('HoursofOperationSchedule')
      # thermal zones, air loops, plant loops will require some logic if they refer to more than one hours of operaiton schedule.
      # for initial use case while have same horus of operaiton so this can be pretty simple, but will have to re-visit it sometime
      # possible solution A: choose hoo that contributes the largest fraction of floor area
      # possible solution B: expand the hours of operation for a given day to include combined range of hoo objects
      # whatever approach is used for gathering parametric inputs for existing ruleset schedules should also be used for model_apply_parametric_schedules

      # loop through spaces (trace hours of operation back to space)
      OpenstudioStandards::Schedules.spaces_space_types_get_parametric_schedule_inputs(model.getSpaces, parametric_inputs, gather_data_only)

      # loop through space types (trace hours of operation back to space type).
      OpenstudioStandards::Schedules.spaces_space_types_get_parametric_schedule_inputs(model.getSpaceTypes, parametric_inputs, gather_data_only)

      # loop through thermal zones (trace hours of operation back to spaces in thermal zone)
      thermal_zone_hash = {} # key is zone and hash is hours of operation
      model.getThermalZones.sort.each do |zone|
        # identify hours of operation
        hours_of_operation = OpenstudioStandards::Space.spaces_hours_of_operation(zone.spaces)
        thermal_zone_hash[zone] = hours_of_operation
        # get thermostat setpoint schedules
        if zone.thermostatSetpointDualSetpoint.is_initialized
          thermostat = zone.thermostatSetpointDualSetpoint.get
          if thermostat.heatingSetpointTemperatureSchedule.is_initialized && thermostat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.is_initialized
            schedule = thermostat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
            OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, thermostat, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: 'tstat')
          end
          if thermostat.coolingSetpointTemperatureSchedule.is_initialized && thermostat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.is_initialized
            schedule = thermostat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
            OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, thermostat, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: 'tstat')
          end
        end
      end

      # loop through air loops (trace hours of operation back through spaces served by air loops)
      air_loop_hash = {} # key is zone and hash is hours of operation
      model.getAirLoopHVACs.sort.each do |air_loop|
        # identify hours of operation
        air_loop_spaces = []
        air_loop.thermalZones.sort.each do |zone|
          air_loop_spaces += zone.spaces
        end
        hours_of_operation = OpenstudioStandards::Space.spaces_hours_of_operation(air_loop_spaces)
        air_loop_hash[air_loop] = hours_of_operation
        if air_loop.availabilitySchedule.to_ScheduleRuleset.is_initialized
          schedule = air_loop.availabilitySchedule.to_ScheduleRuleset.get
          OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, air_loop, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: hoo_var_method)
        end
        avail_mgrs = air_loop.availabilityManagers
        avail_mgrs.sort.each do |avail_mgr|
          # @todo I'm finding availability mangers, but not any resources for them, even if I use OpenStudio::Model.getRecursiveChildren(avail_mgr)
          resources = avail_mgr.resources
          resources = OpenStudio::Model.getRecursiveResources(avail_mgr)
          resources.sort.each do |resource|
            if resource.to_ScheduleRuleset.is_initialized
              schedule = resource.to_ScheduleRuleset.get
              OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, avail_mgr, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: hoo_var_method)
            end
          end
        end
      end

      # look through all model HVAC components find scheduleRuleset objects, resources, that use them and zone or air loop for hours of operation
      hvac_components = model.getHVACComponents
      hvac_components.sort.each do |component|
        # identify zone, or air loop it refers to, some may refer to plant loop, OA or other component
        thermal_zone = nil
        air_loop = nil
        plant_loop = nil
        schedules = []
        if component.to_ZoneHVACComponent.is_initialized && component.to_ZoneHVACComponent.get.thermalZone.is_initialized
          thermal_zone = component.to_ZoneHVACComponent.get.thermalZone.get
        end
        if component.airLoopHVAC.is_initialized
          air_loop = component.airLoopHVAC.get
        end
        if component.plantLoop.is_initialized
          plant_loop = component.plantLoop.get
        end
        component.resources.sort.each do |resource|
          if resource.to_ThermalZone.is_initialized
            thermal_zone = resource.to_ThermalZone.get
          elsif resource.to_ScheduleRuleset.is_initialized
            schedules << resource.to_ScheduleRuleset.get
          end
        end

        # inspect resources for children of objects found in thermal zone or plant loop
        # get objects like OA controllers and unitary object components
        next if thermal_zone.nil? && air_loop.nil?

        children = OpenStudio::Model.getRecursiveChildren(component)
        children.sort.each do |child|
          child.resources.sort.each do |sub_resource|
            if sub_resource.to_ScheduleRuleset.is_initialized
              schedules << sub_resource.to_ScheduleRuleset.get
            end
          end
        end

        # process schedules found for this component
        schedules.sort.each do |schedule|
          hours_of_operation = nil
          if !thermal_zone.nil?
            hours_of_operation = thermal_zone_hash[thermal_zone]
          elsif !air_loop.nil?
            hours_of_operation = air_loop_hash[air_loop]
          elsif !plant_loop.nil?
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Parametric.Model', "#{schedule.name.get} is associated with plant loop, will not gather parametric inputs")
            next
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.Model', "Cannot identify where #{component.name.get} is in system. Will not gather parametric inputs for #{schedule.name.get}")
            next
          end
          OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, component, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: hoo_var_method)
        end
      end

      # @todo Service Water Heating supply side (may or may not be associated with a space)
      # @todo water use equipment definitions (temperature, sensible, latent) may be in multiple spaces, need to identify hoo, but typically constant schedules

      # water use equipment (flow rate fraction)
      # @todo address common schedules used across multiple instances
      model.getWaterUseEquipments.sort.each do |water_use_equipment|
        if water_use_equipment.flowRateFractionSchedule.is_initialized && water_use_equipment.flowRateFractionSchedule.get.to_ScheduleRuleset.is_initialized
          schedule = water_use_equipment.flowRateFractionSchedule.get.to_ScheduleRuleset.get
          next if parametric_inputs.key?(schedule)

          opt_space = water_use_equipment.space
          if opt_space.is_initialized
            space = opt_space.get
            hours_of_operation = OpenstudioStandards::Space.space_hours_of_operation(space)
            OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, water_use_equipment, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: hoo_var_method)
          else
            hours_of_operation = OpenstudioStandards::Space.spaces_hours_of_operation(model.getSpaces)
            if !hours_of_operation.nil?
              OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(schedule, water_use_equipment, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: hoo_var_method)
            end
          end

        end
      end
      # @todo Refrigeration (will be associated with thermal zone)
      # @todo exterior lights (will be astronomical, but like AEDG's may have reduction later at night)

      return parametric_inputs
    end

    # This method applies the hours of operation for a space and the load profile formulas in the overloaded ScheduleRulset
    # objects to update time value pairs for ScheduleDay objects. Object type specific logic will be used to generate profiles
    # for summer and winter design days.
    #
    # @note This measure will replace any prior chagnes made to ScheduleRule objects with new ScheduleRule values from
    # profile formulas
    # @author David Goldwasser
    # @param model [OpenStudio::Model::Model] OpenStudio Model object
    # @param ramp_frequency [Double] ramp frequency in minutes. If nil method will match simulation timestep
    # @param infer_hoo_for_non_assigned_objects [Boolean] # attempt to get hoo for objects like swh with and exterior lighting
    # @param error_on_out_of_order [Boolean] true will error if applying formula creates out of order values
    # @return [Array] of modified ScheduleRuleset objects
    def self.model_apply_parametric_schedules(model,
                                              ramp_frequency: nil,
                                              infer_hoo_for_non_assigned_objects: true,
                                              error_on_out_of_order: true)
      # get ramp frequency (fractional hour) from timestep
      if ramp_frequency.nil?
        steps_per_hour = if model.getSimulationControl.timestep.is_initialized
                           model.getSimulationControl.timestep.get.numberOfTimestepsPerHour
                         else
                           6 # default OpenStudio timestep if none specified
                         end
        ramp_frequency = 1.0 / steps_per_hour.to_f
      end

      # Go through model and create parametric formulas for all schedules
      parametric_inputs = OpenstudioStandards::Schedules.model_setup_parametric_schedules(model, gather_data_only: true)

      parametric_schedules = []
      model.getScheduleRulesets.sort.each do |sch|
        if !sch.hasAdditionalProperties || !sch.additionalProperties.hasFeature('param_sch_ver')
          # for now don't look at schedules without targets, in future can alter these by looking at building level hours of operation
          next if sch.directUseCount <= 0 # won't catch if used for space type load instance, but that space type isn't used

          # @todo address schedules that fall into this category, if they are used in the model
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.Model', "For #{sch.sources.first.name}, #{sch.name} is not setup as parametric schedule. It has #{sch.sources.size} sources.")
          next
        end

        # apply parametric inputs
        OpenstudioStandards::Schedules.schedule_ruleset_apply_parametric_inputs(sch, ramp_frequency, infer_hoo_for_non_assigned_objects, error_on_out_of_order, parametric_inputs)

        # add schedule to array
        parametric_schedules << sch
      end

      return parametric_schedules
    end

    # @!endgroup Parametric:Model

    # @!group Parametric:Spaces

    # Gathers parametric inputs for all loads objects associated with spaces/space types in provided array.
    # Parametric formulas are encoded in AdditionalProperties objects attached to the ScheduleRuleset.
    #
    # @author David Goldwasser
    # @param spaces_space_types [Array] array of OpenStudio::Model::Space or OpenStudio::Model::SpaceType objects
    # @param parametric_inputs [Hash] parametric inputs hash of ScheduleRuleset, example:
    #   {
    #     floor: schedule floor,
    #     ceiling: schedule ceiling,
    #     target: load instance,
    #     hoo_inputs: hours_of_operation hash
    #   }
    # @param gather_data_only [Boolean] if true, no changes will be made to schedules
    # @return [Hash] parametric inputs hash of ScheduleRuleset, example:
    #   {
    #     floor: schedule floor,
    #     ceiling: schedule ceiling,
    #     target: load instance,
    #     hoo_inputs: hours_of_operation hash
    #   }
    def self.spaces_space_types_get_parametric_schedule_inputs(spaces_space_types, parametric_inputs, gather_data_only)
      spaces_space_types.each do |space_type|
        # get hours of operation for space type once
        next if space_type.instance_of?(OpenStudio::Model::SpaceType) && space_type.floorArea == 0

        hours_of_operation = Space.space_hours_of_operation(space_type)
        if hours_of_operation.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.Space', "Can't evaluate schedules for #{space_type.name}, doesn't have hours of operation.")
          next
        end
        # loop through internal load instances
        space_type.lights.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.luminaires.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.electricEquipment.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.gasEquipment.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.steamEquipment.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.otherEquipment.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.people.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
          if space_load_instance.activityLevelSchedule.is_initialized && space_load_instance.activityLevelSchedule.get.to_ScheduleRuleset.is_initialized
            act_sch = space_load_instance.activityLevelSchedule.get.to_ScheduleRuleset.get
            OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(act_sch, space_load_instance, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: 'hours')
          end
        end
        space_type.spaceInfiltrationDesignFlowRates.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        space_type.spaceInfiltrationEffectiveLeakageAreas.each do |space_load_instance|
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
        end
        dsgn_spec_oa = space_type.designSpecificationOutdoorAir
        if dsgn_spec_oa.is_initialized
          OpenstudioStandards::Space.space_load_instance_get_parametric_schedule_inputs(dsgn_spec_oa.get, parametric_inputs, hours_of_operation, gather_data_only)
        end
      end

      return parametric_inputs
    end

    # @!endgroup Parametric:Spaces

    # @!group Parametric:Schedule

    # Method to process space load instance schedules for model_setup_parametric_schedules
    #
    # @author David Goldwasser
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param space_load_instance [OpenStudio::Model::SpaceLoadInstance] OpenStudio SpaceLoadInstance object
    # @param parametric_inputs [Hash]
    # @param hours_of_operation [Hash] hash, example:
    #   {
    #     profile_index: {
    #       hoo_start: [float] rule operation start hour,
    #       hoo_end: [float] rule operation end hour,
    #       hoo_hours: [float] rule operation duration hours,
    #       days_used: [Array] annual day indices
    #     }
    #   }
    # @param ramp [Boolean] flag to add intermediate values ramp between input schedule values
    # @param min_ramp_dur_hr [Double] minimum time difference to ramp between
    # @param gather_data_only [Boolean] if true, no changes are made to schedules
    # @param hoo_var_method [String] accepts hours and fractional. Any other value value will result in hoo variables not being applied
    # @return [Hash] parametric inputs hash of ScheduleRuleset, example:
    #   {
    #     floor: schedule floor,
    #     ceiling: schedule ceiling,
    #     target: load instance,
    #     hoo_inputs: hours_of_operation hash
    #   }
    def self.schedule_ruleset_get_parametric_inputs(schedule_ruleset, space_load_instance, parametric_inputs, hours_of_operation,
                                                    ramp: true,
                                                    min_ramp_dur_hr: 2.0,
                                                    gather_data_only: false,
                                                    hoo_var_method: 'hours')
      if parametric_inputs.key?(schedule_ruleset) && (hours_of_operation != parametric_inputs[schedule_ruleset][:hoo_inputs]) # don't warn if the hours of operation between old and new schedule are equivalent
        # OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.Schedule', "#{space_load_instance.name} uses #{schedule_ruleset.name} but parametric inputs have already been setup based on hours of operation for #{parametric_inputs[schedule_ruleset][:target].name}.")
        return nil
      end

      # gather and store data for scheduleRuleset
      min_max = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(schedule_ruleset)
      ruleset_hash = { floor: min_max['min'], ceiling: min_max['max'], target: space_load_instance, hoo_inputs: hours_of_operation }
      parametric_inputs[schedule_ruleset] = ruleset_hash

      # stop here if only gathering information otherwise will continue and generate additional parametric properties for schedules and rules
      if gather_data_only then return parametric_inputs end

      # set scheduleRuleset properties
      props = schedule_ruleset.additionalProperties

      # don't need to gather more than once
      return parametric_inputs if props.getFeatureAsString('param_sch_ver') == '0.0.1'

      props.setFeature('param_sch_ver', '0.0.1') # this is needed to see if formulas are in sync with version of standards that processes them also used to flag schedule as parametric
      props.setFeature('param_sch_floor', min_max['min'])
      props.setFeature('param_sch_ceiling', min_max['max'])

      # cleanup existing profiles
      OpenstudioStandards::Schedules.schedule_ruleset_cleanup_profiles(schedule_ruleset)

      # get initial hash of schedule days => rule index values
      schedule_days = OpenstudioStandards::Schedules.schedule_ruleset_get_schedule_day_rule_indices(schedule_ruleset)
      # get all day schedule equivalent full load hours to tag
      daily_flhs = schedule_days.keys.map { |day_sch| OpenstudioStandards::Schedules.schedule_day_get_equivalent_full_load_hours(day_sch) }
      # collect initial rule index => array of days used hash
      sch_ruleset_days_used = OpenstudioStandards::Schedules.schedule_ruleset_get_annual_days_used(schedule_ruleset)

      # match up schedule rule days with hours of operation days
      # sch_day_map is a hash where keys are the rule index values of the schedule
      # and values are hashes where keys are the hours of operation rule index, and values are arrays of days that the schedule
      sch_day_map = {}
      sch_ruleset_days_used.each do |sch_index, sch_days|
        # first create a hash that maps each day index to the hoo index that covers that day
        day_map = {}
        sch_days.each do |day|
          # find the hour of operation rule that contains the day number
          hoo_keys = hours_of_operation.find { |_, val| val[:days_used].include?(day) }
          if hoo_keys.nil?
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.Schedule', "In #{__method__}, cannot find schedule #{schedule_days.key(sch_index).name.get} day #{day} in hour of operation profiles. Something went wrong.")
          end

          hoo_key = hoo_keys.first
          day_map[day] = hoo_key
        end
        # group days with the same hour of operation index
        grouped_days = Hash.new { |h, k| h[k] = [] }
        day_map.each { |day, hoo_idx| grouped_days[hoo_idx] << day }
        # group by schedule rule index
        sch_day_map[sch_index] = grouped_days
      end

      # create new rule corresponding to the hour of operation rules
      new_rule_ct = 0
      rule_idxs_to_keep = []
      sch_day_map.each do |sch_index, hoo_group|
        hoo_group.each do |hoo_index, day_group|
          # skip common default days
          next if sch_index == -1 && hoo_index == -1

          # skip if rules already match
          if (sch_ruleset_days_used[sch_index] - day_group).empty?
            # OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.Schedules', "in #{__method__}: #{schedule_ruleset.name} rule #{sch_index} already matches hours of operation rule #{hoo_index}; new rule won't be created.")
            # keep these rules index values to avoid deleting later
            rule_idxs_to_keep << sch_index unless sch_index == -1
            next
          end
          # create new rules
          new_rules = OpenstudioStandards::Schedules.schedule_ruleset_create_rules_from_day_list(schedule_ruleset, day_group, schedule_day: schedule_days.key(sch_index))
          new_rule_ct += new_rules.size
        end
      end
      # new rules are created at top of list - cleanup old rules that have been replaced
      if !(new_rule_ct == 0 || new_rule_ct == schedule_ruleset.scheduleRules.size)
        # increase index values by the number of new rules
        rule_idxs_adjusted = rule_idxs_to_keep.map { |v| v + new_rule_ct }
        rules_to_remove = []
        schedule_ruleset.scheduleRules.each_with_index do |rule, i|
          # don't remove new rules or rules that already match
          if (rule.ruleIndex > new_rule_ct - 1) && !rule_idxs_adjusted.include?(rule.ruleIndex)
            rules_to_remove << rule
          end
        end
        rules_to_remove.each(&:remove)
      end

      # re-collect new schedule rules
      schedule_days = OpenstudioStandards::Schedules.schedule_ruleset_get_schedule_day_rule_indices(schedule_ruleset)
      # re-collect new rule index => days used array
      sch_ruleset_days_used = OpenstudioStandards::Schedules.schedule_ruleset_get_annual_days_used(schedule_ruleset)

      # step through profiles and add additional properties to describe profiles
      schedule_days.each_with_index do |(schedule_day, current_rule_index), i|
        hoo_target_index = nil

        days_used = sch_ruleset_days_used[current_rule_index]

        # find days_used in hoo profiles that contains all days used from this profile
        hoo_profile_match_hash = {}
        best_fit_check = {}

        # loop through indices looking of rule in hoo that contains all days in the rule
        hours_of_operation.each do |profile_index, value|
          if (days_used - value[:days_used]).empty?
            hoo_target_index = profile_index
          end
        end

        # if schedule day days used can't be mapped to single hours of operation then do not use hoo variables, otherwise would have to split rule and alter model
        if hoo_target_index.nil?

          hoo_start = nil
          hoo_end = nil
          occ = nil
          vac = nil
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.Schedules', "In #{__method__}, schedule #{schedule_day.name} has no hours_of_operation target index. Won't be modified")
          # OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.Schedules', "In #{__method__}, schedule #{schedule_day.name} has no hours_of_operation target index. Won't be modified")
        else
          # get hours of operation for this specific profile
          hoo_start = hours_of_operation[hoo_target_index][:hoo_start]
          hoo_end = hours_of_operation[hoo_target_index][:hoo_end]
          occ = hours_of_operation[hoo_target_index][:hoo_hours]
          vac = 24.0 - hours_of_operation[hoo_target_index][:hoo_hours]
        end

        props = schedule_day.additionalProperties
        par_val_time_hash = {} # time is key, value is value in and optional value out as a one or two object array
        times = schedule_day.times
        values = schedule_day.values
        values.each_with_index do |value, j|
          # don't add value until 24 if it is the same as first value for non constant profiles
          if values.size > 1 && j == values.size - 1 && value == values.first
            next
          end

          current_time = times[j].totalHours
          # if step height goes floor to ceiling then do not ramp.
          if !ramp || (values.uniq.size < 3)
            # this will result in steps like old profiles, update to ramp in most cases
            if j == values.size - 1
              par_val_time_hash[current_time] = [value, values.first]
            else
              par_val_time_hash[current_time] = [value, values[j + 1]]
            end
          else
            if j == 0
              prev_time = times.last.totalHours - 24 # e.g. 24 would show as until 0
            else
              prev_time = times[j - 1].totalHours
            end
            if j == values.size - 1
              next_time = times.first.totalHours + 24 # e.g. 6 would show as until 30
              next_value = values.first

              # do nothing if value is same as first value
              if value == next_value
                next
              end

            else
              next_time = times[j + 1].totalHours
              next_value = values[j + 1]
            end
            # delta time is min min_ramp_dur_hr, half of previous dur, half of next dur
            # todo - would be nice to change to 0.25 for vally less than 2 hours
            multiplier = 0.5
            delta = [min_ramp_dur_hr, (current_time - prev_time) * multiplier, (next_time - current_time) * multiplier].min
            # add value to left if not already added
            if !par_val_time_hash.key?(current_time - delta)
              time_left = current_time - delta
              if time_left < 0.0 then time_left += 24.0 end
              par_val_time_hash[time_left] = [value]
            end
            # add value to right
            time_right = current_time + delta
            if time_right > 24.0 then time_right -= 24.0 end
            par_val_time_hash[time_right] = [next_value]
          end
        end

        # sort hash by keys
        par_val_time_hash.sort.to_h

        # calculate estimated value (not including any secondary logic)
        est_daily_flh = 0.0
        prev_time = par_val_time_hash.keys.max - 24.0
        prev_value = par_val_time_hash.values.last.last # last value in last optional pair of values
        par_val_time_hash.sort.each do |time, value_array|
          segment_length = time - prev_time
          avg_value = (value_array.first + prev_value) * 0.5
          est_daily_flh += segment_length * avg_value
          prev_time = time
          prev_value = value_array.last
        end

        # test expected value against estimated value
        daily_flh = OpenstudioStandards::Schedules.schedule_day_get_equivalent_full_load_hours(schedule_day)
        percent_change = ((daily_flh - est_daily_flh) / daily_flh) * 100.0
        if percent_change.abs > 0.05
          # @todo this estimation can have flaws. Fix or remove it, make sure to update for secondary logic (if we implement that here)
          # post application checks compares against actual instead of estimated values
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.Schedule', "For day schedule #{schedule_day.name} in #{schedule_ruleset.name} there was a #{percent_change.round(4)}% change. Expected full load hours is #{daily_flh.round(4)}, but estimated value is #{est_daily_flh.round(4)}")
        end

        # puts "#{schedule_day.name}: par_val_time_hash: #{par_val_time_hash}"

        raw_string = []
        # flags to control variable settings for tstats
        start_set = false
        end_set = false
        par_val_time_hash.sort.each do |time, value_array|
          # add in value variables
          # not currently using range, only using min max for constant schedules or schedules with just two values
          value_array_var = []
          value_array.each do |val|
            if val == min_max['min'] && values.uniq.size < 3
              value_array_var << 'val_flr'
            elsif val == min_max['max'] && values.uniq.size < 3
              value_array_var << 'val_clg'
            else
              value_array_var << val
            end
          end

          # add in hoo variables when matching profile found
          if !hoo_start.nil?

            # identify which identifier (star,mid,end) time is closest to, which will impact formula structure
            # includes code to identify delta for wrap around of 24
            formula_identifier = {}
            start_delta_array = [hoo_start - time, hoo_start - time + 24, hoo_start - time - 24]
            start_delta_array_abs = [(hoo_start - time).abs, (hoo_start - time + 24).abs, (hoo_start - time - 24).abs]
            start_delta_h = start_delta_array[start_delta_array_abs.index(start_delta_array_abs.min)]
            formula_identifier['start'] = start_delta_h
            mid_calc = hoo_start + (occ * 0.5)
            mid_delta_array = [mid_calc - time, mid_calc - time + 24, mid_calc - time - 24]
            mid_delta_array_abs = [(mid_calc - time).abs, (mid_calc - time + 24).abs, (mid_calc - time - 24).abs]
            mid_delta_h = mid_delta_array[mid_delta_array_abs.index(mid_delta_array_abs.min)]
            formula_identifier['mid'] = mid_delta_h
            end_delta_array = [hoo_end - time, hoo_end - time + 24, hoo_end - time - 24]
            end_delta_array_abs = [(hoo_end - time).abs, (hoo_end - time + 24).abs, (hoo_end - time - 24).abs]
            end_delta_h = end_delta_array[end_delta_array_abs.index(end_delta_array_abs.min)]
            formula_identifier['end'] = end_delta_h

            # need to store min absolute value to pick the best fit
            formula_identifier_min_abs = {}
            formula_identifier.each do |k, v|
              formula_identifier_min_abs[k] = v.abs
            end
            # puts formula_identifier
            # puts formula_identifier_min_abs
            # pick from possible formula approaches for any datapoint where x is hour value
            min_key = formula_identifier_min_abs.key(formula_identifier_min_abs.values.min)
            min_value = formula_identifier[min_key]

            case hoo_var_method
            when 'hours'
              # minimize x, which should be no greater than 12, see if rounding to 2 decimal places works
              min_value = min_value.round(2)
              if min_key == 'start'
                if min_value == 0
                  time = 'hoo_start'
                elsif min_value < 0
                  time = "hoo_start + #{min_value.abs}"
                else # greater than 0
                  time = "hoo_start - #{min_value}"
                end
                # puts time
              elsif min_key == 'mid'
                if min_value == 0
                  time = 'mid'
                  # converted to variable for simplicity but could also be described like this
                  # time = "hoo_start + occ * 0.5"
                elsif min_value < 0
                  time = "mid + #{min_value.abs}"
                else # greater than 0
                  time = "mid - #{min_value}"
                end
                # puts time
              else # min_key == "end"
                if min_value == 0
                  time = 'hoo_end'
                elsif min_value < 0
                  time = "hoo_end + #{min_value.abs}"
                else # greater than 0
                  time = "hoo_end - #{min_value}"
                end
                # puts time
              end

            when 'fractional'

              # minimize x(hour before converted to fraction), which should be no greater than 0.5 as fraction, see if rounding to 3 decimal places works
              if occ > 0
                min_value_occ_fract = min_value.abs / occ
              else
                min_value_occ_fract = 0.0
              end
              if vac > 0
                min_value_vac_fract = min_value.abs / vac
              else
                min_value_vac_fract = 0.0
              end
              if min_key == 'start'
                if min_value == 0
                  time = 'hoo_start'
                elsif min_value < 0
                  time = "hoo_start + occ * #{min_value_occ_fract.round(3)}"
                else # greater than 0
                  time = "hoo_start - vac * #{min_value_vac_fract.round(3)}"
                end
              elsif min_key == 'mid'
                # @todo see what is going wrong with after mid in formula
                if min_value == 0
                  time = 'mid'
                  # converted to variable for simplicity but could also be described like this
                  # time = "hoo_start + occ * 0.5"
                elsif min_value < 0
                  time = "mid + occ * #{min_value_occ_fract.round(3)}"
                else # greater than 0
                  time = "mid - occ * #{min_value_occ_fract.round(3)}"
                end
              else # min_key == "end"
                if min_value == 0
                  time = 'hoo_end'
                elsif min_value < 0
                  time = "hoo_end + vac * #{min_value_vac_fract.round(3)}"
                else # greater than 0
                  time = "hoo_end - occ * #{min_value_occ_fract.round(3)}"
                end
              end

            when 'tstat'
              # puts formula_identifier
              if min_key == 'start' && !start_set
                time = 'hoo_start + 0'
                start_set = true
              else
                time = 'hoo_end + 0'
              end
            end
          end

          # populate string
          if value_array_var.size == 1
            raw_string << "#{time} ~ #{value_array_var.first}"
          else # should only have 1 or two values (value in and optional value out)
            raw_string << "#{time} ~ #{value_array_var.first} ~ #{value_array_var.last}"
          end
        end

        # puts "#{schedule_day.name}: param_day_profile: #{raw_string.join(' | ')}"

        # store profile formula with hoo and value variables
        props.setFeature('param_day_profile', raw_string.join(' | '))

        # @todo not used yet, but will add methods described below and others
        # @todo lower infiltration based on air loop hours of operation if air loop has outdoor air object
        # @todo lower lighting or plug loads based on occupancy at given time steps in a space
        # @todo set elevator fraction based multiple factors such as trips, occupants per trip, and elevator type to determine floor consumption when not in use.
        props.setFeature('param_day_secondary_logic', '') # secondary logic method such as occupancy impacting schedule values
        props.setFeature('param_day_secondary_logic_arg_val', '') # optional argument used for some secondary logic applied to values

        # tag profile type
        # may be useful for parametric changes to tag typical, medium, minimal, or same ones with off_peak prefix
        # todo - I would like to use these same tags for hours of operation and have parametric tags then ignore the days of week and date range from the rule object
        # tagging min/max makes sense in fractional schedules but not temperature schedules like thermostats (specifically cooling setpoints)
        # todo - I think these tags should come from occpancy schedule for space(s) schedule. That way all schedules in a space will refer to same profile from hours of operation
        # todo - add school specific logic hear or in post processing, currently default profile for school may not be most prevalent one
        if current_rule_index == -1
          props.setFeature('param_day_tag', 'typical_operation')
        elsif daily_flh == daily_flhs.min
          props.setFeature('param_day_tag', 'minimal_operation')
        elsif daily_flh == daily_flhs.max
          props.setFeature('param_day_tag', 'maximum_operation') # normally this should not be used as typical should be the most active day
        else
          props.setFeature('param_day_tag', 'medium_operation') # not min max or typical
        end
      end

      return parametric_inputs
    end

    # @!endgroup Parametric:Schedule

    # @!group Parametric:ScheduleRuleset

    # Apply specified hours of operation values to rules in this schedule.
    # Weekday values will be applied to the default profile.
    # Weekday values will be applied to any rules that are used on a weekday.
    # Saturday values will be applied to any rules that are used on a Saturday.
    # Sunday values will be applied to any rules that are used on a Sunday.
    # If a rule applies to Weekdays, Saturdays, and/or Sundays, values will be applied in that order of precedence.
    # If a rule does not apply to any of these days, it is unused and will not be modified.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] schedule ruleset object
    # @param wkdy_start_time [OpenStudio::Time] Weekday start time. If nil, no change will be made to this day.
    # @param wkdy_end_time [OpenStudio::Time] Weekday end time.  If greater than 24:00, hours of operation will wrap over midnight.
    # @param sat_start_time [OpenStudio::Time] Saturday start time. If nil, no change will be made to this day.
    # @param sat_end_time [OpenStudio::Time] Saturday end time.  If greater than 24:00, hours of operation will wrap over midnight.
    # @param sun_start_time [OpenStudio::Time] Sunday start time.  If nil, no change will be made to this day.
    # @param sun_end_time [OpenStudio::Time] Sunday end time.  If greater than 24:00, hours of operation will wrap over midnight.
    # @return [Boolean] returns true if successful, false if not
    def self.schedule_ruleset_set_hours_of_operation(schedule_ruleset,
                                                     wkdy_start_time: nil,
                                                     wkdy_end_time: nil,
                                                     sat_start_time: nil,
                                                     sat_end_time: nil,
                                                     sun_start_time: nil,
                                                     sun_end_time: nil)
      # Default day is assumed to represent weekdays
      if wkdy_start_time && wkdy_end_time
        schedule_day_set_hours_of_operation(schedule_ruleset.defaultDaySchedule, wkdy_start_time, wkdy_end_time)
        # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ScheduleRuleset', "For #{schedule_ruleset.name}, set default operating hours to #{wkdy_start_time}-#{wkdy_end_time}.")
      end

      # Modify each rule
      schedule_ruleset.scheduleRules.each do |rule|
        if rule.applyMonday || rule.applyTuesday || rule.applyWednesday || rule.applyThursday || rule.applyFriday
          if wkdy_start_time && wkdy_end_time
            schedule_day_set_hours_of_operation(rule.daySchedule, wkdy_start_time, wkdy_end_time)
            # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ScheduleRuleset', "For #{schedule_ruleset.name}, set Saturday rule operating hours to #{wkdy_start_time}-#{wkdy_end_time}.")
          end
        elsif rule.applySaturday
          if sat_start_time && sat_end_time
            schedule_day_set_hours_of_operation(rule.daySchedule, sat_start_time, sat_end_time)
            # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ScheduleRuleset', "For #{schedule_ruleset.name}, set Saturday rule operating hours to #{sat_start_time}-#{sat_end_time}.")
          end
        elsif rule.applySunday
          if sun_start_time && sun_end_time
            schedule_day_set_hours_of_operation(rule.daySchedule, sun_start_time, sun_end_time)
            # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ScheduleRuleset', "For #{schedule_ruleset.name}, set Sunday rule operating hours to #{sun_start_time}-#{sun_end_time}.")
          end
        end
      end

      return true
    end

    # this will use parametric inputs contained in schedule and profiles along with inferred hours of operation to generate updated ruleset schedule profiles
    #
    # @author David Goldwasser
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param ramp_frequency [Double] ramp frequency in minutes
    # @param infer_hoo_for_non_assigned_objects [Boolean] attempt to get hoo for objects like swh with and exterior lighting
    # @param error_on_out_of_order [Boolean] true will error if applying formula creates out of order values
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.schedule_ruleset_apply_parametric_inputs(schedule_ruleset, ramp_frequency, infer_hoo_for_non_assigned_objects, error_on_out_of_order, parametric_inputs = nil)
      # Check if parametric inputs were supplied and generate them if not
      if parametric_inputs.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Parametric.ScheduleRuleset', "For #{schedule_ruleset.name}, no parametric inputs were not supplied so they will be generated now.")
        parametric_inputs = OpenstudioStandards::Schedules.model_setup_parametric_schedules(schedule.model, gather_data_only: true)
      end

      # Check that parametric inputs exist for this schedule after generation
      if parametric_inputs[schedule_ruleset].nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.ScheduleRuleset', "For #{schedule_ruleset.name}, no parametric inputs exists so schedule will not be changed.")
        return schedule_ruleset
      end

      # Check that an hours of operation schedule is associated with this schedule
      if parametric_inputs[schedule_ruleset][:hoo_inputs].nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.ScheduleRuleset', "For #{schedule_ruleset.name}, no associated hours of operation schedule was found so schedule will not be changed.")
        return schedule_ruleset
      end

      # Get the hours of operation schedule
      hours_of_operation = parametric_inputs[schedule_ruleset][:hoo_inputs]
      # OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.ScheduleRuleset', "For #{schedule_ruleset.name} hours_of_operation = #{hours_of_operation}.")

      starting_aeflh = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule_ruleset)

      # store floor and ceiling value
      val_flr = nil
      if schedule_ruleset.hasAdditionalProperties && schedule_ruleset.additionalProperties.hasFeature('param_sch_floor')
        val_flr = schedule_ruleset.additionalProperties.getFeatureAsDouble('param_sch_floor').get
      end
      val_clg = nil
      if schedule_ruleset.hasAdditionalProperties && schedule_ruleset.additionalProperties.hasFeature('param_sch_ceiling')
        val_clg = schedule_ruleset.additionalProperties.getFeatureAsDouble('param_sch_ceiling').get
      end

      # loop through schedule days from highest to lowest priority (with default as lowest priority)
      # if rule needs to be split to address hours of operation rules add new rule next to relevant existing rule
      profiles = {}
      schedule_ruleset.scheduleRules.each do |rule|
        # remove any use manually generated non parametric rules or any auto-generated rules from prior application of formulas and hoo
        sch_day = rule.daySchedule
        if !sch_day.hasAdditionalProperties || !sch_day.additionalProperties.hasFeature('param_day_tag') || (sch_day.additionalProperties.getFeatureAsString('param_day_tag').get == 'autogen')
          sch_day.remove # remove day schedule for this rule
          rule.remove # remove the rule
        elsif !sch_day.additionalProperties.hasFeature('param_day_profile')
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.ScheduleRuleset', "#{schedule.name} doesn't have a parametric formula for #{rule.name} This profile will not be altered.")
          next
        else
          profiles[sch_day] = rule
        end
      end
      profiles[schedule_ruleset.defaultDaySchedule] = nil

      # get indices for current schedule
      year_description = schedule_ruleset.model.yearDescription.get
      year = year_description.assumedYear
      year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
      year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      indices_vector = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)

      # process profiles
      profiles.each do |sch_day, rule|
        # for current profile index identify hours of operation index that contains all days
        if rule.nil?
          current_rule_index = -1
        else
          current_rule_index = rule.ruleIndex
        end

        # loop through indices looking of rule in hoo that contains days in the rule
        hoo_target_index = nil
        days_used = []
        indices_vector.each_with_index do |profile_index, i|
          if profile_index == current_rule_index then days_used << (i + 1) end
        end
        # find days_used in hoo profiles that contains all days used from this profile
        hoo_profile_match_hash = {}
        best_fit_check = {}
        hours_of_operation.each do |profile_index, value|
          days_for_rule_not_in_hoo_profile = days_used - value[:days_used]
          hoo_profile_match_hash[profile_index] = days_for_rule_not_in_hoo_profile
          best_fit_check[profile_index] = days_for_rule_not_in_hoo_profile.size
          if days_for_rule_not_in_hoo_profile.empty?
            hoo_target_index = profile_index
          end
        end
        clone_needed = false
        hoo_target_index = best_fit_check.key(best_fit_check.values.min)
        if best_fit_check[hoo_target_index] > 0
          clone_needed = true
        end

        # get hours of operation for this specific profile
        hoo_start = hours_of_operation[hoo_target_index][:hoo_start]
        # puts hoo_start
        hoo_end = hours_of_operation[hoo_target_index][:hoo_end]
        # puts hoo_end

        # update scheduleDay
        OpenstudioStandards::Schedules.schedule_day_adjust_from_parameters(sch_day, hoo_start, hoo_end, val_flr, val_clg, ramp_frequency, infer_hoo_for_non_assigned_objects, error_on_out_of_order)

        # clone new rule if needed
        if clone_needed

          # make list of new rules needed as has or array
          autogen_rules = {}
          days_to_fill = hoo_profile_match_hash[hoo_target_index]
          hours_of_operation.each do |profile_index, value|
            remainder = days_to_fill - value[:days_used]
            day_for_rule = days_to_fill - remainder
            if remainder.size < days_to_fill.size
              autogen_rules[profile_index] = { days_to_fill: day_for_rule, hoo_start: hoo_start, hoo_end: hoo_end }
            end
            days_to_fill = remainder
          end

          # loop through new rules to make and process
          autogen_rules.each do |autogen_rule, hash|
            # generate new rule
            sch_rule_autogen = OpenStudio::Model::ScheduleRule.new(schedule_ruleset)
            if current_rule_index
              target_index = schedule_ruleset.scheduleRules.size - 1 # just above default
            else
              target_index = current_rule_index - 1 # confirm just above orig rule
            end
            current_rule_index = target_index
            if rule.nil?
              sch_rule_autogen.setName("autogen #{schedule_ruleset.name} #{target_index}")
            else
              sch_rule_autogen.setName("autogen #{rule.name} #{target_index}")
            end
            schedule_ruleset.setScheduleRuleIndex(sch_rule_autogen, target_index)
            # @todo confirm this is higher priority than the non-auto-generated rule
            hash[:days_to_fill].each do |day|
              date = OpenStudio::Date.fromDayOfYear(day, year)
              sch_rule_autogen.addSpecificDate(date)
            end
            sch_rule_autogen.setApplySunday(true)
            sch_rule_autogen.setApplyMonday(true)
            sch_rule_autogen.setApplyTuesday(true)
            sch_rule_autogen.setApplyWednesday(true)
            sch_rule_autogen.setApplyThursday(true)
            sch_rule_autogen.setApplyFriday(true)
            sch_rule_autogen.setApplySaturday(true)

            # match profile from source rule (don't add time/values need a formula to process)
            sch_day_auto_gen = sch_rule_autogen.daySchedule
            sch_day_auto_gen.setName("#{sch_rule_autogen.name}_day_sch")
            sch_day_auto_gen.additionalProperties.setFeature('param_day_tag', 'autogen')
            val = sch_day.additionalProperties.getFeatureAsString('param_day_profile').get
            sch_day_auto_gen.additionalProperties.setFeature('param_day_profile', val)
            val = sch_day.additionalProperties.getFeatureAsString('param_day_secondary_logic').get
            sch_day_auto_gen.additionalProperties.setFeature('param_day_secondary_logic', val)
            val = sch_day.additionalProperties.getFeatureAsString('param_day_secondary_logic_arg_val').get
            sch_day_auto_gen.additionalProperties.setFeature('param_day_secondary_logic_arg_val', val)

            # get hours of operation for this specific profile
            hoo_start = hash[:hoo_start]
            hoo_end = hash[:hoo_end]

            # process new rule
            OpenstudioStandards::Schedules.schedule_day_adjust_from_parameters(sch_day_auto_gen, hoo_start, hoo_end, val_flr, val_clg, ramp_frequency, infer_hoo_for_non_assigned_objects, error_on_out_of_order)
          end

        end
      end

      # @todo create summer and winter design day profiles (make sure scheduleDay objects parametric)
      # @todo should they have their own formula, or should this be hard coded logic by schedule type

      # check orig vs. updated aeflh
      final_aeflh = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule_ruleset)
      percent_change = ((starting_aeflh - final_aeflh) / starting_aeflh) * 100.0
      if percent_change.abs > 0.05
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Parametric.ScheduleRuleset', "For #{schedule_ruleset.name}, applying parametric schedules made a #{percent_change.round(1)}% change in annual equivalent full load hours. (from #{starting_aeflh.round(2)} to #{final_aeflh.round(2)})")
      end

      return schedule_ruleset
    end

    # @!endgroup Parametric:ScheduleRuleset

    # @!group Parametric:ScheduleDay

    # adjust individual schedule profiles from parametric inputs
    #
    # @author David Goldwasser
    # @param schedule_day [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @param hoo_start [Double] hours of operation start
    # @param hoo_end [Double] hours of operation end
    # @param val_flr [Double] value floor
    # @param val_clg [Double] value ceiling
    # @param ramp_frequency [Double] ramp frequency in minutes
    # @param infer_hoo_for_non_assigned_objects [Boolean] attempt to get hoo for objects like swh with and exterior lighting
    # @param error_on_out_of_order [Boolean] true will error if applying formula creates out of order values
    # @return [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @api private
    def self.schedule_day_adjust_from_parameters(schedule_day, hoo_start, hoo_end, val_flr, val_clg, ramp_frequency, infer_hoo_for_non_assigned_objects, error_on_out_of_order)
      # process hoo and floor/ceiling vars to develop formulas without variables
      formula_string = schedule_day.additionalProperties.getFeatureAsString('param_day_profile').get
      formula_hash = {}
      formula_string.split('|').each do |time_val_valopt|
        a1 = time_val_valopt.to_s.split('~')
        time = a1[0]
        value_array = a1.drop(1)
        formula_hash[time] = value_array
      end

      # setup additional variables
      if hoo_end >= hoo_start
        occ = hoo_end - hoo_start
      else
        occ = 24.0 + hoo_end - hoo_start
      end
      vac = 24.0 - occ
      range = val_clg - val_flr

      timestep_minutes = (0..60).step(60 * ramp_frequency).to_a

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.ScheduleDay', "Schedule #{schedule_day.name} has this formula hash: #{formula_hash}")

      # apply variables and create updated hash with only numbers
      formula_hash_var_free = {}
      formula_hash.each do |time, val_in_out|
        # replace time variables with value
        time = time.gsub('hoo_start', hoo_start.to_s)
        time = time.gsub('hoo_end', hoo_end.to_s)
        time = time.gsub('occ', occ.to_s)
        # can save special variables like lunch or break using this logic
        mid_start = hoo_start + (occ * 0.5)
        mid_start_min = mid_start.modulo(1) * 60
        mid_start_min_ts = timestep_minutes.min { |a, b| (a - mid_start_min).abs <=> (b - mid_start_min).abs }
        mid_start_adjusted = mid_start.floor + (mid_start_min_ts / 60)
        time = time.gsub('mid', mid_start_adjusted.to_s)
        time = time.gsub('vac', vac.to_s)
        begin
          time_float = eval(time)
          if time_float.to_i.to_s == time_float.to_s || time_float.to_f.to_s == time_float.to_s # check to see if numeric
            time_float = time_float.to_f
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.ScheduleDay', "Time formula #{time} for #{schedule_day.name} is invalid. It can't be converted to a float.")
          end
        rescue SyntaxError => e
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.ScheduleDay', "Time formula #{time} for #{schedule_day.name} is invalid. It can't be evaluated.")
        end

        # replace variables in array of values
        val_in_out_float = []
        val_in_out.each do |val|
          # replace variables for values
          val = val.gsub('val_flr', val_flr.to_s)
          val = val.gsub('val_clg', val_clg.to_s)
          val = val.gsub('val_range', range.to_s) # will expect a fractional value and will scale within ceiling and floor
          begin
            val_float = eval(val)
            if val_float.to_i.to_s == val_float.to_s || val_float.to_f.to_s == val_float.to_s # check to see if numeric
              val_float = val_float.to_f
            else
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.ScheduleDay', "Value formula #{val_float} for #{schedule_day.name} is invalid. It can't be converted to a float.")
            end
          rescue SyntaxError => e
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.ScheduleDay', "Time formula #{val_float} for #{schedule_day.name} is invalid. It can't be evaluated.")
          end
          val_in_out_float << val_float
        end

        # update hash
        formula_hash_var_free[time_float] = val_in_out_float
      end

      # this is old variable used in loop, just combining for now to avoid refactor, may change this later
      time_value_pairs = []
      formula_hash_var_free.each do |time, val_in_out|
        val_in_out.each do |val|
          time_value_pairs << [time, val]
        end
      end

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.ScheduleDay', "Schedule #{schedule_day.name} will be adjusted with these time-value pairs: #{time_value_pairs}")

      # re-order so first value is lowest, and last is highest (need to adjust so no negative or > 24 values first)
      neg_time_hash = {}
      temp_min_time_hash = {}
      time_value_pairs.each_with_index do |pair, i|
        # if value  24 add it to 24 so it will go on tail end of profile
        # case when value is greater than 24 can be left alone for now, will be addressed
        if pair[0] < 0.0
          neg_time_hash[i] = pair[0]
          time = pair[0] + 24.0
          time_value_pairs[i][0] = time
        else
          time = pair[0]
        end
        temp_min_time_hash[i] = pair[0]
      end
      time_value_pairs.rotate!(temp_min_time_hash.key(temp_min_time_hash.values.min))

      # validate order, issue warning and correct if out of order
      last_time = nil
      throw_order_warning = false
      pre_fix_time_value_pairs = time_value_pairs.to_s
      time_value_pairs.each_with_index do |time_value_pair, i|
        if last_time.nil?
          last_time = time_value_pair[0]
        elsif time_value_pair[0] < last_time || neg_time_hash.key?(i)

          # @todo it doesn't actually stop here now
          if error_on_out_of_order
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.ScheduleDay', "Pre-interpolated processed hash for #{schedule_day.name} has one or more out of order conflicts: #{pre_fix_time_value_pairs}. Method will stop because Error on Out of Order was set to true.")
          end

          if neg_time_hash.key?(i)
            orig_current_time = time_value_pair[0]
            updated_time = 0.0
            last_buffer = 'NA'
          else
            # determine much space last item can move
            if i < 2
              last_buffer = time_value_pairs[i - 1][0] # can move down to 0 without any issues
            else
              last_buffer = time_value_pairs[i - 1][0] - time_value_pairs[i - 2][0]
            end

            # move to previous timestep but don't exceed available buffer
            updated_time = time_value_pairs[i - 1][0] - [ramp_frequency, last_buffer].min
          end

          # update values in array
          orig_current_time = time_value_pair[0]
          time_value_pairs[i - 1][0] = updated_time
          time_value_pairs[i][0] = updated_time

          # reporting mostly for diagnostic purposes
          # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Parametric.ScheduleDay', "For #{schedule_day.name} profile item #{i} time was #{last_time} and item #{i + 1} time was #{orig_current_time}. Last buffer is #{last_buffer}. Changing both times to #{updated_time}.")

          last_time = updated_time
          throw_order_warning = true

        else
          last_time = time_value_pair[0]
        end
      end

      # issue warning if order was changed
      if throw_order_warning
        # OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Parametric.ScheduleDay', "Pre-interpolated processed hash for #{schedule_day.name} has one or more out of order conflicts: #{pre_fix_time_value_pairs}. Time values were adjusted as shown to crate a valid profile: #{time_value_pairs}")
      end

      # add interpolated values at ramp_frequency
      time_value_pairs.each_with_index do |time_value_pair, i|
        # store current and next time and value
        current_time = time_value_pair[0]
        current_value = time_value_pair[1]
        if i + 1 < time_value_pairs.size
          next_time = time_value_pairs[i + 1][0]
          next_value = time_value_pairs[i + 1][1]
        else
          # use time and value of first item
          next_time = time_value_pairs[0][0] + 24 # need to adjust values for beginning of array
          next_value = time_value_pairs[0][1]
        end
        step_delta = next_time - current_time

        # skip if time between values is 0 or less than ramp frequency
        next if step_delta <= ramp_frequency

        # skip if next value is same
        next if current_value == next_value

        # add interpolated value to array
        interpolated_time = current_time + ramp_frequency
        interpolated_value = (next_value * (interpolated_time - current_time) / step_delta) + (current_value * (next_time - interpolated_time) / step_delta)
        time_value_pairs.insert(i + 1, [interpolated_time, interpolated_value])
      end

      # remove second instance of time when there are two
      time_values_used = []
      items_to_remove = []
      time_value_pairs.each_with_index do |time_value_pair, i|
        if time_values_used.include? time_value_pair[0]
          items_to_remove << i
        else
          time_values_used << time_value_pair[0]
        end
      end
      items_to_remove.reverse.each do |i|
        time_value_pairs.delete_at(i)
      end

      # if time is > 24 shift to front of array and adjust value
      rotate_steps = 0
      time_value_pairs.reverse.each_with_index do |time_value_pair, i|
        next unless time_value_pair[0] > 24

        rotate_steps -= 1
        time_value_pair[0] -= 24
      end
      time_value_pairs.rotate!(rotate_steps)

      # add a 24 on the end of array that matches the first value
      if time_value_pairs.last[0].to_i != 24
        time_value_pairs << [24.0, time_value_pairs.first[1]]
      end

      # OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.ScheduleDay', "Schedule #{schedule_day.name} will be adjusted with these time-value pairs: #{time_value_pairs}")

      # reset scheduleDay values based on interpolated values
      schedule_day.clearValues
      time_value_pairs.each do |time_val|
        hour = time_val.first.floor
        min = ((time_val.first - hour) * 60.0).floor
        os_time = OpenStudio::Time.new(0, hour, min, 0)
        value = time_val.last
        schedule_day.addValue(os_time, value)
      end
      # @todo apply secondary logic

      # Tell EnergyPlus to interpolate schedules to timestep so that it doesn't have to be done in this code
      # sch_day.setInterpolatetoTimestep(true)
      # if model.version < OpenStudio::VersionString.new('3.8.0')
      #   day_sch.setInterpolatetoTimestep(true)
      # else
      #   day_sch.setInterpolatetoTimestep('Average')
      # end

      return schedule_day
    end

    # @!endgroup Parametric:ScheduleDay
  end
end
