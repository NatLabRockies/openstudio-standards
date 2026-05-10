#!/usr/bin/env ruby
# Parallel test runner for NECB new test suite
# Runs all test files in parallel using available CPU cores

require_relative '../helpers/minitest_helper'
require 'parallel'
require 'open3'
require 'fileutils'

class NECBParallelTestRunner
  def initialize
    @test_dir = File.dirname(__FILE__)
    @test_files = Dir.glob(File.join(@test_dir, '*/test_*.rb')).sort
    @output_dir = File.join(@test_dir, 'output', 'parallel_results')
    @start_time = Time.now

    # Use all but one processor to leave system responsive
    @processors = [(Parallel.processor_count - 1), 1].max
  end

  def run
    print_header
    FileUtils.mkdir_p(@output_dir)

    results = run_tests_parallel

    print_results(results)
    save_results(results)

    exit(results.any? { |r| !r[:success] } ? 1 : 0)
  end

  private

  def print_header
    puts "\n" + "=" * 80
    puts "NECB Parallel Test Runner"
    puts "=" * 80
    puts "Test suites:    #{@test_files.size}"
    puts "Processors:     #{@processors} of #{Parallel.processor_count} available"
    puts "Output dir:     #{@output_dir}"
    puts "=" * 80
    puts ""
  end

  def run_tests_parallel
    completed = 0
    mutex = Mutex.new

    Parallel.map(@test_files, in_processes: @processors) do |test_file|
      file_name = File.basename(test_file)

      # Run the test
      start = Time.now
      stdout, stderr, status = Open3.capture3("bundle exec ruby #{test_file}")
      elapsed = Time.now - start

      # Update progress
      mutex.synchronize do
        completed += 1
        status_icon = status.success? ? "✅" : "❌"
        puts "[#{completed}/#{@test_files.size}] #{status_icon} #{file_name} (#{elapsed.round(1)}s)"
      end

      # Parse test counts from output
      test_line = stdout.match(/^(\d+) tests, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips/)

      result = {
        file: file_name,
        path: test_file,
        success: status.success?,
        elapsed: elapsed,
        output: stdout + stderr,
        tests: test_line ? test_line[1].to_i : 0,
        assertions: test_line ? test_line[2].to_i : 0,
        failures: test_line ? test_line[3].to_i : 0,
        errors: test_line ? test_line[4].to_i : 0,
        skips: test_line ? test_line[5].to_i : 0
      }

      # Save individual output
      output_file = File.join(@output_dir, "#{file_name}.txt")
      File.write(output_file, result[:output])

      result
    end
  end

  def print_results(results)
    total_elapsed = Time.now - @start_time

    passed = results.count { |r| r[:success] }
    failed = results.count { |r| !r[:success] }

    total_tests = results.sum { |r| r[:tests] }
    total_assertions = results.sum { |r| r[:assertions] }
    total_failures = results.sum { |r| r[:failures] }
    total_errors = results.sum { |r| r[:errors] }
    total_skips = results.sum { |r| r[:skips] }

    puts "\n" + "=" * 80
    puts "RESULTS"
    puts "=" * 80
    puts "Suites:        #{passed} passed, #{failed} failed (#{results.size} total)"
    puts "Tests:         #{total_tests} (#{total_assertions} assertions)"
    puts "Failures:      #{total_failures}"
    puts "Errors:        #{total_errors}"
    puts "Skips:         #{total_skips}"
    puts "Time:          #{total_elapsed.round(1)}s"
    puts "=" * 80

    if failed > 0
      puts "\nFailed Test Suites:"
      results.select { |r| !r[:success] }.each do |result|
        puts "  ❌ #{result[:file]}"
        puts "     #{result[:failures]} failures, #{result[:errors]} errors"
      end
    end

    # Show slowest tests
    puts "\nSlowest Test Suites (Top 10):"
    results.sort_by { |r| -r[:elapsed] }.first(10).each do |result|
      status = result[:success] ? "✅" : "❌"
      puts "  #{status} #{result[:file].ljust(50)} #{result[:elapsed].round(1)}s"
    end

    puts "\nDetailed results saved to: #{@output_dir}"
    puts "=" * 80
  end

  def save_results(results)
    summary = {
      timestamp: Time.now.iso8601,
      total_suites: results.size,
      passed_suites: results.count { |r| r[:success] },
      failed_suites: results.count { |r| !r[:success] },
      total_tests: results.sum { |r| r[:tests] },
      total_assertions: results.sum { |r| r[:assertions] },
      total_failures: results.sum { |r| r[:failures] },
      total_errors: results.sum { |r| r[:errors] },
      total_skips: results.sum { |r| r[:skips] },
      elapsed_seconds: (Time.now - @start_time).round(2),
      processors_used: @processors,
      results: results.map do |r|
        {
          file: r[:file],
          success: r[:success],
          tests: r[:tests],
          assertions: r[:assertions],
          failures: r[:failures],
          errors: r[:errors],
          skips: r[:skips],
          elapsed: r[:elapsed].round(2)
        }
      end
    }

    File.write(File.join(@output_dir, 'summary.json'), JSON.pretty_generate(summary))
  end
end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME
  NECBParallelTestRunner.new.run
end
