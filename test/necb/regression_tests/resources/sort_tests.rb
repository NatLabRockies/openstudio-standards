require 'fileutils'

# New Construction
vintages = /NECB2011|NECB2017|NECB2020/
building_types = /FullServiceRestaurant|HighriseApartment|LargeHotel|LargeOffice|MediumOffice|MidriseApartment|PrimarySchool|QuickServiceRestaurant|RetailStandalone|SecondarySchool|SmallHotel|Warehouse/
fuel_type_sets = /Electricity|NaturalGas|NaturalGasHPGasBackup|NaturalGasHPElecBackupMixed|ElectricityHPElecBackup|ElectricityHPGasBackupMixed/

folder_path = "#{File.dirname(__FILE__)}/../tests/"
files = Dir.glob(folder_path + "/test_necb_bldg_*").sort
files = files.grep(vintages).grep(building_types).grep(fuel_type_sets)
files.each do |file|
  puts "necb/regression_tests/tests/" + File.basename(file)
end

# New Construction
vintages = /BTAP1980TO2010|BTAPPRE1980/
building_types = /FullServiceRestaurant|HighriseApartment|LargeHotel|LargeOffice|MediumOffice|MidriseApartment|PrimarySchool|QuickServiceRestaurant|RetailStandalone|SecondarySchool|SmallHotel|Warehouse/
fuel_type_sets = /Electricity\.rb|NaturalGas\.rb/



folder_path = "#{File.dirname(__FILE__)}/../tests/"
files = Dir.glob(folder_path + "/test_necb_bldg_*").sort
files = files.grep(vintages).grep(building_types).grep(fuel_type_sets)
files.each do |file|
  puts "necb/regression_tests/tests/" + File.basename(file)
end

