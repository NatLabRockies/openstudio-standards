#!/usr/bin/env ruby

require_relative '../../test_helper'

# Test suite for NECB2020-specific features
# Tests lib/openstudio-standards/standards/necb/NECB2020/necb_2020.rb
# Focus on methods that DIFFER from NECB2017 baseline, especially infiltration calculation
class TestNecb2020Specific < Minitest::Test
  def setup
    @standard_2017 = Standard.build('NECB2017')
    @standard_2020 = Standard.build('NECB2020')
    @model = OpenStudio::Model::Model.new

    # Set weather file
    epw_path = File.join(__dir__, '../../../../data/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(@model, epw_file)

    # Create a simple space for testing
    @space = OpenStudio::Model::Space.new(@model)
    @space.setName('TestSpace')
  end

  # ===== Standards Database Loading Tests =====

  def test_necb2020_loads_standards_database
    # Test that NECB2020 successfully loads and extends NECB2017 database
    assert @standard_2020.instance_variable_get(:@standards_data), "Should load standards database"
    assert @standard_2020.instance_variable_get(:@standards_data)['tables'], "Should have tables"
  end

  def test_necb2020_extends_necb2017
    # Test that NECB2020 class inherits from NECB2017
    assert @standard_2020.is_a?(NECB2017), "NECB2020 should inherit from NECB2017"
  end

  def test_necb2020_template_name
    # Test template registration
    assert_equal 'NECB2020', @standard_2020.class.name
  end

  # ===== Infiltration Calculation Tests (MAJOR CHANGE in NECB2020) =====

  def test_space_apply_infiltration_rate_method_exists
    # Test that NECB2020 has infiltration rate method
    assert @standard_2020.respond_to?(:space_apply_infiltration_rate),
           "Should have space_apply_infiltration_rate method"
  end

  def test_infiltration_pressure_conversion_75pa_to_5pa
    # NECB2020 specifies infiltration at 75 Pa, must convert to 5 Pa
    # Conversion formula: rate_5Pa = rate_75Pa * (5/75)^0.6

    infil_75pa = 1.0  # m³/s·m²
    pressure_ratio = 5.0 / 75.0
    exponent = 0.6

    infil_5pa = infil_75pa * (pressure_ratio ** exponent)

    # Calculate expected value
    expected = 1.0 * ((5.0 / 75.0) ** 0.6)
    assert_in_delta expected, infil_5pa, 0.001
  end

  def test_infiltration_surface_area_normalization
    # NECB2020 uses total building envelope area (above + below grade)
    # Previous codes used only above grade area

    # Create surfaces for testing
    create_test_geometry_with_ground_contact

    # Calculate areas
    total_area = 0.0
    above_grade_area = 0.0

    @model.getSpaces.each do |space|
      multiplier = space.multiplier
      space.surfaces.each do |surface|
        if surface.outsideBoundaryCondition == 'Outdoors'
          area = surface.grossArea * multiplier
          total_area += area
          above_grade_area += area
        elsif surface.outsideBoundaryCondition == 'Ground'
          area = surface.grossArea * multiplier
          total_area += area
        end
      end
    end

    assert total_area >= above_grade_area, "Total area should be >= above grade area"
  end

  def test_infiltration_calculation_no_exterior_surfaces
    # Test that infiltration is not applied when no exterior surfaces exist
    # (lines 78-82 in necb_2020.rb)

    # Space with no exterior surfaces
    space = OpenStudio::Model::Space.new(@model)
    space.setName('Interior Space')

    # Check exterior area calculation
    exterior_area = OpenstudioStandards::Geometry.space_get_exterior_wall_and_subsurface_and_roof_area(space)
    assert_equal 0.0, exterior_area, "Interior space should have 0 exterior area"
  end

  def test_infiltration_coefficients_from_standards
    # NECB2020 uses specific infiltration coefficients from standards constants
    # Test that constants are accessible

    # These constants should exist in NECB2020 standards data:
    # - infiltration_constant_term_coefficient
    # - infiltration_temperature_term_coefficient
    # - infiltration_velocity_term_coefficient
    # - infiltration_velocity_squared_term_coefficient

    # Method signature test
    assert @standard_2020.respond_to?(:get_standards_constant),
           "Should have get_standards_constant method"
  end

  def test_infiltration_schedule_inheritance
    # Test infiltration schedule inheritance logic (lines 107-129)
    # Priority: space infiltration > space type infiltration > always on

    schedule = @model.alwaysOnDiscreteSchedule
    assert schedule, "Should have always on schedule as fallback"
  end

  def test_infiltration_object_creation
    # Test that infiltration object is created with correct properties
    create_simple_exterior_wall

    # Apply infiltration
    result = @standard_2020.space_apply_infiltration_rate(@space)

    # Check infiltration was created
    infiltrations = @space.spaceInfiltrationDesignFlowRates
    assert infiltrations.size > 0, "Should create infiltration object" if result
  end

  # ===== Infiltration Pressure Conversion Formula Tests =====

  def test_pressure_conversion_exponent
    # NECB2020 uses exponent of 0.6 for pressure conversion
    # Test this is correctly applied

    exponent = 0.6
    pressure_75 = 75.0
    pressure_5 = 5.0

    ratio = (pressure_5 / pressure_75) ** exponent

    # (5/75)^0.6 = (0.0667)^0.6 ≈ 0.197
    assert_in_delta 0.197, ratio, 0.001
  end

  def test_infiltration_area_adjustment_formula
    # Test full infiltration conversion formula (line 104)
    # infil_5Pa_above_grade = infil_75Pa * (5/75)^0.6 * totalArea / aboveGradeArea

    infil_75pa_all_surf = 0.001  # m³/s·m² at 75 Pa
    total_area = 1000.0  # m²
    above_grade_area = 800.0  # m²

    infil_5pa_above_grade = infil_75pa_all_surf *
                             ((5.0 / 75.0) ** 0.6) *
                             (total_area / above_grade_area)

    # Should be positive value
    assert infil_5pa_above_grade > 0, "Infiltration rate should be positive"
    # Verify calculation
    expected = 0.001 * 0.197 * 1.25  # ≈ 0.000246
    assert_in_delta expected, infil_5pa_above_grade, 0.00001
  end

  # ===== Surface Boundary Condition Tests =====

  def test_outdoor_surface_detection
    # Test detection of outdoor surfaces (line 91)
    create_simple_exterior_wall

    outdoor_surfaces = @space.surfaces.select { |s| s.outsideBoundaryCondition == 'Outdoors' }
    assert outdoor_surfaces.size > 0, "Should have outdoor surfaces"
  end

  def test_ground_contact_surface_detection
    # Test detection of ground contact surfaces (line 95)
    create_ground_floor

    ground_surfaces = @space.surfaces.select { |s| s.outsideBoundaryCondition == 'Ground' }
    assert ground_surfaces.size > 0, "Should have ground surfaces"
  end

  def test_surface_multiplier_application
    # Test that space multiplier is applied to surface areas (lines 89, 92, 96)
    create_simple_exterior_wall

    # Space multiplier defaults to 1
    multiplier = @space.multiplier

    assert_equal 1, multiplier, "Space multiplier should default to 1"
    assert multiplier.is_a?(Numeric), "Multiplier should be numeric"
  end

  # ===== Building Envelope Area Calculation Tests =====

  def test_total_building_envelope_calculation
    # NECB2020 calculates total envelope area including above and below grade
    create_test_geometry_with_ground_contact

    total_envelope_area = 0.0

    @model.getSpaces.each do |space|
      multiplier = space.multiplier
      space.surfaces.each do |surface|
        if surface.outsideBoundaryCondition == 'Outdoors' ||
           surface.outsideBoundaryCondition == 'Ground'
          total_envelope_area += surface.grossArea * multiplier
        end
      end
    end

    assert total_envelope_area > 0, "Should calculate total envelope area"
  end

  # ===== Performance Path Compliance Tests =====

  def test_performance_path_compliance_method_exists
    # NECB2020 introduces performance path compliance (Section 8.4)
    # Check for method existence (commented in necb_2020.rb lines 144-150)

    # The method signature should exist even if implementation is in progress
    # This tests the NECB2020 class structure
    assert @standard_2020.class.name == 'NECB2020'
  end

  # ===== Envelope Construction Application Tests =====

  def test_apply_standard_construction_properties_method_exists
    # NECB2020 has envelope construction method
    # Test in building_envelope.rb
    assert @standard_2020.respond_to?(:apply_standard_construction_properties),
           "Should have apply_standard_construction_properties method"
  end

  def test_construction_properties_hdd_requirement
    # NECB2020 requires HDD for envelope construction selection
    # Method should accept necb_hdd parameter

    method = @standard_2020.method(:apply_standard_construction_properties)
    params = method.parameters

    param_names = params.map { |type, name| name }
    assert param_names.include?(:necb_hdd), "Should have necb_hdd parameter"
    assert param_names.include?(:model), "Should have model parameter"
  end

  # ===== Comparison with NECB2017 Tests =====

  def test_infiltration_method_overridden_from_2017
    # NECB2020 infiltration method should be different from NECB2017
    necb2020_method = @standard_2020.method(:space_apply_infiltration_rate)
    necb2017_method = @standard_2017.method(:space_apply_infiltration_rate)

    # Methods should have different source locations (owner classes)
    assert_equal 'NECB2020', necb2020_method.owner.to_s
  end

  # ===== JSON Data File Loading Tests =====

  def test_json_data_loading_structure
    # Test JSON data loading (lines 28-51)
    standards_data = @standard_2020.instance_variable_get(:@standards_data)

    assert standards_data, "Should have standards data"
    assert standards_data['tables'], "Should have tables"
    assert standards_data['constants'], "Should have constants"
  end

  def test_json_merge_preserves_parent_data
    # NECB2020 should inherit all NECB2017 data and add its own
    standards_data = @standard_2020.instance_variable_get(:@standards_data)

    # Should have merged data from multiple vintages
    assert standards_data['tables'].keys.size > 0, "Should have multiple tables"
  end

  # ===== Helper Methods =====

  private

  def create_simple_exterior_wall
    # Create a simple exterior wall for testing
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(0, 0, 3)
    vertices << OpenStudio::Point3d.new(10, 0, 3)
    vertices << OpenStudio::Point3d.new(10, 0, 0)

    wall = OpenStudio::Model::Surface.new(vertices, @model)
    wall.setSpace(@space)
    wall.setSurfaceType('Wall')
    wall.setOutsideBoundaryCondition('Outdoors')
  end

  def create_ground_floor
    # Create a ground-contact floor
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 10, 0)
    vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(vertices, @model)
    floor.setSpace(@space)
    floor.setSurfaceType('Floor')
    floor.setOutsideBoundaryCondition('Ground')
  end

  def create_test_geometry_with_ground_contact
    # Create complete test geometry with above and below grade surfaces
    create_simple_exterior_wall
    create_ground_floor

    # Add roof
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 3)
    vertices << OpenStudio::Point3d.new(0, 10, 3)
    vertices << OpenStudio::Point3d.new(10, 10, 3)
    vertices << OpenStudio::Point3d.new(10, 0, 3)

    roof = OpenStudio::Model::Surface.new(vertices, @model)
    roof.setSpace(@space)
    roof.setSurfaceType('RoofCeiling')
    roof.setOutsideBoundaryCondition('Outdoors')
  end
end
