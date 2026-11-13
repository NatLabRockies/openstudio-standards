require_relative '../../helpers/minitest_helper'

class TestSpaceTypeInformation < Minitest::Test
  def test_space_type_get_largest_thermal_zone
    std = Standard.build('90.1-2013')
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    classroom_space_type = model.getSpaceTypeByName('PrimarySchool Classroom').get
    largest_thermal_zone = OpenstudioStandards::SpaceType.space_type_get_largest_thermal_zone(classroom_space_type)
    assert_equal('TZ-Mult_Class_1_Pod_1_ZN_1_FLR_1', largest_thermal_zone.name.to_s)
  end
end
