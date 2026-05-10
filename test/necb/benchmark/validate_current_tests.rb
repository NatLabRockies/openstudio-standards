#!/usr/bin/env ruby

# Test Validation Script
# Validates that all NECB unit tests pass in their current state before improvements
# This establishes a baseline to ensure we don't break working tests

require 'open3'
require 'json'
require 'fileutils'

puts "="*80
puts "NECB Test Validation"
puts "="*80
puts "Validating all unit tests pass in current state..."
puts ""

# Find all test files in unit_tests/tests directory
test_dir = File.join(__dir__, '../unit_tests/tests')
test_files = Dir.glob(File.join(test_dir, 'test_*.rb')).sort

results = {
  passing: [],
  failing: [],
  errors: {}
}

test_files.each_with_index do |test_path, index|
  test_name = File.basename(test_path, '.rb')
  relative_path = test_path.sub(File.join(__dir__, '../../..'), 'test')

  puts "[#{index + 1}/#{test_files.length}] Validating #{test_name}..."

  # Run test with timeout (some tests can hang)
  stdout, stderr, status = Open3.capture3(
    "timeout 600 bundle exec ruby -I test #{test_path}",
    chdir: File.join(__dir__, '../../..')
  )

  if status.success?
    results[:passing] << test_name
    puts "  ✓ PASS"
  else
    results[:failing] << test_name

    # Store error details
    results[:errors][test_name] = {
      stdout: stdout[-1000..-1] || stdout,  # Last 1000 chars
      stderr: stderr[-1000..-1] || stderr,
      exit_code: status.exitstatus,
      test_path: relative_path
    }

    puts "  ✗ FAIL (exit code: #{status.exitstatus})"

    # Show brief error summary
    if stderr && !stderr.empty?
      error_lines = stderr.split("\n").last(3)
      puts "     Error: #{error_lines.join("\n            ")}"
    end
  end

  puts ""
end

# Save validation results
output_file = File.join(__dir__, 'test_validation.json')
File.write(output_file, JSON.pretty_generate({
  timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
  git_branch: `git branch --show-current`.strip,
  git_commit: `git rev-parse HEAD`.strip,
  total_tests: test_files.length,
  passing: results[:passing].length,
  failing: results[:failing].length,
  passing_tests: results[:passing],
  failing_tests: results[:failing],
  error_details: results[:errors]
}))

# Print summary
puts "="*80
puts "Validation Summary"
puts "="*80
puts "Total tests: #{test_files.length}"
puts "Passing: #{results[:passing].length} (#{(results[:passing].length.to_f / test_files.length * 100).round(1)}%)"
puts "Failing: #{results[:failing].length} (#{(results[:failing].length.to_f / test_files.length * 100).round(1)}%)"
puts ""

if results[:failing].any?
  puts "⚠️  WARNING: Some tests are currently failing!"
  puts ""
  puts "Failing tests:"
  results[:failing].each { |name| puts "  - #{name}" }
  puts ""
  puts "See #{output_file} for full error details."
  puts ""
  puts "These failures should be:"
  puts "  1. Fixed before proceeding with test improvements, OR"
  puts "  2. Documented as known failures and excluded from improvement work"
  exit 1
else
  puts "✓ All tests passing! Safe to proceed with improvements."
  puts ""
  puts "Results saved to: #{output_file}"
  exit 0
end
