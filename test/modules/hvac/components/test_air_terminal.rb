require_relative '../../../helpers/minitest_helper'

class TestHVACAirTerminal < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_air_terminal_single_duct_vav_reheat_reheat_type
    model = OpenStudio::Model::Model.new

    # Add an electric reheat coil
    electric_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    air_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, electric_coil)
    assert_equal('Electricity', @hvac.air_terminal_single_duct_vav_reheat_reheat_type(air_terminal), 'Expected reheat type to be Electricity')

    # Add a hot water reheat coil
    hot_water_coil = OpenStudio::Model::CoilHeatingWater.new(model)
    air_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, hot_water_coil)
    assert_equal('HotWater', @hvac.air_terminal_single_duct_vav_reheat_reheat_type(air_terminal), 'Expected reheat type to be HotWater')

    # Add a natural gas reheat coil
    natural_gas_coil = OpenStudio::Model::CoilHeatingGas.new(model)
    air_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, natural_gas_coil)
    assert_equal('NaturalGas', @hvac.air_terminal_single_duct_vav_reheat_reheat_type(air_terminal), 'Expected reheat type to be NaturalGas')
  end
end
