#!/usr/bin/env ruby

# Run all NECB tests sequentially with SimpleCov coverage tracking
# This is slower than parallel execution but provides accurate coverage data

require 'fileutils'

# Test directories to run (ordered by importance)
test_dirs = [
  'test/necb_new/service_water_heating_tests',
  'test/necb_new/hvac_base_tests',
  'test/necb_new/hvac_base_complete_tests',
  'test/necb_new/core_tests',
  'test/necb_new/envelope_tests',
  'test/necb_new/hvac_systems_1_4_tests',
  'test/necb_new/autozone_tests',
  'test/necb_new/lighting_tests',
  'test/necb_new/qaqc_tests',
  'test/necb_new/system_fuels_tests'
]

puts "="*80
puts "Running NECB Test Suite with SimpleCov Coverage"
puts "="*80
puts "Started: #{Time.now}"
puts

# Build command to run all test files
test_files = []
test_dirs.each do |dir|
  if Dir.exist?(dir)
    files = Dir.glob("#{dir}/*.rb").sort
    test_files.concat(files)
    puts "Found #{files.length} test files in #{File.basename(dir)}"
  end
end

puts
puts "Total test files: #{test_files.length}"
puts

# Run all tests in a single Ruby process to merge coverage
# This ensures SimpleCov tracks coverage across all test files
cmd = "bundle exec ruby -I test #{test_files.join(' ')}"

puts "Running tests..."
puts
system(cmd)

puts
puts "="*80
puts "Test run complete: #{Time.now}"
puts "Coverage report: test/necb_new/coverage/index.html"
puts "="*80
