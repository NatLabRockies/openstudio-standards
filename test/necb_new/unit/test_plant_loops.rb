# Test NECB plant loop creation and configuration
# Tests hot water loops, chilled water loops, condenser loops with their components
#
# Methods tested:
# - NECB2011#setup_hw_loop_with_components
# - NECB2011#setup_chw_loop_with_components
# - NECB2011#setup_cw_loop_with_components
# - NECB2011#boiler_hot_water_apply_efficiency_and_curves
# - NECB2011#chiller_electric_eir_apply_efficiency_and_curves
# - Standard#boiler_hot_water_find_search_criteria
# - Standard#chiller_electric_eir_find_search_criteria
#
# References:
# - NECB 2011 Section 5.2.2.1 (Boilers)
# - NECB 2011 Section 5.2.2.2 (Chillers)
# - NECB 2011 Table 5.2.2.2-A (Minimum Chiller Efficiency)
# - NECB 2011 Section 5.2.2.4 (Cooling Towers)
# - NECB 2011 Section 5.2.11 (Plant Equipment Staging)
class TestPlantLoops < Minitest::Test

  def test_hot_water_loop_basic_creation
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)

    # Create pump schedule
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0)

    # Setup hot water loop with components (NECB method)
    standard.setup_hw_loop_with_components(
      model,
      hw_loop,
      'NaturalGas',
      'NaturalGas',
      pump_flow_sch)

    # Verify loop name
    assert_equal 'Hot Water Loop', hw_loop.name.to_s

    # Verify sizing parameters
    sizing_plant = hw_loop.sizingPlant
    assert_equal 'Heating', sizing_plant.loopType
    assert_in_delta 82.0, sizing_plant.designLoopExitTemperature, 0.1
    assert_in_delta 16.0, sizing_plant.loopDesignTemperatureDifference, 0.1

    # Verify pump exists
    pumps = hw_loop.supplyComponents(OpenStudio::Model::PumpVariableSpeed::iddObjectType)
    assert_equal 1, pumps.size, "Should have 1 variable speed pump"

    # Verify two boilers exist (NECB requires staging)
    boilers = hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType)
    assert_equal 2, boilers.size, "Should have 2 boilers for redundancy"
  end

  def test_hot_water_loop_outdoor_air_reset_setpoint
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    standard.setup_hw_loop_with_components(
      model, hw_loop, 'NaturalGas', 'NaturalGas', pump_flow_sch
    )

    # Check for outdoor air reset setpoint manager
    setpoint_managers = hw_loop.supplyOutletNode.setpointManagers
    oa_reset_spm = setpoint_managers.select { |spm| spm.to_SetpointManagerOutdoorAirReset.is_initialized }

    assert_equal 1, oa_reset_spm.size, "Should have outdoor air reset setpoint manager"

    spm = oa_reset_spm.first.to_SetpointManagerOutdoorAirReset.get
    assert_equal 'Temperature', spm.controlVariable
  end

  def test_boiler_efficiency_application_small_capacity
    # Test boiler efficiency for small capacity (<176 kW)
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setName('Primary Boiler')
    boiler.setNominalCapacity(100_000)

    standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    thermal_eff = boiler.nominalThermalEfficiency
    assert thermal_eff > 0.75, "Boiler efficiency should be reasonable (>0.75), got #{thermal_eff}"
    assert thermal_eff < 1.0, "Boiler efficiency should be less than 1.0, got #{thermal_eff}"
  end

  def test_boiler_efficiency_application_medium_capacity
    # Test boiler efficiency for medium capacity (176-352 kW)
    # NECB requires two boilers in this range
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setName('Primary Boiler')
    boiler.setNominalCapacity(250_000) # 250 kW

    standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    # Verify thermal efficiency is set
    thermal_eff = boiler.nominalThermalEfficiency
    assert thermal_eff > 0.75, "Boiler efficiency should be reasonable"
  end

  def test_boiler_efficiency_application_large_capacity
    # Test boiler efficiency for large capacity (>352 kW)
    # NECB requires modulating primary boiler
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setName('Primary Boiler')
    boiler.setNominalCapacity(500_000) # 500 kW

    standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    # Verify modulating settings for large capacity
    assert_equal 'LeavingSetpointModulated', boiler.boilerFlowMode
    assert_equal 0.25, boiler.minimumPartLoadRatio
  end

  def test_chilled_water_loop_basic_creation
    # Test basic chilled water loop creation with NECB method
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    chw_loop = OpenStudio::Model::PlantLoop.new(model)

    # Setup chilled water loop with components
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    # Verify loop name
    assert_equal 'Chilled Water Loop', chw_loop.name.to_s

    # Verify sizing parameters
    sizing_plant = chw_loop.sizingPlant
    assert_equal 'Cooling', sizing_plant.loopType
    assert_in_delta 7.0, sizing_plant.designLoopExitTemperature, 0.1
    assert_in_delta 6.0, sizing_plant.loopDesignTemperatureDifference, 0.1

    # Verify pump exists
    pumps = chw_loop.supplyComponents(OpenStudio::Model::PumpVariableSpeed::iddObjectType)
    assert_equal 1, pumps.size, "Should have 1 variable speed pump"

    # Verify two chillers exist (NECB requires staging)
    chillers = chw_loop.supplyComponents(OpenStudio::Model::ChillerElectricEIR::iddObjectType)
    assert_equal 2, chillers.size, "Should have 2 chillers for redundancy"

    # Verify returned chiller objects
    assert chiller1.is_a?(OpenStudio::Model::ChillerElectricEIR)
    assert chiller2.is_a?(OpenStudio::Model::ChillerElectricEIR)
  end

  def test_chiller_efficiency_application
    # Test chiller efficiency application
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller.setCondenserType('WaterCooled')
    chiller.setName('Primary Chiller WaterCooled Scroll')
    chiller.setReferenceCapacity(500_000) # 500 kW

    # Apply efficiency
    standard.chiller_electric_eir_apply_efficiency_and_curves(chiller, [])

    # Verify COP is set
    cop = chiller.referenceCOP
    assert cop > 2.0, "Chiller COP should be reasonable (>2.0), got #{cop}"
    assert cop < 10.0, "Chiller COP should be realistic (<10.0), got #{cop}"
  end

  def test_condenser_loop_basic_creation
    # Test basic condenser water loop creation with NECB method
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create chilled water loop first (chillers needed for condenser loop)
    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    # Create condenser loop
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify loop name
    assert_equal 'Condenser Water Loop', cw_loop.name.to_s

    # Verify sizing parameters
    sizing_plant = cw_loop.sizingPlant
    assert_equal 'Condenser', sizing_plant.loopType
    assert_in_delta 29.0, sizing_plant.designLoopExitTemperature, 0.1
    assert_in_delta 6.0, sizing_plant.loopDesignTemperatureDifference, 0.1
  end

  def test_condenser_loop_cooling_tower_configuration
    # Test cooling tower design parameters
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Get cooling tower
    towers = cw_loop.supplyComponents(OpenStudio::Model::CoolingTowerSingleSpeed::iddObjectType)
    tower = towers.first.to_CoolingTowerSingleSpeed.get

    # Verify design parameters
    # Note: WB and DB temps return Float directly, approach and range return OptionalDouble
    assert_in_delta 24.0, tower.designInletAirWetBulbTemperature, 0.1
    assert_in_delta 35.0, tower.designInletAirDryBulbTemperature, 0.1

    # Approach and range return OptionalDouble
    assert tower.designApproachTemperature.is_initialized
    assert_in_delta 5.0, tower.designApproachTemperature.get, 0.1

    assert tower.designRangeTemperature.is_initialized
    assert_in_delta 6.0, tower.designRangeTemperature.get, 0.1
  end
end
