require_relative '../../helpers/minitest_helper'

class TestSpaceTypeModule < Minitest::Test
  def test_set_standards_space_type_additional_properties
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))

    # test basic mapping
    std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: false)
    model.getSpaceTypes.each do |space_type|
      value = space_type.additionalProperties.getFeatureAsString('standards_space_type').to_s
      case space_type.name.to_s
      when 'PrimarySchool Classroom'
        assert('classroom/lecture/training', value)
      when 'PrimarySchool ComputerRoom'
        assert('classroom/lecture/training', value)
      when 'PrimarySchool Kitchen'
        assert('food preparation', value)
      when 'PrimarySchool Cafeteria'
        assert('dining', value)
      when 'PrimarySchool Library'
        assert('library', value)
      when 'PrimarySchool Office'
        assert('office', value)
      when 'PrimarySchool Restroom'
        assert('restroom', value)
      when 'PrimarySchool MechanicalRoom'
        assert('electrical/mechanical', value)
      when 'PrimarySchool Corridor'
       assert('corridor', value)
      when 'PrimarySchool Gym'
        assert('exercise area', value)
      end
    end

    # test setting additional properties
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model, space_type_field: 'AdditionalProperties', reset_standards_space_type: false)

    # check the correct lighting space type was set
    model.getSpaceTypes.each do |space_type|
      value = space_type.additionalProperties.getFeatureAsString('lighting_space_type').to_s
      case space_type.standardsSpaceType.get.to_s
      when 'Office'
        assert_equal('office_lighting', value) # office_enclosed_lighting?
      when 'Lobby'
        assert_equal('lobby_lighting', value)
      when 'Gym'
        assert_equal('exercise_area_lighting', value) # playing_area_lighting?
      when 'Mechanical'
        assert_equal('electrical_mechanical_lighting', value)
      when 'Cafeteria'
        assert_equal('dining_lighting', value) # dining_cafeteria_fast_food_general_lighting?
      when 'Kitchen'
        assert_equal('food_preparation_lighting', value)
      when 'Restroom'
        assert_equal('restroom_lighting', value)
      when 'Corridor'
        assert_equal('corridor_lighting', value)
      when 'Classroom'
        assert_equal('classroom_lecture_training_lighting', value)
      when 'ComputerRoom'
        assert_equal('computer_room_lighting', value)
      when 'Library'
        assert_equal('library_lighting', value) # library_reading_area_lighting?
      end
    end
  end

  def test_set_standards_space_type_additional_properties_all_ashrae_models
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAECollege.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAECourthouse.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEFullServiceRestaurant.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEHighriseApartment.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEHospital.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAELaboratory.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAELargeDataCenterHighITE.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAELargeDataCenterLowITE.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAELargeHotel.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAELargeOffice.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEMediumOffice.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEMidriseApartment.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEOutpatient.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEQuickServiceRestaurant.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAERetailStripmall.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAESecondarySchool.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAESmallDataCenterHighITE.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAESmallDataCenterLowITE.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAESmallHotel.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAESuperMarket.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAE90120102013Warehouse.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))
  end

  def test_set_standards_space_type_additional_properties_all_deer_models
    # load model and set up weather file
    template = 'DEER 2011'
    climate_zone = 'CEC T24-CEC3'
    std = Standard.build(template)

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_Asm.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_ECC.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_EPr.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_ESe.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_EUn.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_Gro.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_Hsp.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_Htl.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_MBT.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    # model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_MFm.osm")
    # assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    # assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_MLI.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_Nrs.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_OfL.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_OfS.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_RFF.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_RSD.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_Rt3.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_RtL.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_RtS.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_SCn.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_SUn.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))

    # model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_WRf.osm")
    # assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    # assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true))
  end
end