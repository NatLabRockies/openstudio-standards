require_relative '../../../../helpers/minitest_helper'
require_relative '../../../../helpers/create_doe_prototype_helper'
require 'json'
require_relative '../../../../helpers/necb_helper'
include(NecbHelper)

module InsuiteCentralDOASTestHelper
  # Test configuration constants
  TEMPLATE = 'NECB2011'.freeze
  EPW_FILE = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'.freeze
  PRIMARY_HEATING_FUEL = 'NaturalGas'.freeze

  def setup_insuite_doas_test
    @test_passed = true
    @test_results_array = []
  end

  def run_insuite_doas_test(building_type, baseline_system_zones_map_option)
    @building_type = building_type
    @baseline_system_zones_map_option = baseline_system_zones_map_option
    
    setup_file_paths
    build_test_result
    write_test_results
    compare_results
  end

  private

  def setup_file_paths
    # Create unique test result filename based on building type and system map option
    result_filename = "insuite_central_doas_#{@building_type}_#{@baseline_system_zones_map_option}_test_results.json"
    expected_filename = "insuite_central_doas_#{@building_type}_#{@baseline_system_zones_map_option}_expected_results.json"
    
    @output_folder = File.join(__dir__, '../output/test_insuite_central_doas',@building_type,@baseline_system_zones_map_option)
    @expected_results_file = File.join(__dir__, '../../expected_results', expected_filename)
    @test_results_file = File.join(__dir__, '../../expected_results', result_filename)
    @sizing_run_dir = File.join(@output_folder, 'sizing_folder')
  end

  def build_test_result
    result = {}
    result['template'] = TEMPLATE
    result['epw_file'] = EPW_FILE
    result['building_type'] = @building_type
    result['primary_heating_fuel'] = PRIMARY_HEATING_FUEL
    result['doas_type'] = @baseline_system_zones_map_option

    # Create and configure the model
    model = create_building_model
    
    # Save OSM file for debugging
    save_debug_model(model)
    
    # Gather airloop information
    gather_airloop_info(model, result)
    
    @test_results_array << result
  end

  def create_building_model
    # Make an empty model
    model = OpenStudio::Model::Model.new
    
    # Set up basic model
    standard = Standard.build(TEMPLATE)
    
    # Load osm geometry and space types from library
    model = standard.load_building_type_from_library(building_type: @building_type)
    
    # Apply standard with all parameters
    standard.model_apply_standard(
      model: model,
      epw_file: EPW_FILE,
      sizing_run_dir: @sizing_run_dir,
      primary_heating_fuel: PRIMARY_HEATING_FUEL,
      dcv_type: nil,
      lights_type: nil,
      lights_scale: nil,
      daylighting_type: nil,
      ecm_system_name: nil,
      ecm_system_zones_map_option: nil,
      erv_package: nil,
      boiler_eff: nil,
      unitary_cop: nil,
      furnace_eff: nil,
      shw_eff: nil,
      ext_wall_cond: nil,
      ext_floor_cond: nil,
      ext_roof_cond: nil,
      ground_wall_cond: nil,
      ground_floor_cond: nil,
      ground_roof_cond: nil,
      door_construction_cond: nil,
      fixed_window_cond: nil,
      glass_door_cond: nil,
      overhead_door_cond: nil,
      skylight_cond: nil,
      glass_door_solar_trans: nil,
      fixed_wind_solar_trans: nil,
      skylight_solar_trans: nil,
      rotation_degrees: nil,
      fdwr_set: nil,
      srr_set: nil,
      nv_type: nil,
      nv_opening_fraction: nil,
      nv_temp_out_min: nil,
      nv_delta_temp_in_out: nil,
      scale_x: nil,
      scale_y: nil,
      scale_z: nil,
      pv_ground_type: nil,
      pv_ground_total_area_pv_panels_m2: nil,
      pv_ground_tilt_angle: nil,
      pv_ground_azimuth_angle: nil,
      pv_ground_module_description: nil,
      occupancy_loads_scale: nil,
      electrical_loads_scale: nil,
      oa_scale: nil,
      infiltration_scale: nil,
      chiller_type: nil,
      output_variables: nil,
      shw_scale: nil,
      output_meters: nil,
      airloop_economizer_type: nil,
      baseline_system_zones_map_option: @baseline_system_zones_map_option
    )
    
    model
  end

  def save_debug_model(model)
    FileUtils.mkdir_p(@output_folder)
    filename = "#{TEMPLATE}-#{@building_type}-doas-type-#{@baseline_system_zones_map_option}.osm"
    filepath = File.join(@output_folder, filename)
    BTAP::FileIO.save_osm(model, filepath)
    puts "Saved debug model: #{filepath}"
  end

  def gather_airloop_info(model, result)
    number_of_airloops = 0
    model.getAirLoopHVACs.sort.each do |air_loop|
      result["airloop - #{number_of_airloops}"] = air_loop.name.to_s
      number_of_airloops += 1
    end
    result["number_of_airloops"] = number_of_airloops.to_f
  end

  def write_test_results
    # Ensure expected results directory exists
    FileUtils.mkdir_p(File.dirname(@test_results_file))
    
    File.open(@test_results_file, 'w') do |f|
      f.write(JSON.pretty_generate(@test_results_array))
    end
    puts "Generated test results: #{@test_results_file}"
  end

  def compare_results
    compare_message = ''
    
    # Check if expected file exists
    if File.exist?(@expected_results_file)
      # Load expected results from file
      expected_results = JSON.parse(File.read(@expected_results_file))
      
      if expected_results.size == @test_results_array.size
        # Iterate through each test result
        expected_results.each_with_index do |expected, row|
          # Compare if row/hash is exactly the same
          if expected != @test_results_array[row]
            # If not, set test flag to false
            @test_passed = false
            compare_message << "\nERROR: This row was different expected/result\n"
            compare_message << "EXPECTED: #{expected}\n"
            compare_message << "TEST:     #{@test_results_array[row]}\n\n"
          end
        end
      else
        assert(false, "#{@expected_results_file} # of rows do not match the #{@test_results_array}..cannot compare")
      end
    else
      assert(false, "Expected results file not found: #{@expected_results_file}")
    end
    
    puts compare_message
    assert(@test_passed, "Error: This test failed to produce the same result as in the #{@expected_results_file}\n")
  end
end