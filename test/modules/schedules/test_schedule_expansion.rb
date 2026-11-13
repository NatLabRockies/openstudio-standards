require_relative '../../helpers/minitest_helper'

# Tests for the parametric schedule expanders (control-point and slope), explicit
# expander selection via the `expansion` field, and the pluggable interpolation easing.
class TestScheduleExpansion < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
    @schedule_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/test_schedules_data.json"), symbolize_names: true)
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  # A profile carrying BOTH control points and slopes so the `expansion` field
  # decides which expander runs.
  def dual_profile(expansion: nil)
    obj = {
      name: 'dual profile',
      day_types: 'Default|SmrDsn|Wkdy',
      start_date: '2018-01-01T00:00:00+00:00',
      end_date: '2018-12-31T00:00:00+00:00',
      category: 'Occupancy',
      type: 'parametric',
      base_std: 0.0,
      peak_std: 0.9,
      st_std: 8.0,
      et_std: 19.0,
      start_slope: 0.8,
      end_slope: 0.5,
      control_points: [['st-1', 'base'], ['st+2', 'peak'], ['et-2', 'peak'], ['et', 'base']]
    }
    obj[:expansion] = expansion unless expansion.nil?
    [obj]
  end

  # -------------------------------------------------------------------------
  # Ruleset structure: default day, design days, rule day-types and dates
  # -------------------------------------------------------------------------

  def assert_full_ruleset(sched)
    refute_nil sched
    assert sched.to_ScheduleRuleset.is_initialized
    rs = sched.to_ScheduleRuleset.get

    # default day populated
    assert_operator rs.defaultDaySchedule.values.size, :>, 0, 'default day schedule is empty'

    # summer design day populated (day_types includes SmrDsn)
    assert_operator rs.summerDesignDaySchedule.values.size, :>, 0, 'summer design day schedule is empty'

    # exactly one weekday rule, applying Mon-Fri, dated for the full year
    assert_equal 1, rs.scheduleRules.size, 'expected a single Wkdy rule'
    rule = rs.scheduleRules.first
    assert rule.applyMonday && rule.applyTuesday && rule.applyWednesday && rule.applyThursday && rule.applyFriday,
           'weekday rule should apply Mon-Fri'
    refute rule.applySaturday, 'weekday rule should not apply Saturday'
    refute rule.applySunday, 'weekday rule should not apply Sunday'
    assert rule.startDate.is_initialized && rule.endDate.is_initialized, 'rule dates should be set'
    assert_equal 1, rule.startDate.get.monthOfYear.value
    assert_equal 1, rule.startDate.get.dayOfMonth
    assert_equal 12, rule.endDate.get.monthOfYear.value
    assert_equal 31, rule.endDate.get.dayOfMonth
    rs
  end

  def test_control_point_expander_builds_full_ruleset
    model = new_model
    sched = @sch.create_parametric_schedule_full(model, @schedule_data, 'conference occupancy', {})
    rs = assert_full_ruleset(sched)
    # peak of a [0, 0.9] occupancy control-point profile should approach peak_std
    assert_operator rs.defaultDaySchedule.values.max, :>, 0.8
  end

  def test_slope_expander_builds_full_ruleset
    model = new_model
    sched = @sch.create_parametric_schedule_full(model, @schedule_data, 'slope occupancy', {})
    assert_full_ruleset(sched)
  end

  # -------------------------------------------------------------------------
  # Explicit expander selection via the `expansion` field
  # -------------------------------------------------------------------------

  def default_day_values(model, schedule_array)
    sched = @sch.create_parametric_schedule_full(model, schedule_array, 'dual profile', {})
    sched.to_ScheduleRuleset.get.defaultDaySchedule.values
  end

  def test_expansion_field_selects_expander
    inferred = default_day_values(new_model, dual_profile)                              # both slopes present -> slope
    forced_slope = default_day_values(new_model, dual_profile(expansion: 'slope'))
    forced_cp = default_day_values(new_model, dual_profile(expansion: 'control_points'))

    # explicit 'slope' reproduces the legacy inference exactly
    assert_equal forced_slope, inferred, 'expansion: slope should match inferred slope behavior'

    # forcing control points yields a different profile than the slope expander
    refute_equal forced_cp, forced_slope, 'expansion: control_points should differ from slope expansion'
  end

  def test_slope_expansion_without_slopes_logs_and_skips
    obj = dual_profile(expansion: 'slope').first
    obj.delete(:start_slope)
    obj.delete(:end_slope)
    sched = @sch.create_parametric_schedule_full(new_model, [obj], 'dual profile', {})
    # the profile is skipped (logged error), so only the trivial fallback default day
    # remains - no expanded multi-point profile and no weekday rule
    assert sched.to_ScheduleRuleset.is_initialized
    rs = sched.to_ScheduleRuleset.get
    assert_operator rs.defaultDaySchedule.values.size, :<=, 1
    assert_equal 0, rs.scheduleRules.size
  end

  # -------------------------------------------------------------------------
  # Category-aware lookup (generalized name + category keying)
  # -------------------------------------------------------------------------

  def test_lookup_matches_name_and_category
    base = {
      day_types: 'Default', start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      type: 'parametric', base_std: 0.0, st_std: 8.0, et_std: 19.0,
      control_points: [['st', 'base'], ['st+2', 'peak'], ['et', 'base']]
    }
    occ = base.merge(name: 'shared name', category: 'Occupancy', peak_std: 0.9)
    light = base.merge(name: 'shared name', category: 'Lighting', peak_std: 0.4)
    array = [occ, light]

    occ_sched = @sch.create_parametric_schedule_full(new_model, array, 'shared name', {}, category: 'Occupancy')
    light_sched = @sch.create_parametric_schedule_full(new_model, array, 'shared name', {}, category: 'Lighting')

    assert_in_delta 0.9, occ_sched.to_ScheduleRuleset.get.defaultDaySchedule.values.max, 0.05
    assert_in_delta 0.4, light_sched.to_ScheduleRuleset.get.defaultDaySchedule.values.max, 0.05
  end

  def test_lookup_missing_category_returns_nil
    array = [{ name: 'only occ', category: 'Occupancy', day_types: 'Default',
               start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
               type: 'parametric', base_std: 0.0, peak_std: 0.9, st_std: 8.0, et_std: 19.0,
               control_points: [['st', 'base'], ['et', 'base']] }]
    assert_nil @sch.create_parametric_schedule_full(new_model, array, 'only occ', {}, category: 'Lighting')
  end

  # -------------------------------------------------------------------------
  # Pluggable interpolation easing
  # -------------------------------------------------------------------------

  def test_smootherstep_delegates_to_easing
    [0.0, 0.25, 0.5, 0.75, 1.0].each do |x|
      assert_in_delta @sch.smootherstep_easing(x), @sch.smootherstep(0.0, 1.0, x), 1e-12
    end
    # smootherstep is symmetric: x = 0.5 -> 0.5
    assert_in_delta 0.5, @sch.smootherstep_easing(0.5), 1e-12
  end

  def test_easing_is_swappable
    pairs = [[6.0, 0.0], [12.0, 1.0]]
    default = @sch.smooth_schedule_from_time_values(pairs.map(&:dup), 4)
    explicit = @sch.smooth_schedule_from_time_values(pairs.map(&:dup), 4, easing: @sch.method(:smootherstep_easing))
    linear = @sch.smooth_schedule_from_time_values(pairs.map(&:dup), 4, easing: ->(x) { x })

    # default easing == smootherstep easing
    assert_equal default.map { |t, v| [t, v.round(9)] }, explicit.map { |t, v| [t, v.round(9)] }

    # a different easing family produces a different ramp
    refute_equal default.map { |_, v| v.round(6) }, linear.map { |_, v| v.round(6) }
  end
end
