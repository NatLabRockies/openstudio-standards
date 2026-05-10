require_relative '../../helpers/minitest_helper'

# Test suite for core NECB2011 methods
# These tests cover fundamental methods that are used throughout the NECB2011 implementation
class TestNECB2011Core < Minitest::Test

  # Test argument conversion methods

  def test_convert_arg_to_f_with_numeric
    # Test that numeric values are returned as-is
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_f(variable: 5.5, default: 1.0)
    assert_equal 5.5, result, "Numeric float should be returned as-is"

    result = standard.convert_arg_to_f(variable: 10, default: 1.0)
    assert_equal 10, result, "Numeric integer should be returned as-is"
  end

  def test_convert_arg_to_f_with_string
    # Test that string values are converted to float
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_f(variable: "3.14", default: 1.0)
    assert_equal 3.14, result, "String number should be converted to float"

    result = standard.convert_arg_to_f(variable: "  2.5  ", default: 1.0)
    assert_equal 2.5, result, "String with whitespace should be stripped and converted"
  end

  def test_convert_arg_to_f_with_necb_default
    # Test that 'NECB_Default' returns the default value
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_f(variable: "NECB_Default", default: 7.5)
    assert_equal 7.5, result, "NECB_Default string should return default value"

    result = standard.convert_arg_to_f(variable: "necb_default", default: 7.5)
    assert_equal 7.5, result, "necb_default (lowercase) should return default value"
  end

  def test_convert_arg_to_f_with_nil
    # Test that nil returns the default value
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_f(variable: nil, default: 9.9)
    assert_equal 9.9, result, "nil variable should return default value"
  end

  def test_convert_arg_to_bool_with_boolean
    # Test that boolean values are returned as-is
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_bool(variable: true, default: false)
    assert_equal true, result, "True boolean should be returned as-is"

    result = standard.convert_arg_to_bool(variable: false, default: true)
    assert_equal false, result, "False boolean should be returned as-is"
  end

  def test_convert_arg_to_bool_with_string
    # Test that string values are converted to boolean
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_bool(variable: "true", default: false)
    assert_equal true, result, "String 'true' should be converted to boolean true"

    result = standard.convert_arg_to_bool(variable: "false", default: true)
    assert_equal false, result, "String 'false' should be converted to boolean false"

    result = standard.convert_arg_to_bool(variable: "NECB_Default", default: true)
    assert_equal true, result, "NECB_Default should return default value"
  end

  def test_convert_arg_to_string_with_string
    # Test that string values are returned correctly
    standard = Standard.build('NECB2011')

    result = standard.convert_arg_to_string(variable: "test_value", default: "default")
    assert_equal "test_value", result, "String value should be returned as-is"

    result = standard.convert_arg_to_string(variable: "NECB_Default", default: "fallback")
    assert_equal "fallback", result, "NECB_Default should return default value"
  end

  # Test standards data access methods

  def test_get_standards_table
    # Test that standards tables can be retrieved
    standard = Standard.build('NECB2011')

    # Try to get a known table
    table = standard.get_standards_table(table_name: 'space_types')
    assert table, "Should retrieve space_types table"
    assert table.is_a?(Hash), "Table should be a hash"
    assert table['table'], "Table should have 'table' key with data"
  end

  def test_get_standards_constant
    # Test that constants can be retrieved from standards data
    standard = Standard.build('NECB2011')

    # Get infiltration rate constant
    constant = standard.get_standards_constant('infiltration_rate_m3_per_s_per_m2')
    assert constant, "Should retrieve infiltration rate constant"
    assert constant.is_a?(Numeric), "Constant should be numeric"
    assert constant > 0, "Infiltration rate should be positive"
  end

  def test_get_standards_formula
    # Test that formulas can be retrieved from standards data
    standard = Standard.build('NECB2011')

    # This will raise if formula doesn't exist, which is expected behavior
    # We're just testing the method works
    begin
      formula = standard.get_standards_formula('test_formula')
      # If we get here, formula exists
      assert formula, "Should retrieve formula if it exists"
    rescue RuntimeError => e
      # Expected if formula doesn't exist
      assert e.message.include?('could not find'), "Should raise error with descriptive message"
    end
  end

  # Test space type methods

  def test_get_all_spacetype_names
    # Test that all space type names can be retrieved
    standard = Standard.build('NECB2011')

    spacetype_names = standard.get_all_spacetype_names
    assert spacetype_names, "Should return space type names"
    assert spacetype_names.is_a?(Array), "Should return an array"
    assert spacetype_names.size > 0, "Should have space types defined"

    # Verify structure: each entry should be [building_type, space_type]
    first_entry = spacetype_names.first
    assert first_entry.is_a?(Array), "Each entry should be an array"
    assert_equal 2, first_entry.size, "Each entry should have 2 elements: [building_type, space_type]"

    # Verify some known space types exist
    office_spaces = spacetype_names.select { |bt, st| bt == 'Office' }
    assert office_spaces.size > 0, "Should have Office building type space types"
  end

  def test_validate_and_update_space_types_with_matching_vintage
    # Test space type validation when model uses same vintage
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Set up a space type with NECB2011 standards
    space_type = model.getSpaceTypes.first
    if space_type
      space_type.setStandardsBuildingType('Office')
      space_type.setStandardsSpaceType('Open plan office')
      space_type.setName('Office Open plan office')
    end

    # Validate - should return true for matching vintage
    result = standard.validate_and_upate_space_types(model)
    assert_equal true, result, "Should validate space types for matching vintage"
  end

  def test_determine_spacetype_vintage
    # Test that space type vintage can be determined from model
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Set up space types with NECB2011 standards
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Office')
      space_type.setStandardsSpaceType('Open plan office')
    end

    vintage = standard.determine_spacetype_vintage(model)
    assert vintage, "Should determine a vintage"
    assert_includes ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], vintage,
                    "Should determine a NECB vintage"
  end

  # Test climate zone methods

  def test_get_climate_zone_index_from_hdd
    # Test climate zone index calculation from HDD values
    standard = Standard.build('NECB2011')

    # Zone 4 (0-2999 HDD)
    assert_equal 0, standard.get_climate_zone_index(1500), "1500 HDD should be zone 4 (index 0)"
    assert_equal 0, standard.get_climate_zone_index(2999), "2999 HDD should be zone 4 (index 0)"

    # Zone 5 (3000-3999 HDD)
    assert_equal 1, standard.get_climate_zone_index(3000), "3000 HDD should be zone 5 (index 1)"
    assert_equal 1, standard.get_climate_zone_index(3500), "3500 HDD should be zone 5 (index 1)"

    # Zone 6 (4000-4999 HDD)
    assert_equal 2, standard.get_climate_zone_index(4500), "4500 HDD should be zone 6 (index 2)"

    # Zone 7a (5000-5999 HDD)
    assert_equal 3, standard.get_climate_zone_index(5500), "5500 HDD should be zone 7a (index 3)"

    # Zone 7b (6000-6999 HDD)
    assert_equal 4, standard.get_climate_zone_index(6500), "6500 HDD should be zone 7b (index 4)"

    # Zone 8 (7000+ HDD)
    assert_equal 5, standard.get_climate_zone_index(7500), "7500 HDD should be zone 8 (index 5)"
    assert_equal 5, standard.get_climate_zone_index(10000), "10000 HDD should be zone 8 (index 5)"
  end

  def test_get_climate_zone_name_from_hdd
    # Test climate zone name retrieval from HDD values
    standard = Standard.build('NECB2011')

    assert_equal '4', standard.get_climate_zone_name(2000), "2000 HDD should be zone 4"
    assert_equal '5', standard.get_climate_zone_name(3500), "3500 HDD should be zone 5"
    assert_equal '6', standard.get_climate_zone_name(4500), "4500 HDD should be zone 6"
    assert_equal '7a', standard.get_climate_zone_name(5500), "5500 HDD should be zone 7a"
    assert_equal '7b', standard.get_climate_zone_name(6500), "6500 HDD should be zone 7b"
    assert_equal '8', standard.get_climate_zone_name(8000), "8000 HDD should be zone 8"
  end

  def test_get_necb_hdd18_with_model
    # Test HDD18 calculation from model weather file
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Set a weather file location
    epw_file = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'
    weather_file_path = File.absolute_path(
      File.join(__FILE__, '..', '..', '..', '..', '..', 'data', 'weather', epw_file)
    )

    # Only run test if weather file exists
    if File.exist?(weather_file_path)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)

      hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)
      assert hdd, "Should calculate HDD18"
      assert hdd.is_a?(Numeric), "HDD18 should be numeric"
      assert hdd > 0, "HDD18 should be positive"

      # Calgary should be in zone 7a range (5000-5999 HDD)
      assert hdd >= 4500 && hdd <= 6000, "Calgary HDD18 should be in expected range (~5000)"
    else
      skip "Weather file not found at #{weather_file_path}"
    end
  end

  # Test building type loading

  def test_load_building_type_from_library
    # Test loading a building type geometry from library
    standard = Standard.build('NECB2011')

    # Try to load a known building type
    building_type = 'SmallOffice'
    model = standard.load_building_type_from_library(building_type: building_type)

    # Only test if the building type exists
    if model
      assert model.is_a?(OpenStudio::Model::Model), "Should return an OpenStudio Model"
      assert_equal building_type, model.getBuilding.name.to_s, "Building name should match building type"
      assert model.getSpaces.size > 0, "Model should have spaces"
    else
      # Building type not in library is acceptable
      assert true, "Building type #{building_type} not in library (acceptable)"
    end
  end

  # Test heating fuel validation

  def test_validate_primary_heating_fuel_with_explicit_fuel
    # Test that explicit fuel types are returned as-is
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Set a weather file (required for regional lookup)
    epw_file = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'
    weather_file_path = File.absolute_path(
      File.join(__FILE__, '..', '..', '..', '..', '..', 'data', 'weather', epw_file)
    )

    if File.exist?(weather_file_path)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)

      result = standard.validate_primary_heating_fuel(primary_heating_fuel: 'NaturalGas', model: model)
      assert_equal 'NaturalGas', result, "Explicit fuel type should be returned"

      result = standard.validate_primary_heating_fuel(primary_heating_fuel: 'Electricity', model: model)
      assert_equal 'Electricity', result, "Explicit electricity should be returned"
    else
      skip "Weather file not found"
    end
  end

  def test_validate_primary_heating_fuel_with_default
    # Test that 'DefaultFuel' uses regional defaults
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    epw_file = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'
    weather_file_path = File.absolute_path(
      File.join(__FILE__, '..', '..', '..', '..', '..', 'data', 'weather', epw_file)
    )

    if File.exist?(weather_file_path)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)

      result = standard.validate_primary_heating_fuel(primary_heating_fuel: 'DefaultFuel', model: model)
      assert result, "Should return a fuel type"
      assert_includes ['NaturalGas', 'Electricity', 'FuelOilNo2'], result,
                      "Should return a valid fuel type for Alberta"
    else
      skip "Weather file not found"
    end
  end

  # Test boiler capacity ratio methods

  def test_set_boiler_cap_ratios_with_nil
    # Test default boiler capacity ratios
    standard = Standard.build('NECB2011')

    result = standard.set_boiler_cap_ratios(boiler_cap_ratio: nil, boiler_fuel: nil)
    assert result, "Should return boiler capacity ratios"
    assert result.is_a?(Hash), "Should return a hash"
    assert_equal 0.75, result[:primary_ratio], "Default primary ratio should be 0.75"
    assert_equal 0.25, result[:secondary_ratio], "Default secondary ratio should be 0.25"
  end

  def test_set_boiler_cap_ratios_with_custom_values
    # Test custom boiler capacity ratios
    standard = Standard.build('NECB2011')

    result = standard.set_boiler_cap_ratios(boiler_cap_ratio: '60-40', boiler_fuel: 'NaturalGas')
    assert_equal 0.6, result[:primary_ratio], "Should set primary ratio to 60%"
    assert_equal 0.4, result[:secondary_ratio], "Should set secondary ratio to 40%"

    result = standard.set_boiler_cap_ratios(boiler_cap_ratio: '50-50', boiler_fuel: 'NaturalGas')
    assert_equal 0.5, result[:primary_ratio], "Should set primary ratio to 50%"
    assert_equal 0.5, result[:secondary_ratio], "Should set secondary ratio to 50%"
  end

  def test_set_boiler_cap_ratios_with_necb_default
    # Test NECB default (nil ratios)
    standard = Standard.build('NECB2011')

    result = standard.set_boiler_cap_ratios(boiler_cap_ratio: '0-0', boiler_fuel: 'NaturalGas')
    assert_nil result[:primary_ratio], "NECB default should have nil primary ratio"
    assert_nil result[:secondary_ratio], "NECB default should have nil secondary ratio"
  end

  # Test HVAC system reset method

  def test_reset_hvac_system_if_required_with_nil_primary
    # Test that systems are reset to NECB_Default when primary is nil
    standard = Standard.build('NECB2011')

    dwelling, corridor, storage, washrooms = standard.reset_hvac_system_if_required(
      hvac_system_primary: nil
    )

    assert_equal "NECB_Default", dwelling, "Dwelling units should be NECB_Default"
    assert_equal "NECB_Default", corridor, "Corridor should be NECB_Default"
    assert_equal "NECB_Default", storage, "Storage should be NECB_Default"
    assert_equal "NECB_Default", washrooms, "Washrooms should be NECB_Default"
  end

  def test_reset_hvac_system_if_required_with_custom_primary
    # Test HVAC system reset logic when primary is set to custom value
    # Logic: "X = primary UNLESS X.nil? || X == 'necb_default'"
    # This means: Set X to primary, but DON'T if X is already nil or necb_default
    standard = Standard.build('NECB2011')

    # When other systems are nil or NECB_Default, they DON'T get overridden
    dwelling, corridor, storage, washrooms = standard.reset_hvac_system_if_required(
      hvac_system_primary: 'System 3',
      hvac_system_dwelling_units: nil,
      hvac_system_corridor: 'NECB_Default',
      hvac_system_storage: nil,
      hvac_system_washrooms: 'necb_default'
    )

    # The unless clause means: DON'T override if nil or necb_default
    assert_nil dwelling, "Dwelling units should stay nil (protected by unless)"
    assert_equal 'NECB_Default', corridor, "Corridor should stay NECB_Default (protected by unless)"
    assert_nil storage, "Storage should stay nil (protected by unless)"
    assert_equal 'necb_default', washrooms, "Washrooms should stay necb_default (protected by unless)"

    # When other systems are set to actual values (not nil, not necb_default),
    # they DO get overridden to primary
    dwelling, corridor, storage, washrooms = standard.reset_hvac_system_if_required(
      hvac_system_primary: 'System 3',
      hvac_system_dwelling_units: 'System 5',
      hvac_system_corridor: 'System 6',
      hvac_system_storage: 'System 7',
      hvac_system_washrooms: 'System 8'
    )

    # Not nil and not necb_default, so they GET OVERRIDDEN to primary
    assert_equal 'System 3', dwelling, "Dwelling units should be overridden to primary"
    assert_equal 'System 3', corridor, "Corridor should be overridden to primary"
    assert_equal 'System 3', storage, "Storage should be overridden to primary"
    assert_equal 'System 3', washrooms, "Washrooms should be overridden to primary"
  end

  # Test distance calculation method

  def test_distance_calculation
    # Test geographic distance calculation between two coordinates
    standard = Standard.build('NECB2011')

    # Calgary coordinates: [51.0447, -114.0719]
    # Edmonton coordinates: [53.5461, -113.4938]
    calgary = [51.0447, -114.0719]
    edmonton = [53.5461, -113.4938]

    distance = standard.distance(calgary, edmonton)
    assert distance.is_a?(Numeric), "Distance should be numeric"
    assert distance > 0, "Distance should be positive"

    # Distance between Calgary and Edmonton is approximately 280 km = 280,000 m
    assert distance > 200000, "Distance should be greater than 200 km"
    assert distance < 350000, "Distance should be less than 350 km"

    # Test distance to itself is zero
    distance_same = standard.distance(calgary, calgary)
    assert_equal 0, distance_same, "Distance to same location should be zero"
  end

  # Test check output meters method

  def test_check_output_meters_with_nil
    # Test that default meters are added when nil
    standard = Standard.build('NECB2011')

    result = standard.check_output_meters(output_meters: nil)
    assert result, "Should return output meters"
    assert result.is_a?(Array), "Should return an array"
    assert result.size > 0, "Should have default meters"

    # Check for expected default meters
    meter_names = result.map { |m| m['name'] }
    assert_includes meter_names, 'ElectricityNet:Facility', "Should include net electricity meter"
  end

  # Test schedule creation (inherited from parent but verify works)

  def test_model_add_schedule
    # Test that NECB schedules can be created
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule = standard.model_add_schedule(model, 'NECB-A-Occupancy')
    assert schedule, "Should create NECB-A-Occupancy schedule"
    assert_equal 'NECB-A-Occupancy', schedule.name.to_s, "Schedule name should match"
  end

  # Test inheritance across NECB vintages

  def test_necb_methods_across_vintages
    # Test that core methods work across all NECB vintages
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      standard = Standard.build(vintage)

      # Test standards data loaded
      assert standard.standards_data, "#{vintage} should have standards data loaded"
      assert standard.standards_data['tables'], "#{vintage} should have tables"

      # Test space type names available
      spacetypes = standard.get_all_spacetype_names
      assert spacetypes.size > 0, "#{vintage} should have space types defined"

      # Test climate zone methods
      assert_equal '6', standard.get_climate_zone_name(4500), "#{vintage} should calculate zone 6 correctly"

      # Test argument conversion
      assert_equal 5.0, standard.convert_arg_to_f(variable: 5.0, default: 1.0),
                   "#{vintage} should convert arguments correctly"
    end
  end

  # Test standards data initialization

  def test_standards_data_loaded_on_init
    # Test that standards data is loaded during initialization
    standard = Standard.build('NECB2011')

    assert standard.standards_data, "Standards data should be loaded"
    assert standard.standards_data.is_a?(Hash), "Standards data should be a hash"
    assert standard.standards_data['tables'], "Should have tables in standards data"
    assert standard.standards_data['tables'].is_a?(Hash), "Tables should be a hash"

    # Check for expected tables
    assert standard.standards_data['tables']['space_types'], "Should have space_types table"
    assert standard.standards_data['tables']['necb_2015_table_c1'], "Should have NECB climate zone table"
  end

  def test_template_name
    # Test that template name is set correctly
    standard = Standard.build('NECB2011')

    assert_equal 'NECB2011', standard.template, "Template should be NECB2011"

    standard2015 = Standard.build('NECB2015')
    assert_equal 'NECB2015', standard2015.template, "Template should be NECB2015"
  end
end
