class Standard
  # @!group ScheduleRuleset

  # Return Array of weekday values from Array of all day values
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param values [Array] hourly time-series values of all days
  # @param value_includes_holiday [Boolean] whether the input values include a day of holiday at the end of the array
  #
  # @return [Array] hourly time-series values in weekdays
  #
  def get_weekday_values_from_8760(model, values, value_includes_holiday = true)
    start_day = model.getYearDescription.dayofWeekforStartDay
    start_day_map = {
      'Sunday' => 0,
      'Monday' => 1,
      'Tuesday' => 2,
      'Wednesday' => 3,
      'Thursday' => 4,
      'Friday' => 5,
      'Saturday' => 6
    }
    start_day_num = start_day_map[start_day]
    weekday_values = []
    day_of_week = start_day_num
    num_of_days = values.size / 24
    if value_includes_holiday
      num_of_days -= 1
    end

    for day_i in 1..num_of_days do
      if day_of_week >= 1 && day_of_week <= 5
        weekday_values += values.slice!(0, 24)
      end
      day_of_week += 1
      # reset day of week
      if day_of_week == 7
        day_of_week = 0
      end
    end

    return weekday_values
  end

  # Create a ScheduleRuleset object from an 8760 sequential array of values for a
  # Values array will actually include 24 extra values if model year is a leap year
  # Values array will also include 24 values at end of array representing the holiday day schedule
  # @author Doug Maddox, PNNL
  # @param model [Object]
  # @param values [Array<Double>] array of annual values (8760 +/ 24) + holiday values (24)
  # @param sch_name [String] name of schedule to be created
  # @param sch_type_limits [Object] ScheduleTypeLimits object
  # @return [Object] ScheduleRuleset
  def make_ruleset_sched_from_8760(model, values, sch_name, sch_type_limits)
    # Build array of arrays: each top element is a week, each sub element is an hour of week
    all_week_values = []
    hr_of_yr = -1
    (0..51).each do |iweek|
      week_values = []
      (0..167).each do |hr_of_wk|
        hr_of_yr += 1
        week_values[hr_of_wk] = values[hr_of_yr]
      end
      all_week_values << week_values
    end

    # Extra week for days 365 and 366 (if applicable) of year
    # since 52 weeks is 364 days
    hr_of_yr += 1
    last_hr = values.size - 1
    iweek = 52
    week_values = []
    hr_of_wk = -1
    (hr_of_yr..last_hr).each do |ihr_of_yr|
      hr_of_wk += 1
      week_values[hr_of_wk] = values[ihr_of_yr]
    end
    all_week_values << week_values

    # Build ruleset schedules for first week
    yd = model.getYearDescription
    start_date = yd.makeDate(1, 1)
    one_day = OpenStudio::Time.new(1.0)
    seven_days = OpenStudio::Time.new(7.0)
    end_date = start_date + seven_days - one_day

    # Create new ruleset schedule
    sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
    sch_ruleset.setName(sch_name)
    sch_ruleset.setScheduleTypeLimits(sch_type_limits)

    # Make week schedule for first week
    num_week_scheds = 1
    week_sch_name = "#{sch_name}_ws#{num_week_scheds}"
    week_1_rules = make_week_ruleset_sched_from_168(model, sch_ruleset, all_week_values[1], start_date, end_date, week_sch_name)
    week_n_rules = week_1_rules
    all_week_rules = []
    all_week_rules << week_1_rules
    iweek_previous_week_rule = 0

    # temporary loop for debugging
    week_n_rules.each do |sch_rule|
      day_rule = sch_rule.daySchedule
      xtest = 1
    end

    # For each subsequent week, check if it is same as previous
    # If same, then append to Schedule:Rule of previous week
    # If different, then create new Schedule:Rule
    (1..51).each do |iweek|
      is_a_match = true
      start_date = end_date + one_day
      end_date += seven_days
      (0..167).each do |ihr|
        if all_week_values[iweek][ihr] != all_week_values[iweek_previous_week_rule][ihr]
          is_a_match = false
          break
        end
      end
      if is_a_match
        # Update the end date for the Rules of the previous week to include this week
        all_week_rules[iweek_previous_week_rule].each do |sch_rule|
          sch_rule.setEndDate(end_date)
        end
      else
        # Create a new week schedule for this week
        num_week_scheds += 1
        week_sch_name = sch_name + '_ws' + num_week_scheds.to_s
        week_n_rules = make_week_ruleset_sched_from_168(model, sch_ruleset, all_week_values[iweek], start_date, end_date, week_sch_name)
        all_week_rules << week_n_rules
        # Set this week as the reference for subsequent weeks
        iweek_previous_week_rule = iweek
      end
    end

    # temporary loop for debugging
    week_n_rules.each do |sch_rule|
      day_rule = sch_rule.daySchedule
      xtest = 1
    end

    # Need to handle week 52 with days 365 and 366
    # For each of these days, check if it matches a day from the previous week
    iweek = 52
    # First handle day 365
    end_date += one_day
    start_date = end_date
    match_was_found = false
    # week_n is the previous week
    week_n_rules.each do |sch_rule|
      day_rule = sch_rule.daySchedule
      is_match = true
      # Need a 24 hour array of values for the day rule
      ihr_start = 0
      day_values = []
      day_rule.times.each do |time|
        now_value = day_rule.getValue(time).to_f
        until_ihr = time.totalHours.to_i - 1
        (ihr_start..until_ihr).each do |ihr|
          day_values << now_value
        end
      end
      (0..23).each do |ihr|
        if day_values[ihr] != all_week_values[iweek][ihr + ihr_start]
          # not matching for this day_rule
          is_match = false
          break
        end
      end
      if is_match
        match_was_found = true
        # Extend the schedule period to include this day
        sch_rule.setEndDate(end_date)
        break
      end
    end
    if match_was_found == false
      # Need to add a new rule
      day_of_week = start_date.dayOfWeek.valueName
      day_names = [day_of_week]
      day_sch_name = "#{sch_name}_Day_365"
      day_sch_values = []
      (0..23).each do |ihr|
        day_sch_values << all_week_values[iweek][ihr]
      end
      # sch_rule is a sub-component of the ScheduleRuleset
      sch_rule = OpenstudioStandards::Schedules.schedule_ruleset_add_rule(sch_ruleset, day_sch_values,
                                                                          start_date: start_date,
                                                                          end_date: end_date,
                                                                          day_names: day_names,
                                                                          rule_name: day_sch_name)
      week_n_rules = sch_rule
    end

    # Handle day 366, if leap year
    # Last day in this week is the holiday schedule
    # If there are three days in this week, then the second is day 366
    if all_week_values[iweek].size == 24 * 3
      ihr_start = 23
      end_date += one_day
      start_date = end_date
      match_was_found = false
      # week_n is the previous week
      # which would be the week based on day 356, if that was its own week
      week_n_rules.each do |sch_rule|
        day_rule = sch_rule.daySchedule
        is_match = true
        day_rule.times.each do |ihr|
          if day_rule.getValue(ihr).to_f != all_week_values[iweek][ihr + ihr_start]
            # not matching for this day_rule
            is_match = false
            break
          end
        end
        if is_match
          match_was_found = true
          # Extend the schedule period to include this day
          sch_rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(end_date.month.to_i), end_date.day.to_i))
          break
        end
      end
      if match_was_found == false
        # Need to add a new rule
        # sch_rule is a sub-component of the ScheduleRuleset

        day_of_week = start_date.dayOfWeek.valueName
        day_names = [day_of_week]
        day_sch_name = "#{sch_name}_Day_366"
        day_sch_values = []
        (0..23).each do |ihr|
          day_sch_values << all_week_values[iweek][ihr]
        end
        sch_rule = OpenstudioStandards::Schedules.schedule_ruleset_add_rule(sch_ruleset, day_sch_values,
                                                                            start_date: start_date,
                                                                            end_date: end_date,
                                                                            day_names: day_names,
                                                                            rule_name: day_sch_name)
        week_n_rules = sch_rule
      end

      # Last day in values array is the holiday schedule
      # @todo add holiday schedule when implemented in OpenStudio SDK
    end

    # Need to handle design days
    # Find schedule with the most operating hours in a day,
    # and apply that to both cooling and heating design days
    hr_of_yr = -1
    max_eflh = 0
    ihr_max = -1
    (0..364).each do |iday|
      eflh = 0
      ihr_start = hr_of_yr + 1
      (0..23).each do |ihr|
        hr_of_yr += 1
        eflh += 1 if values[hr_of_yr] > 0
      end
      if eflh > max_eflh
        max_eflh = eflh
        # store index to first hour of day with max on hours
        ihr_max = ihr_start
      end
    end
    # Create the schedules for the design days
    day_sch = OpenStudio::Model::ScheduleDay.new(model)
    day_sch.setName("#{sch_name} Winter Design Day")
    (0..23).each do |ihr|
      hr_of_yr = ihr_max + ihr
      next if values[hr_of_yr] == values[hr_of_yr + 1]

      day_sch.addValue(OpenStudio::Time.new(0, ihr + 1, 0, 0), values[hr_of_yr])
    end
    sch_ruleset.setWinterDesignDaySchedule(day_sch)

    day_sch = OpenStudio::Model::ScheduleDay.new(model)
    day_sch.setName("#{sch_name} Summer Design Day")
    (0..23).each do |ihr|
      hr_of_yr = ihr_max + ihr
      next if values[hr_of_yr] == values[hr_of_yr + 1]

      day_sch.addValue(OpenStudio::Time.new(0, ihr + 1, 0, 0), values[hr_of_yr])
    end
    sch_ruleset.setSummerDesignDaySchedule(day_sch)

    return sch_ruleset
  end

  # Create a ScheduleRules object from an hourly array of values for a week
  # @author Doug Maddox, PNNL
  # @param model [Object]
  # @param sch_ruleset [Object] ScheduleRuleset object
  # @param values [Array<Double>] array of hourly values for week (168)
  # @param start_date [Date] start date of week period
  # @param end_date [Date] end date of week period
  # @param sch_name [String] name of parent ScheduleRuleset object
  # @return [Array<Object>] array of ScheduleRules objects
  def make_week_ruleset_sched_from_168(model, sch_ruleset, values, start_date, end_date, sch_name)
    one_day = OpenStudio::Time.new(1.0)
    now_date = start_date - one_day
    days_of_week = []
    values_by_day = []
    # Organize data into days
    # create a 2-D array values_by_day[iday][ihr]
    hr_of_wk = -1
    (0..6).each do |iday|
      hr_values = []
      (0..23).each do |hr_of_day|
        hr_of_wk += 1
        hr_values << values[hr_of_wk]
      end
      values_by_day << hr_values
      now_date += one_day
      days_of_week << now_date.dayOfWeek.valueName
    end

    # Make list of unique day schedules
    # First one is automatically unique
    # Store indexes to days with the same sched in array of arrays
    # day_sched_idays[0] << 0
    day_sched = {}
    day_sched['day_idx_list'] = [0]
    day_sched['hr_values'] = values_by_day[0]
    day_scheds = []
    day_scheds << day_sched

    # Check each day with the cumulative list of day_scheds and add new, if unique
    (1..6).each do |iday|
      match_was_found = false
      day_scheds.each do |day_sched|
        # Compare each jday to the current iday and check for a match
        is_a_match = true
        (0..23).each do |ihr|
          if day_sched['hr_values'][ihr] != values_by_day[iday][ihr]
            # this hour is not a match
            is_a_match = false
            break
          end
        end
        if is_a_match
          # Add the day index to the list for this day_sched
          day_sched['day_idx_list'] << iday
          match_was_found = true
          break
        end
      end
      if match_was_found == false
        # Add a new day type
        day_sched = {}
        day_sched['day_idx_list'] = [iday]
        day_sched['hr_values'] = values_by_day[iday]
        day_scheds << day_sched
      end
    end

    # Add the Rule and Day objects
    sch_rules = []
    iday_sch = 0
    day_scheds.each do |day_sched|
      iday_sch += 1

      day_names = []
      day_sched['day_idx_list'].each do |idx|
        day_names << days_of_week[idx]
      end
      day_sch_name = "#{sch_name} Day #{iday_sch}"
      day_sch_values = day_sched['hr_values']
      sch_rule = OpenstudioStandards::Schedules.schedule_ruleset_add_rule(sch_ruleset, day_sch_values,
                                                                          start_date: start_date,
                                                                          end_date: end_date,
                                                                          day_names: day_names,
                                                                          rule_name: day_sch_name)
      sch_rules << sch_rule
    end

    return sch_rules
  end
end
