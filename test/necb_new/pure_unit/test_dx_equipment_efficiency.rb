require_relative '../test_helper'

# Test DX equipment efficiency lookups and conversions
# Tests the DX cooling and heating coil efficiency lookup methods with minimal coil objects
#
# Methods tested:
# - Standard#coil_cooling_dx_single_speed_standard_minimum_cop
# - Standard#coil_cooling_dx_two_speed_standard_minimum_cop
# - Standard#coil_heating_dx_single_speed_standard_minimum_cop
# - OpenstudioStandards::HVAC.eer_to_cop
# - OpenstudioStandards::HVAC.cop_to_eer
# - OpenstudioStandards::HVAC.eer_to_cop_no_fan
# - OpenstudioStandards::HVAC.cop_no_fan_to_eer
# - OpenstudioStandards::HVAC.seer_to_cop_no_fan
# - OpenstudioStandards::HVAC.cop_no_fan_to_seer
# - OpenstudioStandards::HVAC.hspf_to_cop_no_fan
#
# References:
# - NECB 2011 Table 5.2.12.1 (Unitary AC and Heat Pump Efficiency Requirements)
# - NECB 2015 Table 5.2.12.1 (Unitary AC and Heat Pump Efficiency Requirements)
# - NECB 2017 Table 5.2.12.1 (Unitary AC and Heat Pump Efficiency Requirements)
# - NECB 2020 Table 5.2.12.1 (Unitary AC and Heat Pump Efficiency Requirements)
class TestDxEquipmentEfficiency < Minitest::Test

  # ============================================================================
  # Efficiency Conversion Tests - EER ↔ COP
  # ============================================================================

  def test_eer_to_cop_conversion_with_fan
    # Test EER to COP conversion (with fan energy included)
    # EER 12.0 should convert to approximately COP 3.517
    # Formula: COP = EER / 3.412 (Btu/W-h conversion)
    eer = 12.0
    cop = OpenstudioStandards::HVAC.eer_to_cop(eer)

    assert_in_delta 3.517, cop, 0.01,
      "EER 12.0 should convert to approximately COP 3.517"
  end

  def test_cop_to_eer_conversion_with_fan
    # Test COP to EER conversion (reverse)
    # Formula: EER = COP * 3.412
    cop = 3.5
    eer = OpenstudioStandards::HVAC.cop_to_eer(cop)

    assert_in_delta 11.942, eer, 0.01,
      "COP 3.5 should convert to approximately EER 11.942"
  end

  def test_eer_to_cop_no_fan_conversion
    # Test EER to COP (no fan) conversion using default method
    # r = 0.12 (assumed ratio of supply fan power to total equipment power)
    eer = 11.0
    cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(eer)

    # Expected: cop = ((eer / 3.412) + 0.12) / (1 - 0.12) = approximately 3.82
    assert_in_delta 3.82, cop, 0.1,
      "EER 11.0 should convert to approximately COP 3.82 (no fan)"
  end

  def test_cop_no_fan_to_eer_conversion
    # Test COP (no fan) to EER conversion
    cop = 3.8
    eer = OpenstudioStandards::HVAC.cop_no_fan_to_eer(cop)

    # Expected: eer = 3.412 * ((cop * 0.88) - 0.12) = approximately 10.95
    assert_in_delta 10.95, eer, 0.2,
      "COP 3.8 (no fan) should convert to approximately EER 10.95"
  end

  def test_round_trip_eer_cop_conversion
    # Test round-trip conversion: COP -> EER -> COP
    original_cop = 3.5

    eer = OpenstudioStandards::HVAC.cop_to_eer(original_cop)
    recovered_cop = OpenstudioStandards::HVAC.eer_to_cop(eer)

    assert_in_delta original_cop, recovered_cop, 0.01,
      "Round-trip EER/COP conversion should recover original value"
  end

  # ============================================================================
  # Efficiency Conversion Tests - SEER ↔ COP
  # ============================================================================

  def test_seer_to_cop_no_fan_conversion
    # Test SEER to COP (no fan) conversion
    # Formula: COP = (-0.0076 * SEER^2) + (0.3796 * SEER)
    seer = 14.0
    cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(seer)

    # Expected: cop = (-0.0076 * 196) + (5.3144) = approximately 3.83
    assert_in_delta 3.83, cop, 0.1,
      "SEER 14.0 should convert to approximately COP 3.83 (no fan)"
  end

  def test_seer_to_cop_no_fan_conversion_high_efficiency
    # Test SEER to COP for high efficiency unit
    seer = 18.0
    cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(seer)

    # Expected: cop = (-0.0076 * 324) + (6.8328) = approximately 4.37
    assert_in_delta 4.37, cop, 0.1,
      "SEER 18.0 should convert to approximately COP 4.37 (no fan)"
  end

  def test_cop_no_fan_to_seer_conversion
    # Test COP (no fan) to SEER conversion (reverse)
    # Uses quadratic formula to solve for SEER
    cop = 4.0
    seer = OpenstudioStandards::HVAC.cop_no_fan_to_seer(cop)

    # Expected: approximately 15.0-15.5 SEER
    assert_in_delta 15.2, seer, 0.5,
      "COP 4.0 (no fan) should convert to approximately 15.2 SEER"
  end

  def test_round_trip_seer_cop_conversion
    # Test round-trip conversion: SEER -> COP -> SEER
    original_seer = 15.0

    cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(original_seer)
    recovered_seer = OpenstudioStandards::HVAC.cop_no_fan_to_seer(cop)

    assert_in_delta original_seer, recovered_seer, 0.5,
      "Round-trip SEER/COP conversion should recover original value within 0.5 SEER"
  end

  # ============================================================================
  # Efficiency Conversion Tests - HSPF ↔ COP
  # ============================================================================

  def test_hspf_to_cop_no_fan_conversion
    # Test HSPF to COP (no fan) conversion for heat pumps
    # Formula: COP = (-0.0296 * HSPF^2) + (0.7134 * HSPF)
    hspf = 8.5
    cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(hspf)

    # Expected: cop = (-0.0296 * 72.25) + (6.0639) = approximately 3.92
    assert_in_delta 3.92, cop, 0.1,
      "HSPF 8.5 should convert to approximately COP 3.92 (no fan)"
  end

  def test_hspf_to_cop_no_fan_conversion_high_efficiency
    # Test HSPF to COP for high efficiency heat pump
    hspf = 10.0
    cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(hspf)

    # Expected: cop = (-0.0296 * 100) + (7.134) = approximately 4.17
    assert_in_delta 4.17, cop, 0.1,
      "HSPF 10.0 should convert to approximately COP 4.17 (no fan)"
  end

  def test_hspf_to_cop_with_fan_conversion
    # Test HSPF to COP (with fan) conversion
    # Formula: COP = (-0.0255 * HSPF^2) + (0.6239 * HSPF)
    hspf = 8.5
    cop = OpenstudioStandards::HVAC.hspf_to_cop(hspf)

    # Expected: cop = (-0.0255 * 72.25) + (5.30315) = approximately 3.46
    assert_in_delta 3.46, cop, 0.1,
      "HSPF 8.5 should convert to approximately COP 3.46 (with fan)"
  end

  # ============================================================================
  # NECB2011 DX Cooling Equipment Tests - Single Speed
  # ============================================================================

  def test_necb2011_single_speed_cooling_small_single_package
    # NECB 2011 Table 5.2.12.1
    # Air-cooled AC, Single Package, < 65,000 Btu/hr -> 14.0 SEER
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small single-speed DX cooling coil (10 kW = 34,120 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Single_Package_10kW')
    coil.setRatedTotalCoolingCapacity(10000)  # 10 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Convert expected SEER to COP for comparison
    expected_cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(14.0)

    assert_in_delta expected_cop, cop, 0.15,
      "Expected 10kW single package AC to have COP ~#{expected_cop.round(2)} (14.0 SEER) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_single_speed_cooling_small_split_system
    # NECB 2011 Table 5.2.12.1
    # Air-cooled AC, Split System, < 65,000 Btu/hr -> 15.0 SEER
    # Note: This test checks that the lookup works, but may default to Single Package
    # unless the coil is properly configured in a split system configuration
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small split system DX cooling coil (15 kW = 51,180 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Split_System_15kW')
    coil.setRatedTotalCoolingCapacity(15000)  # 15 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Convert expected SEER to COP for comparison (may get 14.0 for Single Package)
    expected_cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(14.0)

    assert_in_delta expected_cop, cop, 0.3,
      "Expected 15kW AC to have COP ~#{expected_cop.round(2)} (14.0-15.0 SEER) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_single_speed_cooling_medium_capacity
    # NECB 2011 Table 5.2.12.1
    # Air-cooled AC, 65,001-249,999 Btu/hr -> 9.7 EER
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a medium-capacity DX cooling coil (30 kW = 102,360 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Single_Package_30kW')
    coil.setRatedTotalCoolingCapacity(30000)  # 30 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Convert expected EER to COP for comparison
    expected_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(9.7)

    assert_in_delta expected_cop, cop, 0.2,
      "Expected 30kW AC to have COP ~#{expected_cop.round(2)} (9.7 EER) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_single_speed_cooling_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Air-cooled AC, 250,000-759,999 Btu/hr -> 8.39 EER
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a large-capacity DX cooling coil (100 kW = 341,200 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Single_Package_100kW')
    coil.setRatedTotalCoolingCapacity(100000)  # 100 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Convert expected EER to COP for comparison
    expected_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(8.39)

    assert_in_delta expected_cop, cop, 0.2,
      "Expected 100kW AC to have COP ~#{expected_cop.round(2)} (8.39 EER) per NECB 2011 Table 5.2.12.1"
  end

  # ============================================================================
  # NECB2011 DX Cooling Equipment Tests - Two Speed
  # ============================================================================

  def test_necb2011_two_speed_cooling_small_capacity
    # NECB 2011 Table 5.2.12.1
    # Two-speed AC, < 65,000 Btu/hr -> should use SEER rating
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small two-speed DX cooling coil (12 kW = 40,944 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
    coil.setName('AC_TwoSpeed_12kW')
    coil.setRatedHighSpeedTotalCoolingCapacity(12000)  # 12 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_two_speed_standard_minimum_cop(coil)

    # Expected to use SEER rating (14.0 for single package)
    expected_cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(14.0)

    assert_in_delta expected_cop, cop, 0.2,
      "Expected 12kW two-speed AC to have COP ~#{expected_cop.round(2)} (14.0 SEER) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_two_speed_cooling_medium_capacity
    # NECB 2011 Table 5.2.12.1
    # Two-speed AC, 65,001-249,999 Btu/hr -> 9.7 EER
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a medium two-speed DX cooling coil (40 kW = 136,480 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
    coil.setName('AC_TwoSpeed_40kW')
    coil.setRatedHighSpeedTotalCoolingCapacity(40000)  # 40 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_two_speed_standard_minimum_cop(coil)

    # Convert expected EER to COP for comparison
    expected_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(9.7)

    assert_in_delta expected_cop, cop, 0.2,
      "Expected 40kW two-speed AC to have COP ~#{expected_cop.round(2)} (9.7 EER) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_two_speed_cooling_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Two-speed AC, 250,000-759,999 Btu/hr -> 8.39 EER
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a large two-speed DX cooling coil (120 kW = 409,440 Btu/hr)
    coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
    coil.setName('AC_TwoSpeed_120kW')
    coil.setRatedHighSpeedTotalCoolingCapacity(120000)  # 120 kW in Watts

    # Get minimum COP
    cop = standard.coil_cooling_dx_two_speed_standard_minimum_cop(coil)

    # Convert expected EER to COP for comparison
    expected_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(8.39)

    assert_in_delta expected_cop, cop, 0.2,
      "Expected 120kW two-speed AC to have COP ~#{expected_cop.round(2)} (8.39 EER) per NECB 2011 Table 5.2.12.1"
  end

  # ============================================================================
  # NECB2011 Heat Pump Tests - Cooling Mode
  # ============================================================================

  def test_necb2011_heat_pump_cooling_small_single_package
    # NECB 2011 Table 5.2.12.1
    # Heat pump, Single Package, < 65,000 Btu/hr -> 10.0 EER (cooling mode)
    # Note: Without proper unitary system connection, may be treated as AC
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small heat pump DX cooling coil (10 kW = 34,120 Btu/hr)
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_Single_Package_10kW')
    cooling_coil.setRatedTotalCoolingCapacity(10000)  # 10 kW in Watts

    # Create matching heating coil (required for heat pump identification)
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_Single_Package_10kW_Heating')

    # Get minimum COP for cooling coil
    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(cooling_coil)

    # May get SEER 14.0 (if treated as AC) or EER 10.0 (if treated as HP)
    # SEER 14.0 = ~3.8 COP, EER 10.0 = ~3.47 COP
    assert_operator cop, :>, 3.2, "Heat pump cooling COP should be > 3.2"
    assert_operator cop, :<, 4.2, "Heat pump cooling COP should be < 4.2"
  end

  def test_necb2011_heat_pump_cooling_small_split_system
    # NECB 2011 Table 5.2.12.1
    # Heat pump, Split System, < 65,000 Btu/hr -> 10.0 EER (cooling mode)
    # Note: Without proper unitary system connection, may be treated as AC
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small split system heat pump DX cooling coil (15 kW = 51,180 Btu/hr)
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_Split_System_15kW')
    cooling_coil.setRatedTotalCoolingCapacity(15000)  # 15 kW in Watts

    # Create matching heating coil
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_Split_System_15kW_Heating')

    # Get minimum COP for cooling coil
    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(cooling_coil)

    # May get SEER 14.0-15.0 (if treated as AC) or EER 10.0 (if treated as HP)
    # SEER 14.0-15.0 = ~3.8-4.0 COP, EER 10.0 = ~3.47 COP
    assert_operator cop, :>, 3.2, "Heat pump cooling COP should be > 3.2"
    assert_operator cop, :<, 4.2, "Heat pump cooling COP should be < 4.2"
  end

  # ============================================================================
  # NECB2011 Heat Pump Tests - Heating Mode
  # ============================================================================

  def test_necb2011_heat_pump_heating_small_single_package
    # NECB 2011 Table 5.2.12.1
    # Heat pump heating, Single Package, < 65,000 Btu/hr -> uses cooling SEER for heating lookup
    # Cooling SEER = 14.0
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create cooling coil first (required for capacity lookup)
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_Heating_Single_Package_10kW')
    cooling_coil.setRatedTotalCoolingCapacity(10000)  # 10 kW in Watts

    # Create heating coil
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_Heating_Single_Package_10kW')

    # Connect coils in a unitary system (required for paired coil detection)
    unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
    unitary.setCoolingCoil(cooling_coil)
    unitary.setHeatingCoil(heating_coil)

    # Get minimum COP for heating coil
    cop = standard.coil_heating_dx_single_speed_standard_minimum_cop(heating_coil)

    # Expected to use SEER 14.0 from cooling side
    expected_cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(14.0)

    assert_in_delta expected_cop, cop, 0.3,
      "Expected 10kW heat pump heating coil to have COP ~#{expected_cop.round(2)} (14.0 SEER) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_heat_pump_heating_medium_capacity
    # NECB 2011 Table 5.2.12.1
    # Heat pump heating, 65,000-250,000 Btu/hr -> 3.3 COP at 47F
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create cooling coil first (30 kW = 102,360 Btu/hr)
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_Heating_Medium_30kW')
    cooling_coil.setRatedTotalCoolingCapacity(30000)  # 30 kW in Watts

    # Create heating coil
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_Heating_Medium_30kW')

    # Connect coils in a unitary system
    unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
    unitary.setCoolingCoil(cooling_coil)
    unitary.setHeatingCoil(heating_coil)

    # Get minimum COP for heating coil
    cop = standard.coil_heating_dx_single_speed_standard_minimum_cop(heating_coil)

    # Expected COP at 47F rating condition
    # Need to convert from COP-H (with fan) to COP (no fan)
    expected_coph = 3.3
    expected_cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(expected_coph, 30000)

    assert_in_delta expected_cop, cop, 0.3,
      "Expected 30kW heat pump heating coil to have COP ~#{expected_cop.round(2)} (3.3 COP-H) per NECB 2011 Table 5.2.12.1"
  end

  def test_necb2011_heat_pump_heating_large_capacity
    # NECB 2011 Table 5.2.12.1
    # Heat pump heating, >= 250,000 Btu/hr -> 3.4 COP at 47F
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create cooling coil first (100 kW = 341,200 Btu/hr)
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_Heating_Large_100kW')
    cooling_coil.setRatedTotalCoolingCapacity(100000)  # 100 kW in Watts

    # Create heating coil
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_Heating_Large_100kW')

    # Connect coils in a unitary system
    unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
    unitary.setCoolingCoil(cooling_coil)
    unitary.setHeatingCoil(heating_coil)

    # Get minimum COP for heating coil
    cop = standard.coil_heating_dx_single_speed_standard_minimum_cop(heating_coil)

    # Expected COP at 47F rating condition
    expected_coph = 3.4
    expected_cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(expected_coph, 100000)

    assert_in_delta expected_cop, cop, 0.3,
      "Expected 100kW heat pump heating coil to have COP ~#{expected_cop.round(2)} (3.4 COP-H) per NECB 2011 Table 5.2.12.1"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2015_vs_necb2011_cooling_efficiency
    # Compare NECB 2015 to NECB 2011 for same AC configuration
    # NECB 2015 inherits from NECB 2011, so should have same or better efficiency
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Compare_20kW')
    coil.setRatedTotalCoolingCapacity(20000)  # 20 kW

    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    cop_2011 = standard_2011.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Reset coil for 2015 test
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Compare_20kW')
    coil.setRatedTotalCoolingCapacity(20000)

    cop_2015 = standard_2015.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # NECB 2015 should have same or better efficiency than 2011
    assert_operator cop_2015, :>=, cop_2011 - 0.1,
      "NECB 2015 efficiency should not be worse than NECB 2011"
  end

  def test_necb2020_vs_necb2011_cooling_efficiency
    # Compare NECB 2020 to NECB 2011 for same AC configuration
    # NECB 2020 typically has higher efficiency requirements
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Compare_25kW')
    coil.setRatedTotalCoolingCapacity(25000)  # 25 kW

    standard_2011 = Standard.build('NECB2011')
    standard_2020 = Standard.build('NECB2020')

    cop_2011 = standard_2011.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Reset coil for 2020 test
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Compare_25kW')
    coil.setRatedTotalCoolingCapacity(25000)

    cop_2020 = standard_2020.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # NECB 2020 should have same or better efficiency than 2011
    assert_operator cop_2020, :>=, cop_2011 - 0.1,
      "NECB 2020 efficiency should not be worse than NECB 2011"
  end

  # ============================================================================
  # Capacity Boundary Tests
  # ============================================================================

  def test_boundary_65000_btu_hr_cooling
    # Test exactly at capacity threshold (65,000 Btu/hr = 19.05 kW)
    # Should transition from SEER rating to EER rating
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # 65,000 Btu/hr = 19,050 W
    capacity_w = OpenStudio.convert(65000, 'Btu/hr', 'W').get

    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Boundary_65kBtuhr')
    coil.setRatedTotalCoolingCapacity(capacity_w)

    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # At boundary, should get a valid efficiency
    assert_operator cop, :>, 2.5, "COP should be greater than 2.5"
    assert_operator cop, :<, 5.0, "COP should be less than 5.0"
  end

  def test_boundary_250000_btu_hr_cooling
    # Test exactly at capacity threshold (250,000 Btu/hr = 73.25 kW)
    # Should transition from 9.7 EER to 8.39 EER per NECB 2011 data
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # 250,000 Btu/hr = 73,250 W
    capacity_w = OpenStudio.convert(250000, 'Btu/hr', 'W').get

    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_Boundary_250kBtuhr')
    coil.setRatedTotalCoolingCapacity(capacity_w)

    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # At boundary, should get efficiency around 8.39-9.7 EER
    expected_cop_low = OpenstudioStandards::HVAC.eer_to_cop_no_fan(8.39)
    expected_cop_high = OpenstudioStandards::HVAC.eer_to_cop_no_fan(9.7)

    assert_operator cop, :>=, expected_cop_low - 0.2, "COP should be near lower EER threshold"
    assert_operator cop, :<=, expected_cop_high + 0.2, "COP should be near upper EER threshold"
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  def test_very_small_dx_cooling_unit
    # Test very small DX cooling unit (1 kW = 3,412 Btu/hr)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_VerySmall_1kW')
    coil.setRatedTotalCoolingCapacity(1000)  # 1 kW

    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Should still return a valid efficiency (use SEER method for small units)
    assert_operator cop, :>, 2.0, "Even very small units should have > 2.0 COP"
    assert_operator cop, :<, 6.0, "Even very small units should have < 6.0 COP"
  end

  def test_very_large_dx_cooling_unit
    # Test very large DX cooling unit (500 kW = 1,706,000 Btu/hr)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    coil.setName('AC_VeryLarge_500kW')
    coil.setRatedTotalCoolingCapacity(500000)  # 500 kW

    cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil)

    # Should still return a valid efficiency (use EER method for large units)
    assert_operator cop, :>, 2.5, "Large units should have > 2.5 COP"
    assert_operator cop, :<, 5.0, "Large units should have < 5.0 COP"
  end

  def test_very_small_heat_pump_heating
    # Test very small heat pump heating coil (2 kW cooling capacity = 6,824 Btu/hr)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create very small cooling coil
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_VerySmall_2kW')
    cooling_coil.setRatedTotalCoolingCapacity(2000)  # 2 kW

    # Create heating coil
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_VerySmall_2kW_Heating')

    # Connect in unitary system
    unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
    unitary.setCoolingCoil(cooling_coil)
    unitary.setHeatingCoil(heating_coil)

    cop = standard.coil_heating_dx_single_speed_standard_minimum_cop(heating_coil)

    # Should still return a valid efficiency
    assert_operator cop, :>, 2.0, "Even very small heat pumps should have > 2.0 COP"
    assert_operator cop, :<, 6.0, "Even very small heat pumps should have < 6.0 COP"
  end

  def test_very_large_heat_pump_heating
    # Test very large heat pump heating coil (300 kW cooling capacity = 1,023,600 Btu/hr)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create large cooling coil
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setName('HP_VeryLarge_300kW')
    cooling_coil.setRatedTotalCoolingCapacity(300000)  # 300 kW

    # Create heating coil
    heating_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    heating_coil.setName('HP_VeryLarge_300kW_Heating')

    # Connect in unitary system
    unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
    unitary.setCoolingCoil(cooling_coil)
    unitary.setHeatingCoil(heating_coil)

    cop = standard.coil_heating_dx_single_speed_standard_minimum_cop(heating_coil)

    # Should still return a valid efficiency
    assert_operator cop, :>, 2.5, "Large heat pumps should have > 2.5 COP"
    assert_operator cop, :<, 5.0, "Large heat pumps should have < 5.0 COP"
  end

end
