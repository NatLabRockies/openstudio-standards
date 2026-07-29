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
    #           determination uses the 4.2.2.3./4.2.2.5. threshold geometry on the
    #           reference's actual (FDWR/SRR-scaled) fenestration instead —
    #           an audited interpretation (E+ detailed daylighting evaluates the
    #           real scaled apertures the envelope reference produces).
    #
    # WHICH 4.2.2 RULE DECIDES "where Subsection 4.2.2 requires photocontrols":
    # the NECB 2020/2025 one — Article 4.2.2.1., sentences (10)-(15) — per D-57.
    # Before D-57 this transform ran the legacy NECB 2011 criteria, which are
    # area/effective-aperture based and applied CONJUNCTIVELY, so a window-only
    # space could never qualify and the reference got no photocontrols at all on
    # most archetypes (L-26). `placement: :necb2011` still reaches the legacy rule
    # for the parity gate.
    module ReferenceDaylighting
      module_function

      REFLECTANCES = { 'Floor' => 0.15, 'Wall' => 0.50, 'RoofCeiling' => 0.80 }.freeze

      # Apply reference daylighting to a reference model (after the envelope
      # reference transform). Set-points come from the proposed model's controls
      # when given.
      # @param proposed [OpenStudio::Model::Model, nil] for (11)(a) set-points
      # @param placement [:necb2020, :necb2011, :necb_default, :all] which spaces
      #   get photocontrols. :necb2020 (DEFAULT) = where 4.2.2.1.(10)-(15)
      #   requires them (D-57); :necb2011 (alias :necb_default) = the legacy
      #   NECB 2011 threshold semantics, defects and all, kept for the parity
      #   gate; :all = every daylighted space
      # @param unknown_control_requirement [:required, :not_required] :necb2020
      #   only — the default for an unresolvable Table 4.2.1.6. column (warns)
      def apply(reference, vintage: '2020', proposed: nil, placement: :necb2020,
                office_match: :any_enclosed_office, unknown_control_requirement: :required, audit: nil)
        audit ||= AuditLog.new
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
        placement = :necb2011 if placement == :necb_default

        set_reference_reflectances(reference, prefix, audit)

        proposed_setpoints = {}
        proposed&.getDaylightingControls&.each do |control|
          next if control.space.empty?

          proposed_setpoints[control.space.get.nameString] = control.illuminanceSetpoint
        end

        option = placement == :all ? 'all' : 'NECB_Default'
        created = Daylighting.add_controls(reference, vintage: vintage, option: option,
                                           placement: placement, office_match: office_match,
                                           unknown_control_requirement: unknown_control_requirement,
                                           audit: audit)

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
                   'daylighted-AREA determination uses the 4.2.2.3./4.2.2.5. threshold geometry on the ' \
                   'reference\'s actual scaled fenestration instead of the analytic single-centered-window/' \
                   'skylight convention of sentences (5)-(8) — interpretation: E+ evaluates the real apertures',
                   article: "#{prefix}.5.(5)-(8)")
        if placement == :necb2011
          audit.warn(:lighting_reference,
                     'REFERENCE PHOTOCONTROL PLACEMENT USES THE LEGACY NECB 2011 CRITERIA (placement: ' \
                     ':necb2011): area and effective-aperture tests, applied conjunctively, so window-only ' \
                     'spaces get NO photocontrols and the reference target is LOOSER than 4.2.2.1.(10)-(15) ' \
                     'requires. Pass placement: :necb2020 (the default) for the code rule',
                     article: '4.2.2.1.(10); 4.2.2.1.(13)',
                     ruling: 'D-57')
        else
          audit.decision(:lighting_reference,
                         'reference photocontrols are placed where NECB 2020/2025 4.2.2.1.(10)-(15) requires ' \
                         'them — the Table 4.2.1.6. column for the space type, then an INPUT-POWER test inside ' \
                         'the unioned daylighted areas (>=150 W primary sidelighted, or >=300 W primary + ' \
                         'secondary, or >=150 W under skylights), sidelighting and toplighting evaluated ' \
                         'INDEPENDENTLY. The legacy NECB 2011 criteria this replaced could not qualify a ' \
                         'window-only space at all (L-26)',
                         inputs: { controls: created, placement: placement },
                         article: '4.2.2.1.(10); 4.2.2.1.(12); 4.2.2.1.(13); 4.2.2.1.(15); Table 4.2.1.6.',
                         ruling: 'D-57')
        end
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
