#!/usr/bin/env ruby
# frozen_string_literal: true

# NECB 2020 Performance Path Compliance - Usage Example
#
# This script demonstrates how to use the new NECB 2020 Performance Path
# compliance method to generate reference buildings and compliance reports.

require 'openstudio'
require_relative 'lib/openstudio-standards'

# ============================================================================
# BASIC USAGE - Generate Reference Building without Simulations
# ============================================================================

def example_basic_usage
  puts "\n=== Example 1: Basic Usage (No Simulations) ===\n"

  # 1. Load your proposed building model
  proposed_model_path = 'path/to/your/proposed_building.osm'
  proposed_model = BTAP::FileIO.load_osm(proposed_model_path)

  # 2. Create NECB2020 standard instance
  standard = Standard.build('NECB2020')

  # 3. Run performance compliance
  result = standard.model_create_necb_2020_performance_compliance(
    proposed_model: proposed_model,
    epw_file: 'data/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    output_dir: './output/necb_performance_compliance',
    run_simulations: false,  # Don't run EnergyPlus (fast)
    html_report: true        # Generate HTML report
  )

  # 4. Access results
  puts "Climate Zone: #{result[:climate_zone]} (HDD: #{result[:hdd18].round(0)})"
  puts "Reference Model: #{result[:reference_model_path]}"
  puts "HTML Report: #{result[:html_report_path]}"

  # 5. Check logging
  logger = result[:compliance_log]
  summary = logger.get_summary
  puts "\nLogging Summary:"
  puts "  Total entries: #{summary[:total_entries]}"
  puts "  Section 8.4.3 (Proposed): #{logger.get_logs_by_section('8.4.3').length}"
  puts "  Section 8.4.4 (Reference): #{logger.get_logs_by_section('8.4.4').length}"
  puts "  Passed: #{summary[:passed]}, Failed: #{summary[:failed]}"

  result
end

# ============================================================================
# ADVANCED USAGE - With EnergyPlus Simulations and Compliance Validation
# ============================================================================

def example_with_simulations
  puts "\n=== Example 2: With Simulations (Full Compliance Check) ===\n"

  # Load proposed model
  proposed_model = BTAP::FileIO.load_osm('path/to/your/proposed_building.osm')

  # Create standard
  standard = Standard.build('NECB2020')

  # Run with simulations (this will take longer)
  result = standard.model_create_necb_2020_performance_compliance(
    proposed_model: proposed_model,
    epw_file: 'data/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    output_dir: './output/necb_performance_compliance',
    sizing_run_dir: './output/sizing_runs',
    run_simulations: true,   # Run EnergyPlus simulations
    html_report: true
  )

  # Check compliance results
  if result[:compliance_result]
    compliance = result[:compliance_result]

    puts "\nCompliance Results:"
    puts "  Overall: #{compliance[:compliant] ? 'PASS ✓' : 'FAIL ✗'}"

    # Annual energy
    annual_energy = compliance[:annual_energy]
    puts "\n  Annual Energy Consumption:"
    puts "    Proposed: #{annual_energy[:proposed_energy_gj]} GJ"
    puts "    Building Energy Target: #{annual_energy[:building_energy_target_gj]} GJ"
    puts "    Margin: #{annual_energy[:margin_gj]} GJ (#{annual_energy[:margin_percent]}%)"
    puts "    Status: #{annual_energy[:passed] ? 'PASS ✓' : 'FAIL ✗'}"

    # Unmet hours
    heating = compliance[:unmet_heating_hours]
    puts "\n  Heating Unmet Hours:"
    puts "    Proposed: #{heating[:proposed_hours]} hours"
    puts "    Reference: #{heating[:reference_hours]} hours"
    puts "    Status: #{heating[:passed] ? 'PASS ✓' : 'FAIL ✗'}"

    cooling = compliance[:unmet_cooling_hours]
    puts "\n  Cooling Unmet Hours:"
    puts "    Proposed: #{cooling[:proposed_hours]} hours"
    puts "    Reference: #{cooling[:reference_hours]} hours"
    puts "    Difference: #{cooling[:difference_percent]}%"
    puts "    Status: #{cooling[:passed] ? 'PASS ✓' : 'FAIL ✗'}"
  end

  result
end

# ============================================================================
# INSPECTING DETAILED LOGS - Article-by-Article
# ============================================================================

def example_inspect_logs(result)
  puts "\n=== Example 3: Inspecting Detailed Logs ===\n"

  logger = result[:compliance_log]

  # Get envelope changes (Section 8.4.4.3)
  puts "\nEnvelope Changes (Article 8.4.4.3):"
  envelope_logs = logger.get_logs_by_section('8.4.4').select do |log|
    log[:article]&.start_with?('8.4.4.3') &&
      log[:proposed_value] && log[:reference_value]
  end

  envelope_logs.first(5).each do |log|
    puts "\n  Component: #{log[:component_name]}"
    puts "    Proposed: #{log[:proposed_value]} #{log[:units]}"
    puts "    Reference: #{log[:reference_value]} #{log[:units]}"
    puts "    Change: #{log[:change_percent]}%"
    puts "    Code: #{log[:code_reference]}"
  end

  # Get HVAC system selections (Section 8.4.4.7)
  puts "\nHVAC System Selections (Article 8.4.4.7):"
  hvac_logs = logger.get_logs_by_section('8.4.4').select do |log|
    log[:article]&.start_with?('8.4.4.7')
  end

  hvac_logs.each do |log|
    if log[:system_name]
      puts "\n  Thermal Block: #{log[:thermal_block]}"
      puts "    System: #{log[:system_name]}"
      puts "    Building Type: #{log[:building_type]}"
      puts "    Stories: #{log[:num_stories]}"
    end
  end

  # Get all Section 8.4.3 (proposed) logs
  puts "\nProposed Building Characteristics (Section 8.4.3):"
  proposed_logs = logger.get_logs_by_section('8.4.3')
  proposed_logs.group_by { |log| log[:article] }.each do |article, logs|
    puts "\n  #{article}: #{logs.first[:action]}"
    if logs.first[:details]
      logs.first[:details].each do |key, value|
        puts "    #{key}: #{value}"
      end
    end
  end
end

# ============================================================================
# ACCESSING REFERENCE MODEL FOR FURTHER ANALYSIS
# ============================================================================

def example_reference_model_analysis(result)
  puts "\n=== Example 4: Analyzing Reference Model ===\n"

  reference_model = result[:reference_model]

  # Analyze envelope
  walls = reference_model.getSurfaces.select do |s|
    s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors'
  end

  puts "Reference Building Analysis:"
  puts "  Exterior Walls: #{walls.length}"

  if !walls.empty? && walls.first.construction.is_initialized
    u_factor = walls.first.construction.get.uFactor
    puts "  Wall U-Factor: #{u_factor.get.round(3)} W/(m²·K)" if u_factor.is_initialized
  end

  # Analyze HVAC
  air_loops = reference_model.getAirLoopHVACs
  thermal_zones = reference_model.getThermalZones

  puts "  Air Loops: #{air_loops.length}"
  puts "  Thermal Zones: #{thermal_zones.length}"

  air_loops.each do |air_loop|
    puts "    - #{air_loop.nameString}"
  end

  # Analyze lighting
  total_lighting_power = 0.0
  total_floor_area = 0.0

  reference_model.getSpaces.each do |space|
    total_floor_area += space.floorArea
    space.lights.each do |light|
      power = light.getLightingPower(space.floorArea, space.numberOfPeople)
      total_lighting_power += power
    end
  end

  lpd = total_floor_area > 0 ? (total_lighting_power / total_floor_area).round(2) : 0.0
  puts "  Lighting Power Density: #{lpd} W/m²"
end

# ============================================================================
# BATCH PROCESSING MULTIPLE BUILDINGS
# ============================================================================

def example_batch_processing
  puts "\n=== Example 5: Batch Processing Multiple Buildings ===\n"

  # List of building models to process
  building_models = [
    { name: 'Office Building A', path: 'models/office_a.osm', epw: 'weather/toronto.epw' },
    { name: 'Office Building B', path: 'models/office_b.osm', epw: 'weather/toronto.epw' },
    { name: 'Retail Store', path: 'models/retail.osm', epw: 'weather/vancouver.epw' }
  ]

  standard = Standard.build('NECB2020')
  results = []

  building_models.each do |building|
    puts "\nProcessing: #{building[:name]}"

    # Load model
    model = BTAP::FileIO.load_osm(building[:path])

    # Run compliance
    result = standard.model_create_necb_2020_performance_compliance(
      proposed_model: model,
      epw_file: building[:epw],
      output_dir: "./output/#{building[:name].gsub(' ', '_').downcase}",
      run_simulations: false,
      html_report: true
    )

    # Store results
    results << {
      name: building[:name],
      climate_zone: result[:climate_zone],
      reference_model: result[:reference_model_path],
      report: result[:html_report_path]
    }

    puts "  ✓ Complete - Report: #{result[:html_report_path]}"
  end

  # Summary
  puts "\n\nBatch Processing Summary:"
  results.each do |res|
    puts "  #{res[:name]}: Zone #{res[:climate_zone]}"
    puts "    Report: #{res[:report]}"
  end
end

# ============================================================================
# MAIN - Run Examples
# ============================================================================

if __FILE__ == $PROGRAM_NAME
  puts "\n" + ('=' * 80)
  puts 'NECB 2020 Performance Path Compliance - Usage Examples'
  puts '=' * 80

  # NOTE: These examples assume you have:
  # 1. A proposed building OSM file
  # 2. An appropriate weather file (EPW)
  # 3. OpenStudio and openstudio-standards properly installed

  puts "\nTo run these examples:"
  puts "1. Update the file paths to your actual OSM and EPW files"
  puts "2. Run: ruby #{__FILE__}"
  puts "\nFor now, showing example code structure..."

  # Uncomment to run actual examples:
  # result = example_basic_usage
  # result = example_with_simulations
  # example_inspect_logs(result)
  # example_reference_model_analysis(result)
  # example_batch_processing

  puts "\n" + ('=' * 80)
end
