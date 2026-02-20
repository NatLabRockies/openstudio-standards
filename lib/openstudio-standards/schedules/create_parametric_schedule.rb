module OpenstudioStandards
  module Schedules
    # @!group Schedule Derivation Methods
    # Apply the smootherstep function to a given input located beetween a starting and ending value range between start/end values will be unitized
    #
    # @param edge0 [Float] lower limit
    # @param edge1 [FLoat] upper limit
    # @param x [Float] input value
    # @return [Float] evaluated value
    def self.smootherstep(edge0, edge1, x)
      if x < edge0 && x > edge1
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', 'Cannot apply smootherstep to an input outside of range')
        return false
      end

      if edge0 == edge1
        return 0.0
      end

      # fractionalize input over unitized input range
      x_i = ((x - edge0) / (edge1 - edge0))

      return x_i * x_i * x_i * ((x_i * ((6.0 * x_i) - 15.0)) + 10.0)
    end

    # Applies smootherstep to the input set of <24 time_value_pairs to interpolate missing points
    #
    # @param time_value_pairs [Array] array of time value pairs
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [<Array>] Returns an expanded array of 24 time value pairs
    def self.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour)
      return_arry = []
      if time_value_pairs[0][0] != 0
        time_value_pairs.unshift([0, time_value_pairs[0][1]])
      end
      if time_value_pairs[-1][0] < 24
        time_value_pairs << [24, time_value_pairs[-1][1]]
      end

      time_value_pairs.each_cons(2) do |this_pair, next_pair|
        this_time = this_pair[0].to_f
        this_val = this_pair[1]
        next_time = next_pair[0].to_f
        next_val = next_pair[1]
        last_time = time_value_pairs[-1][0]

        next_time == last_time ? exclude_end = false : exclude_end = true

        Range.new(this_time, next_time, exclude_end).step(1.0 / timesteps_per_hour).each do |time|
          val_frac = smootherstep(this_time, next_time, time)
          if next_val < this_val
            val_actual = this_val - (val_frac * (next_val - this_val).abs)
          else
            val_actual = this_val + (val_frac * (next_val - this_val).abs)
          end
          return_arry << [time, val_actual]
        end
      end
      return_arry
    end

    # Wrap time value pairs to 24 hours
    #
    # @param time_value_pairs [Array] array of time value pairs
    # @return [Array] array of wrapped time value pairs
    def self.wrap_schedule_pairs(time_value_pairs)
      # divide the time value pairs at 24 hours
      wrap_group = []
      normal_group = []

      time_value_pairs.each do |time, value|
        if time >= 24
          wrap_group << [time - 24.0, value]
        end
        if time <= 24.0
          normal_group << [time, value]
        end
      end

      # merge both groups by time. If the same time exists, sum the values
      merged = {}

      (wrap_group + normal_group).each do |time, value|
        key = merged.keys.find { |k| (k - time).abs < 1e-6 } || time
        merged[key] ||= []
        merged[key] << value
      end

      result = merged.map do |time, values|
        combined = values.size > 1 ? values.reduce(:+) / [values.sum, 1.0].max : values[0]
        [time, combined]
      end

      result.sort_by { |time, _| time }
    end

    # Expands parametric schedule control points
    #
    # @param schedule_data [Hash] hash of schedule data
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @param start_time [Float] input start time
    # @param end_time [Float] input end time
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Array] array of time value pairs
    def self.expand_schedule_control_points(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      # proc to round to timestep
      round_to_timestep = ->(val) { (val * timesteps_per_hour).round / timesteps_per_hour.to_f }

      # adjust end time to be after start time
      if end_time < start_time
        end_time += 24
      end

      # calculate baseline duration and relative adjustment multiplier
      standard_duration = schedule_data[:et_std] - schedule_data[:st_std]
      adjustment_multiplier = (end_time - start_time) / standard_duration

      # TODO: add option to truncate schedule rather than fill to st/et

      # evaluate control points with inputs
      time_value_pairs = []

      control_points = schedule_data[:control_points]
      control_points.each do |point|
        # control points are an array of two strings describing the time and value modifiers relative to start and end time (st/et) and base and peak values
        # e.g. ['st-1', 'base*0.5']
        parser = /([a-z]+)(?:([+\-*])(\d+(?:\.\d+)?))?/
        time_point = point[0].scan(parser)[0]
        value_point = point[1].scan(parser)[0]
        case time_point[0]
        when 'st'
          time = start_time
        when 'et'
          time = end_time
        end

        # adjust time modifier by ratio of given duration to standard duration
        unless time_point[1].nil? && time_point[2].nil?
          time = time.send(time_point[1], time_point[2].to_i * adjustment_multiplier)
        end
        # ensure time lands on timestep
        time = round_to_timestep.call(time)

        # evaluate value point
        case value_point[0]
        when 'base'
          val = base
        when 'peak'
          val = peak
        end

        unless value_point[1].nil? && value_point[2].nil?
          val = val.send(value_point[1], value_point[2].to_f)
        end

        # limit value between 0 and 1
        val.clamp(0, 1)

        time_value_pairs << [time, val]
      end
      time_value_pairs.sort_by! { |pair| pair[0] }

      if time_value_pairs[-1][0] > 24
        time_value_pairs = OpenstudioStandards::Schedules.wrap_schedule_pairs(time_value_pairs)
      end

      # apply smoothing to intermediate values between
      OpenstudioStandards::Schedules.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour)

      # p expanded_tv_pairs

      # wrap around to 24 hours
      # wrap_schedule_pairs(expanded_tv_pairs)
    end

    # Add time value pairs to OpenStudio ScheduleDay
    #
    # @param day_sch [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @param time_value_pairs [Array] array of time value pairs
    # @return [Boolean] true if successful, false if not
    def self.add_time_value_pairs_to_schedule(day_sch, time_value_pairs)
      time_value_pairs.each_with_index do |pair, i|
        # p pair
        if i != (time_value_pairs.size - 1) && pair[1] == time_value_pairs[i + 1][1]
          next
        end

        hr = pair[0].to_i
        min = (pair[0].modulo(1) * 60).to_i

        day_sch.addValue(OpenStudio::Time.new(0, hr, min, 0), pair[1])
      end
    end

    # Revised method to construct ScheduleRulesets from data in parametric form, which uses the existing Schedules module method
    # Constructs all day schedules and assign appropriate rules
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param schedule_array [Array] array of default schedule data objects to load from - TODO: extract this part out
    # @param schedule_name [String] name of schedule to create
    # @param params [Hash] hash of schedule input parameters. Specific key/values will depend on the schedule type
    # @return [ScheduleRuleset] the resulting schedule ruleset
    def self.create_parametric_schedule_full(model, schedule_array, schedule_name, params)
      timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour
      schedule_objs = schedule_array.select { |o| o[:name].to_s == schedule_name }

      options = {}
      options['name'] = schedule_objs[0][:name]
      options['rules'] = []
      schedule_objs.each do |obj|
        sch_type = obj[:type]

        st = params[:st].nil? ? obj[:st_std] : params[:st]
        et = params[:et].nil? ? obj[:et_std] : params[:et]
        base = params[:base].nil? ? obj[:base_std] : params[:base]
        peak = params[:peak].nil? ? obj[:peak_std] : params[:peak]

        time_value_pairs = OpenstudioStandards::Schedules.expand_schedule_control_points(obj, base, peak, st, et, timesteps_per_hour)

        tv_pairs_reduced = time_value_pairs.reject.with_index { |e, i| e[1] == time_value_pairs[i + 1][1] unless i == (time_value_pairs.size - 1) }

        day_types = obj[:day_types].split('|')
        day_types.each do |day_type|
          case day_type
          when 'Default'
            options['default_day'] = ['default'] + tv_pairs_reduced
          when 'WntrDsn'
            options['winter_design_day'] = tv_pairs_reduced
          when 'SmrDsn'
            options['summer_design_day'] = tv_pairs_reduced
          when 'Hol'
            # do nothing
          else
            start_date = DateTime.strptime(obj[:start_date]).strftime('%m/%d')
            end_date = DateTime.strptime(obj[:end_date]).strftime('%m/%d')
            rule_a = [day_type]
            rule_a << "#{start_date}-#{end_date}"
            rule_a << day_type
            rule_a += tv_pairs_reduced
            options['rules'] << rule_a
          end
        end
      end

      schedule = OpenstudioStandards::Schedules.create_complex_schedule(model, options)
      return schedule
    end

    # Method to derive time-value pairs from a set of time-value pairs. The derived values are determined by applying the given parameters and derivation type.
    #
    # @param derivation_type [String] type of derivation to perform. Options are 'linear', 'exponential', and 'exponential-inverse'
    # @param base [Float] base value for schedule derivation
    # @param peak [Float] peak value for schedule derivation
    # @param response [Float] response factor for schedule derivation, which modifies the influence
    # @param initial_values [Array] array of time value pairs to derive from
    # @return [Array] array of derived time value pairs
    def self.derive_values(derivation_type, base, peak, response, initial_values)
      # correct values if base > peak or peak < base to ensure base is always the lower value and peak is the higher value
      peak = base if (base > peak) && (base > 0.5)
      base = peak if (peak < base) && (peak < 0.5)

      # derive time-value pairs
      derived_pairs = []
      case derivation_type
      when 'linear'
        initial_values.each do |initial_pair|
          derived_value = base + ((peak - base) * (initial_pair[1] * response))
          derived_pairs << [initial_pair[0], derived_value]
        end
      when 'exponential'
        initial_values.each do |initial_pair|
          derived_value = base + ((peak - base) * (initial_pair[1]**response.to_f))
          derived_pairs << [initial_pair[0], derived_value]
        end
      when 'exponential-inverse'
        initial_values.each do |initial_pair|
          derived_value = base + ((peak - base) * (initial_pair[1]**(1 / response.to_f)))
          derived_pairs << [initial_pair[0], derived_value]
        end
      end
      return derived_pairs
    end

    # Add a schedule derived from an occupancy schedule and parametric inputs. The derived schedule is created by modifying the occupancy schedule time-value pairs according to the given parameters.
    #
    # @param occupancy_schedule [OpenStudio::Model::ScheduleRuleset] input occupancy schedule to derive information from
    # @param params [Hash] hash of schedule input parameters. Specific key/values will depend on the schedule type
    # @return [ScheduleRuleset] the resulting schedule ruleset
    def self.create_derived_schedule_from_occupancy_schedule(occupancy_schedule, params)
      # get model object from existing schedule
      model = occupancy_schedule.model

      # get values from params
      derivation_type = params[:derivation_type]
      base = params[:base]
      peak = params[:peak]
      response = params[:response]
      winter_design_day_base = params[:winter_design_day_base].nil? ? base : params[:winter_design_day_base]
      winter_design_day_peak = params[:winter_design_day_peak].nil? ? peak : params[:winter_design_day_peak]
      winter_design_day_response = params[:winter_design_day_response].nil? ? response : params[:winter_design_day_response]
      summer_design_day_base = params[:summer_design_day_base].nil? ? base : params[:summer_design_day_base]
      summer_design_day_peak = params[:summer_design_day_peak].nil? ? peak : params[:summer_design_day_peak]
      summer_design_day_response = params[:summer_design_day_response].nil? ? response : params[:summer_design_day_response]

      # create a new schedule ruleset
      derived_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
      derived_schedule.setName(params[:name])

      # create default day schedules
      default_occ_day_sch = occupancy_schedule.defaultDaySchedule
      default_occ_times = default_occ_day_sch.times.map(&:totalHours)
      occ_time_values = default_occ_times.zip(default_occ_day_sch.values)
      derived_pairs = OpenstudioStandards::Schedules.derive_values(derivation_type, base, peak, response, occ_time_values)
      default_day = derived_schedule.defaultDaySchedule
      default_day.setName("#{params[:name]} Default Day")
      OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(default_day, derived_pairs)

      # create summer design day schedule
      smr_occ_day_sch = occupancy_schedule.summerDesignDaySchedule
      smr_occ_times = smr_occ_day_sch.times.map(&:totalHours)
      occ_time_values = smr_occ_times.zip(smr_occ_day_sch.values)
      derived_pairs = OpenstudioStandards::Schedules.derive_values(derivation_type, summer_design_day_base, summer_design_day_peak, summer_design_day_response, occ_time_values)
      summer_day = OpenStudio::Model::ScheduleDay.new(model)
      summer_day.setName("#{params[:name]} Summer Design Day")
      OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(summer_day, derived_pairs)
      derived_schedule.setSummerDesignDaySchedule(summer_day)

      # create winter design day schedule
      wnt_occ_day_sch = occupancy_schedule.winterDesignDaySchedule
      wnt_occ_times = wnt_occ_day_sch.times.map(&:totalHours)
      occ_time_values = wnt_occ_times.zip(wnt_occ_day_sch.values)
      derived_pairs = OpenstudioStandards::Schedules.derive_values(derivation_type, winter_design_day_base, winter_design_day_peak, winter_design_day_response, occ_time_values)
      winter_day = OpenStudio::Model::ScheduleDay.new(model)
      winter_day.setName("#{params[:name]} Winter Design Day")
      OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(winter_day, derived_pairs)
      derived_schedule.setWinterDesignDaySchedule(winter_day)

      # get rules from existing schedule
      occupancy_schedule.scheduleRules.each do |rule|
        # get occ schedule time value pairs
        occ_day_sch = rule.daySchedule
        occ_times = occ_day_sch.times.map(&:totalHours)
        occ_time_values = occ_times.zip(occ_day_sch.values)

        # derive time-value pairs
        derived_pairs = OpenstudioStandards::Schedules.derive_values(derivation_type, base, peak, response, occ_time_values)

        # Make the Rule
        sch_rule = OpenStudio::Model::ScheduleRule.new(derived_schedule)
        sch_rule.setName("#{rule.name} Derived #{params[:category]} Rule")
        day_sch = sch_rule.daySchedule
        day_sch.setName("#{rule.name} Derived #{params[:category]} Day Sch")
        OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(day_sch, derived_pairs)

        # Set the dates when the rule applies
        sch_rule.setStartDate(rule.startDate.get) if rule.startDate.is_initialized
        sch_rule.setEndDate(rule.endDate.get) if rule.endDate.is_initialized

        # Set the days when the rule applies
        sch_rule.setApplyMonday(rule.applyMonday) if rule.applyMonday
        sch_rule.setApplyTuesday(rule.applyTuesday) if rule.applyTuesday
        sch_rule.setApplyWednesday(rule.applyWednesday) if rule.applyWednesday
        sch_rule.setApplyThursday(rule.applyThursday) if rule.applyThursday
        sch_rule.setApplyFriday(rule.applyFriday) if rule.applyFriday
        sch_rule.setApplySaturday(rule.applySaturday) if rule.applySaturday
        sch_rule.setApplySunday(rule.applySunday) if rule.applySunday

        # add params to schedule additional properties
        props = day_sch.additionalProperties
        props.setFeature('base', base)
        props.setFeature('peak', peak)
        props.setFeature('response', response)
        props.setFeature('derived_from', rule.name.get)
      end

      return derived_schedule
    end

    # Sets the schedules for the selected internal loads to typical schedules.
    # Uses parametric formulations for the occupancy schedule and derives interior lighting and equipment schedules from the occupancy schedule. If set_people is false, the occupancy schedule will not be applied but will still be used as the basis for deriving the lighting and equipment schedules.
    #
    # @param space_type [OpenStudio::Model::SpaceType] space type object
    # @param set_people [Boolean] if true, set the occupancy and activity schedules
    # @param set_lights [Boolean] if true, set the interior lighting schedule
    # @param set_electric_equipment [Boolean] if true, set the electric schedule schedule
    # @param set_gas_equipment [Boolean] if true, set the gas equipment schedule
    # @param set_hot_water_equipment [Boolean] if true, set the hot water equipment schedule
    # @return [Boolean] returns true if successful, false if not
    def self.space_type_apply_parametric_internal_load_schedules(space_type, set_people: true, set_lights: true, set_electric_equipment: true, set_gas_equipment: true, set_hot_water_equipment: true)
      # Get the default schedule set or create a new one if none exists
      default_sch_set = nil
      if space_type.defaultScheduleSet.is_initialized
        default_sch_set = space_type.defaultScheduleSet.get
      else
        default_sch_set = OpenStudio::Model::DefaultScheduleSet.new(space_type.model)
        default_sch_set.setName("#{space_type.name} Schedule Set")
        space_type.setDefaultScheduleSet(default_sch_set)
      end

      # Load the default schedule set information
      default_parametric_sch_set = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_parametric_schedule_set.json"), symbolize_names: true)

      # Get the default parametric schedule set for this space type
      standards_building_type = nil
      if space_type.standardsBuildingType.is_initialized
        standards_building_type = space_type.standardsBuildingType.get
      end

      if space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized
        schedule_set_name = space_type.additionalProperties.getFeatureAsString('schedule_set').get
        possible_schedule_sets = default_parametric_sch_set.select { |s| s[:space_type_name] == schedule_set_name }

        if standards_building_type.nil?
          space_type_properties = possible_schedule_sets.find { |s| s[:standards_building_type].nil? }
        else
          space_type_properties = possible_schedule_sets.find { |s| s[:standards_building_type] == standards_building_type }
          space_type_properties = possible_schedule_sets.find { |s| s[:standards_building_type].nil? } if space_type_properties.nil?
        end

        space_type_properties = possible_schedule_sets[0] if space_type_properties.nil?

        if space_type_properties.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Unable to find schedule set '#{schedule_set_name}' for #{space_type.name} with standards building type '#{standards_building_type}'.")
          return false
        end
      else
        standards_space_type = 'not defined'
        if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
          standards_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
        end

        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Unable to find schedule set for #{space_type.name} with standards space type '#{standards_space_type}'. Please ensure the space type additional property 'schedule_set' is set to a valid schedule set name. Refer to the documentation for more information on parametric schedule sets.")
        return false
      end

      # Find occupancy schedule
      occupancy_schedules = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_parametric_occupancy_schedules.json"), symbolize_names: true)
      occupancy_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(space_type.model, occupancy_schedules, space_type_properties[:occupancy_schedule], {})

      # Add occupancy schedule to the default schedule set
      if set_people
        unless occupancy_sch.nil?
          default_sch_set.setNumberofPeopleSchedule(occupancy_sch)
        end

        # Set the activity schedule. Use a default 120 W/person
        occupancy_activity_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(space_type.model, 120.0, name: "#{space_type.name} Occupant Activity Schedule")
        default_sch_set.setPeopleActivityLevelSchedule(occupancy_activity_sch)
      end

      # Derive the interior lighting schedule and set as the default
      if set_lights && !space_type_properties[:derived_interior_lighting_parameters].nil?
        lighting_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_lighting_parameters.json"), symbolize_names: true)
        lighting_params = lighting_data.find { |s| s[:name] == space_type_properties[:derived_interior_lighting_parameters] }
        light_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occupancy_sch, lighting_params)
        default_sch_set.setLightingSchedule(light_sch)
      end

      # Derive the electric equipment schedule and set as the default
      if set_electric_equipment && !space_type_properties[:derived_electric_equipment_parameters].nil?
        equip_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_electric_equipment_parameters.json"), symbolize_names: true)
        equip_params = equip_data.find { |s| s[:name] == space_type_properties[:derived_electric_equipment_parameters] }
        equip_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occupancy_sch, equip_params)
        default_sch_set.setElectricEquipmentSchedule(equip_sch)
      end

      # Derive the gas equipment schedule and set as the default
      if set_gas_equipment && !space_type_properties[:derived_gas_equipment_parameters].nil?
        gas_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_gas_equipment_parameters.json"), symbolize_names: true)
        gas_params = gas_data.find { |s| s[:name] == space_type_properties[:derived_gas_equipment_parameters] }
        gas_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occupancy_sch, gas_params)
        default_sch_set.setGasEquipmentSchedule(gas_sch)
      end

      # Derive the hot water equipment schedule and set as the default
      if set_hot_water_equipment && !space_type_properties[:derived_hot_water_equipment_parameters].nil?
        hot_water_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_hot_water_equipment_parameters.json"), symbolize_names: true)
        hot_water_params = hot_water_data.find { |s| s[:name] == space_type_properties[:derived_hot_water_equipment_parameters] }
        hot_water_sch = OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occupancy_sch, hot_water_params)
        default_sch_set.setHotWaterEquipmentSchedule(hot_water_sch)
      end

      return true
    end
  end
end
