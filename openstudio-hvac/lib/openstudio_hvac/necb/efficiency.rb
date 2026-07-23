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
        model.getCoilCoolingDXSingleSpeeds.sort_by(&:nameString).each { |c| apply_dx_cooling(c, tables, audit) }
        model.getCoilHeatingDXSingleSpeeds.sort_by(&:nameString).each { |c| apply_dx_heating(c, tables, audit) }
        model.getCoilHeatingGass.sort_by(&:nameString).each { |c| apply_gas_coil(c, tables, audit) }
        model.getFanVariableVolumes.sort_by(&:nameString).each { |f| apply_fan_power_curve(f, vintage, audit) }
        apply_pump_rules(model, requested_vintage, plant_rules['hydronic_pumps'], audit, proposed: proposed)
        audit&.info(:efficiency, 'NECB efficiency pass complete',
                    inputs: { vintage: vintage,
                              boilers: model.getBoilerHotWaters.size,
                              chillers: model.getChillerElectricEIRs.size,
                              dx_cooling: model.getCoilCoolingDXSingleSpeeds.size,
                              dx_heating: model.getCoilHeatingDXSingleSpeeds.size,
                              gas_coils: model.getCoilHeatingGass.size })
        true
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
                                   "skipped (Table #{prefix}.14. curves still applied)")
        elsif stats.empty?
          audit&.warn(:efficiency, 'proposed model has NO pumps with determinable power+flow — ' \
                                   "#{prefix}.14.(1)-(3) power NOT transferred to any reference pump")
        end
        model.getPlantLoops.sort_by(&:nameString).each do |loop_|
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
                              article: "#{prefix}.14.(4)-(5); Table #{prefix}.14.")
              transfer_pump_power(pump, flow, loop_type, stats, prefix, audit) if proposed && !stats.empty?
            elsif comp.to_PumpConstantSpeed.is_initialized && proposed && !stats.empty?
              pump = comp.to_PumpConstantSpeed.get
              flow = optional_f(pump.ratedFlowRate) || optional_f(pump.autosizedRatedFlowRate)
              transfer_pump_power(pump, flow, loop_type, stats, prefix, audit)
            end
          end
        end
      end

      # Sentences (1)-(3) through one mechanism: the proposed loop-type's pumps'
      # combined peak power intensity, W/(L/s) — sentence (3)'s own metric, which
      # equals head/efficiency (sentence (1): P = V x head / eff) and absorbs the
      # multi-pump combination of sentence (2) by summing power AND flow. The
      # reference pump's rated power is hard-set to that intensity times its own
      # sized flow (reference flows legitimately differ from proposed flows, so
      # the INTENSITY, not the absolute wattage, is what transfers).
      def transfer_pump_power(pump, flow, loop_type, stats, prefix, audit)
        s = stats[loop_type]
        if s.nil?
          audit&.warn(:efficiency, "#{pump.nameString}: proposed has NO #{loop_type}-type loop pumps with known " \
                                   "power+flow — #{prefix}.14.(1)-(3) power NOT transferred (gem default retained)")
          return
        end
        if flow.nil?
          audit&.warn(:efficiency, "#{pump.nameString}: reference pump flow not sized — #{prefix}.14.(1)-(3) " \
                                   'transfer needs the sized flow; run sizing first')
          return
        end
        w_per_l_s = s[:power_w] / s[:flow_l_s]
        power_w = w_per_l_s * flow * 1000.0
        pump.setRatedPowerConsumption(power_w)
        audit&.decision(:efficiency, 'pump power transferred from the proposed building',
                        target: pump.nameString,
                        inputs: { proposed_pumps: s[:count], proposed_w_per_l_s: w_per_l_s.round(2),
                                  reference_flow_l_s: (flow * 1000.0).round(2), loop_type: loop_type },
                        value: "rated power #{power_w.round(0)} W (combined proposed intensity x reference flow)",
                        article: "#{prefix}.14.(1)-(3)")
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
          if kw >= plant['two_boiler_max_kw']
            if name.include?('Primary Boiler')
              boiler.setBoilerFlowMode('LeavingSetpointModulated')
              boiler.setMinimumPartLoadRatio(plant['modulating_min_fraction'])
            else
              boiler_capacity = 0.001
            end
          elsif kw >= plant['single_boiler_max_kw']
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
          if capacity_w / 1000.0 < plant['single_chiller_max_kw']
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
        apply_tower_rules(chiller, capacity_w, audit) if name.include?('Primary Chiller')
        chiller.setName("#{name} #{tons.round}tons #{kw_per_ton.round(1)}kW/ton")
        audit&.decision(:efficiency, 'chiller efficiency applied', target: name,
                        inputs: { cooling_type: cooling_type, compressor: compressor, tons: tons.round(1) },
                        value: "COP #{cop.round(2)} (#{kw_per_ton.round(2)} kW/ton), curves #{row['capft']}/#{row['eirft']}/#{row['eirfplr']}",
                        article: 'NECB 2020 Table 5.2.12.1 (chillers)')
      end

      # Legacy tower rules: cells per 1750 kW of heat rejection; fan power 1.5% of
      # rejection when above the 13 kW EnergyPlus small-tower threshold.
      def apply_tower_rules(chiller, capacity_w, audit)
        loop = chiller.condenserWaterLoop
        return unless loop.is_initialized

        towers = loop.get.supplyComponents
                     .select { |c| c.to_CoolingTowerSingleSpeed.is_initialized }
                     .map { |c| c.to_CoolingTowerSingleSpeed.get }
        return if towers.empty?

        tower_cap = capacity_w * (1.0 + 1.0 / chiller.referenceCOP)
        cells = tower_cap / 1000.0 < 1750 ? 1 : (tower_cap / (1000 * 1750) + 0.5).round
        towers[0].setNumberofCells(cells)
        towers[0].setFanPoweratDesignAirFlowRate(0.015 * tower_cap) if tower_cap * 0.015 > 13_000.0
        audit&.decision(:efficiency, 'cooling tower sized from chiller heat rejection',
                        target: towers[0].nameString,
                        inputs: { tower_cap_kw: (tower_cap / 1000.0).round(1) },
                        value: "#{cells} cell(s)#{tower_cap * 0.015 > 13_000.0 ? ", fan #{(0.015 * tower_cap / 1000.0).round(1)} kW" : ''}",
                        article: 'NECB heat rejection rules (5.2.12.2)')
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
        cop, label =
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

        cop, label =
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
        if loop.is_initialized
          return loop.get.supplyComponents.any? { |c| c.to_CoilHeatingDXSingleSpeed.is_initialized || c.to_CoilHeatingDXVariableSpeed.is_initialized }
        end

        containing = coil.containingHVACComponent
        return false unless containing.is_initialized

        comp = containing.get
        comp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized ||
          (comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized rescue false)
      end

      # Legacy coil_dx_heating_type: 'Electric Resistance or None' vs 'All Other'.
      def electric_or_no_heating?(coil)
        loop = coil.airLoopHVAC
        if loop.is_initialized
          comps = loop.get.supplyComponents
          gas_or_hydronic = comps.any? do |c|
            c.to_CoilHeatingGas.is_initialized || c.to_CoilHeatingWater.is_initialized ||
              c.to_CoilHeatingDXSingleSpeed.is_initialized || c.to_CoilHeatingDXVariableSpeed.is_initialized
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
  end
end
