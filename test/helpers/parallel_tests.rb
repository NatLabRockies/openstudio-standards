require_relative './minitest_helper'
require 'fileutils'
require 'parallel'
require 'open3'

ProcessorsUsed = (Parallel.processor_count - 1).floor
$totalTestCount = 0
$completedTestCount = 0
$completedMutex = Mutex.new

class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def blue
    colorize(34)
  end

  def pink
    colorize(35)
  end

  def light_blue
    colorize(36)
  end
end

def write_results(result, test_file, test_name)
  test_file_output = File.join(@test_output_folder, "#{File.basename(test_file)}_#{test_name}_test_output.json")
  File.delete(test_file_output) if File.exist?(test_file_output)
  test_result = false
  $completedMutex.synchronize {$completedTestCount += 1}
  if result[2].success?
    puts "PASSED (#{$completedTestCount}/#{$totalTestCount}): #{test_name} IN FILE #{test_file.gsub(/.*\/test\//, 'test/')}".green
    return true
  else
    #store output for failed run.
    output = {"test_file" => test_file,
              "test_name" => test_name,
              "test_result" => test_result,
              "output" => {
                  "status" => result[2],
                  "std_out" => result[0].split(/\r?\n/),
                  "std_err" => result[1].split(/\r?\n/)
              }
    }

    #puts test_file_output
    File.open(test_file_output, 'w') {|f| f.write(JSON.pretty_generate(output))}
    puts "FAILED (#{$completedTestCount}/#{$totalTestCount}): #{test_name} IN FILE #{test_file.gsub(/.*\/test\//, 'test/')}".red
    return false
  end
end

class ParallelTests

  def run(file_list, test_output_folder, processors = nil)
    processors = ProcessorsUsed if processors.nil?
    did_all_tests_pass = true
    @test_output_folder = test_output_folder
    @full_file_list = nil
    FileUtils.rm_rf(@test_output_folder)
    FileUtils.mkpath(@test_output_folder)

    # load test files from file.
    @full_file_list = file_list.shuffle

    # Parallelize all individual tests within the files
    # Since some files contain programatically generated tests
    # we can't simply search the text for def test_foo
    # but instead must load the file and inspect the objects.
    # However, to keep minitest/autorun from actually running
    # the tests at this time, we need to temporarily disable it.
    test_files_and_test_names = []
    test_files_already_checked = []
    @full_file_list.each do |test_file|

      # Disable minitest/autorun
      eval('module Minitest @@installed_at_exit = true end')

      # Load the test file
      require test_file

      # Find the test method names
      ObjectSpace.each_object(Class) do |klass|
        next if test_files_already_checked.include?(klass.name) # Skip files already checked
        next if klass.name.to_s == 'RunAllTests' # Don't want this to run recursively
        klass.ancestors.each do |ancestor|
          next unless ancestor.name == 'Minitest::Test'
          next if klass.to_s.include?('Minitest') # Skip classes from the Minitest library itself
          test_files_already_checked << klass.name
          # puts "*** Test file is: #{klass}"
          # puts "  ancestor is: #{ancestor.name}"
          klass.runnable_methods.each do |test_name|
            # puts "  #{test_name}"
            test_files_and_test_names << [test_file, test_name]
          end
        end
      end

      # Re-enable minitest/autorun
      eval('module Minitest @@installed_at_exit = false end')
    end

    $totalTestCount = test_files_and_test_names.size
    puts "Running #{test_files_and_test_names.size} tests from #{@full_file_list.size} tests suites in parallel using #{processors} of #{Parallel.processor_count} available cpus."
    puts "To increase or decrease the ProcessorsUsed, please edit the test/helpers/parallel_tests.rb file."
    timings_json = Hash.new()
    Parallel.each(test_files_and_test_names, in_threads: (processors),progress: "Progress :") do |test_file_test_name|
      test_file = test_file_test_name[0]
      file_name = test_file.gsub(/^.+(openstudio-standards\/test\/)/, '')
      test_name = test_file_test_name[1]
      timings_json[file_name.to_s] = {}
      timings_json[file_name.to_s]['start'] = Time.now.to_i
      did_all_tests_pass = false unless write_results(Open3.capture3('bundle', 'exec', "ruby '#{test_file}' -n '#{test_name}'"), test_file, test_name)
      timings_json[file_name.to_s]['end'] = Time.now.to_i
      timings_json[file_name.to_s]['time'] = timings_json[file_name.to_s]['end'] - timings_json[file_name.to_s]['start']
    end

    #Sometimes the runs fail.
    #Load failed JSON files from folder local_test_output
    unless did_all_tests_pass
      did_all_tests_pass = true
      failed_runs = []
      files = Dir.glob("#{@test_output_folder}/*.json").select {|e| File.file? e}
      files.each do |file|
        data = JSON.parse(File.read(file))
        failed_runs << [data["test_file"], data['test_name']]
      end
      $totalTestCount = failed_runs.size
      puts "Some tests failed the first time. This may have been due to computer performance issues. Rerunning failed tests..."
      Parallel.each(failed_runs, in_threads: (processors), progress: "Progress :") do |test_file_test_name|
        test_file = test_file_test_name[0]
        file_name = test_file.gsub(/^.+(openstudio-standards\/test\/)/, '')
        test_name = test_file_test_name[1]
        timings_json[file_name.to_s] = {}
        timings_json[file_name.to_s]['start'] = Time.now.to_i
        did_all_tests_pass = false unless write_results(Open3.capture3('bundle', 'exec', "ruby '#{test_file}' -n '#{test_name}'"), test_file, test_name)
        timings_json[file_name.to_s]['end'] = Time.now.to_i
        timings_json[file_name.to_s]['time'] = timings_json[file_name.to_s]['end'] - timings_json[file_name.to_s]['start']
      end
    end
    # Before saving the file, sort tests by the total time.
    timings_json = Hash[ timings_json.sort_by { |k, v| v['time'] } ]
    # Get rid of start and end
    timings_json.each do |file_name, data|
      data.delete('start')
      data.delete('end')
    end
    File.open(File.join(File.dirname(__FILE__), 'ci_test_helper', 'timings.json'), 'w') {|file| file.puts(JSON.pretty_generate(timings_json))}
    return did_all_tests_pass
  end
end
