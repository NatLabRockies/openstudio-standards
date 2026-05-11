module OpenstudioStandards
  # The Schedules module provides methods to create, modify, and get information about Schedule objects
  module Schedules
    # @!group Information
    # Methods to get information about Schedule objects

    # Returns the Schedule minimum and maximum values encountered during the run-period.
    # This method does not include summer and winter design day values.
    #
    # @param schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object
    # @param only_run_period_values [Bool] check values encountered only during the run period
    #   Default to false. Only applicable to ScheduleRuleset schedules.
    #   This will ignore ScheduleRules or the DefaultDaySchedule if never used.
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_get_min_max(schedule, only_run_period_values: false)
      case schedule.iddObjectType.valueName.to_s
      when 'OS_Schedule_Ruleset'
        schedule = schedule.to_ScheduleRuleset.get
        result = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(schedule, only_run_period_values: only_run_period_values)
      when 'OS_Schedule_Constant'
        schedule = schedule.to_ScheduleConstant.get
        result = OpenstudioStandards::Schedules.schedule_constant_get_min_max(schedule)
      when 'OS_Schedule_Compact'
        schedule = schedule.to_ScheduleCompact.get
        result = OpenstudioStandards::Schedules.schedule_compact_get_min_max(schedule)
      when 'OS_Schedule_Year'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleYear schedules.")
        result = { 'min' => nil, 'max' => nil }
      when 'OS_Schedule_Interval'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleInterval schedules.")
        result = { 'min' => nil, 'max' => nil }
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "unrecognized schedule type #{schedule.iddObjectType.valueName} for #{__method__}.")
        result = { 'min' => nil, 'max' => nil }
      end

      return result
    end

    # Returns the Schedule minimum and maximum values during the winter or summer design day.
    #
    # @param schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object
    # @param type [String] 'winter' for the winter design day, 'summer' for the summer design day
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_get_design_day_min_max(schedule, type = 'winter')
      case schedule.iddObjectType.valueName.to_s
      when 'OS_Schedule_Ruleset'
        schedule = schedule.to_ScheduleRuleset.get
        result = OpenstudioStandards::Schedules.schedule_ruleset_get_design_day_min_max(schedule, type)
      when 'OS_Schedule_Constant'
        schedule = schedule.to_ScheduleConstant.get
        result = OpenstudioStandards::Schedules.schedule_constant_get_design_day_min_max(schedule, type)
      when 'OS_Schedule_Compact'
        schedule = schedule.to_ScheduleCompact.get
        result = OpenstudioStandards::Schedules.schedule_compact_get_design_day_min_max(schedule, type)
      when 'OS_Schedule_Year'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleYear schedules.")
        result = { 'min' => nil, 'max' => nil }
      when 'OS_Schedule_Interval'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleInterval schedules.")
        result = { 'min' => nil, 'max' => nil }
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "unrecognized schedule type #{schedule.iddObjectType.valueName} for #{__method__}.")
        result = { 'min' => nil, 'max' => nil }
      end

      return result
    end

    # Returns the Schedule equivalent full load hours (EFLH).
    # For example a fractional schedule of 0.5, 24/7, 365 would return a value of 4380.
    # This method includes leap days on leap years.
    #
    # @param schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object
    # return [Double] The total equivalent full load hours for this schedule
    def self.schedule_get_equivalent_full_load_hours(schedule)
      case schedule.iddObjectType.valueName.to_s
      when 'OS_Schedule_Ruleset'
        schedule = schedule.to_ScheduleRuleset.get
        result = OpenstudioStandards::Schedules.schedule_ruleset_get_equivalent_full_load_hours(schedule)
      when 'OS_Schedule_Constant'
        schedule = schedule.to_ScheduleConstant.get
        result = OpenstudioStandards::Schedules.schedule_constant_get_equivalent_full_load_hours(schedule)
      when 'OS_Schedule_Compact'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleCompact schedules.")
        result = nil
      when 'OS_Schedule_Year'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleYear schedules.")
        result = nil
      when 'OS_Schedule_Interval'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleInterval schedules.")
        result = nil
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "unrecognized schedule type #{schedule.iddObjectType.valueName} for #{__method__}.")
        result = nil
      end

      return result
    end

    # Returns an array of average hourly values from a Schedule object
    # Returns 8760 values, 8784 for leap years.
    #
    # @param schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object
    # @return [Array<Double>] Array of hourly values for the year
    def self.schedule_get_hourly_values(schedule)
      case schedule.iddObjectType.valueName.to_s
      when 'OS_Schedule_Ruleset'
        schedule = schedule.to_ScheduleRuleset.get
        result = OpenstudioStandards::Schedules.schedule_ruleset_get_hourly_values(schedule)
      when 'OS_Schedule_Constant'
        schedule = schedule.to_ScheduleConstant.get
        result = OpenstudioStandards::Schedules.schedule_constant_get_hourly_values(schedule)
      when 'OS_Schedule_Compact'
        schedule = schedule.to_ScheduleCompact.get
        result = OpenstudioStandards::Schedules.schedule_compact_get_hourly_values(schedule)
      when 'OS_Schedule_Year'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleYear schedules.")
        result = nil
      when 'OS_Schedule_Interval'
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} does not yet support ScheduleInterval schedules.")
        result = nil
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "unrecognized schedule type #{schedule.iddObjectType.valueName} for #{__method__}.")
        result = nil
      end

      return result
    end

    # @!endgroup Information

    # @!group Information:ScheduleConstant

    # Returns the ScheduleConstant minimum and maximum values encountered during the run-period.
    # This method does not include summer and winter design day values.
    #
    # @param schedule_constant [OpenStudio::Model::ScheduleConstant] OpenStudio ScheduleConstant object
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_constant_get_min_max(schedule_constant)
      result = { 'min' => schedule_constant.value, 'max' => schedule_constant.value }

      return result
    end

    # Returns the ScheduleConstant minimum and maximum values during the winter or summer design day.
    #
    # @param schedule_constant [OpenStudio::Model::ScheduleConstant] OpenStudio ScheduleConstant object
    # @param type [String] 'winter' for the winter design day, 'summer' for the summer design day
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_constant_get_design_day_min_max(schedule_constant, type)
      result = { 'min' => schedule_constant.value, 'max' => schedule_constant.value }

      return result
    end

    # Returns SheduleConstant equivalent full load hours (EFLH).
    # For example a fractional schedule of 0.5, 24/7, 365 would return a value of 4380.
    # This method includes leap days on leap years.
    #
    # @param schedule_constant [OpenStudio::Model::ScheduleConstant] OpenStudio ScheduleConstant object
    # return [Double] The total equivalent full load hours for this schedule
    def self.schedule_constant_get_equivalent_full_load_hours(schedule_constant)
      hours = 8760
      hours += 24 if schedule_constant.model.getYearDescription.isLeapYear
      eflh = schedule_constant.value * hours

      return eflh
    end

    # Returns an array of average hourly values from a ScheduleConstant object
    # Returns 8760 values, 8784 for leap years.
    #
    # @param schedule_constant [OpenStudio::Model::ScheduleConstant] OpenStudio ScheduleConstant object
    # @return [Array<Double>] Array of hourly values for the year
    def self.schedule_constant_get_hourly_values(schedule_constant)
      hours = 8760
      hours += 24 if schedule_constant.model.getYearDescription.isLeapYear
      values = Array.new(hours) { schedule_constant.value }

      return values
    end

    # @!endgroup Information:ScheduleConstant

    # @!group Information:ScheduleCompact

    # Returns the ScheduleCompact minimum and maximum values encountered during the run-period.
    # This method does not include summer and winter design day values.
    #
    # @param schedule_compact [OpenStudio::Model::ScheduleCompact] OpenStudio ScheduleCompact object
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_compact_get_min_max(schedule_compact)
      vals = []
      prev_str = ''
      schedule_compact.extensibleGroups.each do |eg|
        if prev_str.include?('until')
          val = eg.getDouble(0)
          if val.is_initialized
            vals << eg.getDouble(0).get
          end
        end
        str = eg.getString(0)
        if str.is_initialized
          prev_str = str.get.downcase
        end
      end

      # Error if no values were found
      if vals.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "Could not find any value in #{schedule_compact.name} when determining min and max.")
        result = { 'min' => nil, 'max' => nil }
        return result
      end

      result = { 'min' => vals.min, 'max' => vals.max }

      return result
    end

    # Returns the ScheduleCompact minimum and maximum values during the winter or summer design day.
    #
    # @param schedule_compact [OpenStudio::Model::ScheduleCompact] OpenStudio ScheduleCompact object
    # @param type [String] 'winter' for the winter design day, 'summer' for the summer design day
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_compact_get_design_day_min_max(schedule_compact, type = 'winter')
      vals = []
      design_day_flag = false
      prev_str = ''
      schedule_compact.extensibleGroups.each do |eg|
        if design_day_flag && prev_str.include?('until')
          val = eg.getDouble(0)
          if val.is_initialized
            vals << val.get
          end
        end

        str = eg.getString(0)
        if str.is_initialized
          prev_str = str.get.downcase
          if prev_str.include?('for:')
            # Process a new day schedule, turn the flag off.
            design_day_flag = false
            # in the same line, if there is design day label and matches the type, turn the flag back on.
            if prev_str.include?(type) || prev_str.include?('alldays')
              design_day_flag = true
            end
          end
        end
      end

      # Error if no values were found
      if vals.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "Could not find any value in #{schedule_compact.name} design day schedule when determining min and max.")
        result = { 'min' => nil, 'max' => nil }
        return result
      end

      result = { 'min' => vals.min, 'max' => vals.max }

      return result
    end

    # Returns an array of average hourly values from a ScheduleCompact object
    # Returns 8760 values, 8784 for leap years.
    #
    # @param schedule_compact [OpenStudio::Model::ScheduleCompact] OpenStudio ScheduleCompact object
    # @return [Array<Double>] Array of hourly values for the year
    def self.schedule_compact_get_hourly_values(schedule_compact)
      # set a ScheduleTypeLimits if none is present
      # this is required for the ScheduleTranslator instantiation
      unless schedule_compact.scheduleTypeLimits.is_initialized
        schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
        schedule_compact.setScheduleTypeLimits(schedule_type_limits)
      end

      # convert to a ScheduleRuleset and use its method
      sch_translator = ScheduleTranslator.new(schedule_compact.model, schedule_compact)
      schedule_ruleset = sch_translator.convert_schedule_compact_to_schedule_ruleset
      result = OpenstudioStandards::Schedules.schedule_ruleset_get_hourly_values(schedule_ruleset)

      return result
    end

    # @!endgroup Information:ScheduleCompact

    # @!group Information:ScheduleDay

    # Returns the ScheduleDay minimum and maximum values
    #
    # @param schedule_day [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_day_get_min_max(schedule_day)
      min = nil
      max = nil
      values = schedule_day.values
      values.each do |value|
        if min.nil?
          min = value
        else
          if min > value then min = value end
        end
        if max.nil?
          max = value
        else
          if max < value then max = value end
        end
      end

      result = { 'min' => min, 'max' => max }
    end

    # Returns the ScheduleDay daily equivalent full load hours (EFLH).
    #
    # @param schedule_day [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # return [Double] The daily total equivalent full load hours for this schedule
    def self.schedule_day_get_equivalent_full_load_hours(schedule_day)
      daily_flh = 0
      values = schedule_day.values
      times = schedule_day.times

      previous_time_decimal = 0
      times.each_with_index do |time, i|
        time_decimal = (time.days * 24.0) + time.hours + (time.minutes / 60.0) + (time.seconds / 3600.0)
        duration_of_value = time_decimal - previous_time_decimal
        daily_flh += values[i] * duration_of_value
        previous_time_decimal = time_decimal
      end

      return daily_flh
    end

    # Returns an array of average hourly values from a ScheduleDay object
    # Returns 24 values
    #
    # @param schedule_day [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @return [Array<Double>] Array of hourly values for the day
    def self.schedule_day_get_hourly_values(schedule_day, model = nil)
      schedule_values = []

      if model.nil?
        model = schedule_day.model
      end

      if model.version.str < '3.8.0'
        # determine smallest time interval
        times = schedule_day.times
        time_interval_min = 15.0
        previous_time_decimal = 0.0
        times.each_with_index do |time, i|
          time_decimal = (time.days * 24.0 * 60.0) + (time.hours * 60.0) + time.minutes + (time.seconds / 60)
          interval_min = time_decimal - previous_time_decimal
          time_interval_min = interval_min if interval_min < time_interval_min
          previous_time_decimal = time_decimal
        end
        time_interval_min = time_interval_min.round(0).to_i

        # get the hourly average by averaging the values in the hour at the smallest time interval
        (0..23).each do |j|
          values = []
          times = (time_interval_min..60).step(time_interval_min).to_a
          times.each { |t| values << schedule_day.getValue(OpenStudio::Time.new(0, j, t, 0)) }
          schedule_values << (values.sum / times.size).round(5)
        end
      else
        num_timesteps = model.getTimestep.numberOfTimestepsPerHour
        day_timeseries = schedule_day.timeSeries.values.to_a
        schedule_values = day_timeseries.each_slice(num_timesteps).map { |slice| (slice.sum / slice.size.to_f).round(10) }
      end

      unless schedule_values.size == 24
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} returned illegal number of values: #{schedule_values.size}.")
        return false
      end

      return schedule_values
    end

    # @!endgroup Information:ScheduleDay

    # @!group Information:ScheduleRuleset

    # Returns the ScheduleRuleset minimum and maximum values.
    # This method does not include summer and winter design day values.
    # By default the method reports values from all component day schedules even if unused,
    # but can optionally report values encountered only during the run period.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param only_run_period_values [Bool] check values encountered only during the run period
    #   Default to false. This will ignore ScheduleRules or the DefaultDaySchedule if never used.
    # @return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_ruleset_get_min_max(schedule_ruleset, only_run_period_values: false)
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return nil
      end

      # day schedules
      day_schedules = []

      # check only day schedules in the run period
      if only_run_period_values
        # get year
        if schedule_ruleset.model.yearDescription.is_initialized
          year_description = schedule_ruleset.model.yearDescription.get
          year = year_description.assumedYear
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', 'Year description is not specified. Full load hours calculation will assume 2009, the default year OS uses.')
          year = 2009
        end

        # get start and end month and day
        run_period = schedule_ruleset.model.getRunPeriod
        start_month = run_period.getBeginMonth
        start_day = run_period.getBeginDayOfMonth
        end_month = run_period.getEndMonth
        end_day = run_period.getEndDayOfMonth

        # set the start and end date
        start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(start_month), start_day, year)
        end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(end_month), end_day, year)

        # Get the ordered list of all the day schedules
        day_schs = schedule_ruleset.getDaySchedules(start_date, end_date)

        # Get the array of which schedule is used on each day of the year
        day_schs_used_each_day = schedule_ruleset.getActiveRuleIndices(start_date, end_date)

        # Create a map that shows how many days each schedule is used
        day_sch_freq = day_schs_used_each_day.group_by { |n| n }

        # Build a hash that maps schedule day index to schedule day
        schedule_index_to_day = {}
        day_schs.each_with_index do |day_sch, i|
          schedule_index_to_day[day_schs_used_each_day[i]] = day_sch
        end

        # Loop through each of the schedules and record which ones are used
        day_sch_freq.each do |freq|
          sch_index = freq[0]
          number_of_days_sch_used = freq[1].size
          next unless number_of_days_sch_used > 0

          # Get the day schedule at this index
          day_sch = nil
          if sch_index == -1 # If index = -1, this day uses the default day schedule (not a rule)
            day_sch = schedule_ruleset.defaultDaySchedule
          else
            day_sch = schedule_index_to_day[sch_index]
          end

          # add day schedule to array
          day_schedules << day_sch
        end
      else
        # use all day schedules
        day_schedules << schedule_ruleset.defaultDaySchedule
        schedule_ruleset.scheduleRules.each { |rule| day_schedules << rule.daySchedule }
      end

      # get min and max from day schedules array
      min = nil
      max = nil
      day_schedules.each do |day_schedule|
        values = day_schedule.values
        values.each do |value|
          if min.nil?
            min = value
          else
            if min > value then min = value end
          end
          if max.nil?
            max = value
          else
            if max < value then max = value end
          end
        end
      end
      result = { 'min' => min, 'max' => max }

      return result
    end

    # Returns the ScheduleRuleset minimum and maximum values during the winter or summer design day.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param type [String] 'winter' for the winter design day, 'summer' for the summer design day
    # return [Hash] returns a hash with 'min' and 'max' values
    def self.schedule_ruleset_get_design_day_min_max(schedule_ruleset, type = 'winter')
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return nil
      end

      if type == 'winter'
        schedule = schedule_ruleset.winterDesignDaySchedule
      elsif type == 'summer'
        schedule = schedule_ruleset.summerDesignDaySchedule
      end

      if !schedule
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', "#{schedule_ruleset.name.get} is missing #{type} design day schedule, use default day schedule to process the min max search")
        schedule = schedule_ruleset.defaultDaySchedule
      end

      min = nil
      max = nil
      values = schedule.values
      values.each do |value|
        if min.nil?
          min = value
        else
          min = value if min > value
        end
        if max.nil?
          max = value
        else
          max = value if max < value
        end
      end
      result = { 'min' => min, 'max' => max }

      return result
    end

    # Returns SheduleRuleset equivalent full load hours (EFLH).
    # For example a fractional schedule of 0.5, 24/7, 365 would return a value of 4380.
    # This method includes leap days on leap years.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # return [Double] The total equivalent full load hours for this schedule
    def self.schedule_ruleset_get_equivalent_full_load_hours(schedule_ruleset)
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return nil
      end

      # define the start and end date
      year_start_date = nil
      year_end_date = nil
      if schedule_ruleset.model.yearDescription.is_initialized
        year_description = schedule_ruleset.model.yearDescription.get
        year = year_description.assumedYear
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', 'Year description is not specified. Full load hours calculation will assume 2009, the default year OS uses.')
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, 2009)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, 2009)
      end

      # Get the ordered list of all the day schedules
      day_schs = schedule_ruleset.getDaySchedules(year_start_date, year_end_date)

      # Get the array of which schedule is used on each day of the year
      day_schs_used_each_day = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)

      # Create a map that shows how many days each schedule is used
      day_sch_freq = day_schs_used_each_day.group_by { |n| n }

      # Build a hash that maps schedule day index to schedule day
      schedule_index_to_day = {}
      day_schs.each_with_index do |day_sch, i|
        schedule_index_to_day[day_schs_used_each_day[i]] = day_sch
      end

      # Loop through each of the schedules that is used, figure out the
      # full load hours for that day, then multiply this by the number
      # of days that day schedule applies and add this to the total.
      annual_flh = 0.0
      max_daily_flh = 0.0
      default_day_sch = schedule_ruleset.defaultDaySchedule
      day_sch_freq.each do |freq|
        sch_index = freq[0]
        number_of_days_sch_used = freq[1].size

        # Get the day schedule at this index
        day_sch = nil
        if sch_index == -1 # If index = -1, this day uses the default day schedule (not a rule)
          day_sch = default_day_sch
        else
          day_sch = schedule_index_to_day[sch_index]
        end
        daily_flh = OpenstudioStandards::Schedules.schedule_day_get_equivalent_full_load_hours(day_sch)

        # Multiply the daily EFLH by the number
        # of days this schedule is used per year
        # and add this to the overall total
        annual_flh += daily_flh * number_of_days_sch_used
      end

      # Warn if the max daily EFLH is more than 24,
      # which would indicate that this isn't a fractional schedule.
      if max_daily_flh > 24
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', "#{schedule_ruleset.name.get} has more than 24 EFLH in one day schedule, indicating that it is not a fractional schedule.")
      end

      return annual_flh
    end

    # Returns an array of average hourly values from a ScheduleRuleset object
    # Returns 8760 values, 8784 for leap years.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [Array<Double>] Array of hourly values for the year
    def self.schedule_ruleset_get_hourly_values(schedule_ruleset)
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return nil
      end

      model = schedule_ruleset.model

      # define the start and end date
      year_start_date = nil
      year_end_date = nil
      if model.yearDescription.is_initialized
        year_description = model.yearDescription.get
        year = year_description.assumedYear
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', 'Year description is not specified. Annual hours above value calculation will assume 2009, the default year OS uses.')
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, 2009)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, 2009)
      end

      # Get the ordered list of all the day schedules
      day_schs = schedule_ruleset.getDaySchedules(year_start_date, year_end_date)

      # Loop through each day schedule and add its hours to total
      # @todo store the 24 hourly average values for each day schedule instead of recalculating for all days
      annual_hourly_values = []
      day_schs.each do |day_sch|
        # add daily average hourly values to annual hourly values array
        daily_hours = OpenstudioStandards::Schedules.schedule_day_get_hourly_values(day_sch, model)
        annual_hourly_values += daily_hours
      end

      return annual_hourly_values
    end

    # Returns the total number of hours where the schedule is greater than the specified value.
    # This method includes leap days on leap years.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param lower_limit [Double] the lower limit.  Values equal to the limit will not be counted.
    # @return [Double] The total number of hours this schedule is above the specified value.
    def self.schedule_ruleset_get_hours_above_value(schedule_ruleset, lower_limit)
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return nil
      end

      # define the start and end date
      year_start_date = nil
      year_end_date = nil
      if schedule_ruleset.model.yearDescription.is_initialized
        year_description = schedule_ruleset.model.yearDescription.get
        year = year_description.assumedYear
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', 'Year description is not specified. Annual hours above value calculation will assume 2009, the default year OS uses.')
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, 2009)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, 2009)
      end

      # Get the ordered list of all the day schedules
      day_schs = schedule_ruleset.getDaySchedules(year_start_date, year_end_date)

      # Get the array of which schedule is used on each day of the year
      day_schs_used_each_day = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)

      # Create a map that shows how many days each schedule is used
      day_sch_freq = day_schs_used_each_day.group_by { |n| n }

      # Build a hash that maps schedule day index to schedule day
      schedule_index_to_day = {}
      day_schs.each_with_index do |day_sch, i|
        schedule_index_to_day[day_schs_used_each_day[i]] = day_sch
      end

      # Loop through each of the schedules that is used, figure out the
      # hours for that day, then multiply this by the number
      # of days that day schedule applies and add this to the total.
      annual_hrs = 0.0
      default_day_sch = schedule_ruleset.defaultDaySchedule
      day_sch_freq.each do |freq|
        sch_index = freq[0]
        number_of_days_sch_used = freq[1].size

        # Get the day schedule at this index
        day_sch = nil
        day_sch = if sch_index == -1 # If index = -1, this day uses the default day schedule (not a rule)
                    default_day_sch
                  else
                    schedule_index_to_day[sch_index]
                  end

        # Determine the hours for just one day
        daily_hrs = 0.0
        values = day_sch.values
        times = day_sch.times

        previous_time_decimal = 0.0
        times.each_with_index do |time, i|
          time_decimal = (time.days * 24.0) + time.hours + (time.minutes / 60.0) + (time.seconds / 3600.0)
          duration_of_value = time_decimal - previous_time_decimal
          if values[i] > lower_limit
            daily_hrs += duration_of_value
          end
          previous_time_decimal = time_decimal
        end

        # Multiply the daily hours by the number
        # of days this schedule is used per year
        # and add this to the overall total
        annual_hrs += daily_hrs * number_of_days_sch_used
      end

      return annual_hrs
    end

    # create OpenStudio TimeSeries object from ScheduleRuleset values
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [OpenStudio::TimeSeries] OpenStudio TimeSeries object of schedule values
    def self.schedule_ruleset_get_timeseries(schedule_ruleset)
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{method} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return nil
      end

      yd = schedule_ruleset.model.getYearDescription
      start_date = yd.makeDate(1, 1)
      end_date = yd.makeDate(12, 31)

      values = OpenStudio::DoubleVector.new
      day = OpenStudio::Time.new(1.0)
      interval = OpenStudio::Time.new(1.0 / 48.0)
      day_schedules = schedule_ruleset.getDaySchedules(start_date, end_date)
      day_schedules.each do |day_schedule|
        time = interval
        while time < day
          values << day_schedule.getValue(time)
          time += interval
        end
      end
      timeseries = OpenStudio::TimeSeries.new(start_date, interval, OpenStudio.createVector(values), '')
      return timeseries
    end

    # Determine the hour when the schedule first exceeds the starting value and when
    # it goes back down to the ending value at the end of the day.
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [Hash<OpenStudio:Time>] returns as hash with 'start_time', 'end time']
    def self.schedule_ruleset_get_start_and_end_times(schedule_ruleset)
      # validate schedule
      unless schedule_ruleset.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "#{__method__} failed because object #{schedule_ruleset.name.get} is not a ScheduleRuleset.")
        return [nil, nil]
      end

      # Define the start and end date
      if schedule_ruleset.model.yearDescription.is_initialized
        year_description = schedule_ruleset.model.yearDescription.get
        year = year_description.assumedYear
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      else
        year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, 2009)
        year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, 2009)
      end

      # Get the ordered list of all the day schedules that are used by this schedule ruleset
      day_schs = schedule_ruleset.getDaySchedules(year_start_date, year_end_date)

      # Get a 365-value array of which schedule is used on each day of the year,
      day_schs_used_each_day = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)

      # Create a map that shows how many days each schedule is used
      day_sch_freq = day_schs_used_each_day.group_by { |n| n }
      day_sch_freq = day_sch_freq.sort_by { |freq| freq[1].size }
      common_day_freq = day_sch_freq.last

      # Build a hash that maps schedule day index to schedule day
      schedule_index_to_day = {}
      day_schs.each_with_index do |day_sch, i|
        schedule_index_to_day[day_schs_used_each_day[i]] = day_sch
      end

      # Get the most common day schedule
      sch_index = common_day_freq[0]
      number_of_days_sch_used = common_day_freq[1].size

      # Get the day schedule at this index
      day_sch = if sch_index == -1 # If index = -1, this day uses the default day schedule (not a rule)
                  schedule_ruleset.defaultDaySchedule
                else
                  schedule_index_to_day[sch_index]
                end

      # Determine the full load hours for just one day
      values = []
      times = []
      day_sch.times.each_with_index do |time, i|
        times << day_sch.times[i]
        values << day_sch.values[i]
      end

      # Get the minimum value
      start_val = values.first
      end_val = values.last

      # Get the start time (first time value goes above minimum)
      start_time = nil
      values.each_with_index do |val, i|
        break if i == values.size - 1 # Stop if we reach end of array

        if val == start_val && values[i + 1] > start_val
          start_time = times[i]
          break
        end
      end

      # Get the end time (first time value goes back down to minimum)
      end_time = nil
      values.each_with_index do |val, i|
        if i < values.size - 1
          if val > end_val && values[i + 1] == end_val
            end_time = times[i]
            break
          end
        else
          if val > end_val && values[0] == start_val # Check first hour of day for schedules that end at midnight
            end_time = OpenStudio::Time.new(0, 24, 0, 0)
            break
          end
        end
      end

      return { 'start_time' => start_time, 'end_time' => end_time }
    end

    # Returns the day schedules associated with a schedule ruleset
    # Optionally includes summer and winter design days
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @param include_design_days [Bool] include summer and winter design day profiles
    #   Defaults to false
    # @return [Array<OpenStudio::Model::ScheduleDay>] array of day schedules
    def self.schedule_ruleset_get_day_schedules(schedule_ruleset, include_design_days: false)
      profiles = []
      profiles << schedule_ruleset.defaultDaySchedule
      schedule_ruleset.scheduleRules.each do |rule|
        profiles << rule.daySchedule
      end

      if include_design_days

        if schedule_ruleset.isSummerDesignDayScheduleDefaulted
          OpenStudio.logFree(OpenStudio::Warning, 'openstudio.standards.Schedules.Information', "#{__method__} called for #{schedule_ruleset.name.get} with include_design_days: true, but the summer design day is defaulted. Duplicate design day will not be added.")
        else
          profiles << rule.summerDesignDaySchedule
        end

        if schedule_ruleset.isWinterDesignDayScheduleDefaulted
          OpenStudio.logFree(OpenStudio::Warning, 'openstudio.standards.Schedules.Information', "#{__method__} called for #{schedule_ruleset.name.get} with include_design_days: true, but the winter design day is defaulted. Duplicate design day will not be added.")
        else
          profiles << rule.winterDesignDaySchedule
        end

      end

      return profiles
    end

    # Return the annual days of year that covered by each rule of a schedule ruleset
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [Hash] hash of rule_index => [days_used]. Default day has rule_index = -1
    def self.schedule_ruleset_get_annual_days_used(schedule_ruleset)
      year_description = schedule_ruleset.model.getYearDescription
      year = year_description.assumedYear
      year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
      year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      sch_indices_vector = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)
      days_used_hash = Hash.new { |h, k| h[k] = [] }
      sch_indices_vector.uniq.sort.each do |rule_i|
        sch_indices_vector.each_with_index { |rule, i| days_used_hash[rule_i] << (i + 1) if rule_i == rule }
      end
      return days_used_hash
    end

    # Returns the rule indices associated with defaultDay and Rule days for a given ScheduleRuleset
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [Hash] hash of ScheduleDay => rule index. Default day has rule index of -1
    def self.schedule_ruleset_get_schedule_day_rule_indices(schedule_ruleset)
      schedule_day_hash = {}
      schedule_day_hash[schedule_ruleset.defaultDaySchedule] = -1
      schedule_ruleset.scheduleRules.each { |rule| schedule_day_hash[rule.daySchedule] = rule.ruleIndex }
      return schedule_day_hash
    end

    # @!endgroup Information:ScheduleRuleset

    # @!group Information:Model

    # Get the predominant air loop HVAC schedule in the model by floor area served.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Schedule] OpenStudio Schedule object
    def self.model_get_hvac_schedule(model)
      # lookup from model, using largest air loop
      # check multiple kinds of systems, including unitary systems
      hvac_schedule = nil
      largest_area = 0.0

      model.getAirLoopHVACs.each do |air_loop|
        air_loop_area = 0.0
        air_loop.thermalZones.each { |tz| air_loop_area += tz.floorArea }
        if air_loop_area > largest_area
          hvac_schedule = air_loop.availabilitySchedule
          largest_area = air_loop_area
        end
      end

      model.getAirLoopHVACUnitarySystems.each do |unitary|
        next unless unitary.thermalZone.is_initialized

        air_loop_area = unitary.thermalZone.get.floorArea
        if air_loop_area > largest_area
          if unitary.availabilitySchedule.is_initialized
            hvac_schedule = unitary.availabilitySchedule.get
          else
            hvac_schedule = model.alwaysOnDiscreteSchedule
          end
          largest_area = air_loop_area
        end
      end

      model.getAirLoopHVACUnitaryHeatPumpAirToAirs.each do |unitary|
        next unless unitary.controllingZone.is_initialized

        air_loop_area = unitary.controllingZone.get.floorArea
        if air_loop_area > largest_area
          hvac_schedule = unitary.availabilitySchedule.get
          largest_area = air_loop_area
        end
      end

      model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.each do |unitary|
        next unless unitary.controllingZoneorThermostatLocation.is_initialized

        air_loop_area = unitary.controllingZoneorThermostatLocation.get.floorArea
        if air_loop_area > largest_area
          if unitary.availabilitySchedule.is_initialized
            hvac_schedule = unitary.availabilitySchedule.get
          else
            hvac_schedule = model.alwaysOnDiscreteSchedule
          end
          largest_area = air_loop_area
        end
      end

      model.getFanZoneExhausts.each do |fan|
        next unless fan.thermalZone.is_initialized

        air_loop_area = fan.thermalZone.get.floorArea
        if air_loop_area > largest_area
          if fan.availabilitySchedule.is_initialized
            hvac_schedule = fan.availabilitySchedule.get
          else
            hvac_schedule = model.alwaysOnDiscreteSchedule
          end
          largest_area = air_loop_area
        end
      end

      building_area = model.getBuilding.floorArea
      if largest_area < 0.05 * building_area
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules', "The largest airloop or HVAC system serves #{largest_area.round(1)} m^2, which is less than 5% of the building area #{building_area.round(1)} m^2. Attempting to use building hours of operation schedule instead.")
        default_schedule_set = model.getBuilding.defaultScheduleSet
        if default_schedule_set.is_initialized
          default_schedule_set = default_schedule_set.get
          hoo = default_schedule_set.hoursofOperationSchedule
          if hoo.is_initialized
            hvac_schedule = hoo.get
            largest_area = building_area
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules', 'Unable to determine building hours of operation schedule. Treating the building as if there is no HVAC system schedule.')
            hvac_schedule = nil
          end
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules', 'Unable to determine building hours of operation schedule. Treating the building as if there is no HVAC system schedule.')
          hvac_schedule = nil
        end
      end

      unless hvac_schedule.nil?
        area_fraction = 100.0 * largest_area / building_area
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules', "Using schedule #{hvac_schedule.name} serving area #{largest_area.round(1)} m^2, #{area_fraction.round(0)}% of building area #{building_area.round(1)} m^2 as the building HVAC operation schedule.")
      end

      return hvac_schedule
    end

    # @!endgroup Information:Model
  end
end
