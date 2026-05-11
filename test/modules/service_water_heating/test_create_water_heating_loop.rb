require_relative '../../helpers/minitest_helper'

class TestServiceWaterHeatingCreateWaterHeatingLoop < Minitest::Test
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

  def test_create_service_water_heating_loop
    # get existing service water heating loop
    model = @model
    swh_loop = model.getPlantLoopByName('Main Service Water Loop').get

    # set output directory
    output_dir = "#{__dir__}/output/test_create_service_water_heating_loop"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # run the model to get the previous water use
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: @climate_zone)
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/pre/AR")
    assert(annual_run_success)
    # model.save("#{output_dir}/pre/pre.osm", true)

    # replace the service water heating loop and rerun
    swh_loop.remove
    service_water_loop = @swh.create_service_water_heating_loop(model, water_heater_fuel: 'NaturalGas')

    water_fixture = model.getWaterUseEquipments[0]
    swh_connection = OpenStudio::Model::WaterUseConnections.new(model)
    swh_connection.addWaterUseEquipment(water_fixture)
    service_water_loop.addDemandBranchForComponent(swh_connection)

    # run the model to check that the new energy use is similar
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/post/AR")
    assert(annual_run_success)
    # model.save("#{output_dir}/post/post.osm", true)
  end

  def test_create_booster_water_heating_loop
    # get existing service water heating loop
    model = @model
    swh_loop = model.getPlantLoopByName('Main Service Water Loop').get

    booster_loop = @swh.create_booster_water_heating_loop(model,
                                                          water_heater_capacity: 12000.0,
                                                          water_heater_volume: OpenStudio.convert(10.0, 'gal', 'm^3').get,
                                                          water_heater_fuel: 'Electricity',
                                                          on_cycle_parasitic_fuel_consumption_rate: 3.0,
                                                          off_cycle_parasitic_fuel_consumption_rate: 3.0,
                                                          service_water_temperature: 85.0,
                                                          service_water_loop: swh_loop)

    # set output directory
    output_dir = "#{__dir__}/output/test_create_booster_water_heating_loop"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # run the model to make sure it applies correctly
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: @climate_zone)
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR")
    assert(annual_run_success)
    # model.save("#{output_dir}/out.osm", true)
  end
end
