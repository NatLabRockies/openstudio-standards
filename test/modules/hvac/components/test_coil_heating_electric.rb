require_relative '../../../helpers/minitest_helper'

class TestHVACCoilHeatingElectric < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_coil_heating_electric
    model = OpenStudio::Model::Model.new

    coil = @hvac.create_coil_heating_electric(model)
    assert(coil.is_a?(OpenStudio::Model::CoilHeatingElectric), 'Expected coil to be a CoilHeatingElectric object')
  end
end
