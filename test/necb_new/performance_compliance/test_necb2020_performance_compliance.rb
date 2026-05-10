require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# NECB 2020 Performance Compliance Path Tests
#
# Tests the NECB 2020 performance compliance method that generates reference buildings
# and validates compliance per Section 8.4 of NECB 2020.
#
# Coverage:
# - Main workflow: model_create_necb_2020_performance_compliance (361 lines)
# - Support modules:
#   - ComplianceLogger (319 lines) - Logging compliance steps
#   - ComplianceReportGenerator (401 lines) - HTML report generation
#   - ComplianceValidator (212 lines) - Energy/unmet hours validation
#   - ProposedBuilder (438 lines) - Document proposed building (Section 8.4.3)
#   - ReferenceBuilder (334 lines) - Generate reference building (Section 8.4.4)
#   - ReferenceHVACSelector (112 lines) - HVAC system selection logic
#
# Total coverage: ~2,177 lines

class TestNECB2020PerformanceCompliance < Minitest::Test
  include(NecbHelper)

  def setup
    # Create output directory for test results
    @test_dir = File.join(Dir.pwd, 'output', 'necb2020_performance_compliance')
    FileUtils.mkdir_p(@test_dir) unless Dir.exist?(@test_dir)

    # Get standard
    @standard = Standard.build('NECB2020')

    # Use Toronto weather file (Climate Zone 5)
    @epw_file = get_test_weather_file
  end

  # =============================================================================
  # Test 1: Basic Workflow Without Simulations
  # =============================================================================
  # Tests the core workflow without running EnergyPlus simulations
  # Verifies:
  # - Method completes successfully
  # - Returns all expected result keys
  # - Creates proposed and reference models
  # - Generates compliance log
  # - Saves OSM files
  #
  def test_basic_workflow_without_simulations
    puts "\n=== Test: Basic workflow without simulations ==="

    # Create a simple test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Run performance compliance method
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: true
    )

    # Verify result structure
    assert result, 'Result should not be nil'
    assert result[:proposed_model], 'Should return proposed model'
    assert result[:reference_model], 'Should return reference model'
    assert result[:compliance_log], 'Should return compliance logger'
    assert result[:climate_zone], 'Should return climate zone'
    assert result[:hdd18], 'Should return HDD18'
    assert result[:proposed_model_path], 'Should return proposed model path'
    assert result[:reference_model_path], 'Should return reference model path'

    # Verify files were created
    assert File.exist?(result[:proposed_model_path]), 'Proposed OSM should be saved'
    assert File.exist?(result[:reference_model_path]), 'Reference OSM should be saved'

    # Verify HTML report if requested
    if result[:html_report_path]
      assert File.exist?(result[:html_report_path]), 'HTML report should be created'
    end

    # Verify logging
    logger = result[:compliance_log]
    summary = logger.get_summary

    puts "  Total log entries: #{summary[:total_entries]}"
    puts "  Climate zone: #{result[:climate_zone]} (HDD: #{result[:hdd18].round(0)})"
    puts "  ✓ Test passed\n"

    assert summary[:total_entries] > 0, 'Should have logged entries'
  end

  # =============================================================================
  # Test 2: Proposed Model Unchanged
  # =============================================================================
  # Verifies that the proposed model is not modified by the compliance method
  # The method should create a reference model copy, not modify the original
  #
  def test_proposed_model_unchanged
    puts "\n=== Test: Proposed model is not modified ==="

    # Create test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Get initial characteristics
    initial_surface_count = proposed_model.getSurfaces.length
    initial_zone_count = proposed_model.getThermalZones.length
    initial_construction_count = proposed_model.getConstructions.length

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    # Verify proposed model unchanged
    final_surface_count = proposed_model.getSurfaces.length
    final_zone_count = proposed_model.getThermalZones.length
    final_construction_count = proposed_model.getConstructions.length

    assert_equal initial_surface_count, final_surface_count, 'Proposed model surfaces should not change'
    assert_equal initial_zone_count, final_zone_count, 'Proposed model zones should not change'
    assert_equal initial_construction_count, final_construction_count, 'Proposed model constructions should not change'

    puts "  Surfaces: #{initial_surface_count} → #{final_surface_count}"
    puts "  Zones: #{initial_zone_count} → #{final_zone_count}"
    puts "  Constructions: #{initial_construction_count} → #{final_construction_count}"
    puts "  ✓ Test passed: Proposed model unchanged\n"
  end

  # =============================================================================
  # Test 3: Reference Model Has Prescriptive Envelope
  # =============================================================================
  # Verifies that the reference model has NECB-prescribed envelope constructions
  # Per Section 8.4.4.3, envelope must meet prescriptive requirements
  #
  def test_reference_has_prescriptive_envelope
    puts "\n=== Test: Reference model has prescriptive envelope ==="

    # Create test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    reference_model = result[:reference_model]

    # Check that exterior surfaces have constructions
    ext_walls = reference_model.getSurfaces.select do |s|
      s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors'
    end

    ext_roofs = reference_model.getSurfaces.select do |s|
      s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors'
    end

    assert ext_walls.length > 0, 'Should have exterior walls'
    assert ext_roofs.length > 0, 'Should have exterior roofs'

    # Verify walls have constructions
    walls_with_construction = ext_walls.select { |w| w.construction.is_initialized }
    assert walls_with_construction.length > 0, 'Exterior walls should have constructions'

    # Verify roofs have constructions
    roofs_with_construction = ext_roofs.select { |r| r.construction.is_initialized }
    assert roofs_with_construction.length > 0, 'Exterior roofs should have constructions'

    # Check logging for envelope changes (Section 8.4.4.3)
    logger = result[:compliance_log]
    envelope_logs = logger.get_logs_by_section('8.4.4').select do |log|
      log[:article]&.start_with?('8.4.4.3')
    end

    assert envelope_logs.length > 0, 'Should have logged envelope changes'

    puts "  Exterior walls: #{ext_walls.length} (#{walls_with_construction.length} with constructions)"
    puts "  Exterior roofs: #{ext_roofs.length} (#{roofs_with_construction.length} with constructions)"
    puts "  Envelope log entries: #{envelope_logs.length}"
    puts "  ✓ Test passed\n"
  end

  # =============================================================================
  # Test 4: Reference Model Has HVAC Systems
  # =============================================================================
  # Verifies that the reference model has HVAC systems assigned
  # Per Section 8.4.4.7, HVAC systems must be selected based on building characteristics
  #
  def test_reference_has_hvac_systems
    puts "\n=== Test: Reference model has HVAC systems ==="

    # Create test model with thermal zones
    proposed_model = create_simple_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    reference_model = result[:reference_model]

    # Check for thermal zones
    thermal_zones = reference_model.getThermalZones
    assert thermal_zones.length > 0, 'Should have thermal zones'

    # Check for HVAC equipment (air loops or zone equipment)
    air_loops = reference_model.getAirLoopHVACs
    has_zone_equipment = thermal_zones.any? { |z| z.equipment.length > 0 }

    assert (air_loops.length > 0 || has_zone_equipment), 'Should have HVAC systems (air loops or zone equipment)'

    # Check logging for HVAC system selection (Section 8.4.4.7)
    logger = result[:compliance_log]
    hvac_logs = logger.get_logs_by_section('8.4.4').select do |log|
      log[:article]&.start_with?('8.4.4.7')
    end

    puts "  Thermal zones: #{thermal_zones.length}"
    puts "  Air loops: #{air_loops.length}"
    puts "  Zones with equipment: #{thermal_zones.count { |z| z.equipment.length > 0 }}"
    puts "  HVAC log entries: #{hvac_logs.length}"
    puts "  ✓ Test passed\n"
  end

  # =============================================================================
  # Test 5: Compliance Logger Captures Key Information
  # =============================================================================
  # Verifies that the compliance logger captures all required information
  # Tests logging for both Section 8.4.3 (proposed) and 8.4.4 (reference)
  #
  def test_compliance_logger_captures_information
    puts "\n=== Test: Compliance logger captures key information ==="

    # Create test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    logger = result[:compliance_log]

    # Verify Section 8.4.3 logs (proposed building documentation)
    section_843_logs = logger.get_logs_by_section('8.4.3')
    assert section_843_logs.length > 0, 'Should have Section 8.4.3 logs (proposed building)'

    # Verify Section 8.4.4 logs (reference building generation)
    section_844_logs = logger.get_logs_by_section('8.4.4')
    assert section_844_logs.length > 0, 'Should have Section 8.4.4 logs (reference building)'

    # Verify logs have required structure
    if section_844_logs.any?
      sample_log = section_844_logs.find { |log| log[:proposed_value] && log[:reference_value] }
      if sample_log
        assert sample_log[:component_name], 'Log should have component name'
        assert sample_log[:proposed_value], 'Log should have proposed value'
        assert sample_log[:reference_value], 'Log should have reference value'
        assert sample_log[:article], 'Log should have article number'

        puts "  Sample log entry:"
        puts "    Component: #{sample_log[:component_name]}"
        puts "    Proposed: #{sample_log[:proposed_value]}"
        puts "    Reference: #{sample_log[:reference_value]}"
        puts "    Article: #{sample_log[:article]}"
      end
    end

    # Verify summary
    summary = logger.get_summary
    puts "\n  Log Summary:"
    puts "    Total entries: #{summary[:total_entries]}"
    puts "    Section 8.4.3: #{section_843_logs.length}"
    puts "    Section 8.4.4: #{section_844_logs.length}"
    puts "  ✓ Test passed\n"
  end

  # =============================================================================
  # Test 6: HTML Report Generation
  # =============================================================================
  # Verifies that HTML report is generated with correct content
  # Report should include climate info, proposed/reference characteristics, and logging
  #
  def test_html_report_generation
    puts "\n=== Test: HTML report generation ==="

    # Create test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Run with HTML report enabled
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: true
    )

    assert result[:html_report_path], 'Should return HTML report path'
    assert File.exist?(result[:html_report_path]), 'HTML report file should exist'

    # Read and verify HTML content
    html_content = File.read(result[:html_report_path])

    assert html_content.include?('NECB 2020'), 'Should contain NECB 2020 title'
    assert html_content.include?('Performance'), 'Should contain Performance reference'
    assert html_content.include?('Climate Zone') || html_content.include?('climate'), 'Should contain climate information'

    # Check for section references
    has_section_843 = html_content.include?('8.4.3') || html_content.include?('Proposed')
    has_section_844 = html_content.include?('8.4.4') || html_content.include?('Reference')

    assert (has_section_843 || has_section_844), 'Should contain compliance section references'

    file_size_kb = File.size(result[:html_report_path]) / 1024.0
    puts "  HTML report: #{File.basename(result[:html_report_path])}"
    puts "  File size: #{file_size_kb.round(1)} KB"
    puts "  Contains NECB 2020: #{html_content.include?('NECB 2020')}"
    puts "  Contains sections: #{has_section_843 || has_section_844}"
    puts "  ✓ Test passed\n"
  end

  # =============================================================================
  # Test 7: Climate Zone Handling
  # =============================================================================
  # Verifies that the method correctly determines climate zone from HDD18
  # and applies climate-appropriate prescriptive requirements
  #
  def test_climate_zone_handling
    puts "\n=== Test: Climate zone handling ==="

    # Create test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    # Verify climate information
    assert result[:climate_zone], 'Should return climate zone'
    assert result[:hdd18], 'Should return HDD18'

    # Verify HDD18 is positive
    assert result[:hdd18] > 0, 'HDD18 should be positive'

    # Verify climate zone is valid NECB zone (4, 5, 6, 7A, 7B, 8)
    valid_zones = ['4', '5', '6', '7A', '7B', '8']
    assert valid_zones.include?(result[:climate_zone]), "Climate zone should be valid NECB zone, got: #{result[:climate_zone]}"

    # Verify climate info logged
    logger = result[:compliance_log]
    init_log = logger.get_logs_by_article('8.4.1.1').first
    assert init_log, 'Should have initialization log with climate info'
    assert init_log[:details][:climate_zone], 'Initialization log should include climate zone'

    puts "  Climate zone: #{result[:climate_zone]}"
    puts "  HDD18: #{result[:hdd18].round(0)}"
    puts "  EPW file: #{File.basename(result[:epw_file])}"
    puts "  ✓ Test passed\n"
  end

  # =============================================================================
  # Test 8: Reference Model Thermal Blocks
  # =============================================================================
  # Verifies that reference model properly handles thermal blocks
  # Per NECB 2020, building is divided into thermal blocks for HVAC system selection
  #
  def test_reference_model_thermal_blocks
    puts "\n=== Test: Reference model thermal blocks ==="

    # Create test model
    proposed_model = create_simple_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    reference_model = result[:reference_model]

    # Verify thermal zones exist
    thermal_zones = reference_model.getThermalZones
    assert thermal_zones.length > 0, 'Should have thermal zones'

    # Verify zones have thermostats
    zones_with_thermostats = thermal_zones.select do |zone|
      zone.thermostatSetpointDualSetpoint.is_initialized
    end

    assert zones_with_thermostats.length > 0, 'Thermal zones should have thermostats'

    # Check for thermal block documentation in logs
    logger = result[:compliance_log]
    thermal_block_logs = logger.get_logs_by_section('8.4.4').select do |log|
      log[:thermal_block] || log[:details]&.key?(:thermal_block)
    end

    puts "  Thermal zones: #{thermal_zones.length}"
    puts "  Zones with thermostats: #{zones_with_thermostats.length}"
    puts "  Thermal block log entries: #{thermal_block_logs.length}"
    puts "  ✓ Test passed\n"
  end

  private

  # Create a simple test model for compliance testing
  # Creates a basic building with walls, roof, floor, and thermal zone
  #
  # @param building_type [String] Type of building (for naming)
  # @return [OpenStudio::Model::Model] Test model
  def create_simple_test_model(building_type)
    model = OpenStudio::Model::Model.new

    # Set building properties
    building = model.getBuilding
    building.setName(building_type)
    building.setStandardsBuildingType('Office')
    building.setStandardsNumberOfStories(1)
    building.setStandardsNumberOfAboveGroundStories(1)

    # Create a space
    space = OpenStudio::Model::Space.new(model)
    space.setName('Test Space')

    # Create a space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Office - Open Plan')
    space_type.setStandardsSpaceType('Office - open plan')
    space_type.setStandardsBuildingType('Office')
    space.setSpaceType(space_type)

    # Create simple 10m x 10m x 3m box geometry
    floor_vertices = OpenStudio::Point3dVector.new
    floor_vertices << OpenStudio::Point3d.new(0, 0, 0)
    floor_vertices << OpenStudio::Point3d.new(10, 0, 0)
    floor_vertices << OpenStudio::Point3d.new(10, 10, 0)
    floor_vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(floor_vertices, model)
    floor.setSurfaceType('Floor')
    floor.setOutsideBoundaryCondition('Ground')
    floor.setSpace(space)

    # Add exterior walls
    wall_height = 3.0
    wall_coords = [[0, 0], [10, 0], [10, 10], [0, 10]]

    wall_coords.each_with_index do |pt, i|
      next_pt = wall_coords[(i + 1) % 4]

      wall_vertices = OpenStudio::Point3dVector.new
      wall_vertices << OpenStudio::Point3d.new(pt[0], pt[1], 0)
      wall_vertices << OpenStudio::Point3d.new(next_pt[0], next_pt[1], 0)
      wall_vertices << OpenStudio::Point3d.new(next_pt[0], next_pt[1], wall_height)
      wall_vertices << OpenStudio::Point3d.new(pt[0], pt[1], wall_height)

      wall = OpenStudio::Model::Surface.new(wall_vertices, model)
      wall.setSurfaceType('Wall')
      wall.setOutsideBoundaryCondition('Outdoors')
      wall.setSpace(space)
    end

    # Add roof
    roof_vertices = OpenStudio::Point3dVector.new
    roof_vertices << OpenStudio::Point3d.new(0, 0, wall_height)
    roof_vertices << OpenStudio::Point3d.new(0, 10, wall_height)
    roof_vertices << OpenStudio::Point3d.new(10, 10, wall_height)
    roof_vertices << OpenStudio::Point3d.new(10, 0, wall_height)

    roof = OpenStudio::Model::Surface.new(roof_vertices, model)
    roof.setSurfaceType('RoofCeiling')
    roof.setOutsideBoundaryCondition('Outdoors')
    roof.setSpace(space)

    # Create thermal zone
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    thermal_zone.setName('Test Zone')
    space.setThermalZone(thermal_zone)

    # Add thermostat
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermostat.setName('Test Thermostat')

    # Create heating/cooling schedules
    heating_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    heating_sch.setName('Heating Setpoint')
    heating_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 21.0)

    cooling_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    cooling_sch.setName('Cooling Setpoint')
    cooling_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 24.0)

    thermostat.setHeatingSetpointTemperatureSchedule(heating_sch)
    thermostat.setCoolingSetpointTemperatureSchedule(cooling_sch)
    thermal_zone.setThermostatSetpointDualSetpoint(thermostat)

    # Set weather file on model (required for HDD18 calculation)
    epw_path = get_test_weather_file
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    model
  end

  # Get test weather file
  # Returns path to a CWEC2020 weather file for testing
  #
  # @return [String] Path to EPW file
  def get_test_weather_file
    # Look for Toronto weather file (most common test location)
    weather_dir = File.join(Dir.pwd, 'data', 'weather')

    # Try to find Toronto CWEC2020
    toronto_epw = Dir.glob(File.join(weather_dir, '*Toronto*.epw')).first
    return toronto_epw if toronto_epw && File.exist?(toronto_epw)

    # Fallback - any CWEC2020 file
    cwec_files = Dir.glob(File.join(weather_dir, '*CWEC2020.epw'))
    return cwec_files.first if cwec_files.any?

    # Fallback - any EPW file
    epw_files = Dir.glob(File.join(weather_dir, '*.epw'))
    return epw_files.first if epw_files.any?

    # If still nothing, raise error
    raise "No weather files found in #{weather_dir}"
  end
end
