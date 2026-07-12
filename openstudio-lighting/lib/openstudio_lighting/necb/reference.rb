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
    #   (5)-(12) daylighting geometry + photocontrols — not modeled (loud gaps)
    module Reference
      module_function

      def reference_lighting(model, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
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
        audit.warn(:lighting_reference,
                   "#{prefix}.5.(5)-(12): reference daylighting geometry (centered-window sidelighting, " \
                   'centred-skylight toplighting) and photocontrol evaluation are NOT modeled',
                   article: "#{prefix}.5.(5)-(12)")
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
    end

    def self.reference_lighting(model, **kwargs)
      Reference.reference_lighting(model, **kwargs)
    end
  end
end
