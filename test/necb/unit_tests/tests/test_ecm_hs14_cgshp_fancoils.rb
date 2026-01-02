require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)


class ECM_HS14_CGSHP_FanCoils_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the unitary performance curves for water to water heat pumps
  def test_ecm_hs14_cgshp_curves
    logger.debug!
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'NaturalGas',
                       epw_file: 'CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw',
                       archetype: 'QuickServiceRestaurant'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references.
    test_cases = {Reference: "ECM test - checking hs14 CGSHP curves"}
    
    # Test cases. Three cases for NG.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['NECB2017'], # @AllTemplates, 
                       TestCase: ["case 1"], 
                       TestPars: {:ecm_system => 'hs14_cgshp_fancoils'}}
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
  # @note Companion method to test_ecm_hs14_cgshp_curves that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_ecm_hs14_cgshp_curves(test_pars:, test_case:)

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
    ecm_system = test_case[:ecm_system]
    
    # Define the test name. 
    name = "#{vintage}_#{ecm_system}"
    name_short = "#{vintage}_#{ecm_system}"
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
                                                    sizing_run_dir: output_folder,
                                                    ecm_system_name: ecm_system)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end
    
    # Recover water heat pump curves
    wshpc_units = model.getHeatPumpWaterToWaterEquationFitHeatings
    cap_curve = wshpc_units[0].heatingCapacityCurve.to_CurveQuadLinear.get
    results[:capacity_curve] = {
        type: 'quadlinear',
        const: "#{'%.5E' % cap_curve.coefficient1Constant}",
        coeff2w: "#{'%.5E' % cap_curve.coefficient2w}",
        coeff3x: "#{'%.5E' % cap_curve.coefficient3x}",
        coeff4y: "#{'%.5E' % cap_curve.coefficient4y}",
        coeff5z: "#{'%.5E' % cap_curve.coefficient5z}",
        min_w: "#{'%.5E' % cap_curve.minimumValueofw}",
        max_w: "#{'%.5E' % cap_curve.maximumValueofw}",
        min_x: "#{'%.5E' % cap_curve.minimumValueofx}",
        max_x: "#{'%.5E' % cap_curve.maximumValueofx}",
        min_y: "#{'%.5E' % cap_curve.minimumValueofy}",
        max_y: "#{'%.5E' % cap_curve.maximumValueofy}",
        min_z: "#{'%.5E' % cap_curve.minimumValueofz}",
        max_z: "#{'%.5E' % cap_curve.maximumValueofz}",
        min_output: "#{'%.5E' % cap_curve.minimumCurveOutput}",
        max_output: "#{'%.5E' % cap_curve.maximumCurveOutput}"
    }

    power_curve = wshpc_units[0].heatingCompressorPowerCurve.to_CurveQuadLinear.get
    results[:power_curve] = {
        type: 'quadlinear',
        const: "#{'%.5E' % power_curve.coefficient1Constant}",
        coeff2w: "#{'%.5E' % power_curve.coefficient2w}",
        coeff3x: "#{'%.5E' % power_curve.coefficient3x}",
        coeff4y: "#{'%.5E' % power_curve.coefficient4y}",
        coeff5z: "#{'%.5E' % power_curve.coefficient5z}",
        min_w: "#{'%.5E' % power_curve.minimumValueofw}",
        max_w: "#{'%.5E' % power_curve.maximumValueofw}",
        min_x: "#{'%.5E' % power_curve.minimumValueofx}",
        max_x: "#{'%.5E' % power_curve.maximumValueofx}",
        min_y: "#{'%.5E' % power_curve.minimumValueofy}",
        max_y: "#{'%.5E' % power_curve.maximumValueofy}",
        min_z: "#{'%.5E' % power_curve.minimumValueofz}",
        max_z: "#{'%.5E' % power_curve.maximumValueofz}",
        min_output: "#{'%.5E' % power_curve.minimumCurveOutput}",
        max_output: "#{'%.5E' % power_curve.maximumCurveOutput}"
    }

    logger.info "Completed individual test: #{name}"
    return results
  end
end
