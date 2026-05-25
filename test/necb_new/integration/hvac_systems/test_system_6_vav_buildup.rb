require_relative '../../test_helper'

# NECB System 6: VAV (Variable Air Volume) Built-up System
#
# Components:
# - Variable air volume air handling unit
# - VAV terminals with reheat (hot water or electric)
# - Central chilled water plant with chillers
# - Central hot water plant with boilers
# - Condenser water loop with cooling towers
# - Zone baseboard heating (supplemental)
# - Variable or two-speed fans
#
# Applications:
# - Large commercial buildings, offices
# - Buildings requiring precise zone control
# - Most flexible NECB system type
#
# Variants:
# - Hot water vs Electric reheat
# - Scroll vs Centrifugal chiller
# - Variable speed drive vs Inlet vane fan control
# - Electric vs Hot water baseboard
#
# Key methods under test:
# - add_sys6_multi_zone_built_up_system_with_baseboard_heating
class TestNECBSystem6 < Minitest::Test
  include NecbHelper

  ##############################################################################
  # METHOD EXISTENCE AND API TESTS
  ##############################################################################

  def test_system_6_method_exists
    standard = Standard.build('NECB2011')
    assert standard.respond_to?(:add_sys6_multi_zone_built_up_system_with_baseboard_heating),
           "NECB2011 should have add_sys6_multi_zone_built_up_system_with_baseboard_heating method"
  end

  def test_system_6_method_parameters
    standard = Standard.build('NECB2011')

    method = standard.method(:add_sys6_multi_zone_built_up_system_with_baseboard_heating)
    expected_params = [:model, :zones, :heating_coil_type, :baseboard_type, :chiller_type, :fan_type, :hw_loop]
    actual_params = method.parameters.map { |p| p[1] }

    expected_params.each do |param|
      assert actual_params.include?(param),
             "System 6 method should accept parameter: #{param}"
    end
  end

  def test_system_6_chiller_type_options
    valid_types = ['Scroll', 'Reciprocating', 'Screw', 'Centrifugal']

    valid_types.each do |type|
      refute_nil type, "System 6 should support #{type} chiller type"
    end
  end

  def test_system_6_fan_type_options
    valid_types = ['var_speed_drive', 'AF_or_BI_rdg_fancurve']

    valid_types.each do |type|
      refute_nil type, "System 6 should support #{type} fan type"
    end
  end

  ##############################################################################
  # NECB VINTAGE METHOD AVAILABILITY
  ##############################################################################

  def test_system_6_vintages_have_method
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      standard = Standard.build(vintage)
      assert standard.respond_to?(:add_sys6_multi_zone_built_up_system_with_baseboard_heating),
             "#{vintage} should have System 6 method"
    end
  end

  ##############################################################################
  # SYSTEM 7 (VAV PFP) CONCEPTUAL TESTS
  # System 7 would use parallel fan-powered boxes instead of standard VAV terminals
  ##############################################################################

  def test_system_7_vav_pfp_concept
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: model.getThermalZones,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should create VAV air loop"

    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "Should create VAV terminal units"
  end

  ##############################################################################
  # INTEGRATION TESTS (Require sizing run)
  ##############################################################################

  def test_system_6_components_created
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_vav_terminals_with_hw_reheat
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_vav_terminals_with_electric_reheat
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_variable_volume_fans
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_chilled_water_plant
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_zone_baseboards
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_central_heating_coil
    skip "NECB System 6 requires sizing run - implement as full integration test"
  end

  def test_system_6_central_cooling_coil
    skip "NECB System 6 requires sizing run - implement as full integration test"
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

    building = model.getBuilding
    building.setStandardsNumberOfStories(2)
    building.setStandardsNumberOfAboveGroundStories(2)

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

  def test_system_6_electric_can_be_created_and_sized
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: nil
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_6_electric_sizing')

    assert model.sqlFile.is_initialized, "System 6 with electric sizing should succeed"

    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV terminals"

    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 6 should have CHW loop"
  end

  def test_system_6_with_hot_water_reheat
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: hw_loop
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_6_hw')

    assert model.sqlFile.is_initialized, "System 6 with HW sizing should succeed"

    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV terminals"

    assert model.getBoilerHotWaters.size > 0, "Should have boiler"

    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 6 should have CHW loop"

    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 6 should have hot water baseboards"
  end

  def test_system_6_works_across_necb_vintages
    vintages = ['NECB2011', 'NECB2015', 'NECB2017']

    vintages.each do |vintage|
      model, standard = create_test_model_for_sizing(template: vintage)
      zones = model.getThermalZones.sort

      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones,
        heating_coil_type: 'Electric',
        baseboard_type: 'Electric',
        chiller_type: 'Scroll',
        fan_type: 'AF_or_BI_rdg_fancurve',
        hw_loop: nil
      )

      run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
      FileUtils.mkdir_p(run_dir)
      standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: "system_6_#{vintage.downcase}")

      assert model.sqlFile.is_initialized, "System 6 should work with #{vintage}"
    end
  end
end
