require_relative '../../../helpers/minitest_helper'

class TestHVACCoilHeatingGas < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_coil_heating_gas
    model = OpenStudio::Model::Model.new

    coil = @hvac.create_coil_heating_gas(model)
    assert(coil.is_a?(OpenStudio::Model::CoilHeatingGas), 'Expected coil to be a CoilHeatingGas object')
  end

  def test_coil_heating_gas_get_capacity
    model = OpenStudio::Model::Model.new
    coil = @hvac.create_coil_heating_gas(model)

    # Set a nominal capacity for the coil
    coil.setNominalCapacity(10000.0) # W

    # Get the capacity using the helper method
    capacity = @hvac.coil_heating_gas_get_capacity(coil)

    assert_in_delta(10000.0, capacity, 0.01, 'Expected coil capacity to be 10000 W')
  end
end
