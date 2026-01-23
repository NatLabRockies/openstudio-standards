require_relative 'information'
module OpenstudioStandards
  module Schedules
    # apply the smootherstep function to a given input located beetween a starting and ending value
    # range between start/end values will be unitized
    #
    # @param edge0 [Float] lower limit
    # @param edge1 [FLoat] upper limit
    # @param x [Float] input value
    # @return [Float] evaluated value
    def self.smootherstep(edge0, edge1, x)
      if x < edge0 && x > edge1
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Parametric.Model', 'Cannot apply smootherstep to an input outside of range')
        return false
      end
      # fractionalize input over unitized input range
      x_i = ((x - edge0) / (edge1 - edge0))

      return x_i * x_i * x_i * ((x_i * ((6.0 * x_i) - 15.0)) + 10.0)
    end

    # applies smootherstep to the input set of <24 time_value_pairs to interpolate missing points
    # returns an expanded array of 24 time value pairs
    def self.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour)
      return_arry = []
      if time_value_pairs[0][0] != 0
        time_value_pairs.unshift([0, time_value_pairs[0][1]])
      end
      if time_value_pairs[-1][0] <= 24
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

    # wraps time value pairs to 24 hours
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

    # expands parametric schedule control points
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

      control_points = schedule_data[:control_pts]
      puts control_points.inspect
      control_points.each do |point|
        # control points are an array of two strings describing hte time and value modifiers relative to start and end time (st/et) and base and peak values
        # e.g. ['st-1', 'base*0.5']
        parser = /([a-z]+)(?:([+\-*])(\d+(?:\.\d+)?))?/
        time_point = point[0].scan(parser)[0]
        # puts time_point.inspect
        value_point = point[1].scan(parser)[0]
        # puts value_point.inspect
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
      p time_value_pairs

      if time_value_pairs[-1][0] > 24
        time_value_pairs = wrap_schedule_pairs(time_value_pairs)
      end
      p time_value_pairs
      # apply smoothing to intermediate values between
      smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour)

      # p expanded_tv_pairs

      # wrap around to 24 hours
      # wrap_schedule_pairs(expanded_tv_pairs)
    end

    def self.model_add_time_value_pairs_to_schedule(day_sch, time_value_pairs)
      time_value_pairs.each_with_index do |pair, i|
        # p pair
        if i != (time_value_pairs.size - 1) && pair[1] == time_value_pairs[i + 1][1]
          next
        end

        hr = pair[0].to_i
        min = (pair[0].modulo(1) * 60).to_i

        # puts "#{hr}:#{min} -> #{pair[1]}"

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
    def self.model_add_parametric_schedule_full(model, schedule_array, schedule_name, params)
      timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour
      schedule_objs = schedule_array.select { |o| o[:name].to_s == schedule_name }

      options = {}
      options['name'] = schedule_array[0][:name]
      options['rules'] = []
      schedule_objs.each do |obj|
        # puts obj.inspect
        sch_type = obj[:type]
        control_points = obj[:control_points]

        st = params[:st].nil? ? obj[:st_std] : params[:st]
        et = params[:et].nil? ? obj[:et_std] : params[:et]
        base = params[:base].nil? ? obj[:base_std] : params[:base]
        peak = params[:peak].nil? ? obj[:peak_std] : params[:peak]

        time_value_pairs = expand_schedule_control_points(obj, base, peak, st, et, timesteps_per_hour)

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

      puts options
      schedule = OpenstudioStandards::Schedules.create_complex_schedule(model, options)
      return schedule
    end

    # Add a schedule derived from an occupancy schedule and parametric inputs
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param occ_schedule [OpenStudio::Model::Schedule] input occupancy schedule to derive information from
    # @param schedule_array [Array] list of default schedule data objects
    # @param schedule_name [String] name of schedule to add
    # @param params [Hash] hash of schedule input parameters. Specific key/values will depend on the schedule type
    # @return [ScheduleRuleset] the resulting schedule ruleset
    def self.model_derive_schedule_from_occupancy(model, occ_schedule, schedule_array, schedule_name, params)
      schedule_objs = schedule_array.select { |o| o[:name].to_s == schedule_name }

      options = {}
      options['name'] = schedule_array[0][:name]
      options['rules'] = []
      schedule_objs.each do |obj|
        sch_type = obj[:type]
        day_types = rule[:day_types]
        day_type_array = day_types.split('|')

        # categorize ocupancy schedule profiles
        occ_profiles = schedule_ruleset_categorize_day_schedules(occ_schedule)

        day_type_array.each do |day_type|
          # find corresponding occ schedule rule by day type
          target_occ_profile = nil

          occ_profiles.each do |key, value|
            next unless target_occ_profile.nil?

            if value.split('|').include? day_type
              target_occ_profile = key
            end
          end
          if target_occ_profile.nil?
            OpenStudio.logfree(OpenStudio::Error, 'openstudio.standards.Schedule', "Could not find matching occupancy schedule day type for #{day_types} in #{occ_schedule.name.get} types")
            return false
          end

          target_occ_rule = occ_schedule.scheduleRules.select { |rule| rule.daySchedule == target_occ_profile }.first

          occ_times = target_occ_profile.times.map(&:totalHours)
          occ_time_values = occ_times.zip(target_occ_profile)

          # derive time-value pairs
          derived_pairs = []
          case params[:derivation_type]
          when 'linear'
            # override inputs if included in params
            base = params[:base].nil? ? rule[:base] : params[:base]
            peak = params[:peak].nil? ? rule[:peak] : params[:peak]
            response = params[:response].nil? ? rule[:response] : params[:response]

            occ_time_values.each do |initial_pair|
              derived_value = base + ((peak - base) * (initial_pair[1] * response))
              derived_pairs << [initial_pair[0], derived_value]
            end
          when 'exponential'
            # override inputs if included in params
            base = params[:base].nil? ? rule[:base] : params[:base]
            peak = params[:peak].nil? ? rule[:peak] : params[:peak]
            response = params[:response].nil? ? rule[:response] : params[:response]

            occ_time_values.each do |initial_pair|
              derived_value = base + ((peak - base) * (initial_pair[1]**response.to_f))
              derived_pairs << [initial_pair[0], derived_value]
            end
          when 'exponential-inverse'
            # override inputs if included in params
            base = params[:base].nil? ? rule[:base] : params[:base]
            peak = params[:peak].nil? ? rule[:peak] : params[:peak]
            response = params[:response].nil? ? rule[:response] : params[:response]

            occ_time_values.each do |initial_pair|
              derived_value = base + ((peak - base) * (initial_pair[1]**(1 / response.to_f)))
              derived_pairs << [initial_pair[0], derived_value]
            end
          end

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
            start_date = DateTime.strptime(obj[:start_date], '%m/%d/%Y').strftime('%m/%d')
            end_date = DateTime.strptime(obj[:end_date], '%m/%d/%Y').strftime('%m/%d')
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

    # Add an equipment schedule derived from an occupancy schedule and parametric data
    #
    # @param model [OpenStudio::Model::Model] Openstudio model object
    # @param occ_schedule [OpenStudio::Model::Schedule] input occupancy schedule to derive information from
    # @param schedule_array [Array] list of default schedule data objects
    # @param schedule_name [String] name of schedule to add
    # @param params [Hash] hash of schedule input parameters. Specific key/values will depend on the schedule type
    def self.model_derive_equipment_schedule(model, occ_schedule, schedule_array, schedule_name, params)
      timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour

      rules = schedule_array.select { |o| o[:name] == schedule_name }

      sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      sch_ruleset.setName(schedule_name)

      rules.each do |rule|
        day_types = rule[:day_types]
        # start_date = DateTime.strptime(rule[:start_date], '%m/%d/%Y')
        # end_date = DateTime.strptime(rule[:end_date], '%m/%d/%Y')
        sch_type = rule[:type]

        # find corresponding occ schedule rule by day type
        day_type_array = day_types.split('|')

        # categorize occupancy schedule profiles
        occ_profiles = schedule_ruleset_categorize_day_schedules(occ_schedule)

        day_type_array.each do |day_type|
          puts day_type
          target_occ_profile = nil

          # puts occ_profiles

          occ_profiles.each do |key, value|
            next unless target_occ_profile.nil?

            if value.split('|').include? day_type
              target_occ_profile = key
            end
          end

          if target_occ_profile.nil?
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedule', "Could not find matching occupancy schedule day type for #{day_types} in #{occ_schedule.name.get} types")
            return false
          end
          puts target_occ_profile

          # get corresponding target rule
          target_occ_rule = occ_schedule.scheduleRules.select { |r| r.daySchedule == target_occ_profile }.first

          # puts target_occ_rule

          # get occ schedule time value pairs
          occ_times = target_occ_profile.times.map(&:totalHours)
          occ_time_values = occ_times.zip(target_occ_profile.values)

          # override inputs if included in params
          base = params[:base].nil? ? rule[:base] : params[:base]
          peak = params[:peak].nil? ? rule[:peak] : params[:peak]
          response = params[:response].nil? ? rule[:response] : params[:response]

          # implement derivation
          derived_pairs = []
          occ_time_values.each do |initial_pair|
            derived_value = base + ((peak - base) * (initial_pair[1]**(1 / response.to_f)))
            derived_pairs << [initial_pair[0], derived_value]
          end

          puts derived_pairs

          # create rule
          if day_types.include?('Default')
            day_sch = sch_ruleset.defaultDaySchedule
            day_sch.setName("#{schedule_name} Default")
            model_add_time_value_pairs_to_schedule(day_sch, derived_pairs)
          end

          # Winter Design Day
          if day_types.include?('WntrDsn')
            day_sch = OpenStudio::Model::ScheduleDay.new(model)
            sch_ruleset.setWinterDesignDaySchedule(day_sch)
            day_sch = sch_ruleset.winterDesignDaySchedule
            day_sch.setName("#{schedule_name} Winter Design Day")
            model_add_time_value_pairs_to_schedule(day_sch, derived_pairs)
          end

          # Summer Design Day
          if day_types.include?('SmrDsn')
            day_sch = OpenStudio::Model::ScheduleDay.new(model)
            sch_ruleset.setSummerDesignDaySchedule(day_sch)
            day_sch = sch_ruleset.summerDesignDaySchedule
            day_sch.setName("#{schedule_name} Summer Design Day")
            model_add_time_value_pairs_to_schedule(day_sch, derived_pairs)
          end

          # Other days (weekdays, weekends, etc)
          if day_type_array.include?('Wknd') ||
             day_type.include?('Wkdy') ||
             day_type.include?('Sat') ||
             day_type.include?('Sun') ||
             day_type.include?('Mon') ||
             day_type.include?('Tue') ||
             day_type.include?('Wed') ||
             day_type.include?('Thu') ||
             day_type.include?('Fri')

            # Make the Rule
            sch_rule = OpenStudio::Model::ScheduleRule.new(sch_ruleset)
            day_sch = sch_rule.daySchedule
            day_sch.setName("#{schedule_name} #{day_types} Day")
            model_add_time_value_pairs_to_schedule(day_sch, derived_pairs)

            # Set the dates when the rule applies
            sch_rule.setStartDate(target_occ_rule.startDate.get) if target_occ_rule.startDate.is_initialized
            sch_rule.setEndDate(target_occ_rule.endDate.get) if target_occ_rule.endDate.is_initialized

            # Set the days when the rule applies
            # Weekends
            if day_types.include?('Wknd')
              sch_rule.setApplySaturday(true)
              sch_rule.setApplySunday(true)
            end
            # Weekdays
            if day_types.include?('Wkdy')
              sch_rule.setApplyMonday(true)
              sch_rule.setApplyTuesday(true)
              sch_rule.setApplyWednesday(true)
              sch_rule.setApplyThursday(true)
              sch_rule.setApplyFriday(true)
            end
            # Individual Days
            sch_rule.setApplyMonday(true) if day_types.include?('Mon')
            sch_rule.setApplyTuesday(true) if day_types.include?('Tue')
            sch_rule.setApplyWednesday(true) if day_types.include?('Wed')
            sch_rule.setApplyThursday(true) if day_types.include?('Thu')
            sch_rule.setApplyFriday(true) if day_types.include?('Fri')
            sch_rule.setApplySaturday(true) if day_types.include?('Sat')
            sch_rule.setApplySunday(true) if day_types.include?('Sun')
          end

          # add params to schedule additional properties
          props = day_sch.additionalProperties
          props.setFeature('base', base)
          props.setFeature('peak', peak)
          props.setFeature('response', response)
          props.setFeature('derived_from', target_occ_profile.name.get)
        end
      end

      return sch_ruleset
    end
  end
end

def test_add_parametric
  require 'json'
  require 'openstudio'

  schedule_data = JSON.parse(File.read('schedules_data_test.json'), symbolize_names: true)

  model = OpenStudio::Model::Model.new
  model.getTimestep.setNumberOfTimestepsPerHour(4)

  # default params
  occ_sch = OpenstudioStandards::Schedules.model_add_parametric_schedule(model, schedule_data, 'conference_meeting_multipurpose_occupancy', {})
  # puts occ_sch.defaultDaySchedule

  [0.5, 0.75, 1.0].each do |peak|
    [0.5, 1, 10].each do |response|
      equip_sch = OpenstudioStandards::Schedules.model_derive_equipment_schedule(model, occ_sch, schedule_data, 'conference_meeting_multipurpose_equipment', { base: 0.1, peak: peak, response: response })
      equip_sch.setName("equipment_peak:#{peak}_resp:#{response}")
    end
  end
  # puts equip_sch.defaultDaySchedule

  # equip_sch = OpenstudioStandards::Schedules.model_derive_equipment_schedule(model, occ_sch, schedule_data, 'conference_meeting_multipurpose_equipment', {base: 0.1, peak: 0.5, response: 10})

  # model.save('test1.osm', true)
  model.save('test4.osm', true)

  # model = OpenStudio::Model::Model.new
  # model.getTimestep.setNumberOfTimestepsPerHour(4)

  # # modified params
  # sch = OpenstudioStandards::Schedules.model_add_parametric_schedule(model, schedule_data, 'conference_meeting_multipurpose', { st: 6.0, et: 23.0, base: 0.25, peak: 0.75 })
  # puts sch.defaultDaySchedule
  # model.save('test2.osm', true)
end
