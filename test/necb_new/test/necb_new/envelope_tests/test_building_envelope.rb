require_relative '../test_helper'

# Building Envelope Tests for NECB
# Tests envelope calculations, FDWR, SRR, U-values, and construction application

class TestBuildingEnvelope < Minitest::Test

  # Helper to create a simple test model with geometry
  def create_test_model_with_geometry(template: 'NECB2011')
    standard = Standard.build(template)
    model = OpenStudio::Model::Model.new

    # Create a simple box geometry
    length = 20.0
    width = 15.0
    height = 3.0
    num_floors = 2

    OpenstudioStandards::Geometry.create_shape_rectangle(
      model,
      length,
      width,
      height,
      num_floors,
      0, # No plenum
      OpenStudio::Point3dVector.new
    )

    # Set weather file (Toronto - Zone 5, HDD ~4000)
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply NECB space types
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    # Set building properties
    building = model.getBuilding
    building.setStandardsNumberOfStories(num_floors)
    building.setStandardsNumberOfAboveGroundStories(num_floors)

    return model, standard
  end

  # ============================================================================
  # HDD Calculations
  # ============================================================================

  def test_get_necb_hdd18_returns_value
    # Test that HDD calculation returns a valid number
    model, standard = create_test_model_with_geometry

    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)

    assert hdd.is_a?(Numeric), "HDD should be a number"
    assert hdd > 0, "HDD should be positive"
    assert hdd < 10000, "HDD should be reasonable (< 10000)"
  end

  def test_get_necb_hdd18_toronto_is_correct
    # Test that Toronto HDD is approximately correct (~4000)
    model, standard = create_test_model_with_geometry

    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)

    # Toronto is Climate Zone 5 with HDD ~3700-4300
    assert hdd > 3500, "Toronto HDD should be > 3500, got #{hdd}"
    assert hdd < 4500, "Toronto HDD should be < 4500, got #{hdd}"
  end

  def test_max_fwdr_returns_value
    # Test that max FDWR calculation returns a valid percentage
    model, standard = create_test_model_with_geometry

    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)
    max_fdwr = standard.max_fwdr(hdd)

    assert max_fdwr.is_a?(Numeric), "Max FDWR should be a number"
    assert max_fdwr > 0, "Max FDWR should be positive"
    assert max_fdwr < 1, "Max FDWR should be < 1 (it's a ratio)"
  end

  def test_max_u_necb_returns_value_for_walls
    # Test that U-value calculation returns valid values for walls
    model, standard = create_test_model_with_geometry

    hdd = standard.get_necb_hdd18(model: model, necb_hdd: true)
    u_value = standard.max_u_necb("wall", "outdoors", hdd)

    assert u_value.is_a?(Numeric), "U-value should be a number"
    assert u_value > 0, "U-value should be positive"
    assert u_value < 2.0, "U-value should be reasonable (< 2.0 W/m²K)"
  end
end
