require_relative '../../helpers/minitest_helper'

class TestServiceWaterHeatingCreatePipingLosses < Minitest::Test
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

  def test_create_piping_losses_defaults
    # get existing service water heating loop
    model = @model
    swh_loop = model.getPlantLoopByName('Main Service Water Loop').get
    result = @swh.create_service_water_heating_piping_losses(model, swh_loop)
    assert(result)

    # expected pipe length
    floor_area = model.getBuilding.floorArea
    floor_area_ft2 = OpenStudio.convert(floor_area, 'm^2', 'ft^2').get
    number_of_stories = model.getBuilding.buildingStories.size
    expected_pipe_length_ft = 2.0 * (Math.sqrt(floor_area_ft2 / number_of_stories) + (10.0 * (number_of_stories - 1.0)))

    actual_pipe_length_m = model.getPipeIndoors[0].pipeLength
    actual_pipe_length_ft = OpenStudio.convert(actual_pipe_length_m, 'm', 'ft').get
    assert_in_delta(expected_pipe_length_ft.round, actual_pipe_length_ft, 0.1)
  end

  def test_create_piping_losses_custom_length
    # get existing service water heating loop
    model = @model
    swh_loop = model.getPlantLoopByName('Main Service Water Loop').get
    result = @swh.create_service_water_heating_piping_losses(model, swh_loop,
                                                             circulating: false,
                                                             pipe_insulation_thickness: 0.0254,
                                                             pipe_length: 12.2)

    assert(result)
    pipe = model.getPipeIndoorByName('Main Service Water Loop Pipe 40ft').get
    assert_in_delta(12.2, pipe.pipeLength, 0.001)
    assert_equal('Copper pipe 0.75in type L with 1.0in fiberglass batt', pipe.construction.get.name.get)
  end
end
