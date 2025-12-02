require_relative '../helpers/minitest_helper'
require_relative 'create_performance_rating_method_helper'

class PerformanceRatingMethodBaselineWorkflowTest < Minitest::Test

  def test_create_prm_baseline_building
    # set output directory
    output_dir = "#{__dir__}/output/#{__method__}"
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # generate model with create_bar
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 37500.0
    args['bldg_type_a'] = 'SecondarySchool'
    args['template'] = "ComStock DOE Ref Pre-1980"
    result = OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(model, args)

    # set_cliamte_zone
    climate_zone = 'ASHRAE 169-2013-4A'
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # create typical building
    template = '90.1-2007'
    result = OpenstudioStandards::CreateTypical.create_typical_building_from_model(model, template,
                                                                                   climate_zone: climate_zone,
                                                                                   sizing_run_directory: output_dir)

    # save to models directory
    model.save('models/prm_base_bldg.osm', true)

    # create prm baseline
    model_name = 'prm_base_bldg'
    base_model = create_baseline_model(model_name, template, climate_zone, 'SecondarySchool', debug = true, load_existing_model = true)
  end
end
