module OpenStudioLighting
  module NECB
    # Daylighting controls — port of the legacy model_add_daylighting_controls
    # 'add_daylighting_controls' option: every space with exterior fenestration
    # (fixed/operable window or skylight) gets ONE DaylightingControl at the
    # centre of its lowest floor's bounding box, 0.8 m above the floor, Stepped
    # control with 2 steps (NECB minimum), illuminance setpoint from the
    # space-type target_illuminance_setpoint, wired as the zone's primary
    # control at fraction 1.0.
    #
    # HONEST SCOPE: the NECB-threshold option (sensors ONLY where 4.2.2 requires
    # them, driven by the primary-sidelighted-area / effective-aperture geometry)
    # is NOT ported — the daylighted-area machinery remains a documented future.
    # This is the legacy Option #2 semantics ("sensors in all daylighted spaces
    # regardless of NECB requirements").
    module Daylighting
      module_function

      STEPPED_STEPS = 2 # NECB minimum

      # ---- Daylighted-area geometry (verbatim ports of legacy
      # get_parameters_sidelighting / get_parameters_skylight) -------------------

      # Primary sidelighted area (NECB 4.2.2.9): per exterior-wall window at floor
      # level, depth = min(window head height, space depth), width = window width
      # + min(distance to each side wall, 0.6 m).
      # @return [Hash] { area_m2:, vt_handle:, window_area_m2: } (vt_handle =
      #   sum(window area x VT), for the 4.2.2.10 effective aperture)
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

      # Daylighted area under skylights (NECB 4.2.2.5) + VT sums for the 4.2.2.7
      # effective aperture. LEGACY DEFECT preserved for parity (audited by the
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
      #   spaces passing the 4.2.2 thresholds (legacy-exact, incl. its defects —
      #   see necb_default_spaces)
      # @param office_match [:legacy, :any_enclosed_office] the >=25 m2 office
      #   exemption matcher — :legacy preserves the exact string
      #   'Office - enclosed', which does NOT exist in the NECB2020 space-type
      #   names, so the exemption never fires on 2020 models (defect, audited);
      #   :any_enclosed_office matches the intent (/office enclosed/i)
      # @return [Integer] number of controls created
      def add_controls(model, vintage: '2020', option: 'all', office_match: :legacy, audit: nil)
        audit ||= AuditLog.new
        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        created = 0

        eligible = if option == 'NECB_Default'
                     necb_default_spaces(model, office_match, audit)
                   else
                     model.getSpaces.sort_by(&:nameString).select { |s| daylighted?(s) }
                   end

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

          sensor = OpenStudio::Model::DaylightingControl.new(model)
          sensor.setName("#{space.nameString} daylighting control")
          sensor.setSpace(space)
          sensor.setIlluminanceSetpoint(setpoint)
          sensor.setLightingControlType('Stepped')
          sensor.setNumberofSteppedControlSteps(STEPPED_STEPS)
          sensor.setPosition(OpenStudio::Point3d.new((bounds[:xmin] + bounds[:xmax]) / 2.0,
                                                     (bounds[:ymin] + bounds[:ymax]) / 2.0,
                                                     bounds[:zmin] + 0.8))
          zone.setPrimaryDaylightingControl(sensor)
          zone.setFractionofZoneControlledbyPrimaryDaylightingControl(1.0)
          created += 1
          audit.info(:daylighting, 'daylighting control placed (all-daylighted-spaces option)',
                     target: space.nameString,
                     inputs: { illuminance_lux: setpoint, control: 'Stepped x2', fraction: 1.0 },
                     article: '4.2.2. (sensor hardware; threshold geometry not evaluated)')
        end

        audit.decision(:daylighting,
                       option == 'NECB_Default' ? 'daylighting controls added where the 4.2.2 thresholds require them (legacy-exact)' : 'daylighting controls added to every daylighted space',
                       inputs: { controls: created, option: option }, article: '4.2.2.')
        created
      end

      # The legacy NECB_Default selection, defects preserved and audited:
      # a space is EXCEPTED (no sensor) if it fails ANY single criterion —
      # primary sidelighted area <= 100 m2 (4.2.2.4), sidelighting effective
      # aperture <= 0.1 (4.2.2.10), daylighted area under skylights <= 400 m2
      # (4.2.2.8) or skylight effective aperture <= 0.006 (4.2.2.7) — unless it
      # is an office >= 25 m2. CONSEQUENCES (legacy behavior): window-only
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
        audit.info(:daylighting, 'NECB_Default threshold evaluation (any single failed criterion excepts a space — legacy semantics)',
                   inputs: { daylighted: daylight_spaces.size, excepted: excepted.size, offices_exempt: offices.size },
                   evidence: metrics.first(5).map { |k, v| "#{k}: #{v}" }.join('; '),
                   article: '4.2.2.4.; 4.2.2.5.; 4.2.2.7.-4.2.2.10.')
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
