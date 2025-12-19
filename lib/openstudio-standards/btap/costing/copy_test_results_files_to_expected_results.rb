require 'fileutils'

folder_path = "#{File.dirname(__FILE__)}/btap_results/tests/regression_files/"
puts folder_path
Dir.glob(folder_path + "/*test_result.cost.json").sort.each do |f|
  new_file = f.gsub("test_result.cost.json","expected_result.cost.json")
  FileUtils.cp(f,new_file )
  FileUtils.rm(f, :force => true)
  puts "created new #{new_file}"
end

