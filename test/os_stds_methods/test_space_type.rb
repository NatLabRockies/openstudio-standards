require_relative '../helpers/minitest_helper'

class TestSpaceType < Minitest::Test
  def test_apply_internal_loads
    test_name = 'test_apply_internal_loads'
    # Load model
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/models/basic_2_story_office_no_hvac_20WWR_data_center.osm")

    data_center_space_type = model.getSpaceTypeByName('Data Center').get
    value = std.space_type_apply_internal_loads(data_center_space_type)
    assert(!value.nil?)
  end
end
