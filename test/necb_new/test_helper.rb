#!/usr/bin/env ruby

# Test Helper for NECB New Test Suite
# Provides SimpleCov coverage tracking for new tests

# Configure SimpleCov for new test suite (unless disabled for parallel execution)
unless ENV['DISABLE_SIMPLECOV'] == 'true'
  require 'simplecov'
  # Distinct command_name per process so parallel test subprocesses do not
  # overwrite each other's entry in .resultset.json. ResultMerger reads every
  # named entry and combines them when generating the final report.
  test_label = ENV['SIMPLECOV_COMMAND_NAME'] ||
               ($0 ? File.basename($0, '.rb') : "necb_new")
  SimpleCov.command_name "#{test_label}-#{Process.pid}"
  SimpleCov.start do
    # Coverage output directory
    coverage_dir 'test/necb_new/coverage'

    # Track only NECB implementation code in /lib/openstudio-standards/standards/necb/
    add_group 'NECB2011', 'lib/openstudio-standards/standards/necb/NECB2011'
    add_group 'NECB2015', 'lib/openstudio-standards/standards/necb/NECB2015'
    add_group 'NECB2017', 'lib/openstudio-standards/standards/necb/NECB2017'
    add_group 'NECB2020', 'lib/openstudio-standards/standards/necb/NECB2020'
    add_group 'NECB Common', 'lib/openstudio-standards/standards/necb/common'
    add_group 'NECB ECMS', 'lib/openstudio-standards/standards/necb/ECMS'
    add_group 'NECB BTAP1980-2010', 'lib/openstudio-standards/standards/necb/BTAP1980TO2010'
    add_group 'NECB BTAP Pre-1980', 'lib/openstudio-standards/standards/necb/BTAPPRE1980'

    # Only include files in /standards/necb/ folder - filter out everything else
    add_filter do |source_file|
      !source_file.filename.include?('/standards/necb/')
    end

    # Keep results around for 1 hour so parallel runs all combine on merge.
    merge_timeout 3600

    # Coverage thresholds are only meaningful on the *merged* result; do not
    # enforce them inside individual subprocesses (each one would otherwise
    # exit non-zero and the parallel runner would treat that as a test
    # failure even though all tests passed).
  end

  # Use HTML formatter locally, Codecov in CI
  if ENV['CI'] == 'true'
    require 'codecov'
    SimpleCov.formatter = SimpleCov::Formatter::Codecov
  else
    SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
    puts "📊 Coverage report will be generated at: test/necb_new/coverage/index.html"
  end
end

# Load standard test helpers
require_relative '../helpers/minitest_helper'
require_relative '../helpers/necb_helper'

# Load NECB-specific helpers
require_relative 'fixtures/necb_fixture_manager'

puts "✅ NECB New Test Suite loaded with coverage tracking"
