require_relative '../../helpers/minitest_helper'

class TestInteriorLightingCreate < Minitest::Test
  def setup
    @int = OpenstudioStandards::InteriorLighting
  end

  def test_create_lights
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.new(model)

    @int.create_lights(model,
                       name: 'test lights',
                       lighting_power: 5.0,
                       lighting_power_type: 'Watts/Area',
                       space: space)

    assert_equal(1, model.getLightss.size)
    added_lights = model.getLightss[0]
    assert_equal('test lights', added_lights.name.to_s)
    assert_in_delta(5.0, added_lights.lightsDefinition.wattsperSpaceFloorArea.get, 0.001)
  end

  def test_create_typical_interior_lighting
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set lighting space types
    std.prototype_space_type_map(model, set_additional_properties: true)
    result = @int.create_typical_interior_lighting(model, lighting_generation: 'gen4_led')
    assert(11, result.size)
    space_type = model.getSpaceTypeByName('PrimarySchool Cafeteria').get
    space_type_floor_area = space_type.floorArea
    space_type_number_of_people = space_type.getNumberOfPeople(space_type_floor_area)
    ending_space_type_lighting_power = space_type.getLightingPower(space_type_floor_area, space_type_number_of_people)
    puts "space_type_floor_area = #{space_type_floor_area}"
    puts "space_type_number_of_people = #{space_type_number_of_people}"
    puts "ending_space_type_lighting_power = #{ending_space_type_lighting_power}"
  end
end