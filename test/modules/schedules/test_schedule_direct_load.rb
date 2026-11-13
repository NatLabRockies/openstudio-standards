require_relative '../../helpers/minitest_helper'

# Tests for the direct (non-occupancy) load path: a schedule set with a null
# occupancy schedule builds its loads directly from parametric definitions rather
# than deriving them from an occupancy schedule.
class TestScheduleDirectLoad < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  def test_null_occupancy_set_builds_direct_lighting
    model = new_model
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('interior parking')
    space_type.additionalProperties.setFeature('schedule_set', 'interior parking schedule set')

    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type)
    sch_set = space_type.defaultScheduleSet.get

    # a valid lighting ScheduleRuleset is produced directly
    assert sch_set.lightingSchedule.is_initialized, 'expected a direct lighting schedule'
    light = sch_set.lightingSchedule.get.to_ScheduleRuleset.get
    vals = @sch.schedule_day_get_hourly_values(light.defaultDaySchedule)
    assert_in_delta 1.0, vals.max, 0.05, 'direct lighting peak should reach peak_std'
    assert_operator vals.min, :>=, 0.25, 'direct lighting should not fall below its base'

    # no people / occupancy schedule for a not-regularly-occupied space
    refute sch_set.numberofPeopleSchedule.is_initialized, 'null-occupancy set should not set a people schedule'
  end

  def test_resolve_load_schedule_prefers_direct_over_derived
    model = new_model
    light = @sch.resolve_load_schedule(model, 'interior parking lighting', 'Lighting',
                                       :interior_lighting, nil, {}, {})
    refute_nil light, 'a control-point lighting schedule should resolve even with no occupancy'
    assert light.to_ScheduleRuleset.is_initialized
  end

  def test_resolve_load_schedule_warns_when_no_basis
    model = new_model
    # a derived record resolves only against an occupancy schedule, so without one it is nil
    result = @sch.resolve_load_schedule(model, 'atrium lighting', 'Lighting',
                                        :interior_lighting, nil, {}, {})
    assert_nil result, 'a derived schedule with no occupancy schedule should resolve to nil'
  end

  def test_resolve_load_schedule_reports_an_unknown_name
    model = new_model
    result = @sch.resolve_load_schedule(model, 'no such lighting schedule', 'Lighting',
                                        :interior_lighting, nil, {}, {})
    assert_nil result, 'an unknown schedule name should resolve to nil'
  end
end
