require_relative '../../helpers/minitest_helper'

# Tests for truncate occupancy mode: time-of-day-anchored profiles clip
# to the [st, et] window instead of stretching, so a restaurant open only for lunch and
# dinner shows two peaks at their correct wall-clock times rather than three compressed.
class TestScheduleTruncateMode < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  # three meal-time humps anchored to absolute times (breakfast 9, lunch 13, dinner 19)
  def restaurant_profile(mode)
    [{
      name: 'restaurant', day_types: 'Default', category: 'Occupancy', type: 'parametric',
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      base_std: 0.1, peak_std: 1.0, st_std: 8.0, et_std: 22.0, adjustment_mode: mode,
      control_points: [
        ['st', 'base'], ['st+1', 'peak'], ['st+2', 'base'],     # breakfast hump @ 9
        ['st+5', 'peak'], ['st+6', 'base'],                     # lunch hump @ 13
        ['st+11', 'peak'], ['st+12', 'base'],                   # dinner hump @ 19
        ['et', 'base']
      ]
    }]
  end

  def default_hourly(profiles, params)
    sched = @sch.create_parametric_schedule_full(new_model, profiles, 'restaurant', params)
    @sch.schedule_day_get_hourly_values(sched.to_ScheduleRuleset.get.defaultDaySchedule)
  end

  # number of contiguous segments rising above a threshold (one per distinct hump)
  def count_peaks(vals, thresh = 0.5)
    count = 0
    above = false
    vals.each do |v|
      if v > thresh && !above
        count += 1
        above = true
      elsif v <= thresh
        above = false
      end
    end
    count
  end

  # index of the maximum value within an hour range
  def peak_hour_in(vals, range)
    range.max_by { |h| vals[h] }
  end

  def test_truncate_standalone_keeps_all_three_humps
    vals = default_hourly(restaurant_profile('truncate'), {})
    assert_equal 3, count_peaks(vals), 'standalone truncate profile should show three meal humps'
  end

  def test_truncate_lunch_and_dinner_window_drops_breakfast
    # open only for lunch + dinner (12:00-22:00) -> breakfast hump (9:00) is clipped out
    vals = default_hourly(restaurant_profile('truncate'), { st: 12.0, et: 22.0 })
    assert_equal 2, count_peaks(vals), 'lunch+dinner window should show exactly two humps'

    # the retained humps stay at their correct wall-clock times (≈13 and ≈19)
    assert_includes 12..15, peak_hour_in(vals, 12..15)
    assert_operator vals[12..15].max, :>, 0.5
    assert_operator vals[17..20].max, :>, 0.5
    # the breakfast window is at base
    assert_operator vals[9], :<, 0.3
  end

  def test_stretch_mode_compresses_into_window
    # the same profile in stretch mode keeps all three humps but compresses them into
    # the shorter window, so the dinner peak is pulled much earlier than 19:00
    truncate_vals = default_hourly(restaurant_profile('truncate'), { st: 12.0, et: 22.0 })
    stretch_vals = default_hourly(restaurant_profile('stretch'), { st: 12.0, et: 22.0 })

    assert_equal 3, count_peaks(stretch_vals), 'stretch mode compresses all three humps into the window'
    assert_operator count_peaks(truncate_vals), :<, count_peaks(stretch_vals),
                    'truncate mode should drop the out-of-window hump that stretch keeps'
  end

  def test_default_mode_is_stretch
    explicit = default_hourly(restaurant_profile('stretch'), { st: 10.0, et: 20.0 })
    profiles = restaurant_profile('stretch')
    profiles.first.delete(:adjustment_mode)
    implicit = default_hourly(profiles, { st: 10.0, et: 20.0 })
    assert_equal explicit.map { |v| v.round(6) }, implicit.map { |v| v.round(6) },
                 'omitting adjustment_mode should behave as stretch'
  end
end
