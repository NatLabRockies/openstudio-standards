module OpenstudioStandards
  # The Geometry module provides methods to create, modify, and get information about model geometry
  module Geometry
    # Methods to modify geometry

    # @!group Modify:SubSurface

    # Reduce the area of the subsurface by shrinking it toward the centroid
    # @author Julien Marrec
    #
    # @param sub_surface [OpenStudio::Model::SubSurface] OpenStudio SubSurface object
    # @param percent_reduction [Double] the fractional amount to reduce the area
    # @return [Boolean] returns true if successful, false if not
    def self.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(sub_surface, percent_reduction)
      # if percent_reduction > 1=> percent increase instead of reduction
      mult = percent_reduction <= 1 ? 1 - percent_reduction : percent_reduction
      scale_factor = mult**0.5

      # Get the centroid (Point3d)
      g = sub_surface.centroid

      # Create an array to collect the new vertices
      new_vertices = []

      # Loop on vertices (Point3ds)
      sub_surface.vertices.each do |vertex|
        # Point3d - Point3d = Vector3d
        # Vector from centroid to vertex (GA, GB, GC, etc)
        centroid_vector = vertex - g

        # Resize the vector (done in place) according to scale_factor
        centroid_vector.setLength(centroid_vector.length * scale_factor)

        # Move the vertex toward the centroid
        vertex = g + centroid_vector

        new_vertices << vertex
      end

      # Assign the new vertices to the self
      sub_surface.setVertices(new_vertices)

      return true
    end

    # Reduce the area of the subsurface by raising the sill height
    #
    # @param sub_surface [OpenStudio::Model::SubSurface] OpenStudio SubSurface object
    # @param percent_reduction [Double] the fractional amount to reduce the area
    # @return [Boolean] returns true if successful, false if not
    def self.sub_surface_reduce_area_by_percent_by_raising_sill(sub_surface, percent_reduction)
      # Find the min and max z values
      min_z_val = 99_999
      max_z_val = -99_999
      sub_surface.vertices.each do |vertex|
        # Min z value
        if vertex.z < min_z_val
          min_z_val = vertex.z
        end
        # Max z value
        if vertex.z > max_z_val
          max_z_val = vertex.z
        end
      end

      # Calculate the window height
      height = max_z_val - min_z_val

      # Calculate the new sill height
      z_delta = height * percent_reduction

      # Reset the z value of the lowest points within a certain threshold
      new_vertices = []
      sub_surface.vertices.each do |vertex|
        if (vertex.z - min_z_val).abs < 0.025
          new_vertices << (vertex + OpenStudio::Vector3d.new(0.0, 0.0, z_delta))
        else
          new_vertices << vertex
        end
      end

      # Reset the vertices
      sub_surface.setVertices(new_vertices)

      return true
    end

    # @!endgroup Modify:SubSurface

    # @!group Modify:Space

    # Rename space surfaces using the convention 'SpaceName SurfaceType #'.
    # Rename sub surfaces using the convention 'SurfaceName SubSurfaceType #'.
    #
    # @param space [OpenStudio::Model::Space] OpenStudio space object
    # @return [Boolean] returns true if successful, false if not
    def self.space_rename_surfaces_and_subsurfaces(space)
      # reset names
      surf_i = 1
      space.surfaces.each do |surface|
        surface.setName("temp surf #{surf_i}")
        sub_i = 1
        surface.subSurfaces.each do |sub_surface|
          sub_surface.setName("#{surface.name} sub #{sub_i}")
          sub_i += 1
        end
        surf_i += 1
      end

      # rename surfaces based on space name and surface type
      surface_type_counter = Hash.new(0)
      space.surfaces.sort.each do |surface|
        surface_type = surface.surfaceType
        surface_type_counter[surface_type] += 1
        surface.setName("#{space.name} #{surface_type} #{surface_type_counter[surface_type]}")

        # rename sub surfaces based on surface name and subsurface type
        sub_surface_type_counter = Hash.new(0)
        surface.subSurfaces.sort.each do |sub_surface|
          sub_surface_type = sub_surface.subSurfaceType
          sub_surface_type_counter[sub_surface_type] += 1
          sub_surface.setName("#{surface.name} #{sub_surface_type} #{sub_surface_type_counter[sub_surface_type]}")
        end
      end

      return true
    end

    # @!endgroup Modify:Space

    # @!group Modify:Model

    # Assign each space in the model to a building story based on common z (height) values.
    # If no story object is found for a particular height, create a new one and assign it to the space.
    # Does not assign a story to plenum spaces.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Boolean] returns true if successful, false if not
    def self.model_assign_spaces_to_building_stories(model)
      # Make hash of spaces and min z values
      sorted_spaces = {}
      model.getSpaces.sort.each do |space|
        # Skip plenum spaces
        next if OpenstudioStandards::Space.space_plenum?(space)

        # loop through space surfaces to find min z value
        z_points = []
        space.surfaces.each do |surface|
          surface.vertices.each do |vertex|
            z_points << vertex.z
          end
        end
        min_z = z_points.min + space.zOrigin
        sorted_spaces[space] = min_z
      end

      # Pre-sort spaces
      sorted_spaces = sorted_spaces.sort_by { |a| a[1] }

      # Take the sorted list and assign/make stories
      sorted_spaces.each do |space|
        space_obj = space[0]
        space_min_z = space[1]
        if space_obj.buildingStory.empty?
          tolerance = 0.3
          story = OpenstudioStandards::Geometry.model_get_building_story_for_nominal_height(model, space_min_z, tolerance: tolerance)
          if story.nil?
            story = OpenStudio::Model::BuildingStory.new(model)
            story.setNominalZCoordinate(space_min_z)
            story.setName("Building Story #{space_min_z.round(1)}m")
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "No story with a min z value of #{space_min_z.round(2)} m +/- #{tolerance} m was found, so a new story called #{story.name} was created.")
          end
          space_obj.setBuildingStory(story)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Space #{space[0].name} was not assigned to a story by the user.  It has been assigned to #{story.name}.")
        end
      end

      return true
    end

    # Rename all model surfaces using the convention 'SpaceName SurfaceType #'.
    # Rename all model sub surfaces using the convention 'SurfaceName SubSurfaceType #'.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Boolean] returns true if successful, false if not
    def self.model_rename_surfaces_and_subsurfaces(model)
      model.getSpaces.each { |space| OpenstudioStandards::Geometry.space_rename_surfaces_and_subsurfaces(space) }

      return true
    end

    # Set the model's north axis (degrees from true North)
    #
    # @param model [OpenStudio::Model::Model] OpenStudio Model object
    # @param north_axis [Float] Degrees from true North
    # @return [Boolean] Returns true if successful, false otherwise
    def self.model_set_building_north_axis(model, north_axis)
      return false if north_axis.nil?

      building = model.getBuilding
      building.setNorthAxis(north_axis)

      return true
    end

    # @!endgroup Modify:Model
  end
end
