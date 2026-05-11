require 'fileutils'
require 'parallel'
require 'open3'

TestOutputFolder = File.join(File.dirname(__FILE__), 'local_test_output')
ProcessorsUsed = (Parallel.processor_count * 4 / 5).floor
#ProcessorsUsed = 20

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


def write_results(result, test_file)
  test_file_output = File.join(TestOutputFolder, "#{File.basename(test_file)}_test_output.json")
  File.delete(test_file_output) if File.exist?(test_file_output)
  test_result = false
  if result[2].success?
    puts "PASSED: #{test_file}".green
    return true
  else
    #store output for failed run.
    output = {"test" => test_file,
              "test_result" => test_result,
              "output" => {
                  "status" => result[2],
                  "std_out" => result[0].split(/\r?\n/),
                  "std_err" => result[1].split(/\r?\n/)
              }
    }

    #puts test_file_output
    File.open(test_file_output, 'w') {|f| f.write(JSON.pretty_generate(output))}
    puts "FAILED: #{test_file_output}".red
    return false
  end
end

class ParallelTests

  def run(file_list)
    did_all_tests_pass = true

    @full_file_list = nil
    FileUtils.rm_rf(TestOutputFolder)
    FileUtils.mkpath(TestOutputFolder)

    # load test files from file.
    @full_file_list = file_list.shuffle

    puts "Running #{@full_file_list.size} tests suites in parallel using #{ProcessorsUsed} of available cpus."
    puts "To increase or decrease the ProcessorsUsed, please edit the test/test_run_all_locally.rb file."
    timings_json = Hash.new()
    Parallel.each_with_index(@full_file_list, in_threads: (ProcessorsUsed), progress: "Progress :") do |test_file, index|
      file_name = test_file.gsub(/^.+(openstudio-standards\/test\/)/, '')
      timings_json[file_name.to_s] = {}
      timings_json[file_name.to_s]['start'] = Time.now.to_i
      did_all_tests_pass = false unless write_results(Open3.capture3("bundle exec ruby #{test_file}"), test_file)
      timings_json[file_name.to_s]['end'] = Time.now.to_i
      timings_json[file_name.to_s]['total'] = timings_json[file_name.to_s]['end'] - timings_json[file_name.to_s]['start']
    end

    return did_all_tests_pass
  end
end
