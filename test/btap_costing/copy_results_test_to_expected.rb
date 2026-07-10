require 'pathname'
require 'fileutils'

folder_path = Pathname.new(File.dirname(__FILE__)) / "tests/regression_files/"
Dir.glob(folder_path / "*test_result.cost.json").sort.each do |file|
  new_file = file.gsub("test_result.cost.json","expected_result.cost.json")
  FileUtils.cp(file, new_file)
  FileUtils.rm(file, :force => true)
  puts "Updated #{new_file}"
end

