class Standard
  # @!group Space

  # Returns values for the different types of daylighted areas in the space.
  # Definitions for each type of area follow the respective template.
  # @note This method is super complicated because of all the polygon/geometry math required.
  #   and therefore may not return perfect results.  However, it works well in most tested
  #   situations.  When it fails, it will log warnings/errors for users to see.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param draw_daylight_areas_for_debugging [Boolean] If this argument is set to true,
  #   daylight areas will be added to the model as surfaces for visual debugging.
  #   Yellow = toplighted area, Red = primary sidelighted area,
  #   Blue = secondary sidelighted area, Light Blue = floor
  # @return [Hash] returns a hash of resulting areas (m^2).
  #   Hash keys are: 'toplighted_area', 'primary_sidelighted_area',
  #   'secondary_sidelighted_area', 'total_window_area', 'total_skylight_area'
  # @todo add a list of valid choices for template argument
  # @todo stop skipping non-vertical walls
  def space_daylighted_areas(space, draw_daylight_areas_for_debugging = false)
    ### Begin the actual daylight area calculations ###

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, calculating daylighted areas.")

    result = { 'toplighted_area' => 0.0,
               'primary_sidelighted_area' => 0.0,
               'secondary_sidelighted_area' => 0.0,
               'total_window_area' => 0.0,
               'total_skylight_area' => 0.0 }

    total_window_area = 0
    total_skylight_area = 0

    # Make rendering colors to help debug visually
    if draw_daylight_areas_for_debugging
      # Yellow
      toplit_construction = OpenStudio::Model::Construction.new(space.model)
      toplit_color = OpenStudio::Model::RenderingColor.new(space.model)
      toplit_color.setRenderingRedValue(255)
      toplit_color.setRenderingGreenValue(255)
      toplit_color.setRenderingBlueValue(0)
      toplit_construction.setRenderingColor(toplit_color)

      # Red
      pri_sidelit_construction = OpenStudio::Model::Construction.new(space.model)
      pri_sidelit_color = OpenStudio::Model::RenderingColor.new(space.model)
      pri_sidelit_color.setRenderingRedValue(255)
      pri_sidelit_color.setRenderingGreenValue(0)
      pri_sidelit_color.setRenderingBlueValue(0)
      pri_sidelit_construction.setRenderingColor(pri_sidelit_color)

      # Blue
      sec_sidelit_construction = OpenStudio::Model::Construction.new(space.model)
      sec_sidelit_color = OpenStudio::Model::RenderingColor.new(space.model)
      sec_sidelit_color.setRenderingRedValue(0)
      sec_sidelit_color.setRenderingGreenValue(0)
      sec_sidelit_color.setRenderingBlueValue(255)
      sec_sidelit_construction.setRenderingColor(sec_sidelit_color)

      # Light Blue
      flr_construction = OpenStudio::Model::Construction.new(space.model)
      flr_color = OpenStudio::Model::RenderingColor.new(space.model)
      flr_color.setRenderingRedValue(0)
      flr_color.setRenderingGreenValue(255)
      flr_color.setRenderingBlueValue(255)
      flr_construction.setRenderingColor(flr_color)
    end

    # Move the polygon up slightly for viewability in sketchup
    up_translation_flr = OpenStudio.createTranslation(OpenStudio::Vector3d.new(0, 0, 0.05))
    up_translation_top = OpenStudio.createTranslation(OpenStudio::Vector3d.new(0, 0, 0.1))
    up_translation_pri = OpenStudio.createTranslation(OpenStudio::Vector3d.new(0, 0, 0.1))
    up_translation_sec = OpenStudio.createTranslation(OpenStudio::Vector3d.new(0, 0, 0.1))

    # Get the space's surface group's transformation
    @space_transformation = space.transformation

    # Record a floor in the space for later use
    floor_surface = nil

    # Record all floor polygons
    floor_polygons = []
    floor_z = 0.0
    space.surfaces.sort.each do |surface|
      if surface.surfaceType == 'Floor'
        floor_surface = surface
        floor_z = surface.vertices[0].z
        # floor_polygons << surface.vertices
        # Hard-set the z for the floor to zero
        new_floor_polygon = []
        surface.vertices.each do |vertex|
          new_floor_polygon << OpenStudio::Point3d.new(vertex.x, vertex.y, 0.0)
        end
        floor_polygons << new_floor_polygon
      end
    end

    # Make sure there is one floor surface
    if floor_surface.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Could not find a floor in space #{space.name}, cannot determine daylighted areas.")
      return result
    end

    # Make a set of vertices representing each subsurfaces sidelighteding area
    # and fold them all down onto the floor of the self.
    toplit_polygons = []
    pri_sidelit_polygons = []
    sec_sidelit_polygons = []
    space.surfaces.sort.each do |surface|
      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'

        # @todo stop skipping non-vertical walls
        surface_normal = surface.outwardNormal
        surface_normal_z = surface_normal.z
        unless surface_normal_z.abs < 0.001
          unless surface.subSurfaces.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Cannot currently handle non-vertical walls; skipping windows on #{surface.name} in #{space.name}.")
            next
          end
        end

        surface.subSurfaces.sort.each do |sub_surface|
          next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && (sub_surface.subSurfaceType == 'FixedWindow' || sub_surface.subSurfaceType == 'OperableWindow' || sub_surface.subSurfaceType == 'GlassDoor')

          # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.Space", "***#{sub_surface.name}***"
          total_window_area += sub_surface.netArea

          # Find the head height and sill height of the window
          vertex_heights_above_floor = []
          sub_surface.vertices.each do |vertex|
            vertex_on_floorplane = floor_surface.plane.project(vertex)
            vertex_heights_above_floor << (vertex - vertex_on_floorplane).length
          end
          sill_height_m = vertex_heights_above_floor.min
          head_height_m = vertex_heights_above_floor.max
          # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.Space", "head height = #{head_height_m.round(2)}m, sill height = #{sill_height_m.round(2)}m")

          # Find the width of the window
          rot_origin = nil
          unless sub_surface.vertices.size == 4
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "A sub-surface in space #{space.name} has other than 4 vertices; this sub-surface will not be included in the daylighted area calculation.")
            next
          end
          prev_vertex_on_floorplane = nil
          max_window_width_m = 0
          sub_surface.vertices.each do |vertex|
            vertex_on_floorplane = floor_surface.plane.project(vertex)
            unless prev_vertex_on_floorplane
              prev_vertex_on_floorplane = vertex_on_floorplane
              next
            end
            width_m = (prev_vertex_on_floorplane - vertex_on_floorplane).length
            if width_m > max_window_width_m
              max_window_width_m = width_m
              rot_origin = vertex_on_floorplane
            end
          end

          # Determine the extra width to add to the sidelighted area
          extra_width_m = 0
          width_method = space_daylighted_area_window_width(space)
          if width_method == 'proportional'
            extra_width_m = head_height_m / 2
          elsif width_method == 'fixed'
            extra_width_m = OpenStudio.convert(2, 'ft', 'm').get
          end
          # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.Space", "Adding #{extra_width_m.round(2)}m to the width for the sidelighted area.")

          # Align the vertices with face coordinate system
          face_transform = OpenStudio::Transformation.alignFace(sub_surface.vertices)
          aligned_vertices = face_transform.inverse * sub_surface.vertices

          # Find the min and max x values
          min_x_val = 99_999
          max_x_val = -99_999
          aligned_vertices.each do |vertex|
            # Min x value
            if vertex.x < min_x_val
              min_x_val = vertex.x
            end
            # Max x value
            if vertex.x > max_x_val
              max_x_val = vertex.x
            end
          end
          # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.Space", "min_x_val = #{min_x_val.round(2)}, max_x_val = #{max_x_val.round(2)}")

          # Create polygons that are adjusted
          # to expand from the window shape to the sidelighteded areas.
          pri_sidelit_sub_polygon = []
          sec_sidelit_sub_polygon = []
          aligned_vertices.each do |vertex|
            # Primary sidelighted area
            # Move the x vertices outward by the specified amount.
            if (vertex.x - min_x_val).abs < 0.01
              new_x = vertex.x - extra_width_m
            elsif (vertex.x - max_x_val).abs < 0.01
              new_x = vertex.x + extra_width_m
            else
              new_x = 99.9
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "A window in space #{space.name} is non-rectangular; this sub-surface will not be included in the primary daylighted area calculation. #{vertex.x} != #{min_x_val} or #{max_x_val}")
            end

            # Zero-out the y for the bottom edge because the
            # sidelighteding area extends down to the floor.
            new_y = if vertex.y.zero?
                      vertex.y - sill_height_m
                    else
                      vertex.y
                    end

            # Set z = 0 so that intersection works.
            new_z = 0.0

            # Make the new vertex
            new_vertex = OpenStudio::Point3d.new(new_x, new_y, new_z)
            pri_sidelit_sub_polygon << new_vertex
            # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "#{vertex.x.round(2)}, #{vertex.y.round(2)}, #{vertex.z.round(2)} to #{new_vertex.x.round(2)}, #{new_vertex.y.round(2)}, #{new_vertex.z.round(2)}")

            # Secondary sidelighted area
            # Move the x vertices outward by the specified amount.
            if (vertex.x - min_x_val).abs < 0.01
              new_x = vertex.x - extra_width_m
            elsif (vertex.x - max_x_val).abs < 0.01
              new_x = vertex.x + extra_width_m
            else
              new_x = 99.9
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "A window in space #{space.name} is non-rectangular; this sub-surface will not be included in the secondary daylighted area calculation.")
            end

            # Add the head height of the window to all points
            # sidelighteding area extends down to the floor.
            new_y = if vertex.y.zero?
                      vertex.y - sill_height_m + head_height_m
                    else
                      vertex.y + head_height_m
                    end

            # Set z = 0 so that intersection works.
            new_z = 0.0

            # Make the new vertex
            new_vertex = OpenStudio::Point3d.new(new_x, new_y, new_z)
            sec_sidelit_sub_polygon << new_vertex
          end

          # Realign the vertices with space coordinate system
          pri_sidelit_sub_polygon = face_transform * pri_sidelit_sub_polygon
          sec_sidelit_sub_polygon = face_transform * sec_sidelit_sub_polygon

          # Rotate the sidelighteded areas down onto the floor
          down_vector = OpenStudio::Vector3d.new(0, 0, -1)
          outward_normal_vector = sub_surface.outwardNormal
          rot_vector = down_vector.cross(outward_normal_vector)
          ninety_deg_in_rad = OpenStudio.degToRad(90)
          # @todo change
          new_rotation = OpenStudio.createRotation(rot_origin, rot_vector, ninety_deg_in_rad)
          pri_sidelit_sub_polygon = new_rotation * pri_sidelit_sub_polygon
          sec_sidelit_sub_polygon = new_rotation * sec_sidelit_sub_polygon

          # Put the polygon vertices into counterclockwise order
          pri_sidelit_sub_polygon = pri_sidelit_sub_polygon.reverse
          sec_sidelit_sub_polygon = sec_sidelit_sub_polygon.reverse

          # Add these polygons to the list
          pri_sidelit_polygons << pri_sidelit_sub_polygon
          sec_sidelit_polygons << sec_sidelit_sub_polygon
        end
      elsif surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'

        # @todo stop skipping non-horizontal roofs
        surface_normal = surface.outwardNormal
        straight_upward = OpenStudio::Vector3d.new(0, 0, 1)
        unless surface_normal.to_s == straight_upward.to_s
          unless surface.subSurfaces.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Cannot currently handle non-horizontal roofs; skipping skylights on #{surface.name} in #{space.name}.")
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---Surface #{surface.name} has outward normal of #{surface_normal.to_s.gsub(/\[|\]/, '|')}; up is #{straight_upward.to_s.gsub(/\[|\]/, '|')}.")
            next
          end
        end

        surface.subSurfaces.sort.each do |sub_surface|
          next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && sub_surface.subSurfaceType == 'Skylight'

          # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.Space", "***#{sub_surface.name}***")
          total_skylight_area += sub_surface.netArea

          # Project the skylight onto the floor plane
          polygon_on_floor = []
          vertex_heights_above_floor = []
          sub_surface.vertices.each do |vertex|
            vertex_on_floorplane = floor_surface.plane.project(vertex)
            vertex_heights_above_floor << (vertex - vertex_on_floorplane).length
            polygon_on_floor << vertex_on_floorplane
          end

          # Determine the ceiling height.
          # Assumes skylight is flush with ceiling.
          ceiling_height_m = vertex_heights_above_floor.max

          # Align the vertices with face coordinate system
          face_transform = OpenStudio::Transformation.alignFace(polygon_on_floor)
          aligned_vertices = face_transform.inverse * polygon_on_floor

          # Find the min and max x and y values
          min_x_val = 99_999
          max_x_val = -99_999
          min_y_val = 99_999
          max_y_val = -99_999
          aligned_vertices.each do |vertex|
            # Min x value
            if vertex.x < min_x_val
              min_x_val = vertex.x
            end
            # Max x value
            if vertex.x > max_x_val
              max_x_val = vertex.x
            end
            # Min y value
            if vertex.y < min_y_val
              min_y_val = vertex.y
            end
            # Max y value
            if vertex.y > max_y_val
              max_y_val = vertex.y
            end
          end

          # Figure out how much to expand the window
          additional_extent_m = 0.7 * ceiling_height_m

          # Create polygons that are adjusted
          # to expand from the window shape to the sidelighteded areas.
          toplit_sub_polygon = []
          aligned_vertices.each do |vertex|
            # Move the x vertices outward by the specified amount.
            if vertex.x == min_x_val
              new_x = vertex.x - additional_extent_m
            elsif vertex.x == max_x_val
              new_x = vertex.x + additional_extent_m
            else
              new_x = 99.9
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "A skylight in space #{space.name} is non-rectangular; this sub-surface will not be included in the daylighted area calculation.")
            end

            # Move the y vertices outward by the specified amount.
            if vertex.y == min_y_val
              new_y = vertex.y - additional_extent_m
            elsif vertex.y == max_y_val
              new_y = vertex.y + additional_extent_m
            else
              new_y = 99.9
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "A skylight in space #{space.name} is non-rectangular; this sub-surface will not be included in the daylighted area calculation.")
            end

            # Set z = 0 so that intersection works.
            new_z = 0.0

            # Make the new vertex
            new_vertex = OpenStudio::Point3d.new(new_x, new_y, new_z)
            toplit_sub_polygon << new_vertex
          end

          # Realign the vertices with space coordinate system
          toplit_sub_polygon = face_transform * toplit_sub_polygon

          # Put the polygon vertices into counterclockwise order
          toplit_sub_polygon = toplit_sub_polygon.reverse

          # Add these polygons to the list
          toplit_polygons << toplit_sub_polygon
        end

      end
    end

    # Set z=0 for all the polygons so that intersection will work
    toplit_polygons = space_polygons_set_z(space, toplit_polygons, 0.0)
    pri_sidelit_polygons = space_polygons_set_z(space, pri_sidelit_polygons, 0.0)
    sec_sidelit_polygons = space_polygons_set_z(space, sec_sidelit_polygons, 0.0)

    # Check the initial polygons
    space_check_z_zero(space, floor_polygons, 'floor_polygons')
    space_check_z_zero(space, toplit_polygons, 'toplit_polygons')
    space_check_z_zero(space, pri_sidelit_polygons, 'pri_sidelit_polygons')
    space_check_z_zero(space, sec_sidelit_polygons, 'sec_sidelit_polygons')

    # Join, then subtract
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '***Joining polygons***')

    # Join toplighted polygons into a single set
    combined_toplit_polygons = space_join_polygons(space, toplit_polygons, 0.01, 'toplit_polygons')

    # Join primary sidelighted polygons into a single set
    combined_pri_sidelit_polygons = space_join_polygons(space, pri_sidelit_polygons, 0.01, 'pri_sidelit_polygons')

    # Join secondary sidelighted polygons into a single set
    combined_sec_sidelit_polygons = space_join_polygons(space, sec_sidelit_polygons, 0.01, 'sec_sidelit_polygons')

    # Join floor polygons into a single set
    combined_floor_polygons = space_join_polygons(space, floor_polygons, 0.01, 'floor_polygons')

    # Check the joined polygons
    space_check_z_zero(space, combined_floor_polygons, 'combined_floor_polygons')
    space_check_z_zero(space, combined_toplit_polygons, 'combined_toplit_polygons')
    space_check_z_zero(space, combined_pri_sidelit_polygons, 'combined_pri_sidelit_polygons')
    space_check_z_zero(space, combined_sec_sidelit_polygons, 'combined_sec_sidelit_polygons')

    # Make a new surface for each of the resulting polygons to visually inspect it
    # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.Space", "***Making Surfaces to view in SketchUp***")

    # combined_toplit_polygons.each do |polygon|
    # dummy_space = OpenStudio::Model::Space.new(model)
    # polygon = up_translation_top * polygon
    # daylt_surf = OpenStudio::Model::Surface.new(polygon, model)
    # daylt_surf.setConstruction(toplit_construction)
    # daylt_surf.setSpace(dummy_space)
    # daylt_surf.setName("Top")
    # end

    # combined_pri_sidelit_polygons.each do |polygon|
    # dummy_space = OpenStudio::Model::Space.new(model)
    # polygon = up_translation_pri * polygon
    # daylt_surf = OpenStudio::Model::Surface.new(polygon, model)
    # daylt_surf.setConstruction(pri_sidelit_construction)
    # daylt_surf.setSpace(dummy_space)
    # daylt_surf.setName("Pri")
    # end

    # combined_sec_sidelit_polygons.each do |polygon|
    # dummy_space = OpenStudio::Model::Space.new(model)
    # polygon = up_translation_sec * polygon
    # daylt_surf = OpenStudio::Model::Surface.new(polygon, model)
    # daylt_surf.setConstruction(sec_sidelit_construction)
    # daylt_surf.setSpace(dummy_space)
    # daylt_surf.setName("Sec")
    # end

    # combined_floor_polygons.each do |polygon|
    # dummy_space = OpenStudio::Model::Space.new(model)
    # polygon = up_translation_flr * polygon
    # daylt_surf = OpenStudio::Model::Surface.new(polygon, model)
    # daylt_surf.setConstruction(flr_construction)
    # daylt_surf.setSpace(dummy_space)
    # daylt_surf.setName("Flr")
    # end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '***Subtracting overlapping areas***')

    # Subtract lower-priority daylighting areas from higher priority ones
    pri_minus_top_polygons = space_a_polygons_minus_b_polygons(space, combined_pri_sidelit_polygons, combined_toplit_polygons, 'combined_pri_sidelit_polygons', 'combined_toplit_polygons')

    sec_minus_top_polygons = space_a_polygons_minus_b_polygons(space, combined_sec_sidelit_polygons, combined_toplit_polygons, 'combined_sec_sidelit_polygons', 'combined_toplit_polygons')

    sec_minus_top_minus_pri_polygons = space_a_polygons_minus_b_polygons(space, sec_minus_top_polygons, combined_pri_sidelit_polygons, 'sec_minus_top_polygons', 'combined_pri_sidelit_polygons')

    # Check the subtracted polygons
    space_check_z_zero(space, pri_minus_top_polygons, 'pri_minus_top_polygons')
    space_check_z_zero(space, sec_minus_top_polygons, 'sec_minus_top_polygons')
    space_check_z_zero(space, sec_minus_top_minus_pri_polygons, 'sec_minus_top_minus_pri_polygons')

    # Make a new surface for each of the resulting polygons to visually inspect it.
    # First reset the z so the surfaces show up on the correct plane.
    if draw_daylight_areas_for_debugging

      combined_toplit_polygons_at_floor = space_polygons_set_z(space, combined_toplit_polygons, floor_z)
      pri_minus_top_polygons_at_floor = space_polygons_set_z(space, pri_minus_top_polygons, floor_z)
      sec_minus_top_minus_pri_polygons_at_floor = space_polygons_set_z(space, sec_minus_top_minus_pri_polygons, floor_z)
      combined_floor_polygons_at_floor = space_polygons_set_z(space, combined_floor_polygons, floor_z)

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '***Making Surfaces to view in SketchUp***')
      dummy_space = OpenStudio::Model::Space.new(space.model)

      combined_toplit_polygons_at_floor.each do |polygon|
        polygon = up_translation_top * polygon
        polygon = @space_transformation * polygon
        daylt_surf = OpenStudio::Model::Surface.new(polygon, space.model)
        daylt_surf.setConstruction(toplit_construction)
        daylt_surf.setSpace(dummy_space)
        daylt_surf.setName('Top')
      end

      pri_minus_top_polygons_at_floor.each do |polygon|
        polygon = up_translation_pri * polygon
        polygon = @space_transformation * polygon
        daylt_surf = OpenStudio::Model::Surface.new(polygon, space.model)
        daylt_surf.setConstruction(pri_sidelit_construction)
        daylt_surf.setSpace(dummy_space)
        daylt_surf.setName('Pri')
      end

      sec_minus_top_minus_pri_polygons_at_floor.each do |polygon|
        polygon = up_translation_sec * polygon
        polygon = @space_transformation * polygon
        daylt_surf = OpenStudio::Model::Surface.new(polygon, space.model)
        daylt_surf.setConstruction(sec_sidelit_construction)
        daylt_surf.setSpace(dummy_space)
        daylt_surf.setName('Sec')
      end

      combined_floor_polygons_at_floor.each do |polygon|
        polygon = up_translation_flr * polygon
        polygon = @space_transformation * polygon
        daylt_surf = OpenStudio::Model::Surface.new(polygon, space.model)
        daylt_surf.setConstruction(flr_construction)
        daylt_surf.setSpace(dummy_space)
        daylt_surf.setName('Flr')
      end
    end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '***Calculating Daylighted Areas***')

    # Get the total floor area
    total_floor_area_m2 = space_total_area_of_polygons(space, combined_floor_polygons)
    total_floor_area_ft2 = OpenStudio.convert(total_floor_area_m2, 'm^2', 'ft^2').get
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "total_floor_area_ft2 = #{total_floor_area_ft2.round(1)}")

    # Toplighted area
    toplighted_area_m2 = space_area_a_polygons_overlap_b_polygons(space, combined_toplit_polygons, combined_floor_polygons, 'combined_toplit_polygons', 'combined_floor_polygons')

    # Primary sidelighted area
    primary_sidelighted_area_m2 = space_area_a_polygons_overlap_b_polygons(space, pri_minus_top_polygons, combined_floor_polygons, 'pri_minus_top_polygons', 'combined_floor_polygons')

    # Secondary sidelighted area
    secondary_sidelighted_area_m2 = space_area_a_polygons_overlap_b_polygons(space, sec_minus_top_minus_pri_polygons, combined_floor_polygons, 'sec_minus_top_minus_pri_polygons', 'combined_floor_polygons')

    # Convert to IP for displaying
    toplighted_area_ft2 = OpenStudio.convert(toplighted_area_m2, 'm^2', 'ft^2').get
    primary_sidelighted_area_ft2 = OpenStudio.convert(primary_sidelighted_area_m2, 'm^2', 'ft^2').get
    secondary_sidelighted_area_ft2 = OpenStudio.convert(secondary_sidelighted_area_m2, 'm^2', 'ft^2').get

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "toplighted_area_ft2 = #{toplighted_area_ft2.round(1)}")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "primary_sidelighted_area_ft2 = #{primary_sidelighted_area_ft2.round(1)}")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "secondary_sidelighted_area_ft2 = #{secondary_sidelighted_area_ft2.round(1)}")

    result['toplighted_area'] = toplighted_area_m2
    result['primary_sidelighted_area'] = primary_sidelighted_area_m2
    result['secondary_sidelighted_area'] = secondary_sidelighted_area_m2
    result['total_window_area'] = total_window_area
    result['total_skylight_area'] = total_skylight_area

    return result
  end

  # Determines the method used to extend the daylighted area horizontally next to a window.
  # If the method is 'fixed', 2 ft is added to the width of each window.
  # If the method is 'proportional', a distance equal to half of the head height of the window is added.
  # If the method is 'none', no additional width is added.
  # Default is none.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @return [String] returns 'fixed' or 'proportional'
  def space_daylighted_area_window_width(space)
    method = 'none'
    return method
  end

  # Returns the sidelighting effective aperture
  # space_sidelighting_effective_aperture(space) = E(window area * window VT) / primary_sidelighted_area
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param primary_sidelighted_area [Double] the primary sidelighted area (m^2) of the space
  # @return [Double] the unitless sidelighting effective aperture metric
  def space_sidelighting_effective_aperture(space, primary_sidelighted_area)
    # space_sidelighting_effective_aperture(space)  = E(window area * window VT) / primary_sidelighted_area
    sidelighting_effective_aperture = 9999

    num_sub_surfaces = 0

    # Loop through all windows and add up area * VT
    sum_window_area_times_vt = 0
    construction_name_to_vt_map = {}
    space.surfaces.sort.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'

      surface.subSurfaces.sort.each do |sub_surface|
        next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && (sub_surface.subSurfaceType == 'FixedWindow' || sub_surface.subSurfaceType == 'OperableWindow' || sub_surface.subSurfaceType == 'GlassDoor')

        num_sub_surfaces += 1

        # Get the area
        area_m2 = sub_surface.netArea

        # Get the window construction name
        construction_name = nil
        construction = sub_surface.construction
        if construction.is_initialized
          construction = construction.get
          construction_name = construction.name.get.upcase
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "For #{space.name}, could not determine construction for #{sub_surface.name}, will not be included in space_sidelighting_effective_aperture(space) calculation.")
          next
        end

        # Store VT for this construction in map if not already looked up
        if construction_name_to_vt_map[construction_name].nil?

          # Get the VT from construction (Simple Glazing) if available
          if construction.visibleTransmittance.is_initialized
            construction_name_to_vt_map[construction_name] = construction.visibleTransmittance.get
          else
            # get the VT from the sql file
            sql = space.model.sqlFile
            if sql.is_initialized
              sql = sql.get

              row_query = "SELECT RowName
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND Value='#{construction_name.upcase}'"

              row_id = sql.execAndReturnFirstString(row_query)

              if row_id.is_initialized
                row_id = row_id.get
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "VT row ID not found for construction: #{construction_name}, #{sub_surface.name} will not be included in space_sidelighting_effective_aperture(space) calculation.")
                row_id = 9999
              end

              vt_query = "SELECT Value
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND ColumnName='Glass Visible Transmittance'
                          AND RowName='#{row_id}'"

              vt = sql.execAndReturnFirstDouble(vt_query)

              vt = if vt.is_initialized
                     vt.get
                   end

              # Record the VT
              construction_name_to_vt_map[construction_name] = vt
            else
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Space', 'Model has no sql file containing results, cannot lookup data.')
            end
          end
        end

        # Get the VT from the map
        vt = construction_name_to_vt_map[construction_name]
        if vt.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "For #{space.name}, could not determine VLT for #{construction_name}, will not be included in sidelighting effective aperture calculation.")
          vt = 0
        end

        sum_window_area_times_vt += area_m2 * vt
      end
    end

    # Calculate the effective aperture
    if sum_window_area_times_vt.zero?
      sidelighting_effective_aperture = 9999
      if num_sub_surfaces > 0
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{space.name} has no windows where VLT could be determined, sidelighting effective aperture will be higher than it should.")
      end
    else
      sidelighting_effective_aperture = sum_window_area_times_vt / primary_sidelighted_area
    end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name} sidelighting effective aperture = #{sidelighting_effective_aperture.round(4)}.")

    return sidelighting_effective_aperture
  end

  # Returns the skylight effective aperture
  # space_skylight_effective_aperture(space) = E(0.85 * skylight area * skylight VT * WF) / toplighted_area
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param toplighted_area [Double] the toplighted area (m^2) of the space
  # @return [Double] the unitless skylight effective aperture metric
  def space_skylight_effective_aperture(space, toplighted_area)
    # space_skylight_effective_aperture(space)  = E(0.85 * skylight area * skylight VT * WF) / toplighted_area
    skylight_effective_aperture = 0.0

    num_sub_surfaces = 0

    # Assume that well factor (WF) is 0.9 (all wells are less than 2 feet deep)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', 'Assuming that all skylight wells are less than 2 feet deep to calculate skylight effective aperture.')
    wf = 0.9

    # Loop through all windows and add up area * VT
    sum_85pct_times_skylight_area_times_vt_times_wf = 0
    construction_name_to_vt_map = {}
    space.surfaces.sort.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'

      surface.subSurfaces.sort.each do |sub_surface|
        next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && sub_surface.subSurfaceType == 'Skylight'

        num_sub_surfaces += 1

        # Get the area
        area_m2 = sub_surface.netArea

        # Get the window construction name
        construction_name = nil
        construction = sub_surface.construction
        if construction.is_initialized
          construction = construction.get
          construction_name = construction.name.get.upcase
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "For #{space.name}, could not determine construction for #{sub_surface.name}, will not be included in space_skylight_effective_aperture(space) calculation.")
          next
        end

        # Store VT for this construction in map if not already looked up
        if construction_name_to_vt_map[construction_name].nil?

          # Get the VT from construction (Simple Glazing) if available
          if construction.visibleTransmittance.is_initialized
            construction_name_to_vt_map[construction_name] = construction.visibleTransmittance.get
          else
            # get the VT from the sql file
            sql = space.model.sqlFile
            if sql.is_initialized
              sql = sql.get

              row_query = "SELECT RowName
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND Value='#{construction_name}'"

              row_id = sql.execAndReturnFirstString(row_query)

              if row_id.is_initialized
                row_id = row_id.get
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Data not found for query: #{row_query}")
                next
              end

              vt_query = "SELECT Value
                          FROM tabulardatawithstrings
                          WHERE ReportName='EnvelopeSummary'
                          AND ReportForString='Entire Facility'
                          AND TableName='Exterior Fenestration'
                          AND ColumnName='Glass Visible Transmittance'
                          AND RowName='#{row_id}'"

              vt = sql.execAndReturnFirstDouble(vt_query)

              vt = if vt.is_initialized
                     vt.get
                   end

              # Record the VT
              construction_name_to_vt_map[construction_name] = vt

            else
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Space', 'Model has no sql file containing results, cannot lookup data.')
            end
          end
        end

        # Get the VT from the map
        vt = construction_name_to_vt_map[construction_name]
        if vt.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "For #{space.name}, could not determine VLT for #{construction_name}, will not be included in skylight effective aperture calculation.")
          vt = 0
        end

        sum_85pct_times_skylight_area_times_vt_times_wf += 0.85 * area_m2 * vt * wf
      end
    end

    # Calculate the effective aperture
    if sum_85pct_times_skylight_area_times_vt_times_wf.zero?
      skylight_effective_aperture = 9999
      if num_sub_surfaces > 0
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{space.name} has no skylights where VLT could be determined, skylight effective aperture will be higher than it should.")
      end
    else
      skylight_effective_aperture = sum_85pct_times_skylight_area_times_vt_times_wf / toplighted_area
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "#{space.name} skylight effective aperture = #{skylight_effective_aperture}.")

    return skylight_effective_aperture
  end

  # Removes daylighting controls from model
  #
  # @param space [OpenStudio::Model::Space] OpenStudio space object
  #
  # @return [Boolean] Returns true if a sizing run is required
  def space_remove_daylighting_controls(space)
    # Retrieves daylighting control objects
    existing_daylighting_controls = space.daylightingControls
    unless existing_daylighting_controls.empty?
      existing_daylighting_controls.each(&:remove)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}, removed #{existing_daylighting_controls.size} existing daylight controls before adding new controls.")
      return true
    end
    return false
  end

  # Default for 2013 and earlier is to Add daylighting controls (sidelighting and toplighting) per the template
  # @param space [OpenStudio::Model::Space] the space with daylighting
  # @param remove_existing [Boolean] if true, will remove existing controls then add new ones
  # @param draw_areas_for_debug [Boolean] If this argument is set to true,
  # @return [Boolean] returns true if successful, false if not
  def space_set_baseline_daylighting_controls(space, remove_existing = false, draw_areas_for_debug = false)
    added = space_add_daylighting_controls(space, remove_existing, draw_areas_for_debug)
    return added
  end

  # Adds daylighting controls (sidelighting and toplighting) per the template
  # @note This method is super complicated because of all the polygon/geometry math required.
  #   and therefore may not return perfect results.  However, it works well in most tested
  #   situations.  When it fails, it will log warnings/errors for users to see.
  #
  # @param space [OpenStudio::Model::Space] the space with daylighting
  # @param remove_existing_controls [Boolean] if true, will remove existing controls then add new ones
  # @param draw_daylight_areas_for_debugging [Boolean] If this argument is set to true,
  #   daylight areas will be added to the model as surfaces for visual debugging.
  #   Yellow = toplighted area, Red = primary sidelighted area,
  #   Blue = secondary sidelighted area, Light Blue = floor
  # @return [Boolean] returns true if successful, false if not
  # @todo add a list of valid choices for template argument
  # @todo add exception for retail spaces
  # @todo add exception 2 for skylights with VT < 0.4
  # @todo add exception 3 for CZ 8 where lighting < 200W
  # @todo stop skipping non-vertical walls
  # @todo stop skipping non-horizontal roofs
  # @todo Determine the illuminance setpoint for the controls based on space type
  # @todo rotate sensor to face window (only needed for glare calcs)
  def space_add_daylighting_controls(space, remove_existing_controls, draw_daylight_areas_for_debugging = false)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "******For #{space.name}, adding daylight controls.")

    # Get the space thermal zone
    zone = space.thermalZone
    if zone.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Space', "Space #{space.name} has no thermal zone; cannot set daylighting controls for zone.")
    else
      zone = zone.get
    end

    # Check for existing daylighting controls
    # and remove if specified in the input
    existing_daylighting_controls = space.daylightingControls
    unless existing_daylighting_controls.empty?
      if remove_existing_controls
        space_remove_daylighting_controls(space)
        zone.resetFractionofZoneControlledbyPrimaryDaylightingControl
        zone.resetFractionofZoneControlledbySecondaryDaylightingControl
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}, daylight controls were already present, no additional controls added.")
        return false
      end
    end

    # Skip this space if it has no exterior windows or skylights
    ext_fen_area_m2 = 0
    space.surfaces.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors'

      surface.subSurfaces.each do |sub_surface|
        next unless sub_surface.subSurfaceType == 'FixedWindow' || sub_surface.subSurfaceType == 'OperableWindow' || sub_surface.subSurfaceType == 'Skylight' || sub_surface.subSurfaceType == 'GlassDoor'

        ext_fen_area_m2 += sub_surface.netArea
      end
    end
    if ext_fen_area_m2.zero?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}, daylighting control not applicable because no exterior fenestration is present.")
      return false
    end

    areas = nil

    # Get the daylighting areas
    areas = space_daylighted_areas(space, draw_daylight_areas_for_debugging)

    # Determine the type of daylighting controls required
    req_top_ctrl, req_pri_ctrl, req_sec_ctrl = space_daylighting_control_required?(space, areas)

    # Stop here if no controls are required
    if !req_top_ctrl && !req_pri_ctrl && !req_sec_ctrl
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, no daylighting control is required.")
      return false
    end

    # Output the daylight control requirements
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, toplighting control required = #{req_top_ctrl}")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, primary sidelighting control required = #{req_pri_ctrl}")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, secondary sidelighting control required = #{req_sec_ctrl}")

    # Record a floor in the space for later use
    floor_surface = nil
    space.surfaces.sort.each do |surface|
      if surface.surfaceType == 'Floor'
        floor_surface = surface
        break
      end
    end

    # Find all exterior windows/skylights in the space and record their azimuths and areas
    windows = {}
    skylights = {}
    space.surfaces.sort.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors' && (surface.surfaceType == 'Wall' || surface.surfaceType == 'RoofCeiling')

      # Skip non-vertical walls and non-horizontal roofs
      straight_upward = OpenStudio::Vector3d.new(0, 0, 1)
      surface_normal = surface.outwardNormal
      if surface.surfaceType == 'Wall'
        # @todo stop skipping non-vertical walls
        unless surface_normal.z.abs < 0.001
          unless surface.subSurfaces.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Cannot currently handle non-vertical walls; skipping windows on #{surface.name} in #{space.name} for daylight sensor positioning.")
            next
          end
        end
      elsif surface.surfaceType == 'RoofCeiling'
        # @todo stop skipping non-horizontal roofs
        unless surface_normal.to_s == straight_upward.to_s
          unless surface.subSurfaces.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Cannot currently handle non-horizontal roofs; skipping skylights on #{surface.name} in #{space.name} for daylight sensor positioning.")
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---Surface #{surface.name} has outward normal of #{surface_normal.to_s.gsub(/\[|\]/, '|')}; up is #{straight_upward.to_s.gsub(/\[|\]/, '|')}.")
            next
          end
        end
      end

      # Find the azimuth of the facade
      facade = nil
      group = surface.planarSurfaceGroup
      # The surface is not in a group; should not hit, since called from Space.surfaces
      next unless group.is_initialized

      group = group.get
      site_transformation = group.buildingTransformation
      site_vertices = site_transformation * surface.vertices
      site_outward_normal = OpenStudio.getOutwardNormal(site_vertices)
      if site_outward_normal.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Space', "Could not compute outward normal for #{surface.name.get}")
        next
      end
      site_outward_normal = site_outward_normal.get
      north = OpenStudio::Vector3d.new(0.0, 1.0, 0.0)
      azimuth = if site_outward_normal.x < 0.0
                  360.0 - OpenStudio.radToDeg(OpenStudio.getAngle(site_outward_normal, north))
                else
                  OpenStudio.radToDeg(OpenStudio.getAngle(site_outward_normal, north))
                end

      # @todo modify to work for buildings in the southern hemisphere?
      if azimuth >= 315.0 || azimuth < 45.0
        facade = '4-North'
      elsif azimuth >= 45.0 && azimuth < 135.0
        facade = '3-East'
      elsif azimuth >= 135.0 && azimuth < 225.0
        facade = '1-South'
      elsif azimuth >= 225.0 && azimuth < 315.0
        facade = '2-West'
      end

      # Label the facade as "Up" if it is a skylight
      if surface_normal.to_s == straight_upward.to_s
        facade = '0-Up'
      end

      # Loop through all subsurfaces and
      surface.subSurfaces.sort.each do |sub_surface|
        next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && (sub_surface.subSurfaceType == 'FixedWindow' || sub_surface.subSurfaceType == 'OperableWindow' || sub_surface.subSurfaceType == 'Skylight')

        # Find the area
        net_area_m2 = sub_surface.netArea

        # Find the head height and sill height of the window
        vertex_heights_above_floor = []
        sub_surface.vertices.each do |vertex|
          vertex_on_floorplane = floor_surface.plane.project(vertex)
          vertex_heights_above_floor << (vertex - vertex_on_floorplane).length
        end
        head_height_m = vertex_heights_above_floor.max
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "---head height = #{head_height_m}m, sill height = #{sill_height_m}m")

        # Log the window properties to use when creating daylight sensors
        properties = { facade: facade, area_m2: net_area_m2, handle: sub_surface.handle, head_height_m: head_height_m, name: sub_surface.name.get.to_s }
        if facade == '0-Up'
          skylights[sub_surface] = properties
        else
          windows[sub_surface] = properties
        end
      end
    end

    # Determine the illuminance setpoint for the controls based on space type
    daylight_stpt_lux = 375

    # find the specific space_type properties
    space_type = space.spaceType
    if space_type.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Space #{space_type} is an unknown space type, assuming #{daylight_stpt_lux} Lux daylight setpoint")
    else
      space_type = space_type.get
      standards_building_type = nil
      standards_space_type = nil
      data = nil
      if space_type.standardsBuildingType.is_initialized
        standards_building_type = space_type.standardsBuildingType.get
      end
      if space_type.standardsSpaceType.is_initialized
        standards_space_type = space_type.standardsSpaceType.get
      end

      unless standards_building_type.nil? || standards_space_type.nil?
        # use the building type (standards_building_type) and space type (standards_space_type)
        # as well as template to locate the space type data
        search_criteria = {
          'template' => template,
          'building_type' => standards_building_type,
          'space_type' => standards_space_type
        }
        data = model_find_object(standards_data['space_types'], search_criteria)
      end

      if standards_building_type.nil? || standards_space_type.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Unable to determine standards building type and standards space type for space '#{space.name}' with space type '#{space_type.name}'. Assign a standards building type and standards space type to the space type object. Defaulting to a #{daylight_stpt_lux} Lux daylight setpoint.")
      elsif data.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Unable to find target illuminance setpoint data for space type '#{space_type.name}' with #{template} space type '#{standards_space_type}' in building type '#{standards_building_type}'. Defaulting to a #{daylight_stpt_lux} Lux daylight setpoint.")
      else
        # Read the illuminance setpoint value
        # If 'na', daylighting is not appropriate for this space type for some reason
        daylight_stpt_lux = data['target_illuminance_setpoint']
        if daylight_stpt_lux == 'na'
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: daylighting is not appropriate for #{template} #{standards_building_type} #{standards_space_type}.")
          return true
        end
        # If a setpoint is specified, use that.  Otherwise use a default.
        daylight_stpt_lux = daylight_stpt_lux.to_f
        if daylight_stpt_lux.zero?
          daylight_stpt_lux = 375
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: no specific illuminance setpoint defined for #{template} #{standards_building_type} #{standards_space_type}, assuming #{daylight_stpt_lux} Lux.")
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: illuminance setpoint = #{daylight_stpt_lux} Lux")
        end
        # for the office prototypes where core and perimeter zoning is used,
        # there are additional assumptions about how much of the daylit area can be used.
        if standards_building_type == 'Office' && standards_space_type.include?('WholeBuilding')
          psa_nongeo_frac = data['psa_nongeometry_fraction'].to_f
          ssa_nongeo_frac = data['ssa_nongeometry_fraction'].to_f
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: assuming only #{(psa_nongeo_frac * 100).round}% of the primary sidelit area is daylightable based on typical design practice.")
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: assuming only #{(ssa_nongeo_frac * 100).round}% of the secondary sidelit area is daylightable based on typical design practice.")
        end
      end
    end

    # Sort by priority; first by facade, then by area,
    # then by name to ensure deterministic in case identical in other ways
    sorted_windows = windows.sort_by { |_window, vals| [vals[:facade], vals[:area], vals[:name]] }
    sorted_skylights = skylights.sort_by { |_skylight, vals| [vals[:facade], vals[:area], vals[:name]] }

    # Report out the sorted skylights for debugging
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, Skylights:")
    sorted_skylights.each do |sky, p|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{sky.name} #{p[:facade]}, area = #{p[:area_m2].round(2)} m^2")
    end

    # Report out the sorted windows for debugging
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, Windows:")
    sorted_windows.each do |win, p|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{win.name} #{p[:facade]}, area = #{p[:area_m2].round(2)} m^2")
    end

    # Determine the sensor fractions and the attached windows
    sensor_1_frac, sensor_2_frac, sensor_1_window, sensor_2_window = space_daylighting_fractions_and_windows(space,
                                                                                                             areas,
                                                                                                             sorted_windows,
                                                                                                             sorted_skylights,
                                                                                                             req_top_ctrl,
                                                                                                             req_pri_ctrl,
                                                                                                             req_sec_ctrl)

    # Further adjust the sensor controlled fraction for the three
    # office prototypes based on assumptions about geometry that is not explicitly
    # defined in the model.
    if standards_building_type == 'Office' && standards_space_type.include?('WholeBuilding')
      sensor_1_frac *= psa_nongeo_frac unless psa_nongeo_frac.nil?
      sensor_2_frac *= ssa_nongeo_frac unless ssa_nongeo_frac.nil?
    end

    # Ensure that total controlled fraction
    # is never set above 1 (100%)
    sensor_1_frac = sensor_1_frac.round(3)
    sensor_2_frac = sensor_2_frac.round(3)
    if sensor_1_frac >= 1.0
      sensor_1_frac = 1.0 - 0.001
    end
    if sensor_1_frac + sensor_2_frac >= 1.0
      # Lower sensor_2_frac so that the total
      # is just slightly lower than 1.0
      sensor_2_frac = 1.0 - sensor_1_frac - 0.001
    end

    # Sensors
    if sensor_1_frac > 0.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: sensor 1 controls #{(sensor_1_frac * 100).round}% of the zone lighting.")
    end
    if sensor_2_frac > 0.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "For #{space.name}: sensor 2 controls #{(sensor_2_frac * 100).round}% of the zone lighting.")
    end

    # First sensor
    if sensor_1_window
      # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "For #{self.name}, calculating daylighted areas.")
      # runner.registerInfo("Daylight sensor 1 inside of #{sensor_1_frac.name}")
      sensor_1 = OpenStudio::Model::DaylightingControl.new(space.model)
      sensor_1.setName("#{space.name} Daylt Sensor 1")
      sensor_1.setSpace(space)
      sensor_1.setIlluminanceSetpoint(daylight_stpt_lux)
      sensor_1.setLightingControlType(space_daylighting_control_type(space))
      sensor_1.setNumberofSteppedControlSteps(3) unless space_daylighting_control_type(space) != 'Stepped' # all sensors 3-step per design
      sensor_1.setMinimumInputPowerFractionforContinuousDimmingControl(space_daylighting_minimum_input_power_fraction(space))
      sensor_1.setMinimumLightOutputFractionforContinuousDimmingControl(0.2)
      sensor_1.setProbabilityLightingwillbeResetWhenNeededinManualSteppedControl(1.0)
      sensor_1.setMaximumAllowableDiscomfortGlareIndex(22.0)

      # Place sensor depending on skylight or window
      sensor_vertex = nil
      if sensor_1_window[1][:facade] == '0-Up'
        sub_surface = sensor_1_window[0]
        outward_normal = sub_surface.outwardNormal
        centroid = OpenStudio.getCentroid(sub_surface.vertices).get
        ht_above_flr = OpenStudio.convert(2.5, 'ft', 'm').get
        outward_normal.setLength(sensor_1_window[1][:head_height_m] - ht_above_flr)
        sensor_vertex = centroid + outward_normal.reverseVector
      else
        sub_surface = sensor_1_window[0]
        window_outward_normal = sub_surface.outwardNormal
        window_centroid = OpenStudio.getCentroid(sub_surface.vertices).get
        window_outward_normal.setLength(sensor_1_window[1][:head_height_m] * 0.66)
        vertex = window_centroid + window_outward_normal.reverseVector
        vertex_on_floorplane = floor_surface.plane.project(vertex)
        floor_outward_normal = floor_surface.outwardNormal
        floor_outward_normal.setLength(OpenStudio.convert(2.5, 'ft', 'm').get)
        sensor_vertex = vertex_on_floorplane + floor_outward_normal.reverseVector
      end
      sensor_1.setPosition(sensor_vertex)

      # @todo rotate sensor to face window (only needed for glare calcs)
      zone.setPrimaryDaylightingControl(sensor_1)
      if zone.fractionofZoneControlledbyPrimaryDaylightingControl + sensor_1_frac > 1
        zone.resetFractionofZoneControlledbySecondaryDaylightingControl
      end
      zone.setFractionofZoneControlledbyPrimaryDaylightingControl(sensor_1_frac)
    end

    # Second sensor
    if sensor_2_window
      # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "For #{self.name}, calculating daylighted areas.")
      # runner.registerInfo("Daylight sensor 2 inside of #{sensor_2_frac.name}")
      sensor_2 = OpenStudio::Model::DaylightingControl.new(space.model)
      sensor_2.setName("#{space.name} Daylt Sensor 2")
      sensor_2.setSpace(space)
      sensor_2.setIlluminanceSetpoint(daylight_stpt_lux)
      sensor_2.setLightingControlType(space_daylighting_control_type(space))
      sensor_2.setNumberofSteppedControlSteps(3) unless space_daylighting_control_type(space) != 'Stepped' # all sensors 3-step per design
      sensor_2.setMinimumInputPowerFractionforContinuousDimmingControl(space_daylighting_minimum_input_power_fraction(space))
      sensor_2.setMinimumLightOutputFractionforContinuousDimmingControl(0.2)
      sensor_2.setProbabilityLightingwillbeResetWhenNeededinManualSteppedControl(1.0)
      sensor_2.setMaximumAllowableDiscomfortGlareIndex(22.0)

      # Place sensor depending on skylight or window
      sensor_vertex = nil
      if sensor_2_window[1][:facade] == '0-Up'
        sub_surface = sensor_2_window[0]
        outward_normal = sub_surface.outwardNormal
        centroid = OpenStudio.getCentroid(sub_surface.vertices).get
        ht_above_flr = OpenStudio.convert(2.5, 'ft', 'm').get
        outward_normal.setLength(sensor_2_window[1][:head_height_m] - ht_above_flr)
        sensor_vertex = centroid + outward_normal.reverseVector
      else
        sub_surface = sensor_2_window[0]
        window_outward_normal = sub_surface.outwardNormal
        window_centroid = OpenStudio.getCentroid(sub_surface.vertices).get
        window_outward_normal.setLength(sensor_2_window[1][:head_height_m] * 1.33)
        vertex = window_centroid + window_outward_normal.reverseVector
        vertex_on_floorplane = floor_surface.plane.project(vertex)
        floor_outward_normal = floor_surface.outwardNormal
        floor_outward_normal.setLength(OpenStudio.convert(2.5, 'ft', 'm').get)
        sensor_vertex = vertex_on_floorplane + floor_outward_normal.reverseVector
      end
      sensor_2.setPosition(sensor_vertex)

      # @todo rotate sensor to face window (only needed for glare calcs)
      zone.setSecondaryDaylightingControl(sensor_2)
      if zone.fractionofZoneControlledbySecondaryDaylightingControl + sensor_2_frac > 1
        zone.resetFractionofZoneControlledbyPrimaryDaylightingControl
      end
      zone.setFractionofZoneControlledbySecondaryDaylightingControl(sensor_2_frac)
    end

    return true
  end

  # Determine if the space requires daylighting controls for
  # toplighting, primary sidelighting, and secondary sidelighting.
  # Defaults to false for all types.
  #
  # @param space [OpenStudio::Model::Space] the space in question
  # @param areas [Hash] a hash of daylighted areas
  # @return [Array<Bool>] req_top_ctrl, req_pri_ctrl, req_sec_ctrl
  def space_daylighting_control_required?(space, areas)
    req_top_ctrl = false
    req_pri_ctrl = false
    req_sec_ctrl = false

    return [req_top_ctrl, req_pri_ctrl, req_sec_ctrl]
  end

  # Determine the fraction controlled by each sensor and which window each sensor should go near.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param areas [Hash] a hash of daylighted areas
  # @param sorted_windows [Hash] a hash of windows, sorted by priority
  # @param sorted_skylights [Hash] a hash of skylights, sorted by priority
  # @param req_top_ctrl [Boolean] if toplighting controls are required
  # @param req_pri_ctrl [Boolean] if primary sidelighting controls are required
  # @param req_sec_ctrl [Boolean] if secondary sidelighting controls are required
  # @return [Array] array of 4 items
  #   [sensor 1 fraction, sensor 2 fraction, sensor 1 window, sensor 2 window]
  def space_daylighting_fractions_and_windows(space,
                                              areas,
                                              sorted_windows,
                                              sorted_skylights,
                                              req_top_ctrl,
                                              req_pri_ctrl,
                                              req_sec_ctrl)
    sensor_1_frac = 0.0
    sensor_2_frac = 0.0
    sensor_1_window = nil
    sensor_2_window = nil

    return [sensor_1_frac, sensor_2_frac, sensor_1_window, sensor_2_window]
  end

  # Determines whether the space is conditioned per 90.1, which is based on heating and cooling loads.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @return [String] NonResConditioned, ResConditioned, Semiheated, Unconditioned
  # @todo add logic to detect indirectly-conditioned spaces based on air transfer
  def space_conditioning_category(space)
    # Return space conditioning category if already assigned as an additional properties
    return space.additionalProperties.getFeatureAsString('space_conditioning_category').get if space.additionalProperties.hasFeature('space_conditioning_category')

    # Get climate zone
    climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(space.model)
    if climate_zone.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Space', 'Model has no climate zone assigned, cannot determine space conditioning category.')
    end

    # Get the zone this space is inside
    zone = space.thermalZone

    # Assume unconditioned if not assigned to a zone
    if zone.empty?
      return 'Unconditioned'
    end

    # Return air plenums are indirectly conditioned spaces according to the
    # 90.1-2019 Performance Rating Method Reference Manual
    # #
    # Additionally, Section 2 of ASHRAE 90.1 states that indirectly
    # conditioned spaces are unconditioned spaces that are adjacent to
    # heated or cooled spaced and provided that air from these spaces is
    # intentionally transferred into the space at a rate exceeding 3 ach
    # which most if not all return air plenum do.
    space.model.getAirLoopHVACReturnPlenums.each do |return_air_plenum|
      if return_air_plenum.thermalZone.get.name.to_s == zone.get.name.to_s
        # Determine if residential
        res = OpenstudioStandards::ThermalZone.thermal_zone_residential?(zone.get)

        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "Zone #{zone.get.name} is (indirectly) conditioned (return air plenum).")
        cond_cat = res ? 'ResConditioned' : 'NonResConditioned'

        return cond_cat
      end
    end
    # Following the same assumptions,  we designate supply air plenums
    # as indirectly conditioned as well
    space.model.getAirLoopHVACSupplyPlenums.each do |supply_air_plenum|
      if supply_air_plenum.thermalZone.get.name.to_s == zone.get.name.to_s
        # Determine if residential
        res = OpenstudioStandards::ThermalZone.thermal_zone_residential?(zone.get)

        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "Zone #{zone.get.name} is (indirectly) conditioned (supply air plenum).")
        cond_cat = res ? 'ResConditioned' : 'NonResConditioned'

        return cond_cat
      end
    end

    # Get the category from the zone, this methods does NOT detect indirectly
    # conditioned spaces
    cond_cat = thermal_zone_conditioning_category(zone.get, climate_zone)

    # Detect indirectly conditioned spaces based on UA sum product comparison
    if cond_cat == 'Unconditioned'

      # Initialize UA sum product for surfaces adjacent to conditioned spaces
      cond_ua = 0

      # Initialize UA sum product for surfaces adjacent to unconditoned spaces,
      # semi-heated spaces and outdoors
      otr_ua = 0

      space.surfaces.sort.each do |surface|
        # Surfaces adjacent to other surfaces can be next to conditioned,
        # unconditioned or semi-heated spaces
        if surface.outsideBoundaryCondition == 'Surface'

          # Retrieve adjacent space conditioning category
          adj_space = surface.adjacentSurface.get.space.get
          adj_zone = adj_space.thermalZone.get
          adj_space_cond_type = thermal_zone_conditioning_category(adj_zone, climate_zone)

          # adj_zone == zone.get means that the surface is adjacent to its zone
          # This is translated by an adiabtic outside boundary condition, which are
          # assumed to be used only if the surface is adjacent to a conditioned space
          if adj_space_cond_type == 'ResConditioned' || adj_space_cond_type == 'NonResConditioned' || adj_zone == zone.get
            cond_ua += surface_subsurface_ua(surface)
          else
            otr_ua += surface_subsurface_ua(surface)
          end

        # Adiabtic outside boundary condition are assumed to be used only if the
        # surface is adjacent to a conditioned space
        elsif surface.outsideBoundaryCondition == 'Adiabatic'

          # If the surface is a floor and is located at the lowest floor of the
          # building it is assumed to be adjacent to an unconditioned space
          # (i.e. ground)
          if surface.surfaceType == 'Floor' && surface.space.get.buildingStory == find_lowest_story(surface.model)
            otr_ua += surface_subsurface_ua(surface)
          else
            cond_ua += surface_subsurface_ua(surface)
          end

        # All other outside boundary conditions are assumed to be adjacent to either:
        # outdoors or ground and hence count towards the unconditioned UA product
        else
          otr_ua += surface_subsurface_ua(surface)
        end
      end

      # Determine if residential
      res = OpenstudioStandards::ThermalZone.thermal_zone_residential?(zone.get)

      return cond_cat unless cond_ua > otr_ua

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.ThermalZone', "Zone #{zone.get.name} is (indirectly) conditioned because its conditioned UA product (#{cond_ua.round} W/K) exceeds its non-conditioned UA product (#{otr_ua.round} W/K).")
      cond_cat = res ? 'ResConditioned' : 'NonResConditioned'
    end

    return cond_cat
  end

  # Create annual array of occupancy for the space: 1 = occupied, 0 = unoccupied
  # @author Doug Maddox, PNNL
  # @param space object
  # @return [Double] 8760 array of the occupancy flag
  def space_occupancy_annual_array(model, space)
    occ_sch_values = nil
    ppl_values = Array.new(8760, 0)

    # Need to review all people objects in this space
    space_name = space.name.get
    space_type_name = space.spaceType.get.name.get
    people_objs = []
    model.getPeoples.sort.each do |people|
      parent_obj = people.parent.get.iddObjectType.valueName.to_s
      if parent_obj == 'OS_Space'
        # This object is associated with a single space
        # Check if it is the current space
        if space_name == people.space.get.name.get
          people_objs << people
        end
      elsif parent_obj == 'OS_SpaceType'
        # This object is associated with a space type
        # Check if it is the current space type
        if space_type_name == people.spaceType.get.name.get
          people_objs << people
        end
      end
    end

    unoccupied_threshold = air_loop_hvac_unoccupied_threshold
    people_objs.each do |people|
      occ_sch = people.numberofPeopleSchedule
      if occ_sch.is_initialized
        occ_sch_obj = occ_sch.get
        occ_sch_values = OpenstudioStandards::Schedules.schedule_get_hourly_values(occ_sch_obj)
        # Flag = 1 if any schedule shows occupancy for a given hour
        if !occ_sch_values.nil?
          (0..8759).each do |ihr|
            ppl_values[ihr] = 1 if occ_sch_values[ihr] >= unoccupied_threshold
          end
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Failed to retrieve people schedule for #{space.name}.  Assuming #{w_per_person}W/person.")
        end
      end
    end

    return ppl_values
  end

  # Determine the design internal gain (W) for
  # this space without space multipliers.
  # This includes People, Lights, Electric Equipment, and Gas Equipment.
  # This version accounts for operating schedules
  # and fraction lost for equipment
  # @author Doug Maddox, PNNL
  # @param space object
  # @param return_noncoincident_value [Boolean] if true, return value is noncoincident peak; if false, return is array off coincident load
  # @return [Double] 8760 array of the design internal load, in W, for this space
  def space_internal_load_annual_array(model, space, return_noncoincident_value)
    # For each type of load, first convert schedules to 8760 arrays so coincident load can be determined
    ppl_values = Array.new(8760, 0)
    ltg_values = Array.new(8760, 0)
    load_values = Array.new(8760, 0)
    noncoincident_peak_load = 0
    space_name = space.name.get
    space_type_name = space.spaceType.get.name.get

    # People
    # Make list of people objects for this space
    # Including those associated with space directly and those associated with space type
    ppl_total = 0
    people_objs = []
    model.getPeoples.sort.each do |people|
      parent_obj = people.parent.get.iddObjectType.valueName.to_s
      if parent_obj == 'OS_Space'
        # This object is associated with a single space
        # Check if it is the current space
        if space_name == people.space.get.name.get
          people_objs << people
        end
      elsif parent_obj == 'OS_SpaceType'
        # This object is associated with a space type
        # Check if it is the current space type
        if space_type_name == people.spaceType.get.name.get
          people_objs << people
        end
      end
    end

    people_objs.each do |people|
      w_per_person = 125 # Initial assumption
      occ_sch_max = 1
      act_sch = people.activityLevelSchedule
      if people.isActivityLevelScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.peopleActivityLevelSchedule.empty?
            act_sch = space.spaceType.get.defaultScheduleSet.get.peopleActivityLevelSchedule
          end
        end
      end
      if act_sch.is_initialized
        act_sch_obj = act_sch.get
        act_sch_values = OpenstudioStandards::Schedules.schedule_get_hourly_values(act_sch_obj)
        if !act_sch_values.nil?
          w_per_person = act_sch_values.max
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Failed to retrieve people activity schedule for #{space.name}.  Assuming #{w_per_person}W/person.")
        end
      end

      occ_sch_ruleset = nil
      occ_sch = people.numberofPeopleSchedule
      if people.isNumberofPeopleScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule.empty?
            occ_sch = space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule
          end
        end
      end
      if occ_sch.is_initialized
        occ_sch_obj = occ_sch.get
        occ_sch_values = OpenstudioStandards::Schedules.schedule_get_hourly_values(occ_sch_obj)
        if !occ_sch_max.nil?
          occ_sch_max = occ_sch_values.max
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Failed to retrieve people schedule for #{space.name}.  Assuming #{w_per_person}W/person.")
        end
      end

      num_ppl = people.getNumberOfPeople(space.floorArea)
      ppl_total += num_ppl

      act_sch_value = w_per_person
      occ_sch_value = occ_sch_max
      (0..8759).each do |ihr|
        act_sch_value = act_sch_values[ihr] unless act_sch_values.nil?
        occ_sch_value = occ_sch_values[ihr] unless occ_sch_values.nil?
        ppl_values[ihr] += num_ppl * act_sch_value * occ_sch_value
      end
    end

    # Make list of lights objects for this space
    # Including those associated with space directly and those associated with space type
    # Note: in EnergyPlus, Lights are associated with zone or zonelist
    # In OS, they are associated with space or space type
    light_objs = []
    model.getLightss.sort.each do |light|
      parent_obj = light.parent.get.iddObjectType.valueName.to_s
      if parent_obj == 'OS_Space'
        # This object is associated with a single space
        # Check if it is the current space
        if space_name == light.space.get.name.get
          light_objs << light
        end
      elsif parent_obj == 'OS_SpaceType'
        # This object is associated with a space type
        # Check if it is the current space type
        if space_type_name == light.spaceType.get.name.get
          light_objs << light
        end
      end
    end

    light_objs.each do |light|
      ltg_sch_ruleset = nil
      ltg_sch = light.schedule
      ltg_w = light.getLightingPower(space.floorArea, ppl_total)

      if light.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.lightingSchedule.empty?
            ltg_sch = space.spaceType.get.defaultScheduleSet.get.lightingSchedule
          end
        end
      end
      if ltg_sch.is_initialized
        ltg_sch_obj = ltg_sch.get
        ltg_sch_values = OpenstudioStandards::Schedules.schedule_get_hourly_values(ltg_sch_obj)
        if !ltg_sch_values.nil?
          ltg_sch_max = ltg_sch_values.max
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Failed to retreive lighting schedule for #{space.name}.  Assuming #{ltg_w} W.")
        end
      end

      if !ltg_sch_values.nil?
        ltg_sch_value = 1.0
        (0..8759).each do |ihr|
          ltg_sch_value = ltg_sch_values[ihr] unless ltg_sch_ruleset.nil?
          ltg_values[ihr] += ltg_w * ltg_sch_value
        end
      end
    end

    # Luminaire Objects
    space.spaceType.get.luminaires.each do |light|
      ltg_sch_values = nil
      ltg_sch = light.schedule
      ltg_w = light.lightingPower(space.floorArea, ppl_total)
      # not sure if above line is valid, so calculate from parts instead until above can be verified
      ltg_w = light.getPowerPerFloorArea(space.floorArea) * space.floorArea
      ltg_w += light.getPowerPerPerson(ppl_total) * ppl_total

      if light.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.lightingSchedule.empty?
            ltg_sch = space.spaceType.get.defaultScheduleSet.get.lightingSchedule
          end
        end
      end
      if ltg_sch.is_initialized
        ltg_sch_obj = ltg_sch.get
        ltg_sch_values = OpenstudioStandards::Schedules.schedule_get_hourly_values(ltg_sch_obj)
        if !ltg_sch_values.nil?
          ltg_sch_max = ltg_sch_values.max
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Failed to retreive lighting schedule for luminaires for #{space.name}.  Assuming #{ltg_w} W.")
        end
      end

      if !ltg_sch_values.nil?
        ltg_sch_value = 1.0
        (0..8759).each do |ihr|
          ltg_sch_value = ltg_sch_values[ihr] unless ltg_sch_ruleset.nil?
          ltg_values[ihr] += ltg_w * ltg_sch_value
        end
      end
    end

    # Equipment Loads
    eqp_type = 'electric equipment'
    equips = model.getElectricEquipments
    load_values = space_get_loads_for_all_equips(model, space, equips, eqp_type, ppl_total, load_values, return_noncoincident_value)

    eqp_type = 'gas equipment'
    equips = model.getGasEquipments
    load_values = space_get_loads_for_all_equips(model, space, equips, eqp_type, ppl_total, load_values, return_noncoincident_value)

    eqp_type = 'steam equipment'
    equips = model.getSteamEquipments
    load_values = space_get_loads_for_all_equips(model, space, equips, eqp_type, ppl_total, load_values, return_noncoincident_value)

    eqp_type = 'hot water equipment'
    equips = model.getHotWaterEquipments
    load_values = space_get_loads_for_all_equips(model, space, equips, eqp_type, ppl_total, load_values, return_noncoincident_value)

    eqp_type = 'other equipment'
    equips = model.getOtherEquipments
    load_values = space_get_loads_for_all_equips(model, space, equips, eqp_type, ppl_total, load_values, return_noncoincident_value)

    # Add lighting and people to the load values array
    if return_noncoincident_value
      noncoincident_peak_load = load_values[0] + ppl_values.max + ltg_values.max
      return noncoincident_peak_load
    else
      (0..8759).each do |ihr|
        load_values[ihr] += ppl_values[ihr] + ltg_values[ihr]
      end
      return load_values
    end
  end

  # Loops through a set of equipment objects of one type
  # For each applicable equipment object, call method to get annual gain values
  # This is useful for the Appendix G test for multizone systems
  # to determine whether specific zones should be isolated to PSZ based on
  # space loads that differ significantly from other zones on the multizone system
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param space [OpenStudio::Model::Space] the space
  # @param equips [object] This is an array of equipment objects in the model
  # @param eqp_type [String] string description of the type of equipment object
  # @param ppl_total [Numeric] total number of people in the space
  # @param load_values [Array] 8760 array of load values for the equipment type
  # @param return_noncoincident_value [Boolean] return a single peak value if true; return 8760 gain profile if false
  # @return [Array] load values array; if return_noncoincident_value is true, array has only one value
  def space_get_loads_for_all_equips(model, space, equips, eqp_type, ppl_total, load_values, return_noncoincident_value)
    space_name = space.name.get
    space_type_name = space.spaceType.get.name.get
    equips.sort.each do |equip|
      parent_obj = equip.parent.get.iddObjectType.valueName.to_s
      if parent_obj == 'OS_Space'
        # This object is associated with a single space
        # Check if it is the current space
        if space_name == equip.space.get.name.get
          euip_name = equip.name.get
          load_values = space_get_equip_annual_array(model, space, equip, eqp_type, ppl_total, load_values, return_noncoincident_value)
        end
      elsif parent_obj == 'OS_SpaceType'
        # This object is associated with a space type
        # Check if it is the current space type
        if space_type_name == equip.spaceType.get.name.get
          load_values = space_get_equip_annual_array(model, space, equip, eqp_type, ppl_total, load_values, return_noncoincident_value)
        end
      end
    end
    return load_values
  end

  # Returns an 8760 array of load values for a specific type of load in a space.
  # This is useful for the Appendix G test for multizone systems
  # to determine whether specific zones should be isolated to PSZ based on
  # space loads that differ significantly from other zones on the multizone system
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param space [OpenStudio::Model::Space] the space
  # @param equip [object] This can be any type of equipment object in the space
  # @param eqp_type [String] string description of the type of equipment object
  # @param ppl_total [Numeric] total number of people in the space
  # @param load_values [Array] 8760 array of load values for the equipment type
  # @param return_noncoincident_value [Boolean] return a single peak value if true; return 8760 gain profile if false
  # @return [Array] load values array; if return_noncoincident_value is true, array has only one value
  def space_get_equip_annual_array(model, space, equip, eqp_type, ppl_total, load_values, return_noncoincident_value)
    # Get load schedule and load lost value depending on equipment type
    case eqp_type
    when 'electric equipment'
      load_sch = equip.schedule
      load_lost = equip.electricEquipmentDefinition.fractionLost # eqp-type-specific
      load_w = equip.getDesignLevel(space.floorArea, ppl_total) * (1 - load_lost)

      if equip.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.electricEquipmentSchedule.empty? # eqp-type-specific
            load_sch = space.spaceType.get.defaultScheduleSet.get.electricEquipmentSchedule # eqp-type-specific
          end
        end
      end
    when 'gas equipment'
      load_sch = equip.schedule
      load_lost = equip.gasEquipmentDefinition.fractionLost # eqp-type-specific
      load_w = equip.getDesignLevel(space.floorArea, ppl_total) * (1 - load_lost)

      if equip.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.gasEquipmentSchedule.empty? # eqp-type-specific
            load_sch = space.spaceType.get.defaultScheduleSet.get.gasEquipmentSchedule # eqp-type-specific
          end
        end
      end
    when 'steam equipment'
      load_sch = equip.schedule
      load_lost = equip.steamEquipmentDefinition.fractionLost # eqp-type-specific
      load_w = equip.getDesignLevel(space.floorArea, ppl_total) * (1 - load_lost)

      if equip.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.steamEquipmentSchedule.empty? # eqp-type-specific
            load_sch = space.spaceType.get.defaultScheduleSet.get.steamEquipmentSchedule # eqp-type-specific
          end
        end
      end
    when 'hot water equipment'
      load_sch = equip.schedule
      load_lost = equip.hotWaterEquipmentDefinition.fractionLost # eqp-type-specific
      load_w = equip.getDesignLevel(space.floorArea, ppl_total) * (1 - load_lost)

      if equip.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.hotWaterEquipmentSchedule.empty? # eqp-type-specific
            load_sch = space.spaceType.get.defaultScheduleSet.get.hotWaterEquipmentSchedule # eqp-type-specific
          end
        end
      end
    when 'other equipment'
      load_sch = equip.schedule
      load_lost = equip.otherEquipmentDefinition.fractionLost # eqp-type-specific
      load_w = equip.getDesignLevel(space.floorArea, ppl_total) * (1 - load_lost)

      if equip.isScheduleDefaulted
        # Check default schedule set
        unless space.spaceType.get.defaultScheduleSet.empty?
          unless space.spaceType.get.defaultScheduleSet.get.otherEquipmentSchedule.empty? # eqp-type-specific
            load_sch = space.spaceType.get.defaultScheduleSet.get.otherEquipmentSchedule # eqp-type-specific
          end
        end
      end
    end

    load_sch_ruleset = nil
    if load_sch.is_initialized
      load_sch_obj = load_sch.get
      load_sch_values = OpenstudioStandards::Schedules.schedule_get_hourly_values(load_sch_obj)
      if !load_sch_values.nil?
        load_sch_max = load_sch_values.max
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Failed to retreive schedule for equipment type #{eqp_type} in space #{space.name}.  Assuming #{load_w} W.")
      end
    end

    if return_noncoincident_value
      load_values[0] += load_w * load_sch_values.max
    else
      if !load_sch_values.nil?
        load_sch_value = 1.0
        (0..8759).each do |ihr|
          load_sch_value = load_sch_values[ihr]
          load_values[ihr] += load_w * load_sch_value
        end
      end
    end
    return load_values
  end

  private

  # A series of private methods to modify polygons.
  # Most are wrappers of native OpenStudio methods, but with workarounds for known issues or limitations.

  # Check the z coordinates of a polygon
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param polygons [Array<Array>] Array of array of vertices (polygons)
  # @param name [String] name of polygons
  # @return [Integer] return number of errors
  # @api private
  def space_check_z_zero(space, polygons, name)
    fails = []
    errs = 0
    polygons.each do |polygon|
      # OpenStudio::logFree(OpenStudio::Error, "openstudio.standards.Space", "Checking z=0: #{name} is greater than or equal to #{polygon.to_s.gsub(/\[|\]/,'|')}.")
      polygon.each do |vertex|
        # clsss << vertex.class
        unless vertex.z == 0.0
          errs += 1
          fails << vertex.z
        end
      end
    end
    # OpenStudio::logFree(OpenStudio::Error, "openstudio.standards.Space", "Checking z=0: #{name} is greater than or equal to #{clsss.uniq.to_s.gsub(/\[|\]/,'|')}.")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space', "***FAIL*** #{space.name} z=0 failed for #{errs} vertices in #{name}; #{fails.join(', ')}.") if errs > 0
    return errs
  end

  # A method to convert an array of arrays to an array of OpenStudio::Point3ds.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param ruby_polygons [Array<Array>] Array of array of vertices (polygons)
  # @return [Array<Array>] Array of array of Point3D objects (polygons)
  # @api private
  def space_ruby_polygons_to_point3d_z_zero(space, ruby_polygons)
    # Convert the final polygons back to OpenStudio
    os_polygons = []
    ruby_polygons.each do |ruby_polygon|
      os_polygon = []
      ruby_polygon.each do |vertex|
        vertex = OpenStudio::Point3d.new(vertex[0], vertex[1], 0.0) # Set z to hard-zero instead of vertex[2]
        os_polygon << vertex
      end
      os_polygons << os_polygon
    end

    return os_polygons
  end

  # A method to zero-out the z vertex of an array of polygons
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param polygons [Array<Array>] Array of array of vertices (polygons)
  # @param new_z [Double] new z value in meters
  # @return [Array<Array>] Array of array of Point3D objects (polygons)
  # @api private
  def space_polygons_set_z(space, polygons, new_z)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "### #{polygons}")

    # Convert the final polygons back to OpenStudio
    new_polygons = []
    polygons.each do |polygon|
      new_polygon = []
      polygon.each do |vertex|
        new_vertex = OpenStudio::Point3d.new(vertex.x, vertex.y, new_z) # Set z to hard-zero instead of vertex[2]
        new_polygon << new_vertex
      end
      new_polygons << new_polygon
    end

    return new_polygons
  end

  # A method to returns the number of duplicate vertices in a polygon.
  # @todo does not actually work
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param ruby_polygon [Array] array of vertices (polygon)
  # @param tol [Double] tolerance
  # @return [Array] array of duplicates
  # @api private
  def space_find_duplicate_vertices(space, ruby_polygon, tol = 0.001)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '***')
    duplicates = []

    combos = ruby_polygon.combination(2).to_a
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "########{combos.size}")
    combos.each do |i, j|
      i_vertex = OpenStudio::Point3d.new(i[0], i[1], i[2])
      j_vertex = OpenStudio::Point3d.new(j[0], j[1], j[2])

      distance = OpenStudio.getDistance(i_vertex, j_vertex)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "------- #{i} to #{j} = #{distance}")
      if distance < tol
        duplicates << i
      end
    end

    return duplicates
  end

  # Subtracts one array of polygons from the next, returning an array of resulting polygons.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param a_polygons [Array<Array>] Array of array of vertices (polygons)
  # @param b_polygons [Array<Array>] Array of array of vertices (polygons)
  # @param a_name [String] name of a polygons
  # @param b_name [String] name of b polygons
  # @return [Array<Array>] Array of array of vertices (polygons)
  # @api private
  def space_a_polygons_minus_b_polygons(space, a_polygons, b_polygons, a_name, b_name)
    final_polygons_ruby = []

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "#{a_polygons.size} #{a_name} minus #{b_polygons.size} #{b_name}")

    # Don't try to subtract anything if either set is empty
    if a_polygons.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{a_name} - #{b_name}: #{a_name} contains no polygons.")
      return space_polygons_set_z(space, a_polygons, 0.0)
    elsif b_polygons.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{a_name} - #{b_name}: #{b_name} contains no polygons.")
      return space_polygons_set_z(space, a_polygons, 0.0)
    end

    # Loop through all a polygons, and for each one,
    # subtract all the b polygons.
    a_polygons.each do |a_polygon|
      # Translate the polygon to plain arrays
      a_polygon_ruby = []
      a_polygon.each do |vertex|
        a_polygon_ruby << [vertex.x, vertex.y, vertex.z]
      end

      # @todo Skip really small polygons
      # reduced_b_polygons = []
      # b_polygons.each do |b_polygon|
      # next
      # end

      # Perform the subtraction
      a_minus_b_polygons = OpenStudio.subtract(a_polygon, b_polygons, 0.01)

      # Translate the resulting polygons to plain ruby arrays
      a_minus_b_polygons_ruby = []
      num_small_polygons = 0
      a_minus_b_polygons.each do |a_minus_b_polygon|
        # Drop any super small or zero-vertex polygons resulting from the subtraction
        area = OpenStudio.getArea(a_minus_b_polygon)
        if area.is_initialized
          if area.get < 0.5 # 5 square feet
            num_small_polygons += 1
            next
          end
        else
          num_small_polygons += 1
          next
        end

        # Translate polygon to ruby array
        a_minus_b_polygon_ruby = []
        a_minus_b_polygon.each do |vertex|
          a_minus_b_polygon_ruby << [vertex.x, vertex.y, vertex.z]
        end

        a_minus_b_polygons_ruby << a_minus_b_polygon_ruby
      end

      if num_small_polygons > 0
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---Dropped #{num_small_polygons} small or invalid polygons resulting from subtraction.")
      end

      # Remove duplicate polygons
      unique_a_minus_b_polygons_ruby = a_minus_b_polygons_ruby.uniq

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---Remove duplicates: #{a_minus_b_polygons_ruby.size} to #{unique_a_minus_b_polygons_ruby.size}")

      # @todo bug workaround?
      # If the result includes the a polygon, the a polygon
      # was unchanged; only include that polgon and throw away the other junk?/bug? polygons.
      # If the result does not include the a polygon, the a polygon was
      # split into multiple pieces.  Keep all those pieces.
      if unique_a_minus_b_polygons_ruby.include?(a_polygon_ruby)
        if unique_a_minus_b_polygons_ruby.size == 1
          final_polygons_ruby.concat([a_polygon_ruby])
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '---includes only original polygon, keeping that one')
        else
          # Remove the original polygon
          unique_a_minus_b_polygons_ruby.delete(a_polygon_ruby)
          final_polygons_ruby.concat(unique_a_minus_b_polygons_ruby)
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '---includes the original and others; keeping all other polygons')
        end
      else
        final_polygons_ruby.concat(unique_a_minus_b_polygons_ruby)
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '---does not include original, keeping all resulting polygons')
      end
    end

    # Remove duplicate polygons again
    unique_final_polygons_ruby = final_polygons_ruby.uniq

    # @todo remove this workaround
    # Split any polygons that are joined by a line into two separate
    # polygons.  Do this by finding duplicate
    # unique_final_polygons_ruby.each do |unique_final_polygon_ruby|
    # next if unique_final_polygon_ruby.size == 4 # Don't check 4-sided polygons
    # dupes = space_find_duplicate_vertices(space, unique_final_polygon_ruby)
    # if dupes.size > 0
    # OpenStudio::logFree(OpenStudio::Error, "openstudio.standards.Space", "---Two polygons attached by line = #{unique_final_polygon_ruby.to_s.gsub(/\[|\]/,'|')}")
    # end
    # end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---Remove final duplicates: #{final_polygons_ruby.size} to #{unique_final_polygons_ruby.size}")

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{a_name} minus #{b_name} = #{unique_final_polygons_ruby.size} polygons.")

    # Convert the final polygons back to OpenStudio
    unique_final_polygons = space_ruby_polygons_to_point3d_z_zero(space, unique_final_polygons_ruby)

    return unique_final_polygons
  end

  # Wrapper to catch errors in joinAll method
  # [utilities.geometry.joinAll] <1> Expected polygons to join together
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param polygons [Array] array of vertices (polygon)
  # @param tol [Double] tolerance
  # @param name [String] name of polygons
  # @return [Array<Array>] Array of array of vertices (polygons)
  # @api private
  def space_join_polygons(space, polygons, tol, name)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "Joining #{name} from #{space.name}")

    combined_polygons = []

    # Don't try to combine an empty array of polygons
    if polygons.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{name} contains no polygons, not combining.")
      return combined_polygons
    end

    # Open a log
    msg_log = OpenStudio::StringStreamLogSink.new
    msg_log.setLogLevel(OpenStudio::Info)

    # Combine the polygons
    combined_polygons = OpenStudio.joinAll(polygons, 0.01)

    # Count logged errors
    join_errs = 0
    inner_loop_errs = 0
    msg_log.logMessages.each do |msg|
      if /utilities.geometry/ =~ msg.logChannel
        if msg.logMessage.include?('Expected polygons to join together')
          join_errs += 1
        elsif msg.logMessage.include?('Union has inner loops')
          inner_loop_errs += 1
        end
      end
    end

    # Disable the log sink to prevent memory hogging
    msg_log.disable

    # @todo remove this workaround, which is tried if there
    # are any join errors.  This handles the case of polygons
    # that make an inner loop, the most common case being
    # when all 4 sides of a space have windows.
    # If an error occurs, attempt to join n-1 polygons,
    # then subtract the
    if join_errs > 0 || inner_loop_errs > 0

      # Open a log
      msg_log_2 = OpenStudio::StringStreamLogSink.new
      msg_log_2.setLogLevel(OpenStudio::Info)

      first_polygon = polygons.first
      polygons = polygons.drop(1)

      combined_polygons_2 = OpenStudio.joinAll(polygons, 0.01)

      join_errs_2 = 0
      inner_loop_errs_2 = 0
      msg_log_2.logMessages.each do |msg|
        if /utilities.geometry/ =~ msg.logChannel
          if msg.logMessage.include?('Expected polygons to join together')
            join_errs_2 += 1
          elsif msg.logMessage.include?('Union has inner loops')
            inner_loop_errs_2 += 1
          end
        end
      end

      # Disable the log sink to prevent memory hogging
      msg_log_2.disable

      if join_errs_2 > 0 || inner_loop_errs_2 > 0
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, the workaround for joining polygons failed.")
      else

        # First polygon minus the already combined polygons
        first_polygon_minus_combined = space_a_polygons_minus_b_polygons(space, [first_polygon], combined_polygons_2, 'first_polygon', 'combined_polygons_2')

        # Add the result back
        combined_polygons_2 += first_polygon_minus_combined
        combined_polygons = combined_polygons_2
        join_errs = 0
        inner_loop_errs = 0

      end
    end

    # Report logged errors to user
    if join_errs > 0
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, #{join_errs} of #{polygons.size} #{space.name} were not joined properly due to limitations of the geometry calculation methods.  The resulting daylighted areas will be smaller than they should be.")
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "For #{space.name}, the #{name.gsub('_polygons', '')} daylight area calculations hit limitations.  Double-check and possibly correct the fraction of lights controlled by each daylight sensor.")
    end
    if inner_loop_errs > 0
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, #{inner_loop_errs} of #{polygons.size} #{space.name} were not joined properly because the joined polygons have an internal hole.  The resulting daylighted areas will be smaller than they should be.")
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "For #{space.name}, the #{name.gsub('_polygons', '')} daylight area calculations hit limitations.  Double-check and possibly correct the fraction of lights controlled by each daylight sensor.")
    end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---Joined #{polygons.size} #{space.name} into #{combined_polygons.size} polygons.")

    return combined_polygons
  end

  # Gets the total area of a series of polygons
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param polygons [Array] array of vertices (polygon)
  # @return [Double] area in meters
  # @api private
  def space_total_area_of_polygons(space, polygons)
    total_area_m2 = 0
    polygons.each do |polygon|
      area_m2 = OpenStudio.getArea(polygon)
      if area_m2.is_initialized
        total_area_m2 += area_m2.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Could not get area for a polygon in #{space.name}, daylighted area calculation will not be accurate.")
      end
    end

    return total_area_m2
  end

  # Returns an array of resulting polygons.
  # Assumes that a_polygons don't overlap one another, and that b_polygons don't overlap one another
  #
  # @param a_polygons [Array<Array>] Array of array of vertices (polygons)
  # @param b_polygons [Array<Array>] Array of array of vertices (polygons)
  # @param a_name [String] name of a polygons
  # @param b_name [String] name of b polygons
  # @return [Double] overlapping area in meters
  # @api private
  def space_area_a_polygons_overlap_b_polygons(space, a_polygons, b_polygons, a_name, b_name)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "#{a_polygons.size} #{a_name} overlaps #{b_polygons.size} #{b_name}")

    overlap_area = 0

    # Don't try anything if either set is empty
    if a_polygons.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{a_name} overlaps #{b_name}: #{a_name} contains no polygons.")
      return overlap_area
    elsif b_polygons.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "---#{a_name} overlaps #{b_name}: #{b_name} contains no polygons.")
      return overlap_area
    end

    # Loop through each base surface
    b_polygons.each do |b_polygon|
      # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "---b polygon = #{b_polygon_ruby.to_s.gsub(/\[|\]/,'|')}")

      # Loop through each overlap surface and determine if it overlaps this base surface
      a_polygons.each do |a_polygon|
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "------a polygon = #{a_polygon_ruby.to_s.gsub(/\[|\]/,'|')}")

        # If the entire a polygon is within the b polygon, count 100% of the area
        # as overlapping and remove a polygon from the list
        if OpenStudio.within(a_polygon, b_polygon, 0.01)

          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '---------a overlaps b ENTIRELY.')

          area = OpenStudio.getArea(a_polygon)
          if area.is_initialized
            overlap_area += area.get
            next
          else
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "Could not determine the area of #{a_polygon.to_s.gsub(/\[|\]/, '|')} in #{a_name}; #{a_name} overlaps #{b_name}.")
          end

          # If part of a polygon overlaps b polygon, determine the
          # original area of polygon b, subtract polygon a from b,
          # then add the difference in area to the total.
        elsif OpenStudio.intersects(a_polygon, b_polygon, 0.01)

          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '---------a overlaps b PARTIALLY.')

          # Get the initial area
          area_initial = 0
          area = OpenStudio.getArea(b_polygon)
          if area.is_initialized
            area_initial = area.get
          else
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "Could not determine the area of #{a_polygon.to_s.gsub(/\[|\]/, '|')} in #{a_name}; #{a_name} overlaps #{b_name}.")
          end

          # Perform the subtraction
          b_minus_a_polygons = OpenStudio.subtract(b_polygon, [a_polygon], 0.01)

          # Get the final area
          area_final = 0
          b_minus_a_polygons.each do |polygon|
            # Skip polygons that have no vertices
            # resulting from the subtraction.
            if polygon.empty?
              OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "Zero-vertex polygon resulting from #{b_polygon.to_s.gsub(/\[|\]/, '|')} minus #{a_polygon.to_s.gsub(/\[|\]/, '|')}.")
              next
            end
            # Find the area of real polygons
            area = OpenStudio.getArea(polygon)
            if area.is_initialized
              area_final += area.get
            else
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Could not determine the area of #{polygon.to_s.gsub(/\[|\]/, '|')} in #{a_name}; #{a_name} overlaps #{b_name}.")
            end
          end

          # Add the diference to the total
          overlap_area += (area_initial - area_final)

          # There is no overlap
        else

          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', '---------a does not overlaps b at all.')

        end
      end
    end

    return overlap_area
  end

  # A function to check whether a space is a return / supply plenum.
  # This function only works on spaces used as a AirLoopSupplyPlenum or AirLoopReturnPlenum
  # @param space [OpenStudio::Model::Space]
  # @return [Boolean] true if it is plenum, else false.
  def space_is_plenum(space)
    # Get the zone this space is inside
    zone = space.thermalZone
    # the zone is a return air plenum
    space.model.getAirLoopHVACReturnPlenums.each do |return_air_plenum|
      if return_air_plenum.thermalZone.get.name.to_s == zone.get.name.to_s
        # Determine if residential
        return true
      end
    end
    # the zone is a supply plenum
    space.model.getAirLoopHVACSupplyPlenums.each do |supply_air_plenum|
      if supply_air_plenum.thermalZone.get.name.to_s == zone.get.name.to_s
        return true
      end
    end
    # None match, return false
    return false
  end

  # Determine if a space should be modeled with an occupancy standby mode
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [Boolean] true if occupancy standby mode is to be modeled, false otherwise
  def space_occupancy_standby_mode_required?(space)
    return false
  end

  # Provide the type of daylighting control type
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [String] daylighting control type
  def space_daylighting_control_type(space)
    return 'Stepped'
  end

  # Provide the minimum input power fraction for continuous
  # dimming daylighting control
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [Double] daylighting minimum input power fraction
  def space_daylighting_minimum_input_power_fraction(space)
    return 0.3
  end

  # Create and assign PRM computer room electric equipment schedule
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [Boolean] returns true if successful, false if not
  def space_add_prm_computer_room_equipment_schedule(space)
    return true
  end
end
