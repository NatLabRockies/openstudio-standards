require_relative '../../helpers/minitest_helper'

class TestScheduleCompatibility < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
    @model = OpenStudio::Model::Model.new
    @model.getTimestep.setNumberOfTimestepsPerHour(4)
    @data_dir = "#{__dir__}/../../../lib/openstudio-standards/schedules/data"
  end

  def test_legacy_load_schedule_call
    profiles = JSON.parse(File.read("#{@data_dir}/default_parametric_schedules.json"), symbolize_names: true)
    direct = @sch.resolve_load_schedule(@model, profiles, 'parking interior lighting', 'Lighting',
                                        "#{@data_dir}/default_lighting_parameters.json", nil, {}, {})
    refute_nil(direct)
    occupancy = @sch.create_parametric_schedule_full(@model, profiles, 'office occupancy', {}, category: 'Occupancy')
    derived = @sch.resolve_load_schedule(@model, profiles, 'office open lighting', 'Lighting',
                                         "#{@data_dir}/default_lighting_parameters.json", occupancy, {}, {},
                                         { base: 0.1, peak: 0.6, derivation_type: 'linear', response: 1.0 })
    refute_nil(derived)
    values = @sch.schedule_day_get_hourly_values(derived.defaultDaySchedule)
    assert_operator(values.min, :>=, 0.1)
    assert_operator(values.max, :<=, 0.6)
    occupancy_values = @sch.schedule_day_get_hourly_values(occupancy.defaultDaySchedule)
    occupancy_values.zip(values).each do |presence, value|
      assert_in_delta(0.1 + (0.5 * presence), value, 0.0001, 'legacy calls retain relative occupancy scaling')
    end
  end

  def test_legacy_and_new_schedule_set_names
    %w[office_open].concat(['office schedule set']).each do |name|
      space_type = OpenStudio::Model::SpaceType.new(@model)
      space_type.additionalProperties.setFeature('schedule_set', name)
      assert(@sch.space_type_apply_parametric_internal_load_schedules(space_type), name)
      defaults = space_type.defaultScheduleSet.get
      assert(defaults.numberofPeopleSchedule.is_initialized, name)
      assert(defaults.lightingSchedule.is_initialized, name)
      assert(defaults.electricEquipmentSchedule.is_initialized, name)
    end
  end

  def test_catalog_schedule_references_preserve_existing_gap
    path = "#{__dir__}/../../../lib/openstudio-standards/space_type/data/space_types.json"
    catalog = JSON.parse(File.read(path))
    sets = JSON.parse(File.read("#{@data_dir}/default_parametric_schedule_set.json"))
    names = sets.map { |row| row.fetch('schedule_set_name') }
    unresolved = catalog.map { |row| row.fetch('schedule_set_name') }.uniq - names
    assert_equal(['guest_room_vacant'], unresolved)
  end

  def test_legacy_building_specific_set
    space_type = OpenStudio::Model::SpaceType.new(@model)
    space_type.setStandardsBuildingType('PrimarySchool')
    space_type.additionalProperties.setFeature('schedule_set', 'kitchen')
    assert(@sch.space_type_apply_parametric_internal_load_schedules(space_type))
    expected = JSON.parse(File.read("#{@data_dir}/default_parametric_schedule_set.json")).find do |row|
      row['schedule_set_name'] == 'kitchen' && row['standards_building_type'] == 'PrimarySchool'
    end
    refute_nil(expected)
    assert_equal(expected.fetch('occupancy_schedule'), space_type.defaultScheduleSet.get.numberofPeopleSchedule.get.name.to_s)
  end

  def test_all_schedule_sets_are_usable
    sets = JSON.parse(File.read("#{@data_dir}/default_parametric_schedule_set.json"))
    sets.each do |row|
      model = OpenStudio::Model::Model.new
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.additionalProperties.setFeature('schedule_set', row.fetch('schedule_set_name'))
      space_type.setStandardsBuildingType(row['standards_building_type']) unless row['standards_building_type'].nil?
      assert(@sch.space_type_apply_parametric_internal_load_schedules(space_type), row.inspect)
    end
  end

  def test_null_slots_preserve_legacy_loads_and_respect_flags
    [
      ['parking_area_interior', true, 2],
      ['restroom schedule set', true, 0],
      ['restroom schedule set', false, 2]
    ].each do |name, enabled, expected_count|
      space_type = OpenStudio::Model::SpaceType.new(@model)
      space_type.additionalProperties.setFeature('schedule_set', name)
      space = OpenStudio::Model::Space.new(@model)
      space.setSpaceType(space_type)
      [space_type, space].each do |parent|
        people = OpenStudio::Model::People.new(OpenStudio::Model::PeopleDefinition.new(@model))
        gas = OpenStudio::Model::GasEquipment.new(OpenStudio::Model::GasEquipmentDefinition.new(@model))
        if parent == space_type
          people.setSpaceType(parent)
          gas.setSpaceType(parent)
        else
          people.setSpace(parent)
          gas.setSpace(parent)
        end
      end
      assert(@sch.space_type_apply_parametric_internal_load_schedules(
        space_type, set_people: enabled, set_gas_equipment: enabled
      ), name)
      assert_equal(expected_count, space_type.people.size + space.people.size, name)
      assert_equal(expected_count, space_type.gasEquipment.size + space.gasEquipment.size, name)
    end
  end

  def test_legacy_schedule_override_matching
    result = @sch.resolve_schedule_overrides([
      { space_type: '*', lighting: { base: 0.1, peak: 0.8 } },
      { schedule_set: 'office_open', lighting: { peak: 0.5 } }
    ], 'office_open', 'office')
    assert_equal({ lighting: { base: 0.1, peak: 0.5 } }, result)
  end

  def test_invalid_named_schedule_reports_failure
    space_type = OpenStudio::Model::SpaceType.new(@model)
    space_type.additionalProperties.setFeature('schedule_set', 'office schedule set')
    overrides = [{ space_type: '*', occupancy: { schedule: 'missing occupancy profile' } }]
    refute(@sch.space_type_apply_parametric_internal_load_schedules(space_type, schedule_overrides: overrides))
  end

  def test_ventilation_space_type_override_matching
    result = @sch.resolve_schedule_overrides([
      { space_type: '*', lighting: { base: 0.1 } },
      { ventilation_space_type: 'office', lighting: { peak: 0.5 } }
    ], 'office schedule set', 'office_open', extra_match_keys: ['office'])
    assert_equal({ lighting: { base: 0.1, peak: 0.5 } }, result)
  end

  def test_relative_load_warning_with_legacy_and_new_sets
    ['office_open', 'office schedule set'].each do |name|
      space_type = OpenStudio::Model::SpaceType.new(@model)
      space_type.additionalProperties.setFeature('schedule_set', name)
      space_type.additionalProperties.setFeature('occupancy_peak_override', 0.4)
      log = OpenStudio::StringStreamLogSink.new
      log.setLogLevel(OpenStudio::Warn)
      overrides = [{ space_type: '*', lighting: { base_peak_mode: 'relative' } }]
      assert(@sch.space_type_apply_parametric_internal_load_schedules(space_type, schedule_overrides: overrides))
      assert(log.logMessages.any? { |message| message.logMessage.include?("uses base_peak_mode 'relative'") }, name)
    end
  end
end
