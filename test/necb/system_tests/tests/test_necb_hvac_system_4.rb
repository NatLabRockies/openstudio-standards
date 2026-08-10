require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'

class NECB_HVAC_System_4_Matrix_Test < Minitest::Test
  include NecbHelper

  matrix = NecbHelper.test_case_matrix(
    boiler_fueltype:   ['NaturalGas', 'Electricity', 'FuelOilNo2'],
    heating_coil_type: ['Electric', 'Gas'],
    baseboard_type:    ['Hot Water', 'Electric']
  )

  matrix.each do |case_args|
    fuel_token      = NecbHelper.hvac_case_token(case_args[:boiler_fueltype])
    heating_token   = NecbHelper.hvac_case_token(case_args[:heating_coil_type])
    baseboard_token = NecbHelper.hvac_case_token(case_args[:baseboard_type])
    test_name       = "test_necb_hvac_system_4_#{fuel_token}_#{heating_token}_#{baseboard_token}"

    define_method(test_name) do
      weather_file  = 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'
      vintage       = 'NECB2011'
      output_folder = "#{File.dirname(__FILE__)}/output/#{test_name}"

      FileUtils.mkdir_p(output_folder)

      standard = Standard.build(vintage)
      name = "system_4_Boiler-#{case_args[:boiler_fueltype]}_HeatingCoilType#-#{case_args[:heating_coil_type]}_BaseboardType-#{case_args[:baseboard_type]}"
      model = standard.load_building_type_from_library(building_type: 'SmallOffice')
      standard.assign_building_activity(model: model)
      standard.assign_building_structure(model: model, activity: @activity)
      standard.apply_weather_data(model: model, epw_file: weather_file)
      standard.apply_loads(model: model)
      standard.apply_envelope(model: model)
      standard.apply_fdwr_srr_daylighting(model: model)
      standard.apply_auto_zoning(model: model, sizing_run_dir: output_folder)

      hw_loop = nil
      if case_args[:baseboard_type] == 'Hot Water'
        hw_loop = OpenStudio::Model::PlantLoop.new(model)
        standard.setup_hw_loop_with_components(model, hw_loop, case_args[:boiler_fueltype], case_args[:boiler_fueltype], model.alwaysOnDiscreteSchedule)
      end

      standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
        model:             model,
        zones:             model.getThermalZones,
        heating_coil_type: case_args[:heating_coil_type],
        baseboard_type:    case_args[:baseboard_type],
        hw_loop:           hw_loop
      )

      BTAP::FileIO::save_osm(model, "#{output_folder}/#{name}.hvacrb")
      result = run_necb_hvac_measure(model: model, standard: standard, sizing_dir: "#{output_folder}/#{name}/sizing")
      BTAP::FileIO::save_osm(model, "#{output_folder}/#{name}.osm")
      assert_equal(true, result, "Failure in Standards for #{name}")

      result = standard.model_run_simulation_and_log_errors(model, "#{output_folder}/#{name}/")
      result = result && necb_hvac_simulation_clean?(model)
      assert_equal(true, result, "Failure in Standards for #{name}")
    end
  end
end
