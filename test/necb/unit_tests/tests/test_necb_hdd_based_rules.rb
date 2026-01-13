require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

# This class will perform tests that are HDD driven, A Test model will be created
# that will have all of OpenStudios surface types with different contructions. All
# components are created from scratch to ensure model are up to date and we will
# not run into version issues with the test. 
## to specifically test aspects of the NECB2011 code that are HDD dependant. 
class NECB_HDD_Tests < Minitest::Test

  # Set to true to run the standards in the test.
  PERFORM_STANDARDS = true

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Create scaffolding to create a model with windows, then reset to appropriate values.
  # Will require large windows and constructions that have high U-values.    
  def create_base_model()

    # Create new model for testing. 
    model = OpenStudio::Model::Model.new

    # Create Geometry that will be used for all tests.  
    # Below ground story to tests all ground surfaces including roof.
    length = 100.0; width = 100.0; num_above_ground_floors = 0; num_under_ground_floors = 1; floor_to_floor_height = 3.8; plenum_height = 1; perimeter_zone_depth = 4.57; initial_height = -10.0
    OpenstudioStandards::Geometry.create_shape_rectangle(model, length, width, num_above_ground_floors, num_under_ground_floors, floor_to_floor_height, plenum_height, perimeter_zone_depth, initial_height)
    below_ground_floors = OpenstudioStandards::Geometry.model_get_building_stories_below_ground(model)

    # Above ground story to test all above outdoors surfaces including floor.
    length = 100.0; width = 100.0; num_above_ground_floors = 3; num_under_ground_floors = 0; floor_to_floor_height = 3.8; plenum_height = 1; perimeter_zone_depth = 4.57; initial_height = 10.0
    OpenstudioStandards::Geometry.create_shape_rectangle(model, length, width, num_above_ground_floors, num_under_ground_floors, floor_to_floor_height, plenum_height, perimeter_zone_depth, initial_height)
    above_ground_floors = OpenstudioStandards::Geometry.model_get_building_stories_above_ground(model)

    # Find all outdoor surfaces. 
    outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Outdoors")
    outdoor_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Wall")
    outdoor_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "RoofCeiling")

    model.getBuilding.setStandardsNumberOfStories(4)
    model.getBuilding.setStandardsNumberOfAboveGroundStories(3)

    # Set all FWDR to a ratio of 0.60
    subsurfaces = []
    counter = 0
    outdoor_walls.each { |wall| subsurfaces << wall.setWindowToWallRatio(0.60) }
    
    # Ensure all wall subsurface types are represented. 
    subsurfaces.each do |subsurface|
      counter = counter + 1

      case counter
      when 1
        subsurface.get.setSubSurfaceType('FixedWindow')
      when 2
        subsurface.get.setSubSurfaceType('OperableWindow')
      when 3
        subsurface.get.setSubSurfaceType('Door')
      when 4
        subsurface.get.setSubSurfaceType('GlassDoor')
        counter = 0
      end
    end

    # Create skylights that are 10% of area with a 4x4m size.
    pattern = OpenStudio::Model::generateSkylightPattern(model.getSpaces, model.getSpaces[0].directionofRelativeNorth, 0.10, 4.0, 4.0) # ratio, x value, y value
    subsurfaces = OpenStudio::Model::applySkylightPattern(pattern, model.getSpaces, OpenStudio::Model::OptionalConstructionBase.new)

    # Ensure all roof subsurface types are represented. 
    subsurfaces.each do |subsurface|
      counter = counter + 1
      case counter
      when 1
        subsurface.setSubSurfaceType('Skylight')
      when 2
        subsurface.setSubSurfaceType('TubularDaylightDome')
      when 3
        subsurface.setSubSurfaceType('TubularDaylightDiffuser')
      when 4
        subsurface.setSubSurfaceType('OverheadDoor')
        counter = 0
      end
    end

    standard = get_standard("NECB2011")
    standard.model_clear_and_set_example_constructions(model)

    # Ensure that building is Conditioned add spacetype to each space. 

    return model
  end

  # Tests to ensure that the U-Values of the construction are set correctly. This 
  # test will set up  
  # for all HDDs 
  # NECB2011 8.4.4.1
  # @return [Bool] true if successful. 
  def test_envelope_rules()
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB2011 8.4.4.1"}
    test_cases[:NECB2015] = {Reference: "xx"}
    test_cases[:NECB2017] = {Reference: "xx"}
    test_cases[:NECB2020] = {Reference: "xx"}
    
    # Test cases. Define each case seperately as they have unique locations.
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["climate_zone_4"], 
                       TestPars: {:epw_file => "CAN_BC_Vancouver.Intl.AP.718920_CWEC2016.epw"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["climate_zone_5"], 
                       TestPars: {:epw_file => "CAN_BC_Kamloops.AP.718870_CWEC2016.epw"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["climate_zone_6"], 
                       TestPars: {:epw_file => "CAN_ON_Ottawa-Macdonald-Cartier.Intl.AP.716280_CWEC2016.epw"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["climate_zone_7a"], 
                       TestPars: {:epw_file => "CAN_AB_Banff.CS.711220_CWEC2016.epw"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["climate_zone_7b"], 
                       TestPars: {:epw_file => "CAN_ON_Armstrong.AP.718410_CWEC2016.epw"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates, 
                       TestCase: ["climate_zone_8"], 
                       TestPars: {:epw_file => "CAN_NU_Resolute.AP.719240_CWEC2016.epw"}}
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
    msg = "Envelope HDD dependent test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_necb_hdd_envelope_rules that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_envelope_rules(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    vintage = test_pars[:vintage]
    
    # Test specific inputs.
    epw_file = test_case[:epw_file]

    # Define the base model. HDD rules are applied to this.
    model = create_base_model()

    # Create a space type and assign to all spaces. This is done because the FWDR is only applied to conditioned spaces. So we need conditioning data.
    building_type = "Office"
    space_type = "WholeBuilding"

    # Define the vintage, set weather file and get the HDD.
    standard = get_standard(vintage)
    standard.apply_weather_data(model: model, epw_file: File.basename(epw_file))
    hdd = standard.get_necb_hdd18(model: model)
    
    # Define the test name.
    name = "#{vintage}-#{hdd} HDD"
    name_short = "#{vintage}-#{hdd}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    BTAP::FileIO.save_osm(model, "#{output_folder}/base.osm") if save_intermediate_models

    table = standard.standards_data['tables']['space_types']['table']
    space_type_properties = table.detect { |st| st["building_type"] == building_type && st["space_type"] == space_type }
    st = OpenStudio::Model::SpaceType.new(model)
    st.setStandardsBuildingType(space_type_properties['building_type'])
    st.setStandardsSpaceType(space_type_properties['space_type'])
    st.setName("#{vintage}-#{space_type_properties['building_type']}-#{space_type_properties['space_type']}")
    standard.space_type_apply_rendering_color(st)
    standard.model_add_loads(model, 'NECB_Default', 1.0)

    # Now loop through each space and assign the spacetype.
    model.getSpaces.each do |space|
      space.setSpaceType(st)
    end

    # Create Zones.
    standard.model_create_thermal_zones(model)

    # Worflow should mirror BTAP workflow up to fdwr. Note envelope includes infiltration.
    # Not validating spacetypes as not needed for this simplified test.
    standard.assign_building_activity(model: model)
    standard.assign_building_structure(model: model, activity: @activity)
    standard.apply_loads(model: model)
    standard.apply_envelope(model: model)
    standard.apply_fdwr_srr_daylighting(model: model)

    # Set the infiltration rate at each space.
    model.getSpaces.sort.each do |space|
      standard.space_apply_infiltration_rate(space)
    end

    # Save model if requested.
    BTAP::FileIO.save_osm(model, "#{output_folder}/hdd-#{hdd}.osm") if save_intermediate_models

    # Get Surfaces by type.
    outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Outdoors")
    outdoor_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Wall")
    outdoor_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "RoofCeiling")
    outdoor_floors = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Floor")
    outdoor_subsurfaces = outdoor_surfaces.flat_map(&:subSurfaces)
    windows = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["FixedWindow", "OperableWindow"])
    skylights = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["Skylight", "TubularDaylightDiffuser", "TubularDaylightDome"])
    doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["Door", "GlassDoor"])
    overhead_doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["OverheadDoor"])
    ground_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Ground")
    ground_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "Wall")
    ground_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "RoofCeiling")
    ground_floors = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "Floor")

    # Determine the weighted average conductances by surface type.
    ## exterior surfaces.
    outdoor_walls_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_walls)
    outdoor_roofs_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_roofs)
    outdoor_floors_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(outdoor_floors)
    ## Ground surfaces.
    ground_walls_average_conductances = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_walls)
    ground_roofs_average_conductances = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_roofs)
    ground_floors_average_conductances = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_floors)
    ## Sub surfaces.
    windows_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(windows)
    windows_average_shgc = OpenstudioStandards::Constructions.surfaces_get_solar_transmittance(windows)
    skylights_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(skylights)
    doors_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(doors)
    #overhead_doors_average_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(overhead_doors)

    # SRR and FDWR.
    srr_info = standard.find_exposed_conditioned_roof_surfaces(model)
    fdwr_info = standard.find_exposed_conditioned_vertical_surfaces(model)

    # Output conductances.
    def roundOrNA(data, figs = 4)
      if data.is_a?(Numeric)
        return data.signif(figs)
      end
      return 'NA'
    end

    results = Hash.new
    results = {
      epw_file: epw_file,
      hdd: hdd,
      fdwr: roundOrNA(fdwr_info["fdwr"], 2),
      srr: roundOrNA(srr_info["srr"], 2),
      outdoor_roofs_average_conductance: roundOrNA(outdoor_roofs_average_conductance),
      outdoor_walls_average_conductance: roundOrNA(outdoor_walls_average_conductance),
      outdoor_floors_average_conductance: roundOrNA(outdoor_floors_average_conductance),
      ground_roofs_average_conductance: roundOrNA(ground_roofs_average_conductances),
      ground_walls_average_conductance: roundOrNA(ground_walls_average_conductances),
      ground_floors_average_conductance: roundOrNA(ground_floors_average_conductances),
      windows_average_conductance: roundOrNA(windows_average_conductance),
      windows_average_shgc: roundOrNA(windows_average_shgc, 2),
      skylights_average_conductance: roundOrNA(skylights_average_conductance),
      doors_average_conductance: roundOrNA(doors_average_conductance)
    }

    # Infiltration rates.
    # Get the effective infiltration rate through the walls and roof only. Need to sort spaces otherwise the output order is random.
    #sorted_spaces = BTAP::Geometry::Spaces::get_spaces_from_storeys(model, above_ground_floors).sort_by { |space| space.name.get }
    sorted_spaces = model.getSpaces.sort_by { |space| space.name.get }
    infiltration_results = Hash.new
    sorted_spaces.each do |space|
      assert(space.spaceInfiltrationDesignFlowRates.size <= 1, "There should be no more than one infiltration object per space in the reference/budget building#{space.spaceInfiltrationDesignFlowRates}")
      
      # If space rightfully does not have an infiltration rate (no exterior surfaces) output an NA. 
      if space.spaceInfiltrationDesignFlowRates.size == 0
        infiltration_results[space.name.get] = "NA"
      else
        # Do some math to determine the effective infiltration rate of the walls and roof only as per NECB. 
        wall_roof_infiltration_rate = space.spaceInfiltrationDesignFlowRates[0].flowperExteriorSurfaceArea.get * space.exteriorArea / OpenstudioStandards::Geometry.space_get_exterior_wall_and_subsurface_and_roof_area(space)
        # Output effective infiltration rate
        infiltration_results[space.name.get] = (wall_roof_infiltration_rate * 1000.0).signif(3)
      end
    end
    results['Infiltration rates (L/s/m2)'.to_sym] = infiltration_results.transform_keys(&:to_sym)

    logger.info "Completed individual test: #{name}"
    return results
  end
end
