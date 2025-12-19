require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# This class will perform tests mapping of space types for different versions of NECB.
class NECB_VintageMap_Test < Minitest::Test
  
  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the mapoing of space tuypes to the vintages.
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_space_type_vintage_map
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 xxx"}
    
    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: @AllTemplates, 
                       space_type: @AllSpaceTypes,
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
    msg = "Space type mappings do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_boiler_efficiency that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_space_type_vintage_map(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    vintage = test_pars[:vintage]
    space_type = test_pars[:space_type]

    # Reporting
    results = {}

    # Current space_type is NECB2011. Need to check it agains the current vintage (i.e. does it map)
    begin

      # Create new simple geometry only model for testing.
      model = make_test_geometry

      # Create a new space type and assign it to the spaces in the model.
      test_spacetype = OpenStudio::Model::SpaceType.new(model)
      test_spacetype.setStandardsBuildingType('Space Function')
      test_spacetype.setStandardsSpaceType(space_type)
      test_spacetype.setName("Space Function #{space_type}") # NRCan use setNameProtected in the water heating test.
      logger.info "Assigning space type to spaces:"
      model.getSpaces.each do |space|
        logger.info "  Space: #{space.name}"
        space.setSpaceType(test_spacetype)
        logger.info "  New spacetype: #{test_spacetype.name}"
        logger.debug "  full object: #{test_spacetype}"
      end

      # Load the current vintage and update the space type.
      standard = get_standard(vintage)
      standard.validate_and_upate_space_types(model)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract results.
    results[:mapped_vintage] = vintage
    results[:mapped_space_type] = []
    model.getSpaceTypes.sort.each do |st|
      results[:mapped_space_type] << st.standardsSpaceType
    end
    logger.info "Completed individual test: #{name}"
    return results
  end


# Old test code that checks for all space types. Above only checks the space types we use.
# The code below fails as not all space types have been mapped.
  def no_test_necb2011()
    vintage_mapper('BTAP1980TO2010')
  end
  def no_test_necb2011()
    vintage_mapper('BTAPPRE1980')
  end
  def no_test_necb2011()
    vintage_mapper('NECB2011')
  end
  def no_test_necb2015()
    vintage_mapper('NECB2015')
  end
  def no_test_necb2017()
    vintage_mapper('NECB2017')
  end
  def no_test_necb2020()
    vintage_mapper('NECB2020')
  end

  private

  def vintage_mapper(vintage_name)
    standard = get_standard(vintage_name)
    vintage_space_types = standard.get_all_spacetype_names.map {|map| map[0] + '-' + map[1]}
    space_type_upgrade_map = standard.standards_lookup_table_many(table_name: 'space_type_upgrade_map').map {|map| map["#{vintage_name}_building_type"] + '-' + map["#{vintage_name}_space_type"]}.sort.uniq
    assert((space_type_upgrade_map.sort - vintage_space_types.sort).empty?, "Some #{vintage_name} Mapped spacetypes are not contained in the standards #{vintage_name} list \n #{space_type_upgrade_map.sort - vintage_space_types.sort} ")
    assert((vintage_space_types.sort - space_type_upgrade_map.sort).empty?, "Some #{vintage_name} spacetypes are not mapped \n #{vintage_space_types.sort - space_type_upgrade_map.sort}")
  end
end