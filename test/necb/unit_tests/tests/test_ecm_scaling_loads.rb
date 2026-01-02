require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_scaling_loads_Tests < Minitest::Test

  
  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the ecm scaling loads functionality against expected values.
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_ecm_scaling_loads
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false,
                       epw_file: 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw', 
                       fuel_type: 'NaturalGas'}

    # Define test cases. 
    test_cases = Hash.new

    # Define reference.
    test_cases[:Reference] = 'ECM functionality built into BTAP'
    
    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ["NECB2011"], #@AllTemplates, 
                       archetype: ["FullServiceRestaurant"],
                       TestCase: ["case zero"], 
                       TestPars: {:scaling_factor => 0.0}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = {vintage: ["NECB2011"], #@AllTemplates, 
                       archetype: ["FullServiceRestaurant"],
                       TestCase: ["case half"], 
                       TestPars: {:scaling_factor => 0.5}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = {vintage: ["NECB2011"], #@AllTemplates, 
                       archetype: ["FullServiceRestaurant"],
                       TestCase: ["case one+half"], 
                       TestPars: {:scaling_factor => 1.5}}
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
  # @note Companion method to test_ecm_scaling_loads that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_ecm_scaling_loads(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # Static inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    epw_file = test_pars[:epw_file]
    fuel_type = test_pars[:fuel_type]

    # Variable inputs.
    vintage = test_pars[:vintage]
    building_type = test_pars[:archetype]

    # Test case specific inuts.
    loads_scale = test_case[:scaling_factor]

    # Define the test name. 
    name = "#{vintage}_#{building_type}_load_scaling-#{fuel_type}_scale-#{format('%.1f', loads_scale)}"
    name_short = "#{vintage}_#{building_type}_scale-#{fuel_type}-#{format('%.1f', loads_scale)}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin
    
      # Make an empty model.
      model = OpenStudio::Model::Model.new

      # Set up basic model.
      standard = Standard.build(vintage)

      # Loads osm geometry and spactypes from library.
      model = standard.load_building_type_from_library(building_type: building_type)

      # This runs the steps in the model.
      standard.model_apply_standard(model: model,
                                    epw_file: epw_file,
                                    sizing_run_dir: output_folder,
                                    primary_heating_fuel: fuel_type,
                                    dcv_type: nil, # Four options: (1) 'NECB_Default', (2) 'No_DCV', (3) 'Occupancy_based_DCV' , (4) 'CO2_based_DCV'
                                    lights_type: nil, # Two options: (1) 'NECB_Default', (2) 'LED'
                                    lights_scale: nil,
                                    daylighting_type: nil, # Two options: (1) 'NECB_Default', (2) 'add_daylighting_controls'
                                    ecm_system_name: nil,
                                    ecm_system_zones_map_option: nil, # (1) 'NECB_Default' (2) 'one_sys_per_floor' (3) 'one_sys_per_bldg'
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
                                    nv_type: nil, # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_nv'
                                    nv_opening_fraction: nil, # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 0.1), (3) opening fraction of windows, which can be a float number between 0.0 and 1.0
                                    nv_temp_out_min: nil, # options: (1) nil/none/false(2) 'NECB_Default' (i.e. 13.0 based on inputs from Michel Tardif re a real school in QC), (3) minimum outdoor air temperature (in Celsius) below which natural ventilation is shut down
                                    nv_delta_temp_in_out: nil, # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 1.0 based on inputs from Michel Tardif re a real school in QC), (3) temperature difference (in Celsius) between the indoor and outdoor air temperatures below which ventilation is shut down
                                    scale_x: nil,
                                    scale_y: nil,
                                    scale_z: nil,
                                    pv_ground_type: nil, # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_pv_ground'
                                    pv_ground_total_area_pv_panels_m2: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. building footprint), (3) area value (e.g. 50)
                                    pv_ground_tilt_angle: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. latitude), (3) tilt angle value (e.g. 20)
                                    pv_ground_azimuth_angle: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. south), (3) azimuth angle value (e.g. 90)
                                    pv_ground_module_description: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. Standard), (3) other options ('Standard', 'Premium', ThinFilm')
                                    occupancy_loads_scale: loads_scale,
                                    electrical_loads_scale: loads_scale,
                                    oa_scale: loads_scale,
                                    infiltration_scale: loads_scale,
                                    chiller_type: nil, # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) e.g. 'VSD'
                                    output_variables: nil,
                                    shw_scale: loads_scale,  # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) a float number larger than 0.0
                                    output_meters: nil,
                                    airloop_economizer_type: nil, # (1) 'NECB_Default'/nil/' (2) 'DifferentialEnthalpy' (3) 'DifferentialTemperature'
                                    baseline_system_zones_map_option: nil  # Three options: (1) 'NECB_Default'/'none'/nil (i.e. 'one_sys_per_bldg'), (2) 'one_sys_per_dwelling_unit', (3) 'one_sys_per_bldg'
      )

    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    ##### Gather info of occupancy_loads_scale in the model
    results["scaling_factor"] = loads_scale.to_f
    model.getPeoples.sort.each do |item|
      results["#{item.name.to_s} - multiplier"] = item.multiplier.to_f
    end

    ##### Gather info of electrical_loads_scale in the model
    model.getElectricEquipments.sort.each do |item|
      results["#{item.name.to_s} - multiplier"] = item.multiplier.to_f
    end

    ##### Gather info of oa_scale in the model
    model.getDesignSpecificationOutdoorAirs.sort.each do |item|
      results["#{item.name.to_s} - outdoorAirFlowperPerson"] = item.outdoorAirFlowperPerson.to_f.signif(6)
      results["#{item.name.to_s} - outdoorAirFlowperFloorArea"] = item.outdoorAirFlowperFloorArea.to_f.signif(6)
      results["#{item.name.to_s} - outdoorAirFlowRate"] = item.outdoorAirFlowRate.to_f.signif(6)
      results["#{item.name.to_s} - outdoorAirFlowAirChangesperHour"] = item.outdoorAirFlowAirChangesperHour.to_f.signif(6)
    end

    ##### Gather info of infiltration_scale in the model
    model.getSpaceInfiltrationDesignFlowRates.sort.each do |item|
      results["#{item.name.to_s} - designFlowRate"] = item.designFlowRate.to_f.signif(6)
      results["#{item.name.to_s} - flowperSpaceFloorArea"] = item.flowperSpaceFloorArea.to_f.signif(6)
      results["#{item.name.to_s} - flowperExteriorSurfaceArea"] = item.flowperExteriorSurfaceArea.to_f.signif(6)
      results["#{item.name.to_s} - airChangesperHour"] = item.airChangesperHour.to_f.signif(6)
    end

    ##### Gather info of shw_scale in the model
    model.getWaterUseEquipmentDefinitions.sort.each do |item|
      results["#{item.name.to_s} - peakFlowRate"] = item.peakFlowRate.to_f.signif(6)
    end
    model.getWaterHeaterMixeds.sort.each do |item|
      results["#{item.name.to_s} - tankVolume"] = item.tankVolume.to_f.signif
    end
    
    logger.info "Completed individual test: #{name}"
    return results
  end

  def old_test_scaling_loads()

    # File paths.
    @output_folder = File.join(__dir__, 'output/test_scaling_loads')
    @expected_results_file = File.join(__dir__, '../expected_results/scaling_loads_expected_results.json')
    @test_results_file = File.join(__dir__, '../expected_results/scaling_loads-test_results.json')
    @sizing_run_dir = File.join(@output_folder, 'sizing_folder')

    # Initial test condition
    @test_passed = true

    #Range of test options.
    @templates = [
        'NECB2011',
    # 'NECB2015',
    # 'NECB2017'
    ]
    @building_types = [
        'FullServiceRestaurant',
        # 'HighriseApartment',
        # 'Hospital'#,
        # 'LargeHotel',
        # 'LargeOffice',
        # 'MediumOffice',
        # 'MidriseApartment',
        # 'Outpatient',
        # 'PrimarySchool',
        # 'QuickServiceRestaurant',
        # 'RetailStandalone',
        # 'SecondarySchool',
        # 'SmallHotel',
        # 'Warehouse'
    ]
    @epw_files = [
        'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'
    ]
    @primary_heating_fuels = ['NaturalGas']

    @loads_scales = [
        0.0,
        0.5
    ]

    # Test results storage array.
    @test_results_array = []

    @templates.sort.each do |template|
      @epw_files.sort.each do |epw_file|
        @building_types.sort.each do |building_type|
          @primary_heating_fuels.sort.each do |primary_heating_fuel|
            @loads_scales.sort.each do |loads_scale|
              result = {}
              result['template'] = template
              result['epw_file'] = epw_file
              result['building_type'] = building_type
              result['primary_heating_fuel'] = primary_heating_fuel

              # make an empty model
              model = OpenStudio::Model::Model.new
              #set up basic model
              standard = Standard.build(template)

              #loads osm geometry and spactypes from library.
              model = standard.load_building_type_from_library(building_type: building_type)

              # # this runs the steps in the model.
              standard.model_apply_standard(model: model,
                                            epw_file: epw_file,
                                            sizing_run_dir: @sizing_run_dir,
                                            primary_heating_fuel: primary_heating_fuel,
                                            dcv_type: nil, # Four options: (1) 'NECB_Default', (2) 'No_DCV', (3) 'Occupancy_based_DCV' , (4) 'CO2_based_DCV'
                                            lights_type: nil, # Two options: (1) 'NECB_Default', (2) 'LED'
                                            lights_scale: nil,
                                            daylighting_type: nil, # Two options: (1) 'NECB_Default', (2) 'add_daylighting_controls'
                                            ecm_system_name: nil,
                                            ecm_system_zones_map_option: nil, # (1) 'NECB_Default' (2) 'one_sys_per_floor' (3) 'one_sys_per_bldg'
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
                                            nv_type: nil, # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_nv'
                                            nv_opening_fraction: nil, # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 0.1), (3) opening fraction of windows, which can be a float number between 0.0 and 1.0
                                            nv_temp_out_min: nil, # options: (1) nil/none/false(2) 'NECB_Default' (i.e. 13.0 based on inputs from Michel Tardif re a real school in QC), (3) minimum outdoor air temperature (in Celsius) below which natural ventilation is shut down
                                            nv_delta_temp_in_out: nil, # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 1.0 based on inputs from Michel Tardif re a real school in QC), (3) temperature difference (in Celsius) between the indoor and outdoor air temperatures below which ventilation is shut down
                                            scale_x: nil,
                                            scale_y: nil,
                                            scale_z: nil,
                                            pv_ground_type: nil, # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_pv_ground'
                                            pv_ground_total_area_pv_panels_m2: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. building footprint), (3) area value (e.g. 50)
                                            pv_ground_tilt_angle: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. latitude), (3) tilt angle value (e.g. 20)
                                            pv_ground_azimuth_angle: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. south), (3) azimuth angle value (e.g. 90)
                                            pv_ground_module_description: nil, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. Standard), (3) other options ('Standard', 'Premium', ThinFilm')
                                            occupancy_loads_scale: loads_scale,
                                            electrical_loads_scale: loads_scale,
                                            oa_scale: loads_scale,
                                            infiltration_scale: loads_scale,
                                            chiller_type: nil, # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) e.g. 'VSD'
                                            output_variables: nil,
                                            shw_scale: loads_scale,  # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) a float number larger than 0.0
                                            output_meters: nil,
                                            airloop_economizer_type: nil, # (1) 'NECB_Default'/nil/' (2) 'DifferentialEnthalpy' (3) 'DifferentialTemperature'
                                            baseline_system_zones_map_option: nil  # Three options: (1) 'NECB_Default'/'none'/nil (i.e. 'one_sys_per_bldg'), (2) 'one_sys_per_dwelling_unit', (3) 'one_sys_per_bldg'
              )

              # # comment out for regular tests
              # BTAP::FileIO.save_osm(model, File.join(@output_folder,"#{template}-#{building_type}-loads_scale-#{loads_scale}.osm"))
              # puts File.join(@output_folder,"#{template}-#{building_type}-loads_scale-#{loads_scale}.osm")

              result["loads_scale"] = loads_scale.to_f

              ##### Gather info of occupancy_loads_scale in the model
              model.getPeoples.sort.each do |item|
                result["#{item.name.to_s} - multiplier"] = item.multiplier.to_f
              end

              ##### Gather info of electrical_loads_scale in the model
              model.getElectricEquipments.sort.each do |item|
                result["#{item.name.to_s} - multiplier"] = item.multiplier.to_f
              end

              ##### Gather info of oa_scale in the model
              model.getDesignSpecificationOutdoorAirs.sort.each do |item|
                result["#{item.name.to_s} - outdoorAirFlowperPerson"] = item.outdoorAirFlowperPerson.to_f
                result["#{item.name.to_s} - outdoorAirFlowperFloorArea"] = item.outdoorAirFlowperFloorArea.to_f
                result["#{item.name.to_s} - outdoorAirFlowRate"] = item.outdoorAirFlowRate.to_f
                result["#{item.name.to_s} - outdoorAirFlowAirChangesperHour"] = item.outdoorAirFlowAirChangesperHour.to_f
              end

              ##### Gather info of infiltration_scale in the model
              model.getSpaceInfiltrationDesignFlowRates.sort.each do |item|
                result["#{item.name.to_s} - designFlowRate"] = item.designFlowRate.to_f
                result["#{item.name.to_s} - flowperSpaceFloorArea"] = item.flowperSpaceFloorArea.to_f
                result["#{item.name.to_s} - flowperExteriorSurfaceArea"] = item.flowperExteriorSurfaceArea.to_f
                result["#{item.name.to_s} - airChangesperHour"] = item.airChangesperHour.to_f
              end

              ##### Gather info of shw_scale in the model
              model.getWaterUseEquipmentDefinitions.sort.each do |item|
                result["#{item.name.to_s} - peakFlowRate"] = item.peakFlowRate.to_f
              end
              model.getWaterHeaterMixeds.sort.each do |item|
                result["#{item.name.to_s} - tankVolume"] = item.tankVolume.to_f
              end

              # puts JSON.pretty_generate(result)

              ##### then store results into the array that contains all the scenario results.
              @test_results_array << result

            end #@loads_scales.sort.each do |loads_scale|
          end #@primary_heating_fuels.sort.each do |primary_heating_fuel|
        end
      end
    end

    # puts @test_results_array

    # Save test results to file.
    File.open(@test_results_file, 'w') { |f| f.write(JSON.pretty_generate(@test_results_array)) }

    # Compare results
    compare_message = ''
    # Check if expected file exists.
    if File.exist?(@expected_results_file)
      # Load expected results from file.
      @expected_results = JSON.parse(File.read(@expected_results_file))
      if @expected_results.size == @test_results_array.size
        # Iterate through each test result.
        @expected_results.each_with_index do |expected, row|
          # Compare if row /hash is exactly the same.
          if expected != @test_results_array[row]
            #if not set test flag to false
            @test_passed = false
            compare_message << "\nERROR: This row was different expected/result\n"
            compare_message << "EXPECTED:#{expected.to_s}\n"
            compare_message << "TEST:    #{@test_results_array[row].to_s}\n\n"
          end
        end
      else
        assert(false, "#{@expected_results_file} # of rows do not match the #{@test_results_array}..cannot compare")
      end
    else
      assert(false, "#{@expected_results_file} does not exist..cannot compare")
    end
    puts compare_message
    assert(@test_passed, "Error: This test failed to produce the same result as in the #{@expected_results_file}\n")

  end #def test_scaling_loads()

end