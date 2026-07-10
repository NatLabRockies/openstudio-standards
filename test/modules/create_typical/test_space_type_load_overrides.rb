require_relative '../../helpers/minitest_helper'

class TestSpaceTypeLoadOverrides < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    @template = '90.1-2013'
  end

  # build a space type with standard loads applied and override matching keys set
  def build_space_type(model, building_type, space_type_name, standards_space_type_property)
    standard = Standard.build(@template)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType(building_type)
    space_type.setStandardsSpaceType(space_type_name)
    space_type.setName("#{building_type} #{space_type_name}")
    space_type.additionalProperties.setFeature('standards_space_type', standards_space_type_property)
    assert(standard.space_type_apply_internal_loads(space_type), "could not apply standard loads to #{space_type.name}")
    space_type
  end

  def test_parse_overrides_argument
    array_input = [{ 'space_type' => '*', 'lighting' => { 'w_per_area' => 0.9 } }]
    parsed = @create.parse_overrides_argument(array_input, 'load_overrides')
    assert_equal('*', parsed[0][:space_type])

    json_input = '[{"space_type": "*", "lighting": {"w_per_area": 0.9}}]'
    parsed = @create.parse_overrides_argument(json_input, 'load_overrides')
    assert_equal(0.9, parsed[0][:lighting][:w_per_area])

    assert_nil(@create.parse_overrides_argument('[{"space_type": ', 'load_overrides'))
    assert_nil(@create.parse_overrides_argument(nil, 'load_overrides'))
    assert_nil(@create.parse_overrides_argument('', 'load_overrides'))
  end

  def test_load_overrides_set_definition_values
    model = OpenStudio::Model::Model.new
    space_type = build_space_type(model, 'Office', 'Conference', 'conference/meeting/multipurpose')

    load_overrides = [
      { space_type: 'conference/meeting/multipurpose',
        people: { people_per_1000_ft2: 40.0 },
        lighting: { w_per_area: 0.8 },
        electric_equipment: { w_per_area: 1.2 },
        gas_equipment: { btu_per_hr_per_area: 5.0 },
        ventilation: { cfm_per_person: 7.5, cfm_per_area: 0.06, ach: 0.5 } }
    ]
    assert(@create.space_type_apply_load_overrides(space_type, load_overrides))

    tol = 0.0001
    people_def = space_type.people.first.peopleDefinition
    assert_in_delta(OpenStudio.convert(40.0 / 1000.0, 'people/ft^2', 'people/m^2').get, people_def.peopleperSpaceFloorArea.get, tol)

    lights_def = space_type.lights.first.lightsDefinition
    assert_in_delta(OpenStudio.convert(0.8, 'W/ft^2', 'W/m^2').get, lights_def.wattsperSpaceFloorArea.get, tol)

    elec_def = space_type.electricEquipment.first.electricEquipmentDefinition
    assert_in_delta(OpenStudio.convert(1.2, 'W/ft^2', 'W/m^2').get, elec_def.wattsperSpaceFloorArea.get, tol)

    # gas equipment is created by the override; Conference has no standard gas equipment
    assert_equal(1, space_type.gasEquipment.size)
    gas_def = space_type.gasEquipment.first.gasEquipmentDefinition
    assert_in_delta(OpenStudio.convert(5.0, 'Btu/hr*ft^2', 'W/m^2').get, gas_def.wattsperSpaceFloorArea.get, tol)

    ventilation = space_type.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(7.5, 'ft^3/min', 'm^3/s').get, ventilation.outdoorAirFlowperPerson, tol)
    assert_in_delta(OpenStudio.convert(0.06, 'ft^3/min*ft^2', 'm^3/s*m^2').get, ventilation.outdoorAirFlowperFloorArea, tol)
    assert_in_delta(0.5, ventilation.outdoorAirFlowAirChangesperHour, tol)
  end

  def test_load_overrides_wildcard_and_precedence
    model = OpenStudio::Model::Model.new
    conference = build_space_type(model, 'Office', 'Conference', 'conference/meeting/multipurpose')
    open_office = build_space_type(model, 'Office', 'OpenOffice', 'office')

    load_overrides = [
      { space_type: '*', lighting: { w_per_area: 0.85 }, electric_equipment: { w_per_area: 2.0 } },
      { space_type: 'conference/meeting/multipurpose', lighting: { w_per_area: 0.5 } }
    ]
    assert(@create.space_type_apply_load_overrides(conference, load_overrides))
    assert(@create.space_type_apply_load_overrides(open_office, load_overrides))

    tol = 0.0001
    # specific entry wins over the wildcard for conference lighting
    assert_in_delta(OpenStudio.convert(0.5, 'W/ft^2', 'W/m^2').get,
                    conference.lights.first.lightsDefinition.wattsperSpaceFloorArea.get, tol)
    # conference still picks up the wildcard electric equipment field
    assert_in_delta(OpenStudio.convert(2.0, 'W/ft^2', 'W/m^2').get,
                    conference.electricEquipment.first.electricEquipmentDefinition.wattsperSpaceFloorArea.get, tol)
    # open office only matches the wildcard
    assert_in_delta(OpenStudio.convert(0.85, 'W/ft^2', 'W/m^2').get,
                    open_office.lights.first.lightsDefinition.wattsperSpaceFloorArea.get, tol)
  end

  def test_load_overrides_create_missing_load
    model = OpenStudio::Model::Model.new
    # PrimarySchool corridors have zero occupant density in the standards data, so no People load exists
    corridor = build_space_type(model, 'PrimarySchool', 'Corridor', 'corridor')
    assert_equal(0, corridor.people.size)

    load_overrides = [{ space_type: 'corridor', people: { people_per_1000_ft2: 5.0 } }]
    assert(@create.space_type_apply_load_overrides(corridor, load_overrides))
    assert_equal(1, corridor.people.size)
    assert_in_delta(OpenStudio.convert(5.0 / 1000.0, 'people/ft^2', 'people/m^2').get,
                    corridor.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  def test_load_overrides_keep_standard_design_level
    model = OpenStudio::Model::Model.new
    space_type = build_space_type(model, 'Office', 'Conference', 'conference/meeting/multipurpose')
    standard_density_si = space_type.people.first.peopleDefinition.peopleperSpaceFloorArea.get
    standard_per_1000_ft2 = OpenStudio.convert(standard_density_si, 'people/m^2', 'people/ft^2').get * 1000.0
    target = standard_per_1000_ft2 * 0.6

    load_overrides = [{ space_type: 'conference/meeting/multipurpose',
                        people: { people_per_1000_ft2: target, keep_standard_design_level: true } }]
    assert(@create.space_type_apply_load_overrides(space_type, load_overrides))

    # the design occupancy level is unchanged; the schedule peak adjustment is registered instead
    assert_in_delta(standard_density_si, space_type.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
    peak = space_type.additionalProperties.getFeatureAsDouble('occupancy_peak_override')
    assert(peak.is_initialized, 'occupancy_peak_override additional property should be set')
    assert_in_delta(0.6, peak.get, 0.0001)
  end

  def test_load_overrides_keep_standard_design_level_without_standard_people
    model = OpenStudio::Model::Model.new
    # PrimarySchool corridors have zero occupant density, so there is no standard level to keep
    corridor = build_space_type(model, 'PrimarySchool', 'Corridor', 'corridor')
    assert_equal(0, corridor.people.size)

    load_overrides = [{ space_type: 'corridor',
                        people: { people_per_1000_ft2: 5.0, keep_standard_design_level: true } }]
    assert(@create.space_type_apply_load_overrides(corridor, load_overrides))

    # falls back to setting the occupancy level directly
    assert_equal(1, corridor.people.size)
    assert_in_delta(OpenStudio.convert(5.0 / 1000.0, 'people/ft^2', 'people/m^2').get,
                    corridor.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
    assert_equal(false, corridor.additionalProperties.getFeatureAsDouble('occupancy_peak_override').is_initialized)
  end

  def test_keep_standard_design_level_adjusts_parametric_schedule
    model = OpenStudio::Model::Model.new
    space_type = build_space_type(model, 'Office', 'Conference', 'conference/meeting/multipurpose')
    space_type.additionalProperties.setFeature('schedule_set', 'conference_meeting_multipurpose')

    standard_density_si = space_type.people.first.peopleDefinition.peopleperSpaceFloorArea.get
    standard_per_1000_ft2 = OpenStudio.convert(standard_density_si, 'people/m^2', 'people/ft^2').get * 1000.0
    target = standard_per_1000_ft2 * 0.6
    load_overrides = [{ space_type: 'conference/meeting/multipurpose',
                        people: { people_per_1000_ft2: target, keep_standard_design_level: true } }]
    assert(@create.space_type_apply_load_overrides(space_type, load_overrides))

    # capture the warning about derived schedules in relative base/peak mode
    log_sink = OpenStudio::StringStreamLogSink.new
    log_sink.setLogLevel(OpenStudio::Warn)

    # the parametric schedule application consumes the occupancy_peak_override property;
    # a lighting override in relative base/peak mode follows the occupancy values and warns
    schedule_overrides = [{ space_type: 'conference/meeting/multipurpose', lighting: { base_peak_mode: 'relative' } }]
    assert(OpenstudioStandards::Schedules.space_type_apply_parametric_internal_load_schedules(space_type, schedule_overrides: schedule_overrides))

    occ_sch = space_type.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    day_schedules = [occ_sch.defaultDaySchedule] + occ_sch.scheduleRules.map(&:daySchedule)
    values = day_schedules.flat_map { |day_sch| OpenstudioStandards::Schedules.schedule_day_get_hourly_values(day_sch) }
    assert_in_delta(0.6, values.max, 0.001, 'occupancy schedule peak should match the keep_standard_design_level adjustment')

    warnings = log_sink.logMessages.map(&:logMessage)
    assert(warnings.any? { |w| w.include?("base_peak_mode 'relative'") },
           "expected a warning that relative-mode derived schedules will be adjusted, got: #{warnings}")
  end

  def test_load_overrides_no_match_is_noop
    model = OpenStudio::Model::Model.new
    space_type = build_space_type(model, 'Office', 'Conference', 'conference/meeting/multipurpose')
    original_lpd = space_type.lights.first.lightsDefinition.wattsperSpaceFloorArea.get

    load_overrides = [{ space_type: 'classroom/lecture/training', lighting: { w_per_area: 0.5 } }]
    assert(@create.space_type_apply_load_overrides(space_type, load_overrides))
    assert_in_delta(original_lpd, space_type.lights.first.lightsDefinition.wattsperSpaceFloorArea.get, 0.0001)
  end
end
