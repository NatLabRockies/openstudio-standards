require_relative '../../../helpers/minitest_helper'

class TestHVACCoilCoolingDXMultiSpeed < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_coil_cooling_dx_multi_speed_get_capacity
    model = OpenStudio::Model::Model.new
    coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
    stage = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    stage.setGrossRatedTotalCoolingCapacity(10000.0) # Set a nominal capacity for the stage
    coil.addStage(stage)

    # Get the capacity using the helper method
    capacity = @hvac.coil_cooling_dx_multi_speed_get_capacity(coil)

    assert_in_delta(10000.0, capacity, 0.01, 'Expected coil capacity to be 10000 W')
  end
end
