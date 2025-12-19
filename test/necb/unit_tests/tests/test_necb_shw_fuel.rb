require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include NecbHelper

class NECB_SWH_Fuel < Minitest::Test

  def setup
    define_folders(__dir__)
    define_std_ranges
  end

  def test_btap_swh_fuel
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: false,
                        building_type: 'FullServiceRestaurant',
                        fuel_type: 'NaturalGas',
                        epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw' 
                      }

    # Define test cases.
    test_cases = {}

    # Test cases. Two cases for NG and one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: ['BTAP1980TO2010', 'NECB2020'],
                        swh_fuel_type: ['NECB_Default', 'Electricity', 'NaturalGas', 'FuelOilNo2'],
                        TestCase: ["case-1"],
                        TestPars: { } 
                      }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # Create empty results hash and call the template method that runs the individual test cases.
    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    file_root = "#{self.class.name}-#{__method__}".downcase
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Read expected results.
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), { symbolize_names: true })
    # Check if test results match expected.
    msg = "furnacSWH fuel typee test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_btap_swh_fuel that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_btap_swh_fuel(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    building_type = test_pars[:building_type]
    fuel_type = test_pars[:fuel_type]
    epw_file = test_pars[:epw_file]
    vintage = test_pars[:vintage]

    # Test specific inputs.
    swh_fuel_type = test_pars[:swh_fuel_type]

    name = "#{vintage}_fuel-#{fuel_type}_swh_fuel-#{swh_fuel_type}"
    name_short = "#{vintage}_#{swh_fuel_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Array.new

    # Wrap test in begin/rescue/ensure.
    begin

      swh_out_data = []
      standard = get_standard(vintage)
      model = standard.model_create_prototype_model(building_type: building_type,
                                                      epw_file: epw_file,
                                                      template: vintage,
                                                      primary_heating_fuel: fuel_type,
                                                      swh_fuel: swh_fuel_type,
                                                      sizing_run_dir: output_folder)
    rescue => error
      backtrace_hash = {}

      # Split the full message into lines and iterate over them
      error.full_message.split("\n").each_with_index do |line, index|
        # Use the index to create a unique key for each line
        backtrace_hash["#{index + 1}"] = line
      end
      #msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      msg = {
          file: "#{__FILE__}",
          method: "#{__method__}",
          backtrace: backtrace_hash
        }
      logger.error("#{msg}")
      return {ERROR: msg}
    end

    # Extract results
    results = {
        template: vintage,
        default_fuel_type: fuel_type,
        test_SWH_fuel: swh_fuel_type,
        swh_tanks: []
      }
    water_heaters = model.getWaterHeaterMixeds
    water_heaters.each do |wh|
      vol_m3 = wh.tankVolume.get.to_f
      results[:swh_tanks] << {
        name: wh.name.get.to_s,
        tankVolume_L: (vol_m3*1000.0).signif(3),
        tankVolume_gal: OpenStudio.convert(vol_m3, 'm^3', 'gal').get.signif(3),
        heaterFuelType: wh.heaterFuelType,
        Efficiency: wh.heaterThermalEfficiency.get.to_f
      }
    end

    logger.info "Completed individual test: #{name}"
    return results
  end
end
