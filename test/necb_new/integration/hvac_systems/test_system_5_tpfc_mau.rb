require_relative '../../test_helper'

# NECB System 5: TPFC (Two-Pipe Fan Coil) + MAU
#
# Components:
# - Make-up Air Unit (MAU/DOAS) for ventilation
# - Two-pipe fan coil units in each zone (changeover system)
# - Chilled water plant with chillers
# - Hot water plant with boilers
# - Condenser water loop with cooling towers
#
# Applications:
# - Multi-story buildings with seasonal heating/cooling
# - Buildings where zones don't need simultaneous heating/cooling
# - More economical than four-pipe systems
#
# Key difference from System 2 (FPFC):
# - Two-pipe fan coils operate in seasonal mode (heating OR cooling)
# - Four-pipe can do both simultaneously
#
# Variants:
# - DX vs Hydronic MAU cooling
# - Various chiller types
#
# Key methods under test:
# - add_sys2_FPFC_sys5_TPFC (with fan_coil_type: 'TPFC')
class TestNECBSystem5 < Minitest::Test
  include NecbHelper

  ##############################################################################
  # BASIC SYSTEM CREATION TESTS
  ##############################################################################

  def test_system_5_tpfc_creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should create at least one air loop (MAU)"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should create fan coils for System 5"

    plant_loops = model.getPlantLoops
    assert plant_loops.size >= 2, "Should create multiple plant loops"
  end

  def test_system_5_heating_cooling_schedules
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    fan_coils = model.getZoneHVACFourPipeFanCoils

    fan_coils.each do |fan_coil|
      avail_sch = fan_coil.availabilitySchedule
      assert avail_sch, "Fan coil should have availability schedule"
    end
  end

  ##############################################################################
  # MAU COOLING TYPE TESTS
  ##############################################################################

  def test_system_5_with_hydronic_mau_cooling
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    mau_loop = air_loops.first

    chw_coils = []
    mau_loop.supplyComponents.each do |component|
      if component.to_CoilCoolingWater.is_initialized
        chw_coils << component.to_CoilCoolingWater.get
      end
    end

    assert chw_coils.size > 0, "MAU with hydronic cooling should have chilled water coil"
  end

  def test_system_5_with_dx_mau_cooling
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have MAU air loop"
  end

  ##############################################################################
  # PLANT LOOP TESTS
  ##############################################################################

  def test_system_5_chilled_water_plant
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    chw_loops = model.getPlantLoops.select { |loop|
      loop.name.to_s.downcase.include?('chw') ||
      loop.name.to_s.downcase.include?('chilled')
    }
    assert chw_loops.size > 0, "Should create chilled water loop"
  end

  def test_system_5_condenser_water_loop
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    cw_loops = model.getPlantLoops.select { |loop|
      loop.name.to_s.downcase.include?('cw') ||
      loop.name.to_s.downcase.include?('condenser')
    }
    assert cw_loops.size > 0, "Should create condenser water loop"
  end

  ##############################################################################
  # METHOD API TESTS
  ##############################################################################

  def test_system_5_method_exists
    standard = Standard.build('NECB2011')
    assert standard.respond_to?(:add_sys2_FPFC_sys5_TPFC),
           "NECB2011 should have add_sys2_FPFC_sys5_TPFC method"
  end

  ##############################################################################
  # NECB VINTAGE TESTS
  ##############################################################################

  def test_system_5_across_vintages
    ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'].each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Toronto')
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys2_FPFC_sys5_TPFC(
        model: model,
        zones: model.getThermalZones,
        chiller_type: 'Scroll',
        fan_coil_type: 'TPFC',
        mau_cooling_type: 'Hydronic',
        hw_loop: hw_loop
      )

      air_loops = model.getAirLoopHVACs
      assert air_loops.size > 0, "#{vintage}: Should create air loop"

      fan_coils = model.getZoneHVACFourPipeFanCoils
      assert fan_coils.size > 0, "#{vintage}: Should create fan coils"
    end
  end

  ##############################################################################
  # INTEGRATION TESTS (Require sizing run)
  ##############################################################################

  def test_system_5_fan_coil_units
    skip "NECB System 5 requires sizing run - implement as full integration test"
  end

  def test_system_5_mau_provides_ventilation
    skip "NECB System 5 requires sizing run - implement as full integration test"
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  def create_baseline_necb_model(template:, climate:, heating_fuel: 'NaturalGas')
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
      primary_heating_fuel: heating_fuel
    )

    [model, standard]
  end

  def create_hot_water_loop(model, standard, boiler_fuel: 'NaturalGas')
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
    boiler.setFuelType(boiler_fuel)
    hw_loop.addSupplyBranchForComponent(boiler)

    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 82.0)
    setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch)
    setpoint_mgr.addToNode(hw_loop.supplyOutletNode)

    hw_loop
  end

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

  ##############################################################################
  # SIZING TESTS (EnergyPlus sizing runs)
  ##############################################################################

  public

  def test_system_5_can_be_created_and_sized
    skip "System 5 (Two-Pipe Fan Coil) requires complex plant loop setup"

    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    standard.fuel_type_set = SystemFuels.new
    standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: 'Electricity')

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'Electricity', 'Electricity', always_on)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TwoPipe',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_5_sizing')

    assert model.sqlFile.is_initialized, "System 5 sizing should succeed"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "System 5 should have fan coils"
  end
end
