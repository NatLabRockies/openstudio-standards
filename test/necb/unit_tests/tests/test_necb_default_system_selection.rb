require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# This class will perform tests that are Spacetype dependant, Test model will be created
# to specifically test aspects of the NECB code that are Spacetype dependant.
class NECB_Default_System_Selection_Tests < Minitest::Test
  # Set to true to run the standards in the test.
  PERFORM_STANDARDS = true

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  #  # This test will ensure that the system selection for each of the spacetypes are
  #  # being assigned the appropriate values.
  #  # @return [Bool] true if successful.
  def test_system_selection
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: false
    }

    # Define test cases.
    test_cases = {}

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3 Table 8.4.4.8.A." }
    test_cases[:NECB2015] = { Reference: "NECB 2011 p3 Table 8.4.4.7.-A" }
    test_cases[:NECB2017] = { Reference: "NECB 2011 p3 Table 8.4.4.7.-A" }
    test_cases[:NECB2020] = { Reference: "NECB 2011 p3 Table 8.4.4.7.-A." }

    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: @AllTemplates,
                        space_type: @AllSpaceTypes,
                        TestCase: ["case-1"],
                        TestPars: { :number_of_floors => 2 } }

    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        space_type: @AllSpaceTypes,
                        TestCase: ["case-2"],
                        TestPars: { :number_of_floors => 4 } }

    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        space_type: @AllSpaceTypes,
                        TestCase: ["case-3"],
                        TestPars: { :number_of_floors => 5 } }

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
    msg = "Default system test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_system_selection that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_system_selection(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"
    
    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    vintage = test_pars[:vintage]
    space_type = test_pars[:space_type]
    number_of_floors = test_case[:number_of_floors]

    # Define the test name.
    name = "#{vintage}_number_of_floors-#{number_of_floors}"
    name_short = "#{vintage}_#{number_of_floors}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = {}

    # Create new model for testing.
    standard = Standard.build(vintage)
    model = OpenStudio::Model::Model.new

    # Create only above ground geometry for this test.
    length = 100.0; width = 100.0; num_above_ground_floors = number_of_floors; num_under_ground_floors = 0; floor_to_floor_height = 3.8; plenum_height = 1; perimeter_zone_depth = 4.57; initial_height = 10.0
    OpenstudioStandards::Geometry.create_shape_rectangle(model, length, width, num_above_ground_floors, num_under_ground_floors, floor_to_floor_height, plenum_height, perimeter_zone_depth, initial_height)

    mapped_space_type = ""
    space_type_map = standard.standards_lookup_table_many(table_name: 'space_type_upgrade_map').detect do |row|
      if row["NECB2011_space_type"] == space_type
        mapped_space_type = row[vintage + "_space_type"]
      end
    end
    space_type = mapped_space_type

    # Define search criteria.
    search_criteria = {
      "template" => vintage,
      "space_type" => mapped_space_type
    }

    # Lookup space type properties.
    standards_table = standard.standards_data['space_types']
    standard.model_find_objects(standards_table, search_criteria).each do |space_type_properties|
      # Create a space type.
      st = OpenStudio::Model::SpaceType.new(model)
      st.setStandardsBuildingType(space_type_properties['building_type'])
      st.setStandardsSpaceType(space_type_properties['space_type'])
      st.setName("#{vintage}-#{space_type_properties['building_type']}-#{space_type_properties['space_type']}")
      standard.space_type_apply_rendering_color(st)
      standard.model_add_loads(model, 'NECB_Default', 1.0)
      # Assign Thermal zone and thermostats
      standard.model_create_thermal_zones(model, nil)
      # Set all spaces to spacetype.
      model.getSpaces.each do |space|
        space.setSpaceType(st)
      end

      # Access the space type data
      space_type_data = standard.model_find_object(standards_table, {
        'space_type' => st.standardsSpaceType.get,
        'building_type' => st.standardsBuildingType.get
      })
      space_type_selected = space_type_data['necb_hvac_system_selection_type']

      # Access the NECB HVAC system selection table
      necb_hvac_system_selection_table = standard.standards_data['necb_hvac_system_selection_type']

      # Filter the table based on the number of floors and space type
      selected_hvac_system = necb_hvac_system_selection_table.select do |entry|
        entry['necb_hvac_system_selection_type'] == space_type_selected &&
          entry['min_stories'] <= number_of_floors &&
          entry['max_stories'] >= number_of_floors
      end

      # Check that selected_hvac_system is not empty before accessing it.
      if selected_hvac_system.any?
        results = {
          :necb_hvac_system_selection_type => "#{space_type_selected}",
          :space_type_name => "#{st.standardsSpaceType.get}",
          :tested_number_of_floors => "#{number_of_floors}",
          :system_type => "#{selected_hvac_system.first['system_type']}" # .first is used to access the actual hash inside the array
        }
      else
        raise('could not find system for given spacetype')
      end
    end

    logger.info "Completed individual test: #{name}"
    # results=results.sort.to_h
    return results
  end
end
