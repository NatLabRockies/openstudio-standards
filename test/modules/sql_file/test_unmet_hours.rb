require_relative '../../helpers/minitest_helper'
require 'minitest/mock'

class TestUnmetHours < Minitest::Test
  def setup
    @sql_file_path = 'output/AR/run/eplusout.sql'

    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)

    # load model and set weather file
    @model = std.safe_load_model("#{File.dirname(__FILE__)}/../../doe_prototype/regression_models/PrimarySchool-90.1-2013-ASHRAE 169-2013-4A_expected_result.osm")
    weather_file_path = OpenstudioStandards::Weather.climate_zone_representative_weather_file_path(climate_zone)
    epw_file = OpenStudio::EpwFile.new(weather_file_path)
    OpenStudio::Model::WeatherFile.setWeatherFile(@model, epw_file)

    # add extra output variables to test the detailed methods
    output_var = OpenStudio::Model::OutputVariable.new('Zone Air Temperature', @model)
    output_var.setReportingFrequency('Hourly')
    output_var = OpenStudio::Model::OutputVariable.new('Zone Thermostat Heating Setpoint Temperature', @model)
    output_var.setReportingFrequency('Hourly')
    output_var = OpenStudio::Model::OutputVariable.new('Zone Thermostat Cooling Setpoint Temperature', @model)
    output_var.setReportingFrequency('Hourly')

    # run simulation to create the .sql file
    std.model_run_simulation_and_log_errors(@model, 'output/AR')
    sql = OpenStudio::SqlFile.new(@sql_file_path)
    @model.setSqlFile(sql)
  end

  def test_model_get_annual_occupied_unmet_heating_hours_detailed
    result = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours_detailed(@model, tolerance: 2.0)
    assert_in_delta(79.0, result['sum_bldg_unmet_hours'], 1.0)
  end

  def test_model_get_annual_occupied_unmet_cooling_hours_detailed
    result = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours_detailed(@model, tolerance: 5.0)
    assert_in_delta(1946.0, result['sum_bldg_occupied_unmet_hours'], 10.0)
  end

  def test_model_get_annual_occupied_unmet_heating_hours
    result = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours(@model)
    assert_in_delta(0.67, result, 1.0)
  end

  def test_model_get_annual_occupied_unmet_cooling_hours
    result = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours(@model)
    assert_in_delta(230.33, result, 1.0)
  end

  def test_model_get_annual_occupied_unmet_hours
    result = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(@model)
    assert_in_delta(231.0, result, 1.0)
  end

  def test_thermal_zone_get_annual_occupied_unmet_heating_hours
    thermal_zone = @model.getThermalZoneByName('GYM_ZN_1_FLR_1 ZN').get
    result = OpenstudioStandards::SqlFile.thermal_zone_get_annual_occupied_unmet_heating_hours(thermal_zone)
    assert_in_delta(0.0, result, 1.0)
  end

  def test_thermal_zone_get_annual_occupied_unmet_cooling_hours
    thermal_zone = @model.getThermalZoneByName('GYM_ZN_1_FLR_1 ZN').get
    result = OpenstudioStandards::SqlFile.thermal_zone_get_annual_occupied_unmet_cooling_hours(thermal_zone)
    assert_in_delta(54.67, result, 1.0)
  end
end

class TestUnmetHoursAggregation < Minitest::Test
  def test_missing_results
    [[false, false], [false, 10.0], [10.0, false]].each do |heating_hours, cooling_hours|
      OpenstudioStandards::SqlFile.stub(:model_get_annual_occupied_unmet_heating_hours, heating_hours) do
        OpenstudioStandards::SqlFile.stub(:model_get_annual_occupied_unmet_cooling_hours, cooling_hours) do
          assert_equal(false, OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(nil))
        end
      end
    end
  end

  def test_valid_results
    [[0.0, 0.0], [10.0, 20.0]].each do |heating_hours, cooling_hours|
      OpenstudioStandards::SqlFile.stub(:model_get_annual_occupied_unmet_heating_hours, heating_hours) do
        OpenstudioStandards::SqlFile.stub(:model_get_annual_occupied_unmet_cooling_hours, cooling_hours) do
          assert_equal(heating_hours + cooling_hours, OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(nil))
        end
      end
    end
  end
end
