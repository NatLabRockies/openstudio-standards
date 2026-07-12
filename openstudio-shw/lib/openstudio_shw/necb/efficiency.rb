module OpenStudioSHW
  module NECB
    # Water-heater performance — verbatim port of the NECB2020
    # water_heater_mixed_apply_efficiency (Table 6.2.2.1 via the UEF procedure +
    # Maguire-Roberts (2020) UA derivation + PNNL assumptions). Electric: thermal
    # efficiency 1.0 + max standby-loss formulas -> UA. Gas/oil storage: UEF
    # ladder by tank volume and first-hour rating (FHR = 0.7 x V_litres + 151,
    # the legacy rule of thumb), burner efficiency 0.82, RE/UA from the UEF test
    # draw; large equipment: Et 0.9 + SL formula. Cubic part-load curve
    # SWH-EFFFPLR-NECB2011 on fuel-fired heaters.
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

        if rules['part_load_curve']['applies_to'].include?(fuel)
          water_heater.setPartLoadFactorCurve(part_load_curve(water_heater.model, rules['part_load_curve']))
        end
        water_heater.setName("#{water_heater.nameString} #{efficiency.round(3)} Therm Eff")

        audit.decision(:shw_efficiency, 'water heater performance applied (Table 6.2.2.1, NECB2020 UEF procedure)',
                       target: water_heater.nameString,
                       inputs: { fuel: fuel, capacity_kw: (capacity / 1000).round(2), volume_l: volume_l.round(1),
                                 thermal_efficiency: efficiency.round(4), ua_w_per_k: ua_w_k.round(4) },
                       evidence: evidence, article: '6.2.2.1.')
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

      def part_load_curve(model, spec)
        existing = model.getCurveCubicByName(spec['name'])
        return existing.get if existing.is_initialized

        curve = OpenStudio::Model::CurveCubic.new(model)
        curve.setName(spec['name'])
        curve.setCoefficient1Constant(spec['coefficients'][0])
        curve.setCoefficient2x(spec['coefficients'][1])
        curve.setCoefficient3xPOW2(spec['coefficients'][2])
        curve.setCoefficient4xPOW3(spec['coefficients'][3])
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
