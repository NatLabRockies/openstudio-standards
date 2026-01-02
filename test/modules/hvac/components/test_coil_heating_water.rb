require_relative '../../../helpers/minitest_helper'

class TestHVACCoilHeatingWater < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_coil_heating_water
    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)

    coil = @hvac.create_coil_heating_water(model, plant_loop)
    assert(coil.is_a?(OpenStudio::Model::CoilHeatingWater), 'Expected coil to be a CoilHeatingWater object')
  end
end
