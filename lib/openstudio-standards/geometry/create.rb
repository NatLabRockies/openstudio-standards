module OpenstudioStandards
  # The Geometry module provides methods to create, modify, and get information about model geometry
  module Geometry
    # @!group Create
    # Methods to create geometry

    # method to create a point object at the center of a floor
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param z_offset_m [Double] vertical offset in meters
    # @return [OpenStudio::Point3d] point at the center of the space. return nil if point is not on floor in space.
    def self.space_create_point_at_center_of_floor(space, z_offset_m)
      # find floors
      floor_surfaces = []
      space.surfaces.each { |surface| floor_surfaces << surface if surface.surfaceType == 'Floor' }

      # this method only works for flat (non-inclined) floors
      bounding_box = OpenStudio::BoundingBox.new
      floor_surfaces.each { |floor| bounding_box.addPoints(floor.vertices) }
      xmin = bounding_box.minX.get
      ymin = bounding_box.minY.get
      zmin = bounding_box.minZ.get
      xmax = bounding_box.maxX.get
      ymax = bounding_box.maxY.get

      x_pos = (xmin + xmax) / 2
      y_pos = (ymin + ymax) / 2
      z_pos = zmin + z_offset_m
      point_on_floor = OpenstudioStandards::Geometry.surfaces_contain_point?(floor_surfaces, OpenStudio::Point3d.new(x_pos, y_pos, zmin))

      if point_on_floor
        new_point = OpenStudio::Point3d.new(x_pos, y_pos, z_pos)
      else
        # don't make point, it doesn't appear to be inside of the space
        new_point = nil
      end

      return new_point
    end

    # method to create a point object from a sub surface
    #
    # @param sub_surface [OpenStudio::Model::SubSurface] OpenStudio SubSurface object
    # @param reference_floor [OpenStudio::Model::SubSurface] OpenStudio SubSurface object
    # @param distance_from_window_m [Double] distance in from the window, in meters
    # @param height_above_subsurface_bottom_m [Double] height above the bottom of the subsurface, in meters
    # @return [OpenStudio::Point3d] point at the center of the space. return nil if point is not on floor in space.
    def self.sub_surface_create_point_at_specific_height(sub_surface, reference_floor, distance_from_window_m, height_above_subsurface_bottom_m)
      window_outward_normal = sub_surface.outwardNormal
      window_centroid = OpenStudio.getCentroid(sub_surface.vertices).get
      window_outward_normal.setLength(distance_from_window_m)
      vertex = window_centroid + window_outward_normal.reverseVector
      vertex_on_floorplane = reference_floor.plane.project(vertex)
      floor_outward_normal = reference_floor.outwardNormal
      floor_outward_normal.setLength(height_above_subsurface_bottom_m)

      floor_surfaces = []
      space.surfaces.each { |surface| floor_surfaces << surface if surface.surfaceType == 'Floor' }

      point_on_floor = OpenstudioStandards::Geometry.surfaces_contain_point?(floor_surfaces, vertex_on_floorplane)

      if point_on_floor
        new_point = vertex_on_floorplane + floor_outward_normal.reverseVector
      else
        # don't make point, it doesn't appear to be inside of the space
        # nil
        new_point = vertex_on_floorplane + floor_outward_normal.reverseVector
      end

      return new_point
    end

    # create core and perimeter polygons from length width and origin
    #
    # @param length [Double] length of building in meters
    # @param width [Double] width of building in meters
    # @param footprint_origin_point [OpenStudio::Point3d] Optional OpenStudio Point3d object for the new origin
    # @param perimeter_zone_depth [Double] Optional perimeter zone depth in meters
    # @return [Hash] Hash of point vectors that define the space geometry for each direction
    def self.create_core_and_perimeter_polygons(length, width,
                                                footprint_origin_point = OpenStudio::Point3d.new(0.0, 0.0, 0.0),
                                                perimeter_zone_depth = OpenStudio.convert(15.0, 'ft', 'm').get)
      # key is name, value is a hash, one item of which is polygon. Another could be space type.
      hash_of_point_vectors = {}

      # determine if core and perimeter zoning can be used
      if !(length > perimeter_zone_depth * 2.5 && width > perimeter_zone_depth * 2.5)
        # if any size is to small then just model floor as single zone, issue warning
        perimeter_zone_depth = 0.0
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', 'Due to the size of the building modeling each floor as a single zone.')
      end

      x_delta = footprint_origin_point.x - (length / 2.0)
      y_delta = footprint_origin_point.y - (width / 2.0)
      z = 0
      nw_point = OpenStudio::Point3d.new(x_delta, y_delta + width, z)
      ne_point = OpenStudio::Point3d.new(x_delta + length, y_delta + width, z)
      se_point = OpenStudio::Point3d.new(x_delta + length, y_delta, z)
      sw_point = OpenStudio::Point3d.new(x_delta, y_delta, z)

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
        hash_of_point_vectors['West Perimeter Space'] = {}
        hash_of_point_vectors['West Perimeter Space'][:space_type] = nil # other methods being used by makeSpacesFromPolygons may have space types associated with each polygon but this doesn't.
        hash_of_point_vectors['West Perimeter Space'][:polygon] = west_polygon

        north_polygon = OpenStudio::Point3dVector.new
        north_polygon << nw_point
        north_polygon << ne_point
        north_polygon << perimeter_ne_point
        north_polygon << perimeter_nw_point
        hash_of_point_vectors['North Perimeter Space'] = {}
        hash_of_point_vectors['North Perimeter Space'][:space_type] = nil
        hash_of_point_vectors['North Perimeter Space'][:polygon] = north_polygon

        east_polygon = OpenStudio::Point3dVector.new
        east_polygon << ne_point
        east_polygon << se_point
        east_polygon << perimeter_se_point
        east_polygon << perimeter_ne_point
        hash_of_point_vectors['East Perimeter Space'] = {}
        hash_of_point_vectors['East Perimeter Space'][:space_type] = nil
        hash_of_point_vectors['East Perimeter Space'][:polygon] = east_polygon

        south_polygon = OpenStudio::Point3dVector.new
        south_polygon << se_point
        south_polygon << sw_point
        south_polygon << perimeter_sw_point
        south_polygon << perimeter_se_point
        hash_of_point_vectors['South Perimeter Space'] = {}
        hash_of_point_vectors['South Perimeter Space'][:space_type] = nil
        hash_of_point_vectors['South Perimeter Space'][:polygon] = south_polygon

        core_polygon = OpenStudio::Point3dVector.new
        core_polygon << perimeter_sw_point
        core_polygon << perimeter_nw_point
        core_polygon << perimeter_ne_point
        core_polygon << perimeter_se_point
        hash_of_point_vectors['Core Space'] = {}
        hash_of_point_vectors['Core Space'][:space_type] = nil
        hash_of_point_vectors['Core Space'][:polygon] = core_polygon

        # Minimal zones
      else
        whole_story_polygon = OpenStudio::Point3dVector.new
        whole_story_polygon << sw_point
        whole_story_polygon << nw_point
        whole_story_polygon << ne_point
        whole_story_polygon << se_point
        hash_of_point_vectors['Whole Story Space'] = {}
        hash_of_point_vectors['Whole Story Space'][:space_type] = nil
        hash_of_point_vectors['Whole Story Space'][:polygon] = whole_story_polygon
      end

      return hash_of_point_vectors
    end

    # sliced bar multi creates and array of multiple sliced bar simple hashes
    #
    # @param space_types [Array<Hash>] Array of hashes with the space type and floor area
    # @param length [Double] length of building in meters
    # @param width [Double] width of building in meters
    # @param footprint_origin_point [OpenStudio::Point3d] OpenStudio Point3d object for the new origin
    # @param story_hash [Hash] A hash of building story information including space origin z value and space height
    # @return [Hash] Hash of point vectors that define the space geometry for each direction
    def self.create_sliced_bar_multi_polygons(space_types, length, width, footprint_origin_point, story_hash)
      # total building floor area to calculate ratios from space type floor areas
      total_floor_area = 0.0
      target_per_space_type = {}
      space_types.each do |space_type, space_type_hash|
        total_floor_area += space_type_hash[:floor_area]
        target_per_space_type[space_type] = space_type_hash[:floor_area]
      end

      # sort array by floor area, this hash will be altered to reduce floor area for each space type to 0
      space_types_running_count = space_types.sort_by { |k, v| v[:floor_area] }

      # array entry for each story
      footprints = []

      # variables for sliver check
      # re-evaluate what the default should be
      valid_bar_width_min_m = OpenStudio.convert(3.0, 'ft', 'm').get
      # building width
      bar_length = width
      valid_bar_area_min_m2 = valid_bar_width_min_m * bar_length

      # loop through stories to populate footprints
      story_hash.each_with_index do |(k, v), i|
        # update the length and width for partial floors
        if i + 1 == story_hash.size
          area_multiplier = v[:partial_story_multiplier]
          edge_multiplier = Math.sqrt(area_multiplier)
          length *= edge_multiplier
          width *= edge_multiplier
        end

        # this will be populated for each building story
        target_footprint_area = v[:multiplier] * length * width
        current_footprint_area = 0.0
        space_types_local_count = {}

        space_types_running_count.each do |space_type, space_type_hash|
          # next if floor area is full or space type is empty

          tol_value = 0.0001
          next if current_footprint_area + tol_value >= target_footprint_area
          next if space_type_hash[:floor_area] <= tol_value

          # special test for when total floor area is smaller than valid_bar_area_min_m2, just make bar smaller that valid min and warn user
          if target_per_space_type[space_type] < valid_bar_area_min_m2
            sliver_override = true
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', "Floor area of #{space_type.name} results in a bar with smaller than target minimum width.")
          else
            sliver_override = false
          end

          # add entry for space type if it doesn't have one yet
          if !space_types_local_count.key?(space_type)
            if space_type_hash.key?(:children)
              space_type = space_type_hash[:children][:default][:space_type] # will re-using space type create issue
              space_types_local_count[space_type] = { floor_area: 0.0 }
              space_types_local_count[space_type][:children] = space_type_hash[:children]
            else
              space_types_local_count[space_type] = { floor_area: 0.0 }
            end
          end

          # if there is enough of this space type to fill rest of floor area
          remaining_in_footprint = target_footprint_area - current_footprint_area
          raw_footprint_area_used = [space_type_hash[:floor_area], remaining_in_footprint].min

          # add to local hash
          space_types_local_count[space_type][:floor_area] = raw_footprint_area_used / v[:multiplier].to_f

          # adjust balance ot running and local counts
          current_footprint_area += raw_footprint_area_used
          space_type_hash[:floor_area] -= raw_footprint_area_used

          # test if think sliver left on current floor.
          # fix by moving smallest space type to next floor and and the same amount more of the sliver space type to this story
          raw_footprint_area_used < valid_bar_area_min_m2 && sliver_override == false ? (test_a = true) : (test_a = false)

          # test if what would be left of the current space type would result in a sliver on the next story.
          # fix by removing some of this space type so their is enough left for the next story, and replace the removed amount with the largest space type in the model
          (space_type_hash[:floor_area] < valid_bar_area_min_m2) && (space_type_hash[:floor_area] > tol_value) ? (test_b = true) : (test_b = false)

          # identify very small slices and re-arrange spaces to different stories to avoid this
          if test_a

            # get first/smallest space type to move to another story
            first_space = space_types_local_count.first

            # adjustments running counter for space type being removed from this story
            space_types_running_count.each do |k2, v2|
              next if k2 != first_space[0]

              v2[:floor_area] += first_space[1][:floor_area] * v[:multiplier]
            end

            # adjust running count for current space type
            space_type_hash[:floor_area] -= first_space[1][:floor_area] * v[:multiplier]

            # add to local count for current space type
            space_types_local_count[space_type][:floor_area] += first_space[1][:floor_area]

            # remove from local count for removed space type
            space_types_local_count.shift

          elsif test_b

            # swap size
            swap_size = valid_bar_area_min_m2 * 5.0 # currently equal to default perimeter zone depth of 15'
            # this prevents too much area from being swapped resulting in a negative number for floor area
            if swap_size > space_types_local_count[space_type][:floor_area] * v[:multiplier].to_f
              swap_size = space_types_local_count[space_type][:floor_area] * v[:multiplier].to_f
            end

            # adjust running count for current space type
            space_type_hash[:floor_area] += swap_size

            # remove from local count for current space type
            space_types_local_count[space_type][:floor_area] -= swap_size / v[:multiplier].to_f

            # adjust footprint used
            current_footprint_area -= swap_size

            # the next larger space type will be brought down to fill out the footprint without any additional code
          end
        end

        # creating footprint for story
        footprints << OpenstudioStandards::Geometry.create_sliced_bar_simple_polygons(space_types_local_count, length, width, footprint_origin_point)
      end
      return footprints
    end

    # sliced bar simple creates a single sliced bar for space types passed in
    # look at length and width to adjust slicing direction
    #
    # @param space_types [Array<Hash>] Array of hashes with the space type and floor area
    # @param length [Double] length of building in meters
    # @param width [Double] width of building in meters
    # @param footprint_origin_point [OpenStudio::Point3d] Optional OpenStudio Point3d object for the new origin
    # @param perimeter_zone_depth [Double] Optional perimeter zone depth in meters
    # @return [Hash] Hash of point vectors that define the space geometry for each direction
    def self.create_sliced_bar_simple_polygons(space_types, length, width,
                                               footprint_origin_point = OpenStudio::Point3d.new(0.0, 0.0, 0.0),
                                               perimeter_zone_depth = OpenStudio.convert(15.0, 'ft', 'm').get)
      hash_of_point_vectors = {} # key is name, value is a hash, one item of which is polygon. Another could be space type

      reverse_slice = false
      if length < width
        reverse_slice = true
        # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Reverse typical slice direction for bar because of aspect ratio less than 1.0.")
      end

      # determine if core and perimeter zoning can be used
      if !([length, width].min > perimeter_zone_depth * 2.5 && [length, width].min > perimeter_zone_depth * 2.5)
        perimeter_zone_depth = 0 # if any size is to small then just model floor as single zone, issue warning
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', 'Not modeling core and perimeter zones for some portion of the model.')
      end

      x_delta = footprint_origin_point.x - (length / 2.0)
      y_delta = footprint_origin_point.y - (width / 2.0)
      z = 0.0
      # this represents the entire bar, not individual space type slices
      nw_point = OpenStudio::Point3d.new(x_delta, y_delta + width, z)
      sw_point = OpenStudio::Point3d.new(x_delta, y_delta, z)
      # used when length is less than width
      se_point = OpenStudio::Point3d.new(x_delta + length, y_delta, z)

      # total building floor area to calculate ratios from space type floor areas
      total_floor_area = 0.0
      space_types.each do |space_type, space_type_hash|
        total_floor_area += space_type_hash[:floor_area]
      end

      # sort array by floor area but shift largest object to front
      space_types = space_types.sort_by { |k, v| v[:floor_area] }
      space_types.insert(0, space_types.delete_at(space_types.size - 1)) # .to_h

      # min and max bar end values
      min_bar_end_multiplier = 0.75
      max_bar_end_multiplier = 1.5

      # sort_by results in arrays with two items , first is key, second is hash value
      re_apply_largest_space_type_at_end = false
      max_reduction = nil # used when looping through section_hash_for_space_type if first space type needs to also be at far end of bar
      space_types.each do |space_type, space_type_hash|
        # setup end perimeter zones if needed
        start_perimeter_width_deduction = 0.0
        end_perimeter_width_deduction = 0.0
        if space_type == space_types.first[0]
          if [length, width].max * space_type_hash[:floor_area] / total_floor_area > max_bar_end_multiplier * perimeter_zone_depth
            start_perimeter_width_deduction = perimeter_zone_depth
          end
          # see if last space type is too small for perimeter. If it is then save some of this space type
          if [length, width].max * space_types.last[1][:floor_area] / total_floor_area < perimeter_zone_depth * min_bar_end_multiplier
            re_apply_largest_space_type_at_end = true
          end
        end
        if space_type == space_types.last[0]
          if [length, width].max * space_type_hash[:floor_area] / total_floor_area > max_bar_end_multiplier * perimeter_zone_depth
            end_perimeter_width_deduction = perimeter_zone_depth
          end
        end
        non_end_adjusted_width = ([length, width].max * space_type_hash[:floor_area] / total_floor_area) - start_perimeter_width_deduction - end_perimeter_width_deduction

        # adjustment of end space type is too small and is replaced with largest space type
        if (space_type == space_types.first[0]) && re_apply_largest_space_type_at_end
          max_reduction = [perimeter_zone_depth, non_end_adjusted_width].min
          non_end_adjusted_width -= max_reduction
        end
        if (space_type == space_types.last[0]) && re_apply_largest_space_type_at_end
          end_perimeter_width_deduction = space_types.first[0]
          end_b_flag = true
        else
          end_b_flag = false
        end

        # populate data for core and perimeter of slice
        section_hash_for_space_type = {}
        section_hash_for_space_type['end_a'] = start_perimeter_width_deduction
        section_hash_for_space_type[''] = non_end_adjusted_width
        section_hash_for_space_type['end_b'] = end_perimeter_width_deduction

        # determine if this space+type is double loaded corridor, and if so what the perimeter zone depth should be based on building width
        # look at reverse_slice to see if length or width should be used to determine perimeter depth
        if space_type_hash.key?(:children)
          core_ratio = space_type_hash[:children][:circ][:orig_ratio]
          perim_ratio = space_type_hash[:children][:default][:orig_ratio]
          core_ratio_adj = core_ratio / (core_ratio + perim_ratio)
          perim_ratio_adj = perim_ratio / (core_ratio + perim_ratio)
          core_space_type = space_type_hash[:children][:circ][:space_type]
          perim_space_type = space_type_hash[:children][:default][:space_type]
          if reverse_slice
            custom_cor_val = length * core_ratio_adj
            custom_perim_val = (length - custom_cor_val) / 2.0
          else
            custom_cor_val = width * core_ratio_adj
            custom_perim_val = (width - custom_cor_val) / 2.0
          end
          # use perimeter zone depth if the custom perimeter value is within 1 milimeter
          if (custom_perim_val - perimeter_zone_depth).abs < 0.001
            actual_perim = perimeter_zone_depth
          else
            actual_perim = custom_perim_val
          end

          double_loaded_corridor = true
        else
          actual_perim = perimeter_zone_depth
          double_loaded_corridor = false
        end

        # may overwrite
        first_space_type_hash = space_types.first[1]
        if end_b_flag && first_space_type_hash.key?(:children)
          end_b_core_ratio = first_space_type_hash[:children][:circ][:orig_ratio]
          end_b_perim_ratio = first_space_type_hash[:children][:default][:orig_ratio]
          end_b_core_ratio_adj = end_b_core_ratio / (end_b_core_ratio + end_b_perim_ratio)
          end_b_perim_ratio_adj = end_b_perim_ratio / (end_b_core_ratio + end_b_perim_ratio)
          end_b_core_space_type = first_space_type_hash[:children][:circ][:space_type]
          end_b_perim_space_type = first_space_type_hash[:children][:default][:space_type]
          if reverse_slice
            end_b_custom_cor_val = length * end_b_core_ratio_adj
            end_b_custom_perim_val = (length - end_b_custom_cor_val) / 2.0
          else
            end_b_custom_cor_val = width * end_b_core_ratio_adj
            end_b_custom_perim_val = (width - end_b_custom_cor_val) / 2.0
          end
          end_b_actual_perim = end_b_custom_perim_val
          end_b_double_loaded_corridor = true
        else
          end_b_actual_perim = perimeter_zone_depth
          end_b_double_loaded_corridor = false
        end

        # loop through sections for space type (main and possibly one or two end perimeter sections)
        section_hash_for_space_type.each do |k, slice|
          # need to use different space type for end_b
          if end_b_flag && k == 'end_b' && space_types.first[1].key?(:children)
            slice = space_types.first[0]
            actual_perim = end_b_actual_perim
            double_loaded_corridor = end_b_double_loaded_corridor
            core_ratio = end_b_core_ratio
            perim_ratio = end_b_perim_ratio
            core_ratio_adj = end_b_core_ratio_adj
            perim_ratio_adj = end_b_perim_ratio_adj
            core_space_type = end_b_core_space_type
            perim_space_type = end_b_perim_space_type
          end

          if slice.class.to_s == 'OpenStudio::Model::SpaceType' || slice.class.to_s == 'OpenStudio::Model::Building'
            space_type = slice
            max_reduction = [perimeter_zone_depth, max_reduction].min
            slice = max_reduction
          end
          if slice == 0
            next
          end

          if reverse_slice
            # create_bar at 90 degrees if aspect ration is less than 1.0
            # typical order (sw,nw,ne,se)
            # order used here (se,sw,nw,ne)
            nw_point = (sw_point + OpenStudio::Vector3d.new(0, slice, 0))
            ne_point = (se_point + OpenStudio::Vector3d.new(0, slice, 0))

            if actual_perim > 0 && (actual_perim * 2.0) < length
              polygon_a = OpenStudio::Point3dVector.new
              polygon_a << se_point
              polygon_a << (se_point + OpenStudio::Vector3d.new(- actual_perim, 0, 0))
              polygon_a << (ne_point + OpenStudio::Vector3d.new(- actual_perim, 0, 0))
              polygon_a << ne_point
              if double_loaded_corridor
                hash_of_point_vectors["#{perim_space_type.name} A #{k}"] = {}
                hash_of_point_vectors["#{perim_space_type.name} A #{k}"][:space_type] = perim_space_type
                hash_of_point_vectors["#{perim_space_type.name} A #{k}"][:polygon] = polygon_a
              else
                hash_of_point_vectors["#{space_type.name} A #{k}"] = {}
                hash_of_point_vectors["#{space_type.name} A #{k}"][:space_type] = space_type
                hash_of_point_vectors["#{space_type.name} A #{k}"][:polygon] = polygon_a
              end

              polygon_b = OpenStudio::Point3dVector.new
              polygon_b << (se_point + OpenStudio::Vector3d.new(- actual_perim, 0, 0))
              polygon_b << (sw_point + OpenStudio::Vector3d.new(actual_perim, 0, 0))
              polygon_b << (nw_point + OpenStudio::Vector3d.new(actual_perim, 0, 0))
              polygon_b << (ne_point + OpenStudio::Vector3d.new(- actual_perim, 0, 0))
              if double_loaded_corridor
                hash_of_point_vectors["#{core_space_type.name} B #{k}"] = {}
                hash_of_point_vectors["#{core_space_type.name} B #{k}"][:space_type] = core_space_type
                hash_of_point_vectors["#{core_space_type.name} B #{k}"][:polygon] = polygon_b
              else
                hash_of_point_vectors["#{space_type.name} B #{k}"] = {}
                hash_of_point_vectors["#{space_type.name} B #{k}"][:space_type] = space_type
                hash_of_point_vectors["#{space_type.name} B #{k}"][:polygon] = polygon_b
              end

              polygon_c = OpenStudio::Point3dVector.new
              polygon_c << (sw_point + OpenStudio::Vector3d.new(actual_perim, 0, 0))
              polygon_c << sw_point
              polygon_c << nw_point
              polygon_c << (nw_point + OpenStudio::Vector3d.new(actual_perim, 0, 0))
              if double_loaded_corridor
                hash_of_point_vectors["#{perim_space_type.name} C #{k}"] = {}
                hash_of_point_vectors["#{perim_space_type.name} C #{k}"][:space_type] = perim_space_type
                hash_of_point_vectors["#{perim_space_type.name} C #{k}"][:polygon] = polygon_c
              else
                hash_of_point_vectors["#{space_type.name} C #{k}"] = {}
                hash_of_point_vectors["#{space_type.name} C #{k}"][:space_type] = space_type
                hash_of_point_vectors["#{space_type.name} C #{k}"][:polygon] = polygon_c
              end
            else
              polygon_a = OpenStudio::Point3dVector.new
              polygon_a << se_point
              polygon_a << sw_point
              polygon_a << nw_point
              polygon_a << ne_point
              hash_of_point_vectors["#{space_type.name} #{k}"] = {}
              hash_of_point_vectors["#{space_type.name} #{k}"][:space_type] = space_type
              hash_of_point_vectors["#{space_type.name} #{k}"][:polygon] = polygon_a
            end

            # update west points
            sw_point = nw_point
            se_point = ne_point
          else
            ne_point = nw_point + OpenStudio::Vector3d.new(slice, 0, 0)
            se_point = sw_point + OpenStudio::Vector3d.new(slice, 0, 0)

            if actual_perim > 0 && (actual_perim * 2.0) < width
              polygon_a = OpenStudio::Point3dVector.new
              polygon_a << sw_point
              polygon_a << (sw_point + OpenStudio::Vector3d.new(0, actual_perim, 0))
              polygon_a << (se_point + OpenStudio::Vector3d.new(0, actual_perim, 0))
              polygon_a << se_point
              if double_loaded_corridor
                hash_of_point_vectors["#{perim_space_type.name} A #{k}"] = {}
                hash_of_point_vectors["#{perim_space_type.name} A #{k}"][:space_type] = perim_space_type
                hash_of_point_vectors["#{perim_space_type.name} A #{k}"][:polygon] = polygon_a
              else
                hash_of_point_vectors["#{space_type.name} A #{k}"] = {}
                hash_of_point_vectors["#{space_type.name} A #{k}"][:space_type] = space_type
                hash_of_point_vectors["#{space_type.name} A #{k}"][:polygon] = polygon_a
              end

              polygon_b = OpenStudio::Point3dVector.new
              polygon_b << (sw_point + OpenStudio::Vector3d.new(0, actual_perim, 0))
              polygon_b << (nw_point + OpenStudio::Vector3d.new(0, - actual_perim, 0))
              polygon_b << (ne_point + OpenStudio::Vector3d.new(0, - actual_perim, 0))
              polygon_b << (se_point + OpenStudio::Vector3d.new(0, actual_perim, 0))
              if double_loaded_corridor
                hash_of_point_vectors["#{core_space_type.name} B #{k}"] = {}
                hash_of_point_vectors["#{core_space_type.name} B #{k}"][:space_type] = core_space_type
                hash_of_point_vectors["#{core_space_type.name} B #{k}"][:polygon] = polygon_b
              else
                hash_of_point_vectors["#{space_type.name} B #{k}"] = {}
                hash_of_point_vectors["#{space_type.name} B #{k}"][:space_type] = space_type
                hash_of_point_vectors["#{space_type.name} B #{k}"][:polygon] = polygon_b
              end

              polygon_c = OpenStudio::Point3dVector.new
              polygon_c << (nw_point + OpenStudio::Vector3d.new(0, - actual_perim, 0))
              polygon_c << nw_point
              polygon_c << ne_point
              polygon_c << (ne_point + OpenStudio::Vector3d.new(0, - actual_perim, 0))
              if double_loaded_corridor
                hash_of_point_vectors["#{perim_space_type.name} C #{k}"] = {}
                hash_of_point_vectors["#{perim_space_type.name} C #{k}"][:space_type] = perim_space_type
                hash_of_point_vectors["#{perim_space_type.name} C #{k}"][:polygon] = polygon_c
              else
                hash_of_point_vectors["#{space_type.name} C #{k}"] = {}
                hash_of_point_vectors["#{space_type.name} C #{k}"][:space_type] = space_type
                hash_of_point_vectors["#{space_type.name} C #{k}"][:polygon] = polygon_c
              end
            else
              polygon_a = OpenStudio::Point3dVector.new
              polygon_a << sw_point
              polygon_a << nw_point
              polygon_a << ne_point
              polygon_a << se_point
              hash_of_point_vectors["#{space_type.name} #{k}"] = {}
              hash_of_point_vectors["#{space_type.name} #{k}"][:space_type] = space_type
              hash_of_point_vectors["#{space_type.name} #{k}"][:polygon] = polygon_a
            end

            # update west points
            nw_point = ne_point
            sw_point = se_point
          end
        end
      end

      return hash_of_point_vectors
    end

    # take diagram made by create_core_and_perimeter_polygons and make multi-story building
    # @todo add option to create shading surfaces when using multiplier. Mainly important for non rectangular buildings where self shading would be an issue.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param footprints [Hash] Array of footprint polygons that make up the spaces
    # @param typical_story_height [Double] typical story height in meters
    # @param effective_num_stories [Double] effective number of stories
    # @param footprint_origin_point [OpenStudio::Point3d] Optional OpenStudio Point3d object for the new origin
    # @param story_hash [Hash] A hash of building story information including space origin z value and space height
    #  If blank, this method will default to using information in the story_hash.
    # @return [Array<OpenStudio::Model::Space>] Array of OpenStudio Space objects
    def self.create_spaces_from_polygons(model, footprints, typical_story_height, effective_num_stories,
                                         footprint_origin_point = OpenStudio::Point3d.new(0.0, 0.0, 0.0),
                                         story_hash = {})
      # default story hash is for three stories with mid-story multiplier, but user can pass in custom versions
      if story_hash.empty?
        if effective_num_stories > 2
          story_hash['ground'] = { space_origin_z: footprint_origin_point.z, space_height: typical_story_height, multiplier: 1 }
          story_hash['mid'] = { space_origin_z: footprint_origin_point.z + typical_story_height + (typical_story_height * (effective_num_stories.ceil - 3) / 2.0), space_height: typical_story_height, multiplier: effective_num_stories - 2 }
          story_hash['top'] = { space_origin_z: footprint_origin_point.z + (typical_story_height * (effective_num_stories.ceil - 1)), space_height: typical_story_height, multiplier: 1 }
        elsif effective_num_stories > 1
          story_hash['ground'] = { space_origin_z: footprint_origin_point.z, space_height: typical_story_height, multiplier: 1 }
          story_hash['top'] = { space_origin_z: footprint_origin_point.z + (typical_story_height * (effective_num_stories.ceil - 1)), space_height: typical_story_height, multiplier: 1 }
        else
          # one story only
          story_hash['ground'] = { space_origin_z: footprint_origin_point.z, space_height: typical_story_height, multiplier: 1 }
        end
      end

      # hash of new spaces (only change boundary conditions for these)
      new_spaces = []

      # loop through story_hash and polygons to generate all of the spaces
      story_hash.each_with_index do |(story_name, story_data), index|
        # make new story unless story at requested height already exists.
        story = nil
        model.getBuildingStorys.sort.each do |ext_story|
          if (ext_story.nominalZCoordinate.to_f - story_data[:space_origin_z].to_f).abs < 0.01
            story = ext_story
          end
        end
        if story.nil?
          story = OpenStudio::Model::BuildingStory.new(model)
          # not used for anything
          story.setNominalFloortoFloorHeight(story_data[:space_height])
          # not used for anything
          story.setNominalZCoordinate(story_data[:space_origin_z])
          story.setName("Story #{story_name}")
        end

        # multiplier values for adjacent stories to be altered below as needed
        multiplier_story_above = 1
        multiplier_story_below = 1

        if index == 0 # bottom floor, only check above
          if story_hash.size > 1
            multiplier_story_above = story_hash.values[index + 1][:multiplier]
          end
        elsif index == story_hash.size - 1 # top floor, check only below
          multiplier_story_below = story_hash.values[index + -1][:multiplier]
        else # mid floor, check above and below
          multiplier_story_above = story_hash.values[index + 1][:multiplier]
          multiplier_story_below = story_hash.values[index + -1][:multiplier]
        end

        # if adjacent story has multiplier > 1 then make appropriate surfaces adiabatic
        adiabatic_ceilings = false
        adiabatic_floors = false
        if story_data[:multiplier] > 1
          adiabatic_ceilings = true
          adiabatic_floors = true
        elsif multiplier_story_above > 1
          adiabatic_ceilings = true
        elsif multiplier_story_below > 1
          adiabatic_floors = true
        end

        # get the right collection of polygons to make up footprint for each building story
        if index > footprints.size - 1
          # use last footprint
          target_footprint = footprints.last
        else
          target_footprint = footprints[index]
        end
        target_footprint.each do |name, space_data|
          # gather options
          options = {
            'name' => "#{name} - #{story.name}",
            'space_type' => space_data[:space_type],
            'story' => story,
            'make_thermal_zone' => true,
            'thermal_zone_multiplier' => story_data[:multiplier],
            'floor_to_floor_height' => story_data[:space_height]
          }

          # make space
          space = OpenstudioStandards::Geometry.create_space_from_polygon(model, space_data[:polygon].first, space_data[:polygon], options)
          new_spaces << space

          # set z origin to proper position
          space.setZOrigin(story_data[:space_origin_z])

          # loop through celings and floors to hard asssign constructions and set boundary condition
          if adiabatic_ceilings || adiabatic_floors
            space.surfaces.each do |surface|
              if adiabatic_floors && (surface.surfaceType == 'Floor')
                if surface.construction.is_initialized
                  surface.setConstruction(surface.construction.get)
                end
                surface.setOutsideBoundaryCondition('Adiabatic')
              end
              if adiabatic_ceilings && (surface.surfaceType == 'RoofCeiling')
                if surface.construction.is_initialized
                  surface.setConstruction(surface.construction.get)
                end
                surface.setOutsideBoundaryCondition('Adiabatic')
              end
            end
          end
        end

        # @tofo in future add code to include plenums or raised floor to each/any story.
      end
      # any changes to wall boundary conditions will be handled by same code that calls this method.
      # this method doesn't need to know about basements and party walls.
      return new_spaces
    end

    # add def to create a space from input, optionally take a name, space type, story and thermal zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object describing the space footprint polygon
    # @param space_origin [OpenStudio::Point3d] origin point
    # @param point_3d_vector [OpenStudio::Point3dVector] OpenStudio Point3dVector defining the space footprint
    # @param options [Hash] Hash of options for additional arguments
    # @option options [String] :name name of the space
    # @option options [OpenStudio::Model::SpaceType] :space_type OpenStudio SpaceType object
    # @option options [String] :story name name of the building story
    # @option options [Boolean] :make_thermal_zone set to true to make an thermal zone object, defaults to true.
    # @option options [OpenStudio::Model::ThermalZone] :thermal_zone attach a specific ThermalZone object to the space
    # @option options [Integer] :thermal_zone_multiplier the thermal zone multiplier, defaults to 1.
    # @option options [Double] :floor_to_floor_height floor to floor height in meters, defaults to 10 ft.
    # @return [OpenStudio::Model::Space] OpenStudio Space object
    def self.create_space_from_polygon(model, space_origin, point_3d_vector, options = {})
      # set defaults to use if user inputs not passed in
      defaults = {
        'name' => nil,
        'space_type' => nil,
        'story' => nil,
        'make_thermal_zone' => nil,
        'thermal_zone' => nil,
        'thermal_zone_multiplier' => 1,
        'floor_to_floor_height' => OpenStudio.convert(10.0, 'ft', 'm').get
      }

      # merge user inputs with defaults
      options = defaults.merge(options)

      # Identity matrix for setting space origins
      m = OpenStudio::Matrix.new(4, 4, 0)
      m[0, 0] = 1
      m[1, 1] = 1
      m[2, 2] = 1
      m[3, 3] = 1

      # make space from floor print
      space = OpenStudio::Model::Space.fromFloorPrint(point_3d_vector, options['floor_to_floor_height'], model)
      space = space.get
      m[0, 3] = space_origin.x
      m[1, 3] = space_origin.y
      m[2, 3] = space_origin.z
      space.changeTransformation(OpenStudio::Transformation.new(m))
      space.setBuildingStory(options['story'])
      if !options['name'].nil?
        space.setName(options['name'])
      end

      if !options['space_type'].nil? && options['space_type'].class.to_s == 'OpenStudio::Model::SpaceType'
        space.setSpaceType(options['space_type'])
      end

      # create thermal zone if requested and assign
      if options['make_thermal_zone']
        new_zone = OpenStudio::Model::ThermalZone.new(model)
        new_zone.setMultiplier(options['thermal_zone_multiplier'])
        space.setThermalZone(new_zone)
        new_zone.setName("Zone #{space.name}")
      else
        if !options['thermal_zone'].nil? then space.setThermalZone(options['thermal_zone']) end
      end

      return space
    end
  end
end
