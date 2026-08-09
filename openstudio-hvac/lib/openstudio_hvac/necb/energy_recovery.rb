module OpenStudioHVAC
  # NECB 5.2.10.1 energy recovery: the post-sizing airflow-threshold trigger and
  # the reference ERV recipe. Reopens the module defined in reference.rb, whose
  # NECB.optional_flow / NECB.rules this file uses.
  module NECB
    # ==================== 8.4.4.19 / 5.2.10.1: energy recovery (post-sizing) ====================
    # 8.4.4.19 (2020) / 8.4.5.19 (2025): where Subsection 5.2.10 applies, the
    # reference system shall be modeled with energy recovery, used to preheat
    # the outside air — via NECB 2020/2025 Tables 5.2.10.1.-A/-B: the
    # airflow-threshold trigger, evaluated POST-SIZING (it needs the sized
    # supply and minimum-OA flows), called by the umbrella after the reference
    # sizing run. Replaces the NECB 2011 150 kW exhaust-heat-content trigger
    # previously implemented here — wrong vintage, and divergent exactly where
    # it matters: a small high-%OA system is "R (required at all flow rates)"
    # under 2020 while the 2011 formula waves it through (permissive).
    # Idempotent: loops already carrying an HX are skipped.
    # @param model [OpenStudio::Model::Model] SIZED model (needs supply/OA flows; modified in place)
    # @param vintage [String] NECB vintage ('2020' or '2025')
    # @param hdd [Numeric] heating degree-days below 18 degC for the location
    # @param audit [AuditLog, nil] audit to append to (a new one is created if nil)
    # @return [AuditLog] the audit carrying the per-loop 5.2.10.1 determinations
    def self.apply_energy_recovery(model, vintage: '2020', hdd:, audit: nil)
      audit ||= AuditLog.new
      rule = NECB.rules(vintage)['energy_recovery']
      return audit if rule.nil?

      model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        oa_system = air_loop.airLoopHVACOutdoorAirSystem
        next if oa_system.empty? # no OA intake: 5.2.10 does not apply
        next if oa_system.get.oaComponents.any? { |c| c.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized }

        supply = optional_flow(air_loop.designSupplyAirFlowRate) ||
                 optional_flow(air_loop.autosizedDesignSupplyAirFlowRate)
        ctrl = oa_system.get.getControllerOutdoorAir
        min_oa = optional_flow(ctrl.minimumOutdoorAirFlowRate) ||
                 optional_flow(ctrl.autosizedMinimumOutdoorAirFlowRate)
        if supply.nil? || min_oa.nil? || supply.zero?
          audit.warn(:rules, '5.2.10.1 energy-recovery trigger needs SIZED supply/OA flows — not evaluated ' \
                             '(run sizing first)', target: air_loop.nameString, article: rule['trigger_article'],
                     ruling: 'D-06')
          next
        end

        supply_l_s = supply * 1000.0
        oa_pct = 100.0 * min_oa / supply
        hours = annual_availability_hours(air_loop)
        if hours.nil?
          audit.warn(:rules, 'fan availability hours not computable — conservatively classified CONTINUOUS',
                     target: air_loop.nameString, article: rule['trigger_article'], ruling: 'D-06')
        end
        mode = hours.nil? || hours >= rule['continuous_hours_per_year'] ? 'continuous' : 'non_continuous'
        required, threshold_desc = erv_threshold_verdict(rule, mode, hdd, oa_pct, supply_l_s)
        inputs = { supply_l_s: supply_l_s.round, min_oa_l_s: (min_oa * 1000).round,
                   oa_pct: oa_pct.round(1), operation: mode, annual_hours: hours&.round,
                   hdd: hdd, threshold: threshold_desc }
        if required
          erv = add_energy_recovery(air_loop, oa_system.get, rule)
          audit.decision(:rules, 'energy recovery added to reference system (Table 5.2.10.1 threshold met)',
                         target: air_loop.nameString, inputs: inputs,
                         value: "rotary HX @ #{(rule['effectiveness'] * 100).round}% sensible+latent effectiveness " \
                                "(= #{(rule['effectiveness'] * 100).round}% ENTHALPY effectiveness by identity, " \
                                "the 5.2.10.1.(4) minimum) with 5.2.10.1.(6) overshoot control (#{erv.nameString})",
                         article: "#{rule['article']}; #{rule['trigger_article']}; 5.2.10.1.(4); 5.2.10.1.(6)",
                         ruling: 'D-06 D-15')
        else
          audit.decision(:rules, 'energy recovery not required (below the Table 5.2.10.1 threshold)',
                         target: air_loop.nameString, inputs: inputs, article: rule['trigger_article'],
                         ruling: 'D-06')
        end
      end
      audit
    end

    # Table row by HDD, band by %OA. Cells: 'R' = required at all flow rates,
    # 'NR' = never, numeric = required at/above that supply flow (L/s).
    # Below the smallest band (<10% OA) is outside the Tables entirely -> NR.
    # @param rule [Hash] the ruleset's 'energy_recovery' block
    # @param mode [String] 'continuous' or 'non_continuous' operation
    # @param hdd [Numeric] heating degree-days below 18 degC
    # @param oa_pct [Numeric] minimum outdoor air as a percentage of supply (0-100)
    # @param supply_l_s [Numeric] design supply flow in L/s
    # @return [Array(Boolean, String)] [required?, threshold description]
    def self.erv_threshold_verdict(rule, mode, hdd, oa_pct, supply_l_s)
      bands = rule['oa_bands_pct']
      return [false, 'below 10% OA (outside Tables 5.2.10.1.-A/-B)'] if oa_pct < bands.first

      row = rule['thresholds_l_s'][mode].find { |r| hdd < r['hdd_max'] }
      cell = row['bands'][bands.rindex { |b| oa_pct >= b }]
      case cell
      when 'R' then [true, 'R (required at all flow rates)']
      when 'NR' then [false, 'NR (not required at any flow rate)']
      else [supply_l_s >= cell, ">= #{cell} L/s"]
      end
    end

    # Annual fan-availability hours from the air loop's availability schedule
    # (>= 8000 h/yr = continuously operating per the Table notes). Constant
    # schedules (incl. the SDK's Always On) count directly; rulesets are summed
    # hourly across the year; anything else is not computable (nil).
    # @param air_loop [OpenStudio::Model::AirLoopHVAC]
    # @return [Integer, nil] annual availability hours, or nil when not computable
    def self.annual_availability_hours(air_loop)
      schedule = air_loop.availabilitySchedule
      constant = schedule.to_ScheduleConstant
      return constant.get.value.positive? ? 8760 : 0 if constant.is_initialized

      ruleset = schedule.to_ScheduleRuleset
      return nil unless ruleset.is_initialized

      y = air_loop.model.getYearDescription.assumedYear
      days = ruleset.get.getDaySchedules(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(1), 1, y),
                                         OpenStudio::Date.new(OpenStudio::MonthOfYear.new(12), 31, y))
      days.sum { |d| (1..24).count { |h| d.getValue(OpenStudio::Time.new(0, h, 0, 0)).positive? } }
    end

    # Legacy air_loop_hvac_apply_energy_recovery_ventilator recipe: rotary HX, 50%
    # effectiveness at all conditions, economizer lockout, ExhaustOnly frost control,
    # -23.3 degC threshold, and an OA-pretreat setpoint manager on the HX outlet.
    def self.add_energy_recovery(air_loop, oa_system, rule)
      model = air_loop.model
      hx = rule['hx']
      erv = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
      erv.setName("#{air_loop.nameString} ERV")
      erv.setHeatExchangerType(hx['type'])
      erv.setEconomizerLockout(hx['economizer_lockout'])
      erv.setSupplyAirOutletTemperatureControl(true)
      erv.setFrostControlType(hx['frost_control'])
      eff = rule['effectiveness']
      erv.setSensibleEffectivenessat100HeatingAirFlow(eff)
      erv.setLatentEffectivenessat100HeatingAirFlow(eff)
      erv.setSensibleEffectivenessat100CoolingAirFlow(eff)
      erv.setLatentEffectivenessat100CoolingAirFlow(eff)
      if erv.respond_to?(:setSensibleEffectivenessat75HeatingAirFlow)
        erv.setSensibleEffectivenessat75HeatingAirFlow(eff)
        erv.setLatentEffectivenessat75HeatingAirFlow(eff)
        erv.setSensibleEffectivenessat75CoolingAirFlow(eff)
        erv.setLatentEffectivenessat75CoolingAirFlow(eff)
      end
      erv.setThresholdTemperature(hx['threshold_temperature_c'])
      erv.setInitialDefrostTimeFraction(hx['initial_defrost_time_fraction'])
      erv.setRateofDefrostTimeFractionIncrease(hx['rate_of_defrost_increase'])
      erv.addToNode(oa_system.outboardOANode.get)

      # T6 (audit 2026-07-25): the wheel is not free — PNNL-20405 surrogate
      # for rotary-HX fan/motor parasitics (legacy parity), computed from the
      # sized min OA; and the OA controller must bypass the wheel when OA
      # exceeds minimum (economizer-compatible behaviour on mixed systems).
      ctrl = oa_system.getControllerOutdoorAir
      oa_flow = ctrl.minimumOutdoorAirFlowRate.is_initialized ? ctrl.minimumOutdoorAirFlowRate.get : nil
      oa_flow ||= ctrl.autosizedMinimumOutdoorAirFlowRate.is_initialized ? ctrl.autosizedMinimumOutdoorAirFlowRate.get : nil
      if oa_flow
        erv.setNominalElectricPower((oa_flow * 212.5 / 0.5) + (oa_flow * 0.9 * 162.5 / 0.5) + 50.0)
      end
      ctrl.setHeatRecoveryBypassControlType('BypassWhenOAFlowGreaterThanMinimum')

      spm = OpenStudio::Model::SetpointManagerOutdoorAirPretreat.new(model)
      spm.setMinimumSetpointTemperature(-99.0)
      spm.setMaximumSetpointTemperature(99.0)
      spm.setMinimumSetpointHumidityRatio(0.00001)
      spm.setMaximumSetpointHumidityRatio(1.0)
      mixed_air_node = oa_system.mixedAirModelObject.get.to_Node.get
      spm.setReferenceSetpointNode(mixed_air_node)
      spm.setMixedAirStreamNode(mixed_air_node)
      spm.setOutdoorAirStreamNode(oa_system.outboardOANode.get)
      spm.setReturnAirStreamNode(oa_system.returnAirModelObject.get.to_Node.get)
      spm.addToNode(erv.primaryAirOutletModelObject.get.to_Node.get)
      erv
    end

    # ---- internals (not API) ----
    private_class_method :add_energy_recovery
  end
end
