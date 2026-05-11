#!/usr/bin/env ruby

# Test Helper for NECB New Test Suite
# Provides SimpleCov coverage tracking for new tests

# Configure SimpleCov for new test suite (unless disabled for parallel execution)
unless ENV['DISABLE_SIMPLECOV'] == 'true'
  require 'simplecov'
  SimpleCov.start do
  # Coverage output directory
  coverage_dir 'test/necb_new/coverage'

  # Track only NECB implementation code
  add_group 'NECB2011', 'lib/openstudio-standards/standards/necb/NECB2011'
  add_group 'NECB2015', 'lib/openstudio-standards/standards/necb/NECB2015'
  add_group 'NECB2017', 'lib/openstudio-standards/standards/necb/NECB2017'
  add_group 'NECB2020', 'lib/openstudio-standards/standards/necb/NECB2020'
  add_group 'NECB Common', 'lib/openstudio-standards/standards/necb/common'
  add_group 'NECB ECMS', 'lib/openstudio-standards/standards/necb/ECMS'
  add_group 'Component Standards', 'lib/openstudio-standards/standards/Standards.*'

  # Don't track test code, data, docs
  add_filter '/test/'
  add_filter '/data/'
  add_filter '/doc/'
  add_filter '/docs/'
  add_filter '/pkg/'
  add_filter '/hvac_sizing/'
  add_filter 'version'

    # Minimum coverage thresholds (optional - will warn if not met)
    minimum_coverage 70      # Overall
    minimum_coverage_by_file 50  # Per file
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

# Load NECB-specific helpers
require_relative 'fixtures/necb_fixture_manager'

puts "✅ NECB New Test Suite loaded with coverage tracking"
