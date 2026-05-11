#!/usr/bin/env ruby

# Test NECB Multi-Speed HVAC Systems
#
# System 1 Multi-Speed: PTAC with Multi-Speed Heat Pump + Electric Baseboard
#   - Variable speed PTHP (AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed)
#   - Multi-speed DX cooling (CoilCoolingDXMultiSpeed with 2 stages)
#   - Multi-stage gas heating (CoilHeatingGasMultiStage with 1 stage)
#   - Supplemental heating coil (electric or hot water)
#   - Variable speed compressor operation
#   - Make-up air unit (MAU) if specified
#   - Electric or hot water baseboard heating
#
# System 3 & 8 Multi-Speed: PSZ/VAV with Multi-Speed RTU + Baseboard
#   - Variable speed packaged rooftop unit
#   - Multi-speed DX cooling (CoilCoolingDXMultiSpeed with 2 stages)
#   - Multi-stage gas/electric heating (CoilHeatingGasMultiStage with 1 stage)
#   - Supplemental heating coil
#   - Variable speed fan operation
#   - Single zone or multi-zone control
#   - Electric or hot water baseboard heating
#
# Key Differences from Single-Speed:
#   - Multi-speed compressor with staged cooling (vs single-speed)
#   - Multi-stage heating (vs single-stage)
#   - AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed (vs single-speed unitary)
#   - CoilCoolingDXMultiSpeed with stages (vs CoilCoolingDXSingleSpeed)
#   - CoilHeatingGasMultiStage with stages (vs single coil)
#   - Better part-load performance
#
# Test Coverage: 15 tests
# - System 1 Multi-Speed: 7 tests
# - System 3 & 8 Multi-Speed: 6 tests
# - Comparison & Vintage: 2 tests
#
# Execution time: ~6-8 seconds

require_relative '../test_helper'

class TestNECBSystemsMultiSpeed < Minitest::Test

  # Helper method to create a simple test model with thermal zones
  def create_simple_model(standard, num_zones: 1)
    model = OpenStudio::Model::Model.new

    # Create simple rectangular geometry
    length = 15.0
    width = 10.0

    num_zones.times do |i|
      # Create a space for each zone
      space = OpenStudio::Model::Space.new(model)
      space.setName("Space_#{i + 1}")

      # Create simple rectangular floor
      vertices = OpenStudio::Point3dVector.new
      vertices << OpenStudio::Point3d.new(0 + (i * length), 0, 0)
      vertices << OpenStudio::Point3d.new(length + (i * length), 0, 0)
      vertices << OpenStudio::Point3d.new(length + (i * length), width, 0)
      vertices << OpenStudio::Point3d.new(0 + (i * length), width, 0)

      floor = OpenStudio::Model::Surface.new(vertices, model)
      floor.setSpace(space)

      # Create thermal zone
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone_#{i + 1}")
      space.setThermalZone(zone)

      # Add thermostat
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      thermostat.setName("#{zone.name} Thermostat")
      zone.setThermostatSetpointDualSetpoint(thermostat)
    end

    model
  end

  # Helper to setup hot water loop
  def setup_hw_loop(standard, model, boiler_fuel)
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName("Hot Water Loop")
    standard.setup_hw_loop_with_components(
      model,
      hw_loop,
      boiler_fuel,
      boiler_fuel,
      model.alwaysOnDiscreteSchedule
    )
    hw_loop
  end

  #################################################
  # System 1 Multi-Speed Tests
  #################################################

  # Test 1: Verify System 1 Multi-Speed with MAU creates unitary heat pump
  def test_system_1_multispeed_mau_creation
    puts "\n[System 1 Multi-Speed] Testing MAU with multi-speed heat pump creation..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 2)

    # Create hot water loop for MAU supplemental heating
    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    # Add System 1 Multi-Speed with MAU
    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    # Verify multi-speed heat pump created
    heat_pumps = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds
    assert_equal 1, heat_pumps.size, "Should have 1 multi-speed heat pump for MAU"

    mshp = heat_pumps.first

    # Verify it's assigned to control zone
    assert mshp.controllingZoneorThermostatLocation.is_initialized,
           "Multi-speed heat pump should have control zone"

    # Verify speed configuration
    assert_equal 1, mshp.numberofSpeedsforHeating, "Should have 1 heating speed"
    assert_equal 2, mshp.numberofSpeedsforCooling, "Should have 2 cooling speeds"

    # Verify minimum compressor temperature
    assert_in_delta(-10.0, mshp.minimumOutdoorDryBulbTemperatureforCompressorOperation, 0.1,
                    "Minimum compressor temp should be -10°C per NECB")

    puts "  ✓ System 1 Multi-Speed MAU created with proper configuration"
  end

  # Test 2: Verify multi-speed cooling coil with 2 stages
  def test_system_1_multispeed_cooling_coil_stages
    puts "\n[System 1 Multi-Speed] Testing multi-speed DX cooling coil stages..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    cooling_coil = mshp.coolingCoil

    # Verify cooling coil is multi-speed
    assert cooling_coil.to_CoilCoolingDXMultiSpeed.is_initialized,
           "Should have multi-speed DX cooling coil"

    dx_coil = cooling_coil.to_CoilCoolingDXMultiSpeed.get

    # Verify 2 cooling stages
    stages = dx_coil.stages
    assert_equal 2, stages.size, "Should have 2 cooling stages"

    # Verify fuel type
    assert_equal 'Electricity', dx_coil.fuelType, "Cooling should use electricity"

    # Verify part load fraction configuration
    refute dx_coil.applyPartLoadFractiontoSpeedsGreaterthan1,
           "Part load fraction should not apply to speeds > 1"

    puts "  ✓ Multi-speed cooling coil has 2 stages with proper configuration"
  end

  # Test 3: Verify multi-stage gas heating coil
  def test_system_1_multispeed_heating_coil_stages
    puts "\n[System 1 Multi-Speed] Testing multi-stage gas heating coil..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    heating_coil = mshp.heatingCoil

    # Verify heating coil is multi-stage gas
    assert heating_coil.to_CoilHeatingGasMultiStage.is_initialized,
           "Should have multi-stage gas heating coil"

    gas_coil = heating_coil.to_CoilHeatingGasMultiStage.get

    # Verify 1 heating stage
    stages = gas_coil.stages
    assert_equal 1, stages.size, "Should have 1 heating stage"

    # Verify stage has minimal capacity (MAU heating is via supplemental coil)
    stage = stages.first
    assert stage.nominalCapacity.is_initialized,
           "Heating stage should have capacity set"
    assert_in_delta 0.001, stage.nominalCapacity.get, 0.0001,
                    "Heating stage should have minimal capacity (0.001 W)"

    puts "  ✓ Multi-stage gas heating coil configured correctly"
  end

  # Test 4: Verify hot water supplemental heating coil
  def test_system_1_multispeed_hw_supplemental_heating
    puts "\n[System 1 Multi-Speed] Testing hot water supplemental heating..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    supp_coil = mshp.supplementalHeatingCoil

    # Verify supplemental coil is hot water
    assert supp_coil.to_CoilHeatingWater.is_initialized,
           "Supplemental heating should be hot water coil"

    hw_coil = supp_coil.to_CoilHeatingWater.get

    # Verify connected to hot water loop
    assert hw_coil.plantLoop.is_initialized,
           "Hot water coil should be connected to plant loop"
    assert_equal hw_loop, hw_coil.plantLoop.get,
                 "Hot water coil should be on specified hw_loop"

    puts "  ✓ Hot water supplemental heating coil connected properly"
  end

  # Test 5: Verify electric supplemental heating coil
  def test_system_1_multispeed_electric_supplemental_heating
    puts "\n[System 1 Multi-Speed] Testing electric supplemental heating..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    supp_coil = mshp.supplementalHeatingCoil

    # Verify supplemental coil is electric
    assert supp_coil.to_CoilHeatingElectric.is_initialized,
           "Supplemental heating should be electric coil when specified"

    elec_coil = supp_coil.to_CoilHeatingElectric.get

    # Verify availability schedule
    schedule = elec_coil.availabilitySchedule
    refute_nil schedule, "Electric coil should have availability schedule"

    puts "  ✓ Electric supplemental heating coil configured properly"
  end

  # Test 6: Verify PTAC units still created (zone-level cooling)
  def test_system_1_multispeed_ptac_zone_units
    puts "\n[System 1 Multi-Speed] Testing PTAC units in zones..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 3)

    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    # Verify PTAC units created for each zone
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal 3, ptacs.size, "Should have PTAC for each zone"

    # Verify each PTAC is assigned to a zone
    ptacs.each do |ptac|
      assert ptac.thermalZone.is_initialized,
             "Each PTAC should be assigned to a zone"
    end

    # Verify electric baseboards also created
    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert_equal 3, baseboards.size, "Should have electric baseboard for each zone"

    puts "  ✓ PTAC units and baseboards created for all zones"
  end

  # Test 7: Verify MAU air loop configuration
  def test_system_1_multispeed_mau_air_loop
    puts "\n[System 1 Multi-Speed] Testing MAU air loop configuration..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 2)

    hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model,
      zones: model.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    # Verify air loop created
    air_loops = model.getAirLoopHVACs
    assert air_loops.size >= 1, "Should have MAU air loop"

    mau_loop = air_loops.first

    # Verify outdoor air system
    oa_system = mau_loop.airLoopHVACOutdoorAirSystem
    assert oa_system.is_initialized, "MAU should have outdoor air system"

    oa_sys = oa_system.get
    oa_controller = oa_sys.getControllerOutdoorAir

    # Verify outdoor air method is ZoneSum
    mech_vent = oa_controller.controllerMechanicalVentilation
    assert_equal 'ZoneSum', mech_vent.systemOutdoorAirMethod,
                 "Outdoor air method should be ZoneSum"

    # Verify setpoint manager exists
    setpoint_mgrs = mau_loop.supplyOutletNode.setpointManagers
    assert setpoint_mgrs.size > 0, "MAU should have setpoint manager"

    # Verify zones connected to MAU
    assert mau_loop.thermalZones.size > 0,
           "MAU should serve thermal zones"

    puts "  ✓ MAU air loop properly configured with outdoor air and zones"
  end

  #################################################
  # System 3 & 8 Multi-Speed Tests
  #################################################

  # Test 8: Verify System 3 Multi-Speed creates unitary heat pump
  def test_system_3_multispeed_basic_creation
    puts "\n[System 3 Multi-Speed] Testing basic creation with multi-speed RTU..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    zone = model.getThermalZones.first

    # Add System 3 Multi-Speed with gas heating
    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
      model: model,
      zones: [zone],
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil,
      new_auto_zoner: false
    )

    # Verify multi-speed heat pump created
    heat_pumps = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds
    assert heat_pumps.size > 0, "Should have multi-speed heat pump(s)"

    mshp = heat_pumps.first

    # Verify speed configuration for System 3
    assert_equal 1, mshp.numberofSpeedsforHeating, "Should have 1 heating speed"
    assert_equal 2, mshp.numberofSpeedsforCooling, "Should have 2 cooling speeds"

    # Verify control zone
    assert mshp.controllingZoneorThermostatLocation.is_initialized,
           "Should have control zone"

    # Verify minimum compressor temperature
    assert_in_delta(-10.0, mshp.minimumOutdoorDryBulbTemperatureforCompressorOperation, 0.1,
                    "Minimum compressor temp should be -10°C per NECB")

    puts "  ✓ System 3 Multi-Speed RTU created successfully"
  end

  # Test 9: Verify multi-speed cooling coil in System 3
  def test_system_3_multispeed_cooling_coil
    puts "\n[System 3 Multi-Speed] Testing multi-speed cooling coil..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    zone = model.getThermalZones.first

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
      model: model,
      zones: [zone],
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil,
      new_auto_zoner: false
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    cooling_coil = mshp.coolingCoil

    # Verify multi-speed DX cooling
    assert cooling_coil.to_CoilCoolingDXMultiSpeed.is_initialized,
           "Should have multi-speed DX cooling coil"

    dx_coil = cooling_coil.to_CoilCoolingDXMultiSpeed.get

    # Verify 2 stages
    assert_equal 2, dx_coil.stages.size, "Should have 2 cooling stages"

    # Verify electricity fuel type
    assert_equal 'Electricity', dx_coil.fuelType, "Should use electricity"

    # Verify part load fraction setting
    refute dx_coil.applyPartLoadFractiontoSpeedsGreaterthan1,
           "Part load fraction should not apply to speeds > 1"

    puts "  ✓ System 3 multi-speed cooling coil configured properly"
  end

  # Test 10: Verify multi-stage gas heating in System 3
  def test_system_3_multispeed_gas_heating
    puts "\n[System 3 Multi-Speed] Testing multi-stage gas heating..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    zone = model.getThermalZones.first

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
      model: model,
      zones: [zone],
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil,
      new_auto_zoner: false
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    heating_coil = mshp.heatingCoil

    # Verify multi-stage gas heating
    assert heating_coil.to_CoilHeatingGasMultiStage.is_initialized,
           "Should have multi-stage gas heating coil"

    gas_coil = heating_coil.to_CoilHeatingGasMultiStage.get

    # Verify 1 stage
    assert_equal 1, gas_coil.stages.size, "Should have 1 heating stage"

    # Verify supplemental coil
    supp_coil = mshp.supplementalHeatingCoil
    assert supp_coil.to_CoilHeatingGas.is_initialized,
           "Supplemental should be gas coil for Gas heating_coil_type"

    gas_supp = supp_coil.to_CoilHeatingGas.get
    assert gas_supp.nominalCapacity.is_initialized,
           "Gas supplemental should have minimal capacity"
    assert_in_delta 0.001, gas_supp.nominalCapacity.get, 0.0001,
                    "Gas supplemental capacity should be 0.001 W"

    puts "  ✓ System 3 multi-stage gas heating configured properly"
  end

  # Test 11: Verify electric heating variant in System 3
  def test_system_3_multispeed_electric_heating
    puts "\n[System 3 Multi-Speed] Testing electric heating variant..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    zone = model.getThermalZones.first

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
      model: model,
      zones: [zone],
      heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil,
      new_auto_zoner: false
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    heating_coil = mshp.heatingCoil

    # Verify multi-stage gas heating (even for Electric type)
    assert heating_coil.to_CoilHeatingGasMultiStage.is_initialized,
           "Primary heating should still be multi-stage gas"

    # Verify supplemental is electric
    supp_coil = mshp.supplementalHeatingCoil
    assert supp_coil.to_CoilHeatingElectric.is_initialized,
           "Supplemental should be electric for Electric heating_coil_type"

    # Verify heating stage has minimal capacity
    gas_coil = heating_coil.to_CoilHeatingGasMultiStage.get
    stage = gas_coil.stages.first
    assert stage.nominalCapacity.is_initialized,
           "Heating stage should have minimal capacity"
    assert_in_delta 0.001, stage.nominalCapacity.get, 0.0001,
                    "Heating stage capacity should be 0.001 W for Electric type"

    puts "  ✓ System 3 electric heating variant configured properly"
  end

  # Test 12: Verify air loop components in System 3
  def test_system_3_multispeed_air_loop_components
    puts "\n[System 3 Multi-Speed] Testing air loop components..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    zone = model.getThermalZones.first

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
      model: model,
      zones: [zone],
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil,
      new_auto_zoner: false
    )

    # Verify air loop created
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have air loop(s)"

    air_loop = air_loops.first

    # Verify outdoor air system
    oa_system = air_loop.airLoopHVACOutdoorAirSystem
    assert oa_system.is_initialized, "Should have outdoor air system"

    oa_sys = oa_system.get
    oa_controller = oa_sys.getControllerOutdoorAir

    # Verify ZoneSum outdoor air method
    mech_vent = oa_controller.controllerMechanicalVentilation
    assert_equal 'ZoneSum', mech_vent.systemOutdoorAirMethod,
                 "Outdoor air method should be ZoneSum"

    # Verify setpoint manager (single zone reheat for PSZ)
    setpoint_mgrs = air_loop.supplyOutletNode.setpointManagers
    assert setpoint_mgrs.size > 0, "Should have setpoint manager"

    sptrh = setpoint_mgrs.first
    if sptrh.to_SetpointManagerSingleZoneReheat.is_initialized
      spm = sptrh.to_SetpointManagerSingleZoneReheat.get

      # Verify control zone
      assert spm.controlZone.is_initialized,
             "Setpoint manager should have control zone"

      # Verify temperature limits per NECB
      assert_in_delta 13.0, spm.minimumSupplyAirTemperature, 0.1,
                      "Min supply temp should be 13°C"
      assert_in_delta 43.0, spm.maximumSupplyAirTemperature, 0.1,
                      "Max supply temp should be 43°C"
    end

    puts "  ✓ System 3 air loop components configured properly"
  end

  # Test 13: Verify constant volume fan in System 3 multi-speed
  def test_system_3_multispeed_fan_configuration
    puts "\n[System 3 Multi-Speed] Testing fan configuration..."

    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)

    zone = model.getThermalZones.first

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
      model: model,
      zones: [zone],
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil,
      new_auto_zoner: false
    )

    mshp = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first

    # Verify fan is constant volume (used with multi-speed unitary system)
    fan = mshp.supplyAirFan
    assert fan.to_FanConstantVolume.is_initialized,
           "Should have constant volume fan in multi-speed system"

    cv_fan = fan.to_FanConstantVolume.get

    # Verify availability schedule
    schedule = cv_fan.availabilitySchedule
    refute_nil schedule, "Fan should have availability schedule"

    puts "  ✓ System 3 fan configured properly"
  end

  #################################################
  # Comparison & Vintage Tests
  #################################################

  # Test 14: Compare single-speed vs multi-speed System 1
  def test_system_1_single_vs_multispeed_comparison
    puts "\n[Comparison] Testing single-speed vs multi-speed System 1..."

    standard = Standard.build('NECB2011')

    # Single-speed model
    model_single = create_simple_model(standard, num_zones: 1)
    zone_single = model_single.getThermalZones.first
    standard.add_ptac_dx_cooling(model_single, zone_single, false)

    # Multi-speed model with MAU
    model_multi = create_simple_model(standard, num_zones: 1)
    hw_loop = setup_hw_loop(standard, model_multi, 'NaturalGas')
    standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
      model: model_multi,
      zones: model_multi.getThermalZones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Electric',
      hw_loop: hw_loop
    )

    # Single-speed: PTAC with single-speed DX
    ptac = model_single.getZoneHVACPackagedTerminalAirConditioners.first
    refute_nil ptac, "Single-speed should have PTAC"

    single_dx = ptac.coolingCoil
    assert single_dx.to_CoilCoolingDXSingleSpeed.is_initialized,
           "Single-speed should use CoilCoolingDXSingleSpeed"

    # Multi-speed: Unitary heat pump with multi-speed DX
    mshp = model_multi.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds.first
    refute_nil mshp, "Multi-speed should have unitary heat pump"

    multi_dx = mshp.coolingCoil
    assert multi_dx.to_CoilCoolingDXMultiSpeed.is_initialized,
           "Multi-speed should use CoilCoolingDXMultiSpeed"

    # Multi-speed has staged cooling
    dx_multi = multi_dx.to_CoilCoolingDXMultiSpeed.get
    assert_equal 2, dx_multi.stages.size, "Multi-speed should have 2 cooling stages"

    # Multi-speed has better part-load performance
    refute dx_multi.applyPartLoadFractiontoSpeedsGreaterthan1,
           "Multi-speed should not apply PLF to higher speeds"

    puts "  ✓ Single-speed vs multi-speed differences validated"
  end

  # Test 15: Verify multi-speed systems across NECB vintages
  def test_multispeed_systems_necb_vintages
    puts "\n[Vintages] Testing multi-speed systems across NECB vintages..."

    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      standard = Standard.build(vintage)
      model = create_simple_model(standard, num_zones: 1)

      hw_loop = setup_hw_loop(standard, model, 'NaturalGas')

      # Test System 1 Multi-Speed
      standard.add_sys1_unitary_ac_baseboard_heating_multi_speed(
        model: model,
        zones: model.getThermalZones,
        mau_type: true,
        mau_heating_coil_type: 'Hot Water',
        baseboard_type: 'Electric',
        hw_loop: hw_loop
      )

      # Verify multi-speed heat pump created
      heat_pumps = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds
      assert heat_pumps.size > 0,
             "#{vintage} should support System 1 Multi-Speed"

      mshp = heat_pumps.first
      assert_equal 2, mshp.numberofSpeedsforCooling,
                   "#{vintage} should have 2 cooling speeds"
      assert_equal 1, mshp.numberofSpeedsforHeating,
                   "#{vintage} should have 1 heating speed"

      # Test System 3 Multi-Speed
      model3 = create_simple_model(standard, num_zones: 1)
      zone = model3.getThermalZones.first

      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(
        model: model3,
        zones: [zone],
        heating_coil_type: 'Gas',
        baseboard_type: 'Electric',
        hw_loop: nil,
        new_auto_zoner: false
      )

      # Verify multi-speed heat pump created
      heat_pumps3 = model3.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds
      assert heat_pumps3.size > 0,
             "#{vintage} should support System 3 Multi-Speed"

      mshp3 = heat_pumps3.first
      assert_equal 2, mshp3.numberofSpeedsforCooling,
                   "#{vintage} System 3 should have 2 cooling speeds"
    end

    puts "  ✓ All NECB vintages support multi-speed systems"
  end

end
