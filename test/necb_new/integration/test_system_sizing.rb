require_relative '../test_helper'

# Integration Tests for NECB Systems with Sizing
# These tests create and size HVAC systems to verify end-to-end functionality
#
# Note: These tests run EnergyPlus sizing and are slower (~3-5 min per test).
# They are critical for verifying that systems can be created and sized correctly.

class TestSystemSizingIntegration < Minitest::Test

  # Helper to create a simple test model with proper setup for sizing
  # Uses NECB resource model approach (same as existing NECB tests)
  def create_test_model_for_sizing(template: 'NECB2011')
    standard = Standard.build(template)

    # Load the standard NECB test resource model (same approach as existing NECB tests)
    resource_path = File.join(File.dirname(__FILE__), '../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    # Set weather file
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply NECB space types to the model (required for NECB validation)
    # Update all space types to use NECB standards
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    # Set building properties required for NECB validation
    building = model.getBuilding
    building.setStandardsNumberOfStories(1)
    building.setStandardsNumberOfAboveGroundStories(1)

    return model, standard
  end

  # ============================================================================
  # System 1: PTAC + Electric Baseboard
  # ============================================================================

  def test_system_1_can_be_created_and_sized
    # Test that System 1 can be created and sized successfully
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Add System 1 with electric heating (no hw_loop needed)
    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    # Run sizing using NECB's try_sizing_run method (handles Sizing:Zone creation)
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    # Use try_sizing_run which is the NECB standard way to run sizing
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_sizing')

    # Check that sizing succeeded by verifying SQL file exists
    assert model.sqlFile.is_initialized, "System 1 sizing should succeed and create SQL file"

    # Verify components exist
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert ptacs.size > 0, "System 1 should have PTAC units"

    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert baseboards.size > 0, "System 1 should have electric baseboards"
  end

  def test_system_1_with_hot_water_baseboard
    # Test that System 1 with hot water baseboards can be created and sized
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Create hot water loop (required for hot water baseboards)
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

    # Add System 1 with hot water baseboards
    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Run sizing using NECB's method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_hw')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 1 with HW sizing should succeed"

    # Verify components exist
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert ptacs.size > 0, "System 1 should have PTAC units"

    # Verify hot water system components
    assert model.getPlantLoops.size > 0, "Should have hot water loop"
    assert model.getBoilerHotWaters.size > 0, "Should have boiler"

    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 1 should have hot water baseboards"
  end

  # ============================================================================
  # System 3: Packaged Single-Zone Rooftop
  # ============================================================================

  def test_system_3_can_be_created_and_sized
    # Test that System 3 can be created and sized successfully
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Add System 3 with gas heating (no hw_loop needed)
    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    # Run sizing using NECB's standard method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_3_sizing')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 3 sizing should succeed"

    # Verify components
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 3 should have air loops"

    # Verify DX cooling
    has_dx = model.getAirLoopHVACs.any? do |loop|
      loop.supplyComponents.any? { |comp| comp.to_CoilCoolingDXSingleSpeed.is_initialized }
    end
    assert has_dx, "System 3 should have DX cooling"
  end

  # ============================================================================
  # System 4: MAU + Baseboards
  # ============================================================================

  def test_system_4_gas_can_be_created_and_sized
    # Test that System 4 with gas heating can be created and sized
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Add System 4 with gas heating (no hw_loop needed)
    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    # Run sizing using NECB's standard method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_4_gas_sizing')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 4 with gas sizing should succeed"

    # Verify MAU exists
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 4 should have MAU air loops"

    # Verify baseboards
    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert baseboards.size > 0, "System 4 should have electric baseboards"
  end

  def test_system_4_electric_can_be_created_and_sized
    # Test that System 4 with electric can be created and sized
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Add System 4 with electric
    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    # Run sizing using NECB's standard method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_4_electric_sizing')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 4 with electric sizing should succeed"

    # Verify electric baseboards
    electric_bb = model.getZoneHVACBaseboardConvectiveElectrics
    assert electric_bb.size > 0, "System 4 should have electric baseboards"
  end

  def test_system_4_with_hot_water_baseboard
    # Test that System 4 with hot water baseboards can be created and sized
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

    # Add System 4 with hot water heating and baseboards
    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Run sizing using NECB's method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_4_hw')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 4 with HW sizing should succeed"

    # Verify MAU exists
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 4 should have MAU air loops"

    # Verify hot water system components
    assert model.getPlantLoops.size > 0, "Should have hot water loop"
    assert model.getBoilerHotWaters.size > 0, "Should have boiler"

    # Verify hot water baseboards
    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 4 should have hot water baseboards"
  end

  # ============================================================================
  # System 5: Two-Pipe Fan Coil
  # ============================================================================

  def test_system_5_can_be_created_and_sized
    skip "System 5 (Two-Pipe Fan Coil) requires complex plant loop setup - see test_necb_loop_rules.rb for working examples"

    # Test that System 5 can be created and sized
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Set up fuel types (required for System 2/5)
    standard.fuel_type_set = SystemFuels.new()
    standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: 'Electricity')

    # System 2/5 requires a hot water loop - create it
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'Electricity', 'Electricity', always_on)

    # Add System 5 with DX cooling
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TwoPipe',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    # Run sizing using NECB's standard method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_5_sizing')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 5 sizing should succeed"

    # Verify fan coils
    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "System 5 should have fan coils"

    # Verify plant loops (System 5 creates its own)
    plant_loops = model.getPlantLoops
    assert plant_loops.size > 0, "System 5 should create plant loops"
  end

  # ============================================================================
  # System 6: VAV with Reheat
  # ============================================================================

  def test_system_6_electric_can_be_created_and_sized
    # Test that System 6 with electric can be created and sized
    # Use larger model for VAV (multi-zone)
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Add System 6 with electric heating (no hw_loop needed)
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: nil
    )

    # Run sizing using NECB's standard method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_6_electric_sizing')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 6 with electric sizing should succeed"

    # Verify VAV terminals
    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV terminals"

    # Verify chilled water loop
    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 6 should have CHW loop"
  end

  def test_system_6_with_hot_water_reheat
    # Test that System 6 with hot water reheat can be created and sized
    # This is a very common VAV configuration in NECB buildings
    model, standard = create_test_model_for_sizing

    zones = model.getThermalZones.sort

    # Create hot water loop for reheat coils
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    always_on = model.alwaysOnDiscreteSchedule
    standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

    # Add System 6 with hot water reheat
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: hw_loop
    )

    # Run sizing using NECB's method
    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_6_hw')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 6 with HW sizing should succeed"

    # Verify VAV terminals with hot water reheat
    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV terminals"

    # Verify hot water system components
    hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
    assert hw_loops.size > 0, "Should have hot water loop"
    assert model.getBoilerHotWaters.size > 0, "Should have boiler"

    # Verify chilled water loop
    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 6 should have CHW loop"

    # Verify hot water baseboards
    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 6 should have hot water baseboards"
  end

  # ============================================================================
  # Multi-Climate Tests
  # ============================================================================

  def test_system_1_works_in_vancouver
    # Test that System 1 works in different climate
    model, standard = create_test_model_for_sizing

    # Set Vancouver weather
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

    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_vancouver')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 1 should work in Vancouver climate"
  end

  def test_system_1_works_in_yellowknife
    # Test that System 1 works in extreme cold climate
    model, standard = create_test_model_for_sizing

    # Set Yellowknife weather
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

    run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
    FileUtils.mkdir_p(run_dir)

    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system_1_yellowknife')

    # Verify sizing succeeded
    assert model.sqlFile.is_initialized, "System 1 should work in Yellowknife (extreme cold) climate"
  end

  # ============================================================================
  # Vintage Comparison Tests
  # ============================================================================

  def test_system_1_works_across_necb_vintages
    # Test that System 1 works with different NECB vintages
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

      run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
      FileUtils.mkdir_p(run_dir)

      standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: "system_1_#{vintage.downcase}")

      # Verify sizing succeeded
      assert model.sqlFile.is_initialized, "System 1 should work with #{vintage}"
    end
  end

  def test_system_6_works_across_necb_vintages
    # Test that System 6 works with different NECB vintages
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

      run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
      FileUtils.mkdir_p(run_dir)

      standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: "system_6_#{vintage.downcase}")

      # Verify sizing succeeded
      assert model.sqlFile.is_initialized, "System 6 should work with #{vintage}"
    end
  end
end
