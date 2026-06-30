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
    space_type.additionalProperties.setFeature('schedule_set', 'parking_area_interior')

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
    schedules = JSON.parse(File.read("#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/schedules/data/default_parametric_schedules.json"), symbolize_names: true)
    light = @sch.resolve_load_schedule(model, schedules, 'parking interior lighting', 'Lighting',
                                       "#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/schedules/data/default_lighting_parameters.json",
                                       nil, {}, {})
    refute_nil light, 'a Lighting name should resolve to a direct schedule even with no occupancy'
    assert light.to_ScheduleRuleset.is_initialized
  end

  def test_resolve_load_schedule_warns_when_no_basis
    model = new_model
    schedules = JSON.parse(File.read("#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/schedules/data/default_parametric_schedules.json"), symbolize_names: true)
    # a name that is neither a direct Lighting schedule nor resolvable without occupancy
    result = @sch.resolve_load_schedule(model, schedules, 'some derived lighting name', 'Lighting',
                                        "#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/schedules/data/default_lighting_parameters.json",
                                        nil, {}, {})
    assert_nil result, 'a derived name with no occupancy schedule should resolve to nil'
  end
end
