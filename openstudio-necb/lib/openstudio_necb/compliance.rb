require 'json'

module OpenStudioNECB
  # The NECB Part 8 performance path (Division B, 8.4.1.2, identical intent in
  # 2020 and 2025):
  #   (2) annual energy consumption of the PROPOSED building shall not exceed the
  #       building energy target of the REFERENCE building
  #   (3) unmet heating hours <= 100 h/year for both buildings
  #   (4) unmet cooling hours: proposed within +10% of reference (2025 8.4.4 path:
  #       proposed <= 100 h; 8.4.5 path: within +10% or 20 h, whichever is greater)
  #   (5) where (3)/(4) fail, capacities shall be incrementally increased — this
  #       pipeline REPORTS the failure (loud warning); it does not auto-iterate.
  #
  # One clone, one audit: reference_hvac (openstudio-hvac) then reference_envelope
  # (openstudio-envelope) transform a single reference model, and optional costing
  # of both models lands in the same AuditLog.
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
    def performance_compliance(model, vintage: '2020', weather: {}, building: nil,
                               hdd: nil, run_dir:, simulate: :annual, run_period: nil,
                               costing: false, city: nil, province_state: nil,
                               costs_csv: nil, thermal_bridging: nil,
                               actual_roof_absorptance_used: false, audit: nil)
      audit ||= AuditLog.new
      FileUtils.mkdir_p(run_dir)
      proposed = load_model(model)
      audit.decision(:compliance, 'performance-path run started',
                     inputs: { vintage: vintage, simulate: simulate, costing: costing },
                     article: '8.4.1.2.(1)')

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
      reference_result = OpenStudioHVAC::NECB.reference_hvac(proposed, vintage: vintage,
                                                             building: building, audit: audit)
      reference = reference_result.model
      OpenStudioEnvelope::NECB.reference_envelope(reference, vintage: vintage, hdd: hdd,
                                                  actual_roof_absorptance_used: actual_roof_absorptance_used,
                                                  thermal_bridging: thermal_bridging, audit: audit)

      # 3. size the reference, then re-apply efficiencies on sized equipment
      #    (the openstudio-hvac contract: efficiency rows are capacity-binned)
      if simulate != :none
        Runner.run_energyplus!(reference, File.join(run_dir, 'reference_sizing'), sizing_only: true)
        OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: vintage, audit: audit)
        audit.info(:compliance, 'reference sized; efficiencies re-applied on sized capacities',
                   target: 'reference')
      end

      report = { 'vintage' => vintage, 'hdd' => hdd, 'simulate' => simulate.to_s,
                 'proposed' => {}, 'reference' => {} }
      compliant = nil

      # 4. the energy comparison (8.4.1.2.(2)-(4))
      if simulate == :annual
        run_annual(proposed, File.join(run_dir, 'proposed_annual'), run_period, report['proposed'])
        run_annual(reference, File.join(run_dir, 'reference_annual'), run_period, report['reference'])
        compliant = evaluate(report, vintage, run_period, audit)
      elsif simulate == :sizing
        audit.info(:compliance, 'simulate: :sizing — both models generated and sized; ' \
                                'no energy comparison performed (compliance undetermined)')
      end

      # 5. unified costing of BOTH models (same audit)
      cost_models(proposed, reference, report, city: city, province_state: province_state,
                  costs_csv: costs_csv, audit: audit) if costing

      report['compliant'] = compliant
      report['warnings'] = audit.warnings.map { |w| w[:action] }
      write_outputs(run_dir, report, audit)
      ComplianceResult.new(proposed_model: proposed, reference_model: reference,
                           report: report, audit: audit, compliant: compliant, run_dir: run_dir)
    end

    def load_model(model)
      return OpenStudio::Model::Model.load(OpenStudio::Path.new(model)).get if model.is_a?(String)

      # never mutate the caller's model — the pipeline sizes/simulates its own copy
      model.clone(true).to_Model
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
      heat_p = report['proposed'].dig('unmet_occupied_hours', 'heating')
      heat_r = report['reference'].dig('unmet_occupied_hours', 'heating')
      cool_p = report['proposed'].dig('unmet_occupied_hours', 'cooling')
      cool_r = report['reference'].dig('unmet_occupied_hours', 'cooling')

      heating_ok = !heat_p.nil? && !heat_r.nil? && heat_p <= 100.0 && heat_r <= 100.0
      audit.decision(:compliance, heating_ok ? 'unmet heating hours within 100 h for both buildings' : 'unmet heating hours EXCEED 100 h',
                     inputs: { proposed_h: heat_p, reference_h: heat_r, limit_h: 100 },
                     article: '8.4.1.2.(3)')

      # (4): 2020 wording is +10% of reference; 2025's 8.4.5 path allows +10% or
      # 20 h, whichever is greater
      allowance = cool_r.to_f * 0.10
      allowance = [allowance, 20.0].max if vintage.to_s == '2025'
      cooling_ok = !cool_p.nil? && !cool_r.nil? && cool_p <= cool_r + allowance
      audit.decision(:compliance, cooling_ok ? 'unmet cooling hours within the allowance over reference' : 'unmet cooling hours EXCEED the allowance',
                     inputs: { proposed_h: cool_p, reference_h: cool_r, allowance_h: allowance.round(1) },
                     article: '8.4.1.2.(4)')

      unless heating_ok && cooling_ok
        audit.warn(:compliance, '8.4.1.2.(5): unmet-hours limits not met — primary/secondary system capacities ' \
                                'shall be incrementally increased until loads are met. This pipeline reports the ' \
                                'condition; it does not auto-iterate capacities.', article: '8.4.1.2.(5)')
      end
      heating_ok && cooling_ok
    end

    def cost_models(proposed, reference, report, city:, province_state:, costs_csv:, audit:)
      { 'proposed' => proposed, 'reference' => reference }.each do |label, model|
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
  end
end
