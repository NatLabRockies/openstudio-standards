require 'parallel_tests'
require 'open3'
require 'minitest'

Minitest.seed = 42

ci_tests_file = File.join(__dir__, 'test', 'ci_tests.txt')
abort("Cannot find #{ci_tests_file}") unless File.exist?(ci_tests_file)

test_files = File.readlines(ci_tests_file)
                 .map(&:strip)
                 .select { |line| line.end_with?('.rb') }
                 .map { |line| File.absolute_path(File.join(__dir__, 'test', line)) }
                 .select { |path| File.exist?(path) }

abort('No valid test files found in ci_tests.txt') if test_files.empty?

# Discover individual test methods from each file
puts "Scanning #{test_files.size} test files for test methods..."
test_methods = []
test_files.each do |test_file|
  # Snapshot all runnable methods on all known subclasses
  before_methods = {}
  Minitest::Test.subclasses.each do |klass|
    before_methods[klass] = Set.new(klass.runnable_methods)
  end

  original_stdout = $stdout
  $stdout = File.open(File::NULL, 'w')
  begin
    require test_file
  ensure
    $stdout.close
    $stdout = original_stdout
  end

  # Find new methods on new or existing classes
  Minitest::Test.subclasses.each do |klass|
    old = before_methods[klass] || Set.new
    (Set.new(klass.runnable_methods) - old).each do |method_name|
      test_methods << [test_file, method_name]
    end
  end
end

abort('No test methods found') if test_methods.empty?

total = test_methods.size
completed = 0
mutex = Mutex.new
failed = []
cpus = ENV.fetch('CPUS', Parallel.processor_count).to_i

puts "Running #{total} test methods from #{test_files.size} files using #{cpus} CPUs"

Parallel.each(test_methods, in_threads: cpus) do |test_file, test_name|
  short_name = test_file.sub(%r{.*/test/}, '')
  result = Open3.capture3('bundle', 'exec', 'ruby', test_file, '-n', test_name)

  mutex.synchronize do
    completed += 1
    remaining = total - completed
    if result[2].success?
      puts "PASSED #{test_name} (#{short_name}) [#{completed}/#{total}, #{remaining} remaining]"
    else
      failed << "#{test_name} (#{short_name})"
      puts "FAILED #{test_name} (#{short_name}) [#{completed}/#{total}, #{remaining} remaining]"
    end
  end
end

if failed.any?
  puts "\n#{failed.size} test(s) failed:"
  failed.each { |f| puts "  #{f}" }
  exit 1
else
  puts "\nAll #{total} tests passed."
end

