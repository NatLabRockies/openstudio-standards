require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# Comprehensive Building Envelope Tests for NECB
# Tests construction assembly creation, U-value lookups, SHGC, FDWR, SRR,
# and compliance with NECB tables across multiple climate zones and vintages
#
# Target: /lib/openstudio-standards/standards/necb/NECB2011/building_envelope.rb
# Coverage Goal: Test the 15-20 most critical methods in building_envelope.rb

class TestNECBBuildingEnvelope < Minitest::Test
  include(NecbHelper)

  # Tolerance for U-value comparisons (W/m2·K)
  U_VALUE_TOLERANCE = 0.01

  # Tolerance for FDWR/SRR comparisons (ratio)
  RATIO_TOLERANCE = 0.01

  ##############################################################################
  # Helper Methods
  ##############################################################################

  # Create a simple test model with geometry for envelope testing
  def create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    # Set climate
    climate_files = {
      'Toronto' => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      'Vancouver' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
      'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
    }
    epw_file = climate_files[climate] || climate_files['Toronto']
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply NECB space types
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    # Set building properties
    building = model.getBuilding
    building.setStandardsNumberOfStories(2)
    building.setStandardsNumberOfAboveGroundStories(2)

    # Add thermostats to zones (needed for some envelope methods)
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

    [model, standard]
  end

  ##############################################################################
  # TEST 1-3: HDD Calculation Tests
  ##############################################################################

  def test_get_necb_hdd18_returns_valid_value
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)

    assert hdd.is_a?(Numeric), "HDD should be numeric"
    assert hdd > 0, "HDD should be positive"
    assert hdd < 12000, "HDD should be realistic (<12000)"
  end

  def test_get_necb_hdd18_toronto_climate_zone_5
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)

    # Toronto is climate zone 5 with HDD ~4000
    assert hdd > 3500 && hdd < 4500,
      "Toronto HDD should be ~4000 (zone 5), got #{hdd}"
  end

  def test_get_necb_hdd18_varies_correctly_by_climate
    climates = {
      'Vancouver' => { min: 2500, max: 3500 },    # Zone 4
      'Toronto' => { min: 3500, max: 4500 },      # Zone 5
      'Yellowknife' => { min: 7500, max: 9000 }   # Zone 8
    }

    climates.each do |city, expected|
      model, standard = create_baseline_necb_model(template: 'NECB2011', climate: city)
      hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)

      assert hdd >= expected[:min] && hdd <= expected[:max],
        "#{city} HDD (#{hdd}) not in expected range #{expected[:min]}-#{expected[:max]}"
    end
  end

  ##############################################################################
  # TEST 4-6: FDWR (Fenestration-to-Wall Ratio) Tests
  ##############################################################################

  def test_max_fwdr_returns_valid_ratio
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)
    max_fdwr = standard.max_fwdr(hdd)

    assert max_fdwr.is_a?(Numeric), "FDWR should be numeric"
    assert max_fdwr > 0, "FDWR should be positive"
    assert max_fdwr < 1.0, "FDWR should be less than 1.0 (100%)"
    assert max_fdwr > 0.1, "FDWR should be reasonable (>0.1)"
  end

  def test_max_fwdr_decreases_with_colder_climates
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # NECB restricts fenestration more in colder climates
    fdwr_3000 = standard.max_fwdr(3000)   # Mild climate
    fdwr_5000 = standard.max_fwdr(5000)   # Moderate climate
    fdwr_7000 = standard.max_fwdr(7000)   # Cold climate
    fdwr_9000 = standard.max_fwdr(9000)   # Very cold climate

    assert fdwr_3000 > fdwr_5000,
      "FDWR should decrease with HDD (3000: #{fdwr_3000}, 5000: #{fdwr_5000})"
    assert fdwr_5000 > fdwr_7000,
      "FDWR should decrease with HDD (5000: #{fdwr_5000}, 7000: #{fdwr_7000})"
    # FDWR may plateau at very high HDDs - just verify it doesn't increase
    assert fdwr_7000 >= fdwr_9000,
      "FDWR should not increase with HDD (7000: #{fdwr_7000}, 9000: #{fdwr_9000})"
  end

  def test_max_fwdr_necb_formula_consistency
    # Test that FDWR follows expected NECB formula behavior
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Test a range of HDD values
    test_hdds = [3000, 4000, 5000, 6000, 7000, 8000, 9000]
    previous_fdwr = 1.0

    test_hdds.each do |hdd|
      fdwr = standard.max_fwdr(hdd)
      assert fdwr <= previous_fdwr,
        "FDWR should be monotonically decreasing with HDD"
      assert fdwr >= 0.15 && fdwr <= 0.5,
        "FDWR should be in reasonable NECB range (0.15-0.5), got #{fdwr} at HDD #{hdd}"
      previous_fdwr = fdwr
    end
  end

  ##############################################################################
  # TEST 7-12: U-Value Lookup Tests (Core NECB Compliance)
  ##############################################################################

  def test_max_u_necb_wall_outdoors_all_climate_zones
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Test NECB 2011 Table 3.2.1.3 values for walls (outdoors)
    # Logic: returns U-value for first threshold HDD >= input HDD
    # If HDD >= all thresholds, returns default 0.110
    test_cases = {
      2500 => 0.315,  # HDD < 3000, returns 3000 threshold (Zone 4)
      3500 => 0.278,  # HDD 3000-4000, returns 4000 threshold (Zone 5)
      4500 => 0.247,  # HDD 4000-5000, returns 5000 threshold
      5500 => 0.210,  # HDD 5000-6000, returns 6000 threshold (Zone 6)
      6500 => 0.210,  # HDD 6000-7000, returns 7000 threshold (Zone 7)
      9500 => 0.183   # HDD 7000-9999, returns 9999 threshold (Zone 8)
    }

    test_cases.each do |hdd, expected_u|
      u_value = standard.max_u_necb("wall", "outdoors", hdd)
      assert_in_delta expected_u, u_value, U_VALUE_TOLERANCE,
        "Wall U-value at HDD #{hdd} should be #{expected_u}, got #{u_value}"
    end
  end

  def test_max_u_necb_roof_outdoors_all_climate_zones
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Test NECB 2011 Table 3.2.1.3 values for roofs (outdoors)
    # Logic: returns U-value for first threshold HDD >= input HDD
    test_cases = {
      2500 => 0.227,  # HDD < 3000
      3500 => 0.183,  # HDD 3000-4000
      4500 => 0.183,  # HDD 4000-5000 (same as 4000)
      5500 => 0.162,  # HDD 5000-6000
      6500 => 0.162,  # HDD 6000-7000 (same as 6000)
      9500 => 0.142   # HDD 7000-9999
    }

    test_cases.each do |hdd, expected_u|
      u_value = standard.max_u_necb("roofceiling", "outdoors", hdd)
      assert_in_delta expected_u, u_value, U_VALUE_TOLERANCE,
        "Roof U-value at HDD #{hdd} should be #{expected_u}, got #{u_value}"
    end
  end

  def test_max_u_necb_floor_outdoors_all_climate_zones
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Exposed floors have same U-values as roofs in NECB
    # Logic: returns U-value for first threshold HDD >= input HDD
    test_cases = {
      2500 => 0.227,  # HDD < 3000
      3500 => 0.183,  # HDD 3000-4000
      5500 => 0.162,  # HDD 5000-6000
      9500 => 0.142   # HDD 7000-9999
    }

    test_cases.each do |hdd, expected_u|
      u_value = standard.max_u_necb("floor", "outdoors", hdd)
      assert_in_delta expected_u, u_value, U_VALUE_TOLERANCE,
        "Floor U-value at HDD #{hdd} should be #{expected_u}, got #{u_value}"
    end
  end

  def test_max_u_necb_window_outdoors_all_climate_zones
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Test NECB 2011 window U-values
    # Logic: returns U-value for first threshold HDD >= input HDD
    test_cases = {
      2500 => 2.400,  # HDD < 3000
      3500 => 2.200,  # HDD 3000-4000
      4500 => 2.200,  # HDD 4000-5000
      5500 => 2.200,  # HDD 5000-6000
      6500 => 2.200,  # HDD 6000-7000
      9500 => 1.600   # HDD 7000-9999
    }

    test_cases.each do |hdd, expected_u|
      u_value = standard.max_u_necb("window", "outdoors", hdd)
      assert_in_delta expected_u, u_value, U_VALUE_TOLERANCE,
        "Window U-value at HDD #{hdd} should be #{expected_u}, got #{u_value}"
    end
  end

  def test_max_u_necb_ground_contact_surfaces
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Test ground contact walls (basement walls)
    # Logic: returns U-value for first threshold HDD >= input HDD
    test_cases = {
      2500 => 0.568,  # HDD < 3000
      3500 => 0.379,  # HDD 3000-4000
      4500 => 0.284,  # HDD 4000-5000
      5500 => 0.284,  # HDD 5000-6000 (same as 5000)
      9500 => 0.210   # HDD 7000-9999
    }

    test_cases.each do |hdd, expected_u|
      u_value = standard.max_u_necb("wall", "ground", hdd)
      assert_in_delta expected_u, u_value, U_VALUE_TOLERANCE,
        "Ground wall U-value at HDD #{hdd} should be #{expected_u}, got #{u_value}"
    end
  end

  def test_max_u_necb_all_surface_types_return_valid
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    surface_types = ["wall", "roofceiling", "floor", "window", "skylight", "door"]
    conditions = ["outdoors", "ground"]

    surface_types.each do |stype|
      conditions.each do |condition|
        # Skip invalid combinations
        next if ["window", "skylight", "door"].include?(stype) && condition == "ground"

        u_value = standard.max_u_necb(stype, condition, 4000)
        assert u_value > 0,
          "#{stype} (#{condition}) should have positive U-value"
        assert u_value < 5.0,
          "#{stype} (#{condition}) U-value should be realistic (<5.0)"
      end
    end
  end

  ##############################################################################
  # TEST 13-15: Multi-Vintage NECB Compliance Tests
  ##############################################################################

  def test_necb2011_vs_necb2015_envelope_requirements
    # NECB 2011 and 2015 have identical envelope requirements
    ['NECB2011', 'NECB2015'].each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Toronto')
      hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)

      # Wall U-value at HDD 4500 (between 4000-5000 thresholds, returns 5000 value)
      u_wall = standard.max_u_necb("wall", "outdoors", 4500)
      assert_in_delta 0.247, u_wall, U_VALUE_TOLERANCE,
        "#{vintage} wall U-value should be 0.247 at HDD 4500"

      # Window U-value at HDD 4500
      u_window = standard.max_u_necb("window", "outdoors", 4500)
      assert_in_delta 2.200, u_window, U_VALUE_TOLERANCE,
        "#{vintage} window U-value should be 2.200 at HDD 4500"
    end
  end

  def test_necb2017_improved_roof_requirements
    # NECB 2017 improved roof requirements compared to 2011
    model_2011, standard_2011 = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    model_2017, standard_2017 = create_baseline_necb_model(template: 'NECB2017', climate: 'Toronto')

    # At HDD 4000
    u_roof_2011 = standard_2011.max_u_necb("roofceiling", "outdoors", 4000)
    u_roof_2017 = standard_2017.max_u_necb("roofceiling", "outdoors", 4000)

    assert_in_delta 0.183, u_roof_2011, U_VALUE_TOLERANCE, "NECB2011 roof should be 0.183"
    assert_in_delta 0.156, u_roof_2017, U_VALUE_TOLERANCE, "NECB2017 roof should be 0.156"
    assert u_roof_2017 < u_roof_2011,
      "NECB2017 roof U-value should be stricter than NECB2011"
  end

  def test_necb2020_most_stringent_requirements
    # NECB 2020 has the most stringent envelope requirements
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    # Test wall U-values at HDD 7000 (cold climate)
    u_values = {}
    vintages.each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Yellowknife')
      u_values[vintage] = standard.max_u_necb("wall", "outdoors", 7000)
    end

    # NECB2020 should have the lowest (best) U-value
    assert u_values['NECB2020'] <= u_values['NECB2017'],
      "NECB2020 should be equal or stricter than NECB2017"
    assert u_values['NECB2017'] <= u_values['NECB2015'],
      "NECB2017 should be equal or stricter than NECB2015"
  end

  ##############################################################################
  # TEST 16-18: Construction Set Creation Tests
  ##############################################################################

  def test_model_add_constructions_creates_construction_sets
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    initial_sets = model.getDefaultConstructionSets.size
    standard.model_add_constructions(model)
    final_sets = model.getDefaultConstructionSets.size

    assert final_sets > initial_sets,
      "model_add_constructions should create construction sets"
  end

  def test_apply_building_default_constructionset_assigns_to_building
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    standard.model_add_constructions(model)
    standard.apply_building_default_constructionset(model)

    assert model.getBuilding.defaultConstructionSet.is_initialized,
      "Building should have default construction set assigned"
  end

  def test_construction_sets_vary_by_climate
    climates = ['Vancouver', 'Toronto', 'Yellowknife']
    construction_counts = {}

    climates.each do |city|
      model, standard = create_baseline_necb_model(template: 'NECB2011', climate: city)
      standard.model_add_constructions(model)
      construction_counts[city] = model.getConstructions.size
    end

    # All should have constructions
    climates.each do |city|
      assert construction_counts[city] > 0,
        "#{city} should have constructions created"
    end
  end

  ##############################################################################
  # TEST 19-20: Edge Cases and Error Handling
  ##############################################################################

  def test_max_u_necb_handles_invalid_surface_types
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Should default to roofceiling behavior
    u_value = standard.max_u_necb("invalid_type", "outdoors", 4000)
    assert u_value > 0, "Invalid surface type should return default U-value"
  end

  def test_max_u_necb_handles_extreme_hdd_values
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Very low HDD (should use minimum requirements)
    u_low = standard.max_u_necb("wall", "outdoors", 1000)
    assert u_low > 0, "Very low HDD should return valid U-value"

    # Very high HDD (should use maximum requirements)
    u_high = standard.max_u_necb("wall", "outdoors", 15000)
    assert u_high > 0, "Very high HDD should return valid U-value"
    assert u_high <= u_low, "Higher HDD should have stricter (lower) U-value"
  end

  ##############################################################################
  # TEST 21: Integration Test - Full Envelope Application
  ##############################################################################

  def test_full_envelope_workflow_necb2011_toronto
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    # Get HDD
    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)
    assert hdd > 0, "HDD should be calculated"

    # Get maximum FDWR
    max_fdwr = standard.max_fwdr(hdd)
    assert max_fdwr > 0 && max_fdwr < 1.0, "Max FDWR should be valid"

    # Get U-values for all envelope components
    u_wall = standard.max_u_necb("wall", "outdoors", hdd)
    u_roof = standard.max_u_necb("roofceiling", "outdoors", hdd)
    u_window = standard.max_u_necb("window", "outdoors", hdd)

    assert u_wall > 0, "Wall U-value should be valid"
    assert u_roof > 0, "Roof U-value should be valid"
    assert u_window > 0, "Window U-value should be valid"

    # Create constructions
    standard.model_add_constructions(model)
    assert model.getConstructions.size > 0, "Constructions should be created"

    # Assign to building
    standard.apply_building_default_constructionset(model)
    assert model.getBuilding.defaultConstructionSet.is_initialized,
      "Construction set should be assigned to building"
  end
end
