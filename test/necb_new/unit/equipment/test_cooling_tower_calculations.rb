require_relative '../../test_helper'

# Test cooling tower calculation methods
# Tests the cooling tower fan power and efficiency lookup methods without requiring sizing runs
#
# Methods tested:
# - Standard#cooling_tower_apply_minimum_power_per_flow
# - Cooling tower fan power calculations (single, two-speed, variable speed)
# - ASHRAE 90.1 performance requirements (NECB inherits these)
#
# References:
# - NECB 2011 Section 8.4.4.12 (Cooling Tower Requirements)
# - NECB 2015 Section 8.4.4.11, Table 5.2.12.2
# - ASHRAE 90.1 Table 6.8.1-7 (Open Tower Performance)
#
# IMPORTANT NOTE:
# NECB standards (2011, 2015, 2017, 2020) do not have their own heat_rejection template data.
# They inherit the base Standard class cooling tower methods but reference ASHRAE 90.1 data.
# These tests use ASHRAE 90.1 standards to test the calculation logic that NECB would inherit.
class TestCoolingTowerCalculations < Minitest::Test

  # ============================================================================
  # Test Helper Methods
  # ============================================================================

  # Calculate expected fan power based on flow rate and gpm/hp requirement
  # @param design_water_flow_gpm [Float] design water flow in gallons per minute
  # @param min_gpm_per_hp [Float] minimum performance in gpm/hp
  # @return [Float] expected fan motor power in Watts
  def calculate_expected_fan_power(design_water_flow_gpm, min_gpm_per_hp)
    # Calculate nominal HP from flow rate and efficiency requirement
    nominal_hp = design_water_flow_gpm / min_gpm_per_hp

    # Fan brake horsepower is 90% of nominal HP per PNNL method
    fan_bhp = 0.9 * nominal_hp

    # Default motor efficiency (used when motor properties lookup fails)
    fan_motor_eff = 0.85

    # Calculate fan motor power
    fan_motor_actual_power_hp = fan_bhp / fan_motor_eff

    # Convert to Watts (745.7 W/HP)
    fan_motor_actual_power_w = fan_motor_actual_power_hp * 745.7

    return fan_motor_actual_power_w
  end

  # Create a cooling tower with specified properties
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @param type [Symbol] :single_speed, :two_speed, or :variable_speed
  # @param design_water_flow_m3_per_s [Float] design water flow rate in m3/s
  # @param fan_type [String] 'Centrifugal' or 'Propeller or Axial'
  # @return [OpenStudio::Model::StraightComponent] cooling tower object
  def create_test_cooling_tower(model, type, design_water_flow_m3_per_s, fan_type)
    case type
    when :single_speed
      tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
      tower.setDesignWaterFlowRate(design_water_flow_m3_per_s)
    when :two_speed
      tower = OpenStudio::Model::CoolingTowerTwoSpeed.new(model)
      tower.setDesignWaterFlowRate(design_water_flow_m3_per_s)
    when :variable_speed
      tower = OpenStudio::Model::CoolingTowerVariableSpeed.new(model)
      tower.setDesignWaterFlowRate(design_water_flow_m3_per_s)
    else
      raise "Unknown tower type: #{type}"
    end

    # Encode fan type in the name for the method to detect
    tower.setName("Test_#{fan_type}_CoolingTower_#{type}")

    return tower
  end

  # ============================================================================
  # Single Speed Cooling Tower Tests
  # ============================================================================

  def test_single_speed_tower_propeller_fan_ashrae_901_2010
    # ASHRAE 90.1-2010 (similar to what NECB 2011 references)
    # Open tower with propeller/axial fan: 38.2 gpm/hp
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    # Create tower with 1000 gpm design flow (0.063 m3/s)
    design_flow_gpm = 1000.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Propeller')

    # Apply minimum power per flow
    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should return true for successful application"

    # Calculate expected fan power: 1000 gpm / 38.2 gpm/hp = 26.18 hp nominal
    expected_power_w = calculate_expected_fan_power(design_flow_gpm, 38.2)

    # Get actual fan power from tower
    actual_power_w = tower.fanPoweratDesignAirFlowRate.get

    # Allow 20% tolerance due to motor efficiency lookup variations
    assert_in_delta expected_power_w, actual_power_w, expected_power_w * 0.20,
      "Single speed tower fan power should match calculated value. Expected: #{expected_power_w.round} W, Got: #{actual_power_w.round} W"
  end

  def test_single_speed_tower_centrifugal_fan_ashrae_901_2010
    # ASHRAE 90.1-2010
    # Open tower with centrifugal fan: 20.0 gpm/hp (lower efficiency)
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    # Create tower with 500 gpm design flow
    design_flow_gpm = 500.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Centrifugal')

    # Apply minimum power per flow
    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should return true"

    # Calculate expected fan power: 500 gpm / 20.0 gpm/hp = 25 hp nominal
    expected_power_w = calculate_expected_fan_power(design_flow_gpm, 20.0)

    actual_power_w = tower.fanPoweratDesignAirFlowRate.get

    assert_in_delta expected_power_w, actual_power_w, expected_power_w * 0.20,
      "Centrifugal fan tower should use 20.0 gpm/hp. Expected: #{expected_power_w.round} W, Got: #{actual_power_w.round} W"
  end

  def test_single_speed_tower_small_capacity
    # Test very small cooling tower (100 gpm)
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 100.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Propeller')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should handle small towers"

    # Should still have valid fan power
    actual_power_w = tower.fanPoweratDesignAirFlowRate.get
    assert_operator actual_power_w, :>, 0, "Small tower should have positive fan power"
    assert_operator actual_power_w, :<, 10000, "Small tower should have <10kW fan power"
  end

  # ============================================================================
  # Two Speed Cooling Tower Tests
  # ============================================================================

  def test_two_speed_tower_fan_power_split
    # Two-speed towers should have high and low fan power settings
    # Low speed is typically 30% of high speed
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 1000.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :two_speed, design_flow_m3s, 'Propeller')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should return true"

    # Get high and low speed fan power
    high_speed_power = tower.highFanSpeedFanPower.get
    low_speed_power = tower.lowFanSpeedFanPower.get

    # Low speed should be 30% of high speed
    expected_low_power = 0.3 * high_speed_power

    assert_in_delta expected_low_power, low_speed_power, 1.0,
      "Low speed power should be 30% of high speed. High: #{high_speed_power.round} W, Low: #{low_speed_power.round} W"

    # High speed should match calculated value
    expected_high_power = calculate_expected_fan_power(design_flow_gpm, 38.2)
    assert_in_delta expected_high_power, high_speed_power, expected_high_power * 0.20,
      "High speed power should match calculated value"
  end

  def test_two_speed_tower_centrifugal_fan
    # Test two-speed tower with centrifugal fan
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 750.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :two_speed, design_flow_m3s, 'Centrifugal')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should return true"

    high_speed_power = tower.highFanSpeedFanPower.get
    expected_power = calculate_expected_fan_power(design_flow_gpm, 20.0)

    assert_in_delta expected_power, high_speed_power, expected_power * 0.20,
      "Two-speed centrifugal tower should use 20.0 gpm/hp"
  end

  # ============================================================================
  # Variable Speed Cooling Tower Tests
  # ============================================================================

  def test_variable_speed_tower_propeller_fan
    # Variable speed towers have design fan power
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 1200.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :variable_speed, design_flow_m3s, 'Propeller')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should return true"

    design_power = tower.designFanPower.get
    expected_power = calculate_expected_fan_power(design_flow_gpm, 38.2)

    assert_in_delta expected_power, design_power, expected_power * 0.20,
      "Variable speed tower design power should match calculated value"
  end

  def test_variable_speed_tower_large_capacity
    # Test variable speed tower with large capacity (5000 gpm)
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 5000.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :variable_speed, design_flow_m3s, 'Propeller')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should handle large towers"

    design_power = tower.designFanPower.get

    # Large tower should have reasonable power
    assert_operator design_power, :>, 10000, "Large tower should have >10kW fan power"
    assert_operator design_power, :<, 200000, "Large tower should have <200kW fan power"
  end

  # ============================================================================
  # ASHRAE 90.1 Vintage Comparison Tests
  # ============================================================================

  def test_ashrae_901_2010_vs_2013_propeller_fan_efficiency
    # ASHRAE 90.1-2010 uses 38.2 gpm/hp
    # ASHRAE 90.1-2013 improved to 40.2 gpm/hp (more efficient)
    # This mirrors what would happen with NECB 2011 vs NECB 2015
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 1000.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    # Test 90.1-2010
    standard_2010 = Standard.build('90.1-2010')
    tower_2010 = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Propeller')
    standard_2010.cooling_tower_apply_minimum_power_per_flow(tower_2010)
    power_2010 = tower_2010.fanPoweratDesignAirFlowRate.get

    # Test 90.1-2013
    standard_2013 = Standard.build('90.1-2013')
    tower_2013 = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Propeller')
    standard_2013.cooling_tower_apply_minimum_power_per_flow(tower_2013)
    power_2013 = tower_2013.fanPoweratDesignAirFlowRate.get

    # 90.1-2013 should be MORE efficient (40.2 vs 38.2 gpm/hp)
    # More efficient = LOWER fan power for same flow
    # Expected ratio: 38.2/40.2 = 0.95 (5% reduction)
    expected_ratio = 38.2 / 40.2
    actual_ratio = power_2013 / power_2010

    assert_operator power_2013, :<, power_2010,
      "90.1-2013 should require less fan power than 90.1-2010 (more efficient)"

    assert_in_delta expected_ratio, actual_ratio, 0.10,
      "Power ratio should reflect gpm/hp improvement. Expected ratio: #{expected_ratio.round(2)}, Got: #{actual_ratio.round(2)}"
  end

  def test_ashrae_901_2013_propeller_fan_efficiency
    # ASHRAE 90.1-2013 uses 40.2 gpm/hp (same efficiency NECB 2015+ would use)
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 1500.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    standard_2013 = Standard.build('90.1-2013')
    tower_2013 = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Propeller')
    standard_2013.cooling_tower_apply_minimum_power_per_flow(tower_2013)
    power_2013 = tower_2013.fanPoweratDesignAirFlowRate.get

    # Calculate expected power using 40.2 gpm/hp
    expected_power = calculate_expected_fan_power(design_flow_gpm, 40.2)

    assert_in_delta expected_power, power_2013, expected_power * 0.20,
      "90.1-2013 should use 40.2 gpm/hp for propeller fans"
  end

  # ============================================================================
  # Fan Power Calculation Component Tests
  # ============================================================================

  def test_fan_power_calculation_logic
    # Test the calculation logic directly
    # 1000 gpm / 38.2 gpm/hp = 26.18 hp nominal
    # 26.18 * 0.9 = 23.56 hp brake
    # 23.56 / 0.85 = 27.72 hp motor actual
    # 27.72 * 745.7 = 20,670 W

    design_flow_gpm = 1000.0
    min_gpm_per_hp = 38.2

    expected_power = calculate_expected_fan_power(design_flow_gpm, min_gpm_per_hp)

    # Manual calculation for verification
    nominal_hp = design_flow_gpm / min_gpm_per_hp  # 26.18 hp
    fan_bhp = 0.9 * nominal_hp  # 23.56 hp
    fan_motor_actual_hp = fan_bhp / 0.85  # 27.72 hp
    manual_power_w = fan_motor_actual_hp * 745.7  # 20,670 W

    assert_in_delta manual_power_w, expected_power, 1.0,
      "Helper method calculation should match manual calculation"

    # Expected value around 20,670 W
    assert_in_delta 20670, expected_power, 100,
      "1000 gpm at 38.2 gpm/hp should result in approximately 20,670 W"
  end

  def test_fan_power_scales_with_flow
    # Fan power should scale linearly with flow rate
    base_flow_gpm = 1000.0
    double_flow_gpm = 2000.0
    min_gpm_per_hp = 38.2

    base_power = calculate_expected_fan_power(base_flow_gpm, min_gpm_per_hp)
    double_power = calculate_expected_fan_power(double_flow_gpm, min_gpm_per_hp)

    # Doubling flow should double power
    assert_in_delta base_power * 2.0, double_power, 1.0,
      "Fan power should scale linearly with flow rate"
  end

  def test_fan_power_scales_with_efficiency
    # Higher gpm/hp means more efficient, lower power
    design_flow_gpm = 1000.0
    lower_eff_gpm_per_hp = 20.0  # Centrifugal
    higher_eff_gpm_per_hp = 38.2  # Propeller

    lower_eff_power = calculate_expected_fan_power(design_flow_gpm, lower_eff_gpm_per_hp)
    higher_eff_power = calculate_expected_fan_power(design_flow_gpm, higher_eff_gpm_per_hp)

    # Lower efficiency (20 gpm/hp) should require MORE power
    assert_operator lower_eff_power, :>, higher_eff_power,
      "Lower gpm/hp efficiency should require more fan power"

    # Ratio should match efficiency ratio: 38.2/20.0 = 1.91
    expected_ratio = higher_eff_gpm_per_hp / lower_eff_gpm_per_hp
    actual_ratio = lower_eff_power / higher_eff_power

    assert_in_delta expected_ratio, actual_ratio, 0.01,
      "Power ratio should match efficiency ratio"
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  def test_very_small_cooling_tower
    # Test very small cooling tower (50 gpm)
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 50.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :single_speed, design_flow_m3s, 'Propeller')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should handle very small towers"

    actual_power_w = tower.fanPoweratDesignAirFlowRate.get

    # Should have reasonable power for small tower
    assert_operator actual_power_w, :>, 100, "Even small towers need >100W"
    assert_operator actual_power_w, :<, 5000, "Small tower should have <5kW fan power"
  end

  def test_very_large_cooling_tower
    # Test very large cooling tower (10000 gpm)
    standard = Standard.build('90.1-2013')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 10000.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = create_test_cooling_tower(model, :variable_speed, design_flow_m3s, 'Propeller')

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should handle very large towers"

    actual_power_w = tower.designFanPower.get

    # Should have reasonable power for large tower
    assert_operator actual_power_w, :>, 50000, "Large tower should have >50kW fan power"
    assert_operator actual_power_w, :<, 500000, "Large tower should have <500kW fan power"
  end

  def test_tower_without_flow_rate
    # Test behavior when tower doesn't have flow rate set
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
    tower.setName("Test_Propeller_CoolingTower")
    # Don't set design water flow rate

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    # Should return false when flow rate not available
    refute result, "Method should return false when design flow rate is not available"
  end

  def test_tower_name_without_fan_type
    # Test when tower name doesn't include fan type
    # Should default to Propeller or Axial
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new

    design_flow_gpm = 1000.0
    design_flow_m3s = OpenStudio.convert(design_flow_gpm, 'gal/min', 'm^3/s').get

    tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
    tower.setName("Generic_Tower_Name")
    tower.setDesignWaterFlowRate(design_flow_m3s)

    result = standard.cooling_tower_apply_minimum_power_per_flow(tower)

    assert result, "Method should default to Propeller/Axial fan type"

    # Should use propeller/axial efficiency (38.2 gpm/hp for 90.1-2010)
    actual_power_w = tower.fanPoweratDesignAirFlowRate.get
    expected_power = calculate_expected_fan_power(design_flow_gpm, 38.2)

    assert_in_delta expected_power, actual_power_w, expected_power * 0.20,
      "Tower without fan type in name should default to Propeller/Axial"
  end

end
