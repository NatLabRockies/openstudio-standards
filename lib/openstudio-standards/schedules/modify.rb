module OpenstudioStandards
  # The Schedules module provides methods to create, modify, and get information about Schedule objects
  module Schedules
    # Methods to modify existing Schedule objects

    # @!group Modify:ScheduleDay

    # Method to multiply the values in a day schedule by a specified value
    # The method can optionally apply the multiplier to only values above a lower limit.
    # This limit prevents multipliers for things like occupancy sensors from affecting unoccupied hours.
    #
    # @param schedule_day [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @param multiplier [Double] value to multiply schedule values by
    # @param lower_apply_limit [Double] apply the multiplier to only values above this value
    # @return [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    def self.schedule_day_multiply_by_value(schedule_day, multiplier, lower_apply_limit: nil)
      # Record the original times and values
      times = schedule_day.times
      values = schedule_day.values

      # Remove the original times and values
      schedule_day.clearValues

      # Create new values by using the multiplier on the original values
      new_values = []
      values.each do |value|
        if lower_apply_limit.nil?
          new_values << (value * multiplier)
        else
          if value > lower_apply_limit
            new_values << (value * multiplier)
          else
            new_values << value
          end
        end
      end

      # Add the revised time/value pairs to the schedule
      new_values.each_with_index do |new_value, i|
        schedule_day.addValue(times[i], new_value)
      end

      return schedule_day
    end

    # Set the hours of operation (0 or 1) for a ScheduleDay.
    # Clears out existing time/value pairs and sets to supplied values.
    #
    # @author Andrew Parker
    # @param schedule_day [OpenStudio::Model::ScheduleDay] The day schedule to set.
    # @param start_time [OpenStudio::Time] Start time.
    # @param end_time [OpenStudio::Time] End time.  If greater than 24:00, hours of operation will wrap over midnight.
    #
    # @return [Void]
    # @api private
    def self.schedule_day_set_hours_of_operation(schedule_day, start_time, end_time)
      schedule_day.clearValues
      twenty_four_hours = OpenStudio::Time.new(0, 24, 0, 0)
      if end_time < twenty_four_hours
        # Operating hours don't wrap over midnight
        schedule_day.addValue(start_time, 0) # 0 until start time
        schedule_day.addValue(end_time, 1) # 1 from start time until end time
        schedule_day.addValue(twenty_four_hours, 0) # 0 after end time
      else
        # Operating hours start on previous day
        schedule_day.addValue(end_time - twenty_four_hours, 1) # 1 for hours started on the previous day
        schedule_day.addValue(start_time, 0) # 0 from end of previous days hours until start of today's
        schedule_day.addValue(twenty_four_hours, 1) # 1 from start of today's hours until midnight
      end
    end

    # Sets the values of a day schedule from an array of values
    # Clears out existing time value pairs and sets to supplied values
    #
    # @param schedule_day [OpenStudio::Model::ScheduleDay] The day schedule to set.
    # @param value_array [Array] Array of 24 values. Schedule times set based on value index. Identical values will be skipped.
    # @return [OpenStudio::Model::ScheduleDay]
    def self.schedule_day_populate_from_array_of_values(schedule_day, value_array)
      schedule_day.clearValues
      if value_array.size != 24
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Modify', "#{__method__} expects value_array to contain 24 values, instead #{value_array.size} values were given. Resulting schedule will use first #{[24, value_array.size].min} values")
      end

      value_array[0..23].each_with_index do |value, h|
        next if value == value_array[h + 1]

        time = OpenStudio::Time.new(0, h + 1, 0, 0)
        schedule_day.addValue(time, value)
      end
      return schedule_day
    end

    # @!endgroup Modify:ScheduleDay

    # @!group Modify:ScheduleRuleset

    # Add a ScheduleRule to a ScheduleRuleset object from an array of hourly values
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param start_date [OpenStudio::Date] start date of week period
    # @param end_date [OpenStudio::Date] end date of week period
    # @param day_names [Array<String>] list of days of week for which this day type is applicable
    # @param values [Array<Double>] array of 24 hourly values for a day
    # @param rule_name [String] rule ScheduleDay object name
    # @return [OpenStudio::Model::ScheduleRule] OpenStudio ScheduleRule object
    def self.schedule_ruleset_add_rule(schedule_ruleset, values,
                                       start_date: nil,
                                       end_date: nil,
                                       day_names: nil,
                                       rule_name: nil)
      # create new schedule rule
      sch_rule = OpenStudio::Model::ScheduleRule.new(schedule_ruleset)
      day_sch = sch_rule.daySchedule
      day_sch.setName(rule_name) unless rule_name.nil?

      # set the dates when the rule applies
      sch_rule.setStartDate(start_date) unless start_date.nil?
      sch_rule.setEndDate(end_date) unless end_date.nil?

      # set the days for which the rule applies
      day_names&.each do |day_of_week|
        sch_rule.setApplySunday(true) if day_of_week == 'Sunday'
        sch_rule.setApplyMonday(true) if day_of_week == 'Monday'
        sch_rule.setApplyTuesday(true) if day_of_week == 'Tuesday'
        sch_rule.setApplyWednesday(true) if day_of_week == 'Wednesday'
        sch_rule.setApplyThursday(true) if day_of_week == 'Thursday'
        sch_rule.setApplyFriday(true) if day_of_week == 'Friday'
        sch_rule.setApplySaturday(true) if day_of_week == 'Saturday'
      end

      # Create the day schedule and add hourly values
      (0..23).each do |ihr|
        next if values[ihr] == values[ihr + 1]

        day_sch.addValue(OpenStudio::Time.new(0, ihr + 1, 0, 0), values[ihr])
      end

      return sch_rule
    end

    # Increase/decrease by percentage or static value.
    # If the schedule has a scheduleTypeLimits object, the adjusted values will subject to the lower and upper bounds of the schedule type limits object.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param value [Double] Hash of name and time value pairs
    # @param modification_type [String] Options are 'Multiplier', which multiples by the value,
    #   and 'Sum' which adds by the value
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @todo add in design day adjustments, maybe as an optional argument
    # @todo provide option to clone existing schedule
    def self.schedule_ruleset_simple_value_adjust(schedule_ruleset, value, modification_type = 'Multiplier')
      # gather profiles
      profiles = []
      # positive infinity
      upper_bound = Float::INFINITY
      # negative infinity
      lower_bound = -upper_bound
      if schedule_ruleset.scheduleTypeLimits.is_initialized
        schedule_type_limits = schedule_ruleset.scheduleTypeLimits.get
        if schedule_type_limits.lowerLimitValue.is_initialized
          lower_bound = schedule_type_limits.lowerLimitValue.get
        end
        if schedule_type_limits.upperLimitValue.is_initialized
          upper_bound = schedule_type_limits.upperLimitValue.get
        end
      end
      default_profile = schedule_ruleset.to_ScheduleRuleset.get.defaultDaySchedule
      profiles << default_profile
      rules = schedule_ruleset.scheduleRules
      rules.each do |rule|
        profiles << rule.daySchedule
      end

      # alter profiles
      profiles.each do |profile|
        times = profile.times
        i = 0
        profile.values.each do |sch_value|
          case modification_type
          when 'Multiplier', 'Percentage'
            # percentage was used early on but Multiplier is preferable
            new_value = (sch_value * value).clamp(lower_bound, upper_bound)
            profile.addValue(times[i], new_value)
          when 'Sum', 'Value'
            # value was used early on but Sum is preferable
            new_value = (sch_value + value).clamp(lower_bound, upper_bound)
            profile.addValue(times[i], new_value)
          end
          i += 1
        end
      end

      return schedule_ruleset
    end

    # Increase/decrease by percentage or static value
    # change value when value passes/fails test
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param test_value [Double] if less than the test_value, use the pass_value to modify, otherwise use the fail_value
    # @param pass_value [Double] value to adjust by if less than test value
    # @param fail_value [Double] value to adjust by if more than test value
    # @param floor_value [Double] minimum value that the adjustment can take
    # @param modification_type [String] Options are 'Multiplier', which multiples by the value,
    #   and 'Sum' which adds by the value
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @todo add in design day adjustments, maybe as an optional argument
    # @todo provide option to clone existing schedule
    def self.schedule_ruleset_conditional_adjust_value(schedule_ruleset, test_value, pass_value, fail_value, floor_value, modification_type = 'Multiplier')
      # gather profiles
      profiles = []
      default_profile = schedule_ruleset.to_ScheduleRuleset.get.defaultDaySchedule
      profiles << default_profile
      rules = schedule_ruleset.scheduleRules
      rules.each do |rule|
        profiles << rule.daySchedule
      end

      # alter profiles
      profiles.each do |profile|
        times = profile.times
        i = 0

        profile.values.each do |sch_value|
          # run test on this sch_value
          if sch_value < test_value
            adjust_value = pass_value
          else
            adjust_value = fail_value
          end

          # skip if sch_value is floor or less
          next if sch_value <= floor_value

          case modification_type
          when 'Multiplier'
            # take the max of the floor or resulting value
            profile.addValue(times[i], [sch_value * adjust_value, floor_value].max)
          when 'Sum'
            # take the max of the floor or resulting value
            profile.addValue(times[i], [sch_value + adjust_value, floor_value].max)
          end
          i += 1
        end
      end

      return schedule_ruleset
    end

    # Increase/decrease by percentage or static value
    # change value when time passes test
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param hhmm_before [String] time before string in hhmm format, e.g. 1530
    # @param hhmm_after [String] string in hhmm format, e.g. 1530
    # @param inside_value [Double]
    # @param outside_value [Double]
    # @param modification_type [String] Options are 'Sum', which adds to the value,
    #   and 'Replace' which replaces the value
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.schedule_ruleset_time_conditional_adjust_value(schedule_ruleset, hhmm_before, hhmm_after, inside_value, outside_value, modification_type = 'Sum')
      # setup variables
      array = hhmm_before.to_s.chars
      before_hour = "#{array[0]}#{array[1]}".to_i
      before_min = "#{array[2]}#{array[3]}".to_i
      array = hhmm_after.to_s.chars
      after_hour = "#{array[0]}#{array[1]}".to_i
      after_min = "#{array[2]}#{array[3]}".to_i

      # gather profiles
      profiles = []
      schedule = schedule_ruleset.to_ScheduleRuleset.get
      default_profile = schedule_ruleset.defaultDaySchedule
      profiles << default_profile
      rules = schedule_ruleset.scheduleRules
      rules.each do |rule|
        profiles << rule.daySchedule
      end

      # alter profiles
      profiles.each do |day_sch|
        times = day_sch.times
        i = 0

        # set times special times needed for methods below
        before_time = OpenStudio::Time.new(0, before_hour, before_min, 0)
        after_time = OpenStudio::Time.new(0, after_hour, after_min, 0)
        # day_end_time = OpenStudio::Time.new(0, 24, 0, 0)

        # add datapoint at before and after time
        original_value_at_before_time = day_sch.getValue(before_time)
        original_value_at_after_time = day_sch.getValue(after_time)
        day_sch.addValue(before_time, original_value_at_before_time)
        day_sch.addValue(after_time, original_value_at_after_time)

        # make arrays for original times and values
        times = day_sch.times
        sch_values = day_sch.values
        day_sch.clearValues

        # make arrays for new values
        new_times = []
        new_values = []

        # loop through original time/value pairs to populate new array
        for i in 0..(sch_values.length - 1)
          new_times << times[i]

          if times[i] > before_time && times[i] <= after_time
            # updated this so times[i] == before_time goes into the else
            if inside_value.nil?
              new_values << sch_values[i]
            elsif modification_type == 'Sum'
              new_values << (inside_value + sch_values[i])
            elsif modification_type == 'Replace'
              new_values << inside_value
            else # should be Multiplier
              new_values << (inside_value * sch_values[i])
            end
          else
            if outside_value.nil?
              new_values << sch_values[i]
            elsif modification_type == 'Sum'
              new_values << (outside_value + sch_values[i])
            elsif modification_type == 'Replace'
              new_values << outside_value
            else # should be Multiplier
              new_values << (outside_value * sch_values[i])
            end
          end

        end

        # generate new day_sch values
        for i in 0..(new_values.length - 1)
          day_sch.addValue(new_times[i], new_values[i])
        end
      end

      return schedule_ruleset
    end

    # Adjust hours of operation
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param options [Hash] Hash of argument options
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.schedule_ruleset_adjust_hours_of_operation(schedule_ruleset, options = {})
      defaults = {
        'base_start_hoo' => 8.0, # may not be good idea to have default
        'base_finish_hoo' => 18.0, # may not be good idea to have default
        'delta_length_hoo' => 0.0,
        'shift_hoo' => 0.0,
        'default' => true,
        'mon' => true,
        'tue' => true,
        'wed' => true,
        'thur' => true,
        'fri' => true,
        'sat' => true,
        'sun' => true,
        'summer' => false,
        'winter' => false
      }

      # merge user inputs with defaults
      options = defaults.merge(options)

      # grab schedule out of argument
      if schedule_ruleset.to_ScheduleRuleset.is_initialized
        schedule = schedule_ruleset.to_ScheduleRuleset.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Modify', "schedule_ruleset_adjust_hours_of_operation only applies to ScheduleRuleset objects. Skipping #{schedule.name}")
        return nil
      end

      # array of all profiles to change
      profiles = []

      # push default profiles to array
      if options['default']
        profiles << schedule.defaultDaySchedule
      end

      # push profiles to array
      schedule.scheduleRules.each do |rule|
        day_sch = rule.daySchedule

        # if any day requested also exists in the rule, then it will be altered
        alter_rule = false
        if rule.applyMonday && rule.applyMonday == options['mon'] then alter_rule = true end
        if rule.applyTuesday && rule.applyTuesday == options['tue'] then alter_rule = true end
        if rule.applyWednesday && rule.applyWednesday == options['wed'] then alter_rule = true end
        if rule.applyThursday && rule.applyThursday == options['thur'] then alter_rule = true end
        if rule.applyFriday && rule.applyFriday == options['fri'] then alter_rule = true end
        if rule.applySaturday && rule.applySaturday == options['sat'] then alter_rule = true end
        if rule.applySunday && rule.applySunday == options['sun'] then alter_rule = true end

        # @todo add in logic to warn user about conflicts where a single rule has conflicting tests

        if alter_rule
          profiles << day_sch
        end
      end

      # add design days to array
      if options['summer']
        profiles << schedule.summerDesignDaySchedule
      end
      if options['winter']
        profiles << schedule.winterDesignDaySchedule
      end

      # give info messages as I change specific profiles
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules.Modify', "Adjusting #{schedule.name}")

      # rename schedule
      schedule.setName("#{schedule.name} - extend #{options['delta_length_hoo']} shift #{options['shift_hoo']}")

      # break time args into hours and minutes
      start_hoo_hours = options['base_start_hoo'].to_i
      start_hoo_minutes = ((options['base_start_hoo'] - options['base_start_hoo'].to_i) * 60).to_i
      finish_hoo_hours = options['base_finish_hoo'].to_i
      finish_hoo_minutes = ((options['base_finish_hoo'] - options['base_finish_hoo'].to_i) * 60).to_i
      delta_hours = options['delta_length_hoo'].to_i
      delta_minutes = ((options['delta_length_hoo'] - options['delta_length_hoo'].to_i) * 60).to_i
      shift_hours = options['shift_hoo'].to_i
      shift_minutes = ((options['shift_hoo'] - options['shift_hoo'].to_i) * 60).to_i

      # time objects to use in measure
      time_0 = OpenStudio::Time.new(0, 0, 0, 0)
      time_1_min = OpenStudio::Time.new(0, 0, 1, 0) # add this to avoid times in day profile less than this
      time_12 =  OpenStudio::Time.new(0, 12, 0, 0)
      time_24 =  OpenStudio::Time.new(0, 24, 0, 0)
      start_hoo_time = OpenStudio::Time.new(0, start_hoo_hours, start_hoo_minutes, 0)
      finish_hoo_time = OpenStudio::Time.new(0, finish_hoo_hours, finish_hoo_minutes, 0)
      delta_time = OpenStudio::Time.new(0, delta_hours, delta_minutes, 0) # not used
      shift_time = OpenStudio::Time.new(0, shift_hours, shift_minutes, 0)

      # calculations
      if options['base_start_hoo'] <= options['base_finish_hoo']
        base_opp_day_length = options['base_finish_hoo'] - options['base_start_hoo']
        mid_hoo = start_hoo_time + ((finish_hoo_time - start_hoo_time) / 2)
        mid_non_hoo = mid_hoo + time_12
        if mid_non_hoo > time_24 then mid_non_hoo -= time_24 end
      else
        base_opp_day_length = options['base_finish_hoo'] - options['base_start_hoo'] + 24
        mid_non_hoo = finish_hoo_time + ((start_hoo_time - finish_hoo_time) / 2)
        mid_hoo = mid_non_hoo + time_12
        if mid_non_hoo > time_24 then mid_non_hoo -= time_24 end
      end
      adjusted_opp_day_length = base_opp_day_length + options['delta_length_hoo']
      hoo_time_multiplier = adjusted_opp_day_length / base_opp_day_length
      non_hoo_time_multiplier = (24 - adjusted_opp_day_length) / (24 - base_opp_day_length)

      # check for invalid input
      if adjusted_opp_day_length < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Modify', 'Requested hours of operation adjustment results in an invalid negative hours of operation')
        return false
      end
      # check for invalid input
      if adjusted_opp_day_length > 24
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Modify', 'Requested hours of operation adjustment results in more than 24 hours of operation')
        return false
      end

      # making some temp objects to avoid having to deal with wrap around for change of hoo times
      mid_hoo < start_hoo_time ? (adj_mid_hoo = mid_hoo + time_24) : (adj_mid_hoo = mid_hoo)
      finish_hoo_time < adj_mid_hoo ? (adj_finish_hoo_time = finish_hoo_time + time_24) : (adj_finish_hoo_time = finish_hoo_time)
      mid_non_hoo < adj_finish_hoo_time ? (adj_mid_non_hoo = mid_non_hoo + time_24) : (adj_mid_non_hoo = mid_non_hoo)
      adj_start = start_hoo_time + time_24 # not used

      # edit profiles
      profiles.each do |day_sch|
        times = day_sch.times
        values = day_sch.values

        # in this case delete all values outside of
        # todo - may need similar logic if exactly 0 hours
        if adjusted_opp_day_length == 24
          start_val = day_sch.getValue(start_hoo_time)
          finish_val = day_sch.getValue(finish_hoo_time)

          # remove times out of range that should not be reference or compressed
          if start_hoo_time < finish_hoo_time
            times.each do |time|
              if time <= start_hoo_time || time > finish_hoo_time
                day_sch.removeValue(time)
              end
            end
            # add in values
            day_sch.addValue(start_hoo_time, start_val)
            day_sch.addValue(finish_hoo_time, finish_val)
            day_sch.addValue(time_24, [start_val, finish_val].max)
          else
            times.each do |time|
              if time > start_hoo_time && time <= finish_hoo_time
                day_sch.removeValue(time)
              end
            end
            # add in values
            day_sch.addValue(finish_hoo_time, finish_val)
            day_sch.addValue(start_hoo_time, start_val)
            day_sch.addValue(time_24, [values.first, values.last].max)
          end

        end

        times = day_sch.times
        values = day_sch.values

        # arrays for values to avoid overlap conflict of times
        new_times = []
        new_values = []

        # this is to store what datapoint will be first after midnight, and what the value at that time should be
        min_time_new = time_24
        min_time_value = nil

        # flag if found time at 24
        found_24_or_0 = false

        # push times to array
        times.each do |time|
          # create logic for four possible quadrants. Assume any quadrant can pass over 24/0 threshold
          time < start_hoo_time ? (temp_time = time + time_24) : (temp_time = time)

          # calculate change in time do to hoo delta
          if temp_time <= adj_finish_hoo_time
            expand_time = ((temp_time - adj_mid_hoo) * hoo_time_multiplier) - (temp_time - adj_mid_hoo)
          else
            expand_time = ((temp_time - adj_mid_non_hoo) * non_hoo_time_multiplier) - (temp_time - adj_mid_non_hoo)
          end

          new_time = time + shift_time + expand_time

          # adjust wrap around times
          if new_time < time_0
            new_time += time_24
          elsif new_time > time_24
            new_time -= time_24
          end
          new_times << new_time

          # see which new_time has the lowest value. Then add a value at 24 equal to that
          if !found_24_or_0 && new_time <= min_time_new
            min_time_new = new_time
            min_time_value = day_sch.getValue(time)
          elsif new_time == time_24 # this was added to address time exactly at 24
            min_time_new = new_time
            min_time_value = day_sch.getValue(time)
            found_24_or_0 = true
          elsif new_time == time_0
            min_time_new = new_time
            min_time_value = day_sch.getValue(time_0)
            found_24_or_0 = true
          end
        end

        # push values to array
        new_values.concat(values)

        # add value for what will be 24
        new_times << time_24
        new_values << min_time_value

        new_time_val_hash = {}
        new_times.each_with_index do |time, i|
          new_time_val_hash[time.totalHours] = { time: time, value: new_values[i] }
        end

        # clear values
        day_sch.clearValues

        new_time_val_hash = new_time_val_hash.sort.to_h
        prev_time = nil
        new_time_val_hash.sort.each do |hours, time_val|
          if prev_time.nil? || time_val[:time] - prev_time > time_1_min
            day_sch.addValue(time_val[:time], time_val[:value])
            prev_time = time_val[:time]
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Modify', "Time step in #{day_sch.name} between #{prev_time.toString} and #{time_val[:time].toString} is too small to support, not adding value.")
          end
        end
      end

      return schedule
    end

    # Remove unused profiles and set most prevalent profile as default.
    # This method expands on the functionality of the RemoveUnusedDefaultProfiles measure.
    #
    # @author David Goldwasser
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @todo There are potential issues with overlapping rule dates or days of week when setting a profile that isn't the lowest priority as the default day.
    def self.schedule_ruleset_cleanup_profiles(schedule_ruleset)
      # set start and end dates
      year_description = schedule_ruleset.model.yearDescription.get
      year = year_description.assumedYear
      year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
      year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)

      indices_vector = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)
      most_frequent_item = indices_vector.uniq.max_by { |i| indices_vector.count(i) }
      rule_vector = schedule_ruleset.scheduleRules

      replace_existing_default = false
      if indices_vector.include?(-1) && (most_frequent_item != -1)
        # clean up if default isn't most common (e.g. sunday vs. weekday)
        # if no existing rules cover specific days of week, make new rule from default covering those days of week
        possible_days_of_week = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        used_days_of_week = []
        rule_vector.each do |rule|
          if rule.applyMonday then used_days_of_week << 'Monday' end
          if rule.applyTuesday then used_days_of_week << 'Tuesday' end
          if rule.applyWednesday then used_days_of_week << 'Wednesday' end
          if rule.applyThursday then used_days_of_week << 'Thursday' end
          if rule.applyFriday then used_days_of_week << 'Friday' end
          if rule.applySaturday then used_days_of_week << 'Saturday' end
          if rule.applySunday then used_days_of_week << 'Sunday' end
        end
        if used_days_of_week.uniq.size < possible_days_of_week.size
          replace_existing_default = true
          schedule_rule_new = OpenStudio::Model::ScheduleRule.new(schedule_ruleset, schedule_ruleset.defaultDaySchedule)
          if !used_days_of_week.include?('Monday') then schedule_rule_new.setApplyMonday(true) end
          if !used_days_of_week.include?('Tuesday') then schedule_rule_new.setApplyTuesday(true) end
          if !used_days_of_week.include?('Wednesday') then schedule_rule_new.setApplyWednesday(true) end
          if !used_days_of_week.include?('Thursday') then schedule_rule_new.setApplyThursday(true) end
          if !used_days_of_week.include?('Friday') then schedule_rule_new.setApplyFriday(true) end
          if !used_days_of_week.include?('Saturday') then schedule_rule_new.setApplySaturday(true) end
          if !used_days_of_week.include?('Sunday') then schedule_rule_new.setApplySunday(true) end
        end
      end

      if !indices_vector.include?(-1) || replace_existing_default
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules.Modify', "#{schedule_ruleset.name} does not use the default profile, it will be replaced.")

        # reset values in default ScheduleDay
        old_default_schedule_day = schedule_ruleset.defaultDaySchedule
        old_default_schedule_day.clearValues

        # update selection to the most commonly used profile vs. the lowest priority, if it can be done without any conflicts
        # safe test is to see if any other rules use same days of week as most common,
        # if doesn't pass then make highest rule the new default to avoid any problems. School may not pass this test, woudl use last rule
        days_of_week_most_frequent_item = []
        schedule_rule_most_frequent = rule_vector[most_frequent_item]
        if schedule_rule_most_frequent.applyMonday then days_of_week_most_frequent_item << 'Monday' end
        if schedule_rule_most_frequent.applyTuesday then days_of_week_most_frequent_item << 'Tuesday' end
        if schedule_rule_most_frequent.applyWednesday then days_of_week_most_frequent_item << 'Wednesday' end
        if schedule_rule_most_frequent.applyThursday then days_of_week_most_frequent_item << 'Thursday' end
        if schedule_rule_most_frequent.applyFriday then days_of_week_most_frequent_item << 'Friday' end
        if schedule_rule_most_frequent.applySaturday then days_of_week_most_frequent_item << 'Saturday' end
        if schedule_rule_most_frequent.applySunday then days_of_week_most_frequent_item << 'Sunday' end

        # loop through rules
        conflict_found = false
        rule_vector.each do |rule|
          next if rule == schedule_rule_most_frequent

          days_of_week_most_frequent_item.each do |day_of_week|
            if (day_of_week == 'Monday') && rule.applyMonday then conflict_found == true end
            if (day_of_week == 'Tuesday') && rule.applyTuesday then conflict_found == true end
            if (day_of_week == 'Wednesday') && rule.applyWednesday then conflict_found == true end
            if (day_of_week == 'Thursday') && rule.applyThursday then conflict_found == true end
            if (day_of_week == 'Friday') && rule.applyFriday then conflict_found == true end
            if (day_of_week == 'Saturday') && rule.applySaturday then conflict_found == true end
            if (day_of_week == 'Sunday') && rule.applySunday then conflict_found == true end
          end
        end
        if conflict_found
          new_default_index = indices_vector.max
        else
          new_default_index = most_frequent_item
        end

        # get values for new default profile
        new_default_day_schedule = rule_vector[new_default_index].daySchedule
        new_default_day_schedule_values = new_default_day_schedule.values
        new_default_day_schedule_times = new_default_day_schedule.times

        # update values and times for default profile
        for i in 0..(new_default_day_schedule_values.size - 1)
          old_default_schedule_day.addValue(new_default_day_schedule_times[i], new_default_day_schedule_values[i])
        end

        # remove rule object that has become the default. Also try to remove the ScheduleDay
        rule_vector[new_default_index].remove # this seems to also remove the ScheduleDay associated with the rule
      end

      return schedule_ruleset
    end

    # creates a minimal set of ScheduleRules that applies to all days in a given array of day of year indices
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset]
    # @param days_used [Array] array of day of year integers
    # @param schedule_day [OpenStudio::Model::ScheduleDay] optional day schedule to apply to new rule. A new default schedule will be created for each rule if nil
    # @return [Array]
    def self.schedule_ruleset_create_rules_from_day_list(schedule_ruleset, days_used, schedule_day: nil)
      # get year from schedule_ruleset
      year = schedule_ruleset.model.getYearDescription.assumedYear

      # split day_used into sub arrays of consecutive days
      consec_days = days_used.chunk_while { |i, j| i + 1 == j }.to_a

      # split consec_days into sub arrays of consecutive weeks by checking that any value in next array differs by seven from a value in this array
      consec_weeks = consec_days.chunk_while { |i, j| i.product(j).any? { |x, y| (x - y).abs == 7 } }.to_a

      # make new rule for blocks of consectutive weeks
      rules = []
      consec_weeks.each do |week_group|
        if schedule_day.nil?
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.ScheduleRuleset', 'Creating new Rule Schedule from days_used vector with new Day Schedule')
          rule = OpenStudio::Model::ScheduleRule.new(schedule_ruleset)
        else
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Parametric.ScheduleRuleset', "Creating new Rule Schedule from days_used vector with clone of Day Schedule: #{schedule_day.name.get}")
          rule = OpenStudio::Model::ScheduleRule.new(schedule_ruleset, schedule_day)
        end

        # set day types and dates
        dates = week_group.flatten.map { |d| OpenStudio::Date.fromDayOfYear(d, year) }
        day_types = dates.map { |date| date.dayOfWeek.valueName }.uniq
        day_types.each { |type| rule.send("setApply#{type}", true) }
        rule.setStartDate(dates.min)
        rule.setEndDate(dates.max)

        rules << rule
      end

      return rules
    end

    # @!endgroup Modify:ScheduleRuleset
  end
end
