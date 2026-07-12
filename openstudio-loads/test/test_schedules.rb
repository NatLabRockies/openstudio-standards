require_relative 'test_helper'

# P2 gate (standalone half): the schedule builder produces correct rulesets from
# the vendored data — day values, design days, rule day-of-week flags, memoization,
# loud unknown-name fallback.
class TestSchedules < Minitest::Test
  include FixtureHelper

  def hourly_values(day_schedule)
    (1..24).map do |hour|
      day_schedule.getValue(OpenStudio::Time.new(0, hour, 0, 0))
    end
  end

  def test_hourly_ruleset_day_values
    model = OpenStudio::Model::Model.new
    schedule = OpenStudioLoads::Schedules.add(model, 'NECB-A-Occupancy')
    ruleset = schedule.to_ScheduleRuleset.get
    expected = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.7, 0.9, 0.9, 0.9, 0.5, 0.5,
                0.9, 0.9, 0.9, 0.7, 0.3, 0.1, 0.1, 0.1, 0.1, 0.0]
    assert_equal expected, hourly_values(ruleset.defaultDaySchedule)

    saturday_rule = ruleset.scheduleRules.find(&:applySaturday)
    refute_nil saturday_rule
    assert_equal [0.0] * 24, hourly_values(saturday_rule.daySchedule)
  end

  def test_design_days_and_setpoints
    model = OpenStudio::Model::Model.new
    heating = OpenStudioLoads::Schedules.add(model, 'NECB-A-Thermostat Setpoint-Heating')
                                        .to_ScheduleRuleset.get
    default = hourly_values(heating.defaultDaySchedule)
    assert_equal [18.0] * 6 + [20.0] + [22.0] * 14 + [18.0] * 3, default

    # design-day schedules exist when the data carries WntrDsn/SmrDsn rows
    rows = OpenStudioLoads::NECB.table('2020', 'schedules').select { |r| r['name'] == 'NECB-A-Thermostat Setpoint-Heating' }
    if rows.any? { |r| r['day_types'].to_s.include?('WntrDsn') }
      refute heating.winterDesignDaySchedule.values.empty?
    end
  end

  def test_memoized_and_activity_constant
    model = OpenStudio::Model::Model.new
    first = OpenStudioLoads::Schedules.add(model, 'NECB-Activity')
    again = OpenStudioLoads::Schedules.add(model, 'NECB-Activity')
    assert_equal first.handle, again.handle, 'same object returned on repeat'
    count = model.getScheduleRulesets.count { |s| s.nameString == 'NECB-Activity' }
    assert_equal 1, count
  end

  def test_unknown_name_warns_never_silent
    model = OpenStudio::Model::Model.new
    audit = OpenStudioLoads::AuditLog.new
    schedule = OpenStudioLoads::Schedules.add(model, 'NECB-Z-Nonsense', audit: audit)
    assert_equal model.alwaysOnDiscreteSchedule.handle, schedule.handle
    warning = audit.warnings.find { |w| w[:action].include?("'NECB-Z-Nonsense'") }
    refute_nil warning, 'unknown schedule warns (legacy is silent here)'
  end

  def test_every_vendored_schedule_builds
    model = OpenStudio::Model::Model.new
    audit = OpenStudioLoads::AuditLog.new
    names = OpenStudioLoads::NECB.table('2020', 'schedules').map { |r| r['name'] }.uniq
    names.each do |name|
      schedule = OpenStudioLoads::Schedules.add(model, name, audit: audit)
      refute_nil schedule, name
    end
    assert_equal 0, audit.warnings.size, 'no fallbacks while building the full catalog'
    assert_operator model.getScheduleRulesets.size, :>=, names.size - 1 # 'Always On' may alias
  end
end
