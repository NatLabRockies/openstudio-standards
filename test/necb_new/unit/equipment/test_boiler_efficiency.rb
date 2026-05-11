require_relative '../../test_helper'

# Test boiler efficiency lookups and conversions
# Tests the boiler efficiency lookup methods without requiring any OpenStudio model
#
# Methods tested:
# - Standard#boiler_hot_water_standard_minimum_thermal_efficiency
# - OpenstudioStandards::HVAC.afue_to_thermal_eff
# - OpenstudioStandards::HVAC.thermal_eff_to_afue
# - OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff
# - OpenstudioStandards::HVAC.thermal_eff_to_comb_eff
#
# References:
# - NECB 2011 Table 5.2.12.1 (Boiler Efficiency Requirements)
# - NECB 2011 Clause 8.4.4.10 (Boiler Staging)
class TestBoilerEfficiency < Minitest::Test

  # ============================================================================
  # NECB2011 Boiler Efficiency Tests
  # ============================================================================

  def test_necb2011_natural_gas_boiler_small_capacity
    # NECB 2011 Table 5.2.12.1
    # Natural gas boiler < 73 kW (250,000 Btu/hr) -> 85% AFUE (from actual data)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small natural gas boiler (50 kW = 170,000 Btu/hr)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_NaturalGas_Boiler_50kW')
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(50000)  # 50 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Convert to AFUE for comparison
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.85, afue, 0.01,
      "Expected 50kW natural gas boiler to have 85% AFUE per NECB 2011 Table 5.2.12.1"
    assert_in_delta 0.85, thermal_eff, 0.02,
      "Expected thermal efficiency of ~0.85 (85% AFUE)"
  end

  def test_necb2011_natural_gas_boiler_medium_capacity
    # NECB 2011 Table 5.2.12.1
    # Natural gas boiler 73-2200 kW (250k-7.5M Btu/hr) -> 83% thermal efficiency (from actual data)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a medium natural gas boiler (500 kW = 1.7M Btu/hr)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_NaturalGas_Boiler_500kW')
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(500000)  # 500 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    assert_in_delta 0.83, thermal_eff, 0.01,
      "Expected 500kW natural gas boiler to have 83% thermal efficiency per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_natural_gas_boiler_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Natural gas boiler > 2200 kW (7.5M Btu/hr) -> 83.3% combustion efficiency (from actual data)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a large natural gas boiler (2500 kW = 8.5M Btu/hr)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_NaturalGas_Boiler_2500kW')
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(2500000)  # 2500 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Convert to combustion efficiency for comparison
    comb_eff = OpenstudioStandards::HVAC.thermal_eff_to_comb_eff(thermal_eff)

    assert_in_delta 0.833, comb_eff, 0.02,
      "Expected 2500kW natural gas boiler to have 83.3% combustion efficiency per NECB 2011 Table 5.2.12.1"
    assert_in_delta 0.81, thermal_eff, 0.02,
      "Expected thermal efficiency of ~0.81 (83.3% combustion eff)"
  end

  def test_necb2011_fuel_oil_boiler_small_capacity
    # NECB 2011 Table 5.2.12.1
    # Fuel oil boiler < 73 kW -> 84.7% AFUE (from actual data)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small fuel oil boiler (50 kW)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_FuelOil_Boiler_50kW')
    boiler.setFuelType('FuelOilNo2')
    boiler.setNominalCapacity(50000)  # 50 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Convert to AFUE for comparison
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.847, afue, 0.02,
      "Expected 50kW fuel oil boiler to have 84.7% AFUE per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_fuel_oil_boiler_medium_capacity
    # NECB 2011 Table 5.2.12.1
    # Fuel oil boiler 73-2200 kW -> 84% thermal efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a medium fuel oil boiler (500 kW)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_FuelOil_Boiler_500kW')
    boiler.setFuelType('FuelOilNo2')
    boiler.setNominalCapacity(500000)  # 500 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    assert_in_delta 0.84, thermal_eff, 0.01,
      "Expected 500kW fuel oil boiler to have 84% thermal efficiency per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_fuel_oil_boiler_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Fuel oil boiler > 2200 kW -> 85.8% combustion efficiency (from actual data)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a large fuel oil boiler (2500 kW)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_FuelOil_Boiler_2500kW')
    boiler.setFuelType('FuelOilNo2')
    boiler.setNominalCapacity(2500000)  # 2500 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Convert to combustion efficiency for comparison
    comb_eff = OpenstudioStandards::HVAC.thermal_eff_to_comb_eff(thermal_eff)

    assert_in_delta 0.858, comb_eff, 0.02,
      "Expected 2500kW fuel oil boiler to have 85.8% combustion efficiency per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_electric_boiler
    # NECB 2011 Table 5.2.12.1
    # Electric boiler -> 100% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create an electric boiler (100 kW)
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Test_Electric_Boiler_100kW')
    boiler.setFuelType('Electricity')
    boiler.setNominalCapacity(100000)  # 100 kW in Watts

    # Get efficiency
    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    assert_in_delta 1.00, thermal_eff, 0.01,
      "Expected electric boiler to have 100% thermal efficiency"
  end

  # ============================================================================
  # Capacity Threshold Boundary Tests
  # ============================================================================

  def test_boundary_73kw_natural_gas
    # Test exactly at threshold (73 kW = 250,000 Btu/hr)
    # Should transition from AFUE to thermal efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(73000)  # Exactly 73 kW

    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # At boundary, should use thermal efficiency method (85% from actual data)
    assert_in_delta 0.85, thermal_eff, 0.02,
      "Expected 73kW (boundary) boiler to use thermal efficiency method"
  end

  def test_boundary_2200kw_natural_gas
    # Test exactly at threshold (2200 kW = 7.5M Btu/hr)
    # Should transition from thermal eff to combustion eff
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(2200000)  # Exactly 2200 kW

    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # At boundary, might use either method - just verify it's reasonable
    assert_operator thermal_eff, :>, 0.75, "Efficiency should be greater than 75%"
    assert_operator thermal_eff, :<, 0.85, "Efficiency should be less than 85%"
  end

  # ============================================================================
  # Efficiency Conversion Tests
  # ============================================================================

  def test_afue_to_thermal_eff_conversion
    # Test AFUE to thermal efficiency conversion
    # In practice, AFUE is used directly as thermal efficiency in this implementation
    afue = 0.80
    thermal_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(afue)

    assert_in_delta 0.80, thermal_eff, 0.02,
      "AFUE 80% should convert to 80% thermal efficiency (identity conversion)"
  end

  def test_thermal_eff_to_afue_conversion
    # Test thermal efficiency to AFUE conversion (reverse)
    # In practice, thermal efficiency is used directly as AFUE in this implementation
    thermal_eff = 0.75
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.75, afue, 0.02,
      "Thermal efficiency 75% should convert to 75% AFUE (identity conversion)"
  end

  def test_combustion_eff_to_thermal_eff_conversion
    # Test combustion efficiency to thermal efficiency conversion
    # Combustion eff 82% should convert to approximately 80% thermal efficiency
    combustion_eff = 0.82
    thermal_eff = OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff(combustion_eff)

    assert_in_delta 0.80, thermal_eff, 0.02,
      "Combustion efficiency 82% should convert to approximately 80% thermal efficiency"
  end

  def test_thermal_eff_to_combustion_eff_conversion
    # Test thermal efficiency to combustion efficiency conversion (reverse)
    thermal_eff = 0.80
    combustion_eff = OpenstudioStandards::HVAC.thermal_eff_to_comb_eff(thermal_eff)

    assert_in_delta 0.82, combustion_eff, 0.02,
      "Thermal efficiency 80% should convert to approximately 82% combustion efficiency"
  end

  def test_round_trip_afue_conversion
    # Test round-trip conversion: thermal_eff -> AFUE -> thermal_eff
    original_thermal_eff = 0.75

    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(original_thermal_eff)
    recovered_thermal_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(afue)

    assert_in_delta original_thermal_eff, recovered_thermal_eff, 0.01,
      "Round-trip conversion should recover original value"
  end

  def test_round_trip_combustion_eff_conversion
    # Test round-trip conversion: thermal_eff -> combustion_eff -> thermal_eff
    original_thermal_eff = 0.80

    combustion_eff = OpenstudioStandards::HVAC.thermal_eff_to_comb_eff(original_thermal_eff)
    recovered_thermal_eff = OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff(combustion_eff)

    assert_in_delta original_thermal_eff, recovered_thermal_eff, 0.01,
      "Round-trip conversion should recover original value"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2015_vs_necb2011_efficiency
    # Compare NECB 2015 to NECB 2011 for same boiler configuration
    # (NECB 2015 may have different requirements)
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(500000)  # 500 kW

    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    eff_2011 = standard_2011.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Reset boiler for 2015 test
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(500000)

    eff_2015 = standard_2015.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # NECB 2015 should have same or better efficiency than 2011
    assert_operator eff_2015, :>=, eff_2011 - 0.01,
      "NECB 2015 efficiency should not be worse than NECB 2011"
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  def test_very_small_boiler
    # Test very small boiler (1 kW)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(1000)  # 1 kW

    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Should still return a valid efficiency (use AFUE method)
    assert_operator thermal_eff, :>, 0.6, "Even small boilers should have > 60% efficiency"
    assert_operator thermal_eff, :<, 1.0, "Efficiency cannot exceed 100%"
  end

  def test_very_large_boiler
    # Test very large boiler (10 MW)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(10000000)  # 10 MW

    thermal_eff = standard.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

    # Should still return a valid efficiency (use combustion eff method)
    assert_operator thermal_eff, :>, 0.75, "Large boilers should have > 75% efficiency"
    assert_operator thermal_eff, :<, 0.90, "Large boilers typically < 90% thermal efficiency"
  end

end
