require 'fileutils'
require 'parallel'
require 'open3'
require 'minitest/autorun'
require 'json'
require_relative './parallel_tests'
TestListFile = File.join(File.dirname(__FILE__), 'local_tests.txt')


class RunAllCostTests < Minitest::Test
  def test_costing_all()

    # The OpenStudio v3.2.1 CLI has issues so running the tests by calling the methods directly
    #test_cli = File.join(__dir__, "measures", "btap_results", "tests", "test_helper.rb")
    test_cli = File.join(__dir__, "btap_results", "tests", "test_helper_nocli.rb")
    building_types = [
      #'Hospital',
      #'Outpatient',
      'HighriseApartment',
      'SmallHotel',
      'LargeHotel',
      'LowriseApartment',
      'MidriseApartment',
      'SecondarySchool',
      'LargeOffice',
      'MediumOffice',
      'PrimarySchool',
      'RetailStandalone',
      'RetailStripmall',
      'SmallOffice',
      'Warehouse',
      'FullServiceRestaurant',
      'QuickServiceRestaurant',
    ]

    epw_files = [
      #"CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw",
      #"CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw",
      #"CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw",
      #"CAN_AB_Fort.Mcmurray.AP.716890_CWEC2020.epw",
      #"CAN_NS_Halifax.Dockyard.713280_CWEC2020.epw",
      #"CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw",
      #"CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw",
      "CAN_NT_Yellowknife.AP.719360_CWEC2020.epw"
    ]

# NECB2015 will work after openstudio-standards/tree/nrcan_48
# has been pulled into nrcan
# NOTE:  Only use one template at a time!!!!!!!!!  If more than one selected the test will fail!!!!!!
    templates = [
      #"BTAPPRE1980",
      "BTAP1980TO2010",
      "NECB2011",
      "NECB2015",
      "NECB2017",
      "NECB2020"
    ]
    fuels = [
      'NaturalGas',
      'Electricity',
      'NaturalGasHPGasBackup'
    ]
    # Test list to pass to parallel tester.
    test_list = []
    building_types.each do |build_type|
      epw_files.each do |epw_file|
        templates.each do |template|
          fuels.each do |fuel|
            next if ((template == 'BTAPPRE1980') || (template == 'BTAP1980TO2010')) && (fuel == 'NaturalGasHPGasBackup')
            test_list << "#{test_cli} -b " + build_type + " -w " + epw_file + " -t " + template + " -f " + fuel + " -k"
          end
        end
      end
    end
    puts 'testing these scenarioes'
    puts test_list
    puts "To change the costing tests being run please edit test_run_costing_tests.rb."
    assert(ParallelTests.new.run(test_list), "Some tests failed please ensure all test pass and tests have been updated to reflect the changes you expect before issuing a pull request")
  end
end
