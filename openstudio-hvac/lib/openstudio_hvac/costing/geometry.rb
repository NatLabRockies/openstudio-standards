module OpenStudioHVAC
  module Costing
    # SDK-only ports of the legacy BTAP/NECB geometry helpers that drive the
    # distance-based costing items (header piping, utility runs, flues, trunk ducts,
    # terminal piping/wiring runs).
    #
    # Deviations from legacy (documented):
    # - "conditioned, non-plenum" is proxied by Space#partofTotalFloorArea (legacy reads
    #   NECB space-type setpoint schedules from standards_data, which the gem does not
    #   depend on). Plenums/attics are excluded from floor area in both schemes.
    # - The mechanical room can be pinned explicitly via the mech_room_name option on
    #   OpenStudioHVAC.cost; otherwise the legacy election runs: a space whose space-type
    #   name contains 'Electrical/Mechanical', else the lowest-storey space closest to the
    #   building centre.
    module Geometry
      module_function

      M_TO_FT = 3.2808398950131235

      def conditioned?(space)
        space.partofTotalFloorArea
      end

      # Area-weighted centroid of a space's floor (lowest) surfaces, in building coords.
      def space_floor_centroid(space)
        surfaces = space.surfaces
        return nil if surfaces.empty?

        min_surf = surfaces.min_by { |s| s.centroid.z.to_f }
        cx = cy = area = 0.0
        surfaces.each do |s|
          next unless s.centroid.z.to_f == min_surf.centroid.z.to_f

          cx += s.centroid.x.to_f * s.grossArea.to_f
          cy += s.centroid.y.to_f * s.grossArea.to_f
          area += s.grossArea.to_f
        end
        return nil if area.zero?

        [cx / area + space.xOrigin.to_f, cy / area + space.yOrigin.to_f,
         min_surf.centroid.z.to_f + space.zOrigin.to_f]
      end

      # Legacy find_mech_room: explicit 'Electrical/Mechanical' space type wins; otherwise
      # the lowest-storey conditioned space closest to the area-weighted building centre.
      # @return [Hash] { space:, centroid: [x,y,z] } or nil (no conditioned spaces)
      def mech_room(model, mech_room_name: nil)
        candidates = []
        centre = [0.0, 0.0, 0.0]
        model.getSpaces.sort_by(&:nameString).each do |space|
          next unless conditioned?(space)

          centroid = space_floor_centroid(space)
          next if centroid.nil?

          area = space.floorArea.to_f
          centre[0] += centroid[0] * area
          centre[1] += centroid[1] * area
          centre[2] += area
          candidates << { space: space, centroid: centroid }
        end
        return nil if candidates.empty?

        if mech_room_name
          named = candidates.find { |c| c[:space].nameString == mech_room_name }
          return named if named
        end
        typed = candidates.find do |c|
          st = c[:space].spaceType
          st.is_initialized && st.get.nameString.include?('Electrical/Mechanical')
        end
        return typed if typed

        centre[0] /= centre[2]
        centre[1] /= centre[2]
        lowest_z = candidates.map { |c| c[:centroid][2] }.min
        candidates.select { |c| c[:centroid][2] == lowest_z }
                  .min_by { |c| Math.sqrt((c[:centroid][0] - centre[0])**2 + (c[:centroid][1] - centre[1])**2).round(1) }
      end

      # Legacy find_highest_roof_centre: area-weighted centroid of the highest outdoor
      # roof/ceiling surfaces. @return [Array(Float,Float,Float)] or nil
      def highest_roof_centroid(model)
        tol = 6
        spaces_info = []
        max_height = -Float::INFINITY
        model.getSpaces.sort_by(&:nameString).each do |space|
          surfaces = space.surfaces
          next unless surfaces.any? { |s| s.surfaceType.upcase == 'ROOFCEILING' && s.outsideBoundaryCondition.upcase == 'OUTDOORS' }

          max_surf = surfaces.max_by { |s| s.centroid.z.to_f.round(tol) }
          cx = cy = area = 0.0
          surfaces.each do |s|
            next unless s.centroid.z.to_f.round(tol) == max_surf.centroid.z.to_f.round(tol)

            cx += s.centroid.x.to_f * s.grossArea.to_f
            cy += s.centroid.y.to_f * s.grossArea.to_f
            area += s.grossArea.to_f
          end
          next if area.zero?

          z = max_surf.centroid.z.to_f + space.zOrigin.to_f
          spaces_info << { x: cx / area + space.xOrigin.to_f, y: cy / area + space.yOrigin.to_f, z: z, area: area }
          max_height = z.round(tol) if z.round(tol) > max_height
        end
        return nil if spaces_info.empty?

        top = spaces_info.select { |i| i[:z].round(tol) == max_height }
        area = top.sum { |i| i[:area] }
        [top.sum { |i| i[:x] * i[:area] } / area, top.sum { |i| i[:y] * i[:area] } / area, max_height]
      end

      # Legacy get_lowest_space: the lowest roof/ceiling centroid among conditioned spaces
      # (the trunk duct drops from the roof centroid to this height).
      def lowest_roof_centroid(model)
        cents = []
        model.getSpaces.sort_by(&:nameString).each do |space|
          next unless conditioned?(space)

          space.surfaces.each do |surface|
            next unless surface.surfaceType.upcase == 'ROOFCEILING'

            cents << [surface.centroid.x.to_f + space.xOrigin.to_f,
                      surface.centroid.y.to_f + space.yOrigin.to_f,
                      surface.centroid.z.to_f + space.zOrigin.to_f]
          end
        end
        cents.min_by { |c| c[2] }
      end

      def nominal_floor_height_m(model)
        building = model.getBuilding
        return building.nominalFloortoFloorHeight.get if building.nominalFloortoFloorHeight.is_initialized

        volume = building.airVolume
        floor_area = building.conditionedFloorArea.is_initialized ? building.conditionedFloorArea.get : building.floorArea
        return 0.0 if floor_area < 0.01

        volume / floor_area
      end

      def above_ground_storeys(model)
        declared = model.getBuilding.standardsNumberOfAboveGroundStories
        return declared.get if declared.is_initialized

        model.getBuildingStorys.count do |story|
          story.spaces.any? { |s| s.zOrigin.to_f >= -0.01 }
        end.clamp(1, 1000)
      end

      # Legacy getGeometryData: distances used by plant utility runs and header piping.
      # All distances in FEET (matching legacy's unit convention downstream).
      # @return [Hash] util_dist_ft, ht_roof_ft, flr_height_ft, horz_dist_ft, storeys,
      #   mech_room_in_basement, mech_room; or nil when geometry cannot be resolved.
      def building_data(model, mech_room_name: nil)
        room = mech_room(model, mech_room_name: mech_room_name)
        return nil if room.nil?

        flr_height = nominal_floor_height_m(model)
        storeys = above_ground_storeys(model)
        story = model.getBuildingStorys.find { |st| st.spaces.any? { |sp| sp.nameString == room[:space].nameString } }
        edge = story ? story_cent_to_edge(story, [room[:centroid][0], room[:centroid][1]]) : nil
        horz = edge ? edge[:start_point][:dist] : 0.0

        z = room[:centroid][2]
        in_basement = z.negative?
        if in_basement
          ht_roof = (storeys + 1) * flr_height
          util = flr_height + horz
        elsif z.zero?
          ht_roof = storeys * flr_height
          util = horz
        else
          ht_roof = (storeys - (z / flr_height).round) * flr_height
          util = ht_roof + horz
        end

        { util_dist_ft: util * M_TO_FT, ht_roof_ft: ht_roof * M_TO_FT,
          flr_height_ft: flr_height * M_TO_FT, horz_dist_ft: horz * M_TO_FT,
          storeys: storeys, mech_room_in_basement: in_basement, mech_room: room }
      end

      # Legacy thermal_zone_get_centroid_per_floor: the zone's conditioned spaces grouped
      # by building storey with the area-weighted ceiling centroid of each group.
      # @return [Array<Hash>] [{ story_name:, spaces:, centroid: [x,y,z], ceiling_area: }]
      def zone_story_centroids(zone)
        stories = {}
        zone.spaces.sort_by(&:nameString).each do |space|
          next unless conditioned?(space)

          story = space.buildingStory
          story_name = story.is_initialized ? story.get.nameString : 'none'
          (stories[story_name] ||= []) << space
        end
        stories.map do |story_name, spaces|
          cx = cy = cz = area = 0.0
          spaces.each do |space|
            sx = sy = sz = sarea = 0.0
            space.surfaces.each do |surface|
              next unless surface.surfaceType.upcase == 'ROOFCEILING'

              sx += surface.centroid.x.to_f * surface.grossArea.to_f
              sy += surface.centroid.y.to_f * surface.grossArea.to_f
              sz += surface.centroid.z.to_f * surface.grossArea.to_f
              sarea += surface.grossArea.to_f
            end
            next if sarea.zero?

            cx += (sx / sarea + space.xOrigin.to_f) * sarea
            cy += (sy / sarea + space.yOrigin.to_f) * sarea
            cz += (sz / sarea + space.zOrigin.to_f) * sarea
            area += sarea
          end
          next nil if area.zero?

          { story_name: story_name, spaces: spaces,
            centroid: [cx / area, cy / area, cz / area], ceiling_area: area }
        end.compact
      end

      # Legacy get_story_cent_to_edge: the ceiling edge of the storey furthest from a
      # target x,y point. Without full_length, returns the furthest-edge distance (used
      # for the mech-room-to-exterior run). With full_length, also intersects the line
      # (target -> furthest edge) with the opposite side of the storey outline so the
      # full crossing length is available (used for floor trunk ducts).
      # @return [Hash] { start_point: {point:, dist:}, end_point: {point:, dist:} or nil }
      def story_cent_to_edge(story, target_cent, full_length: false)
        edges = []
        outlines = []
        story.spaces.sort_by(&:nameString).each do |space|
          next unless conditioned?(space)

          origin = [space.xOrigin.to_f, space.yOrigin.to_f, space.zOrigin.to_f]
          space.surfaces.each do |surface|
            next unless surface.surfaceType.upcase == 'ROOFCEILING'

            verts = surface.vertices.map do |v|
              [v.x.to_f + origin[0], v.y.to_f + origin[1], v.z.to_f + origin[2]]
            end
            outlines << verts
            verts.each_index do |i|
              ip = i.zero? ? verts.length - 1 : i - 1
              mid = [(verts[i][0] + verts[ip][0]) / 2.0, (verts[i][1] + verts[ip][1]) / 2.0,
                     (verts[i][2] + verts[ip][2]) / 2.0]
              dist = Math.sqrt((target_cent[0] - mid[0])**2 + (target_cent[1] - mid[1])**2)
              edges << { point: mid, dist: dist }
            end
          end
        end
        return nil if edges.empty?

        start_edge = edges.max_by { |e| e[:dist] }
        result = { start_point: start_edge, end_point: nil }
        return result unless full_length

        # walk every outline segment; keep intersections with the target->start line that
        # lie on the OPPOSITE side of the target from the start edge; take the furthest
        sx = start_edge[:point][0] - target_cent[0]
        sy = start_edge[:point][1] - target_cent[1]
        best = nil
        outlines.each do |verts|
          verts.each_index do |i|
            ip = i.zero? ? verts.length - 1 : i - 1
            int = segment_line_intersection(verts[ip], verts[i], target_cent, start_edge[:point])
            next if int.nil?

            dx = int[0] - target_cent[0]
            dy = int[1] - target_cent[1]
            next if (dx * sx + dy * sy).positive? # same side as start edge

            dist = Math.sqrt((start_edge[:point][0] - int[0])**2 + (start_edge[:point][1] - int[1])**2)
            best = { point: int, dist: dist } if best.nil? || dist > best[:dist]
          end
        end
        result[:end_point] = best
        result
      end

      # Intersection of segment a1-a2 with the infinite line through b1-b2 (x,y plane).
      def segment_line_intersection(a1, a2, b1, b2)
        dax = a2[0] - a1[0]
        day = a2[1] - a1[1]
        dbx = b2[0] - b1[0]
        dby = b2[1] - b1[1]
        denom = dax * dby - day * dbx
        return nil if denom.abs < 1e-9

        t = ((b1[0] - a1[0]) * dby - (b1[1] - a1[1]) * dbx) / denom
        return nil if t < -1e-9 || t > 1.0 + 1e-9

        [a1[0] + t * dax, a1[1] + t * day, a1[2] + t * (a2[2] - a1[2])]
      end

      # Manhattan x+y distance (used by legacy for terminal piping/wiring runs), metres.
      def manhattan_xy_m(a, b)
        (a[0] - b[0]).abs + (a[1] - b[1]).abs
      end

      # Manhattan x+y+z distance (used for mech-room-to-roof utility runs), metres.
      def manhattan_xyz_m(a, b)
        (a[0] - b[0]).abs + (a[1] - b[1]).abs + (a[2] - b[2]).abs
      end

      # Zone exterior wall area in ft2 (legacy perimeter distribution runs).
      def zone_exterior_wall_area_ft2(zone)
        zone.spaces.sum { |space| space.exteriorWallArea.to_f } * M_TO_FT * M_TO_FT
      end
    end
  end
end
