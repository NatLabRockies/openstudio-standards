module OpenStudioLighting
  module NECB
    # Daylighted-area geometry per NECB 2020/2025 Articles 4.2.2.3. (primary and
    # secondary SIDELIGHTED areas), 4.2.2.4. (under ROOF MONITORS) and 4.2.2.5.
    # (under SKYLIGHTS) — the areas that 4.2.2.1.(10) and (13) test lighting
    # power against.
    #
    # WHY THIS EXISTS instead of Daylighting.sidelighting_parameters: each of
    # 4.2.2.3.(1), 4.2.2.3.(5), 4.2.2.4.(1) and 4.2.2.5.(1) defines its total as
    # "the combined ... areas WITHOUT DOUBLE-COUNTING OVERLAPPING AREAS", and
    # 4.2.2.5.(2)(b) and 4.2.2.4.(2)(a)(iii) additionally clip toplit area at the
    # edge of a primary sidelighted area. A per-window sum cannot express either.
    # This is an adaptation of openstudio-standards' Standard#space_daylighted_areas
    # (lib/openstudio-standards/standards/Standards.Space.rb): build one polygon
    # per aperture, flatten every polygon to z = 0, JOIN each set into a union,
    # then SUBTRACT in priority order (toplit wins over primary, primary over
    # secondary) and intersect the result with the floor. Polygon booleans are
    # OpenStudio's own (OpenStudio.joinAll / .subtract / .within / .intersects /
    # .getArea) — no new dependency.
    #
    # NECB-SPECIFIC DEVIATIONS from the openstudio-standards original (which
    # implements ASHRAE 90.1):
    #   * side extension = 1/2 the window HEAD HEIGHT on each side
    #     (4.2.2.3.(3)(a) and (7)(a)); the original's width method is a template
    #     hook that returns 'none' by default and 2 ft for some 90.1 vintages.
    #   * primary depth = one window head height (4.2.2.3.(4)(a)); secondary
    #     depth runs from the end of the primary to one further head height
    #     (4.2.2.3.(8)(a)) — the same geometry the original builds, but here it
    #     is the CODE requirement rather than a coincidence.
    #   * skylight extension = 70% of the ceiling height (4.2.2.5.(2)(a)) — same
    #     as the original.
    #
    # HONEST LIMITS, audited every run (see #limitations):
    #   * 4.2.2.3.(3)(b)/(4)(b)/(8)(b) and 4.2.2.5.(2)(c) bound each dimension by
    #     "the distance to any vertical obstruction that is 1.5 m or more in
    #     height". The space's own enclosure IS honoured — every polygon is
    #     intersected with the floor, so no daylighted area escapes the room.
    #     Obstructions INSIDE the space (partitions, racking, furniture) are not
    #     in an OpenStudio thermal model at all, so they cannot be detected; the
    #     computed areas are therefore an UPPER BOUND within each space.
    #   * 4.2.2.4. ROOF MONITORS are vertical glazing ABOVE the ceiling. A
    #     monitor is not a distinguishable object in an OpenStudio model (it is
    #     ordinary wall glazing, usually on a separate high space), so toplit
    #     area here covers SKYLIGHTS only. Every model whose spaces have no
    #     above-ceiling glazing is unaffected; models with monitors get less
    #     toplit area than the code would give them.
    module DaylightedAreas
      module_function

      WINDOW_TYPES = %w[FixedWindow OperableWindow GlassDoor].freeze
      SKYLIGHT_EXTENT_FRACTION = 0.7 # 4.2.2.5.(2)(a)
      TOLERANCE = 0.01

      # @param space [OpenStudio::Model::Space]
      # @param audit [OpenStudioLighting::AuditLog, nil]
      # @return [Hash] all areas in m2:
      #   :toplighted_m2, :primary_sidelighted_m2, :secondary_sidelighted_m2,
      #   :floor_m2, :window_area_m2, :skylight_area_m2,
      #   :window_vt_max, :skylight_vt_max (nil when there are none)
      def areas(space, audit: nil)
        result = { toplighted_m2: 0.0, primary_sidelighted_m2: 0.0, secondary_sidelighted_m2: 0.0,
                   floor_m2: 0.0, window_area_m2: 0.0, skylight_area_m2: 0.0,
                   window_vt_max: nil, skylight_vt_max: nil }

        floor_surface = nil
        floor_polygons = []
        space.surfaces.sort_by(&:nameString).each do |surface|
          next unless surface.surfaceType == 'Floor'

          floor_surface ||= surface
          floor_polygons << surface.vertices.map { |v| OpenStudio::Point3d.new(v.x, v.y, 0.0) }
        end
        if floor_surface.nil?
          audit&.warn(:daylighting,
                      "space '#{space.nameString}' has NO FLOOR SURFACE — daylighted areas cannot be " \
                      'determined, so 4.2.2.1.(10)/(13) are evaluated against zero area',
                      article: '4.2.2.3.; 4.2.2.5.')
          return result
        end

        toplit = []
        primary = []
        secondary = []

        space.surfaces.sort_by(&:nameString).each do |surface|
          if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'
            next unless vertical?(surface, space, audit)

            surface.subSurfaces.sort_by(&:nameString).each do |sub|
              next unless sub.outsideBoundaryCondition == 'Outdoors' && WINDOW_TYPES.include?(sub.subSurfaceType)

              result[:window_area_m2] += sub.netArea
              vt = visible_transmittance(sub)
              result[:window_vt_max] = [result[:window_vt_max] || 0.0, vt].max if vt

              pair = sidelit_polygons(space, sub, floor_surface, audit)
              next if pair.nil?

              primary << pair[0]
              secondary << pair[1]
            end
          elsif surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'
            next unless horizontal?(surface, space, audit)

            surface.subSurfaces.sort_by(&:nameString).each do |sub|
              next unless sub.outsideBoundaryCondition == 'Outdoors' && sub.subSurfaceType == 'Skylight'

              result[:skylight_area_m2] += sub.netArea
              vt = visible_transmittance(sub)
              result[:skylight_vt_max] = [result[:skylight_vt_max] || 0.0, vt].max if vt

              polygon = toplit_polygon(space, sub, floor_surface, audit)
              toplit << polygon unless polygon.nil?
            end
          end
        end

        # Join each set into its own union — this is what "without double-counting
        # overlapping areas" (4.2.2.3.(1)/(5), 4.2.2.4.(1), 4.2.2.5.(1)) requires.
        floor_union = join(space, floor_polygons, 'floor', audit)
        toplit_union = join(space, toplit, 'toplighted', audit)
        primary_union = join(space, primary, 'primary sidelighted', audit)
        secondary_union = join(space, secondary, 'secondary sidelighted', audit)

        # Subtract in NECB's OWN precedence order: PRIMARY > TOPLIT > SECONDARY.
        #   * 4.2.2.5.(2)(b) caps each skylight extension at "the distance to any
        #     primary sidelighted area", so the toplit area STOPS at the primary
        #     band — the primary is never reduced by a skylight. Because a primary
        #     band always hugs an exterior wall and every polygon is clipped to
        #     the floor, "stop the extension at the band" and "subtract the band"
        #     give the same area here.
        #   * 4.2.2.3.(9): no secondary sidelighted area exists beyond the limit
        #     of an adjacent under-skylight or primary area, so secondary loses to
        #     both.
        # NOTE this is the OPPOSITE of the openstudio-standards original this was
        # adapted from, which subtracts toplit from primary — correct for ASHRAE
        # 90.1, wrong for NECB.
        toplit_only = subtract(toplit_union, primary_union)
        secondary_only = subtract(subtract(secondary_union, primary_union), toplit_union)

        result[:floor_m2] = total_area(floor_union)
        result[:toplighted_m2] = overlap_area(toplit_only, floor_union)
        result[:primary_sidelighted_m2] = overlap_area(primary_union, floor_union)
        result[:secondary_sidelighted_m2] = overlap_area(secondary_only, floor_union)
        result
      end

      # One-line audit of what this geometry cannot see. Emitted once per run by
      # the caller, never suppressed.
      def limitations
        '4.2.2.3.(3)(b)/(4)(b)/(8)(b) and 4.2.2.5.(2)(c) bound each daylighted dimension by the distance ' \
          'to a vertical obstruction >= 1.5 m high: the SPACE ENCLOSURE is honoured (every daylighted ' \
          'polygon is intersected with the floor), but obstructions INSIDE a space are not present in an ' \
          'OpenStudio thermal model, so the areas are an upper bound within each space; and 4.2.2.4. ROOF ' \
          'MONITORS are not a distinguishable object in an OpenStudio model, so toplighted area covers ' \
          'SKYLIGHTS only'
      end

      # --- geometry helpers -----------------------------------------------------

      def visible_transmittance(sub_surface)
        vt = sub_surface.visibleTransmittance
        vt.is_initialized ? vt.get : nil
      rescue StandardError
        nil
      end

      def vertical?(surface, space, audit)
        return true if surface.outwardNormal.z.abs < 0.001
        return true if surface.subSurfaces.empty?

        audit&.warn(:daylighting,
                    "NON-VERTICAL EXTERIOR WALL '#{surface.nameString}' in space '#{space.nameString}' carries " \
                    'glazing — its sidelighted areas are NOT computed (the 4.2.2.3. width/depth construction ' \
                    'assumes vertical glazing)', article: '4.2.2.3.')
        false
      end

      def horizontal?(surface, space, audit)
        normal = surface.outwardNormal
        return true if normal.z > 0.999 && normal.x.abs < 0.001 && normal.y.abs < 0.001
        return true if surface.subSurfaces.empty?

        audit&.warn(:daylighting,
                    "NON-HORIZONTAL ROOF '#{surface.nameString}' in space '#{space.nameString}' carries " \
                    'skylights — the daylighted area under them is NOT computed (the 4.2.2.5. projection ' \
                    'construction assumes a horizontal roof)', article: '4.2.2.5.')
        false
      end

      # Primary (4.2.2.3.(2)-(4)) and secondary (4.2.2.3.(6)-(8)) polygons for one
      # window, both folded down onto the z = 0 floor plane.
      def sidelit_polygons(space, sub_surface, floor_surface, audit)
        vertices = sub_surface.vertices
        unless vertices.size == 4
          audit&.warn(:daylighting,
                      "WINDOW '#{sub_surface.nameString}' in space '#{space.nameString}' has " \
                      "#{vertices.size} vertices, not 4 — EXCLUDED from the sidelighted areas",
                      article: '4.2.2.3.')
          return nil
        end

        heights = vertices.map { |v| (v - floor_surface.plane.project(v)).length }
        sill_height = heights.min
        head_height = heights.max
        return nil if head_height <= 0.0

        # 4.2.2.3.(3)(a)/(7)(a): 1/2 the window head height on each side.
        extra_width = head_height / 2.0

        rotation_origin = nil
        previous = nil
        widest = 0.0
        vertices.each do |vertex|
          projected = floor_surface.plane.project(vertex)
          if previous
            width = (previous - projected).length
            if width > widest
              widest = width
              rotation_origin = projected
            end
          end
          previous = projected
        end
        return nil if rotation_origin.nil?

        face_transform = OpenStudio::Transformation.alignFace(vertices)
        aligned = face_transform.inverse * vertices
        min_x = aligned.map(&:x).min
        max_x = aligned.map(&:x).max

        primary = []
        secondary = []
        non_rectangular = false
        aligned.each do |vertex|
          if (vertex.x - min_x).abs < TOLERANCE
            new_x = vertex.x - extra_width
          elsif (vertex.x - max_x).abs < TOLERANCE
            new_x = vertex.x + extra_width
          else
            non_rectangular = true
            new_x = vertex.x
          end
          # Zero the bottom edge: the primary area runs from the wall inward,
          # so the aperture's own sill offset is folded out (4.2.2.3.(4)(a)
          # measures the depth from the FLOOR to the top of the glazing).
          primary_y = vertex.y.zero? ? vertex.y - sill_height : vertex.y
          # 4.2.2.3.(8)(a): the secondary band begins where the primary ends and
          # runs one further head height.
          secondary_y = primary_y + head_height
          primary << OpenStudio::Point3d.new(new_x, primary_y, 0.0)
          secondary << OpenStudio::Point3d.new(new_x, secondary_y, 0.0)
        end
        if non_rectangular
          audit&.warn(:daylighting,
                      "NON-RECTANGULAR WINDOW '#{sub_surface.nameString}' in space '#{space.nameString}': its " \
                      'side extension is applied only to the extreme vertices, so its sidelighted areas are ' \
                      'approximate', article: '4.2.2.3.')
        end

        primary = face_transform * primary
        secondary = face_transform * secondary

        # Rotate both bands down onto the floor plane about the window's own base.
        rotation = OpenStudio.createRotation(rotation_origin,
                                            OpenStudio::Vector3d.new(0, 0, -1).cross(sub_surface.outwardNormal),
                                            OpenStudio.degToRad(90))
        [set_z_zero((rotation * primary).reverse), set_z_zero((rotation * secondary).reverse)]
      end

      # 4.2.2.5.(2): the skylight's projection onto the floor grown by 70% of the
      # ceiling height in each direction.
      def toplit_polygon(space, sub_surface, floor_surface, audit)
        vertices = sub_surface.vertices
        unless vertices.size == 4
          audit&.warn(:daylighting,
                      "SKYLIGHT '#{sub_surface.nameString}' in space '#{space.nameString}' has " \
                      "#{vertices.size} vertices, not 4 — EXCLUDED from the toplighted area",
                      article: '4.2.2.5.')
          return nil
        end

        on_floor = vertices.map { |v| floor_surface.plane.project(v) }
        ceiling_height = vertices.map { |v| (v - floor_surface.plane.project(v)).length }.max
        return nil if ceiling_height <= 0.0

        extent = SKYLIGHT_EXTENT_FRACTION * ceiling_height
        face_transform = OpenStudio::Transformation.alignFace(on_floor)
        aligned = face_transform.inverse * on_floor
        min_x = aligned.map(&:x).min
        max_x = aligned.map(&:x).max
        min_y = aligned.map(&:y).min
        max_y = aligned.map(&:y).max

        grown = aligned.map do |vertex|
          new_x = if (vertex.x - min_x).abs < TOLERANCE then vertex.x - extent
                  elsif (vertex.x - max_x).abs < TOLERANCE then vertex.x + extent
                  else vertex.x
                  end
          new_y = if (vertex.y - min_y).abs < TOLERANCE then vertex.y - extent
                  elsif (vertex.y - max_y).abs < TOLERANCE then vertex.y + extent
                  else vertex.y
                  end
          OpenStudio::Point3d.new(new_x, new_y, 0.0)
        end
        set_z_zero((face_transform * grown).reverse)
      end

      def set_z_zero(polygon)
        polygon.map { |vertex| OpenStudio::Point3d.new(vertex.x, vertex.y, 0.0) }
      end

      # --- polygon booleans (thin wrappers over the OpenStudio utilities) -------

      # Union a set of polygons. joinAll can fail on sets that form an inner loop
      # (the classic case: windows on all four walls); the openstudio-standards
      # original retries with n-1 polygons and adds the remainder back, and that
      # workaround is kept here.
      def join(space, polygons, name, audit)
        return [] if polygons.empty?
        return polygons if polygons.size == 1

        sink = OpenStudio::StringStreamLogSink.new
        sink.setLogLevel(OpenStudio::Info)
        combined = OpenStudio.joinAll(polygons, TOLERANCE)
        failed = join_failures(sink)
        sink.disable

        if failed.positive?
          retry_sink = OpenStudio::StringStreamLogSink.new
          retry_sink.setLogLevel(OpenStudio::Info)
          first = polygons.first
          rest = OpenStudio.joinAll(polygons.drop(1), TOLERANCE)
          retry_failed = join_failures(retry_sink)
          retry_sink.disable
          if retry_failed.zero?
            combined = rest + subtract([first], rest)
            failed = 0
          end
        end

        if failed.positive?
          audit&.warn(:daylighting,
                      "POLYGON UNION FAILED for the #{name} areas of space '#{space.nameString}' " \
                      "(#{failed} joinAll complaint(s) over #{polygons.size} polygons) — the area reported is " \
                      'SMALLER than the code requires, so the 4.2.2.1.(10)/(13) power test may under-trigger',
                      article: '4.2.2.3.; 4.2.2.5.')
        end
        combined
      end

      def join_failures(sink)
        sink.logMessages.count do |message|
          /utilities.geometry/ =~ message.logChannel &&
            (message.logMessage.include?('Expected polygons to join together') ||
             message.logMessage.include?('Union has inner loops'))
        end
      end

      # a_polygons minus b_polygons.
      def subtract(a_polygons, b_polygons)
        return [] if a_polygons.empty?
        return a_polygons if b_polygons.empty?

        results = []
        a_polygons.each do |a_polygon|
          pieces = OpenStudio.subtract(a_polygon, b_polygons, TOLERANCE).reject do |piece|
            next true if piece.empty?

            area = OpenStudio.getArea(piece)
            !area.is_initialized || area.get < 0.5 # drop slivers, as the original does
          end
          results.concat(pieces.map { |piece| set_z_zero(piece) })
        end
        dedupe(results)
      end

      def dedupe(polygons)
        seen = {}
        polygons.each do |polygon|
          key = polygon.map { |v| [v.x.round(6), v.y.round(6)] }
          seen[key] ||= polygon
        end
        seen.values
      end

      def total_area(polygons)
        polygons.sum do |polygon|
          area = OpenStudio.getArea(polygon)
          area.is_initialized ? area.get : 0.0
        end
      end

      # Area of a_polygons that lies inside b_polygons.
      def overlap_area(a_polygons, b_polygons)
        return 0.0 if a_polygons.empty? || b_polygons.empty?

        overlap = 0.0
        b_polygons.each do |b_polygon|
          a_polygons.each do |a_polygon|
            if OpenStudio.within(a_polygon, b_polygon, TOLERANCE)
              area = OpenStudio.getArea(a_polygon)
              overlap += area.get if area.is_initialized
            elsif OpenStudio.intersects(a_polygon, b_polygon, TOLERANCE)
              initial = OpenStudio.getArea(b_polygon)
              next unless initial.is_initialized

              remaining = OpenStudio.subtract(b_polygon, [a_polygon], TOLERANCE).sum do |piece|
                next 0.0 if piece.empty?

                area = OpenStudio.getArea(piece)
                area.is_initialized ? area.get : 0.0
              end
              overlap += (initial.get - remaining)
            end
          end
        end
        overlap
      end
    end
  end
end
