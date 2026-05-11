#!/usr/bin/env ruby

# Calculate coverage for test/necb_new tests against lib/openstudio-standards/standards/necb code

require 'simplecov'

SimpleCov.start do
  coverage_dir 'test/necb_new/coverage'

  # Track ONLY the NECB folder
  add_filter do |source_file|
    !source_file.filename.include?('lib/openstudio-standards/standards/necb')
  end

  # Add groups for detailed breakdown
  add_group 'NECB2011', 'lib/openstudio-standards/standards/necb/NECB2011'
  add_group 'NECB2015', 'lib/openstudio-standards/standards/necb/NECB2015'
  add_group 'NECB2017', 'lib/openstudio-standards/standards/necb/NECB2017'
  add_group 'NECB2020', 'lib/openstudio-standards/standards/necb/NECB2020'
  add_group 'NECB Common', 'lib/openstudio-standards/standards/necb/common'
  add_group 'NECB BTAP', 'lib/openstudio-standards/standards/necb/BTAP'
  add_group 'NECB ECMS', 'lib/openstudio-standards/standards/necb/ECMS'

  # Ensure we're filtering test files
  add_filter '/test/'
end

puts "="*80
puts "NECB Coverage Calculation"
puts "="*80
puts "Tests from: /workspaces/openstudio-standards/test/necb_new"
puts "Code tracked: /workspaces/openstudio-standards/lib/openstudio-standards/standards/necb"
puts "="*80
puts ""

# Load test helper
require_relative 'test_helper'

# Load all our passing test files
puts "Loading test files..."
require_relative 'envelope_tests/test_necb_envelope_calculations.rb'
require_relative 'autozone_tests/test_necb_autozone_edge_cases.rb'
require_relative 'core_tests/test_necb_2011_edge_cases.rb'

puts "All tests loaded. Running with coverage tracking..."
puts ""
