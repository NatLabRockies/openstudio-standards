require_relative '../../helpers/minitest_helper'

class TestRefrigerationInformation < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_refrigeration_case_zone
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # get case zone
    zone = @refrig.refrigeration_case_zone(model)
    assert_equal('Zone SuperMarket Sales B  - Story ground', zone.name.to_s)
  end

  def test_refrigeration_walkin_zone
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # get case zone
    zone = @refrig.refrigeration_walkin_zone(model)
    assert_equal('Zone SuperMarket DryStorage B  - Story ground', zone.name.to_s)
  end
end
