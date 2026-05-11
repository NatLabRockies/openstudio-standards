require_relative '../test_helper'

# Test space type assignment and load densities for NECB standards.
# Phase 2 of new NECB test suite.
#
# Tests cover:
# - Space type creation and load application
# - Lighting power density (LPD) assignment and values
# - Equipment power density (EPD) assignment
# - Occupancy density assignment
# - Schedule assignment to loads
# - Comparison between NECB2011 and NECB2020 LPD values
# - Multiple space types in multi-zone models
#
# NOTE: These tests focus on load assignment verification only.
# No HVAC systems or sizing runs are performed.
class TestSpaceTypeAssignment < Minitest::Test
  # Test that office space type has lighting power density assigned
  def test_office_space_type_has_lpd
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create an office space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - open plan')
    space_type.setName('Office - open plan')

    # Apply internal loads to the space type
    standard.space_type_apply_internal_loads(space_type: space_type)

    # Check that LPD was assigned
    lights = space_type.lights
    refute_empty lights, 'Office space type should have lighting defined'

    # Verify that LPD value is greater than zero
    lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        lpd = definition.wattsperSpaceFloorArea.get
        assert lpd > 0, "Office space type LPD should be > 0, got #{lpd}"
      end
    end
  end

  # Test that retail space type has lighting, equipment, and people loads
  def test_retail_space_type_has_all_loads
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create a retail space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Retail')
    space_type.setStandardsSpaceType('WholeBuilding')
    space_type.setName('Retail - WholeBuilding')

    # Apply internal loads
    standard.space_type_apply_internal_loads(space_type: space_type)

    # Check lighting
    lights = space_type.lights
    refute_empty lights, 'Retail space type should have lighting'

    # Check electric equipment
    equipment = space_type.electricEquipment
    refute_empty equipment, 'Retail space type should have electric equipment'

    # Check people
    people = space_type.people
    refute_empty people, 'Retail space type should have people/occupancy'
  end

  # Test that warehouse space type has lower LPD than office
  def test_warehouse_lpd_lower_than_office
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create office space type
    office_st = OpenStudio::Model::SpaceType.new(model)
    office_st.setStandardsBuildingType('Space Function')
    office_st.setStandardsSpaceType('Office - open plan')
    standard.space_type_apply_internal_loads(space_type: office_st)

    # Create storage/warehouse space type
    warehouse_st = OpenStudio::Model::SpaceType.new(model)
    warehouse_st.setStandardsBuildingType('Space Function')
    warehouse_st.setStandardsSpaceType('Storage area')
    standard.space_type_apply_internal_loads(space_type: warehouse_st)

    # Get LPD values
    office_lpd = 0
    office_st.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        office_lpd = definition.wattsperSpaceFloorArea.get
      end
    end

    warehouse_lpd = 0
    warehouse_st.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        warehouse_lpd = definition.wattsperSpaceFloorArea.get
      end
    end

    # Warehouse should have lower LPD than office
    assert warehouse_lpd < office_lpd,
           "Warehouse LPD (#{warehouse_lpd}) should be less than Office LPD (#{office_lpd})"
  end

  # Test that NECB2020 has different LPD than NECB2011 for office space
  def test_necb2020_lpd_differs_from_necb2011
    model_2011 = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')
    model_2020 = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    std_2011 = Standard.build('NECB2011')
    std_2020 = Standard.build('NECB2020')

    # Create office space types for both vintages
    st_2011 = OpenStudio::Model::SpaceType.new(model_2011)
    st_2011.setStandardsBuildingType('Space Function')
    st_2011.setStandardsSpaceType('Office - open plan')
    std_2011.space_type_apply_internal_loads(space_type: st_2011)

    st_2020 = OpenStudio::Model::SpaceType.new(model_2020)
    st_2020.setStandardsBuildingType('Space Function')
    st_2020.setStandardsSpaceType('Office open plan')
    std_2020.space_type_apply_internal_loads(space_type: st_2020)

    # Get LPD values
    lpd_2011 = 0
    st_2011.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        lpd_2011 = definition.wattsperSpaceFloorArea.get
      end
    end

    lpd_2020 = 0
    st_2020.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        lpd_2020 = definition.wattsperSpaceFloorArea.get
      end
    end

    # NECB 2020 typically has lower LPD due to LED requirements
    # At minimum, they should be different values
    refute_equal lpd_2011, lpd_2020,
                 "NECB2011 LPD (#{lpd_2011}) should differ from NECB2020 LPD (#{lpd_2020})"
  end

  # Test that equipment power density is assigned correctly
  def test_space_type_equipment_power_density
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create office space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - open plan')

    # Apply internal loads
    standard.space_type_apply_internal_loads(space_type: space_type)

    # Check that electric equipment was assigned
    equipment = space_type.electricEquipment
    refute_empty equipment, 'Space type should have electric equipment'

    # Verify EPD value
    equipment.each do |equip|
      definition = equip.electricEquipmentDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        epd = definition.wattsperSpaceFloorArea.get
        assert epd > 0, "Equipment power density should be > 0, got #{epd}"
      end
    end
  end

  # Test that occupancy density is assigned correctly
  def test_space_type_occupancy_density
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create office space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - open plan')

    # Apply internal loads
    standard.space_type_apply_internal_loads(space_type: space_type)

    # Check that people were assigned
    people = space_type.people
    refute_empty people, 'Space type should have people/occupancy defined'

    # Verify occupancy density
    people.each do |person|
      definition = person.peopleDefinition
      if definition.peopleperSpaceFloorArea.is_initialized
        occupancy = definition.peopleperSpaceFloorArea.get
        assert occupancy > 0, "Occupancy density should be > 0, got #{occupancy}"
      end
    end
  end

  # Test that loads are assigned when space type is assigned to a space
  def test_loads_assigned_to_space_with_space_type
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - open plan')
    standard.space_type_apply_internal_loads(space_type: space_type)

    # Assign space type to first space
    space = model.getSpaces.first
    space.setSpaceType(space_type)

    # Verify space now has effective loads through space type
    assert space.spaceType.is_initialized, 'Space should have space type assigned'
    assigned_st = space.spaceType.get

    # Check that assigned space type has loads
    refute_empty assigned_st.lights, 'Assigned space type should have lighting'
    refute_empty assigned_st.electricEquipment, 'Assigned space type should have equipment'
    refute_empty assigned_st.people, 'Assigned space type should have occupancy'
  end

  # Test multiple space types in multi-zone model
  def test_multiple_space_types_in_multi_zone_model
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/multi_zone_rectangle.osm')

    # Create different space types
    office_st = OpenStudio::Model::SpaceType.new(model)
    office_st.setStandardsBuildingType('Space Function')
    office_st.setStandardsSpaceType('Office - open plan')
    office_st.setName('Office Space Type')
    standard.space_type_apply_internal_loads(space_type: office_st)

    corridor_st = OpenStudio::Model::SpaceType.new(model)
    corridor_st.setStandardsBuildingType('Space Function')
    corridor_st.setStandardsSpaceType('Corr. < 2.4m wide-sch-A')
    corridor_st.setName('Corridor Space Type')
    standard.space_type_apply_internal_loads(space_type: corridor_st)

    # Get office and corridor LPD
    office_lpd = 0
    office_st.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        office_lpd = definition.wattsperSpaceFloorArea.get
      end
    end

    corridor_lpd = 0
    corridor_st.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        corridor_lpd = definition.wattsperSpaceFloorArea.get
      end
    end

    # Both should have LPD defined
    assert office_lpd > 0, 'Office space type should have LPD'
    assert corridor_lpd > 0, 'Corridor space type should have LPD'

    # Office should have higher LPD than corridor
    assert office_lpd > corridor_lpd,
           "Office LPD (#{office_lpd}) should be greater than Corridor LPD (#{corridor_lpd})"
  end

  # Test that schedules are assigned to loads
  def test_schedules_assigned_to_space_type_loads
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create space type with loads
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('Space Function')
    space_type.setStandardsSpaceType('Office - open plan')
    standard.space_type_apply_internal_loads(space_type: space_type)

    # Apply schedules
    standard.space_type_apply_internal_load_schedules(space_type)

    # Check that schedules were assigned to lights
    space_type.lights.each do |light|
      assert light.schedule.is_initialized, 'Light should have schedule assigned'
    end

    # Check that schedules were assigned to equipment
    space_type.electricEquipment.each do |equipment|
      assert equipment.schedule.is_initialized, 'Equipment should have schedule assigned'
    end

    # Check that schedules were assigned to people
    space_type.people.each do |person|
      assert person.numberofPeopleSchedule.is_initialized, 'People should have schedule assigned'
    end
  end

  # Test that model_add_loads applies loads to all space types
  def test_model_add_loads_applies_to_all_space_types
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/multi_zone_rectangle.osm')

    # Create multiple space types without loads
    office_st = OpenStudio::Model::SpaceType.new(model)
    office_st.setStandardsBuildingType('Space Function')
    office_st.setStandardsSpaceType('Office - open plan')

    retail_st = OpenStudio::Model::SpaceType.new(model)
    retail_st.setStandardsBuildingType('Retail')
    retail_st.setStandardsSpaceType('WholeBuilding')

    # Apply loads to all space types in model using model_add_loads
    standard.model_add_loads(model, 'NECB_Default', 1.0)

    # Check that both space types now have loads
    refute_empty office_st.lights, 'Office space type should have lights after model_add_loads'
    refute_empty retail_st.lights, 'Retail space type should have lights after model_add_loads'
  end
end
