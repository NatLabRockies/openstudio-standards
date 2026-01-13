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
class BTAPResults_VRF_Test < Minitest::Test
  def test_qaqc()
    #building_type = 'Outpatient'
    #building_type = 'LargeHotel'
    #building_type = 'FullServiceRestaurant'
    #building_type = 'Warehouse'
    building_type = 'LargeOffice'
    #building_type = 'MediumOffice'
    #building_type = 'MidriseApartment'
    #building_type = 'SmallOffice'
    #building_type = 'HighriseApartment'
    #building_type = 'LowriseApartment'

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
    #template = 'NECB2011'
    #template = 'NECB2015'
    template = 'NECB2017'

    #primary_heating_fuel = 'DefaultFuel'
    primary_heating_fuel = 'NaturalGas'
    #primary_heating_fuel = 'Electricity'

    dcv_type = 'NECB_Default'
    #dcv_type = 'No_DCV'
    #dcv_type = 'Occupancy_based_DCV'
    #dcv_type = 'CO2_based_DCV'

    daylighting_type = 'NECB_Default'
    #daylighting_type = 'add_daylighting_controls'

    lights_type = 'NECB_Default'
    #lights_type = 'LED'

    lights_scale = 1.0

    #ecm_system_name = 'NECB_Default'
    #ecm_system_name = 'HS09_CCASHPSys'
    ecm_system_name = 'HS08_CCASHP_VRF'
    #ecm_system_name = 'Remove_AirLoops_Add_Zone_Baseboards'

    erv_package = 'NECB_Default'
    #erv_package = 'Rotary-NREL-NZE'
    #erv_package = 'Rotary-NREL-NZE_All_'
    #erv_package = 'Plate-NREL-NZE-EXISTING'
    #erv_package = 'Plate-NREL-NZE-ALL'
    #erv_package = 'Rotary-Minimum-Eff-Existing'

    boiler_eff = 'NECB_Default'
    #boiler_eff = 'NECB 88% Efficient Condensing Boiler'
    #boiler_eff = 'Viessmann Vitocrossal 300 CT3-17 96.2% Efficient Condensing Gas Boiler'

    furnace_eff = 'NECB_Default'
    #furnace_eff = 'NECB 85% Efficient Condensing Gas Furnace'

    unitary_cop = 'NECB_Default'
    #unitary_cop = 'Carrier WeatherExpert'

    shw_eff = 'NECB_Default'
    #shw_eff = 'Natural Gas Power Vent with Electric Ignition'
    #shw_eff = 'Natural Gas Direct Vent with Electric Ignition'

    # baseline_system_zones_map_option = 'one_sys_per_dwelling_unit' # same as nil, 'NECB_Default', 'none'
    baseline_system_zones_map_option = 'one_sys_per_bldg'

    create_model_simulate_and_qaqc_regression_test(epw_file: epw_file,
                                                   template: template,
                                                   building_type: building_type,
                                                   primary_heating_fuel: primary_heating_fuel,
                                                   dcv_type: dcv_type,
                                                   daylighting_type: daylighting_type,
                                                   lights_type: lights_type,
                                                   lights_scale: lights_scale,
                                                   ecm_system_name: ecm_system_name,
                                                   erv_package: erv_package,
                                                   boiler_eff: boiler_eff,
                                                   furnace_eff: furnace_eff,
                                                   unitary_cop: unitary_cop,
                                                   shw_eff: shw_eff,
                                                   cached: BTAPResultsHelper.cached)
  end

  def create_model_simulate_and_qaqc_regression_test(epw_file:,
                                                     template:,
                                                     building_type:,
                                                     primary_heating_fuel: 'DefaultFuel',
                                                     dcv_type: 'NECB_Default',
                                                     daylighting_type: 'NECB_Default',
                                                     lights_type: 'NECB_Default',
                                                     lights_scale: 1.0,
                                                     ecm_system_name: 'NECB_Default',
                                                     erv_package: 'NECB_Default',
                                                     boiler_eff: 'NECB_Default',
                                                     furnace_eff: 'NECB_Default',
                                                     unitary_cop: 'NECB_Default',
                                                     shw_eff: 'NECB_Default',
                                                     cached: false)

    model_name = "#{building_type}-#{template}-DefaultFuel-#{File.basename(epw_file, '.epw')}_VRF"
    test_dir   = "#{File.dirname(__FILE__)}/output"
    run_dir    = "#{test_dir}/#{model_name}"
    helper     = BTAPResultsHelper.new(test_path: __FILE__, model_name: model_name, run_dir: run_dir)

    Dir.mkdir(test_dir) unless Dir.exist?(test_dir)
    Dir.mkdir(run_dir) unless Dir.exist?(run_dir)

    if !cached
      standard = Standard.build("#{template}")
      ecm = ECMS.new  #Sara
      model_name = "#{building_type}-#{template}-DefaultFuel-#{File.basename(epw_file, '.epw')}_VRF"
      model = standard.load_building_type_from_library(building_type: building_type)
      standard.model_apply_standard(
        model: model,
        epw_file: epw_file,
        sizing_run_dir: run_dir,
        primary_heating_fuel: primary_heating_fuel,
        dcv_type: dcv_type,
        lights_type: lights_type,
        lights_scale: lights_scale,
        daylighting_type: daylighting_type,
        ecm_system_name: ecm_system_name,
        ecm_system_zones_map_option: nil,
        erv_package: erv_package,
        boiler_eff: boiler_eff,
        unitary_cop: unitary_cop,
        furnace_eff: furnace_eff,
        shw_eff: shw_eff,
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
