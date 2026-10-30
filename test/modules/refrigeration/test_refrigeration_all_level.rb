require_relative '../../helpers/minitest_helper'

# Tests for the all-level space type crosswalk on typical refrigeration. Unlike exhaust and
# service water heating, the building type stays part of the key: the amount of refrigeration a
# space holds depends on the building as much as on the space, and a supermarket sales floor and
# a hotel gift shop are the same all-level space type.
#
# The DOE prototype and DEER paths are covered by test_create_typical_refrigeration.rb.
class TestRefrigerationAllLevel < Minitest::Test
  def setup
    @refrig = OpenstudioStandards::Refrigeration
    @geo = OpenstudioStandards::Geometry
  end

  # Build a model the way the typical path does: all-level space type names, and the building
  # type carried by the Building object rather than by each space type.
  def all_level_model(building_type, space_types)
    model = OpenStudio::Model::Model.new
    model.getBuilding.setStandardsBuildingType(building_type)
    space_types.each do |name, area_ft2|
      st = OpenStudio::Model::SpaceType.new(model)
      st.setName(name)
      st.setStandardsSpaceType(name)

      space = OpenStudio::Model::Space.fromFloorPrint(
        square_polygon(OpenStudio.convert(area_ft2, 'ft^2', 'm^2').get), 3.0, model
      ).get
      space.setName("#{name} space")
      space.setSpaceType(st)
    end
    model
  end

  def square_polygon(area_m2)
    side = Math.sqrt(area_m2)
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    vertices << OpenStudio::Point3d.new(0.0, side, 0.0)
    vertices << OpenStudio::Point3d.new(side, side, 0.0)
    vertices << OpenStudio::Point3d.new(side, 0.0, 0.0)
    vertices
  end

  # the space types carry no building type of their own; the getter falls back to the Building
  def test_building_type_comes_from_the_building_object
    model = all_level_model('SuperMarket', { 'retail' => 27_500.0 })
    st = model.getSpaceTypes.first
    assert(st.standardsBuildingType.is_initialized, 'standardsBuildingType did not fall back to the Building object')
    assert_equal('SuperMarket', st.standardsBuildingType.get)
  end

  def test_supermarket_gets_its_cases_and_walkins
    model = all_level_model('SuperMarket', { 'retail' => 27_500.0, 'storage' => 4500.0 })
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(8, result[:cases].size, 'the sales floor lost its display cases')
    assert_equal(14, result[:walkins].size, 'the storage room lost its walk-ins')
  end

  # A qualified name inherits its level-1 name's rows, as the thermostat and schedule lookups
  # do. The grocery spec moved its sales floor from 'retail' to 'retail - supermarket' and lost
  # all eight display cases in a validation run, because the row was matched exactly.
  def test_qualified_sales_floor_keeps_its_cases
    model = all_level_model('SuperMarket', { 'retail - supermarket' => 27_500.0, 'storage' => 4500.0 })
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(8, result[:cases].size, 'the qualified sales floor lost its display cases')
    assert_equal(14, result[:walkins].size)
    # the building type still gates it
    hotel = all_level_model('LargeHotel', { 'retail - supermarket' => 27_500.0 })
    assert_empty(@refrig.typical_refrigeration_equipment_list(hotel)[:cases])
    # a qualified name the data tags has rows of its own and does not fall back
    school_kitchen_in_hospital = all_level_model('Hospital', { 'food preparation - primary school' => 10_000.0 })
    assert_empty(@refrig.typical_refrigeration_equipment_list(school_kitchen_in_hospital)[:walkins])
  end

  # The reason the building type stays in the key. 'retail' is used by RetailStandalone,
  # RetailStripmall and LargeHotel as well as SuperMarket, and only a supermarket sales floor is
  # refrigerated.
  def test_retail_alone_does_not_earn_display_cases
    ['LargeHotel', 'RetailStandalone', 'RetailStripmall'].each do |building_type|
      model = all_level_model(building_type, { 'retail' => 27_500.0, 'storage' => 4500.0 })
      result = @refrig.typical_refrigeration_equipment_list(model)
      assert_empty(result[:cases], "#{building_type} retail should not get display cases")
      assert_empty(result[:walkins], "#{building_type} storage should not get walk-ins")
    end
  end

  # Kitchens, where the space type is shared but the walk-in size and its reference area are not.
  def test_kitchen_walkins_are_sized_per_building_type
    kitchens = {
      'FullServiceRestaurant' => ['food preparation', 1500.0],
      'QuickServiceRestaurant' => ['food preparation', 1250.0],
      'LargeHotel' => ['food preparation', 1110.0],
      'Hospital' => ['food preparation', 10_000.0],
      'PrimarySchool' => ['food preparation - primary school', 1800.0],
      'SecondarySchool' => ['food preparation - secondary school', 2325.0]
    }
    kitchens.each do |building_type, (space_type, reference_area)|
      model = all_level_model(building_type, { space_type => reference_area })
      result = @refrig.typical_refrigeration_equipment_list(model)
      assert_equal(2, result[:walkins].size, "#{building_type} #{space_type} lost its walk-ins")
      assert_empty(result[:cases], "#{building_type} should have no display cases")
    end
  end

  # A school kitchen's own all-level name reaches its own record, and not the generic one.
  def test_school_kitchen_names_do_not_cross
    model = all_level_model('PrimarySchool', { 'food preparation' => 1800.0 })
    assert_empty(@refrig.typical_refrigeration_equipment_list(model)[:walkins],
                 "a primary school's kitchen is 'food preparation - primary school', not 'food preparation'")

    model = all_level_model('Hospital', { 'food preparation - primary school' => 10_000.0 })
    assert_empty(@refrig.typical_refrigeration_equipment_list(model)[:walkins],
                 'a hospital kitchen should not match the primary school record')
  end

  # Under a DEER template primary_building_type is the DEER code, so the DEER rows stay reachable
  # from all-level space type names.
  def test_deer_building_types_reach_their_own_rows
    model = all_level_model('Gro', { 'retail' => 40_000.0 })
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(8, result[:cases].size, 'a DEER grocery lost its display cases')
    assert_equal(14, result[:walkins].size, 'a DEER grocery lost its walk-ins')

    { 'Hsp' => 'food preparation', 'Htl' => 'food preparation',
      'EPr' => 'food preparation - primary school', 'ESe' => 'food preparation - secondary school' }.each do |bt, st|
      model = all_level_model(bt, { st => 2000.0 })
      assert_equal(2, @refrig.typical_refrigeration_equipment_list(model)[:walkins].size, "DEER #{bt} lost its walk-ins")
    end
  end

  # The DEER restaurant rows key on a StockRoom space type that no DEER restaurant model has, so
  # they have never matched anything. They are left untagged rather than pointed at a kitchen,
  # which would turn dead data into new equipment.
  def test_dead_deer_restaurant_rows_stay_dead
    rows = CSV.table("#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/refrigeration/data/typical_refrigerated_walkins.csv",
                     encoding: 'ISO8859-1:utf-8').map(&:to_hash)
    dead = rows.select { |r| ['RFF', 'RSD'].include?(r[:building_type]) }
    assert_equal(4, dead.size)
    dead.each do |row|
      assert_nil(row[:all_level_space_type], "#{row[:building_type]} #{row[:space_type]} should stay untagged")
      refute_nil(row[:notes], "#{row[:building_type]} #{row[:space_type]} should say why it is untagged")
    end

    ['RFF', 'RSD'].each do |bt|
      model = all_level_model(bt, { 'food preparation' => 1250.0 })
      assert_empty(@refrig.typical_refrigeration_equipment_list(model)[:walkins],
                   "DEER #{bt} should have no walk-ins, matching the prototype path")
    end
  end

  # Every tagged row's all-level name has to be a real space type name.
  def test_tagged_names_are_valid_all_level_space_types
    valid = JSON.parse(File.read("#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/space_type/data/all_level_space_types.json"))
    valid = (valid.is_a?(Array) ? valid : valid.values.find { |v| v.is_a?(Array) }).map { |r| r['space_type_name'] }

    ['typical_refrigerated_cases', 'typical_refrigerated_walkins'].each do |file|
      rows = CSV.table("#{File.dirname(__FILE__)}/../../../lib/openstudio-standards/refrigeration/data/#{file}.csv",
                       encoding: 'ISO8859-1:utf-8').map(&:to_hash)
      rows.each do |row|
        next if row[:all_level_space_type].nil?

        row[:all_level_space_type].to_s.split('|').map(&:strip).each do |name|
          assert_includes(valid, name, "#{file}: '#{name}' is not an all-level space type name")
        end
      end
    end
  end

  # The zone the equipment lands in is chosen by the same matcher, so it has to follow.
  def test_equipment_zone_selection_follows_the_all_level_name
    model = OpenStudio::Model::Model.new
    args = { 'total_bldg_floor_area' => 50_000.0, 'bldg_type_a' => 'SuperMarket' }
    @geo.create_bar_from_building_type_ratios(model, args)

    # relabel the sales floor and dry storage with their all-level names
    model.getSpaceTypes.each do |st|
      next unless st.standardsSpaceType.is_initialized

      case st.standardsSpaceType.get
      when 'Sales' then st.setStandardsSpaceType('retail')
      when 'DryStorage' then st.setStandardsSpaceType('storage')
      end
    end

    refute_nil(@refrig.refrigeration_case_zone(model), 'no zone was chosen for the display cases')
    refute_nil(@refrig.refrigeration_walkin_zone(model), 'no zone was chosen for the walk-ins')
    result = @refrig.typical_refrigeration_equipment_list(model)
    assert_equal(8, result[:cases].size)
    assert_equal(14, result[:walkins].size)
  end
end
