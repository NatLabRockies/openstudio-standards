#!/usr/bin/env ruby
require 'benchmark'
require 'json'

# Get all system test files
test_files = Dir.glob(File.join(File.dirname(__FILE__), 'test_system_*.rb')).sort

puts "=" * 70
puts "Running #{test_files.size} HVAC System Tests in Parallel"
puts "=" * 70
puts

# Run tests in parallel using Process.spawn
results = {}
pids = {}

test_files.each do |test_file|
  test_name = File.basename(test_file, '.rb')
  output_file = "/tmp/#{test_name}_output.txt"
  time_file = "/tmp/#{test_name}_time.txt"
  
  # Run with timing
  pid = Process.spawn(
    "bash -c 'TIMEFORMAT=\"%R\"; time bundle exec ruby #{test_file} 2>&1' > #{output_file} 2>#{time_file}",
    chdir: '/workspaces/openstudio-standards'
  )
  pids[test_name] = { pid: pid, output_file: output_file, time_file: time_file, test_file: test_file }
end

puts "Started #{pids.size} test processes..."
puts

# Wait for all to complete and collect results
pids.each do |test_name, info|
  Process.wait(info[:pid])
  exit_status = $?.exitstatus
  
  output = File.read(info[:output_file]) rescue ""
  time_output = File.read(info[:time_file]).strip rescue "0"
  
  # Parse time (last line should be the real time)
  elapsed = time_output.split("\n").last.to_f rescue 0
  
  # Parse test results from output
  if output =~ /(\d+) tests?, (\d+) assertions?, (\d+) failures?, (\d+) errors?,?\s*(\d+)?\s*skips?/
    tests = $1.to_i
    assertions = $2.to_i
    failures = $3.to_i
    errors = $4.to_i
    skips = $5.to_i rescue 0
  else
    tests = assertions = failures = errors = skips = 0
  end
  
  results[test_name] = {
    elapsed: elapsed,
    tests: tests,
    assertions: assertions,
    failures: failures,
    errors: errors,
    skips: skips,
    exit_status: exit_status,
    passed: (failures == 0 && errors == 0)
  }
end

# Sort by elapsed time
sorted = results.sort_by { |name, data| -data[:elapsed] }

# Print results table
puts "=" * 90
puts "Test Results (sorted by time)"
puts "=" * 90
printf "%-45s %8s %6s %6s %6s %6s %8s\n", "Test File", "Time(s)", "Tests", "Assert", "Fail", "Skip", "Status"
puts "-" * 90

total_time = 0
total_tests = 0
total_assertions = 0
total_failures = 0
total_skips = 0

sorted.each do |test_name, data|
  status = data[:passed] ? "PASS" : "FAIL"
  status_color = data[:passed] ? "\e[32m" : "\e[31m"
  
  printf "%-45s %8.1f %6d %6d %6d %6d %s%8s\e[0m\n",
    test_name,
    data[:elapsed],
    data[:tests],
    data[:assertions],
    data[:failures],
    data[:skips],
    status_color,
    status
  
  total_time += data[:elapsed]
  total_tests += data[:tests]
  total_assertions += data[:assertions]
  total_failures += data[:failures]
  total_skips += data[:skips]
end

puts "-" * 90
printf "%-45s %8.1f %6d %6d %6d %6d\n", "TOTAL", total_time, total_tests, total_assertions, total_failures, total_skips
puts "=" * 90

# Calculate wall clock time
wall_time = sorted.map { |_, d| d[:elapsed] }.max
puts
puts "Wall clock time (parallel): #{wall_time.round(1)}s"
puts "Sequential time would be:   #{total_time.round(1)}s"
puts "Speedup factor:             #{(total_time / wall_time).round(1)}x" if wall_time > 0

# Save results to JSON
File.write('/tmp/hvac_test_results.json', JSON.pretty_generate({
  timestamp: Time.now.iso8601,
  total_tests: total_tests,
  total_assertions: total_assertions,
  total_failures: total_failures,
  total_skips: total_skips,
  wall_time: wall_time,
  sequential_time: total_time,
  results: results
}))

puts
puts "Results saved to /tmp/hvac_test_results.json"
