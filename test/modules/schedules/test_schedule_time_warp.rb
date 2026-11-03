require_relative '../../helpers/minitest_helper'

# Tests for the control-point time warp: a profile expanded away from its standard
# timing stretches inside the occupied window, keeps its arrival and departure ramps at
# their authored width, and never lets a control point cross, invert, or wrap past
# another. Scaling each offset off its own anchor - the previous formulation - did all
# three wrong: an 'et+7' point on a 1.4x duration landed at 31 h, wrapped to 07:00, and
# punched a notch into a rising edge.
class TestScheduleTimeWarp < Minitest::Test
  TIMESTEPS_PER_HOUR = 4

  def setup
    @sch = OpenstudioStandards::Schedules
  end

  # Mirrors the shipped 'office occupancy' Default profile: an arrival ramp, a lunch
  # dip, a departure ramp and a low overnight tail. Inlined so the test pins the
  # expansion behavior rather than the current contents of the data files.
  def office_profile(overrides = {})
    {
      name: 'office', day_types: 'Default', category: 'Occupancy', type: 'parametric',
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      base_std: 0.0, peak_std: 0.95, st_std: 8.0, et_std: 17.0,
      control_points: [
        ['st-8', 'base'], ['st-3', 'base'], ['st-1', 'peak*0.211'],
        ['st', 'peak'], ['st+3', 'peak'], ['st+4', 'peak*0.526'],
        ['et-4', 'peak'], ['et-1', 'peak'], ['et', 'peak*0.316'],
        ['et+1', 'peak*0.105'], ['et+7', 'peak*0.053']
      ]
    }.merge(overrides)
  end

  # Mirrors a shipped 'dining' profile, whose st- and et-anchored points interleave in
  # standard coordinates ('st+6' at 22 h sits ahead of 'et-7' at 19 h). Under offset
  # scaling their relative order is a function of the duration multiplier.
  def interleaved_profile
    {
      name: 'interleaved', day_types: 'Default', category: 'Occupancy', type: 'parametric',
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      base_std: 0.05, peak_std: 0.8, st_std: 16.0, et_std: 26.0,
      control_points: [
        ['st-7', 'base'], ['st-2', 'base'], ['st-1', 'peak*0.125'], ['st', 'peak*0.5'],
        ['st+2', 'peak*0.5'], ['st+3', 'peak*0.25'], ['st+5', 'peak*0.3125'],
        ['st+6', 'peak'], ['et-7', 'peak'], ['et-6', 'peak'], ['et-4', 'peak*0.625'],
        ['et-2', 'peak*0.25'], ['et-1', 'peak*0.25'], ['et+1', 'base'], ['et+2', 'base']
      ]
    }
  end

  def anchors(profile, st, et)
    @sch.evaluate_schedule_control_points(profile, profile[:base_std], profile[:peak_std], st, et, TIMESTEPS_PER_HOUR)
  end

  def expanded(profile, st, et)
    @sch.expand_schedule_control_points(profile, profile[:base_std], profile[:peak_std], st, et, TIMESTEPS_PER_HOUR)
  end

  # authored control-point times in standard coordinates, sorted
  def standard_times(profile)
    profile[:control_points].map { |point| @sch.control_point_standard_time(point[0], profile[:st_std], profile[:et_std]) }.sort
  end

  # a spread of windows: standard, longer, shorter, shifted early, shifted late
  WINDOWS = [[8.0, 17.0], [8.25, 21.0], [6.0, 22.0], [9.0, 13.0], [4.0, 11.0], [13.0, 23.0]].freeze

  # -------------------------------------------------------------------------
  # The warp is the identity at the profile's own standard timing
  # -------------------------------------------------------------------------

  def test_identity_at_standard_timing
    profile = office_profile
    result = anchors(profile, profile[:st_std], profile[:et_std]).map(&:first)
    assert_equal standard_times(profile), result,
                 'expanding at st_std/et_std must reproduce the authored standard times'
  end

  # -------------------------------------------------------------------------
  # Inside the occupied window the shape scales with the duration
  # -------------------------------------------------------------------------

  def test_occupied_window_scales_proportionally
    profile = office_profile
    st = 8.25
    et = 21.0
    ratio = (et - st) / (profile[:et_std] - profile[:st_std])
    result = anchors(profile, st, et)

    standard_times(profile).each_with_index do |std_time, i|
      next unless std_time >= profile[:st_std] && std_time <= profile[:et_std]

      expected = st + ((std_time - profile[:st_std]) * ratio)
      assert_in_delta expected, result[i][0], 1.0 / TIMESTEPS_PER_HOUR,
                      "in-window point at standard hour #{std_time} should scale with the duration"
    end
  end

  def test_window_edges_land_on_the_requested_times
    profile = office_profile
    result = anchors(profile, 8.25, 21.0)
    times = result.map(&:first)
    assert_includes times, 8.25, "the 'st' control point must land on the requested start time"
    assert_includes times, 21.0, "the 'et' control point must land on the requested end time"
  end

  # -------------------------------------------------------------------------
  # Outside the window the ramps keep their authored width
  # -------------------------------------------------------------------------

  def test_shoulders_keep_absolute_width
    profile = office_profile
    WINDOWS.each do |st, et|
      result = anchors(profile, st, et).map(&:first)
      arrival = result.select { |t| t < st }.max
      departure = result.select { |t| t > et }.min

      assert_in_delta 1.0, st - arrival, 1e-9,
                      "arrival ramp should stay 1 h wide at st #{st} / et #{et}"
      assert_in_delta 1.0, departure - et, 1e-9,
                      "departure ramp should stay 1 h wide at st #{st} / et #{et}"
    end
  end

  def test_shoulder_field_widens_the_rigid_region
    # 'st-2' sits outside the default 1 h rigid region, so it rides the elastic pad;
    # widening the shoulder to 2 h brings it inside and pins its offset
    points = [['st-2', 'base'], ['st', 'peak'], ['et', 'peak'], ['et+2', 'base']]
    elastic = anchors(office_profile(control_points: points), 8.25, 21.0).map(&:first)
    rigid = anchors(office_profile(control_points: points, shoulder: 2.0), 8.25, 21.0).map(&:first)

    assert_in_delta 2.0, 8.25 - rigid.first, 1e-9, 'a 2 h shoulder should hold the point 2 h before st'
    assert_in_delta 2.0, rigid.last - 21.0, 1e-9, 'a 2 h shoulder should hold the point 2 h after et'
    refute_in_delta 2.0, 8.25 - elastic.first, 1e-9, 'outside the default shoulder the point should stretch'
  end

  # -------------------------------------------------------------------------
  # No self-interference: order preserved, at most a day of coverage
  # -------------------------------------------------------------------------

  def test_anchors_are_monotone
    [office_profile, interleaved_profile].each do |profile|
      WINDOWS.each do |st, et|
        times = anchors(profile, st, et).map(&:first)
        assert_equal times.sort, times,
                     "#{profile[:name]} anchors must stay ordered at st #{st} / et #{et}"
      end
    end
  end

  def test_span_never_exceeds_a_day
    # one timestep of slack: each endpoint rounds to the grid independently
    tolerance = 1.0 / TIMESTEPS_PER_HOUR
    [office_profile, interleaved_profile].each do |profile|
      WINDOWS.each do |st, et|
        times = anchors(profile, st, et).map(&:first)
        span = times.max - times.min
        assert_operator span, :<=, 24.0 + tolerance,
                        "#{profile[:name]} spans #{span} h at st #{st} / et #{et}"
      end
    end
  end

  def test_value_order_is_independent_of_duration
    # st- and et-anchored points interleave here, so this locks the property that the
    # resolved order is a function of the authored offsets alone and never of the
    # requested duration
    profile = interleaved_profile
    reference = anchors(profile, profile[:st_std], profile[:et_std]).map(&:last)
    [[16.0, 22.0], [14.0, 30.0], [18.0, 24.0]].each do |st, et|
      assert_equal reference, anchors(profile, st, et).map(&:last),
                   "anchor values should keep their authored order at st #{st} / et #{et}"
    end
  end

  def test_no_duplicate_times
    [office_profile, interleaved_profile].each do |profile|
      WINDOWS.each do |st, et|
        times = anchors(profile, st, et).map(&:first)
        assert_equal times.uniq, times,
                     "#{profile[:name]} should not repeat a timestep at st #{st} / et #{et}"
      end
    end
  end

  # -------------------------------------------------------------------------
  # The headline regression: a long et-anchored offset wrapping into the morning
  # -------------------------------------------------------------------------

  def test_rising_edge_has_no_wrapped_notch
    # 'et+7' scaled to 31.0 under the old formulation, wrapped to 07:00, and dropped a
    # 0.05 value into the middle of a ramp climbing to 0.95
    profile = office_profile
    st = 8.25
    edge = expanded(profile, st, 21.0).select { |time, _| time >= st - 2.0 && time <= st }
    values = edge.map(&:last)

    refute_empty values
    values.each_cons(2) do |current, following|
      assert_operator following, :>=, current - 1e-9,
                      "the arrival ramp must climb without a dip: #{edge.inspect}"
    end
  end

  def test_overnight_base_is_preserved
    # the old formulation pushed the anchors carrying the overnight level outside the day
    # and read a flat zero through the small hours. The tail now decays across midnight
    # from the 'et+1' level toward the 'et+7' level, so every small-hours value sits
    # inside that band.
    profile = office_profile
    pairs = expanded(profile, 8.25, 21.0)
    overnight = pairs.select { |time, _| time >= 0.0 && time <= 2.0 }.map(&:last)
    floor = profile[:peak_std] * 0.053
    ceiling = profile[:peak_std] * 0.105

    refute_empty overnight
    assert_operator overnight.min, :>, 0.0, 'the overnight tail should not read as unoccupied'
    assert_operator overnight.min, :>=, floor - 1e-6, 'the tail should not fall below its own overnight level'
    assert_operator overnight.max, :<=, ceiling + 1e-6, 'the tail should not exceed the level it decays from'
    # and it is a decay, not a plateau
    assert_operator overnight.first, :>, overnight.last
  end

  def test_expansion_emits_no_negative_times
    profile = office_profile
    ([[0.5, 8.0], [1.0, 6.0], [2.0, 9.0]] + WINDOWS).each do |st, et|
      times = expanded(profile, st, et).map(&:first)
      assert_operator times.min, :>=, 0.0, "expansion at st #{st} / et #{et} produced a negative time"
      assert_operator times.max, :<=, 24.0, "expansion at st #{st} / et #{et} ran past hour 24"
    end
  end

  # -------------------------------------------------------------------------
  # The day boundary: hour 24 sits partway along the wrapped segment
  # -------------------------------------------------------------------------

  # the anchors the expander smooths, i.e. after the cross-midnight wrap
  def wrapped_anchors(profile, st, et)
    pairs = anchors(profile, st, et)
    return pairs unless pairs[-1][0] > 24 || pairs[0][0].negative?

    @sch.wrap_schedule_pairs(pairs)
  end

  def test_day_boundary_value_is_interpolated
    # the profile's last anchor sits at 22:00 and its next one is 02:15 the following
    # morning, so hour 24 is 2 h into a 4.25 h segment - not the end of a flat hold
    profile = office_profile
    pairs = wrapped_anchors(profile, 8.25, 21.0)
    last_time, last_value = pairs.last
    first_time, first_value = pairs.first
    gap = (first_time + 24.0) - last_time
    expected = last_value + (@sch.smootherstep_easing((24.0 - last_time) / gap) * (first_value - last_value))

    boundary = expanded(profile, 8.25, 21.0).assoc(24.0)
    refute_nil boundary, 'the expanded profile must carry a value at hour 24'
    assert_in_delta expected, boundary[1], 1e-12,
                    'hour 24 should be the eased value between the anchors either side of midnight'
    refute_in_delta last_value, boundary[1], 1e-6,
                    'hour 24 should not simply repeat the last anchor value'
  end

  def test_day_boundary_is_not_a_flat_hold
    # the old padding copied the last anchor value out to hour 24 and the first anchor
    # value back to hour 0, leaving a flat run either side of midnight and a step between
    profile = office_profile
    pairs = expanded(profile, 8.25, 21.0)
    tail = pairs.select { |time, _| time > 22.0 }.map(&:last)
    head = pairs.select { |time, _| time < 2.25 }.map(&:last)

    assert_operator tail.uniq.size, :>, 1, 'the run into midnight should not be flat'
    assert_operator head.uniq.size, :>, 1, 'the run out of midnight should not be flat'
  end

  def test_profile_is_continuous_across_midnight
    profile = office_profile
    pairs = expanded(profile, 8.25, 21.0)
    interior = pairs.each_cons(2).map { |current, following| (following[1] - current[1]).abs }.max
    midnight = (pairs.first[1] - pairs.last[1]).abs

    assert_operator midnight, :<=, interior,
                    'the step across midnight should be no larger than the steepest step within the day'
  end

  def test_cyclic_smoothing_covers_the_day
    profile = office_profile
    WINDOWS.each do |st, et|
      times = expanded(profile, st, et).map(&:first)
      assert_operator times.min, :>=, 0.0
      assert_equal 24.0, times.max, "the profile must end on hour 24 at st #{st} / et #{et}"
      assert_equal times.uniq, times, "no repeated sample times at st #{st} / et #{et}"
      assert_equal times.sort, times, "samples must be ordered at st #{st} / et #{et}"
    end
  end

  def test_non_cyclic_smoothing_still_pads_flat
    # the slope expander hands over bare ramp segments that it assembles itself, so the
    # default (non-cyclic) padding must stay a flat hold
    pairs = [[6.0, 0.2], [10.0, 0.9]]
    smoothed = @sch.smooth_schedule_from_time_values(pairs.map(&:dup), TIMESTEPS_PER_HOUR)

    assert_in_delta 0.2, smoothed.first[1], 1e-12, 'hour 0 should hold the first value'
    assert_in_delta 0.9, smoothed.assoc(24.0)[1], 1e-12, 'hour 24 should hold the last value'
  end

  def test_cyclic_smoothing_closes_the_same_pairs
    pairs = [[6.0, 0.2], [10.0, 0.9]]
    smoothed = @sch.smooth_schedule_from_time_values(pairs.map(&:dup), TIMESTEPS_PER_HOUR, cyclic: true)
    boundary = smoothed.assoc(24.0)[1]

    # 24 is 14 h into the 20 h run from (10.0, 0.9) back round to (6.0, 0.2)
    expected = 0.9 + (@sch.smootherstep_easing(14.0 / 20.0) * (0.2 - 0.9))
    assert_in_delta expected, boundary, 1e-12
  end

  # -------------------------------------------------------------------------
  # Data edge cases
  # -------------------------------------------------------------------------

  def test_fractional_offsets_are_honored
    # the token parser accepts decimals; the offset used to be read with to_i, which
    # silently turned 'st-0.5' into 'st'
    profile = office_profile(control_points: [['st-0.5', 'base'], ['st', 'peak'], ['et', 'base']])
    assert_equal [7.5, 8.0, 17.0], anchors(profile, 8.0, 17.0).map(&:first)
  end

  def test_overspecified_pad_is_compressed
    # authored pads of 8 h and 6 h around an 18 h window cover 32 h of a 24 h day
    profile = office_profile(
      st_std: 5.0, et_std: 23.0,
      control_points: [['st-8', 'base'], ['st', 'peak'], ['et', 'peak'], ['et+6', 'base']]
    )
    times = anchors(profile, profile[:st_std], profile[:et_std]).map(&:first)

    assert_operator times.max - times.min, :<=, 24.0 + (1.0 / TIMESTEPS_PER_HOUR)
    # the occupied window itself is untouched; only the padding gives ground
    assert_includes times, 5.0
    assert_includes times, 23.0
  end

  def test_full_day_profile_expands_without_error
    # design days run st_std 0 / et_std 24, leaving no unoccupied hours to hold rigid
    profile = office_profile(st_std: 0.0, et_std: 24.0, control_points: [['st', 'peak'], ['et', 'peak']])
    assert_equal [0.0, 24.0], anchors(profile, 0.0, 24.0).map(&:first)

    shifted = anchors(profile, 9.0, 13.0).map(&:first)
    assert_equal shifted.sort, shifted
    assert_equal [9.0, 13.0], shifted
  end

  def test_inverted_window_wraps_across_midnight
    profile = office_profile(control_points: [['st', 'base'], ['st+1', 'peak'], ['et-1', 'peak'], ['et', 'base']])
    # an end time before the start time means the window runs past midnight
    times = anchors(profile, 20.0, 6.0).map(&:first)
    assert_equal times.sort, times
    assert_includes times, 20.0
    assert_includes times, 30.0
  end
end
