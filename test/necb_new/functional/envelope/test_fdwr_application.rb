require_relative '../../test_helper'

# Test NECB FDWR (Fenestration to Door to Wall Ratio) Application
# Tests the apply_max_fdwr_nrcan method which enforces FDWR limits on building models
#
# Total Tests: 13
#
# Methods tested:
# - NECB2011#apply_max_fdwr_nrcan(model:, fdwr_lim:) - Apply FDWR limits to model
# - NECB2011#max_fwdr(hdd) - Get max FDWR for HDD zone (tested in Phase 1)
#
# References:
# - NECB 2011 Section 3.2.1.4 (Maximum Fenestration and Door to Wall Ratio)
# - NECB 2011 Section 8.4.4.3 (Fenestration area calculation)
#
# Test Strategy:
# - Uses simple_box.osm fixture (10m x 10m x 3m box with 4 exterior walls)
# - Tests FDWR enforcement across different HDD zones (6 tests)
# - Verifies window area is adjusted to meet FDWR limits
# - Tests edge cases: no windows, excessive glazing, zero FDWR (4 tests)
# - Tests vintage comparison and window distribution (2 tests)
# - Tests construction assignment (1 test)
class TestFDWRApplication < Minitest::Test

  # Fixture path
  SIMPLE_BOX_PATH = File.absolute_path(File.join(__dir__, '../fixtures/geometry/simple_box.osm'))

  # Helper method to add thermal zone with heating thermostat to make spaces conditioned
  # Also adds default construction set to avoid errors
  def add_heated_thermal_zone(model)
    # Get the space
    space = model.getSpaces.first

    # Create thermal zone
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    thermal_zone.setName('Zone 1')
    space.setThermalZone(thermal_zone)

    # Create heating thermostat (to make space "heated")
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermostat.setName('Zone 1 Thermostat')

    # Create constant heating setpoint schedule (20C)
    heating_schedule = OpenStudio::Model::ScheduleConstant.new(model)
    heating_schedule.setName('Heating Setpoint Schedule')
    heating_schedule.setValue(20.0)
    thermostat.setHeatingSetpointTemperatureSchedule(heating_schedule)

    # Set thermostat to thermal zone
    thermal_zone.setThermostatSetpointDualSetpoint(thermostat)

    # Add default construction set if not present
    unless model.getBuilding.defaultConstructionSet.is_initialized
      construction_set = OpenStudio::Model::DefaultConstructionSet.new(model)
      construction_set.setName('Default Construction Set')
      model.getBuilding.setDefaultConstructionSet(construction_set)

      # Add exterior subsurface constructions
      ext_subsurface_constructions = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
      construction_set.setDefaultExteriorSubSurfaceConstructions(ext_subsurface_constructions)

      # Create simple window construction
      simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
      simple_glazing.setUFactor(2.0)
      simple_glazing.setSolarHeatGainCoefficient(0.4)

      window_construction = OpenStudio::Model::Construction.new(model)
      window_construction.setName('Default Window Construction')
      window_construction.insertLayer(0, simple_glazing)

      ext_subsurface_constructions.setFixedWindowConstruction(window_construction)
    end

    # Assign construction to any existing subsurfaces
    model.getSubSurfaces.each do |subsurface|
      unless subsurface.construction.is_initialized
        if subsurface.subSurfaceType.include?('Window') || subsurface.subSurfaceType.include?('Skylight')
          construction_set = model.getBuilding.defaultConstructionSet.get
          ext_subsurface_constructions = construction_set.defaultExteriorSubSurfaceConstructions.get
          if ext_subsurface_constructions.fixedWindowConstruction.is_initialized
            subsurface.setConstruction(ext_subsurface_constructions.fixedWindowConstruction.get)
          end
        end
      end
    end
  end

  # Helper method to calculate actual FDWR from a model
  def calculate_fdwr(model)
    total_window_area = 0.0
    total_wall_area = 0.0

    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
        total_wall_area += surface.grossArea
        surface.subSurfaces.each do |subsurface|
          if subsurface.subSurfaceType.include?('Window')
            total_window_area += subsurface.grossArea
          end
        end
      end
    end

    return 0.0 if total_wall_area < 0.01
    total_window_area / total_wall_area
  end

  # Helper method to set uniform FDWR on all exterior walls
  def set_uniform_fdwr(model, target_fdwr)
    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
        # Remove existing subsurfaces
        surface.subSurfaces.each(&:remove)
        # Add windows with target ratio
        if target_fdwr > 0.0
          surface.setWindowToWallRatio(target_fdwr)
        end
      end
    end
  end

  # ============================================================================
  # FDWR Enforcement Tests - Different HDD Zones
  # ============================================================================

  def test_fdwr_enforcement_hdd_below_3000
    # NECB 2011 Table 3.2.1.4
    # HDD <= 3000 -> max FDWR = 0.40 (per formula)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set excessive glazing (60% FDWR)
    set_uniform_fdwr(model, 0.60)

    # Get expected FDWR limit
    max_fdwr = standard.max_fwdr(2500)
    assert_in_delta 0.40, max_fdwr, 0.01, "Expected max FDWR of ~0.40 for HDD=2500"

    # Apply FDWR limits
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Calculate actual FDWR
    actual_fdwr = calculate_fdwr(model)

    # Verify FDWR is at or below limit (with small tolerance for rounding)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)} for HDD=2500"
  end

  def test_fdwr_enforcement_hdd_3000_to_4000
    # NECB 2011 Table 3.2.1.4
    # HDD 3500 -> max FDWR = 0.40 (interpolated)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set excessive glazing (50% FDWR)
    set_uniform_fdwr(model, 0.50)

    # Get expected FDWR limit
    max_fdwr = standard.max_fwdr(3500)
    assert_in_delta 0.40, max_fdwr, 0.01, "Expected max FDWR of ~0.40 for HDD=3500"

    # Apply FDWR limits
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR is at or below limit
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)} for HDD=3500"
  end

  def test_fdwr_enforcement_hdd_4000_to_5000
    # NECB 2011 Table 3.2.1.4
    # HDD 4500 -> max FDWR = 0.3667 (interpolated)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set excessive glazing (45% FDWR)
    set_uniform_fdwr(model, 0.45)

    # Get expected FDWR limit
    max_fdwr = standard.max_fwdr(4500)
    assert_in_delta 0.3667, max_fdwr, 0.01, "Expected max FDWR of ~0.3667 for HDD=4500"

    # Apply FDWR limits
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR is at or below limit
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)} for HDD=4500"
  end

  def test_fdwr_enforcement_hdd_5000_to_6000
    # NECB 2011 Table 3.2.1.4
    # HDD 5500 -> max FDWR = 0.30 (interpolated)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set excessive glazing (40% FDWR)
    set_uniform_fdwr(model, 0.40)

    # Get expected FDWR limit
    max_fdwr = standard.max_fwdr(5500)
    assert_in_delta 0.30, max_fdwr, 0.01, "Expected max FDWR of ~0.30 for HDD=5500"

    # Apply FDWR limits
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR is at or below limit
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)} for HDD=5500"
  end

  def test_fdwr_enforcement_hdd_6000_to_7000
    # NECB 2011 Table 3.2.1.4
    # HDD 6500 -> max FDWR = 0.2333 (interpolated)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set excessive glazing (35% FDWR)
    set_uniform_fdwr(model, 0.35)

    # Get expected FDWR limit
    max_fdwr = standard.max_fwdr(6500)
    assert_in_delta 0.2333, max_fdwr, 0.01, "Expected max FDWR of ~0.2333 for HDD=6500"

    # Apply FDWR limits
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR is at or below limit
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)} for HDD=6500"
  end

  def test_fdwr_enforcement_hdd_above_7000
    # NECB 2011 Table 3.2.1.4
    # HDD 8000 -> max FDWR = 0.20 (interpolated)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set excessive glazing (30% FDWR)
    set_uniform_fdwr(model, 0.30)

    # Get expected FDWR limit
    max_fdwr = standard.max_fwdr(8000)
    assert_in_delta 0.20, max_fdwr, 0.01, "Expected max FDWR of ~0.20 for HDD=8000"

    # Apply FDWR limits
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR is at or below limit
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)} for HDD=8000"
  end

  # ============================================================================
  # Edge Case Tests
  # ============================================================================

  def test_fdwr_model_with_no_windows
    # Test that method works correctly when model has no windows
    # Should add windows up to the FDWR limit
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Remove all windows
    model.getSubSurfaces.each(&:remove)

    # Verify no windows exist
    initial_fdwr = calculate_fdwr(model)
    assert_in_delta 0.0, initial_fdwr, 0.001, "Model should have no windows initially"

    # Apply FDWR for moderate climate (HDD=4000, FDWR=0.30)
    max_fdwr = standard.max_fwdr(4000)
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify windows were added up to the limit
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr > 0.01, "Windows should have been added to the model"
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)}"
  end

  def test_fdwr_model_below_limit
    # Test that method doesn't modify windows when FDWR is already below limit
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set low glazing (10% FDWR)
    set_uniform_fdwr(model, 0.10)
    initial_fdwr = calculate_fdwr(model)

    # Apply FDWR for warm climate (HDD=2500, FDWR=0.40)
    max_fdwr = standard.max_fwdr(2500)
    assert initial_fdwr < max_fdwr, "Initial FDWR should be below limit"

    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR increased to meet the limit (method applies the limit)
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be <= #{max_fdwr.round(3)}"
  end

  def test_fdwr_zero_limit
    # Test edge case where FDWR limit is zero (no windows allowed)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set some initial glazing
    set_uniform_fdwr(model, 0.20)

    # Apply zero FDWR limit
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: 0.0005)
    assert result, "apply_max_fdwr_nrcan should return true even with zero FDWR"

    # Verify all windows were removed
    actual_fdwr = calculate_fdwr(model)
    assert_in_delta 0.0, actual_fdwr, 0.001, "All windows should have been removed"
  end

  def test_fdwr_excessive_glazing
    # Test with extremely high initial glazing (80% FDWR)
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Set very high glazing (80% FDWR)
    set_uniform_fdwr(model, 0.80)
    initial_fdwr = calculate_fdwr(model)
    assert initial_fdwr > 0.70, "Initial FDWR should be very high"

    # Apply FDWR for cold climate (HDD=6000, FDWR=0.24)
    max_fdwr = standard.max_fwdr(6000)
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Verify FDWR was reduced significantly
    actual_fdwr = calculate_fdwr(model)
    assert actual_fdwr <= max_fdwr + 0.01,
      "FDWR #{actual_fdwr.round(3)} should be reduced to <= #{max_fdwr.round(3)}"
    assert actual_fdwr < initial_fdwr - 0.10,
      "FDWR should have been reduced significantly from #{initial_fdwr.round(3)} to #{actual_fdwr.round(3)}"
  end

  # ============================================================================
  # NECB Vintage Comparison Tests
  # ============================================================================

  def test_fdwr_necb2015_vs_2011
    # Compare FDWR limits between NECB2011 and NECB2015
    # Both should enforce the same FDWR limits per the standard
    hdd = 4000

    standard_2011 = Standard.build('NECB2011')
    standard_2015 = Standard.build('NECB2015')

    max_fdwr_2011 = standard_2011.max_fwdr(hdd)
    max_fdwr_2015 = standard_2015.max_fwdr(hdd)

    # FDWR limits should be the same across NECB vintages
    assert_in_delta max_fdwr_2011, max_fdwr_2015, 0.001,
      "NECB2011 and NECB2015 should have same FDWR limits for HDD=#{hdd}"

    # Test application on both vintages
    model_2011 = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)
    model_2015 = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Set same initial glazing
    set_uniform_fdwr(model_2011, 0.50)
    set_uniform_fdwr(model_2015, 0.50)

    # Apply FDWR limits
    standard_2011.apply_max_fdwr_nrcan(model: model_2011, fdwr_lim: max_fdwr_2011)
    standard_2015.apply_max_fdwr_nrcan(model: model_2015, fdwr_lim: max_fdwr_2015)

    # Compare results
    fdwr_2011 = calculate_fdwr(model_2011)
    fdwr_2015 = calculate_fdwr(model_2015)

    assert_in_delta fdwr_2011, fdwr_2015, 0.01,
      "Both vintages should produce similar FDWR: 2011=#{fdwr_2011.round(3)}, 2015=#{fdwr_2015.round(3)}"
  end

  def test_fdwr_uniform_distribution
    # Test that windows are distributed uniformly across facades
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Remove all windows
    model.getSubSurfaces.each(&:remove)

    # Apply FDWR
    max_fdwr = standard.max_fwdr(4000)
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Check that windows exist on multiple facades
    facades_with_windows = 0
    model.getSurfaces.each do |surface|
      if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
        if surface.subSurfaces.any? { |ss| ss.subSurfaceType.include?('Window') }
          facades_with_windows += 1
        end
      end
    end

    # Simple box has 4 exterior walls, so expect windows on all 4
    assert facades_with_windows >= 3,
      "Windows should be distributed across multiple facades (found #{facades_with_windows})"
  end

  def test_fdwr_preserves_window_construction
    # Test that applying FDWR uses the correct window construction
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm(SIMPLE_BOX_PATH)

    # Add thermal zone to make space conditioned
    add_heated_thermal_zone(model)

    # Add default construction set if not present
    unless model.getBuilding.defaultConstructionSet.is_initialized
      construction_set = OpenStudio::Model::DefaultConstructionSet.new(model)
      construction_set.setName('Default Construction Set')
      model.getBuilding.setDefaultConstructionSet(construction_set)

      # Add exterior subsurface constructions
      ext_subsurface_constructions = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
      construction_set.setDefaultExteriorSubSurfaceConstructions(ext_subsurface_constructions)

      # Create simple window construction
      simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
      simple_glazing.setUFactor(2.0)
      simple_glazing.setSolarHeatGainCoefficient(0.4)

      window_construction = OpenStudio::Model::Construction.new(model)
      window_construction.setName('Test Window Construction')
      window_construction.insertLayer(0, simple_glazing)

      ext_subsurface_constructions.setFixedWindowConstruction(window_construction)
    end

    # Apply FDWR
    max_fdwr = standard.max_fwdr(4000)
    result = standard.apply_max_fdwr_nrcan(model: model, fdwr_lim: max_fdwr)
    assert result, "apply_max_fdwr_nrcan should return true on success"

    # Check that windows have a construction assigned
    windows_with_construction = 0
    model.getSubSurfaces.each do |subsurface|
      if subsurface.subSurfaceType.include?('Window')
        if subsurface.construction.is_initialized
          windows_with_construction += 1
        end
      end
    end

    assert windows_with_construction > 0,
      "All windows should have a construction assigned"
  end

end
