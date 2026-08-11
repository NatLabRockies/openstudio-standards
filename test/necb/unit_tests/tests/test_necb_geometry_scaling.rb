$LOAD_PATH.unshift File.expand_path('../../../../lib', __dir__)

require 'minitest/autorun'
require 'openstudio'
require_relative '../../../../lib/openstudio-standards/btap/geometry'

class NECB_Geometry_Scaling_Tests < Minitest::Test
  def test_scale_model_uses_dimension_multipliers
    model = rectangular_model(length: 10.0, width: 5.0)

    BTAP::Geometry.scale_model(model, 2.0, 1.0, 1.0)

    length, width = horizontal_dimensions(model)
    assert_in_delta(20.0, length, 0.001)
    assert_in_delta(5.0, width, 0.001)
  end

  def test_set_footprint_aspect_ratio_preserves_area_and_height
    model = rectangular_model(length: 10.0, width: 5.0)
    original_floor_area = model.getBuilding.floorArea
    original_height = model.getBuilding.airVolume / original_floor_area

    BTAP::Geometry.set_footprint_aspect_ratio(model, 4.0)

    length, width = horizontal_dimensions(model)
    assert_in_delta(4.0, length / width, 0.001)
    assert_in_delta(original_floor_area, model.getBuilding.floorArea, 0.001)
    assert_in_delta(original_height, model.getBuilding.airVolume / model.getBuilding.floorArea, 0.001)
  end

  def test_set_footprint_aspect_ratio_rejects_values_below_one
    model = rectangular_model(length: 10.0, width: 5.0)

    assert_raises(ArgumentError) do
      BTAP::Geometry.set_footprint_aspect_ratio(model, 0.5)
    end
  end

  def test_horizontal_dimensions_rejects_empty_model
    assert_raises(ArgumentError) do
      BTAP::Geometry.model_horizontal_dimensions(OpenStudio::Model::Model.new)
    end
  end

  def test_set_footprint_aspect_ratio_preserves_archetype_topology
    model = load_archetype('SmallOffice')
    original_floor_area = model.getBuilding.floorArea
    original_matched_surfaces = matched_surface_count(model)

    BTAP::Geometry.set_footprint_aspect_ratio(model, 3.0)

    length, width = horizontal_dimensions(model)
    assert_in_delta(3.0, [length, width].max / [length, width].min, 0.001)
    assert_in_delta(original_floor_area, model.getBuilding.floorArea, 0.001)
    assert_equal(original_matched_surfaces, matched_surface_count(model))
  end

  private

  def rectangular_model(length:, width:)
    model = OpenStudio::Model::Model.new
    points = OpenStudio::Point3dVector.new
    points << OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    points << OpenStudio::Point3d.new(0.0, width, 0.0)
    points << OpenStudio::Point3d.new(length, width, 0.0)
    points << OpenStudio::Point3d.new(length, 0.0, 0.0)
    OpenStudio::Model::Space.fromFloorPrint(points, 3.0, model).get
    model
  end

  def horizontal_dimensions(model)
    bounding_box = OpenStudio::BoundingBox.new
    model.getSpaces.each do |space|
      space.surfaces.each do |surface|
        bounding_box.addPoints(space.transformation * surface.vertices)
      end
    end

    [bounding_box.maxX.get - bounding_box.minX.get,
     bounding_box.maxY.get - bounding_box.minY.get]
  end

  def load_archetype(building_type)
    path = File.expand_path("../../../../lib/openstudio-standards/standards/necb/NECB2011/data/geometry/#{building_type}.osm", __dir__)
    OpenStudio::OSVersion::VersionTranslator.new.loadModel(OpenStudio::Path.new(path)).get
  end

  def matched_surface_count(model)
    model.getSurfaces.count { |surface| surface.outsideBoundaryCondition == 'Surface' }
  end
end