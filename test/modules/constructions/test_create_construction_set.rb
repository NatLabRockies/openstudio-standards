require_relative '../../helpers/minitest_helper'

class TestCreateConstructionSet < Minitest::Test
  def setup
    @constructions = OpenstudioStandards::Constructions
  end

  def wall_of(set)
    set.defaultExteriorSurfaceConstructions.get.wallConstruction.get
  end

  def roof_of(set)
    set.defaultExteriorSurfaceConstructions.get.roofCeilingConstruction.get
  end

  def test_spec_reproduces_the_building_type_set
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    from_row = std.model_add_construction_set(model, cz, 'SuperMarket', nil, 'No').get
    from_spec = @constructions.create_construction_set(
      model, std, cz,
      { building_category: 'Nonresidential', is_residential: false, exterior_wall_type: 'Mass',
        exterior_roof_type: 'IEAD', exterior_floor_type: 'Mass' },
      fallback_building_type: 'SuperMarket'
    )

    refute_nil(from_spec)
    assert_equal(wall_of(from_row).standardsInformation.standardsConstructionType.get,
                 wall_of(from_spec).standardsInformation.standardsConstructionType.get)
    assert_equal(roof_of(from_row).standardsInformation.standardsConstructionType.get,
                 roof_of(from_spec).standardsInformation.standardsConstructionType.get)
    assert_equal(from_row.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get.name.to_s,
                 from_spec.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get.name.to_s)
  end

  def test_deer_template_with_an_ashrae_building_type
    std = Standard.build('ComStock DEER 2014')
    cz = 'CEC T24-CEC9'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    assert_nil(@constructions.construction_set_row(std, model, cz, 'SuperMarket', 'No'))

    set = @constructions.create_construction_set(
      model, std, cz,
      { building_category: 'Nonresidential', is_residential: false, exterior_wall_type: 'Mass',
        exterior_roof_type: 'IEAD', exterior_floor_type: 'Mass',
        surfaces: { ground_contact_floor: { construction_type: 'Unheated' },
                    exterior_fixed_window: { construction_type: 'Metal framing, fixed' },
                    interior_walls: 'Typical Interior Wall' } },
      fallback_building_type: 'SuperMarket'
    )
    refute_nil(set)
    refute_empty(wall_of(set).to_Construction.get.layers)
    assert_equal('Mass', wall_of(set).standardsInformation.standardsConstructionType.get)
    assert_equal('IEAD', roof_of(set).standardsInformation.standardsConstructionType.get)
    refute_nil(set.defaultInteriorSurfaceConstructions.get.wallConstruction)
  end

  def test_partial_spec_falls_back_to_the_row_per_surface
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    row_set = std.model_add_construction_set(model, cz, 'SuperMarket', nil, 'No').get
    set = @constructions.create_construction_set(model, std, cz, { exterior_wall_type: 'SteelFramed' },
                                                 fallback_building_type: 'SuperMarket')

    assert_equal('SteelFramed', wall_of(set).standardsInformation.standardsConstructionType.get)
    assert_equal(roof_of(row_set).standardsInformation.standardsConstructionType.get,
                 roof_of(set).standardsInformation.standardsConstructionType.get)
    assert_equal(row_set.defaultInteriorSurfaceConstructions.get.wallConstruction.get.name.to_s,
                 set.defaultInteriorSurfaceConstructions.get.wallConstruction.get.name.to_s)
  end

  def test_surface_entry_beats_the_shorthand_field
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    set = @constructions.create_construction_set(
      model, std, cz,
      { exterior_wall_type: 'SteelFramed',
        surfaces: { exterior_wall: { construction_type: 'WoodFramed' } } },
      fallback_building_type: 'SuperMarket'
    )
    assert_equal('WoodFramed', wall_of(set).standardsInformation.standardsConstructionType.get)
  end

  def test_symbol_and_string_keys_both_work
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    strings = @constructions.create_construction_set(model, std, cz, { 'exterior_wall_type' => 'WoodFramed' },
                                                     fallback_building_type: 'SuperMarket')
    symbols = @constructions.create_construction_set(model, std, cz, { exterior_wall_type: 'WoodFramed' },
                                                     fallback_building_type: 'SuperMarket')
    assert_equal(wall_of(strings).standardsInformation.standardsConstructionType.get,
                 wall_of(symbols).standardsInformation.standardsConstructionType.get)
  end

  def test_no_spec_fields_and_no_row_leaves_surfaces_unset
    std = Standard.build('ComStock DEER 2014')
    cz = 'CEC T24-CEC9'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    set = @constructions.create_construction_set(model, std, cz, { is_residential: false },
                                                 fallback_building_type: 'SuperMarket')
    refute_nil(set)
    assert(set.defaultExteriorSurfaceConstructions.get.wallConstruction.empty?)
  end

  def test_argument_parsing
    parsed = OpenstudioStandards::CreateTypical.parse_constructions_argument(
      '{"exterior_wall_type": "Mass", "surfaces": {"interior_walls": "Typical Interior Wall"}}'
    )
    assert_equal('Mass', parsed[:exterior_wall_type])
    assert_equal('Typical Interior Wall', parsed[:surfaces][:interior_walls])
    assert_nil(OpenstudioStandards::CreateTypical.parse_constructions_argument(nil))
    assert_nil(OpenstudioStandards::CreateTypical.parse_constructions_argument(''))
    assert_nil(OpenstudioStandards::CreateTypical.parse_constructions_argument({}))
    assert_nil(OpenstudioStandards::CreateTypical.parse_constructions_argument('not json'))
  end

  def space_type(model, name, building_type = nil)
    st = OpenStudio::Model::SpaceType.new(model)
    st.setName(name)
    st.setStandardsSpaceType(name)
    st.setStandardsBuildingType(building_type) unless building_type.nil?
    st
  end

  def mixed_use_model(model)
    %w[retail storage apartment guest_room corridor].each { |name| space_type(model, name) }
    model
  end

  def test_sets_are_assigned_to_the_space_types_they_name
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    mixed_use_model(model)
    building_set = @constructions.assign_construction_sets(
      model, std, cz,
      { default: { exterior_wall_type: 'Mass' },
        sets: [{ name: 'residential tower', space_types: %w[apartment guest_room],
                 is_residential: true, building_category: 'Residential', exterior_wall_type: 'SteelFramed' }] },
      fallback_building_type: 'MidriseApartment'
    )

    assert_equal(building_set, model.getBuilding.defaultConstructionSet.get)
    tower = model.getSpaceTypes.select { |st| %w[apartment guest_room].include?(st.name.to_s) }
    podium = model.getSpaceTypes - tower
    tower.each do |st|
      assert(st.defaultConstructionSet.is_initialized)
      assert_equal('SteelFramed', wall_of(st.defaultConstructionSet.get).standardsInformation.standardsConstructionType.get)
    end
    podium.each { |st| refute(st.defaultConstructionSet.is_initialized) }
    assert_equal('Mass', wall_of(building_set).standardsInformation.standardsConstructionType.get)
  end

  def test_entries_inherit_the_default_then_the_row
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    mixed_use_model(model)
    @constructions.assign_construction_sets(
      model, std, cz,
      { default: { exterior_roof_type: 'Attic and Other',
                   surfaces: { interior_walls: 'Typical Interior Wall' } },
        sets: [{ name: 'tower', space_types: ['apartment'], exterior_wall_type: 'SteelFramed' }] },
      fallback_building_type: 'MidriseApartment'
    )
    tower = model.getSpaceTypes.find { |st| st.name.to_s == 'apartment' }.defaultConstructionSet.get
    assert_equal('SteelFramed', wall_of(tower).standardsInformation.standardsConstructionType.get)
    assert_equal('Typical Interior Wall', tower.defaultInteriorSurfaceConstructions.get.wallConstruction.get.name.to_s)
    assert(tower.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.is_initialized)
  end

  def test_building_type_selector
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    space_type(model, 'retail', 'RetailStandalone')
    space_type(model, 'apartment', 'MidriseApartment')
    @constructions.assign_construction_sets(
      model, std, cz,
      { default: { exterior_wall_type: 'Mass', building_category: 'Nonresidential' },
        sets: [{ name: 'apartments', building_types: ['MidriseApartment'], exterior_wall_type: 'WoodFramed' }] },
      fallback_building_type: 'RetailStandalone'
    )
    apartment = model.getSpaceTypes.find { |st| st.name.to_s == 'apartment' }
    retail = model.getSpaceTypes.find { |st| st.name.to_s == 'retail' }
    assert_equal('WoodFramed', wall_of(apartment.defaultConstructionSet.get).standardsInformation.standardsConstructionType.get)
    refute(retail.defaultConstructionSet.is_initialized)
  end

  def test_first_matching_entry_wins
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    space_type(model, 'corridor')
    @constructions.assign_construction_sets(
      model, std, cz,
      { sets: [{ name: 'first', space_types: ['corridor'], exterior_wall_type: 'WoodFramed' },
               { name: 'second', space_types: ['*'], exterior_wall_type: 'SteelFramed' }] },
      fallback_building_type: 'SuperMarket'
    )
    corridor = model.getSpaceTypes.first
    assert_equal('WoodFramed', wall_of(corridor.defaultConstructionSet.get).standardsInformation.standardsConstructionType.get)
  end

  def test_a_spec_without_sets_behaves_as_before
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    mixed_use_model(model)
    set = @constructions.assign_construction_sets(model, std, cz, { exterior_wall_type: 'SteelFramed' },
                                                 fallback_building_type: 'SuperMarket')
    assert_equal(set, model.getBuilding.defaultConstructionSet.get)
    model.getSpaceTypes.each { |st| refute(st.defaultConstructionSet.is_initialized) }
  end

  def test_entry_matching_nothing_does_not_fail
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    space_type(model, 'retail')
    set = @constructions.assign_construction_sets(
      model, std, cz,
      { sets: [{ name: 'missing', space_types: ['not in model'], exterior_wall_type: 'SteelFramed' }] },
      fallback_building_type: 'SuperMarket'
    )
    refute_nil(set)
  end

  def test_merge_keeps_selectors_out_of_the_spec
    merged = @constructions.merge_construction_spec(
      { exterior_wall_type: 'Mass', surfaces: { interior_walls: 'Typical Interior Wall' } },
      { name: 'tower', space_types: ['apartment'], building_types: ['MidriseApartment'],
        exterior_wall_type: 'SteelFramed', surfaces: { ground_contact_floor: { construction_type: 'Unheated' } } }
    )
    refute(merged.key?(:name))
    refute(merged.key?(:space_types))
    refute(merged.key?(:building_types))
    assert_equal('SteelFramed', merged[:exterior_wall_type])
    assert_equal('Typical Interior Wall', merged[:surfaces][:interior_walls])
    assert_equal('Unheated', merged[:surfaces][:ground_contact_floor][:construction_type])
  end

  def test_surfaces_record_their_source
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    set = @constructions.create_construction_set(model, std, cz,
                                                 { exterior_wall_type: 'WoodFramed' },
                                                 fallback_building_type: 'SuperMarket')
    assert_equal('shorthand', set.additionalProperties.getFeatureAsString('exterior_wall source').get)
    assert_equal('building type row', set.additionalProperties.getFeatureAsString('exterior_roof source').get)
  end

  def test_pinned_construction_on_an_assembly_surface
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    set = @constructions.create_construction_set(
      model, std, cz,
      { exterior_wall_type: 'SteelFramed',
        surfaces: { exterior_roof: { construction: 'Typical Built Up Roof' } } },
      fallback_building_type: 'SuperMarket'
    )
    assert_equal('Typical Built Up Roof', roof_of(set).name.to_s)
    assert_equal('SteelFramed', wall_of(set).standardsInformation.standardsConstructionType.get)
  end

  def test_pinned_construction_wins_over_construction_type
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: cz)
    set = @constructions.create_construction_set(
      model, std, cz,
      { surfaces: { exterior_wall: { construction: 'Typical Insulated Exterior Mass Wall',
                                     construction_type: 'WoodFramed' } } },
      fallback_building_type: 'SuperMarket'
    )
    assert_equal('Typical Insulated Exterior Mass Wall', wall_of(set).name.to_s)

    set = @constructions.create_construction_set(
      model, std, cz,
      { surfaces: { exterior_wall: { construction: 'No Such Construction' } } }
    )
    assert(set.defaultExteriorSurfaceConstructions.get.wallConstruction.empty?)
  end

  def test_surface_table_matches_openstudio_api
    model = OpenStudio::Model::Model.new
    groups = {
      construction_set: OpenStudio::Model::DefaultConstructionSet.new(model),
      exterior_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
      interior_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
      ground_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
      exterior_subsurfaces: OpenStudio::Model::DefaultSubSurfaceConstructions.new(model),
      interior_subsurfaces: OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
    }
    @constructions::ASSEMBLY_SURFACES.each do |surface, (_, group, setter)|
      assert(groups[group].respond_to?(setter), "#{surface}: #{group} has no #{setter}")
    end
    @constructions::NAMED_SURFACES.each do |surface, (group, setter)|
      assert(groups[group].respond_to?(setter), "#{surface}: #{group} has no #{setter}")
    end
  end
end
