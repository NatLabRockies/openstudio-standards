#!/usr/bin/env ruby

# TODO: NLR's parallel test helper class
# `test/helpers/parallel_tests.rb`:ParallelTests needs to be renamed to not
# conflict with `simplecov`'s assumptions since it overrwrites the class
# with the same name in the parralel tests gem. Coverage will not work until
# then, but one can temporarily rename the class without pushing to remote as
# a workaround.

# Test Helper for NECB New Test Suite
# Provides SimpleCov coverage tracking for new tests

# Configure SimpleCov for new test suite (unless disabled for parallel execution)
if ENV['ENABLE_SIMPLECOV'] == 'true'
  require 'simplecov'

  # Distinct command_name per process so parallel test subprocesses do not
  # overwrite each other's entry in .resultset.json. ResultMerger reads every
  # named entry and combines them when generating the final report.
  test_label   = ENV['SIMPLECOV_COMMAND_NAME'] || ($0 ? File.basename($0, '.rb') : "necb_new")
  coverage_dir = 'test/necb_new/coverage'
  SimpleCov.command_name "#{test_label}-#{Process.pid}"
  SimpleCov.start do
    # Coverage output directory
    coverage_dir coverage_dir

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
  SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
  puts "Coverage report will be generated at: #{coverage_dir}/index.html"
end

require_relative '../helpers/minitest_helper'
require_relative '../helpers/necb_helper'
