module OpenStudioLighting
  module NECB
    # Reference-building lighting — NECB 2020 8.4.4.5 (2025: renumbered
    # performance path):
    #   (1) installed interior lighting power = the Part 4 allowance
    #       (apply_lights with NECB_Default IS the allowance)
    #   (2) dwelling units at 5 W/m2
    #   (3) occupancy/personal-control factors (Table 4.3.2.10) — applied via the
    #       sensor-schedule synthesis (schedule modulation), the legacy NECB2015+
    #       interpretation of the power-multiplier wording
    #   (4) radiant/convective/return-air fractions identical to proposed — holds
    #       by construction (same space-type records drive both models)
    #   (5)-(12) daylighting geometry + photocontrols — modeled by the SEPARATE
    #       reference_daylighting transform (reference_daylighting.rb), which
    #       audits (5)-(12) itself. This transform therefore says nothing about
    #       them when it is told daylighting ran (daylighting: true) and warns
    #       loudly only when it did not.
    module Reference
      module_function

      # @param daylighting [Boolean] whether the caller ALSO runs
      #   reference_daylighting on this model. When it does, (5)-(12) are
      #   modeled and audited there, so this transform stays silent about them;
      #   when it does not, the gap is shouted here. Defaults to false so a
      #   caller that never runs the daylighting transform still gets the loud
      #   gap without opting in.
      def reference_lighting(model, vintage: '2020', daylighting: false, audit: nil)
        audit ||= AuditLog.new
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'

        # HARD GATE: apply_lights silently skips space types with no NECB
        # catalog record, and the reference is a clone — so an unmatched type
        # keeps the PROPOSED's lighting power verbatim, waiving the Part 4
        # allowance for exactly the spaces where it matters (an over-lit space
        # then incurs zero penalty). The allowance for an unlisted space
        # function is a human judgement (4.2.1.6.(1)(b): "most closely
        # represents the proposed use"), so no fallback value is invented here:
        # the transform refuses, loudly, before a wrong reference can exist.
        unmatched = ApplyLights.unmatched_space_types(model, vintage)
        unless unmatched.empty?
          pairs = unmatched.map { |u| "'#{u[:name]}' [#{u[:building_type].inspect}, #{u[:space_type].inspect}]" }
          unmatched.each do |u|
            audit.warn(:lighting_reference,
                       "space type '#{u[:name]}' is UNRESOLVABLE against the NECB catalog — the #{prefix}.5.(1) " \
                       'reference lighting allowance cannot be established for it',
                       article: "#{prefix}.5.(1); 4.2.1.6.")
          end
          raise(ArgumentError,
                "reference lighting ABORTED: #{unmatched.size} space type(s) have no NECB #{vintage} catalog " \
                "record, so the #{prefix}.5.(1) interior lighting allowance cannot be established: " \
                "#{pairs.join('; ')}. Tag the model with NECB space functions " \
                '(OpenStudioLoads assign_space_types, or correct standardsBuildingType/standardsSpaceType) — ' \
                'proceeding would silently keep the proposed lighting power in the reference.')
        end

        ApplyLights.apply_lights(model, vintage: vintage, lights_type: 'NECB_Default', audit: audit)
        audit.decision(:lighting_reference,
                       'reference interior lighting set to the Part 4 allowance (space-type LPDs)',
                       article: "#{prefix}.5.(1)")

        apply_dwelling_rule(model, vintage, prefix, audit)
        audit.info(:lighting_reference,
                   'occupancy/personal-control factors applied via the sensor-schedule synthesis ' \
                   '(schedule modulation of the Table 4.3.2.10 factors — legacy NECB2015+ interpretation ' \
                   'of the power-multiplier wording)', article: "#{prefix}.5.(3); 4.3.2.10.")
        audit.info(:lighting_reference,
                   'lighting heat fractions identical to proposed by construction (same space-type records)',
                   article: "#{prefix}.5.(4)")
        unless daylighting
          audit.warn(:lighting_reference,
                     "#{prefix}.5.(5)-(12): reference daylighting geometry (centered-window sidelighting, " \
                     'centred-skylight toplighting) and photocontrol evaluation are NOT modeled on this run ' \
                     '(reference_daylighting was not run)',
                     article: "#{prefix}.5.(5)-(12)")
        end
        audit
      end

      # 8.4.4.5.(2): dwelling units at 5 W/m2.
      def apply_dwelling_rule(model, vintage, prefix, audit)
        lpd = NECB.rules(vintage)['dwelling_unit_lpd_w_per_m2'].to_f
        changed = 0
        model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
          standards = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : ''
          next unless standards =~ /dwelling/i

          space_type.lights.sort_by(&:nameString).each do |lights|
            lights.lightsDefinition.setWattsperSpaceFloorArea(lpd)
            changed += 1
          end
        end
        audit.decision(:lighting_reference, "dwelling units modeled at #{lpd} W/m2",
                       inputs: { lights_instances: changed }, article: "#{prefix}.5.(2)")
      end

      # ---- internals (not API) ----
      private_class_method :apply_dwelling_rule
    end

    def self.reference_lighting(model, **kwargs)
      Reference.reference_lighting(model, **kwargs)
    end
  end
end
