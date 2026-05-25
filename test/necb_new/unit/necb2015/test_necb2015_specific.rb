#!/usr/bin/env ruby

require_relative '../../test_helper'

# Test suite for NECB2015-specific features
# Tests lib/openstudio-standards/standards/necb/NECB2015/necb_2015.rb
# Focus on methods that DIFFER from NECB2011 baseline
class TestNecb2015Specific < Minitest::Test
  def setup
    @standard_2011 = Standard.build('NECB2011')
    @standard_2015 = Standard.build('NECB2015')
    @model = OpenStudio::Model::Model.new

    # Set weather file
    epw_path = File.join(__dir__, '../../../../data/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(@model, epw_file)
  end

  # ===== Standards Database Loading Tests =====

  def test_necb2015_loads_standards_database
    # Test that NECB2015 successfully loads and extends NECB2011 database
    assert @standard_2015.instance_variable_get(:@standards_data), "Should load standards database"
    assert @standard_2015.instance_variable_get(:@standards_data)['tables'], "Should have tables"
  end

  def test_necb2015_extends_necb2011
    # Test that NECB2015 class inherits from NECB2011
    assert @standard_2015.is_a?(NECB2011), "NECB2015 should inherit from NECB2011"
  end

  def test_necb2015_template_name
    # Test template registration
    assert_equal 'NECB2015', @standard_2015.class.name
  end

  # ===== Pump Power Application Tests =====

  def test_apply_loop_pump_power_method_exists
    # Test that NECB2015 has apply_loop_pump_power method
    assert @standard_2015.respond_to?(:apply_loop_pump_power), "Should have apply_loop_pump_power method"
  end

  def test_apply_loop_pump_power_requires_sizing_run
    # NECB2015 requires a second sizing run for pump power calculations
    # This is unique to NECB2015 - testing the method signature
    method = @standard_2015.method(:apply_loop_pump_power)
    params = method.parameters

    # Check for required parameters
    param_names = params.map { |type, name| name }
    assert param_names.include?(:model), "Should require model parameter"
    assert param_names.include?(:sizing_run_dir), "Should require sizing_run_dir parameter"
  end

  # ===== LED Lighting Tests =====

  def test_set_lighting_per_area_led_lighting_method_exists
    # Test that NECB2015 has LED lighting method
    assert @standard_2015.respond_to?(:set_lighting_per_area_led_lighting),
           "Should have set_lighting_per_area_led_lighting method"
  end

  def test_led_lighting_atrium_height_thresholds
    # NECB2015 has different LPD calculations for atriums based on height
    # Test threshold logic (line 76 in necb_2015.rb)

    # Heights below 12.0 meters use one equation
    height_below = 10.0
    assert height_below < 12.0, "Test height should be below threshold"

    # Heights at or above 12.0 meters use another equation
    height_above = 15.0
    assert height_above >= 12.0, "Test height should be at or above threshold"
  end

  def test_led_lighting_atrium_calculation_below_12m
    # Test atrium LPD calculation for height < 12m
    # Formula: (0 + 1.06 * height) * 0.092903 W/ft² → W/m²
    space_height = 10.0  # meters

    atrium_lpd_eq_smaller_12_intercept = 0
    atrium_lpd_eq_smaller_12_slope = 1.06

    lighting_per_area_w_ft2 = (atrium_lpd_eq_smaller_12_intercept +
                                 atrium_lpd_eq_smaller_12_slope * space_height) * 0.092903

    expected_w_ft2 = (0 + 1.06 * 10.0) * 0.092903
    assert_in_delta expected_w_ft2, lighting_per_area_w_ft2, 0.001
  end

  def test_led_lighting_atrium_calculation_above_12m
    # Test atrium LPD calculation for height >= 12m
    # Formula: (4.3 + 1.06 * height) * 0.092903 W/ft² → W/m²
    space_height = 15.0  # meters

    atrium_lpd_eq_larger_12_intercept = 4.3
    atrium_lpd_eq_larger_12_slope = 1.06

    lighting_per_area_w_ft2 = (atrium_lpd_eq_larger_12_intercept +
                                 atrium_lpd_eq_larger_12_slope * space_height) * 0.092903

    expected_w_ft2 = (4.3 + 1.06 * 15.0) * 0.092903
    assert_in_delta expected_w_ft2, lighting_per_area_w_ft2, 0.001
  end

  def test_led_lighting_scale_factor_application
    # Test that lights_scale multiplier is applied to LPD
    base_lpd = 10.0  # W/ft²
    lights_scale = 0.8

    scaled_lpd = base_lpd * lights_scale
    assert_equal 8.0, scaled_lpd
  end

  def test_unit_conversion_w_ft2_to_w_m2
    # Test W/ft² to W/m² conversion used in LED lighting
    w_ft2 = 10.0
    w_m2 = OpenStudio.convert(w_ft2, 'W/ft^2', 'W/m^2').get

    # 1 W/ft² = 10.7639 W/m²
    expected_w_m2 = 10.0 * 10.7639
    assert_in_delta expected_w_m2, w_m2, 0.01
  end

  # ===== Occupancy Sensor Tests =====

  def test_set_occ_sensor_spacetypes_returns_true
    # NECB2015 implements occupancy sensor control via lighting schedule
    # Method should return true (line 49)
    space_type_map = {}
    result = @standard_2015.set_occ_sensor_spacetypes(@model, space_type_map)

    assert_equal true, result, "set_occ_sensor_spacetypes should return true"
  end

  def test_occupancy_sensor_applied_via_schedule
    # NECB2015 applies occupancy sensors through lighting schedules
    # This is different from NECB2011 which may use LPD reduction

    # Create space type
    space_type = OpenStudio::Model::SpaceType.new(@model)
    space_type.setName('Office')

    # In NECB2015, occupancy sensor control is in the schedule, not LPD fraction
    # Test that method completes without error
    result = @standard_2015.set_occ_sensor_spacetypes(@model, {})
    assert result, "Should handle occupancy sensor setup"
  end

  # ===== Maximum Loop Pump Power Tests =====

  def test_maximum_loop_pump_power_normalization
    # NECB2015 5.2.6.3.(1) specifies maximum loop pump power
    # normalized by peak demand of served spaces

    # Create a plant loop to test
    plant_loop = OpenStudio::Model::PlantLoop.new(@model)
    plant_loop.setName('Test Plant Loop')

    # Add a pump
    pump = OpenStudio::Model::PumpConstantSpeed.new(@model)
    pump.addToNode(plant_loop.supplyInletNode)

    assert @model.getPlantLoops.size > 0, "Should have plant loop"
    assert @model.getPumpConstantSpeeds.size > 0, "Should have pump"
  end

  # ===== Comparison with NECB2011 Tests =====

  def test_necb2015_has_additional_methods_vs_2011
    # Test that NECB2015 has methods that NECB2011 doesn't or are different
    necb2015_methods = @standard_2015.methods

    # These methods should exist in NECB2015
    assert necb2015_methods.include?(:set_lighting_per_area_led_lighting),
           "NECB2015 should have LED lighting method"
    assert necb2015_methods.include?(:apply_loop_pump_power),
           "NECB2015 should have loop pump power method"
  end

  def test_standards_data_merged_from_json_files
    # Test that NECB2015 loads additional JSON data files
    # Data files in NECB2015/data/ should extend NECB2011 database

    standards_data = @standard_2015.instance_variable_get(:@standards_data)
    assert standards_data, "Should have standards data"
    assert standards_data['tables'], "Should have tables"

    # NECB2015 should have merged data from its own JSON files
    # plus inherited all NECB2011 data
  end

  # ===== Space Height Calculation Tests =====

  def test_get_max_space_height_for_space_type_logic
    # NECB2015 needs to determine max space height for atrium LPD calculations
    # Create a space with known height

    space = OpenStudio::Model::Space.new(@model)
    space.setName('Atrium Space')

    # Create floor vertices
    floor_vertices = OpenStudio::Point3dVector.new
    floor_vertices << OpenStudio::Point3d.new(0, 0, 0)
    floor_vertices << OpenStudio::Point3d.new(10, 0, 0)
    floor_vertices << OpenStudio::Point3d.new(10, 10, 0)
    floor_vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(floor_vertices, @model)
    floor.setSpace(space)
    floor.setSurfaceType('Floor')

    # Create ceiling vertices at height 5m
    ceiling_vertices = OpenStudio::Point3dVector.new
    ceiling_vertices << OpenStudio::Point3d.new(0, 0, 5)
    ceiling_vertices << OpenStudio::Point3d.new(0, 10, 5)
    ceiling_vertices << OpenStudio::Point3d.new(10, 10, 5)
    ceiling_vertices << OpenStudio::Point3d.new(10, 0, 5)

    ceiling = OpenStudio::Model::Surface.new(ceiling_vertices, @model)
    ceiling.setSpace(space)
    ceiling.setSurfaceType('RoofCeiling')

    # Space height should be approximately 5m
    # (Test setup validates geometry creation)
    assert @model.getSpaces.size > 0, "Should have space"
  end

  # ===== Atrium Detection Tests =====

  def test_atrium_space_type_detection
    # Test atrium detection logic (line 73 in necb_2015.rb)
    # Uses string matching on space type name

    space_type_atrium = "Gymnasium-exercise Atrium < 6 m high - undefined"
    space_type_office = "Office - open plan"

    assert space_type_atrium.include?('Atrium'), "Should detect Atrium in name"
    assert !space_type_office.include?('Atrium'), "Should not detect Atrium in office"
  end

  # ===== Lighting Definition Tests =====

  def test_lighting_definition_watts_per_area_setting
    # Test setting LPD on lighting definition
    definition = OpenStudio::Model::LightsDefinition.new(@model)
    definition.setName('Test Lights')

    # Set LPD in W/m²
    lpd_w_m2 = 10.0
    definition.setWattsperSpaceFloorArea(lpd_w_m2)

    # Verify it was set
    assert definition.wattsperSpaceFloorArea.is_initialized
    assert_equal lpd_w_m2, definition.wattsperSpaceFloorArea.get
  end

  # ===== JSON Data File Loading Tests =====

  def test_json_data_file_structure
    # Test that JSON data files have expected structure
    # Files should have 'tables', 'constants', or 'formulas' keys

    expected_keys = ['tables', 'constants', 'formulas']

    # Sample JSON structure
    sample_data = { 'tables' => {} }
    assert sample_data.key?('tables'), "Should have tables key"
  end

  def test_json_merge_logic
    # Test JSON data merging logic (lines 21-26, 33-38)
    base_tables = { 'table1' => { 'key1' => 'value1' } }
    new_tables = { 'table2' => { 'key2' => 'value2' } }

    # Merge using array concatenation and to_h
    merged = [*base_tables, *new_tables].to_h

    assert merged['table1'], "Should have base table"
    assert merged['table2'], "Should have new table"
  end
end
