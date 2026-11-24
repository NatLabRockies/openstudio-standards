require_relative '../../helpers/minitest_helper'

class TestEquipmentCreate < Minitest::Test
  def setup
    @equip = OpenstudioStandards::Equipment
  end

  def test_create_typical_equipment
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set equipment space types
    std.prototype_space_type_map(model, set_additional_properties: true)
    assert_equal(0, model.getElectricEquipmentDefinitions.size)
    result = @equip.create_typical_equipment(model)
    assert(result)
    assert_equal(11, model.getElectricEquipmentDefinitions.size)
    space_type = model.getSpaceTypeByName('PrimarySchool Kitchen').get
    elec_equip_def = space_type.electricEquipment[0].to_ElectricEquipment.get.electricEquipmentDefinition
    assert_in_delta(OpenStudio.convert(2.2516, 'W/ft^2', 'W/m^2').get, elec_equip_def.wattsperSpaceFloorArea.get, 0.01)
    gas_equip_def = space_type.gasEquipment[0].to_GasEquipment.get.gasEquipmentDefinition
    assert_in_delta(OpenStudio.convert(453.7, 'Btu/hr*ft^2', 'W/m^2').get, gas_equip_def.wattsperSpaceFloorArea.get, 0.01)
  end

  def test_create_typical_equipment_uses_median_when_building_type_is_unmatched
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Custom Space Type')
    space_type.setStandardsBuildingType('CustomBuilding')
    space_type.additionalProperties.setFeature('electric_equipment_space_type', 'sales_electric_equipment')
    space_type.additionalProperties.setFeature('natural_gas_equipment_space_type', 'kitchen')

    assert(@equip.create_typical_equipment(model, building_type_fallback: true))

    electric_definition = space_type.electricEquipment.first.to_ElectricEquipment.get.electricEquipmentDefinition
    gas_definition = space_type.gasEquipment.first.to_GasEquipment.get.gasEquipmentDefinition
    assert_in_delta(OpenStudio.convert(0.356656563, 'W/ft^2', 'W/m^2').get, electric_definition.wattsperSpaceFloorArea.get, 0.01)
    assert_in_delta(OpenStudio.convert(205.81, 'Btu/hr*ft^2', 'W/m^2').get, gas_definition.wattsperSpaceFloorArea.get, 0.01)
  end

  def test_create_typical_equipment_does_not_fallback_by_default
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Custom Space Type')
    space_type.setStandardsBuildingType('CustomBuilding')
    space_type.additionalProperties.setFeature('electric_equipment_space_type', 'sales_electric_equipment')

    assert(@equip.create_typical_equipment(model))
    assert_empty(space_type.electricEquipment)
  end
end
