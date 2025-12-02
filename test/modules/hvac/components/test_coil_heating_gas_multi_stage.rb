require_relative '../../../helpers/minitest_helper'

class TestHVACCoilHeatingGasMultiStage < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_coil_heating_gas_multi_stage_get_capacity
    model = OpenStudio::Model::Model.new
    coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
    stage = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
    stage.setNominalCapacity(10000.0) # Set a nominal capacity for the stage
    coil.addStage(stage)

    # Get the capacity using the helper method
    capacity = @hvac.coil_heating_gas_multi_stage_get_capacity(coil)

    assert_in_delta(10000.0, capacity, 0.01, 'Expected coil capacity to be 10000 W')
  end
end
