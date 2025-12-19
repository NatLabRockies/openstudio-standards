require_relative '../helpers/minitest_helper'

class TestFindSpaceTypeStandardsData < Minitest::Test

  def test_find_space_type_standards_data_valid_standards

    # for now this just runs for single building type and climate zone, but could sweep across larger selection
    template = '90.1-2013'
    standard_building_type = 'LargeHotel'
    standard_space_type = 'GuestRoom'

    # make an empty model
    model = OpenStudio::Model::Model.new

    standard = Standard.build(template)

    # create space type and set standards info
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType(standard_building_type)
    space_type.setStandardsSpaceType(standard_space_type)

    # lookup standards data for space type
    data = standard.space_type_get_standards_data(space_type)

    # gather specific internal load values for testing
    lighting_per_area = data['lighting_per_area']
    electric_equipment_per_area = data['electric_equipment_per_area']
    gas_equipment_per_area = data['gas_equipment_per_area']
    occupancy_per_area = data['occupancy_per_area']
    ventilation_per_area = data['ventilation_per_area']
    ventilation_per_person = data['ventilation_per_person']
    infiltration_air_changes = data['infiltration_air_changes']

    # check various internal loads. This has ip values
    assert_in_delta(lighting_per_area.to_f, 0.91)
    assert_in_delta(electric_equipment_per_area.to_f, 0.627)
    assert_nil(gas_equipment_per_area)
    assert_in_delta(occupancy_per_area.to_f, 3.57)
    assert_in_delta(ventilation_per_area.to_f, 0.06)
    assert_in_delta(ventilation_per_person.to_f, 5)
  end
end
