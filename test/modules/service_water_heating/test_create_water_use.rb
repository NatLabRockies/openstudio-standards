require_relative '../../helpers/minitest_helper'

class TestServiceWaterHeatingCreateWaterUse < Minitest::Test
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

  def test_create_water_use
    # get existing service water heating loop
    model = @model
    swh_loop = model.getPlantLoopByName('Main Service Water Loop').get
    space = model.getSpaceByName('Kitchen').get
    flow_rate = OpenStudio.convert(1.0, 'gal/min', 'm^3/s').get
    flow_rate_fraction_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                  0.5,
                                                                                                  name: 'Water Use Fraction Schedule',
                                                                                                  schedule_type_limit: 'Fractional')

    water_use_fixture = @swh.create_water_use(model,
                                              name: 'Test Water Use',
                                              flow_rate: flow_rate,
                                              flow_rate_fraction_schedule: flow_rate_fraction_schedule,
                                              water_use_temperature: 50.0,
                                              sensible_fraction: 0.25,
                                              latent_fraction: 0.10,
                                              service_water_loop: swh_loop,
                                              space: space)

    assert_equal('Water Use Fraction Schedule', water_use_fixture.flowRateFractionSchedule.get.name.get)
    assert_equal('Kitchen', water_use_fixture.space.get.name.get)
    assert_in_delta(flow_rate, water_use_fixture.waterUseEquipmentDefinition.peakFlowRate, 0.000001)

    # set output directory
    output_dir = "#{__dir__}/output/test_create_water_use"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # run the model to make sure it applies correctly
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: @climate_zone)
    annual_run_success = @std.model_run_simulation_and_log_errors(model, "#{output_dir}/AR")
    assert(annual_run_success)
    #model.save("#{output_dir}/out.osm", true)
  end
end
