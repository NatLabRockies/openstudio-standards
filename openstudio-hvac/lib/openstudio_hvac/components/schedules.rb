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
  end
end
