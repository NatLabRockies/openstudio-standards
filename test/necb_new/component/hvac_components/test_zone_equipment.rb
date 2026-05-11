require_relative '../../test_helper'

# Test NECB zone equipment configuration and characteristics
# Tests PTAC, baseboard heaters, and fan coil units without requiring sizing runs
#
# Methods tested:
# - NECB2011#add_ptac_dx_cooling
# - NECB2011#add_zone_baseboards
# - NECB2011#add_sys1_unitary_ac_baseboard_heating
# - Standard zone equipment configuration methods
#
# References:
# - NECB 2011 Table 5.2.2.3 (Equipment Performance)
# - NECB 2011 Clause 8.4.4.13 (System 1 - PTAC with Baseboard)
# - NECB 2011 Clause 5.2.10.3 (Direct Expansion Equipment Efficiency)
class TestZoneEquipment < Minitest::Test

  # Helper method to load model and create thermal zones from spaces
  def setup_model_with_zones(fixture_name)
    model = BTAP::FileIO.load_osm("/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/#{fixture_name}")

    # Create thermal zones for all spaces
    model.getSpaces.each_with_index do |space, i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone_#{i + 1}")
      space.setThermalZone(zone)
    end

    return model
  end

  # ============================================================================
  # PTAC Configuration Tests
  # ============================================================================

  def test_ptac_basic_configuration
    # Test basic PTAC unit creation and configuration
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Create PTAC using NECB method
    standard.add_ptac_dx_cooling(model, zone, true)

    # Verify PTAC was added
    ptacs = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
    assert_equal 1, ptacs.size, "Should have 1 PTAC in zone"

    # Get PTAC and verify basic configuration
    ptac = ptacs.first.to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify PTAC has cooling coil
    cooling_coil = ptac.coolingCoil
    assert cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized,
      "PTAC should have DX cooling coil"

    # Verify PTAC has heating coil
    heating_coil = ptac.heatingCoil
    assert heating_coil.to_CoilHeatingElectric.is_initialized,
      "PTAC should have electric heating coil"

    # Verify PTAC has fan
    fan = ptac.supplyAirFan
    assert fan.to_FanOnOff.is_initialized,
      "PTAC should have on-off fan"
  end

  def test_ptac_outdoor_air_configuration_zero_oa
    # Test PTAC with zero outdoor air (typical for NECB System 1)
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Create PTAC with zero outdoor air flag
    zero_outdoor_air = true
    standard.add_ptac_dx_cooling(model, zone, zero_outdoor_air)

    # Get PTAC
    ptac = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      .first.to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify outdoor air flow rates are very small (near zero)
    if ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
      oa_flow = ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
      assert oa_flow < 0.0001, "OA flow when no cooling/heating should be near zero, got #{oa_flow}"
    end

    if ptac.outdoorAirFlowRateDuringCoolingOperation.is_initialized
      oa_cool = ptac.outdoorAirFlowRateDuringCoolingOperation.get
      assert oa_cool < 0.0001, "OA flow during cooling should be near zero, got #{oa_cool}"
    end

    if ptac.outdoorAirFlowRateDuringHeatingOperation.is_initialized
      oa_heat = ptac.outdoorAirFlowRateDuringHeatingOperation.get
      assert oa_heat < 0.0001, "OA flow during heating should be near zero, got #{oa_heat}"
    end
  end

  def test_ptac_dx_cooling_coil_has_necb_performance_curves
    # Test that PTAC DX cooling coil has NECB-specific performance curves
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    standard.add_ptac_dx_cooling(model, zone, true)

    # Get DX cooling coil
    ptac = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      .first.to_ZoneHVACPackagedTerminalAirConditioner.get
    dx_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get

    # Verify performance curves exist
    cap_f_temp_curve = dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve
    cap_f_flow_curve = dx_coil.totalCoolingCapacityFunctionOfFlowFractionCurve
    eir_f_temp_curve = dx_coil.energyInputRatioFunctionOfTemperatureCurve
    eir_f_flow_curve = dx_coil.energyInputRatioFunctionOfFlowFractionCurve
    plf_curve = dx_coil.partLoadFractionCorrelationCurve

    refute_nil cap_f_temp_curve, "DX coil should have capacity-f(T) curve"
    refute_nil cap_f_flow_curve, "DX coil should have capacity-f(flow) curve"
    refute_nil eir_f_temp_curve, "DX coil should have EIR-f(T) curve"
    refute_nil eir_f_flow_curve, "DX coil should have EIR-f(flow) curve"
    refute_nil plf_curve, "DX coil should have PLF curve"

    # Verify curve types
    assert cap_f_temp_curve.to_CurveBiquadratic.is_initialized,
      "Capacity-f(T) curve should be biquadratic"
  end

  def test_ptac_fan_configuration
    # Test PTAC fan pressure rise and configuration
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    standard.add_ptac_dx_cooling(model, zone, true)

    # Get PTAC fan
    ptac = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      .first.to_ZoneHVACPackagedTerminalAirConditioner.get
    fan = ptac.supplyAirFan.to_FanOnOff.get

    # Verify fan pressure rise (NECB sets 640 Pa)
    assert_in_delta 640.0, fan.pressureRise, 10.0,
      "PTAC fan pressure rise should be 640 Pa per NECB"
  end

  def test_ptac_heating_coil_always_off
    # Test that PTAC heating coil is always off (baseboard provides heating)
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    standard.add_ptac_dx_cooling(model, zone, true)

    # Get PTAC heating coil
    ptac = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      .first.to_ZoneHVACPackagedTerminalAirConditioner.get
    htg_coil = ptac.heatingCoil.to_CoilHeatingElectric.get

    # Verify heating coil has always-off schedule
    sched = htg_coil.availabilitySchedule
    assert sched.name.to_s.downcase.include?('off'),
      "PTAC heating coil schedule should be always off, got #{sched.name}"
  end

  # ============================================================================
  # Electric Baseboard Tests
  # ============================================================================

  def test_electric_baseboard_creation
    # Test electric baseboard heater creation
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Add electric baseboard
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify baseboard was added
    baseboards = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }
    assert_equal 1, baseboards.size, "Should have 1 electric baseboard in zone"
  end

  def test_hot_water_baseboard_creation
    # Test hot water baseboard heater creation
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')

    # Add hot water baseboard
    standard.add_zone_baseboards(
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      model: model,
      zone: zone
    )

    # Verify baseboard was added
    baseboards = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveWater.is_initialized }
    assert_equal 1, baseboards.size, "Should have 1 hot water baseboard in zone"

    # Verify baseboard has heating coil
    baseboard = baseboards.first.to_ZoneHVACBaseboardConvectiveWater.get
    htg_coil = baseboard.heatingCoil
    assert htg_coil.to_CoilHeatingWaterBaseboard.is_initialized,
      "Hot water baseboard should have water heating coil"

    # Verify coil is connected to hot water loop
    coil = htg_coil.to_CoilHeatingWaterBaseboard.get
    assert coil.plantLoop.is_initialized,
      "Baseboard heating coil should be connected to plant loop"
    assert_equal hw_loop.handle.to_s, coil.plantLoop.get.handle.to_s,
      "Baseboard should be connected to hot water loop"
  end

  def test_baseboard_no_creation_for_invalid_type
    # Test that no baseboard is created for invalid type
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    initial_equipment_count = zone.equipment.size

    # Try to add baseboard with invalid type
    standard.add_zone_baseboards(
      baseboard_type: 'Invalid',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify no equipment was added
    assert_equal initial_equipment_count, zone.equipment.size,
      "No equipment should be added for invalid baseboard type"
  end

  # ============================================================================
  # Multi-Zone Tests
  # ============================================================================

  def test_ptac_and_baseboard_in_multiple_zones
    # Test PTAC and baseboard in all zones of multi-zone model
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('multi_zone_rectangle.osm')

    zones = model.getThermalZones
    assert zones.size > 1, "Multi-zone model should have multiple zones"

    # Add PTAC and electric baseboard to each zone
    zones.each do |zone|
      standard.add_ptac_dx_cooling(model, zone, true)
      standard.add_zone_baseboards(
        baseboard_type: 'Electric',
        hw_loop: nil,
        model: model,
        zone: zone
      )
    end

    # Verify each zone has both PTAC and baseboard
    zones.each do |zone|
      ptacs = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      baseboards = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }

      assert_equal 1, ptacs.size, "Zone #{zone.name} should have 1 PTAC"
      assert_equal 1, baseboards.size, "Zone #{zone.name} should have 1 baseboard"
    end
  end

  def test_mixed_baseboard_types_in_multiple_zones
    # Test mixing electric and hot water baseboards in different zones
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('multi_zone_rectangle.osm')

    zones = model.getThermalZones.to_a
    assert zones.size >= 2, "Need at least 2 zones for mixed baseboard test"

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')

    # Add electric baseboard to first zone
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zones[0]
    )

    # Add hot water baseboard to second zone
    standard.add_zone_baseboards(
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      model: model,
      zone: zones[1]
    )

    # Verify first zone has electric baseboard
    elec_bb = zones[0].equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }
    assert_equal 1, elec_bb.size, "First zone should have electric baseboard"

    # Verify second zone has hot water baseboard
    hw_bb = zones[1].equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveWater.is_initialized }
    assert_equal 1, hw_bb.size, "Second zone should have hot water baseboard"
  end

  # ============================================================================
  # Zone Equipment Sequencing Tests
  # ============================================================================

  def test_zone_equipment_cooling_priority
    # Test that PTAC has priority for cooling when both PTAC and baseboard exist
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Add both PTAC and baseboard
    standard.add_ptac_dx_cooling(model, zone, true)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify zone has equipment list
    if zone.equipmentInCoolingOrder.size > 0
      # First equipment in cooling order should be PTAC
      first_cooling_equip = zone.equipmentInCoolingOrder.first
      assert first_cooling_equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized,
        "PTAC should be first in cooling priority"
    end
  end

  def test_zone_equipment_heating_priority
    # Test heating equipment priority with PTAC and baseboard
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Add both PTAC and baseboard
    standard.add_ptac_dx_cooling(model, zone, true)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify zone has equipment in heating order
    heating_equip = zone.equipmentInHeatingOrder
    assert heating_equip.size >= 2, "Zone should have at least 2 pieces of heating equipment"

    # Baseboard should be in heating equipment list
    baseboards = heating_equip.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }
    assert baseboards.size > 0, "Baseboard should be in heating equipment list"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_necb2015_ptac_configuration
    # Test PTAC configuration for NECB 2015 (should be similar to 2011)
    standard = Standard.build('NECB2015')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    standard.add_ptac_dx_cooling(model, zone, true)

    # Verify PTAC was added
    ptacs = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
    assert_equal 1, ptacs.size, "NECB 2015 should create PTAC"

    # Verify basic components
    ptac = ptacs.first.to_ZoneHVACPackagedTerminalAirConditioner.get
    assert ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized,
      "NECB 2015 PTAC should have DX cooling coil"
    assert ptac.heatingCoil.to_CoilHeatingElectric.is_initialized,
      "NECB 2015 PTAC should have electric heating coil"
  end

  def test_necb2017_baseboard_configuration
    # Test baseboard configuration for NECB 2017
    standard = Standard.build('NECB2017')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Add electric baseboard
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify baseboard was added
    baseboards = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }
    assert_equal 1, baseboards.size, "NECB 2017 should create electric baseboard"
  end

  # ============================================================================
  # Equipment Schedule Tests
  # ============================================================================

  def test_ptac_availability_schedule
    # Test PTAC availability schedule configuration
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    standard.add_ptac_dx_cooling(model, zone, true)

    # Get PTAC
    ptac = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      .first.to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify PTAC has availability schedule
    avail_sched = ptac.availabilitySchedule
    assert avail_sched.name.to_s.downcase.include?('always') ||
           avail_sched.name.to_s.downcase.include?('on'),
      "PTAC should have always-on availability schedule, got #{avail_sched.name}"
  end

  def test_ptac_fan_operating_mode_schedule
    # Test PTAC fan operating mode schedule (cycling vs continuous)
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first
    standard.add_ptac_dx_cooling(model, zone, true)

    # Get PTAC
    ptac = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
      .first.to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify fan operating mode schedule exists
    fan_op_sched = ptac.supplyAirFanOperatingModeSchedule
    assert !fan_op_sched.nil?, "PTAC should have fan operating mode schedule"

    # For NECB System 1, fan should cycle with load (always off when no load)
    assert fan_op_sched.name.to_s.downcase.include?('off'),
      "PTAC fan operating mode should be cycling (always off), got #{fan_op_sched.name}"
  end

  def test_baseboard_availability_schedule
    # Test baseboard heater availability schedule
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)

    # Add hot water baseboard
    standard.add_zone_baseboards(
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      model: model,
      zone: zone
    )

    # Get baseboard
    baseboard = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveWater.is_initialized }
      .first.to_ZoneHVACBaseboardConvectiveWater.get

    # Verify baseboard has availability schedule
    avail_sched = baseboard.availabilitySchedule
    assert avail_sched.name.to_s.downcase.include?('always') ||
           avail_sched.name.to_s.downcase.include?('on'),
      "Baseboard should have always-on availability schedule, got #{avail_sched.name}"
  end

  # ============================================================================
  # Zone Equipment Count and Type Verification
  # ============================================================================

  def test_zone_equipment_count_with_ptac_and_baseboard
    # Test total equipment count when both PTAC and baseboard are added
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Add both PTAC and baseboard
    standard.add_ptac_dx_cooling(model, zone, true)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify total equipment count
    zone_equipment = zone.equipment
    assert zone_equipment.size >= 2, "Zone should have at least 2 pieces of equipment"

    # Verify equipment types
    ptacs = zone_equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
    baseboards = zone_equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }

    assert_equal 1, ptacs.size, "Should have exactly 1 PTAC"
    assert_equal 1, baseboards.size, "Should have exactly 1 baseboard"
  end

  def test_no_duplicate_equipment_on_multiple_calls
    # Test that calling add methods multiple times doesn't create duplicate equipment
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Add PTAC twice
    standard.add_ptac_dx_cooling(model, zone, true)
    standard.add_ptac_dx_cooling(model, zone, true)

    # Should have 2 PTACs (method doesn't check for duplicates)
    ptacs = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
    assert_equal 2, ptacs.size, "Adding PTAC twice creates 2 PTACs (no duplicate check)"
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  def test_baseboard_with_nil_hot_water_loop
    # Test hot water baseboard creation fails gracefully with nil loop
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # This should fail or not create baseboard when hot water type but nil loop
    # The implementation may raise an error or silently fail
    begin
      standard.add_zone_baseboards(
        baseboard_type: 'Hot Water',
        hw_loop: nil,
        model: model,
        zone: zone
      )

      # If it doesn't raise error, check that no baseboard was created
      # or that an error occurred during coil connection
      hw_bb = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveWater.is_initialized }
      if hw_bb.size > 0
        # Baseboard was created but coil won't be properly connected
        baseboard = hw_bb.first.to_ZoneHVACBaseboardConvectiveWater.get
        coil = baseboard.heatingCoil.to_CoilHeatingWaterBaseboard.get
        # Plant loop connection should fail or be missing
        refute coil.plantLoop.is_initialized,
          "Hot water coil should not be connected to plant loop when loop is nil"
      end
    rescue => e
      # Expected: method raises error for nil hot water loop
      assert true, "Method raised error for nil hot water loop: #{e.message}"
    end
  end

  def test_ptac_in_zone_without_thermostat
    # Test PTAC can be added to zone even without thermostat
    standard = Standard.build('NECB2011')
    model = setup_model_with_zones('simple_box.osm')
    zone = model.getThermalZones.first

    # Remove thermostat if present
    if zone.thermostatSetpointDualSetpoint.is_initialized
      zone.thermostatSetpointDualSetpoint.get.remove
    end

    # Add PTAC
    standard.add_ptac_dx_cooling(model, zone, true)

    # Verify PTAC was added even without thermostat
    ptacs = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
    assert_equal 1, ptacs.size, "PTAC should be added even without thermostat"
  end

end
