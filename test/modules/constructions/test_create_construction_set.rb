require_relative '../../helpers/minitest_helper'

# Tests for building a default construction set from named construction types instead of from a
# building type's row in the construction_sets table, and for the per-slot fallback to that row.
class TestCreateConstructionSet < Minitest::Test
  def setup
    @constructions = OpenstudioStandards::Constructions
  end

  def model_for(climate_zone)
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)
    model
  end

  def wall_of(set)
    set.defaultExteriorSurfaceConstructions.get.wallConstruction.get
  end

  def roof_of(set)
    set.defaultExteriorSurfaceConstructions.get.roofCeilingConstruction.get
  end

  # A spec naming only the axes reproduces what the building type's row produces, because the row
  # does nothing but select the same construction type and category.
  def test_spec_reproduces_the_building_type_set
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'

    from_row = std.model_add_construction_set(model_for(cz), cz, 'SuperMarket', nil, 'No').get

    model = model_for(cz)
    from_spec = @constructions.create_construction_set(model, std, cz, {
                                                         'building_category' => 'Nonresidential',
                                                         'is_residential' => false,
                                                         'exterior_wall_type' => 'Mass',
                                                         'exterior_roof_type' => 'IEAD',
                                                         'exterior_floor_type' => 'Mass'
                                                       }, fallback_building_type: 'SuperMarket')

    refute_nil(from_spec)
    assert_equal(wall_of(from_row).name.to_s, wall_of(from_spec).name.to_s)
    assert_equal(roof_of(from_row).name.to_s, roof_of(from_spec).name.to_s)
    assert_equal(from_row.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get.name.to_s,
                 from_spec.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get.name.to_s)
  end

  # The point of the section: a template whose construction_sets table has no row for this
  # building type still produces a full set.
  def test_deer_template_with_an_ashrae_building_type
    std = Standard.build('ComStock DEER 2014')
    cz = 'CEC T24-CEC9'

    # the building type lookup finds nothing, which is what aborts create_typical today
    assert_nil(@constructions.construction_set_row(std, model_for(cz), cz, 'SuperMarket', 'No'))
    refute(std.model_add_construction_set(model_for(cz), cz, 'SuperMarket', nil, 'No').is_initialized)

    model = model_for(cz)
    set = @constructions.create_construction_set(model, std, cz, {
                                                   'building_category' => 'Nonresidential',
                                                   'is_residential' => false,
                                                   'exterior_wall_type' => 'Mass',
                                                   'exterior_roof_type' => 'IEAD',
                                                   'exterior_floor_type' => 'Mass',
                                                   'surfaces' => {
                                                     'ground_contact_floor' => { 'construction_type' => 'Unheated' },
                                                     'exterior_fixed_window' => { 'construction_type' => 'Metal framing, fixed' },
                                                     'interior_walls' => 'Typical Interior Wall'
                                                   }
                                                 }, fallback_building_type: 'SuperMarket')

    refute_nil(set, 'no construction set was produced without a building type row')
    refute_empty(wall_of(set).to_Construction.get.layers, 'the exterior wall has no layers')
    assert_equal('Mass', wall_of(set).standardsInformation.standardsConstructionType.get)
    assert_equal('IEAD', roof_of(set).standardsInformation.standardsConstructionType.get)
    refute_nil(set.defaultInteriorSurfaceConstructions.get.wallConstruction)
  end

  # Naming one surface and inheriting the rest from the row.
  def test_partial_spec_falls_back_to_the_row_per_surface
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    from_row = std.model_add_construction_set(model_for(cz), cz, 'SuperMarket', nil, 'No').get

    model = model_for(cz)
    set = @constructions.create_construction_set(model, std, cz,
                                                 { 'exterior_wall_type' => 'SteelFramed' },
                                                 fallback_building_type: 'SuperMarket')

    assert_equal('SteelFramed', wall_of(set).standardsInformation.standardsConstructionType.get,
                 'the named wall type did not win')
    assert_equal('Mass', wall_of(from_row).standardsInformation.standardsConstructionType.get,
                 "the row's own wall type, for contrast")
    assert_equal(roof_of(from_row).name.to_s, roof_of(set).name.to_s, 'the unnamed roof did not come from the row')
    assert_equal(from_row.defaultInteriorSurfaceConstructions.get.wallConstruction.get.name.to_s,
                 set.defaultInteriorSurfaceConstructions.get.wallConstruction.get.name.to_s,
                 'the unnamed interior wall did not come from the row')
  end

  # A per-surface entry beats the shorthand field, which beats the row.
  def test_surface_entry_beats_the_shorthand_field
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = model_for(cz)
    set = @constructions.create_construction_set(model, std, cz, {
                                                   'exterior_wall_type' => 'SteelFramed',
                                                   'surfaces' => { 'exterior_wall' => { 'construction_type' => 'WoodFramed' } }
                                                 }, fallback_building_type: 'SuperMarket')
    assert_equal('WoodFramed', wall_of(set).standardsInformation.standardsConstructionType.get)
  end

  def test_symbol_and_string_keys_both_work
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    strings = @constructions.create_construction_set(model_for(cz), std, cz,
                                                     { 'exterior_wall_type' => 'WoodFramed' },
                                                     fallback_building_type: 'SuperMarket')
    symbols = @constructions.create_construction_set(model_for(cz), std, cz,
                                                     { exterior_wall_type: 'WoodFramed' },
                                                     fallback_building_type: 'SuperMarket')
    assert_equal(wall_of(strings).standardsInformation.standardsConstructionType.get,
                 wall_of(symbols).standardsInformation.standardsConstructionType.get)
  end

  # A spec that names nothing and has no row to fall back on leaves the surfaces unset rather than
  # raising, so the caller still gets a set and OpenStudio's own defaults apply.
  def test_no_spec_fields_and_no_row_leaves_surfaces_unset
    std = Standard.build('ComStock DEER 2014')
    cz = 'CEC T24-CEC9'
    set = @constructions.create_construction_set(model_for(cz), std, cz, { 'is_residential' => false },
                                                 fallback_building_type: 'SuperMarket')
    refute_nil(set)
    assert(set.defaultExteriorSurfaceConstructions.get.wallConstruction.empty?,
           'a wall was created from a spec that named no wall type')
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

  # --- mixed use: a default set on the building and further sets on collections of space types

  def space_type(model, name, building_type = nil)
    st = OpenStudio::Model::SpaceType.new(model)
    st.setName(name)
    st.setStandardsSpaceType(name)
    st.setStandardsBuildingType(building_type) unless building_type.nil?
    st
  end

  def mixed_use_model(cz)
    model = model_for(cz)
    ['retail', 'storage', 'apartment', 'guest room', 'corridor'].each { |n| space_type(model, n) }
    model
  end

  def test_sets_are_assigned_to_the_space_types_they_name
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = mixed_use_model(cz)

    building_set = @constructions.assign_construction_sets(model, std, cz, {
                                                             'default' => { 'exterior_wall_type' => 'Mass' },
                                                             'sets' => [
                                                               { 'name' => 'residential tower',
                                                                 'space_types' => ['apartment', 'guest room'],
                                                                 'is_residential' => true,
                                                                 'building_category' => 'Residential',
                                                                 'exterior_wall_type' => 'SteelFramed' }
                                                             ]
                                                           }, fallback_building_type: 'MidriseApartment')

    refute_nil(building_set)
    assert_equal(building_set, model.getBuilding.defaultConstructionSet.get)

    tower = model.getSpaceTypes.select { |st| ['apartment', 'guest room'].include?(st.name.to_s) }
    podium = model.getSpaceTypes.reject { |st| ['apartment', 'guest room'].include?(st.name.to_s) }

    tower.each do |st|
      assert(st.defaultConstructionSet.is_initialized, "#{st.name} got no construction set")
      assert_equal('SteelFramed', wall_of(st.defaultConstructionSet.get).standardsInformation.standardsConstructionType.get)
    end
    podium.each { |st| refute(st.defaultConstructionSet.is_initialized, "#{st.name} should inherit the building set") }
    assert_equal('Mass', wall_of(building_set).standardsInformation.standardsConstructionType.get)
  end

  # An entry names only what differs and takes the rest from the default, which takes the rest
  # from the row of the fallback building type.
  def test_entries_inherit_the_default_then_the_row
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = mixed_use_model(cz)
    from_row = std.model_add_construction_set(model_for(cz), cz, 'MidriseApartment', nil, 'No').get

    @constructions.assign_construction_sets(model, std, cz, {
                                              'default' => { 'exterior_roof_type' => 'Attic and Other',
                                                             'surfaces' => { 'interior_walls' => 'Typical Interior Wall' } },
                                              'sets' => [{ 'name' => 'tower', 'space_types' => ['apartment'],
                                                           'exterior_wall_type' => 'SteelFramed' }]
                                            }, fallback_building_type: 'MidriseApartment')

    default_only = @constructions.create_construction_set(model_for(cz), std, cz,
                                                          { 'exterior_roof_type' => 'Attic and Other' },
                                                          fallback_building_type: 'MidriseApartment')

    tower = model.getSpaceTypes.find { |st| st.name.to_s == 'apartment' }.defaultConstructionSet.get
    assert_equal('SteelFramed', wall_of(tower).standardsInformation.standardsConstructionType.get, 'the entry did not win')
    assert_equal(roof_of(default_only).name.to_s, roof_of(tower).name.to_s.sub(/ \d+\z/, ''),
                 'the default roof did not carry into the entry')
    assert_equal('Typical Interior Wall', tower.defaultInteriorSurfaceConstructions.get.wallConstruction.get.name.to_s, 'the default slot did not carry into the entry')
    assert_equal(from_row.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get.name.to_s,
                 tower.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get.name.to_s,
                 'the window did not fall through to the building type row')
  end

  def test_building_type_selector
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = model_for(cz)
    space_type(model, 'retail', 'RetailStandalone')
    space_type(model, 'apartment', 'MidriseApartment')

    @constructions.assign_construction_sets(model, std, cz, {
                                              'default' => { 'exterior_wall_type' => 'Mass', 'building_category' => 'Nonresidential' },
                                              'sets' => [{ 'name' => 'apartments', 'building_types' => ['MidriseApartment'],
                                                           'exterior_wall_type' => 'WoodFramed' }]
                                            }, fallback_building_type: 'RetailStandalone')

    apartment = model.getSpaceTypes.find { |st| st.name.to_s == 'apartment' }
    retail = model.getSpaceTypes.find { |st| st.name.to_s == 'retail' }
    assert(apartment.defaultConstructionSet.is_initialized)
    assert_equal('WoodFramed', wall_of(apartment.defaultConstructionSet.get).standardsInformation.standardsConstructionType.get)
    refute(retail.defaultConstructionSet.is_initialized)
  end

  # Order is precedence, so overlapping selectors are resolved rather than racing.
  def test_first_matching_entry_wins
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = mixed_use_model(cz)

    @constructions.assign_construction_sets(model, std, cz, {
                                              'sets' => [
                                                { 'name' => 'first', 'space_types' => ['corridor'], 'exterior_wall_type' => 'WoodFramed' },
                                                { 'name' => 'second', 'space_types' => ['*'], 'exterior_wall_type' => 'SteelFramed' }
                                              ]
                                            }, fallback_building_type: 'MidriseApartment')

    corridor = model.getSpaceTypes.find { |st| st.name.to_s == 'corridor' }.defaultConstructionSet.get
    retail = model.getSpaceTypes.find { |st| st.name.to_s == 'retail' }.defaultConstructionSet.get
    assert_equal('WoodFramed', wall_of(corridor).standardsInformation.standardsConstructionType.get)
    assert_equal('SteelFramed', wall_of(retail).standardsInformation.standardsConstructionType.get)
  end

  # A bare construction spec is still a bare construction spec.
  def test_a_spec_without_sets_behaves_as_before
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = mixed_use_model(cz)
    set = @constructions.assign_construction_sets(model, std, cz, { 'exterior_wall_type' => 'WoodFramed' },
                                                  fallback_building_type: 'MidriseApartment')
    assert_equal(set, model.getBuilding.defaultConstructionSet.get)
    assert_equal('WoodFramed', wall_of(set).standardsInformation.standardsConstructionType.get)
    model.getSpaceTypes.each { |st| refute(st.defaultConstructionSet.is_initialized) }
  end

  def test_entry_matching_nothing_is_a_warning_not_a_failure
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = mixed_use_model(cz)
    set = @constructions.assign_construction_sets(model, std, cz, {
                                                    'sets' => [{ 'name' => 'nobody', 'space_types' => ['data center'],
                                                                 'exterior_wall_type' => 'WoodFramed' }]
                                                  }, fallback_building_type: 'MidriseApartment')
    refute_nil(set)
    model.getSpaceTypes.each { |st| refute(st.defaultConstructionSet.is_initialized) }
  end

  def test_merge_keeps_selectors_out_of_the_merged_spec
    merged = @constructions.merge_construction_spec(
      { exterior_wall_type: 'Mass', surfaces: { interior_walls: 'Typical Interior Wall', exterior_door: { construction_type: 'Swinging' } } },
      { name: 'tower', space_types: ['apartment'], exterior_wall_type: 'SteelFramed', surfaces: { interior_walls: 'LargeHotel Interior Wall' } }
    )
    assert_equal('SteelFramed', merged[:exterior_wall_type])
    assert_equal('LargeHotel Interior Wall', merged[:surfaces][:interior_walls], 'the entry slot did not win')
    assert_equal({ construction_type: 'Swinging' }, merged[:surfaces][:exterior_door], 'a default slot was lost in the merge')
    refute(merged.key?(:name))
    refute(merged.key?(:space_types))
  end

  # A construction name pinned on an assembly-lookup surface wins over the lookup entirely.
  # The name comes from the standards constructions data, same as the interior surfaces.
  # Each resolved surface records where its value came from, so a surprising assembly is
  # traced by reading a property instead of re-deriving the resolution order.
  def test_surfaces_record_their_source
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    set = @constructions.create_construction_set(std.model_add_construction_set(model_for(cz), cz, 'SuperMarket', nil, 'No').get.model,
                                                 std, cz, {
                                                   'exterior_wall_type' => 'SteelFramed',
                                                   'surfaces' => {
                                                     'exterior_floor' => { 'construction_type' => 'Mass' },
                                                     'exterior_roof' => { 'construction' => 'Typical Built Up Roof' },
                                                     'interior_walls' => 'Typical Interior Wall'
                                                   }
                                                 }, fallback_building_type: 'SuperMarket')

    source_of = lambda do |surface|
      feature = set.additionalProperties.getFeatureAsString("#{surface} source")
      feature.is_initialized ? feature.get : nil
    end
    assert_equal('shorthand', source_of.call('exterior_wall'))
    assert_equal('surface entry', source_of.call('exterior_floor'))
    assert_equal('pinned construction', source_of.call('exterior_roof'))
    assert_equal('surface entry', source_of.call('interior_walls'))
    assert_equal('building type row', source_of.call('ground_contact_floor'))
    assert_equal('building type row', source_of.call('interior_ceilings'))
  end

  def test_pinned_construction_on_an_assembly_surface
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'
    model = model_for(cz)

    set = @constructions.create_construction_set(model, std, cz, {
                                                   'exterior_wall_type' => 'SteelFramed',
                                                   'surfaces' => { 'exterior_roof' => { 'construction' => 'Typical Built Up Roof' } }
                                                 }, fallback_building_type: 'SuperMarket')
    assert_equal('Typical Built Up Roof', roof_of(set).name.to_s, 'the pinned construction was not used')
    assert_equal('SteelFramed', wall_of(set).standardsInformation.standardsConstructionType.get,
                 'the other surfaces should still resolve normally')
  end

  # Both fields on one surface: the pin wins with a warning; an unknown pin leaves the
  # surface unset rather than falling back to the type it also named.
  def test_pinned_construction_wins_over_construction_type
    std = Standard.build('ComStock 90.1-2013')
    cz = 'ASHRAE 169-2013-5A'

    set = @constructions.create_construction_set(model_for(cz), std, cz, {
                                                   'surfaces' => { 'exterior_wall' => { 'construction' => 'Typical Insulated Exterior Mass Wall',
                                                                                        'construction_type' => 'WoodFramed' } }
                                                 }, fallback_building_type: 'SuperMarket')
    assert_equal('Typical Insulated Exterior Mass Wall', wall_of(set).name.to_s)

    set = @constructions.create_construction_set(model_for(cz), std, cz, {
                                                   'surfaces' => { 'exterior_wall' => { 'construction' => 'No Such Construction' } }
                                                 }, fallback_building_type: nil)
    assert(set.defaultExteriorSurfaceConstructions.get.wallConstruction.empty?,
           'an unknown pinned construction should leave the surface unset')
  end

  # Every surface the module knows about is a real setter on the object it belongs to.
  def test_surface_table_matches_the_openstudio_api
    model = OpenStudio::Model::Model.new
    groups = {
      construction_set: OpenStudio::Model::DefaultConstructionSet.new(model),
      exterior_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
      interior_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
      ground_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
      exterior_subsurfaces: OpenStudio::Model::DefaultSubSurfaceConstructions.new(model),
      interior_subsurfaces: OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
    }
    OpenstudioStandards::Constructions::ASSEMBLY_SURFACES.each do |surface, (_type, group, setter)|
      assert(groups[group].respond_to?(setter), "#{surface}: #{group} has no #{setter}")
    end
    OpenstudioStandards::Constructions::NAMED_SURFACES.each do |surface, (group, setter)|
      assert(groups[group].respond_to?(setter), "#{surface}: #{group} has no #{setter}")
    end
  end
end
