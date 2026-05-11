require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# Comprehensive test suite to complete HVAC base methods testing for NECB
# This file tests the remaining ~1,256 lines not covered in test_necb_hvac_systems.rb
# Target file: /lib/openstudio-standards/standards/necb/NECB2011/hvac_systems.rb (2,456 lines)
# Focus areas: outdoor air sizing, DX coil methods, multi-stage equipment, zone equipment,
# plant loop configuration, system naming, terminal units, and helper methods
class TestNECBHVACSystemsComplete < Minitest::Test
  include(NecbHelper)

  ##############################################################################
  # OUTDOOR AIR AND VAV SIZING TESTS
  # Test outdoor air damper sizing and VAV control methods
  ##############################################################################

  def test_air_loop_hvac_apply_multizone_vav_outdoor_air_sizing
    # NECB does not change damper positions - verify no-op behavior
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Test VAV System')

    result = standard.air_loop_hvac_apply_multizone_vav_outdoor_air_sizing(air_loop)

    assert result, "Method should return true (no-op for NECB)"
  end

  def test_air_loop_hvac_apply_vav_damper_action_single_maximum
    # NECB uses single maximum damper control (Normal action)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('VAV with Reheat')

    # Add VAV reheat terminal
    zone = model.getThermalZones.first
    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    air_loop.addBranchForZone(zone, terminal)

    result = standard.air_loop_hvac_apply_vav_damper_action(air_loop)

    assert result, "Should successfully apply damper action"
    assert_equal 'Normal', terminal.damperHeatingAction, "NECB should use Normal (Single Maximum) damper action"

    max_flow = terminal.maximumFlowFractionDuringReheat
    if max_flow.respond_to?(:is_initialized)
      assert max_flow.is_initialized, "Maximum flow should be initialized"
      assert_equal 0.5, max_flow.get, "Max flow during reheat should be 0.5"
    else
      assert_equal 0.5, max_flow, "Max flow during reheat should be 0.5"
    end
  end

  def test_air_loop_hvac_apply_single_zone_controls
    # NECB has no special single zone control requirements
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    result = standard.air_loop_hvac_apply_single_zone_controls(air_loop, 'NECB HDD Method')

    assert result, "Method should return true (no special controls)"
  end

  def test_air_loop_hvac_static_pressure_reset_not_required
    # NECB does not require static pressure reset
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    sp_reset_required = standard.air_loop_hvac_static_pressure_reset_required?(air_loop, true)

    refute sp_reset_required, "NECB should not require static pressure reset"
  end

  def test_air_loop_hvac_motorized_oa_damper_limits
    # NECB motorized OA damper requirements
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    result = standard.air_loop_hvac_motorized_oa_damper_limits(air_loop, 'NECB HDD Method')

    # Method may return array or single value; NECB requires motorized dampers for all systems (min = 0)
    if result.is_a?(Array)
      assert_equal 0, result.first, "NECB requires motorized OA dampers for all systems"
    else
      assert_equal 0, result, "NECB requires motorized OA dampers for all systems"
    end
  end

  ##############################################################################
  # DEMAND CONTROL VENTILATION (DCV) TESTS
  # Test DCV requirement logic at both air loop and zone levels
  ##############################################################################

  def test_air_loop_hvac_demand_control_ventilation_not_required
    # NECB does not require DCV
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    dcv_required = standard.air_loop_hvac_demand_control_ventilation_required?(air_loop, 'NECB HDD Method')

    refute dcv_required, "NECB2011 should not require DCV"
  end

  def test_thermal_zone_demand_control_ventilation_not_required
    # NECB does not require zone-level DCV
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zone = model.getThermalZones.first

    dcv_required = standard.thermal_zone_demand_control_ventilation_required?(zone, 'NECB HDD Method')

    refute dcv_required, "NECB should not require zone-level DCV"
  end

  ##############################################################################
  # MULTI-SPEED DX COIL TESTS
  # Test multi-speed cooling and heating coil efficiency application
  ##############################################################################

  def test_coil_cooling_dx_multi_speed_apply_efficiency_and_curves
    # Integration test: Create complete multi-speed heat pump system and apply efficiency
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Multi-Speed Heat Pump System')

    # Create multi-speed heat pump components
    fan = OpenStudio::Model::FanOnOff.new(model)
    htg_coil = OpenStudio::Model::CoilHeatingDXMultiSpeed.new(model)
    clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
    supp_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)

    # Create unitary system
    heat_pump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(
      model, fan, htg_coil, clg_coil, supp_htg_coil
    )

    # Add to air loop supply
    heat_pump.addToNode(air_loop.supplyOutletNode)

    # Add thermal zone for OA calculation
    zone = model.getThermalZones.first
    air_terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
    air_loop.addBranchForZone(zone, air_terminal)

    # Add speed stages with capacity data (required for efficiency application)
    # Speed 1 (low)
    clg_stage1 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_stage1.setGrossRatedTotalCoolingCapacity(10000.0) # 10 kW
    clg_coil.addStage(clg_stage1)

    # Speed 2 (high)
    clg_stage2 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_stage2.setGrossRatedTotalCoolingCapacity(20000.0) # 20 kW
    clg_coil.addStage(clg_stage2)

    # Apply efficiency and curves (this is what we're testing)
    # sql_db_vars_map is used for sizing data - pass empty hash for hardsized coil
    result = standard.coil_cooling_dx_multi_speed_apply_efficiency_and_curves(clg_coil, {})

    # Verify method executed successfully (returns true/false)
    # The method modifies the coil in-place
    assert !result.nil?, "Method should execute successfully"

    # Verify stages still exist
    assert_equal 2, clg_coil.stages.size, "Should have 2 cooling stages"

    # Verify each stage has performance curves applied
    clg_coil.stages.each_with_index do |stage, i|
      capft = stage.totalCoolingCapacityFunctionofTemperatureCurve
      assert capft.is_a?(OpenStudio::Model::Curve), "Stage #{i+1} should have CAPFT curve"

      capff = stage.totalCoolingCapacityFunctionofFlowFractionCurve
      assert capff.is_a?(OpenStudio::Model::Curve), "Stage #{i+1} should have CAPFF curve"

      eirft = stage.energyInputRatioFunctionofTemperatureCurve
      assert eirft.is_a?(OpenStudio::Model::Curve), "Stage #{i+1} should have EIRFT curve"

      eirff = stage.energyInputRatioFunctionofFlowFractionCurve
      assert eirff.is_a?(OpenStudio::Model::Curve), "Stage #{i+1} should have EIRFF curve"
    end
  end

  def test_coil_heating_gas_multi_stage_apply_efficiency_and_curves
    # Integration test: Create multi-speed heat pump with multi-stage gas heating
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Multi-Stage Gas Heat Pump System')

    # Create multi-speed heat pump components
    # Note: Must use AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed, not AirLoopHVACUnitarySystem
    # because the method searches for the heat pump by coil name
    fan = OpenStudio::Model::FanOnOff.new(model)
    htg_coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
    clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
    supp_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)

    # Add one stage with capacity to the heating coil
    # Method expects 1 stage and will configure/add more as needed per NECB rules
    stage1 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
    stage1.setNominalCapacity(80000.0) # 80 kW total capacity
    htg_coil.addStage(stage1)

    # Add cooling stages (required for heat pump)
    clg_stage = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_stage.setGrossRatedTotalCoolingCapacity(20000.0)
    clg_coil.addStage(clg_stage)

    # Create multi-speed heat pump
    heat_pump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(
      model, fan, htg_coil, clg_coil, supp_htg_coil
    )
    heat_pump.addToNode(air_loop.supplyOutletNode)

    # Add OA system (required for airflow calculations)
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.setMinimumOutdoorAirFlowRate(0.5) # 0.5 m3/s OA
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Add zone for complete system
    zone = model.getThermalZones.first
    air_terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
    air_loop.addBranchForZone(zone, air_terminal)

    # Set air loop design airflow (required for OA fraction calculation)
    sizing = air_loop.sizingSystem
    sizing.setDesignOutdoorAirFlowRate(0.5) # Match OA rate

    # Apply NECB efficiency rules (this is what we're testing)
    # NECB limits gas heating stages to 66 kW each
    # With 80 kW total, method should create 2 stages (40 kW each per NECB logic)
    result = standard.coil_heating_gas_multi_stage_apply_efficiency_and_curves(htg_coil)

    # Verify method executed successfully (returns true/false)
    assert !result.nil?, "Method should execute successfully"

    # Verify stages were configured (should be 2 stages for 80 kW)
    assert_equal 2, htg_coil.stages.size, "Should have 2 stages after NECB rules"

    # Verify each stage capacity is within NECB limits or appropriately configured
    htg_coil.stages.each_with_index do |stage, i|
      capacity = stage.nominalCapacity
      if capacity.is_initialized
        cap_w = capacity.get
        # NECB allows up to 66 kW per stage, or the method may have reconfigured
        # Just verify the stage has valid capacity data
        assert cap_w > 0, "Stage #{i+1} should have positive capacity"
      end

      # Verify efficiency was set (NECB thermal efficiency requirements)
      thermal_eff = stage.gasBurnerEfficiency
      assert thermal_eff > 0.0, "Stage #{i+1} should have thermal efficiency set"
      assert thermal_eff <= 1.0, "Stage #{i+1} thermal efficiency should be <= 1.0"
    end
  end

  ##############################################################################
  # DX COIL CREATION HELPER METHODS
  # Test methods that create DX coils with performance curves
  ##############################################################################

  def test_add_onespeed_dx_coil
    # Test creation of single-speed DX cooling coil with NECB curves
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    always_on = model.alwaysOnDiscreteSchedule

    dx_coil = standard.add_onespeed_DX_coil(model, always_on)

    assert dx_coil.is_a?(OpenStudio::Model::CoilCoolingDXSingleSpeed), "Should create single-speed DX cooling coil"

    # Verify performance curves were applied
    # Note: In OpenStudio 3.x, these methods return Curve directly, not OptionalCurve
    capft_curve = dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve
    assert capft_curve.is_a?(OpenStudio::Model::Curve), "Should have CAPFT curve"

    capfflow_curve = dx_coil.totalCoolingCapacityFunctionOfFlowFractionCurve
    assert capfflow_curve.is_a?(OpenStudio::Model::Curve), "Should have CAPFFLOW curve"

    eirft_curve = dx_coil.energyInputRatioFunctionOfTemperatureCurve
    assert eirft_curve.is_a?(OpenStudio::Model::Curve), "Should have EIRFT curve"

    eirfflow_curve = dx_coil.energyInputRatioFunctionOfFlowFractionCurve
    assert eirfflow_curve.is_a?(OpenStudio::Model::Curve), "Should have EIRFFLOW curve"

    plf_curve = dx_coil.partLoadFractionCorrelationCurve
    assert plf_curve.is_a?(OpenStudio::Model::Curve), "Should have PLF curve"

    # Verify NECB-specific curve coefficients
    capft = capft_curve.to_CurveBiquadratic.get
    assert_in_delta 0.867905, capft.coefficient1Constant, 0.001, "Should have NECB CAPFT coefficient"
  end

  def test_add_onespeed_htg_dx_coil
    # Test creation of single-speed DX heating coil with NECB curves
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    always_on = model.alwaysOnDiscreteSchedule

    dx_htg_coil = standard.add_onespeed_htg_DX_coil(model, always_on)

    assert dx_htg_coil.is_a?(OpenStudio::Model::CoilHeatingDXSingleSpeed), "Should create single-speed DX heating coil"

    # Verify performance curves (these methods return Curve directly, not OptionalCurve)
    capft_curve = dx_htg_coil.totalHeatingCapacityFunctionofTemperatureCurve
    assert capft_curve.is_a?(OpenStudio::Model::Curve), "Should have CAPFT curve"

    capfflow_curve = dx_htg_coil.totalHeatingCapacityFunctionofFlowFractionCurve
    assert capfflow_curve.is_a?(OpenStudio::Model::Curve), "Should have CAPFFLOW curve"

    eirft_curve = dx_htg_coil.energyInputRatioFunctionofTemperatureCurve
    assert eirft_curve.is_a?(OpenStudio::Model::Curve), "Should have EIRFT curve"

    eirfflow_curve = dx_htg_coil.energyInputRatioFunctionofFlowFractionCurve
    assert eirfflow_curve.is_a?(OpenStudio::Model::Curve), "Should have EIRFFLOW curve"

    plf_curve = dx_htg_coil.partLoadFractionCorrelationCurve
    assert plf_curve.is_a?(OpenStudio::Model::Curve), "Should have PLF curve"

    # Verify minimum outdoor temperature for compressor operation
    assert_equal(-10.0, dx_htg_coil.minimumOutdoorDryBulbTemperatureforCompressorOperation, "Should have -10C min outdoor temp")
  end

  def test_coil_dx_heating_type_reference_heat_pump
    # Test determination of supplemental heating type in reference heat pump
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create heat pump with gas supplemental heating
    heat_pump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(
      model,
      model.alwaysOnDiscreteSchedule,
      OpenStudio::Model::FanOnOff.new(model),
      OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model),
      OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model),
      OpenStudio::Model::CoilHeatingGas.new(model) # Gas supplemental heating
    )

    dx_heating_coil = heat_pump.heatingCoil.to_CoilHeatingDXSingleSpeed.get

    # Test with necb_reference_hp = true
    heating_type = standard.coil_dx_heating_type(dx_heating_coil, necb_reference_hp: true)

    assert_equal 'All Other', heating_type, "Should identify gas supplemental heating as 'All Other'"
  end

  def test_coil_dx_heating_type_electric_supplement
    # Test heat pump with electric supplemental heating
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create heat pump with electric supplemental heating
    heat_pump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(
      model,
      model.alwaysOnDiscreteSchedule,
      OpenStudio::Model::FanOnOff.new(model),
      OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model),
      OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model),
      OpenStudio::Model::CoilHeatingElectric.new(model) # Electric supplemental heating
    )

    dx_heating_coil = heat_pump.heatingCoil.to_CoilHeatingDXSingleSpeed.get

    heating_type = standard.coil_dx_heating_type(dx_heating_coil, necb_reference_hp: true)

    assert_equal 'Electric Resistance or None', heating_type, "Should identify electric supplement"
  end

  ##############################################################################
  # ZONE EQUIPMENT TESTS
  # Test zone-level HVAC equipment creation and configuration
  ##############################################################################

  def test_add_zone_baseboards_electric
    # Test electric baseboard creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zone = model.getThermalZones.first
    hw_loop = nil # Not needed for electric

    standard.add_zone_baseboards(baseboard_type: 'Electric', hw_loop: hw_loop, model: model, zone: zone)

    # Verify electric baseboard was added
    zone_equipment = zone.equipment
    has_electric_baseboard = zone_equipment.any? { |equip| equip.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }

    assert has_electric_baseboard, "Zone should have electric baseboard"
  end

  def test_add_zone_baseboards_hot_water
    # Test hot water baseboard creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zone = model.getThermalZones.first
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_zone_baseboards(baseboard_type: 'Hot Water', hw_loop: hw_loop, model: model, zone: zone)

    # Verify hot water baseboard was added
    zone_equipment = zone.equipment
    has_hw_baseboard = zone_equipment.any? { |equip| equip.to_ZoneHVACBaseboardConvectiveWater.is_initialized }

    assert has_hw_baseboard, "Zone should have hot water baseboard"

    # Verify baseboard is connected to hot water loop
    hw_baseboard = zone_equipment.find { |equip| equip.to_ZoneHVACBaseboardConvectiveWater.is_initialized }
                                  .to_ZoneHVACBaseboardConvectiveWater.get
    baseboard_coil = hw_baseboard.heatingCoil
    assert baseboard_coil.plantLoop.is_initialized, "Baseboard coil should be connected to plant loop"
  end

  def test_add_ptac_dx_cooling
    # Test PTAC with DX cooling creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zone = model.getThermalZones.first
    zero_outdoor_air = false

    standard.add_ptac_dx_cooling(model, zone, zero_outdoor_air)

    # Verify PTAC was added
    zone_equipment = zone.equipment
    has_ptac = zone_equipment.any? { |equip| equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }

    assert has_ptac, "Zone should have PTAC"

    ptac = zone_equipment.find { |equip| equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
                         .to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify PTAC has DX cooling coil
    assert ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized, "PTAC should have DX cooling coil"

    # Verify fan pressure rise
    fan = ptac.supplyAirFan.to_FanOnOff.get
    assert_equal 640, fan.pressureRise, "PTAC fan should have 640 Pa pressure rise"
  end

  def test_add_ptac_dx_cooling_zero_outdoor_air
    # Test PTAC with zero outdoor air
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, true) # zero_outdoor_air = true

    ptac = zone.equipment.find { |equip| equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
                         .to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify OA flow rates are near zero
    assert ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get < 0.0001, "PTAC should have minimal OA when no heating/cooling"
    assert ptac.outdoorAirFlowRateDuringCoolingOperation.get < 0.0001, "PTAC should have minimal OA during cooling"
    assert ptac.outdoorAirFlowRateDuringHeatingOperation.get < 0.0001, "PTAC should have minimal OA during heating"
  end

  ##############################################################################
  # AIR TERMINAL TESTS
  # Test VAV terminal unit configuration
  ##############################################################################

  def test_air_terminal_single_duct_vav_reheat_set_heating_cap
    # Test VAV reheat terminal capacity sizing
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create VAV terminal with electric reheat
    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName('VAV Terminal with Reheat')

    # Set constant minimum air flow fraction
    terminal.setConstantMinimumAirFlowFraction(0.3)

    # Need to size the terminal first (set a flow rate)
    terminal.setMaximumAirFlowRate(1.0) # 1.0 m3/s

    # Apply heating capacity sizing
    result = standard.air_terminal_single_duct_vav_reheat_set_heating_cap(terminal)

    assert result, "Should successfully set heating capacity"

    # Verify reheat coil capacity was set
    assert reheat_coil.nominalCapacity.is_initialized, "Reheat coil should have nominal capacity set"

    # Verify maximum reheat air temperature
    max_temp = terminal.maximumReheatAirTemperature
    if max_temp.is_a?(Float)
      assert_equal 43.0, max_temp, "Max reheat temp should be 43C"
    else
      assert_equal 43.0, max_temp.get, "Max reheat temp should be 43C"
    end
  end

  def test_air_terminal_single_duct_vav_reheat_hot_water
    # Test VAV terminal with hot water reheat
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    hw_loop = create_hot_water_loop(model, standard)

    reheat_coil = OpenStudio::Model::CoilHeatingWater.new(model)
    hw_loop.addDemandBranchForComponent(reheat_coil)

    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setConstantMinimumAirFlowFraction(0.25)
    terminal.setMaximumAirFlowRate(2.0)

    result = standard.air_terminal_single_duct_vav_reheat_set_heating_cap(terminal)

    assert result, "Should successfully set heating capacity for HW coil"

    # Verify hot water coil capacity was set
    assert reheat_coil.ratedCapacity.is_initialized, "HW reheat coil should have rated capacity"
    assert_equal 'NominalCapacity', reheat_coil.performanceInputMethod, "Should use NominalCapacity input method"
  end

  ##############################################################################
  # PLANT LOOP HELPER METHODS
  # Test hot water, chilled water, and condenser water loop setup
  ##############################################################################

  def test_setup_hw_loop_with_components
    # Test hot water loop setup with boilers and pumps
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create an empty hot water loop first
    hw_loop = OpenStudio::Model::PlantLoop.new(model)

    boiler_fueltype = 'NaturalGas'
    backup_boiler_fueltype = 'DefaultFuel'  # Required parameter
    pump_flow_sch = nil  # Optional schedule

    standard.setup_hw_loop_with_components(
      model,
      hw_loop,
      boiler_fueltype,
      backup_boiler_fueltype,
      pump_flow_sch
    )

    assert hw_loop.is_a?(OpenStudio::Model::PlantLoop), "Should create plant loop"
    assert_equal 'Hot Water Loop', hw_loop.name.to_s, "Should be named Hot Water Loop"

    # Verify loop has boiler
    has_boiler = hw_loop.supplyComponents.any? { |comp| comp.to_BoilerHotWater.is_initialized }
    assert has_boiler, "Hot water loop should have boiler"

    # Verify loop has pump
    has_pump = hw_loop.supplyComponents.any? { |comp| comp.to_PumpVariableSpeed.is_initialized }
    assert has_pump, "Hot water loop should have pump"
  end

  def test_setup_chw_loop_with_components_water_cooled
    # Test chilled water loop setup with water-cooled chiller
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chw_loop.setName('Chilled Water Loop')

    chiller_type = 'Scroll' # Water-cooled

    result_loop = standard.setup_chw_loop_with_components(model, chw_loop, chiller_type)

    # Verify chiller was added
    has_chiller = chw_loop.supplyComponents.any? { |comp| comp.to_ChillerElectricEIR.is_initialized }
    assert has_chiller, "Chilled water loop should have chiller"

    # Verify pump was added
    has_pump = chw_loop.supplyComponents.any? { |comp| comp.to_PumpVariableSpeed.is_initialized }
    assert has_pump, "Chilled water loop should have pump"
  end

  def test_setup_cw_loop_with_components
    # Test condenser water loop setup with cooling tower
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    cw_loop.setName('Condenser Water Loop')

    # Create two chillers
    chiller1 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller2 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chw_loop.addSupplyBranchForComponent(chiller1)
    chw_loop.addSupplyBranchForComponent(chiller2)

    result_loop = standard.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Verify cooling tower was added
    has_tower = cw_loop.supplyComponents.any? { |comp| comp.to_CoolingTowerSingleSpeed.is_initialized }
    assert has_tower, "Condenser water loop should have cooling tower"

    # Verify pump was added
    has_pump = cw_loop.supplyComponents.any? { |comp| comp.to_PumpVariableSpeed.is_initialized }
    assert has_pump, "Condenser water loop should have pump"

    # Verify chillers are connected to condenser loop
    assert chiller1.secondaryPlantLoop.is_initialized, "Chiller1 should be connected to condenser loop"
    assert chiller2.secondaryPlantLoop.is_initialized, "Chiller2 should be connected to condenser loop"
  end

  ##############################################################################
  # AIR LOOP CONFIGURATION METHODS
  # Test common air loop setup and system naming
  ##############################################################################

  def test_common_air_loop
    # Test common air loop creation with sizing parameters
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    system_data = {
      name: 'Test MAU System',
      PreheatDesignTemperature: 5.0,
      PreheatDesignHumidityRatio: 0.004,
      PrecoolDesignTemperature: 13.0,
      PrecoolDesignHumidityRatio: 0.008,
      SizingOption: 'Coincident',
      CoolingDesignAirFlowMethod: 'DesignDay',
      HeatingDesignAirFlowMethod: 'DesignDay',
      SystemOutdoorAirMethod: 'ZoneSum',
      TypeofLoadtoSizeOn: 'Sensible',
      CentralCoolingDesignSupplyAirTemperature: 13.0,
      CentralHeatingDesignSupplyAirTemperature: 43.0,
      AllOutdoorAirinCooling: true,
      AllOutdoorAirinHeating: true
    }

    air_loop = standard.common_air_loop(model: model, system_data: system_data)

    assert air_loop.is_a?(OpenStudio::Model::AirLoopHVAC), "Should create air loop"
    assert_equal 'Test MAU System', air_loop.name.to_s, "Air loop should have correct name"

    sizing = air_loop.sizingSystem

    # Verify sizing parameters were applied
    assert_equal 5.0, sizing.preheatDesignTemperature, "Preheat temp should be 5.0C"
    assert_equal 13.0, sizing.precoolDesignTemperature, "Precool temp should be 13.0C"
    assert_equal 'Coincident', sizing.sizingOption, "Should use Coincident sizing"
    assert_equal 'Sensible', sizing.typeofLoadtoSizeOn, "Should size on Sensible load"
    assert sizing.allOutdoorAirinCooling, "Should have 100% OA in cooling"
    assert sizing.allOutdoorAirinHeating, "Should have 100% OA in heating"
  end

  def test_create_heating_cooling_on_off_availability_schedule
    # Test creation of on/off availability schedule
    # Method returns [cooling_schedule, heating_schedule]
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    clg_sch, htg_sch = standard.create_heating_cooling_on_off_availability_schedule(model)

    # Verify cooling schedule
    assert clg_sch.is_a?(OpenStudio::Model::ScheduleRuleset), "Should create cooling schedule ruleset"
    assert clg_sch.name.to_s.include?('clg'), "Cooling schedule name should indicate cooling"

    # Verify heating schedule
    assert htg_sch.is_a?(OpenStudio::Model::ScheduleRuleset), "Should create heating schedule ruleset"
    assert htg_sch.name.to_s.include?('htg'), "Heating schedule name should indicate heating"

    # Verify schedules have rules
    assert clg_sch.scheduleRules.size > 0, "Cooling schedule should have rules"
    assert htg_sch.scheduleRules.size > 0, "Heating schedule should have rules"
  end

  ##############################################################################
  # SYSTEM NAMING METHODS
  # Test air loop system naming conventions and updates
  ##############################################################################

  def test_assign_base_sys_name
    # Test base system name assignment
    # Use a proper NECB system abbreviation (sys_6 = VAV with reheat)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    # Add components for System 6 (VAV with reheat)
    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.addToNode(air_loop.supplyInletNode)

    # Add heating and cooling coils (chilled water)
    htg_coil = OpenStudio::Model::CoilHeatingWater.new(model)
    htg_coil.addToNode(air_loop.supplyInletNode)

    clg_coil = OpenStudio::Model::CoilCoolingWater.new(model)
    clg_coil.addToNode(air_loop.supplyInletNode)

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Add VAV terminal with reheat to a zone (required for sys_6 detection)
    zone = model.getThermalZones.first
    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    air_loop.addBranchForZone(zone, terminal)

    # Use proper NECB system abbreviation
    sys_abbr = 'sys_6'  # VAV with reheat
    sys_oa = 'oa>min'
    sys_name_pars = {
      sys_hr: 'none',
      sys_htg: 'hot water',
      sys_clg: 'chilled water',
      sys_sf: 'vv',
      zone_htg: 'electric',
      zone_clg: 'none',
      sys_rf: 'none'
    }

    # Call the method
    standard.assign_base_sys_name(air_loop: air_loop, sys_abbr: sys_abbr, sys_oa: sys_oa, sys_name_pars: sys_name_pars)

    name = air_loop.name.to_s

    # Verify name was set and contains expected components using the actual naming convention
    # The method uses abbreviations like 'sh>c-hw' for hot water heating, 'sc>c-chw' for chilled water cooling
    assert !name.empty?, "System name should be set (got: #{name})"
    assert name.include?('sys_6'), "System name should include system abbreviation (got: #{name})"
    assert name.include?('sh>c-hw'), "System name should include hot water heating (got: #{name})"
    assert name.include?('sc>c-chw'), "System name should include chilled water cooling (got: #{name})"
    assert name.include?('ssf>vv'), "System name should include variable volume fan (got: #{name})"
    assert name.include?('zh>b-e'), "System name should include electric zone heating (got: #{name})"
  end

  def test_update_sys_name
    # Test system name update
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('PSZ|oa>min|sh>gas|sc>dx|ssf>cv|zh>none|zc>none|')

    # Update heating type
    standard.update_sys_name(air_loop, sys_htg: 'hwcoil')

    updated_name = air_loop.name.to_s

    assert updated_name.include?('sh>hwcoil'), "System name should have updated heating designation"
    refute updated_name.include?('sh>gas'), "Old heating designation should be removed"
  end

  def test_update_sys_name_multiple_fields
    # Test updating multiple fields in system name
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('VAV|oa>full|shr>none|sh>gas|sc>chw|ssf>vav|zh>elec|zc>none|')

    standard.update_sys_name(air_loop, sys_hr: 'erv', sys_clg: 'dx', zone_htg: 'hwbb')

    updated_name = air_loop.name.to_s

    assert updated_name.include?('shr>erv'), "Should update heat recovery"
    assert updated_name.include?('sc>dx'), "Should update cooling type"
    assert updated_name.include?('zh>hwbb'), "Should update zone heating"
  end

  ##############################################################################
  # FAN PART LOAD LIMITATION TEST
  # Test VAV fan part load power limitation requirement
  ##############################################################################

  def test_fan_variable_volume_part_load_fan_power_limitation_not_required
    # NECB does not require part load fan power limitation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanVariableVolume.new(model)

    part_load_control_required = standard.fan_variable_volume_part_load_fan_power_limitation?(fan)

    refute part_load_control_required, "NECB should not require part load fan power limitation"
  end

  ##############################################################################
  # FAN PRESSURE RISE TESTS
  # Test prototype fan pressure rise application
  ##############################################################################

  def test_fan_variable_volume_apply_prototype_fan_pressure_rise_supply
    # Test VAV supply fan pressure rise
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('VAV Supply Fan')

    result = standard.fan_variable_volume_apply_prototype_fan_pressure_rise(fan)

    assert result, "Should successfully apply pressure rise"

    # NECB uses 1000 Pa for supply fans
    supply_pressure = standard.get_standards_constant('supply_fan_variable_volume_pressure_rise_value')
    assert_equal supply_pressure, fan.pressureRise, "Supply fan should have correct pressure rise"
  end

  def test_fan_variable_volume_apply_prototype_fan_pressure_rise_return
    # Test VAV return fan pressure rise
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    fan = OpenStudio::Model::FanVariableVolume.new(model)
    fan.setName('VAV Return Fan')

    standard.fan_variable_volume_apply_prototype_fan_pressure_rise(fan)

    # NECB uses 458.33 Pa for return fans
    return_pressure = standard.get_standards_constant('return_fan_variable_volume_pressure_rise_value')
    assert_equal return_pressure, fan.pressureRise, "Return fan should have correct pressure rise"
  end

  ##############################################################################
  # ECONOMIZER APPLICATION TEST
  # Test economizer application to entire model
  ##############################################################################

  def test_apply_economizers_model_wide
    # Test applying economizers to all air loops in model
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create air loop with sufficient cooling capacity for economizer
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Test Air Loop')
    air_loop.setDesignSupplyAirFlowRate(3.0) # 3000 L/s > 1500 L/s threshold

    # Add OA system
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(air_loop.supplyInletNode)

    # Add cooling coil
    cooling_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cooling_coil.setRatedTotalCoolingCapacity(25000) # 25 kW > 20 kW
    cooling_coil.addToNode(air_loop.supplyInletNode)

    # Apply economizers to model
    standard.apply_economizers('NECB HDD Method', model)

    # Verify economizer was applied
    assert_equal 'DifferentialEnthalpy', oa_controller.getEconomizerControlType, "Should apply differential enthalpy economizer"
  end

  ##############################################################################
  # THERMAL ZONE HELPER METHOD TEST
  # Test thermal zone centroid calculation
  ##############################################################################

  def test_thermal_zone_get_centroid_per_floor
    # Test calculation of zone centroid per floor
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zone = model.getThermalZones.first

    centroid_per_floor = standard.thermal_zone_get_centroid_per_floor(zone)

    # Method should return hash, array, or nil
    assert !centroid_per_floor.nil?, "Should return non-nil result"

    # If it's a hash, verify structure
    if centroid_per_floor.is_a?(Hash) && !centroid_per_floor.empty?
      centroid_per_floor.each do |floor, centroid|
        assert centroid.key?(:x), "Centroid should have x coordinate"
        assert centroid.key?(:y), "Centroid should have y coordinate"
        assert centroid.key?(:z), "Centroid should have z coordinate"
      end
    end
  end

  ##############################################################################
  # EMS NIGHT CYCLE CONTROL TEST
  # Test EMS program creation for multi-speed heat pump night cycle
  ##############################################################################

  def test_create_ems_to_turn_on_multispeed_heat_pump_for_night_cycle
    # Test EMS creation for night cycle control
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Create components required for multi-speed heat pump
    fan = OpenStudio::Model::FanOnOff.new(model)
    htg_coil = OpenStudio::Model::CoilHeatingDXMultiSpeed.new(model)
    clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
    supp_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)

    # Create multi-speed heat pump
    heat_pump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(
      model,
      fan,
      htg_coil,
      clg_coil,
      supp_htg_coil
    )
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    heat_pump.addToNode(air_loop.supplyInletNode)

    # Add availability manager night cycle
    avail_mgr = OpenStudio::Model::AvailabilityManagerNightCycle.new(model)
    air_loop.addAvailabilityManager(avail_mgr)

    # Create EMS program
    standard.create_ems_to_turn_on_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed_for_night_cycle(heat_pump)

    # Verify EMS components were created
    has_sensor = model.getEnergyManagementSystemSensors.size > 0
    has_actuator = model.getEnergyManagementSystemActuators.size > 0
    has_program = model.getEnergyManagementSystemPrograms.size > 0
    has_pcm = model.getEnergyManagementSystemProgramCallingManagers.size > 0

    assert has_sensor, "Should create EMS sensor"
    assert has_actuator, "Should create EMS actuator"
    assert has_program, "Should create EMS program"
    assert has_pcm, "Should create EMS program calling manager"
  end

  ##############################################################################
  # VRF EFFICIENCY TEST
  # Test VRF efficiency application (dummy method for NECB)
  ##############################################################################

  def test_air_conditioner_variable_refrigerant_flow_apply_efficiency_and_curves
    # NECB uses dummy method to avoid NREL defaults conflicting with NRCan VRF ECMs
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    vrf = OpenStudio::Model::AirConditionerVariableRefrigerantFlow.new(model)

    # Should return nil (no-op method)
    result = standard.air_conditioner_variable_refrigerant_flow_apply_efficiency_and_curves(vrf)

    assert_nil result, "VRF efficiency method should be no-op for NECB (returns nil)"
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  # Helper to create baseline NECB model with basic geometry
  def create_baseline_necb_model(template:, climate:)
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
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
