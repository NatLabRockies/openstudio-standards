require_relative '../../helpers/minitest_helper'

class TestGeometryModify < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry

    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    @model = std.safe_load_model("#{File.dirname(__FILE__)}/../../../data/geometry/ASHRAESecondarySchool.osm")
  end

  def test_sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid
    sub_surface = @model.getSubSurfaceByName('Aux_Gym_ZN_1_FLR_1_Wall_2_window_1').get
    starting_area = sub_surface.grossArea
    result = OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(sub_surface, 0.3)
    assert(result)
    ending_area = sub_surface.grossArea
    assert_in_delta(starting_area * 0.7, ending_area, 0.1)

    # test non-retangular geometry
    model = OpenStudio::Model::Model.new

    width = 5.0
    length = 10.0
    polygon = OpenStudio::Point3dVector.new
    polygon << OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << OpenStudio::Point3d.new(0.0, width, 0.0)
    polygon << OpenStudio::Point3d.new(length, width, 0.0)
    polygon << OpenStudio::Point3d.new(length, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get

    south_surface = nil
    space.surfaces.each do |surface|
      south_surface = surface if @geo.surface_get_cardinal_direction(surface) == 'S'
    end

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(6.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(7.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(8.0, 0.0, 1.0)
    tri_sub_surface = OpenStudio::Model::SubSurface.new(vertices, model)
    tri_sub_surface.setSurface(south_surface)

    starting_area = tri_sub_surface.grossArea
    result = OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(tri_sub_surface, 0.4)
    assert(result)
    ending_area = tri_sub_surface.grossArea
    assert_in_delta(starting_area * 0.6, ending_area, 0.1)
  end

  def test_sub_surface_reduce_area_by_percent_by_raising_sill
    sub_surface = @model.getSubSurfaceByName('Aux_Gym_ZN_1_FLR_1_Wall_2_window_1').get
    starting_area = sub_surface.grossArea
    result = OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_raising_sill(sub_surface, 0.3)
    assert(result)
    ending_area = sub_surface.grossArea
    assert_in_delta(starting_area * 0.7, ending_area, 0.1)

    # test issue with mixed z axis
    model = OpenStudio::Model::Model.new

    width = 5.0
    length = 10.0
    polygon = OpenStudio::Point3dVector.new
    polygon << OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << OpenStudio::Point3d.new(0.0, width, 0.0)
    polygon << OpenStudio::Point3d.new(length, width, 0.0)
    polygon << OpenStudio::Point3d.new(length, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get

    south_surface = nil
    space.surfaces.each do |surface|
      south_surface = surface if @geo.surface_get_cardinal_direction(surface) == 'S'
    end

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 0.99)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 2.0)
    rect_sub_surface = OpenStudio::Model::SubSurface.new(vertices, model)
    rect_sub_surface.setSurface(south_surface)

    starting_area = rect_sub_surface.grossArea
    result = OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_raising_sill(rect_sub_surface, 0.4)
    assert(result)
    ending_area = rect_sub_surface.grossArea
    assert_in_delta(starting_area * 0.6, ending_area, 0.1)
  end

  def test_space_rename_surfaces_and_subsurfaces
    space = @model.getSpaceByName('Gym_ZN_1_FLR_1').get
    result = @geo.space_rename_surfaces_and_subsurfaces(space)
    surface = @model.getSurfaceByName('Gym_ZN_1_FLR_1 RoofCeiling 1')
    assert(surface.is_initialized)
    sub_surface = @model.getSubSurfaceByName('Gym_ZN_1_FLR_1 RoofCeiling 1 Skylight 1')
    assert(sub_surface.is_initialized)
  end

  def test_model_assign_spaces_to_building_stories
    result = @geo.model_assign_spaces_to_building_stories(@model)
    assert(result)
  end

  def test_model_rename_surfaces_and_subsurfaces
    result = @geo.model_rename_surfaces_and_subsurfaces(@model)
    surface = @model.getSurfaceByName('Gym_ZN_1_FLR_1 RoofCeiling 1')
    assert(surface.is_initialized)
    sub_surface = @model.getSubSurfaceByName('Gym_ZN_1_FLR_1 RoofCeiling 1 Skylight 1')
    assert(sub_surface.is_initialized)
    assert(result)
  end

  def test_model_set_building_north_axis
    result = @geo.model_set_building_north_axis(@model, 45.0)
    assert(result)
    assert(45.0, @model.getBuilding.northAxis)
  end
end