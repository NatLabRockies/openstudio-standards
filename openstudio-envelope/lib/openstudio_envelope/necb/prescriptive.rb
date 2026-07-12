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
    # include_films: false (default) matches legacy BTAP (construction-only
    # conductance); true treats the table value as overall transmittance and solves
    # the construction to 1/(1/U - R_films). The choice is always audited.
    module Prescriptive
      module_function

      SUBSURFACE_CLASS = {
        'FixedWindow' => 'window', 'OperableWindow' => 'window', 'GlassDoor' => 'window',
        'Skylight' => 'skylight', 'TubularDaylightDome' => 'skylight', 'TubularDaylightDiffuser' => 'skylight',
        'Door' => 'door', 'OverheadDoor' => 'door'
      }.freeze

      SURFACE_CLASS = { 'Wall' => 'wall', 'RoofCeiling' => 'roofceiling', 'Floor' => 'floor' }.freeze

      def apply(model, vintage:, hdd: nil, apply_fdwr: false, apply_srr: false,
                include_films: false, thermal_bridging: nil, audit: nil)
        audit ||= AuditLog.new
        hdd = Climate.hdd18(model, hdd: hdd, audit: audit)
        raise(ArgumentError, 'HDD unresolvable: pass hdd: explicitly or set a weather file') if hdd.nil?

        audit.info(:prescriptive, 'film convention',
                   value: include_films ? 'code-literal: table U treated as overall transmittance (films subtracted)' \
                                        : 'legacy-compatible: table U applied as construction-only conductance',
                   article: '3.1.1.7 note')

        cache = {}
        window_construction = nil
        skylight_construction = nil

        model.getSurfaces.sort_by(&:nameString).each do |surface|
          boundary = boundary_of(surface)
          surface_class = SURFACE_CLASS[surface.surfaceType]
          next if boundary.nil? || surface_class.nil?

          assign_surface(model, surface, surface_class, boundary, vintage, hdd, include_films, cache, audit)
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

      def assign_subsurface(model, sub, sub_class, vintage, hdd, include_films, cache, audit)
        construction = sub.construction
        if construction.empty? || construction.get.to_Construction.empty?
          audit.warn(:prescriptive, 'subsurface has no layered construction — skipped', target: sub.nameString)
          return nil
        end

        base = construction.get.to_Construction.get
        target = target_conductance(vintage, sub_class, 'outdoors', hdd, include_films, audit)
        key = [base.handle.to_s, sub_class, target]
        cache[key] ||= begin
          c = if sub_class == 'door' && base.isOpaque
                Constructions.opaque_at_conductance(model, base, target)
              else
                Constructions.fenestration_at_conductance(model, base, target)
              end
          audit.decision(:prescriptive, "#{sub_class} construction set to maximum U",
                         target: c.nameString,
                         inputs: { hdd: hdd, target_u: target.round(4) },
                         value: sub_class == 'door' && base.isOpaque ? "conductance #{c.thermalConductance.to_f.round(4)}" : "SimpleGlazing U #{target.round(4)} (SHGC/VT preserved)",
                         article: 'Table 3.2.2.3.')
          c
        end
        sub.setConstruction(cache[key])
        cache[key]
      end

      # A window/skylight construction at the prescriptive U when the model has no
      # existing subsurface of that class to derive one from (needed by the FDWR/SRR
      # rebuild on windowless models).
      def subsurface_target_construction(model, sub_class, vintage, hdd, include_films, cache, audit)
        target = target_conductance(vintage, sub_class, 'outdoors', hdd, include_films, audit)
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
    end

    # Facade
    def self.apply_prescriptive(model, vintage:, hdd: nil, apply_fdwr: false,
                                apply_srr: false, include_films: false,
                                thermal_bridging: nil, audit: nil)
      Prescriptive.apply(model, vintage: vintage, hdd: hdd, apply_fdwr: apply_fdwr,
                         apply_srr: apply_srr, include_films: include_films,
                         thermal_bridging: thermal_bridging, audit: audit)
    end
  end
end
