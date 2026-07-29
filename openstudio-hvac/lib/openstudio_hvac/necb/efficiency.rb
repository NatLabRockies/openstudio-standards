require 'json'
require 'date'

module OpenStudioHVAC
  module NECB
    # Vintage efficiency application — a faithful, SDK-only port of the NECB subset of
    # openstudio-standards' model_apply_hvac_efficiency_standard, driven entirely by the
    # vendored data/necb/efficiencies_<vintage>.json (NECB Table 5.2.12.1 values +
    # performance curves).
    #
    # Covered components: hot-water boilers (incl. NECB primary/secondary staging),
    # electric chillers (incl. 2100 kW split + cooling-tower sizing rules), single-speed
    # DX cooling and heating coils, gas heating coils, VAV fan power curves (8.4.4.17)
    # and hydronic pump power (8.4.4.14: Table curves + proposed W/(L/s) transfer when
    # a proposed model is supplied). Reference-model fans get their explicit 8.4.4.18
    # static pressure/efficiency values in the reference transform; motor-table
    # application remains host-side.
    #
    # Requires a SIZED model (capacities read from hard or autosized values).
    module Efficiency
      module_function

      def data(vintage)
        @data ||= {}
        @data[vintage.to_s] ||= begin
          path = File.join(RULES_DIR, "efficiencies_#{vintage}.json")
          raise(ArgumentError, "no NECB efficiency data for vintage '#{vintage}' (expected #{path})") unless File.exist?(path)

          JSON.parse(File.read(path))
        end
      end

      # The efficiency vintage to actually apply: the requested vintage when its tables
      # are vendored, else the fallback its rules file declares (e.g. NECB 2025 falls
      # back to 2020 until the restructured Table 5.2.12.1 series is transcribed).
      # @return [Array(String, String or nil)] [effective vintage, fallback reason or nil]
      def effective_vintage(vintage)
        return [vintage.to_s, nil] if File.exist?(File.join(RULES_DIR, "efficiencies_#{vintage}.json"))

        provenance = NECB.rules(vintage)['provenance']
        fallback = provenance['efficiency_vintage_fallback']
        raise(ArgumentError, "no NECB efficiency data for vintage '#{vintage}' and no declared fallback") if fallback.nil?

        [fallback.to_s, provenance['efficiency_fallback_reason'] || "vintage #{vintage} tables not vendored"]
      end

      # Apply NECB minimum-performance values + curves to every supported component.
      # @param model [OpenStudio::Model::Model] sized model
      # @param vintage [String] e.g. '2020'
      # @param audit [AuditLog, nil]
      def apply(model, vintage: '2020', audit: nil, proposed: nil)
        requested_vintage = vintage.to_s
        vintage, fallback_reason = effective_vintage(vintage)
        if fallback_reason
          audit&.warn(:efficiency, "efficiency tables fall back to NECB #{vintage} values: #{fallback_reason}",
                      article: 'Table 5.2.12.1')
        end
        tables = data(vintage)
        # Boiler/chiller staging thresholds (8.4.4.9.(6)/8.4.4.10.(6)) live in the
        # reference ruleset (heating_plant/cooling_plant), not the efficiencies table —
        # fetched by the originally requested vintage since reference_rules_<vintage>.json
        # is vendored for every supported vintage (no efficiency-style fallback needed).
        plant_rules = NECB.rules(requested_vintage)
        heating_plant = plant_rules.fetch('heating_plant')
        cooling_plant = plant_rules.fetch('cooling_plant')
        model.getBoilerHotWaters.sort_by(&:nameString).each { |b| apply_boiler(b, tables, heating_plant, audit) }
        model.getChillerElectricEIRs.sort_by(&:nameString).each { |c| apply_chiller(c, tables, cooling_plant, audit) }
        apply_tower_rules(model, audit) # after ALL chiller capacities are final — the tower sees the loop SUM
        # 8.4.4.9.(7)/8.4.4.10.(8) stage COUNTS first: the multispeed appliers bin
        # by TOP-stage capacity, and the top stage is unchanged by re-staging, but
        # the per-stage values must land on the stages the staging pass leaves behind.
        totals = apply_staging(model, plant_rules, requested_vintage, audit)
        model.getCoilCoolingDXSingleSpeeds.sort_by(&:nameString).each { |c| apply_dx_cooling(c, tables, audit) }
        model.getCoilCoolingDXMultiSpeeds.sort_by(&:nameString).each { |c| apply_dx_cooling_multi(c, tables, audit, totals[c.handle.to_s]) }
        model.getCoilHeatingDXSingleSpeeds.sort_by(&:nameString).each { |c| apply_dx_heating(c, tables, audit) }
        model.getCoilHeatingDXMultiSpeeds.sort_by(&:nameString).each { |c| apply_dx_heating_multi(c, tables, audit, totals[c.handle.to_s]) }
        model.getCoilHeatingGass.sort_by(&:nameString).each { |c| apply_gas_coil(c, tables, audit) }
        model.getCoilHeatingGasMultiStages.sort_by(&:nameString).each { |c| apply_gas_multi(c, tables, audit, totals[c.handle.to_s]) }
        model.getFanVariableVolumes.sort_by(&:nameString).each { |f| apply_fan_power_curve(f, vintage, audit) }
        apply_pump_rules(model, requested_vintage, plant_rules['hydronic_pumps'], audit, proposed: proposed)
        align_heat_pump_heating_capacity(model, audit)
        audit&.info(:efficiency, 'NECB efficiency pass complete',
                    inputs: { vintage: vintage,
                              boilers: model.getBoilerHotWaters.size,
                              chillers: model.getChillerElectricEIRs.size,
                              dx_cooling: model.getCoilCoolingDXSingleSpeeds.size,
                              dx_cooling_staged: model.getCoilCoolingDXMultiSpeeds.size,
                              dx_heating: model.getCoilHeatingDXSingleSpeeds.size,
                              dx_heating_staged: model.getCoilHeatingDXMultiSpeeds.size,
                              gas_coils: model.getCoilHeatingGass.size,
                              gas_coils_staged: model.getCoilHeatingGasMultiStages.size })
        true
      end

      # ---------------- 8.4.4.9.(7) / 8.4.4.10.(8) staged heating and cooling ----------------

      # The EnergyPlus structural ceiling: both Coil:Cooling:DX:MultiSpeed and
      # Coil:Heating:Gas:MultiStage refuse a fifth stage (probe-verified on the
      # SDK — addStage returns false), so a system needing more equal stages
      # than this is clamped, loudly (D-47).
      MAX_STAGES = 4

      # Post-sizing stage-COUNT pass. Sentence (7)/(8) read the same way: at or
      # below the two-stage threshold the equipment is modelled as two equal
      # stages; above it, as equal stages of the stage size (rounded up). Only
      # the COUNT is set here — every stage capacity stays AUTOSIZED, and the
      # equal increments realize themselves through the containing unitary's
      # UnitarySystemPerformanceMultispeed flow ratios (stage k -> k/N). Never
      # hard-set a stage capacity: hard-sized equipment stops responding to the
      # 8.4.1.2.(5) capacity iteration.
      #
      # @return [Hash{String => Float}] coil handle -> the TOTAL capacity measured
      #   before re-staging. Growing a coil appends a stage EnergyPlus has never
      #   sized, so the new top stage reads back nil and shrinking one leaves a
      #   stale partial value behind — the appliers must bin on the measurement
      #   taken here, not on a re-read.
      def apply_staging(model, rules, vintage, audit)
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
        totals = {}
        model.getAirLoopHVACUnitarySystems.sort_by(&:nameString).each do |unitary|
          stage_multispeed_coil(unitary.coolingCoil, rules['dx_staging'],
                                "#{prefix}.10.(8)", 'DX cooling', audit, totals)
          stage_multispeed_coil(unitary.heatingCoil, rules['furnace_staging'],
                                "#{prefix}.9.(7)", 'furnace', audit, totals)
          audit_electric_resistance_heating(unitary, prefix, audit)
          Coils.set_stage_flow_ratios(unitary)
        end
        audit_staging_skips(model, prefix, audit)
        totals
      end

      # @return [Integer, nil] the stage count applied, nil when the coil is not staged
      def stage_multispeed_coil(optional_coil, rule, article, label, audit, totals = {})
        return nil if rule.nil?

        coil = Coils.multispeed(optional_coil)
        return nil if coil.nil?

        name = coil.nameString
        capacity_w = top_stage_capacity(coil)
        if capacity_w.nil?
          audit&.warn(:efficiency, "#{name}: staged capacity unavailable (model not sized?) — #{article} stage " \
                                   'count NOT set; run sizing first', article: article, ruling: 'D-46')
          return nil
        end
        totals[coil.handle.to_s] = capacity_w

        kw = capacity_w / 1000.0
        wanted = kw <= rule['two_stage_max_kw'] ? 2 : (kw / rule['stage_size_kw']).ceil
        stages = [wanted, MAX_STAGES].min
        if wanted > MAX_STAGES
          audit&.warn(:efficiency, "#{name}: #{wanted} equal stages required at #{kw.round(1)} kW but EnergyPlus " \
                                   "EXCEEDS its multispeed ceiling beyond #{MAX_STAGES} — stage count CLAMPED to " \
                                   "#{MAX_STAGES} (stages are larger than the code increment)",
                      target: name, article: article, ruling: 'D-47')
        end
        before = coil.stages.size
        resize_stages(coil, stages)
        audit&.decision(:efficiency, "#{label} modelled as #{stages} equal stages",
                        target: name,
                        inputs: { capacity_kw: kw.round(1), two_stage_max_kw: rule['two_stage_max_kw'],
                                  stage_size_kw: rule['stage_size_kw'], stages_required: wanted,
                                  stages_before: before },
                        value: "#{stages} autosized stage(s), each sized to #{(100.0 / stages).round(1)}% increments " \
                               'of the total by the unitary flow ratios',
                        article: article, ruling: 'D-46')
        stages
      end

      # The TOTAL capacity of a staged coil is its TOP stage (the stages are
      # cumulative in EnergyPlus, not additive).
      def top_stage_capacity(coil)
        stage = coil.stages.last
        return nil if stage.nil?

        if stage.respond_to?(:grossRatedTotalCoolingCapacity)
          optional_f(stage.grossRatedTotalCoolingCapacity) || optional_f(stage.autosizedGrossRatedTotalCoolingCapacity)
        elsif stage.respond_to?(:grossRatedHeatingCapacity)
          optional_f(stage.grossRatedHeatingCapacity) || optional_f(stage.autosizedGrossRatedHeatingCapacity)
        else
          optional_f(stage.nominalCapacity) || optional_f(stage.autosizedNominalCapacity)
        end
      end

      # Grow/shrink to +stages+ and, when the count actually moved, re-autosize
      # every stage capacity and flow so the next sizing run redistributes them
      # at the new k/N increments. An unchanged count is left untouched — the
      # stages are already autosized from the build, and re-autosizing would
      # wipe the 8.4.4.13.(2)(c) heating=cooling pinning a previous pass applied.
      def resize_stages(coil, stages)
        model = coil.model
        before = coil.stages.size
        while coil.stages.size > stages
          doomed = coil.stages.last
          coil.removeStage(doomed)
          doomed.remove
        end
        while coil.stages.size < stages
          added =
            if coil.to_CoilCoolingDXMultiSpeed.is_initialized then Coils.dx_cooling_stage(model)
            elsif coil.to_CoilHeatingDXMultiSpeed.is_initialized then Coils.dx_heating_stage(model)
            else Coils.gas_heating_stage(model)
            end
          break unless coil.addStage(added) # SDK refuses beyond MAX_STAGES

          added.setName("#{coil.nameString} Stage #{coil.stages.size}")
        end
        return coil.stages.size if coil.stages.size == before

        coil.stages.each do |stage|
          stage.autosizeGrossRatedTotalCoolingCapacity if stage.respond_to?(:autosizeGrossRatedTotalCoolingCapacity)
          stage.autosizeGrossRatedHeatingCapacity if stage.respond_to?(:autosizeGrossRatedHeatingCapacity)
          stage.autosizeNominalCapacity if stage.respond_to?(:autosizeNominalCapacity)
          stage.autosizeRatedAirFlowRate if stage.respond_to?(:autosizeRatedAirFlowRate)
        end
        coil.stages.size
      end

      # D-49: an electric-resistance coil is not a furnace — no burner, no
      # combustion staging, linear part-load — so the furnace staging sentence
      # does not reach it and the staged unitary keeps a single-stage electric
      # coil next to its staged DX cooling. Recorded per unit so the reader sees
      # the sentence was considered and declined, not overlooked.
      def audit_electric_resistance_heating(unitary, prefix, audit)
        return if audit.nil?

        coil = unitary.heatingCoil
        return if coil.empty? || !coil.get.to_CoilHeatingElectric.is_initialized

        audit.info(:efficiency, 'electric resistance heating left single-stage — it is not a furnace, so the ' \
                                'furnace staging sentence does not apply (the staged DX cooling still does)',
                   target: coil.get.nameString,
                   inputs: { unitary: unitary.nameString },
                   article: "#{prefix}.9.(7)", ruling: 'D-49')
      end

      # D-48: the staging scope is AIR-LOOP equipment. Zone terminals (PTAC /
      # PTHP) cannot host a multispeed coil — the EnergyPlus IDD restricts their
      # coil choices even though the SDK accepts the assignment — and make-up-air
      # tempering DX is not the staged unitary equipment the sentences describe.
      # Both stay single-speed; the skips are audited by REASON (one entry per
      # reason with the count, rather than one per coil, so a fleet-scale model's
      # hundreds of identical terminals cannot swamp the log).
      def audit_staging_skips(model, prefix, audit)
        return if audit.nil?

        zonal = []
        air_loop = []
        (model.getCoilCoolingDXSingleSpeeds + model.getCoilHeatingDXSingleSpeeds).sort_by(&:nameString).each do |coil|
          (coil.airLoopHVAC.is_initialized ? air_loop : zonal) << coil.nameString
        end
        unless zonal.empty?
          audit.info(:efficiency, "#{zonal.size} zone-terminal DX coil(s) left single-speed — " \
                                  "#{prefix}.9.(7)/#{prefix}.10.(8) staging is modelled on air-loop unitary " \
                                  'equipment; EnergyPlus packaged terminal objects cannot host a multispeed coil',
                     inputs: { coils: zonal.size }, value: zonal.first(5).join(', '),
                     article: "#{prefix}.9.(7); #{prefix}.10.(8)", ruling: 'D-48')
        end
        return if air_loop.empty?

        audit.info(:efficiency, "#{air_loop.size} air-loop DX coil(s) left single-speed — make-up-air tempering " \
                                'and non-reference systems are outside the staged-unitary scope',
                   inputs: { coils: air_loop.size }, value: air_loop.first(5).join(', '),
                   article: "#{prefix}.9.(7); #{prefix}.10.(8)", ruling: 'D-48')
      end

      # 8.4.4.17.(2)-(5) (2025: 8.4.5.17): VAV fan power-vs-flow curves from
      # Table 8.4.4.17. Selection by rated fan power ((3)-(5)): default = airfoil/
      # backward-inclined riding the fan curve; VAV fans > 7.5 kW and < 25 kW =
      # airfoil/backward-inclined WITH inlet vanes; >= 25 kW = forward curved
      # with inlet vanes. E+ mapping: coefficients A/B/C -> c1/c2/c3 (c4=c5=0)
      # and the below-D floor (P = E x Prated) approximated by the Fan Power
      # Minimum Flow Fraction = D clamp — the polynomial at D equals E within
      # the table's rounding (verified for all three rows).
      FAN_CURVES = {
        'airfoil riding fan curve' => { a: 0.227143, b: 1.178929, c: -0.41071, d: 0.47, e: 0.68 },
        'airfoil with inlet vanes' => { a: 0.584345, b: -0.57917, c: 0.970238, d: 0.35, e: 0.50 },
        'forward curved with inlet vanes' => { a: 0.339619, b: -0.84814, c: 1.495671, d: 0.25, e: 0.22 }
      }.freeze

      def apply_fan_power_curve(fan, vintage, audit)
        flow = fan.maximumFlowRate.is_initialized ? fan.maximumFlowRate.get : nil
        flow ||= fan.autosizedMaximumFlowRate.is_initialized ? fan.autosizedMaximumFlowRate.get : nil
        if flow.nil?
          audit&.warn(:efficiency, "#{fan.nameString}: flow not sized — 8.4.4.17 fan curve selection needs the " \
                                   'rated power; run sizing first (curve not applied)')
          return
        end

        power_kw = fan.pressureRise * flow / (fan.fanTotalEfficiency * 1000.0)
        row_name = if power_kw > 7.5 && power_kw < 25.0
                     'airfoil with inlet vanes'
                   elsif power_kw >= 25.0
                     'forward curved with inlet vanes'
                   else
                     'airfoil riding fan curve'
                   end
        row = FAN_CURVES[row_name]
        fan.setFanPowerCoefficient1(row[:a])
        fan.setFanPowerCoefficient2(row[:b])
        fan.setFanPowerCoefficient3(row[:c])
        fan.setFanPowerCoefficient4(0.0)
        fan.setFanPowerCoefficient5(0.0)
        fan.setFanPowerMinimumFlowRateInputMethod('Fraction')
        fan.setFanPowerMinimumFlowFraction(row[:d])
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
        audit&.decision(:efficiency, "VAV fan power curve set (#{row_name})",
                        target: fan.nameString,
                        inputs: { rated_kw: power_kw.round(2), coefficients: [row[:a], row[:b], row[:c]],
                                  minimum_flow_fraction: row[:d] },
                        value: "below-D floor (E=#{row[:e]}) approximated by the minimum-flow clamp",
                        article: "#{prefix}.17.(2)-(5); Table #{prefix}.17.")
      end

      # 8.4.4.14 (2025: 8.4.5.14) hydronic pump power. Sentence (5) directs
      # variable-flow pumps to be modeled as a pump riding its curve, so
      # reference PumpVariableSpeeds get the Table's riding-curve row (identical
      # coefficients to the 8.4.4.17 airfoil fan row — same DOE-2 lineage; the
      # VSD row is vendored for completeness). Coefficients come from the
      # ruleset's hydronic_pumps.curves (Table 8.4.4.14., both vintages
      # identical). E+ mapping: A/B/C -> part-load performance coefficients 1-3
      # (4th = 0); the below-D floor (P = E x Prated) is approximated by the
      # minimum-flow clamp at D x rated flow — the polynomial at D equals E
      # within the table's rounding (riding curve 0.691 vs 0.68, VSD 0.043 vs
      # 0.04).
      def apply_pump_rules(model, vintage, rule, audit, proposed: nil)
        return if rule.nil?

        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
        stats = proposed_pump_stats(proposed)
        if proposed.nil?
          audit&.info(:efficiency, "no proposed model supplied — #{prefix}.14.(1)-(3) pump power transfer " \
                                   "skipped (Table #{prefix}.14. curves still applied)", ruling: 'D-11')
        elsif stats.empty?
          audit&.warn(:efficiency, 'proposed model has NO pumps with determinable power+flow — ' \
                                   "#{prefix}.14.(1)-(3) power NOT transferred to any reference pump", ruling: 'D-11')
        end
        model.getPlantLoops.sort_by(&:nameString).each do |loop_|
          # 8.4.4.14 scopes HVAC hydronic pumping; a service-water loop's
          # circulator is Part 6 territory and stays as built. Transferring the
          # space-heating W/(L/s) intensity onto an SWH circulator (8 W against
          # the proposed's 1.9 MPa head) implies a 724% pump efficiency and is
          # an E+ FATAL — found by the gas-fuel variant sweep; the electric
          # fleet passed the same code path only by arithmetic luck.
          if swh_loop?(loop_)
            audit&.info(:efficiency, 'service water heating loop — outside 8.4.4.14 (HVAC hydronic pumps); pump left as built',
                        target: loop_.nameString, ruling: 'D-27')
            next
          end

          loop_type = loop_.sizingPlant.loopType
          loop_.supplyComponents.sort_by(&:nameString).each do |comp|
            if comp.to_PumpVariableSpeed.is_initialized
              pump = comp.to_PumpVariableSpeed.get
              row = rule['curves']['riding pump curve']
              pump.setCoefficient1ofthePartLoadPerformanceCurve(row['a'])
              pump.setCoefficient2ofthePartLoadPerformanceCurve(row['b'])
              pump.setCoefficient3ofthePartLoadPerformanceCurve(row['c'])
              pump.setCoefficient4ofthePartLoadPerformanceCurve(0.0)
              flow = optional_f(pump.ratedFlowRate) || optional_f(pump.autosizedRatedFlowRate)
              pump.setMinimumFlowRate(row['d'] * flow) if flow
              audit&.decision(:efficiency, 'variable-flow pump modeled riding its curve',
                              target: pump.nameString,
                              inputs: { coefficients: [row['a'], row['b'], row['c']],
                                        minimum_flow_fraction: row['d'], loop: loop_.nameString },
                              value: flow ? "below-D floor (E=#{row['e']}) via min flow #{(row['d'] * flow).round(5)} m3/s" \
                                          : 'coefficients set; min-flow clamp deferred (flow not sized)',
                              article: "#{prefix}.14.(4)-(5); Table #{prefix}.14.", ruling: 'D-11')
              transfer_pump_power(pump, flow, loop_type, stats, prefix, audit) if proposed && !stats.empty?
            elsif comp.to_PumpConstantSpeed.is_initialized && proposed && !stats.empty?
              pump = comp.to_PumpConstantSpeed.get
              flow = optional_f(pump.ratedFlowRate) || optional_f(pump.autosizedRatedFlowRate)
              transfer_pump_power(pump, flow, loop_type, stats, prefix, audit)
            end
          end
          apply_pump_power_cap(loop_, loop_type, rule['power_caps_w_per_kw'], prefix, audit)
        end
      end

      # D-38 (A3 ruled min-wins, phylroy 2026-07-28): 8.4.4.1.(2) makes the
      # Part 5 prescriptive articles a CEILING for the reference, so after the
      # 8.4.4.14 intensity transfer the loop's COMBINED pump motor power is
      # clamped at the Table 5.2.6.3 W/kW of the loop's peak thermal demand at
      # design. min-wins: a proposed intensity below the cap transfers
      # untouched; one above it is cut to the cap (audited). Applies with or
      # without a proposed model (the cap binds the reference regardless).
      def apply_pump_power_cap(loop_, loop_type, caps, prefix, audit)
        return if caps.nil?

        row, thermal_kw = pump_cap_basis(loop_, loop_type)
        rate = row && caps[row]
        return if rate.nil?

        if thermal_kw.nil? || thermal_kw <= 0.0
          audit&.info(:efficiency, "5.2.6.3 pump-power cap not evaluable — loop's peak thermal demand unsized",
                      target: loop_.nameString, article: '5.2.6.3.(1)', ruling: 'D-38')
          return
        end
        pumps = loop_.supplyComponents.filter_map do |c|
          c.to_PumpVariableSpeed.is_initialized ? c.to_PumpVariableSpeed.get : c.to_PumpConstantSpeed.is_initialized ? c.to_PumpConstantSpeed.get : nil
        end
        powers = pumps.map { |p| optional_f(p.ratedPowerConsumption) || optional_f(p.autosizedRatedPowerConsumption) }
        if pumps.empty? || powers.any?(&:nil?)
          audit&.info(:efficiency, '5.2.6.3 pump-power cap not evaluable — pump power unsized',
                      target: loop_.nameString, article: '5.2.6.3.(1)', ruling: 'D-38')
          return
        end
        combined = powers.sum
        cap_w = rate * thermal_kw
        if combined <= cap_w
          audit&.info(:efficiency, 'combined pump power within the Table 5.2.6.3 maximum',
                      target: loop_.nameString,
                      inputs: { combined_w: combined.round, cap_w: cap_w.round, w_per_kw: rate,
                                thermal_kw: thermal_kw.round(1), system_type: row },
                      article: '5.2.6.3.(1)', ruling: 'D-38')
          return
        end

        factor = cap_w / combined
        pumps.zip(powers).each do |pump, power|
          new_power = power * factor
          flow = optional_f(pump.ratedFlowRate) || optional_f(pump.autosizedRatedFlowRate)
          # keep the flow/head/power triple physical (same guard as the transfer)
          reconcile_pump_head(pump, new_power, flow)
          pump.setRatedPowerConsumption(new_power)
        end
        audit&.decision(:efficiency, 'combined pump power exceeds Table 5.2.6.3 — clamped to the maximum (min-wins over the pump-power transfer)',
                        target: loop_.nameString,
                        inputs: { before_w: combined.round, cap_w: cap_w.round, w_per_kw: rate,
                                  thermal_kw: thermal_kw.round(1), system_type: row, scale: factor.round(3) },
                        value: "#{combined.round} W -> #{cap_w.round} W",
                        article: "5.2.6.3.(1); #{prefix}.1.(2)", ruling: 'D-38')
      end

      # Table 5.2.6.3 row + the loop's peak thermal demand (kW). A loop hosting
      # water-to-air heat pump coils takes the WSHP row regardless of its
      # sizing type; otherwise the row follows the Sizing:Plant loop type
      # ('Condenser' = heat rejection, demand from the chillers it serves).
      def pump_cap_basis(loop_, loop_type)
        wta = loop_.demandComponents.select do |c|
          c.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized ||
            c.to_CoilHeatingWaterToAirHeatPumpEquationFit.is_initialized
        end
        unless wta.empty?
          kw = wta.sum do |c|
            coil = c.to_CoilCoolingWaterToAirHeatPumpEquationFit
            next 0.0 if coil.empty?

            coil = coil.get
            (optional_f(coil.ratedTotalCoolingCapacity) || optional_f(coil.autosizedRatedTotalCoolingCapacity) || 0.0) / 1000.0
          end
          return ['Water-source heat pump', kw.positive? ? kw : nil]
        end

        case loop_type
        when 'Heating'
          kw = loop_.supplyComponents.sum do |c|
            if c.to_BoilerHotWater.is_initialized
              b = c.to_BoilerHotWater.get
              (optional_f(b.nominalCapacity) || optional_f(b.autosizedNominalCapacity) || 0.0) / 1000.0
            else
              0.0
            end
          end
          ['Heating', kw.positive? ? kw : nil]
        when 'Cooling'
          kw = loop_.supplyComponents.sum do |c|
            if c.to_ChillerElectricEIR.is_initialized
              ch = c.to_ChillerElectricEIR.get
              (optional_f(ch.referenceCapacity) || optional_f(ch.autosizedReferenceCapacity) || 0.0) / 1000.0
            else
              0.0
            end
          end
          ['Cooling', kw.positive? ? kw : nil]
        when 'Condenser'
          kw = loop_.demandComponents.sum do |c|
            if c.to_ChillerElectricEIR.is_initialized
              ch = c.to_ChillerElectricEIR.get
              cap = optional_f(ch.referenceCapacity) || optional_f(ch.autosizedReferenceCapacity)
              cap.nil? ? 0.0 : cap * (1.0 + 1.0 / ch.referenceCOP) / 1000.0
            else
              0.0
            end
          end
          ['Heat rejection', kw.positive? ? kw : nil]
        else
          [nil, nil]
        end
      end

      # A service-water-heating loop: a water heater on supply or water-use
      # connections on demand. Outside the 8.4.4.14 hydronic-pump scope.
      def swh_loop?(loop_)
        loop_.supplyComponents.any? do |c|
          c.to_WaterHeaterMixed.is_initialized || c.to_WaterHeaterStratified.is_initialized
        end || loop_.demandComponents.any? { |c| c.to_WaterUseConnections.is_initialized }
      end

      # Sentences (1)-(3) through one mechanism: the proposed loop-type's pumps'
      # combined peak power intensity, W/(L/s) — sentence (3)'s own metric, which
      # equals head/efficiency (sentence (1): P = V x head / eff) and absorbs the
      # multi-pump combination of sentence (2) by summing power AND flow. The
      # reference pump's rated power is hard-set to that intensity times its own
      # sized flow (reference flows legitimately differ from proposed flows, so
      # the INTENSITY, not the absolute wattage, is what transfers).
      # The total (wire-to-water) pump efficiency the reconciliation targets when
      # a hard-set power and an inherited head disagree.
      DESIGN_PUMP_EFFICIENCY = 0.65

      # Keep a pump's flow/head/power triple physical whenever the power is
      # hard-set (the 8.4.4.14 transfer and the 5.2.6.3 clamp both do that):
      # EnergyPlus FATALS on a triple implying a pump efficiency above the motor
      # efficiency. The transferred power is authoritative (it IS the article's
      # number), so the inherited head is what gives.
      # @return [Boolean] whether the head was changed
      def reconcile_pump_head(pump, power_w, flow)
        return false unless flow&.positive? && power_w.to_f.positive?
        return false if (flow * pump.ratedPumpHead / power_w) <= pump.motorEfficiency

        pump.setRatedPumpHead(DESIGN_PUMP_EFFICIENCY * power_w / flow)
        true
      end

      def transfer_pump_power(pump, flow, loop_type, stats, prefix, audit)
        s = stats[loop_type]
        if s.nil?
          audit&.warn(:efficiency, "#{pump.nameString}: proposed has NO #{loop_type}-type loop pumps with known " \
                                   "power+flow — #{prefix}.14.(1)-(3) power NOT transferred (gem default retained)",
                     ruling: 'D-11')
          return
        end
        if flow.nil?
          audit&.warn(:efficiency, "#{pump.nameString}: reference pump flow not sized — #{prefix}.14.(1)-(3) " \
                                   'transfer needs the sized flow; run sizing first', ruling: 'D-11')
          return
        end
        w_per_l_s = s[:power_w] / s[:flow_l_s]
        power_w = w_per_l_s * flow * 1000.0
        # E+ hard-rejects power/head/flow triples implying pump efficiency
        # above motor efficiency ("Calculated Pump Efficiency > 100%" fatal).
        # The transferred power is authoritative (it IS the article's number);
        # reconcile the inherited head to a physical 65% total efficiency.
        head = pump.ratedPumpHead
        if reconcile_pump_head(pump, power_w, flow)
          audit&.warn(:efficiency, "#{pump.nameString}: inherited rated head #{head.round} Pa implies pump efficiency " \
                                   "above motor efficiency with the transferred #{power_w.round} W — head reduced to " \
                                   "#{pump.ratedPumpHead.round} Pa (65% total efficiency) to stay physical", ruling: 'D-27')
        end
        pump.setRatedPowerConsumption(power_w)
        audit&.decision(:efficiency, 'pump power transferred from the proposed building',
                        target: pump.nameString,
                        inputs: { proposed_pumps: s[:count], proposed_w_per_l_s: w_per_l_s.round(2),
                                  reference_flow_l_s: (flow * 1000.0).round(2), loop_type: loop_type },
                        value: "rated power #{power_w.round(0)} W (combined proposed intensity x reference flow)",
                        article: "#{prefix}.14.(1)-(3)", ruling: 'D-11')
      end

      # Combined peak power and flow of the PROPOSED building's pumps, grouped
      # by plant-loop type ('Heating'/'Cooling'/'Condenser') — the loop-type
      # correspondence sidesteps the pump-to-pump bijection that cannot exist
      # between different topologies. Pumps whose power or flow cannot be read
      # (unsized, no sql) are excluded; empty groups are dropped so callers can
      # warn loudly instead of transferring zeros.
      def proposed_pump_stats(proposed)
        return {} if proposed.nil?

        stats = Hash.new { |h, k| h[k] = { power_w: 0.0, flow_l_s: 0.0, count: 0 } }
        proposed.getPlantLoops.each do |loop_|
          next if swh_loop?(loop_) # SWH circulators must not pollute the Heating-loop intensity

          type = loop_.sizingPlant.loopType
          loop_.supplyComponents.each do |comp|
            pump = comp.to_PumpVariableSpeed.is_initialized ? comp.to_PumpVariableSpeed.get : nil
            pump ||= comp.to_PumpConstantSpeed.is_initialized ? comp.to_PumpConstantSpeed.get : nil
            next if pump.nil?

            power = optional_f(pump.ratedPowerConsumption) || optional_f(pump.autosizedRatedPowerConsumption)
            flow = optional_f(pump.ratedFlowRate) || optional_f(pump.autosizedRatedFlowRate)
            next if power.nil? || flow.nil? || flow.zero?

            stats[type][:power_w] += power
            stats[type][:flow_l_s] += flow * 1000.0
            stats[type][:count] += 1
          end
        end
        stats.reject { |_, s| s[:flow_l_s].zero? }
      end

      # T4 (audit 2026-07-25) 8.4.4.13.(2)(c): "the heat pump's heating capacity
      # at an outdoor air temperature of 8.3 C shall be identical to its cooling
      # capacity". The vendored CAP_FT cubic evaluates ~1.0 at 8.3 C, so pinning
      # the RATED heating capacity to the rated cooling capacity realizes the
      # sentence (the -8.3 C 50% point comes from the same curve). Post-sizing:
      # both capacities must be readable; paired coils only (same air loop).
      def align_heat_pump_heating_capacity(model, audit)
        model.getAirLoopHVACs.sort_by(&:nameString).each do |loop_|
          comps = Coils.supply_components(loop_)
          staged_heat = comps.find { |c| c.to_CoilHeatingDXMultiSpeed.is_initialized }
          staged_cool = comps.find { |c| c.to_CoilCoolingDXMultiSpeed.is_initialized }
          if staged_heat && staged_cool
            align_staged_heat_pump(staged_heat.to_CoilHeatingDXMultiSpeed.get,
                                   staged_cool.to_CoilCoolingDXMultiSpeed.get, audit)
            next
          end

          heat = comps.find { |c| c.to_CoilHeatingDXSingleSpeed.is_initialized }
          cool = comps.find { |c| c.to_CoilCoolingDXSingleSpeed.is_initialized }
          next if heat.nil? || cool.nil?

          heat = heat.to_CoilHeatingDXSingleSpeed.get
          cool = cool.to_CoilCoolingDXSingleSpeed.get
          cool_w = optional_f(cool.ratedTotalCoolingCapacity) || optional_f(cool.autosizedRatedTotalCoolingCapacity)
          if cool_w.nil?
            audit&.warn(:efficiency, "#{heat.nameString}: cooling capacity unavailable — 8.4.4.13.(2)(c) heating="                                      'cooling alignment skipped (run sizing first)')
            next
          end
          heat.setRatedTotalHeatingCapacity(cool_w)
          audit&.decision(:efficiency, 'heat pump heating capacity pinned to cooling capacity',
                          target: heat.nameString, inputs: { cooling_kw: (cool_w / 1000.0).round(1) },
                          value: "rated heating capacity = #{(cool_w / 1000.0).round(1)} kW (CAP_FT ~1.0 at 8.3 C)",
                          article: '8.4.4.13.(2)(c)', ruling: 'D-22')
        end
      end

      # Same sentence on a STAGED heat pump: the unit's heating capacity is its
      # top stage, so the top stages are what must match. The lower stages follow
      # the cooling coil's own increments stage-for-stage, which keeps the two
      # coils staged identically (both were sized to the same k/N ratios).
      # This pins capacities that were autosized — the article demands a specific
      # capacity, so the same D-22 exception that governs the single-speed coil
      # governs here; the COOLING side stays autosized and drives the pair.
      def align_staged_heat_pump(heat, cool, audit)
        pairs = heat.stages.zip(cool.stages)
        if pairs.any? { |_, c| c.nil? }
          audit&.warn(:efficiency, "#{heat.nameString}: staged heat pump has MORE heating stages than cooling " \
                                   'stages — 8.4.4.13.(2)(c) alignment applied only to the matched stages',
                      target: heat.nameString, article: '8.4.4.13.(2)(c)', ruling: 'D-22')
        end
        top = nil
        pairs.each do |heat_stage, cool_stage|
          next if cool_stage.nil?

          cool_w = optional_f(cool_stage.grossRatedTotalCoolingCapacity) ||
                   optional_f(cool_stage.autosizedGrossRatedTotalCoolingCapacity)
          next if cool_w.nil?

          heat_stage.setGrossRatedHeatingCapacity(cool_w)
          top = cool_w
        end
        if top.nil?
          audit&.warn(:efficiency, "#{heat.nameString}: staged cooling capacity unavailable — 8.4.4.13.(2)(c) " \
                                   'heating=cooling alignment skipped (run sizing first)',
                      target: heat.nameString, article: '8.4.4.13.(2)(c)', ruling: 'D-22')
          return
        end
        audit&.decision(:efficiency, 'staged heat pump heating capacity pinned to cooling capacity, stage for stage',
                        target: heat.nameString,
                        inputs: { stages: heat.stages.size, cooling_kw: (top / 1000.0).round(1) },
                        value: "top-stage heating capacity = #{(top / 1000.0).round(1)} kW (CAP_FT ~1.0 at 8.3 C)",
                        article: '8.4.4.13.(2)(c)', ruling: 'D-22 D-46')
      end

      # ---------------- table lookup (legacy model_find_object semantics) ----------------

      # Rows match when every criteria key PRESENT in the row equals the wanted value (a
      # missing key or 'Any' is a wildcard); capacity matches min < cap <= max, retried at
      # 0.99x on boundary misses; date ranges are honored when present.
      def find_row(table, criteria, capacity = nil)
        rows = table.select do |row|
          criteria.all? { |k, v| !row.key?(k) || row[k].nil? || row[k] == 'Any' || row[k] == v } &&
            date_ok?(row)
        end
        return rows.first if capacity.nil?

        rows = rows.select { |r| numeric?(r['minimum_capacity']) || r['minimum_capacity'].is_a?(String) }
        match = rows.select { |r| in_capacity_range?(r, capacity) }
        match = rows.select { |r| in_capacity_range?(r, capacity * 0.99) } if match.empty?
        match.first
      end

      def in_capacity_range?(row, capacity)
        min = row['minimum_capacity'].to_f
        max = row['maximum_capacity'].to_f
        capacity > min && capacity <= max
      end

      def numeric?(value)
        value.is_a?(Numeric)
      end

      def date_ok?(row)
        return true unless row['start_date'] && row['end_date']

        today = Date.today
        starts = parse_date(row['start_date'], Date.new(1900, 1, 1))
        ends = parse_date(row['end_date'], Date.new(2999, 1, 1))
        today >= starts && today <= ends
      rescue StandardError
        true
      end

      def parse_date(value, fallback)
        Date.parse(value.to_s)
      rescue StandardError
        fallback
      end

      # ---------------- conversions (ports of OpenstudioStandards::HVAC) ----------------

      W_PER_BTUH = 0.2930710701722222

      def seer_to_cop_no_fan(seer) = (-0.0076 * seer * seer) + (0.3796 * seer)
      def hspf_to_cop_no_fan(hspf) = (-0.0296 * hspf * hspf) + (0.7134 * hspf)
      def kw_per_ton_to_cop(kw_per_ton) = 3.517 / kw_per_ton
      def afue_to_thermal_eff(afue) = afue
      def combustion_eff_to_thermal_eff(eff) = eff - 0.007
      def cop_heating_to_cop_heating_no_fan(coph47, capacity_w) = (1.48E-7 * coph47 * (capacity_w / W_PER_BTUH)) + (1.062 * coph47)

      def eer_to_cop_no_fan(eer, capacity_w = nil)
        if capacity_w.nil?
          r = 0.12 # supply-fan fraction of total power, Thornton et al. 2011
          ((eer * W_PER_BTUH) + r) / (1 - r)
        else
          (7.84E-8 * eer * (capacity_w / W_PER_BTUH)) + (0.338 * eer)
        end
      end

      def w_to_btu_per_hr(watts) = watts / W_PER_BTUH
      def w_to_kbtu_per_hr(watts) = watts / W_PER_BTUH / 1000.0
      def w_to_tons(watts) = watts / 3516.8525

      # ---------------- curves ----------------

      # Build (or reuse by name) a performance curve from a vendored curve row.
      def curve(model, tables, name)
        return nil if name.nil? || name.to_s.empty?

        existing = model.getCurves.find { |c| c.nameString == name }
        return existing if existing

        row = tables['curves'].find { |c| c['name'] == name }
        return nil if row.nil?

        coeffs = (1..10).map { |i| row["coeff_#{i}"] }
        c =
          case row['form']
          when 'BiQuadratic', 'Biquadratic'
            k = OpenStudio::Model::CurveBiquadratic.new(model)
            k.setCoefficient1Constant(coeffs[0]); k.setCoefficient2x(coeffs[1]); k.setCoefficient3xPOW2(coeffs[2])
            k.setCoefficient4y(coeffs[3]); k.setCoefficient5yPOW2(coeffs[4]); k.setCoefficient6xTIMESY(coeffs[5])
            set_limits(k, row, two_vars: true)
            k
          when 'BiCubic', 'Bicubic'
            k = OpenStudio::Model::CurveBicubic.new(model)
            k.setCoefficient1Constant(coeffs[0]); k.setCoefficient2x(coeffs[1]); k.setCoefficient3xPOW2(coeffs[2])
            k.setCoefficient4y(coeffs[3]); k.setCoefficient5yPOW2(coeffs[4]); k.setCoefficient6xTIMESY(coeffs[5])
            k.setCoefficient7xPOW3(coeffs[6]); k.setCoefficient8yPOW3(coeffs[7])
            k.setCoefficient9xPOW2TIMESY(coeffs[8]); k.setCoefficient10xTIMESYPOW2(coeffs[9])
            set_limits(k, row, two_vars: true)
            k
          when 'Cubic'
            k = OpenStudio::Model::CurveCubic.new(model)
            k.setCoefficient1Constant(coeffs[0]); k.setCoefficient2x(coeffs[1])
            k.setCoefficient3xPOW2(coeffs[2]); k.setCoefficient4xPOW3(coeffs[3])
            set_limits(k, row)
            k
          when 'Quadratic'
            k = OpenStudio::Model::CurveQuadratic.new(model)
            k.setCoefficient1Constant(coeffs[0]); k.setCoefficient2x(coeffs[1]); k.setCoefficient3xPOW2(coeffs[2])
            set_limits(k, row)
            k
          else
            return nil
          end
        c.setName(name)
        c
      end

      def set_limits(curve, row, two_vars: false)
        curve.setMinimumValueofx(row['minimum_independent_variable_1']) if row['minimum_independent_variable_1']
        curve.setMaximumValueofx(row['maximum_independent_variable_1']) if row['maximum_independent_variable_1']
        if two_vars
          curve.setMinimumValueofy(row['minimum_independent_variable_2']) if row['minimum_independent_variable_2']
          curve.setMaximumValueofy(row['maximum_independent_variable_2']) if row['maximum_independent_variable_2']
        end
        if curve.respond_to?(:setMinimumCurveOutput)
          curve.setMinimumCurveOutput(row['minimum_dependent_variable_output']) if row['minimum_dependent_variable_output']
          curve.setMaximumCurveOutput(row['maximum_dependent_variable_output']) if row['maximum_dependent_variable_output']
        end
      end

      # ---------------- capacities ----------------

      def optional_f(value)
        return nil if value.nil?
        return value.to_f unless value.respond_to?(:is_initialized)
        value.is_initialized ? value.get.to_f : nil
      end

      # ---------------- component appliers ----------------

      # Legacy boiler_hot_water_apply_efficiency_and_curves (NECB2011 hvac_systems.rb:539):
      # primary/secondary staging (176/352 kW), EFFFPLR curve, AFUE/thermal/combustion ->
      # thermal efficiency, legacy rename.
      def apply_boiler(boiler, tables, plant, audit)
        fuel = case boiler.fuelType
               when 'Electricity' then 'Electric'
               when 'FuelOilNo1', 'FuelOilNo2' then 'Oil'
               else 'Gas'
               end
        capacity_w = optional_f(boiler.nominalCapacity) || optional_f(boiler.autosizedNominalCapacity)
        return audit&.warn(:efficiency, 'boiler capacity unavailable (model not sized?) — not set', target: boiler.nameString) if capacity_w.nil?

        boiler_capacity = capacity_w
        name = boiler.nameString
        if name.include?('Primary Boiler') || name.include?('Secondary Boiler')
          kw = capacity_w / 1000.0
          if kw > plant['two_boiler_max_kw'] # 8.4.4.9.(6)(d): 'exceeds 352 kW' (strict)
            if name.include?('Primary Boiler')
              boiler.setBoilerFlowMode('LeavingSetpointModulated')
              boiler.setMinimumPartLoadRatio(plant['modulating_min_fraction'])
            else
              boiler_capacity = 0.001
            end
          elsif kw > plant['single_boiler_max_kw'] # (6)(c): 'greater than 176' (strict)
            boiler_capacity = capacity_w / 2
          elsif name.include?('Secondary Boiler')
            boiler_capacity = 0.001
          elsif capacity_w <= 1.0
            boiler_capacity = 1.0
          end
        end
        boiler.setNominalCapacity(boiler_capacity)

        cap_btuh = w_to_btu_per_hr(boiler_capacity)
        row = find_row(tables['boilers'], { 'fluid_type' => 'Hot Water', 'fuel_type' => fuel }, cap_btuh)
        return audit&.warn(:efficiency, 'no boiler efficiency row found — not set', target: name,
                           inputs: { fuel: fuel, capacity_btu_hr: cap_btuh.round }) if row.nil?

        eff_fplr = curve(boiler.model, tables, row['efffplr'])
        boiler.setNormalizedBoilerEfficiencyCurve(eff_fplr) if eff_fplr

        thermal_eff, label = boiler_thermal_efficiency(row)
        return audit&.warn(:efficiency, 'boiler row has no efficiency value — not set', target: name) if thermal_eff.nil?

        boiler.setNominalThermalEfficiency(thermal_eff)
        boiler.setName("#{name} #{w_to_kbtu_per_hr(boiler_capacity).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'boiler efficiency applied', target: name,
                        inputs: { fuel: fuel, capacity_kw: (boiler_capacity / 1000.0).round(1) },
                        value: "thermal efficiency #{thermal_eff.round(3)} (#{label}), curve #{row['efffplr']}",
                        article: 'NECB 2020 Table 5.2.12.1 (boilers)')
      end

      def boiler_thermal_efficiency(row)
        if row['minimum_annual_fuel_utilization_efficiency']
          [afue_to_thermal_eff(row['minimum_annual_fuel_utilization_efficiency']),
           "#{row['minimum_annual_fuel_utilization_efficiency']} AFUE"]
        elsif row['minimum_thermal_efficiency']
          [row['minimum_thermal_efficiency'], "#{row['minimum_thermal_efficiency']} Thermal Eff"]
        elsif row['minimum_combustion_efficiency']
          [combustion_eff_to_thermal_eff(row['minimum_combustion_efficiency']),
           "#{row['minimum_combustion_efficiency']} Combustion Eff"]
        else
          [nil, nil]
        end
      end

      # Legacy chiller_electric_eir_apply_efficiency_and_curves (NECB2011:648): modulating
      # to 25%, primary/secondary 2100 kW split, curves, kW/ton -> COP, tower sizing.
      def apply_chiller(chiller, tables, plant, audit)
        name = chiller.nameString
        capacity_w = optional_f(chiller.referenceCapacity) || optional_f(chiller.autosizedReferenceCapacity)
        return audit&.warn(:efficiency, 'chiller capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        chiller.setChillerFlowMode('LeavingSetpointModulated')
        chiller.setMinimumPartLoadRatio(plant['modulating_min_fraction'])
        chiller.setMinimumUnloadingRatio(plant['modulating_min_fraction'])

        chiller_capacity = capacity_w
        if name.include?('Primary') || name.include?('Secondary')
          if capacity_w / 1000.0 <= plant['single_chiller_max_kw'] # 8.4.4.10.(6)(b): 'not greater than 2100'
            chiller_capacity = 0.001 if name.include?('Secondary Chiller')
          else
            chiller_capacity = capacity_w / 2.0
          end
        end
        chiller.setReferenceCapacity(chiller_capacity)

        cooling_type = chiller.condenserType == 'AirCooled' ? 'AirCooled' : 'WaterCooled'
        compressor = %w[Reciprocating Scroll Centrifugal].find { |t| name.downcase.include?(t.downcase) }
        compressor = 'Rotary Screw' if compressor.nil? && name.downcase.include?('screw')
        if compressor.nil?
          audit&.warn(:efficiency, 'chiller compressor type not in name — Scroll assumed', target: name)
          compressor = 'Scroll'
        end

        tons = w_to_tons(chiller_capacity)
        row = find_row(tables['chillers'],
                       { 'cooling_type' => cooling_type, 'compressor_type' => compressor }, tons)
        return audit&.warn(:efficiency, 'no chiller efficiency row found — not set', target: name,
                           inputs: { cooling_type: cooling_type, compressor: compressor, tons: tons.round(1) }) if row.nil?

        %w[capft eirft eirfplr].zip(
          %i[setCoolingCapacityFunctionOfTemperature
             setElectricInputToCoolingOutputRatioFunctionOfTemperature
             setElectricInputToCoolingOutputRatioFunctionOfPLR]
        ).each do |key, setter|
          c = curve(chiller.model, tables, row[key])
          chiller.send(setter, c) if c
        end

        kw_per_ton = row['minimum_full_load_efficiency']
        return audit&.warn(:efficiency, 'chiller row has no full-load efficiency — COP not set', target: name) if kw_per_ton.nil?

        cop = kw_per_ton_to_cop(kw_per_ton)
        chiller.setReferenceCOP(cop)
        chiller.setName("#{name} #{tons.round}tons #{kw_per_ton.round(1)}kW/ton")
        audit&.decision(:efficiency, 'chiller efficiency applied', target: name,
                        inputs: { cooling_type: cooling_type, compressor: compressor, tons: tons.round(1) },
                        value: "COP #{cop.round(2)} (#{kw_per_ton.round(2)} kW/ton), curves #{row['capft']}/#{row['eirft']}/#{row['eirfplr']}",
                        article: 'NECB 2020 Table 5.2.12.1 (chillers)')
      end

      # Legacy tower rules: cells per 1750 kW of heat rejection; fan at the
      # Table 5.2.12.2 maximum. Runs as its OWN pass after every chiller
      # capacity is final: the tower rejects heat for EVERY chiller on its
      # condenser loop, and a two-chiller plant (8.4.4.10.(6) split) halves
      # the per-chiller capacity — sizing the fan from the Primary alone
      # starves E+'s fan-power-derived autosized air flow until the tower UA
      # solve fails ("Bad starting values for UA"; found by the LargeOffice
      # archetype, the first two-chiller+tower fleet member).
      def apply_tower_rules(model, audit)
        model.getPlantLoops.sort_by(&:nameString).each do |loop|
          towers = loop.supplyComponents
                       .select { |c| c.to_CoolingTowerSingleSpeed.is_initialized }
                       .map { |c| c.to_CoolingTowerSingleSpeed.get }
          next if towers.empty?

          chillers = loop.demandComponents
                         .select { |c| c.to_ChillerElectricEIR.is_initialized }
                         .map { |c| c.to_ChillerElectricEIR.get }
          tower_cap = chillers.sum do |ch|
            cap = optional_f(ch.referenceCapacity) || optional_f(ch.autosizedReferenceCapacity)
            cap.nil? ? 0.0 : cap * (1.0 + 1.0 / ch.referenceCOP)
          end
          if tower_cap <= 0.0
            audit&.warn(:efficiency, 'condenser loop has a tower but no readable chiller capacity — tower rules not applied',
                        target: towers[0].nameString, ruling: 'D-26')
            next
          end

          # 8.4.4.11.(2)-(3): one cell up to 1750 kW; above, capacity/1750 rounded UP
          cells = tower_cap / 1000.0 <= 1750 ? 1 : (tower_cap / (1000.0 * 1750)).ceil
          towers[0].setNumberofCells(cells)
          # Table 5.2.12.2 (NECB 2015+ incl. 2020/2025): axial direct-contact tower
          # fan <= 0.013 kW/kW rejection — NOT the 2011 value 0.015 (T2, audit
          # 2026-07-25; legacy NECB2015 override uses 0.013). Below the 13 kW
          # small-tower threshold the E+ default fan sizing stands.
          fan_w = 0.013 * tower_cap
          if fan_w > 13_000.0
            # Harden the sizing run's tower hydraulics BEFORE overriding the fan:
            # E+ derives autosized tower air flow FROM fan power and then solves
            # UA by regula falsi — re-running sizing with a hard code fan lands
            # in an infeasible solver band ("Bad starting values for UA";
            # LargeOffice fails at 17-30 kW while its 15.9 kW autosize and
            # 39.3 kW both pass — legacy clears the band by luck). Pinning
            # water/air/UA at their solved values leaves nothing to re-solve;
            # Table 5.2.12.2 governs fan POWER only, so the code fan rides on
            # E+'s self-consistent heat-transfer sizing.
            { autosizedDesignWaterFlowRate: :setDesignWaterFlowRate,
              autosizedDesignAirFlowRate: :setDesignAirFlowRate,
              autosizedUFactorTimesAreaValueatDesignAirFlowRate: :setUFactorTimesAreaValueatDesignAirFlowRate,
              autosizedAirFlowRateinFreeConvectionRegime: :setAirFlowRateinFreeConvectionRegime,
              autosizedUFactorTimesAreaValueatFreeConvectionAirFlowRate: :setUFactorTimesAreaValueatFreeConvectionAirFlowRate }.each do |getter, setter|
              v = towers[0].public_send(getter)
              towers[0].public_send(setter, v.get) if v.respond_to?(:is_initialized) && v.is_initialized
            end
            towers[0].setFanPoweratDesignAirFlowRate(fan_w)
          end
          audit&.decision(:efficiency, 'cooling tower cells set from heat rejection',
                          target: towers[0].nameString,
                          inputs: { tower_cap_kw: (tower_cap / 1000.0).round(1), chillers_on_loop: chillers.size },
                          value: "#{cells} cell(s)", article: '8.4.4.11.(2)-(3)', ruling: 'D-26')
          if fan_w > 13_000.0
            audit&.decision(:efficiency, 'cooling tower fan power set at the Table 5.2.12.2 maximum',
                            target: towers[0].nameString,
                            inputs: { kw_per_kw: 0.013, tower_cap_kw: (tower_cap / 1000.0).round(1) },
                            value: "fan #{(fan_w / 1000.0).round(1)} kW", article: 'Table 5.2.12.2', ruling: 'D-22')
          end
        end
      end

      # Legacy coil_cooling_dx_single_speed_apply_efficiency_and_curves via NECB
      # unitary_acs/heat_pumps tables: SEER/EER -> COP (no fan) + performance curves.
      def apply_dx_cooling(coil, tables, audit)
        name = coil.nameString
        capacity_w = optional_f(coil.ratedTotalCoolingCapacity) || optional_f(coil.autosizedRatedTotalCoolingCapacity)
        return audit&.warn(:efficiency, 'DX cooling capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        heat_pump = paired_with_dx_heating?(coil)
        table = heat_pump ? tables['heat_pumps'] : tables['unitary_acs']
        heating_type = electric_or_no_heating?(coil) ? 'Electric Resistance or None' : 'All Other'
        cap_btuh = w_to_btu_per_hr(capacity_w)
        row = find_row(table, { 'cooling_type' => 'AirCooled', 'heating_type' => heating_type,
                                'subcategory' => 'Single Package' }, cap_btuh)
        row ||= find_row(table, { 'cooling_type' => 'AirCooled', 'subcategory' => 'Single Package' }, cap_btuh)
        return audit&.warn(:efficiency, 'no DX cooling efficiency row found — not set', target: name,
                           inputs: { heat_pump: heat_pump, heating_type: heating_type, capacity_btu_hr: cap_btuh.round }) if row.nil?

        # SEER2/EER2 converted like SEER/EER — the documented openstudio-standards
        # assumption (Standards.CoilCoolingDXSingleSpeed: 'assumed to be the same').
        cop, label = dx_cooling_cop(row)
        return audit&.warn(:efficiency, 'DX cooling row has no efficiency value — not set', target: name) if cop.nil?

        coil.setRatedCOP(cop)
        { 'cool_cap_ft' => :setTotalCoolingCapacityFunctionOfTemperatureCurve,
          'cool_cap_fflow' => :setTotalCoolingCapacityFunctionOfFlowFractionCurve,
          'cool_eir_ft' => :setEnergyInputRatioFunctionOfTemperatureCurve,
          'cool_eir_fflow' => :setEnergyInputRatioFunctionOfFlowFractionCurve,
          'cool_plf_fplr' => :setPartLoadFractionCorrelationCurve }.each do |key, setter|
          c = curve(coil.model, tables, row[key])
          coil.send(setter, c) if c
        end
        coil.setName("#{name} #{w_to_kbtu_per_hr(capacity_w).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'DX cooling efficiency applied', target: name,
                        inputs: { table: heat_pump ? 'heat_pumps' : 'unitary_acs',
                                  heating_type: heating_type, capacity_kw: (capacity_w / 1000.0).round(1) },
                        value: "COP #{cop.round(2)} (#{label})",
                        article: 'NECB 2020 Table 5.2.12.1 (unitary equipment)')
      end

      # Staged DX cooling (8.4.4.10.(8)). Binned by TOP-stage capacity — which IS
      # the unit's total capacity — against the same unitary_acs/heat_pumps
      # tables as the single-speed coil, with the row's COP and curves applied to
      # EVERY stage. That is exactly what the legacy multispeed applier does
      # (one row read from the last stage, same values per stage): the tables are
      # unit-capacity tables, not per-stage tables.
      def apply_dx_cooling_multi(coil, tables, audit, capacity_w = nil)
        name = coil.nameString
        capacity_w ||= top_stage_capacity(coil)
        return audit&.warn(:efficiency, 'staged DX cooling capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        heat_pump = paired_with_dx_heating?(coil)
        table = heat_pump ? tables['heat_pumps'] : tables['unitary_acs']
        heating_type = electric_or_no_heating?(coil) ? 'Electric Resistance or None' : 'All Other'
        cap_btuh = w_to_btu_per_hr(capacity_w)
        row = find_row(table, { 'cooling_type' => 'AirCooled', 'heating_type' => heating_type,
                                'subcategory' => 'Single Package' }, cap_btuh)
        row ||= find_row(table, { 'cooling_type' => 'AirCooled', 'subcategory' => 'Single Package' }, cap_btuh)
        return audit&.warn(:efficiency, 'no DX cooling efficiency row found — not set', target: name,
                           inputs: { heat_pump: heat_pump, heating_type: heating_type, capacity_btu_hr: cap_btuh.round }) if row.nil?

        cop, label = dx_cooling_cop(row)
        return audit&.warn(:efficiency, 'DX cooling row has no efficiency value — not set', target: name) if cop.nil?

        curves = { 'cool_cap_ft' => :setTotalCoolingCapacityFunctionofTemperatureCurve,
                   'cool_cap_fflow' => :setTotalCoolingCapacityFunctionofFlowFractionCurve,
                   'cool_eir_ft' => :setEnergyInputRatioFunctionofTemperatureCurve,
                   'cool_eir_fflow' => :setEnergyInputRatioFunctionofFlowFractionCurve,
                   'cool_plf_fplr' => :setPartLoadFractionCorrelationCurve }
        coil.stages.each do |stage|
          stage.setGrossRatedCoolingCOP(cop)
          curves.each do |key, setter|
            c = curve(coil.model, tables, row[key])
            stage.send(setter, c) if c
          end
        end
        coil.setName("#{name} #{w_to_kbtu_per_hr(capacity_w).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'staged DX cooling efficiency applied to every stage', target: name,
                        inputs: { table: heat_pump ? 'heat_pumps' : 'unitary_acs', stages: coil.stages.size,
                                  heating_type: heating_type, top_stage_kw: (capacity_w / 1000.0).round(1) },
                        value: "COP #{cop.round(2)} (#{label}) on all #{coil.stages.size} stages, binned by total capacity",
                        article: 'NECB 2020 Table 5.2.12.1 (unitary equipment)', ruling: 'D-46')
      end

      # The SEER/EER/full-load ladder shared by the single- and multi-speed DX
      # cooling appliers. @return [Array(Float, String), nil]
      def dx_cooling_cop(row)
        if row['minimum_seasonal_energy_efficiency_ratio']
          [seer_to_cop_no_fan(row['minimum_seasonal_energy_efficiency_ratio']),
           "#{row['minimum_seasonal_energy_efficiency_ratio']}SEER"]
        elsif row['minimum_seasonal_energy_efficiency_ratio_2']
          [seer_to_cop_no_fan(row['minimum_seasonal_energy_efficiency_ratio_2']),
           "#{row['minimum_seasonal_energy_efficiency_ratio_2']}SEER2"]
        elsif row['minimum_seasonal_efficiency']
          [seer_to_cop_no_fan(row['minimum_seasonal_efficiency']), "#{row['minimum_seasonal_efficiency']}SEER"]
        elsif row['minimum_energy_efficiency_ratio']
          [eer_to_cop_no_fan(row['minimum_energy_efficiency_ratio']), "#{row['minimum_energy_efficiency_ratio']}EER"]
        elsif row['minimum_energy_efficiency_ratio_2']
          [eer_to_cop_no_fan(row['minimum_energy_efficiency_ratio_2']), "#{row['minimum_energy_efficiency_ratio_2']}EER2"]
        elsif row['minimum_full_load_efficiency']
          [eer_to_cop_no_fan(row['minimum_full_load_efficiency']), "#{row['minimum_full_load_efficiency']}EER"]
        end
      end

      # Staged DX heating (reference ASHP). Same top-stage binning contract as
      # the staged cooling applier.
      def apply_dx_heating_multi(coil, tables, audit, capacity_w = nil)
        name = coil.nameString
        capacity_w ||= top_stage_capacity(coil)
        return audit&.warn(:efficiency, 'staged DX heating capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        cap_btuh = w_to_btu_per_hr(capacity_w)
        row = find_row(tables['heat_pumps_heating'],
                       { 'cooling_type' => 'AirCooled', 'subcategory' => 'Single Package' }, cap_btuh)
        return audit&.warn(:efficiency, 'no DX heating efficiency row found — not set', target: name,
                           inputs: { capacity_btu_hr: cap_btuh.round }) if row.nil?

        cop, label = dx_heating_cop(row, capacity_w)
        return audit&.warn(:efficiency, 'DX heating row has no efficiency value — not set', target: name) if cop.nil?

        curves = { 'heat_cap_ft' => :setHeatingCapacityFunctionofTemperatureCurve,
                   'heat_cap_fflow' => :setHeatingCapacityFunctionofFlowFractionCurve,
                   'heat_eir_ft' => :setEnergyInputRatioFunctionofTemperatureCurve,
                   'heat_eir_fflow' => :setEnergyInputRatioFunctionofFlowFractionCurve,
                   'heat_plf_fplr' => :setPartLoadFractionCorrelationCurve }
        coil.stages.each do |stage|
          stage.setGrossRatedHeatingCOP(cop)
          curves.each do |key, setter|
            c = curve(coil.model, tables, row[key])
            stage.send(setter, c) if c && stage.respond_to?(setter)
          end
        end
        coil.setName("#{name} #{w_to_kbtu_per_hr(capacity_w).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'staged DX heating efficiency applied to every stage', target: name,
                        inputs: { stages: coil.stages.size, top_stage_kw: (capacity_w / 1000.0).round(1) },
                        value: "heating COP #{cop.round(2)} (#{label}) on all #{coil.stages.size} stages",
                        article: 'NECB 2020 Table 5.2.12.1 (heat pumps, heating)', ruling: 'D-46')
      end

      # @return [Array(Float, String), nil]
      def dx_heating_cop(row, capacity_w)
        if row['minimum_heating_seasonal_performance_factor']
          [hspf_to_cop_no_fan(row['minimum_heating_seasonal_performance_factor']),
           "#{row['minimum_heating_seasonal_performance_factor']}HSPF"]
        elsif row['minimum_heating_seasonal_performance_factor_2']
          # HSPF2 converted like HSPF (consistent with the SEER2/EER2 assumption)
          [hspf_to_cop_no_fan(row['minimum_heating_seasonal_performance_factor_2']),
           "#{row['minimum_heating_seasonal_performance_factor_2']}HSPF2"]
        elsif row['minimum_coefficient_of_performance_heating']
          [cop_heating_to_cop_heating_no_fan(row['minimum_coefficient_of_performance_heating'], capacity_w),
           "#{row['minimum_coefficient_of_performance_heating']}COPH"]
        end
      end

      # Staged gas furnace (8.4.4.9.(7)). Binned by TOP-stage (= total) capacity
      # against the same furnaces table; the burner efficiency goes on every
      # stage and the part-load curve on the parent coil.
      def apply_gas_multi(coil, tables, audit, capacity_w = nil)
        name = coil.nameString
        capacity_w ||= top_stage_capacity(coil)
        return audit&.warn(:efficiency, 'staged gas coil capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        cap_btuh = [w_to_btu_per_hr(capacity_w), 0.001].max
        row = find_row(tables['furnaces'], { 'fluid_type' => 'Air', 'fuel_type' => 'Gas' }, cap_btuh)
        return audit&.warn(:efficiency, 'no furnace efficiency row found — not set', target: name,
                           inputs: { capacity_btu_hr: cap_btuh.round }) if row.nil?

        plf = curve(coil.model, tables, row['efffplr'])
        coil.setPartLoadFractionCorrelationCurve(plf) if plf

        thermal_eff, label = boiler_thermal_efficiency(row) # same AFUE/thermal/combustion triad
        return audit&.warn(:efficiency, 'furnace row has no efficiency value — not set', target: name) if thermal_eff.nil?

        coil.stages.each { |stage| stage.setGasBurnerEfficiency(thermal_eff) }
        coil.setName("#{name} #{w_to_kbtu_per_hr(capacity_w).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'staged gas heating efficiency applied to every stage', target: name,
                        inputs: { stages: coil.stages.size, top_stage_kw: (capacity_w / 1000.0).round(1) },
                        value: "burner efficiency #{thermal_eff.round(3)} (#{label}) on all #{coil.stages.size} " \
                               "stages, curve #{row['efffplr']}",
                        article: 'NECB 2020 Table 5.2.12.1 (furnaces)', ruling: 'D-46')
      end

      # Legacy DX heating via heat_pumps_heating: HSPF or COPH47 -> heating COP (no fan).
      def apply_dx_heating(coil, tables, audit)
        name = coil.nameString
        capacity_w = optional_f(coil.ratedTotalHeatingCapacity) || optional_f(coil.autosizedRatedTotalHeatingCapacity)
        return audit&.warn(:efficiency, 'DX heating capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        cap_btuh = w_to_btu_per_hr(capacity_w)
        row = find_row(tables['heat_pumps_heating'],
                       { 'cooling_type' => 'AirCooled', 'subcategory' => 'Single Package' }, cap_btuh)
        return audit&.warn(:efficiency, 'no DX heating efficiency row found — not set', target: name,
                           inputs: { capacity_btu_hr: cap_btuh.round }) if row.nil?

        cop, label = dx_heating_cop(row, capacity_w)
        return audit&.warn(:efficiency, 'DX heating row has no efficiency value — not set', target: name) if cop.nil?

        coil.setRatedCOP(cop)
        { 'heat_cap_ft' => :setTotalHeatingCapacityFunctionofTemperatureCurve,
          'heat_cap_fflow' => :setTotalHeatingCapacityFunctionofFlowFractionCurve,
          'heat_eir_ft' => :setEnergyInputRatioFunctionofTemperatureCurve,
          'heat_eir_fflow' => :setEnergyInputRatioFunctionofFlowFractionCurve,
          'heat_plf_fplr' => :setPartLoadFractionCorrelationCurve }.each do |key, setter|
          c = curve(coil.model, tables, row[key])
          coil.send(setter, c) if c && coil.respond_to?(setter)
        end
        coil.setName("#{name} #{w_to_kbtu_per_hr(capacity_w).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'DX heating efficiency applied', target: name,
                        inputs: { capacity_kw: (capacity_w / 1000.0).round(1) },
                        value: "heating COP #{cop.round(2)} (#{label})",
                        article: 'NECB 2020 Table 5.2.12.1 (heat pumps, heating)')
      end

      # Legacy coil_heating_gas_apply_efficiency_and_curves (NECB2011:855).
      def apply_gas_coil(coil, tables, audit)
        name = coil.nameString
        capacity_w = optional_f(coil.nominalCapacity) || optional_f(coil.autosizedNominalCapacity)
        return audit&.warn(:efficiency, 'gas coil capacity unavailable (model not sized?) — not set', target: name) if capacity_w.nil?

        cap_btuh = [w_to_btu_per_hr(capacity_w), 0.001].max
        row = find_row(tables['furnaces'], { 'fluid_type' => 'Air', 'fuel_type' => 'Gas' }, cap_btuh)
        return audit&.warn(:efficiency, 'no furnace efficiency row found — not set', target: name,
                           inputs: { capacity_btu_hr: cap_btuh.round }) if row.nil?

        plf = curve(coil.model, tables, row['efffplr'])
        coil.setPartLoadFractionCorrelationCurve(plf) if plf

        thermal_eff, label = boiler_thermal_efficiency(row) # same AFUE/thermal/combustion triad
        return audit&.warn(:efficiency, 'furnace row has no efficiency value — not set', target: name) if thermal_eff.nil?

        coil.setGasBurnerEfficiency(thermal_eff)
        coil.setName("#{name} #{w_to_kbtu_per_hr(capacity_w).round}kBtu/hr #{label}")
        audit&.decision(:efficiency, 'gas heating coil efficiency applied', target: name,
                        inputs: { capacity_kw: (capacity_w / 1000.0).round(1) },
                        value: "burner efficiency #{thermal_eff.round(3)} (#{label}), curve #{row['efffplr']}",
                        article: 'NECB 2020 Table 5.2.12.1 (furnaces)')
      end

      # ---------------- context helpers ----------------

      # Is this cooling coil part of a heat-pump system (paired DX heating on the same
      # air loop / containing HVAC component)?
      def paired_with_dx_heating?(coil)
        loop = coil.airLoopHVAC
        loop = containing_unitary(coil)&.airLoopHVAC if loop.nil? || loop.empty?
        if loop&.is_initialized
          return Coils.supply_components(loop.get).any? do |c|
            c.to_CoilHeatingDXSingleSpeed.is_initialized || c.to_CoilHeatingDXVariableSpeed.is_initialized ||
              c.to_CoilHeatingDXMultiSpeed.is_initialized
          end
        end

        containing = coil.containingHVACComponent
        return false unless containing.is_initialized

        comp = containing.get
        comp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized ||
          (comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized rescue false)
      end

      # The AirLoopHVACUnitarySystem holding this coil, if any — a staged coil is
      # never a direct supply component of its air loop.
      # @return [OpenStudio::Model::AirLoopHVACUnitarySystem, nil]
      def containing_unitary(coil)
        containing = coil.containingHVACComponent
        return nil unless containing.is_initialized

        unitary = containing.get.to_AirLoopHVACUnitarySystem
        unitary.is_initialized ? unitary.get : nil
      end

      # Legacy coil_dx_heating_type: 'Electric Resistance or None' vs 'All Other'.
      def electric_or_no_heating?(coil)
        loop = coil.airLoopHVAC
        loop = containing_unitary(coil)&.airLoopHVAC if loop.nil? || loop.empty?
        if loop&.is_initialized
          comps = Coils.supply_components(loop.get)
          gas_or_hydronic = comps.any? do |c|
            c.to_CoilHeatingGas.is_initialized || c.to_CoilHeatingWater.is_initialized ||
              c.to_CoilHeatingGasMultiStage.is_initialized ||
              c.to_CoilHeatingDXSingleSpeed.is_initialized || c.to_CoilHeatingDXVariableSpeed.is_initialized ||
              c.to_CoilHeatingDXMultiSpeed.is_initialized
          end
          return !gas_or_hydronic
        end

        containing = coil.containingHVACComponent
        if containing.is_initialized && containing.get.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          heat = containing.get.to_ZoneHVACPackagedTerminalAirConditioner.get.heatingCoil
          return !(heat.to_CoilHeatingGas.is_initialized || heat.to_CoilHeatingWater.is_initialized)
        end
        true
      end
    end

    # Facade: apply NECB minimum efficiencies to a sized model. Pass the sized
    # PROPOSED model via proposed: to enable the 8.4.4.14.(1)-(3) pump power
    # transfer (combined W/(L/s) by loop type); without it the Table 8.4.4.14
    # curves still apply and the skip is noted in the audit.
    def self.apply_efficiencies(model, vintage: '2020', audit: nil, proposed: nil)
      Efficiency.apply(model, vintage: vintage, audit: audit, proposed: proposed)
    end

    # Facade: make an ALREADY-EFFICIENCY-APPLIED model safe to re-size.
    #
    # The efficiency pass hard-sets pump rated power (the 8.4.4.14 transfer and
    # the 5.2.6.3 clamp) while pump FLOW stays autosized, and reconciles the
    # head so the triple is physical at the flow sized so far. A later sizing
    # run re-derives the flow: if it grows, the frozen power/head no longer fit
    # it and EnergyPlus FATALS on "Calculated Pump Efficiency > 100%" during
    # input checking — before the efficiency pass gets its chance to
    # re-reconcile. Releasing the hard power back to autosize removes the
    # inconsistency by construction (EnergyPlus then derives power from the
    # flow and head it just sized), and the caller's next apply_efficiencies
    # re-transfers it against the NEW flow.
    #
    # Call this before EVERY re-sizing run of a model that has already been
    # through apply_efficiencies — the 8.4.1.2.(5) capacity iteration does.
    # @return [Integer] pumps released
    def self.prepare_for_resizing(model, audit: nil)
      pumps = model.getPumpVariableSpeeds.reject { |p| p.ratedPowerConsumption.empty? } +
              model.getPumpConstantSpeeds.reject { |p| p.ratedPowerConsumption.empty? }
      pumps.each(&:autosizeRatedPowerConsumption)
      unless pumps.empty?
        audit&.info(:efficiency, 'hard-set pump power released to autosize for the re-sizing run — the ' \
                                 'efficiency pass re-transfers it against the newly sized flow',
                    inputs: { pumps: pumps.size }, article: '8.4.4.14.(1)-(3)', ruling: 'D-11 D-27')
      end
      pumps.size
    end
  end
end
