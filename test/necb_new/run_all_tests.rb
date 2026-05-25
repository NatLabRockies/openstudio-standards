#!/usr/bin/env ruby

# Consolidated NECB New Test Runner
# Runs all tests with options for parallel execution and code coverage

require 'optparse'
require 'fileutils'
require 'etc'

# Auto-detect optimal worker count: CPU count - 2, but cap at 16 because
# EnergyPlus sizing runs each use 200-500 MB of RAM; ~70 parallel EP processes
# can exhaust a 32 GB host and cause flaky "Optional not initialized" errors
# (the SQL file fails to be written when the EP child OOM-dies). 16 keeps
# memory pressure manageable while still parallelizing the suite ~10x.
cpu_count = Etc.nprocessors
default_workers = [[cpu_count - 2, 1].max, 16].min

# Parse options
options = {
  coverage: true,
  workers: default_workers
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby run_all_tests.rb [options]"

  opts.on("-c", "--[no-]coverage", "Enable/disable code coverage (default: enabled)") do |c|
    options[:coverage] = c
  end

  opts.on("-w", "--workers N", Integer, "Number of parallel workers (default: CPU-2, currently #{default_workers})") do |n|
    options[:workers] = n
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Find all test files
base_dir = File.dirname(__FILE__)
test_files = Dir.glob(File.join(base_dir, '**', 'test_*.rb'))
  .reject { |f| f.include?('_backup') }
  .reject { |f| f.include?('test_helper') }
  .reject { |f| f.include?('run_all') }
  .sort

puts "=" * 80
puts "NECB New Test Suite Runner"
puts "=" * 80
puts "CPUs:        #{cpu_count} (using #{options[:workers]} workers)"
puts "Mode:        Parallel"
puts "Coverage:    #{options[:coverage] ? "Enabled" : "Disabled"}"
puts "Test files:  #{test_files.size}"
puts "=" * 80
puts

# PARALLEL MODE
# Enable SimpleCov if requested (results will be merged at the end)
if options[:coverage]
  ENV.delete('DISABLE_SIMPLECOV')
else
  ENV['DISABLE_SIMPLECOV'] = 'true'
end

# Create temp dir for outputs
  tmp_dir = "/tmp/necb_tests_#{$$}"
  FileUtils.mkdir_p(tmp_dir)

  puts "Running tests in parallel..."
  puts

  # Throttled parallel pool: spawn at most options[:workers] processes at a
  # time. Without a cap, ~70 EnergyPlus sizing runs spawn simultaneously and
  # exhaust system RAM, causing flaky "Optional not initialized" failures.
  pids = {}
  in_flight = {}

  spawn_one = ->(test_file) {
    test_name = File.basename(test_file, '.rb')
    output_file = "#{tmp_dir}/#{test_name}.txt"
    pid = Process.spawn(
      "bundle exec ruby #{test_file}",
      chdir: File.dirname(__FILE__) + '/../..',
      out: output_file,
      err: output_file
    )
    info = { pid: pid, output_file: output_file, test_file: test_file, test_name: test_name, exit_status: nil }
    pids[test_name] = info
    in_flight[pid] = info
  }

  test_queue = test_files.dup
  options[:workers].times { spawn_one.call(test_queue.shift) if test_queue.any? }

  puts "Started parallel test pool with #{options[:workers]} workers (#{test_files.size} files queued)..."
  puts

  # Drain: as each process exits, capture its exit status and queue the next
  until in_flight.empty?
    finished_pid, status = Process.wait2
    info = in_flight.delete(finished_pid)
    info[:exit_status] = status.exitstatus if info
    spawn_one.call(test_queue.shift) if test_queue.any?
  end

  test_results = {}
  pids.each do |test_name, info|
    exit_status = info[:exit_status]

    output = File.read(info[:output_file]) rescue ""
    # Strip ANSI color codes before parsing so the summary regex works on
    # Minitest's colorized output ("\e[31m0 failures\e[0m").
    plain = output.gsub(/\e\[\d+(?:;\d+)*m/, '')

    # Parse test time
    if plain =~ /Finished in ([\d.]+)s/
      time = $1.to_f
    else
      time = 0
    end

    # Parse test results
    if plain =~ /(\d+) tests?, (\d+) assertions?, (\d+) failures?, (\d+) errors?,?\s*(\d+)?\s*skips?/
      tests, assertions, failures, errors, skips = $1.to_i, $2.to_i, $3.to_i, $4.to_i, ($5 || 0).to_i
    else
      tests = assertions = failures = errors = skips = 0
    end

    test_results[test_name] = {
      time: time,
      tests: tests,
      assertions: assertions,
      failures: failures,
      errors: errors,
      skips: skips,
      exit_status: exit_status,
      passed: (exit_status == 0 || exit_status == 2) && failures == 0 && errors == 0
    }
  end

  # Sort by time (longest first)
  sorted_results = test_results.sort_by { |_, d| -d[:time] }

  # Calculate totals
  total_tests = total_assertions = total_failures = total_errors = total_skips = 0
  total_time = 0
  failed_tests = []

  sorted_results.each do |name, d|
    total_tests += d[:tests]
    total_assertions += d[:assertions]
    total_failures += d[:failures]
    total_errors += d[:errors]
    total_skips += d[:skips]
    total_time += d[:time]
    failed_tests << name unless d[:passed]
  end

  # Print detailed results table
  puts "=" * 110
  puts "RESULTS (sorted by time - longest first)"
  puts "=" * 110
  printf "%-60s %8s %6s %6s %6s %6s %6s %10s\n",
    "Test File", "Time(s)", "Tests", "Assert", "Fail", "Error", "Skip", "Status"
  puts "-" * 110

  sorted_results.each do |name, d|
    status = d[:passed] ? "PASS" : "FAIL"
    color = d[:passed] ? "\e[32m" : "\e[31m"

    printf "%-60s %8.1f %6d %6d %6d %6d %6d %s%10s\e[0m\n",
      name[0..59], d[:time], d[:tests], d[:assertions],
      d[:failures], d[:errors], d[:skips], color, status
  end

  puts "-" * 110
  printf "%-60s %8.1f %6d %6d %6d %6d %6d\n",
    "TOTAL", total_time, total_tests, total_assertions,
    total_failures, total_errors, total_skips
  puts "=" * 110

  # Calculate wall clock time (longest test)
  wall_time = sorted_results.first&.last&.fetch(:time, 0) || 0

  puts
  puts "Wall clock time (parallel): #{wall_time.round(1)}s"
  puts "Sequential time would be:   #{total_time.round(1)}s"
  puts "Speedup factor:             #{wall_time > 0 ? (total_time / wall_time).round(1) : 0}x"
  puts

  passing = total_tests - total_failures - total_errors - total_skips
  pass_rate = total_tests > 0 ? (passing.to_f / total_tests * 100) : 0

  puts "=" * 110
  puts "SUMMARY"
  puts "=" * 110
  puts "Total tests:      #{total_tests}"
  puts "Assertions:       #{total_assertions}"
  puts "Failures:         #{total_failures}"
  puts "Errors:           #{total_errors}"
  puts "Skips:            #{total_skips}"
  puts "Passing:          #{passing} (#{pass_rate.round(1)}%)"
  puts "=" * 110

  if total_failures == 0 && total_errors == 0
    puts "✅ ALL TESTS PASSING!"
  else
    puts "⚠️  #{total_failures + total_errors} tests need attention"
  end

  if failed_tests.any?
    puts
    puts "\e[31mFailed tests:\e[0m"
    failed_tests.each { |t| puts "  - #{t}" }
  end

  # Merge coverage results if coverage was enabled
  if options[:coverage]
    puts
    puts "=" * 80
    puts "MERGING COVERAGE RESULTS"
    puts "=" * 80

    require 'simplecov'

    coverage_path = 'test/necb_new/coverage'
    resultset_file = File.join(coverage_path, '.resultset.json')

    if File.exist?(resultset_file)
      puts "Loading coverage results from: #{resultset_file}"

      # Configure SimpleCov for report generation only (no tracking)
      SimpleCov.coverage_dir coverage_path
      SimpleCov.add_group 'NECB2011', 'lib/openstudio-standards/standards/necb/NECB2011'
      SimpleCov.add_group 'NECB2015', 'lib/openstudio-standards/standards/necb/NECB2015'
      SimpleCov.add_group 'NECB2017', 'lib/openstudio-standards/standards/necb/NECB2017'
      SimpleCov.add_group 'NECB2020', 'lib/openstudio-standards/standards/necb/NECB2020'
      SimpleCov.add_group 'NECB Common', 'lib/openstudio-standards/standards/necb/common'
      SimpleCov.add_group 'NECB ECMS', 'lib/openstudio-standards/standards/necb/ECMS'
      SimpleCov.add_group 'NECB BTAP1980-2010', 'lib/openstudio-standards/standards/necb/BTAP1980TO2010'
      SimpleCov.add_group 'NECB BTAP Pre-1980', 'lib/openstudio-standards/standards/necb/BTAPPRE1980'

      # Only include files in /standards/necb/ folder
      SimpleCov.add_filter do |source_file|
        !source_file.filename.include?('/standards/necb/')
      end
      SimpleCov.merge_timeout 3600

      # Read all stored results from .resultset.json and merge them into a
      # single SimpleCov::Result. from_hash returns an Array; store_result
      # expects a single Result — so we use ResultMerger.merged_result which
      # reads the resultset file directly and combines every command_name.
      merged = SimpleCov::ResultMerger.merged_result
      if merged.nil?
        puts "⚠️  Resultset was empty or all entries timed out"
      else
        merged.format!
      end

      # Print coverage summary
      if merged
        total_lines = merged.total_lines
        covered_lines = merged.covered_lines
        coverage_pct = total_lines > 0 ? (covered_lines.to_f / total_lines * 100).round(2) : 0
        puts "Line Coverage: #{coverage_pct}% (#{covered_lines} / #{total_lines})"
        puts "✅ Coverage report generated at: #{coverage_path}/index.html"
      end
    else
      puts "⚠️  No coverage results found at #{resultset_file}"
    end
    puts "=" * 80
  end

  # Cleanup
  FileUtils.rm_rf(tmp_dir)

  exit_code = (total_failures > 0 || total_errors > 0) ? 1 : 0
  exit exit_code
