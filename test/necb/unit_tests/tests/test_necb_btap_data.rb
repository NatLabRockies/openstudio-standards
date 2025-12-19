require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_BTAP_Data_Reporting < Minitest::Test


  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate btap_data.json generation
  def test_btap_data_reporting
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'NaturalGas',
                       epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
                       archetype: 'FullServiceRestaurant'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references.
    test_cases = {Reference: "BTAP test - checking creation of btap_data report"}
    
    # Test cases. Three cases for NG.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['NECB2011'], # @AllTemplates, 
                       TestCase: ["case 1"], 
                       TestPars: {:tbd => 'tbd'}}
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
  # @note Companion method to test_btap_data_reporting that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_btap_data_reporting(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    epw_file = test_pars[:epw_file]
    building_type = test_pars[:archetype]
    
    # Variable inputs.
    vintage = test_pars[:vintage]

    # Test case inputs.
    

    # Define the test name. 
    name = "#{vintage}_btap_data_report"
    name_short = "#{vintage}_btap_rep"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Generate the osm files for all relevant cases to generate the envelope test data
    standard = get_standard(vintage)
    begin

      # Generate osm file.
      model = standard.model_create_prototype_model(building_type: building_type,
                                                    epw_file: epw_file,
                                                    template: vintage,
                                                    primary_heating_fuel: fuel_type,
                                                    sizing_run_dir: output_folder)

      standard.model_run_simulation_and_log_errors(model, output_folder)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Create the results file
    qaqc = standard.init_qaqc(model)
    # Replace the openstudio-standards version with test to avoid the test failing with every commit to a branch.
    qaqc[:os_standards_revision] = "test"
    qaqc[:os_standards_version] = "test"
    qaqc[:openstudio_version] = "test"
    qaqc[:energyplus_version] = "test"
    results = BTAPData.new(model: model,
                           runner: nil,
                           cost_result: nil,
                           carbon_result: nil,
                           qaqc: qaqc,
                           npv_start_year: 2010,
                           npv_end_year: 2030,
                           npv_discount_rate: @npv_discount_rate).btap_data

    #btap_data_out.select.first
    results["simulation_btap_data_version"] = "test"
    results["simulation_os_standards_revision"] = "test"
    results["simulation_os_standards_version"] = "test"
    results["simulation_date"] = "test"
    
    logger.info "Completed individual test: #{name}"
    return results
  end
end
