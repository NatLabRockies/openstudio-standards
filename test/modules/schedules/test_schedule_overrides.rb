require_relative '../../helpers/minitest_helper'

# Tests for runtime schedule overrides: caller-supplied per-space-type
# overrides field-merge over the standard parameters, with a "*" wildcard and specific
# entries (specific wins). Precedence: override > building hours + offsets > standard.
#
# Matching itself is CreateTypical.resolve_overrides, shared by every override family, and is
# covered in test_space_type_load_overrides.rb.
class TestScheduleOverrides < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
    @create = OpenstudioStandards::CreateTypical
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  def space_type_named(model, name, schedule_set: nil, all_level: nil)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(name)
    space_type.additionalProperties.setFeature('schedule_set', schedule_set) unless schedule_set.nil?
    space_type.additionalProperties.setFeature('standards_space_type', all_level) unless all_level.nil?
    space_type
  end

  def test_resolve_specific_wins_over_wildcard
    model = new_model
    space_type = space_type_named(model, 'kitchen space', schedule_set: 'kitchen', all_level: 'food preparation')
    overrides = [
      { space_type: '*', occupancy: { base: 0.5 } },
      { space_type: 'kitchen', occupancy: { base: 0.7, peak: 0.95 }, lighting: { base: 0.1 } }
    ]
    merged = @create.resolve_overrides(overrides, space_type, section_keys: %i[occupancy lighting])
    assert_equal 0.7, merged[:occupancy][:base], 'specific entry should override the wildcard base'
    assert_equal 0.95, merged[:occupancy][:peak]
    assert_equal 0.1, merged[:lighting][:base]
  end

  def test_resolve_wildcard_only_when_no_specific
    model = new_model
    space_type = space_type_named(model, 'office space', schedule_set: 'office_open')
    overrides = [{ space_type: '*', occupancy: { base: 0.5 } },
                 { space_type: 'kitchen', occupancy: { base: 0.7 } }]
    merged = @create.resolve_overrides(overrides, space_type, section_keys: [:occupancy])
    assert_equal 0.5, merged[:occupancy][:base], 'office should pick up only the wildcard'
  end

  def test_resolve_matches_the_all_level_space_type
    model = new_model
    space_type = space_type_named(model, 'kitchen space', schedule_set: 'kitchen', all_level: 'food preparation')
    overrides = [{ space_type: 'food preparation', lighting: { peak: 0.4 } }]
    merged = @create.resolve_overrides(overrides, space_type, section_keys: [:lighting])
    assert_equal 0.4, merged[:lighting][:peak], 'entry should match the all-level space type name'
  end

  def test_resolve_empty_for_no_overrides
    model = new_model
    space_type = space_type_named(model, 'kitchen space', schedule_set: 'kitchen')
    assert_equal({}, @create.resolve_overrides(nil, space_type, section_keys: [:occupancy]))
    assert_equal({}, @create.resolve_overrides([], space_type, section_keys: [:occupancy]))
  end

  def test_override_applied_end_to_end
    model = new_model
    space_type = space_type_named(model, 'kitchen space', schedule_set: 'food preparation schedule set')

    overrides = [{ space_type: 'food preparation schedule set',
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

  # A schedule set that names no occupancy schedule leaves the space type unoccupied and its
  # People objects are removed, because a People object without a schedule terminates the
  # EnergyPlus run. Naming a schedule in the override is how a restroom given occupancy by an
  # occupancy_overrides entry keeps it.
  def test_occupancy_schedule_name_override_occupies_an_unoccupied_schedule_set
    model = new_model
    space_type = space_type_named(model, 'restroom space', schedule_set: 'restroom schedule set',
                                                          all_level: 'restroom')
    definition = OpenStudio::Model::PeopleDefinition.new(model)
    definition.setPeopleperSpaceFloorArea(0.05)
    people = OpenStudio::Model::People.new(definition)
    people.setSpaceType(space_type)

    # without a named schedule the People object is removed
    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type)
    assert_equal(0, space_type.people.size, 'a restroom schedule set names no occupancy schedule')

    # with one, the schedule is built and the People object survives
    space_type_2 = space_type_named(model, 'restroom space 2', schedule_set: 'restroom schedule set',
                                                              all_level: 'restroom')
    definition_2 = OpenStudio::Model::PeopleDefinition.new(model)
    definition_2.setPeopleperSpaceFloorArea(0.05)
    people_2 = OpenStudio::Model::People.new(definition_2)
    people_2.setSpaceType(space_type_2)

    overrides = [{ space_type: 'restroom', occupancy: { schedule: 'office occupancy' } }]
    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type_2, schedule_overrides: overrides)
    assert_equal(1, space_type_2.people.size, 'a named occupancy schedule should keep the People object')
    sch_set = space_type_2.defaultScheduleSet.get
    assert(sch_set.numberofPeopleSchedule.is_initialized, 'the named occupancy schedule should be assigned')
    assert(sch_set.peopleActivityLevelSchedule.is_initialized, 'the activity schedule comes with it')
  end

  # the name selects which schedule to draw from and is not mistaken for an expansion parameter
  def test_schedule_name_override_is_not_treated_as_a_parameter
    model = new_model
    space_type = space_type_named(model, 'office space', schedule_set: 'office schedule set',
                                                         all_level: 'office')
    overrides = [{ space_type: 'office', occupancy: { schedule: 'office occupancy', peak: 0.5 } }]
    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type, schedule_overrides: overrides)
    occ = space_type.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    values = @sch.schedule_day_get_hourly_values(occ.defaultDaySchedule)
    assert_in_delta(0.5, values.max, 0.001, 'the peak parameter should still apply alongside the schedule name')
  end
end
