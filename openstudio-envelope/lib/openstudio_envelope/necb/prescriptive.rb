module OpenStudioEnvelope
  module NECB
    # Prescriptive Section 3.2 application: set every exterior/ground surface and
    # subsurface to its Table 3.2.2.x/3.2.3.1 maximum U at the building's HDD, and
    # optionally rebuild fenestration to the 3.2.1.4 FDWR/SRR limits.
    #
    # Application is by HARD ASSIGNMENT of deep-copied constructions (one copy per
    # unique construction x target, legacy naming/reuse conventions preserved) —
    # default construction sets are left untouched; parity with the legacy
    # default-set path is by resulting per-surface conductance.
    #
    # include_films: true (default) treats the table value as OVERALL thermal
    # transmittance and solves the construction to 1/(1/U - R_films) — the
    # 1.4.1.2 definition says U "reflects ... air films on both faces of
    # above-ground components", and the legacy OSut construction path
    # (TBD.genConstruction, NECB2020 prototypes) does the same. false applies
    # the table value as construction-only conductance (the OLD legacy BTAP
    # apply_standard_construction_properties convention, ~4% more stringent
    # on walls — kept for mechanism-parity tests). The choice is always audited.
    #
    # Scope follows the 1.4.1.2 "building envelope" definition: surfaces of
    # unconditioned spaces (attics, crawlspaces) are NOT envelope and keep
    # their constructions; assemblies separating conditioned space from
    # enclosed unconditioned space ARE envelope — they get the Table 3.2.2.2
    # row for their inclination (3.1.1.7.(6)) with the unconditioned
    # enclosure credited at U 6.25 per 3.1.1.7.(4).
    module Prescriptive
      module_function

      SUBSURFACE_CLASS = {
        'FixedWindow' => 'window', 'OperableWindow' => 'window', 'GlassDoor' => 'window',
        'Skylight' => 'skylight', 'TubularDaylightDome' => 'skylight', 'TubularDaylightDiffuser' => 'skylight',
        'Door' => 'door', 'OverheadDoor' => 'door'
      }.freeze

      SURFACE_CLASS = { 'Wall' => 'wall', 'RoofCeiling' => 'roofceiling', 'Floor' => 'floor' }.freeze

      # 3.1.1.7.(4): an enclosed unconditioned space protecting an envelope
      # component may be considered to have an overall U of 6.25 W/(m2.K).
      ENCLOSURE_R = 1.0 / 6.25

      def apply(model, vintage:, hdd: nil, apply_fdwr: false, apply_srr: false,
                include_films: true, thermal_bridging: nil, audit: nil)
        audit ||= AuditLog.new
        hdd = Climate.hdd18(model, hdd: hdd, audit: audit)
        raise(ArgumentError, 'HDD unresolvable: pass hdd: explicitly or set a weather file') if hdd.nil?

        audit.info(:prescriptive, 'film convention',
                   value: include_films ? 'code-literal: table U treated as overall transmittance incl. air films (1.4.1.2 definition; films subtracted from construction)' \
                                        : 'legacy-BTAP-compatible: table U applied as construction-only conductance',
                   article: '1.4.1.2.', ruling: 'D-23')

        cache = {}
        window_construction = nil
        skylight_construction = nil

        outside_envelope = 0
        model.getSurfaces.sort_by(&:nameString).each do |surface|
          surface_class = SURFACE_CLASS[surface.surfaceType]
          next if surface_class.nil?

          # 1.4.1.2: surfaces of unconditioned spaces are not building envelope.
          space = surface.space
          if space.is_initialized && !inside_envelope?(space.get)
            outside_envelope += 1 unless boundary_of(surface).nil?
            next
          end

          boundary = boundary_of(surface)
          if boundary.nil?
            assign_interzone_envelope(model, surface, surface_class, vintage, hdd, include_films, cache, audit)
            next
          end

          if boundary == 'ground' && surface_class == 'floor'
            assign_ground_floor(model, surface, vintage, hdd, include_films, cache, audit)
          else
            assign_surface(model, surface, surface_class, boundary, vintage, hdd, include_films, cache, audit)
          end
          surface.subSurfaces.sort_by(&:nameString).each do |sub|
            sub_class = SUBSURFACE_CLASS[sub.subSurfaceType]
            if sub_class.nil?
              audit.warn(:prescriptive, "subsurface type '#{sub.subSurfaceType}' not classified — construction left as-is",
                         target: sub.nameString)
              next
            end
            next if boundary == 'ground' # NECB: no ground windows/doors

            construction = assign_subsurface(model, sub, sub_class, vintage, hdd, include_films, cache, audit)
            window_construction ||= construction if sub_class == 'window'
            skylight_construction ||= construction if sub_class == 'skylight'
          end
        end

        if outside_envelope.positive?
          audit.info(:prescriptive,
                     'exterior/ground surfaces of unconditioned spaces left untouched — not part of the building envelope',
                     inputs: { surfaces: outside_envelope }, article: '1.4.1.2.', ruling: 'D-24')
        end

        if apply_fdwr
          limit = NECB.max_fdwr(vintage: vintage, hdd: hdd, audit: audit)
          window_construction ||= subsurface_target_construction(model, 'window', vintage, hdd, include_films, cache, audit)
          Geometry.apply_fdwr(model, limit, window_construction, audit: audit)
        end
        if apply_srr
          limit = NECB.max_srr(vintage: vintage, audit: audit)
          skylight_construction ||= subsurface_target_construction(model, 'skylight', vintage, hdd, include_films, cache, audit)
          Geometry.apply_srr(model, limit, skylight_construction, audit: audit)
        end

        # 3.1.1.7: table values are EFFECTIVE transmittance — uprate for thermal
        # bridging when requested (psi set name/Hash, or true for the default set).
        if thermal_bridging
          psi = thermal_bridging == true ? 'regular (BETBG)' : thermal_bridging
          ThermalBridging.apply(model, vintage: vintage, hdd: hdd, psi_set: psi, audit: audit)
        else
          audit.warn(:thermal_bridging,
                     'thermal bridging not requested — applied U-values are clear-field; ' \
                     'NECB 3.1.1.7 requires EFFECTIVE transmittance (pass thermal_bridging:)',
                     article: '3.1.1.7.')
        end

        audit
      end

      def boundary_of(surface)
        case surface.outsideBoundaryCondition
        when 'Outdoors' then 'outdoors'
        when 'Ground', 'Foundation', 'GroundFCfactorMethod', 'GroundSlabPreprocessorAverage' then 'ground'
        end
      end

      # Inside the building envelope = conditioned or indirectly conditioned.
      # partofTotalFloorArea is the primary signal (same predicate as the
      # 8.4.3.3 air-leakage transform); spaces tagged with the legacy
      # space_conditioning_category property count as inside unless tagged
      # 'unconditioned' (legacy tags plenums 'nonresconditioned' — indirectly
      # conditioned, thermal block (c) of the 1.4.1.2 definition).
      def inside_envelope?(space)
        return true if space.partofTotalFloorArea

        tag = space.additionalProperties.getFeatureAsString('space_conditioning_category')
        tag.is_initialized && tag.get.casecmp('unconditioned') != 0
      end

      # Assemblies separating conditioned space from ENCLOSED UNCONDITIONED
      # space (attic ceilings, walls to unheated storage, floors over
      # crawlspaces) are building envelope per 1.4.1.2 and must meet the
      # Table 3.2.2.2 row for their inclination (3.1.1.7.(6) — surfaceType
      # already encodes it). The unconditioned enclosure is credited at
      # U 6.25 per 3.1.1.7.(4); both faces see interior air films. The
      # paired surface gets the same construction so the pair stays
      # consistent. (Legacy OSut instead applies the exposed-FLOOR row to
      # attic ceilings — floor 0.175 vs roof 0.156 at HDD 3890 — a more
      # lenient reading with no inclination-rule basis; divergence logged.)
      def assign_interzone_envelope(model, surface, surface_class, vintage, hdd, include_films, cache, audit)
        return unless surface.outsideBoundaryCondition == 'Surface'

        adj = surface.adjacentSurface
        return if adj.empty?

        adj_space = adj.get.space
        return if adj_space.empty? || inside_envelope?(adj_space.get)

        construction = surface.construction
        if construction.empty? || construction.get.to_Construction.empty?
          audit.warn(:prescriptive, 'envelope surface to unconditioned space has no layered construction — skipped',
                     target: surface.nameString, ruling: 'D-24')
          return
        end

        u = NECB.max_u(vintage: vintage, surface: surface_class, boundary: 'outdoors', hdd: hdd)
        r = (1.0 / u) - ENCLOSURE_R
        r -= Constructions.film_r_interzone(surface_class) if include_films
        target = 1.0 / r
        key = [construction.get.handle.to_s, surface_class, 'interzone', target]
        cache[key] ||= begin
          c = Constructions.opaque_at_conductance(model, construction.get.to_Construction.get, target)
          audit.decision(:prescriptive,
                         "envelope #{surface_class} to enclosed unconditioned space set to maximum U " \
                         '(row by inclination; enclosure credited at U 6.25)',
                         target: c.nameString,
                         inputs: { hdd: hdd, table_u: u.round(4), target_u_construction: target.round(4) },
                         value: "conductance #{c.thermalConductance.to_f.round(4)} W/m2K",
                         article: 'Table 3.2.2.2.; 3.1.1.7.(4)', ruling: 'D-24')
          c
        end
        surface.setConstruction(cache[key])
        adj.get.setConstruction(cache[key])
      end

      def target_conductance(vintage, surface_class, boundary, hdd, include_films, audit)
        u = NECB.max_u(vintage: vintage, surface: surface_class, boundary: boundary, hdd: hdd)
        return u unless include_films

        r_films = Constructions.film_r(surface_class, boundary)
        1.0 / ((1.0 / u) - r_films)
      end

      def assign_surface(model, surface, surface_class, boundary, vintage, hdd, include_films, cache, audit)
        construction = surface.construction
        if construction.empty? || construction.get.to_Construction.empty?
          audit.warn(:prescriptive, 'surface has no layered construction — skipped', target: surface.nameString)
          return
        end

        target = target_conductance(vintage, surface_class, boundary, hdd, include_films, audit)
        key = [construction.get.handle.to_s, surface_class, boundary, target]
        cache[key] ||= begin
          c = Constructions.opaque_at_conductance(model, construction.get.to_Construction.get, target)
          audit.decision(:prescriptive, "#{boundary} #{surface_class} construction set to maximum U",
                         target: c.nameString,
                         inputs: { hdd: hdd, target_u_construction: target.round(4) },
                         value: "conductance #{c.thermalConductance.to_f.round(4)} W/m2K",
                         article: boundary == 'ground' ? 'Table 3.2.3.1.' : 'Table 3.2.2.2.')
          c
        end
        surface.setConstruction(cache[key])
      end

      # Table 3.2.3.1 floors row is zone-conditional: zone 8 prescribes the
      # table U over the FULL slab area; zones 4-7B prescribe it only within a
      # 1.2 m perimeter strip (3.2.3.3.(3)) and leave the slab field without a
      # maximum. Full-area zones retarget the construction like any other
      # surface; strip zones keep the modeled slab and represent the strip
      # with the Kiva foundation's interior horizontal insulation. (Legacy
      # OSut archetypes model the bare slab and OMIT the strip; the old BTAP
      # path applied the strip U over the full area — both simplifications
      # diverge from the printed table, see D-32.)
      def assign_ground_floor(model, surface, vintage, hdd, include_films, cache, audit)
        extent = NECB.ground_floor_extent(vintage: vintage, hdd: hdd)
        if extent[:extent] == :full_area
          assign_surface(model, surface, 'floor', 'ground', vintage, hdd, include_films, cache, audit)
          return
        end

        apply_ground_strip(model, surface, vintage, hdd, include_films, extent[:width_m], cache, audit)
      end

      def apply_ground_strip(model, surface, vintage, hdd, include_films, width_m, cache, audit)
        kiva = surface.adjacentFoundation
        if kiva.empty?
          audit.warn(:prescriptive,
                     'ground floor without a Kiva foundation in a perimeter-strip zone — the 1.2 m strip (3.2.3.3.(3)) is not representable; slab left as modeled',
                     target: surface.nameString, article: 'Table 3.2.3.1.; 3.2.3.3.(3)', ruling: 'D-32')
          return
        end

        u = NECB.max_u(vintage: vintage, surface: 'floor', boundary: 'ground', hdd: hdd)
        target = include_films ? 1.0 / ((1.0 / u) - Constructions.film_r('floor', 'ground')) : u
        slab_r = 0.0
        construction = surface.construction
        if construction.is_initialized && construction.get.to_Construction.is_initialized
          conductance = construction.get.to_Construction.get.thermalConductance
          slab_r = 1.0 / conductance.get if conductance.is_initialized && conductance.get.positive?
        end
        r_add = (1.0 / target) - slab_r

        key = ['kiva-strip', kiva.get.handle.to_s]
        cache[key] ||= begin
          if r_add.positive?
            k = kiva.get
            # XPS-like board sized so the strip assembly meets the table U
            mat = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumSmooth', 0.029 * r_add, 0.029, 29.0, 1210.0)
            mat.setName("NECB 3.2.3.3 strip insulation R-#{r_add.round(3)}")
            k.setInteriorHorizontalInsulationMaterial(mat)
            k.setInteriorHorizontalInsulationDepth(0.0)
            k.setInteriorHorizontalInsulationWidth(width_m)
            audit.decision(:prescriptive,
                           'ground floor: slab field left as modeled (no full-area maximum below zone 8); perimeter strip insulated via Kiva interior horizontal insulation',
                           target: k.nameString,
                           inputs: { hdd: hdd, table_u: u.round(4), strip_target_u_construction: target.round(4),
                                     slab_r: slab_r.round(4), strip_insulation_r: r_add.round(4), width_m: width_m },
                           value: "insulation R #{r_add.round(3)} m2K/W x #{width_m} m from perimeter",
                           article: 'Table 3.2.3.1.; 3.2.3.3.(3)', ruling: 'D-32')
          else
            audit.info(:prescriptive, 'slab construction already meets the perimeter-strip U — no strip insulation added',
                       target: surface.nameString,
                       inputs: { hdd: hdd, strip_target_u_construction: target.round(4), slab_r: slab_r.round(4) },
                       article: 'Table 3.2.3.1.; 3.2.3.3.(3)', ruling: 'D-32')
          end
          true
        end
      end

      def assign_subsurface(model, sub, sub_class, vintage, hdd, include_films, cache, audit)
        construction = sub.construction
        if construction.empty? || construction.get.to_Construction.empty?
          audit.warn(:prescriptive, 'subsurface has no layered construction — skipped', target: sub.nameString)
          return nil
        end

        base = construction.get.to_Construction.get
        # SimpleGlazing's uFactor IS the overall (with-films) value — films are
        # E+'s job there; only opaque doors get the construction-only solve.
        opaque_door = sub_class == 'door' && base.isOpaque
        target = target_conductance(vintage, sub_class, 'outdoors', hdd, include_films && opaque_door, audit)
        key = [base.handle.to_s, sub_class, target]
        cache[key] ||= begin
          c = if opaque_door
                Constructions.opaque_at_conductance(model, base, target)
              else
                Constructions.fenestration_at_conductance(model, base, target)
              end
          audit.decision(:prescriptive, "#{sub_class} construction set to maximum U",
                         target: c.nameString,
                         inputs: { hdd: hdd, target_u: target.round(4) },
                         value: opaque_door ? "conductance #{c.thermalConductance.to_f.round(4)}" : "SimpleGlazing U #{target.round(4)} (SHGC/VT preserved)",
                         article: 'Table 3.2.2.3.')
          c
        end
        sub.setConstruction(cache[key])
        cache[key]
      end

      # A window/skylight construction at the prescriptive U when the model has no
      # existing subsurface of that class to derive one from (needed by the FDWR/SRR
      # rebuild on windowless models).
      def subsurface_target_construction(model, sub_class, vintage, hdd, _include_films, cache, audit)
        # always SimpleGlazing here — its uFactor is the with-films value
        target = target_conductance(vintage, sub_class, 'outdoors', hdd, false, audit)
        stub = OpenStudio::Model::Construction.new(model)
        stub.setName("NECB #{sub_class} base")
        glazing = OpenStudio::Model::SimpleGlazing.new(model)
        glazing.setUFactor(target)
        glazing.setSolarHeatGainCoefficient(0.60)
        stub.setLayers([glazing])
        c = Constructions.fenestration_at_conductance(model, stub, target)
        stub.remove
        audit.decision(:prescriptive, "#{sub_class} construction created at maximum U (no existing #{sub_class})",
                       target: c.nameString, inputs: { target_u: target.round(4) }, article: 'Table 3.2.2.3.')
        c
      end

      # ---- internals (not API) ----
      private_class_method :assign_interzone_envelope, :target_conductance,
                           :assign_surface, :assign_ground_floor, :apply_ground_strip,
                           :assign_subsurface, :subsurface_target_construction
    end

    # Facade
    def self.apply_prescriptive(model, vintage:, hdd: nil, apply_fdwr: false,
                                apply_srr: false, include_films: true,
                                thermal_bridging: nil, audit: nil)
      Prescriptive.apply(model, vintage: vintage, hdd: hdd, apply_fdwr: apply_fdwr,
                         apply_srr: apply_srr, include_films: include_films,
                         thermal_bridging: thermal_bridging, audit: audit)
    end
  end
end
