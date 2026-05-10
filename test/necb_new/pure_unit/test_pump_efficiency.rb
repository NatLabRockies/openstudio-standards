require_relative '../test_helper'

# Test pump efficiency lookups and calculations
# Tests the pump motor efficiency and pump power calculation methods without requiring sized pumps
#
# Methods tested:
# - Standard#pump_standard_minimum_motor_efficiency_and_size
# - OpenstudioStandards::HVAC.pump_get_brake_horsepower
# - OpenstudioStandards::HVAC.pump_get_motor_horsepower
# - OpenstudioStandards::HVAC.pump_get_power
# - OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm
# - Standard#motor_fractional_hp_efficiencies
#
# References:
# - NECB 2011 motors.json (Pump Motor Efficiency Requirements)
# - ASHRAE 90.1 Appendix G (Baseline Pump Power Assumptions)
# - EnergyPlus Engineering Reference (Pump Sizing - 0.78 impeller efficiency)
class TestPumpEfficiency < Minitest::Test

  # ============================================================================
  # Motor Efficiency Tests - NECB2011
  # ============================================================================

  def test_necb2011_pump_motor_very_small_fractional_hp
    # Test very small fractional HP pump motor (< 1/12 HP = 0.0833 HP)
    # With bhp = 0.05 HP, nominal_hp = 0.05 * 1.1 = 0.055 HP
    # This falls in fractional HP range (nominal_hp <= 0.75)
    # For 0.055 HP, motor_fractional_hp_efficiencies returns ~0.7 efficiency (1/6 HP category)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create a small pump
    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_Very_Small_Pump_0.05HP')

    # Motor BHP of 0.05 HP (very small)
    motor_bhp = 0.05

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    # Fractional HP motors have lower efficiency (50-70% range)
    assert_operator motor_eff, :>, 0.5,
      "Expected fractional HP motor to have efficiency > 50%"
    assert_operator motor_eff, :<, 0.8,
      "Expected fractional HP motor to have efficiency < 80%"
    assert_operator nominal_hp, :<=, 0.1,
      "Expected nominal HP to be in the smallest pump motor category"
  end

  def test_necb2011_pump_motor_small_1hp
    # Test 1 HP pump motor
    # NECB 2011 motors.json: 1.0 to 1.499 HP -> 85.5% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_1HP_Pump')

    # Motor BHP of 0.95 HP (will be sized to 1 HP motor with 1.1 safety factor)
    motor_bhp = 0.95

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert_in_delta 0.855, motor_eff, 0.01,
      "Expected 1HP pump motor to have 85.5% efficiency per NECB 2011 motors.json"
    assert_in_delta 1.0, nominal_hp, 0.1,
      "Expected nominal HP to be 1 HP"
  end

  def test_necb2011_pump_motor_medium_5hp
    # Test 5 HP pump motor
    # NECB 2011 motors.json: 5.0 to 7.499 HP -> 89.5% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_5HP_Pump')

    # Motor BHP of 4.5 HP (will be sized to 5 HP motor)
    motor_bhp = 4.5

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert_in_delta 0.895, motor_eff, 0.01,
      "Expected 5HP pump motor to have 89.5% efficiency per NECB 2011 motors.json"
    assert_in_delta 5.0, nominal_hp, 0.5,
      "Expected nominal HP to be 5 HP"
  end

  def test_necb2011_pump_motor_large_50hp
    # Test 50 HP pump motor
    # NECB 2011 motors.json: 40 to 49.999 HP -> 94.1% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_50HP_Pump')

    # Motor BHP of 45 HP (will be sized to 50 HP motor)
    motor_bhp = 45.0

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert_in_delta 0.941, motor_eff, 0.01,
      "Expected 50HP pump motor to have 94.1% efficiency per NECB 2011 motors.json"
    assert_in_delta 50.0, nominal_hp, 5.0,
      "Expected nominal HP to be 50 HP"
  end

  def test_necb2011_pump_motor_very_large_200hp
    # Test very large 200 HP pump motor
    # NECB 2011 motors.json: 200 to 9999 HP -> 96.2% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_200HP_Pump')

    # Motor BHP of 180 HP (will be sized to 200 HP motor)
    motor_bhp = 180.0

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert_in_delta 0.962, motor_eff, 0.01,
      "Expected 200HP pump motor to have 96.2% efficiency per NECB 2011 motors.json"
    assert_in_delta 200.0, nominal_hp, 10.0,
      "Expected nominal HP to be 200 HP"
  end

  # ============================================================================
  # Pump Power Calculation Tests
  # ============================================================================

  def test_pump_brake_horsepower_calculation
    # Test brake horsepower calculation
    # bhp = (pressure_rise * flow_rate) / impeller_efficiency / 745.7
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_BHP_Calc_Pump')

    # Set known values
    flow_m3_per_s = 0.01  # 10 L/s = 158.5 GPM
    pressure_rise_pa = 150000  # 150 kPa = 49.5 ftH2O (typical chilled water pump)
    impeller_eff = 0.78  # EnergyPlus default

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)

    # Calculate expected BHP
    pump_power_w = pressure_rise_pa * flow_m3_per_s / impeller_eff
    expected_bhp = pump_power_w / 745.7

    bhp = OpenstudioStandards::HVAC.pump_get_brake_horsepower(pump)

    assert_in_delta expected_bhp, bhp, 0.01,
      "Brake horsepower should match calculated value (#{expected_bhp.round(2)} HP)"
  end

  def test_pump_motor_horsepower_calculation
    # Test motor horsepower calculation (includes motor efficiency)
    # motor_hp = (pressure_rise * flow_rate) / (impeller_eff * motor_eff) / 745.7
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_Motor_HP_Calc_Pump')

    # Set known values
    flow_m3_per_s = 0.02  # 20 L/s = 317 GPM
    pressure_rise_pa = 200000  # 200 kPa = 66 ftH2O
    motor_eff = 0.90
    impeller_eff = 0.78

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)
    pump.setMotorEfficiency(motor_eff)

    # Calculate expected motor HP
    pump_power_w = (pressure_rise_pa * flow_m3_per_s) / (impeller_eff * motor_eff)
    expected_motor_hp = pump_power_w / 745.7

    motor_hp = OpenstudioStandards::HVAC.pump_get_motor_horsepower(pump)

    assert_in_delta expected_motor_hp, motor_hp, 0.01,
      "Motor horsepower should match calculated value (#{expected_motor_hp.round(2)} HP)"
  end

  def test_pump_power_calculation
    # Test total pump power calculation
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_Power_Calc_Pump')

    # Set known values
    flow_m3_per_s = 0.015
    pressure_rise_pa = 179352  # Approximately 60 ftH2O
    motor_eff = 0.88
    impeller_eff = 0.78

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)
    pump.setMotorEfficiency(motor_eff)

    # Calculate expected power
    expected_power_w = (pressure_rise_pa * flow_m3_per_s) / (impeller_eff * motor_eff)

    power_w = OpenstudioStandards::HVAC.pump_get_power(pump)

    assert_in_delta expected_power_w, power_w, 10.0,
      "Pump power should match calculated value (#{expected_power_w.round(0)} W)"
  end

  # ============================================================================
  # Pump Head / W per GPM Tests (ASHRAE 90.1 Appendix G Baseline)
  # ============================================================================

  def test_chilled_water_primary_pump_baseline_power
    # ASHRAE 90.1 Appendix G: Primary-only CHW system = 16 W/GPM
    # For 100 GPM pump: 1600 W
    # NOTE: pump_get_rated_w_per_gpm requires autosized power consumption, not available in pure unit test
    # This test verifies the manual calculation instead
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_CHW_Primary_Pump')

    # 100 GPM = 0.00631 m3/s
    flow_gpm = 100.0
    flow_m3_per_s = OpenStudio.convert(flow_gpm, 'gal/min', 'm^3/s').get

    # Target 16 W/GPM
    target_w_per_gpm = 16.0
    target_power_w = target_w_per_gpm * flow_gpm

    # With impeller eff = 0.78 and motor eff = 0.90
    # pressure_rise = (target_power_w * impeller_eff * motor_eff) / flow_m3_per_s
    motor_eff = 0.90
    impeller_eff = 0.78
    pressure_rise_pa = (target_power_w * impeller_eff * motor_eff) / flow_m3_per_s

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)
    pump.setMotorEfficiency(motor_eff)

    # Calculate power using pump_get_power method
    calculated_power_w = OpenstudioStandards::HVAC.pump_get_power(pump)
    calculated_w_per_gpm = calculated_power_w / flow_gpm

    assert_in_delta target_w_per_gpm, calculated_w_per_gpm, 0.5,
      "CHW primary pump should achieve approximately 16 W/GPM baseline (calculated #{calculated_w_per_gpm.round(1)} W/GPM)"
  end

  def test_chilled_water_secondary_pump_baseline_power
    # ASHRAE 90.1 Appendix G: CHW secondary pump = 13 W/GPM
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_CHW_Secondary_Pump')

    flow_gpm = 150.0
    flow_m3_per_s = OpenStudio.convert(flow_gpm, 'gal/min', 'm^3/s').get

    target_w_per_gpm = 13.0
    target_power_w = target_w_per_gpm * flow_gpm

    motor_eff = 0.88
    impeller_eff = 0.78
    pressure_rise_pa = (target_power_w * impeller_eff * motor_eff) / flow_m3_per_s

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)
    pump.setMotorEfficiency(motor_eff)

    # Calculate power using pump_get_power method
    calculated_power_w = OpenstudioStandards::HVAC.pump_get_power(pump)
    calculated_w_per_gpm = calculated_power_w / flow_gpm

    assert_in_delta target_w_per_gpm, calculated_w_per_gpm, 0.5,
      "CHW secondary pump should achieve approximately 13 W/GPM baseline (calculated #{calculated_w_per_gpm.round(1)} W/GPM)"
  end

  def test_hot_water_pump_baseline_power
    # ASHRAE 90.1 Appendix G: HW pump = 19 W/GPM
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_HW_Pump')

    flow_gpm = 75.0
    flow_m3_per_s = OpenStudio.convert(flow_gpm, 'gal/min', 'm^3/s').get

    target_w_per_gpm = 19.0
    target_power_w = target_w_per_gpm * flow_gpm

    motor_eff = 0.87
    impeller_eff = 0.78
    pressure_rise_pa = (target_power_w * impeller_eff * motor_eff) / flow_m3_per_s

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)
    pump.setMotorEfficiency(motor_eff)

    # Calculate power using pump_get_power method
    calculated_power_w = OpenstudioStandards::HVAC.pump_get_power(pump)
    calculated_w_per_gpm = calculated_power_w / flow_gpm

    assert_in_delta target_w_per_gpm, calculated_w_per_gpm, 0.5,
      "HW pump should achieve approximately 19 W/GPM baseline (calculated #{calculated_w_per_gpm.round(1)} W/GPM)"
  end

  def test_condenser_water_pump_baseline_power
    # ASHRAE 90.1 Appendix G: Condenser water pump = 22 W/GPM
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_CW_Pump')

    flow_gpm = 300.0  # Larger condenser water pump
    flow_m3_per_s = OpenStudio.convert(flow_gpm, 'gal/min', 'm^3/s').get

    target_w_per_gpm = 22.0
    target_power_w = target_w_per_gpm * flow_gpm

    motor_eff = 0.92
    impeller_eff = 0.78
    pressure_rise_pa = (target_power_w * impeller_eff * motor_eff) / flow_m3_per_s

    pump.setRatedFlowRate(flow_m3_per_s)
    pump.setRatedPumpHead(pressure_rise_pa)
    pump.setMotorEfficiency(motor_eff)

    # Calculate power using pump_get_power method
    calculated_power_w = OpenstudioStandards::HVAC.pump_get_power(pump)
    calculated_w_per_gpm = calculated_power_w / flow_gpm

    assert_in_delta target_w_per_gpm, calculated_w_per_gpm, 0.5,
      "Condenser water pump should achieve approximately 22 W/GPM baseline (calculated #{calculated_w_per_gpm.round(1)} W/GPM)"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2015_vs_necb2011_pump_motor_efficiency
    # Compare NECB 2015 to NECB 2011 for same pump motor size
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_10HP_Pump')

    motor_bhp = 9.0  # Will be sized to 10 HP

    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    eff_2011, hp_2011 = standard_2011.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)
    eff_2015, hp_2015 = standard_2015.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    # NECB 2015 should have same or better efficiency than 2011
    assert_operator eff_2015, :>=, eff_2011 - 0.01,
      "NECB 2015 pump motor efficiency should not be worse than NECB 2011"
    assert_equal hp_2011, hp_2015,
      "Nominal HP sizing should be consistent between vintages"
  end

  def test_necb2020_vs_necb2011_pump_motor_efficiency
    # Compare NECB 2020 to NECB 2011 for same pump motor size
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_25HP_Pump')

    motor_bhp = 22.0  # Will be sized to 25 HP

    standard_2011 = Standard.build('NECB2011')
    standard_2020 = Standard.build('NECB2020')

    eff_2011, hp_2011 = standard_2011.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)
    eff_2020, hp_2020 = standard_2020.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    # NECB 2020 should have same or better efficiency than 2011
    assert_operator eff_2020, :>=, eff_2011 - 0.01,
      "NECB 2020 pump motor efficiency should not be worse than NECB 2011"
  end

  # ============================================================================
  # Edge Cases and Boundary Tests
  # ============================================================================

  def test_zero_hp_pump_motor
    # Test zero HP pump (circulation-pump-free service water heating)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_Zero_HP_Pump')

    motor_bhp = 0.0

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert_equal 1.0, motor_eff,
      "Zero HP pump should return 100% efficiency (placeholder)"
    assert_equal 0, nominal_hp,
      "Zero HP pump should return 0 nominal HP"
  end

  def test_very_small_pump_under_1_watt
    # Test pump under 1 watt (< 0.0001 HP)
    # Note: NECB2011 override only checks for motor_bhp == 0.0 (exact equality)
    # So very small non-zero pumps still look up efficiency in motors.json
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Test_Micro_Pump')

    motor_bhp = 0.00005  # Less than 0.0001 HP (under 1 watt)

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    # NECB looks up in motors.json: 0 to 0.08333 HP -> 70% efficiency
    # The lookup returns maximum_capacity which is 0.08333, then rounded to 0.1
    assert_in_delta 0.70, motor_eff, 0.05,
      "Very small pump should return efficiency from smallest motors.json category (70%)"
    assert_operator nominal_hp, :<=, 0.1,
      "Very small pump nominal HP should be in smallest category (0.1 HP after rounding)"
  end

  def test_boundary_1hp_motor_sizing
    # Test pump at 1 HP boundary
    # Below 1 HP uses fractional HP method, at/above 1 HP uses motors table
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName('Test_Boundary_1HP_Pump')

    # Test just below 1 HP (after 1.1 safety factor)
    motor_bhp_low = 0.85  # Will be sized to 0.935 HP nominal (below 1 HP)
    motor_eff_low, nominal_hp_low = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp_low)

    # Test at 1 HP (after 1.1 safety factor)
    motor_bhp_high = 0.95  # Will be sized to 1.045 HP nominal (at 1 HP)
    motor_eff_high, nominal_hp_high = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp_high)

    # Both should return valid efficiencies
    assert_operator motor_eff_low, :>, 0.6, "Motor efficiency should be greater than 60%"
    assert_operator motor_eff_low, :<, 1.0, "Motor efficiency should be less than 100%"
    assert_operator motor_eff_high, :>, 0.6, "Motor efficiency should be greater than 60%"
    assert_operator motor_eff_high, :<, 1.0, "Motor efficiency should be less than 100%"
  end

  def test_fractional_hp_motor_efficiency_psc
    # Test fractional HP motor efficiency for PSC (Permanent Split Capacitor) motors
    standard = Standard.build('NECB2011')

    # Test 1/3 HP motor
    nominal_hp = 1.0 / 3.0
    motor_type = standard.motor_type(nominal_hp)
    motor_properties = standard.motor_fractional_hp_efficiencies(nominal_hp, motor_type)

    refute_nil motor_properties,
      "Should return motor properties for 1/3 HP PSC motor"
    assert_operator motor_properties['nominal_full_load_efficiency'], :>, 0.5,
      "Fractional HP motor efficiency should be greater than 50%"
    assert_operator motor_properties['nominal_full_load_efficiency'], :<, 0.8,
      "Fractional HP motor efficiency should be less than 80%"
  end

  def test_variable_vs_constant_speed_pump_power
    # Test that variable speed pumps can achieve same power as constant speed
    model = OpenStudio::Model::Model.new

    # Create constant speed pump
    pump_constant = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump_constant.setName('Test_Constant_Speed')

    # Create variable speed pump
    pump_variable = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump_variable.setName('Test_Variable_Speed')

    # Set identical parameters
    flow_m3_per_s = 0.012
    pressure_rise_pa = 180000
    motor_eff = 0.89

    [pump_constant, pump_variable].each do |pump|
      pump.setRatedFlowRate(flow_m3_per_s)
      pump.setRatedPumpHead(pressure_rise_pa)
      pump.setMotorEfficiency(motor_eff)
    end

    power_constant = OpenstudioStandards::HVAC.pump_get_power(pump_constant)
    power_variable = OpenstudioStandards::HVAC.pump_get_power(pump_variable)

    assert_in_delta power_constant, power_variable, 1.0,
      "Variable and constant speed pumps with identical parameters should have same rated power"
  end

  def test_motor_efficiency_increases_with_size
    # Test that motor efficiency generally increases with motor size
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)

    # Test series of increasing motor sizes
    test_sizes = [1.0, 5.0, 10.0, 25.0, 50.0, 100.0]
    efficiencies = []

    test_sizes.each do |bhp|
      motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, bhp)
      efficiencies << motor_eff
    end

    # Check that efficiency generally increases (allowing for some plateaus)
    # Last efficiency should be higher than first
    assert_operator efficiencies.last, :>, efficiencies.first,
      "Motor efficiency should generally increase with motor size (#{efficiencies.first.round(3)} to #{efficiencies.last.round(3)})"
  end

end
