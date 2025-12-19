require_relative '../../../helpers/minitest_helper'

class TestHVACCoilCoolingDXSingleSpeed < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_coil_cooling_dx_single_speed
    model = OpenStudio::Model::Model.new

    coil = @hvac.create_coil_cooling_dx_single_speed(model)
    assert(coil.is_a?(OpenStudio::Model::CoilCoolingDXSingleSpeed), 'Expected coil to be a CoilCoolingDXSingleSpeed object')
  end

  def test_coil_cooling_dx_single_speed_get_capacity
    model = OpenStudio::Model::Model.new
    coil = @hvac.create_coil_cooling_dx_single_speed(model)

    # Set a nominal capacity for the coil
    coil.setRatedTotalCoolingCapacity(10000.0) # W

    # Get the capacity using the helper method
    capacity = @hvac.coil_cooling_dx_single_speed_get_capacity(coil)

    assert_in_delta(10000.0, capacity, 0.01, 'Expected coil capacity to be 10000 W')
  end
end
