module OpenStudioLighting
  module NECB
    # NECB 2020/2025 Article 4.2.2.1., sentences (10)-(15): WHERE automatic
    # daylight-responsive photocontrols are required.
    #
    # (10) SIDELIGHTING — in space types whose Table 4.2.1.6 "Automatic Daylight
    #      Responsive Controls for Sidelighting" column carries an X, the general
    #      lighting in the primary and secondary sidelighted areas shall be
    #      separately photocontrolled where
    #        (a) the combined input power of all general lighting completely or
    #            partially within the PRIMARY sidelighted areas is >= 150 W, OR
    #        (b) the combined input power within the PRIMARY AND SECONDARY
    #            sidelighted areas is >= 300 W.
    # (12) exceptions to (10): (a) obstruction ratio >= 2, (b) total glazing area
    #      < 2 m2, (c) retail spaces.
    # (13) TOPLIGHTING — in space types whose Table 4.2.1.6 toplighting column
    #      carries an X, the general lighting in the daylighted areas under
    #      skylights AND roof monitors shall be photocontrolled where that
    #      combined input power is >= 150 W.
    # (15) exceptions to (13): (a) adjacent structures/natural objects block
    #      direct sun > 1 500 h/yr between 8 a.m. and 4 p.m., (b) skylight and
    #      roof-monitor VT < 0.4, (c) buildings above 55 degN latitude where the
    #      general-lighting input power within the daylighted areas is < 200 W.
    #
    # (10) AND (13) ARE INDEPENDENT. Nothing in either sentence conditions one on
    # the other; a space qualifies under either alone. The NECB 2011 criteria the
    # legacy port applies (primary sidelighted area > 100 m2 AND under-skylight
    # area > 400 m2 AND skylight effective aperture > 0.006, all ANDed) make a
    # window-only space fail on its zero skylight area, which is exactly why the
    # legacy path places no controls at all on window-only archetypes (L-26).
    #
    # THE POWER TEST, DERIVED. Sentences (10) and (13) test INPUT POWER inside a
    # daylighted area, which in general needs per-luminaire placement. It does not
    # here: this gem applies a single uniform lighting power density per space
    # (4.2.1.6. allowance, W/m2 over the whole space floor area), so the general
    # lighting is uniformly distributed by construction and
    #
    #     input power within a daylighted area = LPD_general x daylighted_area
    #
    # exactly. No luminaire layout is needed or possible. "General" excludes the
    # 4.2.1.6. specialty/decorative additional allowance, which this gem models as
    # a separately named "Additional Lights" instance and which (10)/(13) do not
    # cover.
    module DaylightControlRequirement
      module_function

      PRIMARY_THRESHOLD_W = 150.0        # 4.2.2.1.(10)(a)
      COMBINED_THRESHOLD_W = 300.0       # 4.2.2.1.(10)(b)
      TOPLIGHTING_THRESHOLD_W = 150.0   # 4.2.2.1.(13)
      MIN_GLAZING_AREA_M2 = 2.0          # 4.2.2.1.(12)(b)
      OBSTRUCTION_RATIO = 2.0            # 4.2.2.1.(12)(a)
      SKYLIGHT_VT_THRESHOLD = 0.4        # 4.2.2.1.(15)(b)
      HIGH_LATITUDE_DEG_N = 55.0         # 4.2.2.1.(15)(c)
      HIGH_LATITUDE_THRESHOLD_W = 200.0 # 4.2.2.1.(15)(c)

      # Table 4.2.1.6.'s two daylight-control columns, mapped to the NECB
      # space-function catalog names. Five states per column:
      #   required       — the column carries 'X'
      #   not_required   — blank or a dash in BOTH the 2020 and 2025 extractions
      #   not_applicable — the table refers the space type to a DIFFERENT article
      #                    (4.2.2.2. storage garages, 4.2.2.6.(2) guest rooms)
      #   not_listed     — the space type has no row at all, and (10)/(13) reach
      #                    only spaces requiring the control "in accordance with
      #                    Table 4.2.1.6." (dwelling units)
      #   unknown        — the two extractions CONFLICT, or the cell holds
      #                    header/footnote text. Never decided silently
      # The file's own provenance block says why 'unknown' has to exist: BOTH MCP
      # extractions of Table 4.2.1.6 are corrupted, and differently.
      def table
        @table ||= begin
          require 'json'
          JSON.parse(File.read(File.join(NECB::DATA_DIR, 'daylighting_controls_4_2_1_6.json')))
        end
      end

      def residue
        table['residue']
      end

      # @return [Hash, nil] the Table 4.2.1.6. row for a standards space-type name
      #   (schedule-letter suffixes stripped), or nil when the name is not in the
      #   catalog at all
      def requirement(standards_space_type)
        return nil if standards_space_type.nil?

        table['space_types'][base_name(standards_space_type)]
      end

      def base_name(standards_space_type)
        standards_space_type.to_s.sub(/-sch-[A-Z]\z/, '')
      end

      # Evaluate 4.2.2.1.(10)-(15) for one space.
      #
      # @param space [OpenStudio::Model::Space]
      # @param unknown_default [:required, :not_required] what to do when
      #   Table 4.2.1.6. cannot be read for this space type. Default :required —
      #   photocontrols in the REFERENCE building lower the reference's lighting
      #   energy and therefore TIGHTEN the target the proposed building must beat,
      #   so assuming "required" cannot hand a non-conforming building a pass.
      #   Every use of the default WARNS.
      # @return [Hash] :required (Boolean), :sidelighting / :toplighting
      #   (sub-hashes with :required, :reason, :power_w), :areas, :lpd_w_per_m2
      # @param seen [Hash, nil] a caller-owned dedupe map so a 122-space apartment
      #   run logs each unresolved (space type, column) ONCE rather than 122 times
      def evaluate(space, audit: nil, unknown_default: :required, shading_surfaces: nil, seen: nil)
        standards_type = standards_space_type(space)
        row = requirement(standards_type)
        lpd = general_lighting_lpd(space)
        areas = DaylightedAreas.areas(space, audit: audit)

        if row.nil?
          if seen.nil? || seen["absent|#{standards_type}"].nil?
            seen && seen["absent|#{standards_type}"] = true
            audit&.warn(:daylighting,
                        "SPACE TYPE #{standards_type.inspect} IS NOT IN THE VENDORED TABLE 4.2.1.6. CONTROL " \
                        "MATRIX — its 4.2.2.1.(10)/(13) columns cannot be read (first seen on space " \
                        "'#{space.nameString}'), so the conservative default (#{unknown_default}) is applied to " \
                        'BOTH sidelighting and toplighting',
                        target: space.nameString, article: '4.2.1.6.; 4.2.2.1.(10); 4.2.2.1.(13)',
                        ruling: 'D-57')
          end
          row = { 'sidelighting' => 'unknown', 'toplighting' => 'unknown',
                  'table_row' => standards_type,
                  'evidence' => 'space type absent from the vendored matrix' }
        end

        side = evaluate_sidelighting(space, row, lpd, areas, audit, unknown_default, shading_surfaces, standards_type, seen)
        top = evaluate_toplighting(space, row, lpd, areas, audit, unknown_default, standards_type, seen)

        { required: side[:required] || top[:required],
          sidelighting: side, toplighting: top, areas: areas,
          lpd_w_per_m2: lpd, space_type: standards_type,
          table_row: row['table_row'] }
      end

      def evaluate_sidelighting(space, row, lpd, areas, audit, unknown_default, shading_surfaces,
                                standards_type = nil, seen = nil)
        state = column_state(row['sidelighting'], unknown_default, space, 'sidelighting', row, audit,
                             standards_type, seen)
        primary_w = lpd * areas[:primary_sidelighted_m2]
        combined_w = lpd * (areas[:primary_sidelighted_m2] + areas[:secondary_sidelighted_m2])
        result = { primary_power_w: primary_w.round(1), combined_power_w: combined_w.round(1),
                   table: row['sidelighting'] }

        return result.merge(required: false, reason: 'Table 4.2.1.6. does not require sidelighting photocontrols for this space type') unless state

        # (12)(c) retail
        if row['retail']
          audit&.info(:daylighting, 'sidelighting photocontrols not required: retail space',
                      target: space.nameString, article: '4.2.2.1.(12)(c)',
                      ruling: 'D-57')
          return result.merge(required: false, reason: '4.2.2.1.(12)(c) exception: retail space')
        end

        # (12)(b) total glazing < 2 m2
        if areas[:window_area_m2] < MIN_GLAZING_AREA_M2
          return result.merge(required: false,
                              reason: format('4.2.2.1.(12)(b) exception: total glazing %.2f m2 < 2 m2',
                                             areas[:window_area_m2]))
        end

        # (12)(a) obstruction ratio >= 2
        ratio = obstruction_ratio(space, shading_surfaces)
        if !ratio.nil? && ratio >= OBSTRUCTION_RATIO
          audit&.info(:daylighting,
                      'sidelighting photocontrols not required: adjacent-structure obstruction ratio >= 2',
                      target: space.nameString, inputs: { obstruction_ratio: ratio.round(2) },
                      article: '4.2.2.1.(12)(a)',
                      ruling: 'D-57')
          return result.merge(required: false,
                              reason: format('4.2.2.1.(12)(a) exception: obstruction ratio %.2f >= 2', ratio))
        end

        if primary_w >= PRIMARY_THRESHOLD_W
          result.merge(required: true,
                       reason: format('4.2.2.1.(10)(a): %.0f W of general lighting in %.1f m2 of primary ' \
                                      'sidelighted area >= 150 W', primary_w, areas[:primary_sidelighted_m2]))
        elsif combined_w >= COMBINED_THRESHOLD_W
          result.merge(required: true,
                       reason: format('4.2.2.1.(10)(b): %.0f W of general lighting in %.1f m2 of primary + ' \
                                      'secondary sidelighted area >= 300 W', combined_w,
                                      areas[:primary_sidelighted_m2] + areas[:secondary_sidelighted_m2]))
        else
          result.merge(required: false,
                       reason: format('below both 4.2.2.1.(10) thresholds: %.0f W primary (< 150 W) and ' \
                                      '%.0f W primary + secondary (< 300 W)', primary_w, combined_w))
        end
      end

      def evaluate_toplighting(space, row, lpd, areas, audit, unknown_default,
                               standards_type = nil, seen = nil)
        state = column_state(row['toplighting'], unknown_default, space, 'toplighting', row, audit,
                             standards_type, seen)
        power_w = lpd * areas[:toplighted_m2]
        result = { power_w: power_w.round(1), table: row['toplighting'] }

        return result.merge(required: false, reason: 'Table 4.2.1.6. does not require toplighting photocontrols for this space type') unless state

        # (15)(b) skylight VT < 0.4
        vt = areas[:skylight_vt_max]
        if !vt.nil? && vt < SKYLIGHT_VT_THRESHOLD
          return result.merge(required: false,
                              reason: format('4.2.2.1.(15)(b) exception: highest skylight VT %.3f < 0.4', vt))
        end

        # (15)(c) above 55 degN with < 200 W
        latitude = site_latitude(space.model)
        if !latitude.nil? && latitude > HIGH_LATITUDE_DEG_N && power_w < HIGH_LATITUDE_THRESHOLD_W
          audit&.info(:daylighting,
                      'toplighting photocontrols not required: above 55 degN with < 200 W of general lighting ' \
                      'in the daylighted areas',
                      target: space.nameString,
                      inputs: { latitude_deg_n: latitude.round(2), power_w: power_w.round(1) },
                      article: '4.2.2.1.(15)(c)',
                      ruling: 'D-57')
          return result.merge(required: false,
                              reason: format('4.2.2.1.(15)(c) exception: latitude %.2f degN > 55 degN and ' \
                                             '%.0f W < 200 W', latitude, power_w))
        end

        if power_w >= TOPLIGHTING_THRESHOLD_W
          result.merge(required: true,
                       reason: format('4.2.2.1.(13): %.0f W of general lighting in %.1f m2 of daylighted area ' \
                                      'under skylights >= 150 W', power_w, areas[:toplighted_m2]))
        else
          result.merge(required: false,
                       reason: format('below the 4.2.2.1.(13) threshold: %.0f W in %.1f m2 of daylighted area ' \
                                      'under skylights (< 150 W)', power_w, areas[:toplighted_m2]))
        end
      end

      # Is the Table 4.2.1.6. column gate open? 'not_listed' and 'not_applicable'
      # are DETERMINATIONS read from the code text and are logged once as such;
      # only 'unknown' falls back on the caller's documented default, LOUDLY.
      def column_state(value, unknown_default, space, column, row, audit, standards_type = nil, seen = nil)
        sentence = column == 'sidelighting' ? 10 : 13
        label = standards_type || row['table_row'] || '(untagged space type)'
        case value
        when 'required' then true
        when 'not_required', 'not_applicable' then false
        when 'not_listed'
          if seen.nil? || seen["not_listed|#{label}|#{column}"].nil?
            seen && seen["not_listed|#{label}|#{column}"] = true
            audit&.info(:daylighting,
                        "space type '#{label}' has NO Table 4.2.1.6. row, and 4.2.2.1.(#{sentence}) reaches " \
                        'only spaces requiring the control "in accordance with Table 4.2.1.6." (4.2.2.1.(2) ' \
                        "ties the requirement to that table's space-by-space types) — so #{column} " \
                        "photocontrols are not required for it. #{row['note']}",
                        target: space.nameString, article: "4.2.1.6.; 4.2.2.1.(#{sentence}); 4.2.2.1.(2)",
                        ruling: 'D-57')
          end
          false
        else
          if seen.nil? || seen["unknown|#{label}|#{column}"].nil?
            seen && seen["unknown|#{label}|#{column}"] = true
            audit&.warn(:daylighting,
                        "TABLE 4.2.1.6. #{column.upcase} COLUMN IS UNRESOLVED for space type " \
                        "'#{label}' (row #{row['table_row'].inspect}) — " \
                        "#{row["evidence_#{column}"] || row['evidence']}. Every space of this type therefore " \
                        "takes the documented conservative default (#{unknown_default}); photocontrols in the " \
                        'REFERENCE lower its lighting energy and so tighten the target, which cannot grant an ' \
                        "undeserved pass. First seen on '#{space.nameString}'",
                        target: space.nameString, article: "4.2.1.6.; 4.2.2.1.(#{sentence})",
                        ruling: 'D-57')
          end
          unknown_default == :required
        end
      end

      # --- inputs ---------------------------------------------------------------

      def standards_space_type(space)
        return nil if space.spaceType.empty?

        space_type = space.spaceType.get
        space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
      end

      # W/m2 of GENERAL lighting for a space: every Lights instance reaching the
      # space except the 4.2.1.6. specialty/decorative "Additional Lights"
      # allowance, which 4.2.2.1.(10)/(13) do not cover.
      def general_lighting_lpd(space)
        floor_area = space.floorArea
        instances = space.lights.to_a
        instances += space.spaceType.get.lights.to_a if space.spaceType.is_initialized
        instances.sum do |instance|
          next 0.0 if instance.nameString =~ /additional/i

          definition = instance.lightsDefinition
          multiplier = instance.multiplier
          case definition.designLevelCalculationMethod
          when 'Watts/Area'
            definition.wattsperSpaceFloorArea.is_initialized ? definition.wattsperSpaceFloorArea.get * multiplier : 0.0
          when 'LightingLevel'
            next 0.0 unless definition.lightingLevel.is_initialized && floor_area > 0.0

            definition.lightingLevel.get * multiplier / floor_area
          when 'Watts/Person'
            next 0.0 unless definition.wattsperPerson.is_initialized && floor_area > 0.0

            definition.wattsperPerson.get * multiplier * space.numberOfPeople / floor_area
          else
            0.0
          end
        end
      end

      def site_latitude(model)
        site = model.getSite
        latitude = site.latitude
        latitude.zero? ? nil : latitude
      rescue StandardError
        nil
      end

      # World-coordinate shading surfaces, computed once per model.
      # @return [Array<Array<OpenStudio::Point3d>>]
      def shading_polygons(model)
        model.getShadingSurfaceGroups.flat_map do |group|
          transformation = group.transformation
          group.shadingSurfaces.map { |surface| (transformation * surface.vertices).to_a }
        end
      end

      # 4.2.2.1.(12)(a): "the vertical projected distance from the top of the
      # windows to the top of any adjacent structure divided by the horizontal
      # distance from the window to the adjacent structure". Adjacent structures
      # in an OpenStudio model are ShadingSurfaces; the ratio is taken per window
      # against every shading surface and the LARGEST governs (the sentence says
      # "any adjacent structure").
      # @return [Float, nil] nil when the model carries no shading surfaces, in
      #   which case the exception has nothing to apply to
      def obstruction_ratio(space, shading_surfaces = nil)
        polygons = shading_surfaces || shading_polygons(space.model)
        return nil if polygons.empty?

        transformation = space.transformation
        best = nil
        space.surfaces.each do |surface|
          next unless surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'

          surface.subSurfaces.each do |sub|
            next unless DaylightedAreas::WINDOW_TYPES.include?(sub.subSurfaceType)

            world = (transformation * sub.vertices).to_a
            head_z = world.map(&:z).max
            centre_x = world.sum(&:x) / world.size
            centre_y = world.sum(&:y) / world.size
            polygons.each do |polygon|
              rise = polygon.map(&:z).max - head_z
              next unless rise.positive?

              run = plan_distance(centre_x, centre_y, polygon)
              next unless run.positive?

              ratio = rise / run
              best = ratio if best.nil? || ratio > best
            end
          end
        end
        best
      end

      # Shortest distance in PLAN from a point to a polygon's boundary — measured
      # to the edges, not only the vertices, so a broad wall 5 m away reads 5 m
      # (a vertex-only measure would read the diagonal and understate the ratio).
      def plan_distance(point_x, point_y, polygon)
        polygon.each_with_index.map do |vertex, index|
          nxt = polygon[(index + 1) % polygon.size]
          segment_distance(point_x, point_y, vertex.x, vertex.y, nxt.x, nxt.y)
        end.min
      end

      def segment_distance(point_x, point_y, ax, ay, bx, by)
        dx = bx - ax
        dy = by - ay
        length_squared = (dx * dx) + (dy * dy)
        t = length_squared.zero? ? 0.0 : (((point_x - ax) * dx) + ((point_y - ay) * dy)) / length_squared
        t = [[t, 0.0].max, 1.0].min
        Math.sqrt(((point_x - (ax + (t * dx)))**2) + ((point_y - (ay + (t * dy)))**2))
      end
    end
  end
end
