require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# This class will perform tests to ensure that the centroid of the highest ceiling is being found and that the overall
# centroid of ceilings of spaces in a thermal zone in story is properly found.  It uses the Ceilingtest.osm which is
# a modified version of the initial HighriseApartement.osm geometry file.
class NECB_Ceiling_Centroid_Test < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end
  
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_ceiling_centroid
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       epw_file: 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references.
    test_cases = {Reference: "BTAP test - checking geometry data used in costing"}
    
    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["case-1"], 
                       TestPars: {:value => :tbd}}
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
    msg = "Ceiling centroid test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_boiler_efficiency that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_ceiling_centroid(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    epw_file = test_pars[:epw_file]
    
    # Variable inputs.
    vintage = test_pars[:vintage]

    # Define the test name. 
    name = "#{vintage}_ceiling_centroid"
    name_short = "#{vintage}_ceiling_centroid"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder,"Ceilingtest.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models

      # Get access to the standards class
      standard = get_standard(vintage)

    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end
      
    # Add this test case to results and return the hash.
    # Find the centroid of the highest outside ceiling
    roof_cent = standard.find_highest_roof_centre(model)
    results = {
      roof_centroid_x_m: roof_cent[:roof_centroid][0].signif(3),
      roof_centroid_y_m: roof_cent[:roof_centroid][1].signif(3),
      roof_height_m: roof_cent[:roof_centroid][2].signif(3),
      roof_area_m2: roof_cent[:roof_area].signif(3)
    }

    # Go through the thermal zones and find all the conditioned, non-plenum, spaces in the thermal zone.  Sort by
    # story and find the overall centroid of all the ceilings in the thermal zone on that floor.  Add the result
    # to the output array.
    tz_results = []
    model.getThermalZones.sort.each do |tz|
      tz_data = standard.thermal_zone_get_centroid_per_floor(tz)
      next if tz_data[0] == nil
      tz_results << {
        name: tz.nameString,
        story: tz_data[0][:story_name],
        centroid_x_m: tz_data[0][:centroid][0].signif(3),
        centroid_y_m: tz_data[0][:centroid][1].signif(3),
        centroid_z_m: tz_data[0][:centroid][2].signif(3),
        ceiling_area_m2: tz_data[0][:ceiling_area].signif(3)
      }
    end
    #tz_results.sort_by! { |entry| entry[:thermal_zone] }
    results[:thermal_zones] = tz_results

    logger.info "Completed individual test: #{name}"
    return results
  end
end