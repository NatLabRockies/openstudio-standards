require_relative '../helpers/minitest_helper'

class TestServiceWaterHeating < Minitest::Test
  def test_water_heater_sub_type
    std = Standard.build('90.1-2019')

    # Gas water heaters
    assert(std.water_heater_determine_sub_type('NaturalGas', 74000, 5) == "residential_duty")
    assert(std.water_heater_determine_sub_type('NaturalGas', 74000, 20) == "consumer_storage")
    assert(std.water_heater_determine_sub_type('NaturalGas', 76000, 5) == "residential_duty")

    # Electricity water heaters
    assert(std.water_heater_determine_sub_type('Electricity', 74000, 5).nil?)
    assert(std.water_heater_determine_sub_type('Electricity', 74000, 2) == "residential_duty")
    assert(std.water_heater_determine_sub_type('Electricity', 300000, 2) == "instantaneous")
  end

  def test_uef_to_ef()
    std = Standard.build('90.1-2019')
    model = OpenStudio::Model::Model.new
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    assert(std.water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater, 'Electricity', 1, 1, 1) == 1.0194)
    assert(std.water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater, 'Electricity', 1, 300000, 2) == 1)
    assert(std.water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater, 'Electricity', 0, 74000, 2) == -0.0025)
    assert(std.water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater, 'NaturalGas', 0, 76000, 5) == 0.0019)
    assert(std.water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater, 'NaturalGas', 0, 74000, 20) == 0.0711)
  end
end
