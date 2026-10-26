require 'optparse'
require_relative '../../lib/openstudio-standards'

@options  = {}
@options[:output_folder]  = File.join(__dir__, 'output')

OptionParser.new { |opts|
  opts.banner = "Usage: #{$0} -s NAME id ..."
  opts.on('--help', 'Display this screen') do
    puts opts
    exit
  end
  opts.on('--output_path NAME', "Default is #{@options[:output_folder]} ") { |s| @options[:output_folder] = s }
}.parse!

BTAP::NoSimAnalysis.new(
  model_path:    @options[:output_folder] + "/output.osm",
  sql_file_path: @options[:output_folder] + "/run_dir/run/eplusout.sql",
  output_folder: @options[:output_folder],
  datapoint_id:  'test_run').run_costing
