require_relative '../../../helpers/minitest_helper'

class TestHVACCoilHeatingWaterToAirHeatPumpEquationFit < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_coil_heating_water_to_air_heat_pump_equation_fit
    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)
    air_loop_node = OpenStudio::Model::Node.new(model)

    coil = @hvac.create_coil_heating_water_to_air_heat_pump_equation_fit(model, plant_loop, air_loop_node: air_loop_node)
    assert(coil.is_a?(OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit), 'Expected coil to be a CoilHeatingWaterToAirHeatPumpEquationFit object')
    assert_equal('Water-to-Air HP Htg Coil', coil.name.to_s, "Expected coil name to be 'Water-to-Air HP Htg Coil'")
  end

  def test_coil_heating_water_to_air_heat_pump_equation_fit_get_capacity
    model = OpenStudio::Model::Model.new
    plant_loop = OpenStudio::Model::PlantLoop.new(model)
    air_loop_node = OpenStudio::Model::Node.new(model)

    coil = @hvac.create_coil_heating_water_to_air_heat_pump_equation_fit(model, plant_loop, air_loop_node: air_loop_node)

    # Set a nominal capacity for the coil
    coil.setRatedHeatingCapacity(10000.0) # W

    # Get the capacity using the helper method
    capacity = @hvac.coil_heating_water_to_air_heat_pump_equation_fit_get_capacity(coil)

    assert_in_delta(10000.0, capacity, 0.01, 'Expected coil capacity to be 10000 W')
  end
end
