#!/usr/bin/env ruby

# Fixture Generation Script
# Pre-generates common NECB fixtures to avoid repeated sizing runs in tests
#
# This script creates a library of pre-sized models covering the most common
# combinations of:
# - NECB templates (2011, 2015, 2017, 2020)
# - Building types (Office, Retail, School, Restaurant, etc.)
# - Climate zones (representative EPW files)
# - System types (1-8)
#
# Generated fixtures are stored in /test/necb/fixtures/sized_models/ and
# can be reused by multiple tests via NecbFixtureManager.

require_relative '../../helpers/necb_fixture_manager'
require_relative '../../helpers/necb_helper'
require 'parallel'

puts "="*80
puts "NECB Fixture Generation"
puts "="*80
puts ""

# Configuration for fixtures to generate
FIXTURE_CONFIGS = []

# Common NECB templates
templates = [
  'NECB2011',
  'NECB2015',
  'NECB2017',
  'NECB2020'
]

# Common building types (from test_necb_activities.rb analysis)
building_types = [
  'SmallOffice',
  'MediumOffice',
  'LargeOffice',
  'FullServiceRestaurant',
  'QuickServiceRestaurant',
  'RetailStandalone',
  'PrimarySchool',
  'SecondarySchool',
  'SmallHotel',
  'LargeHotel',
  'Warehouse',
  'Hospital',
  'Outpatient'
]

# Representative EPW files for different climate zones
epw_files = [
  'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw',        # Zone 7A (cold, dry)
  'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',        # Zone 6A (cold, humid)
  'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',      # Zone 5A (cool, marine)
  'CAN_QC_Montreal-Trudeau.Intl.AP.716270_CWEC2020.epw' # Zone 6A (cold, humid)
]

# NECB system types (1-8 are standard NECB systems)
system_types = [
  nil,  # No HVAC (for envelope/loads testing)
  1,    # PTAC with electric coil
  2,    # Multi-zone VAV with electric reheat
  3,    # FCU with electric heating, gas cooling
  4,    # Multi-zone VAV with gas heat, gas cooling
  5,    # Packaged rooftop VAV with electric heat
  6,    # Packaged rooftop VAV with gas heat
  7,    # VAV with PFP boxes
  8     # VAV with fan powered boxes, reheat
]

# Generate fixture configurations
# Strategy: Generate a subset that covers common test cases
puts "Generating fixture configuration list..."

# 1. All building types with NECB2011 + Toronto + System 2 (most common in tests)
building_types.each do |building_type|
  FIXTURE_CONFIGS << {
    template: 'NECB2011',
    building_type: building_type,
    epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    system_type: 2
  }
end

# 2. SmallOffice across all templates + Toronto + System 2 (template variations)
templates.each do |template|
  FIXTURE_CONFIGS << {
    template: template,
    building_type: 'SmallOffice',
    epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    system_type: 2
  }
end

# 3. SmallOffice + NECB2011 + Toronto across system types (system variations)
system_types.each do |system_type|
  FIXTURE_CONFIGS << {
    template: 'NECB2011',
    building_type: 'SmallOffice',
    epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    system_type: system_type
  }
end

# 4. SmallOffice + NECB2011 + System 2 across climate zones (climate variations)
epw_files.each do |epw_file|
  FIXTURE_CONFIGS << {
    template: 'NECB2011',
    building_type: 'SmallOffice',
    epw_file: epw_file,
    system_type: 2
  }
end

# Remove duplicates (some configs are created multiple times)
FIXTURE_CONFIGS.uniq!

puts "Total fixtures to generate: #{FIXTURE_CONFIGS.length}"
puts ""

# Option parsing
require 'optparse'

options = {
  parallel: true,
  force: false,
  dry_run: false,
  workers: [Parallel.processor_count, 4].min  # Max 4 workers to avoid overwhelming system
}

OptionParser.new do |opts|
  opts.banner = "Usage: generate_fixtures.rb [options]"

  opts.on("--sequential", "Generate fixtures sequentially (default: parallel)") do
    options[:parallel] = false
  end

  opts.on("--force", "Regenerate all fixtures even if they exist") do
    options[:force] = true
  end

  opts.on("--dry-run", "Show what would be generated without actually creating fixtures") do
    options[:dry_run] = true
  end

  opts.on("--workers N", Integer, "Number of parallel workers (default: #{options[:workers]})") do |n|
    options[:workers] = n
  end

  opts.on("--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Clear existing fixtures if --force
if options[:force] && !options[:dry_run]
  puts "Clearing all existing fixtures..."
  NecbFixtureManager.clear_all_fixtures
  puts ""
end

# Dry run mode
if options[:dry_run]
  puts "DRY RUN MODE - No fixtures will be created"
  puts ""
  FIXTURE_CONFIGS.each_with_index do |config, index|
    fixture_key = NecbFixtureManager.send(:generate_fixture_key, config)
    puts "[#{index + 1}/#{FIXTURE_CONFIGS.length}] Would generate: #{fixture_key}"
  end
  puts ""
  puts "Total: #{FIXTURE_CONFIGS.length} fixtures"
  exit 0
end

# Generation function
def generate_fixture(config, index, total)
  fixture_key = NecbFixtureManager.send(:generate_fixture_key, config)

  puts "[#{index + 1}/#{total}] Generating: #{fixture_key}"

  begin
    start_time = Time.now

    model = NecbFixtureManager.get_or_create_sized_model(
      template: config[:template],
      building_type: config[:building_type],
      epw_file: config[:epw_file],
      system_type: config[:system_type]
    )

    elapsed = Time.now - start_time

    if model
      puts "  Success (#{elapsed.round(1)}s)"
      return { success: true, config: config, time: elapsed }
    else
      puts "  Failed to generate model"
      return { success: false, config: config, error: "Model creation returned nil" }
    end

  rescue StandardError => e
    puts "  Error: #{e.message}"
    return { success: false, config: config, error: e.message }
  end
end

# Generate fixtures
results = []
start_time = Time.now

if options[:parallel]
  puts "Generating fixtures in parallel (#{options[:workers]} workers)..."
  puts ""

  results = Parallel.map_with_index(FIXTURE_CONFIGS, in_processes: options[:workers]) do |config, index|
    generate_fixture(config, index, FIXTURE_CONFIGS.length)
  end
else
  puts "Generating fixtures sequentially..."
  puts ""

  FIXTURE_CONFIGS.each_with_index do |config, index|
    results << generate_fixture(config, index, FIXTURE_CONFIGS.length)
  end
end

elapsed_total = Time.now - start_time

# Summary
puts ""
puts "="*80
puts "Generation Summary"
puts "="*80

successful = results.count { |r| r[:success] }
failed = results.count { |r| !r[:success] }

puts "Total fixtures: #{results.length}"
puts "Successful: #{successful}"
puts "Failed: #{failed}"
puts "Total time: #{elapsed_total.round(1)}s"

if successful > 0
  avg_time = results.select { |r| r[:success] }.map { |r| r[:time] }.sum / successful
  puts "Average time per fixture: #{avg_time.round(1)}s"
end

if failed > 0
  puts ""
  puts "Failed fixtures:"
  results.select { |r| !r[:success] }.each do |result|
    config = result[:config]
    puts "  - #{config[:template]} #{config[:building_type]} #{config[:system_type]}"
    puts "    Error: #{result[:error]}"
  end
end

puts ""
puts "Fixture statistics:"
stats = NecbFixtureManager.fixture_stats
puts "  Total fixtures: #{stats[:total_fixtures]}"
puts "  Total size: #{stats[:total_size_mb]} MB"
puts "  By template: #{stats[:by_template].inspect}"
puts "  By building type: #{stats[:by_building_type].inspect}"

exit(failed > 0 ? 1 : 0)
