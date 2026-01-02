require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_QAQC_Reporting < Minitest::Test


  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate qaqc reporting in btap.
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_qaqc_reporting
    
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       building_type: 'FullServiceRestaurant',
                       fuel_type: 'NaturalGas',
                       epw_file: 'CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw'
                      }

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: 'NECB 2011 p3 Table 5.2.12.1'}
    
    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['NECB2011'], #@AllTemplates, 
                       TestCase: ['case-1'], 
                       TestPars: {}
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
    expected_results = JSON.parse(File.read(file_name), {symbolize_names: true})

    # Check if test results match expected.
    msg = "Boiler efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_qaqc_reporting that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_qaqc_reporting(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    epw_file = test_pars[:epw_file]
    building_type = test_pars[:building_type]

    # Test specific inputs.
    boiler_cap = test_case[:tested_capacity_kW]
    efficiency_metric = test_case[:efficiency_metric]

    # Define the test name. 
    name = "#{vintage}_#{fuel_type}"
    name_short = "#{vintage}_#{fuel_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin

      # Create model.
      standard = get_standard(vintage)
      model = standard.model_create_prototype_model(building_type: building_type,
                                                    epw_file: epw_file,
                                                    template: vintage,
                                                    primary_heating_fuel: fuel_type,
                                                    sizing_run_dir: output_folder)

      # Run a simulation to create results.
      standard.model_run_simulation_and_log_errors(model, output_folder)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end
  
    # Create the results file
    results = standard.init_qaqc(model)

    # Replace the openstudio-standards version with test to avoid the test failing with every commit to a branch.
    results[:os_standards_revision] = "test"
    results[:os_standards_version] = "test"
    results[:openstudio_version] = "test"
    results[:energyplus_version] = "test"
  
    logger.info "Completed individual test: #{name}"
    return results
  end
end
