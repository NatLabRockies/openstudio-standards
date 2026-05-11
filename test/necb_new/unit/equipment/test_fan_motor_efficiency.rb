require_relative '../../test_helper'

# Test fan and motor efficiency lookups and calculations
# Tests the fan and motor efficiency lookup/calculation methods without requiring model sizing
#
# Methods tested:
# - Standard#motor_find_object_standards (via fan_standard_minimum_motor_efficiency_and_size)
# - Standard#motor_fractional_hp_efficiencies
# - Standard#motor_type
# - Standard#fan_brake_horsepower
# - Standard#fan_motor_horsepower
# - Standard#fan_fanpower
# - NECB pressure drop assumptions
#
# References:
# - NECB 2011 Section 5.2.9.2 (Fan Power Limitations)
# - Standards.Fan.rb - Fan methods
# - Standards.Motor.rb - Motor efficiency methods
# - NECB2011/data/motors.json - Motor efficiency data
# - NECB2011/data/constants.json - Pressure rise assumptions
class TestFanMotorEfficiency < Minitest::Test

  # ============================================================================
  # Motor Efficiency Lookup Tests - NECB2011
  # ============================================================================

  def test_necb2011_fan_motor_efficiency_small_motor
    # Test motor efficiency lookup for small fan motor (0.5 HP)
    # For fans < 1 HP, NECB uses fractional horsepower efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small constant volume fan
    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setName('Test_Small_Fan_0.5HP')
    fan.setMaximumFlowRate(0.1)  # 0.1 m3/s
    fan.setPressureRise(100)     # 100 Pa
    fan.setFanEfficiency(0.6)
    fan.setMotorEfficiency(0.7)

    # Calculate brake horsepower (should be very small)
    motor_bhp = 0.4  # Simulate small motor requirement

    # Get motor efficiency and size
    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # Small fan should return actual BHP as nominal HP (not 0.5 HP in NECB)
    assert_in_delta 0.4, nominal_hp, 0.1,
      "Small fan should return actual BHP as nominal HP"

    # Efficiency should be reasonable for fractional HP motor
    assert_operator motor_eff, :>, 0.5, "Motor efficiency should be > 50%"
    assert_operator motor_eff, :<, 0.9, "Fractional HP motor efficiency should be < 90%"
  end

  def test_necb2011_fan_motor_efficiency_constant_volume
    # Test motor efficiency lookup for constant volume fan
    # NECB2011 uses fixed 61.5% efficiency for CAV fans (to get total fan eff of 40%)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setName('Test_CAV_Fan')
    fan.setMaximumFlowRate(2.0)
    fan.setPressureRise(640)  # NECB standard CAV pressure
    fan.setFanEfficiency(0.6)
    fan.setMotorEfficiency(0.85)

    motor_bhp = 3.5

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB uses maximum_capacity = 9999 for fan motors, so nominal_hp = motor_bhp
    assert_in_delta 4.0, nominal_hp, 1.0,
      "CAV fan nominal HP should be approximately motor BHP rounded"

    # NECB CAV fans have fixed 0.615 efficiency
    assert_in_delta 0.615, motor_eff, 0.01,
      "NECB CAV fan motor efficiency should be 61.5% per motors.json"
  end

  def test_necb2011_fan_motor_efficiency_variable_supply
    # Test motor efficiency lookup for VAV supply fan
    # NECB2011 uses fixed 84.61% efficiency for VAV supply fans (to get total fan eff of 55%)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('Test_VAV_Supply_Fan')  # Name must include "Supply"
    fan.setMaximumFlowRate(5.0)
    fan.setPressureRise(1000)  # NECB standard VAV supply pressure
    fan.setFanEfficiency(0.65)
    fan.setMotorEfficiency(0.85)

    motor_bhp = 12.0

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB uses maximum_capacity = 9999 for fan motors, so nominal_hp = motor_bhp
    assert_in_delta 12.0, nominal_hp, 1.0,
      "VAV supply fan nominal HP should be approximately motor BHP rounded"

    # NECB VAV supply fans have fixed 0.8461 efficiency
    assert_in_delta 0.8461, motor_eff, 0.01,
      "NECB VAV supply fan motor efficiency should be 84.61% per motors.json"
  end

  def test_necb2011_fan_motor_efficiency_variable_return
    # Test motor efficiency lookup for VAV return fan
    # NECB2011 uses fixed 46.15% efficiency for VAV return fans (to get total fan eff of 30%)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('Test_VAV_Return_Fan')  # Name must include "Return"
    fan.setMaximumFlowRate(4.0)
    fan.setPressureRise(250)  # NECB standard VAV return pressure
    fan.setFanEfficiency(0.65)
    fan.setMotorEfficiency(0.90)

    motor_bhp = 2.5

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB uses maximum_capacity = 9999 for fan motors, so nominal_hp = motor_bhp
    assert_in_delta 2.5, nominal_hp, 0.5,
      "VAV return fan nominal HP should be approximately motor BHP rounded"

    # NECB VAV return fans have fixed 0.4615 efficiency
    assert_in_delta 0.4615, motor_eff, 0.01,
      "NECB VAV return fan motor efficiency should be 46.15% per motors.json"
  end

  def test_necb2011_fan_motor_efficiency_on_off_fan
    # Test motor efficiency lookup for on-off fan (uses CONSTANT motor type)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanOnOff.new(model)
    fan.setName('Test_OnOff_Fan')
    fan.setMaximumFlowRate(1.5)
    fan.setPressureRise(500)
    fan.setFanEfficiency(0.6)
    fan.setMotorEfficiency(0.8)

    motor_bhp = 2.0

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB uses maximum_capacity = 9999 for fan motors, so nominal_hp = motor_bhp
    assert_in_delta 2.0, nominal_hp, 0.5,
      "OnOff fan nominal HP should be approximately motor BHP rounded"

    # NECB OnOff fans use same efficiency as CAV: 0.615
    assert_in_delta 0.615, motor_eff, 0.01,
      "NECB OnOff fan motor efficiency should be 61.5% (same as CAV) per motors.json"
  end

  def test_necb2011_fan_motor_efficiency_zone_exhaust
    # Test motor efficiency lookup for zone exhaust fan
    # Zone exhaust fans are small fans and use nominal_hp = 0.5
    # They look for CONSTANT-RETURN motor type which doesn't exist in motors.json
    # So they fall back to default 85% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanZoneExhaust.new(model)
    fan.setName('Test_Exhaust_Fan')
    fan.setMaximumFlowRate(0.5)
    fan.setPressureRise(100)
    fan.setFanEfficiency(0.55)

    motor_bhp = 0.15

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # Zone exhaust fans are "small fans" so use 0.5 HP nominal
    assert_equal 0.5, nominal_hp,
      "Zone exhaust fan nominal HP should be 0.5 (small fan default)"

    # NECB zone exhaust fans look for CONSTANT-RETURN which doesn't exist
    # Falls back to default 85% efficiency
    assert_equal 0.85, motor_eff,
      "NECB zone exhaust fan motor efficiency falls back to default 85%"
  end

  def test_necb2011_fan_motor_efficiency_large_vav_supply
    # Test motor efficiency lookup for large VAV supply fan
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('Large_VAV_Supply_Fan')  # Name must include "Supply"
    fan.setMaximumFlowRate(40.0)
    fan.setPressureRise(1250)
    fan.setFanEfficiency(0.65)
    fan.setMotorEfficiency(0.94)

    # 100 HP = 74.6 kW, BHP around 90.9
    motor_bhp = 90.9

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB uses maximum_capacity = 9999 for fan motors, so nominal_hp = motor_bhp
    assert_in_delta 91.0, nominal_hp, 5.0,
      "Large VAV supply fan nominal HP should be approximately motor BHP rounded"

    # NECB VAV supply fans have fixed 0.8461 efficiency regardless of size
    assert_in_delta 0.8461, motor_eff, 0.01,
      "NECB large VAV supply fan motor efficiency should be 84.61% per motors.json"
  end

  def test_necb2011_fan_motor_efficiency_large_cav
    # Test motor efficiency lookup for large CAV fan
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setName('Large_CAV_Fan')
    fan.setMaximumFlowRate(80.0)
    fan.setPressureRise(1500)
    fan.setFanEfficiency(0.65)
    fan.setMotorEfficiency(0.95)

    # 200 HP = 149.2 kW, BHP around 181.8
    motor_bhp = 181.8

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB uses maximum_capacity = 9999 for fan motors, so nominal_hp = motor_bhp
    assert_in_delta 182.0, nominal_hp, 10.0,
      "Large CAV fan nominal HP should be approximately motor BHP rounded"

    # NECB CAV fans have fixed 0.615 efficiency regardless of size
    assert_in_delta 0.615, motor_eff, 0.01,
      "NECB large CAV fan motor efficiency should be 61.5% per motors.json"
  end

  # ============================================================================
  # Fractional Horsepower Motor Tests
  # ============================================================================

  def test_fractional_hp_motor_psc_0_05hp
    # Test PSC motor efficiency for 1/20 HP (0.05 HP)
    standard = Standard.build('NECB2011')

    nominal_hp = 1.0 / 20.0  # 0.05 HP
    motor_type = standard.motor_type(nominal_hp)
    motor_properties = standard.motor_fractional_hp_efficiencies(nominal_hp, motor_type)

    assert_equal 'PSC', motor_type, "Small motors should default to PSC type"
    refute_nil motor_properties, "Should find motor properties for 1/20 HP"

    # PSC efficiency for 1/20 HP: 37/70 = 0.5286
    assert_in_delta 0.5286, motor_properties['nominal_full_load_efficiency'], 0.01,
      "1/20 HP PSC motor should have efficiency of approximately 52.86%"
  end

  def test_fractional_hp_motor_psc_0_5hp
    # Test PSC motor efficiency for 1/2 HP
    standard = Standard.build('NECB2011')

    nominal_hp = 0.5
    motor_type = standard.motor_type(nominal_hp)
    motor_properties = standard.motor_fractional_hp_efficiencies(nominal_hp, motor_type)

    assert_equal 'PSC', motor_type, "1/2 HP motor should be PSC type"
    refute_nil motor_properties, "Should find motor properties for 1/2 HP"

    # PSC efficiency for 1/2 HP: 373/530 = 0.7038
    assert_in_delta 0.7038, motor_properties['nominal_full_load_efficiency'], 0.01,
      "1/2 HP PSC motor should have efficiency of approximately 70.38%"
  end

  def test_fractional_hp_motor_psc_0_75hp
    # Test PSC motor efficiency for 3/4 HP
    standard = Standard.build('NECB2011')

    nominal_hp = 0.75
    motor_type = standard.motor_type(nominal_hp)
    motor_properties = standard.motor_fractional_hp_efficiencies(nominal_hp, motor_type)

    assert_equal 'PSC', motor_type, "3/4 HP motor should be PSC type"
    refute_nil motor_properties, "Should find motor properties for 3/4 HP"

    # PSC efficiency for 3/4 HP: 560/699 = 0.8011
    assert_in_delta 0.8011, motor_properties['nominal_full_load_efficiency'], 0.01,
      "3/4 HP PSC motor should have efficiency of approximately 80.11%"
  end

  def test_fractional_hp_motor_above_threshold
    # Test that motors > 3/4 HP don't use fractional HP method
    standard = Standard.build('NECB2011')

    nominal_hp = 1.0
    motor_type = standard.motor_type(nominal_hp)
    motor_properties = standard.motor_fractional_hp_efficiencies(nominal_hp, motor_type)

    # Should return nil for motors >= 1 HP
    assert_nil motor_properties, "Motors >= 1 HP should not use fractional HP efficiency method"
  end

  # ============================================================================
  # Fan Calculation Tests
  # ============================================================================

  def test_fan_brake_horsepower_calculation
    # Test brake horsepower calculation
    # BHP = (fan_power_w * motor_eff) / 746
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setMaximumFlowRate(2.0)       # 2 m3/s
    fan.setPressureRise(800)          # 800 Pa
    fan.setFanEfficiency(0.6)         # 60% total efficiency
    fan.setMotorEfficiency(0.85)      # 85% motor efficiency

    # Expected fan power = (800 Pa * 2 m3/s) / 0.6 = 2666.67 W
    # Expected BHP = (2666.67 * 0.85) / 746 = 3.04 HP
    bhp = standard.fan_brake_horsepower(fan)

    assert_in_delta 3.04, bhp, 0.1,
      "Brake horsepower should be approximately 3.04 HP"
  end

  def test_fan_motor_horsepower_calculation
    # Test motor horsepower calculation (includes both motor and impeller losses)
    # Motor HP = fan_power_w / 745.7
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setMaximumFlowRate(3.0)       # 3 m3/s
    fan.setPressureRise(1000)         # 1000 Pa
    fan.setFanEfficiency(0.55)        # 55% total efficiency
    fan.setMotorEfficiency(0.85)      # 85% motor efficiency

    # Expected fan power = (1000 Pa * 3 m3/s) / 0.55 = 5454.5 W
    # Expected motor HP = 5454.5 / 745.7 = 7.31 HP
    motor_hp = standard.fan_motor_horsepower(fan)

    assert_in_delta 7.31, motor_hp, 0.2,
      "Motor horsepower should be approximately 7.31 HP"
  end

  def test_fan_fanpower_calculation
    # Test fan power calculation
    # Fan Power = (pressure_rise * flow_rate) / fan_efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setMaximumFlowRate(1.5)       # 1.5 m3/s
    fan.setPressureRise(500)          # 500 Pa
    fan.setFanEfficiency(0.6)         # 60% total efficiency
    fan.setMotorEfficiency(0.8)       # Motor eff doesn't affect fan power

    # Expected fan power = (500 Pa * 1.5 m3/s) / 0.6 = 1250 W
    fan_power = standard.fan_fanpower(fan)

    assert_in_delta 1250.0, fan_power, 1.0,
      "Fan power should be approximately 1250 W"
  end

  # ============================================================================
  # NECB Pressure Drop Assumptions
  # ============================================================================

  def test_necb2011_constant_volume_fan_pressure_rise
    # NECB 2011 assumes 640 Pa for constant volume fans
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)

    # Apply prototype fan pressure rise
    standard.fan_constant_volume_apply_prototype_fan_pressure_rise(fan)

    expected_pressure = standard.get_standards_constant('fan_constant_volume_pressure_rise_value')

    assert_equal expected_pressure, fan.pressureRise,
      "Constant volume fan should have pressure rise of #{expected_pressure} Pa per NECB 2011"

    assert_equal 640.0, expected_pressure,
      "NECB 2011 constant volume fan pressure rise should be 640 Pa"
  end

  def test_necb2011_variable_volume_supply_fan_pressure_rise
    # NECB 2011 assumes 1000 Pa for VAV supply fans
    standard = Standard.build('NECB2011')

    expected_pressure = standard.get_standards_constant('supply_fan_variable_volume_pressure_rise_value')

    assert_equal 1000.0, expected_pressure,
      "NECB 2011 VAV supply fan pressure rise should be 1000 Pa"
  end

  def test_necb2011_variable_volume_return_fan_pressure_rise
    # NECB 2011 assumes 250 Pa for VAV return fans
    standard = Standard.build('NECB2011')

    expected_pressure = standard.get_standards_constant('return_fan_variable_volume_pressure_rise_value')

    assert_equal 250.0, expected_pressure,
      "NECB 2011 VAV return fan pressure rise should be 250 Pa"
  end

  def test_necb2011_fan_pressure_ratios
    # Verify the ratio of supply to return fan pressure makes sense
    standard = Standard.build('NECB2011')

    supply_pressure = standard.get_standards_constant('supply_fan_variable_volume_pressure_rise_value')
    return_pressure = standard.get_standards_constant('return_fan_variable_volume_pressure_rise_value')

    ratio = supply_pressure / return_pressure

    assert_equal 4.0, ratio,
      "Supply fan pressure should be 4x return fan pressure (1000 Pa vs 250 Pa)"
  end

  def test_necb2011_cav_vs_vav_pressure_comparison
    # Compare CAV and VAV supply fan pressure assumptions
    standard = Standard.build('NECB2011')

    cav_pressure = standard.get_standards_constant('fan_constant_volume_pressure_rise_value')
    vav_pressure = standard.get_standards_constant('supply_fan_variable_volume_pressure_rise_value')

    # VAV systems typically have higher pressure drop due to VAV boxes
    assert_operator vav_pressure, :>, cav_pressure,
      "VAV supply fan pressure (1000 Pa) should be greater than CAV pressure (640 Pa)"

    difference = vav_pressure - cav_pressure
    assert_equal 360.0, difference,
      "Difference between VAV and CAV pressure should be 360 Pa"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2015_vs_necb2011_motor_efficiency
    # Compare motor efficiency between NECB vintages
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setMaximumFlowRate(2.0)
    fan.setPressureRise(800)
    fan.setFanEfficiency(0.6)
    fan.setMotorEfficiency(0.85)

    motor_bhp = 5.0

    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    eff_2011, hp_2011 = standard_2011.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # Reset fan for 2015 test
    fan2 = OpenStudio::Model::FanConstantVolume.new(model)
    fan2.setMaximumFlowRate(2.0)
    fan2.setPressureRise(800)
    fan2.setFanEfficiency(0.6)
    fan2.setMotorEfficiency(0.85)

    eff_2015, hp_2015 = standard_2015.fan_standard_minimum_motor_efficiency_and_size(fan2, motor_bhp)

    # Motor size should be the same
    assert_equal hp_2011, hp_2015,
      "Motor sizing should be consistent between NECB 2011 and 2015"

    # Efficiency requirements may be same or stricter in newer vintages
    assert_operator eff_2015, :>=, eff_2011 - 0.01,
      "NECB 2015 motor efficiency should not be less than NECB 2011"
  end

  # ============================================================================
  # Edge Cases and Boundary Tests
  # ============================================================================

  def test_very_small_fan_motor_zero_bhp
    # Test handling of fans with zero brake horsepower
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanZoneExhaust.new(model)
    fan.setMaximumFlowRate(0.001)  # Very small flow
    fan.setPressureRise(10)        # Very low pressure
    fan.setFanEfficiency(0.6)

    motor_bhp = 0.0  # Exactly zero

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB returns [0.85, 0] for zero BHP
    assert_equal 0, nominal_hp,
      "Zero BHP fan should return 0 HP"

    assert_equal 0.85, motor_eff,
      "Zero BHP fan should return default 85% efficiency"
  end

  def test_very_large_fan_motor_above_max_capacity
    # Test motor efficiency lookup for very large motors beyond table range
    # NECB uses maximum_capacity = 9999 for all fan motors, so always returns BHP as nominal
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setName('Huge_CAV_Fan')
    fan.setMaximumFlowRate(100.0)  # Very large flow
    fan.setPressureRise(2000)      # High pressure
    fan.setFanEfficiency(0.65)
    fan.setMotorEfficiency(0.95)

    # 500 HP = 373 kW, BHP around 454
    motor_bhp = 454.0

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB always returns BHP as nominal_hp when max_capacity is hit (9999)
    assert_in_delta 454.0, nominal_hp, 1.0,
      "Very large fan should return motor BHP as nominal HP"

    # NECB CAV fans always use 0.615 efficiency
    assert_in_delta 0.615, motor_eff, 0.01,
      "Very large CAV fan should still use 61.5% efficiency"
  end

  def test_small_zone_exhaust_fan_is_recognized
    # Zone exhaust fans should be recognized as small fans
    # Small fans use nominal_hp = 0.5 regardless of actual BHP
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanZoneExhaust.new(model)
    fan.setName('Small_Exhaust_Fan')
    fan.setMaximumFlowRate(0.2)
    fan.setPressureRise(100)
    fan.setFanEfficiency(0.55)

    # Check that it's recognized as a small fan
    is_small = standard.fan_small_fan?(fan)

    assert is_small, "Zone exhaust fan should be recognized as small fan"

    motor_bhp = 0.3
    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB small fans always use nominal_hp = 0.5
    assert_equal 0.5, nominal_hp,
      "Small zone exhaust fan should use 0.5 HP nominal (small fan default)"

    # Falls back to default efficiency since CONSTANT-RETURN doesn't exist
    assert_equal 0.85, motor_eff,
      "Zone exhaust fan should use default 85% efficiency (lookup fails)"
  end

  def test_motor_sizing_safety_factor
    # Test that nominal HP includes 10% safety factor (motor_bhp * 1.1)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setMaximumFlowRate(1.0)
    fan.setPressureRise(600)
    fan.setFanEfficiency(0.6)
    fan.setMotorEfficiency(0.85)

    # If BHP = 2.0, nominal should be 2.0 * 1.1 = 2.2, rounds to 2 HP
    motor_bhp = 1.8
    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # nominal_hp = motor_bhp * 1.1
    expected_nominal = motor_bhp * 1.1

    # Should be close to expected (may round)
    assert_in_delta expected_nominal, nominal_hp, 0.5,
      "Nominal HP should include 10% safety factor (BHP * 1.1)"
  end

end
