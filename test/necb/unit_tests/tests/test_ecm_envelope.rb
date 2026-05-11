require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_ECM_Envelope < Minitest::Test


  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate ecm envelope methods
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_ecm_envelope
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'NaturalGas',
                       epw_file: 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
                       archetype: 'FullServiceRestaurant'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references.
    test_cases = {Reference: "ECM test - setting specific thermal transmittance values (W/m2K)"}
    
    # Test cases. Three cases for NG.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['BTAPPRE1980', 'NECB2020'], # @AllTemplates, 
                       TestCase: ["high values"], 
                       TestPars: {:wall_cond => 0.278,
                                     :roof_cond => 0.162,
                                     :ground_floor_cond => 0.758}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    
    test_cases_hash = {vintage: ['BTAPPRE1980', 'NECB2020'], # @AllTemplates, 
                       TestCase: ["low values"], 
                       TestPars: {:wall_cond => 0.183,
                                     :roof_cond => 0.121,
                                     :ground_floor_cond => 0.379}}
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
  # @note Companion method to test_ecm_envelope that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_ecm_envelope(test_pars:, test_case:)

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
    wall_cond = test_case[:wall_cond]
    roof_cond = test_case[:roof_cond]
    ground_floor_cond = test_case[:ground_floor_cond]

    # Define the test name. 
    name = "#{vintage}_envelope_wall-#{wall_cond}_roof-#{roof_cond}_ground-#{ground_floor_cond}"
    name_short = "#{vintage}_env_w-#{wall_cond}_r-#{roof_cond}_g-#{ground_floor_cond}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Generate the osm files for all relevant cases to generate the envelope test data
    standard = get_standard(vintage)
    begin
      model = standard.model_create_prototype_model(building_type: building_type,
                                                    epw_file: epw_file,
                                                    template: vintage,
                                                    primary_heating_fuel: fuel_type,
                                                    sizing_run_dir: output_folder,
                                                    ext_wall_cond: wall_cond,
                                                    ext_roof_cond: roof_cond,
                                                    ground_floor_cond: ground_floor_cond)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # generate output data.
    results = {
      standard: vintage,
      wall_cond: wall_cond,
      roof_cond: roof_cond,
      ground_floor_cond: ground_floor_cond,
      surfaces: []
    }
    surfs = model.getSurfaces
    env_surfaces = surfs.select{ |surf| surf.outsideBoundaryCondition == 'Outdoors' || surf.outsideBoundaryCondition == 'Foundation' || surf.outsideBoundaryCondition == 'Ground' }
    env_surfaces.sort.each do |env_surface|
      therm_cond = env_surface.thermalConductance
      results[:surfaces] << {
        space: env_surface.space.get.name.to_s,
        surface_name: env_surface.name.get.to_s,
        outside_boundary_condition: env_surface.outsideBoundaryCondition,
        thermal_conductance: therm_cond.get.to_f.round(4)
      }
    end

    logger.info "Completed individual test: #{name}"
    return results
  end
end
