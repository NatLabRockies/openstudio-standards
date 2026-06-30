require_relative '../../helpers/minitest_helper'

# Tests for runtime schedule overrides: caller-supplied per-space-type
# overrides field-merge over the standard parameters, with a "*" wildcard and specific
# entries (specific wins). Precedence: override > building hours + offsets > standard.
class TestScheduleOverrides < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  def test_resolve_specific_wins_over_wildcard
    overrides = [
      { space_type: '*', occupancy: { base: 0.5 } },
      { space_type: 'kitchen', occupancy: { base: 0.7, peak: 0.95 }, lighting: { base: 0.1 } }
    ]
    merged = @sch.resolve_schedule_overrides(overrides, 'kitchen', 'food_preparation')
    assert_equal 0.7, merged[:occupancy][:base], 'specific entry should override the wildcard base'
    assert_equal 0.95, merged[:occupancy][:peak]
    assert_equal 0.1, merged[:lighting][:base]
  end

  def test_resolve_wildcard_only_when_no_specific
    overrides = [{ space_type: '*', occupancy: { base: 0.5 } },
                 { space_type: 'kitchen', occupancy: { base: 0.7 } }]
    merged = @sch.resolve_schedule_overrides(overrides, 'office_open', nil)
    assert_equal 0.5, merged[:occupancy][:base], 'office should pick up only the wildcard'
  end

  def test_resolve_matches_standards_space_type
    overrides = [{ space_type: 'food_preparation', lighting: { peak: 0.4 } }]
    merged = @sch.resolve_schedule_overrides(overrides, 'kitchen', 'food_preparation')
    assert_equal 0.4, merged[:lighting][:peak], 'entry should match the standards space type key'
  end

  def test_resolve_empty_for_no_overrides
    assert_equal({}, @sch.resolve_schedule_overrides(nil, 'kitchen', nil))
    assert_equal({}, @sch.resolve_schedule_overrides([], 'kitchen', nil))
  end

  def test_override_applied_end_to_end
    model = new_model
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('kitchen space')
    space_type.additionalProperties.setFeature('schedule_set', 'kitchen')

    overrides = [{ space_type: 'kitchen',
                   occupancy: { peak: 0.4 },
                   lighting: { base: 0.02, peak: 0.3, response: 1.0 } }]
    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type, schedule_overrides: overrides)
    sch_set = space_type.defaultScheduleSet.get

    # occupancy peak override caps the people schedule (standard kitchen peak is ~0.7-0.8)
    occ = sch_set.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    occ_vals = @sch.schedule_day_get_hourly_values(occ.defaultDaySchedule)
    assert_operator occ_vals.max, :<=, 0.42, 'occupancy peak override should cap the people schedule'

    # lighting base/peak override caps the derived lighting schedule
    light = sch_set.lightingSchedule.get.to_ScheduleRuleset.get
    light_vals = @sch.schedule_day_get_hourly_values(light.defaultDaySchedule)
    assert_operator light_vals.max, :<=, 0.32, 'lighting peak override should cap the derived schedule'
  end
end
