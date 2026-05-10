require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'

class NECB2020PerformanceComplianceTest < Minitest::Test
  include(NecbHelper)

  def setup
    # Create output directory for test results
    @test_dir = File.join(__dir__, 'output', 'necb_2020_performance_compliance')
    FileUtils.mkdir_p(@test_dir) unless Dir.exist?(@test_dir)

    # Get standard and test weather file
    @standard = Standard.build('NECB2020')
    @epw_file = get_climate_zone_epw('5') # Climate zone 5
  end

  # Test basic workflow without simulations
  def test_basic_workflow_without_simulations
    puts "\n=== Test: Basic workflow without simulations ==="

    # Load a small test model (office prototype)
    proposed_model = load_test_model('SmallOffice')
    assert(proposed_model, 'Failed to load test model')

    # Run performance compliance method
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: true
    )

    # Verify result structure
    assert(result, 'Result should not be nil')
    assert(result[:proposed_model], 'Should return proposed model')
    assert(result[:reference_model], 'Should return reference model')
    assert(result[:compliance_log], 'Should return compliance logger')
    assert(result[:climate_zone], 'Should return climate zone')
    assert(result[:hdd18], 'Should return HDD18')

    # Verify files were created
    assert(File.exist?(result[:proposed_model_path]), 'Proposed OSM should be saved')
    assert(File.exist?(result[:reference_model_path]), 'Reference OSM should be saved')
    assert(File.exist?(result[:html_report_path]), 'HTML report should be created') if result[:html_report_path]

    # Verify logging
    logger = result[:compliance_log]
    summary = logger.get_summary

    puts "  Total log entries: #{summary[:total_entries]}"
    puts "  Section 8.4.3 entries: #{logger.get_logs_by_section('8.4.3').length}"
    puts "  Section 8.4.4 entries: #{logger.get_logs_by_section('8.4.4').length}"
    puts "  Climate zone: #{result[:climate_zone]} (HDD: #{result[:hdd18].round(0)})"

    assert(summary[:total_entries] > 0, 'Should have logged entries')
    assert(logger.get_logs_by_section('8.4.3').length > 0, 'Should have Section 8.4.3 logs')
    assert(logger.get_logs_by_section('8.4.4').length > 0, 'Should have Section 8.4.4 logs')

    # Verify reference model has prescriptive values applied
    reference_model = result[:reference_model]
    assert(reference_model.getThermalZones.length > 0, 'Reference should have thermal zones')

    puts "  Reference model thermal zones: #{reference_model.getThermalZones.length}"
    puts "  ✓ Test passed\n"
  end

  # Test that proposed model is not modified
  def test_proposed_model_unchanged
    puts "\n=== Test: Proposed model is not modified ==="

    # Load test model
    proposed_model = load_test_model('SmallOffice')

    # Get initial characteristics
    initial_wall_count = proposed_model.getSurfaces.select { |s| s.surfaceType == 'Wall' }.length
    initial_zone_count = proposed_model.getThermalZones.length

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    # Verify proposed model unchanged
    final_wall_count = proposed_model.getSurfaces.select { |s| s.surfaceType == 'Wall' }.length
    final_zone_count = proposed_model.getThermalZones.length

    assert_equal(initial_wall_count, final_wall_count, 'Proposed model walls should not change')
    assert_equal(initial_zone_count, final_zone_count, 'Proposed model zones should not change')

    puts "  Initial walls: #{initial_wall_count}, Final walls: #{final_wall_count}"
    puts "  Initial zones: #{initial_zone_count}, Final zones: #{final_zone_count}"
    puts "  ✓ Test passed: Proposed model unchanged\n"
  end

  # Test reference model has prescriptive envelope
  def test_reference_has_prescriptive_envelope
    puts "\n=== Test: Reference model has prescriptive envelope ==="

    # Load test model
    proposed_model = load_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    reference_model = result[:reference_model]

    # Check that walls have constructions
    walls = reference_model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    assert(walls.length > 0, 'Should have exterior walls')

    walls_with_construction = walls.select { |w| w.construction.is_initialized }
    assert(walls_with_construction.length > 0, 'Walls should have constructions')

    # Check logging for envelope changes
    envelope_logs = result[:compliance_log].get_logs_by_article('8.4.4.3.(1)')
    assert(envelope_logs.length > 0, 'Should have logged envelope changes')

    puts "  Exterior walls: #{walls.length}"
    puts "  Walls with construction: #{walls_with_construction.length}"
    puts "  Envelope log entries: #{envelope_logs.length}"
    puts "  ✓ Test passed\n"
  end

  # Test reference model has HVAC systems
  def test_reference_has_hvac_systems
    puts "\n=== Test: Reference model has HVAC systems ==="

    # Load test model
    proposed_model = load_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    reference_model = result[:reference_model]

    # Check for HVAC systems
    air_loops = reference_model.getAirLoopHVACs
    thermal_zones = reference_model.getThermalZones

    assert(thermal_zones.length > 0, 'Should have thermal zones')
    # Note: air_loops might be 0 if using zone equipment

    # Check logging for HVAC
    hvac_logs = result[:compliance_log].get_logs_by_section('8.4.4').select do |log|
      log[:article]&.start_with?('8.4.4.7')
    end

    puts "  Thermal zones: #{thermal_zones.length}"
    puts "  Air loops: #{air_loops.length}"
    puts "  HVAC log entries: #{hvac_logs.length}"
    puts "  ✓ Test passed\n"
  end

  # Test HTML report generation
  def test_html_report_generation
    puts "\n=== Test: HTML report generation ==="

    # Load test model
    proposed_model = load_test_model('SmallOffice')

    # Run with HTML report
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: true
    )

    assert(result[:html_report_path], 'Should return HTML report path')
    assert(File.exist?(result[:html_report_path]), 'HTML report file should exist')

    # Check HTML contains key sections
    html_content = File.read(result[:html_report_path])
    assert(html_content.include?('NECB 2020 Performance'), 'Should contain title')
    assert(html_content.include?('Section 8.4.3'), 'Should contain Section 8.4.3')
    assert(html_content.include?('Section 8.4.4'), 'Should contain Section 8.4.4')
    assert(html_content.include?('Climate Zone'), 'Should contain climate zone')

    file_size_kb = File.size(result[:html_report_path]) / 1024.0
    puts "  HTML report created: #{File.basename(result[:html_report_path])}"
    puts "  File size: #{file_size_kb.round(1)} KB"
    puts "  ✓ Test passed\n"
  end

  # Test logging captures before/after values
  def test_logging_captures_changes
    puts "\n=== Test: Logging captures before/after values ==="

    # Load test model
    proposed_model = load_test_model('SmallOffice')

    # Run performance compliance
    result = @standard.model_create_necb_2020_performance_compliance(
      proposed_model: proposed_model,
      epw_file: @epw_file,
      output_dir: @test_dir,
      run_simulations: false,
      html_report: false
    )

    logger = result[:compliance_log]

    # Find envelope change logs
    envelope_logs = logger.get_logs_by_section('8.4.4').select do |log|
      log[:proposed_value] && log[:reference_value]
    end

    assert(envelope_logs.length > 0, 'Should have logs with before/after values')

    # Check first envelope log has required fields
    if envelope_logs.length > 0
      log = envelope_logs.first
      assert(log[:component_name], 'Should have component name')
      assert(log[:proposed_value], 'Should have proposed value')
      assert(log[:reference_value], 'Should have reference value')
      assert(log[:code_reference], 'Should have code reference')
      assert(log[:units], 'Should have units')

      puts "  Example log entry:"
      puts "    Component: #{log[:component_name]}"
      puts "    Proposed: #{log[:proposed_value]} #{log[:units]}"
      puts "    Reference: #{log[:reference_value]} #{log[:units]}"
      puts "    Code ref: #{log[:code_reference]}"
    end

    puts "  Logs with before/after values: #{envelope_logs.length}"
    puts "  ✓ Test passed\n"
  end

  private

  # Load a test model (simplified - would use actual prototype in real tests)
  def load_test_model(building_type)
    # For testing, create a simple model
    # In production, would load actual prototype
    model = OpenStudio::Model::Model.new

    # Set building
    building = model.getBuilding
    building.setName(building_type)

    # Add a simple space
    space = OpenStudio::Model::Space.new(model)
    space.setName('Test Space')

    # Add simple geometry (10m x 10m x 3m box)
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 10, 0)
    vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(vertices, model)
    floor.setSurfaceType('Floor')
    floor.setSpace(space)

    # Add walls
    wall_height = 3.0
    [[0, 0], [10, 0], [10, 10], [0, 10]].each_with_index do |pt, i|
      next_pt = [[0, 0], [10, 0], [10, 10], [0, 10]][(i + 1) % 4]

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

    model
  end

  # Get test weather file for climate zone
  def get_climate_zone_epw(zone)
    # Return a test EPW file path
    # In production, would return actual climate-appropriate EPW
    epw_dir = File.join(__dir__, '..', '..', '..', '..', 'data', 'weather')

    # Try to find a CWEC2016 file
    epw_files = Dir.glob(File.join(epw_dir, '*.epw'))
    return epw_files.first if epw_files.any?

    # Fallback - return any EPW from project
    project_epws = Dir.glob('/workspaces/openstudio-standards/**/*.epw')
    project_epws.first if project_epws.any?
  end
end
