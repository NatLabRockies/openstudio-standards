require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class ECM_NatVent_Tests < Minitest::Test

  # Set to true to run the standards in the test.
  PERFORM_STANDARDS = true

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the ventilation requirements.
  # Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_natural_vent
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: true,
                        epw_file: 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw',
                        fuel_type: 'NaturalGas' }

    # Define test cases.
    test_cases = {}

    test_cases_hash = {
      vintage: ['NECB2017'], #@AllTemplates,
      archetype: ['FullServiceRestaurant', 'SmallHotel'],
      TestCase: ["ZoneResults"],
      TestPars: {  } # :oaf => "tbd"
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
    msg = "Natural ventilation ECM test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_ventilation that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_natural_vent(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    vintage = test_pars[:vintage]
    building_type = test_pars[:archetype]
    epw_file = test_pars[:epw_file]
    fuel_type = test_pars[:fuel_type]

    name = "#{vintage}_#{building_type}_#{fuel_type}_#{epw_file}"
    name_short = "#{vintage}_#{building_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}/")
    logger.info "Starting individual test: #{name}"
    results = {}

    # (1) Create archetype with NV active
    # (2) loop through space types in the model and change them to the desired space type
    # (3) call standard.model_add_loads(model, 'NECB_Default', 1.0)
    # (4) check ventilation

    # Wrap test in begin/rescue/ensure.
    begin

      # Load osm geometry and spactypes from library.
      standard = get_standard(vintage)
      model = standard.load_building_type_from_library(building_type: building_type)

      # Update model to match vintage, turn on NV.
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
                                    nv_type: 'add_nv', # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_nv'
                                    nv_opening_fraction: 'NECB_Default', # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 0.1), (3) opening fraction of windows, which can be a float number between 0.0 and 1.0
                                    nv_temp_out_min: 'NECB_Default', # options: (1) nil/none/false(2) 'NECB_Default' (i.e. 13.0 based on inputs from Michel Tardif re a real school in QC), (3) minimum outdoor air temperature (in Celsius) below which natural ventilation is shut down
                                    nv_delta_temp_in_out: 'NECB_Default', # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 1.0 based on inputs from Michel Tardif re a real school in QC), (3) temperature difference (in Celsius) between the indoor and outdoor air temperatures below which ventilation is shut down
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
    rescue StandardError => error
      msg = "Model creation failed for #{name}\n#{__FILE__}::#{__method__} #{error.message}"
      logger.error(msg)
      return [ERROR: msg]
    end

    ##### Gather information about ZoneVentilationDesignFlowRate & ZoneVentilationWindandStackOpenArea
    model.getHVACComponents.sort.each do |hvac_component|
      if hvac_component.to_ZoneHVACComponent.is_initialized
        zn_hvac_component = hvac_component.to_ZoneHVACComponent.get

        ### Gather information about ZoneVentilationDesignFlowRate
        if zn_hvac_component.to_ZoneVentilationDesignFlowRate.is_initialized
          zn_vent_design_flow_rate = zn_hvac_component.to_ZoneVentilationDesignFlowRate.get
          zn_vent_design_flow_rate_name = zn_vent_design_flow_rate.name.to_s

          thermal_zone = zn_hvac_component.thermalZone.get

          thermal_zone.spaces.sort.each do |space|
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - DesignFlowRateCalculationMethod"] = zn_vent_design_flow_rate.designFlowRateCalculationMethod
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - FlowRateperPerson"] = zn_vent_design_flow_rate.flowRateperPerson
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - FlowRateperFloorArea"] = zn_vent_design_flow_rate.flowRateperZoneFloorArea
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - VentilationType"] = zn_vent_design_flow_rate.ventilationType
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - MinimumIndoorTemperatureSchedule"] = zn_vent_design_flow_rate.minimumIndoorTemperatureSchedule.get.name.to_s
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - MaximumIndoorTemperatureSchedule"] = zn_vent_design_flow_rate.maximumIndoorTemperatureSchedule.get.name.to_s
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - MinimumOutdoorTemperature"] = zn_vent_design_flow_rate.minimumOutdoorTemperature
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - MaximumOutdoorTemperature"] = zn_vent_design_flow_rate.maximumOutdoorTemperature
            results["#{space.name.to_s} - #{zn_vent_design_flow_rate_name} - DeltaTemperature"] = zn_vent_design_flow_rate.deltaTemperature
          end
        end

        ### Gather information about ZoneVentilationWindandStackOpenArea
        if zn_hvac_component.to_ZoneVentilationWindandStackOpenArea.is_initialized
          zn_vent_wind_and_stack = zn_hvac_component.to_ZoneVentilationWindandStackOpenArea.get
          zn_vent_wind_and_stack_name = zn_vent_wind_and_stack.name.to_s

          thermal_zone = zn_hvac_component.thermalZone.get

          thermal_zone.spaces.sort.each do |space|
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - OpeningArea"] = zn_vent_wind_and_stack.openingArea
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - OpeningAreaFractionSchedule"] = zn_vent_wind_and_stack.openingAreaFractionSchedule.name.to_s
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - EffectiveAngle"] = zn_vent_wind_and_stack.effectiveAngle
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - MinimumIndoorTemperatureSchedule"] = zn_vent_wind_and_stack.minimumIndoorTemperatureSchedule.get.name.to_s
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - MaximumIndoorTemperatureSchedule"] = zn_vent_wind_and_stack.maximumIndoorTemperatureSchedule.get.name.to_s
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - MinimumOutdoorTemperature"] = zn_vent_wind_and_stack.minimumOutdoorTemperature
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - MaximumOutdoorTemperature"] = zn_vent_wind_and_stack.maximumOutdoorTemperature
            results["#{space.name.to_s} - #{zn_vent_wind_and_stack_name} - DeltaTemperature"] = zn_vent_wind_and_stack.deltaTemperature
          end
        end
      end #if hvac_component.to_ZoneHVACComponent.is_initialized
    end #model.getHVACComponents.sort.each do |hvac_component|

    ### Gather information about AvailabilityManagerHybridVentilation
    model.getSpaces.sort.each do |space|
      thermal_zone = space.thermalZone
      if thermal_zone.is_initialized
        thermal_zone = space.thermalZone.get
        thermal_zone.airLoopHVACs.sort.each do |air_loop|
          air_loop.availabilityManagers.sort.each do |avail_mgr|
            if avail_mgr.to_AvailabilityManagerHybridVentilation.is_initialized
              avail_mgr_hybr_vent = avail_mgr.to_AvailabilityManagerHybridVentilation.get
              results["#{space.name.to_s} - #{avail_mgr_hybr_vent.name.to_s} - MinimumOutdoorTemperature"] = avail_mgr_hybr_vent.minimumOutdoorTemperature
              results["#{space.name.to_s} - #{avail_mgr_hybr_vent.name.to_s} - MaximumOutdoorTemperature"] = avail_mgr_hybr_vent.maximumOutdoorTemperature
            end
          end
        end
      end
    end
    logger.info "Completed individual test: #{name}"
    return results
  end
end
