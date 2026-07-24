#!/usr/bin/env ruby

require 'fileutils'
require 'open3'
require 'optparse'
require 'parallel'
require 'securerandom'
require 'yaml'

input_folder              = File.join(__dir__, "input/")
copied_input_folder       = File.join(__dir__, "copied-input/")
output_folder             = File.join(__dir__, "output/")
options                   = {}
options[:num_cores]       = (Parallel.processor_count * 4 / 5).floor
options[:input_file_path] = File.join(input_folder, "sample_run_options.yml")
OptionParser.new { |opts|
  opts.on('-f FILE', "Path of the parametric YAML input file") { |file| options[:input_file_path] = file }
  opts.on('-c NUM_CORES', "Number of CPU cores to use")        { |num_cores| options[:num_cores] = num_cores.to_i }
}.parse!

raise ("Cannot find input file: #{options[:input_file_path]}") unless File.exist?(options[:input_file_path])

input_hash   = YAML.load(File.open(options[:input_file_path]).read)
keys         = input_hash[:options].keys
values       = input_hash[:options].values
headers      = input_hash.reject { |k ,v| k == :options }
combinations = values[0].product(*values[1..-1]).map { |combination| headers.merge(Hash[keys.zip(combination)]) }
analysis_output_folder       = File.join(output_folder, input_hash[:analysis_name])
analysis_copied_input_folder = File.join(copied_input_folder, input_hash[:analysis_name])

FileUtils.rm_rf(Dir.glob("#{analysis_output_folder}/*"))       if File.exist?(analysis_output_folder)
FileUtils.rm_rf(Dir.glob("#{analysis_copied_input_folder}/*")) if File.exist?(analysis_copied_input_folder)

for combination in combinations.each
  combination[:datapoint_id] = SecureRandom.uuid
  combination[:datapoint_output_folder] = File.join(analysis_output_folder, combination[:datapoint_id])
  combination[:datapoint_copied_input_folder] = File.join(analysis_copied_input_folder, combination[:datapoint_id])
  run_options_file = File.join(combination[:datapoint_copied_input_folder], "run_options.yml")
  FileUtils.mkdir_p(combination[:datapoint_copied_input_folder])
  File.write(run_options_file, YAML.dump(combination))
end

puts("Parametric Input File: #{options[:input_file_path]}\n" \
     "# Combinations:        #{combinations.length}\n" \
     "# CPU Cores:           #{options[:num_cores]}")

Parallel.each(combinations, in_threads: options[:num_cores], progress: "Progress :") do |combination|
  stdout_and_stderr, status = Open3.capture2e(
    "bundle", "exec", "--gemfile=#{__dir__}/../../Gemfile", "ruby", File.join(__dir__, '../btap_cli/btap_cli.rb'),
    "--input_path", combination[:datapoint_copied_input_folder], "--output_path", analysis_output_folder)

  puts("Datapoint #{combination[:datapoint_id].partition('-')[0]}... #{status.success? ? 'succeeded' : 'failed'}")
  FileUtils.mkdir_p(combination[:datapoint_output_folder])
  File.write(File.join(combination[:datapoint_output_folder], "log.txt"), stdout_and_stderr)
end
