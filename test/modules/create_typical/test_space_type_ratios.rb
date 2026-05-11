require_relative '../../helpers/minitest_helper'

class TestCreateTypicalSpaceTypeRatios < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
  end

  def test_get_space_types_from_building_type_primary_school
    building_type = 'PrimarySchool'
    result = @create.get_space_types_from_building_type(building_type, template: '90.1-2013')
    assert_equal(11, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios)
  end

  def test_get_space_types_from_building_type_small_office
    building_type = 'SmallOffice'
    result = @create.get_space_types_from_building_type(building_type, template: '90.1-2013', whole_building: true)
    assert_equal(1, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))

    result = @create.get_space_types_from_building_type(building_type, whole_building: false)
    assert_equal(9, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))
  end

  def test_get_space_types_from_building_type_medium_office
    building_type = 'MediumOffice'
    result = @create.get_space_types_from_building_type(building_type, template: '90.1-2013', whole_building: true)
    assert_equal(1, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))

    result = @create.get_space_types_from_building_type(building_type, whole_building: false)
    assert_equal(11, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))
  end

  def test_get_space_types_from_building_type_large_office
    building_type = 'LargeOffice'
    result = @create.get_space_types_from_building_type(building_type, building_subtype: 'largeoffice_datacenter', template: '90.1-2013', whole_building: true)
    assert_equal(3, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))

    result = @create.get_space_types_from_building_type(building_type, building_subtype: nil, template: '90.1-2013', whole_building: false)
    assert_equal(14, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))

    result = @create.get_space_types_from_building_type(building_type, building_subtype: nil, template: 'DOE Ref Pre-1980', whole_building: false)
    assert_equal(12, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))
  end

  def test_get_space_types_from_building_type_warehouse
    building_type = 'Warehouse'
    result = @create.get_space_types_from_building_type(building_type, building_subtype: 'warehouse_bulk20', template: '90.1-2013', whole_building: true)
    assert_equal(3, result.length)
    sum_of_ratios = 0
    result.each { |key, value| sum_of_ratios += value[:ratio] }
    assert_equal(1.0, sum_of_ratios.round(6))
  end

  def test_get_space_types_from_building_type_fail
    building_type = 'Casa Bonita'
    result = @create.get_space_types_from_building_type(building_type, template: '90.1-2013')
    assert(result == false)
  end
end