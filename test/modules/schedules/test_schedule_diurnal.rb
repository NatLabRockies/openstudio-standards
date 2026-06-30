require_relative '../../helpers/minitest_helper'

# Tests for the diurnal load modifier: derived lighting/equipment can diverge
# from occupancy by a time-of-day awake/asleep gate, so hotel guest-room loads are low
# overnight (asleep) and midday (away) but peak morning/evening, while the occupancy
# (People) schedule and the design days are unmodified.
class TestScheduleDiurnal < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  # occupancy present evening through morning (18:00 -> 09:00), away midday
  def guest_occupancy(model)
    profile = [{
      name: 'guest occ', day_types: 'Default', category: 'Occupancy', type: 'parametric',
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      base_std: 0.1, peak_std: 1.0, st_std: 18.0, et_std: 33.0,
      control_points: [['st', 'base'], ['st+1', 'peak'], ['et-1', 'peak'], ['et', 'base']]
    }]
    @sch.create_parametric_schedule_full(model, profile, 'guest occ', {})
  end

  def lighting_params(diurnal: false)
    p = { name: 'guest lights', category: 'Lighting', derivation_type: 'linear',
          base: 0.05, peak: 0.9, response: 1.0,
          summer_design_day_base: 1.0, winter_design_day_peak: 0.0 }
    if diurnal
      p[:diurnal_profile] = 'sleep awake'
      p[:diurnal_mode] = 'off_when_asleep'
      p[:diurnal_weight] = 1.0
    end
    p
  end

  def hourly(day_sch)
    @sch.schedule_day_get_hourly_values(day_sch)
  end

  def test_diurnal_suppresses_overnight_keeps_evening_and_morning
    model = new_model
    occ = guest_occupancy(model)

    plain = @sch.create_derived_schedule_from_occupancy_schedule(occ, lighting_params(diurnal: false))
    gated = @sch.create_derived_schedule_from_occupancy_schedule(occ, lighting_params(diurnal: true))

    plain_vals = hourly(plain.defaultDaySchedule)
    gated_vals = hourly(gated.defaultDaySchedule)

    # without the gate, overnight loads track the (high) overnight occupancy
    assert_operator plain_vals[3], :>, 0.5, 'plain derivation should be high overnight'

    # with the gate, overnight (asleep) is suppressed toward base...
    assert_operator gated_vals[3], :<, 0.2, 'diurnal gate should suppress overnight loads'
    # ...while evening and morning (present and awake) still peak
    assert_operator gated_vals[20], :>, 0.5, 'evening loads should remain high'
    assert_operator gated_vals[8], :>, 0.4, 'morning loads should remain high'
  end

  def test_design_days_not_gated
    model = new_model
    occ = guest_occupancy(model)
    gated = @sch.create_derived_schedule_from_occupancy_schedule(occ, lighting_params(diurnal: true))

    default_vals = hourly(gated.defaultDaySchedule)
    summer_vals = hourly(gated.summerDesignDaySchedule)

    # the summer design day is not gated, so its overnight value is not suppressed the
    # way the (gated) default day is
    assert_operator summer_vals[3], :>, default_vals[3] + 0.2,
                    'summer design day should ignore the diurnal gate'
  end

  def test_occupancy_schedule_unchanged_by_diurnal
    model = new_model
    occ = guest_occupancy(model)
    occ_vals = hourly(occ.defaultDaySchedule)

    # deriving a gated load must not modify the occupancy/People schedule itself
    @sch.create_derived_schedule_from_occupancy_schedule(occ, lighting_params(diurnal: true))
    assert_equal occ_vals, hourly(occ.defaultDaySchedule), 'occupancy schedule should be untouched'
    assert_operator occ_vals[3], :>, 0.5, 'occupancy stays high overnight'
  end
end
