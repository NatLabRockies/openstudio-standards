module OpenStudioHVAC
  # Minimal SDK-only schedule helpers.
  module Schedules
    # Constant-value ruleset schedule (24h default day).
    #
    # @param model [OpenStudio::Model::Model]
    # @param name [String]
    # @param value [Numeric]
    # @return [OpenStudio::Model::ScheduleRuleset]
    def self.constant_ruleset(model, name, value)
      existing = model.getScheduleRulesets.find { |s| s.nameString == name }
      return existing unless existing.nil?

      sch = OpenStudio::Model::ScheduleRuleset.new(model)
      sch.setName(name)
      sch.defaultDaySchedule.setName("#{name} Default")
      sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), value)
      sch
    end

    # Always-off on/off schedule (0 all year).
    #
    # @param model [OpenStudio::Model::Model]
    # @return [OpenStudio::Model::ScheduleRuleset]
    def self.always_off(model)
      constant_ruleset(model, 'Always Off', 0)
    end

    # Two-pipe fan-coil seasonal availability schedules: heating Jan-Jun + Nov-Dec,
    # cooling Jul-Oct (port of NECB create_heating_cooling_on_off_availability_schedule).
    #
    # @param model [OpenStudio::Model::Model]
    # @return [Array(ScheduleRuleset, ScheduleRuleset)] [cooling_availability, heating_availability]
    def self.seasonal_availability(model)
      existing_clg = model.getScheduleRulesets.find { |s| s.nameString == 'tpfc_clg_availability' }
      existing_htg = model.getScheduleRulesets.find { |s| s.nameString == 'tpfc_htg_availability' }
      return [existing_clg, existing_htg] if existing_clg && existing_htg

      seasons = [
        { start_month: 1, start_day: 1, end_month: 6, end_day: 30, htg: 1, clg: 0 },
        { start_month: 7, start_day: 1, end_month: 10, end_day: 31, htg: 0, clg: 1 },
        { start_month: 11, start_day: 1, end_month: 12, end_day: 31, htg: 1, clg: 0 }
      ]

      build = lambda do |name, key|
        sch = OpenStudio::Model::ScheduleRuleset.new(model)
        sch.setName(name)
        seasons.each do |season|
          rule = OpenStudio::Model::ScheduleRule.new(sch)
          rule.setName("#{name}_sch_rule")
          rule.setStartDate(model.getYearDescription.makeDate(season[:start_month], season[:start_day]))
          rule.setEndDate(model.getYearDescription.makeDate(season[:end_month], season[:end_day]))
          %i[setApplySunday setApplyMonday setApplyTuesday setApplyWednesday
             setApplyThursday setApplyFriday setApplySaturday].each { |m| rule.send(m, true) }
          day = rule.daySchedule
          day.setName("#{name}_sch_rule_day")
          day.addValue(OpenStudio::Time.new(0, 24, 0, 0), season[key])
        end
        sch
      end

      [build.call('tpfc_clg_availability', :clg), build.call('tpfc_htg_availability', :htg)]
    end
  end
end
