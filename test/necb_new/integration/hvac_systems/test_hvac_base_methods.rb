require_relative '../../test_helper'

# Test suite for NECB HVAC base methods
#
# Tests core methods in /lib/openstudio-standards/standards/necb/NECB2011/hvac_systems.rb
# Covers equipment efficiency lookups, fan power calculations, economizer requirements,
# pump sizing, and component creation methods used by all HVAC systems.
#
# These methods are shared across all NECB system types and are tested
# independently of specific system configurations.
class TestNECBHVACBaseMethods < Minitest::Test
  include NecbHelper

  ##############################################################################
  # ECONOMIZER REQUIREMENT TESTS
  ##############################################################################

  def test_economizer_required_by_cooling_capacity
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Test Air Loop')

    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    cooling_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
    cooling_coil.setRatedHighSpeedTotalCoolingCapacity(25000)
    cooling_coil.addToNode(air_loop.supplyInletNode)

    sizing_system = air_loop.sizingSystem
    sizing_system.setDesignOutdoorAirFlowRate(2.0)

    economizer_required = standard.air_loop_hvac_economizer_required?(air_loop)
    assert economizer_required, "Economizer should be required for cooling capacity > 20 kW"
  end

  def test_economizer_not_required_small_system
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Small System')

    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setRatedTotalCoolingCapacity(15000)
    cooling_coil.addToNode(air_loop.supplyInletNode)

    air_loop.setDesignSupplyAirFlowRate(1.0)

    economizer_required = standard.air_loop_hvac_economizer_required?(air_loop)
    refute economizer_required, "Economizer should not be required for small systems"
  end

  def test_economizer_integration_type
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    result = standard.air_loop_hvac_apply_economizer_integration(air_loop, 'NECB HDD Method')

    assert result, "Economizer integration should be applied successfully"
    assert_equal 'NoLockout', oa_controller.getLockoutType, "NECB requires NoLockout (integrated) economizer"
  end

  ##############################################################################
  # ENERGY RECOVERY VENTILATOR (ERV) TESTS
  ##############################################################################

  def test_erv_not_required_with_dcv
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
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    erv_required = standard.air_loop_hvac_energy_recovery_ventilator_required?(air_loop, 'NECB HDD Method')
    refute erv_required, "ERV should not be required for systems without OA intake"
  end

  ##############################################################################
  # BOILER EFFICIENCY TESTS
  ##############################################################################

  def test_boiler_efficiency_natural_gas
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    hw_loop = create_hot_water_loop(model, standard)

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setName('Natural Gas Boiler')
    boiler.setFuelType('NaturalGas')
    boiler.setNominalCapacity(100000)
    hw_loop.addSupplyBranchForComponent(boiler)

    result = standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    assert boiler.normalizedBoilerEfficiencyCurve.is_initialized, "Boiler should have efficiency curve"

    thermal_eff = boiler.nominalThermalEfficiency
    assert thermal_eff > 0.7 && thermal_eff < 1.0, "Boiler thermal efficiency should be realistic"
  end

  def test_boiler_efficiency_oil_vs_gas
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    hw_loop = create_hot_water_loop(model, standard)

    gas_boiler = OpenStudio::Model::BoilerHotWater.new(model)
    gas_boiler.setName('Gas Boiler')
    gas_boiler.setFuelType('NaturalGas')
    gas_boiler.setNominalCapacity(100000)
    hw_loop.addSupplyBranchForComponent(gas_boiler)
    standard.boiler_hot_water_apply_efficiency_and_curves(gas_boiler)

    oil_boiler = OpenStudio::Model::BoilerHotWater.new(model)
    oil_boiler.setName('Oil Boiler')
    oil_boiler.setFuelType('FuelOilNo2')
    oil_boiler.setNominalCapacity(100000)
    hw_loop.addSupplyBranchForComponent(oil_boiler)
    standard.boiler_hot_water_apply_efficiency_and_curves(oil_boiler)

    assert gas_boiler.normalizedBoilerEfficiencyCurve.is_initialized, "Gas boiler should have efficiency curve"
    assert oil_boiler.normalizedBoilerEfficiencyCurve.is_initialized, "Oil boiler should have efficiency curve"
  end

  ##############################################################################
  # CHILLER EFFICIENCY TESTS
  ##############################################################################

  def test_chiller_efficiency_water_cooled
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chw_loop.setName('Chilled Water Loop')

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    cw_loop.setName('Condenser Water Loop')

    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller.setName('Water Cooled Chiller centrifugal')
    chiller.setReferenceCapacity(500000)
    chw_loop.addSupplyBranchForComponent(chiller)
    chiller.addToNode(cw_loop.demandInletNode)

    cooling_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
    cw_loop.addSupplyBranchForComponent(cooling_tower)

    result = standard.chiller_electric_eir_apply_efficiency_and_curves(chiller, [cooling_tower])

    capft_curve = chiller.coolingCapacityFunctionOfTemperature
    assert !capft_curve.to_Curve.empty?, "Chiller should have CAPFT curve"

    eirft_curve = chiller.electricInputToCoolingOutputRatioFunctionOfTemperature
    assert !eirft_curve.to_Curve.empty?, "Chiller should have EIRFT curve"

    eirfplr_curve = chiller.electricInputToCoolingOutputRatioFunctionOfPLR
    assert !eirfplr_curve.to_Curve.empty?, "Chiller should have EIRFPLR curve"

    cop = chiller.referenceCOP
    assert cop > 2.5 && cop < 8.0, "Chiller COP should be realistic for water-cooled unit"
  end

  def test_chiller_flow_mode_modulating
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
  ##############################################################################

  def test_fan_motor_efficiency_constant_volume
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanConstantVolume.new(model)
    fan.setName('Constant Volume Supply Fan')
    fan.setPressureRise(600)
    fan.setMaximumFlowRate(5.0)
    fan.setFanEfficiency(0.6)

    motor_bhp = 5.0 * 600 / (0.6 * 746.0)

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    assert motor_eff > 0.5 && motor_eff < 1.0, "Fan motor efficiency should be realistic (0.5-1.0)"
    assert nominal_hp > 0, "Nominal HP should be positive"
  end

  def test_fan_motor_efficiency_variable_volume
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('Variable Volume Supply Fan')
    fan.setPressureRise(750)
    fan.setMaximumFlowRate(10.0)
    fan.setFanEfficiency(0.65)

    motor_bhp = 10.0 * 750 / (0.65 * 746.0)

    motor_eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)

    assert motor_eff > 0.5, "Variable volume fan motor should have reasonable efficiency"
    assert nominal_hp > 0, "Nominal HP should be positive"

    coeff1_opt = fan.fanPowerCoefficient1
    assert coeff1_opt.is_initialized, "VAV fan should have part load power curve coefficient 1"
  end

  def test_fan_impeller_efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanConstantVolume.new(model)

    impeller_eff = standard.fan_baseline_impeller_efficiency(fan)

    assert_equal 0.65, impeller_eff, "NECB baseline fan impeller efficiency should be 0.65"
  end

  ##############################################################################
  # PUMP SIZING AND EFFICIENCY TESTS
  ##############################################################################

  def test_pump_motor_efficiency_variable_speed
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName('Variable Speed Pump')
    pump.setRatedFlowRate(0.01)
    pump.setRatedPumpHead(150000)

    motor_bhp = 0.01 * 150000 / (0.6 * 746.0)

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)

    assert motor_eff > 0.8, "Pump motor efficiency should be > 0.8"
    assert nominal_hp > 0, "Nominal HP should be positive"
  end

  def test_pump_motor_efficiency_zero_bhp
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)

    motor_eff, nominal_hp = standard.pump_standard_minimum_motor_efficiency_and_size(pump, 0.0)

    assert_equal 1.0, motor_eff, "Zero BHP pump should return 100% efficiency"
    assert_equal 0, nominal_hp, "Zero BHP pump should return 0 nominal HP"
  end

  ##############################################################################
  # SIZING PARAMETERS TESTS
  ##############################################################################

  def test_model_sizing_parameters
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    standard.model_apply_sizing_parameters(model)

    sizing_params = model.getSizingParameters

    heating_factor = sizing_params.heatingSizingFactor
    cooling_factor = sizing_params.coolingSizingFactor

    assert heating_factor >= 1.0 && heating_factor <= 1.3, "Heating sizing factor should be 1.0-1.3"
    assert cooling_factor >= 1.0 && cooling_factor <= 1.3, "Cooling sizing factor should be 1.0-1.3"
  end

  ##############################################################################
  # HEATING COIL EFFICIENCY TESTS
  ##############################################################################

  def test_coil_heating_gas_efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setName('Gas Heating Coil')
    coil.setNominalCapacity(50000)

    thermal_eff = standard.coil_heating_gas_standard_minimum_thermal_efficiency(coil)

    assert thermal_eff > 0.75 && thermal_eff < 1.0, "Gas coil thermal efficiency should be 0.75-1.0"
  end

  def test_coil_heating_gas_apply_efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    coil = OpenStudio::Model::CoilHeatingGas.new(model)
    coil.setNominalCapacity(50000)

    result = standard.coil_heating_gas_apply_efficiency_and_curves(coil)

    assert result, "Should successfully apply gas coil efficiency"

    gas_burner_eff = coil.gasBurnerEfficiency
    assert gas_burner_eff > 0.75, "Gas burner efficiency should be > 0.75"
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  def create_baseline_necb_model(template:, climate:)
    standard = Standard.build(template)

    resource_path = File.join(File.dirname(__FILE__), '..', '..', '..', 'necb', 'unit_tests', 'resources', '5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    climate_files = {
      'Toronto' => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      'Vancouver' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
      'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
    }
    epw_file = climate_files[climate] || climate_files['Toronto']
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

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

    standard.fuel_type_set = SystemFuels.new
    standard.fuel_type_set.set_defaults(
      standards_data: standard.instance_variable_get(:@standards_data),
      primary_heating_fuel: 'NaturalGas'
    )

    [model, standard]
  end

  def create_hot_water_loop(model, standard)
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')

    hw_loop.setMaximumLoopTemperature(82.0)
    hw_loop.setMinimumLoopTemperature(60.0)

    sizing = hw_loop.sizingPlant
    sizing.setLoopType('Heating')
    sizing.setDesignLoopExitTemperature(82.0)
    sizing.setLoopDesignTemperatureDifference(11.0)

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.addToNode(hw_loop.supplyInletNode)

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    hw_loop.addSupplyBranchForComponent(boiler)

    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 82.0)
    setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch)
    setpoint_mgr.addToNode(hw_loop.supplyOutletNode)

    hw_loop
  end
end
