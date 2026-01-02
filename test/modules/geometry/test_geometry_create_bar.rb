require_relative '../../helpers/minitest_helper'

class TestGeometryCreateBar < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  def test_create_bar_from_space_type_ratios
    model = OpenStudio::Model::Model.new

    args = {
      :space_type_hash_string => 'MediumOffice | Conference => 0.2, PrimarySchool | Corridor => 0.125, PrimarySchool | Classroom => 0.175, Warehouse | Office => 0.5'
    }
    result = @geo.create_bar_from_space_type_ratios(model, args)
    assert(result)
    assert(model.getSpaceTypes.size == 4)
  end

  def test_create_bar_from_building_type_ratios
    model = OpenStudio::Model::Model.new

    args = {
      :bldg_type_a => 'LargeOffice',
      :bldg_type_b => 'Warehouse',
      :bldg_type_c => 'EUn',
      :bldg_type_d => 'RtL',
      :bldg_subtype_a => 'largeoffice_datacenter',
      :bldg_subtype_b => 'warehouse_bulk80',
      :bldg_type_a_fract_bldg_area => 0.3,
      :bldg_type_b_fract_bldg_area => 0.3,
      :bldg_type_c_fract_bldg_area => 0.3,
      :bldg_type_d_fract_bldg_area => 0.1
    }
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
  end

  def test_create_bar_from_building_type_ratios_ofs
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 2500.0
    args['bldg_type_a'] = 'OfS'
    args['ns_to_ew_ratio'] = 1.0
    args['num_stories_above_grade'] = 3.0
    args['template'] = "DEER Pre-1975"
    args['climate_zone'] = "CEC T24-CEC9"
    args['floor_height'] = 9.0
    args['story_multiplier'] = "None"
    args['wwr'] = 0.3
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
  end

  def test_create_bar_from_building_type_ratios_secondary_school
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 37500.0
    args['bldg_type_a'] = 'SecondarySchool'
    args['template'] = "ComStock DOE Ref Pre-1980"
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
    model.save("#{__dir__}/output/test_create_bar_from_building_type_ratios_secondary_school.osm", true)
  end

  def test_create_bar_from_building_type_ratios_warehouse
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 37500.0
    args['bldg_type_a'] = 'Warehouse'
    args['ns_to_ew_ratio'] = 2.0
    args['num_stories_above_grade'] = 2.0
    args['template'] = "ComStock DOE Ref Pre-1980"
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
    model.save("#{__dir__}/output/test_create_bar_from_building_type_ratios_warehouse.osm", true)
  end

  def test_create_bar_from_building_type_ratios_supermarket
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 37500.0
    args['bldg_type_a'] = 'SuperMarket'
    args['ns_to_ew_ratio'] = 2.0
    args['num_stories_above_grade'] = 1.0
    args['template'] = 'ComStock DOE Ref Pre-1980'
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
    model.save("#{__dir__}/output/test_create_bar_from_building_type_ratios_supermarket.osm", true)
  end

  def test_create_bar_from_building_type_ratios_doe_deer_mix
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 2500.0
    args['bldg_type_a'] = 'PrimarySchool'
    args['ns_to_ew_ratio'] = 1.0
    args['num_stories_above_grade'] = 3.0
    args['template'] = "DEER Pre-1975"
    args['climate_zone'] = "CEC T24-CEC9"
    args['floor_height'] = 9.0
    args['story_multiplier'] = "None"
    args['wwr'] = 0.3
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
    assert('EPr', model.getSpaceTypes[0].standardsBuildingType.get)
  end

  def test_create_bar_from_building_type_ratios_division_methods
    model = OpenStudio::Model::Model.new

    args = {
      :bldg_type_a => 'LargeOffice',
      :bldg_type_b => 'Warehouse',
      :bldg_type_a_fract_bldg_area => 0.7,
      :bldg_type_b_fract_bldg_area => 0.3,
    }
    args[:bar_division_method] = 'Multiple Space Types - Simple Sliced'
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)

    args[:bar_division_method] = 'Multiple Space Types - Individual Stories Sliced'
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)

    args[:bar_division_method] = 'Single Space Type - Core and Perimeter'
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
  end

  def test_create_bar_from_building_type_ratios_low_aspect_ratio
    model = OpenStudio::Model::Model.new

    args = {}
    args['total_bldg_floor_area'] = 100000.0
    args['bldg_type_a'] = 'SecondarySchool'
    args['num_stories_above_grade'] = 6.0
    args['bar_division_method'] = 'Multiple Space Types - Individual Stories Sliced'
    args['ns_to_ew_ratio'] = 0.2
    args['perim_mult'] = 1.0
    result = @geo.create_bar_from_building_type_ratios(model, args)
    assert(result)
  end
end