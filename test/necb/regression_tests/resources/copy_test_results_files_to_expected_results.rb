require 'fileutils'

expected_folder_path = "#{File.dirname(__FILE__)}/../expected/"
test_folder_path = "#{File.dirname(__FILE__)}/../output_osm/"
puts "Test File OSM directory: #{test_folder_path}"
puts "Expected File OSM directory: #{expected_folder_path}"

Dir.glob(test_folder_path + '*').sort.each do |f|
  #Dir.glob(folder_path + "/*test_result.osm").sort.each do |f|
  # #new_file = f.gsub("test_result.osm","expected_result.osm")
  input_test_file = File.basename(f)
  output_file = File.join(expected_folder_path, input_test_file)
  FileUtils.cp(f,output_file )
  puts "created new #{output_file}"
end

#Dir.glob(folder_path + "/*test_result_qaqc.json").sort.each do |f|
#  new_file = f.gsub("test_result_qaqc.json","expected_result_qaqc.json")
#  FileUtils.cp(f,new_file )
#  puts "created new #{new_file}"
#end
