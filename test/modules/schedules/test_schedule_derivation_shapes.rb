require_relative '../../helpers/minitest_helper'

# Shape-level tests for `derive_values`, exercised as pure arithmetic without SDK objects.
#
# Covers the derivation types added so their shapes can be evaluated by hand in the schedule
# editor - `logistic`, `saturating`, `first_order`, plus the universal `lag_hours` modifier -
# and the start/end time inference that `up_down` depends on.
#
# None of the shipped data uses the new types yet - nothing was refitted onto them - so those
# tests guard the implementation rather than any particular schedule.
class TestScheduleDerivationShapes < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  # A plain daytime presence: flat overnight, ramp 6-9, hold to 17, down by 19.
  def presence_pairs
    (0...24).map do |hour|
      value = if hour < 6 then 0.0
              elsif hour < 9 then (hour - 6) / 3.0
              elsif hour < 17 then 1.0
              elsif hour < 19 then 1.0 - ((hour - 17) / 2.0)
              else 0.0
              end
      [hour + 1.0, value]
    end
  end

  def derive(type, **opts)
    @sch.derive_values(type, 0.0, 1.0, 1.0, presence_pairs,
                       timesteps_per_hour: 1, occupancy_base: 0.0, occupancy_peak: 1.0, **opts)
  end

  def values(pairs)
    pairs.map { |_, value| value }
  end

  def test_existing_types_are_unchanged_without_new_parameters
    # The new keywords all default to nil, so a call that does not pass them must behave
    # exactly as it did before they existed.
    %w[linear exponential exponential-inverse].each do |type|
      before = values(@sch.derive_values(type, 0.05, 0.9, 0.75, presence_pairs,
                                         timesteps_per_hour: 1, occupancy_base: 0.0, occupancy_peak: 1.0))
      after = values(@sch.derive_values(type, 0.05, 0.9, 0.75, presence_pairs,
                                        timesteps_per_hour: 1, occupancy_base: 0.0, occupancy_peak: 1.0,
                                        lag_hours: nil, midpoint: nil, steepness: nil,
                                        threshold: nil, alpha_rise: nil, alpha_fall: nil))
      assert_equal before, after, "#{type} changed when the new parameters were passed as nil"
    end
  end

  def test_lag_hours_shifts_the_load_in_time
    base = values(derive('linear'))
    lagged = values(derive('linear', lag_hours: 3))

    refute_equal base, lagged, 'a non-zero lag should move the profile'
    # presence at 09:00 is carried to 12:00 by a 3 hour lag
    assert_in_delta base[8], lagged[11], 1e-6
    # and a lag of zero is a no-op
    assert_equal base, values(derive('linear', lag_hours: 0))
  end

  def test_lag_hours_wraps_across_midnight
    # Hour 23 with a 6 hour lag samples presence at 17:00, which is still fully occupied.
    lagged = values(derive('linear', lag_hours: 6))

    assert_operator lagged[22], :>, 0.5, 'a late-evening hour should pick up the afternoon presence'
  end

  def test_logistic_switches_around_its_midpoint
    shallow = values(derive('logistic', midpoint: 0.5, steepness: 4))
    steep = values(derive('logistic', midpoint: 0.5, steepness: 40))

    # hour 7 sits at presence 1/3, below the midpoint: a steep curve pushes it further down
    assert_operator steep[7], :<, shallow[7]
    # a low midpoint reaches full output earlier than a high one
    early = values(derive('logistic', midpoint: 0.2, steepness: 20))
    late = values(derive('logistic', midpoint: 0.8, steepness: 20))
    assert_operator early[8], :>, late[8]
    # endpoints stay pinned regardless of shape
    assert_in_delta 0.0, steep[0], 1e-6
    assert_in_delta 1.0, steep[12], 1e-6
  end

  def test_logistic_survives_extreme_steepness
    # Math.exp overflows without the clamp, which would return NaN rather than a step.
    result = values(derive('logistic', midpoint: 0.5, steepness: 500))

    assert(result.all? { |v| v.finite? }, 'extreme steepness produced a non-finite value')
    assert_operator result.max, :<=, 1.0 + 1e-9
  end

  def test_saturating_reaches_peak_at_its_threshold
    low = values(derive('saturating', threshold: 0.3))
    high = values(derive('saturating', threshold: 0.9))

    # hour 7 is at presence 1/3: past a 0.3 threshold, short of a 0.9 one
    assert_in_delta 1.0, low[7], 1e-6
    assert_operator high[7], :<, 1.0
    # and it holds at peak while presence keeps climbing
    assert_in_delta 1.0, low[12], 1e-6
  end

  def test_first_order_decays_more_slowly_than_it_rises
    fast_up = values(derive('first_order', alpha_rise: 0.9, alpha_fall: 0.1))

    # presence is zero from 19:00, but a slow fall rate leaves the load elevated
    assert_operator fast_up[21], :>, 0.2, 'a slow fall rate should leave a trailing load'
    # the reverse asymmetry trails on the way up instead
    slow_up = values(derive('first_order', alpha_rise: 0.1, alpha_fall: 0.9))
    assert_operator slow_up[10], :<, fast_up[10]
  end

  def test_first_order_is_periodic_not_start_of_day_dependent
    # The warm-up passes exist so the profile is the repeating steady state. Deriving from a
    # rotated copy of the same day should give a rotated copy of the same answer.
    result = values(derive('first_order', alpha_rise: 0.5, alpha_fall: 0.5))

    assert(result.all? { |v| v.finite? && v >= 0.0 && v <= 1.0 })
    # a symmetric filter on a profile that returns to zero should also return near zero
    assert_operator result[23], :<, 0.5
  end

  # A presence profile that never reaches zero, which is what almost every occupancy schedule
  # looks like: an overnight floor of 0.05 rather than nothing at all.
  def presence_pairs_with_base(floor = 0.05)
    presence_pairs.map { |time, value| [time, floor + ((1.0 - floor) * value)] }
  end

  def test_infer_start_end_times_is_invariant_to_the_occupancy_base
    # The bug: an absolute `> 0` cutoff counts the overnight floor as occupied, so a profile
    # with any non-zero base infers the whole day.
    zero_base = @sch.infer_start_end_times_from_profile(presence_pairs)
    raised_base = @sch.infer_start_end_times_from_profile(presence_pairs_with_base(0.05))

    assert_equal zero_base, raised_base, 'the inferred span shifted when the profile base was raised'
    refute_equal [0.0, 24.0], raised_base, 'a daytime profile should not infer the full day'
  end

  def test_infer_start_end_times_honors_an_explicit_threshold
    # An explicitly supplied threshold stays an absolute cutoff, so a 0.05 floor still reads as
    # active for the whole day - the pre-existing behavior, kept for callers that pass one.
    assert_equal [1.0, 24.0], @sch.infer_start_end_times_from_profile(presence_pairs_with_base(0.05), 0.0)
    # and a flat profile has no span to recover
    flat = (1..24).map { |hour| [hour.to_f, 0.4] }
    assert_equal [0.0, 24.0], @sch.infer_start_end_times_from_profile(flat)
  end

  def test_up_down_is_not_flattened_by_a_non_zero_occupancy_base
    # Regression: with the whole day inferred as occupied, the trapezoid had no room to come
    # down and every timestep sat at peak.
    pairs = @sch.derive_values('up_down', 0.1, 1.0, 1.0, presence_pairs_with_base(0.05),
                               start_slope: 0.5, end_slope: 0.5, timesteps_per_hour: 1)
    values = values(pairs)

    refute_empty values
    assert_in_delta 0.1, values.min, 1e-6, 'the derived profile never returned to base'
    assert_in_delta 1.0, values.max, 1e-6
  end

  def test_up_down_prefers_explicit_timing_over_inference
    # The editor and the library's production path both carry the occupancy record's st/et
    # through, which must win over anything inferred from the profile.
    narrow = values(@sch.derive_values('up_down', 0.1, 1.0, 1.0, presence_pairs_with_base(0.05),
                                       start_slope: 0.25, end_slope: 0.25,
                                       start_time: 10.0, end_time: 14.0, timesteps_per_hour: 1))
    wide = values(@sch.derive_values('up_down', 0.1, 1.0, 1.0, presence_pairs_with_base(0.05),
                                     start_slope: 0.25, end_slope: 0.25,
                                     start_time: 6.0, end_time: 22.0, timesteps_per_hour: 1))

    at_peak = ->(vals) { vals.count { |v| v > 0.99 } }
    assert_operator at_peak.call(narrow), :<, at_peak.call(wide),
                    'a narrower start/end window should hold peak for fewer hours'
  end

  def test_up_down_derives_an_overnight_load_past_midnight
    # The whole point of the timing fix: an overnight occupancy record (st 17, et 33) derived
    # through `up_down` must stay on across midnight rather than stopping at 24:00.
    vals = values(@sch.derive_values('up_down', 0.1, 1.0, 1.0, presence_pairs_with_base(0.05),
                                     start_slope: 0.5, end_slope: 0.5,
                                     start_time: 17.0, end_time: 33.0, timesteps_per_hour: 1))

    assert_operator vals.first, :>, 0.99, 'the load dropped out at midnight'
    assert_operator vals.last, :>, 0.99, 'the load did not carry into the evening'
    assert_operator vals.min, :<, 0.2, 'the load never returns to base'
  end

  SLOPES = { start_slope: 0.5, end_slope: 0.5, name: 'slope test' }.freeze

  def slope_values(st, et, tph = 4, schedule_data = SLOPES)
    @sch.expand_schedule_start_end_slope(schedule_data, 0.1, 1.0, st, et, tph).map { |_, value| value }
  end

  # Value in force at the end of the given hour, matching ScheduleDay's "applies up to" rule.
  def at_hour(vals, hour, tph = 4)
    vals[((hour + 1) * tph) - 1]
  end

  def test_overnight_slope_expansion_is_not_truncated_at_midnight
    # Regression: et was clamped to 24, so a guest-room span (17:00 -> 09:00) lost everything
    # after midnight and held peak for barely a quarter of its real duration.
    vals = slope_values(17.0, 33.0)

    assert_in_delta 1.0, at_hour(vals, 0), 1e-6, 'the small hours should still be at peak'
    assert_in_delta 1.0, at_hour(vals, 3), 1e-6
    assert_in_delta 1.0, at_hour(vals, 23), 1e-6, 'the late evening should be at peak'
    # and the middle of the day is the unoccupied stretch
    assert_operator at_hour(vals, 12), :<, 0.2, 'midday should fall back to base'
    # the plateau now spans most of the night rather than the 3.75 h the clamp left
    assert_operator vals.count { |v| v > 0.99 } / 4.0, :>, 8.0
  end

  def test_overnight_and_daytime_spans_are_mirror_images
    # A 16 h occupied span should hold peak for the same number of hours whether it sits
    # inside the day or straddles midnight.
    daytime = slope_values(4.0, 20.0)
    overnight = slope_values(16.0, 32.0)

    peak_hours = ->(vals) { vals.count { |v| v > 0.99 } }
    assert_equal peak_hours.call(daytime), peak_hours.call(overnight)
    assert_in_delta daytime.min, overnight.min, 1e-9
    assert_in_delta daytime.max, overnight.max, 1e-9
  end

  def test_slope_expansion_keeps_a_full_day_of_rows
    # The wrap helpers preserve row count; an overnight span must not add or drop timesteps.
    [1, 2, 4, 6].each do |tph|
      vals = slope_values(17.0, 33.0, tph)
      assert_equal 24 * tph, vals.size, "tph #{tph} did not return a full day"
    end
  end

  def test_a_span_of_a_full_day_or_more_stays_at_peak
    # 24 h occupied leaves no room for an off period, in either the same-day or wrapped form.
    assert(slope_values(0.0, 24.0).all? { |v| v > 0.99 })
    assert(slope_values(17.0, 41.0).all? { |v| v > 0.99 })
  end

  def test_overlapping_ramps_do_not_fill_a_plateau
    # start_slope 2.0 over a 16 h span makes the rising ramp wider than the span itself, so
    # start_upper lands past end_lower and there is no plateau to fill. This case used to hit
    # `start_upper % 24 == 0` and pin the entire day to peak.
    vals = slope_values(8.0, 24.0, 1, { start_slope: 2.0, end_slope: 0.1, name: 'overlap' })

    refute(vals.all? { |v| v > 0.89 }, 'an empty plateau was filled across the whole day')
    assert_operator vals.min, :<, 0.2, 'the profile never returns to base'
  end

  def test_unknown_derivation_type_returns_no_pairs
    assert_empty @sch.derive_values('not_a_type', 0.0, 1.0, 1.0, presence_pairs, timesteps_per_hour: 1)
  end
end
