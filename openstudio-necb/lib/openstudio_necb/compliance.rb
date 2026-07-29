require 'json'

module OpenStudioNECB
  # The NECB Part 8 performance path (Division B, 8.4.1.2, identical intent in
  # 2020 and 2025):
  #   (2) annual energy consumption of the PROPOSED building shall not exceed the
  #       building energy target of the REFERENCE building
  #   (3) unmet heating hours <= 100 h/year for both buildings
  #   (4) unmet cooling hours: proposed within +10% of reference (2025 8.4.4 path:
  #       proposed <= 100 h; 8.4.5 path: within +10% or 20 h, whichever is greater)
  #   (5) where (3)/(4) fail, capacities of the primary and secondary systems
  #       shall be incrementally increased until the loads are met — implemented
  #       per THERMAL BLOCK (the resolution sentences (3)/(4) are written at):
  #       each failing zone's Sizing:Zone factors are raised, secant-targeted
  #       from that zone's own (factor, unmet-hours) history, with a global
  #       SizingParameters fallback when per-zone data cannot attribute the
  #       failure; bounded by max_capacity_iterations; a still-failing
  #       result after the cap is a loud warning + non-compliance.
  #
  # One clone, one audit: reference_hvac (openstudio-hvac), reference_envelope
  # (openstudio-envelope), reference_lighting (openstudio-lighting — Part 4
  # allowance LPDs) and reference_shw (openstudio-shw — Part 6 minimum
  # efficiencies) transform a single reference model, and optional costing of
  # both models lands in the same AuditLog.
  module Compliance
    ComplianceResult = Struct.new(:proposed_model, :reference_model, :report, :audit,
                                  :compliant, :run_dir, keyword_init: true)

    module_function

    # @param model [OpenStudio::Model::Model, String] the proposed building (or .osm path)
    # @param vintage ['2020', '2025']
    # @param weather [Hash] { epw:, ddy:, stat: } — epw+ddy required unless simulate: :none
    # @param building [Hash, nil] facts for reference-system selection (storeys,
    #   zone_types, winter_design_temp_c, ...) — see OpenStudioHVAC::NECB.reference_hvac
    # @param hdd [Numeric, nil] heating degree-days; nil resolves via the envelope
    #   gem (explicit > Table C-1 nearest city > .stat)
    # @param run_dir [String] working directory (simulations, report.json, audit.json)
    # @param simulate [:annual, :sizing, :none] :annual = full compliance determination;
    #   :sizing = generate + size both models, no energy comparison; :none = model
    #   transforms only (loud warning: selection kW thresholds stay unresolved)
    # @param run_period [Hash, nil] shortened weather run for TESTS — a non-annual
    #   period cannot determine code compliance and is flagged in the report
    # @param costing [Boolean] cost BOTH models (HVAC via openstudio-hvac + envelope
    #   via openstudio-envelope) into the same audit
    # @param thermal_bridging [String, Hash, nil] TBD PSI set for the envelope transforms
    # @param audit [AuditLog, nil]
    # @return [ComplianceResult]
    # @param max_capacity_iterations [Integer] 8.4.1.2.(5) bound: how many times a
    #   failing building's capacities may be incrementally increased (0 disables)
    # @param capacity_step [Float] multiplier for a zone's (or, on fallback, the
    #   building's) first sizing-factor bump — and for any later bump where the
    #   zone's own history cannot support a secant extrapolation
    # @param necb_loads [Hash, nil] bare-geometry on-ramp: apply the NECB space-use
    #   gems to the proposed clone BEFORE anything else. Keys:
    #   space_type_map: {space name => [building_type, space_type]} (required),
    #   lights_type: 'NECB_Default'|'LED' (default NECB_Default),
    #   shw_fuel: 'NaturalGas'|'Electricity'|'FuelOilNo2'|nil (nil = no SHW),
    #   hvac_system: catalog name for OpenStudioHVAC.build_system (nil = keep
    #   whatever HVAC the model carries)
    # @param path [:reference, :eui] :reference = the 8.4.4 (2025: 8.4.5)
    #   reference-building comparison; :eui = the NECB 2025 8.4.4 archetype-EUI
    #   building energy target (BET = sum(A_i x EUI_i) + PL — no reference
    #   building is generated or simulated)
    # @param archetypes [Hash{String=>:all,Array<String>}] :eui path only —
    #   archetype => :all (every counted space not claimed elsewhere) or an
    #   array of space names. Floor areas are COMPUTED from the model per
    #   8.4.4.1.(3); unmapped space functions distribute pro-rata per
    #   8.4.4.1.(4). The mapping also drives the Table 8.4.4.2 conformance
    #   check and (when non-conformant) the normalization of the proposed.
    # @param process_loads_kwh [Numeric] :eui path PL term (8.4.4.1.(2))
    def performance_compliance(model, vintage: '2020', weather: {}, building: nil,
                               hdd: nil, run_dir:, simulate: :annual, run_period: nil,
                               costing: false, city: nil, province_state: nil,
                               costs_csv: nil, thermal_bridging: nil,
                               actual_roof_absorptance_used: false,
                               max_capacity_iterations: 3, capacity_step: 1.25,
                               necb_loads: nil, reference_daylighting: false,
                               path: :reference, archetypes: nil,
                               process_loads_kwh: 0.0, eui_supplement: nil,
                               report_html: false, report_options: {}, audit: nil)
      if path == :eui
        raise(ArgumentError, 'the archetype-EUI path is a NECB 2025 feature (vintage: 2025)') unless vintage.to_s == '2025'
        raise(ArgumentError, ':eui path requires archetypes: {archetype => :all | [space names]}') if archetypes.nil?

        return eui_compliance(model, vintage: vintage, weather: weather, hdd: hdd,
                              run_dir: run_dir, simulate: simulate, run_period: run_period,
                              archetypes: archetypes, process_loads_kwh: process_loads_kwh,
                              costing: costing, city: city, province_state: province_state,
                              costs_csv: costs_csv, necb_loads: necb_loads,
                              report_html: report_html, report_options: report_options, audit: audit)
      end
      audit ||= AuditLog.new
      FileUtils.mkdir_p(run_dir)
      report = {}
      begin
      proposed = nil
      audit.with_building('input model') do
        proposed = load_model(model)
        apply_necb_loads(proposed, vintage, necb_loads, audit) if necb_loads
        # PRE-FLIGHT: every floor-area space type must resolve against the NECB
        # catalog BEFORE any transform runs. The reference is a clone of the
        # proposed, and the per-space-type transforms (lighting LPD, loads, SHW
        # demand) silently skip unmatched types — so an unresolvable space type
        # yields a reference identical to the proposed for exactly that space:
        # the allowance is waived and the proposed is compared against itself.
        # You cannot certify a building whose reference silently failed to
        # build; fail here, loudly, with the full list (the raise lands inside
        # the begin, so the audit trail is still flushed to run_dir).
        validate_space_types!(proposed, vintage, audit)
      end
      audit.decision(:compliance, 'performance-path run started',
                     inputs: { vintage: vintage, simulate: simulate, costing: costing },
                     article: '8.4.1.2.(1)')

      audit.building = 'proposed building'
      if simulate != :none
        %i[epw ddy].each do |key|
          raise(ArgumentError, "weather[:#{key}] is required when simulate: #{simulate}") unless weather[key]
        end
        Runner.attach_weather!(proposed, epw: weather[:epw], ddy: weather[:ddy])
      end

      # HDD for the envelope rules (explicit > Table C-1 from the EPW site > .stat)
      hdd ||= OpenStudioEnvelope::Climate.hdd18(proposed, audit: audit)
      raise(ArgumentError, 'HDD unresolvable: pass hdd: or weather with a recognized site') if hdd.nil?

      # 1. size the PROPOSED building (selection thresholds + efficiencies + costing
      #    all need capacities; the domain gems never simulate)
      if simulate == :none
        audit.warn(:compliance, 'simulate: :none — proposed is UNSIZED; data-centre kW thresholds ' \
                                'and capacity-binned efficiencies fall back with warnings; the 5.2.10.1 ' \
                                'energy-recovery determination needs sized flows and is SKIPPED')
      else
        Runner.run_energyplus!(proposed, File.join(run_dir, 'proposed_sizing'), sizing_only: true)
        audit.info(:compliance, 'proposed sizing run complete', target: 'proposed')
      end

      # 2. reference building: HVAC then envelope on ONE clone, same audit
      reference = nil
      audit.with_building('reference building') do
        reference_result = OpenStudioHVAC::NECB.reference_hvac(proposed, vintage: vintage,
                                                               building: building, audit: audit)
        reference = reference_result.model
        OpenStudioEnvelope::NECB.reference_envelope(reference, vintage: vintage, hdd: hdd,
                                                    actual_roof_absorptance_used: actual_roof_absorptance_used,
                                                    thermal_bridging: thermal_bridging, audit: audit)
        OpenStudioLighting::NECB.reference_lighting(reference, vintage: vintage, audit: audit)
        if reference_daylighting
          OpenStudioLighting::NECB.reference_daylighting(reference, vintage: vintage,
                                                         proposed: proposed, audit: audit)
        end
        OpenStudioSHW::NECB.reference_shw(reference, vintage: vintage, audit: audit)
      end
      audit.building = nil
      audit.info(:compliance,
                 '8.4.3.2 operating schedules and occupancy/receptacle loads are identical between ' \
                 'proposed and reference by construction (the reference is a clone; neither reset touches ' \
                 'schedules or those loads); interior lighting power is reset to the Part 4 allowance per ' \
                 '8.4.4.5.(1) (reference_lighting); service water heating efficiencies are reset to the ' \
                 'Part 6 minimums per 8.4.4.20 (reference_shw). Representativeness of the loads for the ' \
                 "building type remains the modeller's input (see the openstudio-loads gem for NECB " \
                 'space-use data).',
                 article: '8.4.3.2.(1)-(2)')

      # 3. size the reference, then re-apply efficiencies on sized equipment
      #    (the openstudio-hvac contract: efficiency rows are capacity-binned)
      if simulate != :none
        audit.with_building('reference building') do
          Runner.run_energyplus!(reference, File.join(run_dir, 'reference_sizing'), sizing_only: true)
          # proposed: enables the 8.4.4.14.(1)-(3) pump power transfer (the
          # proposed was sized in step 1, so its pump flows/powers are readable)
          OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: vintage, audit: audit, proposed: proposed)
          # 5.2.10.1 energy recovery is a POST-SIZING determination (Table
          # 5.2.10.1.-A/-B thresholds need the sized supply/OA flows).
          OpenStudioHVAC::NECB.apply_energy_recovery(reference, vintage: vintage, hdd: hdd, audit: audit)
          # T3: 5.2.2.7 economizer trigger is likewise a post-sizing determination
          OpenStudioHVAC::NECB.apply_economizer_thresholds(reference, audit: audit)
          audit.info(:compliance, 'reference sized; efficiencies re-applied and the 5.2.10.1 energy-recovery ' \
                                  'determination evaluated on sized flows', target: 'reference')
        end
      end

      report = { 'vintage' => vintage, 'hdd' => hdd, 'simulate' => simulate.to_s,
                 'proposed' => {}, 'reference' => {} }
      compliant = nil

      # 4. the energy comparison (8.4.1.2.(2)-(4)) with the sentence-(5) capacity
      #    iteration loop
      if simulate == :annual
        report['proposed']['mechanical_cooling'] = mechanical_cooling?(proposed)
        run_annual(proposed, File.join(run_dir, 'proposed_annual'), run_period, report['proposed'])
        run_annual(reference, File.join(run_dir, 'reference_annual'), run_period, report['reference'])
        iterate_capacities(proposed, reference, report, vintage: vintage, run_dir: run_dir,
                           run_period: run_period, max_iterations: max_capacity_iterations,
                           step: capacity_step, audit: audit)
        compliant = evaluate(report, vintage, run_period, audit)
      elsif simulate == :sizing
        audit.info(:compliance, 'simulate: :sizing — both models generated and sized; ' \
                                'no energy comparison performed (compliance undetermined)')
      end

      # NECB 2025 Part 11: operational GHG performance level (needs a province)
      if vintage.to_s == '2025' && simulate == :annual && province_state
        proposed_ghg = Tiers.operational_ghg_kg(report['proposed'], province_state)
        reference_ghg = Tiers.operational_ghg_kg(report['reference'], province_state)
        if proposed_ghg && reference_ghg&.positive?
          report['proposed']['ghg_kg_co2e'] = proposed_ghg
          report['reference']['ghg_kg_co2e'] = reference_ghg
          report['ghg'] = Tiers.ghg_level(proposed_ghg, reference_ghg, audit: audit)
        end
      end

      # 5. unified costing of BOTH models (same audit)
      cost_models(proposed, reference, report, city: city, province_state: province_state,
                  costs_csv: costs_csv, audit: audit) if costing

      # eui_supplement (2025): the 8.4.4 archetype-EUI verdict alongside the
      # reference-path run. The two paths simulate DIFFERENT proposed
      # buildings — as-specified (8.4.3.2) vs normalized to Table 8.4.4.2
      # (8.4.4.2.(1)) — so the reference-path annual result serves the EUI
      # verdict ONLY when the proposed already conforms to the Table. When it
      # does not: report not-computed with the mismatch list (default — never
      # silently double the simulation cost), or, with run_normalized: true,
      # clone-normalize-rerun and compute the verdict from that run.
      if eui_supplement && vintage.to_s == '2025' && report['proposed']['total_site_kwh']
        report['eui_path'] = eui_supplement_verdict(proposed, eui_supplement, hdd, report, run_dir,
                                                    run_period, vintage, audit)
      end

      emit_article_coverage(vintage, audit)
      report['compliant'] = compliant
      report['warnings'] = audit.warnings.map { |w| w[:action] }
      write_outputs(run_dir, report, audit)
      result = ComplianceResult.new(proposed_model: proposed, reference_model: reference,
                                    report: report, audit: audit, compliant: compliant, run_dir: run_dir)
      Report.write_html(result, File.join(run_dir, 'compliance_report.html'), report_options) if report_html
      result
      rescue StandardError => e
        flush_on_failure(run_dir, report, audit, e)
        raise e
      end
    end

    def load_model(model)
      return OpenStudio::Model::Model.load(OpenStudio::Path.new(model)).get if model.is_a?(String)

      # never mutate the caller's model — the pipeline sizes/simulates its own copy
      model.clone(true).to_Model
    end

    # The NECB 2025 8.4.4 archetype-EUI path: the building energy target comes
    # from Table 8.4.4.1 (BET = sum(A_i x EUI_i) + PL) — NO reference building
    # is generated or simulated. The proposed is CHECKED against the Table
    # 8.4.4.2 standardized operating inputs and, when it does not already
    # conform, NORMALIZED to them before the annual run (8.4.4.2.(1)): the EUI
    # targets were derived assuming those inputs, so an as-modeled comparison
    # would be apples-to-oranges. Compliance: proposed annual consumption <=
    # BET; the Section 10 tier is computed against the same BET.
    def eui_compliance(model, vintage:, weather:, hdd:, run_dir:, simulate:, run_period:,
                       archetypes:, process_loads_kwh:, costing:, city:,
                       province_state:, costs_csv:, necb_loads:,
                       report_html: false, report_options: {}, audit: nil)
      audit ||= AuditLog.new
      FileUtils.mkdir_p(run_dir)
      report = {}
      begin
      proposed = nil
      audit.with_building('input model') do
        proposed = load_model(model)
        apply_necb_loads(proposed, vintage, necb_loads, audit) if necb_loads
      end
      audit.decision(:compliance, 'ARCHETYPE-EUI compliance path (NECB 2025 8.4.4) — no reference building',
                     inputs: { vintage: vintage, archetypes: archetypes.keys },
                     article: '8.4.4.1.')

      audit.building = 'proposed building'
      if simulate != :none
        %i[epw ddy].each { |k| raise(ArgumentError, "weather[:#{k}] required") unless weather[k] }
        Runner.attach_weather!(proposed, epw: weather[:epw], ddy: weather[:ddy])
      end
      hdd ||= OpenStudioEnvelope::Climate.hdd18(proposed, audit: audit)

      # Mapping -> model-derived areas -> HARD applicability (refuse outside
      # 8.4.4.1.(1)/HDD bounds: a verdict outside applicability is not a
      # determination) -> Table 8.4.4.2 conformance -> normalize if needed.
      resolved = Archetypes.resolve!(proposed, archetypes, audit: audit)
      Archetypes.applicability!(resolved, hdd: hdd, audit: audit)
      check = Archetypes.conformance(proposed, resolved, vintage: vintage, audit: audit)
      Archetypes.normalize!(proposed, resolved, vintage: vintage, audit: audit) unless check[:conformant]
      audit.building = nil # BET derivation + verdicts are comparisons, not model work

      report = { 'vintage' => vintage, 'hdd' => hdd, 'simulate' => simulate.to_s,
                 'path' => 'eui', 'proposed' => {}, 'reference' => {},
                 'eui' => { 'conformant_to_8_4_4_2' => check[:conformant],
                            'normalized' => !check[:conformant],
                            'mismatches' => check[:mismatches].first(50) } }
      target = Tiers.eui_building_energy_target(Archetypes.bet_areas(resolved, audit: audit),
                                                resolved[:total_area_m2],
                                                hdd: hdd, process_loads_kwh: process_loads_kwh, audit: audit)
      report['reference'] = { 'method' => 'archetype EUI (Table 8.4.4.1)',
                              'building_energy_target_kwh' => target['bet_kwh'],
                              'lines' => target['lines'] }

      compliant = nil
      if simulate == :annual
        run_annual(proposed, File.join(run_dir, 'proposed_annual'), run_period, report['proposed'])
        proposed_kwh = report['proposed']['total_site_kwh']
        compliant = proposed_kwh <= target['bet_kwh']
        audit.decision(:compliance,
                       compliant ? 'proposed does not exceed the archetype-EUI building energy target' : 'proposed EXCEEDS the archetype-EUI building energy target',
                       inputs: { proposed_kwh: proposed_kwh, bet_kwh: target['bet_kwh'] },
                       article: '8.4.4.1.(2)')
        report.merge!(Tiers.energy_tier(proposed_kwh, target['bet_kwh'], audit: audit))
        if province_state
          ghg = Tiers.operational_ghg_kg(report['proposed'], province_state)
          report['proposed']['ghg_kg_co2e'] = ghg if ghg
        end
        if run_period
          audit.warn(:compliance, 'run period is SHORTENED — not a code-compliant annual determination')
          report['annual'] = false
        else
          report['annual'] = true
        end
      elsif simulate == :sizing
        Runner.run_energyplus!(proposed, File.join(run_dir, 'proposed_sizing'), sizing_only: true)
      end

      if costing
        audit.with_building('proposed building') do
          hvac_cost = OpenStudioHVAC.cost(proposed, city: city, province_state: province_state,
                                          costs_csv: costs_csv, audit: audit)
          envelope_cost = OpenStudioEnvelope.cost(proposed, city: hvac_cost.city,
                                                  province_state: hvac_cost.province_state,
                                                  costs_csv: costs_csv, audit: audit)
          report['proposed']['cost'] = { 'hvac' => hvac_cost.total, 'envelope' => envelope_cost.total,
                                         'total' => (hvac_cost.total + envelope_cost.total).round(2) }
        end
      end

      emit_article_coverage(vintage, audit)
      report['compliant'] = compliant
      report['warnings'] = audit.warnings.map { |w| w[:action] }
      write_outputs(run_dir, report, audit)
      result = ComplianceResult.new(proposed_model: proposed, reference_model: nil,
                                    report: report, audit: audit, compliant: compliant, run_dir: run_dir)
      Report.write_html(result, File.join(run_dir, 'compliance_report.html'), report_options) if report_html
      result
      rescue StandardError => e
        flush_on_failure(run_dir, report, audit, e)
        raise e
      end
    end

    # The bare-geometry on-ramp: NECB space types -> loads -> lighting -> SHW ->
    # (optionally) an HVAC system, all on the proposed clone with the shared audit.
    def apply_necb_loads(proposed, vintage, options, audit)
      map = options[:space_type_map] || options['space_type_map']
      raise(ArgumentError, 'necb_loads requires space_type_map: {space name => [building_type, space_type]}') if map.nil?

      OpenStudioLoads.assign_space_types(proposed, map, vintage: vintage, audit: audit)
      OpenStudioLoads::NECB.apply_loads(proposed, vintage: vintage, audit: audit)
      OpenStudioLighting.apply_lights(proposed, vintage: vintage,
                                      lights_type: options[:lights_type] || 'NECB_Default', audit: audit)
      shw_fuel = options[:shw_fuel]
      OpenStudioSHW.apply_shw(proposed, vintage: vintage, fuel: shw_fuel, audit: audit) if shw_fuel
      hvac = options[:hvac_system]
      OpenStudioHVAC.build_system(proposed, hvac, proposed.getThermalZones.sort_by(&:nameString)) if hvac
      audit.decision(:compliance, 'NECB space-use gems applied to the proposed (bare-geometry on-ramp)',
                     inputs: { spaces_mapped: map.size, lights_type: options[:lights_type] || 'NECB_Default',
                               shw_fuel: shw_fuel || 'none', hvac_system: hvac || 'model as given' },
                     article: '8.4.3.2.')
    end

    def run_annual(model, dir, run_period, section)
      run_dir = Runner.run_energyplus!(model, dir, sizing_only: false, run_period: run_period)
      section['clean_run'] = Runner.clean_run?(run_dir)
      section.merge!(Runner.energy_results(model))
      section['unmet_occupied_hours'] = Runner.unmet_occupied_hours(model)
      section['zone_unmet_occupied_hours'] = Runner.zone_unmet_occupied_hours(model)
      section['run_dir'] = run_dir
    end

    # 8.4.1.2 sentences (2)-(4). A shortened run period reports the same arithmetic
    # but flags that it is NOT a code-compliant determination.
    def evaluate(report, vintage, run_period, audit)
      proposed_kwh = report['proposed']['total_site_kwh']
      reference_kwh = report['reference']['total_site_kwh']
      raise('annual runs missing energy results') if proposed_kwh.nil? || reference_kwh.nil?

      energy_ok = proposed_kwh <= reference_kwh
      audit.decision(:compliance,
                     energy_ok ? 'proposed does not exceed the building energy target' : 'proposed EXCEEDS the building energy target',
                     inputs: { proposed_kwh: proposed_kwh, reference_building_energy_target_kwh: reference_kwh },
                     value: "margin #{(reference_kwh - proposed_kwh).round(1)} kWh (#{(100.0 * (reference_kwh - proposed_kwh) / reference_kwh).round(1)}%)",
                     article: '8.4.1.2.(2)')
      report.merge!(Tiers.energy_tier(proposed_kwh, reference_kwh, audit: audit))

      unmet_ok = evaluate_unmet(report, vintage, audit)

      if run_period
        audit.warn(:compliance, 'run period is SHORTENED — the energy comparison above is not a code-compliant ' \
                                'annual determination (8.4.1.2 requires a simulated year)')
        report['annual'] = false
      else
        report['annual'] = true
      end
      energy_ok && unmet_ok
    end

    def evaluate_unmet(report, vintage, audit)
      status = unmet_status(report, vintage)
      audit.decision(:compliance,
                     status[:heating_ok] ? 'unmet heating hours within 100 h for both buildings' : 'unmet heating hours EXCEED 100 h',
                     inputs: { proposed_h: status[:heat_p], reference_h: status[:heat_r], limit_h: 100 },
                     article: '8.4.1.2.(3)')
      if status[:cooling_vacuous]
        audit.decision(:compliance,
                       'sentence (4) is vacuous — the proposed building has no mechanical cooling ' \
                       '(the clause applies to thermal blocks "for which mechanical cooling is provided"; ' \
                       'explicit in the 2025 wording, applied consistently for 2020)',
                       inputs: { proposed_h: status[:cool_p], reference_h: status[:cool_r] },
                       article: '8.4.1.2.(4)')
      else
        audit.decision(:compliance,
                       status[:cooling_ok] ? 'unmet cooling hours within the allowance over reference' : 'unmet cooling hours EXCEED the allowance',
                       inputs: { proposed_h: status[:cool_p], reference_h: status[:cool_r],
                                 allowance_h: status[:allowance].round(1) },
                       article: '8.4.1.2.(4)')
      end

      unless status[:all_ok]
        iterations = (report['capacity_iterations'] || []).size
        audit.warn(:compliance,
                   "8.4.1.2.(5): unmet-hours limits still not met after #{iterations} capacity " \
                   'increase(s) — the building remains non-compliant; raise max_capacity_iterations, ' \
                   'increase capacity_step, or fix the design (hard-sized equipment does not respond ' \
                   'to sizing-factor increases).', article: '8.4.1.2.(5)')
      end
      status[:all_ok]
    end

    # The (3)/(4) arithmetic without audit side effects — shared by the formal
    # verdicts and the capacity-iteration loop.
    # (4): 2020 wording is +10% of reference; 2025's 8.4.5 path allows +10% or
    # 20 h, whichever is greater.
    def unmet_status(report, vintage)
      heat_p = report['proposed'].dig('unmet_occupied_hours', 'heating')
      heat_r = report['reference'].dig('unmet_occupied_hours', 'heating')
      cool_p = report['proposed'].dig('unmet_occupied_hours', 'cooling')
      cool_r = report['reference'].dig('unmet_occupied_hours', 'cooling')

      allowance = cool_r.to_f * 0.10
      allowance = [allowance, 20.0].max if vintage.to_s == '2025'
      heating_p_ok = !heat_p.nil? && heat_p <= HEATING_UNMET_LIMIT_H
      heating_r_ok = !heat_r.nil? && heat_r <= HEATING_UNMET_LIMIT_H

      # Sentence (4) applies to thermal blocks "for which mechanical cooling is
      # provided" (explicit in the 2025 wording; applied consistently for 2020) —
      # a proposed building without mechanical cooling accrues passive-overheating
      # "unmet cooling" hours that are NOT a cooling-capacity shortfall.
      cooling_vacuous = report['proposed']['mechanical_cooling'] == false
      cooling_ok = cooling_vacuous || (!cool_p.nil? && !cool_r.nil? && cool_p <= cool_r + allowance)
      indeterminate = [heat_p, heat_r].any?(&:nil?) ||
                      (!cooling_vacuous && [cool_p, cool_r].any?(&:nil?))

      { heat_p: heat_p, heat_r: heat_r, cool_p: cool_p, cool_r: cool_r,
        allowance: allowance, indeterminate: indeterminate,
        heating_p_ok: heating_p_ok, heating_r_ok: heating_r_ok,
        heating_ok: heating_p_ok && heating_r_ok,
        cooling_ok: cooling_ok, cooling_vacuous: cooling_vacuous,
        all_ok: heating_p_ok && heating_r_ok && cooling_ok }
    end

    # Any mechanical cooling in the model? (cooling coils, chillers, evaporative
    # coolers, district cooling, ideal-loads air systems)
    def mechanical_cooling?(model)
      pattern = /Coil_Cooling|CoilSystem_Cooling|Chiller|EvaporativeCooler|DistrictCooling|IdealLoadsAirSystem/
      model.modelObjects.any? { |o| o.iddObjectType.valueName.match?(pattern) }
    end

    # 8.4.1.2.(5): "the capacities of the primary and secondary systems of the
    # proposed building or the reference building, where applicable, shall be
    # incrementally increased until those loads are met." Sentences (3)/(4) are
    # written per THERMAL BLOCK, so the increase is targeted: each failing
    # building's failing ZONES (per-zone SystemSummary unmet hours from the
    # previous run) get their Sizing:Zone heating/cooling sizing factors
    # raised — the first bump by `step`, later bumps by secant extrapolation
    # from that zone's own (factor, unmet-hours) history, clamped per round so
    # the increase stays incremental. Zone factors override the global
    # SizingParameters factor and propagate into central equipment through the
    # coincident zone sums. When per-zone data is unavailable — or the building
    # gate fails without any single zone failing (facility hours are a union
    # over zones, not a sum) — the bump falls back to the global sizing
    # factors. The reference additionally gets its capacity-binned efficiencies
    # re-applied on the new sizes before its energy run. Bounded by
    # max_iterations; every bump is an audited decision and the history lands
    # in report['capacity_iterations'].
    HEATING_UNMET_LIMIT_H = 100.0    # 8.4.1.2.(3)
    SECANT_TARGET_FRACTION = 0.9     # aim below the limit so noise can't strand the last hour
    SECANT_MAX_STEP = 2.0            # per-round growth cap (never below the configured `step`)
    SECANT_MIN_IMPROVEMENT_H = 1.0   # observations closer than this can't support a slope

    def iterate_capacities(proposed, reference, report, vintage:, run_dir:, run_period:,
                           max_iterations:, step:, audit:)
      history = []
      report['capacity_iterations'] = history
      return if max_iterations.to_i <= 0

      zone_trace = {} # [label, zone, metric] => [[factor, unmet_hours], ...] across rounds
      max_iterations.times do |index|
        status = unmet_status(report, vintage)
        break if status[:all_ok]

        if status[:indeterminate]
          audit.warn(:compliance, 'unmet-hours data missing from SQL (no occupied hours?) — ' \
                                  'capacity iteration cannot assess convergence; stopping',
                     article: '8.4.1.2.(5)')
          break
        end

        iteration = index + 1
        bumps = {}
        bumps['proposed'] = { heating: !status[:heating_p_ok], cooling: !status[:cooling_ok] }
        bumps['reference'] = { heating: !status[:heating_r_ok], cooling: false }
        record = { 'iteration' => iteration, 'bumped' => {} }

        { 'proposed' => proposed, 'reference' => reference }.each do |label, model|
          bump = bumps[label]
          next unless bump[:heating] || bump[:cooling]

          audit.with_building("#{label} building") do
            factors = bump_capacities(model, label, report, bump, vintage, step: step, trace: zone_trace)
            record['bumped'][label] = factors
            summary = case factors['mode']
                      when 'zonal'
                        "capacity increase #{iteration}: #{label} — sizing factor(s) raised on " \
                        "#{factors['zones'].size} failing thermal block(s), secant-targeted from the " \
                        'previous run(s) — building re-sized and re-run'
                      when 'mixed'
                        "capacity increase #{iteration}: #{label} — sizing factor(s) raised on " \
                        "#{factors['zones'].size} failing thermal block(s), plus a global bump for the " \
                        'gate no single zone explains — building re-sized and re-run'
                      else
                        "capacity increase #{iteration}: #{label} #{bump.select { |_, v| v }.keys.join('+')} " \
                        'GLOBAL sizing factor(s) raised (per-zone attribution unavailable) — ' \
                        'building re-sized and re-run'
                      end
            inputs = { building: label, step: step, iteration: iteration, mode: factors['mode'] }
                     .merge(factors.slice('heating_sizing_factor', 'cooling_sizing_factor'))
            if factors['zones']
              inputs[:zones_bumped] = factors['zones'].size
              inputs[:zones] = factors['zones'].first(8).to_h
            end
            inputs[:global] = factors['global'] if factors['global']
            audit.decision(:compliance, summary, inputs: inputs, article: '8.4.1.2.(5)', ruling: 'D-43')

            dir = File.join(run_dir, "#{label}_annual_iter#{iteration}")
            if label == 'reference'
              # size on the new factors FIRST so efficiencies re-bin on the new
              # capacities, then run the energy simulation. Release the values
              # the previous efficiency pass hard-set against the OLD sizes
              # first — a frozen pump power against a freshly grown autosized
              # flow is an EnergyPlus input FATAL, not a modeling nuance.
              OpenStudioHVAC::NECB.prepare_for_resizing(model, audit: audit)
              Runner.run_energyplus!(model, "#{dir}_sizing", sizing_only: true)
              OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: vintage, audit: audit, proposed: proposed)
            end
            run_annual(model, dir, run_period, report[label])
          end
        end

        record['unmet_after'] = { 'proposed' => report['proposed']['unmet_occupied_hours'],
                                  'reference' => report['reference']['unmet_occupied_hours'] }
        history << record

        # Stall detection: a bump that produced no improvement (>= 1 h) means the
        # equipment is not responding to sizing factors (hard-sized, or the gate
        # fails for equipment that does not exist) — iterating further is futile.
        after = unmet_status(report, vintage)
        improvements = []
        improvements << (status[:heat_p].to_f - after[:heat_p].to_f) if bumps['proposed'][:heating]
        improvements << (status[:cool_p].to_f - after[:cool_p].to_f) if bumps['proposed'][:cooling]
        improvements << (status[:heat_r].to_f - after[:heat_r].to_f) if bumps['reference'][:heating]
        next if after[:all_ok] || improvements.any? { |i| i >= 1.0 }

        audit.warn(:compliance,
                   "capacity iteration #{iteration} produced no unmet-hours improvement — the failing " \
                   'equipment is not responding to sizing-factor increases (hard-sized capacity, or the ' \
                   'gate concerns equipment the building does not have); stopping', article: '8.4.1.2.(5)',
                   ruling: 'D-43')
        record['stalled'] = true
        break
      end

      final = unmet_status(report, vintage)
      return unless history.any? && final[:all_ok]

      audit.info(:compliance,
                 "capacity iteration converged after #{history.size} increase(s) — unmet-hours loads are met",
                 inputs: { iterations: history.size }, article: '8.4.1.2.(5)')
    end

    # One building's sentence-(5) increase for one round: per-zone Sizing:Zone
    # factors on the failing thermal blocks when the previous run's per-zone
    # unmet hours can attribute the failure, global SizingParameters otherwise.
    # Returns the history record ('mode', headline factors, per-zone factors).
    def bump_capacities(model, label, report, bump, vintage, step:, trace:)
      targets = failing_zone_targets(label, report, bump, vintage)
      zone_hours = report[label]['zone_unmet_occupied_hours'] || {}
      sizing = model.getSizingParameters
      by_name = model.getThermalZones.to_h { |z| [z.nameString.upcase, z] }

      zones_record = {}
      targets.each do |zone_key, metrics|
        zone = by_name[zone_key.upcase]
        next unless zone

        sizing_zone = zone.sizingZone
        metrics.each do |metric, target_h|
          existing = metric == :heating ? sizing_zone.zoneHeatingSizingFactor : sizing_zone.zoneCoolingSizingFactor
          global = metric == :heating ? sizing.heatingSizingFactor : sizing.coolingSizingFactor
          current_f = existing.is_initialized ? existing.get : global
          current_h = zone_hours.dig(zone_key, metric.to_s).to_f
          key = [label, zone_key, metric]
          new_f = next_sizing_factor(trace[key] ||= [], current_f, current_h, target_h, step)
          trace[key] << [current_f, current_h]
          if metric == :heating
            sizing_zone.setZoneHeatingSizingFactor(new_f)
          else
            sizing_zone.setZoneCoolingSizingFactor(new_f)
          end
          (zones_record[zone_key] ||= {})["#{metric}_sizing_factor"] = new_f.round(3)
        end
      end

      if zones_record.empty?
        return bump_sizing_factors(model, step, heating: bump[:heating], cooling: bump[:cooling])
               .merge('mode' => 'global')
      end

      result = { 'mode' => 'zonal', 'zones' => zones_record }
      %w[heating cooling].each do |metric|
        max = zones_record.values.filter_map { |v| v["#{metric}_sizing_factor"] }.max
        result["#{metric}_sizing_factor"] = max if max
      end

      # A gate can fail with no single zone failing (facility hours are a union
      # over zones) — that gate still needs its increase, globally. Zone factors
      # OVERRIDE the global one, so already-bumped zones are unaffected.
      covered = zones_record.values.flat_map(&:keys)
      global_heating = bump[:heating] && !covered.include?('heating_sizing_factor')
      global_cooling = bump[:cooling] && !covered.include?('cooling_sizing_factor')
      if global_heating || global_cooling
        result['mode'] = 'mixed'
        result['global'] = bump_sizing_factors(model, step, heating: global_heating, cooling: global_cooling)
      end
      result
    end

    # Which zones does the previous run blame, and what unmet-hours value should
    # the next run steer each one toward? Heating (sentence (3)): any zone over
    # 100 h in a building whose heating gate failed. Cooling (sentence (4),
    # proposed only): any zone whose unmet cooling exceeds the SAME zone of the
    # reference (a clone — zone names match) plus the vintage allowance.
    # Targets sit at SECANT_TARGET_FRACTION of the applicable limit so the
    # extrapolation lands safely inside it, not on its edge.
    def failing_zone_targets(label, report, bump, vintage)
      zones = report[label]['zone_unmet_occupied_hours'] || {}
      return {} if zones.empty?

      ref_zones = report['reference']['zone_unmet_occupied_hours'] || {}
      targets = {}
      zones.each do |zone, hours|
        if bump[:heating] && hours['heating'].to_f > HEATING_UNMET_LIMIT_H
          (targets[zone] ||= {})[:heating] = HEATING_UNMET_LIMIT_H * SECANT_TARGET_FRACTION
        end
        next unless bump[:cooling]

        ref_h = ref_zones.dig(zone, 'cooling').to_f
        allowance = ref_h * 0.10
        allowance = [allowance, 20.0].max if vintage.to_s == '2025'
        if hours['cooling'].to_f > ref_h + allowance
          (targets[zone] ||= {})[:cooling] = (ref_h + allowance) * SECANT_TARGET_FRACTION
        end
      end
      targets
    end

    # Secant step on this zone/metric's own (factor, unmet-hours) history: once
    # a previous observation with a real slope exists, extrapolate the factor
    # that lands the hours on the target; otherwise (first bump, or a flat /
    # perverse slope) fall back to the geometric `step`. The result is clamped
    # per round — growth capped at max(step, SECANT_MAX_STEP)x — so the
    # increase stays incremental, as sentence (5) is worded.
    def next_sizing_factor(history, current_f, current_h, target_h, step)
      previous = history.reverse_each.find do |f, h|
        (current_f - f).abs > 1e-6 && (h - current_h).abs >= SECANT_MIN_IMPROVEMENT_H
      end
      if previous
        slope = (current_h - previous[1]) / (current_f - previous[0])
        if slope.negative?
          candidate = current_f + (target_h - current_h) / slope
          return candidate.clamp(current_f, current_f * [step, SECANT_MAX_STEP].max)
        end
      end
      current_f * step
    end

    def bump_sizing_factors(model, step, heating:, cooling:)
      sizing = model.getSizingParameters
      result = {}
      if heating
        sizing.setHeatingSizingFactor(sizing.heatingSizingFactor * step)
        result['heating_sizing_factor'] = sizing.heatingSizingFactor.round(3)
      end
      if cooling
        sizing.setCoolingSizingFactor(sizing.coolingSizingFactor * step)
        result['cooling_sizing_factor'] = sizing.coolingSizingFactor.round(3)
      end
      result
    end

    def cost_models(proposed, reference, report, city:, province_state:, costs_csv:, audit:)
      { 'proposed' => proposed, 'reference' => reference }.each do |label, model|
        audit.with_building("#{label} building") do
          hvac = OpenStudioHVAC.cost(model, city: city, province_state: province_state,
                                     costs_csv: costs_csv, audit: audit)
          envelope = OpenStudioEnvelope.cost(model, city: hvac.city, province_state: hvac.province_state,
                                             costs_csv: costs_csv, audit: audit)
          report[label]['cost'] = {
            'hvac' => hvac.total, 'envelope' => envelope.total,
            'total' => (hvac.total + envelope.total).round(2),
            'city' => hvac.city, 'province_state' => hvac.province_state
          }
        end
      end
      delta = report['proposed'].dig('cost', 'total') - report['reference'].dig('cost', 'total')
      report['incremental_cost_proposed_vs_reference'] = delta.round(2)
      audit.decision(:compliance, 'both models costed (HVAC + envelope) in the shared audit',
                     inputs: { proposed_total: report['proposed'].dig('cost', 'total'),
                               reference_total: report['reference'].dig('cost', 'total') },
                     value: "incremental (proposed - reference) $#{delta.round(2)}")
    end

    # Completeness accounting for the umbrella's OWN manifest (same contract as
    # the five domain gems' emit_article_coverage): every declared article lands
    # in the audit with its status. partial/not_implemented warn — EXCEPT
    # entries flagged gap_owner: "modeller", whose remaining gaps are wholly the
    # modeller's responsibility: those emit as info scope notes instead, so the
    # AHJ report is not permanently stamped with warnings no model change can
    # clear (project decision D-09, openstudio-necb/docs/necb_decisions.md). Emitted at the end
    # of the happy path only — a crash flush must not assert coverage.
    def emit_article_coverage(vintage, audit)
      path = File.expand_path("data/necb/necb_rules_#{vintage}.json", __dir__)
      return unless File.exist?(path)

      coverage = JSON.parse(File.read(path))['article_coverage']
      return if coverage.nil?

      cited = Hash.new(0)
      audit.entries.each { |e| e[:article].to_s.scan(/\d+\.\d+(?:\.\d+)*\./) { |a| cited[a] += 1 } }
      coverage['articles'].each do |art|
        applied = cited.select { |a, _| a.start_with?(art['article'].to_s.sub(/\.\z/, '').sub(/\(\d+\).*/, '')) }.values.sum
        inputs = { status: art['status'], decisions_citing: applied }
        inputs[:gap_owner] = art['gap_owner'] if art['gap_owner']
        if %w[implemented satisfied_by_clone host_scope].include?(art['status'])
          audit.info(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}#{art['how'] ? ": #{art['how']}" : ''}",
                     inputs: inputs, article: art['article'])
        elsif art['gap_owner'] == 'modeller'
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

    def write_outputs(run_dir, report, audit)
      File.write(File.join(run_dir, 'report.json'), JSON.pretty_generate(report))
      File.write(File.join(run_dir, 'audit.json'), audit.to_json)
      File.write(File.join(run_dir, 'audit.txt'), audit.to_s)
    end

    # On any failure mid-run, record the abort in the audit and flush the audit
    # trail + whatever partial report exists to run_dir, so a broken proposed
    # (which aborts before the reference is even built) still leaves diagnostics
    # behind. The caller re-raises the original error afterwards.
    def flush_on_failure(run_dir, report, audit, error)
      audit.warn(:compliance, "run ABORTED before completion: #{error.class}: #{error.message}",
                 inputs: { error_class: error.class.to_s }, article: '8.4.2.1.')
      write_outputs(run_dir, report, audit)
    rescue StandardError
      # never let a write failure mask the original error
      nil
    end

    # The 8.4.4 supplement verdict on a reference-path run. Returns the
    # report['eui_path'] hash. See the call site for the check-first contract.
    def eui_supplement_verdict(proposed, options, hdd, report, run_dir, run_period, vintage, audit)
      opts = options.transform_keys(&:to_sym)
      mapping = opts[:archetypes] or
        raise(ArgumentError, 'eui_supplement requires archetypes: {archetype => :all | [space names]}')
      resolved = Archetypes.resolve!(proposed, mapping, audit: audit)
      problems = Archetypes.applicability_problems(resolved, hdd: hdd, audit: audit)
      unless problems.empty?
        audit.warn(:compliance, 'EUI supplement NOT COMPUTED — outside 8.4.4 applicability', article: '8.4.4.1.(1)',
                   ruling: 'D-04')
        return { 'computed' => false, 'reason' => "outside 8.4.4 applicability: #{problems.join('; ')}" }
      end

      target = Tiers.eui_building_energy_target(Archetypes.bet_areas(resolved, audit: audit),
                                                resolved[:total_area_m2], hdd: hdd,
                                                process_loads_kwh: opts[:process_loads_kwh] || 0.0, audit: audit)
      check = Archetypes.conformance(proposed, resolved, vintage: vintage, audit: audit)
      if check[:conformant]
        proposed_kwh = report['proposed']['total_site_kwh']
        source = 'as-specified annual run (proposed conforms to Table 8.4.4.2 — one run serves both paths)'
      elsif opts[:run_normalized]
        normalized = proposed.clone(true).to_Model
        audit.with_building('proposed building (EUI-normalized)') do
          Archetypes.normalize!(normalized, Archetypes.resolve!(normalized, mapping, audit: audit),
                                vintage: vintage, audit: audit)
        end
        eui_results = {}
        run_annual(normalized, File.join(run_dir, 'proposed_eui_annual'), run_period, eui_results)
        proposed_kwh = eui_results['total_site_kwh']
        report['proposed_eui_normalized'] = eui_results
        source = 'separate annual run of the Table-8.4.4.2-normalized proposed'
      else
        audit.warn(:compliance,
                   'EUI supplement NOT COMPUTED — the proposed does not conform to Table 8.4.4.2, so the ' \
                   'reference-path annual result cannot lawfully serve the 8.4.4 verdict (pass ' \
                   'eui_supplement: {run_normalized: true} to run the normalized proposed)',
                   article: '8.4.4.2.(1)', ruling: 'D-04')
        return { 'computed' => false,
                 'reason' => 'proposed does not conform to Table 8.4.4.2 (run_normalized not requested)',
                 'mismatches' => check[:mismatches].first(50) }
      end

      eui_ok = proposed_kwh <= target['bet_kwh']
      audit.decision(:compliance,
                     eui_ok ? 'proposed ALSO meets the archetype-EUI building energy target (8.4.4 path)' \
                            : 'proposed does NOT meet the archetype-EUI target (8.4.4 path)',
                     inputs: { proposed_kwh: proposed_kwh, bet_kwh: target['bet_kwh'], basis: source },
                     article: '8.4.4.1.(2); 8.4.4.2.(1)', ruling: 'D-04')
      { 'computed' => true, 'bet_kwh' => target['bet_kwh'], 'compliant' => eui_ok,
        'basis' => source, 'lines' => target['lines'] }
        .merge(Tiers.energy_tier(proposed_kwh, target['bet_kwh']))
    end

    # Pre-flight gate for the reference path: every space that counts toward
    # floor area (and is not a plenum) must carry standards tags that resolve
    # against the NECB space-type catalog. Warns per unresolvable type, then
    # raises with the full list and nearest-name suggestions. Runs BEFORE any
    # simulation or transform, so a mistagged model fails in milliseconds with
    # actionable names instead of producing a silently-wrong determination.
    def validate_space_types!(proposed, vintage, audit)
      data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
      problems = {}
      proposed.getSpaces.sort_by(&:nameString).each do |space|
        next unless space.partofTotalFloorArea

        space_type = space.spaceType.empty? ? nil : space.spaceType.get
        name = space_type ? space_type.nameString : '(no space type)'
        next if name.downcase.include?('plenum')

        bt = space_type&.standardsBuildingType&.then { |o| o.is_initialized ? o.get : nil }
        st = space_type&.standardsSpaceType&.then { |o| o.is_initialized ? o.get : nil }
        st = nil if st&.downcase&.include?('plenum')
        record = bt && st && OpenStudioLoads::NECB::SpaceTypes.find(building_type: bt, space_type: st,
                                                                    vintage: data_vintage)
        next unless record.nil? || OpenStudioLoads::NECB::SpaceTypes.undefined?(record)

        (problems[[name, bt, st]] ||= []) << space.nameString
      end
      return if problems.empty?

      catalog = OpenStudioLoads::NECB.table(data_vintage, 'space_types')
      lines = problems.map do |(name, bt, st), spaces|
        audit.warn(:compliance,
                   "space type '#{name}' [#{bt.inspect}, #{st.inspect}] is UNRESOLVABLE against the NECB " \
                   "#{data_vintage} catalog — lighting/loads/SHW rules cannot be established for " \
                   "#{spaces.size} space(s)",
                   target: spaces.join(', '), article: '8.4.3.1.(2); 4.2.1.6.', ruling: 'D-02')
        hint = if st
                 suggestions = suggest_space_types(st, catalog)
                 suggestions.empty? ? '' : " — did you mean: #{suggestions.join(' | ')}?"
               else
                 ' — untagged: run the loads on-ramp (necb_loads:/assign_space_types) or set ' \
                 'standardsBuildingType + standardsSpaceType to NECB catalog names'
               end
        "'#{name}' [#{bt.inspect}, #{st.inspect}] (#{spaces.size} space(s))#{hint}"
      end
      raise(ArgumentError,
            "pre-flight FAILED: #{problems.size} space type(s) do not resolve against the NECB #{data_vintage} " \
            "space-type catalog, so the reference building cannot be generated correctly (unmatched types " \
            "silently keep the proposed's lighting/loads, waiving the allowances):\n  #{lines.join("\n  ")}")
    end

    # Deterministic nearest-name hints: token overlap against catalog space
    # types, best three. Suggestion ONLY — auto-resolution was rejected because
    # 12 catalog pairs differ solely by a size threshold no string metric can
    # choose between.
    def suggest_space_types(name, catalog)
      tokens = name.downcase.scan(/[a-z0-9]+/) - %w[m2 sch]
      return [] if tokens.empty?

      catalog.map { |row| row['space_type'].to_s }
             .uniq
             .map { |cand| [cand, (tokens & cand.downcase.scan(/[a-z0-9]+/)).size] }
             .select { |_, score| score.positive? }
             .max_by(3) { |cand, score| [score, -cand.length] }
             .map { |cand, _| "'#{cand}'" }
    end
  end
end
