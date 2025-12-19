require_relative '../../helpers/minitest_helper'

class TestRefrigerationCreateCompressorRack < Minitest::Test
  def setup
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_create_compressor_rack
    model = OpenStudio::Model::Model.new
    zone = OpenStudio::Model::ThermalZone.new(model)

    # default case
    case1 = @refrig.create_case(model,
                                thermal_zone: zone)

    # default compressor rack
    system1 = @refrig.create_compressor_rack(model, case1)
  end
end
