require_relative '../../../lib/openstudio-standards.rb'
require_relative '../../../lib/openstudio-standards/btap/btap_test_helper.rb'
require 'minitest/autorun'
require 'optparse'
require 'fileutils'
require 'minitest/unit'
require 'optparse'

# NOTE: Runs are cached automatically. To run this test with an annual
# simulation and update the cache, pass the RERUN_CACHED=true environment
# variable pair to the test file, for example:
# RERUN_CACHED=true bundle exec ruby [test_file]
class BTAPResults_Test < Minitest::Test
  def test_qaqc()
    #building_type = 'Outpatient'
    building_type = 'LargeHotel'
    #building_type = 'FullServiceRestaurant'
    #building_type = 'Warehouse'
    #building_type = 'LargeOffice'
    #building_type = 'MediumOffice'
    #building_type = 'MidriseApartment'

    #epw_file = "CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw"
    #epw_file = "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"
    #epw_file = "CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw"
    #epw_file = "CAN_AB_Fort.Mcmurray.AP.716890_CWEC2020.epw"
    #epw_file = "CAN_NS_Halifax.Dockyard.713280_CWEC2020.epw"
    #epw_file = "CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw"
    #epw_file = "CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw"
    epw_file = "CAN_NT_Yellowknife.AP.719360_CWEC2020.epw"

    #template = 'BTAPPRE1980'
    template = 'BTAP1980TO2010'
    #template = 'NECB2011'
    #template = 'NECB2015'
    #template = 'NECB2017'

    dcv_type = 'NECB_Default'

    daylighting_type = 'NECB_Default'

    lights_type = 'NECB_Default'

    lights_scale = 1.0

    # baseline_system_zones_map_option = 'one_sys_per_dwelling_unit' # same as nil, 'NECB_Default', 'none'
    baseline_system_zones_map_option = 'one_sys_per_bldg'

    create_model_simulate_and_qaqc_regression_test(epw_file: epw_file,
                                                   template: template,
                                                   building_type: building_type,
                                                   dcv_type: dcv_type,
                                                   daylighting_type: daylighting_type,
                                                   lights_type: lights_type,
                                                   lights_scale: lights_scale,
                                                   baseline_system_zones_map_option: baseline_system_zones_map_option,
                                                   cached: BTAPResultsHelper.cached)
  end

  def create_model_simulate_and_qaqc_regression_test(epw_file:,
                                                     template:,
                                                     building_type:,
                                                     dcv_type:,
                                                     daylighting_type:,
                                                     lights_type:,
                                                     lights_scale:,
                                                     baseline_system_zones_map_option:,
                                                     cached: false)

    model_name = "#{building_type}-#{template}-DefaultFuel-#{File.basename(epw_file, '.epw')}"
    test_dir   = "#{File.dirname(__FILE__)}/output"
    run_dir    = "#{test_dir}/#{model_name}"
    helper     = BTAPResultsHelper.new(test_path: __FILE__, model_name: model_name, run_dir: run_dir)

    Dir.mkdir(test_dir) unless Dir.exist?(test_dir)
    Dir.mkdir(run_dir) unless Dir.exist?(run_dir)

    if !cached
      standard = Standard.build("#{template}")
      model = standard.load_building_type_from_library(building_type: building_type)
      standard.model_apply_standard(
        model: model,
        epw_file: epw_file,
        sizing_run_dir: run_dir,
        primary_heating_fuel: 'FuelOilNo2', # Replaced DefaultFuel by FuelOilNo2 as the primary_heating_fuels can be only NaturalGas or Electricity or FuelOilNo2 (see 'fuel_type_sets.json' of openstudio-standards)
        dcv_type: dcv_type,
        lights_type: lights_type,
        lights_scale: lights_scale,
        daylighting_type: daylighting_type,
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
        chiller_type: nil,
        occupancy_loads_scale: nil,
        electrical_loads_scale: nil,
        oa_scale: nil,
        infiltration_scale: nil,
        output_variables: nil,
        shw_scale: nil,
        output_meters: nil,
        airloop_economizer_type: nil,
        baseline_system_zones_map_option: baseline_system_zones_map_option)
      # standard.clean_and_scale_model(model: model, rotation_degrees: nil, scale_x: nil, scale_y: nil, scale_z: nil)
      # standard.apply_weather_data(model: model, epw_file: epw_file)
      # standard.apply_loads(model: model, lights_type: lights_type, lights_scale: lights_scale)  #Sara
      # standard.apply_envelope( model: model)
      # standard.apply_fdwr_srr_daylighting(model: model)
      # standard.apply_auto_zoning(model: model, sizing_run_dir: run_dir)
      # standard.apply_systems_and_efficiencies(model: model,
      #                                         primary_heating_fuel: 'DefaultFuel', #NOTE: primary_heating_fuel" has been set to "DefaultFuel" instead of 'FuelOilNo2' and its associated "model_name" has been changed in a way to use an expected result file that already exits on github.
      #                                         sizing_run_dir: run_dir,
      #                                         dcv_type: 'NECB_Default',
      #                                         ecm_system_name: 'NECB_Default',
      #                                         erv_package: 'NECB_Default',
      #                                         boiler_eff: nil,
      #                                         furnace_eff: nil,
      #                                         shw_eff: nil,
      #                                         daylighting_type: 'NECB_Default',
      #                                         pv_ground_type: nil,  #Sara
      #                                         pv_ground_total_area_pv_panels_m2: nil,
      #                                         pv_ground_tilt_angle: nil,
      #                                         pv_ground_azimuth_angle: nil,
      #                                         pv_ground_module_description: nil,
      #                                         shw_scale: 'NECB_Default',
      #                                         baseline_system_zones_map_option: baseline_system_zones_map_option)
      # model = standard.apply_loop_pump_power(model: model, sizing_run_dir: run_dir)

      standard.model_run_simulation_and_log_errors(model, run_dir)

      model_out_path = "#{run_dir}/final.osm"
      sql_path = "#{run_dir}/run/eplusout.sql"
      model.save(model_out_path, true)
      post_analysis = BTAPDatapointAnalysis.new(
        model: model,
        output_folder: run_dir,
        template: template,
        standard: standard,
        qaqc: nil)
    else
      post_analysis = helper.get_analysis(output_folder: run_dir, template: template)
    end

    cost_result = post_analysis.run_costing
    helper.evaluate_regression_files(test_instance: self, cost_result: cost_result)
  end
end
