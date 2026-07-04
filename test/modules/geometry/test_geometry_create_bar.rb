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

  # ---------------------------------------------------------------------------
  # Perimeter/core positioning and thermal zone grouping
  # ---------------------------------------------------------------------------

  PC_METHOD = 'Multiple Space Types - Perimeter and Core Sliced'.freeze

  # exterior (Outdoors) wall area grouped by standards space type
  def ext_wall_by_std_spc(model)
    h = Hash.new(0.0)
    model.getSpaces.each do |space|
      next unless space.spaceType.is_initialized && space.spaceType.get.standardsSpaceType.is_initialized

      key = space.spaceType.get.standardsSpaceType.get
      space.surfaces.each do |surface|
        next unless surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'

        h[key] += surface.grossArea * space.multiplier
      end
    end
    h
  end

  def pc_school_args(extra = {})
    {
      space_type_ratios: [
        { building_type: 'PrimarySchool', space_type: 'Classroom', ratio: 0.45, position: 'perimeter' },
        { building_type: 'PrimarySchool', space_type: 'Office', ratio: 0.15, position: 'perimeter' },
        { building_type: 'PrimarySchool', space_type: 'Gym', ratio: 0.10 },
        { building_type: 'PrimarySchool', space_type: 'Corridor', ratio: 0.10, position: 'core' },
        { building_type: 'PrimarySchool', space_type: 'Restroom', ratio: 0.10, position: 'core' },
        { building_type: 'PrimarySchool', space_type: 'Mechanical', ratio: 0.10, position: 'core' }
      ],
      primary_building_type: 'PrimarySchool',
      template: '90.1-2013',
      total_bldg_floor_area: 60000.0,
      num_stories_above_grade: 2,
      perim_mult: 1.0,
      bar_division_method: PC_METHOD
    }.merge(extra)
  end

  # save the generated model to test/modules/geometry/output for visual inspection
  def save_model(model, name)
    model.save("#{__dir__}/output/#{name}.osm", true)
  end

  def test_space_type_position_heuristic
    assert_equal(['core', 'keyword'], @geo.space_type_position_heuristic('Corridor'))
    assert_equal(['core', 'keyword'], @geo.space_type_position_heuristic('Elec/MechRoom'))
    assert_equal(['perimeter', 'keyword'], @geo.space_type_position_heuristic('Classroom'))
    assert_equal(['perimeter', 'keyword'], @geo.space_type_position_heuristic('OpenOffice'))
    assert_equal(['any', 'default'], @geo.space_type_position_heuristic('Conference'))
    # size bias only for unmatched names
    assert_equal(['core', 'size'], @geo.space_type_position_heuristic('Conference', ratio_of_building: 0.04))
    assert_equal(['perimeter', 'size'], @geo.space_type_position_heuristic('Conference', ratio_of_building: 0.30))
    # keyword is never overridden by size
    assert_equal(['core', 'keyword'], @geo.space_type_position_heuristic('Storage', ratio_of_building: 0.50))
  end

  def test_space_type_zone_alone_heuristic
    assert(@geo.space_type_zone_alone_heuristic('Mechanical'))
    assert(@geo.space_type_zone_alone_heuristic('Electrical Room'))
    assert(@geo.space_type_zone_alone_heuristic('Kitchen'))
    assert(@geo.space_type_zone_alone_heuristic('Laboratory'))
    refute(@geo.space_type_zone_alone_heuristic('Classroom'))
    refute(@geo.space_type_zone_alone_heuristic('Corridor'))
    refute(@geo.space_type_zone_alone_heuristic('Collaboration Space'))
  end

  def test_position_explicit_any_uses_size_rule
    # explicit 'any' is not a protected assignment: the size rule decides, and it
    # overrides the circ flag and keyword heuristics
    hash = {
      'small' => { position: 'any', ratio_of_bldg_total: 0.03, circ: true },
      'large' => { position: 'any', ratio_of_bldg_total: 0.40 }
    }
    @geo.resolve_space_type_positions(hash, {})
    assert_equal('core', hash['small'][:position])
    assert_equal('size', hash['small'][:position_source])
    assert_equal('perimeter', hash['large'][:position])
    assert_equal('size', hash['large'][:position_source])
  end

  def test_position_invalid_inputs
    model = OpenStudio::Model::Model.new
    bad_position = { space_type_ratios: [{ building_type: 'PrimarySchool', space_type: 'Classroom', ratio: 1.0, position: 'middle' }] }
    refute(@geo.create_bar_from_space_type_ratios(model, bad_position))

    model2 = OpenStudio::Model::Model.new
    bad_orientation = { space_type_ratios: [{ building_type: 'PrimarySchool', space_type: 'Classroom', ratio: 1.0, orientation: ['up'] }] }
    refute(@geo.create_bar_from_space_type_ratios(model2, bad_orientation))
  end

  def test_perimeter_core_bar_areas_and_envelope
    model = OpenStudio::Model::Model.new
    # explicit form values so the envelope expectations are deterministic
    args = pc_school_args(ns_to_ew_ratio: 2.0, floor_height: 13.0, wwr: 0.35)
    assert(@geo.create_bar_from_space_type_ratios(model, args))
    assert_equal(6, model.getSpaceTypes.size)

    ext = ext_wall_by_std_spc(model)
    # core-assigned space types have no exterior walls
    ['Corridor', 'Restroom', 'Mechanical'].each do |core_type|
      assert_in_delta(0.0, ext[core_type], 1e-6, "#{core_type} should have no exterior wall area")
    end
    # a perimeter space type carries facade area
    assert(ext['Classroom'] > 0.0)

    # total exterior wall area matches the plain rectangular bar envelope
    footprint_si = OpenStudio.convert(60_000.0 / 2, 'ft^2', 'm^2').get
    width = Math.sqrt(footprint_si / 2.0)
    length = footprint_si / width
    height = OpenStudio.convert(13.0, 'ft', 'm').get
    expected_wall = 2 * (length + width) * height * 2
    assert_in_delta(expected_wall, model.getBuilding.exteriorWallArea, expected_wall * 0.005)

    # window to wall ratio on the exterior walls matches the requested value
    wall_area = 0.0
    window_area = 0.0
    model.getSurfaces.each do |surface|
      next unless surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'

      wall_area += surface.grossArea
      surface.subSurfaces.each { |sub| window_area += sub.grossArea }
    end
    assert_in_delta(0.35, window_area / wall_area, 0.01)

    save_model(model, 'test_perimeter_core_bar_areas_and_envelope')
  end

  # absolute azimuth of a surface in degrees, accounting for space and building rotation
  def surface_absolute_azimuth(surface)
    az = OpenStudio.convert(surface.azimuth, 'rad', 'deg').get
    az += surface.space.get.directionofRelativeNorth + surface.model.getBuilding.northAxis
    az % 360.0
  end

  def test_perimeter_core_bar_party_walls
    model = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(model, pc_school_args(party_wall_stories_south: 2)))

    south_outdoors = 0
    south_adiabatic = 0
    model.getSurfaces.each do |surface|
      next unless surface.surfaceType == 'Wall'

      az = surface_absolute_azimuth(surface)
      next unless az >= 135.0 && az < 225.0

      south_outdoors += 1 if surface.outsideBoundaryCondition == 'Outdoors'
      if surface.outsideBoundaryCondition == 'Adiabatic' && !surface.space.get.name.to_s.include?('Core')
        south_adiabatic += 1
        assert_empty(surface.subSurfaces.to_a, "party wall #{surface.name} should have no windows")
      end
    end
    assert_equal(0, south_outdoors, 'south facade should be entirely party (adiabatic) walls')
    assert(south_adiabatic > 0)

    save_model(model, 'test_perimeter_core_bar_party_walls')
  end

  def test_perimeter_core_bar_dual_bar
    model = OpenStudio::Model::Model.new
    # perimeter multiplier > 1 triggers the dual-bar path with the new division method
    assert(@geo.create_bar_from_space_type_ratios(model, pc_school_args(perim_mult: 1.4)))
    ext = ext_wall_by_std_spc(model)
    assert(ext['Classroom'] > 0.0)

    save_model(model, 'test_perimeter_core_bar_dual_bar')
  end

  def test_perimeter_core_bar_custom_height
    model = OpenStudio::Model::Model.new
    args = pc_school_args
    # leave floor_height at the smart default and give the gym a custom story height,
    # exercising the dedicated custom-height bar with the new division method
    args.delete(:num_stories_above_grade)
    args[:num_stories_above_grade] = 2
    args[:space_type_ratios] = args[:space_type_ratios].map do |entry|
      entry[:space_type] == 'Gym' ? entry.merge(story_height: 17.0) : entry
    end
    assert(@geo.create_bar_from_space_type_ratios(model, args))
    gym_spaces = model.getSpaces.select do |space|
      space.spaceType.is_initialized && space.spaceType.get.standardsSpaceType.is_initialized &&
        space.spaceType.get.standardsSpaceType.get == 'Gym'
    end
    assert(gym_spaces.size > 0)

    save_model(model, 'test_perimeter_core_bar_custom_height')
  end

  def test_zoning_group_precedence_and_default
    model = OpenStudio::Model::Model.new
    args = pc_school_args(
      zoning_method: 'Space Type Groups',
      zone_group_default: 'individual',
      zone_groups: [
        { name: 'first', space_types: ['PrimarySchool|Corridor'], zone_per: 'group' },
        { name: 'second', space_types: ['PrimarySchool|Corridor', 'PrimarySchool|Restroom'], zone_per: 'group' }
      ]
    )
    assert(@geo.create_bar_from_space_type_ratios(model, args))

    spaces_of = lambda do |std_spc|
      model.getSpaces.select do |space|
        space.spaceType.is_initialized && space.spaceType.get.standardsSpaceType.is_initialized &&
          space.spaceType.get.standardsSpaceType.get == std_spc
      end
    end

    # first match wins: corridors zone with 'first', restrooms with 'second'
    corridor_zones = spaces_of.call('Corridor').map { |s| s.thermalZone.get.name.get }.uniq
    assert(corridor_zones.all? { |n| n.include?('first') }, "corridor zones #{corridor_zones.inspect} should use group 'first'")
    restroom_zones = spaces_of.call('Restroom').map { |s| s.thermalZone.get.name.get }.uniq
    assert(restroom_zones.all? { |n| n.include?('second') }, "restroom zones #{restroom_zones.inspect} should use group 'second'")

    # zone_group_default 'individual': unmatched space types get one zone per space
    spaces_of.call('Classroom').each do |space|
      assert_equal(1, space.thermalZone.get.spaces.size, 'unmatched space should be in its own zone')
    end

    save_model(model, 'test_zoning_group_precedence_and_default')
  end

  def test_perimeter_core_bar_heuristic_positions
    model = OpenStudio::Model::Model.new
    args = {
      bldg_type_a: 'PrimarySchool',
      template: '90.1-2013',
      total_bldg_floor_area: 73958.0,
      num_stories_above_grade: 2,
      perim_mult: 1.0,
      bar_division_method: PC_METHOD
    }
    assert(@geo.create_bar_from_building_type_ratios(model, args))
    ext = ext_wall_by_std_spc(model)
    # support space types land in the core (no exterior wall) purely from heuristics
    ['Corridor', 'Restroom', 'Mechanical'].each do |core_type|
      assert_in_delta(0.0, ext[core_type], 1e-6, "#{core_type} should be core-positioned by heuristic")
    end
    assert(ext['Classroom'] > 0.0)

    save_model(model, 'test_perimeter_core_bar_heuristic_positions')
  end

  def test_perimeter_core_bar_partial_story
    model = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(model, pc_school_args(num_stories_above_grade: 2.5)))
    save_model(model, 'test_perimeter_core_bar_partial_story')
  end

  def test_perimeter_core_bar_fallback
    model = OpenStudio::Model::Model.new
    # a very high aspect ratio makes the bar too narrow for a core; the method should
    # still succeed by falling back to the sliced layout
    assert(@geo.create_bar_from_space_type_ratios(model, pc_school_args(ns_to_ew_ratio: 120.0)))
    save_model(model, 'test_perimeter_core_bar_fallback')
  end

  def test_zoning_heuristic
    model = OpenStudio::Model::Model.new
    args = {
      bldg_type_a: 'PrimarySchool',
      template: '90.1-2013',
      total_bldg_floor_area: 73958.0,
      num_stories_above_grade: 2,
      perim_mult: 1.0,
      bar_division_method: PC_METHOD,
      zoning_method: 'Perimeter Orientation and Core'
    }
    assert(@geo.create_bar_from_building_type_ratios(model, args))
    zone_names = model.getThermalZones.map { |z| z.name.get }
    # one grouped zone per facade and a combined core zone, per story
    %w[N S E W].each do |facade|
      assert(zone_names.any? { |n| n =~ /perimeter #{facade}\b/ }, "missing perimeter #{facade} zone")
    end
    assert(zone_names.any? { |n| n =~ /\bcore\b/ }, 'missing core zone')
    # grouped zones carry the additional property
    grouped = model.getThermalZones.select { |z| z.additionalProperties.getFeatureAsString('zone_group').is_initialized }
    assert(grouped.size > 0)
    # zone-alone type (Mechanical) is not folded into the core group
    assert(zone_names.any? { |n| n.include?('Mechanical') })
    # grouping reduces zone count below the space count
    assert(model.getThermalZones.size < model.getSpaces.size)

    save_model(model, 'test_zoning_heuristic')
  end

  def test_zoning_custom_groups
    model = OpenStudio::Model::Model.new
    args = pc_school_args(
      zoning_method: 'Space Type Groups',
      zone_groups: [
        { name: 'core support', space_types: ['PrimarySchool|Corridor', 'PrimarySchool|Restroom'], zone_per: 'group' },
        { name: 'electrical', space_types: ['PrimarySchool|Mechanical'], zone_per: 'space' },
        { name: 'classrooms', space_types: ['PrimarySchool|Classroom'], zone_per: 'facade' }
      ]
    )
    assert(@geo.create_bar_from_space_type_ratios(model, args))
    zone_names = model.getThermalZones.map { |z| z.name.get }

    # corridor and restroom share one core support zone per story
    support_zones = model.getThermalZones.select { |z| z.name.get.include?('core support') }
    assert(support_zones.size > 0)
    support_spc = support_zones.flat_map { |z| z.spaces.map { |s| s.spaceType.get.standardsSpaceType.get } }.uniq.sort
    assert_equal(['Corridor', 'Restroom'], support_spc)

    # classrooms split by facade
    assert(zone_names.any? { |n| n =~ /classrooms [NSEW]\b/ })

    save_model(model, 'test_zoning_custom_groups')
  end

  def test_zoning_default_regression
    model = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(model, pc_school_args))
    # default zoning is one thermal zone per space
    assert_equal(model.getSpaces.size, model.getThermalZones.size)
    save_model(model, 'test_zoning_default_regression')
  end

  def test_zoning_with_sliced_method
    model = OpenStudio::Model::Model.new
    args = pc_school_args(
      bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
      zoning_method: 'Perimeter Orientation and Core'
    )
    assert(@geo.create_bar_from_space_type_ratios(model, args))
    zone_names = model.getThermalZones.map { |z| z.name.get }
    # zoning works even with a sliced division method: facade and core labels appear
    assert(zone_names.any? { |n| n =~ /perimeter [NSEW]\b/ })
    assert(zone_names.any? { |n| n =~ /\bcore\b/ })

    save_model(model, 'test_zoning_with_sliced_method')
  end

  def test_zoning_invalid_spec
    model = OpenStudio::Model::Model.new
    bad_zone_per = pc_school_args(
      zoning_method: 'Space Type Groups',
      zone_groups: [{ name: 'g', space_types: ['PrimarySchool|Corridor'], zone_per: 'bogus' }]
    )
    refute(@geo.create_bar_from_space_type_ratios(model, bad_zone_per))

    model2 = OpenStudio::Model::Model.new
    bad_method = pc_school_args(zoning_method: 'Not A Method')
    refute(@geo.create_bar_from_space_type_ratios(model2, bad_method))
  end
end