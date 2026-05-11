require_relative '../../helpers/minitest_helper'

class TestRefrigerationCreateWalkIn < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_create_walkin
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)
    zone = model.getThermalZoneByName('Zone SuperMarket Sales A  - Story ground').get

    # default walkin
    walkin1 = @refrig.create_walkin(model)

    # old walkin
    walkin2 = @refrig.create_walkin(model,
                                    template: 'old',
                                    thermal_zone: zone)

    # new walkin
    walkin3 = @refrig.create_walkin(model,
                                    template: 'new',
                                    walkin_type: 'Walk-in Freezer - 480SF',
                                    thermal_zone: zone)

    # advanced walkin
    walkin4 = @refrig.create_walkin(model,
                                    template: 'advanced',
                                    walkin_type: 'Walk-in Freezer - 240SF',
                                    thermal_zone: zone)
  end
end
