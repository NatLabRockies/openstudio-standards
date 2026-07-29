module OpenStudioLighting
  module NECB
    # Daylighting controls. Two selection rules live here, chosen by `placement:`:
    #
    #   :necb2020 (DEFAULT) — NECB 2020/2025 Article 4.2.2.1., sentences
    #     (10)-(15): photocontrols where the Table 4.2.1.6. column for the space
    #     type requires them AND the general-lighting input POWER inside the
    #     daylighted areas crosses 150 W / 300 W (sidelighting) or 150 W
    #     (toplighting), the two tested INDEPENDENTLY, with the (12)/(15)
    #     exceptions honoured. Areas come from DaylightedAreas (unioned polygons,
    #     4.2.2.3./4.2.2.4./4.2.2.5.), the requirement from
    #     DaylightControlRequirement. See D-57.
    #
    #   :necb2011 — the legacy-exact port of model_add_daylighting_controls'
    #     'NECB_Default' selection, defects and all, kept reachable so
    #     test_daylighting_parity.rb can still prove the port faithful. It applies
    #     NECB 2011 criteria (areas and effective apertures, ANDed) and is WRONG
    #     for 2020/2025 — that is L-26.
    #
    #   :all — every space with exterior fenestration gets a sensor regardless of
    #     any threshold (the legacy 'add_daylighting_controls' option).
    #
    # Sensor hardware, all paths: ONE DaylightingControl at the centre of the
    # space's lowest floor bounding box, 0.8 m above the floor, illuminance
    # setpoint from the space-type target_illuminance_setpoint, wired as the
    # zone's primary control. Stepped control with 3 steps on the :necb2020 path
    # (4.2.2.1.(11)(a)(i) and (14)(a)(i) want one intermediate level at 50-70% of
    # design power, another at 20-40%, and a point that turns the lighting off;
    # E+ 3-step control gives exactly 67% / 33% / off), 2 steps on the legacy
    # paths (the NECB 2011 minimum, kept for parity).
    #
    # CITATION HYGIENE: the legacy method's docstrings cite 4.2.2.7. through
    # 4.2.2.10. Subsection 4.2.2 of NECB 2020/2025 ENDS AT ARTICLE 4.2.2.6.
    # ("Special Applications"), so those articles DO NOT EXIST in either edition;
    # they were NECB 2011 numbers. Where the legacy behaviour is described below
    # the 2011 numbers are named as such, and the live 2020/2025 articles are
    # 4.2.2.1. (controls), 4.2.2.3. (sidelighted areas), 4.2.2.4. (roof monitors)
    # and 4.2.2.5. (skylights).
    module Daylighting
      module_function

      STEPPED_STEPS = 2 # legacy paths: the NECB 2011 minimum
      STEPPED_STEPS_2020 = 3 # 4.2.2.1.(11)(a)(i) / (14)(a)(i): 67% / 33% / off

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

      # @param option ['all', 'NECB_Default'] 'all' = every daylighted space gets a
      #   sensor (legacy add_daylighting_controls option); 'NECB_Default' = only
      #   spaces where 4.2.2 requires photocontrols — which RULE decides that is
      #   `placement:`
      # @param placement [:necb2020, :necb2011] the 'NECB_Default' selection rule.
      #   :necb2020 (default) = Article 4.2.2.1.(10)-(15) on unioned daylighted
      #   areas (D-57); :necb2011 = the legacy-exact 2011 port, defects included,
      #   kept reachable for the parity gate
      # @param office_match [:legacy, :any_enclosed_office] :necb2011 ONLY — the
      #   >=25 m2 office exemption matcher. :legacy preserves the exact string
      #   'Office - enclosed', which does NOT exist in the NECB2020 space-type
      #   names, so the exemption never fires on 2020 models (defect, audited);
      #   :any_enclosed_office matches the intent (/office enclosed/i)
      # @param unknown_control_requirement [:required, :not_required] :necb2020
      #   ONLY — what to assume when the Table 4.2.1.6. column cannot be resolved
      #   for a space type. Always warns; see DaylightControlRequirement#evaluate
      # @return [Integer] number of controls created
      def add_controls(model, vintage: '2020', option: 'all', placement: :necb2020,
                       office_match: :legacy, unknown_control_requirement: :required, audit: nil)
        audit ||= AuditLog.new
        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        created = 0
        fractions = {}

        if option == 'NECB_Default' && placement == :necb2011
          eligible = necb_default_spaces(model, office_match, audit)
          rule = 'NECB 2011 (legacy-exact)'
        elsif option == 'NECB_Default'
          eligible, fractions = necb2020_spaces(model, audit, unknown_control_requirement)
          rule = 'NECB 2020/2025 4.2.2.1.(10)-(15)'
        else
          eligible = model.getSpaces.sort_by(&:nameString).select { |s| daylighted?(s) }
          rule = 'all daylighted spaces'
        end
        steps = fractions.empty? ? STEPPED_STEPS : STEPPED_STEPS_2020

        eligible.each do |space|
          next if space.thermalZone.empty?

          zone = space.thermalZone.get
          next if zone.primaryDaylightingControl.is_initialized

          setpoint = illuminance_setpoint(space, data_vintage)
          if setpoint.nil?
            audit.warn(:daylighting, 'no target_illuminance_setpoint for this space type — no sensor placed',
                       target: space.nameString)
            next
          end

          bounds = lowest_floor_bounds(space)
          next if bounds.nil?

          # 4.2.2.1.(10)/(13) control the general lighting IN THE DAYLIGHTED
          # AREAS, not the whole room, so the zone fraction under control is the
          # daylighted share of the zone floor area — not 1.0 (which is what the
          # legacy paths use, and what makes their reference over-credit).
          fraction = fractions.key?(space.nameString) ? zone_fraction(space, zone, fractions[space.nameString]) : 1.0
          next if fraction <= 0.0

          sensor = OpenStudio::Model::DaylightingControl.new(model)
          sensor.setName("#{space.nameString} daylighting control")
          sensor.setSpace(space)
          sensor.setIlluminanceSetpoint(setpoint)
          sensor.setLightingControlType('Stepped')
          sensor.setNumberofSteppedControlSteps(steps)
          sensor.setPosition(OpenStudio::Point3d.new((bounds[:xmin] + bounds[:xmax]) / 2.0,
                                                     (bounds[:ymin] + bounds[:ymax]) / 2.0,
                                                     bounds[:zmin] + 0.8))
          zone.setPrimaryDaylightingControl(sensor)
          zone.setFractionofZoneControlledbyPrimaryDaylightingControl(fraction)
          created += 1
          sensor_article = if fractions.empty?
                             '4.2.2.1. (sensor hardware)'
                           else
                             '4.2.2.1.(10); 4.2.2.1.(11); 4.2.2.1.(13); 4.2.2.1.(14)'
                           end
          audit.info(:daylighting, "daylighting control placed (#{rule})",
                     target: space.nameString,
                     inputs: { illuminance_lux: setpoint, control: "Stepped x#{steps}",
                               zone_fraction: fraction.round(4) },
                     article: sensor_article,
                     ruling: 'D-57')
        end

        # D-57 governs WHICH rule this method just used — including the choice to
        # keep the legacy 2011 path reachable — so every path cites it.
        audit.decision(:daylighting, "daylighting controls added by the #{rule} rule",
                       inputs: { controls: created, option: option, placement: placement },
                       article: '4.2.2.1.',
                       ruling: 'D-57')
        created
      end

      # The daylighted share of the ZONE's floor area that this space's control
      # governs. E+ applies the fraction zone-wide, so a space's daylighted area
      # is divided by the zone floor area, not the space's.
      def zone_fraction(space, zone, controlled_area_m2)
        denominator = zone.floorArea
        denominator = space.floorArea if denominator.nil? || denominator <= 0.0
        return 0.0 if denominator.nil? || denominator <= 0.0

        [[controlled_area_m2 / denominator, 1.0].min, 0.0].max
      end

      # NECB 2020/2025 4.2.2.1.(10)-(15) selection. Sidelighting and toplighting
      # are evaluated INDEPENDENTLY and unioned — a space qualifies on either.
      # @return [Array(Array<OpenStudio::Model::Space>, Hash)] the spaces that
      #   require photocontrols, and space name => controlled daylighted area m2
      def necb2020_spaces(model, audit, unknown_control_requirement)
        shading = DaylightControlRequirement.shading_polygons(model)
        if shading.empty?
          audit.info(:daylighting,
                     'the 4.2.2.1.(12)(a) obstruction-ratio exception cannot apply: the model carries no ' \
                     'shading surfaces, so there is no adjacent structure to measure against',
                     article: '4.2.2.1.(12)(a)',
                     ruling: 'D-57')
        end
        audit.warn(:daylighting,
                   'THE 4.2.2.1.(15)(a) EXCEPTION IS NOT EVALUATED: whether adjacent structures or natural ' \
                   'objects block direct sunlight for more than 1 500 h/yr between 8 a.m. and 4 p.m. needs an ' \
                   'annual solar-obstruction study, which an SDK-only gem that never simulates cannot do. ' \
                   'Not applying an exception is the STRICT direction (toplighting photocontrols are required ' \
                   'where they might have been excused), so no reference target is loosened by this gap',
                   article: '4.2.2.1.(15)(a)',
                   ruling: 'D-57')
        audit.info(:daylighting, DaylightedAreas.limitations,
                   article: '4.2.2.3.; 4.2.2.4.; 4.2.2.5.',
                   ruling: 'D-57')

        selected = []
        controlled = {}
        evidence = []
        seen = {} # dedupe the unresolved-column notices: one per (space type, column)
        side_count = 0
        top_count = 0
        model.getSpaces.sort_by(&:nameString).each do |space|
          next unless space.partofTotalFloorArea
          next unless daylighted?(space)

          verdict = DaylightControlRequirement.evaluate(space, audit: audit,
                                                        unknown_default: unknown_control_requirement,
                                                        shading_surfaces: shading, seen: seen)
          areas = verdict[:areas]
          side = verdict[:sidelighting][:required]
          top = verdict[:toplighting][:required]
          side_count += 1 if side
          top_count += 1 if top
          unless verdict[:required]
            audit.info(:daylighting, 'no photocontrols required',
                       target: space.nameString,
                       inputs: { sidelighting: verdict[:sidelighting][:reason],
                                 toplighting: verdict[:toplighting][:reason] },
                       article: '4.2.2.1.(10); 4.2.2.1.(13)',
                       ruling: 'D-57')
            next
          end

          area = 0.0
          area += areas[:primary_sidelighted_m2] + areas[:secondary_sidelighted_m2] if side
          area += areas[:toplighted_m2] if top
          selected << space
          controlled[space.nameString] = area
          evidence << "#{space.nameString}: #{side ? verdict[:sidelighting][:reason] : ''}" \
                      "#{side && top ? ' + ' : ''}#{top ? verdict[:toplighting][:reason] : ''}"
          audit.info(:daylighting, 'photocontrols required',
                     target: space.nameString,
                     inputs: { general_lpd_w_per_m2: verdict[:lpd_w_per_m2].round(3),
                               primary_sidelighted_m2: areas[:primary_sidelighted_m2].round(2),
                               secondary_sidelighted_m2: areas[:secondary_sidelighted_m2].round(2),
                               toplighted_m2: areas[:toplighted_m2].round(2),
                               floor_m2: areas[:floor_m2].round(2),
                               sidelighting: side, toplighting: top },
                     value: format('%.1f m2 under photocontrol', area),
                     evidence: [side ? verdict[:sidelighting][:reason] : nil,
                                top ? verdict[:toplighting][:reason] : nil].compact.join(' + '),
                     article: '4.2.2.1.(10); 4.2.2.1.(13)',
                     ruling: 'D-57')
        end

        audit.decision(:daylighting,
                       'photocontrol requirement determined per 4.2.2.1.(10)-(15): the Table 4.2.1.6. column ' \
                       'for the space type gates each of sidelighting and toplighting, and each is then a test ' \
                       'of general-lighting INPUT POWER inside the daylighted area. With a uniform space-level ' \
                       'LPD that power is exactly LPD x daylighted_area, so no luminaire layout is needed. ' \
                       'Sidelighting (>=150 W primary, or >=300 W primary + secondary) and toplighting ' \
                       '(>=150 W under skylights) are INDEPENDENT — never ANDed as the NECB 2011 criteria were',
                       inputs: { daylighted_spaces: model.getSpaces.count { |s| s.partofTotalFloorArea && daylighted?(s) },
                                 sidelighting_required: side_count, toplighting_required: top_count,
                                 spaces_selected: selected.size,
                                 unknown_column_default: unknown_control_requirement },
                       evidence: evidence.first(5).join('; '),
                       article: '4.2.2.1.(10); 4.2.2.1.(12); 4.2.2.1.(13); 4.2.2.1.(15); Table 4.2.1.6.',
                       ruling: 'D-57')
        [selected, controlled]
      end

      # The legacy NECB_Default selection, defects preserved and audited. It is
      # NECB 2011 machinery: a space is EXCEPTED (no sensor) if it fails ANY
      # single criterion — primary sidelighted area <= 100 m2, sidelighting
      # effective aperture <= 0.1, daylighted area under skylights <= 400 m2 or
      # skylight effective aperture <= 0.006 — unless it is an office >= 25 m2.
      # (Legacy cites 4.2.2.4./4.2.2.7./4.2.2.8./4.2.2.10. for these; those are
      # 2011 numbers. NECB 2020/2025 Subsection 4.2.2 ends at 4.2.2.6., so
      # 4.2.2.7.-4.2.2.10. do not exist there, and 4.2.2.4. means something else
      # entirely — roof monitors.) CONSEQUENCES (legacy behavior): window-only
      # spaces are ALWAYS excepted (their skylight area is 0 <= 400); skylight-
      # only spaces likewise (the skylight-area accumulator only runs inside the
      # window loop). With :legacy office matching on 2020 models the office
      # exemption never fires ('Office - enclosed' is a 2011-era name).
      def necb_default_spaces(model, office_match, audit)
        daylight_spaces = model.getSpaces.sort_by(&:nameString).select { |s| daylighted?(s) }
        offices = daylight_spaces.select do |space|
          next false if space.spaceType.empty? || space.spaceType.get.standardsSpaceType.empty?

          name = space.spaceType.get.standardsSpaceType.get
          matches = office_match == :legacy ? name == 'Office - enclosed' : name =~ /office\s*-?\s*enclosed/i
          matches && lowest_floor_area(space) >= 25.0
        end.map(&:nameString)

        if office_match == :legacy && offices.empty? &&
           daylight_spaces.any? { |s| s.spaceType.is_initialized && s.spaceType.get.standardsSpaceType.to_s =~ /office/i }
          audit.warn(:daylighting,
                     "office >=25 m2 exemption matched NOTHING: legacy compares to the 2011-era name 'Office - enclosed', " \
                     "which does not exist in the NECB2020 space-type names — pass office_match: :any_enclosed_office for the intent")
        end

        excepted = []
        metrics = {}
        daylight_spaces.each do |space|
          side = sidelighting_parameters(space, audit: audit)
          sky = skylight_parameters(space, audit: audit)
          side_ea = side[:window_area_m2] * (side[:vt_handle] / side[:window_area_m2]) / side[:area_m2]
          sky_ea = 0.85 * sky[:skylight_area_m2] * (sky[:vt_handle] / sky[:skylight_area_m2]) * 0.9 / sky[:area_m2]
          metrics[space.nameString] = { sidelighted_m2: side[:area_m2].round(2), side_ea: side_ea.round(4),
                                        skylight_m2: sky[:area_m2].round(2), sky_ea: sky_ea.round(5) }
          office = offices.include?(space.nameString)
          excepted << space.nameString if !office &&
                                          (side[:area_m2] <= 100.0 || (side_ea <= 0.1) ||
                                           sky[:area_m2] <= 400.0 || (sky_ea <= 0.006))
        end
        audit.warn(:daylighting,
                   'LEGACY NECB 2011 THRESHOLD EVALUATION IN USE (placement: :necb2011): any single failed ' \
                   'criterion excepts a space, so a window-only space NEVER gets photocontrols. This is not ' \
                   'the 2020/2025 requirement — 4.2.2.1.(10) and (13) are independent input-POWER tests. The ' \
                   'path exists only to keep the legacy parity gate callable (L-26, D-57)',
                   inputs: { daylighted: daylight_spaces.size, excepted: excepted.size, offices_exempt: offices.size },
                   evidence: metrics.first(5).map { |k, v| "#{k}: #{v}" }.join('; '),
                   article: 'NECB 2011 4.2.2.4./4.2.2.7./4.2.2.8./4.2.2.10. (articles that DO NOT EXIST in NECB 2020/2025, whose Subsection 4.2.2 ends at 4.2.2.6.)',
                   ruling: 'D-57')
        daylight_spaces.reject { |s| excepted.include?(s.nameString) }
      end

      def lowest_floor_area(space)
        floors = space.surfaces.select { |s| s.surfaceType == 'Floor' }
        return 0.0 if floors.empty?

        lowest_z = floors.map { |f| f.vertices.map(&:z).min }.min
        floors.select { |f| f.vertices.map(&:z).min == lowest_z }.sum(&:netArea)
      end

      def daylighted?(space)
        space.surfaces.any? do |surface|
          surface.subSurfaces.any? do |sub|
            sub.outsideBoundaryCondition == 'Outdoors' &&
              %w[FixedWindow OperableWindow Skylight].include?(sub.subSurfaceType)
          end
        end
      end

      def illuminance_setpoint(space, data_vintage)
        return nil if space.spaceType.empty?

        space_type = space.spaceType.get
        return nil unless space_type.standardsBuildingType.is_initialized && space_type.standardsSpaceType.is_initialized

        record = OpenStudioLoads::NECB::SpaceTypes.find(
          building_type: space_type.standardsBuildingType.get,
          space_type: space_type.standardsSpaceType.get, vintage: data_vintage)
        return nil if record.nil?

        value = record['target_illuminance_setpoint'].to_f
        value.zero? ? nil : value
      end

      def lowest_floor_bounds(space)
        floors = space.surfaces.select { |s| s.surfaceType == 'Floor' }
        return nil if floors.empty?

        lowest_z = floors.map { |f| f.vertices.map(&:z).min }.min
        lowest = floors.select { |f| f.vertices.map(&:z).min == lowest_z }
        points = lowest.flat_map(&:vertices)
        { xmin: points.map(&:x).min, xmax: points.map(&:x).max,
          ymin: points.map(&:y).min, ymax: points.map(&:y).max, zmin: lowest_z }
      end
    end

    def self.add_daylighting_controls(model, **kwargs)
      Daylighting.add_controls(model, **kwargs)
    end
  end

  # Facade: add NECB daylighting controls (all-daylighted-spaces option).
  def self.add_daylighting_controls(model, **kwargs)
    NECB.add_daylighting_controls(model, **kwargs)
  end
end
