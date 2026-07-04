require_relative '../../helpers/minitest_helper'

# End-to-end test that combines a custom-space-type-ratio bar model with
# create_typical_building_from_model's runtime schedule_overrides, confirming
# the overrides actually reach the schedules assigned to the generated space types.
class TestCustomBuildingSchedules < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    @create = OpenstudioStandards::CreateTypical
    @sch = OpenstudioStandards::Schedules
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  # returns the additionalProperties 'standards_space_type' feature, or nil if unset
  def standards_space_type_property(space_type)
    prop = space_type.additionalProperties.getFeatureAsString('standards_space_type')
    prop.is_initialized ? prop.get : nil
  end

  # min/max across every day schedule in a ScheduleRuleset (default day plus all rule days).
  # The default day alone is not representative: it is whichever profile has no rule
  # (often an off day), so a schedule's peak may only appear on a weekday rule day.
  def schedule_ruleset_extremes(schedule_ruleset)
    day_schedules = [schedule_ruleset.defaultDaySchedule] + schedule_ruleset.scheduleRules.map(&:daySchedule)
    values = day_schedules.flat_map { |day_sch| @sch.schedule_day_get_hourly_values(day_sch) }
    [values.min, values.max]
  end

  def test_custom_building_schedules_with_overrides
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'

    # build a bar-shaped model from custom space type ratios spanning multiple building types
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)

    bar_args = {
      template: template,
      space_type_hash_string: 'MediumOffice | Conference => 0.2, PrimarySchool | Corridor => 0.125, PrimarySchool | Classroom => 0.175, Warehouse | Office => 0.5'
    }
    assert(@geo.create_bar_from_space_type_ratios(model, bar_args))
    assert_equal(4, model.getSpaceTypes.size)

    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # runtime schedule overrides: a building-wide wildcard, plus two space-type-specific
    # entries keyed by the standards space type that MediumOffice|Conference and
    # PrimarySchool|Classroom resolve to. Specific entries should win field-by-field over
    # the wildcard; space types with no specific entry only pick up the wildcard.
    schedule_overrides = [
      { space_type: '*', lighting: { base: 0.02 } },
      { space_type: 'conference/meeting/multipurpose', occupancy: { base: 0.03, peak: 0.85 }, lighting: { base: 0.06, peak: 0.7 } },
      { space_type: 'classroom/lecture/training', occupancy: { base: 0.04, peak: 0.9 }, electric_equipment: { base: 0.1, peak: 0.5 } }
    ]

    # runtime load overrides applied on top of the standard internal loads, using the
    # same matching keys as schedule_overrides
    load_overrides = [
      { space_type: '*', lighting: { w_per_area: 0.85 } },
      { space_type: 'classroom/lecture/training', people: { people_per_1000_ft2: 40.0 }, electric_equipment: { w_per_area: 1.2 } }
    ]

    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    starting_size = model.getModelObjects.size
    result = @create.create_typical_building_from_model(model, template,
                                                          climate_zone: climate_zone,
                                                          add_hvac: false,
                                                          schedule_method: 'parametric',
                                                          schedule_overrides: schedule_overrides,
                                                          load_overrides: load_overrides,
                                                          sizing_run_directory: output_dir)
    ending_size = model.getModelObjects.size
    assert(result)
    assert_operator(ending_size, :>, starting_size)
    model.save("#{output_dir}/test_custom_building_schedules.osm", true)

    # no HVAC systems should have been added
    assert_equal(0, model.getAirLoopHVACs.size)
    assert_equal(0, model.getZoneHVACPackagedTerminalAirConditioners.size)

    # the four custom space types persisted through create_typical_building_from_model
    space_types = model.getSpaceTypes.to_a
    assert_equal(4, space_types.size)

    conference = space_types.find { |st| standards_space_type_property(st) == 'conference/meeting/multipurpose' }
    classroom = space_types.find { |st| standards_space_type_property(st) == 'classroom/lecture/training' }
    corridor = space_types.find { |st| standards_space_type_property(st) == 'corridor' }
    office = space_types.find { |st| standards_space_type_property(st) == 'office' }
    refute_nil(conference, 'expected a space type mapped to conference/meeting/multipurpose')
    refute_nil(classroom, 'expected a space type mapped to classroom/lecture/training')
    refute_nil(corridor, 'expected a space type mapped to corridor')
    refute_nil(office, 'expected a space type mapped to office')

    # every space type should have loads created and assigned via its default schedule set.
    # Corridor has zero occupant density in the 90.1-2013 standards data, so it gets no
    # People load object even though its default schedule set still carries an occupancy
    # schedule (used to derive the corridor's lighting/equipment schedules).
    [conference, classroom, corridor, office].each do |space_type|
      assert(space_type.defaultScheduleSet.is_initialized, "#{space_type.name} should have a default schedule set")
      sch_set = space_type.defaultScheduleSet.get
      assert(sch_set.numberofPeopleSchedule.is_initialized, "#{space_type.name} default schedule set should have an occupancy schedule")

      assert_operator(space_type.lights.size, :>, 0, "#{space_type.name} should have a Lights load")
      lights = space_type.lights.first
      assert(lights.isScheduleDefaulted, "#{space_type.name} Lights load should defer to the default schedule set, not a directly assigned schedule")
      assert(sch_set.lightingSchedule.is_initialized, "#{space_type.name} default schedule set should have a lighting schedule")
    end

    [conference, classroom, office].each do |space_type|
      assert_operator(space_type.people.size, :>, 0, "#{space_type.name} should have a People load")
      people = space_type.people.first
      assert(people.isNumberofPeopleScheduleDefaulted, "#{space_type.name} People load should defer to the default schedule set, not a directly assigned schedule")
    end

    tol = 0.01

    # occupancy override: conference/meeting/multipurpose specific entry (base 0.03, peak 0.85).
    # Direct parametric schedules are clamped between base and peak, so the ruleset should
    # never go outside that range and should reach both ends on at least one day/rule.
    conference_occ = conference.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    conference_occ_min, conference_occ_max = schedule_ruleset_extremes(conference_occ)
    assert_operator(conference_occ_min, :>=, 0.03 - tol)
    assert_in_delta(0.03, conference_occ_min, tol, 'conference occupancy should reach its overridden base')
    assert_operator(conference_occ_max, :<=, 0.85 + tol)
    assert_in_delta(0.85, conference_occ_max, tol, 'conference occupancy should reach its overridden peak')

    # occupancy override: classroom/lecture/training specific entry (base 0.04, peak 0.9)
    classroom_occ = classroom.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    classroom_occ_min, classroom_occ_max = schedule_ruleset_extremes(classroom_occ)
    assert_operator(classroom_occ_min, :>=, 0.04 - tol)
    assert_in_delta(0.04, classroom_occ_min, tol, 'classroom occupancy should reach its overridden base')
    assert_operator(classroom_occ_max, :<=, 0.9 + tol)
    assert_in_delta(0.9, classroom_occ_max, tol, 'classroom occupancy should reach its overridden peak')

    # lighting overrides: wildcard base 0.02 applies everywhere; conference's specific
    # lighting entry (base 0.06, peak 0.7) should win over the wildcard base.
    conference_light = conference.defaultScheduleSet.get.lightingSchedule.get.to_ScheduleRuleset.get
    conference_light_min, conference_light_max = schedule_ruleset_extremes(conference_light)
    assert_operator(conference_light_min, :>=, 0.06 - tol)
    assert_operator(conference_light_max, :<=, 0.7 + tol)

    [classroom, corridor, office].each do |space_type|
      light_sch = space_type.defaultScheduleSet.get.lightingSchedule.get.to_ScheduleRuleset.get
      light_min, = schedule_ruleset_extremes(light_sch)
      assert_operator(light_min, :>=, 0.02 - tol, "#{space_type.name} lighting schedule should respect the wildcard base override")
    end

    # electric equipment override: classroom/lecture/training specific entry (base 0.1, peak 0.5).
    # Electric equipment is derived from the occupancy schedule (exponential response), so it
    # approaches but need not exactly touch base/peak; assert it stays within the override bounds.
    assert(classroom.defaultScheduleSet.get.electricEquipmentSchedule.is_initialized)
    classroom_equip = classroom.defaultScheduleSet.get.electricEquipmentSchedule.get.to_ScheduleRuleset.get
    classroom_equip_min, classroom_equip_max = schedule_ruleset_extremes(classroom_equip)
    assert_operator(classroom_equip_min, :>=, 0.1 - tol)
    assert_operator(classroom_equip_max, :<=, 0.5 + tol)

    # corridor and office had no specific override entries, so their occupancy base values
    # should follow the standard parametric values rather than the conference/classroom overrides
    corridor_occ = corridor.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    corridor_occ_min, = schedule_ruleset_extremes(corridor_occ)
    refute_in_delta(0.04, corridor_occ_min, tol)

    # load overrides: the wildcard LPD applies to every space type
    load_tol = 0.0001
    expected_lpd_si = OpenStudio.convert(0.85, 'W/ft^2', 'W/m^2').get
    [conference, classroom, corridor, office].each do |space_type|
      lpd = space_type.lights.first.lightsDefinition.wattsperSpaceFloorArea.get
      assert_in_delta(expected_lpd_si, lpd, load_tol, "#{space_type.name} LPD should follow the wildcard load override")
    end

    # load overrides: classroom-specific people density and equipment power density
    classroom_density = classroom.people.first.peopleDefinition.peopleperSpaceFloorArea.get
    assert_in_delta(OpenStudio.convert(40.0 / 1000.0, 'people/ft^2', 'people/m^2').get, classroom_density, load_tol)
    classroom_epd = classroom.electricEquipment.first.electricEquipmentDefinition.wattsperSpaceFloorArea.get
    assert_in_delta(OpenStudio.convert(1.2, 'W/ft^2', 'W/m^2').get, classroom_epd, load_tol)

    # office had no specific load entry, so its equipment power density keeps the standard value
    office_epd = office.electricEquipment.first.electricEquipmentDefinition.wattsperSpaceFloorArea.get
    refute_in_delta(OpenStudio.convert(1.2, 'W/ft^2', 'W/m^2').get, office_epd, load_tol)
  end
end
