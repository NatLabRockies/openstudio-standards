require_relative '../../helpers/minitest_helper'

class TestRefrigerationCreateCase < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_create_case
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    args['bar_division_method'] = 'Multiple Space Types - Simple Sliced'
    result = @geo.create_bar_from_building_type_ratios(model, args)
    zone = model.getThermalZoneByName('Zone SuperMarket Sales A  - Story ground').get

    # default case
    case1 = @refrig.create_case(model)
    assert_equal(2.4, case1.caseLength)
    assert_in_delta(0.6, case1.caseOperatingTemperature, 0.1)

    # old case
    case2 = @refrig.create_case(model,
                                template: 'old',
                                thermal_zone: zone)
    assert_equal(2.4, case2.caseLength)
    assert_in_delta(0.6, case2.caseOperatingTemperature, 0.1)

    # advanced case
    case3 = @refrig.create_case(model,
                                template: 'advanced',
                                case_type: 'Coffin - Frozen Food',
                                thermal_zone: zone)
    assert_equal(2.2, case3.caseLength)
    assert_in_delta(-23.3, case3.caseOperatingTemperature, 0.1)

    # new case with long defrost
    case4 = @refrig.create_case(model,
                                template: 'new',
                                case_type: 'Coffin - Ice Cream',
                                thermal_zone: zone)
    assert_equal(2.0, case4.caseLength)
    assert_in_delta(-28.3, case4.caseOperatingTemperature, 0.1)
  end
end
