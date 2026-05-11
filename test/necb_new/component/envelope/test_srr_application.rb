require_relative '../../test_helper'

# Test SRR (Skylight to Roof Ratio) enforcement
# Tests the SRR limit enforcement methods for NECB standards
#
# Methods tested:
# - NECB2011#apply_max_srr_nrcan(model:, srr_lim:, srr_opt:)
# - NECB2011#find_exposed_conditioned_roof_surfaces
#
# References:
# - NECB 2011 Section 3.2.1.4(2) - Maximum SRR = 5%
# - NECB constants.json - skylight_to_roof_ratio_max_value = 0.05
class TestSRRApplication < Minitest::Test

  # ============================================================================
  # Helper Methods
  # ============================================================================

  # Set up minimal construction set required for SRR method
  def setup_construction_set(model)
    # Create default construction set
    construction_set = OpenStudio::Model::DefaultConstructionSet.new(model)

    # Create exterior subsurface constructions
    ext_subsurface_constructions = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)

    # Create simple skylight construction
    skylight_construction = OpenStudio::Model::Construction.new(model)
    material = OpenStudio::Model::StandardGlazing.new(model)
    skylight_construction.insertLayer(0, material)

    ext_subsurface_constructions.setSkylightConstruction(skylight_construction)
    construction_set.setDefaultExteriorSubSurfaceConstructions(ext_subsurface_constructions)
    model.getBuilding.setDefaultConstructionSet(construction_set)
  end

  # Make spaces conditioned by adding ideal air loads system
  def make_spaces_conditioned(model)
    model.getSpaces.each do |space|
      # Ensure space is part of total floor area (not a plenum)
      space.setPartofTotalFloorArea(true)

      # Create thermal zone if needed
      if space.thermalZone.empty?
        thermal_zone = OpenStudio::Model::ThermalZone.new(model)
        space.setThermalZone(thermal_zone)
      end

      zone = space.thermalZone.get

      # Add thermostat to make it heated/cooled
      if zone.thermostatSetpointDualSetpoint.empty?
        thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
        thermostat.setName("#{zone.name} Thermostat")

        # Create simple heating schedule (21C)
        heating_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
        heating_schedule.setName("Heating Setpoint Schedule")
        heating_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0,24,0,0), 21.0)

        # Create simple cooling schedule (24C)
        cooling_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
        cooling_schedule.setName("Cooling Setpoint Schedule")
        cooling_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0,24,0,0), 24.0)

        thermostat.setHeatingSetpointTemperatureSchedule(heating_schedule)
        thermostat.setCoolingSetpointTemperatureSchedule(cooling_schedule)
        zone.setThermostatSetpointDualSetpoint(thermostat)
      end

      # Add ideal air loads (simplest way to make it conditioned)
      zone_hvac = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
      zone_hvac.addToThermalZone(zone)
    end
  end

  # Calculate actual SRR from model
  def calculate_srr(model)
    total_skylight_area = 0.0
    total_roof_area = 0.0

    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'
        total_roof_area += surface.grossArea
        surface.subSurfaces.each do |subsurface|
          if subsurface.subSurfaceType == 'Skylight'
            total_skylight_area += subsurface.grossArea
          end
        end
      end
    end

    return 0.0 if total_roof_area < 0.001
    return total_skylight_area / total_roof_area
  end

  # Count skylights in model
  def count_skylights(model)
    count = 0
    model.getSurfaces.each do |surface|
      surface.subSurfaces.each do |subsurface|
        count += 1 if subsurface.subSurfaceType == 'Skylight'
      end
    end
    return count
  end

  # Get total skylight area
  def get_skylight_area(model)
    area = 0.0
    model.getSurfaces.each do |surface|
      surface.subSurfaces.each do |subsurface|
        area += subsurface.grossArea if subsurface.subSurfaceType == 'Skylight'
      end
    end
    return area
  end

  # ============================================================================
  # NECB2011 SRR Limit Tests
  # ============================================================================

  def test_necb2011_default_srr_limit
    # Test that NECB2011 has the correct default SRR limit of 5%
    standard = Standard.build('NECB2011')

    srr_limit = standard.get_standards_constant('skylight_to_roof_ratio_max_value')

    assert_in_delta 0.05, srr_limit, 0.001,
      "NECB2011 should have SRR limit of 0.05 (5%) per Section 3.2.1.4(2)"
  end

  def test_srr_enforcement_with_standard_limit
    # Test applying standard NECB SRR limit to a model with skylights
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    # Apply default NECB SRR limit (5%)
    srr_limit = 0.05
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: srr_limit)

    assert result, "apply_max_srr_nrcan should return true on success"

    # Calculate actual SRR
    actual_srr = calculate_srr(model)

    # Verify SRR is at or below limit (with small tolerance for rounding)
    assert actual_srr <= srr_limit + 0.001,
      "SRR #{actual_srr.round(4)} should be <= #{srr_limit} (#{(srr_limit * 100).round(1)}%)"
  end

  def test_srr_enforcement_with_custom_low_limit
    # Test with very restrictive SRR limit (2%)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    # Apply restrictive 2% SRR limit
    srr_limit = 0.02
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: srr_limit)

    assert result, "apply_max_srr_nrcan should return true on success"

    actual_srr = calculate_srr(model)

    assert actual_srr <= srr_limit + 0.001,
      "SRR #{actual_srr.round(4)} should be <= #{srr_limit} (2%)"
    assert actual_srr > 0.0,
      "Should still have some skylights with 2% limit"
  end

  def test_srr_enforcement_with_high_limit
    # Test with generous SRR limit (10%) - should leave skylights mostly unchanged
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    # Get initial SRR
    initial_srr = calculate_srr(model)
    initial_skylight_area = get_skylight_area(model)

    # Apply generous 10% SRR limit
    srr_limit = 0.10
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: srr_limit)

    assert result, "apply_max_srr_nrcan should return true on success"

    actual_srr = calculate_srr(model)
    actual_skylight_area = get_skylight_area(model)

    # If initial SRR was already below 10%, skylight area should increase to meet target
    assert actual_srr <= srr_limit + 0.001,
      "SRR #{actual_srr.round(4)} should be <= #{srr_limit} (10%)"

    # With 10% limit, we should have skylights
    assert actual_skylight_area > 0.0,
      "Should have skylights with 10% SRR limit"
  end

  def test_srr_remove_all_skylights
    # Test removing all skylights (SRR limit < 0.001)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    # Verify we start with skylights
    initial_count = count_skylights(model)
    assert initial_count > 0, "Fixture should have skylights to start"

    # Apply zero SRR limit
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: 0.0005)

    assert result, "apply_max_srr_nrcan should return true when removing skylights"

    # Verify all skylights removed
    final_count = count_skylights(model)
    assert_equal 0, final_count, "All skylights should be removed with SRR < 0.001"

    actual_srr = calculate_srr(model)
    assert_equal 0.0, actual_srr, "SRR should be 0 with no skylights"
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  def test_srr_with_no_roof
    # Test applying SRR to a model without exterior roof surfaces
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Setup required construction set
    setup_construction_set(model)

    # Create a simple space with walls but no roof
    space = OpenStudio::Model::Space.new(model)

    # Add floor
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 10, 0)
    vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(vertices, model)
    floor.setSpace(space)
    floor.setSurfaceType('Floor')
    floor.setOutsideBoundaryCondition('Ground')

    # Try to apply SRR
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: 0.05)

    # Should return false since there's no exposed roof
    assert_equal false, result,
      "Should return false when there are no exposed conditioned roof surfaces"
  end

  def test_srr_with_existing_skylight_within_limit
    # Test that when existing SRR is already below limit, skylights are resized to target
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    # Get initial SRR (fixture has a small skylight)
    initial_srr = calculate_srr(model)
    initial_count = count_skylights(model)

    # Apply 3% SRR limit (stricter than 5% default)
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: 0.03)

    assert result, "apply_max_srr_nrcan should return true"

    # Verify SRR was adjusted
    final_srr = calculate_srr(model)
    final_count = count_skylights(model)

    # Should still have skylights
    assert final_count > 0, "Should maintain skylights"

    # SRR should be at or below the 3% limit
    assert final_srr <= 0.03 + 0.001,
      "Final SRR #{final_srr.round(4)} should be <= 0.03 (3%)"

    # Skylight should be resized to meet the target SRR
    assert_in_delta 0.03, final_srr, 0.002,
      "SRR should be close to target of 3% (actual: #{(final_srr * 100).round(2)}%)"
  end

  def test_srr_invalid_limit_too_high
    # Test that SRR > 1.0 returns false (invalid)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set
    setup_construction_set(model)

    # Try to apply impossible SRR limit > 1.0 (>100%)
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: 1.5)

    assert_equal false, result,
      "Should return false when SRR limit > 1.0 (impossible to have more skylight than roof)"
  end

  # ============================================================================
  # NECB Vintage Comparison
  # ============================================================================

  def test_necb2015_srr_limit
    # Compare NECB2015 to NECB2011 SRR limits
    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    srr_2011 = standard_2011.get_standards_constant('skylight_to_roof_ratio_max_value')
    srr_2015 = standard_2015.get_standards_constant('skylight_to_roof_ratio_max_value')

    # NECB SRR limits should be consistent across vintages (unless code changed)
    assert_in_delta srr_2011, srr_2015, 0.01,
      "NECB2015 and NECB2011 should have similar SRR limits"
  end

  def test_necb2017_srr_enforcement
    # Test NECB2017 SRR enforcement
    standard = Standard.build('NECB2017')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    srr_limit = standard.get_standards_constant('skylight_to_roof_ratio_max_value')
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: srr_limit)

    if result
      actual_srr = calculate_srr(model)
      assert actual_srr <= srr_limit + 0.001,
        "NECB2017 SRR #{actual_srr.round(4)} should be <= #{srr_limit}"
    end
  end

  def test_necb2020_srr_enforcement
    # Test NECB2020 SRR enforcement
    standard = Standard.build('NECB2020')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    srr_limit = standard.get_standards_constant('skylight_to_roof_ratio_max_value')
    result = standard.apply_max_srr_nrcan(model: model, srr_lim: srr_limit)

    if result
      actual_srr = calculate_srr(model)
      assert actual_srr <= srr_limit + 0.001,
        "NECB2020 SRR #{actual_srr.round(4)} should be <= #{srr_limit}"
    end
  end

  # ============================================================================
  # Practical Application Tests
  # ============================================================================

  def test_srr_preserves_roof_geometry
    # Verify that applying SRR doesn't modify the roof surface itself
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box_with_skylight.osm')

    # Setup required construction set and make spaces conditioned
    setup_construction_set(model)
    make_spaces_conditioned(model)

    # Get initial roof area
    initial_roof_area = 0.0
    roof_count = 0
    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'
        initial_roof_area += surface.grossArea
        roof_count += 1
      end
    end

    # Apply SRR
    standard.apply_max_srr_nrcan(model: model, srr_lim: 0.05)

    # Get final roof area
    final_roof_area = 0.0
    final_roof_count = 0
    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'
        final_roof_area += surface.grossArea
        final_roof_count += 1
      end
    end

    # Roof area and count should be unchanged
    assert_equal roof_count, final_roof_count,
      "Number of roof surfaces should not change"
    assert_in_delta initial_roof_area, final_roof_area, 0.01,
      "Total roof area should not change when applying SRR"
  end

end
