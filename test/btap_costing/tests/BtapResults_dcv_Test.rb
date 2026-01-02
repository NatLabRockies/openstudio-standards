require_relative '../../../lib/openstudio-standards.rb'
require_relative '../../../lib/openstudio-standards/btap/btap_test_helper.rb'
require 'minitest/autorun'
require 'optparse'
require 'fileutils'
require 'minitest/unit'
require 'optparse'

class BTAPResults_Test < Minitest::Test
  def test_qaqc()
    #building_type = 'Outpatient'
    #building_type = 'LargeHotel'
    building_type = 'FullServiceRestaurant'
    #building_type = 'Warehouse'
    # building_type = 'LargeOffice'
    #building_type = 'MediumOffice'
    #building_type = 'MidriseApartment'

    #epw_file = "CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw"
    epw_file = "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"
    #epw_file = "CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw"
    #epw_file = "CAN_AB_Fort.Mcmurray.AP.716890_CWEC2020.epw"
    #epw_file = "CAN_NS_Halifax.Dockyard.713280_CWEC2020.epw"
    #epw_file = "CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw"
    #epw_file = "CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw"
    #epw_file = "CAN_NT_Yellowknife.AP.719360_CWEC2020.epw"

    #template = 'BTAPPRE1980'
    #template = 'BTAP1980TO2010'
    template = 'NECB2011'
    #template = 'NECB2015'
    # template = 'NECB2017'

    # dcv_type = 'NECB_Default'
    # dcv_type = 'No_DCV'
    dcv_type = 'Occupancy_based_DCV'
    # dcv_type = 'CO2_based_DCV'

    create_model_simulate_and_qaqc_regression_test(epw_file: epw_file,
                                                   template: template,
                                                   building_type: building_type,
                                                   dcv_type: dcv_type,
                                                   cached: BTAPResultsHelper.cached)
  end

  def create_model_simulate_and_qaqc_regression_test(epw_file:,
                                                     template:,
                                                     building_type:,
                                                     dcv_type:,
                                                     cached: false)

    model_name = "#{building_type}-#{template}-#{File.basename(epw_file, '.epw')}-#{dcv_type}"
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
        primary_heating_fuel: 'FuelOilNo2',
        dcv_type: dcv_type,
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
        chiller_type: nil,
        occupancy_loads_scale: nil,
        electrical_loads_scale: nil,
        oa_scale: nil,
        infiltration_scale: nil,
        output_variables: nil,
        shw_scale: nil,
        output_meters: nil,
        airloop_economizer_type: nil,
        baseline_system_zones_map_option: nil)

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
