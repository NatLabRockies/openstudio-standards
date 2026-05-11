require_relative '../../helpers/minitest_helper'

class TestRefrigerationCreateTypicalRefrigeration < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_typical_refrigeration_equipment_list_supermarket
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # equipment list
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(8, result[:cases].size)
    assert_equal(14, result[:walkins].size)
  end

  def test_typical_refrigeration_equipment_list_secondary_school
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SecondarySchool'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # equipment list
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(0, result[:cases].size)
    assert_equal(2, result[:walkins].size)
  end

  def test_typical_refrigeration_equipment_list_deer_ese
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'ESe'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # equipment list
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(0, result[:cases].size)
    assert_equal(2, result[:walkins].size)
  end

  def test_create_typical_refrigeration_supermarket
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # default refrigeration system
    result = @refrig.create_typical_refrigeration(model)
    assert(result)
  end

  def test_create_typical_refrigeration_small_supermarket
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 5000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # default refrigeration system
    result = @refrig.create_typical_refrigeration(model)
    assert(result)
    model.save('output/small_supermarket.osm', true)
  end

  def test_create_typical_refrigeration_primary_school
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'PrimarySchool'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # default refrigeration system
    result = @refrig.create_typical_refrigeration(model)
    assert(result)
  end
end
