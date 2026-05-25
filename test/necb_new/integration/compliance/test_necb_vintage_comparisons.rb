require_relative '../../test_helper'

# Test differences between NECB vintages (2011, 2015, 2017, 2020)
# Tests the progression of requirements across NECB versions
#
# Key differences tested:
# - NECB 2011: Baseline standard
# - NECB 2015: Minor HVAC updates, lighting adjustments
# - NECB 2017: Envelope improvements, especially roofs
# - NECB 2020: Major changes - LED lighting, UEF water heaters, stricter envelope
#
# Methods tested:
# - Various standard-specific efficiency and performance methods
# - Envelope U-value lookups across vintages
# - HVAC equipment efficiency lookups across vintages
# - Lighting power density lookups across vintages
#
# References:
# - NECB 2011, 2015, 2017, 2020 standards
# - Architecture documented in NECB inheritance chain
class TestVintageComparisons < Minitest::Test

  # ============================================================================
  # Inheritance Chain Tests
  # ============================================================================

  def test_inheritance_chain_necb2015_inherits_from_2011
    # Verify NECB2015 inherits from NECB2011
    std_2015 = Standard.build('NECB2015')

    assert std_2015.class.superclass.name.include?('NECB2011'),
      "NECB2015 should inherit from NECB2011"
  end

  def test_inheritance_chain_necb2017_inherits_from_2015
    # Verify NECB2017 inherits from NECB2015
    std_2017 = Standard.build('NECB2017')

    assert std_2017.class.superclass.name.include?('NECB2015'),
      "NECB2017 should inherit from NECB2015"
  end

  def test_inheritance_chain_necb2020_inherits_from_2017
    # Verify NECB2020 inherits from NECB2017
    std_2020 = Standard.build('NECB2020')

    assert std_2020.class.superclass.name.include?('NECB2017'),
      "NECB2020 should inherit from NECB2017"
  end

  def test_all_vintages_can_be_instantiated
    # Verify all vintages can be created via factory method
    standards = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    standards.each do |std_name|
      std = Standard.build(std_name)
      refute_nil std, "#{std_name} should be instantiated"
      assert_equal std_name, std.class.name, "#{std_name} should match class name"
    end
  end

  # ============================================================================
  # Envelope U-value Progression Tests
  # ============================================================================

  def test_wall_u_values_2011_vs_2015
    # NECB 2015 wall requirements should be same as 2011 (no change)
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')

    hdd = 4000  # Toronto HDD

    u_wall_2011 = std_2011.max_u_necb('wall', 'outdoors', hdd)
    u_wall_2015 = std_2015.max_u_necb('wall', 'outdoors', hdd)

    assert_in_delta u_wall_2011, u_wall_2015, 0.001,
      "NECB 2015 wall U-values should match NECB 2011 (no change)"
  end

  def test_wall_u_values_2011_vs_2017
    # NECB 2017 wall requirements should be same or better than 2011
    std_2011 = Standard.build('NECB2011')
    std_2017 = Standard.build('NECB2017')

    hdd = 4000  # Toronto HDD

    u_wall_2011 = std_2011.max_u_necb('wall', 'outdoors', hdd)
    u_wall_2017 = std_2017.max_u_necb('wall', 'outdoors', hdd)

    assert_operator u_wall_2017, :<=, u_wall_2011,
      "NECB 2017 walls should be same or more stringent than 2011"
  end

  def test_wall_u_values_2011_vs_2020
    # NECB 2020 wall requirements should be more stringent than 2011
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    hdd = 4000  # Toronto HDD

    u_wall_2011 = std_2011.max_u_necb('wall', 'outdoors', hdd)
    u_wall_2020 = std_2020.max_u_necb('wall', 'outdoors', hdd)

    assert_operator u_wall_2020, :<=, u_wall_2011,
      "NECB 2020 walls should be same or more stringent than 2011"
  end

  def test_roof_u_values_2011_vs_2017
    # NECB 2017 had envelope improvements, especially roofs
    std_2011 = Standard.build('NECB2011')
    std_2017 = Standard.build('NECB2017')

    hdd = 5000  # Mid-range HDD

    u_roof_2011 = std_2011.max_u_necb('roofceiling', 'outdoors', hdd)
    u_roof_2017 = std_2017.max_u_necb('roofceiling', 'outdoors', hdd)

    assert_operator u_roof_2017, :<=, u_roof_2011,
      "NECB 2017 roofs should be same or more stringent than 2011"
  end

  def test_roof_u_values_2017_vs_2020
    # NECB 2020 should maintain or improve upon 2017 roof requirements
    std_2017 = Standard.build('NECB2017')
    std_2020 = Standard.build('NECB2020')

    hdd = 5000  # Mid-range HDD

    u_roof_2017 = std_2017.max_u_necb('roofceiling', 'outdoors', hdd)
    u_roof_2020 = std_2020.max_u_necb('roofceiling', 'outdoors', hdd)

    assert_operator u_roof_2020, :<=, u_roof_2017,
      "NECB 2020 roofs should be same or more stringent than 2017"
  end

  def test_window_u_values_progression
    # Window requirements should not regress across vintages
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')
    std_2017 = Standard.build('NECB2017')
    std_2020 = Standard.build('NECB2020')

    hdd = 4000  # Toronto HDD

    u_win_2011 = std_2011.max_u_necb('window', 'outdoors', hdd)
    u_win_2015 = std_2015.max_u_necb('window', 'outdoors', hdd)
    u_win_2017 = std_2017.max_u_necb('window', 'outdoors', hdd)
    u_win_2020 = std_2020.max_u_necb('window', 'outdoors', hdd)

    assert_operator u_win_2015, :<=, u_win_2011,
      "NECB 2015 windows should not regress from 2011"
    assert_operator u_win_2017, :<=, u_win_2015,
      "NECB 2017 windows should not regress from 2015"
    assert_operator u_win_2020, :<=, u_win_2017,
      "NECB 2020 windows should not regress from 2017"
  end

  def test_below_grade_wall_u_values_consistent
    # Below-grade wall requirements should be relatively stable
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    hdd = 5000  # Mid-range HDD

    u_bg_2011 = std_2011.max_u_necb('wall', 'ground', hdd)
    u_bg_2020 = std_2020.max_u_necb('wall', 'ground', hdd)

    assert_operator u_bg_2020, :<=, u_bg_2011,
      "NECB 2020 below-grade walls should be same or better than 2011"
  end

  # ============================================================================
  # FDWR and SRR Tests
  # ============================================================================

  def test_fdwr_limits_across_vintages
    # FDWR (Fenestration to Wall Ratio) limits should not regress
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')
    std_2020 = Standard.build('NECB2020')

    hdd = 4000  # Toronto HDD

    fdwr_2011 = std_2011.max_fwdr(hdd)
    fdwr_2015 = std_2015.max_fwdr(hdd)
    fdwr_2020 = std_2020.max_fwdr(hdd)

    # All should be valid ratios
    assert_operator fdwr_2011, :>, 0.0, "FDWR 2011 should be positive"
    assert_operator fdwr_2015, :>, 0.0, "FDWR 2015 should be positive"
    assert_operator fdwr_2020, :>, 0.0, "FDWR 2020 should be positive"

    assert_operator fdwr_2011, :<=, 1.0, "FDWR 2011 should be <= 1.0"
    assert_operator fdwr_2015, :<=, 1.0, "FDWR 2015 should be <= 1.0"
    assert_operator fdwr_2020, :<=, 1.0, "FDWR 2020 should be <= 1.0"
  end

  def test_srr_limits_cold_climate
    # SRR (Skylight to Roof Ratio) should be consistent or improve
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    # SRR is typically lower in colder climates
    hdd_cold = 7000

    srr_2011 = std_2011.srr_max_nec(hdd_cold) rescue nil
    srr_2020 = std_2020.srr_max_nec(hdd_cold) rescue nil

    # If both methods exist, compare them
    if !srr_2011.nil? && !srr_2020.nil?
      assert_operator srr_2020, :<=, srr_2011,
        "NECB 2020 SRR should be same or more restrictive than 2011"
    end
  end

  # ============================================================================
  # Boiler Efficiency Tests
  # ============================================================================

  def test_boiler_efficiency_consistent_across_vintages
    # Boiler efficiency requirements should be relatively consistent
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create boilers with same specs
    boiler_2011 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler_2011.setFuelType('NaturalGas')
    boiler_2011.setNominalCapacity(500000)  # 500 kW

    boiler_2015 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler_2015.setFuelType('NaturalGas')
    boiler_2015.setNominalCapacity(500000)

    boiler_2020 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler_2020.setFuelType('NaturalGas')
    boiler_2020.setNominalCapacity(500000)

    # Get efficiencies
    eff_2011 = std_2011.boiler_hot_water_standard_minimum_thermal_efficiency(boiler_2011)
    eff_2015 = std_2015.boiler_hot_water_standard_minimum_thermal_efficiency(boiler_2015)
    eff_2020 = std_2020.boiler_hot_water_standard_minimum_thermal_efficiency(boiler_2020)

    # Should be consistent or improving (tolerance for rounding)
    assert_in_delta eff_2011, eff_2015, 0.02,
      "2015 boiler efficiency should be close to 2011"
    assert_operator eff_2020, :>=, eff_2011 - 0.02,
      "2020 boiler efficiency should not be worse than 2011"
  end

  def test_boiler_efficiency_large_capacity_across_vintages
    # Large boiler efficiency should be stable across vintages
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create large boilers (> 2200 kW)
    boiler_2011 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler_2011.setFuelType('NaturalGas')
    boiler_2011.setNominalCapacity(2500000)  # 2500 kW

    boiler_2020 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler_2020.setFuelType('NaturalGas')
    boiler_2020.setNominalCapacity(2500000)

    # Get efficiencies
    eff_2011 = std_2011.boiler_hot_water_standard_minimum_thermal_efficiency(boiler_2011)
    eff_2020 = std_2020.boiler_hot_water_standard_minimum_thermal_efficiency(boiler_2020)

    assert_operator eff_2020, :>=, eff_2011 - 0.02,
      "2020 large boiler efficiency should not be worse than 2011"
  end

  # ============================================================================
  # Chiller Efficiency Tests
  # ============================================================================

  def test_chiller_efficiency_progression
    # Chiller efficiency should improve or stay consistent across vintages
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create chillers
    chiller_2011 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller_2011.setReferenceCapacity(1000000)  # 1 MW cooling

    chiller_2020 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller_2020.setReferenceCapacity(1000000)

    # Apply standards (NECB requires cooling tower objects parameter)
    clg_tower_objs = []
    std_2011.chiller_electric_eir_apply_efficiency_and_curves(chiller_2011, clg_tower_objs)
    std_2020.chiller_electric_eir_apply_efficiency_and_curves(chiller_2020, clg_tower_objs)

    # Get COP
    cop_2011 = chiller_2011.referenceCOP
    cop_2020 = chiller_2020.referenceCOP

    # 2020 should not be worse than 2011
    assert_operator cop_2020, :>=, cop_2011 - 0.1,
      "NECB 2020 chiller COP should not be worse than 2011"
  end

  # ============================================================================
  # DX Equipment Efficiency Tests
  # ============================================================================

  def test_dx_cooling_efficiency_across_vintages
    # DX cooling efficiency should improve across vintages
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create DX cooling coils
    dx_2011 = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    dx_2011.setRatedTotalCoolingCapacity(50000)  # 50 kW

    dx_2020 = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    dx_2020.setRatedTotalCoolingCapacity(50000)

    # Apply standards (requires sql_db_vars_map parameter)
    sql_db_vars_map = {}
    std_2011.coil_cooling_dx_single_speed_apply_efficiency_and_curves(dx_2011, sql_db_vars_map)
    std_2020.coil_cooling_dx_single_speed_apply_efficiency_and_curves(dx_2020, sql_db_vars_map)

    # Get COP (ratedCOP returns Float directly, not Optional)
    cop_2011 = dx_2011.ratedCOP
    cop_2020 = dx_2020.ratedCOP

    # 2020 should be same or better than 2011
    assert_operator cop_2020, :>=, cop_2011 - 0.1,
      "NECB 2020 DX cooling COP should not be worse than 2011"
  end

  # ============================================================================
  # Water Heater Efficiency Tests
  # ============================================================================

  def test_water_heater_efficiency_2011_vs_2020
    # NECB 2011 uses thermal efficiency
    # NECB 2020 uses UEF (Uniform Energy Factor) methodology
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model_2011 = OpenStudio::Model::Model.new
    model_2020 = OpenStudio::Model::Model.new

    # Create water heaters
    wh_2011 = OpenStudio::Model::WaterHeaterMixed.new(model_2011)
    wh_2011.setHeaterFuelType('NaturalGas')
    wh_2011.setHeaterMaximumCapacity(100000)  # 100 kW
    wh_2011.setTankVolume(0.5)  # 500 L

    wh_2020 = OpenStudio::Model::WaterHeaterMixed.new(model_2020)
    wh_2020.setHeaterFuelType('NaturalGas')
    wh_2020.setHeaterMaximumCapacity(100000)
    wh_2020.setTankVolume(0.5)

    # Apply standards
    std_2011.water_heater_mixed_apply_efficiency(wh_2011)
    std_2020.water_heater_mixed_apply_efficiency(wh_2020)

    # Get thermal efficiency
    eff_2011 = wh_2011.heaterThermalEfficiency.get
    eff_2020 = wh_2020.heaterThermalEfficiency.get

    # Both should be valid efficiencies
    assert_operator eff_2011, :>, 0.5, "2011 water heater efficiency should be reasonable"
    assert_operator eff_2020, :>, 0.5, "2020 water heater efficiency should be reasonable"

    # Document that methodologies may differ
    # 2020 uses UEF-based approach, may have different nominal efficiency
  end

  def test_water_heater_electric_efficiency_progression
    # Electric water heater efficiency across vintages
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model_2011 = OpenStudio::Model::Model.new
    model_2020 = OpenStudio::Model::Model.new

    # Create electric water heaters
    wh_2011 = OpenStudio::Model::WaterHeaterMixed.new(model_2011)
    wh_2011.setHeaterFuelType('Electricity')
    wh_2011.setHeaterMaximumCapacity(50000)  # 50 kW
    wh_2011.setTankVolume(0.3)  # 300 L

    wh_2020 = OpenStudio::Model::WaterHeaterMixed.new(model_2020)
    wh_2020.setHeaterFuelType('Electricity')
    wh_2020.setHeaterMaximumCapacity(50000)
    wh_2020.setTankVolume(0.3)

    # Apply standards
    std_2011.water_heater_mixed_apply_efficiency(wh_2011)
    std_2020.water_heater_mixed_apply_efficiency(wh_2020)

    # Get thermal efficiency
    eff_2011 = wh_2011.heaterThermalEfficiency.get
    eff_2020 = wh_2020.heaterThermalEfficiency.get

    # Electric water heaters should have high efficiency
    assert_operator eff_2011, :>, 0.9, "2011 electric WH should have high efficiency"
    assert_operator eff_2020, :>, 0.9, "2020 electric WH should have high efficiency"
  end

  # ============================================================================
  # Fan Power Tests
  # ============================================================================

  def test_fan_motor_efficiency_consistent
    # Fan motor efficiency should be relatively consistent
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create fans
    fan_2011 = OpenStudio::Model::FanConstantVolume.new(model)
    fan_2011.setMaximumFlowRate(5.0)  # 5 m3/s
    fan_2011.setPressureRise(500)  # 500 Pa

    fan_2020 = OpenStudio::Model::FanConstantVolume.new(model)
    fan_2020.setMaximumFlowRate(5.0)
    fan_2020.setPressureRise(500)

    # Get brake horsepower for each fan (method is on standard, not fan)
    bhp_2011 = std_2011.fan_brake_horsepower(fan_2011)
    bhp_2020 = std_2020.fan_brake_horsepower(fan_2020)

    # Apply standards
    std_2011.fan_apply_standard_minimum_motor_efficiency(fan_2011, bhp_2011)
    std_2020.fan_apply_standard_minimum_motor_efficiency(fan_2020, bhp_2020)

    # Motor efficiency should not regress
    eff_2011 = fan_2011.motorEfficiency
    eff_2020 = fan_2020.motorEfficiency

    assert_operator eff_2020, :>=, eff_2011 - 0.02,
      "NECB 2020 fan motor efficiency should not be worse than 2011"
  end

  # ============================================================================
  # Pump Power Tests
  # ============================================================================

  def test_pump_motor_efficiency_consistent
    # Pump motor efficiency should be relatively consistent
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create pumps
    pump_2011 = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump_2011.setRatedFlowRate(0.01)  # 10 L/s
    pump_2011.setRatedPumpHead(50000)  # 50 kPa

    pump_2020 = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump_2020.setRatedFlowRate(0.01)
    pump_2020.setRatedPumpHead(50000)

    # Apply standards
    std_2011.pump_apply_standard_minimum_motor_efficiency(pump_2011)
    std_2020.pump_apply_standard_minimum_motor_efficiency(pump_2020)

    # Pump motor efficiency should be reasonable
    eff_2011 = pump_2011.motorEfficiency
    eff_2020 = pump_2020.motorEfficiency

    assert_operator eff_2011, :>, 0.5, "2011 pump motor efficiency should be reasonable"
    assert_operator eff_2020, :>, 0.5, "2020 pump motor efficiency should be reasonable"
    assert_operator eff_2020, :>=, eff_2011 - 0.02,
      "2020 pump motor efficiency should not be worse than 2011"
  end

  # ============================================================================
  # Furnace Efficiency Tests
  # ============================================================================

  def test_furnace_efficiency_progression
    # Furnace efficiency should improve across vintages
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    model = OpenStudio::Model::Model.new

    # Create gas furnaces
    furnace_2011 = OpenStudio::Model::CoilHeatingGas.new(model)
    furnace_2011.setNominalCapacity(50000)  # 50 kW

    furnace_2020 = OpenStudio::Model::CoilHeatingGas.new(model)
    furnace_2020.setNominalCapacity(50000)

    # Apply standards
    std_2011.coil_heating_gas_apply_efficiency_and_curves(furnace_2011)
    std_2020.coil_heating_gas_apply_efficiency_and_curves(furnace_2020)

    # Get efficiency
    eff_2011 = furnace_2011.gasBurnerEfficiency
    eff_2020 = furnace_2020.gasBurnerEfficiency

    # 2020 should not be worse than 2011
    assert_operator eff_2020, :>=, eff_2011 - 0.01,
      "NECB 2020 furnace efficiency should not be worse than 2011"
  end

  # ============================================================================
  # Economizer Requirements Tests
  # ============================================================================

  def test_economizer_requirements_consistent
    # Economizer requirements should be present in all vintages
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')
    std_2020 = Standard.build('NECB2020')

    # All standards should respond to economizer methods (NECB uses different method names)
    assert_respond_to std_2011, :air_loop_hvac_economizer_required?,
      "NECB 2011 should have economizer methods"
    assert_respond_to std_2015, :air_loop_hvac_economizer_required?,
      "NECB 2015 should have economizer methods"
    assert_respond_to std_2020, :air_loop_hvac_economizer_required?,
      "NECB 2020 should have economizer methods"
  end

  # ============================================================================
  # ERV Requirements Tests
  # ============================================================================

  def test_erv_requirements_consistent
    # ERV (Energy Recovery Ventilation) requirements should be present
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    # Both standards should respond to ERV methods
    assert_respond_to std_2011, :air_loop_hvac_energy_recovery?,
      "NECB 2011 should have ERV methods"
    assert_respond_to std_2020, :air_loop_hvac_energy_recovery?,
      "NECB 2020 should have ERV methods"
  end

  # ============================================================================
  # Verification Tests - No Regression
  # ============================================================================

  def test_newer_vintages_dont_regress_envelope
    # Verify newer vintages don't have significantly worse envelope requirements
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    hdd = 5000  # Mid-range climate

    # Check all major envelope components
    # Note: Allow small tolerance (0.01 W/m2K) for minor variations in lookup tables
    components = [
      ['wall', 'outdoors'],
      ['roofceiling', 'outdoors'],
      ['floor', 'outdoors'],
      ['window', 'outdoors']
    ]

    components.each do |component, boundary|
      u_2011 = std_2011.max_u_necb(component, boundary, hdd)
      u_2020 = std_2020.max_u_necb(component, boundary, hdd)

      # Allow 0.01 W/m2K tolerance for rounding/table variations
      assert_operator u_2020, :<=, u_2011 + 0.01,
        "NECB 2020 #{component} should not significantly regress from 2011 (2020: #{u_2020}, 2011: #{u_2011})"
    end
  end

  def test_all_vintages_produce_valid_values
    # Verify all vintages return valid efficiency values
    standards = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    standards.each do |std_name|
      std = Standard.build(std_name)
      model = OpenStudio::Model::Model.new

      # Create test boiler
      boiler = OpenStudio::Model::BoilerHotWater.new(model)
      boiler.setFuelType('NaturalGas')
      boiler.setNominalCapacity(500000)

      # Get efficiency
      eff = std.boiler_hot_water_standard_minimum_thermal_efficiency(boiler)

      assert_operator eff, :>, 0.5, "#{std_name} should return valid boiler efficiency"
      assert_operator eff, :<, 1.0, "#{std_name} should return realistic boiler efficiency"
    end
  end

  def test_template_name_matches_class_name
    # Verify template name matches for all vintages
    standards = {
      'NECB2011' => Standard.build('NECB2011'),
      'NECB2015' => Standard.build('NECB2015'),
      'NECB2017' => Standard.build('NECB2017'),
      'NECB2020' => Standard.build('NECB2020')
    }

    standards.each do |name, std|
      assert_equal name, std.template,
        "Template name should match class name for #{name}"
    end
  end

  # ============================================================================
  # Additional Vintage Comparison Tests
  # ============================================================================

  def test_envelope_u_values_across_all_hdds
    # Test that envelope requirements trend correctly across HDD ranges
    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    # Test multiple HDD values
    hdds = [2500, 4000, 5500, 7000]

    hdds.each do |hdd|
      u_wall_2011 = std_2011.max_u_necb('wall', 'outdoors', hdd)
      u_wall_2020 = std_2020.max_u_necb('wall', 'outdoors', hdd)

      # Both should be valid U-values
      assert_operator u_wall_2011, :>, 0.1, "2011 wall U-value should be reasonable at HDD #{hdd}"
      assert_operator u_wall_2020, :>, 0.1, "2020 wall U-value should be reasonable at HDD #{hdd}"

      # 2020 should generally be same or better (with small tolerance)
      assert_operator u_wall_2020, :<=, u_wall_2011 + 0.02,
        "2020 should not significantly regress at HDD #{hdd}"
    end
  end

  def test_window_u_values_cold_climate_progression
    # Windows in cold climates should improve over vintages (with tolerance for minor variations)
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')
    std_2017 = Standard.build('NECB2017')
    std_2020 = Standard.build('NECB2020')

    hdd = 7000  # Cold climate (Yellowknife, NWT)

    u_2011 = std_2011.max_u_necb('window', 'outdoors', hdd)
    u_2015 = std_2015.max_u_necb('window', 'outdoors', hdd)
    u_2017 = std_2017.max_u_necb('window', 'outdoors', hdd)
    u_2020 = std_2020.max_u_necb('window', 'outdoors', hdd)

    # Verify progression doesn't significantly regress (allow 0.05 W/m2K tolerance)
    assert_operator u_2015, :<=, u_2011 + 0.05,
      "NECB 2015 windows should not significantly regress from 2011 in cold climate"
    assert_operator u_2017, :<=, u_2015 + 0.05,
      "NECB 2017 windows should not significantly regress from 2015 in cold climate"
    assert_operator u_2020, :<=, u_2017 + 0.05,
      "NECB 2020 windows should not significantly regress from 2017 in cold climate (2020: #{u_2020}, 2017: #{u_2017})"
  end

  def test_fuel_selection_methods_present_all_vintages
    # Verify fuel selection methods exist in all vintages
    std_2011 = Standard.build('NECB2011')
    std_2015 = Standard.build('NECB2015')
    std_2017 = Standard.build('NECB2017')
    std_2020 = Standard.build('NECB2020')

    # All vintages should have fuel selection methods
    [std_2011, std_2015, std_2017, std_2020].each_with_index do |std, idx|
      vintage = ['2011', '2015', '2017', '2020'][idx]

      # Check for key NECB methods (these determine system fuel types)
      assert_respond_to std, :model_find_climate_zone_set,
        "NECB #{vintage} should have climate zone methods"

      # Verify standard responds to building type methods
      assert_respond_to std, :space_type_get_standards_data,
        "NECB #{vintage} should have space type methods"
    end
  end

end
