require_relative '../../test_helper'

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

  # ============================================================================
  # Hot Water Loop Tests
  # ============================================================================

  def test_hot_water_loop_basic_creation
    # Test basic hot water loop creation with NECB method
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)

    # Create pump schedule
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    # Setup hot water loop with components (NECB method)
    standard.setup_hw_loop_with_components(
      model,
      hw_loop,
      'NaturalGas',
      'NaturalGas',
      pump_flow_sch
    )

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

  def test_hot_water_loop_with_gas_boilers
    # Test hot water loop with natural gas boilers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    standard.setup_hw_loop_with_components(
      model, hw_loop, 'NaturalGas', 'NaturalGas', pump_flow_sch
    )

    # Get boilers
    boilers = hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType)
    boiler1 = boilers[0].to_BoilerHotWater.get
    boiler2 = boilers[1].to_BoilerHotWater.get

    # Verify fuel type
    assert_equal 'NaturalGas', boiler1.fuelType
    assert_equal 'NaturalGas', boiler2.fuelType

    # Verify names (NECB convention)
    assert boiler1.name.to_s.include?('Primary'), "First boiler should be named Primary"
    assert boiler2.name.to_s.include?('Secondary'), "Second boiler should be named Secondary"
  end

  def test_hot_water_loop_with_electric_boilers
    # Test hot water loop with electric boilers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    standard.setup_hw_loop_with_components(
      model, hw_loop, 'Electricity', 'Electricity', pump_flow_sch
    )

    # Get boilers
    boilers = hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType)
    boiler1 = boilers[0].to_BoilerHotWater.get
    boiler2 = boilers[1].to_BoilerHotWater.get

    # Verify fuel type
    assert_equal 'Electricity', boiler1.fuelType
    assert_equal 'Electricity', boiler2.fuelType
  end

  def test_hot_water_loop_with_oil_boilers
    # Test hot water loop with oil boilers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    standard.setup_hw_loop_with_components(
      model, hw_loop, 'FuelOilNo2', 'FuelOilNo2', pump_flow_sch
    )

    # Get boilers
    boilers = hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType)
    boiler1 = boilers[0].to_BoilerHotWater.get

    # Verify fuel type
    assert_equal 'FuelOilNo2', boiler1.fuelType
  end

  def test_hot_water_loop_with_mixed_fuel_boilers
    # Test hot water loop with primary gas and backup electric boilers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    # Primary gas, backup electric
    standard.setup_hw_loop_with_components(
      model, hw_loop, 'NaturalGas', 'Electricity', pump_flow_sch
    )

    # Get boilers
    boilers = hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType)
    boiler1 = boilers[0].to_BoilerHotWater.get
    boiler2 = boilers[1].to_BoilerHotWater.get

    # Verify different fuel types
    assert_equal 'NaturalGas', boiler1.fuelType
    assert_equal 'Electricity', boiler2.fuelType
  end

  def test_hot_water_loop_outdoor_air_reset_setpoint
    # Test that hot water loop has outdoor air reset setpoint manager
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

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

  def test_hot_water_loop_has_bypass_pipe
    # Test that hot water loop has bypass pipe for hydraulic balance
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    standard.setup_hw_loop_with_components(
      model, hw_loop, 'NaturalGas', 'NaturalGas', pump_flow_sch
    )

    # Check for bypass pipe
    bypass_pipes = hw_loop.supplyComponents(OpenStudio::Model::PipeAdiabatic::iddObjectType)
    # Should have at least bypass pipe (there's also an outlet pipe)
    assert bypass_pipes.size >= 1, "Should have bypass pipe on supply side"
  end

  # ============================================================================
  # Boiler Efficiency Tests
  # ============================================================================

  def test_boiler_find_search_criteria_natural_gas
    # Test boiler search criteria for natural gas boiler
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')

    search_criteria = standard.boiler_hot_water_find_search_criteria(boiler)

    assert_equal 'NECB2011', search_criteria['template']
    # NECB uses 'Gas' for natural gas boilers
    assert_equal 'Gas', search_criteria['fuel_type']
    assert_equal 'Hot Water', search_criteria['fluid_type']
  end

  def test_boiler_find_search_criteria_electric
    # Test boiler search criteria for electric boiler
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('Electricity')

    search_criteria = standard.boiler_hot_water_find_search_criteria(boiler)

    assert_equal 'NECB2011', search_criteria['template']
    assert_equal 'Electric', search_criteria['fuel_type']
  end

  def test_boiler_find_search_criteria_oil
    # Test boiler search criteria for oil boiler
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('FuelOilNo2')

    search_criteria = standard.boiler_hot_water_find_search_criteria(boiler)

    assert_equal 'NECB2011', search_criteria['template']
    assert_equal 'Oil', search_criteria['fuel_type']
  end

  def test_boiler_efficiency_application_small_capacity
    # Test boiler efficiency for small capacity (<176 kW)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setName('Primary Boiler')
    boiler.setNominalCapacity(100_000) # 100 kW

    standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    # Verify thermal efficiency is set
    thermal_eff = boiler.nominalThermalEfficiency
    assert thermal_eff > 0.75, "Boiler efficiency should be reasonable (>0.75), got #{thermal_eff}"
    assert thermal_eff < 1.0, "Boiler efficiency should be less than 1.0, got #{thermal_eff}"
  end

  def test_boiler_efficiency_application_medium_capacity
    # Test boiler efficiency for medium capacity (176-352 kW)
    # NECB requires two boilers in this range
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

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
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    boiler.setName('Primary Boiler')
    boiler.setNominalCapacity(500_000) # 500 kW

    standard.boiler_hot_water_apply_efficiency_and_curves(boiler)

    # Verify modulating settings for large capacity
    assert_equal 'LeavingSetpointModulated', boiler.boilerFlowMode
    assert_equal 0.25, boiler.minimumPartLoadRatio
  end

  # ============================================================================
  # Chilled Water Loop Tests
  # ============================================================================

  def test_chilled_water_loop_basic_creation
    # Test basic chilled water loop creation with NECB method
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

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

  def test_chilled_water_loop_with_scroll_chillers
    # Test chilled water loop with scroll chillers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    # Verify chiller names include type
    assert chiller1.name.to_s.include?('Scroll'), "Chiller 1 name should include 'Scroll'"
    assert chiller2.name.to_s.include?('Scroll'), "Chiller 2 name should include 'Scroll'"

    # Verify primary/secondary naming
    assert chiller1.name.to_s.include?('Primary'), "Chiller 1 should be Primary"
    assert chiller2.name.to_s.include?('Secondary'), "Chiller 2 should be Secondary"
  end

  def test_chilled_water_loop_with_screw_chillers
    # Test chilled water loop with screw chillers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Screw'
    )

    # Verify chiller names include type
    assert chiller1.name.to_s.include?('Screw'), "Chiller name should include 'Screw'"
  end

  def test_chilled_water_loop_with_centrifugal_chillers
    # Test chilled water loop with centrifugal chillers
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Centrifugal'
    )

    # Verify chiller names include type
    assert chiller1.name.to_s.include?('Centrifugal'), "Chiller name should include 'Centrifugal'"
  end

  def test_chilled_water_loop_chillers_are_water_cooled
    # Test that NECB chillers are water-cooled after connecting to condenser loop
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    # Create condenser loop to connect chillers
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify condenser type after connection
    assert_equal 'WaterCooled', chiller1.condenserType
    assert_equal 'WaterCooled', chiller2.condenserType
  end

  def test_chilled_water_loop_constant_setpoint
    # Test that chilled water loop has constant temperature setpoint
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_chw_loop_with_components(model, chw_loop, 'Scroll')

    # Check for scheduled setpoint manager
    setpoint_managers = chw_loop.supplyOutletNode.setpointManagers
    scheduled_spm = setpoint_managers.select { |spm| spm.to_SetpointManagerScheduled.is_initialized }

    assert_equal 1, scheduled_spm.size, "Should have scheduled setpoint manager"
  end

  def test_chilled_water_loop_has_bypass_pipe
    # Test that chilled water loop has bypass pipe
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_chw_loop_with_components(model, chw_loop, 'Scroll')

    # Check for bypass pipe
    bypass_pipes = chw_loop.supplyComponents(OpenStudio::Model::PipeAdiabatic::iddObjectType)
    assert bypass_pipes.size >= 1, "Should have bypass pipe on supply side"
  end

  # ============================================================================
  # Chiller Configuration Tests
  # ============================================================================

  def test_chiller_find_search_criteria
    # Test chiller search criteria generation
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    # Note: Cannot set WaterCooled until connected to condenser loop

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'NECB2011', search_criteria['template']
    # Condenser type will be 'WithCondenser' or 'AirCooled' by default
    assert search_criteria.key?('condenser_type'), "Should have condenser_type key"
  end

  def test_chiller_modulating_settings
    # Test that NECB chillers have modulating settings
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    # Set a capacity before applying efficiency
    chiller1.setReferenceCapacity(500_000) # 500 kW

    # Create condenser loop
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Apply NECB efficiency (which sets modulating parameters)
    standard.chiller_electric_eir_apply_efficiency_and_curves(chiller1, [])

    # Verify modulating settings
    assert_equal 'LeavingSetpointModulated', chiller1.chillerFlowMode
    assert_equal 0.25, chiller1.minimumPartLoadRatio
    assert_equal 0.25, chiller1.minimumUnloadingRatio
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

  def test_chiller_staging_small_capacity
    # Test chiller staging for capacity < 2100 kW
    # NECB: one operating chiller, one standby
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller.setCondenserType('WaterCooled')
    chiller.setName('Primary Chiller WaterCooled Scroll')
    chiller.setReferenceCapacity(1_000_000) # 1000 kW < 2100 kW

    standard.chiller_electric_eir_apply_efficiency_and_curves(chiller, [])

    # Primary chiller should have full capacity
    capacity = chiller.referenceCapacity.get
    assert_in_delta 1_000_000, capacity, 10, "Primary chiller should retain capacity"
  end

  # ============================================================================
  # Condenser Water Loop Tests
  # ============================================================================

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

  def test_condenser_loop_has_cooling_tower
    # Test that condenser loop has cooling tower
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify cooling tower exists
    towers = cw_loop.supplyComponents(OpenStudio::Model::CoolingTowerSingleSpeed::iddObjectType)
    assert_equal 1, towers.size, "Should have 1 cooling tower"
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

  def test_condenser_loop_has_pump
    # Test that condenser loop has variable speed pump
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify pump exists
    pumps = cw_loop.supplyComponents(OpenStudio::Model::PumpVariableSpeed::iddObjectType)
    assert_equal 1, pumps.size, "Should have 1 variable speed pump"
  end

  def test_condenser_loop_chillers_on_demand_side
    # Test that chillers are connected to condenser loop demand side
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify chillers on demand side
    demand_chillers = cw_loop.demandComponents(OpenStudio::Model::ChillerElectricEIR::iddObjectType)
    assert_equal 2, demand_chillers.size, "Should have 2 chillers on demand side"
  end

  def test_condenser_loop_has_bypass_pipe
    # Test that condenser loop has bypass pipe
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Check for bypass pipe
    bypass_pipes = cw_loop.supplyComponents(OpenStudio::Model::PipeAdiabatic::iddObjectType)
    assert bypass_pipes.size >= 1, "Should have bypass pipe on supply side"
  end

  # ============================================================================
  # NECB Vintage Tests
  # ============================================================================

  def test_necb2015_hot_water_loop
    # Test that NECB2015 can create hot water loop
    standard = Standard.build('NECB2015')
    model = OpenStudio::Model::Model.new

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )

    standard.setup_hw_loop_with_components(
      model, hw_loop, 'NaturalGas', 'NaturalGas', pump_flow_sch
    )

    assert_equal 'Hot Water Loop', hw_loop.name.to_s
    boilers = hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType)
    assert_equal 2, boilers.size
  end

  def test_necb2017_chilled_water_loop
    # Test that NECB2017 can create chilled water loop
    standard = Standard.build('NECB2017')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    assert_equal 'Chilled Water Loop', chw_loop.name.to_s
    assert chiller1.is_a?(OpenStudio::Model::ChillerElectricEIR)
  end

  def test_necb2020_condenser_loop
    # Test that NECB2020 can create condenser loop
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    assert_equal 'Condenser Water Loop', cw_loop.name.to_s
    towers = cw_loop.supplyComponents(OpenStudio::Model::CoolingTowerSingleSpeed::iddObjectType)
    assert_equal 1, towers.size
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  def test_complete_plant_system_integration
    # Test complete plant system with all three loops integrated
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    pump_flow_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(
      model, 'HW Pump Flow', 'Fraction', 1.0
    )
    standard.setup_hw_loop_with_components(
      model, hw_loop, 'NaturalGas', 'NaturalGas', pump_flow_sch
    )

    # Create chilled water loop
    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = standard.setup_chw_loop_with_components(
      model, chw_loop, 'Scroll'
    )

    # Create condenser loop
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify all loops exist
    plant_loops = model.getPlantLoops
    assert_equal 3, plant_loops.size, "Should have 3 plant loops"

    # Verify components
    assert_equal 2, hw_loop.supplyComponents(OpenStudio::Model::BoilerHotWater::iddObjectType).size
    assert_equal 2, chw_loop.supplyComponents(OpenStudio::Model::ChillerElectricEIR::iddObjectType).size
    assert_equal 1, cw_loop.supplyComponents(OpenStudio::Model::CoolingTowerSingleSpeed::iddObjectType).size
  end

  def test_plant_loops_with_different_chiller_types
    # Test that different chiller types can be created
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller_types = ['Scroll', 'Screw', 'Centrifugal']

    chiller_types.each do |chiller_type|
      chw_loop = OpenStudio::Model::PlantLoop.new(model)
      chw_loop.setName("CHW Loop #{chiller_type}")

      chiller1, chiller2 = standard.setup_chw_loop_with_components(
        model, chw_loop, chiller_type
      )

      # Verify chiller names include type
      assert chiller1.name.to_s.include?(chiller_type),
        "Chiller should include type '#{chiller_type}' in name"
    end
  end

end
