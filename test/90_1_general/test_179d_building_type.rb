require_relative '../helpers/minitest_helper'

class ACM179dASHRAE9012007BuildingTypeTest < Minitest::Test

  SPACE_HEIGHT = 3.0
  # Helper to create a model targeting a specific builing area in sqft
  def make_rectangular_building_with_area(building_area_sqft, n_floors = 1)

    building_area_m2 = OpenStudio.convert(building_area_sqft, 'ft^2', 'm^2').get
    space_area_m2 = building_area_m2 / n_floors

    length = Math.sqrt(space_area_m2 / 2)
    width = 2 * length

    min_y = 0.0
    max_y = length
    min_x = 0.0
    max_x = width

    z = 0.0

    m = OpenStudio::Model::Model.new

    spaces = OpenStudio::Model::SpaceVector.new
    n_floors.times do |floor|
      z = floor * SPACE_HEIGHT
      # ULC, but this is a floor, so outward normal must be pointing down, so we use clockwise order
      arr = [
        [max_x, max_y, z],
        [max_x, min_y, z],
        [min_x, min_y, z],
        [min_x, max_y, z],
      ]
      space = OpenStudio::Model::Space.fromFloorPrint(arr.map{|pt| OpenStudio::Point3d.new(*pt)}, 3, m).get
      space.setName("Space#{floor + 1}")
      story = OpenStudio::Model::BuildingStory.new(m)
      story.setName("Story#{floor + 1}")
      space.setBuildingStory(story)

      spaces << space
    end

    OpenStudio::Model.matchSurfaces(spaces)

    return m
  end

  OFFICE_DATA = [
    # building_area_sqft, n_floors, primary_building_type, expected_primary_building_type, standards_space_type
    # Cutoffs on area are 25000 and 150000
    # Area < 25,000
    [10.0, 1, 'Office', 'SmallOffice', 'WholeBuilding - Sm Office'],
    [10.0, 3, 'Office', 'SmallOffice', 'WholeBuilding - Sm Office'],
    [10.0, 4, 'Office', 'MediumOffice', 'WholeBuilding - Md Office'],
    [24999.0, 1, 'Office', 'SmallOffice', 'WholeBuilding - Sm Office'],
    [24999.0, 3, 'Office', 'SmallOffice', 'WholeBuilding - Sm Office'],
    [24999.0, 4, 'Office', 'MediumOffice', 'WholeBuilding - Md Office'],
    # 25,000 <= area_ft2 < 150,000
    [25001.0, 5, 'Office', 'MediumOffice', 'WholeBuilding - Md Office'],
    [25001.0, 6, 'Office', 'LargeOffice', 'WholeBuilding - Lg Office'],
    [149999.0, 5, 'Office', 'MediumOffice', 'WholeBuilding - Md Office'],
    [149999.0, 6, 'Office', 'LargeOffice', 'WholeBuilding - Lg Office'],
    # area_ft2 >= 150,000
    [150001.0, 1, 'Office', 'LargeOffice', 'WholeBuilding - Lg Office'],
  ]
  OFFICE_LPD = 1.0 # Office from Table 9.5.1 of 90.1-2007


  @@logSink = nil

  def suite_init
    OpenStudio::Logger.instance.standardOutLogger.disable
    sink = OpenStudio::StringStreamLogSink.new
    sink.setLogLevel(OpenStudio::Warn)
    sink
  end

  attr_accessor :template, :standard, :model
  def setup
    @@logSink ||= suite_init
    @@logSink.resetStringStream

    @template = '179D 90.1-2007'
    @standard = Standard.build(@template)
  end

  def building_type_test(building_area_sqft, n_floors, building_type, expected_primary_building_type, standards_space_type, expected_lpd_ip, lighting_secondary_space_type, lighting_schedule)
    model = make_rectangular_building_with_area(building_area_sqft, n_floors)
    assert_in_delta(building_area_sqft, OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get, 0.01)

    sp = OpenStudio::Model::SpaceType.new(model)
    sp.setStandardsBuildingType(building_type)
    sp.setStandardsSpaceType(standards_space_type)
    model.getSpaces.each{|s| s.setSpaceType(sp) }

    model.getSpaces.each do |s|
      z = OpenStudio::Model::ThermalZone.new(model)
      s.setThermalZone(z)
    end

    primary_building_type_no_remap = @standard.model_get_primary_building_type(model, remap_office: false)
    assert_equal(building_type, primary_building_type_no_remap)

    primary_building_type = @standard.model_get_primary_building_type(model, remap_office: true)
    assert_equal(expected_primary_building_type, primary_building_type)


    sp_type_name = @standard.whole_building_space_type_name(model, building_type)
    assert_equal(standards_space_type, sp_type_name)

    # Even if you mess up and pass SmallOffice, it works
    sp_type_name = @standard.whole_building_space_type_name(model, expected_primary_building_type)
    assert_equal(standards_space_type, sp_type_name)

    data = standard.space_type_get_standards_data(sp)
    refute_nil(data)
    refute_empty(data)
    assert_equal('179d-90.1-2007', data['template'])
    assert_equal(building_type, data['building_type'])
    assert_equal(standards_space_type, data['space_type'])
    assert_equal('ASHRAE 90.1-2007', data['lighting_standard'])
    assert_equal('WholeBuilding', data['lighting_primary_space_type'])
    assert_equal(lighting_secondary_space_type, data['lighting_secondary_space_type'])
    assert_in_delta(expected_lpd_ip, data['lighting_per_area'])
    assert_equal(lighting_schedule, data['lighting_schedule'])
  end

  OFFICE_DATA.each do |building_area_sqft, n_floors, building_type, expected_primary_building_type, standards_space_type|
    define_method("test_office_get_building_type_#{building_area_sqft.to_i}sqft_#{n_floors}floors") do
      building_type_test(building_area_sqft, n_floors, building_type, expected_primary_building_type, standards_space_type, OFFICE_LPD, 'Office', 'Nonres_Light_Sch')
    end
  end

  def test_get_building_type_sanitizes
    building_area_sqft, n_floors, building_type, expected_primary_building_type, standards_space_type = [160_000, 5, 'Office', 'LargeOffice', 'WholeBuilding - Lg Office']
    model = make_rectangular_building_with_area(building_area_sqft, n_floors)
    assert_equal(5, model.getSpaces.size)

    spaces = model.getSpaces.sort_by(&:nameString)

    building_types = ['SmallOffice', 'MediumOffice', 'LargeOffice']
    building_types.zip(spaces).each do |building_type, s|
      z = OpenStudio::Model::ThermalZone.new(model)
      s.setThermalZone(z)

      sp = OpenStudio::Model::SpaceType.new(model)
      sp.setStandardsBuildingType(building_type)
      sp.setStandardsSpaceType('Gibberish')
      s.setSpaceType(sp)
    end

    sp_warehouse = sp = OpenStudio::Model::SpaceType.new(model)
    sp_warehouse.setStandardsBuildingType('Warehouse')
    sp_warehouse.setStandardsSpaceType('Gibberish')
    spaces[-2..].each do |s|
      s.setSpaceType(sp_warehouse)
    end

    model.getBuilding.setStandardsBuildingType('FullServiceRestaurant')

    # We use model_get_lookup_name inside the model_get_primary_building_type,
    # so the first two resolve to 'Office' and it 'wins' the space_area method
    # And the space area method trumps the building one!
    primary_building_type_no_remap = @standard.model_get_primary_building_type(model, remap_office: false)
    assert_equal(building_type, primary_building_type_no_remap)

    primary_building_type = @standard.model_get_primary_building_type(model, remap_office: true)
    assert_equal(expected_primary_building_type, primary_building_type)

    sp_type_name = @standard.whole_building_space_type_name(model, 'Office')
    assert_equal(standards_space_type, sp_type_name)

    warns =  @@logSink.logMessages.select { |l| l.logLevel == OpenStudio::Warn }
    assert_equal(1, warns.size)
    logMessage = warns.first.logMessage
    assert_equal("The Building has standardsBuildingType 'FullServiceRestaurant' while the area determination based on space types has 'Office'. Preferring the Space Type one", logMessage)
  end

  def test_throws_if_none_can_be_found
    model = OpenStudio::Model::Model.new

    assert_raises(RuntimeError) { @standard.model_get_primary_building_type(model, remap_office: false) }
    errors =  @@logSink.logMessages.select { |l| l.logLevel == OpenStudio::Error }
    assert_equal(1, errors.size)
    logMessage = errors.first.logMessage
    assert_equal("Cannot identify a single building type in model, none of your 0 SpaceTypes have a standardsBuildingType assigned and neither does the Building", logMessage)
  end

  LPD_RETAIL = 1.5

  def retail_test(building_type, remapped_building_type)
    building_area_sqft, n_floors, building_type, expected_primary_building_type, standards_space_type = [5_000, 5, building_type, remapped_building_type, 'WholeBuilding']
    model = make_rectangular_building_with_area(building_area_sqft, n_floors)

    model = make_rectangular_building_with_area(building_area_sqft, n_floors)
    assert_equal(5, model.getSpaces.size)

    spaces = model.getSpaces.sort_by(&:nameString)

    building_types = [building_type, building_type, remapped_building_type, 'Office', 'Office']
    building_types.zip(spaces).each do |building_type, s|
      z = OpenStudio::Model::ThermalZone.new(model)
      s.setThermalZone(z)

      sp = OpenStudio::Model::SpaceType.new(model)
      sp.setStandardsBuildingType(building_type)
      sp.setStandardsSpaceType('Gibberish')
      s.setSpaceType(sp)
    end

    model.getBuilding.setStandardsBuildingType('FullServiceRestaurant')

    # We use model_get_lookup_name inside the model_get_primary_building_type,
    # so the first two resolve to 'Office' and it 'wins' the space_area method
    # And the space area method trumps the building one!
    primary_building_type_no_remap = @standard.model_get_primary_building_type(model, remap_retail: false)
    assert_equal(building_type, primary_building_type_no_remap)

    primary_building_type_remap = @standard.model_get_primary_building_type(model, remap_retail: true)
    assert_equal(remapped_building_type, primary_building_type_remap)

    standards_space_type = @standard.whole_building_space_type_name(model, building_type)
    assert_equal('WholeBuilding', standards_space_type)

    warns =  @@logSink.logMessages.select { |l| l.logLevel == OpenStudio::Warn }
    assert_equal(1, warns.size)
    logMessage = warns.first.logMessage
    assert_equal("The Building has standardsBuildingType 'FullServiceRestaurant' while the area determination based on space types has '#{building_type}'. Preferring the Space Type one", logMessage)

    data = standard.space_type_get_standards_data(model.getSpaceTypes.first)
    refute_nil(data)
    refute_empty(data)
    assert_equal('179d-90.1-2007', data['template'])
    assert_equal(building_type, data['building_type'])
    assert_equal(standards_space_type, data['space_type'])
    assert_equal('ASHRAE 90.1-2007', data['lighting_standard'])
    assert_equal('WholeBuilding', data['lighting_primary_space_type'])
    assert_in_delta(LPD_RETAIL, data['lighting_per_area'])
    assert_equal('Retail_Light_Sch', data['lighting_schedule'])
  end

  RETAILS = [
    # building_type, remapped_building_type
    ['StripMall', 'RetailStripmall'],
    ['Retail', 'RetailStandalone'],
  ]
  RETAILS.each do |building_type, remapped_building_type|
    define_method("test_retail_#{remapped_building_type.downcase}") do
      retail_test(building_type, remapped_building_type)
    end
  end



  OTHER_SUPPORTED_BTS = [
    # building_type,  expected_lpd_ip, lighting_secondary_space_type, lighting_schedule
    ["FullServiceRestaurant", 1.6, "General", "Nonres_Light_Sch"],
    ["PrimarySchool", 1.2, "General", "SchoolPrimary_Light_Sch"],
    ["QuickServiceRestaurant", 1.4, "General", "Nonres_Light_Sch"],
    ["SmallHotel", 1.0, "General", "Res_Light_Sch"],
    ["Warehouse", 0.8, "Warehouse", "Nonres_Light_Sch"],
  ]

  OTHER_SUPPORTED_BTS.each do |building_type,  expected_lpd_ip, lighting_secondary_space_type, lighting_schedule|
    define_method("test_other_#{building_type.downcase}") do
      building_area_sqft = 5_000
      n_floors = 1
      standards_space_type = 'WholeBuilding'
      expected_primary_building_type = building_type
      building_type_test(building_area_sqft, n_floors, building_type, expected_primary_building_type, standards_space_type, expected_lpd_ip, lighting_secondary_space_type, lighting_schedule)
    end
  end

end
