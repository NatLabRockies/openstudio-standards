require 'pathname'
require 'fileutils'

expected_folder_path = Pathname.new(File.dirname(__FILE__)) / "../expected/"
test_folder_path     = Pathname.new(File.dirname(__FILE__)) / "../output_osm/"

Dir.glob(test_folder_path / '*').sort.each do |file|
  input_test_file = Pathname.new(File.basename(file))
  output_file     = expected_folder_path / input_test_file
  FileUtils.cp(file, output_file)
  puts "Updated #{output_file}"
end
