module OpenStudioSHW
  module NECB
    # Water-heater performance — verbatim port of the NECB2020
    # water_heater_mixed_apply_efficiency (Table 6.2.2.1 via the UEF procedure +
    # Maguire-Roberts (2020) UA derivation + PNNL assumptions). Electric: thermal
    # efficiency 1.0 + max standby-loss formulas -> UA. Gas/oil storage: UEF
    # ladder by tank volume and first-hour rating (FHR = 0.7 x V_litres + 151,
    # the legacy rule of thumb), burner efficiency 0.82, RE/UA from the UEF test
    # draw; large equipment: Et 0.9 + SL formula. The 8.4.5.9. (2025: 8.4.6.9.)
    # part-load fuel curve is applied to fuel-fired heaters, storage and
    # instantaneous alike, as the cubic SWH-EFFFPLR-NECB2011 — which is the
    # PLF-domain image of the code's FHeatPLC quadratic, not a rival curve
    # (D-53).
    module Efficiency
      module_function

      def apply_efficiency(water_heater, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        rules = NECB.rules(vintage)['efficiency']

        capacity = optional(water_heater.heaterMaximumCapacity)
        volume_m3 = optional(water_heater.tankVolume)
        if capacity.nil? || volume_m3.nil?
          audit.warn(:shw_efficiency, "#{water_heater.nameString}: capacity or volume not set — standard not applied")
          return false
        end

        fuel = water_heater.heaterFuelType
        volume_l = volume_m3 * 1000.0
        capacity_btu_hr = OpenStudio.convert(capacity, 'W', 'Btu/hr').get
        efficiency = nil
        ua_btu_hr_f = nil
        evidence = nil

        # Instantaneous water heaters (Table 6.2.2.1 instantaneous rows): the code
        # bounds gas instantaneous at Vr <= 7.6 L — treat tanks at/below that (or
        # named instantaneous) as tankless: UEF/Et applied as thermal efficiency,
        # zero standby UA.
        if volume_l <= 7.6 || water_heater.nameString =~ /instantaneous/i
          return apply_instantaneous(water_heater, rules, fuel, capacity, audit)
        end

        case fuel
        when 'Electricity'
          electric = rules['electric']
          efficiency = electric['thermal_efficiency'].to_f
          sl_w = if capacity_btu_hr <= OpenStudio.convert(electric['small_max_kw'], 'kW', 'Btu/hr').get
                   volume_l < 270 ? 40 + 0.2 * volume_l : 0.472 * volume_l - 33.5
                 else
                   0.3 + 102.2 / volume_l
                 end
          ua_btu_hr_f = OpenStudio.convert(sl_w, 'W', 'Btu/hr').get / electric['ua_divisor_f'].to_f
          evidence = "electric SL formula -> #{sl_w.round(2)} W standby"
        when 'NaturalGas', 'FuelOilNo2'
          fuel_rules = rules['fuel_fired']
          fhr = 0.7 * volume_l + 151.0
          if capacity <= 22_000 && volume_l >= 76 && volume_l < 208
            efficiency, ua_btu_hr_f, evidence = uef_path(fuel_rules, 'uef_bins_76_to_208_l', fhr, volume_l, capacity_btu_hr)
          elsif capacity <= 22_000 && volume_l >= 208 && volume_l < 380
            efficiency, ua_btu_hr_f, evidence = uef_path(fuel_rules, 'uef_bins_208_to_380_l', fhr, volume_l, capacity_btu_hr)
          elsif capacity > 22_000 && capacity <= 30_500 && volume_l <= 454
            bin = fuel_rules['uef_22_to_30_5_kw_max_454_l']
            uef = bin['intercept'] + bin['slope'] * volume_l
            draw = draw_gal(fuel_rules['uef_bins_76_to_208_l'], fhr)
            efficiency, ua_btu_hr_f = maguire_roberts(fuel_rules, uef, draw, capacity_btu_hr)
            evidence = "UEF #{uef.round(4)} (22-30.5 kW row), draw #{draw} gal"
          else
            large = fuel_rules['large']
            et = large['thermal_efficiency'].to_f
            sl_w = 0.84 * (1.25 * (capacity / 1000.0) + 16.57 * Math.sqrt(volume_l))
            sl_btu_hr = OpenStudio.convert(sl_w, 'W', 'Btu/hr').get
            ua_btu_hr_f = sl_btu_hr * et / large['ua_divisor_f'].to_f
            efficiency = (ua_btu_hr_f * 70 + capacity_btu_hr * et) / capacity_btu_hr
            evidence = "large equipment: Et #{et}, SL #{sl_w.round(1)} W"
          end
        else
          audit.warn(:shw_efficiency, "#{water_heater.nameString}: fuel '#{fuel}' not supported — standard not applied")
          return false
        end

        ua_w_k = OpenStudio.convert(ua_btu_hr_f, 'Btu/hr*R', 'W/K').get
        water_heater.setHeaterThermalEfficiency(efficiency)
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(ua_w_k)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(ua_w_k)
        water_heater.setOnCycleParasiticFuelType(fuel)
        water_heater.setOnCycleParasiticHeatFractiontoTank(rules['parasitic']['on_cycle_heat_fraction'].to_f)
        water_heater.setOffCycleParasiticFuelType(fuel)
        water_heater.setOffCycleParasiticHeatFractiontoTank(rules['parasitic']['off_cycle_heat_fraction'].to_f)

        water_heater.setName("#{water_heater.nameString} #{efficiency.round(3)} Therm Eff")

        audit.decision(:shw_efficiency, 'water heater performance applied (Table 6.2.2.1, NECB2020 UEF procedure)',
                       target: water_heater.nameString,
                       inputs: { fuel: fuel, capacity_kw: (capacity / 1000).round(2), volume_l: volume_l.round(1),
                                 thermal_efficiency: efficiency.round(4), ua_w_per_k: ua_w_k.round(4) },
                       evidence: evidence, article: '6.2.2.1.')
        apply_part_load_curve(water_heater, rules, fuel, audit)
        true
      end

      # Instantaneous rows of Table 6.2.2.1. Gas < 59 kW: UEF 0.86 (< 6.4 L/min)
      # or 0.87 (>= 6.4 L/min) — rated flow is not model-resolvable, so the
      # CONSERVATIVE 0.86 is used (audited); gas all others: Et >= 94%. Oil:
      # Et >= 80% (< 37.8 L) / 78%. Electric instantaneous carries footnote (6)
      # (no numeric requirement) — modeled at 1.0.
      def apply_instantaneous(water_heater, rules, fuel, capacity, audit)
        efficiency, evidence =
          case fuel
          when 'NaturalGas'
            capacity < 59_000 ? [0.86, 'gas instantaneous < 59 kW: UEF 0.86 (conservative low-flow row; rated flow unknown)'] : [0.94, 'gas instantaneous, all others: Et 0.94']
          when 'FuelOilNo2'
            [0.80, 'oil instantaneous < 37.8 L: Et 0.80']
          when 'Electricity'
            [1.0, 'electric instantaneous: footnote (6), no numeric requirement — modeled at 1.0']
          else
            audit.warn(:shw_efficiency, "#{water_heater.nameString}: instantaneous fuel '#{fuel}' not supported")
            return false
          end
        water_heater.setHeaterThermalEfficiency(efficiency)
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(0.0)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(0.0)
        water_heater.setName("#{water_heater.nameString} #{efficiency.round(3)} Therm Eff Instantaneous")
        audit.decision(:shw_efficiency, 'instantaneous water heater performance applied (tankless: zero standby UA)',
                       target: water_heater.nameString,
                       inputs: { fuel: fuel, capacity_kw: (capacity / 1000).round(2), thermal_efficiency: efficiency },
                       evidence: evidence, article: '6.2.2.1. (instantaneous rows)')
        # 8.4.5.9 draws no storage/instantaneous distinction — a fuel-fired
        # instantaneous heater is a fuel-fired service water heater, so the
        # part-load fuel curve reaches it too.
        apply_part_load_curve(water_heater, rules, fuel, audit)
        true
      end

      # Heat-pump water heater performance: the code floor (2020: EF >= 2.1;
      # 2025: UEF >= 2.23) applied as the DX coil's rated COP — CONSERVATIVE
      # (rated COP >= EF in practice since EF includes tank standby), audited.
      def apply_heat_pump_efficiency(hpwh, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        floor = vintage.to_s == '2025' ? 2.23 : 2.1
        metric = vintage.to_s == '2025' ? 'UEF' : 'EF'
        coil = hpwh.dXCoil.to_CoilWaterHeatingAirToWaterHeatPump
        if coil.empty?
          audit.warn(:shw_efficiency, "#{hpwh.nameString}: no air-to-water HP coil found — performance not applied")
          return false
        end

        coil.get.setRatedCOP(floor)
        audit.decision(:shw_efficiency,
                       "heat-pump water heater performance applied: rated COP set to the code floor #{metric} #{floor} " \
                       '(conservative — rated COP exceeds EF in practice since EF includes tank standby)',
                       target: hpwh.nameString, inputs: { "#{metric.downcase}_floor": floor },
                       article: '6.2.2.1. (storage-type heat pump)')
        true
      end

      def uef_path(fuel_rules, bin_key, fhr, volume_l, capacity_btu_hr)
        bin = fuel_rules[bin_key].find { |b| b['fhr_max'].nil? || fhr < b['fhr_max'] }
        uef = bin['intercept'] + bin['slope'] * volume_l
        efficiency, ua = maguire_roberts(fuel_rules, uef, bin['draw_gal'], capacity_btu_hr)
        [efficiency, ua, "UEF #{uef.round(4)} (FHR #{fhr.round(1)} L/hr bin), draw #{bin['draw_gal']} gal"]
      end

      def draw_gal(bins, fhr)
        bins.find { |b| b['fhr_max'].nil? || fhr < b['fhr_max'] }['draw_gal']
      end

      # Maguire & Roberts (2020): recovery efficiency + UA from the UEF test draw.
      def maguire_roberts(fuel_rules, uef, draw_gal, capacity_btu_hr)
        efficiency = fuel_rules['burner_efficiency'].to_f
        q_load_btu = draw_gal * 8.30074 * 0.99826 * (125.0 - 58.0)
        re = efficiency + q_load_btu * (uef - efficiency) / (24 * capacity_btu_hr * uef)
        ua = (efficiency - re) * capacity_btu_hr / (125 - 67.5)
        [efficiency, ua]
      end

      # NECB 8.4.5.9. (2025: 8.4.6.9.) "Fuel-Fired Service Water Heater" — the
      # part-load fuel curve. SCOPE IS THE ARTICLE'S, not an implementation
      # convenience: the article governs "the reference fuel-fired service
      # water heater", so it reaches gas and oil (storage and instantaneous
      # alike) and does NOT reach electric heaters — 8.4.5 carries no electric
      # counterpart to apply. An out-of-scope fuel is audited as such rather
      # than silently skipped. See D-53.
      def apply_part_load_curve(water_heater, rules, fuel, audit)
        spec = rules['part_load_curve']
        unless spec['applies_to'].include?(fuel)
          audit.info(:shw_efficiency,
                     "part-load fuel curve not applied — '#{fuel}' is not a fuel-fired service water heater, " \
                     "so #{spec['article']} does not reach it (article scope, not an omission)",
                     target: water_heater.nameString, article: spec['article'], ruling: 'D-53')
          return false
        end

        water_heater.setPartLoadFactorCurve(part_load_curve(water_heater.model, spec))
        audit.decision(:shw_efficiency,
                       'part-load fuel curve applied to the fuel-fired water heater',
                       target: water_heater.nameString,
                       inputs: { fuel: fuel, curve: spec['name'], form: spec['form'] },
                       value: spec['coefficients'],
                       evidence: "code FHeatPLC #{spec['code_fheatplc']['coefficients'].inspect} is a fuel-ratio " \
                                 'curve; the EnergyPlus part-load-factor field is a degradation divisor, so it ' \
                                 'carries the transform PLF(x) = x / FHeatPLC(x) — probe-verified equivalent to ' \
                                 '0.98% over PLR 0.25-1.0 (necb_8_4_6_curve_probe.rb)',
                       article: spec['article'], ruling: 'D-53')
        true
      end

      # Builds the curve in the form the ruleset declares. `form` is honoured
      # rather than assumed: the field accepts any UnivariateFunction, so a
      # Quadratic ruleset must not be smuggled through as a cubic with a zero
      # cubic term (that would silently accept a mis-shaped spec).
      def part_load_curve(model, spec)
        coeffs = spec['coefficients']
        case spec['form']
        when 'Quadratic'
          raise ArgumentError, "part_load_curve '#{spec['name']}': Quadratic needs 3 coefficients" unless coeffs.size == 3

          existing = model.getCurveQuadraticByName(spec['name'])
          return existing.get if existing.is_initialized

          curve = OpenStudio::Model::CurveQuadratic.new(model)
          curve.setCoefficient1Constant(coeffs[0])
          curve.setCoefficient2x(coeffs[1])
          curve.setCoefficient3xPOW2(coeffs[2])
        when 'Cubic'
          raise ArgumentError, "part_load_curve '#{spec['name']}': Cubic needs 4 coefficients" unless coeffs.size == 4

          existing = model.getCurveCubicByName(spec['name'])
          return existing.get if existing.is_initialized

          curve = OpenStudio::Model::CurveCubic.new(model)
          curve.setCoefficient1Constant(coeffs[0])
          curve.setCoefficient2x(coeffs[1])
          curve.setCoefficient3xPOW2(coeffs[2])
          curve.setCoefficient4xPOW3(coeffs[3])
        else
          raise ArgumentError, "part_load_curve '#{spec['name']}': unsupported form '#{spec['form']}'"
        end
        curve.setName(spec['name'])
        curve.setMinimumValueofx(0.0)
        curve.setMaximumValueofx(1.0)
        curve
      end

      def optional(value)
        value.is_initialized ? value.get : nil
      end
    end

    def self.apply_water_heater_efficiency(water_heater, **kwargs)
      Efficiency.apply_efficiency(water_heater, **kwargs)
    end
  end
end
