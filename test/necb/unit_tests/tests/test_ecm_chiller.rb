require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class ECM_VSDchiller_Tests < Minitest::Test

  # Set to true to run the standards in the test.
  PERFORM_STANDARDS = true

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the chillers ECM.
  # Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_vsd_chiller
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: true,
                        epw_file: 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw',
                        fuel_type: 'NaturalGas',
                        chiller_type: 'VSD'}
    
    # Define test cases. 
    test_cases = {}

    test_cases_hash = {
      vintage: ['NECB2011'], #@AllTemplates,
      archetype: ['LargeOffice'], # others?
      chiller_capacity_kW: [235, 606, 819, 993, 1220, 1536, 1773], # Approx mid point of defined VSD chillers.
      TestCase: ['Test Case'],
      TestPars: {  } # none.
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
    expected_results = JSON.parse(File.read(file_name), { symbolize_names: true })

    # Check if test results match expected.
    msg = "Chiller ECM test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end
  
  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_vsd_chiller that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_vsd_chiller(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    vintage = test_pars[:vintage]
    building_type = test_pars[:archetype]
    epw_file = test_pars[:epw_file]
    primary_heating_fuel = test_pars[:fuel_type]
    chiller_type = test_pars[:chiller_type]
    chiller_cap = test_pars[:chiller_capacity_kW].to_f

    name = "#{vintage}_Archetype-#{building_type}_Chiller-#{chiller_type}"
    name_short = "#{vintage}_#{building_type}_#{chiller_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}/")
    logger.info "Starting individual test: #{name}"
    results = {}

    # (1) Create archetype with chillers active
    # (2) loop through chillers and update them
    # (3) check efficiency
    
    # Wrap test in begin/rescue/ensure.
    begin

      #loads osm geometry and spactypes from library.
      standard = get_standard(vintage)
      model = standard.load_building_type_from_library(building_type: building_type)

      # # this runs the steps in the model.
      ##### Here, do not implement VSD chiller. This is because in the next step,
      ##### capacity of existing chillers are replaced with mid of min and max capacity of 'chiller_set'
      ##### to avoid hard coding for chiller's capacity (as per Kamel Haddad's comment)
      standard.model_apply_standard(model: model,
                                    epw_file: epw_file,
                                    sizing_run_dir: output_folder,
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
                                    occupancy_loads_scale: nil,
                                    electrical_loads_scale: nil,
                                    oa_scale: nil,
                                    infiltration_scale: nil,
                                    chiller_type: nil, # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) e.g. 'VSD'
                                    output_variables: nil,
                                    shw_scale: nil,  # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) a float number larger than 0.0
                                    output_meters: nil,
                                    airloop_economizer_type: nil, # (1) 'NECB_Default'/nil/' (2) 'DifferentialEnthalpy' (3) 'DifferentialTemperature'
                                    baseline_system_zones_map_option: nil  # Three options: (1) 'NECB_Default'/'none'/nil (i.e. 'one_sys_per_bldg'), (2) 'one_sys_per_dwelling_unit', (3) 'one_sys_per_bldg'
      )
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models

      # Set chiller capacity as per test.
      model.getChillerElectricEIRs.each {|chiller| chiller.setReferenceCapacity(chiller_cap*1000.0)}
      
      ##### Now, implement the VSD chiller measure in the model
      model.getChillerElectricEIRs.sort.each do |mod_chiller|
        ref_capacity_w = mod_chiller.referenceCapacity.to_f

        ##### Look for a chiller set in chiller_set.json (with a capacity close to that of the existing chiller)
        ecm = ECMS.new
        chiller_set, chiller_min_cap, chiller_max_cap = ecm.find_chiller_set(chiller_type: chiller_type, ref_capacity_w: chiller_cap*1000.0)
        ecm.reset_chiller_efficiency(model: model, component: mod_chiller.to_ChillerElectricEIR.get, cop: chiller_set)

        ##### No need to replace any chillers with capacity = 0.001 W as per Kamel Haddad's comment
        #if ref_capacity_w > 0.0011
        #  ecm.reset_chiller_efficiency(model: model, component: mod_chiller.to_ChillerElectricEIR.get, cop: chiller_set)
        #end
      end
      BTAP::FileIO.save_osm(model, "#{output_folder}/ecm_chiller.osm") if save_intermediate_models
    rescue StandardError => error
      msg = "Model creation failed for #{name}\n#{__FILE__}::#{__method__} #{error.message}"
      logger.error(msg)
      return [ERROR: msg]
    end

    ##### Gather info of VSD chillers in the model.
    model.getChillerElectricEIRs.sort.each do |chiller|
      ref_capacity_w = chiller.referenceCapacity.to_f
      next if ref_capacity_w < 0.1 # was < 0.0011
      
      chiller_name = chiller.name.get
      captf_curve_name, captf_curve_type, captf_corr_coeff = get_curve_info(chiller.coolingCapacityFunctionOfTemperature)
      eirft_curve_name, eirft_curve_type, eirft_corr_coeff = get_curve_info(chiller.electricInputToCoolingOutputRatioFunctionOfTemperature)
      eitfplr_curve_name, eitfplr_curve_type, eitfplr_corr_coeff = get_curve_info(chiller.electricInputToCoolingOutputRatioFunctionOfPLR)
      results[chiller_name.to_sym] = {
          capacity_kW: (ref_capacity_w/1000.0).signif(3),
          COP: chiller.referenceCOP.signif(3),
          CAPFT_curve_name: captf_curve_name,
          CAPFT_curve_type: captf_curve_type,
          CAPFT_curve_coeffs: captf_corr_coeff,
          EIRFT_curve_name: eirft_curve_name,
          EIRFT_curve_type: eirft_curve_type,
          EIRFT_curve_coeffs: eirft_corr_coeff,
          EITFPLR_curve_name: eitfplr_curve_name,
          EITFPLR_curve_type: eitfplr_curve_type,
          EITFPLR_curve_coeffs: eitfplr_corr_coeff
      }
    end
    logger.info "Completed individual test: #{name}"
    return results
  end
end
