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
                                                perimeter_zone_depth = OpenStudio.convert(15.0, 'ft', 'm').get,
                                                zone_resolver: nil)
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

      # stamp thermal zone group labels by facade/core for optional zoning
      unless zone_resolver.nil?
        hash_of_point_vectors.each do |key, data|
          band, facade = case key
                         when /North/ then [:perimeter, 'N']
                         when /South/ then [:perimeter, 'S']
                         when /East/ then [:perimeter, 'E']
                         when /West/ then [:perimeter, 'W']
                         else [:core, nil]
                         end
          data[:zone_group] = zone_resolver.call(data[:space_type], band, facade)
        end
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
    def self.create_sliced_bar_multi_polygons(space_types, length, width, footprint_origin_point, story_hash, zone_resolver: nil)
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
        footprints << OpenstudioStandards::Geometry.create_sliced_bar_simple_polygons(space_types_local_count, length, width, footprint_origin_point, zone_resolver: zone_resolver)
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
                                               perimeter_zone_depth = OpenStudio.convert(15.0, 'ft', 'm').get,
                                               zone_resolver: nil)
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

      # stamp thermal zone group labels for optional zoning: perimeter strips (A/C) by
      # facade, core (B) and whole-slice fallbacks left to individual zones
      unless zone_resolver.nil?
        hash_of_point_vectors.each do |key, data|
          space_type = data[:space_type]
          if key =~ / B (?:end_a|end_b|)\z/
            band = :core
            facade = nil
          elsif key =~ / A (?:end_a|end_b|)\z/
            band = :perimeter
            facade = reverse_slice ? 'E' : 'S'
          elsif key =~ / C (?:end_a|end_b|)\z/
            band = :perimeter
            facade = reverse_slice ? 'W' : 'N'
          else
            # whole-slice fallback spans both facades; leave it in its own zone
            data[:zone_group] = nil
            next
          end
          data[:zone_group] = zone_resolver.call(space_type, band, facade)
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

      # thermal zones shared by grouped spaces, keyed by [story, zone_group label]
      group_zones = {}

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

          # optional thermal zone grouping: spaces sharing a (story, zone_group) share a zone
          zone_group = space_data[:zone_group]
          unless zone_group.nil?
            zone = group_zones[[story, zone_group]]
            if zone.nil?
              zone = OpenStudio::Model::ThermalZone.new(model)
              zone.setName("Zone #{story.name} #{zone_group}")
              zone.setMultiplier(story_data[:multiplier])
              zone.additionalProperties.setFeature('zone_group', zone_group.to_s)
              group_zones[[story, zone_group]] = zone
            end
            options['make_thermal_zone'] = false
            options['thermal_zone'] = zone
          end

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

    # name of a space type key for logging (SpaceType object or string)
    #
    # @api private
    # @param space_type [OpenStudio::Model::SpaceType, Object] space type key
    # @return [String] display name
    def self.perimeter_core_space_type_name(space_type)
      space_type.respond_to?(:name) ? space_type.name.to_s : space_type.to_s
    end

    # solve the shared perimeter depth d so that the aggregate geometric core area equals
    # the assigned core area: sum_s m_s (L_s - 2d)(W_s - 2d) = a_core. Returns the smaller
    # positive root, or the target depth when there is no core area or no real root.
    #
    # @api private
    # @return [Double] perimeter depth in meters
    def self.perimeter_core_solve_depth(sum_m, sum_m_lw, sum_m_area, a_core, d_target, min_dim, area_tol)
      return [d_target, (min_dim / 2.0) - area_tol].min if a_core <= area_tol

      a = 4.0 * sum_m
      b = -2.0 * sum_m_lw
      c = sum_m_area - a_core
      disc = (b * b) - (4.0 * a * c)
      return [d_target, (min_dim / 2.0) - area_tol].min if disc < 0.0 || a.abs < area_tol

      d = (-b - Math.sqrt(disc)) / (2.0 * a)
      return d
    end

    # order core-assigned types for spilling to the perimeter on core overflow:
    # size-biased first (largest area first), then keyword/default, then circ.
    # Explicit assignments are excluded (they never move on overflow).
    #
    # @api private
    # @return [Array] ordered array of space type keys
    def self.perimeter_core_overflow_order(core_types)
      by = lambda do |sources|
        core_types.select { |_st, h| sources.include?(h[:position_source]) }
                  .sort_by { |_st, h| -h[:floor_area] }
                  .map(&:first)
      end
      by.call(['size']) + by.call(%w[keyword default]) + by.call(['circ'])
    end

    # order perimeter-assigned types for spilling to the core on core underflow:
    # size-biased (smallest first), then keyword/default (largest first), then explicit last.
    #
    # @api private
    # @return [Array<Array>] ordered array of [space_type, is_explicit] pairs
    def self.perimeter_core_underflow_order(perim_types)
      size = perim_types.select { |_st, h| h[:position_source] == 'size' }
                        .sort_by { |_st, h| h[:floor_area] }.map { |st, _| [st, false] }
      kw = perim_types.select { |_st, h| %w[keyword default].include?(h[:position_source]) }
                      .sort_by { |_st, h| -h[:floor_area] }.map { |st, _| [st, false] }
      ex = perim_types.select { |_st, h| h[:position_source] == 'explicit' }
                      .sort_by { |_st, h| -h[:floor_area] }.map { |st, _| [st, true] }
      size + kw + ex
    end

    # facade letters (in walk order) for an orientation preference array
    #
    # @api private
    # @return [Array<String>] subset of %w[S E N W]
    def self.perimeter_core_orientation_facades(orientation)
      map = { 'north' => 'N', 'south' => 'S', 'east' => 'E', 'west' => 'W' }
      facades = Array(orientation).map { |o| map[o.to_s] }.compact
      %w[S E N W].select { |f| facades.include?(f) }
    end

    # consolidate sliver runs of a band by concentrating a type that is below the minimum
    # width on every story onto the fewest stories, compensating with the largest type in
    # the band so that per-story band totals and per-type building totals are preserved.
    # Mutates draw in place.
    #
    # @api private
    # @param draw [Hash] space_type => Array of per-floor areas by story index
    # @param story_entries [Array<Hash>] story dimensions and multipliers
    # @param min_area_per_story [Array<Double>] minimum per-floor area per story to clear a sliver
    # @param warnings [Array<String>] warning accumulator
    # @param band_label [String] 'perimeter' or 'core' for messages
    # @return [void]
    def self.perimeter_core_consolidate!(draw, story_entries, min_area_per_story, warnings, band_label)
      tol = 1.0e-9
      types = draw.keys.select { |t| draw[t].any? { |val| val > tol } }
      return if types.size <= 1

      partner = types.max_by { |t| draw[t].sum }
      types.each do |t|
        next if t == partner

        present = (0...story_entries.size).select { |i| draw[t][i] > tol }
        next if present.size <= 1
        next unless present.all? { |i| draw[t][i] < min_area_per_story[i] - tol }

        target = present.max_by { |i| story_entries[i][:multiplier] * (story_entries[i][:length] * story_entries[i][:width]) }
        present.each do |i|
          next if i == target

          m_i = story_entries[i][:multiplier]
          m_tg = story_entries[target][:multiplier]
          mult_move = draw[t][i] * m_i
          next if (draw[partner][target] * m_tg) < mult_move - tol

          draw[t][i] = 0.0
          draw[t][target] += mult_move / m_tg
          draw[partner][i] += mult_move / m_i
          draw[partner][target] -= mult_move / m_tg
        end

        if draw[t][target] < min_area_per_story[target] - tol
          warnings << "#{band_label} space type #{OpenstudioStandards::Geometry.perimeter_core_space_type_name(t)} remains below the minimum width after consolidation."
        end
      end
    end

    # allocate space types into perimeter and core bands and produce per-story rectangles.
    # Pure area math with no OpenStudio geometry so it can be unit tested in isolation.
    # See docs/design/space_type_positioning_plan.md Phase 2 for the normative algorithm.
    #
    # @param space_types [Hash] space_type => hash with :floor_area (m^2, building total for
    #   this bar), :position ('perimeter'|'core'), :position_source, optional :orientation
    # @param story_entries [Array<Hash>] one per story footprint, each with :length, :width
    #   (meters, already reduced for a partial top story) and :multiplier
    # @param args [Hash] :perimeter_zone_depth, :perimeter_depth_min, :perimeter_depth_max
    #   (meters), optional :valid_bar_width_min (meters, defaults to 3 ft)
    # @return [Hash] { depth:, fallback: nil|:sliced, rects: Array (per story) of rect hashes
    #   { space_type:, band:, facade:, x0:, y0:, x1:, y1: }, moves: Array, warnings: Array }
    def self.perimeter_core_allocation(space_types, story_entries, args)
      warnings = []
      moves = []
      area_tol = 1.0e-6

      d_min = args[:perimeter_depth_min]
      d_max = args[:perimeter_depth_max]
      d_target = args[:perimeter_zone_depth]
      min_run = args.fetch(:valid_bar_width_min, OpenStudio.convert(3.0, 'ft', 'm').get)

      # Step 9 - degenerate guard (checked first)
      if story_entries.any? { |s| [s[:length], s[:width]].min < (2.5 * d_min) }
        warnings << 'Bar is too narrow for a meaningful core; falling back to sliced layout.'
        return { depth: nil, fallback: :sliced, rects: [], moves: moves, warnings: warnings }
      end

      # Step 1 - partition
      core_types = space_types.select { |_st, h| h[:position] == 'core' }
      perim_types = space_types.select { |_st, h| h[:position] == 'perimeter' }
      a_core = core_types.values.sum { |h| h[:floor_area] }

      sum_m = story_entries.sum { |s| s[:multiplier].to_f }
      sum_m_lw = story_entries.sum { |s| s[:multiplier] * (s[:length] + s[:width]) }
      sum_m_area = story_entries.sum { |s| s[:multiplier] * s[:length] * s[:width] }
      min_dim = story_entries.map { |s| [s[:length], s[:width]].min }.min

      # Step 2 - depth solve
      d_star = OpenstudioStandards::Geometry.perimeter_core_solve_depth(sum_m, sum_m_lw, sum_m_area, a_core, d_target, min_dim, area_tol)

      # Step 3 - clamp
      d = [[d_star, d_min].max, d_max].min

      geometric_core = lambda do |depth|
        story_entries.sum { |s| s[:multiplier] * (s[:length] - (2 * depth)) * (s[:width] - (2 * depth)) }
      end

      core_area = Hash.new(0.0)
      perim_area = Hash.new(0.0)
      space_types.each do |st, h|
        if h[:position] == 'core'
          core_area[st] = h[:floor_area]
        else
          perim_area[st] = h[:floor_area]
        end
      end

      # Step 4 - spill to rebalance
      delta = geometric_core.call(d) - a_core
      if delta < -area_tol
        need = -delta
        OpenstudioStandards::Geometry.perimeter_core_overflow_order(core_types).each do |st|
          break if need <= area_tol

          move = [core_area[st], need].min
          next if move <= area_tol

          core_area[st] -= move
          perim_area[st] += move
          need -= move
          moves << { space_type: st, area: move, from: :core, to: :perimeter, reason: 'core overflow' }
        end
        if need > area_tol
          remaining_core = core_area.values.sum
          d = OpenstudioStandards::Geometry.perimeter_core_solve_depth(sum_m, sum_m_lw, sum_m_area, remaining_core, d_target, min_dim, area_tol)
          d = [[d, area_tol].max, (min_dim / 2.0) - area_tol].min
          warnings << 'Explicit core space types exceed the maximum core size; perimeter depth reduced below the minimum to fit.'
        end
      elsif delta > area_tol
        need = delta
        OpenstudioStandards::Geometry.perimeter_core_underflow_order(perim_types).each do |st, is_explicit|
          break if need <= area_tol

          move = [perim_area[st], need].min
          next if move <= area_tol

          perim_area[st] -= move
          core_area[st] += move
          need -= move
          moves << { space_type: st, area: move, from: :perimeter, to: :core, reason: 'core underflow' }
          warnings << "Explicit perimeter space type #{OpenstudioStandards::Geometry.perimeter_core_space_type_name(st)} placed partly in the core to fill the interior." if is_explicit
        end
      end

      # Step 5 - distribute each type's band area across stories proportional to capacity
      c_s1 = story_entries.map { |s| (s[:length] - (2 * d)) * (s[:width] - (2 * d)) }
      p_s1 = story_entries.map { |s| 2 * d * (s[:length] + s[:width] - (2 * d)) }
      sum_mc = story_entries.each_with_index.sum { |s, i| s[:multiplier] * c_s1[i] }
      sum_mp = story_entries.each_with_index.sum { |s, i| s[:multiplier] * p_s1[i] }

      core_draw = Hash.new { |h, k| h[k] = Array.new(story_entries.size, 0.0) }
      perim_draw = Hash.new { |h, k| h[k] = Array.new(story_entries.size, 0.0) }
      space_types.each_key do |st|
        story_entries.each_index do |i|
          core_draw[st][i] = core_area[st] * c_s1[i] / sum_mc if core_area[st] > area_tol && sum_mc > area_tol
          perim_draw[st][i] = perim_area[st] * p_s1[i] / sum_mp if perim_area[st] > area_tol && sum_mp > area_tol
        end
      end

      # Step 6 - sliver consolidation (per band)
      OpenstudioStandards::Geometry.perimeter_core_consolidate!(perim_draw, story_entries, story_entries.map { min_run * d }, warnings, 'perimeter')
      OpenstudioStandards::Geometry.perimeter_core_consolidate!(core_draw, story_entries, story_entries.map { |s| min_run * (s[:width] - (2 * d)) }, warnings, 'core')

      # Steps 7 and 8 - facade seeding and rect emission, per story
      rects = []
      story_entries.each_with_index do |s, i|
        l = s[:length]
        w = s[:width]
        story_rects = []

        # Step 7 - facade seeding
        budget = { 'S' => d * (l - (2 * d)), 'N' => d * (l - (2 * d)), 'E' => d * w, 'W' => d * w }
        remaining = budget.dup
        assign = { 'S' => [], 'E' => [], 'N' => [], 'W' => [] }
        place = lambda do |st, area, facade|
          assign[facade] << { space_type: st, area: area }
          remaining[facade] -= area
        end

        perim_here = space_types.keys.select { |st| perim_draw[st][i] > area_tol }
        oriented = perim_here.select { |st| space_types[st][:orientation] }
        unoriented = perim_here - oriented

        oriented.each do |st|
          area_left = perim_draw[st][i]
          prefs = OpenstudioStandards::Geometry.perimeter_core_orientation_facades(space_types[st][:orientation])
          prefs.each do |f|
            break if area_left <= area_tol

            take = [area_left, remaining[f]].min
            next if take <= area_tol

            place.call(st, take, f)
            area_left -= take
          end
          next if area_left <= area_tol

          warnings << "Perimeter space type #{OpenstudioStandards::Geometry.perimeter_core_space_type_name(st)} preferred facades are full; overflow placed on adjacent facades."
          %w[S E N W].each do |f|
            break if area_left <= area_tol
            next if prefs.include?(f)

            take = [area_left, remaining[f]].min
            next if take <= area_tol

            place.call(st, take, f)
            area_left -= take
          end
        end

        unoriented.sort_by { |st| -perim_draw[st][i] }.each do |st|
          area_left = perim_draw[st][i]
          while area_left > area_tol
            f = %w[S E N W].max_by { |ff| remaining[ff] }
            take = [area_left, remaining[f]].min
            break if take <= area_tol

            place.call(st, take, f)
            area_left -= take
          end
        end

        # Step 8 - emit perimeter rects per facade
        x_cursor = d
        assign['S'].each do |seg|
          width_seg = seg[:area] / d
          story_rects << { space_type: seg[:space_type], band: :perimeter, facade: 'S', x0: x_cursor, y0: 0.0, x1: x_cursor + width_seg, y1: d }
          x_cursor += width_seg
        end
        y_cursor = 0.0
        assign['E'].each do |seg|
          height_seg = seg[:area] / d
          story_rects << { space_type: seg[:space_type], band: :perimeter, facade: 'E', x0: l - d, y0: y_cursor, x1: l, y1: y_cursor + height_seg }
          y_cursor += height_seg
        end
        x_cursor = d
        assign['N'].each do |seg|
          width_seg = seg[:area] / d
          story_rects << { space_type: seg[:space_type], band: :perimeter, facade: 'N', x0: x_cursor, y0: w - d, x1: x_cursor + width_seg, y1: w }
          x_cursor += width_seg
        end
        y_cursor = 0.0
        assign['W'].each do |seg|
          height_seg = seg[:area] / d
          story_rects << { space_type: seg[:space_type], band: :perimeter, facade: 'W', x0: 0.0, y0: y_cursor, x1: d, y1: y_cursor + height_seg }
          y_cursor += height_seg
        end

        # core slices along x, largest type first
        core_here = space_types.keys.select { |st| core_draw[st][i] > area_tol }.sort_by { |st| -core_draw[st][i] }
        x_cursor = d
        core_here.each do |st|
          width_seg = core_draw[st][i] / (w - (2 * d))
          story_rects << { space_type: st, band: :core, facade: nil, x0: x_cursor, y0: d, x1: x_cursor + width_seg, y1: w - d }
          x_cursor += width_seg
        end

        rects << story_rects
      end

      return { depth: d, fallback: nil, rects: rects, moves: moves, warnings: warnings }
    end

    # create perimeter and core footprints for a bar, positioning larger space types along
    # the facades and smaller/support space types in the interior core. Returns the same
    # footprints shape as {create_sliced_bar_multi_polygons}, one entry per building story.
    #
    # @param space_types [Hash] space_type => hash with :floor_area, :position, and
    #   optional :orientation (see {resolve_space_type_positions})
    # @param length [Double] length of the bar in meters
    # @param width [Double] width of the bar in meters
    # @param footprint_origin_point [OpenStudio::Point3d] center of the footprint
    # @param story_hash [Hash] building story information (space_origin_z, space_height,
    #   multiplier, and :partial_story_multiplier on the top story)
    # @param args [Hash] :perimeter_zone_depth, :perimeter_depth_min, :perimeter_depth_max
    #   (meters), optional :valid_bar_width_min (meters), optional :zone_resolver (callable
    #   taking (space_type, band, facade) and returning a zone-group label or nil)
    # @return [Array<Hash>] array of footprint hashes, one per story
    def self.create_perimeter_core_bar_polygons(space_types, length, width,
                                                footprint_origin_point = OpenStudio::Point3d.new(0.0, 0.0, 0.0),
                                                story_hash = {}, args = {})
      # build per-story dimensions and multipliers, reducing the top story if partial
      story_entries = []
      story_hash.each_with_index do |(_k, v), i|
        l = length
        w = width
        if i + 1 == story_hash.size && v[:partial_story_multiplier]
          edge_multiplier = Math.sqrt(v[:partial_story_multiplier])
          l *= edge_multiplier
          w *= edge_multiplier
        end
        story_entries << { length: l, width: w, multiplier: v[:multiplier] || 1 }
      end

      allocation = OpenstudioStandards::Geometry.perimeter_core_allocation(space_types, story_entries, args)
      allocation[:warnings].each do |msg|
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', msg)
      end

      # graceful fallback for a bar too narrow to have a core
      if allocation[:fallback] == :sliced
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', 'Perimeter and core layout is not possible for this bar; using sliced layout instead.')
        return OpenstudioStandards::Geometry.create_sliced_bar_multi_polygons(space_types, length, width, footprint_origin_point, story_hash, zone_resolver: args[:zone_resolver])
      end

      allocation[:moves].each do |m|
        area_ip = OpenStudio.convert(m[:area], 'm^2', 'ft^2').get
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Moved #{OpenStudio.toNeatString(area_ip, 0, true)} ft^2 of #{OpenstudioStandards::Geometry.perimeter_core_space_type_name(m[:space_type])} from #{m[:from]} to #{m[:to]} (#{m[:reason]}).")
      end
      depth_ip = OpenStudio.convert(allocation[:depth], 'm', 'ft').get
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Perimeter and core layout using a perimeter depth of #{OpenStudio.toNeatString(depth_ip, 1, true)} ft.")

      zone_resolver = args[:zone_resolver]
      footprints = []
      allocation[:rects].each_with_index do |story_rects, i|
        entry = story_entries[i]
        x_delta = footprint_origin_point.x - (entry[:length] / 2.0)
        y_delta = footprint_origin_point.y - (entry[:width] / 2.0)
        hash_of_point_vectors = {}
        counters = Hash.new(0)
        story_rects.each do |r|
          space_type = r[:space_type]
          polygon = OpenStudio::Point3dVector.new
          polygon << OpenStudio::Point3d.new(r[:x0] + x_delta, r[:y0] + y_delta, 0.0)
          polygon << OpenStudio::Point3d.new(r[:x0] + x_delta, r[:y1] + y_delta, 0.0)
          polygon << OpenStudio::Point3d.new(r[:x1] + x_delta, r[:y1] + y_delta, 0.0)
          polygon << OpenStudio::Point3d.new(r[:x1] + x_delta, r[:y0] + y_delta, 0.0)

          base = r[:band] == :core ? "#{space_type.name} Core" : "#{space_type.name} Perim #{r[:facade]}"
          counters[base] += 1
          name = "#{base} #{counters[base]}"

          zone_group = zone_resolver ? zone_resolver.call(space_type, r[:band], r[:facade]) : nil
          hash_of_point_vectors[name] = { space_type: space_type, polygon: polygon, zone_group: zone_group }
        end
        footprints << hash_of_point_vectors
      end

      return footprints
    end
  end
end
