require_relative '../../test_helper'

# Test furnace (CoilHeatingGas) efficiency lookups and conversions
# Tests the furnace efficiency lookup methods without requiring any OpenStudio model sizing
#
# Methods tested:
# - NECB2011#coil_heating_gas_standard_minimum_thermal_efficiency
# - NECB2011#coil_heating_gas_find_search_criteria
# - OpenstudioStandards::HVAC.afue_to_thermal_eff
# - OpenstudioStandards::HVAC.thermal_eff_to_afue
#
# References:
# - NECB 2011 Table 5.2.12.1 (Furnace Efficiency Requirements)
# - NECB 2015 Table 5.2.12.1 (Furnace Efficiency Requirements)
# - NECB 2020 Table 5.2.12.1-O (Furnace Efficiency Requirements)
class TestFurnaceEfficiency < Minitest::Test

  # ============================================================================
  # NECB2011 Furnace Efficiency Tests
  # ============================================================================

  def test_necb2011_gas_furnace_small_capacity
    # NECB 2011 Table 5.2.12.1
    # Gas furnace < 400,000 Btu/hr (117 kW) -> 92.4% AFUE
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small gas furnace (100 kW = 341,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_100kW')
    coil.setNominalCapacity(100000)  # 100 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Convert to AFUE for comparison
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.924, afue, 0.01,
      "Expected 100kW gas furnace to have 92.4% AFUE per NECB 2011 Table 5.2.12.1"
    assert_in_delta 0.924, thermal_eff, 0.01,
      "Expected thermal efficiency to equal AFUE (92.4%)"
  end

  def test_necb2011_gas_furnace_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Gas furnace > 400,000 Btu/hr (117 kW) -> 81% thermal efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a large gas furnace (200 kW = 682,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_200kW')
    coil.setNominalCapacity(200000)  # 200 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 200kW gas furnace to have 81% thermal efficiency per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_gas_furnace_very_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Gas furnace > 400,000 Btu/hr -> 81% thermal efficiency (applies to all large furnaces)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a very large gas furnace (500 kW = 1.7M Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_500kW')
    coil.setNominalCapacity(500000)  # 500 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 500kW gas furnace to have 81% thermal efficiency per NECB 2011 Table 5.2.12.1"
  end

  # ============================================================================
  # NECB2015 Furnace Efficiency Tests
  # ============================================================================

  def test_necb2015_gas_furnace_small_capacity
    # NECB 2015 Table 5.2.12.1
    # Gas furnace < 225,000 Btu/hr (66 kW) -> 92.4% AFUE
    standard = Standard.build('NECB2015')
    model = OpenStudio::Model::Model.new

    # Create a small gas furnace (50 kW = 170,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_50kW')
    coil.setNominalCapacity(50000)  # 50 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Convert to AFUE for comparison
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.924, afue, 0.01,
      "Expected 50kW gas furnace to have 92.4% AFUE per NECB 2015 Table 5.2.12.1"
  end

  def test_necb2015_gas_furnace_large_capacity
    # NECB 2015 Table 5.2.12.1
    # Gas furnace > 225,000 Btu/hr (66 kW) -> 81% thermal efficiency
    standard = Standard.build('NECB2015')
    model = OpenStudio::Model::Model.new

    # Create a large gas furnace (100 kW = 341,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_100kW')
    coil.setNominalCapacity(100000)  # 100 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 100kW gas furnace to have 81% thermal efficiency per NECB 2015 Table 5.2.12.1"
  end

  # ============================================================================
  # NECB2017 Furnace Efficiency Tests
  # ============================================================================

  def test_necb2017_gas_furnace_small_capacity
    # NECB 2017 inherits from NECB 2015 for furnace efficiency
    # Gas furnace < 225,000 Btu/hr -> 92.4% AFUE
    standard = Standard.build('NECB2017')
    model = OpenStudio::Model::Model.new

    # Create a small gas furnace (60 kW = 205,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_60kW')
    coil.setNominalCapacity(60000)  # 60 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Convert to AFUE for comparison
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.924, afue, 0.01,
      "Expected 60kW gas furnace to have 92.4% AFUE per NECB 2017 (inherits 2015 requirements)"
  end

  def test_necb2017_gas_furnace_large_capacity
    # NECB 2017 inherits from NECB 2015 for furnace efficiency
    # Gas furnace > 225,000 Btu/hr -> 81% thermal efficiency
    standard = Standard.build('NECB2017')
    model = OpenStudio::Model::Model.new

    # Create a large gas furnace (150 kW = 512,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_150kW')
    coil.setNominalCapacity(150000)  # 150 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 150kW gas furnace to have 81% thermal efficiency per NECB 2017"
  end

  # ============================================================================
  # NECB2020 Furnace Efficiency Tests
  # ============================================================================

  def test_necb2020_gas_furnace_small_capacity
    # NECB 2020 Table 5.2.12.1-O
    # Gas furnace <= 225,201 Btu/hr (66 kW) -> 95% AFUE
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    # Create a small gas furnace (50 kW = 170,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_50kW')
    coil.setNominalCapacity(50000)  # 50 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Convert to AFUE for comparison
    afue = OpenstudioStandards::HVAC.thermal_eff_to_afue(thermal_eff)

    assert_in_delta 0.95, afue, 0.01,
      "Expected 50kW gas furnace to have 95% AFUE per NECB 2020 Table 5.2.12.1-O"
    assert_in_delta 0.95, thermal_eff, 0.01,
      "Expected thermal efficiency to equal AFUE (95%)"
  end

  def test_necb2020_gas_furnace_medium_capacity
    # NECB 2020 Table 5.2.12.1-O
    # Gas furnace 225,202-399,221 Btu/hr -> 81% thermal efficiency
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    # Create a medium gas furnace (75 kW = 256,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_75kW')
    coil.setNominalCapacity(75000)  # 75 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 75kW gas furnace to have 81% thermal efficiency per NECB 2020 Table 5.2.12.1-O"
  end

  def test_necb2020_gas_furnace_large_capacity
    # NECB 2020 Table 5.2.12.1-O
    # Gas furnace >= 399,222 Btu/hr (117 kW) -> 81% thermal efficiency
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    # Create a large gas furnace (200 kW = 682,000 Btu/hr)
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Test_Gas_Furnace_200kW')
    coil.setNominalCapacity(200000)  # 200 kW in Watts

    # Get efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 200kW gas furnace to have 81% thermal efficiency per NECB 2020 Table 5.2.12.1-O"
  end

  # ============================================================================
  # Capacity Threshold Boundary Tests
  # ============================================================================

  def test_boundary_400000_btu_necb2011
    # Test at 400,000 Btu/hr threshold for NECB 2011 (117 kW)
    # Maximum capacity for small furnace is 400,000 Btu/hr (uses AFUE)
    # Minimum capacity for large furnace is 400,001 Btu/hr (uses thermal eff)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Test just below boundary - should use AFUE
    coil_below = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_below.setNominalCapacity(117200)  # ~399,900 Btu/hr (just below 400k)
    thermal_eff_below = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil_below)
    assert_in_delta 0.924, thermal_eff_below, 0.01,
      "Expected 399,900 Btu/hr furnace to use AFUE method (92.4%)"

    # Test just above boundary - should use thermal efficiency
    coil_above = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_above.setNominalCapacity(117230)  # ~400,001 Btu/hr (just above 400k)
    thermal_eff_above = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil_above)
    assert_in_delta 0.81, thermal_eff_above, 0.01,
      "Expected 400,001 Btu/hr furnace to use thermal efficiency method (81%)"
  end

  def test_boundary_225000_btu_necb2015
    # Test at 225,000 Btu/hr threshold for NECB 2015 (66 kW)
    # Maximum capacity for small furnace is 225,000 Btu/hr (uses AFUE)
    # Minimum capacity for large furnace is 225,001 Btu/hr (uses thermal eff)
    standard = Standard.build('NECB2015')
    model = OpenStudio::Model::Model.new

    # Test just below boundary - should use AFUE
    coil_below = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_below.setNominalCapacity(65900)  # ~224,860 Btu/hr (just below 225k)
    thermal_eff_below = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil_below)
    assert_in_delta 0.924, thermal_eff_below, 0.01,
      "Expected 224,860 Btu/hr furnace to use AFUE method (92.4%)"

    # Test just above boundary - should use thermal efficiency
    coil_above = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_above.setNominalCapacity(65945)  # ~225,014 Btu/hr (just above 225k)
    thermal_eff_above = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil_above)
    assert_in_delta 0.81, thermal_eff_above, 0.01,
      "Expected 225,014 Btu/hr furnace to use thermal efficiency method (81%)"
  end

  def test_boundary_225201_btu_necb2020
    # Test at 225,201 Btu/hr threshold for NECB 2020 (66 kW)
    # Maximum capacity for small furnace is 225,201 Btu/hr (uses AFUE)
    # Minimum capacity for medium furnace is 225,202 Btu/hr (uses thermal eff)
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    # Test just below boundary - should use AFUE (95%)
    # 225,201 Btu/hr = 65,999.65 W
    coil_below = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_below.setNominalCapacity(65999)  # ~225,200 Btu/hr (just below 225,201)
    thermal_eff_below = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil_below)
    assert_in_delta 0.95, thermal_eff_below, 0.01,
      "Expected 225,200 Btu/hr furnace to use AFUE method (95%)"

    # Test just above boundary - should use thermal efficiency
    # 225,202 Btu/hr = 66,000 W
    coil_above = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_above.setNominalCapacity(66001)  # ~225,203 Btu/hr (just above 225,201)
    thermal_eff_above = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil_above)
    assert_in_delta 0.81, thermal_eff_above, 0.01,
      "Expected 225,203 Btu/hr furnace to use thermal efficiency method (81%)"
  end

  def test_boundary_399221_btu_necb2020
    # Test at 399,221 Btu/hr threshold for NECB 2020 (117 kW)
    # Tests upper boundary of medium capacity range
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setNominalCapacity(117000)  # Approximately 399,000 Btu/hr

    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Should still use thermal efficiency (81%)
    assert_in_delta 0.81, thermal_eff, 0.01,
      "Expected 399,221 Btu/hr (boundary) furnace to have 81% thermal efficiency"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2020_vs_necb2011_small_furnace
    # Compare NECB 2020 to NECB 2011 for small furnace
    # NECB 2020 should have higher efficiency (95% vs 92.4% AFUE)
    model = OpenStudio::Model::Model.new

    coil_2011 = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_2011.setNominalCapacity(50000)  # 50 kW

    coil_2020 = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_2020.setNominalCapacity(50000)  # 50 kW

    standard_2011 = Standard.build('NECB2011')
    standard_2020 = Standard.build('NECB2020')

    eff_2011 = standard_2011.coil_heating_gas_standard_minimum_thermal_efficiency(coil_2011)
    eff_2020 = standard_2020.coil_heating_gas_standard_minimum_thermal_efficiency(coil_2020)

    # NECB 2020 should have better efficiency than 2011
    assert_operator eff_2020, :>, eff_2011,
      "NECB 2020 small furnace efficiency should be higher than NECB 2011"

    # Convert to AFUE to verify expected values
    afue_2011 = OpenstudioStandards::HVAC.thermal_eff_to_afue(eff_2011)
    afue_2020 = OpenstudioStandards::HVAC.thermal_eff_to_afue(eff_2020)

    assert_in_delta 0.924, afue_2011, 0.01, "NECB 2011 should have 92.4% AFUE"
    assert_in_delta 0.95, afue_2020, 0.01, "NECB 2020 should have 95% AFUE"
  end

  def test_necb2015_vs_necb2011_threshold_change
    # Compare NECB 2015 to NECB 2011 for mid-size furnace (100 kW)
    # This capacity crosses the threshold change from 400kBtu (2011) to 225kBtu (2015)
    model = OpenStudio::Model::Model.new

    coil_2011 = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_2011.setNominalCapacity(100000)  # 100 kW = 341,000 Btu/hr

    coil_2015 = OpenStudio::Model::CoilHeatingGas.new(model)
    coil_2015.setNominalCapacity(100000)  # 100 kW = 341,000 Btu/hr

    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    eff_2011 = standard_2011.coil_heating_gas_standard_minimum_thermal_efficiency(coil_2011)
    eff_2015 = standard_2015.coil_heating_gas_standard_minimum_thermal_efficiency(coil_2015)

    # 100 kW is < 400k Btu/hr (2011 uses AFUE) but > 225k Btu/hr (2015 uses thermal eff)
    # So 2011 should have higher efficiency due to AFUE metric
    afue_2011 = OpenstudioStandards::HVAC.thermal_eff_to_afue(eff_2011)

    assert_in_delta 0.924, afue_2011, 0.01, "NECB 2011 at 100kW should have 92.4% AFUE"
    assert_in_delta 0.81, eff_2015, 0.01, "NECB 2015 at 100kW should have 81% thermal efficiency"
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  def test_very_small_furnace
    # Test very small furnace (5 kW = 17,000 Btu/hr)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setNominalCapacity(5000)  # 5 kW

    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Should still return a valid efficiency (use AFUE method)
    assert_operator thermal_eff, :>, 0.80, "Even small furnaces should have > 80% efficiency"
    assert_operator thermal_eff, :<, 1.0, "Efficiency cannot exceed 100%"
  end

  def test_very_large_furnace
    # Test very large furnace (1 MW = 3.4M Btu/hr)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setNominalCapacity(1000000)  # 1 MW

    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    # Should still return a valid efficiency (use thermal eff method)
    assert_in_delta 0.81, thermal_eff, 0.01,
      "Large furnaces should have 81% thermal efficiency per NECB 2011"
  end

  def test_search_criteria_structure
    # Test that coil_heating_gas_find_search_criteria returns correct structure
    standard = Standard.build('NECB2011')

    search_criteria = standard.coil_heating_gas_find_search_criteria

    assert_equal 'Air', search_criteria['fluid_type'],
      "Search criteria should specify Air fluid type"
    assert_equal 'Gas', search_criteria['fuel_type'],
      "Search criteria should specify Gas fuel type"
  end

end
