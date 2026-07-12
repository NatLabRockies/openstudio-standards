module OpenStudioLighting
  module NECB
    # Reference-building daylighting — NECB 2020 8.4.4.5.(5)-(12) (2025:
    # renumbered performance path). Where Subsection 4.2.2 requires photocontrols
    # (sentence (9)), their effect is evaluated in the reference building:
    #
    #   (10)(b) reflectances: floor 0.15 / walls 0.50 / ceiling 0.80 — SET on the
    #           reference model's interior surfaces (visible absorptance =
    #           1 - reflectance); works naturally with the envelope gem's
    #           lightweight massless constructions.
    #   (10)(d) fenestration VT: the envelope reference transform preserves the
    #           proposed optics by construction — satisfied.
    #   (11)    photocontrol set-point: the proposed building's, else
    #           representative of the space use (the space-type
    #           target_illuminance_setpoint).
    #   (9)+(12) evaluation method: EnergyPlus performs DETAILED daylighting via
    #           DaylightingControl objects, so the sentence-(12) FDL-factor
    #           fallback (for models that cannot do detailed daylighting) is not
    #           needed — audited.
    #   (5)-(8) the analytic single-centered-window / centered-skylight
    #           convention for daylighted-AREA determination: the requirement
    #           determination uses the ported 4.2.2 threshold geometry on the
    #           reference's actual (FDWR/SRR-scaled) fenestration instead —
    #           an audited interpretation (E+ detailed daylighting evaluates the
    #           real scaled apertures the envelope reference produces).
    module ReferenceDaylighting
      module_function

      REFLECTANCES = { 'Floor' => 0.15, 'Wall' => 0.50, 'RoofCeiling' => 0.80 }.freeze

      # Apply reference daylighting to a reference model (after the envelope
      # reference transform). Set-points come from the proposed model's controls
      # when given.
      # @param proposed [OpenStudio::Model::Model, nil] for (11)(a) set-points
      # @param placement [:necb_default, :all] which spaces get photocontrols —
      #   :necb_default = where 4.2.2 requires them (legacy threshold semantics,
      #   defects and all); :all = every daylighted space
      def apply(reference, vintage: '2020', proposed: nil, placement: :necb_default,
                office_match: :any_enclosed_office, audit: nil)
        audit ||= AuditLog.new
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'

        set_reference_reflectances(reference, prefix, audit)

        proposed_setpoints = {}
        proposed&.getDaylightingControls&.each do |control|
          next if control.space.empty?

          proposed_setpoints[control.space.get.nameString] = control.illuminanceSetpoint
        end

        option = placement == :all ? 'all' : 'NECB_Default'
        created = Daylighting.add_controls(reference, vintage: vintage, option: option,
                                           office_match: office_match, audit: audit)

        overridden = 0
        reference.getDaylightingControls.sort_by(&:nameString).each do |control|
          next if control.space.empty?

          setpoint = proposed_setpoints[control.space.get.nameString]
          next if setpoint.nil?

          control.setIlluminanceSetpoint(setpoint)
          overridden += 1
        end

        audit.decision(:lighting_reference,
                       'reference photocontrols evaluated by DETAILED daylighting (E+ DaylightingControl ' \
                       'objects on the reference\'s FDWR/SRR-scaled fenestration) — the sentence-(12) ' \
                       'FDL-factor fallback is unnecessary for models that can do detailed daylighting',
                       inputs: { controls: created, setpoints_from_proposed: overridden,
                                 placement: option, office_match: office_match },
                       article: "#{prefix}.5.(9); #{prefix}.5.(11); #{prefix}.5.(12)")
        audit.info(:lighting_reference,
                   'fenestration VT identical to proposed by construction (the envelope reference transform ' \
                   'preserves optics)', article: "#{prefix}.5.(10)(d)")
        audit.info(:lighting_reference,
                   'daylighted-AREA determination uses the ported 4.2.2 threshold geometry on the reference\'s ' \
                   'actual scaled fenestration instead of the analytic single-centered-window/skylight ' \
                   'convention of sentences (5)-(8) — interpretation: E+ evaluates the real apertures',
                   article: "#{prefix}.5.(5)-(8)")
        audit
      end

      # (10)(b): floor 0.15 / wall 0.50 / ceiling 0.80 visible reflectances on
      # every interior-facing surface material of the reference.
      def set_reference_reflectances(reference, prefix, audit)
        changed = 0
        reference.getSurfaces.sort_by(&:nameString).each do |surface|
          reflectance = REFLECTANCES[surface.surfaceType]
          next if reflectance.nil?
          next if surface.construction.empty? || surface.construction.get.to_LayeredConstruction.empty?

          layers = surface.construction.get.to_LayeredConstruction.get.layers
          inner = layers.last.to_OpaqueMaterial # inside-facing layer
          next if inner.empty?

          inner.get.setVisibleAbsorptance(OpenStudio::OptionalDouble.new(1.0 - reflectance))
          changed += 1
        end
        audit.decision(:lighting_reference,
                       'reference interior visible reflectances set: floor 0.15 / walls 0.50 / ceiling 0.80',
                       inputs: { surfaces: changed }, article: "#{prefix}.5.(10)(b)")
      end
    end

    def self.reference_daylighting(reference, **kwargs)
      ReferenceDaylighting.apply(reference, **kwargs)
    end
  end
end
