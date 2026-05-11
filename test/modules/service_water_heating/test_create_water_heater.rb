require_relative '../../helpers/minitest_helper'

class TestServiceWaterHeatingCreateWaterHeater < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating

    # load model and set up weather file
    template = '90.1-2010'
    @climate_zone = 'ASHRAE 169-2013-2A'
    @std = Standard.build(template)
    @model = @std.safe_load_model("#{File.dirname(__FILE__)}/../../os_stds_methods/models/QuickServiceRestaurant_2A_2010.osm")

    # create output directory
    FileUtils.mkdir_p "#{__dir__}/output"
  end

  def test_create_water_heater
    model = OpenStudio::Model::Model.new

    # default water heater
    water_heater1 = @swh.create_water_heater(model)

    # custom inputs
    volume = OpenStudio.convert(100.0, 'gal', 'm^3').get
    capacity =  OpenStudio.convert(200.0, 'kBtu/hr', 'W').get
    water_heater2 = @swh.create_water_heater(model,
                                             water_heater_capacity: volume,
                                             water_heater_volume: capacity)
  end

  def test_create_pumped_hpwh_ems
    # get existing water heater
    model = @model
    wh = model.getWaterHeaterMixedByName('100.0gal Natural Gas Water Heater - 100kBtu/hr 0.81 Therm Eff').get

    # create heat pump water heater
    hpwh = @swh.create_heatpump_water_heater(model,
                                             water_heater_capacity: wh.heaterMaximumCapacity.get,
                                             water_heater_volume: wh.tankVolume.get,
                                             service_water_temperature_schedule: wh.setpointTemperatureSchedule.get,
                                             water_heater_thermal_zone: model.getThermalZoneByName('Kitchen ZN').get,
                                             service_water_loop: wh.plantLoop.get,
                                             use_ems_control: true)

    # remove existing water heater
    wh.remove

    # set output directory
    output_dir = "#{__dir__}/output/test_create_pumped_hpwh_ems"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # run the model to make sure it applies correctly
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: @climate_zone)
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR")
    assert(annual_run_success)
    # model.save("#{output_dir}/out.osm", true)
  end

  def test_create_wrapped_hpwh_ems
    # get existing water heater
    model = @model
    wh = model.getWaterHeaterMixedByName('100.0gal Natural Gas Water Heater - 100kBtu/hr 0.81 Therm Eff').get

    # create heat pump water heater
    hpwh = @swh.create_heatpump_water_heater(model,
                                             heat_pump_type: 'WrappedCondenser',
                                             water_heater_capacity: wh.heaterMaximumCapacity.get,
                                             water_heater_volume: wh.tankVolume.get,
                                             service_water_temperature_schedule: wh.setpointTemperatureSchedule.get,
                                             water_heater_thermal_zone: model.getThermalZoneByName('Kitchen ZN').get,
                                             service_water_loop: wh.plantLoop.get,
                                             use_ems_control: true)

    # remove existing water heater
    wh.remove

    # set output directory
    output_dir = "#{__dir__}/output/test_create_wrapped_hpwh_ems"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # run the model to make sure it applies correctly
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: @climate_zone)
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR")
    assert(annual_run_success)
    # model.save("#{output_dir}/out.osm", true)
  end

  def test_create_wrapped_hpwh_no_ems
    # get existing water heater properties
    model = @model
    wh = model.getWaterHeaterMixedByName('100.0gal Natural Gas Water Heater - 100kBtu/hr 0.81 Therm Eff').get

    # create heat pump water heater
    hpwh = @swh.create_heatpump_water_heater(model,
                                             heat_pump_type: 'WrappedCondenser',
                                             water_heater_capacity: wh.heaterMaximumCapacity.get,
                                             water_heater_volume: wh.tankVolume.get,
                                             service_water_temperature_schedule: wh.setpointTemperatureSchedule.get,
                                             water_heater_thermal_zone: model.getThermalZoneByName('Kitchen ZN').get,
                                             service_water_loop: wh.plantLoop.get,
                                             use_ems_control: false)

    # remove existing water heater
    wh.remove

    # set output directory
    output_dir = "#{__dir__}/output/test_create_wrapped_hpwh_no_ems"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # run the model to make sure it applies correctly
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: @climate_zone)
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR")
    assert(annual_run_success)
    # model.save("#{output_dir}/out.osm", true)
  end
end
