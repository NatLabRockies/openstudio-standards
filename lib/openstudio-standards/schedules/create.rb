module OpenstudioStandards
  # The Schedules module provides methods to create, modify, and get information about Schedule objects
  module Schedules
    # @!group Create
    # Methods to create Schedule objects

    # create a ScheduleTypeLimits object for a schedule
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard_schedule_type_limit [String] the name of a standard schedule type limit with predefined limits
    #   options are Dimensionless, Temperature, Humidity Ratio, Fraction, Fractional, OnOff, and Activity
    # @param name [String] the name of the schedule type limits
    # @param lower_limit_value [double] the lower limit value for the schedule type
    # @param upper_limit_value [double] the upper limit value for the schedule type
    # @param numeric_type [String] the numeric type, options are Continuous or Discrete
    # @param unit_type [String] the unit type, options are defined in EnergyPlus I/O reference
    # @return [OpenStudio::Model::ScheduleTypeLimits] OpenStudio ScheduleTypeLimits object
    def self.create_schedule_type_limits(model,
                                         standard_schedule_type_limit: nil,
                                         name: nil,
                                         lower_limit_value: nil,
                                         upper_limit_value: nil,
                                         numeric_type: nil,
                                         unit_type: nil)

      if standard_schedule_type_limit.nil?
        if lower_limit_value.nil? || upper_limit_value.nil? || numeric_type.nil? || unit_type.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Create', 'If calling create_schedule_type_limits without a standard_schedule_type_limit, you must specify all properties of ScheduleTypeLimits.')
          return false
        end
        schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
        schedule_type_limits.setName(name) if !name.nil?
        schedule_type_limits.setLowerLimitValue(lower_limit_value)
        schedule_type_limits.setUpperLimitValue(upper_limit_value)
        schedule_type_limits.setNumericType(numeric_type)
        schedule_type_limits.setUnitType(unit_type)
      else
        schedule_type_limits = model.getScheduleTypeLimitsByName(standard_schedule_type_limit)
        if schedule_type_limits.empty?
          case standard_schedule_type_limit.downcase
          when 'dimensionless'
            schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            schedule_type_limits.setName('Dimensionless')
            schedule_type_limits.setLowerLimitValue(0.0)
            schedule_type_limits.setUpperLimitValue(1000.0)
            schedule_type_limits.setNumericType('Continuous')
            schedule_type_limits.setUnitType('Dimensionless')

          when 'temperature'
            schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            schedule_type_limits.setName('Temperature')
            schedule_type_limits.setLowerLimitValue(0.0)
            schedule_type_limits.setUpperLimitValue(100.0)
            schedule_type_limits.setNumericType('Continuous')
            schedule_type_limits.setUnitType('Temperature')

          when 'humidity ratio'
            schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            schedule_type_limits.setName('Humidity Ratio')
            schedule_type_limits.setLowerLimitValue(0.0)
            schedule_type_limits.setUpperLimitValue(0.3)
            schedule_type_limits.setNumericType('Continuous')
            schedule_type_limits.setUnitType('Dimensionless')

          when 'fraction', 'fractional'
            schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            schedule_type_limits.setName('Fraction')
            schedule_type_limits.setLowerLimitValue(0.0)
            schedule_type_limits.setUpperLimitValue(1.0)
            schedule_type_limits.setNumericType('Continuous')
            schedule_type_limits.setUnitType('Dimensionless')

          when 'onoff'
            schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            schedule_type_limits.setName('OnOff')
            schedule_type_limits.setLowerLimitValue(0)
            schedule_type_limits.setUpperLimitValue(1)
            schedule_type_limits.setNumericType('Discrete')
            schedule_type_limits.setUnitType('Availability')

          when 'activity'
            schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
            schedule_type_limits.setName('Activity')
            schedule_type_limits.setLowerLimitValue(70.0)
            schedule_type_limits.setUpperLimitValue(1000.0)
            schedule_type_limits.setNumericType('Continuous')
            schedule_type_limits.setUnitType('ActivityLevel')
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Create', 'Invalid standard_schedule_type_limit for method create_schedule_type_limits.')
            return false
          end
        else
          schedule_type_limits = schedule_type_limits.get
          if schedule_type_limits.name.to_s.downcase == 'temperature'
            schedule_type_limits.resetLowerLimitValue
            schedule_type_limits.resetUpperLimitValue
            schedule_type_limits.setNumericType('Continuous')
            schedule_type_limits.setUnitType('Temperature')
          end
        end
      end
      return schedule_type_limits
    end

    # Create constant ScheduleRuleset with a given value
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param value [Double] the value to use, 24-7, 365
    # @param name [String] the name of the schedule
    # @param schedule_type_limit [String] the name of a schedule type limit
    #   options are Dimensionless, Temperature, Humidity Ratio, Fraction, Fractional, OnOff, and Activity
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.create_constant_schedule_ruleset(model,
                                              value,
                                              name: nil,
                                              schedule_type_limit: nil)
      # check to see if schedule exists with same name and constant value and return if true
      unless name.nil?
        existing_sch = model.getScheduleRulesetByName(name)
        if existing_sch.is_initialized
          existing_sch = existing_sch.get
          existing_day_sch_vals = existing_sch.defaultDaySchedule.values
          if existing_day_sch_vals.size == 1 && (existing_day_sch_vals[0] - value).abs < 1.0e-6
            return existing_sch
          end
        end
      end

      # create ScheduleRuleset
      schedule = OpenStudio::Model::ScheduleRuleset.new(model)
      schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), value)

      # set name
      unless name.nil?
        schedule.setName(name)
        schedule.defaultDaySchedule.setName("#{name} Default")
      end

      # set schedule type limits
      if !schedule_type_limit.nil?
        sch_type_limits_obj = OpenstudioStandards::Schedules.create_schedule_type_limits(model,
                                                                                         standard_schedule_type_limit: schedule_type_limit)
        schedule.setScheduleTypeLimits(sch_type_limits_obj)
      end

      return schedule
    end

    # create a ruleset schedule with a basic profile
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param options [Hash] Hash of name and time value pairs
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.create_simple_schedule(model, options = {})
      defaults = {
        'name' => nil,
        'winter_time_value_pairs' => { 24.0 => 0.0 },
        'summer_time_value_pairs' => { 24.0 => 1.0 },
        'default_time_value_pairs' => { 24.0 => 1.0 }
      }

      # merge user inputs with defaults
      options = defaults.merge(options)

      # ScheduleRuleset
      sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      if name
        sch_ruleset.setName(options['name'])
      end

      # Winter Design Day
      sch_ruleset.setWinterDesignDaySchedule(sch_ruleset.winterDesignDaySchedule)
      winter_dsn_day = sch_ruleset.winterDesignDaySchedule
      winter_dsn_day.setName("#{sch_ruleset.name} Winter Design Day")
      options['winter_time_value_pairs'].each do |k, v|
        hour = k.truncate
        min = ((k - hour) * 60).to_i
        winter_dsn_day.addValue(OpenStudio::Time.new(0, hour, min, 0), v)
      end

      # Summer Design Day
      sch_ruleset.setSummerDesignDaySchedule(sch_ruleset.summerDesignDaySchedule)
      summer_dsn_day = sch_ruleset.summerDesignDaySchedule
      summer_dsn_day.setName("#{sch_ruleset.name} Summer Design Day")
      options['summer_time_value_pairs'].each do |k, v|
        hour = k.truncate
        min = ((k - hour) * 60).to_i
        summer_dsn_day.addValue(OpenStudio::Time.new(0, hour, min, 0), v)
      end

      # All Days
      default_day = sch_ruleset.defaultDaySchedule
      default_day.setName("#{sch_ruleset.name} Schedule Week Day")
      options['default_time_value_pairs'].each do |k, v|
        hour = k.truncate
        min = ((k - hour) * 60).to_i
        default_day.addValue(OpenStudio::Time.new(0, hour, min, 0), v)
      end

      return sch_ruleset
    end

    # create a ruleset schedule with a complex profile
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param options [Hash] Hash of name and time value pairs
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.create_complex_schedule(model, options = {})
      defaults = {
        'name' => nil,
        'default_day' => ['always_on', [24.0, 1.0]]
      }

      # merge user inputs with defaults
      options = defaults.merge(options)

      # ScheduleRuleset
      sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      if name
        sch_ruleset.setName(options['name'])
      end

      # Winter Design Day
      unless options['winter_design_day'].nil?
        sch_ruleset.setWinterDesignDaySchedule(sch_ruleset.winterDesignDaySchedule)
        winter_dsn_day = sch_ruleset.winterDesignDaySchedule
        winter_dsn_day.setName("#{sch_ruleset.name} Winter Design Day")
        options['winter_design_day'].each do |data_pair|
          hour = data_pair[0].truncate
          min = ((data_pair[0] - hour) * 60).to_i
          winter_dsn_day.addValue(OpenStudio::Time.new(0, hour, min, 0), data_pair[1])
        end
      end

      # Summer Design Day
      unless options['summer_design_day'].nil?
        sch_ruleset.setSummerDesignDaySchedule(sch_ruleset.summerDesignDaySchedule)
        summer_dsn_day = sch_ruleset.summerDesignDaySchedule
        summer_dsn_day.setName("#{sch_ruleset.name} Summer Design Day")
        options['summer_design_day'].each do |data_pair|
          hour = data_pair[0].truncate
          min = ((data_pair[0] - hour) * 60).to_i
          summer_dsn_day.addValue(OpenStudio::Time.new(0, hour, min, 0), data_pair[1])
        end
      end

      # Default Day
      default_day = sch_ruleset.defaultDaySchedule
      default_day.setName("#{sch_ruleset.name} #{options['default_day'][0]}")
      default_data_array = options['default_day']
      default_data_array.delete_at(0)
      default_data_array.each do |data_pair|
        hour = data_pair[0].truncate
        min = ((data_pair[0] - hour) * 60).round
        default_day.addValue(OpenStudio::Time.new(0, hour, min, 0), data_pair[1])
      end

      # Rules
      unless options['rules'].nil?
        options['rules'].each do |data_array|
          rule = OpenStudio::Model::ScheduleRule.new(sch_ruleset)
          rule.setName("#{sch_ruleset.name} #{data_array[0]} Rule")
          date_range = data_array[1].split('-')
          start_date = date_range[0].split('/')
          end_date = date_range[1].split('/')
          rule.setStartDate(model.getYearDescription.makeDate(start_date[0].to_i, start_date[1].to_i))
          rule.setEndDate(model.getYearDescription.makeDate(end_date[0].to_i, end_date[1].to_i))
          days = data_array[2].split('/')
          rule.setApplySunday(true) if days.include? 'Sun'
          rule.setApplyMonday(true) if days.include? 'Mon'
          rule.setApplyTuesday(true) if days.include? 'Tue'
          rule.setApplyWednesday(true) if days.include? 'Wed'
          rule.setApplyThursday(true) if days.include? 'Thu'
          rule.setApplyFriday(true) if days.include? 'Fri'
          rule.setApplySaturday(true) if days.include? 'Sat'
          rule.setApplyWeekdays(true) if days.include? 'Wkdy'
          rule.setApplyWeekends(true) if days.include? 'Wknd'
          day_schedule = rule.daySchedule
          day_schedule.setName("#{sch_ruleset.name} #{data_array[0]}")
          data_array.delete_at(0)
          data_array.delete_at(0)
          data_array.delete_at(0)
          data_array.each do |data_pair|
            hour = data_pair[0].truncate
            min = ((data_pair[0] - hour) * 60).to_i
            day_schedule.addValue(OpenStudio::Time.new(0, hour, min, 0), data_pair[1])
          end
        end
      end

      return sch_ruleset
    end

    # create a new schedule using absolute velocity of existing schedule
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    # @todo fix velocity so it isn't fraction change per step, but per hour
    #   (I need to count hours between times and divide value by this)
    def self.create_schedule_from_rate_of_change(model, schedule_ruleset)
      # clone source schedule
      new_schedule = schedule_ruleset.clone(model)
      new_schedule.setName("#{schedule_ruleset.name} - Rate of Change")
      new_schedule = new_schedule.to_ScheduleRuleset.get

      # create array of all profiles to change. This includes summer, winter, default, and rules
      profiles = []
      profiles << new_schedule.winterDesignDaySchedule
      profiles << new_schedule.summerDesignDaySchedule
      profiles << new_schedule.defaultDaySchedule

      # time values may need
      end_profile_time = OpenStudio::Time.new(0, 24, 0, 0)
      hour_bump_time = OpenStudio::Time.new(0, 1, 0, 0)
      one_hour_left_time = OpenStudio::Time.new(0, 23, 0, 0)

      rules = new_schedule.scheduleRules
      rules.each do |rule|
        profiles << rule.daySchedule
      end

      profiles.uniq.each do |profile|
        times = profile.times
        values = profile.values

        i = 0
        values_intermediate = []
        times_intermediate = []
        until i == values.size
          if i == 0
            values_intermediate << 0.0
            if times[i] > hour_bump_time
              times_intermediate << (times[i] - hour_bump_time)
              if times[i + 1].nil?
                time_step_value = end_profile_time.hours + (end_profile_time.minutes / 60) - times[i].hours - (times[i].minutes / 60)
              else
                time_step_value = times[i + 1].hours + (times[i + 1].minutes / 60) - times[i].hours - (times[i].minutes / 60)
              end
              values_intermediate << ((values[i + 1].to_f - values[i].to_f).abs / (time_step_value * 2))
            end
            times_intermediate << times[i]
          elsif i == (values.size - 1)
            if times[times.size - 2] < one_hour_left_time
              times_intermediate << (times[times.size - 2] + hour_bump_time) # this should be the second to last time
              time_step_value = times[i - 1].hours + (times[i - 1].minutes / 60) - times[i - 2].hours - (times[i - 2].minutes / 60)
              values_intermediate << ((values[i - 1].to_f - values[i - 2].to_f).abs / (time_step_value * 2))
            end
            values_intermediate << 0.0
            times_intermediate << times[i] # this should be the last time
          else
            # get value multiplier based on how many hours it is spread over
            time_step_value = times[i].hours + (times[i].minutes / 60) - times[i - 1].hours - (times[i - 1].minutes / 60)
            values_intermediate << ((values[i].to_f - values[i - 1].to_f).abs / time_step_value)
            times_intermediate << times[i]
          end
          i += 1
        end

        # delete all profile values
        profile.clearValues

        i = 0
        until i == times_intermediate.size
          if i == (times_intermediate.size - 1)
            profile.addValue(times_intermediate[i], values_intermediate[i].to_f)
          else
            profile.addValue(times_intermediate[i], values_intermediate[i].to_f)
          end
          i += 1
        end
      end

      return new_schedule
    end

    # merge multiple schedules into one using load or other value to weight each schedules influence on the merge
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param schedule_weights_hash [Hash] Hash of OpenStudio::Model::ScheduleRuleset, Double
    # @param sch_name [String] Optional name of new schedule
    # @return [Hash] Hash of merged schedule and the total denominator
    # @todo apply weights to schedule rules as well, not just winter, summer, and default profile
    def self.create_weighted_merge_schedules(model, schedule_weights_hash, sch_name: 'Merged Schedule')
      # get denominator for weight
      denominator = 0.0
      schedule_weights_hash.each do |schedule, weight|
        denominator += weight
      end

      # create new schedule
      sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      sch_ruleset.setName(sch_name)

      # create winter design day profile - from the ruleset's own getter, as in
      # create_simple_schedule, so no parentless day schedule is left behind by the clone
      sch_ruleset.setWinterDesignDaySchedule(sch_ruleset.winterDesignDaySchedule)
      winter_dsn_day = sch_ruleset.winterDesignDaySchedule
      winter_dsn_day.clearValues
      winter_dsn_day.setName("#{sch_ruleset.name} Winter Design Day")

      # create  summer design day profile
      sch_ruleset.setSummerDesignDaySchedule(sch_ruleset.summerDesignDaySchedule)
      summer_dsn_day = sch_ruleset.summerDesignDaySchedule
      summer_dsn_day.clearValues
      summer_dsn_day.setName("#{sch_ruleset.name} Summer Design Day")

      # create default profile
      default_day = sch_ruleset.defaultDaySchedule
      default_day.setName("#{sch_ruleset.name} Schedule Week Day")

      # hash of schedule rules
      rules_hash = {} # mon, tue, wed, thur, fri, sat, sun, startDate, endDate
      # to avoid stacking order issues across schedules, I may need to make a rule for each day of the week for each date range

      schedule_weights_hash.each do |schedule, weight|
        # populate winter design day profile
        old_winter_profile = schedule.to_ScheduleRuleset.get.winterDesignDaySchedule
        times_final = summer_dsn_day.times
        i = 0
        value_updated_array = []
        # loop through times already in profile and update values
        until i > times_final.size - 1
          value = old_winter_profile.getValue(times_final[i]) * weight / denominator
          starting_value = winter_dsn_day.getValue(times_final[i])
          winter_dsn_day.addValue(times_final[i], value + starting_value)
          value_updated_array << times_final[i]
          i += 1
        end
        # loop through any new times unique to the current old profile to be merged
        j = 0
        times = old_winter_profile.times
        values = old_winter_profile.values
        until j > times.size - 1
          unless value_updated_array.include? times[j]
            value = values[j] * weight / denominator
            starting_value = winter_dsn_day.getValue(times[j])
            winter_dsn_day.addValue(times[j], value + starting_value)
          end
          j += 1
        end

        # populate summer design day profile
        old_summer_profile = schedule.to_ScheduleRuleset.get.summerDesignDaySchedule
        times_final = summer_dsn_day.times
        i = 0
        value_updated_array = []
        # loop through times already in profile and update values
        until i > times_final.size - 1
          value = old_summer_profile.getValue(times_final[i]) * weight / denominator
          starting_value = summer_dsn_day.getValue(times_final[i])
          summer_dsn_day.addValue(times_final[i], value + starting_value)
          value_updated_array << times_final[i]
          i += 1
        end
        # loop through any new times unique to the current old profile to be merged
        j = 0
        times = old_summer_profile.times
        values = old_summer_profile.values
        until j > times.size - 1
          unless value_updated_array.include? times[j]
            value = values[j] * weight / denominator
            starting_value = summer_dsn_day.getValue(times[j])
            summer_dsn_day.addValue(times[j], value + starting_value)
          end
          j += 1
        end

        # populate default profile
        old_default_profile = schedule.to_ScheduleRuleset.get.defaultDaySchedule
        times_final = default_day.times
        i = 0
        value_updated_array = []
        # loop through times already in profile and update values
        until i > times_final.size - 1
          value = old_default_profile.getValue(times_final[i]) * weight / denominator
          starting_value = default_day.getValue(times_final[i])
          default_day.addValue(times_final[i], value + starting_value)
          value_updated_array << times_final[i]
          i += 1
        end
        # loop through any new times unique to the current old profile to be merged
        j = 0
        times = old_default_profile.times
        values = old_default_profile.values
        until j > times.size - 1
          unless value_updated_array.include? times[j]
            value = values[j] * weight / denominator
            starting_value = default_day.getValue(times[j])
            default_day.addValue(times[j], value + starting_value)
          end
          j += 1
        end

        # create rules

        # gather data for rule profiles

        # populate rule profiles
      end

      result = { 'mergedSchedule' => sch_ruleset, 'denominator' => denominator }
      return result
    end

    # Create a ScheduleDay from another ScheduleDay with inverted values
    #
    # @param old_schedule_day [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object to invert
    # @param new_schedule_day [OpenStudio::Model::ScheduleDay] An OpenStudio ScheduleDay object.
    #   Default nil. If provided, will add values to this ScheduleDay object instead of creating a new one.
    # @param schedule_name [String] Optional name of new schedule
    # @return [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object of inverted schedule
    def self.create_inverted_schedule_day(old_schedule_day, new_schedule_day: nil, schedule_name: nil)
      # create new schedule object if none provided
      if new_schedule_day.nil?
        new_schedule_day = OpenStudio::Model::ScheduleDay.new(old_schedule_day.model)
      end

      # set default name if none provided
      if schedule_name.nil?
        new_schedule_day.setName("#{old_schedule_day.name} inverted")
      else
        new_schedule_day.setName(schedule_name)
      end

      # invert schedule values
      for index in 0..old_schedule_day.times.size - 1
        old_value = old_schedule_day.values[index]
        if old_value == 0
          new_value = 1
        else
          new_value = 0
        end
        new_schedule_day.addValue(old_schedule_day.times[index], new_value)
      end

      return new_schedule_day
    end

    # Create a ScheduleRuleset from another ScheduleRuleset with inverted values
    #
    # @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object to invert
    # @param schedule_name [String] Optional name of new schedule
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object of inverted schedule
    def self.create_inverted_schedule_ruleset(schedule_ruleset, schedule_name: nil)
      model = schedule_ruleset.model
      new_schedule = OpenStudio::Model::ScheduleRuleset.new(model, 0.0)

      # set default name if none provided
      if schedule_name.nil?
        new_schedule.setName("#{schedule_ruleset.name} inverted")
      else
        new_schedule.setName(schedule_name)
      end

      # The design day setters CLONE the day schedule they are handed, so a day schedule
      # built first and handed over is left in the model with no parent once the clone
      # becomes the real child - and orphaned day schedules reach the IDF with no schedule
      # type limits. As in create_simple_schedule: set the design day from the ruleset's
      # own getter, take the clone back, and fill that.
      # change summer design day
      new_schedule.setSummerDesignDaySchedule(new_schedule.summerDesignDaySchedule)
      new_summer_dd_schedule = new_schedule.summerDesignDaySchedule
      new_summer_dd_schedule.clearValues
      OpenstudioStandards::Schedules.create_inverted_schedule_day(schedule_ruleset.summerDesignDaySchedule,
                                                                  new_schedule_day: new_summer_dd_schedule)

      # change winter design day
      new_schedule.setWinterDesignDaySchedule(new_schedule.winterDesignDaySchedule)
      new_winter_dd_schedule = new_schedule.winterDesignDaySchedule
      new_winter_dd_schedule.clearValues
      OpenstudioStandards::Schedules.create_inverted_schedule_day(schedule_ruleset.winterDesignDaySchedule,
                                                                  new_schedule_day: new_winter_dd_schedule)

      # change the default day values
      OpenstudioStandards::Schedules.create_inverted_schedule_day(schedule_ruleset.defaultDaySchedule,
                                                                  new_schedule_day: new_schedule.defaultDaySchedule)

      # change for schedule rules: a rule made on the ruleset owns its day schedule from the
      # start, so fill that rather than handing the constructor one to clone
      schedule_ruleset.scheduleRules.each_with_index do |rule, i|
        old_schedule_day = rule.daySchedule
        new_rule = OpenStudio::Model::ScheduleRule.new(new_schedule)
        new_schedule_day = OpenstudioStandards::Schedules.create_inverted_schedule_day(old_schedule_day,
                                                                                       new_schedule_day: new_rule.daySchedule)
        new_rule.setName("#{new_schedule_day.name} Rule")
        new_rule.setApplySunday(rule.applySunday)
        new_rule.setApplyMonday(rule.applyMonday)
        new_rule.setApplyTuesday(rule.applyTuesday)
        new_rule.setApplyWednesday(rule.applyWednesday)
        new_rule.setApplyThursday(rule.applyThursday)
        new_rule.setApplyFriday(rule.applyFriday)
        new_rule.setApplySaturday(rule.applySaturday)
      end

      return new_schedule
    end

    # @!endgroup Create
  end
end
