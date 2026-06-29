require_relative '../../helpers/minitest_helper'

# Tests for cross-day spillover with day-type correctness: a profile that runs
# past midnight into a different day type produces a day-specific boundary rule rather
# than polluting every day of the type.
class TestScheduleSpillover < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  # A residential-style schedule: weekday occupancy runs overnight (16:00 -> 09:00 next
  # day, spilling into Saturday), weekend occupancy is a daytime profile.
  def residential_profiles
    common = {
      category: 'Occupancy', type: 'parametric',
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      base_std: 0.1, peak_std: 1.0
    }
    wkdy = common.merge(name: 'res', day_types: 'Wkdy', st_std: 16.0, et_std: 33.0,
                        control_points: [['st', 'base'], ['st+1', 'peak'], ['et-1', 'peak'], ['et', 'base']])
    wknd = common.merge(name: 'res', day_types: 'Wknd', st_std: 8.0, et_std: 18.0,
                        control_points: [['st', 'base'], ['st+1', 'peak'], ['et-1', 'peak'], ['et', 'base']])
    [wkdy, wknd]
  end

  def hourly(day_sch)
    @sch.schedule_day_get_hourly_values(day_sch)
  end

  def test_spillover_creates_saturday_boundary_rule
    rs = @sch.create_parametric_schedule_full(new_model, residential_profiles, 'res', {}).to_ScheduleRuleset.get

    # rules: Wkdy (Mon-Fri), Wknd (Sat+Sun), and a Saturday-only boundary rule
    sat_only = rs.scheduleRules.select { |r| r.applySaturday && !r.applySunday && !r.applyMonday && !r.applyFriday }
    assert_equal 1, sat_only.size, 'expected exactly one Saturday-only boundary rule'

    boundary = sat_only.first
    wknd_rule = rs.scheduleRules.find { |r| r.applySaturday && r.applySunday }
    refute_nil wknd_rule, 'expected the weekend rule to remain'

    boundary_vals = hourly(boundary.daySchedule)
    wknd_vals = hourly(wknd_rule.daySchedule)

    # the boundary day carries the overnight spillover in the early hours...
    assert_operator boundary_vals[0, 6].max, :>, 0.5, 'Saturday boundary rule should carry overnight occupancy'
    # ...while the untouched weekend profile stays near its morning base
    assert_operator wknd_vals[0, 6].max, :<, 0.3, 'weekend (Sunday) morning should be unchanged'
  end

  def test_saturday_boundary_rule_has_priority
    rs = @sch.create_parametric_schedule_full(new_model, residential_profiles, 'res', {}).to_ScheduleRuleset.get

    # the first (highest priority) rule applying to Saturday must be the Saturday-only
    # boundary rule, so Saturdays resolve to the combined profile and Sundays do not
    first_sat_rule = rs.scheduleRules.find(&:applySaturday)
    refute_nil first_sat_rule
    refute first_sat_rule.applySunday, 'the highest-priority Saturday rule should be the boundary (Saturday-only) rule'
  end

  def test_no_spillover_no_extra_rule
    # a profile entirely within the day produces no boundary rule
    profiles = [{
      name: 'daytime', day_types: 'Wkdy', category: 'Occupancy', type: 'parametric',
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      base_std: 0.0, peak_std: 1.0, st_std: 8.0, et_std: 17.0,
      control_points: [['st', 'base'], ['st+1', 'peak'], ['et-1', 'peak'], ['et', 'base']]
    }]
    rs = @sch.create_parametric_schedule_full(new_model, profiles, 'daytime', {}).to_ScheduleRuleset.get
    assert_equal 1, rs.scheduleRules.size, 'no spillover should mean a single weekday rule'
  end
end
