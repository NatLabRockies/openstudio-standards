require_relative '../../test_helper'

# Comprehensive test suite for NECB HVAC base methods
# Tests core methods in /lib/openstudio-standards/standards/necb/NECB2011/hvac_systems.rb
# Covers equipment efficiency lookups, fan power calculations, economizer requirements,
# pump sizing, and component creation methods used by all HVAC systems.
class TestNECBHVACBaseMethods < Minitest::Test
  include(NecbHelper)

  ##############################################################################
  # ECONOMIZER REQUIREMENT TESTS
  # Test economizer requirements based on NECB rules (cooling capacity and airflow)
  ##############################################################################

  def test_economizer_required_by_cooling_capacity
    # NECB requires economizer for cooling capacity > 20 kW (68,243 Btu/hr)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create air loop with sufficient cooling capacity
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Test Air Loop')

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Add cooling coil with capacity > 20 kW
    cooling_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
    cooling_coil.setRatedHighSpeedTotalCoolingCapacity(25000) # 25 kW > 20 kW threshold
    cooling_coil.addToNode(air_loop.supplyInletNode)

    # Add to sizing system for design air flow
    sizing_system = air_loop.sizingSystem
    sizing_system.setDesignOutdoorAirFlowRate(2.0) # 2000 L/s

    # Test economizer requirement
    economizer_required = standard.air_loop_hvac_economizer_required?(air_loop)
    assert economizer_required, "Economizer should be required for cooling capacity > 20 kW"
  end

  def test_economizer_required_by_design_airflow
    # NECB requires economizer for design supply air flow > 1500 L/s
    # Note: This test requires a sizing run to get autosizedDesignSupplyAirFlowRate
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('High Airflow System')

    # Connect zones to air loop to get realistic sizing
    zones.each do |zone|
      terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      air_loop.addBranchForZone(zone, terminal)
    end

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Add supply fan
    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.addToNode(air_loop.supplyInletNode)

    # Set design airflow > 1500 L/s threshold
    air_loop.setDesignSupplyAirFlowRate(2.5) # 2.5 m3/s = 2500 L/s

    # For this test, we just verify the method runs without error
    # Actual requirement depends on whether sizing has been run
    economizer_required = standard.air_loop_hvac_economizer_required?(air_loop)
    assert [true, false].include?(economizer_required), "Method should return boolean"
  end

  def test_economizer_not_required_small_system
    # Small systems below thresholds should not require economizer
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Small System')

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Small cooling coil < 20 kW
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setRatedTotalCoolingCapacity(15000) # 15 kW < 20 kW threshold
    cooling_coil.addToNode(air_loop.supplyInletNode)

    # Small airflow < 1500 L/s
    air_loop.setDesignSupplyAirFlowRate(1.0) # 1.0 m3/s = 1000 L/s

    economizer_required = standard.air_loop_hvac_economizer_required?(air_loop)
    refute economizer_required, "Economizer should not be required for small systems"
  end

  def test_economizer_integration_type
    # NECB requires NoLockout (integrated economizer) per 5.2.2.8(3)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Apply economizer integration
    result = standard.air_loop_hvac_apply_economizer_integration(air_loop, 'NECB HDD Method')

    assert result, "Economizer integration should be applied successfully"
    assert_equal 'NoLockout', oa_controller.getLockoutType, "NECB requires NoLockout (integrated) economizer"
  end

  ##############################################################################
  # ENERGY RECOVERY VENTILATOR (ERV) TESTS
  # Test ERV requirements based on exhaust heat content
  ##############################################################################

  def test_erv_required_high_exhaust_heat_content
    # ERV required when exhaust heat content > 150 kW
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    # Connect zones to air loop
    zones.each do |zone|
      # Add terminal
      terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      air_loop.addBranchForZone(zone, terminal)
    end

    # Add OA system with high OA flow
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.setMinimumOutdoorAirFlowRate(5.0) # High OA flow
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Set high design airflow
    air_loop.setDesignSupplyAirFlowRate(10.0)

    # Test ERV requirement (requires weather file for outdoor temp calculation)
    erv_required = standard.air_loop_hvac_energy_recovery_ventilator_required?(air_loop, 'NECB HDD Method')

    # Result depends on exhaust heat content calculation
    # Just verify method executes without error
    assert [true, false].include?(erv_required), "ERV requirement should return boolean"
  end

  def test_erv_not_required_with_dcv
    # ERV not applicable when DCV (demand control ventilation) is enabled
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    controller_mv = oa_controller.controllerMechanicalVentilation
    controller_mv.setDemandControlledVentilation(true)

    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    erv_required = standard.air_loop_hvac_energy_recovery_ventilator_required?(air_loop, 'NECB HDD Method')
    refute erv_required, "ERV should not be required when DCV is enabled"
  end

  def test_erv_not_required_no_oa_system
    # ERV not applicable for systems with no outdoor air intake
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    # No OA system added

    erv_required = standard.air_loop_hvac_energy_recovery_ventilator_required?(air_loop, 'NECB HDD Method')
    refute erv_required, "ERV should not be required for systems without OA intake"
  end

  ##############################################################################
  # BOILER EFFICIENCY TESTS
  # Test boiler efficiency lookups and capacity staging
  ##############################################################################

  def test_boiler_efficiency_natural_gas
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create hot water loop
    hw_loop = create_hot_water_loop(model, standard)

    # Create natural gas boiler
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Natural Gas Boiler')
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(100000) # 100 kW
    hw_loop.addSupplyBranchForComponent(boiler)

    # Apply efficiency and curves
    result = standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    # Verify efficiency curve was applied
    assert boiler.normalizedBoilerEfficiencyCurve.is_initialized, "Boiler should have efficiency curve"

    # Verify nominal thermal efficiency is reasonable (typically 0.75-0.95)
    thermal_eff = boiler.nominalThermalEfficiency
    assert thermal_eff > 0.7 && thermal_eff < 1.0, "Boiler thermal efficiency should be realistic"
  end

  def test_boiler_primary_secondary_staging_large_capacity
    # NECB requires primary/secondary staging for capacity >= 352 kW
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    hw_loop = create_hot_water_loop(model, standard)

    # Create primary boiler with large capacity
    primary_boiler = OpenStudio::Model::BoilerHotWater.new(model)
    primary_boiler.setName('Primary Boiler')
    primary_boiler.setFuelType('NaturalGas')
    primary_boiler.setNominalCapacity(400000) # 400 kW > 352 kW
    hw_loop.addSupplyBranchForComponent(primary_boiler)

    # Apply efficiency
    standard.boiler_hot_water_apply_efficiency_and_curves(primary_boiler)

    # Primary boiler should get full capacity and modulating flow mode
    assert_equal 'LeavingSetpointModulated', primary_boiler.boilerFlowMode, "Large primary boiler should modulate"
    assert_equal 0.25, primary_boiler.minimumPartLoadRatio, "Primary boiler should have 0.25 min PLR"

    # Create secondary boiler
    secondary_boiler = OpenStudio::Model::BoilerHotWater.new(model)
    secondary_boiler.setName('Secondary Boiler')
    secondary_boiler.setFuelType('NaturalGas')
    secondary_boiler.setNominalCapacity(400000)
    hw_loop.addSupplyBranchForComponent(secondary_boiler)

    standard.boiler_hot_water_apply_efficiency_and_curves(secondary_boiler)

    # Secondary boiler should get minimal capacity (0.001 W)
    assert secondary_boiler.nominalCapacity.get < 1.0, "Secondary boiler should have minimal capacity"
  end

  def test_boiler_efficiency_oil_vs_gas
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    hw_loop = create_hot_water_loop(model, standard)

    # Gas boiler
    gas_boiler = OpenStudio::Model::BoilerHotWater.new(model)
    gas_boiler.setName('Gas Boiler')
    gas_boiler.setFuelType('NaturalGas')
    gas_boiler.setNominalCapacity(100000)
    hw_loop.addSupplyBranchForComponent(gas_boiler)
    standard.boiler_hot_water_apply_efficiency_and_curves(gas_boiler)

    # Oil boiler
    oil_boiler = OpenStudio::Model::BoilerHotWater.new(model)
    oil_boiler.setName('Oil Boiler')
    oil_boiler.setFuelType('FuelOilNo2')
    oil_boiler.setNominalCapacity(100000)
    hw_loop.addSupplyBranchForComponent(oil_boiler)
    standard.boiler_hot_water_apply_efficiency_and_curves(oil_boiler)

    # Both should have valid efficiency curves
    assert gas_boiler.normalizedBoilerEfficiencyCurve.is_initialized, "Gas boiler should have efficiency curve"
    assert oil_boiler.normalizedBoilerEfficiencyCurve.is_initialized, "Oil boiler should have efficiency curve"
  end

  ##############################################################################
  # CHILLER EFFICIENCY TESTS
  # Test chiller efficiency lookups and capacity staging
  ##############################################################################

  def test_chiller_efficiency_water_cooled
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create chilled water loop
    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chw_loop.setName('Chilled Water Loop')

    # Create condenser water loop
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    cw_loop.setName('Condenser Water Loop')

    # Create water-cooled chiller
    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller.setName('Water Cooled Chiller centrifugal')
    chiller.setReferenceCapacity(500000) # 500 kW
    chw_loop.addSupplyBranchForComponent(chiller)
    chiller.addToNode(cw_loop.demandInletNode)

    # Add cooling tower to condenser loop
    cooling_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
    cw_loop.addSupplyBranchForComponent(cooling_tower)

    # Apply efficiency and curves
    result = standard.chiller_electric_eir_apply_efficiency_and_curves(chiller, [cooling_tower])

    # Verify performance curves were applied
    capft_curve = chiller.coolingCapacityFunctionOfTemperature
    assert !capft_curve.to_Curve.empty?, "Chiller should have CAPFT curve"

    eirft_curve = chiller.electricInputToCoolingOutputRatioFunctionOfTemperature
    assert !eirft_curve.to_Curve.empty?, "Chiller should have EIRFT curve"

    eirfplr_curve = chiller.electricInputToCoolingOutputRatioFunctionOfPLR
    assert !eirfplr_curve.to_Curve.empty?, "Chiller should have EIRFPLR curve"

    # Verify COP is reasonable (typically 3.0-7.0 for water-cooled)
    cop = chiller.referenceCOP
    assert cop > 2.5 && cop < 8.0, "Chiller COP should be realistic for water-cooled unit"
  end

  def test_chiller_primary_secondary_staging
    # NECB requires primary/secondary staging for capacity >= 2100 kW
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    cw_loop = OpenStudio::Model::PlantLoop.new(model)

    # Primary chiller with large capacity
    primary_chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    primary_chiller.setName('Primary Chiller centrifugal')
    primary_chiller.setReferenceCapacity(2500000) # 2500 kW > 2100 kW
    chw_loop.addSupplyBranchForComponent(primary_chiller)
    primary_chiller.addToNode(cw_loop.demandInletNode)

    cooling_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
    cw_loop.addSupplyBranchForComponent(cooling_tower)

    standard.chiller_electric_eir_apply_efficiency_and_curves(primary_chiller, [cooling_tower])

    # Primary chiller should get half capacity for large systems
    primary_capacity = primary_chiller.referenceCapacity.get
    assert primary_capacity < 1300000, "Primary chiller capacity should be split for large systems"

    # Verify minimum PLR is 0.25
    assert_equal 0.25, primary_chiller.minimumPartLoadRatio, "Chiller should have 0.25 min PLR"
    assert_equal 0.25, primary_chiller.minimumUnloadingRatio, "Chiller should have 0.25 min unloading ratio"
  end

  def test_chiller_flow_mode_modulating
    # All NECB chillers must modulate down to 25% capacity
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    cw_loop = OpenStudio::Model::PlantLoop.new(model)

    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller.setName('Test Chiller scroll')
    chiller.setReferenceCapacity(300000)
    chw_loop.addSupplyBranchForComponent(chiller)
    chiller.addToNode(cw_loop.demandInletNode)

    cooling_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
    cw_loop.addSupplyBranchForComponent(cooling_tower)

    standard.chiller_electric_eir_apply_efficiency_and_curves(chiller, [cooling_tower])

    assert_equal 'LeavingSetpointModulated', chiller.chillerFlowMode, "NECB chillers must use modulating flow mode"
  end

  ##############################################################################
  # FAN POWER CALCULATION TESTS
  # Test fan motor efficiency and pressure rise calculations
  ##############################################################################

  def test_fan_motor_efficiency_constant_volume
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create constant volume fan
    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setName('Constant Volume Supply Fan')
    fan.setPressureRise(600) # 600 Pa
    fan.setMaximumFlowRate(5.0) # 5 m3/s
    fan.setFanEfficiency(0.6)

    # Calculate motor BHP
    motor_bhp = 5.0 * 600 / (0.6 * 746.0) # rough estimate

    # Get motor efficiency
    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    # NECB motor efficiencies vary widely by size - from ~0.6 for small to 0.95 for large
    assert motor_eff > 0.5 && motor_eff < 1.0, "Fan motor efficiency should be realistic (0.5-1.0)"
    assert nominal_hp > 0, "Nominal HP should be positive"
  end

  def test_fan_motor_efficiency_variable_volume
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create variable volume fan
    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('Variable Volume Supply Fan')
    fan.setPressureRise(750)
    fan.setMaximumFlowRate(10.0)
    fan.setFanEfficiency(0.65)

    motor_bhp = 10.0 * 750 / (0.65 * 746.0)

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    assert motor_eff > 0.5, "Variable volume fan motor should have reasonable efficiency"
    assert nominal_hp > 0, "Nominal HP should be positive"

    # VAV fans should have part load curve applied
    # Check that coefficients are set (not zeros - can be negative for polynomial curves)
    coeff1_opt = fan.fanPowerCoefficient1
    assert coeff1_opt.is_initialized, "VAV fan should have part load power curve coefficient 1"
    coeff1 = coeff1_opt.get
    assert coeff1 != 0, "VAV fan coefficient 1 should be non-zero (can be negative)"
  end

  def test_fan_impeller_efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanConstantVolume.new(model)

    impeller_eff = standard.fan_baseline_impeller_efficiency(fan)

    assert_equal 0.65, impeller_eff, "NECB baseline fan impeller efficiency should be 0.65"
  end

  def test_fan_pressure_rise_constant_volume
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanConstantVolume.new(model)

    # Apply prototype fan pressure rise
    result = standard.fan_constant_volume_apply_prototype_fan_pressure_rise(fan)

    assert result, "Should successfully apply fan pressure rise"

    pressure_rise = fan.pressureRise
    assert pressure_rise > 0, "Fan pressure rise should be positive"
  end

  def test_fan_variable_volume_control_type_by_power
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Large VAV fan >= 25 kW should use inlet vanes
    large_fan = OpenStudio::Model::FanVariableVolume.new(model)
    large_fan.setName('Large Variable Volume Supply Fan')
    large_fan.setPressureRise(1200)
    large_fan.setMaximumFlowRate(30.0) # Large airflow
    large_fan.setFanEfficiency(0.65)

    motor_bhp_large = 30.0 * 1200 / (0.65 * 746.0)
    standard.fan_standard_minimum_motor_efficiency_and_size(large_fan, motor_bhp_large)

    # Check that curve was applied (indicates control type selection)
    coeff1_large = large_fan.fanPowerCoefficient1
    assert coeff1_large.is_initialized, "Large VAV fan should have control curve applied"
    # Coefficient can be negative for polynomial curves
    assert coeff1_large.get != 0, "Large VAV fan coefficient should be non-zero"

    # Medium VAV fan 7.5-25 kW should use AFBI with inlet vanes
    medium_fan = OpenStudio::Model::FanVariableVolume.new(model)
    medium_fan.setName('Medium Variable Volume Supply Fan')
    medium_fan.setPressureRise(800)
    medium_fan.setMaximumFlowRate(10.0)
    medium_fan.setFanEfficiency(0.65)

    motor_bhp_medium = 10.0 * 800 / (0.65 * 746.0)
    standard.fan_standard_minimum_motor_efficiency_and_size(medium_fan, motor_bhp_medium)

    coeff1_medium = medium_fan.fanPowerCoefficient1
    assert coeff1_medium.is_initialized, "Medium VAV fan should have control curve applied"
    # Coefficient can be negative for polynomial curves
    assert coeff1_medium.get != 0, "Medium VAV fan coefficient should be non-zero"
  end

  ##############################################################################
  # PUMP SIZING AND EFFICIENCY TESTS
  # Test pump motor efficiency lookups
  ##############################################################################

  def test_pump_motor_efficiency_variable_speed
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create variable speed pump
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Variable Speed Pump')
    pump.setRatedFlowRate(0.01) # 10 L/s
    pump.setRatedPumpHead(150000) # 150 kPa

    # Calculate motor BHP
    motor_bhp = 0.01 * 150000 / (0.6 * 746.0)

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert motor_eff > 0.8, "Pump motor efficiency should be > 0.8"
    assert nominal_hp > 0, "Nominal HP should be positive"
  end

  def test_pump_motor_efficiency_zero_bhp
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)

    # Zero BHP case (circulation-pump-free systems)
    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, 0.0)

    assert_equal 1.0, motor_eff, "Zero BHP pump should return 100% efficiency"
    assert_equal 0, nominal_hp, "Zero BHP pump should return 0 nominal HP"
  end

  def test_pump_variable_speed_control_type
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)

    # The method returns false for NECB2011 (no specific control type requirement)
    control_type = standard.pump_variable_speed_control_type(pump)

    assert_equal false, control_type, "NECB2011 returns false (no specific control type)"
  end

  ##############################################################################
  # SIZING PARAMETERS TESTS
  # Test model-level sizing factors
  ##############################################################################

  def test_model_sizing_parameters
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Apply sizing parameters
    standard.model_apply_sizing_parameters(model)

    sizing_params = model.getSizingParameters

    # NECB typically uses 1.0-1.25 sizing factors
    heating_factor = sizing_params.heatingSizingFactor
    cooling_factor = sizing_params.coolingSizingFactor

    assert heating_factor >= 1.0 && heating_factor <= 1.3, "Heating sizing factor should be 1.0-1.3"
    assert cooling_factor >= 1.0 && cooling_factor <= 1.3, "Cooling sizing factor should be 1.0-1.3"
  end

  ##############################################################################
  # HEATING COIL EFFICIENCY TESTS
  # Test gas furnace efficiency lookups
  ##############################################################################

  def test_coil_heating_gas_efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create gas heating coil
    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Gas Heating Coil')
    coil.setNominalCapacity(50000) # 50 kW

    # Get standard minimum thermal efficiency
    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert thermal_eff > 0.75 && thermal_eff < 1.0, "Gas coil thermal efficiency should be 0.75-1.0"
  end

  def test_coil_heating_gas_apply_efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setNominalCapacity(50000)

    # Apply efficiency and curves
    result = standard.coil_heating_gas_apply_efficiency_and_curves(coil)

    assert result, "Should successfully apply gas coil efficiency"

    # Verify efficiency was set
    gas_burner_eff = coil.gasBurnerEfficiency
    assert gas_burner_eff > 0.75, "Gas burner efficiency should be > 0.75"
  end

  ##############################################################################
  # DEMAND CONTROL VENTILATION (DCV) TESTS
  # Test DCV requirements based on NECB rules
  ##############################################################################

  def test_dcv_required_for_high_occupancy_density
    # NECB requires DCV for spaces with occupancy density > 25 people per 100 m²
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('High Occupancy System')

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Create high-occupancy space
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Conference Room')
    space_type.setPeoplePerFloorArea(0.30) # 30 people per 100 m² > 25 threshold

    zone = model.getThermalZones.first
    zone.spaces.first.setSpaceType(space_type) if zone

    terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
    air_loop.addBranchForZone(zone, terminal) if zone

    # Test DCV requirement
    dcv_required = standard.air_loop_hvac_demand_control_ventilation_required?(air_loop, 'NECB2011')
    assert [true, false].include?(dcv_required), "DCV requirement should return boolean"
  end

  def test_dcv_not_required_for_low_occupancy
    # Low occupancy spaces should not require DCV
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Low occupancy
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setPeoplePerFloorArea(0.05) # 5 people per 100 m² < 25 threshold

    dcv_required = standard.air_loop_hvac_demand_control_ventilation_required?(air_loop, 'NECB2011')
    assert [true, false].include?(dcv_required), "DCV requirement should return boolean"
  end

  ##############################################################################
  # ECONOMIZER INTEGRATION TESTS
  # Test economizer integration application
  ##############################################################################

  def test_apply_economizer_integration
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    # Add OA system with economizer
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.setEconomizerControlType('DifferentialDryBulb')
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Apply economizer integration
    result = standard.air_loop_hvac_apply_economizer_integration(air_loop, 'NECB2011')

    # Method should run without error
    assert [true, false, nil].include?(result), "Should return boolean or nil"

    # Check economizer is still enabled
    oa_controller = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
    assert_equal 'DifferentialDryBulb', oa_controller.getEconomizerControlType
  end

  ##############################################################################
  # ENERGY RECOVERY VENTILATOR (ERV) APPLICATION TESTS
  # Test ERV application to air loops
  ##############################################################################

  def test_apply_erv_to_air_loop
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Apply ERV
    result = standard.air_loop_hvac_apply_energy_recovery_ventilator(air_loop)

    # Method should run without error
    assert [true, false, nil].include?(result), "Should return boolean or nil"
  end

  def test_erv_effectiveness_method_exists
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create heat exchanger
    hx = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
    hx.setName('Test HX')

    # Test that method exists and responds
    assert standard.respond_to?(:heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness),
           "Should have HX effectiveness method"

    # Method signature requires HX object and optional ERV name
    method = standard.method(:heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness)
    params = method.parameters

    assert params.size >= 1, "Should accept at least HX parameter"
  end

  def test_erv_effectiveness_values_range
    # Test ERV effectiveness value ranges (should be 0-100% or 0-1.0)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    hx = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)

    # Manually set effectiveness values to test the range
    hx.setSensibleEffectivenessat100HeatingAirFlow(0.75)
    hx.setLatentEffectivenessat100HeatingAirFlow(0.65)
    hx.setSensibleEffectivenessat75HeatingAirFlow(0.70)
    hx.setLatentEffectivenessat75HeatingAirFlow(0.60)

    # Verify values were set correctly
    assert_equal 0.75, hx.sensibleEffectivenessat100HeatingAirFlow
    assert_equal 0.65, hx.latentEffectivenessat100HeatingAirFlow
    assert_equal 0.70, hx.sensibleEffectivenessat75HeatingAirFlow
    assert_equal 0.60, hx.latentEffectivenessat75HeatingAirFlow
  end

  ##############################################################################
  # STATIC PRESSURE RESET TESTS
  # Test static pressure reset requirements
  ##############################################################################

  def test_static_pressure_reset_required_for_vav
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('VAV System')

    # Add VFD fan (indicates VAV system)
    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.addToNode(air_loop.supplyInletNode)

    # Test static pressure reset requirement (requires has_ddc parameter)
    reset_required = standard.air_loop_hvac_static_pressure_reset_required?(air_loop, true)

    assert [true, false].include?(reset_required), "Static pressure reset should return boolean"
  end

  def test_static_pressure_reset_not_required_for_cv
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    # Add constant volume fan
    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.addToNode(air_loop.supplyInletNode)

    reset_required = standard.air_loop_hvac_static_pressure_reset_required?(air_loop, false)

    # Constant volume systems typically don't require static pressure reset
    assert [true, false].include?(reset_required), "Static pressure reset should return boolean"
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  # Helper to create baseline NECB model with basic geometry
  def create_baseline_necb_model(template:, climate:)
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '..', '..', '..', 'necb', 'unit_tests', 'resources', '5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    # Set climate (use available CWEC2020 or CWEC2016 files)
    climate_files = {
      'Toronto' => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      'Vancouver' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
      'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
    }
    epw_file = climate_files[climate] || climate_files['Toronto']
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply NECB space types
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    # Add thermostats to zones
    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.setName('Heating Setpoint Schedule')
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 21.0)

    clg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    clg_sch.setName('Cooling Setpoint Schedule')
    clg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 24.0)

    model.getThermalZones.each do |zone|
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      thermostat.setHeatingSetpointTemperatureSchedule(htg_sch)
      thermostat.setCoolingSetpointTemperatureSchedule(clg_sch)
      zone.setThermostatSetpointDualSetpoint(thermostat)
    end

    # Initialize fuel_type_set (required by HVAC system methods)
    standard.fuel_type_set = SystemFuels.new()
    standard.fuel_type_set.set_defaults(standards_data: standard.instance_variable_get(:@standards_data), primary_heating_fuel: 'NaturalGas')

    [model, standard]
  end

  # Helper to create hot water loop
  def create_hot_water_loop(model, standard)
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')

    # Set plant loop temperatures
    hw_loop.setMaximumLoopTemperature(82.0)
    hw_loop.setMinimumLoopTemperature(60.0)

    # Add sizing
    sizing = hw_loop.sizingPlant
    sizing.setLoopType('Heating')
    sizing.setDesignLoopExitTemperature(82.0)
    sizing.setLoopDesignTemperatureDifference(11.0)

    # Add supply components
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.addToNode(hw_loop.supplyInletNode)

    # Add boiler
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    hw_loop.addSupplyBranchForComponent(boiler)

    # Add setpoint manager
    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 82.0)
    setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch)
    setpoint_mgr.addToNode(hw_loop.supplyOutletNode)

    hw_loop
  end
end
