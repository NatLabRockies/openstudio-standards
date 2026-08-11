require_relative '../../../helpers/minitest_helper'

class NECB_Geometry_Options_Tests < Minitest::Test
  def setup
    @standard = Standard.build('NECB2011')
  end

  def test_clean_and_scale_model_applies_scale_arguments
    model = @standard.load_building_type_from_library(building_type: 'SmallOffice')
    original_x, original_y = BTAP::Geometry.model_horizontal_dimensions(model)

    @standard.clean_and_scale_model(model: model, scale_x: 2.0, scale_y: 1.0, scale_z: 1.0)

    scaled_x, scaled_y = BTAP::Geometry.model_horizontal_dimensions(model)
    assert_in_delta(original_x * 2.0, scaled_x, 0.001)
    assert_in_delta(original_y, scaled_y, 0.001)
  end

  def test_clean_and_scale_model_applies_footprint_aspect_ratio
    model = @standard.load_building_type_from_library(building_type: 'SmallOffice')
    original_floor_area = model.getBuilding.floorArea

    @standard.clean_and_scale_model(model: model, footprint_aspect_ratio: 3.0)

    x_dimension, y_dimension = BTAP::Geometry.model_horizontal_dimensions(model)
    assert_in_delta(3.0, [x_dimension, y_dimension].max / [x_dimension, y_dimension].min, 0.001)
    assert_in_delta(original_floor_area, model.getBuilding.floorArea, 0.001)
  end
end