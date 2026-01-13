class Standard
  # @!group SubSurface

  # This method adds a subsurface (a window or a skylight depending on the surface) to the centroid of a surface.  The
  # shape of the subsurface is the same as the surface but is scaled so the area of the subsurface is the defined
  # fraction of the surface (set by area_fraction).  Note that this only works for surfaces that do not fold into
  # themselves (like an 'L' or a 'V').
  #
  # @param surface [OpenStudio::Model::Surface] surface object
  # @param area_fraction [Double] fraction of area of the larger surface
  # @return [Boolean] returns true if successful, false if not
  def sub_surface_create_centered_subsurface_from_scaled_surface(surface, area_fraction)
    # Get rid of all existing subsurfaces.
    surface.subSurfaces.sort.each(&:remove)

    # What is the centroid of the surface.
    surf_cent = surface.centroid
    scale_factor = Math.sqrt(area_fraction)

    # Create an array to collect the new vertices
    new_vertices = []

    # Loop on vertices (Point3ds)
    surface.vertices.each do |vertex|
      # Point3d - Point3d = Vector3d
      # Vector from centroid to vertex (GA, GB, GC, etc)
      centroid_vector = vertex - surf_cent

      # Resize the vector (done in place) according to scale_factor
      centroid_vector.setLength(centroid_vector.length * scale_factor)

      # Move the vertex toward the centroid
      new_vertex = surf_cent + centroid_vector

      # Add the new vertices to an array of vertices.
      new_vertices << new_vertex
    end

    # Create a new subsurface with the vertices determined above.
    new_sub_surface = OpenStudio::Model::SubSurface.new(new_vertices, surface.model)
    # Put this sub-surface on the surface.
    new_sub_surface.setSurface(surface)
    # Set the name of the subsurface to be the surface name plus the subsurface type (likely either 'fixedwindow' or
    # 'skylight').
    new_name = "#{surface.name}_#{new_sub_surface.subSurfaceType}"
    new_sub_surface.setName(new_name)
    # There is now only one surface on the subsurface.  Enforce this
    new_sub_surface.setMultiplier(1)
    return true
  end

  # This method adds a subsurface (a window or a skylight depending on the surface) to the centroid of a surface.  The
  # shape of the subsurface is the same as the surface but is scaled so the area of the subsurface is the defined
  # fraction of the surface (set by area_fraction).  This method is different than the
  # 'sub_surface_create_centered_subsurface_from_scaled_surface' method because it can handle concave surfaces.
  # However, it takes longer because it uses BTAP::Geometry::Surfaces.make_convex_surfaces which includes many nested
  # loops that cycle through the verticies in a surface.
  #
  # @param surface [OpenStudio::Model::Surface] surface object
  # @param area_fraction [Double] fraction of area of the larger surface
  # @param construction [OpenStudio::Model::Construction] construction to use for the new surface
  # @return [Boolean] returns true if successful, false if not
  def sub_surface_create_scaled_subsurfaces_from_surface(surface:, area_fraction:, construction:)
    # Set geometry tolerences:
    geometry_tolerence = 12

    # Get rid of all existing subsurfaces
    surface.subSurfaces.sort.each(&:remove)

    # Return vertices of smaller surfaces that fit inside this surface.  This is done in case the surface is
    # concave.

    # Throw an error if the roof is not flat.
    surface.vertices.each do |surf_vert|
      surface.vertices.each do |surf_vert_2|
        return OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Currently skylights can only be added to buildings with non-plenum flat roofs.  No skylight added to surface #{surface.name}") if surf_vert_2.z.to_f.round(geometry_tolerence) != surf_vert.z.to_f.round(geometry_tolerence)
      end
    end
    new_surfaces = BTAP::Geometry::Surfaces.make_convex_surfaces(surface: surface, tol: geometry_tolerence)

    # What is the centroid of the surface.
    new_surf_cents = []
    for i in 0..(new_surfaces.length - 1)
      new_surf_cents << BTAP::Geometry::Surfaces.surf_centroid(surf: new_surfaces[i])
    end

    # Turn everything back into OpenStudio stuff
    os_surf_points = []
    os_surf_cents = []
    for i in 0..(new_surfaces.length - 1)
      os_surf_point = []
      for j in 0..(new_surfaces[i].length - 1)
        os_surf_point << OpenStudio::Point3d.new(new_surfaces[i][j][:x].to_f, new_surfaces[i][j][:y].to_f, new_surfaces[i][j][:z].to_f)
      end
      os_surf_cents << OpenStudio::Point3d.new(new_surf_cents[i][:x].to_f, new_surf_cents[i][:y].to_f, new_surf_cents[i][:z].to_f)
      os_surf_points << os_surf_point
    end
    scale_factor = Math.sqrt(area_fraction)

    new_sub_vertices = []
    os_surf_points.each_with_index do |new_surf, index|
      # Create an array to collect the new vertices
      new_vertices = []
      # Loop on vertices
      new_surf.each do |vertex|
        # Point3d - Point3d = Vector3d
        # Vector from centroid to vertex (GA, GB, GC, etc)
        centroid_vector = vertex - os_surf_cents[index]

        # Resize the vector (done in place) according to scale_factor
        centroid_vector.setLength(centroid_vector.length * scale_factor)

        # Move the vertex toward the centroid
        new_vertex = os_surf_cents[index] + centroid_vector

        # Add the new vertices to an array of vertices.
        new_vertices << new_vertex
      end
      # Check if the new surface/subsurface is too small to model.  If it is then skip it.
      new_area = BTAP::Geometry::Surfaces.getSurfaceAreafromVertices(vertices: new_vertices)
      if new_area < 0.0001
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Attempting to create a subsurface in surface #{surface.name} with an area of #{new_area}m2.  This subsurface is too small so will be skipped")
        next
      end

      # Create a new subsurface with the vertices determined above.
      new_sub_surface = OpenStudio::Model::SubSurface.new(new_vertices, surface.model)
      # Put this sub-surface on the surface.
      new_sub_surface.setSurface(surface)
      # Set the name of the subsurface to be the surface name plus the subsurface type (likely either 'fixedwindow' or
      # 'skylight').  If there will be more than one subsurface then add a counter at the end.
      new_name = "#{surface.name}_#{new_sub_surface.subSurfaceType}"
      if new_surfaces.length > 1
        new_name = "#{surface.name}_#{new_sub_surface.subSurfaceType}_#{index}"
      end
      # Set the skylight type to 'Skylight'
      new_sub_surface.setSubSurfaceType('Skylight')
      # Set the skylight construction to whatever was passed (should be the default skylight construction)
      new_sub_surface.setConstruction(construction)
      new_sub_surface.setName(new_name)
      # There is now only one surface on the subsurface.  Enforce this
      new_sub_surface.setMultiplier(1)
    end
    return true
  end
end
