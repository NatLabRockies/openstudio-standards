require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# Component Tests for DHW (Domestic Hot Water) Systems
# Tests the creation, configuration, and integration of DHW systems in NECB models
#
# Methods tested:
# - NECB2011#water_heater_mixed_apply_efficiency - Apply efficiency standards to water heaters
# - OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop - Create DHW loop
# - OpenstudioStandards::ServiceWaterHeating.create_water_heater - Create water heater
#
# References:
# - NECB 2011/2015/2020 Service Water Heating Requirements
# - PNNL Service Water Heating Appendix A
class TestDhwSystems < Minitest::Test
  def test_necb2011_gas_water_heater_small_capacity_efficiency

    # Test gas water heater efficiency for small units (<= 75,000 Btu/hr)
    # Should use residential efficiency equation with fixed 82% efficiency
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Create small gas water heater
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setName('Test Small Gas Water Heater')
    water_heater.setHeaterMaximumCapacity(20000.0)  # ~68,000 Btu/hr (< 75k threshold)
    water_heater.setTankVolume(0.1514)  # 40 gallons
    water_heater.setHeaterFuelType('NaturalGas')

    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "Efficiency application should succeed"

    thermal_eff = water_heater.heaterThermalEfficiency.get
    assert_in_delta 0.82, thermal_eff, 0.01,
      "Small gas water heater should have 82% thermal efficiency per NECB 2011"
  end

  def test_necb2011_gas_water_heater_large_capacity_efficiency

    # Test gas water heater efficiency for large units (> 75,000 Btu/hr)
    # Should use commercial efficiency equation with 80% minimum efficiency
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Create large gas water heater
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setName('Test Large Gas Water Heater')
    water_heater.setHeaterMaximumCapacity(30000.0)  # ~102,000 Btu/hr (> 75k threshold)
    water_heater.setTankVolume(0.3785)  # 100 gallons
    water_heater.setHeaterFuelType('NaturalGas')

    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "Efficiency application should succeed"

    thermal_eff = water_heater.heaterThermalEfficiency.get
    assert thermal_eff >= 0.78, "Large gas water heater should have >= 78% efficiency"
    assert thermal_eff <= 0.85, "Large gas water heater efficiency should be <= 85%"
  end

  def test_necb2020_gas_water_heater_small_uef_based

    # Test NECB 2020 gas water heater with UEF-based efficiency
    # NECB 2020 uses Uniform Energy Factor methodology
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2020')

    # Small gas water heater (<=22kW, 76-208L volume)
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setHeaterMaximumCapacity(18000.0)  # 18 kW
    water_heater.setTankVolume(0.15)  # 150 liters
    water_heater.setHeaterFuelType('NaturalGas')

    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "NECB2020 UEF efficiency application should succeed"

    thermal_eff = water_heater.heaterThermalEfficiency.get
    assert_in_delta 0.82, thermal_eff, 0.02,
      "NECB2020 small gas water heater should have approximately 82% efficiency"
  end

  def test_necb2020_gas_water_heater_large_capacity

    # Test NECB 2020 large gas water heater efficiency
    # Large units use different efficiency calculation
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2020')

    # Large gas water heater
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setHeaterMaximumCapacity(35000.0)  # 35 kW (>22 kW threshold)
    water_heater.setTankVolume(0.5)  # 500 liters
    water_heater.setHeaterFuelType('NaturalGas')

    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "NECB2020 large capacity efficiency should succeed"

    thermal_eff = water_heater.heaterThermalEfficiency.get
    assert thermal_eff >= 0.85, "NECB2020 large gas WH should have >= 85% efficiency"
    assert thermal_eff <= 0.95, "NECB2020 large gas WH efficiency should be <= 95%"
  end
end
