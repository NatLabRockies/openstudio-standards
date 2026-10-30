require_relative '../../helpers/minitest_helper'

class TestOccupancyCreateTypical < Minitest::Test
  def setup
    @occ = OpenstudioStandards::Occupancy
    data_path = File.expand_path('../../../lib/openstudio-standards/occupancy/data/typical_space_type_occupancy.json', __dir__)
    @occupancy_data = JSON.parse(File.read(data_path))
  end

  def expected_people_per_m2(ventilation_space_type_name, template)
    entry = @occupancy_data.fetch(ventilation_space_type_name).find { |e| e['templates'].include?(template) }
    refute_nil(entry, "no occupancy entry for '#{ventilation_space_type_name}' covering '#{template}'")
    OpenStudio.convert(entry['occupancy_per_area'].to_f / 1000.0, 'people/ft^2', 'people/m^2').get
  end

  def model_with(*space_type_names)
    model = OpenStudio::Model::Model.new
    space_type_names.each do |name|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName(name)
      space_type.setStandardsSpaceType(name)
    end
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)
    model
  end

  def space_type(model, name)
    model.getSpaceTypes.find { |st| st.name.get == name }
  end

  def test_create_typical_occupancy
    model = model_with('office', 'attic', 'plenum')
    # added after the properties are resolved, so it carries no ventilation_space_type at all
    unknown = OpenStudio::Model::SpaceType.new(model)
    unknown.setName('unknown')

    result = @occ.create_typical_occupancy(model, template: '90.1-2019')
    assert_equal(1, result.size)

    office = space_type(model, 'office')
    assert_equal(1, office.people.size)
    people_def = office.people.first.peopleDefinition
    assert_in_delta(expected_people_per_m2('office_ventilation', '90.1-2019'), people_def.peopleperSpaceFloorArea.get, 0.0001)
    source = people_def.additionalProperties.getFeatureAsString('occupancy_source')
    assert(source.is_initialized)
    assert_includes(source.get, 'ASHRAE 62.1', 'the source should name where the density came from')

    assert_equal(0, unknown.people.size, 'space type without a ventilation space type should get no occupancy')
    assert_equal(0, space_type(model, 'attic').people.size, 'zero-occupancy space type should get no occupancy')
    assert_equal(0, space_type(model, 'plenum').people.size, 'plenum should get no occupancy')
  end

  def test_create_typical_occupancy_template_selection
    model = model_with('office')
    office = space_type(model, 'office')

    @occ.create_typical_occupancy(model, template: '90.1-2013')
    assert_in_delta(expected_people_per_m2('office_ventilation', '90.1-2013'),
                    office.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)

    # a DEER template reads the DEER entry, not a 90.1 one
    @occ.create_typical_occupancy(model, template: 'ComStock DEER 2014')
    assert_in_delta(expected_people_per_m2('office_ventilation', 'ComStock DEER 2014'),
                    office.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)

    # a nil template takes the newest 90.1 entry
    result = @occ.create_typical_occupancy(model)
    assert_equal(1, result.size)
    assert_in_delta(expected_people_per_m2('office_ventilation', '90.1-2019'),
                    office.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  def test_create_typical_occupancy_replaces_existing
    model = model_with('office')
    office = space_type(model, 'office')

    stale_definition = OpenStudio::Model::PeopleDefinition.new(model)
    stale_definition.setPeopleperSpaceFloorArea(9.9)
    stale = OpenStudio::Model::People.new(stale_definition)
    stale.setSpaceType(office)

    @occ.create_typical_occupancy(model, template: '90.1-2019')
    assert_equal(1, office.people.size, 'stale people should be replaced, not accumulated')
    refute_in_delta(9.9, office.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  def test_occupancy_overrides
    model = model_with('office', 'laboratory')
    @occ.create_typical_occupancy(
      model, template: '90.1-2013',
      occupancy_overrides: [{ space_type: 'laboratory_ventilation', occupancy: { people_per_1000_ft2: 3.0 } }]
    )
    lab_def = space_type(model, 'laboratory').people.first.peopleDefinition
    assert_in_delta(OpenStudio.convert(3.0 / 1000.0, 'people/ft^2', 'people/m^2').get,
                    lab_def.peopleperSpaceFloorArea.get, 0.0001)
    assert_includes(lab_def.additionalProperties.getFeatureAsString('occupancy_source').get, 'override')

    # an unmatched space type keeps its data density
    assert_in_delta(expected_people_per_m2('office_ventilation', '90.1-2013'),
                    space_type(model, 'office').people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  def test_occupancy_overrides_wildcard_and_string_keys
    model = model_with('office', 'laboratory')
    @occ.create_typical_occupancy(
      model, template: '90.1-2013',
      occupancy_overrides: [{ 'space_type' => '*', 'occupancy' => { 'people_per_1000_ft2' => 7.0 } },
                            { 'space_type' => 'office', 'occupancy' => { 'people_per_1000_ft2' => 1.0 } }]
    )
    expected = ->(density) { OpenStudio.convert(density / 1000.0, 'people/ft^2', 'people/m^2').get }
    assert_in_delta(expected.call(1.0), space_type(model, 'office').people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
    assert_in_delta(expected.call(7.0), space_type(model, 'laboratory').people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  # an override occupies a space type the data gives no density for
  def test_occupancy_override_applies_without_data
    model = model_with('attic')
    @occ.create_typical_occupancy(
      model, template: '90.1-2013',
      occupancy_overrides: [{ space_type: 'attic', occupancy: { people_per_1000_ft2: 2.0 } }]
    )
    attic = space_type(model, 'attic')
    assert_equal(1, attic.people.size, 'an override should apply even where the data has no density')
    assert_in_delta(OpenStudio.convert(2.0 / 1000.0, 'people/ft^2', 'people/m^2').get,
                    attic.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  def test_every_all_level_ventilation_space_type_has_occupancy_data
    all_level_path = File.expand_path('../../../lib/openstudio-standards/space_type/data/all_level_space_types.json', __dir__)
    names = JSON.parse(File.read(all_level_path)).map { |r| r['ventilation_space_type_name'] }.compact.uniq - ['na']
    missing = names - @occupancy_data.keys
    assert_empty(missing, "all-level ventilation space types missing from the occupancy data: #{missing}")
  end
end
