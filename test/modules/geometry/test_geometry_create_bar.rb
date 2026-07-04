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

  def test_create_bar_from_space_type_ratios_structured
    # structured array input should produce the same space types as the legacy string form
    model = OpenStudio::Model::Model.new
    args = {
      space_type_ratios: [
        { building_type: 'MediumOffice', space_type: 'Conference', ratio: 0.2 },
        { building_type: 'PrimarySchool', space_type: 'Corridor', ratio: 0.125 },
        { building_type: 'PrimarySchool', space_type: 'Classroom', ratio: 0.175 },
        { building_type: 'Warehouse', space_type: 'Office', ratio: 0.5 }
      ]
    }
    result = @geo.create_bar_from_space_type_ratios(model, args)
    assert(result)
    assert_equal(4, model.getSpaceTypes.size)

    # same input as legacy string for comparison
    string_model = OpenStudio::Model::Model.new
    string_args = {
      space_type_hash_string: 'MediumOffice | Conference => 0.2, PrimarySchool | Corridor => 0.125, PrimarySchool | Classroom => 0.175, Warehouse | Office => 0.5'
    }
    assert(@geo.create_bar_from_space_type_ratios(string_model, string_args))
    assert_equal(string_model.getSpaceTypes.map { |st| st.name.to_s }.sort, model.getSpaceTypes.map { |st| st.name.to_s }.sort)

    # space type floor areas should match the requested ratios
    total_area = model.getBuilding.floorArea
    conference = model.getSpaceTypes.find { |st| st.name.to_s.include?('Conference') }
    assert_in_delta(0.2, conference.floorArea / total_area, 0.01)
  end

  def test_create_bar_from_space_type_ratios_json_string
    model = OpenStudio::Model::Model.new
    json = '[{"building_type": "MediumOffice", "space_type": "Conference", "ratio": 0.5},' \
           ' {"building_type": "Warehouse", "space_type": "Office", "ratio": 0.5}]'
    result = @geo.create_bar_from_space_type_ratios(model, { space_type_ratios: json })
    assert(result)
    assert_equal(2, model.getSpaceTypes.size)
  end

  def test_create_bar_from_space_type_ratios_entry_metadata
    # user-supplied story_height should create a taller custom-height bar section
    custom_height_ft = 20.0
    model = OpenStudio::Model::Model.new
    args = {
      space_type_ratios: [
        { building_type: 'PrimarySchool', space_type: 'Classroom', ratio: 0.5, story_height: custom_height_ft },
        { building_type: 'PrimarySchool', space_type: 'Office', ratio: 0.5 }
      ]
    }
    result = @geo.create_bar_from_space_type_ratios(model, args)
    assert(result)

    classroom = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'Classroom' }
    office = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'Office' }
    refute_nil(classroom)
    refute_nil(office)

    space_height = lambda do |space_type|
      space = space_type.spaces.first
      z_values = OpenstudioStandards::Geometry.surfaces_get_z_values(space.surfaces.to_a)
      z_values.max - z_values.min
    end
    assert_in_delta(OpenStudio.convert(custom_height_ft, 'ft', 'm').get, space_height.call(classroom), 0.01)
    # office keeps the PrimarySchool typical story height of 13 ft
    assert_in_delta(OpenStudio.convert(13.0, 'ft', 'm').get, space_height.call(office), 0.01)
  end

  def test_create_bar_from_space_type_ratios_default_circ_flags
    # user-supplied default/circ flags should trigger double-loaded corridor placement,
    # reducing the corridor's exterior wall exposure versus plain story slicing
    corridor_ext_wall_area = lambda do |flagged|
      model = OpenStudio::Model::Model.new
      entries = [
        { building_type: 'MediumOffice', space_type: 'ClosedOffice', ratio: 0.7 },
        { building_type: 'MediumOffice', space_type: 'Corridor', ratio: 0.3 }
      ]
      if flagged
        entries[0][:default] = true
        entries[1][:circ] = true
      end
      assert(@geo.create_bar_from_space_type_ratios(model, { space_type_ratios: entries }))
      corridor = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'Corridor' }
      corridor.spaces.map { |space| space.exteriorWallArea }.sum
    end
    assert_operator(corridor_ext_wall_area.call(true), :<, corridor_ext_wall_area.call(false))
  end

  def test_create_bar_from_space_type_ratios_invalid_input
    # missing both input args
    assert_equal(false, @geo.create_bar_from_space_type_ratios(OpenStudio::Model::Model.new, {}))
    # malformed JSON
    assert_equal(false, @geo.create_bar_from_space_type_ratios(OpenStudio::Model::Model.new, { space_type_ratios: '[{"building_type": ' }))
    # missing ratio
    assert_equal(false, @geo.create_bar_from_space_type_ratios(OpenStudio::Model::Model.new,
                                                               { space_type_ratios: [{ building_type: 'MediumOffice', space_type: 'Conference' }] }))
    # missing space type
    assert_equal(false, @geo.create_bar_from_space_type_ratios(OpenStudio::Model::Model.new,
                                                               { space_type_ratios: [{ building_type: 'MediumOffice', ratio: 1.0 }] }))
  end

  def test_create_bar_from_space_type_ratios_primary_building_type
    entries = [
      { building_type: 'MediumOffice', space_type: 'Conference', ratio: 0.5 },
      { building_type: 'Warehouse', space_type: 'Office', ratio: 0.5 }
    ]

    # default primary is MediumOffice (first entry), which has a non-zero default wwr
    model = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(model, { space_type_ratios: entries.map(&:dup) }))
    assert_operator(model.getSubSurfaces.size, :>, 0)

    # overriding primary to Warehouse pulls its form defaults (wwr 0.0), so no windows
    warehouse_model = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(warehouse_model, { space_type_ratios: entries.map(&:dup), primary_building_type: 'Warehouse' }))
    assert_equal(0, warehouse_model.getSubSurfaces.size)
  end

  def test_create_bar_from_space_type_ratios_custom_primary_type
    entries = [{ building_type: 'MediumOffice', space_type: 'Conference', ratio: 1.0 }]

    # a non-standard primary building type with no form information fails cleanly
    model = OpenStudio::Model::Model.new
    result = @geo.create_bar_from_space_type_ratios(model, { space_type_ratios: entries.map(&:dup), primary_building_type: 'MyCustomType' })
    assert_equal(false, result)

    # supplying building_form_defaults makes the custom primary type work
    model = OpenStudio::Model::Model.new
    args = {
      space_type_ratios: entries.map(&:dup),
      primary_building_type: 'MyCustomType',
      building_form_defaults: { aspect_ratio: 2.0, wwr: 0.3, typical_story: 12.0, perim_mult: 1.0 }
    }
    assert(@geo.create_bar_from_space_type_ratios(model, args))
    assert_operator(model.getSpaces.size, :>, 0)
    assert_operator(model.getSubSurfaces.size, :>, 0)
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