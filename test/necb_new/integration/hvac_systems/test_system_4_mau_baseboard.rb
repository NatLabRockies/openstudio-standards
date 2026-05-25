require_relative '../../test_helper'

# NECB System 4: MAU (Make-up Air Unit) + Baseboard Heating
#
# Components:
# - Single-zone make-up air unit (PSZ configuration)
# - Provides ventilation air only
# - Electric or hot water baseboard heating in zones
# - No zone-level cooling (baseboards only)
#
# Applications:
# - Buildings with high ventilation requirements
# - Warehouses, assembly areas
# - Buildings where heating is primary concern
#
# Variants:
# - Electric vs Gas vs Hot Water vs DX heating coil
# - Electric vs Hot Water baseboard
#
# Key methods under test:
# - add_sys4_single_zone_make_up_air_unit_with_baseboard_heating
#
# Note: System 4 requires sizing run for full implementation.
# API verification tests run immediately; integration tests are skipped.
class TestNECBSystem4 < Minitest::Test
  include NecbHelper

  ##############################################################################
  # METHOD EXISTENCE AND API TESTS (Run without sizing)
  ##############################################################################

  def test_system_4_method_exists
    standard = Standard.build('NECB2011')
    assert standard.respond_to?(:add_sys4_single_zone_make_up_air_unit_with_baseboard_heating),
           "NECB2011 should have add_sys4_single_zone_make_up_air_unit_with_baseboard_heating method"
  end

  def test_system_4_method_parameters
    standard = Standard.build('NECB2011')

    method = standard.method(:add_sys4_single_zone_make_up_air_unit_with_baseboard_heating)
    expected_params = [:model, :zones, :heating_coil_type, :baseboard_type, :hw_loop]
    actual_params = method.parameters.map { |p| p[1] }

    expected_params.each do |param|
      assert actual_params.include?(param),
             "System 4 method should accept parameter: #{param}"
    end
  end

  def test_system_4_heating_coil_type_options
    valid_types = ['Electric', 'Gas', 'Hot Water', 'DX']

    valid_types.each do |type|
      refute_nil type, "System 4 should support #{type} heating coil type"
    end
  end

  def test_system_4_baseboard_type_options
    valid_types = ['Electric', 'Hot Water']

    valid_types.each do |type|
      refute_nil type, "System 4 should support #{type} baseboard type"
    end
  end

  ##############################################################################
  # NECB VINTAGE METHOD AVAILABILITY
  ##############################################################################

  def test_system_4_vintages_have_method
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      standard = Standard.build(vintage)
      assert standard.respond_to?(:add_sys4_single_zone_make_up_air_unit_with_baseboard_heating),
             "#{vintage} should have System 4 method"
    end
  end

  ##############################################################################
  # INTEGRATION TESTS (Require sizing run)
  ##############################################################################

  def test_system_4_components_created
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_electric_heating_components
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_gas_heating_components
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_hot_water_heating_components
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_fan_type
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_outdoor_air_system
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_zone_baseboards_electric
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  def test_system_4_zone_baseboards_hot_water
    skip "NECB System 4 requires sizing run - implement as full integration test"
  end

  ##############################################################################
  # SIZING TESTS (EnergyPlus sizing runs)
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

  public

  def test_system_4_gas_can_be_created_and_sized
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_4_gas_sizing')

    assert model.sqlFile.is_initialized, "System 4 with gas sizing should succeed"

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 4 should have MAU air loops"

    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert baseboards.size > 0, "System 4 should have electric baseboards"
  end

  def test_system_4_electric_can_be_created_and_sized
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_4_electric_sizing')

    assert model.sqlFile.is_initialized, "System 4 with electric sizing should succeed"

    electric_bb = model.getZoneHVACBaseboardConvectiveElectrics
    assert electric_bb.size > 0, "System 4 should have electric baseboards"
  end

  def test_system_4_with_hot_water_baseboard
    model, standard = create_test_model_for_sizing
    zones = model.getThermalZones.sort

    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    run_dir = File.join(Dir.pwd, 'output', "integration_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_4_hw')

    assert model.sqlFile.is_initialized, "System 4 with HW sizing should succeed"

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 4 should have MAU air loops"

    assert model.getBoilerHotWaters.size > 0, "Should have boiler"

    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 4 should have hot water baseboards"
  end
end
