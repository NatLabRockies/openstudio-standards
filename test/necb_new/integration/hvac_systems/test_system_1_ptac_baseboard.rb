require_relative '../../test_helper'

# NECB System 1: PTAC + Baseboard Heating
#
# Components:
# - PTAC (Packaged Terminal Air Conditioner) with DX cooling
# - Electric heating coil (always off - baseboards provide heating)
# - Electric or hot water baseboard heating
# - Optional MAU (Make-up Air Unit) for ventilation
#
# Applications:
# - Small buildings, hotels, apartments
# - Residential/accommodation spaces (MURB, hotel/motel guest rooms)
# - Data processing areas when cooling capacity <= 20kW
#
# Variants:
# - Single-speed: Standard PTAC with single-speed DX coil
# - Multi-speed: PTHP with multi-speed DX coil and MAU
#
# Key methods under test:
# - add_sys1_unitary_ac_baseboard_heating
# - add_sys1_unitary_ac_baseboard_heating_multi_speed
# - add_ptac_dx_cooling
# - add_zone_baseboards
# - add_onespeed_DX_coil
class TestNECBSystem1 < Minitest::Test
  include NecbHelper

  ##############################################################################
  # SINGLE-SPEED SYSTEM 1 TESTS
  ##############################################################################

  def test_system_1_ptac_creation
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 2)

    model.getThermalZones.each do |zone|
      standard.add_ptac_dx_cooling(model, zone, false)
    end

    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal 2, ptacs.size, "Should have 2 PTAC units for 2 zones"

    ptacs.each do |ptac|
      assert ptac.thermalZone.is_initialized, "PTAC should be assigned to a thermal zone"
    end
  end

  def test_system_1_single_speed_dx_coil
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    refute_nil ptac, "PTAC should exist"

    cooling_coil = ptac.coolingCoil
    assert cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized,
           "PTAC should have single-speed DX cooling coil"

    dx_coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get

    refute_nil dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve
    refute_nil dx_coil.totalCoolingCapacityFunctionOfFlowFractionCurve
    refute_nil dx_coil.energyInputRatioFunctionOfTemperatureCurve
    refute_nil dx_coil.energyInputRatioFunctionOfFlowFractionCurve
    refute_nil dx_coil.partLoadFractionCorrelationCurve
  end

  def test_system_1_ptac_electric_heating_coil_always_off
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    heating_coil = ptac.heatingCoil

    assert heating_coil.to_CoilHeatingElectric.is_initialized,
           "PTAC should have electric heating coil"

    htg_coil = heating_coil.to_CoilHeatingElectric.get
    schedule = htg_coil.availabilitySchedule

    if schedule.to_ScheduleConstant.is_initialized
      const_sched = schedule.to_ScheduleConstant.get
      assert_equal 0.0, const_sched.value, "PTAC heating coil should be always off"
    end
  end

  def test_system_1_ptac_fan_configuration
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    fan = ptac.supplyAirFan

    assert fan.to_FanOnOff.is_initialized, "PTAC should have FanOnOff"

    fan_on_off = fan.to_FanOnOff.get
    assert_in_delta 640.0, fan_on_off.pressureRise, 10.0,
                    "PTAC fan pressure rise should be 640 Pa per NECB"
  end

  def test_system_1_electric_baseboard_creation
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 2)

    model.getThermalZones.each do |zone|
      standard.add_zone_baseboards(
        baseboard_type: 'Electric',
        hw_loop: nil,
        model: model,
        zone: zone
      )
    end

    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert_equal 2, baseboards.size, "Should have 2 electric baseboards for 2 zones"

    baseboards.each do |baseboard|
      assert baseboard.thermalZone.is_initialized,
             "Electric baseboard should be assigned to a thermal zone"
    end
  end

  def test_system_1_ptac_zero_outdoor_air
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, true)

    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first

    if ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.is_initialized
      oa_flow = ptac.outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded.get
      assert_in_delta 1.0e-5, oa_flow, 1.0e-6,
                      "OA flow when no conditioning should be minimal"
    end
  end

  def test_system_1_multiple_zones_independent_systems
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 3)

    model.getThermalZones.each do |zone|
      standard.add_ptac_dx_cooling(model, zone, false)
      standard.add_zone_baseboards(
        baseboard_type: 'Electric',
        hw_loop: nil,
        model: model,
        zone: zone
      )
    end

    assert_equal 3, model.getZoneHVACPackagedTerminalAirConditioners.size
    assert_equal 3, model.getZoneHVACBaseboardConvectiveElectrics.size

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

  def test_system_1_hot_water_baseboard_variant
    standard = Standard.build('NECB2011')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName("Hot Water Loop")

    standard.add_zone_baseboards(
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      model: model,
      zone: zone
    )

    hw_baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert_equal 1, hw_baseboards.size

    hw_baseboard = hw_baseboards.first
    coil = hw_baseboard.heatingCoil
    assert coil.plantLoop.is_initialized
    assert_equal hw_loop, coil.plantLoop.get
  end

  ##############################################################################
  # NECB VINTAGE TESTS
  ##############################################################################

  def test_system_1_necb2015_vintage
    standard = Standard.build('NECB2015')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    assert_equal 1, model.getZoneHVACPackagedTerminalAirConditioners.size
    assert_equal 1, model.getZoneHVACBaseboardConvectiveElectrics.size
  end

  def test_system_1_necb2017_vintage
    standard = Standard.build('NECB2017')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    assert_equal 1, model.getZoneHVACPackagedTerminalAirConditioners.size
    assert_equal 1, model.getZoneHVACBaseboardConvectiveElectrics.size
  end

  def test_system_1_necb2020_vintage
    standard = Standard.build('NECB2020')
    model = create_simple_model(standard, num_zones: 1)
    zone = model.getThermalZones.first

    standard.add_ptac_dx_cooling(model, zone, false)
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    assert_equal 1, model.getZoneHVACPackagedTerminalAirConditioners.size
    assert_equal 1, model.getZoneHVACBaseboardConvectiveElectrics.size
  end

  ##############################################################################
  # MULTI-SPEED SYSTEM 1 TESTS
  ##############################################################################

  def test_system_1_multispeed_mau_creation
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

    heat_pumps = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds
    assert_equal 1, heat_pumps.size, "Should have 1 multi-speed heat pump for MAU"

    mshp = heat_pumps.first

    assert mshp.controllingZoneorThermostatLocation.is_initialized
    assert_equal 1, mshp.numberofSpeedsforHeating
    assert_equal 2, mshp.numberofSpeedsforCooling
    assert_in_delta(-10.0, mshp.minimumOutdoorDryBulbTemperatureforCompressorOperation, 0.1)
  end

  def test_system_1_multispeed_cooling_coil_stages
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

    assert cooling_coil.to_CoilCoolingDXMultiSpeed.is_initialized
    dx_coil = cooling_coil.to_CoilCoolingDXMultiSpeed.get

    assert_equal 2, dx_coil.stages.size
    assert_equal 'Electricity', dx_coil.fuelType
    refute dx_coil.applyPartLoadFractiontoSpeedsGreaterthan1
  end

  def test_system_1_multispeed_hw_supplemental_heating
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

    assert supp_coil.to_CoilHeatingWater.is_initialized

    hw_coil = supp_coil.to_CoilHeatingWater.get
    assert hw_coil.plantLoop.is_initialized
    assert_equal hw_loop, hw_coil.plantLoop.get
  end

  def test_system_1_multispeed_ptac_zone_units
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

    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal 3, ptacs.size, "Should have PTAC for each zone"

    ptacs.each do |ptac|
      assert ptac.thermalZone.is_initialized
    end

    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert_equal 3, baseboards.size
  end

  ##############################################################################
  # SIZING TESTS (EnergyPlus sizing runs)
  ##############################################################################

  def test_system_1_can_be_created_and_sized
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_sizing')

    assert model.sqlFile.is_initialized, "System 1 sizing should succeed"

    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert ptacs.size > 0, "System 1 should have PTAC units"

    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert baseboards.size > 0, "System 1 should have electric baseboards"
  end

  def test_system_1_sizing_with_hot_water_baseboard
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_hw')

    assert model.sqlFile.is_initialized, "System 1 with HW sizing should succeed"
    assert model.getBoilerHotWaters.size > 0, "Should have boiler"

    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 1 should have hot water baseboards"
  end

  def test_system_1_sizing_vancouver_climate
    model, standard = create_test_model_for_sizing

    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    zones = model.getThermalZones.sort

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_vancouver')

    assert model.sqlFile.is_initialized, "System 1 should work in Vancouver climate"
  end

  def test_system_1_sizing_yellowknife_climate
    model, standard = create_test_model_for_sizing

    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_NT_Yellowknife.AP.719360_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    zones = model.getThermalZones.sort

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_yellowknife')

    assert model.sqlFile.is_initialized, "System 1 should work in Yellowknife climate"
  end

  def test_system_1_sizing_across_necb_vintages
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      model, standard = create_test_model_for_sizing(template: vintage)
      zones = model.getThermalZones.sort

      standard.add_sys1_unitary_ac_baseboard_heating(
        model: model,
        zones: zones,
        mau_type: true,
        mau_heating_coil_type: 'Electric',
        baseboard_type: 'Electric',
        hw_loop: nil
      )

      run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
      FileUtils.mkdir_p(run_dir)
      standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: "system_1_#{vintage.downcase}")

      assert model.sqlFile.is_initialized, "System 1 should work with #{vintage}"
    end
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  def create_test_model_for_sizing(template: 'NECB2011')
    standard = Standard.build(template)

    resource_path = File.join(File.dirname(__FILE__), '..', '..', '..', 'necb', 'unit_tests', 'resources', '5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    building = model.getBuilding
    building.setStandardsNumberOfStories(1)
    building.setStandardsNumberOfAboveGroundStories(1)

    [model, standard]
  end

  def create_simple_model(standard, num_zones: 1)
    model = OpenStudio::Model::Model.new
    length = 15.0
    width = 10.0

    num_zones.times do |i|
      space = OpenStudio::Model::Space.new(model)
      space.setName("Space_#{i + 1}")

      vertices = OpenStudio::Point3dVector.new
      vertices << OpenStudio::Point3d.new(0 + (i * length), 0, 0)
      vertices << OpenStudio::Point3d.new(length + (i * length), 0, 0)
      vertices << OpenStudio::Point3d.new(length + (i * length), width, 0)
      vertices << OpenStudio::Point3d.new(0 + (i * length), width, 0)

      floor = OpenStudio::Model::Surface.new(vertices, model)
      floor.setSpace(space)

      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone_#{i + 1}")
      space.setThermalZone(zone)

      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      thermostat.setName("#{zone.name} Thermostat")
      zone.setThermostatSetpointDualSetpoint(thermostat)
    end

    model
  end

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
end
