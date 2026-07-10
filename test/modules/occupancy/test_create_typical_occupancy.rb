require_relative '../../helpers/minitest_helper'

class TestOccupancyCreateTypical < Minitest::Test
  def setup
    @occ = OpenstudioStandards::Occupancy
  end

  def test_create_typical_occupancy
    model = OpenStudio::Model::Model.new

    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')

    # no standards space type mapping; gets no occupancy
    banking = OpenStudio::Model::SpaceType.new(model)
    banking.setName('banking')
    banking.setStandardsSpaceType('banking')

    # plenums are skipped
    plenum = OpenStudio::Model::SpaceType.new(model)
    plenum.setName('plenum')
    plenum.setStandardsSpaceType('plenum')

    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    template = '90.1-2013'
    result = @occ.create_typical_occupancy(model, template: template)
    assert_equal(1, result.size)

    # office density matches the mapped standards space type occupancy for the template
    standard = Standard.build(template)
    expected = standard.model_find_object(standard.standards_data['space_types'],
                                          'template' => template, 'building_type' => 'Office', 'space_type' => 'OpenOffice')
    refute_nil(expected)
    expected_si = OpenStudio.convert(expected['occupancy_per_area'].to_f / 1000.0, 'people/ft^2', 'people/m^2').get
    assert_equal(1, office.people.size)
    people_def = office.people.first.peopleDefinition
    assert_in_delta(expected_si, people_def.peopleperSpaceFloorArea.get, 0.0001)
    source = people_def.additionalProperties.getFeatureAsString('occupancy_source')
    assert(source.is_initialized)
    assert_equal('90.1-2013 Office | OpenOffice', source.get)

    assert_equal(0, banking.people.size, 'unmapped space type should get no occupancy')
    assert_equal(0, plenum.people.size, 'plenum should get no occupancy')
  end

  def test_create_typical_occupancy_replaces_existing
    model = OpenStudio::Model::Model.new
    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    stale_definition = OpenStudio::Model::PeopleDefinition.new(model)
    stale_definition.setPeopleperSpaceFloorArea(9.9)
    stale = OpenStudio::Model::People.new(stale_definition)
    stale.setSpaceType(office)

    @occ.create_typical_occupancy(model, template: '90.1-2013')
    assert_equal(1, office.people.size, 'stale people should be replaced, not accumulated')
    refute_in_delta(9.9, office.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)
  end

  def test_create_typical_occupancy_requires_template
    model = OpenStudio::Model::Model.new
    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')

    assert_empty(@occ.create_typical_occupancy(model))
    assert_empty(@occ.create_typical_occupancy(model, template: 'not-a-template'))
    assert_equal(0, office.people.size)
  end
end
