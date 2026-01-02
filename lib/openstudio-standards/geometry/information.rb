module OpenstudioStandards
  # The Geometry module provides methods to create, modify, and get information about model geometry
  module Geometry
    # Methods to get information about model geometry

    # @!group Information:Calculations

    # calculate aspect ratio from area and perimeter
    #
    # @param area [Double] area
    # @param perimeter [Double] perimeter
    # @return [Double] aspect ratio
    def self.aspect_ratio(area, perimeter)
      length = 0.25 * (perimeter + Math.sqrt((perimeter**2) - (16 * area)))
      width = 0.25 * (perimeter - Math.sqrt((perimeter**2) - (16 * area)))
      aspect_ratio = length / width

      return aspect_ratio
    end

    # This function returns the length of intersection between a wall and floor sharing space. Primarily used for
    # FFactorGroundFloorConstruction exposed perimeter calculations.
    # @note this calculation has a few assumptions:
    # - Floors are flat. This means they have a constant z-axis value.
    # - If a wall shares an edge with a floor, it's assumed that edge intersects with only this floor.
    # - The wall and floor share a common space. This space is assumed to only have one floor!
    #
    # @param wall[OpenStudio::Model::Surface] wall surface being compared to the floor of interest
    # @param floor[OpenStudio::Model::Surface] floor occupying same space as wall. Edges checked for interesections with wall
    # @return [Double] returns the intersection/overlap length of the wall and floor in meters
    def self.wall_and_floor_intersection_length(wall, floor)
      # Used for determining if two points are 'equal' if within this length
      tolerance = 0.0001

      # Get floor and wall edges
      wall_edge_array = OpenstudioStandards::Geometry.surface_get_edges(wall)
      floor_edge_array = OpenstudioStandards::Geometry.surface_get_edges(floor)

      # Floor assumed flat and constant in x-y plane (i.e. a single z value)
      floor_z_value = floor_edge_array[0][0].z

      # Iterate through wall edges
      wall_edge_array.each do |wall_edge|
        wall_edge_p1 = wall_edge[0]
        wall_edge_p2 = wall_edge[1]

        # If points representing the wall surface edge have different z-coordinates, this edge is not parallel to the
        # floor and can be skipped

        if tolerance <= (wall_edge_p1.z - wall_edge_p2.z).abs
          next
        end

        # If wall edge is parallel to the floor, ensure it's on the same x-y plane as the floor.
        if tolerance <= (wall_edge_p1.z - floor_z_value).abs
          next
        end

        # If the edge is parallel with the floor and in the same x-y plane as the floor, assume an intersection the
        # length of the wall edge
        intersect_vector = wall_edge_p1 - wall_edge_p2
        edge_vector = OpenStudio::Vector3d.new(intersect_vector.x, intersect_vector.y, intersect_vector.z)
        return(edge_vector.length)
      end

      # If no edges intersected, return 0
      return 0.0
    end

    # @!endgroup Information:Calculations

    # @!group Information:Surface

    # Returns an array of OpenStudio::Point3D pairs of an OpenStudio::Model::Surface's edges. Used to calculate surface intersections.
    #
    # @param surface[OpenStudio::Model::Surface] OpenStudio surface object
    # @return [Array<Array(OpenStudio::Point3D, OpenStudio::Point3D)>] Array of pair of points describing the line segment of an edge
    def self.surface_get_edges(surface)
      vertices = surface.vertices
      n_vertices = vertices.length

      # Create edge hash that keeps track of all edges in surface. An edge is defined here as an array of length 2
      # containing two OpenStudio::Point3Ds that define the line segment representing a surface edge.
      # format edge_array[i] = [OpenStudio::Point3D, OpenStudio::Point3D]
      edge_array = []

      # Iterate through each vertex in the surface and construct an edge for it
      for edge_counter in 0..n_vertices - 1

        # If not the last vertex in surface
        if edge_counter < n_vertices - 1
          edge_array << [vertices[edge_counter], vertices[edge_counter + 1]]
        else
          # Make index adjustments for final index in vertices array
          edge_array << [vertices[edge_counter], vertices[0]]
        end
      end

      return edge_array
    end

    # Calculate the window to wall ratio of a surface
    #
    # @param surface [OpenStudio::Model::Surface] OpenStudio Surface object
    # @return [Double] window to wall ratio of a surface
    def self.surface_get_window_to_wall_ratio(surface)
      surface_area = surface.grossArea
      surface_fene_area = 0.0
      surface.subSurfaces.sort.each do |ss|
        next unless ss.subSurfaceType == 'FixedWindow' || ss.subSurfaceType == 'OperableWindow' || ss.subSurfaceType == 'GlassDoor'

        surface_fene_area += ss.netArea
      end
      return surface_fene_area / surface_area
    end

    # Calculate the door to wall ratio of a surface
    #
    # @param surface [OpenStudio::Model::Surface] OpenStudio Surface object
    # @return [Double] door to wall ratio of a surface
    def self.surface_get_door_to_wall_ratio(surface)
      surface_area = surface.grossArea
      surface_door_area = 0.0
      surface.subSurfaces.sort.each do |ss|
        next unless ss.subSurfaceType == 'Door'

        surface_door_area += ss.netArea
      end
      return surface_door_area / surface_area
    end

    # Calculate a surface's absolute azimuth
    #
    # @param surface [OpenStudio::Model::Surface] OpenStudio Surface object
    # @return [Double] surface absolute azimuth in degrees
    def self.surface_get_absolute_azimuth(surface)
      # Get associated space
      space = surface.space.get

      # Get model object
      model = surface.model

      # Calculate azimuth
      surface_azimuth_rel_space = OpenStudio.convert(surface.azimuth, 'rad', 'deg').get
      space_dir_rel_north = space.directionofRelativeNorth
      building_dir_rel_north = model.getBuilding.northAxis
      surface_abs_azimuth = surface_azimuth_rel_space + space_dir_rel_north + building_dir_rel_north
      surface_abs_azimuth -= 360.0 until surface_abs_azimuth < 360.0

      return surface_abs_azimuth
    end

    # Determine a surface absolute cardinal direction
    #
    # @param surface [OpenStudio::Model::Surface] OpenStudio Surface object
    # @return [String] surface absolute cardinal direction, 'N', 'E', 'S, 'W'
    def self.surface_get_cardinal_direction(surface)
      # Get the surface's absolute azimuth
      surface_abs_azimuth = OpenstudioStandards::Geometry.surface_get_absolute_azimuth(surface)

      # Determine the surface's cardinal direction
      cardinal_direction = ''
      if (surface_abs_azimuth >= 0 && surface_abs_azimuth <= 45) || (surface_abs_azimuth > 315 && surface_abs_azimuth <= 360)
        cardinal_direction = 'N'
      elsif surface_abs_azimuth > 45 && surface_abs_azimuth <= 135
        cardinal_direction = 'E'
      elsif surface_abs_azimuth > 135 && surface_abs_azimuth <= 225
        cardinal_direction = 'S'
      elsif surface_abs_azimuth > 225 && surface_abs_azimuth <= 315
        cardinal_direction = 'W'
      end

      return cardinal_direction
    end

    # @!endgroup Information:Surface

    # @!group Information:Surfaces

    # return an array of z values for surfaces passed in. The values will be relative to the parent origin.
    #
    # @param surfaces [Array<OpenStudio::Model::Surface>] Array of OpenStudio Surface objects
    # @return [Array<Double>] array of z values in meters
    def self.surfaces_get_z_values(surfaces)
      z_values = []

      # loop over all surfaces
      surfaces.each do |surface|
        # get the existing vertices
        vertices = surface.vertices
        vertices.each do |vertex|
          # push z value to array
          z_values << vertex.z
        end
      end

      return z_values
    end

    # Check if a point is contained on any surface in an array of surfaces
    #
    # @param surfaces [Array<OpenStudio::Model::Surface>] Array of OpenStudio Surface objects
    # @param point [OpenStudio::Point3d] Point3d object
    # @return [Boolean] true if on a surface in surface array, false if not
    def self.surfaces_contain_point?(surfaces, point)
      on_surface = false

      surfaces.each do |surface|
        # Check if sensor is on floor plane (I need to loop through all floors)
        plane = surface.plane
        point_on_plane = plane.project(point)

        face_transform = OpenStudio::Transformation.alignFace(surface.vertices)
        face_vertices = face_transform * surface.vertices
        face_point_on_plane = face_transform * point_on_plane

        if OpenStudio.pointInPolygon(face_point_on_plane, face_vertices.reverse, 0.01)
          # initial_sensor location lands in this surface's polygon
          on_surface = true
        end
      end

      return on_surface
    end

    # @!endgroup Information:Surfaces

    # @!group Information:SubSurface

    # Determine if the sub surface is a vertical rectangle,
    # meaning a rectangle where the bottom is parallel to the ground.
    #
    # @param sub_surface [OpenStudio::Model::SubSurface] OpenStudio SubSurface object
    # @return [Boolean] returns true if the surface is a vertical rectangle, false if not
    def self.sub_surface_vertical_rectangle?(sub_surface)
      # Get the vertices once
      verts = sub_surface.vertices

      # Check for 4 vertices
      return false unless verts.size == 4

      # Check if the 2 lowest z-values
      # are the same
      z_vals = []
      verts.each do |vertex|
        z_vals << vertex.z
      end
      z_vals = z_vals.sort
      return false unless z_vals[0] == z_vals[1]

      # Check if the diagonals are equal length
      diag_a = verts[0] - verts[2]
      diag_b = verts[1] - verts[3]
      return false unless diag_a.length == diag_b.length

      # If here, we have a rectangle
      return true
    end

    # @!endgroup Information:SubSurface

    # @!group Information:Space

    # Calculate the space envelope area.
    # According to the 90.1 definition, the building envelope includes:
    # 1. "the elements of a building that separate conditioned spaces from the exterior"
    # 2. "the elements of a building that separate conditioned space from unconditioned
    #    space or that enclose semiheated spaces through which thermal energy may be
    #    transferred to or from the exterior, to or from unconditioned spaces or to or
    #    from conditioned spaces."
    #
    # Outside boundary conditions currently supported:
    # - Adiabatic
    # - Surface
    # - Outdoors
    # - Foundation
    # - Ground
    # - GroundFCfactorMethod
    # - OtherSideCoefficients
    # - OtherSideConditionsModel
    # - GroundSlabPreprocessorAverage
    # - GroundSlabPreprocessorCore
    # - GroundSlabPreprocessorPerimeter
    # - GroundBasementPreprocessorAverageWall
    # - GroundBasementPreprocessorAverageFloor
    # - GroundBasementPreprocessorUpperWall
    # - GroundBasementPreprocessorLowerWall
    #
    # Surface type currently supported:
    # - Floor
    # - Wall
    # - RoofCeiling
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param multiplier [Boolean] account for space multiplier
    # @return [Double] area in m^2
    def self.space_get_envelope_area(space, multiplier: true)
      area_m2 = 0.0

      # Get the space conditioning type
      std = Standard.build('90.1-2019') # delete once space methods refactored
      space_cond_type = std.space_conditioning_category(space)

      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Only account for spaces that are conditioned or semi-heated
        next unless space_cond_type != 'Unconditioned'

        surf_cnt = false

        # Conditioned space OR semi-heated space <-> exterior
        # Conditioned space OR semi-heated space <-> ground
        if surface.outsideBoundaryCondition == 'Outdoors' || surface.isGroundSurface
          surf_cnt = true
        end

        # Conditioned space OR semi-heated space <-> unconditioned spaces
        unless surf_cnt
          # @todo add a case for 'Zone' when supported
          if surface.outsideBoundaryCondition == 'Surface'
            adj_space = surface.adjacentSurface.get.space.get
            adj_space_cond_type = std.space_conditioning_category(adj_space)
            surf_cnt = true unless adj_space_cond_type != 'Unconditioned'
          end
        end

        if surf_cnt
          # This surface
          area_m2 += surface.netArea
          # Subsurfaces in this surface
          surface.subSurfaces.sort.each do |subsurface|
            area_m2 += subsurface.netArea
          end
        end
      end

      if multiplier
        area_m2 *= space.multiplier
      end

      return area_m2
    end

    # Calculate the area of the exterior walls, including the area of the windows and doors on these walls.
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param multiplier [Boolean] account for space multiplier, default false
    # @return [Double] area in m^2
    def self.space_get_exterior_wall_and_subsurface_area(space, multiplier: false)
      area_m2 = 0.0

      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == 'Wall'

        # This surface
        area_m2 += surface.netArea
        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |subsurface|
          area_m2 += subsurface.netArea
        end
      end

      if multiplier
        area_m2 *= space.multiplier
      end

      return area_m2
    end

    # Calculate the area of the exterior walls, including the area of the windows and doors on these walls, and the area of roofs.
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param multiplier [Boolean] account for space multiplier, default false
    # @return [Double] area in m^2
    def self.space_get_exterior_wall_and_subsurface_and_roof_area(space, multiplier: false)
      area_m2 = 0.0

      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == 'Wall' || surface.surfaceType == 'RoofCeiling'

        # This surface
        area_m2 += surface.netArea
        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |subsurface|
          area_m2 += subsurface.netArea
        end
      end

      if multiplier
        area_m2 *= space.multiplier
      end

      return area_m2
    end

    # Get a sorted array of tuples containing a list of spaces and connected area in descending order
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param same_floor [Boolean] only consider spaces on the same floor
    # @return [Hash] sorted hash with array of spaces and area
    def self.space_get_adjacent_spaces_with_shared_wall_areas(space, same_floor: true)
      same_floor_spaces = []
      spaces = []
      space.surfaces.each do |surface|
        adj_surface = surface.adjacentSurface
        unless adj_surface.empty?
          space.model.getSpaces.sort.each do |other_space|
            next if other_space == space

            other_space.surfaces.each do |surf|
              if surf == adj_surface.get
                spaces << other_space
              end
            end
          end
        end
      end
      # If looking for only spaces adjacent on the same floor.
      if same_floor == true
        if space.buildingStory.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Information', "Cannot get adjacent spaces of space #{space.name} since space not set to BuildingStory.")
          return nil
        end

        spaces.each do |other_space|
          if space.buildingStory.empty?
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Information', "One or more adjecent spaces to space #{space.name} is not assigned to a BuildingStory. Ensure all spaces are assigned.")
            return nil
          end

          if other_space.buildingStory.get == space.buildingStory.get
            same_floor_spaces << other_space
          end
        end
        spaces = same_floor_spaces
      end

      # now sort by areas.
      area_index = []
      array_hash = {}
      return array_hash if spaces.empty?

      # iterate through each surface in the space
      space.surfaces.each do |surface|
        # get the adjacent surface in another space.
        adj_surface = surface.adjacentSurface
        unless adj_surface.empty?
          # go through each of the adjacent spaces to find the matching surface/space.
          spaces.each_with_index do |other_space, index|
            next if other_space == space

            other_space.surfaces.each do |surf|
              if surf == adj_surface.get
                # initialize array index to zero for first time so += will work.
                area_index[index] = 0 if area_index[index].nil?
                area_index[index] += surf.grossArea
                array_hash[other_space] = area_index[index]
              end
            end
          end
        end
      end
      sorted_spaces = array_hash.sort_by { |_key, value| value }.reverse
      return sorted_spaces
    end

    # Find the space that has the most wall area touching this space.
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param same_floor [Boolean] only consider spaces on the same floor
    # @return [OpenStudio::Model::Space] OpenStudio Space object
    def self.space_get_adjacent_space_with_most_shared_wall_area(space, same_floor: true)
      adjacent_space = OpenstudioStandards::Geometry.space_get_adjacent_spaces_with_shared_wall_areas(space, same_floor: same_floor)[0][0]
      return adjacent_space
    end

    # Finds heights of the first below grade walls and returns them as a numeric. Used when defining C Factor walls.
    # Returns nil if the space is above grade.
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Double] height in meters, or nil if undefined
    def self.space_get_below_grade_wall_height(space)
      # find height of first below-grade wall adjacent to the ground
      surface_height = nil
      space.surfaces.each do |surface|
        next unless surface.surfaceType == 'Wall'

        boundary_condition = surface.outsideBoundaryCondition
        next unless boundary_condition == 'OtherSideCoefficients' || boundary_condition.to_s.downcase.include?('ground')

        # calculate wall height as difference of maximum and minimum z values, assuming square, vertical walls
        z_values = []
        surface.vertices.each do |vertex|
          z_values << vertex.z
        end
        surface_height = z_values.max - z_values.min
      end

      return surface_height
    end

    # This function returns the space's ground perimeter length.
    # Assumes only one floor per space!
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Double] length in meters
    def self.space_get_f_floor_perimeter(space)
      # Find space's floors with ground contact
      floors = []
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition.to_s.downcase.include?('ground')
          floors << surface
        end
      end

      # If this space has no ground contact floors, return 0
      return 0.0 if floors.empty?

      # Raise a warning for any space with more than 1 ground contact floor surface.
      if floors.length > 1
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Information', "Space: #{space.name} has more than one ground contact floor. FFactorGroundFloorConstruction perimeter in this space may be incorrect.")
      end

      # cycle through surfaces in the space and get adjacency length to the floor
      floor = floors[0]
      perimeter = 0.0
      space.surfaces.each do |surface|
        # find perimeter of floor by finding intersecting outdoor walls and measuring the intersection
        if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
          perimeter += OpenstudioStandards::Geometry.wall_and_floor_intersection_length(surface, floor)
        end
      end

      return perimeter
    end

    # This function returns the space's ground area.
    # Assumes only one floor per space!
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Double] area in m^2
    def self.space_get_f_floor_area(space)
      # Find space's floors with ground contact
      floors = []
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition.to_s.downcase.include?('ground')
          floors << surface
        end
      end

      # If this space has no ground contact floors, return 0
      return 0.0 if floors.empty?

      # Raise a warning for any space with more than 1 ground contact floor surface.
      if floors.length > 1
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Information', "Space: #{space.name} has more than one ground contact floor. FFactorGroundFloorConstruction area in this space may be incorrect.")
      end

      # Get floor area
      floor = floors[0]
      area = floor.netArea

      return area
    end

    # @!endgroup Information:Space

    # @!group Information:Spaces

    # Get the total floor area of selected spaces
    #
    # @param spaces [Array<OpenStudio::Model::Space>] array of OpenStudio Space objects
    # @param multiplier [Boolean] account for space multiplier
    # @return [Double] total floor area of spaces in square meters
    def self.spaces_get_floor_area(spaces, multiplier: true)
      total_area = 0.0
      spaces.each do |space|
        space_multiplier = multiplier ? space.multiplier : 1.0
        total_area += space.floorArea * space_multiplier
      end
      return total_area
    end

    # Get the total exterior area of selected spaces
    #
    # @param spaces [Array<OpenStudio::Model::Space>] array of OpenStudio Space objects
    # @param multiplier [Boolean] account for space multiplier
    # @return [Double] total exterior area of spaces in square meters
    def self.spaces_get_exterior_area(spaces, multiplier: true)
      total_area = 0.0
      spaces.each do |space|
        space_multiplier = multiplier ? space.multiplier : 1.0
        total_area += space.exteriorArea * space_multiplier
      end
      return total_area
    end

    # Get the total exterior wall area of selected spaces
    #
    # @param spaces [Array<OpenStudio::Model::Space>] array of OpenStudio Space objects
    # @param multiplier [Boolean] account for space multiplier
    # @return [Double] total exterior wall area of spaces in square meters
    def self.spaces_get_exterior_wall_area(spaces, multiplier: true)
      total_area = 0.0
      spaces.each do |space|
        space_multiplier = multiplier ? space.multiplier : 1.0
        total_area += space.exteriorWallArea * space_multiplier
      end
      return total_area
    end

    # @!endgroup Information:Spaces

    # @!group Information:ThermalZone

    # Return an array of zones that share a wall with the zone
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @param same_floor [Boolean] only valid option for now is true
    # @return [Array<OpenStudio::Model::ThermalZone>] Array of OpenStudio ThermalZone objects
    def self.thermal_zone_get_adjacent_zones_with_shared_walls(thermal_zone, same_floor: true)
      adjacent_zones = []

      thermal_zone.spaces.each do |space|
        adj_spaces = OpenstudioStandards::Geometry.space_get_adjacent_spaces_with_shared_wall_areas(space, same_floor: same_floor)
        adj_spaces.each do |k, v|
          # skip if space is in current thermal zone.
          next unless space.thermalZone.is_initialized
          next if k.thermalZone.get == thermal_zone

          adjacent_zones << k.thermalZone.get
        end
      end

      adjacent_zones = adjacent_zones.uniq

      return adjacent_zones
    end

    # @!endgroup Information:ThermalZone

    # @!group Information:ThermalZones

    # Determine the number of stories spanned by the supplied thermal zones.
    # If all zones on one of the stories have an identical multiplier,
    # assume that the multiplier is a floor multiplier and increase the number of stories accordingly.
    # Stories do not have to be contiguous.
    #
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] An array of OpenStudio ThermalZone objects
    # @return [Integer] The number of stories spanned by the thermal zones
    def self.thermal_zones_get_number_of_stories_spanned(thermal_zones)
      # Get the story object for all zones
      stories = []
      thermal_zones.each do |zone|
        zone.spaces.each do |space|
          story = space.buildingStory
          next if story.empty?

          stories << story.get
        end
      end

      # Reduce down to the unique set of stories
      stories = stories.uniq

      # Tally up stories including multipliers
      num_stories = 0
      stories.each do |story|
        num_stories += OpenstudioStandards::Geometry.building_story_get_floor_multiplier(story)
      end

      return num_stories
    end

    # @!endgroup Information:ThermalZones

    # @!group Information:Story

    # Calculate the story exterior wall perimeter. Selected story should have above grade walls. If not perimeter may return zero.
    #
    # @param story [OpenStudio::Model::BuildingStory]
    # @param multiplier_adjustment [Double] Adjust the calculated perimeter to account for zone multipliers. The value represents the story_multiplier which reduces the adjustment by that factor over the full zone multiplier.
    # @param exterior_boundary_conditions [Array<String>] Array of strings of exterior boundary conditions.
    # @param bounding_box [OpenStudio::BoundingBox] bounding box to determine which spaces are included
    # @todo this doesn't catch walls that are split that sit above floor surfaces that are not (e.g. main corridoor in secondary school model)
    # @todo also odd with multi-height spaces
    def self.building_story_get_exterior_wall_perimeter(story,
                                                        multiplier_adjustment: nil,
                                                        exterior_boundary_conditions: ['Outdoors', 'Ground'],
                                                        bounding_box: nil)
      perimeter = 0
      party_walls = []
      story.spaces.each do |space|
        # counter to use later
        edge_hash = {}
        edge_counter = 0
        space.surfaces.each do |surface|
          # get vertices
          vertex_hash = {}
          vertex_counter = 0
          surface.vertices.each do |vertex|
            vertex_counter += 1
            vertex_hash[vertex_counter] = [vertex.x, vertex.y, vertex.z]
          end
          # make edges
          counter = 0
          vertex_hash.each do |k, v|
            edge_counter += 1
            counter += 1
            if vertex_hash.size == counter
              # different code for wrap around vertex
              edge_hash[edge_counter] = [v, vertex_hash[1], surface, surface.outsideBoundaryCondition, surface.surfaceType]
            else
              edge_hash[edge_counter] = [v, vertex_hash[counter + 1], surface, surface.outsideBoundaryCondition, surface.surfaceType]
            end
          end
        end

        # check edges for matches (need opposite vertices and proper boundary conditions)
        edge_hash.each do |k1, v1|
          # apply to any floor boundary condition. This supports used in floors above basements
          next if v1[4] != 'Floor'

          edge_hash.each do |k2, v2|
            test_boundary_cond = false
            next if !exterior_boundary_conditions.include?(v2[3]) # method arg takes multiple conditions
            next if v2[4] != 'Wall'

            # see if edges have same geometry

            # found cases where the two lines below removed edges and resulted in lower than actual perimeter. Added new code with tolerance.
            # next if not v1[0] == v2[1] # next if not same geometry reversed
            # next if not v1[1] == v2[0]

            # these are three item array's add in tolerance for each array entry
            tolerance = 0.0001
            test_a = true
            test_b = true
            3.times.each do |i|
              if (v1[0][i] - v2[1][i]).abs > tolerance
                test_a = false
              end
              if (v1[1][i] - v2[0][i]).abs > tolerance
                test_b = false
              end
            end

            next if test_a != true
            next if test_b != true

            # edge_bounding_box = OpenStudio::BoundingBox.new
            # edge_bounding_box.addPoints(space.transformation() * v2[2].vertices)
            # if not edge_bounding_box.intersects(bounding_box) doesn't seem to work reliably, writing custom code to check

            point_one = OpenStudio::Point3d.new(v2[0][0], v2[0][1], v2[0][2])
            point_one = (space.transformation * point_one)
            point_two = OpenStudio::Point3d.new(v2[1][0], v2[1][1], v2[1][2])
            point_two = (space.transformation * point_two)

            if !bounding_box.nil? && (v2[3] == 'Adiabatic')

              on_bounding_box = false
              if ((bounding_box.minX.to_f - point_one.x).abs < tolerance) && ((bounding_box.minX.to_f - point_two.x).abs < tolerance)
                on_bounding_box = true
              elsif ((bounding_box.maxX.to_f - point_one.x).abs < tolerance) && ((bounding_box.maxX.to_f - point_two.x).abs < tolerance)
                on_bounding_box = true
              elsif ((bounding_box.minY.to_f - point_one.y).abs < tolerance) && ((bounding_box.minY.to_f - point_two.y).abs < tolerance)
                on_bounding_box = true
              elsif ((bounding_box.maxY.to_f - point_one.y).abs < tolerance) && ((bounding_box.maxY.to_f - point_two.y).abs < tolerance)
                on_bounding_box = true
              end

              # if not edge_bounding_box.intersects(bounding_box) doesn't seem to work reliably, writing custom code to check
              # todo - this is basic check for adiabatic party walls and won't catch all situations. Can be made more robust in the future
              if on_bounding_box == true
                length = OpenStudio::Vector3d.new(point_one - point_two).length
                party_walls << v2[2]
                length_ip_display = OpenStudio.convert(length, 'm', 'ft').get.round(2)
                OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Information', " * #{v2[2].name} has an adiabatic boundary condition and sits in plane with the building bounding box. Adding #{length_ip_display} (ft) to perimeter length of #{story.name} for this surface, assuming it is a party wall.")
              elsif space.multiplier == 1
                length = OpenStudio::Vector3d.new(point_one - point_two).length
                party_walls << v2[2]
                length_ip_display = OpenStudio.convert(length, 'm', 'ft').get.round(2)
                OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Information', " * #{v2[2].name} has an adiabatic boundary condition and is in a zone with a multiplier of 1. Adding #{length_ip_display} (ft) to perimeter length of #{story.name} for this surface, assuming it is a party wall.")
              else
                length = 0
              end

            else
              length = OpenStudio::Vector3d.new(point_one - point_two).length
            end

            if multiplier_adjustment.nil?
              perimeter += length
            else
              # adjust for multiplier
              non_story_multiplier = space.multiplier / multiplier_adjustment.to_f
              perimeter += length * non_story_multiplier
            end
          end
        end
      end

      return { perimeter: perimeter, party_walls: party_walls }
    end

    # Checks all spaces on this story that are part of the total floor area to see if they have the same multiplier.
    # If they do, assume that the multipliers are being used as a floor multiplier.
    #
    # @param building_story [OpenStudio::Model::BuildingStory] OpenStudio BuildingStory object
    # @return [Integer] return the floor multiplier for this story, returning 1 if no floor multiplier.
    def self.building_story_get_floor_multiplier(building_story)
      floor_multiplier = 1

      # Determine the multipliers for all spaces
      multipliers = []
      building_story.spaces.each do |space|
        # Ignore spaces that aren't part of the total floor area
        next unless space.partofTotalFloorArea

        multipliers << space.multiplier
      end

      # If there are no spaces on this story, assume
      # a multiplier of 1
      if multipliers.empty?
        return floor_multiplier
      end

      # Calculate the average multiplier and
      # then convert to integer.
      avg_multiplier = (multipliers.inject { |a, e| a + e }.to_f / multipliers.size).to_i

      # If the multiplier is greater than 1, report this
      if avg_multiplier > 1
        floor_multiplier = avg_multiplier
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Information', "Story #{building_story.name} has a multiplier of #{floor_multiplier}.")
      end

      return floor_multiplier
    end

    # Gets the minimum height of the building story.
    # This is considered to be the minimum z value of any vertex of any surface of any space on the story, with the exception of plenum spaces.
    #
    # @param building_story [OpenStudio::Model::BuildingStory] OpenStudio BuildingStory object
    # @return [Double] the minimum height in meters
    def self.building_story_get_minimum_height(building_story)
      z_heights = []
      building_story.spaces.each do |space|
        # Skip plenum spaces
        next if OpenstudioStandards::Space.space_plenum?(space)

        # Get the z value of the space, which
        # vertices in space surfaces are relative to.
        z_origin = space.zOrigin

        # loop through space surfaces to find min z value
        space.surfaces.each do |surface|
          surface.vertices.each do |vertex|
            z_heights << (vertex.z + z_origin)
          end
        end
      end

      # Error if no z heights were found
      z = 999.9
      if z_heights.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Information', "For #{building_story.name} could not find the minimum_z_value, which means the story has no spaces assigned or the spaces have no surfaces.")
      else
        z = z_heights.min
      end

      return z
    end

    # Get an array of OpenStudio ThermalZone objects for an OpenStudio BuildingStory
    #
    # @param building_story [OpenStudio::Model::BuildingStory] OpenStudio BuildingStory object
    # @return [Array<OpenStudio::Model::ThermalZone>] Array of OpenStudio ThermalZone objects, empty array if none
    def self.building_story_get_thermal_zones(building_story)
      zones = []
      building_story.spaces.sort.each do |space|
        zones << space.thermalZone.get if space.thermalZone.is_initialized
      end
      zones = zones.uniq

      return zones
    end

    # @!endgroup Information:Story

    # @!group Information:Model

    # Returns the building story associated with a given minimum height.
    # This return the story that matches the minimum z value of any vertex of any surface of any space on the story, with the exception of plenum spaces.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param minimum_height [Double] The base height of the desired story, in meters.
    # @param tolerance [Double] tolerance for comparison, in m. Default is 0.3 m ~1ft
    # @return [OpenStudio::Model::BuildingStory] OpenStudio BuildingStory object, nil if none matching
    def self.model_get_building_story_for_nominal_height(model, minimum_height, tolerance: 0.3)
      matched_story = nil
      model.getBuildingStorys.sort.each do |story|
        z = OpenstudioStandards::Geometry.building_story_get_minimum_height(story)
        if (minimum_height - z).abs < tolerance
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Geometry.Information', "The story with a min z value of #{minimum_height.round(2)} is #{story.name}.")
          matched_story = story
        end
      end

      return matched_story
    end

    # Returns an array of the above ground building stories in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Array<OpenStudio::Model::BuildingStory>] Array of OpenStudio BuildingStory objects, empty array if none
    def self.model_get_building_stories_above_ground(model)
      above_ground_stories = []
      model.getBuildingStorys.sort.each do |story|
        z = story.nominalZCoordinate
        if !z.empty? && z.to_f >= 0
          above_ground_stories << story
        end
      end
      return above_ground_stories
    end

    # Returns an array of the below ground building stories in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Array<OpenStudio::Model::BuildingStory>] Array of OpenStudio BuildingStory objects, empty array if none
    def self.model_get_building_stories_below_ground(model)
      below_ground_stories = []
      model.getBuildingStorys.sort.each do |story|
        z = story.nominalZCoordinate
        if !z.empty? && z.to_f < 0
          below_ground_stories << story
        end
      end
      return below_ground_stories
    end

    # Returns the window to wall ratio
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param spaces [Array<OpenStudio::Model::Space>] optional array of Space objects.
    #  If provided, the return will report for only those spaces.
    # @param cardinal_direction [String] Cardinal direction 'N', 'E', 'S', 'W'
    #  If provided, the return will report for only the provided cardinal direction
    # @return [Double] window to wall ratio
    def self.model_get_exterior_window_to_wall_ratio(model,
                                                     spaces: [],
                                                     cardinal_direction: nil)
      # counters
      total_gross_ext_wall_area = 0.0
      total_ext_window_area = 0.0
      window_to_wall_ratio = 0.0

      # get spaces if none provided
      if spaces.empty?
        spaces = model.getSpaces
      end

      # loop through each space and log window and wall areas
      spaces.each do |space|
        # get surface area adjusting for zone multiplier
        zone = space.thermalZone
        if zone.empty?
          # space is not in a thermal zone
          zone_multiplier = 1
        else
          zone_multiplier = zone.get.multiplier
        end

        # loop through spaces and skip all that aren't exterior walls and don't match selected cardinal direction
        space.surfaces.each do |surface|
          next if surface.surfaceType != 'Wall'
          next if surface.outsideBoundaryCondition != 'Outdoors'

          # filter by cardinal direction if specified
          case cardinal_direction
          when 'N', 'n', 'North', 'north'
            next unless OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'N'
          when 'E', 'e', 'East', 'east'
            next unless OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'E'
          when 'S', 's', 'South', 'south'
            next unless OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'S'
          when 'W', 'w', 'West', 'west'
            next unless OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface) == 'W'
          end

          # Get wall and window area
          surface_gross_area = surface.grossArea * zone_multiplier

          # loop through sub surfaces and add area including multiplier
          ext_window_area = 0
          surface.subSurfaces.each do |sub_surface|
            ext_window_area += sub_surface.grossArea * sub_surface.multiplier * zone_multiplier
          end

          total_gross_ext_wall_area += surface_gross_area
          total_ext_window_area += ext_window_area
        end
      end

      if total_gross_ext_wall_area > 0.0
        window_to_wall_ratio = total_ext_window_area / total_gross_ext_wall_area
      end

      return window_to_wall_ratio
    end

    # Returns the wall area and window area by orientation
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param spaces [Array<OpenStudio::Model::Space>] optional array of Space objects.
    #   If provided, the return will report for only those spaces.
    # @return [Hash] Hash of wall area in square meters and window to wall ratio for each orientation
    def self.model_get_exterior_window_and_wall_area_by_orientation(model, spaces: [])
      # counters
      total_gross_ext_wall_area_north = 0.0
      total_gross_ext_wall_area_south = 0.0
      total_gross_ext_wall_area_east = 0.0
      total_gross_ext_wall_area_west = 0.0
      total_ext_window_area_north = 0.0
      total_ext_window_area_south = 0.0
      total_ext_window_area_east = 0.0
      total_ext_window_area_west = 0.0

      if spaces.empty?
        spaces = model.getSpaces
      end

      spaces.each do |space|
        # get surface area adjusting for zone multiplier
        zone = space.thermalZone
        if zone.empty?
          zone_multiplier = 1 # space is not in a thermal zone
        else
          zone_multiplier = zone.get.multiplier
        end

        space.surfaces.each do |s|
          next if s.surfaceType != 'Wall'
          next if s.outsideBoundaryCondition != 'Outdoors'

          surface_gross_area = s.grossArea * zone_multiplier

          # loop through sub surfaces and add area including multiplier
          ext_window_area = 0
          s.subSurfaces.each do |sub_surface|
            ext_window_area += sub_surface.grossArea * sub_surface.multiplier * zone_multiplier
          end

          absolute_azimuth = OpenStudio.convert(s.azimuth, 'rad', 'deg').get + s.space.get.directionofRelativeNorth + model.getBuilding.northAxis
          absolute_azimuth -= 360.0 until absolute_azimuth < 360.0

          # add to exterior wall counter if north or south
          if (absolute_azimuth >= 45.0) && (absolute_azimuth < 125.0)
            # east exterior walls
            total_gross_ext_wall_area_east += surface_gross_area
            total_ext_window_area_east += ext_window_area
          elsif (absolute_azimuth >= 125.0) && (absolute_azimuth < 225.0)
            # south exterior walls
            total_gross_ext_wall_area_south += surface_gross_area
            total_ext_window_area_south += ext_window_area
          elsif (absolute_azimuth >= 225.0) && (absolute_azimuth < 315.0)
            # west exterior walls
            total_gross_ext_wall_area_west += surface_gross_area
            total_ext_window_area_west += ext_window_area
          else
            # north exterior walls
            total_gross_ext_wall_area_north += surface_gross_area
            total_ext_window_area_north += ext_window_area
          end
        end
      end

      result = { 'north_wall' => total_gross_ext_wall_area_north,
                 'north_window' => total_ext_window_area_north,
                 'south_wall' => total_gross_ext_wall_area_south,
                 'south_window' => total_ext_window_area_south,
                 'east_wall' => total_gross_ext_wall_area_east,
                 'east_window' => total_ext_window_area_east,
                 'west_wall' => total_gross_ext_wall_area_west,
                 'west_window' => total_ext_window_area_west }
      return result
    end

    # Calculates the exterior perimeter length, checking checks for edges shared by a ground exposed floor and exterior exposed wall.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Double] perimeter length in meters
    # @todo this doesn't catch walls that are split that sit above floor surfaces that are not (e.g. main corridoor in secondary school model)
    # @todo also odd with multi-height spaces
    def self.model_get_perimeter(model)
      perimeter = 0.0
      model.getSpaces.sort.each do |space|
        # counter to use later
        edge_hash = {}
        edge_counter = 0
        space.surfaces.sort.each do |surface|
          # get vertices
          vertex_hash = {}
          vertex_counter = 0
          surface.vertices.each do |vertex|
            vertex_counter += 1
            vertex_hash[vertex_counter] = [vertex.x, vertex.y, vertex.z]
          end
          # make edges
          counter = 0
          vertex_hash.each do |k, v|
            edge_counter += 1
            counter += 1
            if vertex_hash.size == counter
              # different code for wrap around vertex
              edge_hash[edge_counter] = [v, vertex_hash[1], surface, surface.outsideBoundaryCondition, surface.surfaceType]
            else
              edge_hash[edge_counter] = [v, vertex_hash[counter + 1], surface, surface.outsideBoundaryCondition, surface.surfaceType]
            end
          end
        end

        # check edges for matches (need opposite vertices and proper boundary conditions)
        edge_hash.each do |k1, v1|
          next if v1[3] != 'Ground' # skip if not ground exposed floor
          next if v1[4] != 'Floor'

          edge_hash.each do |k2, v2|
            next if v2[3] != 'Outdoors' # skip if not exterior exposed wall (todo - update to handle basement)
            next if v2[4] != 'Wall'

            # see if edges have same geometry
            # found cases where the two lines below removed edges and resulted in lower than actual perimeter. Added new code with tolerance.
            # next if not v1[0] == v2[1] # next if not same geometry reversed
            # next if not v1[1] == v2[0]

            # these are three item array's add in tolerance for each array entry
            tolerance = 0.0001
            test_a = true
            test_b = true
            3.times.each do |i|
              if (v1[0][i] - v2[1][i]).abs > tolerance
                test_a = false
              end
              if (v1[1][i] - v2[0][i]).abs > tolerance
                test_b = false
              end
            end

            next if test_a != true
            next if test_b != true

            point_one = OpenStudio::Point3d.new(v1[0][0], v1[0][1], v1[0][2])
            point_two = OpenStudio::Point3d.new(v1[1][0], v1[1][1], v1[1][2])
            length = OpenStudio::Vector3d.new(point_one - point_two).length
            perimeter += length
          end
        end
      end

      return perimeter
    end


    # Calculate the model envelope area.
    # According to the 90.1 definition, the building envelope includes:
    # 1. "the elements of a building that separate conditioned spaces from the exterior"
    # 2. "the elements of a building that separate conditioned space from unconditioned
    #    space or that enclose semiheated spaces through which thermal energy may be
    #    transferred to or from the exterior, to or from unconditioned spaces or to or
    #    from conditioned spaces."
    #
    # Outside boundary conditions currently supported:
    # - Adiabatic
    # - Surface
    # - Outdoors
    # - Foundation
    # - Ground
    # - GroundFCfactorMethod
    # - OtherSideCoefficients
    # - OtherSideConditionsModel
    # - GroundSlabPreprocessorAverage
    # - GroundSlabPreprocessorCore
    # - GroundSlabPreprocessorPerimeter
    # - GroundBasementPreprocessorAverageWall
    # - GroundBasementPreprocessorAverageFloor
    # - GroundBasementPreprocessorUpperWall
    # - GroundBasementPreprocessorLowerWall
    #
    # Surface type currently supported:
    # - Floor
    # - Wall
    # - RoofCeiling
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param multiplier [Boolean] account for space multipliers
    # @return [Double] area in m^2
    def self.model_get_envelope_area(model, multiplier: true)
      building_envelope_area_m2 = 0
      model.getSpaces.each do |space|
        building_envelope_area_m2 += OpenstudioStandards::Geometry.space_get_envelope_area(space)
      end
      if building_envelope_area_m2 < 0.01
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Information', 'Calculated building envelope area is 0 m2')
        return 0.0
      end

      return building_envelope_area_m2
    end

    # @!endgroup Information:Model
  end
end
