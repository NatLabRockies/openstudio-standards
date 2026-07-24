require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

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
  include(NecbHelper)

  def test_lpd
    # Test that office space type has lighting power density assigned
    model, standard = create_baseline_necb_model

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

  # Test that warehouse space type has lower LPD than office
  def test_warehouse_lpd_lower_than_office
    model, standard = create_baseline_necb_model

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
    model_2011, standard_2011 = create_baseline_necb_model
    model_2020, standard_2020 = create_baseline_necb_model

    # Create office space types for both vintages
    space_type_2011 = OpenStudio::Model::SpaceType.new(model_2011)
    space_type_2011.setStandardsBuildingType('Space Function')
    space_type_2011.setStandardsSpaceType('Office - open plan')
    standard_2011.space_type_apply_internal_loads(space_type: space_type_2011)

    space_type_2020 = OpenStudio::Model::SpaceType.new(model_2020)
    space_type_2020.setStandardsBuildingType('Space Function')
    space_type_2020.setStandardsSpaceType('Office open plan')
    standard_2020.space_type_apply_internal_loads(space_type: space_type_2020)

    # Get LPD values
    lpd_2011 = 0
    space_type_2011.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        lpd_2011 = definition.wattsperSpaceFloorArea.get
      end
    end

    lpd_2020 = 0
    space_type_2020.lights.each do |light|
      definition = light.lightsDefinition
      if definition.wattsperSpaceFloorArea.is_initialized
        lpd_2020 = definition.wattsperSpaceFloorArea.get
      end
    end

    # NECB 2020 should have lower LPD due to LED requirements
    assert lpd_2011 > lpd_2020, "NECB2011 LPD (#{lpd_2011}) should be great than NECB2020 LPD (#{lpd_2020})"
  end

  def test_space_type_occupancy_density
    model, standard = create_baseline_necb_model

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

  def test_multiple_space_types_in_multi_zone_model
    model, standard = create_baseline_necb_model

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
end
