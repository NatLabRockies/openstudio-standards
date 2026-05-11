#!/usr/bin/env ruby

# Run all passing new tests and generate coverage report

require 'simplecov'

SimpleCov.start do
  coverage_dir 'test/necb_new/coverage'

  # Track only NECB implementation code
  add_group 'NECB2011', 'lib/openstudio-standards/standards/necb/NECB2011'
  add_group 'NECB Common', 'lib/openstudio-standards/standards/necb/common'

  # Filter out test code
  add_filter '/test/'
end

# Load test helper
require_relative 'test_helper'

# Load all passing test files
require_relative 'envelope_tests/test_necb_envelope_calculations.rb'
require_relative 'autozone_tests/test_necb_autozone_edge_cases.rb'
require_relative 'core_tests/test_necb_2011_edge_cases.rb'

puts "\n" + "="*80
puts "All tests loaded. Running with coverage tracking..."
puts "="*80
