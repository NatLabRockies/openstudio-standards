require_relative '../../helpers/minitest_helper'

class TestVentilationCreateTypical < Minitest::Test
  def setup
    @vent = OpenstudioStandards::Ventilation
  end

  def test_create_typical_ventilation
    model = OpenStudio::Model::Model.new

    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')

    classroom = OpenStudio::Model::SpaceType.new(model)
    classroom.setName('classroom/lecture/training')
    classroom.setStandardsSpaceType('classroom/lecture/training')

    patient_room = OpenStudio::Model::SpaceType.new(model)
    patient_room.setName('patient room')
    patient_room.setStandardsSpaceType('patient room')

    no_property = OpenStudio::Model::SpaceType.new(model)
    no_property.setName('no ventilation property')

    # resolve the ventilation_space_type additional properties from the standards space type
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    result = @vent.create_typical_ventilation(model)
    assert_equal(3, result.size)

    # office: ASHRAE 62.1 office space rates, 5 cfm/person + 0.06 cfm/ft^2
    dsoa = office.designSpecificationOutdoorAir
    assert(dsoa.is_initialized)
    dsoa = dsoa.get
    assert_equal('Sum', dsoa.outdoorAirMethod)
    assert_in_delta(OpenStudio.convert(5.0, 'ft^3/min', 'm^3/s').get, dsoa.outdoorAirFlowperPerson, 0.0001)
    assert_in_delta(OpenStudio.convert(0.06, 'ft^3/min*ft^2', 'm^3/s*m^2').get, dsoa.outdoorAirFlowperFloorArea, 0.0001)
    assert_in_delta(0.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)

    # classroom: 10 cfm/person + 0.12 cfm/ft^2
    dsoa = classroom.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(10.0, 'ft^3/min', 'm^3/s').get, dsoa.outdoorAirFlowperPerson, 0.0001)
    assert_in_delta(OpenStudio.convert(0.12, 'ft^3/min*ft^2', 'm^3/s*m^2').get, dsoa.outdoorAirFlowperFloorArea, 0.0001)

    # patient room: ASHRAE 170 air-change based rate
    dsoa = patient_room.designSpecificationOutdoorAir.get
    assert_in_delta(0.0, dsoa.outdoorAirFlowperPerson, 0.0001)
    assert_in_delta(2.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
    vent_std = dsoa.additionalProperties.getFeatureAsString('ventilation_standard')
    assert(vent_std.is_initialized)
    assert_equal('ASHRAE 170-2021', vent_std.get)

    # space type without the property is skipped
    assert_equal(false, no_property.designSpecificationOutdoorAir.is_initialized)
  end

  def test_create_typical_ventilation_overwrites_existing
    model = OpenStudio::Model::Model.new
    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    existing = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
    existing.setOutdoorAirFlowAirChangesperHour(9.0)
    office.setDesignSpecificationOutdoorAir(existing)

    @vent.create_typical_ventilation(model)
    dsoa = office.designSpecificationOutdoorAir.get
    assert_in_delta(0.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001, 'stale ACH value should be overwritten')
    assert_in_delta(OpenStudio.convert(5.0, 'ft^3/min', 'm^3/s').get, dsoa.outdoorAirFlowperPerson, 0.0001)
  end

  def test_create_typical_ventilation_from_template
    model = OpenStudio::Model::Model.new

    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')

    patient_room = OpenStudio::Model::SpaceType.new(model)
    patient_room.setName('patient room')
    patient_room.setStandardsSpaceType('patient room')

    # no standards space type mapping; falls back to the typical ventilation data
    banking = OpenStudio::Model::SpaceType.new(model)
    banking.setName('banking')
    banking.setStandardsSpaceType('banking')

    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    result = @vent.create_typical_ventilation(model, template: '90.1-2013')
    assert_equal(3, result.size)

    # office maps to 90.1-2013 Office | OpenOffice: 5 cfm/person + 0.06 cfm/ft^2
    dsoa = office.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(5.0, 'ft^3/min', 'm^3/s').get, dsoa.outdoorAirFlowperPerson, 0.0001)
    assert_in_delta(OpenStudio.convert(0.06, 'ft^3/min*ft^2', 'm^3/s*m^2').get, dsoa.outdoorAirFlowperFloorArea, 0.0001)
    source = dsoa.additionalProperties.getFeatureAsString('ventilation_source')
    assert(source.is_initialized)
    assert_equal('90.1-2013 Office | OpenOffice', source.get)

    # patient room maps to 90.1-2013 Hospital | PatRoom: 2 air changes per hour
    dsoa = patient_room.designSpecificationOutdoorAir.get
    assert_in_delta(2.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
    assert_in_delta(0.0, dsoa.outdoorAirFlowperPerson, 0.0001)

    # banking has no mapping and falls back to the typical 62.1 rates
    dsoa = banking.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(7.5, 'ft^3/min', 'm^3/s').get, dsoa.outdoorAirFlowperPerson, 0.0001)
    source = dsoa.additionalProperties.getFeatureAsString('ventilation_source')
    assert_equal('banking_ventilation', source.get)
  end

  def test_create_typical_ventilation_from_deer_template
    model = OpenStudio::Model::Model.new

    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')

    patient_room = OpenStudio::Model::SpaceType.new(model)
    patient_room.setName('patient room')
    patient_room.setStandardsSpaceType('patient room')

    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    result = @vent.create_typical_ventilation(model, template: 'DEER 2014')
    assert_equal(2, result.size)

    # office maps to DEER 2014 OfL | OfficeOpen: 0.13 cfm/ft^2
    dsoa = office.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(0.13, 'ft^3/min*ft^2', 'm^3/s*m^2').get, dsoa.outdoorAirFlowperFloorArea, 0.0001)
    assert_in_delta(0.0, dsoa.outdoorAirFlowperPerson, 0.0001)
    source = dsoa.additionalProperties.getFeatureAsString('ventilation_source')
    assert_equal('DEER 2014 OfL | OfficeOpen', source.get)

    # patient room maps to DEER 2014 Hsp | PatientRoom: 0.17 cfm/ft^2
    dsoa = patient_room.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(0.17, 'ft^3/min*ft^2', 'm^3/s*m^2').get, dsoa.outdoorAirFlowperFloorArea, 0.0001)
  end

  def test_create_typical_ventilation_deer_future_vintage
    # DEER vintages after the newest mapped vintage resolve to the newest mapped DEER row
    model = OpenStudio::Model::Model.new
    office = OpenStudio::Model::SpaceType.new(model)
    office.setName('office')
    office.setStandardsSpaceType('office')
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)

    result = @vent.create_typical_ventilation(model, template: 'ComStock DEER 2025')
    assert_equal(1, result.size)
    # resolves through the newest mapped DEER row (DEER 2020, 0.15 cfm/ft^2 for OfL | OfficeOpen)
    dsoa = office.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(0.15, 'ft^3/min*ft^2', 'm^3/s*m^2').get, dsoa.outdoorAirFlowperFloorArea, 0.0001)
    source = dsoa.additionalProperties.getFeatureAsString('ventilation_source')
    assert_equal('ComStock DEER 2025 OfL | OfficeOpen', source.get)
  end

  def test_standards_space_type_map_pairs_exist_in_standards_data
    map_path = File.expand_path('../../../lib/openstudio-standards/space_type/data/level_1_standards_space_type_map.json', __dir__)
    map = JSON.parse(File.read(map_path))
    ['90.1-2013', 'DEER 2014'].each do |template|
      standard = Standard.build(template)
      map.each do |level_1_name, rows|
        row = rows.find { |r| r['template'] == template }
        next if row.nil?

        search_criteria = { 'template' => template, 'building_type' => row['building_type'], 'space_type' => row['space_type'] }
        props = standard.model_find_object(standard.standards_data['space_types'], search_criteria)
        refute_nil(props, "'#{level_1_name}' maps to '#{row['building_type']} | #{row['space_type']}', which is not in the #{template} standards space type data")
      end
    end
  end

  def test_every_level_1_ventilation_space_type_has_data
    level_1_path = File.expand_path('../../../lib/openstudio-standards/space_type/data/level_1_space_types.json', __dir__)
    vent_data_path = File.expand_path('../../../lib/openstudio-standards/ventilation/data/ventilation_space_types.json', __dir__)
    level_1_names = JSON.parse(File.read(level_1_path)).map { |r| r['ventilation_space_type_name'] }.compact.uniq
    vent_names = JSON.parse(File.read(vent_data_path)).map { |r| r['ventilation_space_type_name'] }
    missing = level_1_names - vent_names
    assert_empty(missing, "level-1 ventilation space types missing from ventilation data: #{missing}")
  end
end
