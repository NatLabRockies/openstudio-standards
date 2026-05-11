require_relative '../../helpers/minitest_helper'

# Component Tests for DHW (Domestic Hot Water) Systems
# Tests the creation, configuration, and integration of DHW systems in NECB models
#
# Methods tested:
# - NECB2011#water_heater_mixed_apply_efficiency - Apply efficiency standards to water heaters
# - OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop - Create DHW loop
# - OpenstudioStandards::ServiceWaterHeating.create_water_heater - Create water heater
#
# Phase 3: Component Testing (NO SIZING RUNS)
# - Tests system creation and configuration
# - Verifies water heater efficiency by fuel type
# - Tests pump configuration
# - Tests different NECB vintages
#
# References:
# - NECB 2011/2015/2020 Service Water Heating Requirements
# - PNNL Service Water Heating Appendix A
class TestDhwSystems < Minitest::Test

  # ============================================================================
  # Water Heater Efficiency Tests - NECB 2011
  # ============================================================================

  def test_necb2011_electric_water_heater_efficiency
    # Test electric water heater efficiency application
    # Electric water heaters should have 100% thermal efficiency (NECB 2011)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create electric water heater with known capacity and volume
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setName('Test Electric Water Heater')
    water_heater.setHeaterMaximumCapacity(4500.0)  # 4.5 kW
    water_heater.setTankVolume(0.1514)  # 40 gallons in m3
    water_heater.setHeaterFuelType('Electricity')

    # Apply NECB 2011 efficiency standards
    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "Efficiency application should succeed"
    assert_in_delta 1.0, water_heater.heaterThermalEfficiency.get, 0.01,
      "Electric water heater should be 100% efficient per NECB 2011"
  end

  def test_necb2011_gas_water_heater_small_capacity_efficiency
    # Test gas water heater efficiency for small units (<= 75,000 Btu/hr)
    # Should use residential efficiency equation with fixed 82% efficiency
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

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
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

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

  def test_necb2011_fuel_oil_water_heater_efficiency
    # Test fuel oil water heater efficiency
    # Should have similar requirements to natural gas
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setName('Test Fuel Oil Water Heater')
    water_heater.setHeaterMaximumCapacity(20000.0)  # ~68,000 Btu/hr
    water_heater.setTankVolume(0.1514)  # 40 gallons
    water_heater.setHeaterFuelType('FuelOilNo2')

    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "Fuel oil efficiency application should succeed"

    thermal_eff = water_heater.heaterThermalEfficiency.get
    assert_in_delta 0.82, thermal_eff, 0.01,
      "Small fuel oil water heater should have 82% thermal efficiency"
  end

  def test_necb2011_water_heater_skin_loss_coefficient
    # Test that water heater has appropriate skin loss coefficient (UA) set
    # UA accounts for standby heat losses from tank
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setHeaterMaximumCapacity(4500.0)  # 4.5 kW
    water_heater.setTankVolume(0.1514)  # 40 gallons
    water_heater.setHeaterFuelType('Electricity')

    standard.water_heater_mixed_apply_efficiency(water_heater)

    # Check off-cycle loss coefficient
    off_cycle_ua = water_heater.offCycleLossCoefficienttoAmbientTemperature.get
    assert off_cycle_ua > 0, "Off-cycle loss coefficient should be positive"
    assert off_cycle_ua < 50, "Off-cycle loss coefficient should be reasonable (<50 W/K)"

    # Check on-cycle loss coefficient
    on_cycle_ua = water_heater.onCycleLossCoefficienttoAmbientTemperature.get
    assert on_cycle_ua > 0, "On-cycle loss coefficient should be positive"
  end

  def test_necb2011_water_heater_name_includes_efficiency
    # Test that water heater name includes efficiency information
    # Helps with model inspection and debugging
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setName('Test Water Heater')
    water_heater.setHeaterMaximumCapacity(20000.0)
    water_heater.setTankVolume(0.1514)
    water_heater.setHeaterFuelType('NaturalGas')

    standard.water_heater_mixed_apply_efficiency(water_heater)

    wh_name = water_heater.name.to_s
    assert wh_name.include?('Therm Eff'), "Water heater name should include 'Therm Eff'"
    assert wh_name.include?('0.82'), "Water heater name should include efficiency value"
  end

  # ============================================================================
  # NECB 2020 Efficiency Tests (UEF Methodology)
  # ============================================================================

  def test_necb2020_electric_water_heater_efficiency
    # Test NECB 2020 electric water heater efficiency
    # Should still be 100% efficient for electric
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setHeaterMaximumCapacity(4500.0)
    water_heater.setTankVolume(0.1514)
    water_heater.setHeaterFuelType('Electricity')

    result = standard.water_heater_mixed_apply_efficiency(water_heater)

    assert result, "NECB2020 efficiency application should succeed"
    assert_in_delta 1.0, water_heater.heaterThermalEfficiency.get, 0.01,
      "NECB2020 electric water heater should be 100% efficient"
  end

  def test_necb2020_gas_water_heater_small_uef_based
    # Test NECB 2020 gas water heater with UEF-based efficiency
    # NECB 2020 uses Uniform Energy Factor methodology
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

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
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

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

  # ============================================================================
  # DHW Loop Creation Tests
  # ============================================================================

  def test_create_service_water_heating_loop_electric
    # Test direct creation of service water heating loop with electric heater
    model = OpenStudio::Model::Model.new

    # Create DHW loop
    swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      system_name: 'Test Service Water Loop',
      service_water_temperature: 60.0,
      service_water_pump_head: 29861.0,
      water_heater_capacity: 4500.0,
      water_heater_volume: 0.1514,
      water_heater_fuel: 'Electricity'
    )

    assert swh_loop, "Should create service water heating loop"
    assert_includes ['PlantLoop', 'OS_PlantLoop', 'OS:PlantLoop'], swh_loop.iddObjectType.valueName,
      "Loop should be a PlantLoop object"

    # Verify loop has water heater
    water_heaters = model.getWaterHeaterMixeds
    assert_equal 1, water_heaters.size, "Should have one water heater"
    assert_equal 'Electricity', water_heaters.first.heaterFuelType
  end

  def test_create_service_water_heating_loop_gas
    # Test direct creation of service water heating loop with gas heater
    model = OpenStudio::Model::Model.new

    swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      system_name: 'Gas Service Water Loop',
      service_water_temperature: 60.0,
      water_heater_capacity: 20000.0,
      water_heater_volume: 0.1514,
      water_heater_fuel: 'NaturalGas'
    )

    assert swh_loop, "Should create gas service water heating loop"

    water_heaters = model.getWaterHeaterMixeds
    assert_equal 1, water_heaters.size, "Should have gas water heater"
    assert_equal 'NaturalGas', water_heaters.first.heaterFuelType
  end

  def test_dhw_loop_has_pump
    # Test that DHW loop has pump configured
    model = OpenStudio::Model::Model.new

    swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      water_heater_fuel: 'Electricity',
      service_water_pump_head: 50000.0
    )

    # Check for pump on supply side
    pumps = swh_loop.supplyComponents(OpenStudio::Model::PumpConstantSpeed.iddObjectType)
    pumps += swh_loop.supplyComponents(OpenStudio::Model::PumpVariableSpeed.iddObjectType)

    assert pumps.size > 0, "DHW loop should have a pump"

    # Get pump and verify configuration
    pump = if pumps.first.to_PumpConstantSpeed.is_initialized
             pumps.first.to_PumpConstantSpeed.get
           else
             pumps.first.to_PumpVariableSpeed.get
           end

    # Verify pump head is configured
    # Note: ratedPumpHead returns a Double directly, not an Optional
    assert pump.ratedPumpHead > 0, "Pump rated head should be positive"
    assert pump.motorEfficiency > 0, "Pump should have motor efficiency > 0"
  end

  def test_dhw_loop_temperature_setpoint
    # Test that DHW loop has appropriate temperature setpoint
    model = OpenStudio::Model::Model.new

    target_temp = 60.0  # 60°C
    swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      service_water_temperature: target_temp,
      water_heater_fuel: 'Electricity'
    )

    # Check maximum loop temperature
    max_temp = swh_loop.maximumLoopTemperature
    assert max_temp >= target_temp, "Loop max temp should be >= target temperature"

    # Check for setpoint manager on supply outlet
    supply_outlet_node = swh_loop.supplyOutletNode
    setpoint_managers = supply_outlet_node.setpointManagers
    assert setpoint_managers.size > 0, "Should have setpoint manager on supply outlet"
  end

  def test_dhw_loop_has_bypass_pipes
    # Test that DHW loop has bypass pipes for proper operation
    model = OpenStudio::Model::Model.new

    swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      water_heater_fuel: 'Electricity'
    )

    # Check for pipes on demand and supply sides
    demand_pipes = swh_loop.demandComponents(OpenStudio::Model::PipeAdiabatic.iddObjectType)
    supply_pipes = swh_loop.supplyComponents(OpenStudio::Model::PipeAdiabatic.iddObjectType)

    assert demand_pipes.size >= 2, "Should have demand side bypass and outlet pipes"
    assert supply_pipes.size >= 2, "Should have supply side bypass and outlet pipes"
  end

  def test_dhw_loop_fuel_oil
    # Test DHW loop with fuel oil water heater
    model = OpenStudio::Model::Model.new

    swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      water_heater_fuel: 'FuelOilNo2',
      water_heater_capacity: 20000.0,
      water_heater_volume: 0.1514
    )

    assert swh_loop, "Should create fuel oil DHW loop"

    water_heaters = model.getWaterHeaterMixeds
    assert_equal 1, water_heaters.size
    assert_equal 'FuelOilNo2', water_heaters.first.heaterFuelType
  end

  def test_dhw_loop_circulating_vs_non_circulating
    # Test that DHW loop pump type depends on service_water_pump_head
    # Low/nil pump head should create non-circulating system
    model = OpenStudio::Model::Model.new

    # Non-circulating (low pump head)
    swh_loop_non_circ = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      system_name: 'Non-Circulating Loop',
      water_heater_fuel: 'Electricity',
      service_water_pump_head: 0.001
    )

    # Check that it has variable speed pump (non-circulating characteristic)
    pumps_var = swh_loop_non_circ.supplyComponents(OpenStudio::Model::PumpVariableSpeed.iddObjectType)
    assert pumps_var.size > 0, "Non-circulating loop should have variable speed pump"

    # Circulating (normal pump head)
    swh_loop_circ = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(
      model,
      system_name: 'Circulating Loop',
      water_heater_fuel: 'Electricity',
      service_water_pump_head: 50000.0
    )

    # Check that it has constant speed pump (circulating characteristic)
    pumps_const = swh_loop_circ.supplyComponents(OpenStudio::Model::PumpConstantSpeed.iddObjectType)
    assert pumps_const.size > 0, "Circulating loop should have constant speed pump"
  end

  def test_necb2015_vs_necb2011_consistency
    # Test that NECB 2015 has similar efficiency requirements to NECB 2011
    necb2011 = Standard.build('NECB2011')
    necb2015 = Standard.build('NECB2015')

    model_2011 = OpenStudio::Model::Model.new
    model_2015 = OpenStudio::Model::Model.new

    # Create identical water heaters
    wh_2011 = OpenStudio::Model::WaterHeaterMixed.new(model_2011)
    wh_2011.setHeaterMaximumCapacity(20000.0)
    wh_2011.setTankVolume(0.1514)
    wh_2011.setHeaterFuelType('NaturalGas')

    wh_2015 = OpenStudio::Model::WaterHeaterMixed.new(model_2015)
    wh_2015.setHeaterMaximumCapacity(20000.0)
    wh_2015.setTankVolume(0.1514)
    wh_2015.setHeaterFuelType('NaturalGas')

    # Apply efficiencies
    necb2011.water_heater_mixed_apply_efficiency(wh_2011)
    necb2015.water_heater_mixed_apply_efficiency(wh_2015)

    # Compare efficiencies (should be identical or very close for small gas WH)
    eff_2011 = wh_2011.heaterThermalEfficiency.get
    eff_2015 = wh_2015.heaterThermalEfficiency.get

    assert_in_delta eff_2011, eff_2015, 0.01,
      "NECB2015 and NECB2011 should have similar efficiency for small gas WH"
  end

end
