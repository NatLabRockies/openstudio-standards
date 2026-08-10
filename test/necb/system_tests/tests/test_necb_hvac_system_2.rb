require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'

class NECB_HVAC_System_2_Matrix_Test < Minitest::Test
  include NecbHelper

  matrix = NecbHelper.test_case_matrix(
    boiler_fueltype:  ['NaturalGas', 'Electricity', 'FuelOilNo2'],
    chiller_type:     ['Scroll', 'Centrifugal', 'Rotary Screw', 'Reciprocating'],
    mua_cooling_type: ['Hydronic', 'DX'],
    fan_coil_type:    ['FPFC']
  )

  matrix.each do |case_args|
    fuel_token     = NecbHelper.hvac_case_token(case_args[:boiler_fueltype])
    chiller_token  = NecbHelper.hvac_case_token(case_args[:chiller_type])
    mua_token      = NecbHelper.hvac_case_token(case_args[:mua_cooling_type])
    fan_coil_token = NecbHelper.hvac_case_token(case_args[:fan_coil_type])
    test_name      = "test_necb_hvac_system_2_#{fuel_token}_#{chiller_token}_#{mua_token}_#{fan_coil_token}"

    define_method(test_name) do
      weather_file      = 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw'
      template_osm_file = "#{__dir__}/../../models/5ZoneNoHVAC.osm"
      vintage           = 'NECB2011'
      output_folder     = "#{File.dirname(__FILE__)}/output/#{test_name}"

      FileUtils.mkdir_p(output_folder)

      model = BTAP::FileIO::load_osm(template_osm_file)
      standard = Standard.build(vintage)
      boiler_fueltype = standard.validate_primary_heating_fuel(primary_heating_fuel: case_args[:boiler_fueltype], model: model)
      standard.fuel_type_set = SystemFuels.new()
      standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: boiler_fueltype)

      name = "sys2_Boiler-#{boiler_fueltype}_Chiller-#{case_args[:chiller_type]}_MuACoolingType-#{case_args[:mua_cooling_type]}"
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      standard.setup_hw_loop_with_components(model, hw_loop, boiler_fueltype, boiler_fueltype, model.alwaysOnDiscreteSchedule)
      standard.add_sys2_FPFC_sys5_TPFC(
        model:            model,
        zones:            model.getThermalZones,
        chiller_type:     case_args[:chiller_type],
        fan_coil_type:    case_args[:fan_coil_type],
        mau_cooling_type: case_args[:mua_cooling_type],
        hw_loop:          hw_loop
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
