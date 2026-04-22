require_relative '../helpers/minitest_helper'

class TestSpaceType < Minitest::Test
  def test_apply_internal_loads
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/models/basic_2_story_office_no_hvac_20WWR_data_center.osm")

    data_center_space_type = model.getSpaceTypeByName('Data Center').get
    value = std.space_type_apply_internal_loads(data_center_space_type)
    assert(!value.nil?)
  end

  def test_apply_internal_loads_grocery
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 45000.0
    args['bldg_type_a'] = 'SuperMarket'
    args['bar_division_method'] = 'Multiple Space Types - Simple Sliced'
    result = OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(model, args)
    sales_space_type = model.getSpaceTypeByName('SuperMarket Sales').get
    std = Standard.build('90.1-2013')
    value = std.space_type_apply_internal_loads(sales_space_type)
    assert(!value.nil?)

    total_latent_load = 0.0
    model.getOtherEquipmentDefinitions.each do |equip|
      total_latent_load += equip.designLevel.get
    end
    assert_in_delta(10_000.0, total_latent_load, 1.0)
  end
end
