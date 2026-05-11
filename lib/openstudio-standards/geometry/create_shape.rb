module OpenstudioStandards
  # The Geometry module provides methods to create, modify, and get information about model geometry
  module Geometry
    # Methods to create basic shapes

    # @!group Create:Shape

    # Create a Rectangle shape in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param length [Double] Building length in meters
    # @param width [Double] Building width in meters
    # @param above_ground_storys [Integer] Number of above ground stories
    # @param under_ground_storys [Integer] Number of below ground stories
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @param initial_height [Double] Initial height in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_rectangle(model,
                                    length = 100.0,
                                    width = 100.0,
                                    above_ground_storys = 3,
                                    under_ground_storys = 1,
                                    floor_to_floor_height = 3.8,
                                    plenum_height = 1.0,
                                    perimeter_zone_depth = 4.57,
                                    initial_height = 0.0)
      if length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Length must be greater than 0.')
        return nil
      end

      if width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Width must be greater than 0.')
        return nil
      end

      if (above_ground_storys + under_ground_storys) <= 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Number of floors must be greater than 0.')
        return nil
      end

      if floor_to_floor_height <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Floor to floor height must be greater than 0.')
        return nil
      end

      if plenum_height < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Plenum height must be greater than 0.')
        return nil
      end

      shortest_side = [length, width].min
      if perimeter_zone_depth < 0 || 2 * perimeter_zone_depth >= (shortest_side - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Perimeter zone depth must be greater than or equal to 0 and less than half of the smaller of length and width, #{(shortest_side / 2).round(2)}m")
        return nil
      end

      # Loop through the number of floors
      building_stories = []
      for floor in ((under_ground_storys * -1)..above_ground_storys - 1)
        z = (floor_to_floor_height * floor) + initial_height

        # Create a new story within the building
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setNominalFloortoFloorHeight(floor_to_floor_height)
        story.setName("Story #{floor + 1}")
        building_stories << story

        nw_point = OpenStudio::Point3d.new(0, width, z)
        ne_point = OpenStudio::Point3d.new(length, width, z)
        se_point = OpenStudio::Point3d.new(length, 0, z)
        sw_point = OpenStudio::Point3d.new(0, 0, z)

        # Identity matrix for setting space origins
        m = OpenStudio::Matrix.new(4, 4, 0)
        m[0, 0] = 1
        m[1, 1] = 1
        m[2, 2] = 1
        m[3, 3] = 1

        # Define polygons for a rectangular building
        if perimeter_zone_depth > 0
          perimeter_nw_point = nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_ne_point = ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_se_point = se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_sw_point = sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)

          west_polygon = OpenStudio::Point3dVector.new
          west_polygon << sw_point
          west_polygon << nw_point
          west_polygon << perimeter_nw_point
          west_polygon << perimeter_sw_point
          west_space = OpenStudio::Model::Space.fromFloorPrint(west_polygon, floor_to_floor_height, model)
          west_space = west_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          west_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_space.setBuildingStory(story)
          west_space.setName("Story #{floor + 1} West Perimeter Space")

          north_polygon = OpenStudio::Point3dVector.new
          north_polygon << nw_point
          north_polygon << ne_point
          north_polygon << perimeter_ne_point
          north_polygon << perimeter_nw_point
          north_space = OpenStudio::Model::Space.fromFloorPrint(north_polygon, floor_to_floor_height, model)
          north_space = north_space.get
          m[0, 3] = perimeter_nw_point.x
          m[1, 3] = perimeter_nw_point.y
          m[2, 3] = perimeter_nw_point.z
          north_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_space.setBuildingStory(story)
          north_space.setName("Story #{floor + 1} North Perimeter Space")

          east_polygon = OpenStudio::Point3dVector.new
          east_polygon << ne_point
          east_polygon << se_point
          east_polygon << perimeter_se_point
          east_polygon << perimeter_ne_point
          east_space = OpenStudio::Model::Space.fromFloorPrint(east_polygon, floor_to_floor_height, model)
          east_space = east_space.get
          m[0, 3] = perimeter_se_point.x
          m[1, 3] = perimeter_se_point.y
          m[2, 3] = perimeter_se_point.z
          east_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_space.setBuildingStory(story)
          east_space.setName("Story #{floor + 1} East Perimeter Space")

          south_polygon = OpenStudio::Point3dVector.new
          south_polygon << se_point
          south_polygon << sw_point
          south_polygon << perimeter_sw_point
          south_polygon << perimeter_se_point
          south_space = OpenStudio::Model::Space.fromFloorPrint(south_polygon, floor_to_floor_height, model)
          south_space = south_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          south_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_space.setBuildingStory(story)
          south_space.setName("Story #{floor + 1} South Perimeter Space")

          core_polygon = OpenStudio::Point3dVector.new
          core_polygon << perimeter_sw_point
          core_polygon << perimeter_nw_point
          core_polygon << perimeter_ne_point
          core_polygon << perimeter_se_point
          core_space = OpenStudio::Model::Space.fromFloorPrint(core_polygon, floor_to_floor_height, model)
          core_space = core_space.get
          m[0, 3] = perimeter_sw_point.x
          m[1, 3] = perimeter_sw_point.y
          m[2, 3] = perimeter_sw_point.z
          core_space.changeTransformation(OpenStudio::Transformation.new(m))
          core_space.setBuildingStory(story)
          core_space.setName("Story #{floor + 1} Core Space")
        else
          # Minimal zones
          core_polygon = OpenStudio::Point3dVector.new
          core_polygon << sw_point
          core_polygon << nw_point
          core_polygon << ne_point
          core_polygon << se_point
          core_space = OpenStudio::Model::Space.fromFloorPrint(core_polygon, floor_to_floor_height, model)
          core_space = core_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          core_space.changeTransformation(OpenStudio::Transformation.new(m))
          core_space.setBuildingStory(story)
          core_space.setName("Story #{floor + 1} Core Space")
        end
        # Set vertical story position
        story.setNominalZCoordinate(z)

        # Ensure that underground stories (when z<0 have Ground set as Boundary conditions).
        # Apply the Ground BC to all surfaces, the top ceiling will be corrected below when the surface matching algorithm is called.
        underground_surfaces = story.spaces.flat_map(&:surfaces)
        BTAP::Geometry::Surfaces.set_surfaces_boundary_condition(model, underground_surfaces, 'Ground') if z < 0
      end

      BTAP::Geometry.match_surfaces(model)
      return model
    end

    # Create a Rectangle shape in a model based on a given aspect ratio
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param aspect_ratio [Double] Aspect ratio
    # @param floor_area [Double] Building floor area in m2
    # @param rotation [Double] Building rotation in degrees from North
    # @param num_floors [Integer] Number of floors
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_aspect_ratio(model,
                                       aspect_ratio = 0.5,
                                       floor_area = 1000.0,
                                       rotation = 0.0,
                                       num_floors = 3,
                                       floor_to_floor_height = 3.8,
                                       plenum_height = 1.0,
                                       perimeter_zone_depth = 4.57)
      # determine length and width
      length = Math.sqrt((floor_area / (num_floors * 1.0)) / aspect_ratio)
      width = Math.sqrt((floor_area / (num_floors * 1.0)) * aspect_ratio)
      OpenstudioStandards::Geometry.create_shape_rectangle(model,
                                                           length = length,
                                                           width = width,
                                                           above_ground_storys = num_floors,
                                                           under_ground_storys = 0,
                                                           floor_to_floor_height = floor_to_floor_height,
                                                           plenum_height = plenum_height,
                                                           perimeter_zone_depth = perimeter_zone_depth)
      BTAP::Geometry.rotate_model(model, rotation)

      return model
    end

    # Create a Courtyard shape in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param length [Double] Building length in meters
    # @param width [Double] Building width in meters
    # @param courtyard_length [Double] Courtyard depth in meters
    # @param courtyard_width [Double] Courtyard width in meters
    # @param num_floors [Integer] Number of floors
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_courtyard(model,
                                    length = 50.0,
                                    width = 30.0,
                                    courtyard_length = 15.0,
                                    courtyard_width = 5.0,
                                    num_floors = 3,
                                    floor_to_floor_height = 3.8,
                                    plenum_height = 1.0,
                                    perimeter_zone_depth = 4.57)
      if length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Length must be greater than 0.')
        return nil
      end

      if width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Width must be greater than 0.')
        return nil
      end

      if courtyard_length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Courtyard length must be greater than 0.')
        return nil
      end

      if courtyard_width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Courtyard width must be greater than 0.')
        return nil
      end

      if num_floors <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Number of floors must be greater than 0.')
        return nil
      end

      if floor_to_floor_height <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Floor to floor height must be greater than 0.')
        return nil
      end

      if plenum_height < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Plenum height must be greater than 0.')
        return nil
      end

      shortest_side = [length, width].min
      if perimeter_zone_depth < 0 || 4 * perimeter_zone_depth >= (shortest_side - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Perimeter zone depth must be greater than or equal to 0 and less than #{shortest_side / 4.0}m.")
        return nil
      end

      if courtyard_length >= (length - (4 * perimeter_zone_depth) - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Courtyard length must be less than #{length - (4.0 * perimeter_zone_depth)}m.")
        return nil
      end

      if courtyard_width >= (width - (4 * perimeter_zone_depth) - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Courtyard width must be less than #{width - (4.0 * perimeter_zone_depth)}m.")
        return nil
      end

      # Loop through the number of floors
      for floor in (0..num_floors - 1)
        z = floor_to_floor_height * floor

        # Create a new story within the building
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setNominalFloortoFloorHeight(floor_to_floor_height)
        story.setName("Story #{floor + 1}")

        nw_point = OpenStudio::Point3d.new(0.0, width, z)
        ne_point = OpenStudio::Point3d.new(length, width, z)
        se_point = OpenStudio::Point3d.new(length, 0.0, z)
        sw_point = OpenStudio::Point3d.new(0.0, 0.0, z)

        courtyard_nw_point = OpenStudio::Point3d.new((length - courtyard_length) / 2.0, ((width - courtyard_width) / 2.0) + courtyard_width, z)
        courtyard_ne_point = OpenStudio::Point3d.new(((length - courtyard_length) / 2.0) + courtyard_length, ((width - courtyard_width) / 2.0) + courtyard_width, z)
        courtyard_se_point = OpenStudio::Point3d.new(((length - courtyard_length) / 2.0) + courtyard_length, (width - courtyard_width) / 2.0, z)
        courtyard_sw_point = OpenStudio::Point3d.new((length - courtyard_length) / 2.0, (width - courtyard_width) / 2.0, z)

        # Identity matrix for setting space origins
        m = OpenStudio::Matrix.new(4, 4, 0.0)
        m[0, 0] = 1.0
        m[1, 1] = 1.0
        m[2, 2] = 1.0
        m[3, 3] = 1.0

        # Define polygons for a building with a courtyard
        if perimeter_zone_depth > 0
          outer_perimeter_nw_point = nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0.0)
          outer_perimeter_ne_point = ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0.0)
          outer_perimeter_se_point = se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0.0)
          outer_perimeter_sw_point = sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0.0)
          inner_perimeter_nw_point = courtyard_nw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0.0)
          inner_perimeter_ne_point = courtyard_ne_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0.0)
          inner_perimeter_se_point = courtyard_se_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0.0)
          inner_perimeter_sw_point = courtyard_sw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0.0)

          west_outer_perimeter_polygon = OpenStudio::Point3dVector.new
          west_outer_perimeter_polygon << sw_point
          west_outer_perimeter_polygon << nw_point
          west_outer_perimeter_polygon << outer_perimeter_nw_point
          west_outer_perimeter_polygon << outer_perimeter_sw_point
          west_outer_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_outer_perimeter_polygon, floor_to_floor_height, model)
          west_outer_perimeter_space = west_outer_perimeter_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          west_outer_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_outer_perimeter_space.setBuildingStory(story)
          west_outer_perimeter_space.setName("Story #{floor + 1} West Outer Perimeter Space")

          north_outer_perimeter_polygon = OpenStudio::Point3dVector.new
          north_outer_perimeter_polygon << nw_point
          north_outer_perimeter_polygon << ne_point
          north_outer_perimeter_polygon << outer_perimeter_ne_point
          north_outer_perimeter_polygon << outer_perimeter_nw_point
          north_outer_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_outer_perimeter_polygon, floor_to_floor_height, model)
          north_outer_perimeter_space = north_outer_perimeter_space.get
          m[0, 3] = outer_perimeter_nw_point.x
          m[1, 3] = outer_perimeter_nw_point.y
          m[2, 3] = outer_perimeter_nw_point.z
          north_outer_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_outer_perimeter_space.setBuildingStory(story)
          north_outer_perimeter_space.setName("Story #{floor + 1} North Outer Perimeter Space")

          east_outer_perimeter_polygon = OpenStudio::Point3dVector.new
          east_outer_perimeter_polygon << ne_point
          east_outer_perimeter_polygon << se_point
          east_outer_perimeter_polygon << outer_perimeter_se_point
          east_outer_perimeter_polygon << outer_perimeter_ne_point
          east_outer_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_outer_perimeter_polygon, floor_to_floor_height, model)
          east_outer_perimeter_space = east_outer_perimeter_space.get
          m[0, 3] = outer_perimeter_se_point.x
          m[1, 3] = outer_perimeter_se_point.y
          m[2, 3] = outer_perimeter_se_point.z
          east_outer_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_outer_perimeter_space.setBuildingStory(story)
          east_outer_perimeter_space.setName("Story #{floor + 1} East Outer Perimeter Space")

          south_outer_perimeter_polygon = OpenStudio::Point3dVector.new
          south_outer_perimeter_polygon << se_point
          south_outer_perimeter_polygon << sw_point
          south_outer_perimeter_polygon << outer_perimeter_sw_point
          south_outer_perimeter_polygon << outer_perimeter_se_point
          south_outer_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_outer_perimeter_polygon, floor_to_floor_height, model)
          south_outer_perimeter_space = south_outer_perimeter_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          south_outer_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_outer_perimeter_space.setBuildingStory(story)
          south_outer_perimeter_space.setName("Story #{floor + 1} South Outer Perimeter Space")

          west_core_polygon = OpenStudio::Point3dVector.new
          west_core_polygon << outer_perimeter_sw_point
          west_core_polygon << outer_perimeter_nw_point
          west_core_polygon << inner_perimeter_nw_point
          west_core_polygon << inner_perimeter_sw_point
          west_core_space = OpenStudio::Model::Space.fromFloorPrint(west_core_polygon, floor_to_floor_height, model)
          west_core_space = west_core_space.get
          m[0, 3] = outer_perimeter_sw_point.x
          m[1, 3] = outer_perimeter_sw_point.y
          m[2, 3] = outer_perimeter_sw_point.z
          west_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_core_space.setBuildingStory(story)
          west_core_space.setName("Story #{floor + 1} West Core Space")

          north_core_polygon = OpenStudio::Point3dVector.new
          north_core_polygon << outer_perimeter_nw_point
          north_core_polygon << outer_perimeter_ne_point
          north_core_polygon << inner_perimeter_ne_point
          north_core_polygon << inner_perimeter_nw_point
          north_core_space = OpenStudio::Model::Space.fromFloorPrint(north_core_polygon, floor_to_floor_height, model)
          north_core_space = north_core_space.get
          m[0, 3] = inner_perimeter_nw_point.x
          m[1, 3] = inner_perimeter_nw_point.y
          m[2, 3] = inner_perimeter_nw_point.z
          north_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_core_space.setBuildingStory(story)
          north_core_space.setName("Story #{floor + 1} North Core Space")

          east_core_polygon = OpenStudio::Point3dVector.new
          east_core_polygon << outer_perimeter_ne_point
          east_core_polygon << outer_perimeter_se_point
          east_core_polygon << inner_perimeter_se_point
          east_core_polygon << inner_perimeter_ne_point
          east_core_space = OpenStudio::Model::Space.fromFloorPrint(east_core_polygon, floor_to_floor_height, model)
          east_core_space = east_core_space.get
          m[0, 3] = inner_perimeter_se_point.x
          m[1, 3] = inner_perimeter_se_point.y
          m[2, 3] = inner_perimeter_se_point.z
          east_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_core_space.setBuildingStory(story)
          east_core_space.setName("Story #{floor + 1} East Core Space")

          south_core_polygon = OpenStudio::Point3dVector.new
          south_core_polygon << outer_perimeter_se_point
          south_core_polygon << outer_perimeter_sw_point
          south_core_polygon << inner_perimeter_sw_point
          south_core_polygon << inner_perimeter_se_point
          south_core_space = OpenStudio::Model::Space.fromFloorPrint(south_core_polygon, floor_to_floor_height, model)
          south_core_space = south_core_space.get
          m[0, 3] = outer_perimeter_sw_point.x
          m[1, 3] = outer_perimeter_sw_point.y
          m[2, 3] = outer_perimeter_sw_point.z
          south_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_core_space.setBuildingStory(story)
          south_core_space.setName("Story #{floor + 1} South Core Space")

          west_inner_perimeter_polygon = OpenStudio::Point3dVector.new
          west_inner_perimeter_polygon << inner_perimeter_sw_point
          west_inner_perimeter_polygon << inner_perimeter_nw_point
          west_inner_perimeter_polygon << courtyard_nw_point
          west_inner_perimeter_polygon << courtyard_sw_point
          west_inner_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_inner_perimeter_polygon, floor_to_floor_height, model)
          west_inner_perimeter_space = west_inner_perimeter_space.get
          m[0, 3] = inner_perimeter_sw_point.x
          m[1, 3] = inner_perimeter_sw_point.y
          m[2, 3] = inner_perimeter_sw_point.z
          west_inner_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_inner_perimeter_space.setBuildingStory(story)
          west_inner_perimeter_space.setName("Story #{floor + 1} West Inner Perimeter Space")

          north_inner_perimeter_polygon = OpenStudio::Point3dVector.new
          north_inner_perimeter_polygon << inner_perimeter_nw_point
          north_inner_perimeter_polygon << inner_perimeter_ne_point
          north_inner_perimeter_polygon << courtyard_ne_point
          north_inner_perimeter_polygon << courtyard_nw_point
          north_inner_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_inner_perimeter_polygon, floor_to_floor_height, model)
          north_inner_perimeter_space = north_inner_perimeter_space.get
          m[0, 3] = courtyard_nw_point.x
          m[1, 3] = courtyard_nw_point.y
          m[2, 3] = courtyard_nw_point.z
          north_inner_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_inner_perimeter_space.setBuildingStory(story)
          north_inner_perimeter_space.setName("Story #{floor + 1} North Inner Perimeter Space")

          east_inner_perimeter_polygon = OpenStudio::Point3dVector.new
          east_inner_perimeter_polygon << inner_perimeter_ne_point
          east_inner_perimeter_polygon << inner_perimeter_se_point
          east_inner_perimeter_polygon << courtyard_se_point
          east_inner_perimeter_polygon << courtyard_ne_point
          east_inner_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_inner_perimeter_polygon, floor_to_floor_height, model)
          east_inner_perimeter_space = east_inner_perimeter_space.get
          m[0, 3] = courtyard_se_point.x
          m[1, 3] = courtyard_se_point.y
          m[2, 3] = courtyard_se_point.z
          east_inner_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_inner_perimeter_space.setBuildingStory(story)
          east_inner_perimeter_space.setName("Story #{floor + 1} East Inner Perimeter Space")

          south_inner_perimeter_polygon = OpenStudio::Point3dVector.new
          south_inner_perimeter_polygon << inner_perimeter_se_point
          south_inner_perimeter_polygon << inner_perimeter_sw_point
          south_inner_perimeter_polygon << courtyard_sw_point
          south_inner_perimeter_polygon << courtyard_se_point
          south_inner_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_inner_perimeter_polygon, floor_to_floor_height, model)
          south_inner_perimeter_space = south_inner_perimeter_space.get
          m[0, 3] = inner_perimeter_sw_point.x
          m[1, 3] = inner_perimeter_sw_point.y
          m[2, 3] = inner_perimeter_sw_point.z
          south_inner_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_inner_perimeter_space.setBuildingStory(story)
          south_inner_perimeter_space.setName("Story #{floor + 1} South Inner Perimeter Space")
        else
          # Minimal zones
          west_polygon = OpenStudio::Point3dVector.new
          west_polygon << sw_point
          west_polygon << nw_point
          west_polygon << courtyard_nw_point
          west_polygon << courtyard_sw_point
          west_space = OpenStudio::Model::Space.fromFloorPrint(west_polygon, floor_to_floor_height, model)
          west_space = west_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          west_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_space.setBuildingStory(story)
          west_space.setName("Story #{floor + 1} West Space")

          north_polygon = OpenStudio::Point3dVector.new
          north_polygon << nw_point
          north_polygon << ne_point
          north_polygon << courtyard_ne_point
          north_polygon << courtyard_nw_point
          north_space = OpenStudio::Model::Space.fromFloorPrint(north_polygon, floor_to_floor_height, model)
          north_space = north_space.get
          m[0, 3] = courtyard_nw_point.x
          m[1, 3] = courtyard_nw_point.y
          m[2, 3] = courtyard_nw_point.z
          north_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_space.setBuildingStory(story)
          north_space.setName("Story #{floor + 1} North Space")

          east_polygon = OpenStudio::Point3dVector.new
          east_polygon << ne_point
          east_polygon << se_point
          east_polygon << courtyard_se_point
          east_polygon << courtyard_ne_point
          east_space = OpenStudio::Model::Space.fromFloorPrint(east_polygon, floor_to_floor_height, model)
          east_space = east_space.get
          m[0, 3] = courtyard_se_point.x
          m[1, 3] = courtyard_se_point.y
          m[2, 3] = courtyard_se_point.z
          east_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_space.setBuildingStory(story)
          east_space.setName("Story #{floor + 1} East Space")

          south_polygon = OpenStudio::Point3dVector.new
          south_polygon << se_point
          south_polygon << sw_point
          south_polygon << courtyard_sw_point
          south_polygon << courtyard_se_point
          south_space = OpenStudio::Model::Space.fromFloorPrint(south_polygon, floor_to_floor_height, model)
          south_space = south_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          south_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_space.setBuildingStory(story)
          south_space.setName("Story #{floor + 1} South Space")
        end
        # Set vertical story position
        story.setNominalZCoordinate(z)
      end
      BTAP::Geometry.match_surfaces(model)

      return model
    end

    # Create an H shape in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param length [Double] Building length in meters
    # @param left_width [Double] Left width in meters
    # @param center_width [Double] Center width in meters
    # @param right_width [Double] Right width in meters
    # @param left_end_length [Double] Left end length in meters
    # @param right_end_length [Double] Right end length in meters
    # @param left_upper_end_offset [Double] Left upper end offset in meters
    # @param right_upper_end_offset [Double] Right upper end offset in meters
    # @param num_floors [Integer] Number of floors
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_h(model,
                            length = 40.0,
                            left_width = 40.0,
                            center_width = 10.0,
                            right_width = 40.0,
                            left_end_length = 15.0,
                            right_end_length = 15.0,
                            left_upper_end_offset = 15.0,
                            right_upper_end_offset = 15.0,
                            num_floors = 3,
                            floor_to_floor_height = 3.8,
                            plenum_height = 1,
                            perimeter_zone_depth = 4.57)
      if length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Length must be greater than 0.')
        return nil
      end

      if left_width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Left width must be greater than 0.')
        return nil
      end

      if right_width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Right width must be greater than 0.')
        return nil
      end

      if center_width <= 1e-4 || center_width >= ([left_width, right_width].min - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Center width must be greater than 0 and less than #{[left_width, right_width].min}m.")
        return nil
      end

      if left_end_length <= 1e-4 || left_end_length >= (length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Left end length must be greater than 0 and less than #{length}m.")
        return nil
      end

      if right_end_length <= 1e-4 || right_end_length >= (length - left_end_length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Right end length must be greater than 0 and less than #{length - left_end_length}m.")
        return nil
      end

      if left_upper_end_offset <= 1e-4 || left_upper_end_offset >= (left_width - center_width - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Left upper end offset must be greater than 0 and less than #{left_width - center_width}m.")
        return nil
      end

      if right_upper_end_offset <= 1e-4 || right_upper_end_offset >= (right_width - center_width - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Right upper end offset must be greater than 0 and less than #{right_width - center_width}m.")
        return nil
      end

      if num_floors <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Number of floors must be greater than 0.')
        return nil
      end

      if floor_to_floor_height <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Floor to floor height must be greater than 0.')
        return nil
      end

      if plenum_height < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Plenum height must be greater than 0.')
        return nil
      end

      shortest_side = [length / 2, left_width, center_width, right_width, left_end_length, right_end_length].min
      if perimeter_zone_depth < 0 || 2 * perimeter_zone_depth >= (shortest_side - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Perimeter zone depth must be greater than or equal to 0 and less than #{shortest_side / 2}m.")
        return nil
      end

      # Loop through the number of floors
      for floor in (0..num_floors - 1)
        z = floor_to_floor_height * floor

        # Create a new story within the building
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setNominalFloortoFloorHeight(floor_to_floor_height)
        story.setName("Story #{floor + 1}")

        left_origin = (right_width - right_upper_end_offset) > (left_width - left_upper_end_offset) ? (right_width - right_upper_end_offset) - (left_width - left_upper_end_offset) : 0
        left_nw_point = OpenStudio::Point3d.new(0, left_width + left_origin, z)
        left_ne_point = OpenStudio::Point3d.new(left_end_length, left_width + left_origin, z)
        left_se_point = OpenStudio::Point3d.new(left_end_length, left_origin, z)
        left_sw_point = OpenStudio::Point3d.new(0, left_origin, z)
        center_nw_point = OpenStudio::Point3d.new(left_end_length, left_ne_point.y - left_upper_end_offset, z)
        center_ne_point = OpenStudio::Point3d.new(length - right_end_length, center_nw_point.y, z)
        center_se_point = OpenStudio::Point3d.new(length - right_end_length, center_nw_point.y - center_width, z)
        center_sw_point = OpenStudio::Point3d.new(left_end_length, center_se_point.y, z)
        right_nw_point = OpenStudio::Point3d.new(length - right_end_length, center_ne_point.y + right_upper_end_offset, z)
        right_ne_point = OpenStudio::Point3d.new(length, right_nw_point.y, z)
        right_se_point = OpenStudio::Point3d.new(length, right_ne_point.y - right_width, z)
        right_sw_point = OpenStudio::Point3d.new(length - right_end_length, right_se_point.y, z)

        # Identity matrix for setting space origins
        m = OpenStudio::Matrix.new(4, 4, 0)
        m[0, 0] = 1
        m[1, 1] = 1
        m[2, 2] = 1
        m[3, 3] = 1

        # Define polygons for an H-shape building with perimeter core zoning
        if perimeter_zone_depth > 0
          perimeter_left_nw_point = left_nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_left_ne_point = left_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_left_se_point = left_se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_left_sw_point = left_sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_center_nw_point = center_nw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_center_ne_point = center_ne_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_center_se_point = center_se_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_center_sw_point = center_sw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_right_nw_point = right_nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_right_ne_point = right_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_right_se_point = right_se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_right_sw_point = right_sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)

          west_left_perimeter_polygon = OpenStudio::Point3dVector.new
          west_left_perimeter_polygon << left_sw_point
          west_left_perimeter_polygon << left_nw_point
          west_left_perimeter_polygon << perimeter_left_nw_point
          west_left_perimeter_polygon << perimeter_left_sw_point
          west_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_left_perimeter_polygon, floor_to_floor_height, model)
          west_left_perimeter_space = west_left_perimeter_space.get
          m[0, 3] = left_sw_point.x
          m[1, 3] = left_sw_point.y
          m[2, 3] = left_sw_point.z
          west_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_left_perimeter_space.setBuildingStory(story)
          west_left_perimeter_space.setName("Story #{floor + 1} West Left Perimeter Space")

          north_left_perimeter_polygon = OpenStudio::Point3dVector.new
          north_left_perimeter_polygon << left_nw_point
          north_left_perimeter_polygon << left_ne_point
          north_left_perimeter_polygon << perimeter_left_ne_point
          north_left_perimeter_polygon << perimeter_left_nw_point
          north_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_left_perimeter_polygon, floor_to_floor_height, model)
          north_left_perimeter_space = north_left_perimeter_space.get
          m[0, 3] = perimeter_left_nw_point.x
          m[1, 3] = perimeter_left_nw_point.y
          m[2, 3] = perimeter_left_nw_point.z
          north_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_left_perimeter_space.setBuildingStory(story)
          north_left_perimeter_space.setName("Story #{floor + 1} North Left Perimeter Space")

          east_upper_left_perimeter_polygon = OpenStudio::Point3dVector.new
          east_upper_left_perimeter_polygon << left_ne_point
          east_upper_left_perimeter_polygon << center_nw_point
          east_upper_left_perimeter_polygon << perimeter_center_nw_point
          east_upper_left_perimeter_polygon << perimeter_left_ne_point
          east_upper_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_upper_left_perimeter_polygon, floor_to_floor_height, model)
          east_upper_left_perimeter_space = east_upper_left_perimeter_space.get
          m[0, 3] = perimeter_center_nw_point.x
          m[1, 3] = perimeter_center_nw_point.y
          m[2, 3] = perimeter_center_nw_point.z
          east_upper_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_upper_left_perimeter_space.setBuildingStory(story)
          east_upper_left_perimeter_space.setName("Story #{floor + 1} East Upper Left Perimeter Space")

          north_center_perimeter_polygon = OpenStudio::Point3dVector.new
          north_center_perimeter_polygon << center_nw_point
          north_center_perimeter_polygon << center_ne_point
          north_center_perimeter_polygon << perimeter_center_ne_point
          north_center_perimeter_polygon << perimeter_center_nw_point
          north_center_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_center_perimeter_polygon, floor_to_floor_height, model)
          north_center_perimeter_space = north_center_perimeter_space.get
          m[0, 3] = perimeter_center_nw_point.x
          m[1, 3] = perimeter_center_nw_point.y
          m[2, 3] = perimeter_center_nw_point.z
          north_center_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_center_perimeter_space.setBuildingStory(story)
          north_center_perimeter_space.setName("Story #{floor + 1} North Center Perimeter Space")

          west_upper_right_perimeter_polygon = OpenStudio::Point3dVector.new
          west_upper_right_perimeter_polygon << center_ne_point
          west_upper_right_perimeter_polygon << right_nw_point
          west_upper_right_perimeter_polygon << perimeter_right_nw_point
          west_upper_right_perimeter_polygon << perimeter_center_ne_point
          west_upper_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_upper_right_perimeter_polygon, floor_to_floor_height, model)
          west_upper_right_perimeter_space = west_upper_right_perimeter_space.get
          m[0, 3] = center_ne_point.x
          m[1, 3] = center_ne_point.y
          m[2, 3] = center_ne_point.z
          west_upper_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_upper_right_perimeter_space.setBuildingStory(story)
          west_upper_right_perimeter_space.setName("Story #{floor + 1} West Upper Right Perimeter Space")

          north_right_perimeter_polygon = OpenStudio::Point3dVector.new
          north_right_perimeter_polygon << right_nw_point
          north_right_perimeter_polygon << right_ne_point
          north_right_perimeter_polygon << perimeter_right_ne_point
          north_right_perimeter_polygon << perimeter_right_nw_point
          north_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_right_perimeter_polygon, floor_to_floor_height, model)
          north_right_perimeter_space = north_right_perimeter_space.get
          m[0, 3] = perimeter_right_nw_point.x
          m[1, 3] = perimeter_right_nw_point.y
          m[2, 3] = perimeter_right_nw_point.z
          north_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_right_perimeter_space.setBuildingStory(story)
          north_right_perimeter_space.setName("Story #{floor + 1} North Right Perimeter Space")

          east_right_perimeter_polygon = OpenStudio::Point3dVector.new
          east_right_perimeter_polygon << right_ne_point
          east_right_perimeter_polygon << right_se_point
          east_right_perimeter_polygon << perimeter_right_se_point
          east_right_perimeter_polygon << perimeter_right_ne_point
          east_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_right_perimeter_polygon, floor_to_floor_height, model)
          east_right_perimeter_space = east_right_perimeter_space.get
          m[0, 3] = perimeter_right_se_point.x
          m[1, 3] = perimeter_right_se_point.y
          m[2, 3] = perimeter_right_se_point.z
          east_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_right_perimeter_space.setBuildingStory(story)
          east_right_perimeter_space.setName("Story #{floor + 1} East Right Perimeter Space")

          south_right_perimeter_polygon = OpenStudio::Point3dVector.new
          south_right_perimeter_polygon << right_se_point
          south_right_perimeter_polygon << right_sw_point
          south_right_perimeter_polygon << perimeter_right_sw_point
          south_right_perimeter_polygon << perimeter_right_se_point
          south_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_right_perimeter_polygon, floor_to_floor_height, model)
          south_right_perimeter_space = south_right_perimeter_space.get
          m[0, 3] = right_sw_point.x
          m[1, 3] = right_sw_point.y
          m[2, 3] = right_sw_point.z
          south_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_right_perimeter_space.setBuildingStory(story)
          south_right_perimeter_space.setName("Story #{floor + 1} South Right Perimeter Space")

          west_lower_right_perimeter_polygon = OpenStudio::Point3dVector.new
          west_lower_right_perimeter_polygon << right_sw_point
          west_lower_right_perimeter_polygon << center_se_point
          west_lower_right_perimeter_polygon << perimeter_center_se_point
          west_lower_right_perimeter_polygon << perimeter_right_sw_point
          west_lower_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_lower_right_perimeter_polygon, floor_to_floor_height, model)
          west_lower_right_perimeter_space = west_lower_right_perimeter_space.get
          m[0, 3] = right_sw_point.x
          m[1, 3] = right_sw_point.y
          m[2, 3] = right_sw_point.z
          west_lower_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_lower_right_perimeter_space.setBuildingStory(story)
          west_lower_right_perimeter_space.setName("Story #{floor + 1} West Lower Right Perimeter Space")

          south_center_perimeter_polygon = OpenStudio::Point3dVector.new
          south_center_perimeter_polygon << center_se_point
          south_center_perimeter_polygon << center_sw_point
          south_center_perimeter_polygon << perimeter_center_sw_point
          south_center_perimeter_polygon << perimeter_center_se_point
          south_center_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_center_perimeter_polygon, floor_to_floor_height, model)
          south_center_perimeter_space = south_center_perimeter_space.get
          m[0, 3] = center_sw_point.x
          m[1, 3] = center_sw_point.y
          m[2, 3] = center_sw_point.z
          south_center_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_center_perimeter_space.setBuildingStory(story)
          south_center_perimeter_space.setName("Story #{floor + 1} South Center Perimeter Space")

          east_lower_left_perimeter_polygon = OpenStudio::Point3dVector.new
          east_lower_left_perimeter_polygon << center_sw_point
          east_lower_left_perimeter_polygon << left_se_point
          east_lower_left_perimeter_polygon << perimeter_left_se_point
          east_lower_left_perimeter_polygon << perimeter_center_sw_point
          east_lower_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_lower_left_perimeter_polygon, floor_to_floor_height, model)
          east_lower_left_perimeter_space = east_lower_left_perimeter_space.get
          m[0, 3] = perimeter_left_se_point.x
          m[1, 3] = perimeter_left_se_point.y
          m[2, 3] = perimeter_left_se_point.z
          east_lower_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_lower_left_perimeter_space.setBuildingStory(story)
          east_lower_left_perimeter_space.setName("Story #{floor + 1} East Lower Left Perimeter Space")

          south_left_perimeter_polygon = OpenStudio::Point3dVector.new
          south_left_perimeter_polygon << left_se_point
          south_left_perimeter_polygon << left_sw_point
          south_left_perimeter_polygon << perimeter_left_sw_point
          south_left_perimeter_polygon << perimeter_left_se_point
          south_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_left_perimeter_polygon, floor_to_floor_height, model)
          south_left_perimeter_space = south_left_perimeter_space.get
          m[0, 3] = left_sw_point.x
          m[1, 3] = left_sw_point.y
          m[2, 3] = left_sw_point.z
          south_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_left_perimeter_space.setBuildingStory(story)
          south_left_perimeter_space.setName("Story #{floor + 1} South Left Perimeter Space")

          west_core_polygon = OpenStudio::Point3dVector.new
          west_core_polygon << perimeter_left_sw_point
          west_core_polygon << perimeter_left_nw_point
          west_core_polygon << perimeter_left_ne_point
          west_core_polygon << perimeter_center_nw_point
          west_core_polygon << perimeter_center_sw_point
          west_core_polygon << perimeter_left_se_point
          west_core_space = OpenStudio::Model::Space.fromFloorPrint(west_core_polygon, floor_to_floor_height, model)
          west_core_space = west_core_space.get
          m[0, 3] = perimeter_left_sw_point.x
          m[1, 3] = perimeter_left_sw_point.y
          m[2, 3] = perimeter_left_sw_point.z
          west_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_core_space.setBuildingStory(story)
          west_core_space.setName("Story #{floor + 1} West Core Space")

          center_core_polygon = OpenStudio::Point3dVector.new
          center_core_polygon << perimeter_center_sw_point
          center_core_polygon << perimeter_center_nw_point
          center_core_polygon << perimeter_center_ne_point
          center_core_polygon << perimeter_center_se_point
          center_core_space = OpenStudio::Model::Space.fromFloorPrint(center_core_polygon, floor_to_floor_height, model)
          center_core_space = center_core_space.get
          m[0, 3] = perimeter_center_sw_point.x
          m[1, 3] = perimeter_center_sw_point.y
          m[2, 3] = perimeter_center_sw_point.z
          center_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          center_core_space.setBuildingStory(story)
          center_core_space.setName("Story #{floor + 1} Center Core Space")

          east_core_polygon = OpenStudio::Point3dVector.new
          east_core_polygon << perimeter_right_sw_point
          east_core_polygon << perimeter_center_se_point
          east_core_polygon << perimeter_center_ne_point
          east_core_polygon << perimeter_right_nw_point
          east_core_polygon << perimeter_right_ne_point
          east_core_polygon << perimeter_right_se_point
          east_core_space = OpenStudio::Model::Space.fromFloorPrint(east_core_polygon, floor_to_floor_height, model)
          east_core_space = east_core_space.get
          m[0, 3] = perimeter_right_sw_point.x
          m[1, 3] = perimeter_right_sw_point.y
          m[2, 3] = perimeter_right_sw_point.z
          east_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_core_space.setBuildingStory(story)
          east_core_space.setName("Story #{floor + 1} East Core Space")
        else
          # Minimal zones
          west_polygon = OpenStudio::Point3dVector.new
          west_polygon << left_sw_point
          west_polygon << left_nw_point
          west_polygon << left_ne_point
          west_polygon << center_nw_point
          west_polygon << center_sw_point
          west_polygon << left_se_point
          west_space = OpenStudio::Model::Space.fromFloorPrint(west_polygon, floor_to_floor_height, model)
          west_space = west_space.get
          m[0, 3] = left_sw_point.x
          m[1, 3] = left_sw_point.y
          m[2, 3] = left_sw_point.z
          west_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_space.setBuildingStory(story)
          west_space.setName("Story #{floor + 1} West Space")

          center_polygon = OpenStudio::Point3dVector.new
          center_polygon << center_sw_point
          center_polygon << center_nw_point
          center_polygon << center_ne_point
          center_polygon << center_se_point
          center_space = OpenStudio::Model::Space.fromFloorPrint(center_polygon, floor_to_floor_height, model)
          center_space = center_space.get
          m[0, 3] = center_sw_point.x
          m[1, 3] = center_sw_point.y
          m[2, 3] = center_sw_point.z
          center_space.changeTransformation(OpenStudio::Transformation.new(m))
          center_space.setBuildingStory(story)
          center_space.setName("Story #{floor + 1} Center Space")

          east_polygon = OpenStudio::Point3dVector.new
          east_polygon << right_sw_point
          east_polygon << center_se_point
          east_polygon << center_ne_point
          east_polygon << right_nw_point
          east_polygon << right_ne_point
          east_polygon << right_se_point
          east_space = OpenStudio::Model::Space.fromFloorPrint(east_polygon, floor_to_floor_height, model)
          east_space = east_space.get
          m[0, 3] = right_sw_point.x
          m[1, 3] = right_sw_point.y
          m[2, 3] = right_sw_point.z
          east_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_space.setBuildingStory(story)
          east_space.setName("Story #{floor + 1} East Space")
        end
        # Set vertical story position
        story.setNominalZCoordinate(z)

      end
      BTAP::Geometry.match_surfaces(model)

      return model
    end

    # Create an L shape in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param length [Double] Building length in meters
    # @param width [Double] Building width in meters
    # @param lower_end_width [Double] Lower end width in meters
    # @param upper_end_length [Double] Upper end width in meters
    # @param num_floors [Integer] Number of floors
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_l(model,
                            length = 40.0,
                            width = 40.0,
                            lower_end_width = 20.0,
                            upper_end_length = 20.0,
                            num_floors = 3,
                            floor_to_floor_height = 3.8,
                            plenum_height = 1.0,
                            perimeter_zone_depth = 4.57)
      if length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Length must be greater than 0.')
        return nil
      end

      if width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Width must be greater than 0.')
        return nil
      end

      if lower_end_width <= 1e-4 || lower_end_width >= (width - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Lower end width must be greater than 0 and less than #{width}m.")
        return nil
      end

      if upper_end_length <= 1e-4 || upper_end_length >= (length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Upper end length must be greater than 0 and less than #{length}m.")
        return nil
      end

      if num_floors <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Number of floors must be greater than 0.')
        return nil
      end

      if floor_to_floor_height <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Floor to floor height must be greater than 0.')
        return nil
      end

      if plenum_height < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Plenum height must be greater than 0.')
        return nil
      end

      shortest_side = [lower_end_width, upper_end_length].min
      if perimeter_zone_depth < 0 || 2 * perimeter_zone_depth >= (shortest_side - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Perimeter zone depth must be greater than or equal to 0 and less than #{shortest_side / 2}m.")
        return nil
      end

      # Loop through the number of floors
      for floor in (0..num_floors - 1)
        z = floor_to_floor_height * floor

        # Create a new story within the building
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setNominalFloortoFloorHeight(floor_to_floor_height)
        story.setName("Story #{floor + 1}")

        nw_point = OpenStudio::Point3d.new(0, width, z)
        upper_ne_point = OpenStudio::Point3d.new(upper_end_length, width, z)
        upper_sw_point = OpenStudio::Point3d.new(upper_end_length, lower_end_width, z)
        lower_ne_point = OpenStudio::Point3d.new(length, lower_end_width, z)
        se_point = OpenStudio::Point3d.new(length, 0, z)
        sw_point = OpenStudio::Point3d.new(0, 0, z)

        # Identity matrix for setting space origins
        m = OpenStudio::Matrix.new(4, 4, 0)
        m[0, 0] = 1
        m[1, 1] = 1
        m[2, 2] = 1
        m[3, 3] = 1

        # Define polygons for a L-shape building with perimeter core zoning
        if perimeter_zone_depth > 0
          perimeter_nw_point = nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_upper_ne_point = upper_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_upper_sw_point = upper_sw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_lower_ne_point = lower_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_se_point = se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_lower_sw_point = sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)

          west_perimeter_polygon = OpenStudio::Point3dVector.new
          west_perimeter_polygon << sw_point
          west_perimeter_polygon << nw_point
          west_perimeter_polygon << perimeter_nw_point
          west_perimeter_polygon << perimeter_lower_sw_point
          west_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_perimeter_polygon, floor_to_floor_height, model)
          west_perimeter_space = west_perimeter_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          west_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_perimeter_space.setBuildingStory(story)
          west_perimeter_space.setName("Story #{floor + 1} West Perimeter Space")

          north_upper_perimeter_polygon = OpenStudio::Point3dVector.new
          north_upper_perimeter_polygon << nw_point
          north_upper_perimeter_polygon << upper_ne_point
          north_upper_perimeter_polygon << perimeter_upper_ne_point
          north_upper_perimeter_polygon << perimeter_nw_point
          north_upper_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_upper_perimeter_polygon, floor_to_floor_height, model)
          north_upper_perimeter_space = north_upper_perimeter_space.get
          m[0, 3] = perimeter_nw_point.x
          m[1, 3] = perimeter_nw_point.y
          m[2, 3] = perimeter_nw_point.z
          north_upper_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_upper_perimeter_space.setBuildingStory(story)
          north_upper_perimeter_space.setName("Story #{floor + 1} North Upper Perimeter Space")

          east_upper_perimeter_polygon = OpenStudio::Point3dVector.new
          east_upper_perimeter_polygon << upper_ne_point
          east_upper_perimeter_polygon << upper_sw_point
          east_upper_perimeter_polygon << perimeter_upper_sw_point
          east_upper_perimeter_polygon << perimeter_upper_ne_point
          east_upper_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_upper_perimeter_polygon, floor_to_floor_height, model)
          east_upper_perimeter_space = east_upper_perimeter_space.get
          m[0, 3] = perimeter_upper_sw_point.x
          m[1, 3] = perimeter_upper_sw_point.y
          m[2, 3] = perimeter_upper_sw_point.z
          east_upper_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_upper_perimeter_space.setBuildingStory(story)
          east_upper_perimeter_space.setName("Story #{floor + 1} East Upper Perimeter Space")

          north_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          north_lower_perimeter_polygon << upper_sw_point
          north_lower_perimeter_polygon << lower_ne_point
          north_lower_perimeter_polygon << perimeter_lower_ne_point
          north_lower_perimeter_polygon << perimeter_upper_sw_point
          north_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_lower_perimeter_polygon, floor_to_floor_height, model)
          north_lower_perimeter_space = north_lower_perimeter_space.get
          m[0, 3] = perimeter_upper_sw_point.x
          m[1, 3] = perimeter_upper_sw_point.y
          m[2, 3] = perimeter_upper_sw_point.z
          north_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_lower_perimeter_space.setBuildingStory(story)
          north_lower_perimeter_space.setName("Story #{floor + 1} North Lower Perimeter Space")

          east_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          east_lower_perimeter_polygon << lower_ne_point
          east_lower_perimeter_polygon << se_point
          east_lower_perimeter_polygon << perimeter_se_point
          east_lower_perimeter_polygon << perimeter_lower_ne_point
          east_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_lower_perimeter_polygon, floor_to_floor_height, model)
          east_lower_perimeter_space = east_lower_perimeter_space.get
          m[0, 3] = perimeter_se_point.x
          m[1, 3] = perimeter_se_point.y
          m[2, 3] = perimeter_se_point.z
          east_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_lower_perimeter_space.setBuildingStory(story)
          east_lower_perimeter_space.setName("Story #{floor + 1} East Lower Perimeter Space")

          south_perimeter_polygon = OpenStudio::Point3dVector.new
          south_perimeter_polygon << se_point
          south_perimeter_polygon << sw_point
          south_perimeter_polygon << perimeter_lower_sw_point
          south_perimeter_polygon << perimeter_se_point
          south_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_perimeter_polygon, floor_to_floor_height, model)
          south_perimeter_space = south_perimeter_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          south_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_perimeter_space.setBuildingStory(story)
          south_perimeter_space.setName("Story #{floor + 1} South Perimeter Space")

          west_core_polygon = OpenStudio::Point3dVector.new
          west_core_polygon << perimeter_lower_sw_point
          west_core_polygon << perimeter_nw_point
          west_core_polygon << perimeter_upper_ne_point
          west_core_polygon << perimeter_upper_sw_point
          west_core_space = OpenStudio::Model::Space.fromFloorPrint(west_core_polygon, floor_to_floor_height, model)
          west_core_space = west_core_space.get
          m[0, 3] = perimeter_lower_sw_point.x
          m[1, 3] = perimeter_lower_sw_point.y
          m[2, 3] = perimeter_lower_sw_point.z
          west_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_core_space.setBuildingStory(story)
          west_core_space.setName("Story #{floor + 1} West Core Space")

          east_core_polygon = OpenStudio::Point3dVector.new
          east_core_polygon << perimeter_upper_sw_point
          east_core_polygon << perimeter_lower_ne_point
          east_core_polygon << perimeter_se_point
          east_core_polygon << perimeter_lower_sw_point
          east_core_space = OpenStudio::Model::Space.fromFloorPrint(east_core_polygon, floor_to_floor_height, model)
          east_core_space = east_core_space.get
          m[0, 3] = perimeter_lower_sw_point.x
          m[1, 3] = perimeter_lower_sw_point.y
          m[2, 3] = perimeter_lower_sw_point.z
          east_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_core_space.setBuildingStory(story)
          east_core_space.setName("Story #{floor + 1} East Core Space")
        else
          # Minimal zones
          west_polygon = OpenStudio::Point3dVector.new
          west_polygon << sw_point
          west_polygon << nw_point
          west_polygon << upper_ne_point
          west_polygon << upper_sw_point
          west_space = OpenStudio::Model::Space.fromFloorPrint(west_polygon, floor_to_floor_height, model)
          west_space = west_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          west_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_space.setBuildingStory(story)
          west_space.setName("Story #{floor + 1} West Space")

          east_polygon = OpenStudio::Point3dVector.new
          east_polygon << sw_point
          east_polygon << upper_sw_point
          east_polygon << lower_ne_point
          east_polygon << se_point
          east_space = OpenStudio::Model::Space.fromFloorPrint(east_polygon, floor_to_floor_height, model)
          east_space = east_space.get
          m[0, 3] = sw_point.x
          m[1, 3] = sw_point.y
          m[2, 3] = sw_point.z
          east_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_space.setBuildingStory(story)
          east_space.setName("Story #{floor + 1} East Space")
        end
        # Set vertical story position
        story.setNominalZCoordinate(z)
      end
      BTAP::Geometry.match_surfaces(model)

      return model
    end

    # Create a T shape in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param length [Double] Building length in meters
    # @param width [Double] Building width in meters
    # @param upper_end_width [Double] Upper end width in meters
    # @param lower_end_length [Double] Lower end length in meters
    # @param left_end_offset [Double] Left end offset in meters
    # @param num_floors [Integer] Number of floors
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_t(model,
                            length = 40.0,
                            width = 40.0,
                            upper_end_width = 20.0,
                            lower_end_length = 20.0,
                            left_end_offset = 10.0,
                            num_floors = 3,
                            floor_to_floor_height = 3.8,
                            plenum_height = 1.0,
                            perimeter_zone_depth = 4.57)
      if length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Length must be greater than 0.')
        return nil
      end

      if width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Width must be greater than 0.')
        return nil
      end

      if upper_end_width <= 1e-4 || upper_end_width >= (width - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Upper end width must be greater than 0 and less than #{width}m.")
        return nil
      end

      if lower_end_length <= 1e-4 || lower_end_length >= (length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Lower end length must be greater than 0 and less than #{length}m.")
        return nil
      end

      if left_end_offset <= 1e-4 || left_end_offset >= (length - lower_end_length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Left end offset must be greater than 0 and less than #{length - lower_end_length}m.")
        return nil
      end

      if num_floors <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Number of floors must be greater than 0.')
        return nil
      end

      if floor_to_floor_height <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Floor to floor height must be greater than 0.')
        return nil
      end

      if plenum_height < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Plenum height must be greater than 0.')
        return nil
      end

      shortest_side = [length, width, upper_end_width, lower_end_length].min
      if perimeter_zone_depth < 0 || 2 * perimeter_zone_depth >= (shortest_side - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Perimeter zone depth must be greater than or equal to 0 and less than #{shortest_side / 2}m.")
        return nil
      end

      # Loop through the number of floors
      for floor in (0..num_floors - 1)
        z = floor_to_floor_height * floor

        # Create a new story within the building
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setNominalFloortoFloorHeight(floor_to_floor_height)
        story.setName("Story #{floor + 1}")

        lower_ne_point = OpenStudio::Point3d.new(left_end_offset, width - upper_end_width, z)
        upper_sw_point = OpenStudio::Point3d.new(0, width - upper_end_width, z)
        upper_nw_point = OpenStudio::Point3d.new(0, width, z)
        upper_ne_point = OpenStudio::Point3d.new(length, width, z)
        upper_se_point = OpenStudio::Point3d.new(length, width - upper_end_width, z)
        lower_nw_point = OpenStudio::Point3d.new(left_end_offset + lower_end_length, width - upper_end_width, z)
        lower_se_point = OpenStudio::Point3d.new(left_end_offset + lower_end_length, 0, z)
        lower_sw_point = OpenStudio::Point3d.new(left_end_offset, 0, z)

        # Identity matrix for setting space origins
        m = OpenStudio::Matrix.new(4, 4, 0)
        m[0, 0] = 1
        m[1, 1] = 1
        m[2, 2] = 1
        m[3, 3] = 1

        # Define polygons for a T-shape building with perimeter core zoning
        if perimeter_zone_depth > 0
          perimeter_lower_ne_point = lower_ne_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_upper_sw_point = upper_sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_upper_nw_point = upper_nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_upper_ne_point = upper_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_upper_se_point = upper_se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_lower_nw_point = lower_nw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_lower_se_point = lower_se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_lower_sw_point = lower_sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)

          west_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          west_lower_perimeter_polygon << lower_sw_point
          west_lower_perimeter_polygon << lower_ne_point
          west_lower_perimeter_polygon << perimeter_lower_ne_point
          west_lower_perimeter_polygon << perimeter_lower_sw_point
          west_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_lower_perimeter_polygon, floor_to_floor_height, model)
          west_lower_perimeter_space = west_lower_perimeter_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          west_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_lower_perimeter_space.setBuildingStory(story)
          west_lower_perimeter_space.setName("Story #{floor + 1} West Lower Perimeter Space")

          south_upper_left_perimeter_polygon = OpenStudio::Point3dVector.new
          south_upper_left_perimeter_polygon << lower_ne_point
          south_upper_left_perimeter_polygon << upper_sw_point
          south_upper_left_perimeter_polygon << perimeter_upper_sw_point
          south_upper_left_perimeter_polygon << perimeter_lower_ne_point
          south_upper_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_upper_left_perimeter_polygon, floor_to_floor_height, model)
          south_upper_left_perimeter_space = south_upper_left_perimeter_space.get
          m[0, 3] = upper_sw_point.x
          m[1, 3] = upper_sw_point.y
          m[2, 3] = upper_sw_point.z
          south_upper_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_upper_left_perimeter_space.setBuildingStory(story)
          south_upper_left_perimeter_space.setName("Story #{floor + 1} South Upper Left Perimeter Space")

          west_upper_perimeter_polygon = OpenStudio::Point3dVector.new
          west_upper_perimeter_polygon << upper_sw_point
          west_upper_perimeter_polygon << upper_nw_point
          west_upper_perimeter_polygon << perimeter_upper_nw_point
          west_upper_perimeter_polygon << perimeter_upper_sw_point
          west_upper_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_upper_perimeter_polygon, floor_to_floor_height, model)
          west_upper_perimeter_space = west_upper_perimeter_space.get
          m[0, 3] = upper_sw_point.x
          m[1, 3] = upper_sw_point.y
          m[2, 3] = upper_sw_point.z
          west_upper_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_upper_perimeter_space.setBuildingStory(story)
          west_upper_perimeter_space.setName("Story #{floor + 1} West Upper Perimeter Space")

          north_perimeter_polygon = OpenStudio::Point3dVector.new
          north_perimeter_polygon << upper_nw_point
          north_perimeter_polygon << upper_ne_point
          north_perimeter_polygon << perimeter_upper_ne_point
          north_perimeter_polygon << perimeter_upper_nw_point
          north_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_perimeter_polygon, floor_to_floor_height, model)
          north_perimeter_space = north_perimeter_space.get
          m[0, 3] = perimeter_upper_nw_point.x
          m[1, 3] = perimeter_upper_nw_point.y
          m[2, 3] = perimeter_upper_nw_point.z
          north_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_perimeter_space.setBuildingStory(story)
          north_perimeter_space.setName("Story #{floor + 1} North Perimeter Space")

          east_upper_perimeter_polygon = OpenStudio::Point3dVector.new
          east_upper_perimeter_polygon << upper_ne_point
          east_upper_perimeter_polygon << upper_se_point
          east_upper_perimeter_polygon << perimeter_upper_se_point
          east_upper_perimeter_polygon << perimeter_upper_ne_point
          east_upper_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_upper_perimeter_polygon, floor_to_floor_height, model)
          east_upper_perimeter_space = east_upper_perimeter_space.get
          m[0, 3] = perimeter_upper_se_point.x
          m[1, 3] = perimeter_upper_se_point.y
          m[2, 3] = perimeter_upper_se_point.z
          east_upper_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_upper_perimeter_space.setBuildingStory(story)
          east_upper_perimeter_space.setName("Story #{floor + 1} East Upper Perimeter Space")

          south_upper_right_perimeter_polygon = OpenStudio::Point3dVector.new
          south_upper_right_perimeter_polygon << upper_se_point
          south_upper_right_perimeter_polygon << lower_nw_point
          south_upper_right_perimeter_polygon << perimeter_lower_nw_point
          south_upper_right_perimeter_polygon << perimeter_upper_se_point
          south_upper_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_upper_right_perimeter_polygon, floor_to_floor_height, model)
          south_upper_right_perimeter_space = south_upper_right_perimeter_space.get
          m[0, 3] = lower_nw_point.x
          m[1, 3] = lower_nw_point.y
          m[2, 3] = lower_nw_point.z
          south_upper_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_upper_right_perimeter_space.setBuildingStory(story)
          south_upper_right_perimeter_space.setName("Story #{floor + 1} South Upper Left Perimeter Space")

          east_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          east_lower_perimeter_polygon << lower_nw_point
          east_lower_perimeter_polygon << lower_se_point
          east_lower_perimeter_polygon << perimeter_lower_se_point
          east_lower_perimeter_polygon << perimeter_lower_nw_point
          east_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_lower_perimeter_polygon, floor_to_floor_height, model)
          east_lower_perimeter_space = east_lower_perimeter_space.get
          m[0, 3] = perimeter_lower_se_point.x
          m[1, 3] = perimeter_lower_se_point.y
          m[2, 3] = perimeter_lower_se_point.z
          east_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_lower_perimeter_space.setBuildingStory(story)
          east_lower_perimeter_space.setName("Story #{floor + 1} East Lower Perimeter Space")

          south_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          south_lower_perimeter_polygon << lower_se_point
          south_lower_perimeter_polygon << lower_sw_point
          south_lower_perimeter_polygon << perimeter_lower_sw_point
          south_lower_perimeter_polygon << perimeter_lower_se_point
          south_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_lower_perimeter_polygon, floor_to_floor_height, model)
          south_lower_perimeter_space = south_lower_perimeter_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          south_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_lower_perimeter_space.setBuildingStory(story)
          south_lower_perimeter_space.setName("Story #{floor + 1} South Lower Perimeter Space")

          north_core_polygon = OpenStudio::Point3dVector.new
          north_core_polygon << perimeter_upper_sw_point
          north_core_polygon << perimeter_upper_nw_point
          north_core_polygon << perimeter_upper_ne_point
          north_core_polygon << perimeter_upper_se_point
          north_core_polygon << perimeter_lower_nw_point
          north_core_polygon << perimeter_lower_ne_point
          north_core_space = OpenStudio::Model::Space.fromFloorPrint(north_core_polygon, floor_to_floor_height, model)
          north_core_space = north_core_space.get
          m[0, 3] = perimeter_upper_sw_point.x
          m[1, 3] = perimeter_upper_sw_point.y
          m[2, 3] = perimeter_upper_sw_point.z
          north_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_core_space.setBuildingStory(story)
          north_core_space.setName("Story #{floor + 1} North Core Space")

          south_core_polygon = OpenStudio::Point3dVector.new
          south_core_polygon << perimeter_lower_sw_point
          south_core_polygon << perimeter_lower_ne_point
          south_core_polygon << perimeter_lower_nw_point
          south_core_polygon << perimeter_lower_se_point
          south_core_space = OpenStudio::Model::Space.fromFloorPrint(south_core_polygon, floor_to_floor_height, model)
          south_core_space = south_core_space.get
          m[0, 3] = perimeter_lower_sw_point.x
          m[1, 3] = perimeter_lower_sw_point.y
          m[2, 3] = perimeter_lower_sw_point.z
          south_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_core_space.setBuildingStory(story)
          south_core_space.setName("Story #{floor + 1} South Core Space")
        else
          # Minimal zones
          north_polygon = OpenStudio::Point3dVector.new
          north_polygon << upper_sw_point
          north_polygon << upper_nw_point
          north_polygon << upper_ne_point
          north_polygon << upper_se_point
          north_polygon << lower_nw_point
          north_polygon << lower_ne_point
          north_space = OpenStudio::Model::Space.fromFloorPrint(north_polygon, floor_to_floor_height, model)
          north_space = north_space.get
          m[0, 3] = upper_sw_point.x
          m[1, 3] = upper_sw_point.y
          m[2, 3] = upper_sw_point.z
          north_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_space.setBuildingStory(story)
          north_space.setName("Story #{floor + 1} North Space")

          south_polygon = OpenStudio::Point3dVector.new
          south_polygon << lower_sw_point
          south_polygon << lower_ne_point
          south_polygon << lower_nw_point
          south_polygon << lower_se_point
          south_space = OpenStudio::Model::Space.fromFloorPrint(south_polygon, floor_to_floor_height, model)
          south_space = south_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          south_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_space.setBuildingStory(story)
          south_space.setName("Story #{floor + 1} South Space")
        end
        # Set vertical story position
        story.setNominalZCoordinate(z)
      end
      BTAP::Geometry.match_surfaces(model)

      return model
    end

    # Create a U shape in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param length [Double] Building length in meters
    # @param left_width [Double] Left width in meters
    # @param right_width [Double] Right width in meters
    # @param left_end_length [Double] Left end length in meters
    # @param right_end_length [Double] Right end length in meters
    # @param left_end_offset [Double] Left end offset in meters
    # @param num_floors [Integer] Number of floors
    # @param floor_to_floor_height [Double] Floor to floor height in meters
    # @param plenum_height [Double] Plenum height in meters
    # @param perimeter_zone_depth [Double] Perimeter zone depth in meters
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.create_shape_u(model,
                            length = 40.0,
                            left_width = 40.0,
                            right_width = 40.0,
                            left_end_length = 15.0,
                            right_end_length = 15.0,
                            left_end_offset = 25.0,
                            num_floors = 3.0,
                            floor_to_floor_height = 3.8,
                            plenum_height = 1.0,
                            perimeter_zone_depth = 4.57)
      if length <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Length must be greater than 0.')
        return nil
      end

      if left_width <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Left width must be greater than 0.')
        return nil
      end

      if left_end_length <= 1e-4 || left_end_length >= (length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Left end length must be greater than 0 and less than #{length}m.")
        return nil
      end

      if right_end_length <= 1e-4 || right_end_length >= (length - left_end_length - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Right end length must be greater than 0 and less than #{length - left_end_length}m.")
        return nil
      end

      if left_end_offset <= 1e-4 || left_end_offset >= (left_width - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Left end offset must be greater than 0 and less than #{left_width}m.")
        return nil
      end

      if right_width <= (left_width - left_end_offset - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Right width must be greater than #{left_width - left_end_offset}m.")
        return nil
      end

      if num_floors <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Number of floors must be greater than 0.')
        return nil
      end

      if floor_to_floor_height <= 1e-4
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Floor to floor height must be greater than 0.')
        return nil
      end

      if plenum_height < 0
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', 'Plenum height must be greater than 0.')
        return nil
      end

      shortest_side = [length / 2, left_width, right_width, left_end_length, right_end_length, left_width - left_end_offset].min
      if perimeter_zone_depth < 0 || 2 * perimeter_zone_depth >= (shortest_side - 1e-4)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create.Shape', "Perimeter zone depth must be greater than or equal to 0 and less than #{shortest_side / 2}m.")
        return nil
      end

      # Loop through the number of floors
      for floor in (0..num_floors - 1)
        z = floor_to_floor_height * floor

        # Create a new story within the building
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setNominalFloortoFloorHeight(floor_to_floor_height)
        story.setName("Story #{floor + 1}")

        left_nw_point = OpenStudio::Point3d.new(0, left_width, z)
        left_ne_point = OpenStudio::Point3d.new(left_end_length, left_width, z)
        upper_sw_point = OpenStudio::Point3d.new(left_end_length, left_width - left_end_offset, z)
        upper_se_point = OpenStudio::Point3d.new(length - right_end_length, left_width - left_end_offset, z)
        right_nw_point = OpenStudio::Point3d.new(length - right_end_length, right_width, z)
        right_ne_point = OpenStudio::Point3d.new(length, right_width, z)
        lower_se_point = OpenStudio::Point3d.new(length, 0, z)
        lower_sw_point = OpenStudio::Point3d.new(0, 0, z)

        # Identity matrix for setting space origins
        m = OpenStudio::Matrix.new(4, 4, 0)
        m[0, 0] = 1
        m[1, 1] = 1
        m[2, 2] = 1
        m[3, 3] = 1

        # Define polygons for a U-shape building with perimeter core zoning
        if perimeter_zone_depth > 0
          perimeter_left_nw_point = left_nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_left_ne_point = left_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_upper_sw_point = upper_sw_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_upper_se_point = upper_se_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_right_nw_point = right_nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_right_ne_point = right_ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, -perimeter_zone_depth, 0)
          perimeter_lower_se_point = lower_se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth, perimeter_zone_depth, 0)
          perimeter_lower_sw_point = lower_sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth, perimeter_zone_depth, 0)

          west_left_perimeter_polygon = OpenStudio::Point3dVector.new
          west_left_perimeter_polygon << lower_sw_point
          west_left_perimeter_polygon << left_nw_point
          west_left_perimeter_polygon << perimeter_left_nw_point
          west_left_perimeter_polygon << perimeter_lower_sw_point
          west_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_left_perimeter_polygon, floor_to_floor_height, model)
          west_left_perimeter_space = west_left_perimeter_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          west_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_left_perimeter_space.setBuildingStory(story)
          west_left_perimeter_space.setName("Story #{floor + 1} West Left Perimeter Space")

          north_left_perimeter_polygon = OpenStudio::Point3dVector.new
          north_left_perimeter_polygon << left_nw_point
          north_left_perimeter_polygon << left_ne_point
          north_left_perimeter_polygon << perimeter_left_ne_point
          north_left_perimeter_polygon << perimeter_left_nw_point
          north_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_left_perimeter_polygon, floor_to_floor_height, model)
          north_left_perimeter_space = north_left_perimeter_space.get
          m[0, 3] = perimeter_left_nw_point.x
          m[1, 3] = perimeter_left_nw_point.y
          m[2, 3] = perimeter_left_nw_point.z
          north_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_left_perimeter_space.setBuildingStory(story)
          north_left_perimeter_space.setName("Story #{floor + 1} North Left Perimeter Space")

          east_left_perimeter_polygon = OpenStudio::Point3dVector.new
          east_left_perimeter_polygon << left_ne_point
          east_left_perimeter_polygon << upper_sw_point
          east_left_perimeter_polygon << perimeter_upper_sw_point
          east_left_perimeter_polygon << perimeter_left_ne_point
          east_left_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_left_perimeter_polygon, floor_to_floor_height, model)
          east_left_perimeter_space = east_left_perimeter_space.get
          m[0, 3] = perimeter_upper_sw_point.x
          m[1, 3] = perimeter_upper_sw_point.y
          m[2, 3] = perimeter_upper_sw_point.z
          east_left_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_left_perimeter_space.setBuildingStory(story)
          east_left_perimeter_space.setName("Story #{floor + 1} East Left Perimeter Space")

          north_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          north_lower_perimeter_polygon << upper_sw_point
          north_lower_perimeter_polygon << upper_se_point
          north_lower_perimeter_polygon << perimeter_upper_se_point
          north_lower_perimeter_polygon << perimeter_upper_sw_point
          north_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_lower_perimeter_polygon, floor_to_floor_height, model)
          north_lower_perimeter_space = north_lower_perimeter_space.get
          m[0, 3] = perimeter_upper_sw_point.x
          m[1, 3] = perimeter_upper_sw_point.y
          m[2, 3] = perimeter_upper_sw_point.z
          north_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_lower_perimeter_space.setBuildingStory(story)
          north_lower_perimeter_space.setName("Story #{floor + 1} North Lower Perimeter Space")

          west_right_perimeter_polygon = OpenStudio::Point3dVector.new
          west_right_perimeter_polygon << upper_se_point
          west_right_perimeter_polygon << right_nw_point
          west_right_perimeter_polygon << perimeter_right_nw_point
          west_right_perimeter_polygon << perimeter_upper_se_point
          west_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(west_right_perimeter_polygon, floor_to_floor_height, model)
          west_right_perimeter_space = west_right_perimeter_space.get
          m[0, 3] = upper_se_point.x
          m[1, 3] = upper_se_point.y
          m[2, 3] = upper_se_point.z
          west_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_right_perimeter_space.setBuildingStory(story)
          west_right_perimeter_space.setName("Story #{floor + 1} West Right Perimeter Space")

          north_right_perimeter_polygon = OpenStudio::Point3dVector.new
          north_right_perimeter_polygon << right_nw_point
          north_right_perimeter_polygon << right_ne_point
          north_right_perimeter_polygon << perimeter_right_ne_point
          north_right_perimeter_polygon << perimeter_right_nw_point
          north_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(north_right_perimeter_polygon, floor_to_floor_height, model)
          north_right_perimeter_space = north_right_perimeter_space.get
          m[0, 3] = perimeter_right_nw_point.x
          m[1, 3] = perimeter_right_nw_point.y
          m[2, 3] = perimeter_right_nw_point.z
          north_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          north_right_perimeter_space.setBuildingStory(story)
          north_right_perimeter_space.setName("Story #{floor + 1} North Right Perimeter Space")

          east_right_perimeter_polygon = OpenStudio::Point3dVector.new
          east_right_perimeter_polygon << right_ne_point
          east_right_perimeter_polygon << lower_se_point
          east_right_perimeter_polygon << perimeter_lower_se_point
          east_right_perimeter_polygon << perimeter_right_ne_point
          east_right_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(east_right_perimeter_polygon, floor_to_floor_height, model)
          east_right_perimeter_space = east_right_perimeter_space.get
          m[0, 3] = perimeter_lower_se_point.x
          m[1, 3] = perimeter_lower_se_point.y
          m[2, 3] = perimeter_lower_se_point.z
          east_right_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_right_perimeter_space.setBuildingStory(story)
          east_right_perimeter_space.setName("Story #{floor + 1} East Right Perimeter Space")

          south_lower_perimeter_polygon = OpenStudio::Point3dVector.new
          south_lower_perimeter_polygon << lower_se_point
          south_lower_perimeter_polygon << lower_sw_point
          south_lower_perimeter_polygon << perimeter_lower_sw_point
          south_lower_perimeter_polygon << perimeter_lower_se_point
          south_lower_perimeter_space = OpenStudio::Model::Space.fromFloorPrint(south_lower_perimeter_polygon, floor_to_floor_height, model)
          south_lower_perimeter_space = south_lower_perimeter_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          south_lower_perimeter_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_lower_perimeter_space.setBuildingStory(story)
          south_lower_perimeter_space.setName("Story #{floor + 1} South Lower Perimeter Space")

          west_core_polygon = OpenStudio::Point3dVector.new
          west_core_polygon << perimeter_lower_sw_point
          west_core_polygon << perimeter_left_nw_point
          west_core_polygon << perimeter_left_ne_point
          west_core_polygon << perimeter_upper_sw_point
          west_core_space = OpenStudio::Model::Space.fromFloorPrint(west_core_polygon, floor_to_floor_height, model)
          west_core_space = west_core_space.get
          m[0, 3] = perimeter_lower_sw_point.x
          m[1, 3] = perimeter_lower_sw_point.y
          m[2, 3] = perimeter_lower_sw_point.z
          west_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_core_space.setBuildingStory(story)
          west_core_space.setName("Story #{floor + 1} West Core Space")

          south_core_polygon = OpenStudio::Point3dVector.new
          south_core_polygon << perimeter_upper_sw_point
          south_core_polygon << perimeter_upper_se_point
          south_core_polygon << perimeter_lower_se_point
          south_core_polygon << perimeter_lower_sw_point
          south_core_space = OpenStudio::Model::Space.fromFloorPrint(south_core_polygon, floor_to_floor_height, model)
          south_core_space = south_core_space.get
          m[0, 3] = perimeter_lower_sw_point.x
          m[1, 3] = perimeter_lower_sw_point.y
          m[2, 3] = perimeter_lower_sw_point.z
          south_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_core_space.setBuildingStory(story)
          south_core_space.setName("Story #{floor + 1} South Core Space")

          east_core_polygon = OpenStudio::Point3dVector.new
          east_core_polygon << perimeter_upper_se_point
          east_core_polygon << perimeter_right_nw_point
          east_core_polygon << perimeter_right_ne_point
          east_core_polygon << perimeter_lower_se_point
          east_core_space = OpenStudio::Model::Space.fromFloorPrint(east_core_polygon, floor_to_floor_height, model)
          east_core_space = east_core_space.get
          m[0, 3] = perimeter_upper_se_point.x
          m[1, 3] = perimeter_upper_se_point.y
          m[2, 3] = perimeter_upper_se_point.z
          east_core_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_core_space.setBuildingStory(story)
          east_core_space.setName("Story #{floor + 1} East Core Space")
        else
          # Minimal zones
          west_polygon = OpenStudio::Point3dVector.new
          west_polygon << lower_sw_point
          west_polygon << left_nw_point
          west_polygon << left_ne_point
          west_polygon << upper_sw_point
          west_space = OpenStudio::Model::Space.fromFloorPrint(west_polygon, floor_to_floor_height, model)
          west_space = west_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          west_space.changeTransformation(OpenStudio::Transformation.new(m))
          west_space.setBuildingStory(story)
          west_space.setName("Story #{floor + 1} West Space")

          south_polygon = OpenStudio::Point3dVector.new
          south_polygon << lower_sw_point
          south_polygon << upper_sw_point
          south_polygon << upper_se_point
          south_polygon << lower_se_point
          south_space = OpenStudio::Model::Space.fromFloorPrint(south_polygon, floor_to_floor_height, model)
          south_space = south_space.get
          m[0, 3] = lower_sw_point.x
          m[1, 3] = lower_sw_point.y
          m[2, 3] = lower_sw_point.z
          south_space.changeTransformation(OpenStudio::Transformation.new(m))
          south_space.setBuildingStory(story)
          south_space.setName("Story #{floor + 1} South Space")

          east_polygon = OpenStudio::Point3dVector.new
          east_polygon << upper_se_point
          east_polygon << right_nw_point
          east_polygon << right_ne_point
          east_polygon << lower_se_point
          east_space = OpenStudio::Model::Space.fromFloorPrint(east_polygon, floor_to_floor_height, model)
          east_space = east_space.get
          m[0, 3] = upper_se_point.x
          m[1, 3] = upper_se_point.y
          m[2, 3] = upper_se_point.z
          east_space.changeTransformation(OpenStudio::Transformation.new(m))
          east_space.setBuildingStory(story)
          east_space.setName("Story #{floor + 1} East Space")
        end
        # Set vertical story position
        story.setNominalZCoordinate(z)
      end
      BTAP::Geometry.match_surfaces(model)

      return model
    end

    # @!endgroup Create:Shape
  end
end
