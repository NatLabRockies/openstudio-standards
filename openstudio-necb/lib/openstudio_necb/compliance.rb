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
  #       as an iteration loop on the failing building's global sizing factors
  #       (SizingParameters), bounded by max_capacity_iterations; a still-failing
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
    # @param capacity_step [Float] multiplier applied to the failing building's
    #   heating/cooling sizing factor per iteration
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
    # @param archetype_areas [Hash{String=>Numeric,nil}] :eui path only —
    #   archetype => floor area m2 (nil = remainder of the model's floor area)
    # @param process_loads_kwh [Numeric] :eui path PL term (8.4.4.1.(2))
    def performance_compliance(model, vintage: '2020', weather: {}, building: nil,
                               hdd: nil, run_dir:, simulate: :annual, run_period: nil,
                               costing: false, city: nil, province_state: nil,
                               costs_csv: nil, thermal_bridging: nil,
                               actual_roof_absorptance_used: false,
                               max_capacity_iterations: 3, capacity_step: 1.25,
                               necb_loads: nil, reference_daylighting: false,
                               path: :reference, archetype_areas: nil,
                               process_loads_kwh: 0.0, eui_supplement: nil,
                               report_html: false, report_options: {}, audit: nil)
      if path == :eui
        raise(ArgumentError, 'the archetype-EUI path is a NECB 2025 feature (vintage: 2025)') unless vintage.to_s == '2025'
        raise(ArgumentError, ':eui path requires archetype_areas: {archetype => m2 or nil}') if archetype_areas.nil?

        return eui_compliance(model, vintage: vintage, weather: weather, hdd: hdd,
                              run_dir: run_dir, simulate: simulate, run_period: run_period,
                              archetype_areas: archetype_areas, process_loads_kwh: process_loads_kwh,
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
                                'and capacity-binned efficiencies fall back with warnings')
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
          OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: vintage, audit: audit)
          audit.info(:compliance, 'reference sized; efficiencies re-applied on sized capacities',
                     target: 'reference')
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

      # eui_supplement (2025): the 8.4.4 archetype-EUI verdict computed AGAINST
      # THE SAME proposed annual result — one run, both compliance paths.
      if eui_supplement && vintage.to_s == '2025' && report['proposed']['total_site_kwh']
        supplement_target = Tiers.eui_building_energy_target(
          eui_supplement[:archetype_areas] || eui_supplement['archetype_areas'],
          proposed.getBuilding.floorArea, hdd: hdd,
          process_loads_kwh: eui_supplement[:process_loads_kwh] || 0.0, audit: audit)
        proposed_kwh = report['proposed']['total_site_kwh']
        eui_ok = proposed_kwh <= supplement_target['bet_kwh']
        audit.decision(:compliance,
                       eui_ok ? 'proposed ALSO meets the archetype-EUI building energy target (8.4.4 path)' : 'proposed does NOT meet the archetype-EUI target (8.4.4 path)',
                       inputs: { proposed_kwh: proposed_kwh, bet_kwh: supplement_target['bet_kwh'] },
                       article: '8.4.4.1.(2)')
        report['eui_path'] = { 'bet_kwh' => supplement_target['bet_kwh'],
                               'compliant' => eui_ok, 'lines' => supplement_target['lines'] }
                             .merge(Tiers.energy_tier(proposed_kwh, supplement_target['bet_kwh']))
      end

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
    # is generated or simulated. Compliance: proposed annual consumption <= BET;
    # the Section 10 tier is computed against the same BET.
    def eui_compliance(model, vintage:, weather:, hdd:, run_dir:, simulate:, run_period:,
                       archetype_areas:, process_loads_kwh:, costing:, city:,
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
                     inputs: { vintage: vintage, archetypes: archetype_areas.keys },
                     article: '8.4.4.1.')

      audit.building = 'proposed building'
      if simulate != :none
        %i[epw ddy].each { |k| raise(ArgumentError, "weather[:#{k}] required") unless weather[k] }
        Runner.attach_weather!(proposed, epw: weather[:epw], ddy: weather[:ddy])
      end
      hdd ||= OpenStudioEnvelope::Climate.hdd18(proposed, audit: audit)
      audit.building = nil # BET derivation + verdicts are comparisons, not model work

      report = { 'vintage' => vintage, 'hdd' => hdd, 'simulate' => simulate.to_s,
                 'path' => 'eui', 'proposed' => {}, 'reference' => {} }
      target = Tiers.eui_building_energy_target(archetype_areas, proposed.getBuilding.floorArea,
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
      heating_p_ok = !heat_p.nil? && heat_p <= 100.0
      heating_r_ok = !heat_r.nil? && heat_r <= 100.0

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
    # incrementally increased until those loads are met." Each failing building's
    # global sizing factor (heating and/or cooling, whichever gate fails) is
    # multiplied by `step` and the building re-sized and re-run; the reference
    # additionally gets its capacity-binned efficiencies re-applied on the new
    # sizes before its energy run. Bounded by max_iterations; every bump is an
    # audited decision and the history lands in report['capacity_iterations'].
    def iterate_capacities(proposed, reference, report, vintage:, run_dir:, run_period:,
                           max_iterations:, step:, audit:)
      history = []
      report['capacity_iterations'] = history
      return if max_iterations.to_i <= 0

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
            factors = bump_sizing_factors(model, step, heating: bump[:heating], cooling: bump[:cooling])
            record['bumped'][label] = factors
            audit.decision(:compliance,
                           "capacity increase #{iteration}: #{label} #{bump.select { |_, v| v }.keys.join('+')} " \
                           'sizing factor(s) raised — building re-sized and re-run',
                           inputs: { building: label, step: step, iteration: iteration }.merge(factors),
                           article: '8.4.1.2.(5)')

            dir = File.join(run_dir, "#{label}_annual_iter#{iteration}")
            if label == 'reference'
              # size on the new factors FIRST so efficiencies re-bin on the new
              # capacities, then run the energy simulation
              Runner.run_energyplus!(model, "#{dir}_sizing", sizing_only: true)
              OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: vintage, audit: audit)
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
                   'gate concerns equipment the building does not have); stopping', article: '8.4.1.2.(5)')
        record['stalled'] = true
        break
      end

      final = unmet_status(report, vintage)
      return unless history.any? && final[:all_ok]

      audit.info(:compliance,
                 "capacity iteration converged after #{history.size} increase(s) — unmet-hours loads are met",
                 inputs: { iterations: history.size }, article: '8.4.1.2.(5)')
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
                   target: spaces.join(', '), article: '8.4.3.1.(2); 4.2.1.6.')
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
