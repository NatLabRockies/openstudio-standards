module OpenStudioGeometry
  # The bar massing engine — verbatim port of OpenstudioStandards::Geometry
  # create_bar + bar_hash_setup_run (the David Goldwasser bar lineage) plus
  # their five polygon/space helpers from geometry/create.rb. The DOE/DEER
  # building-type-ratio wrappers (create_bar_from_building_type_ratios etc.)
  # are deliberately NOT ported — they depend on CreateTypical building-type
  # metadata and Standard.build; the family-native ratio entry is
  # OpenStudioGeometry.bar (see openstudio_geometry.rb).
  module Bar
    def self.create_bar(model, bar_hash)
      # ---- 1. Inputs, warnings, and story flattening ----
      # make custom story hash when number of stories below grade > 0
      # @todo update this so have option basements are not below 0? (useful for simplifying existing model and maintaining z position relative to site shading)
      story_hash = {}
      eff_below = bar_hash[:num_stories_below_grade]
      eff_above = bar_hash[:num_stories_above_grade]
      footprint_origin_point = bar_hash[:center_of_footprint]
      typical_story_height = bar_hash[:floor_height]

      # warn about site shading
      if !model.getSite.shadingSurfaceGroups.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', 'The model has one or more site shading surfaces. New geometry may not be positioned where expected, it will be centered over the center of the original geometry.')
      end

      # flatten story_hash out to individual stories included in building area
      stories_flat = []
      stories_flat_counter = 0
      bar_hash[:stories].each_with_index do |(k, v), i|
        # k is invalid in some cases, old story object that has been removed, should be from low to high including basement
        # skip if source story insn't included in building area
        if v[:story_included_in_building_area].nil? || (v[:story_included_in_building_area] == true)

          # add to counter
          stories_flat_counter += v[:story_min_multiplier]

          flat_hash = {}
          flat_hash[:story_party_walls] = v[:story_party_walls]
          flat_hash[:below_partial_story] = v[:below_partial_story]
          flat_hash[:bottom_story_ground_exposed_floor] = v[:bottom_story_ground_exposed_floor]
          flat_hash[:top_story_exterior_exposed_roof] = v[:top_story_exterior_exposed_roof]
          if i < eff_below
            flat_hash[:story_type] = 'b'
            flat_hash[:multiplier] = 1
          elsif i == eff_below
            flat_hash[:story_type] = 'ground'
            flat_hash[:multiplier] = 1
          elsif stories_flat_counter == eff_below + eff_above.ceil
            flat_hash[:story_type] = 'top'
            flat_hash[:multiplier] = 1
          else
            flat_hash[:story_type] = 'mid'
            flat_hash[:multiplier] = v[:story_min_multiplier]
          end

          compare_hash = {}
          if !stories_flat.empty?
            stories_flat.last.each { |s, m| compare_hash[s] = flat_hash[s] if flat_hash[s] != m }
          end
          if (bar_hash[:story_multiplier_method] != 'None' && stories_flat.last == flat_hash) || (bar_hash[:story_multiplier_method] != 'None' && compare_hash.size == 1 && compare_hash.include?(:multiplier))
            stories_flat.last[:multiplier] += v[:story_min_multiplier]
          else
            stories_flat << flat_hash
          end
        end
      end

      # ---- 2. Build story_hash: origin z, height, and multiplier per story ----
      if bar_hash[:num_stories_below_grade] > 0

        # add in below grade levels (may want to add below grade multipliers at some point if we start running deep basements)
        eff_below.times do |i|
          story_hash["B#{i + 1}"] = { space_origin_z: footprint_origin_point.z - (typical_story_height * (i + 1)), space_height: typical_story_height, multiplier: 1 }
        end
      end

      # add in above grade levels
      if eff_above > 2
        story_hash['ground'] = { space_origin_z: footprint_origin_point.z, space_height: typical_story_height, multiplier: 1 }

        footprint_counter = 0
        effective_stories_counter = 1
        stories_flat.each do |hash|
          next if hash[:story_type] != 'mid'

          if footprint_counter == 0
            string = 'mid'
          else
            string = "mid#{footprint_counter + 1}"
          end
          story_hash[string] = { space_origin_z: footprint_origin_point.z + (typical_story_height * effective_stories_counter) + (typical_story_height * (hash[:multiplier] - 1) / 2.0), space_height: typical_story_height, multiplier: hash[:multiplier] }
          footprint_counter += 1
          effective_stories_counter += hash[:multiplier]
        end

        story_hash['top'] = { space_origin_z: footprint_origin_point.z + (typical_story_height * (eff_above.ceil - 1)), space_height: typical_story_height, multiplier: 1 }
      elsif eff_above > 1
        story_hash['ground'] = { space_origin_z: footprint_origin_point.z, space_height: typical_story_height, multiplier: 1 }
        story_hash['top'] = { space_origin_z: footprint_origin_point.z + (typical_story_height * (eff_above.ceil - 1)), space_height: typical_story_height, multiplier: 1 }
      else # one story only
        story_hash['ground'] = { space_origin_z: footprint_origin_point.z, space_height: typical_story_height, multiplier: 1 }
      end

      # ---- 3. Create footprint polygons per bar division method ----
      # create footprints
      if bar_hash[:bar_division_method] == 'Multiple Space Types - Simple Sliced'
        footprints = []
        story_hash.size.times do |i|
          # adjust size of bar of top story is not a full story
          if i + 1 == story_hash.size
            area_multiplier = (1.0 - bar_hash[:num_stories_above_grade].ceil + bar_hash[:num_stories_above_grade])
            edge_multiplier = Math.sqrt(area_multiplier)
            length = bar_hash[:length] * edge_multiplier
            width = bar_hash[:width] * edge_multiplier
          else
            length = bar_hash[:length]
            width = bar_hash[:width]
          end
          footprints << Bar.create_sliced_bar_simple_polygons(bar_hash[:space_types], length, width, bar_hash[:center_of_footprint])
        end

      elsif bar_hash[:bar_division_method] == 'Multiple Space Types - Individual Stories Sliced'

        # update story_hash for partial_story_above
        story_hash.each_with_index do |(k, v), i|
          # adjust size of bar of top story is not a full story
          if i + 1 == story_hash.size
            story_hash[k][:partial_story_multiplier] = (1.0 - bar_hash[:num_stories_above_grade].ceil + bar_hash[:num_stories_above_grade])
          end
        end

        footprints = Bar.create_sliced_bar_multi_polygons(bar_hash[:space_types], bar_hash[:length], bar_hash[:width], bar_hash[:center_of_footprint], story_hash)

      else
        footprints = []
        story_hash.size.times do |i|
          # adjust size of bar of top story is not a full story
          if i + 1 == story_hash.size
            area_multiplier = (1.0 - bar_hash[:num_stories_above_grade].ceil + bar_hash[:num_stories_above_grade])
            edge_multiplier = Math.sqrt(area_multiplier)
            length = bar_hash[:length] * edge_multiplier
            width = bar_hash[:width] * edge_multiplier
          else
            length = bar_hash[:length]
            width = bar_hash[:width]
          end
          # perimeter defaults to 15 ft
          footprints << Bar.create_core_and_perimeter_polygons(length, width, bar_hash[:center_of_footprint])
        end

        # set primary space type to building default space type
        space_types = bar_hash[:space_types].sort_by { |k, v| v[:floor_area] }
        if space_types.last.first.class.to_s == 'OpenStudio::Model::SpaceType'
          model.getBuilding.setSpaceType(space_types.last.first)
        end

      end

      # ---- 4. Make spaces and stories from polygons ----
      # make spaces from polygons
      new_spaces = Bar.create_spaces_from_polygons(model, footprints, bar_hash[:floor_height], bar_hash[:num_stories], bar_hash[:center_of_footprint], story_hash)

      # ---- 5. Surface cleanup, intersection, and matching ----
      # put all of the spaces in the model into a vector for intersection and surface matching
      spaces = OpenStudio::Model::SpaceVector.new
      model.getSpaces.sort.each do |space|
        spaces << space
      end

      # flag for intersection and matching type
      diagnostic_intersect = true

      # only intersect if make_mid_story_surfaces_adiabatic false
      if diagnostic_intersect

        model.getPlanarSurfaces.sort.each do |surface|
          array = []
          vertices = surface.vertices
          fixed = false
          vertices.each do |vertex|
            next if fixed

            if array.include?(vertex)
              # create a new set of vertices
              new_vertices = OpenStudio::Point3dVector.new
              array_b = []
              surface.vertices.each do |vertex_b|
                next if array_b.include?(vertex_b)

                new_vertices << vertex_b
                array_b << vertex_b
              end
              surface.setVertices(new_vertices)
              num_removed = vertices.size - surface.vertices.size
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', "#{surface.name} has duplicate vertices. Started with #{vertices.size} vertices, removed #{num_removed}.")
              fixed = true
            else
              array << vertex
            end
          end
        end

        # remove collinear points in a surface
        model.getPlanarSurfaces.sort.each do |surface|
          new_vertices = OpenStudio.removeCollinear(surface.vertices)
          starting_count = surface.vertices.size
          final_count = new_vertices.size
          if final_count < starting_count
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', "Removing #{starting_count - final_count} collinear vertices from #{surface.name}.")
            surface.setVertices(new_vertices)
          end
        end

        # remove duplicate surfaces in a space (should be done after remove duplicate and collinear points)
        model.getSpaces.sort.each do |space|
          # secondary array to compare against
          surfaces_b = space.surfaces.sort

          space.surfaces.sort.each do |surface_a|
            # delete from secondary array
            surfaces_b.delete(surface_a)

            surfaces_b.each do |surface_b|
              next if surface_a == surface_b # dont' test against same surface

              if surface_a.equalVertices(surface_b)
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', "#{surface_a.name} and #{surface_b.name} in #{space.name} have duplicate geometry, removing #{surface_b.name}.")
                surface_b.remove
              elsif surface_a.reverseEqualVertices(surface_b)
                # @todo add logic to determine which face naormal is reversed and which is correct
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', "#{surface_a.name} and #{surface_b.name} in #{space.name} have reversed geometry, removing #{surface_b.name}.")
                surface_b.remove
              end
            end
          end
        end

        if (bar_hash[:make_mid_story_surfaces_adiabatic])
          # elsif bar_hash[:double_loaded_corridor] # only intersect spaces in each story, not between wtory
          model.getBuilding.buildingStories.sort.each do |story|
            # intersect and surface match two pair by pair
            spaces_b = story.spaces.sort
            # looping through vector of each space
            story.spaces.sort.each do |space_a|
              spaces_b.delete(space_a)
              spaces_b.each do |space_b|
                spaces_temp = OpenStudio::Model::SpaceVector.new
                spaces_temp << space_a
                spaces_temp << space_b

                # intersect and sort
                OpenStudio::Model.intersectSurfaces(spaces_temp)
                OpenStudio::Model.matchSurfaces(spaces_temp)
              end
            end
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Intersecting and matching surfaces in story #{story.name}, this will create additional geometry.")
          end
        else
          # intersect and surface match two pair by pair
          spaces_b = model.getSpaces.sort
          # looping through vector of each space
          model.getSpaces.sort.each do |space_a|
            spaces_b.delete(space_a)
            spaces_b.each do |space_b|
              # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Intersecting and matching surfaces between #{space_a.name} and #{space.name}")
              spaces_temp = OpenStudio::Model::SpaceVector.new
              spaces_temp << space_a
              spaces_temp << space_b
              # intersect and sort
              OpenStudio::Model.intersectSurfaces(spaces_temp)
              OpenStudio::Model.matchSurfaces(spaces_temp)
            end
          end
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', 'Intersecting and matching surfaces in model, this will create additional geometry.')
        end
      else
        if (bar_hash[:make_mid_story_surfaces_adiabatic])
          # elsif bar_hash[:double_loaded_corridor] # only intersect spaces in each story, not between wtory
          model.getBuilding.buildingStories.sort.each do |story|
            story_spaces = OpenStudio::Model::SpaceVector.new
            story.spaces.sort.each do |space|
              story_spaces << space
            end

            # intersect and sort
            OpenStudio::Model.intersectSurfaces(story_spaces)
            OpenStudio::Model.matchSurfaces(story_spaces)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Intersecting and matching surfaces in story #{story.name}, this will create additional geometry.")
          end
        else
          # intersect surfaces
          # (when bottom floor has many space types and one above doesn't will end up with heavily subdivided floor. Maybe use adiabatic and don't intersect floor/ceilings)
          intersect_surfaces = true
          if intersect_surfaces
            OpenStudio::Model.intersectSurfaces(spaces)
            OpenStudio::Model.matchSurfaces(spaces)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', 'Intersecting and matching surfaces in model, this will create additional geometry.')
          end
        end
      end

      # ---- 6. Boundary conditions: below-grade ground and mid-story adiabatic walls ----
      # set boundary conditions if not already set when geometry was created
      # @todo update this to use space original z value vs. story name
      if bar_hash[:num_stories_below_grade] > 0
        model.getBuildingStorys.sort.each do |story|
          next if !story.name.to_s.include?('Story B')

          story.spaces.sort.each do |space|
            next if !new_spaces.include?(space)

            space.surfaces.sort.each do |surface|
              next if surface.surfaceType != 'Wall'
              next if surface.outsideBoundaryCondition != 'Outdoors'

              surface.setOutsideBoundaryCondition('Ground')
            end
          end
        end
      end

      # set wall boundary condtions to adiabatic if using make_mid_story_surfaces_adiabatic prior to windows being made
      if bar_hash[:make_mid_story_surfaces_adiabatic]

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', 'Finding non-exterior walls and setting boundary condition to adiabatic')

        # need to organize by story incase top story is partial story
        # should also be only for a single bar
        story_bounding = {}
        missed_match_count = 0

        # gather new spaces by story
        new_spaces.each do |space|
          story = space.buildingStory.get
          if story_bounding.key?(story)
            story_bounding[story][:spaces] << space
          else
            story_bounding[story] = { spaces: [space] }
          end
        end

        # get bounding box for each story
        story_bounding.each do |story, v|
          # get bounding_box
          bounding_box = OpenStudio::BoundingBox.new
          v[:spaces].each do |space|
            space.surfaces.each do |space_surface|
              bounding_box.addPoints(space.transformation * space_surface.vertices)
            end
          end
          min_x = bounding_box.minX.get
          min_y = bounding_box.minY.get
          max_x = bounding_box.maxX.get
          max_y = bounding_box.maxY.get
          ext_wall_toll = 0.01

          # check surfaces again against min/max and change to adiabatic if not fully on one min or max x or y
          # todo - may need to look at aidiabiatc constructions in downstream measure. Some may be exterior party wall others may be interior walls
          v[:spaces].each do |space|
            space.surfaces.each do |space_surface|
              next if space_surface.surfaceType != 'Wall'
              next if space_surface.outsideBoundaryCondition == 'Surface' # if if found a match leave it alone, don't change to adiabiatc

              surface_bounding_box = OpenStudio::BoundingBox.new
              surface_bounding_box.addPoints(space.transformation * space_surface.vertices)
              surface_on_outside = false
              # check xmin
              if (surface_bounding_box.minX.get - min_x).abs < ext_wall_toll && (surface_bounding_box.maxX.get - min_x).abs < ext_wall_toll then surface_on_outside = true end
              # check xmax
              if (surface_bounding_box.minX.get - max_x).abs < ext_wall_toll && (surface_bounding_box.maxX.get - max_x).abs < ext_wall_toll then surface_on_outside = true end
              # check ymin
              if (surface_bounding_box.minY.get - min_y).abs < ext_wall_toll && (surface_bounding_box.maxY.get - min_y).abs < ext_wall_toll then surface_on_outside = true end
              # check ymax
              if (surface_bounding_box.minY.get - max_y).abs < ext_wall_toll && (surface_bounding_box.maxY.get - max_y).abs < ext_wall_toll then surface_on_outside = true end

              # change if not exterior
              if !surface_on_outside
                space_surface.setOutsideBoundaryCondition('Adiabatic')
                missed_match_count += 1
              end
            end
          end
        end

        if missed_match_count > 0
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "#{missed_match_count} surfaces that were exterior appear to be interior walls and had boundary condition chagned to adiabiatic.")
        end
      end

      # ---- 7. Party walls and window-to-wall ratios by story and facade ----
      # sort stories (by name for now but need better way)
      sorted_stories = {}
      new_spaces.each do |space|
        next if !space.buildingStory.is_initialized

        story = space.buildingStory.get
        if !sorted_stories.key?(name.to_s)
          sorted_stories[story.name.to_s] = story
        end
      end

      # flag space types that have wwr overrides
      space_type_wwr_overrides = {}

      # loop through building stories, spaces, and surfaces
      sorted_stories.sort.each_with_index do |(key, story), i|
        # flag for adiabatic floor if building doesn't have ground exposed floor
        if stories_flat[i][:bottom_story_ground_exposed_floor] == false
          adiabatic_floor = true
        end
        # flag for adiabatic roof if building doesn't have exterior exposed roof
        if stories_flat[i][:top_story_exterior_exposed_roof] == false
          adiabatic_ceiling = true
        end

        # make all mid story floor and ceilings adiabatic if requested
        if bar_hash[:make_mid_story_surfaces_adiabatic]
          if i > 0
            adiabatic_floor = true
          end
          if i < sorted_stories.size - 1
            adiabatic_ceiling = true
          end
        end

        # flag orientations for this story to recieve party walls
        party_wall_facades = stories_flat[i][:story_party_walls]

        story.spaces.each do |space|
          next if !new_spaces.include?(space)

          space.surfaces.each do |surface|
            # set floor to adiabatic if requited
            if (adiabatic_floor && surface.surfaceType == 'Floor') || (adiabatic_ceiling && surface.surfaceType == 'RoofCeiling')
              surface.setOutsideBoundaryCondition('Adiabatic')
            end

            # skip of not exterior wall
            next if surface.surfaceType != 'Wall'
            next if surface.outsideBoundaryCondition != 'Outdoors'

            # get the absolute azimuth for the surface so we can categorize it
            absolute_azimuth = OpenStudio.convert(surface.azimuth, 'rad', 'deg').get + surface.space.get.directionofRelativeNorth + model.getBuilding.northAxis
            absolute_azimuth = absolute_azimuth % 360.0 # should result in value between 0 and 360
            absolute_azimuth = absolute_azimuth.round(5) # this was creating issues at 45 deg angles with opposing facades

            # target wwr values that may be changed for specific space types
            wwr_n = bar_hash[:building_wwr_n]
            wwr_e = bar_hash[:building_wwr_e]
            wwr_s = bar_hash[:building_wwr_s]
            wwr_w = bar_hash[:building_wwr_w]

            # look for space type specific wwr values
            if surface.space.is_initialized && surface.space.get.spaceType.is_initialized
              space_type = surface.space.get.spaceType.get

              # see if space type has wwr value
              bar_hash[:space_types].each do |k, v|
                if v.key?(:space_type) && space_type == v[:space_type] && v.key?(:wwr)
                  # if matching space type specifies a wwr then override the orientation specific recommendations for this surface.
                  wwr_n = v[:wwr]
                  wwr_e = v[:wwr]
                  wwr_s = v[:wwr]
                  wwr_w = v[:wwr]
                  space_type_wwr_overrides[space_type] = v[:wwr]
                end
              end
            end

            # add fenestration (wwr for now, maybe overhang and overhead doors later)
            if (absolute_azimuth >= 315.0) || (absolute_azimuth < 45.0)
              if party_wall_facades.include?('north')
                surface.setOutsideBoundaryCondition('Adiabatic')
              else
                surface.setWindowToWallRatio(wwr_n)
              end
            elsif (absolute_azimuth >= 45.0) && (absolute_azimuth < 135.0)
              if party_wall_facades.include?('east')
                surface.setOutsideBoundaryCondition('Adiabatic')
              else
                surface.setWindowToWallRatio(wwr_e)
              end
            elsif (absolute_azimuth >= 135.0) && (absolute_azimuth < 225.0)
              if party_wall_facades.include?('south')
                surface.setOutsideBoundaryCondition('Adiabatic')
              else
                surface.setWindowToWallRatio(wwr_s)
              end
            elsif (absolute_azimuth >= 225.0) && (absolute_azimuth < 315.0)
              if party_wall_facades.include?('west')
                surface.setOutsideBoundaryCondition('Adiabatic')
              else
                surface.setWindowToWallRatio(wwr_w)
              end
            else
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create', "Unexpected value of facade: #{absolute_azimuth}.")
              return false
            end
          end
        end
      end

      # ---- 8. Report wwr overrides and final floor area ----
      # report space types with custom wwr values
      space_type_wwr_overrides.each do |space_type, wwr|
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "For #{space_type.name} the default building wwr was replaced with a space type specfic value of #{wwr}")
      end

      new_floor_area_si = 0.0
      new_spaces.each do |space|
        new_floor_area_si += space.floorArea * space.multiplier
      end
      new_floor_area_ip = OpenStudio.convert(new_floor_area_si, 'm^2', 'ft^2').get

      final_floor_area_ip = OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get
      if new_floor_area_ip == final_floor_area_ip
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Created bar envelope with floor area of #{OpenStudio.toNeatString(new_floor_area_ip, 0, true)} ft^2.")
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Created bar envelope with floor area of #{OpenStudio.toNeatString(new_floor_area_ip, 0, true)} ft^2. Total building area is #{OpenStudio.toNeatString(final_floor_area_ip, 0, true)} ft^2.")
      end

      return new_spaces
    end

    # give info messages bar hash for create_bar method
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param args [Hash] user arguments
    # @param length [Double] length of building in meters
    # @param width [Double] width of building in meters
    # @param floor_height [Double] floor height in meters
    # @param center_of_footprint [OpenStudio::Point3d] center of footprint
    # @param space_types_hash [Hash] space type hash
    # @param num_stories [Double] number of stories
    # @return [Boolean] returns true if successful, false if not
    def self.bar_hash_setup_run(model, args, length, width, floor_height, center_of_footprint, space_types_hash, num_stories)
      # create envelope
      # populate bar_hash and create envelope with data from envelope_data_hash and user arguments
      bar_hash = {}
      bar_hash[:length] = length
      bar_hash[:width] = width
      bar_hash[:num_stories_below_grade] = args[:num_stories_below_grade]
      bar_hash[:num_stories_above_grade] = args[:num_stories_above_grade]
      bar_hash[:floor_height] = floor_height
      bar_hash[:center_of_footprint] = center_of_footprint
      bar_hash[:bar_division_method] = args[:bar_division_method]
      bar_hash[:story_multiplier_method] = args[:story_multiplier_method]
      bar_hash[:make_mid_story_surfaces_adiabatic] = args[:make_mid_story_surfaces_adiabatic]
      bar_hash[:space_types] = space_types_hash
      bar_hash[:building_wwr_n] = args[:wwr]
      bar_hash[:building_wwr_s] = args[:wwr]
      bar_hash[:building_wwr_e] = args[:wwr]
      bar_hash[:building_wwr_w] = args[:wwr]

      # round up non integer stoires to next integer
      num_stories_round_up = num_stories.ceil
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', "Making bar with length of #{OpenStudio.toNeatString(OpenStudio.convert(length, 'm', 'ft').get, 0, true)} ft and width of #{OpenStudio.toNeatString(OpenStudio.convert(width, 'm', 'ft').get, 0, true)} ft")

      # party_walls_array to be used by orientation specific or fractional party wall values
      party_walls_array = [] # this is an array of arrays, where each entry is effective building story with array of directions

      if args[:party_wall_stories_north] + args[:party_wall_stories_south] + args[:party_wall_stories_east] + args[:party_wall_stories_west] > 0

        # loop through effective number of stories add orientation specific party walls per user arguments
        num_stories_round_up.times do |i|
          test_value = i + 1 - bar_hash[:num_stories_below_grade]

          array = []
          if args[:party_wall_stories_north] >= test_value
            array << 'north'
          end
          if args[:party_wall_stories_south] >= test_value
            array << 'south'
          end
          if args[:party_wall_stories_east] >= test_value
            array << 'east'
          end
          if args[:party_wall_stories_west] >= test_value
            array << 'west'
          end

          # populate party_wall_array for this story
          party_walls_array << array
        end
      end

      # calculate party walls if using party_wall_fraction method
      if args[:party_wall_fraction] > 0 && !party_walls_array.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Geometry.Create', 'Both orientation and fractional party wall values arguments were populated, will ignore fractional party wall input')
      elsif args[:party_wall_fraction] > 0
        # orientation of long and short side of building will vary based on building rotation

        # full story ext wall area
        typical_length_facade_area = length * floor_height
        typical_width_facade_area = width * floor_height

        # top story ext wall area, may be partial story
        partial_story_multiplier = (1.0 - args[:num_stories_above_grade].ceil + args[:num_stories_above_grade])
        area_multiplier = partial_story_multiplier
        edge_multiplier = Math.sqrt(area_multiplier)
        top_story_length = length * edge_multiplier
        top_story_width = width * edge_multiplier
        top_story_length_facade_area = top_story_length * floor_height
        top_story_width_facade_area = top_story_width * floor_height

        total_exterior_wall_area = (2 * (length + width) * (args[:num_stories_above_grade].ceil - 1.0) * floor_height) + (2 * (top_story_length + top_story_width) * floor_height)
        target_party_wall_area = total_exterior_wall_area * args[:party_wall_fraction]

        width_counter = 0
        width_area = 0.0
        facade_area = typical_width_facade_area
        until (width_area + facade_area >= target_party_wall_area) || (width_counter == (args[:num_stories_above_grade].ceil * 2))
          # update facade area for top story
          if (width_counter == (args[:num_stories_above_grade].ceil - 1)) || (width_counter == ((args[:num_stories_above_grade].ceil * 2) - 1))
            facade_area = top_story_width_facade_area
          else
            facade_area = typical_width_facade_area
          end

          width_counter += 1
          width_area += facade_area

        end
        width_area_remainder = target_party_wall_area - width_area

        length_counter = 0
        length_area = 0.0
        facade_area = typical_length_facade_area
        until (length_area + facade_area >= target_party_wall_area) || (length_counter == args[:num_stories_above_grade].ceil * 2)
          # update facade area for top story
          if (length_counter == (args[:num_stories_above_grade].ceil - 1)) || (length_counter == ((args[:num_stories_above_grade].ceil * 2) - 1))
            facade_area = top_story_length_facade_area
          else
            facade_area = typical_length_facade_area
          end

          length_counter += 1
          length_area += facade_area
        end
        length_area_remainder = target_party_wall_area - length_area

        # get rotation and best fit to adjust orientation for fraction party wall
        rotation = args[:building_rotation] % 360.0 # should result in value between 0 and 360
        card_dir_array = [0.0, 90.0, 180.0, 270.0, 360.0]
        # reverse array to properly handle 45, 135, 225, and 315
        best_fit = card_dir_array.reverse.min_by { |x| (x.to_f - rotation).abs }

        if ![90.0, 270.0].include? best_fit
          width_card_dir = ['east', 'west']
          length_card_dir = ['north', 'south']
        else # if rotation is closest to 90 or 270 then reverse which orientation is used for length and width
          width_card_dir = ['north', 'south']
          length_card_dir = ['east', 'west']
        end

        # if dont' find enough on short sides
        if width_area_remainder <= typical_length_facade_area

          num_stories_round_up.times do |i|
            if i + 1 <= args[:num_stories_below_grade]
              party_walls_array << []
              next
            end
            if i + 1 - args[:num_stories_below_grade] <= width_counter
              if i + 1 - args[:num_stories_below_grade] <= width_counter - args[:num_stories_above_grade]
                party_walls_array << width_card_dir
              else
                party_walls_array << [width_card_dir.first]
              end
            else
              party_walls_array << []
            end
          end

        else
          # use long sides instead
          num_stories_round_up.times do |i|
            if i + 1 <= args[:num_stories_below_grade]
              party_walls_array << []
              next
            end
            if i + 1 - args[:num_stories_below_grade] <= length_counter
              if i + 1 - args[:num_stories_below_grade] <= length_counter - args[:num_stories_above_grade]
                party_walls_array << length_card_dir
              else
                party_walls_array << [length_card_dir.first]
              end
            else
              party_walls_array << []
            end
          end

        end
        # @todo currently won't go past making two opposing sets of walls party walls. Info and registerValue are after create_bar in measure.rb
      end

      # populate bar hash with story information
      bar_hash[:stories] = {}
      num_stories_round_up.times do |i|
        if party_walls_array.empty?
          party_walls = []
        else
          party_walls = party_walls_array[i]
        end

        # add below_partial_story
        if num_stories.ceil > num_stories && i == num_stories_round_up - 2
          below_partial_story = true
        else
          below_partial_story = false
        end

        # bottom_story_ground_exposed_floor and top_story_exterior_exposed_roof already setup as bool
        bar_hash[:stories]["key #{i}"] = { story_party_walls: party_walls, story_min_multiplier: 1, story_included_in_building_area: true, below_partial_story: below_partial_story, bottom_story_ground_exposed_floor: args[:bottom_story_ground_exposed_floor], top_story_exterior_exposed_roof: args[:top_story_exterior_exposed_roof] }
      end

      # create bar
      new_spaces = create_bar(model, bar_hash)

      # check expect roof and wall area
      target_footprint = bar_hash[:length] * bar_hash[:width]
      ground_floor_area = 0.0
      roof_area = 0.0
      new_spaces.each do |space|
        space.surfaces.each do |surface|
          if surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Ground'
            ground_floor_area += surface.netArea
          elsif surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'
            roof_area += surface.netArea
          end
        end
      end
      # @todo extend to address when top and or bottom story are not exposed via argument
      if ground_floor_area > target_footprint + 0.001 || roof_area > target_footprint + 0.001
        # OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create', "Ground exposed floor or Roof area is larger than footprint, likely inter-floor surface matching and intersection error.")
        # return false

        # not providing adiabatic work around when top story is partial story.
        if args[:num_stories_above_grade].to_i != args[:num_stories_above_grade].ceil
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Geometry.Create', 'Ground exposed floor or Roof area is larger than footprint, likely inter-floor surface matching and intersection error.')
          return false
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Geometry.Create', 'Ground exposed floor or Roof area is larger than footprint, likely inter-floor surface matching and intersection error, altering impacted surfaces boundary condition to be adiabatic.')
          match_error = true
        end
      else
        match_error = false
      end

      # @todo should be able to remove this fix after OpenStudio intersection issue is fixed. At that time turn the above message into an error with return false after it
      return true unless match_error

      # identify z value of top and bottom story
      bottom_story = nil
      top_story = nil
      new_spaces.each do |space|
        story = space.buildingStory.get
        nom_z = story.nominalZCoordinate.get
        if bottom_story.nil?
          bottom_story = nom_z
        elsif bottom_story > nom_z
          bottom_story = nom_z
        end
        if top_story.nil?
          top_story = nom_z
        elsif top_story < nom_z
          top_story = nom_z
        end
      end

      # change boundary condition and intersection as needed.
      new_spaces.each do |space|
        if space.buildingStory.get.nominalZCoordinate.get > bottom_story
          # change floors
          space.surfaces.each do |surface|
            next if !(surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Ground')

            surface.setOutsideBoundaryCondition('Adiabatic')
          end
        end
        if space.buildingStory.get.nominalZCoordinate.get < top_story
          # change ceilings
          space.surfaces.each do |surface|
            next if !(surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors')

            surface.setOutsideBoundaryCondition('Adiabatic')
          end
        end
      end
    end

    # create core and perimeter polygons for a rectangular single-story footprint
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
          # only apply test_a when there is more than one space type on this story; if there is only one,
          # shifting it out would leave space_types_local_count empty and crash create_sliced_bar_simple_polygons
          if test_a && space_types_local_count.size > 1

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
        footprints << Bar.create_sliced_bar_simple_polygons(space_types_local_count, length, width, footprint_origin_point)
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
      # ---- 1. Setup: slice direction, perimeter depth, and bar corner points ----
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

      # ---- 2. Space type areas, sort order, and bar-end sizing rules ----
      # total building floor area to calculate ratios from space type floor areas
      total_floor_area = 0.0
      space_types.each do |space_type, space_type_hash|
        total_floor_area += space_type_hash[:floor_area]
      end

      # sort array by floor area but shift largest object to front
      space_types = space_types.sort_by { |k, v| v[:floor_area] }
      # guard against empty space_types (e.g. when all space types were slivers removed by caller)
      return hash_of_point_vectors if space_types.empty?
      space_types.insert(0, space_types.delete_at(space_types.size - 1)) # .to_h

      # min and max bar end values
      min_bar_end_multiplier = 0.75
      max_bar_end_multiplier = 1.5

      # ---- 3. Per space type: slice widths and double-loaded corridor data ----
      # sort_by results in arrays with two items , first is key, second is hash value
      re_apply_largest_space_type_at_end = false
      max_reduction = nil # used when looping through section_hash_for_space_type if first space type needs to also be at far end of bar
      space_types.each do |space_type, space_type_hash|
        # setup end perimeter zones if needed
        start_perimeter_width_deduction = 0.0
        end_perimeter_width_deduction = 0.0
        if space_type == space_types.first[0]
          if ([length, width].max * space_type_hash[:floor_area] / total_floor_area) > (max_bar_end_multiplier * perimeter_zone_depth)
            start_perimeter_width_deduction = perimeter_zone_depth
          end
          # see if last space type is too small for perimeter. If it is then save some of this space type
          if ([length, width].max * space_types.last[1][:floor_area] / total_floor_area )< (perimeter_zone_depth * min_bar_end_multiplier)
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

        # ---- 4. Generate polygons for each section (perimeter/core, both slice directions) ----
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
          space = Bar.create_space_from_polygon(model, space_data[:polygon].first, space_data[:polygon], options)
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
