module OpenStudioLighting
  module NECB
    # QUARANTINE FILE. Nothing here is NECB 2020/2025 geometry.
    #
    # This is the VERBATIM legacy NECB 2011 daylighted-area math — the ports of
    # openstudio-standards' get_parameters_sidelighting /
    # get_parameters_skylight — lifted out of `necb/daylighting.rb` by a pure
    # code move, byte-for-byte unchanged. It reopens `Daylighting`, so every
    # constant path is exactly what it always was
    # (`OpenStudioLighting::NECB::Daylighting.sidelighting_parameters` /
    # `.skylight_parameters`); there are no delegators and no call site moved.
    # The FILENAME is the whole point: it labels the code as legacy so the
    # 2020/2025 geometry in `daylighted_areas.rb` is never confused with it.
    #
    # PARITY-PINNED — DEFECTS DELIBERATELY PRESERVED. `test_daylighting_parity.rb`
    # diffs these two methods against the legacy openstudio-standards
    # implementation, so their output must not change, including where it is
    # wrong: per-window areas are SUMMED with no union (overlaps double-counted,
    # contrary to 4.2.2.3.(1)/(5), 4.2.2.4.(1) and 4.2.2.5.(1)), no secondary
    # sidelighted area is computed at all, and the skylight-area accumulator
    # sits inside the exterior-window loop so a skylight-only space always
    # computes zero. Do NOT "clean this up", refactor it, or fix a defect here.
    #
    # DO NOT BUILD ON IT. Production callers are the legacy `placement: :necb2011`
    # selection in `daylighting.rb` and the legacy sensor-count rule in
    # `costing/fixtures.rb`; new work wants `necb/daylighted_areas.rb`, which
    # implements the real NECB 2020/2025 Articles 4.2.2.3. (primary AND secondary
    # sidelighted), 4.2.2.4. (roof monitors) and 4.2.2.5. (skylights) with unioned
    # polygons. See L-26 and D-57.
    module Daylighting
      module_function

      # ---- Daylighted-area geometry (verbatim ports of legacy
      # get_parameters_sidelighting / get_parameters_skylight) -------------------
      #
      # LEGACY-ONLY. These two methods exist to be diffed against legacy by
      # test_daylighting_parity.rb; the 2020/2025 rule uses DaylightedAreas
      # instead, because these SUM per-window areas with no union and so
      # double-count overlaps, contrary to 4.2.2.3.(1)/(5), 4.2.2.4.(1) and
      # 4.2.2.5.(1) ("the combined ... areas without double-counting overlapping
      # areas"), and they compute no secondary sidelighted area at all.

      # Legacy "primary sidelighted area" (its own comment cites NECB 2011
      # 4.2.2.9., an article that does not exist in 2020/2025): per exterior-wall
      # window at floor level, depth = min(window head height, space depth), width
      # = window width + min(distance to each side wall, 0.6 m). NECB 2020
      # 4.2.2.3.(3)-(4) instead specify HALF the window head height on each side,
      # bounded by the distance to any vertical obstruction >= 1.5 m high.
      # @return [Hash] { area_m2:, vt_handle:, window_area_m2: } (vt_handle =
      #   sum(window area x VT), for the legacy 2011 effective aperture)
      def sidelighting_parameters(space, audit: nil)
        floor_surface = nil
        floor_area = 0.0
        floor_vertices = []
        space.surfaces.sort_by(&:nameString).each do |surface|
          next unless surface.surfaceType == 'Floor'

          floor_surface = surface
          floor_area += surface.netArea
          floor_vertices << surface.vertices
        end
        return { area_m2: 0.0, vt_handle: 0.0, window_area_m2: 0.0 } if floor_surface.nil?

        area = 0.0
        vt_handle = 0.0
        window_area_sum = 0.0
        space.surfaces.sort_by(&:nameString).each do |surface|
          next unless surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'

          begin
            surface_z_min = surface.vertices.map(&:z).min
            next unless surface_z_min == floor_vertices[0][0].z

            wall_x = []
            wall_y = []
            surface.vertices.each do |vertex|
              next unless vertex.z == surface_z_min

              wall_x << vertex.x
              wall_y << vertex.y
            end
            next if wall_x.size < 2

            opposite_x = []
            opposite_y = []
            floor_vertices[0].each do |vertex|
              if (vertex.x != wall_x[0] && vertex.y != wall_y[0]) || (vertex.x != wall_x[1] && vertex.y != wall_y[1])
                opposite_x << vertex.x
                opposite_y << vertex.y
              end
            end
            width_wall = Math.sqrt((wall_x[0] - wall_x[1])**2 + (wall_y[0] - wall_y[1])**2)
            width_opposite = Math.sqrt((opposite_x[0] - opposite_x[1])**2 + (opposite_y[0] - opposite_y[1])**2)
            depth = 2 * floor_area / (width_wall + width_opposite)

            surface.subSurfaces.sort_by(&:nameString).each do |sub|
              next unless %w[FixedWindow OperableWindow].include?(sub.subSurfaceType)

              vt = sub.visibleTransmittance.get
              window_area = sub.netArea
              window_area_sum += window_area
              vt_handle += window_area * vt
              v = sub.vertices
              window_width = if v[0].z.round(2) == v[1].z.round(2)
                               Math.sqrt((v[0].x - v[1].x)**2 + (v[0].y - v[1].y)**2)
                             else
                               Math.sqrt((v[1].x - v[2].x)**2 + (v[1].y - v[2].y)**2)
                             end
              head_height = v.map(&:z).max.round(2)
              area_depth = [head_height, depth].min
              projected = v.map { |vertex| floor_surface.plane.project(vertex) }
              side1 = [Math.sqrt((wall_x[0] - projected[0].x)**2 + (wall_y[0] - projected[0].y)**2),
                       Math.sqrt((wall_x[0] - projected[2].x)**2 + (wall_y[0] - projected[2].y)**2), 0.6].min
              side2 = [Math.sqrt((wall_x[1] - projected[0].x)**2 + (wall_y[1] - projected[0].y)**2),
                       Math.sqrt((wall_x[1] - projected[2].x)**2 + (wall_y[1] - projected[2].y)**2), 0.6].min
              area += area_depth * (side1 + window_width + side2)
            end
          rescue StandardError => e
            audit&.warn(:daylighting, "sidelighting geometry failed on #{surface.nameString} (#{e.class}) — surface skipped")
          end
        end
        { area_m2: area, vt_handle: vt_handle, window_area_m2: window_area_sum }
      end

      # Legacy "daylighted area under skylights" + VT sums for the legacy 2011
      # skylight effective aperture (its comment cites 4.2.2.7., which does not
      # exist in 2020/2025). LEGACY DEFECT preserved for parity (audited by the
      # caller): the area accumulation sits INSIDE the exterior-window
      # re-calculation loop, so spaces with skylights but NO exterior windows
      # always compute ZERO daylighted area.
      def skylight_parameters(space, audit: nil)
        area = 0.0
        vt_handle = 0.0
        skylight_area_sum = 0.0
        roof_vertices = nil
        space.surfaces.sort_by(&:nameString).each do |surface|
          roof_vertices = surface.vertices if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'

          surface.subSurfaces.sort_by(&:nameString).each do |sub|
            next unless sub.subSurfaceType == 'Skylight'

            begin
              vt = sub.visibleTransmittance.get
              s = sub.vertices
              skylight_area_sum += sub.netArea
              vt_handle += sub.netArea * vt
              skylight_width = Math.sqrt((s[0].x - s[1].x)**2 + (s[0].y - s[1].y)**2)
              skylight_length = Math.sqrt((s[0].x - s[3].x)**2 + (s[0].y - s[3].y)**2)
              ceiling_height = s[0].z
              r = roof_vertices
              next if r.nil?

              lengths = [dist(r[0], r[1]), dist(r[1], r[2]), dist(r[2], r[3]), dist(r[3], r[0])]
              closest0 = s.min_by { |p| dist(r[0], p) }
              closest2 = s.min_by { |p| dist(r[2], p) }
              d1 = triangle_height(closest0, r[0], r[1], lengths[0])
              d2 = triangle_height(closest0, r[0], r[3], lengths[3])
              d3 = triangle_height(closest2, r[2], r[1], lengths[1])
              d4 = triangle_height(closest2, r[2], r[3], lengths[2])

              width = skylight_width + [0.7 * ceiling_height, d1].min + [0.7 * ceiling_height, d4].min
              length = skylight_length + [0.7 * ceiling_height, d2].min + [0.7 * ceiling_height, d3].min

              space.surfaces.sort_by(&:nameString).each do |wall|
                next unless wall.outsideBoundaryCondition == 'Outdoors' && wall.surfaceType == 'Wall'

                w = wall.vertices
                wall_x = []
                wall_y = []
                if w[0].z == w[1].z
                  wall_x = [w[0].x, w[1].x]
                  wall_y = [w[0].y, w[1].y]
                elsif w[0].z == w[3].z
                  wall_x = [w[0].x, w[3].x]
                  wall_y = [w[0].y, w[3].y]
                end
                next if wall_x.size < 2

                head_height = s.map(&:z).max.round(2)
                wall_length = Math.sqrt((wall_x[0] - wall_x[1])**2 + (wall_y[0] - wall_y[1])**2)
                sv0 = wall_point_distance(wall_x, wall_y, s[0], wall_length)
                sv1 = wall_point_distance(wall_x, wall_y, s[1], wall_length)
                sv3 = wall_point_distance(wall_x, wall_y, s[3], wall_length)

                wall.subSurfaces.sort_by(&:nameString).each do |window|
                  next unless %w[FixedWindow OperableWindow].include?(window.subSurfaceType)

                  window_head = window.vertices.map(&:z).max.round(2)
                  if sv0 == sv1 # skylight edge 0-1 parallel to the wall
                    if sv0.round(2) == d2.round(2)
                      length = skylight_length + [0.7 * ceiling_height, d2, d2 - window_head].min + [0.7 * ceiling_height, d3].min
                    elsif sv0.round(2) == d3.round(2)
                      length = skylight_length + [0.7 * ceiling_height, d2].min + [0.7 * ceiling_height, d3, d3 - window_head].min
                    end
                  elsif sv0 == sv3 # skylight edge 0-3 parallel to the wall
                    if sv0.round(2) == d1.round(2)
                      width = skylight_width + [0.7 * ceiling_height, d1, d1 - window_head].min + [0.7 * ceiling_height, d4].min
                    elsif sv0.round(2) == d4.round(2)
                      width = skylight_width + [0.7 * ceiling_height, d1].min + [0.7 * ceiling_height, d4, d4 - window_head].min
                    end
                  end
                  # LEGACY DEFECT: accumulation only happens here (inside the
                  # window loop) — skylight-only spaces accumulate nothing
                  area += length * width
                  _ = head_height
                end
              end
            rescue StandardError => e
              audit&.warn(:daylighting, "skylight geometry failed on #{sub.nameString} (#{e.class}) — skylight skipped")
            end
          end
        end
        { area_m2: area, vt_handle: vt_handle, skylight_area_m2: skylight_area_sum }
      end

      def dist(a, b)
        Math.sqrt((a.x - b.x)**2 + (a.y - b.y)**2)
      end

      def triangle_height(point, v_a, v_b, base_length)
        area = 0.5 * (((point.x - v_b.x) * (point.y - v_a.y)) - ((point.x - v_a.x) * (point.y - v_b.y))).abs
        2.0 * area / base_length
      end

      def wall_point_distance(wall_x, wall_y, point, wall_length)
        area = 0.5 * (((wall_x[0] - wall_x[1]) * (wall_y[0] - point.y)) -
                      ((wall_x[0] - point.x) * (wall_y[0] - wall_y[1]))).abs
        2.0 * area / wall_length
      end

      # ---- internals (not API) ---- (moved here with their callers; the rest of
      # Daylighting's private list stays in daylighting.rb)
      private_class_method :dist, :triangle_height, :wall_point_distance
    end
  end
end
