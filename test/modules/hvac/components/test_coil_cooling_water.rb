require_relative '../../../helpers/minitest_helper'

class TestHVACCoilCoolingWater < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_coil_cooling_water
    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)

    coil = @hvac.create_coil_cooling_water(model, plant_loop)
    assert(coil.is_a?(OpenStudio::Model::CoilCoolingWater), 'Expected coil to be a CoilCoolingWater object')
  end
end
