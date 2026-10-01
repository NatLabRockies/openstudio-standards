require_relative '../../helpers/minitest_helper'

# Tests for how a profile's base and peak are resolved and how control points are anchored
# to them: the 'range' anchor, the base-to-peak ratio form, and the weekday/weekend split.
class TestScheduleBasePeak < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  # A resolved base and peak are products of the inputs, so compare them with a tolerance
  # rather than for equality: 0.2 * 0.8 is not 0.16 in binary floating point.
  def assert_base_peak(expected, actual, message = nil)
    assert_equal(expected.size, actual.size, message)
    expected.zip(actual).each { |want, got| assert_in_delta(want, got, 1e-9, message) }
  end

  # A profile whose interior points sit at known fractions of the base-to-peak span.
  def range_profile(base: 0.1, peak: 0.9)
    {
      name: 'range profile',
      day_types: 'Default',
      category: 'Occupancy',
      type: 'parametric',
      base_std: base,
      peak_std: peak,
      st_std: 8.0,
      et_std: 18.0,
      control_points: [['st-1', 'base'], ['st', 'range*0.25'], ['st+2', 'peak'],
                       ['et-1', 'range*0.75'], ['et', 'base']]
    }
  end

  # -------------------------------------------------------------------------
  # Control point anchoring

  def test_evaluate_control_point_value_anchors
    # endpoints, with and without a scale factor
    assert_in_delta(0.1, @sch.evaluate_control_point_value('base', 0.1, 0.9), 1e-9)
    assert_in_delta(0.9, @sch.evaluate_control_point_value('peak', 0.1, 0.9), 1e-9)
    assert_in_delta(0.45, @sch.evaluate_control_point_value('peak*0.5', 0.1, 0.9), 1e-9)
    assert_in_delta(0.05, @sch.evaluate_control_point_value('base*0.5', 0.1, 0.9), 1e-9)

    # 'range*f' is f of the way from base to peak
    assert_in_delta(0.1, @sch.evaluate_control_point_value('range*0.0', 0.1, 0.9), 1e-9)
    assert_in_delta(0.5, @sch.evaluate_control_point_value('range*0.5', 0.1, 0.9), 1e-9)
    assert_in_delta(0.9, @sch.evaluate_control_point_value('range*1.0', 0.1, 0.9), 1e-9)
    assert_in_delta(0.9, @sch.evaluate_control_point_value('range', 0.1, 0.9), 1e-9)

    # values are held inside 0..1
    assert_in_delta(1.0, @sch.evaluate_control_point_value('peak', 0.0, 1.5), 1e-9)
  end

  # The reason the shipped data was re-anchored: an endpoint anchor pins its point to one
  # end and leaves it there when the other end moves, so raising the base flattens the
  # profile against its own shoulders instead of lifting it.
  def test_range_anchor_follows_the_base_where_peak_anchor_does_not
    peak_anchored = @sch.evaluate_control_point_value('peak*0.25', 0.5, 0.9)
    range_anchored = @sch.evaluate_control_point_value('range*0.25', 0.5, 0.9)

    assert_in_delta(0.225, peak_anchored, 1e-9)
    assert_in_delta(0.6, range_anchored, 1e-9)
    assert(range_anchored > 0.5, 'a range-anchored interior point stays above the base')
  end

  # -------------------------------------------------------------------------
  # Resolving base and peak

  def test_resolve_base_and_peak_precedence
    std = [0.1, 0.8]

    assert_base_peak([0.1, 0.8], @sch.resolve_base_and_peak({}, *std))
    assert_base_peak([0.25, 0.8], @sch.resolve_base_and_peak({ base: 0.25 }, *std))
    assert_base_peak([0.1, 0.6], @sch.resolve_base_and_peak({ peak: 0.6 }, *std))

    # a ratio is taken against the resolved peak, not the authored one
    assert_base_peak([0.4, 0.8], @sch.resolve_base_and_peak({ base_peak_ratio: 0.5 }, *std))
    assert_base_peak([0.3, 0.6], @sch.resolve_base_and_peak({ base_peak_ratio: 0.5, peak: 0.6 }, *std))

    # an absolute base is a more specific statement than a ratio, so it wins
    assert_base_peak([0.25, 0.8], @sch.resolve_base_and_peak({ base: 0.25, base_peak_ratio: 0.9 }, *std))
  end

  def test_resolve_base_and_peak_weekend_split
    std = [0.1, 0.8]
    params = { base_peak_ratio: 0.5, wknd_base_peak_ratio: 0.25 }

    assert_base_peak([0.4, 0.8], @sch.resolve_base_and_peak(params, *std))
    assert_base_peak([0.2, 0.8], @sch.resolve_base_and_peak(params, *std, weekend: true))

    # weekends follow weekdays when the caller speaks only of the building as a whole
    weekday_only = { base_peak_ratio: 0.5 }
    assert_base_peak(@sch.resolve_base_and_peak(weekday_only, *std),
                     @sch.resolve_base_and_peak(weekday_only, *std, weekend: true))

    # a weekend override with no weekday counterpart leaves weekdays on the authored values
    weekend_only = { wknd_base_peak_ratio: 0.25 }
    assert_base_peak([0.1, 0.8], @sch.resolve_base_and_peak(weekend_only, *std))
    assert_base_peak([0.2, 0.8], @sch.resolve_base_and_peak(weekend_only, *std, weekend: true))
  end

  # Sampling the two ratios independently can put the weekend above the weekday. A caller
  # that does not want a higher unoccupied load at the weekend than on a weekday says so.
  def test_resolve_base_and_peak_weekend_cap
    std = [0.1, 0.8]
    params = { base_peak_ratio: 0.2, wknd_base_peak_ratio: 0.9, cap_wknd_base_at_wkdy: true }

    assert_base_peak([0.16, 0.8], @sch.resolve_base_and_peak(params, *std))
    assert_base_peak([0.16, 0.8], @sch.resolve_base_and_peak(params, *std, weekend: true))

    # a weekend below the weekday is left alone
    lower = { base_peak_ratio: 0.9, wknd_base_peak_ratio: 0.2, cap_wknd_base_at_wkdy: true }
    assert_base_peak([0.16, 0.8], @sch.resolve_base_and_peak(lower, *std, weekend: true))

    # the cap compares resolved values, not ratios, since the peaks can differ
    differing_peaks = { base_peak_ratio: 0.5, wknd_base_peak_ratio: 0.9,
                        wknd_peak: 0.3, cap_wknd_base_at_wkdy: true }
    assert_base_peak([0.27, 0.3], @sch.resolve_base_and_peak(differing_peaks, *std, weekend: true))

    # and it is off unless asked for
    uncapped = { base_peak_ratio: 0.2, wknd_base_peak_ratio: 0.9 }
    assert_base_peak([0.72, 0.8], @sch.resolve_base_and_peak(uncapped, *std, weekend: true))
  end

  # A profile that holds one value all day has no span to restate, and moving its base
  # would turn a deliberately flat profile into a shaped one.
  def test_ratio_skips_flat_profiles
    assert_base_peak([0.6, 0.6], @sch.resolve_base_and_peak({ base_peak_ratio: 0.2 }, 0.6, 0.6))

    # an explicit base is a direct instruction and still applies
    assert_base_peak([0.2, 0.6], @sch.resolve_base_and_peak({ base: 0.2 }, 0.6, 0.6))
  end

  # -------------------------------------------------------------------------
  # Expansion

  def test_expansion_applies_the_ratio
    profile = range_profile
    stock = @sch.evaluate_schedule_control_points(profile, profile[:base_std], profile[:peak_std], 8.0, 18.0, 4)
    assert_in_delta(0.1, stock.map { |_, value| value }.min, 1e-9)

    base, peak = @sch.resolve_base_and_peak({ base_peak_ratio: 0.5 }, profile[:base_std], profile[:peak_std])
    raised = @sch.evaluate_schedule_control_points(profile, base, peak, 8.0, 18.0, 4)
    assert_in_delta(0.45, raised.map { |_, value| value }.min, 1e-9)
    assert_in_delta(profile[:peak_std], raised.map { |_, value| value }.max, 1e-9)
  end

  # A base-to-peak ratio has to reproduce, exactly, the linear remap that the ComStock BPR
  # measures applied to a finished schedule: new = ((peak - value) * sf) + value, with
  # sf = (new_base - base) / (peak - base). Range anchoring is that remap expressed as
  # data, which is what lets the measures be replaced by an override.
  def test_ratio_matches_the_linear_remap
    profile = range_profile
    base = profile[:base_std]
    peak = profile[:peak_std]
    stock = @sch.evaluate_schedule_control_points(profile, base, peak, 8.0, 18.0, 4)

    [0.0, 0.25, 0.5, 0.95].each do |ratio|
      new_base = ratio * peak
      scale = (new_base - base) / (peak - base)
      overridden = @sch.evaluate_schedule_control_points(profile, new_base, peak, 8.0, 18.0, 4)

      stock.zip(overridden).each do |(_, stock_value), (_, override_value)|
        remapped = (((peak - stock_value) * scale) + stock_value).clamp(0, 1)
        assert_in_delta(remapped, override_value, 1e-9,
                        "ratio #{ratio} diverges from the linear remap at #{stock_value}")
      end
    end
  end

  # A design day is a peak-condition sizing assumption, not a statement about how a space
  # runs, so a ratio describing unoccupied hours has nothing to say about it. Without this
  # a winter design day authored flat at zero is lifted, which changes heating sizing.
  def test_ratio_leaves_design_days_alone
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    profiles = @sch.schedule_data(:interior_lighting)
                   .select { |row| row[:name] == 'corridor lighting' && row[:control_points] }
    refute(profiles.empty?)

    stock = @sch.create_parametric_schedule_full(model, profiles, 'corridor lighting', {}, category: 'Lighting')
    ratio = @sch.create_parametric_schedule_full(model, profiles, 'corridor lighting',
                                                 { base_peak_ratio: 0.1 }, category: 'Lighting')

    assert_in_delta(0.0, stock.winterDesignDaySchedule.values.max, 1e-6)
    assert_in_delta(0.0, ratio.winterDesignDaySchedule.values.max, 1e-6, 'a ratio must not lift a design day')
    assert_equal(stock.summerDesignDaySchedule.values, ratio.summerDesignDaySchedule.values)

    # the operating day does move, which is the point
    refute_in_delta(stock.defaultDaySchedule.values.min, ratio.defaultDaySchedule.values.min, 1e-6)

    # an explicit base is a direct instruction and reaches the design days
    absolute = @sch.create_parametric_schedule_full(model, profiles, 'corridor lighting',
                                                    { base: 0.2 }, category: 'Lighting')
    assert_in_delta(0.2, absolute.winterDesignDaySchedule.values.max, 1e-6)
  end

  # A weekend rule that applies to no day is indistinguishable from no rule at all: the
  # weekday profile then runs all seven days and the weekend setback never happens.
  # create_complex_schedule splits its day-type field on '/', so 'Sat|Sun' matches nothing.
  def test_thermostat_schedule_weekend_rule_applies_to_the_weekend
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    schedule = OpenstudioStandards::ThermalZone.create_thermostat_schedule(
      model, name: 'Htg test', setpoint: 21.0, setback_delta: 5.0, heating: true,
             hours: { wkdy_start: 8.0, wkdy_end: 18.0, wknd_start: 10.0, wknd_end: 14.0 }
    )

    rules = schedule.scheduleRules
    assert_equal(1, rules.size)
    rule = rules.first
    assert(rule.applySaturday, 'the weekend rule must apply on Saturday')
    assert(rule.applySunday, 'the weekend rule must apply on Sunday')
    refute(rule.applyMonday, 'the weekend rule must not apply on a weekday')
    refute(rule.applyFriday, 'the weekend rule must not apply on a weekday')

    # and it has to be a different profile from the weekday one, or it buys nothing.
    # Compare times, not values: both profiles step between the same setpoint and setback,
    # so only the hours at which they do it differ.
    weekday_times = schedule.defaultDaySchedule.times.map(&:totalHours)
    weekend_times = rule.daySchedule.times.map(&:totalHours)
    refute_equal(weekday_times, weekend_times)
    assert_in_delta(10.0, weekend_times.first, 0.01, 'the weekend profile should turn up at its own start hour')
  end

  # The shipped data must expand to what it did before its control points were re-anchored.
  # These are the values 'corridor lighting' produced when its interior points were still
  # authored as 'peak*k'; every one of them was a peak anchor, which is why raising the
  # base used to do nothing to this profile at all.
  def test_shipped_profile_expansion_is_unchanged_by_reanchoring
    data = OpenstudioStandards::Schedules.schedule_data(:interior_lighting)
    profile = data.find { |row| row[:name] == 'corridor lighting' && row[:day_types] == 'Default' }
    refute_nil(profile)

    pairs = @sch.evaluate_schedule_control_points(profile, profile[:base_std], profile[:peak_std],
                                                  profile[:st_std], profile[:et_std], 4)
    expected = [0.1228, 0.1399, 0.2298, 0.5963, 0.6567, 0.6035, 0.1235, 0.1228]
    assert_equal(expected.size, pairs.size)
    pairs.map { |_, value| value }.zip(expected).each do |actual, want|
      assert_in_delta(want, actual, 1e-4)
    end

    # and the profile now responds to its base, which is the point of the re-anchoring
    raised = @sch.evaluate_schedule_control_points(profile, 0.3 * profile[:peak_std], profile[:peak_std],
                                                  profile[:st_std], profile[:et_std], 4)
    assert_in_delta(0.197, raised.map { |_, value| value }.min, 1e-3)
  end
end
