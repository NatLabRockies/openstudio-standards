require_relative '../test_helper'

# Test suite for NECB System 1: PTAC + Electric Baseboard
#
# System 1 is typically used for:
# - Small buildings, hotels, apartments
# - Residential/accommodation spaces (MURB, hotel/motel guest rooms)
# - Data processing areas (control room, data center) when cooling capacity <= 20kW
#
# Components:
# - PTAC (Packaged Terminal Air Conditioner) for cooling and ventilation
# - Electric baseboard for heating
# - PTAC contains: DX cooling coil, electric heating coil (always off), on/off fan
#
# Key methods under test:
# - add_ptac_dx_cooling() - Creates PTAC units
# - add_zone_baseboards() - Creates electric baseboards
# - add_onespeed_DX_coil() - Creates DX cooling coil with NECB performance curves
class TestNECBSystem1 < Minitest::Test

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

  # Test 1: Verify PTAC units are created for each zone
  def test_system_1_ptac_creation
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 2)

    # Add PTAC to each zone
    model.getThermalZones.each do |zone|
      standard.add_ptac_dx_cooling(model, zone, false)
    end

    # Verify PTAC units created
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal 2, ptacs.size, "Should have 2 PTAC units for 2 zones"

    # Verify each PTAC is assigned to a zone
    ptacs.each do |ptac|
      assert ptac.thermalZone.is_initialized, "PTAC should be assigned to a thermal zone"
    end
  end

  # Test 2: Verify PTAC has single-speed DX cooling coil
  def test_system_1_single_speed_dx_coil
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    refute_nil ptac, "PTAC should exist"

    # Verify cooling coil is single-speed DX
    cooling_coil = ptac.coolingCoil
    assert cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized,
           "PTAC should have single-speed DX cooling coil"

    dx_coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get

    # Verify DX coil has NECB performance curves
    cap_ft = dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve
    refute_nil cap_ft, "DX coil should have capacity function of temperature curve"

    cap_fflow = dx_coil.totalCoolingCapacityFunctionOfFlowFractionCurve
    refute_nil cap_fflow, "DX coil should have capacity function of flow curve"

    eir_ft = dx_coil.energyInputRatioFunctionOfTemperatureCurve
    refute_nil eir_ft, "DX coil should have EIR function of temperature curve"

    eir_fflow = dx_coil.energyInputRatioFunctionOfFlowFractionCurve
    refute_nil eir_fflow, "DX coil should have EIR function of flow curve"

    plf = dx_coil.partLoadFractionCorrelationCurve
    refute_nil plf, "DX coil should have part load fraction curve"
  end

  # Test 3: Verify PTAC has electric heating coil that is always off
  def test_system_1_ptac_electric_heating_coil_always_off
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    heating_coil = ptac.heatingCoil

    # Verify heating coil is electric
    assert heating_coil.to_CoilHeatingElectric.is_initialized,
           "PTAC should have electric heating coil"

    # Verify heating coil schedule is always off (actual heating by baseboard)
    htg_coil = heating_coil.to_CoilHeatingElectric.get
    schedule = htg_coil.availabilitySchedule

    # Check if schedule is always off by examining schedule values
    # An "always off" schedule should have all values = 0
    if schedule.to_ScheduleConstant.is_initialized
      const_sched = schedule.to_ScheduleConstant.get
      assert_equal 0.0, const_sched.value, "PTAC heating coil should be always off"
    elsif schedule.to_ScheduleCompact.is_initialized
      compact_sched = schedule.to_ScheduleCompact.get
      # Check name contains "off" or similar
      assert_match(/off/i, compact_sched.name.to_s,
                   "PTAC heating coil schedule should be 'always off'")
    end
  end

  # Test 4: Verify PTAC has on/off supply fan
  def test_system_1_ptac_fan_configuration
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    fan = ptac.supplyAirFan

    # Verify fan is on/off type
    assert fan.to_FanOnOff.is_initialized, "PTAC should have FanOnOff"

    fan_on_off = fan.to_FanOnOff.get

    # Verify fan pressure rise is set (NECB uses 640 Pa)
    assert_in_delta 640.0, fan_on_off.pressureRise, 10.0,
                    "PTAC fan pressure rise should be 640 Pa per NECB"
  end

  # Test 5: Verify electric baseboards are created
  def test_system_1_electric_baseboard_creation
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 2)

    # Add electric baseboards to each zone
    model.getThermalZones.each do |zone|
      standard.add_zone_baseboards(
        baseboard_type: 'Electric',
        hw_loop: nil,
        model: model,
        zone: zone
      )
    end

    # Verify electric baseboards created
    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert_equal 2, baseboards.size, "Should have 2 electric baseboards for 2 zones"

    # Verify each baseboard is assigned to a zone
    baseboards.each do |baseboard|
      assert baseboard.thermalZone.is_initialized,
             "Electric baseboard should be assigned to a thermal zone"
    end
  end

  # Test 6: Verify PTAC outdoor air configuration with zero outdoor air
  def test_system_1_ptac_zero_outdoor_air
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    # Add PTAC with zero outdoor air option
    standard.add_ptac_dx_cooling(model, zone, true)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first

    # Verify outdoor air flow rates are set to minimal values
    # When zero_outdoor_air is true, flow rates should be set to 1.0e-5
    if ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
      oa_flow = ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
      assert_in_delta 1.0e-5, oa_flow, 1.0e-6,
                      "OA flow when no conditioning should be minimal"
    end

    if ptac.outdoorAirFlowRateDuringCoolingOperation.is_initialized
      oa_cooling = ptac.outdoorAirFlowRateDuringCoolingOperation.get
      assert_in_delta 1.0e-5, oa_cooling, 1.0e-6,
                      "OA flow during cooling should be minimal"
    end

    if ptac.outdoorAirFlowRateDuringHeatingOperation.is_initialized
      oa_heating = ptac.outdoorAirFlowRateDuringHeatingOperation.get
      assert_in_delta 1.0e-5, oa_heating, 1.0e-6,
                      "OA flow during heating should be minimal"
    end
  end

  # Test 7: Verify PTAC outdoor air configuration with normal outdoor air
  def test_system_1_ptac_normal_outdoor_air
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    # Add PTAC with normal outdoor air (zero_outdoor_air = false)
    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first

    # When zero_outdoor_air is false, outdoor air flow rates should NOT be set to minimal
    # They should be autosized or set to reasonable values
    # Check that if values are set, they're not the minimal 1.0e-5
    if ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
      oa_flow = ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
      refute_in_delta 1.0e-5, oa_flow, 1.0e-6,
                      "OA flow should not be minimal when zero_outdoor_air is false"
    end
  end

  # Test 8: Verify PTAC naming convention
  def test_system_1_ptac_naming
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first
    zone_name = zone.name.to_s

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first

    # Verify PTAC name includes zone name
    assert_match(/#{zone_name}.*PTAC/i, ptac.name.to_s,
                 "PTAC name should include zone name and 'PTAC'")
  end

  # Test 9: Verify multiple zones get independent PTAC + baseboard systems
  def test_system_1_multiple_zones_independent_systems
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 3)

    # Add System 1 to each zone
    model.getThermalZones.each do |zone|
      standard.add_ptac_dx_cooling(model, zone, false)
      standard.add_zone_baseboards(
        baseboard_type: 'Electric',
        hw_loop: nil,
        model: model,
        zone: zone
      )
    end

    # Verify correct number of equipment pieces
    assert_equal 3, model.getZoneHVACPackagedTerminalAirConditioners.size,
                 "Should have 3 PTACs for 3 zones"
    assert_equal 3, model.getZoneHVACBaseboardConvectiveElectrics.size,
                 "Should have 3 electric baseboards for 3 zones"

    # Verify each zone has exactly 1 PTAC and 1 baseboard
    model.getThermalZones.each do |zone|
      zone_equipment = zone.equipment

      ptac_count = zone_equipment.count { |equip|
        equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
      }
      baseboard_count = zone_equipment.count { |equip|
        equip.to_ZoneHVACBaseboardConvectiveElectric.is_initialized
      }

      assert_equal 1, ptac_count, "Each zone should have exactly 1 PTAC"
      assert_equal 1, baseboard_count, "Each zone should have exactly 1 electric baseboard"
    end
  end

  # Test 10: Verify DX coil curve coefficients (NECB-specific values)
  def test_system_1_dx_coil_necb_curve_coefficients
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    dx_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get

    # Verify capacity function of temperature curve (NECB-specific coefficients)
    cap_ft_curve = dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve
    if cap_ft_curve.to_CurveBiquadratic.is_initialized
      curve = cap_ft_curve.to_CurveBiquadratic.get

      # NECB 2011 curve coefficients per add_onespeed_DX_coil method
      assert_in_delta 0.867905, curve.coefficient1Constant, 0.001,
                      "Constant coefficient should match NECB values"
      assert_in_delta 0.0142459, curve.coefficient2x, 0.0001,
                      "x coefficient should match NECB values"
      assert_in_delta 0.000554364, curve.coefficient3xPOW2, 0.0000001,
                      "x^2 coefficient should match NECB values"
    end

    # Verify part load fraction curve (NECB-specific)
    plf_curve = dx_coil.partLoadFractionCorrelationCurve
    if plf_curve.to_CurveCubic.is_initialized
      curve = plf_curve.to_CurveCubic.get

      # NECB curve is modified to account for PLF usage in EnergyPlus
      assert_in_delta 0.0277, curve.coefficient1Constant, 0.001,
                      "PLF constant should match NECB values"
      assert_in_delta 0.7, curve.minimumValueofx, 0.01,
                      "PLF minimum x should be 0.7 per NECB"
      assert_in_delta 1.0, curve.maximumValueofx, 0.01,
                      "PLF maximum x should be 1.0 per NECB"
    end
  end

  # Test 11: Verify PTAC fan operating mode schedule
  def test_system_1_ptac_fan_operating_mode
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first

    # Verify supply air fan operating mode schedule exists
    fan_mode_schedule = ptac.supplyAirFanOperatingModeSchedule
    refute_nil fan_mode_schedule, "PTAC should have supply air fan operating mode schedule"

    # Schedule should be "always off" meaning cycling fan operation
    # Check schedule name or type
    if fan_mode_schedule.to_ScheduleConstant.is_initialized
      const_sched = fan_mode_schedule.to_ScheduleConstant.get
      assert_equal 0.0, const_sched.value,
                   "Fan operating mode schedule should be 0 (cycling)"
    elsif fan_mode_schedule.to_ScheduleCompact.is_initialized
      compact_sched = fan_mode_schedule.to_ScheduleCompact.get
      assert_match(/off/i, compact_sched.name.to_s,
                   "Fan operating mode schedule should indicate cycling operation")
    end
  end

  # Test 12: Test with NECB2015 vintage
  def test_system_1_necb2015_vintage
    standard = Standard.build('NECB2015')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    # Add System 1 components
    standard.add_ptac_dx_cooling(model, zone, false)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify components created
    assert_equal 1, model.getZoneHVACPackagedTerminalAirConditioners.size,
                 "NECB2015 should create PTAC"
    assert_equal 1, model.getZoneHVACBaseboardConvectiveElectrics.size,
                 "NECB2015 should create electric baseboard"
  end

  # Test 13: Test with NECB2017 vintage
  def test_system_1_necb2017_vintage
    standard = Standard.build('NECB2017')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    # Add System 1 components
    standard.add_ptac_dx_cooling(model, zone, false)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify components created
    assert_equal 1, model.getZoneHVACPackagedTerminalAirConditioners.size,
                 "NECB2017 should create PTAC"
    assert_equal 1, model.getZoneHVACBaseboardConvectiveElectrics.size,
                 "NECB2017 should create electric baseboard"
  end

  # Test 14: Test with NECB2020 vintage
  def test_system_1_necb2020_vintage
    standard = Standard.build('NECB2020')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    # Add System 1 components
    standard.add_ptac_dx_cooling(model, zone, false)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify components created
    assert_equal 1, model.getZoneHVACPackagedTerminalAirConditioners.size,
                 "NECB2020 should create PTAC"
    assert_equal 1, model.getZoneHVACBaseboardConvectiveElectrics.size,
                 "NECB2020 should create electric baseboard"
  end

  # Test 15: Verify hot water baseboard as alternative to electric
  def test_system_1_hot_water_baseboard_variant
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    # Create a simple hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName("Hot Water Loop")

    # Add hot water baseboard to zone
    standard.add_zone_baseboards(
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      model: model,
      zone: zone
    )

    # Verify hot water baseboard created (not electric)
    hw_baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert_equal 1, hw_baseboards.size,
                 "Should create hot water baseboard when type is 'Hot Water'"

    # Verify it's connected to the hot water loop
    hw_baseboard = hw_baseboards.first
    coil = hw_baseboard.heatingCoil
    assert coil.plantLoop.is_initialized,
           "Hot water baseboard coil should be connected to plant loop"
    assert_equal hw_loop, coil.plantLoop.get,
                 "Hot water baseboard should be connected to provided hw_loop"

    # Verify NO electric baseboard was created
    elec_baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert_equal 0, elec_baseboards.size,
                 "Should not create electric baseboard when type is 'Hot Water'"
  end

  # Test 16: Verify PTAC availability schedule
  def test_system_1_ptac_availability_schedule
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first

    # Verify PTAC has an availability schedule
    avail_schedule = ptac.availabilitySchedule
    refute_nil avail_schedule, "PTAC should have availability schedule"

    # Should be "always on" schedule for PTAC operation
    if avail_schedule.to_ScheduleConstant.is_initialized
      const_sched = avail_schedule.to_ScheduleConstant.get
      assert_equal 1.0, const_sched.value, "PTAC should be always available"
    elsif avail_schedule.to_ScheduleCompact.is_initialized
      compact_sched = avail_schedule.to_ScheduleCompact.get
      assert_match(/on/i, compact_sched.name.to_s,
                   "PTAC availability should be 'always on'")
    end
  end

  # Test 17: Verify DX coil EIR (Energy Input Ratio) curve limits
  def test_system_1_dx_coil_eir_curve_limits
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    dx_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get

    # Verify EIR function of temperature curve limits (NECB-specific)
    eir_ft_curve = dx_coil.energyInputRatioFunctionOfTemperatureCurve
    if eir_ft_curve.to_CurveBiquadratic.is_initialized
      curve = eir_ft_curve.to_CurveBiquadratic.get

      # NECB specifies specific temperature ranges
      assert_in_delta 13.0, curve.minimumValueofx, 0.1,
                      "EIR curve min x (indoor temp) should be 13°C"
      assert_in_delta 24.0, curve.maximumValueofx, 0.1,
                      "EIR curve max x (indoor temp) should be 24°C"
      assert_in_delta 24.0, curve.minimumValueofy, 0.1,
                      "EIR curve min y (outdoor temp) should be 24°C"
      assert_in_delta 46.0, curve.maximumValueofy, 0.1,
                      "EIR curve max y (outdoor temp) should be 46°C"
    end
  end

  # Test 18: Verify capacity function of flow curve is unity (constant)
  def test_system_1_dx_coil_capacity_flow_curve_unity
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    dx_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get

    # Verify capacity function of flow is unity curve (no flow correction)
    cap_fflow_curve = dx_coil.totalCoolingCapacityFunctionOfFlowFractionCurve
    if cap_fflow_curve.to_CurveQuadratic.is_initialized
      curve = cap_fflow_curve.to_CurveQuadratic.get

      # NECB uses unity curve: f(x) = 1.0
      assert_in_delta 1.0, curve.coefficient1Constant, 0.001,
                      "Capacity flow curve should be unity (constant = 1.0)"
      assert_in_delta 0.0, curve.coefficient2x, 0.001,
                      "Capacity flow curve x coefficient should be 0"
      assert_in_delta 0.0, curve.coefficient3xPOW2, 0.001,
                      "Capacity flow curve x^2 coefficient should be 0"
    end
  end

end
