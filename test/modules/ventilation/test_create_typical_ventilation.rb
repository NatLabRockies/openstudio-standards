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

  def test_every_level_1_ventilation_space_type_has_data
    level_1_path = File.expand_path('../../../lib/openstudio-standards/space_type/data/level_1_space_types.json', __dir__)
    vent_data_path = File.expand_path('../../../lib/openstudio-standards/ventilation/data/ventilation_space_types.json', __dir__)
    level_1_names = JSON.parse(File.read(level_1_path)).map { |r| r['ventilation_space_type_name'] }.compact.uniq
    vent_names = JSON.parse(File.read(vent_data_path)).map { |r| r['ventilation_space_type_name'] }
    missing = level_1_names - vent_names
    assert_empty(missing, "level-1 ventilation space types missing from ventilation data: #{missing}")
  end
end
