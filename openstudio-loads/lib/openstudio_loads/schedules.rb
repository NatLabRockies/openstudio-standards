require 'date'

module OpenStudioLoads
  # The NECB schedule builder — exact port of the legacy model_add_schedule /
  # model_add_vals_to_sch semantics against the vendored schedules table:
  # one ScheduleRuleset per name; per data row the day_types tokens map to the
  # default day (Default), winter/summer design days (WntrDsn/SmrDsn), and dated
  # ScheduleRules (Wkdy/Wknd/Sat/Sun/Mon..Fri); Hourly rows add a value at each
  # hour boundary where the value CHANGES (values are MIDNIGHT-FIRST, values[0] =
  # the hour ending 01:00... applied as until-(i+1):00); Constant rows a single
  # until-24:00 value.
  #
  # DELIBERATE DEVIATION: legacy silently returns alwaysOnDiscreteSchedule for an
  # unknown name — this builder WARNS in the audit (never silent) and then returns
  # the same fallback, preserving downstream behavior.
  module Schedules
    DAY_TOKENS = %w[Wkdy Wknd Mon Tue Wed Thu Fri Sat Sun].freeze

    module_function

    # @param name [String] e.g. 'NECB-A-Occupancy'
    # @return [OpenStudio::Model::Schedule] the ruleset (or the always-on fallback)
    def add(model, name, vintage: '2020', audit: nil)
      return nil if name.nil? || name.to_s.empty?

      existing = model.getSchedules.sort_by(&:nameString).find { |s| s.nameString == name }
      return existing if existing

      rows = NECB.table(vintage, 'schedules').select { |r| r['name'] == name }
      if rows.empty?
        audit&.warn(:schedules, "no NECB #{vintage} schedule data named '#{name}' — falling back to Always On " \
                                '(legacy fails silently here)',
                    target: name)
        return model.alwaysOnDiscreteSchedule
      end

      ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
      ruleset.setName(name)
      rows.each { |row| apply_row(model, ruleset, name, row) }
      audit&.info(:schedules, 'NECB schedule built', target: name,
                  inputs: { rows: rows.size, type: rows.first['type'] })
      ruleset
    end

    def apply_row(model, ruleset, name, row)
      day_types = row['day_types'].to_s

      if day_types.include?('Default')
        day = ruleset.defaultDaySchedule
        day.setName("#{name} Default")
        add_values(day, row)
      end
      if day_types.include?('WntrDsn')
        day = OpenStudio::Model::ScheduleDay.new(model)
        ruleset.setWinterDesignDaySchedule(day)
        day = ruleset.winterDesignDaySchedule
        day.setName("#{name} Winter Design Day")
        add_values(day, row)
      end
      if day_types.include?('SmrDsn')
        day = OpenStudio::Model::ScheduleDay.new(model)
        ruleset.setSummerDesignDaySchedule(day)
        day = ruleset.summerDesignDaySchedule
        day.setName("#{name} Summer Design Day")
        add_values(day, row)
      end
      return unless DAY_TOKENS.any? { |token| day_types.include?(token) }

      rule = OpenStudio::Model::ScheduleRule.new(ruleset)
      day = rule.daySchedule
      day.setName("#{name} #{day_types} Day")
      add_values(day, row)
      start_date = Date.parse(row['start_date'])
      end_date = Date.parse(row['end_date'])
      rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(start_date.month), start_date.day))
      rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(end_date.month), end_date.day))
      if day_types.include?('Wknd')
        rule.setApplySaturday(true)
        rule.setApplySunday(true)
      end
      if day_types.include?('Wkdy')
        %w[Monday Tuesday Wednesday Thursday Friday].each { |d| rule.send("setApply#{d}", true) }
      end
      { 'Mon' => 'Monday', 'Tue' => 'Tuesday', 'Wed' => 'Wednesday', 'Thu' => 'Thursday',
        'Fri' => 'Friday', 'Sat' => 'Saturday', 'Sun' => 'Sunday' }.each do |token, method|
        rule.send("setApply#{method}", true) if day_types.include?(token)
      end
    end

    def add_values(day_schedule, row)
      values = row['values']
      case row['type']
      when 'Constant'
        day_schedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), values[0].to_f)
      when 'Hourly'
        24.times do |i|
          next if values[i] == values[i + 1] # last hour always added (values[24] is nil)

          day_schedule.addValue(OpenStudio::Time.new(0, i + 1, 0, 0), values[i].to_f)
        end
      else
        raise(ArgumentError, "unknown schedule row type '#{row['type']}' (Constant|Hourly)")
      end
      day_schedule.setInterpolatetoTimestep(interpolate_off(day_schedule))
    end

    def interpolate_off(day_schedule)
      day_schedule.model.version < OpenStudio::VersionString.new('3.8.0') ? false : 'No'
    end
  end
end
