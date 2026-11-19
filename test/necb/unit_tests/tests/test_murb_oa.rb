require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'

# Checks if BTAP::Structure instances are correctly deployed within BTAP.
class MURB_OA_Tests < Minitest::Test
  def test_murb_oa()
    outd = "output/test_murb_oa"
    eres = "../expected_results/murb_oa_expected_results.json"
    tres = "../expected_results/murb_oa_results.json"
    sizd = "sizing_folder"

    @output_folder         = File.join(__dir__, outd)
    @expected_results_file = File.join(__dir__, eres)
    @test_results_file     = File.join(__dir__, tres)
    @szg_dir               = File.join(@output_folder, sizd)
    @test_results_array    = []

    # Intial test condition.
    @test_passed = true

    @buildings = [
      # 'HighriseApartment',
      # 'HighriseApartmentMult',
      # 'LEEPMidriseApartment',
      # 'LEEPMultiTower',
      # 'LEEPPointTower',
      'LEEPTownHouse',
      # 'LowriseApartment',
      # 'MidriseApartment'
    ]

    @templates = [
      # "NECB2011",
      # "NECB2015",
      # "NECB2017",
      "NECB2020",
      # "NECB2025"
    ]

    @options = [
      "",        # BTAP default solution
      # "a622",  # ANSI/ASHRAE 62.2 2016
      # "a621",  # ANSI/ASHRAE 62.1 2016
      # "nbc932" # National Building Code of Canada (NBC 9.32, 2025)
    ]

    epw = "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"

    fdback = []
    fdback << ""
    fdback << "BTAP: MURB OA Unit Tests"
    fdback << "~~~~  ~~~~~~~~~~~~~~~~~~"

    @buildings.sort.each   do |building|
      @templates.sort.each do |template|
        @options.sort.each do |option  |
          cas   = "CASE #{building} (#{template})"
          cas  += " - #{option}" unless option.empty?
          st    = Standard.build(template)
          model = st.model_create_prototype_model(template: template,
                                                    epw_file: epw,
                                                    building_type: building,
                                                    construction_opt: option,
                                                    sizing_run_dir: @szg_dir)
        end                 # |option  |
      end                   # |template|
    end                     # |building|

    fdback.each { |msg| puts msg }

    # Save test results to file.
    # File.open(@test_results_file, 'w') do |f|
    #   f.write(JSON.pretty_generate(@test_results_array))
    # end
  end

end
