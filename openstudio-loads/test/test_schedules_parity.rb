require_relative 'test_helper'

# P2 gate (parity half): EVERY schedule name in the vendored 2020 table builds
# identically via the gem and via legacy model_add_schedule — default day values,
# design days, rule day-of-week flags and dates. Runs under the repo bundle.
class TestSchedulesParity < Minitest::Test
  include FixtureHelper

  def self.legacy
    @legacy ||= begin
      require File.expand_path('../../lib/openstudio-standards', __dir__)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy
    skip 'openstudio-standards not loadable — parity gate runs from the monorepo' if std == :unavailable
    std
  end

  def day_values(day_schedule)
    (1..24).map { |hour| day_schedule.getValue(OpenStudio::Time.new(0, hour, 0, 0)).round(6) }
  end

  def rule_signature(rule)
    { days: %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].map { |d| rule.send("apply#{d}") },
      values: day_values(rule.daySchedule),
      start: rule.startDate.is_initialized ? rule.startDate.get.to_s : nil,
      end: rule.endDate.is_initialized ? rule.endDate.get.to_s : nil }
  end

  def ruleset_signature(schedule)
    ruleset = schedule.to_ScheduleRuleset
    return { fallback: schedule.nameString } if ruleset.empty?

    ruleset = ruleset.get
    { default: day_values(ruleset.defaultDaySchedule),
      winter: ruleset.isWinterDesignDayScheduleDefaulted ? nil : day_values(ruleset.winterDesignDaySchedule),
      summer: ruleset.isSummerDesignDayScheduleDefaulted ? nil : day_values(ruleset.summerDesignDaySchedule),
      rules: ruleset.scheduleRules.map { |r| rule_signature(r) }
                    .sort_by { |s| s[:days].map { |b| b ? 1 : 0 }.join } }
  end

  def test_all_schedules_parity
    std = legacy
    names = OpenStudioLoads::NECB.table('2020', 'schedules').map { |r| r['name'] }.uniq
    mismatches = []

    names.each do |name|
      gem_model = OpenStudio::Model::Model.new
      legacy_model = OpenStudio::Model::Model.new
      gem_schedule = OpenStudioLoads::Schedules.add(gem_model, name)
      legacy_schedule = std.model_add_schedule(legacy_model, name)

      gem_signature = ruleset_signature(gem_schedule)
      legacy_signature = ruleset_signature(legacy_schedule)
      mismatches << name unless gem_signature == legacy_signature
    end

    assert_operator names.size, :>=, 85, 'the full catalog was compared (86 unique names over 240 rows)'
    assert_empty mismatches, "schedule parity mismatches: #{mismatches.first(10).inspect}"
  end
end
