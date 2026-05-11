require_relative '../../helpers/minitest_helper'

class TestRefrigerationCreateRefrigerationSystem < Minitest::Test
  def setup
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_create_refrigeration_system
    model = OpenStudio::Model::Model.new
    zone = OpenStudio::Model::ThermalZone.new(model)

    # default case
    case1 = @refrig.create_case(model,
                                template: 'new',
                                case_length:5.0,
                                thermal_zone: zone)

    # old case
    case2 = @refrig.create_case(model,
                                template: 'old',
                                case_length: 30.0,
                                thermal_zone: zone)

    # default refrigeration system
    system1 = @refrig.create_refrigeration_system(model, [case1, case2])
  end
end
