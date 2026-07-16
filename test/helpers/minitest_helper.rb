require_relative 'coverage_helper'

$LOAD_PATH.unshift File.expand_path('../../../lib', __FILE__)

require 'minitest/autorun'

if ENV['CI'] == 'true'
  require 'minitest/ci'
  puts "Saving test results to #{Minitest::Ci.report_dir}"
end
require 'minitest/reporters'
require 'minitest/reporters/base_reporter'
require 'minitest/reporters/spec_reporter'

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'json'
require 'fileutils'

# Test category support for selective test execution
# Usage: TEST_CATEGORY=pure_unit ruby test/necb/unit_tests/tests/test_*.rb
module TestCategories
  # Pure unit tests - no OpenStudio simulations, fast execution
  def self.pure_unit?
    ENV['TEST_CATEGORY'] == 'pure_unit' || ENV['TEST_CATEGORY'].nil?
  end

  # Component unit tests - may use fixtures, but no new sizing runs
  def self.component_unit?
    ENV['TEST_CATEGORY'] == 'component_unit' || ENV['TEST_CATEGORY'].nil?
  end

  # Integration tests - may require sizing runs
  def self.integration?
    ENV['TEST_CATEGORY'] == 'integration' || ENV['TEST_CATEGORY'] == 'all'
  end

  # Regression tests - full building simulations
  def self.regression?
    ENV['TEST_CATEGORY'] == 'regression' || ENV['TEST_CATEGORY'] == 'all'
  end

  # Helper to skip test based on category
  # Usage in test: skip "Integration test" unless TestCategories.integration?
  def self.skip_unless(category)
    case category
    when :pure_unit
      return if pure_unit?
    when :component_unit
      return if component_unit?
    when :integration
      return if integration?
    when :regression
      return if regression?
    end
    "Skipped - TEST_CATEGORY=#{ENV['TEST_CATEGORY'] || 'default'} does not include #{category}"
  end
end

# Require local version instead of installed version for developers
begin
  require_relative '../../lib/openstudio-standards.rb'
  puts 'DEVELOPERS OF OPENSTUDIO-STANDARDS: Requiring code directly instead of using installed gem.  This avoids having to run rake install every time you make a change.'
rescue LoadError
  require 'openstudio-standards'
  puts 'Using installed openstudio-standards gem.'
end

# Set the output reporting format based on the run environment
if ENV['RM_INFO'] || ENV['TEAMCITY_RAKE_RUNNER_MODE'] # RubyMine
  puts "Running tests from RubyMine, using RubyMine test reporter."
  ENV.delete('RM_INFO') # Delete this environment variable because it forces use of only RubyMineReporter
  Minitest::Reporters.use! [Minitest::Reporters::RubyMineReporter.new]
  # line below for PNNL local testing
  # Minitest::Reporters.use! [Minitest::Reporters::RubyMineReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir="test/reports", empty=false)]
elsif ENV['JENKINS_HOME'] # Jenkins
  puts "Running tests from Jenkins, using JUnit XML test reporter and console-based test reporter."
  Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir = "test/reports", empty = false)]
else # Terminal or other
  puts "Running tests from terminal, using console-based test reporter."
  Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]
  # line below for PNNL local testing
  # Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir="test/reports", empty=false)]
end
