require_relative '../../../helpers/minitest_helper'

class TestHVACChiller < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_chiller_electric_get_capacity
    model = OpenStudio::Model::Model.new
    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)

    # Set a reference capacity for the chiller
    chiller.setReferenceCapacity(10000.0) # W

    # Get the capacity using the helper method
    capacity = @hvac.chiller_electric_get_capacity(chiller)

    assert_in_delta(10000.0, capacity, 0.01, 'Expected chiller capacity to be 10000 W')
  end
end
