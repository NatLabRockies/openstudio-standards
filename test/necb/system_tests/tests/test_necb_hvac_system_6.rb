require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'

class NECB_HVAC_System_6_Matrix_Test < Minitest::Test
  include NecbHelper

  matrix = NecbHelper.test_case_matrix(
    boiler_fueltype:   ['NaturalGas', 'Electricity', 'FuelOilNo2'],
    heating_coil_type: ['Electric', 'Hot Water'],
    baseboard_type:    ['Hot Water', 'Electric'],
    chiller_type:      ['Scroll'],
    fan_type:          ['AF_or_BI_rdg_fancurve', 'AF_or_BI_inletvanes', 'FC_inletvanes', 'var_speed_drive']
  )

  matrix.each do |case_args|
    fuel_token      = NecbHelper.hvac_case_token(case_args[:boiler_fueltype])
    heating_token   = NecbHelper.hvac_case_token(case_args[:heating_coil_type])
    baseboard_token = NecbHelper.hvac_case_token(case_args[:baseboard_type])
    chiller_token   = NecbHelper.hvac_case_token(case_args[:chiller_type])
    fan_token       = NecbHelper.hvac_case_token(case_args[:fan_type])
    test_name       =
      "test_necb_hvac_system_6_#{fuel_token}_#{heating_token}_#{baseboard_token}__#{chiller_token}_#{fan_token}"

    define_method(test_name) do
      weather_file      = 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'
      template_osm_file = "#{__dir__}/../../models/5ZoneNoHVAC.osm"
      vintage           = 'NECB2011'
      output_folder     = "#{File.dirname(__FILE__)}/output/#{test_name}"

      FileUtils.mkdir_p(output_folder)

      standard = Standard.build(vintage)
      name = "sys6_Bo-#{case_args[:boiler_fueltype]}_Ch-#{case_args[:chiller_type]}_BB-#{case_args[:baseboard_type]}_HC-#{case_args[:heating_coil_type]}_Fan-#{case_args[:fan_type]}"
      model = BTAP::FileIO::load_osm(template_osm_file)

      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)

      hw_loop = nil
      if case_args[:baseboard_type] == 'Hot Water' || case_args[:heating_coil_type] == 'Hot Water'
        hw_loop = OpenStudio::Model::PlantLoop.new(model)
        standard.setup_hw_loop_with_components(model, hw_loop, case_args[:boiler_fueltype], case_args[:boiler_fueltype], model.alwaysOnDiscreteSchedule)
      end

      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model:             model,
        zones:             model.getThermalZones,
        heating_coil_type: case_args[:heating_coil_type],
        baseboard_type:    case_args[:baseboard_type],
        chiller_type:      case_args[:chiller_type],
        fan_type:          case_args[:fan_type],
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
