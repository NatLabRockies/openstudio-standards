#!/usr/bin/env ruby

# Run all NECB new tests and generate aggregate coverage report

require_relative 'test_helper'

# Find all test files
test_files = Dir.glob(File.join(__dir__, '**', 'test_*.rb')).reject do |f|
  f.include?('test_helper.rb') || f.include?('run_all_new_tests.rb')
end

puts "Found #{test_files.size} test files"
puts "=" * 80

# Require all test files
test_files.sort.each do |test_file|
  puts "Loading: #{File.basename(test_file)}"
  require test_file
end

puts "=" * 80
puts "All tests loaded. Minitest will now run all tests."
