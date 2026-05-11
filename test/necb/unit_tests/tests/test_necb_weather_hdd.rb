require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# This test checks that the option to get HDD from the weather file or from an NECB table works properly.

class NECB_Weather_HDD_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the hdd rules for weather file/building location.
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_necb_weather_hdd
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                        SaveIntermediateModels: true,
                        building_type: 'SmallOffice',
                        epw_file: 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw',
                        fuel_type: 'Electricity'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    #test_cases[:NECB2011] = {Reference: "NECB 2011 "}

    # Define the tests.
    test_cases_hash = {vintage: @AllTemplates, 
                        necb_hdd_option: [true, false, 'NECB_Default'],
                        TestCase: ["case-1"], 
                        TestPars: {}}
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
    expected_results = JSON.parse(File.read(file_name), {symbolize_names: true})

    # Check if test results match expected.
    msg = "Weather HDD options test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end
  
  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_necb_weather_hdd that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_necb_weather_hdd(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # Static inputs (smae for all tests).
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    building_type = test_pars[:building_type]
    epw_file = test_pars[:epw_file]
    fuel_type = test_pars[:fuel_type]

    # Variable inputs
    vintage = test_pars[:vintage]
    necb_hdd = test_pars[:necb_hdd_option]


    # Define the test name. 
    name = "#{vintage}_weather_hdd-#{necb_hdd}"
    name_short = "#{vintage}_weather_hdd-#{necb_hdd}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin
      
      # Load standard and create model.
      standard = Standard.build(vintage)
      model = standard.model_create_prototype_model(template: vintage,
                                                    building_type: building_type,
                                                    epw_file: epw_file,
                                                    sizing_run_dir: output_folder,
                                                    primary_heating_fuel: fuel_type,
                                                    necb_hdd: necb_hdd)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract results
    construction_sets = model.getDefaultConstructionSets
    results = {
      construction_set_name: construction_sets[0].name.to_s
    }
    logger.info "Completed individual test: #{name}"
    return results
  end
end
