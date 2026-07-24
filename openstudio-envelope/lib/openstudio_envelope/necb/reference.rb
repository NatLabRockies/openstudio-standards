module OpenStudioEnvelope
  module NECB
    # The performance-path reference ENVELOPE (2020: 8.4.4.1.(2)/8.4.4.3./8.4.4.4.;
    # 2025: 8.4.5.x, verbatim text) — greenfield: no legacy implementation exists.
    # Operates IN PLACE on a model the caller clones, so a compliance umbrella can
    # chain openstudio-hvac's reference_hvac and this transform on ONE clone with
    # ONE audit (the AuditLog schemas are identical).
    #
    # Order of operations:
    #  1. prescriptive U-values (8.4.4.1.(2): the reference envelope meets 3.2)
    #  2. FDWR/SRR overage -> PROPORTIONAL per-orientation scaling of existing
    #     fenestration (8.4.4.3.(3) — never a window rebuild)
    #  3. roof solar absorptance 0.7 iff the proposed model used actual values
    #     (8.4.4.3.(1)/(2))
    #  4. remove Space/Building shading + shading controls, keep Site shading
    #     (8.4.4.3.(4)/(5))
    #  5. fenestration optics preserved by construction (8.4.4.3.(8))
    #  6. lightweight construction rebuild at the prescriptive targets (8.4.4.4.(1))
    #  7. air leakage default: I_AGW = (5/75)^0.6 x 1.50 x S/A_AGW applied per space
    #     (8.4.4.3.(6) + 8.4.3.3.(3) + 8.4.2.9.(2))
    #  8. article-coverage emission (every article, statuses + citations, warnings
    #     for anything partial)
    module Reference
      module_function

      AIR_LEAKAGE_I75 = 1.50   # L/(s.m2) @ 75 Pa, 8.4.3.3.(3)
      AIR_LEAKAGE_N = 0.60     # flow exponent, 8.4.2.9.(2)

      def apply(model, vintage:, hdd: nil, actual_roof_absorptance_used: false,
                thermal_bridging: nil, audit: nil)
        audit ||= AuditLog.new
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
        hdd = Climate.hdd18(model, hdd: hdd, audit: audit)
        raise(ArgumentError, 'HDD unresolvable: pass hdd: explicitly or set a weather file') if hdd.nil?

        # 1. prescriptive Section 3.2 on the reference (no window rebuild here)
        Prescriptive.apply(model, vintage: vintage, hdd: hdd,
                           thermal_bridging: thermal_bridging, audit: audit)
        audit.decision(:reference, 'reference envelope meets prescriptive Section 3.2',
                       inputs: { hdd: hdd }, article: "#{prefix}.1.(2)")

        scale_fenestration_to_limits(model, vintage, hdd, prefix, audit)
        roof_absorptance = NECB.rules(vintage).fetch('reference_envelope').fetch('roof_absorptance_if_actual_used')
        apply_roof_absorptance(model, actual_roof_absorptance_used, roof_absorptance, prefix, audit)
        strip_shading(model, prefix, audit)
        audit.info(:reference, 'fenestration optics (SHGC/VT) preserved — only U changed by construction of the prescriptive transform',
                   article: "#{prefix}.3.(8)")
        apply_lightweight_construction(model, vintage, hdd, prefix, audit)
        apply_air_leakage_default(model, prefix, audit)
        emit_article_coverage(vintage, audit)
        audit
      end

      # 8.4.4.3.(3): where the proposed FDWR/SRR exceeds the 3.2.1.4 limits, scale the
      # EXISTING fenestration proportionally (per orientation — a uniform ratio on
      # every wall preserves each orientation's share).
      def scale_fenestration_to_limits(model, vintage, hdd, prefix, audit)
        walls = Geometry.exposed_walls(model)
        limit = NECB.max_fdwr(vintage: vintage, hdd: hdd)
        if walls[:fdwr] && walls[:fdwr] > limit
          ratio = limit / walls[:fdwr]
          walls[:walls].each { |w| Geometry.scale_subsurfaces(w, ratio) }
          audit.decision(:reference, 'proposed FDWR exceeds the limit — fenestration scaled proportionally per orientation',
                         inputs: { proposed_fdwr: walls[:fdwr].round(4), limit: limit.round(4) },
                         value: "area ratio #{ratio.round(4)} applied to every subsurface (resulting FDWR #{Geometry.exposed_walls(model)[:fdwr]&.round(4)})",
                         article: "#{prefix}.3.(3)")
        else
          audit.info(:reference, 'proposed FDWR within the limit — fenestration areas identical to proposed',
                     inputs: { proposed_fdwr: walls[:fdwr]&.round(4), limit: limit.round(4) },
                     article: "#{prefix}.3.(3)")
        end

        roofs = Geometry.exposed_roofs(model)
        srr_limit = NECB.max_srr(vintage: vintage)
        return unless roofs[:srr] && roofs[:srr] > srr_limit

        ratio = srr_limit / roofs[:srr]
        roofs[:roofs].each { |r| Geometry.scale_subsurfaces(r, ratio) }
        audit.decision(:reference, 'proposed skylight area exceeds the limit — skylights scaled proportionally',
                       inputs: { proposed_srr: roofs[:srr].round(4), limit: srr_limit },
                       value: "area ratio #{ratio.round(4)}", article: "#{prefix}.3.(3)")
      end

      # 8.4.4.3.(1)/(2): roof solar absorptance 0.7 ONLY when the proposed model used
      # actual absorptance values; otherwise identical to proposed.
      def apply_roof_absorptance(model, actual_used, roof_absorptance, prefix, audit)
        unless actual_used
          audit.info(:reference, 'proposed roof absorptance not flagged as actual — reference keeps the proposed value',
                     article: "#{prefix}.3.(2)(a)")
          return
        end

        changed = 0
        model.getSurfaces.sort_by(&:nameString).each do |surface|
          next unless surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'
          next if surface.construction.empty? || surface.construction.get.to_Construction.empty?

          outer = surface.construction.get.to_Construction.get.layers.first.to_OpaqueMaterial
          next if outer.empty?

          outer.get.setSolarAbsorptance(OpenStudio::OptionalDouble.new(roof_absorptance))
          changed += 1
        end
        audit.decision(:reference, "roof solar absorptance set to #{roof_absorptance} (proposed used actual values)",
                       inputs: { roofs_changed: changed }, value: roof_absorptance, article: "#{prefix}.3.(2)(b)")
      end

      # 8.4.4.3.(4): remove permanent fenestration shading projections (Space/Building
      # shading groups + shading controls); (5): keep exterior shading from nearby
      # structures (Site groups).
      def strip_shading(model, prefix, audit)
        removed = []
        kept = []
        model.getShadingSurfaceGroups.sort_by(&:nameString).each do |group|
          if group.shadingSurfaceType == 'Site'
            kept << group.nameString
          else
            removed << "#{group.nameString} (#{group.shadingSurfaceType})"
            group.remove
          end
        end
        controls = model.getShadingControls.size
        model.getShadingControls.each(&:remove)
        audit.decision(:reference, 'permanent shading projections removed; nearby-structure shading kept',
                       inputs: { removed_groups: removed.size, shading_controls_removed: controls,
                                 site_groups_kept: kept.size },
                       value: removed.empty? ? 'no Space/Building shading present' : removed.join('; '),
                       article: "#{prefix}.3.(4)-(5)")
      end

      # 8.4.4.4.(1): reference envelope thermal characteristics = lightweight
      # construction. Implemented by rebuilding each exterior/ground opaque assembly
      # as a single MASSLESS layer at the identical (already-prescriptive) resistance
      # — zero thermal mass with unchanged Ut. NOTE: the canonical layer set of Note
      # A-8.4.4.4.(1) is not machine-retrievable; the massless interpretation is
      # documented in the coverage manifest.
      def apply_lightweight_construction(model, vintage, hdd, prefix, audit)
        cache = {}
        rebuilt = 0
        model.getSurfaces.sort_by(&:nameString).each do |surface|
          boundary = Prescriptive.boundary_of(surface)
          surface_class = Prescriptive::SURFACE_CLASS[surface.surfaceType]
          next if boundary.nil? || surface_class.nil?
          next if surface.construction.empty? || surface.construction.get.to_Construction.empty?

          original = surface.construction.get.to_Construction.get
          conductance = original.thermalConductance.to_f
          next if conductance <= 0

          # The massless rebuild must CARRY OVER the outer layer's absorptances:
          # a fresh MasslessOpaqueMaterial defaults to solar 0.7 / thermal 0.9 /
          # visible 0.7, which silently overwrote the proposed values on EVERY
          # opaque surface — violating the 8.4.4.3.(2)(a) keep-the-proposed
          # promise, and making the (2)(b) set-to-0.7 branch "work" only by
          # coincidence (this transform runs AFTER apply_roof_absorptance, so
          # whatever that set is preserved here too). The absorptance triple is
          # part of the cache key: equal-conductance surfaces with different
          # finishes must not share a rebuilt construction.
          outer = original.layers.first.to_OpaqueMaterial
          solar = outer.empty? ? 0.7 : outer.get.solarAbsorptance
          thermal = outer.empty? ? 0.9 : outer.get.thermalAbsorptance
          visible = outer.empty? ? 0.7 : outer.get.visibleAbsorptance

          # EnergyPlus's Kiva engine REQUIRES regular (thickness+conductivity)
          # materials on Foundation-boundary surfaces — a massless layer there
          # is a hard E+ fatal ("must use only regular material objects...
          # Kiva: Errors discovered, program terminates"). Found by the
          # legacy-archetype cross-validation (real slab-on-grade Kiva
          # geometry no hand-built fixture exercises). Those surfaces get a
          # LOW-MASS StandardOpaqueMaterial at the identical resistance
          # (insulation-board-like: 45 kg/m3, cp 1000) — lightweight in the
          # 8.4.4.4.(1) sense AND Kiva-legal. Everything else stays massless.
          kiva = surface.outsideBoundaryCondition == 'Foundation'
          key = [surface_class, boundary, kiva, conductance.round(5),
                 solar.round(4), thermal.round(4), visible.round(4)]
          cache[key] ||= begin
            material = if kiva
                         m = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumSmooth',
                                                                           0.05, 0.05 * conductance, 45.0, 1000.0)
                         m.setName("NECB Ref Lightweight(Kiva) #{surface_class} R-#{(1.0 / conductance).round(3)}")
                         m.setSolarAbsorptance(OpenStudio::OptionalDouble.new(solar))
                         m.setThermalAbsorptance(OpenStudio::OptionalDouble.new(thermal))
                         m.setVisibleAbsorptance(OpenStudio::OptionalDouble.new(visible))
                         m
                       else
                         m = OpenStudio::Model::MasslessOpaqueMaterial.new(model, 'MediumSmooth', 1.0 / conductance)
                         m.setName("NECB Ref Lightweight #{surface_class} R-#{(1.0 / conductance).round(3)} a#{solar.round(2)}")
                         # NOTE: MasslessOpaqueMaterial setters take PLAIN
                         # doubles; StandardOpaqueMaterial's need
                         # OptionalDouble (the CLAUDE.md trap cuts both ways).
                         m.setThermalAbsorptance(thermal)
                         m.setSolarAbsorptance(solar)
                         m.setVisibleAbsorptance(visible)
                         m
                       end
            c = OpenStudio::Model::Construction.new(model)
            c.setName("NECB Ref Lightweight#{kiva ? '(Kiva)' : ''} #{boundary} #{surface_class}:U-#{conductance.round(4)} a#{solar.round(2)}")
            c.setLayers([material])
            c.setInsulation(material)
            c
          end
          surface.setConstruction(cache[key])
          rebuilt += 1
        end
        audit.decision(:reference, 'opaque assemblies rebuilt as lightweight (massless) at unchanged Ut',
                       inputs: { surfaces: rebuilt, unique_assemblies: cache.size },
                       article: "#{prefix}.4.(1) (Note A interpretation: zero-mass layer at identical resistance)")
      end

      # 8.4.4.3.(6) via 8.4.3.3.(3) + 8.4.2.9.(2):
      # I_AGW = (5/75)^0.6 x I75 x S / A_AGW, applied per space as flow per exterior
      # above-ground wall area.
      def apply_air_leakage_default(model, prefix, audit)
        # S per 3.2.4.2.(1)(c) (D-21): the enclosure of the CONDITIONED volume —
        # Outdoors and ground-contact surfaces of conditioned spaces PLUS
        # interzone surfaces separating conditioned from unconditioned spaces
        # (attic ceilings, plenum boundaries). Surfaces of unconditioned spaces
        # themselves (attic roofs/gables) bound no conditioned space and are
        # NOT envelope. Ground contact stays IN S: it is enclosure area used to
        # NORMALIZE the tested/assumed rate, not a claim of slab leakage — the
        # S/A_AGW term moves the whole total onto above-ground walls.
        # Unconditioned = not part of total floor area (the OS attic/plenum
        # marker). Space multipliers honoured.
        envelope_area = 0.0
        wall_area = 0.0
        model.getSpaces.each do |space|
          mult = space.multiplier.to_f
          conditioned = space.partofTotalFloorArea
          space.surfaces.each do |surface|
            case surface.outsideBoundaryCondition
            when 'Outdoors'
              next unless conditioned

              envelope_area += surface.grossArea * mult
              wall_area += surface.grossArea * mult if surface.surfaceType == 'Wall'
            when /Ground|Foundation/i
              envelope_area += surface.grossArea * mult if conditioned
            when 'Surface'
              next unless conditioned

              adj = surface.adjacentSurface
              next if adj.empty? || adj.get.space.empty?

              envelope_area += surface.grossArea * mult unless adj.get.space.get.partofTotalFloorArea
            end
          end
        end
        if wall_area < 0.1
          audit.warn(:reference, 'no above-ground walls — air-leakage default not applied', article: "#{prefix}.3.(6)")
          return
        end

        c = (5.0 / 75.0)**AIR_LEAKAGE_N
        i_agw = c * AIR_LEAKAGE_I75 * envelope_area / wall_area # L/(s.m2 of AG wall)

        # Clear EVERY infiltration representation before adding the default.
        # OpenStudio models infiltration with three unrelated object types, and
        # they are additive: clearing only DesignFlowRate leaves a proposed
        # model that used EffectiveLeakageArea or FlowCoefficient with its
        # original leakage PLUS the NECB default on top — roughly double
        # infiltration on the reference, which inflates reference energy and
        # makes the proposed easier to pass.
        cleared = { design_flow_rate: model.getSpaceInfiltrationDesignFlowRates.size,
                    effective_leakage_area: model.getSpaceInfiltrationEffectiveLeakageAreas.size,
                    flow_coefficient: model.getSpaceInfiltrationFlowCoefficients.size }
        # D-19: the reference must model the SAME default the proposed carries
        # (8.4.4.3.(6) -> 8.4.3.3.(3)) — including its TEMPORAL modulation. The
        # E+ modifier coefficients (constant/temperature/wind terms) change
        # delivered infiltration by ~2x between the constant convention (A=1)
        # and the DOE-2 wind-driven convention (A=0, C=0.224) even at identical
        # design totals, and an asymmetric pair breaks the comparison. Inherit
        # the proposed's dominant coefficient set + schedule; fall back to
        # constant (A=1) when the proposed has no DesignFlowRate infiltration.
        # Proposed installed total (DesignFlowRate representations only — the
        # other object types cannot be totalled without weather) for the
        # 8.4.3.3.(3) default-conformance check below.
        proposed_total_l_s = nil
        if model.getSpaceInfiltrationEffectiveLeakageAreas.empty? && model.getSpaceInfiltrationFlowCoefficients.empty?
          proposed_total_l_s = model.getSpaceInfiltrationDesignFlowRates.sum do |i|
            next 0.0 if i.space.empty?

            sp = i.space.get
            mult = sp.multiplier
            if i.flowperExteriorSurfaceArea.is_initialized then i.flowperExteriorSurfaceArea.get * sp.exteriorArea * mult * 1000.0
            elsif i.flowperExteriorWallArea.is_initialized then i.flowperExteriorWallArea.get * sp.exteriorWallArea * mult * 1000.0
            elsif i.designFlowRate.is_initialized then i.designFlowRate.get * mult * 1000.0
            elsif i.flowperSpaceFloorArea.is_initialized then i.flowperSpaceFloorArea.get * sp.floorArea * mult * 1000.0
            else 0.0
            end
          end
        end
        donor = model.getSpaceInfiltrationDesignFlowRates.min_by(&:nameString)
        coeffs = if donor
                   { a: donor.constantTermCoefficient, b: donor.temperatureTermCoefficient,
                     c: donor.velocityTermCoefficient, d: donor.velocitySquaredTermCoefficient,
                     schedule: (donor.schedule.get if donor.schedule.is_initialized) }
                 else
                   { a: 1.0, b: 0.0, c: 0.0, d: 0.0, schedule: nil }
                 end
        model.getSpaceInfiltrationDesignFlowRates.each(&:remove)
        model.getSpaceInfiltrationEffectiveLeakageAreas.each(&:remove)
        model.getSpaceInfiltrationFlowCoefficients.each(&:remove)
        model.getSpaces.sort_by(&:nameString).each do |space|
          # unconditioned spaces (attics/plenums) receive NO infiltration
          # object: their exterior walls are outside A_AGW, and giving them
          # flow-per-wall-area would silently re-inflate the installed total
          # beyond the S-based default
          next unless space.partofTotalFloorArea

          infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
          infiltration.setName("#{space.nameString} NECB Ref Infiltration")
          infiltration.setFlowperExteriorWallArea(i_agw / 1000.0) # m3/s per m2
          infiltration.setConstantTermCoefficient(coeffs[:a])
          infiltration.setTemperatureTermCoefficient(coeffs[:b])
          infiltration.setVelocityTermCoefficient(coeffs[:c])
          infiltration.setVelocitySquaredTermCoefficient(coeffs[:d])
          infiltration.setSchedule(coeffs[:schedule]) if coeffs[:schedule]
          infiltration.setSpace(space)
        end
        # 8.4.3.3.(3)/(4): an UNTESTED proposed carries this same default. Warn
        # when the proposed's installed total deviates — below-default proposed
        # infiltration is a free heating credit (permissive direction).
        code_total_l_s = c * AIR_LEAKAGE_I75 * envelope_area
        if proposed_total_l_s && (proposed_total_l_s - code_total_l_s).abs > 0.10 * code_total_l_s
          audit.warn(:reference, format('proposed infiltration total %.0f L/s DEVIATES from the untested 8.4.3.3.(3) ' \
                                        'default %.0f L/s by %+.0f%% — only a 3.2.4.2 airtightness test justifies ' \
                                        'a different value', proposed_total_l_s, code_total_l_s,
                                        100 * (proposed_total_l_s / code_total_l_s - 1)),
                     article: '8.4.3.3.(3)-(4)')
        end
        audit.decision(:reference, 'air-leakage default applied',
                       inputs: { i75_l_per_s_m2: AIR_LEAKAGE_I75, flow_exponent: AIR_LEAKAGE_N,
                                 envelope_area_m2: envelope_area.round(1), ag_wall_area_m2: wall_area.round(1),
                                 proposed_infiltration_objects_cleared: cleared,
                                 inherited_coefficients: { a: coeffs[:a], b: coeffs[:b], c: coeffs[:c], d: coeffs[:d],
                                                           schedule: coeffs[:schedule]&.nameString } },
                       value: "I_AGW = (5/75)^0.6 x #{AIR_LEAKAGE_I75} x #{envelope_area.round(1)}/#{wall_area.round(1)} " \
                              "= #{i_agw.round(4)} L/(s.m2 AG wall), per space as flow-per-exterior-wall-area",
                       article: "#{prefix}.3.(6); 8.4.3.3.(3); 8.4.2.9.(2)")
      end

      # Completeness accounting (same contract as openstudio-hvac).
      def emit_article_coverage(vintage, audit)
        coverage = NECB.rules(vintage)['article_coverage']
        return if coverage.nil?

        cited = Hash.new(0)
        audit.entries.each do |entry|
          entry[:article].to_s.scan(/\d+\.\d+(?:\.\d+)*\./) { |a| cited[a] += 1 }
        end
        coverage['articles'].each do |art|
          applied = cited.select { |a, _| a.start_with?(art['article'].sub(/\.\z/, '')) }.values.sum
          inputs = { status: art['status'], decisions_citing: applied }
          inputs[:gap_owner] = art['gap_owner'] if art['gap_owner']
          if %w[implemented satisfied_by_clone host_scope].include?(art['status'])
            audit.info(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}#{art['how'] ? ": #{art['how']}" : ''}",
                       inputs: inputs, article: art['article'])
          elsif art['gap_owner'] == 'modeller' # scope note, not a warning (D-09)
            audit.info(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}, modeller scope" \
                                  "#{art['how'] ? ". Applied: #{art['how']}" : ''}" \
                                  "#{art['gaps'] ? ". Modeller's responsibility: #{art['gaps']}" : ''}",
                       inputs: inputs, article: art['article'])
          else
            audit.warn(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}" \
                                  "#{art['how'] ? ". Applied: #{art['how']}" : ''}" \
                                  "#{art['gaps'] ? ". Gaps: #{art['gaps']}" : ''}",
                       inputs: inputs, article: art['article'])
          end
        end
      end
    end

    # Facade: reference envelope IN PLACE on the caller's clone.
    def self.reference_envelope(model, vintage:, hdd: nil, actual_roof_absorptance_used: false,
                                thermal_bridging: nil, audit: nil)
      Reference.apply(model, vintage: vintage, hdd: hdd,
                      actual_roof_absorptance_used: actual_roof_absorptance_used,
                      thermal_bridging: thermal_bridging, audit: audit)
    end
  end
end
