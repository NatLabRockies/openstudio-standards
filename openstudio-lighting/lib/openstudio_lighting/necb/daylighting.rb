module OpenStudioLighting
  module NECB
    # Daylighting controls. ONE knob selects who gets a sensor — `placement:`
    # (the older `option:` is a deprecated alias for it, mapped and audited in
    # Daylighting.resolve_placement):
    #
    #   :all (DEFAULT for add_controls) — every space with exterior
    #     fenestration gets a sensor regardless of any threshold (the legacy
    #     'add_daylighting_controls' blanket option). ReferenceDaylighting.apply
    #     defaults to :necb2020 instead, because the reference building must be
    #     built to the code rule.
    #
    #   :necb2020 — NECB 2020/2025 Article 4.2.2.1., sentences
    #     (10)-(15): photocontrols where the Table 4.2.1.6. column for the space
    #     type requires them AND the general-lighting input POWER inside the
    #     daylighted areas crosses 150 W / 300 W (sidelighting) or 150 W
    #     (toplighting), the two tested INDEPENDENTLY, with the (12)/(15)
    #     exceptions honoured. Areas come from DaylightedAreas (unioned polygons,
    #     4.2.2.3./4.2.2.4./4.2.2.5.), the requirement from
    #     DaylightControlRequirement. See D-57.
    #
    #   :necb2011 — the legacy-exact port of model_add_daylighting_controls'
    #     'NECB_Default' selection, mirroring legacy AS FIXED BY #2119 (merged
    #     2026-07-15, in tree since the origin/nrcan merge), kept reachable so
    #     test_daylighting_parity.rb can still prove the port faithful. It
    #     applies NECB 2011 criteria (areas and effective apertures, ANDed
    #     within the fenestration type a space actually has) and is WRONG for
    #     2020/2025 — that is L-26. What is left between the two is a RULE
    #     difference between the editions, not a defect.
    #     (:necb_default is an accepted alias.)
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

      # MOVED: the legacy NECB 2011 daylighted-area math (pinned to legacy as
      # fixed by #2119) —
      # sidelighting_parameters / skylight_parameters + the dist / triangle_height /
      # wall_point_distance helpers — now lives in necb/daylighted_areas_legacy_2011.rb,
      # which reopens this module, so every constant path here is unchanged.

      # @param placement [:all, :necb2020, :necb2011] THE selection knob — which
      #   spaces get a sensor. :all (DEFAULT) = every space with exterior
      #   fenestration, no threshold (the legacy blanket option); :necb2020 =
      #   Article 4.2.2.1.(10)-(15) on unioned daylighted areas (D-57);
      #   :necb2011 (alias :necb_default) = the legacy-exact 2011 port, defects
      #   included, kept reachable for the parity gate
      # @param option ['all', 'NECB_Default', nil] DEPRECATED alias for
      #   `placement:`, kept so existing callers keep working: 'all' forces
      #   placement :all; 'NECB_Default' selects the code rule, i.e. the given
      #   `placement:` when it names one (:necb2011), else :necb2020. Passing it
      #   logs an audit info entry. Prefer `placement:` alone.
      # @param office_match [:legacy, :any_enclosed_office] :necb2011 ONLY — the
      #   >=25 m2 office exemption matcher. Both values now BEHAVE IDENTICALLY:
      #   #2119 replaced legacy's exact `== 'Office - enclosed'` (a 2011-era
      #   name that never matched the NECB2015+/2020 'Office enclosed <= 25 m2'
      #   / '> 25 m2' names) with /office\s*-?\s*enclosed/i, which is what
      #   :any_enclosed_office already meant. Both stay accepted; :legacy is the
      #   value pinned to whatever legacy does, so if legacy's matcher moves
      #   again only :legacy follows it.
      # @param unknown_control_requirement [:required, :not_required] :necb2020
      #   ONLY — what to assume when the Table 4.2.1.6. column cannot be resolved
      #   for a space type. Always warns; see DaylightControlRequirement#evaluate
      # @return [Integer] number of controls created
      def add_controls(model, vintage: '2020', placement: nil, option: nil,
                       office_match: :legacy, unknown_control_requirement: :required, audit: nil)
        audit ||= AuditLog.new
        placement = resolve_placement(placement, option, audit)
        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        created = 0
        fractions = {}

        case placement
        when :necb2011
          eligible = necb_default_spaces(model, office_match, audit)
          rule = 'NECB 2011 (legacy-exact)'
        when :necb2020
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
                       inputs: { controls: created, placement: placement },
                       article: '4.2.2.1.',
                       ruling: 'D-57')
        created
      end

      PLACEMENTS = %i[all necb2020 necb2011].freeze

      # ONE selector. `placement:` is it; `option:` is the deprecated alias that
      # used to share the job (and used to win, silently ignoring `placement:`).
      # The mapping reproduces the old truth table exactly:
      #   option 'all'          -> :all                (whatever placement said)
      #   option 'NECB_Default' -> :necb2011 if placement named it, else :necb2020
      #   option nil            -> placement, defaulting to :all
      # @return [Symbol] one of PLACEMENTS
      def resolve_placement(placement, option, audit)
        given = placement.nil? ? nil : normalize_placement(placement)
        return given || :all if option.nil?

        resolved = case option.to_s
                   when 'NECB_Default' then given == :necb2011 ? :necb2011 : :necb2020
                   else :all # 'all', and anything unrecognized, as the legacy branch did
                   end
        audit&.info(:daylighting,
                    "the `option:` argument is DEPRECATED — `placement:` is now the single selector; " \
                    "option: #{option.inspect} was read as placement: #{resolved.inspect}",
                    inputs: { option: option, placement_given: placement, placement_used: resolved },
                    article: '4.2.2.1.',
                    ruling: 'D-57')
        resolved
      end

      # PUBLIC (deliberately): the one place that knows the placement vocabulary,
      # so callers that must branch on the rule (ReferenceDaylighting) resolve the
      # :necb_default alias here instead of keeping a second copy of the mapping.
      # @return [Symbol] :all | :necb2020 | :necb2011
      def normalize_placement(placement)
        value = placement.to_sym
        value = :necb2011 if value == :necb_default
        unless PLACEMENTS.include?(value)
          raise ArgumentError, "unknown placement: #{placement.inspect} (expected one of " \
                               "#{PLACEMENTS.map(&:inspect).join(', ')}, or :necb_default for :necb2011)"
        end

        value
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

      # The legacy NECB_Default selection, MIRRORING LEGACY AS FIXED BY #2119
      # (merged 2026-07-15). It is NECB 2011 machinery: a space is EXCEPTED (no
      # sensor) if it fails ANY single APPLICABLE criterion — primary
      # sidelighted area <= 100 m2 or sidelighting effective aperture <= 0.1
      # (applied ONLY to spaces WITH exterior windows), daylighted area under
      # skylights <= 400 m2 or skylight effective aperture <= 0.006 (applied
      # ONLY to spaces WITH skylights) — unless it is an office >= 25 m2.
      # (Legacy cites 4.2.2.4./4.2.2.7./4.2.2.8./4.2.2.10. for these; those are
      # 2011 numbers. NECB 2020/2025 Subsection 4.2.2 ends at 4.2.2.6., so
      # 4.2.2.7.-4.2.2.10. do not exist there, and 4.2.2.4. means something else
      # entirely — roof monitors.)
      #
      # The pre-#2119 defects are gone from both sides: a window-only space is
      # no longer auto-excepted by a skylight criterion it cannot meet (its
      # skylight area was 0 <= 400), a skylight-only space likewise, and the
      # >=25 m2 office exemption now matches the 2015+/2020 space-type names.
      # What is left is a 2011-vs-2020 RULE difference: these thresholds are
      # ANDed area/aperture tests, where 4.2.2.1.(10)/(13) are INDEPENDENT
      # input-POWER tests (L-26, D-57).
      def necb_default_spaces(model, office_match, audit)
        daylight_spaces = model.getSpaces.sort_by(&:nameString).select { |s| daylighted?(s) }
        # #2119 made legacy's office test a regex — `== 'Office - enclosed'`
        # became `=~ /office\s*-?\s*enclosed/i` — so :legacy and
        # :any_enclosed_office now COINCIDE. Both stay accepted (callers and
        # docs name either), and :legacy is still the one pinned to legacy: if
        # legacy's matcher ever changes again, only the :legacy branch moves.
        offices = daylight_spaces.select do |space|
          next false if space.spaceType.empty? || space.spaceType.get.standardsSpaceType.empty?

          name = space.spaceType.get.standardsSpaceType.get
          (name =~ /office\s*-?\s*enclosed/i) && lowest_floor_area(space) >= 25.0
        end.map(&:nameString)

        # Which criteria even apply, per #2119: window criteria to spaces with
        # exterior windows, skylight criteria to spaces with skylights.
        with_windows = []
        with_skylights = []
        daylight_spaces.each do |space|
          space.surfaces.sort_by(&:nameString).each do |surface|
            surface.subSurfaces.sort_by(&:nameString).each do |sub|
              next unless sub.outsideBoundaryCondition == 'Outdoors'

              if %w[FixedWindow OperableWindow].include?(sub.subSurfaceType)
                with_windows << space.nameString
              elsif sub.subSurfaceType == 'Skylight'
                with_skylights << space.nameString
              end
            end
          end
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
          next if offices.include?(space.nameString)

          windowed = with_windows.include?(space.nameString)
          skylit = with_skylights.include?(space.nameString)
          excepted << space.nameString if (windowed && side[:area_m2] <= 100.0) ||
                                          (windowed && side_ea <= 0.1) ||
                                          (skylit && sky[:area_m2] <= 400.0) ||
                                          (skylit && sky_ea <= 0.006)
        end
        audit.warn(:daylighting,
                   'LEGACY NECB 2011 THRESHOLD EVALUATION IN USE (placement: :necb2011): the applicable ' \
                   'area/aperture criteria are ANDed, so any single failed criterion excepts a space. This is ' \
                   'not the 2020/2025 requirement — 4.2.2.1.(10) and (13) are INDEPENDENT input-POWER tests. ' \
                   'The path exists only to keep the legacy parity gate callable (L-26, D-57)',
                   inputs: { daylighted: daylight_spaces.size, excepted: excepted.size, offices_exempt: offices.size,
                             with_windows: with_windows.uniq.size, with_skylights: with_skylights.uniq.size,
                             office_match: office_match },
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

      # ---- internals (not API) ----
      # (dist / triangle_height / wall_point_distance are declared private in
      # necb/daylighted_areas_legacy_2011.rb, where they are now defined.)
      private_class_method :resolve_placement,
                           :zone_fraction, :necb2020_spaces, :necb_default_spaces,
                           :lowest_floor_area, :daylighted?, :illuminance_setpoint,
                           :lowest_floor_bounds
    end

    def self.add_daylighting_controls(model, **kwargs)
      Daylighting.add_controls(model, **kwargs)
    end
  end

  # Facade: add NECB daylighting controls (placement: :all by default — every
  # daylighted space; pass placement: :necb2020 for the code rule).
  def self.add_daylighting_controls(model, **kwargs)
    NECB.add_daylighting_controls(model, **kwargs)
  end
end
