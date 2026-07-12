module OpenStudioHVAC
  module NECB
    # Part 5 prescriptive QAQC checker (first slice) — WARNINGS ONLY, never
    # modifies the model. Checks a PROPOSED design against:
    #   5.2.2.8  air economizer capability on mechanically-cooled air systems
    #   5.2.10.1 heat/energy recovery where the exhaust heat content exceeds
    #            150 kW (the same spec-based trigger the reference pass uses)
    #   5.2.12   equipment minimum efficiencies — checked by applying the NECB
    #            efficiency pass to a CLONE and diffing: any proposed value
    #            below what the pass would set is below the Table 5.2.12.1
    #            minimum (reuses the full lookup machinery with zero drift)
    #
    # Out of this slice (documented): duct/pipe insulation (5.2.2/5.2.5),
    # fan power limits 5.2.3, controls 5.2.8, VAV 5.2.11.
    module Checker
      module_function

      TOLERANCE = 1e-3

      # @param building [Hash, nil] { winter_design_temp_c: } enables the
      #   5.2.10.1 heat-recovery check (skipped with an info note otherwise)
      # @return [AuditLog]
      def check_part5(model, vintage: '2020', building: nil, audit: nil)
        audit ||= AuditLog.new
        check_economizers(model, audit)
        check_heat_recovery(model, vintage, building, audit)
        check_minimum_efficiencies(model, vintage, audit)
        audit.decision(:check_part5, 'Part 5 prescriptive QAQC complete (economizers, heat recovery, ' \
                                     'minimum efficiencies; duct/pipe insulation, fan power limits and ' \
                                     'controls are outside this slice)',
                       inputs: { warnings: audit.warnings.size },
                       article: '5.2.2.8.; 5.2.10.1.; 5.2.12.')
        audit
      end

      # 5.2.2.8.(1): mechanically-cooled systems that could cool with outdoor
      # air must be capable of up to 100% outdoor air.
      def check_economizers(model, audit)
        model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
          oa_system = air_loop.airLoopHVACOutdoorAirSystem
          next if oa_system.empty?

          cooled = air_loop.supplyComponents.any? { |c| c.iddObjectType.valueName =~ /Coil_Cooling|CoilSystem_Cooling/ }
          next unless cooled

          controller = oa_system.get.getControllerOutdoorAir
          if controller.getEconomizerControlType == 'NoEconomizer'
            audit.warn(:check_part5,
                       'mechanically-cooled air system has NO economizer — 5.2.2.8.(1) requires the capability ' \
                       'to mix up to 100% outdoor air with differential reversion (5.2.2.8.(2))',
                       target: air_loop.nameString, article: '5.2.2.8.')
          else
            audit.info(:check_part5, "economizer present (#{controller.getEconomizerControlType})",
                       target: air_loop.nameString, article: '5.2.2.8.')
          end
        end
      end

      # 5.2.10.1: same spec-based trigger as the reference ERV rule.
      def check_heat_recovery(model, vintage, building, audit)
        if building.nil? || building[:winter_design_temp_c].nil?
          audit.info(:check_part5, '5.2.10.1 heat-recovery check skipped — pass building: ' \
                                   '{ winter_design_temp_c: } to evaluate the 150 kW exhaust-heat trigger')
          return
        end

        ruleset = NECB.rules(vintage)
        rule = ruleset['energy_recovery']
        return if rule.nil?

        model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
          oa_system = air_loop.airLoopHVACOutdoorAirSystem
          next if oa_system.empty?

          ehc = NECB.exhaust_heat_content_kw(air_loop, building, audit)
          next if ehc.nil? || ehc <= rule['exhaust_heat_content_threshold_kw']

          has_recovery = !oa_system.get.oaComponents.grep(OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent).empty? ||
                         oa_system.get.oaComponents.any? { |c| c.iddObjectType.valueName =~ /HeatExchanger/ }
          next if has_recovery

          audit.warn(:check_part5,
                     "exhaust heat content #{ehc.round(1)} kW exceeds the #{rule['exhaust_heat_content_threshold_kw']} kW " \
                     'trigger but NO heat/energy recovery is present — 5.2.10.1 requires it',
                     target: air_loop.nameString, article: rule['trigger_article'])
        end
      end

      # 5.2.12: apply the NECB efficiency pass to a clone; any proposed value
      # BELOW the applied value is below the code minimum. Capacity-binned
      # rows need SIZED equipment — unsized items are skipped by the pass
      # (run a sizing run first for full coverage).
      def check_minimum_efficiencies(model, vintage, audit)
        clone = model.clone(true).to_Model
        Efficiency.apply(clone, vintage: vintage)
        unsized = model.getCoilCoolingDXSingleSpeeds.count { |c| c.ratedTotalCoolingCapacity.empty? && !c.autosizedRatedTotalCoolingCapacity.is_initialized }
        if unsized.positive?
          audit.info(:check_part5, "#{unsized} DX coil(s) unsized — capacity-binned 5.2.12 minimums cannot be " \
                                   'checked for them; run sizing first for full coverage')
        end

        pairs = [
          [:getBoilerHotWaters, ->(b) { b.nominalThermalEfficiency }, 'boiler nominal thermal efficiency'],
          [:getChillerElectricEIRs, ->(c) { c.referenceCOP }, 'chiller reference COP'],
          [:getCoilCoolingDXSingleSpeeds, ->(c) { c.ratedCOP.respond_to?(:get) && c.ratedCOP.is_initialized ? c.ratedCOP.get : c.ratedCOP }, 'DX cooling rated COP'],
          [:getCoilHeatingDXSingleSpeeds, ->(c) { c.ratedCOP }, 'DX heating rated COP'],
          [:getCoilHeatingGass, ->(c) { c.gasBurnerEfficiency }, 'gas coil burner efficiency']
        ]
        pairs.each do |getter, reader, label|
          proposed_items = model.send(getter).sort_by(&:nameString)
          minimum_items = clone.send(getter).sort_by(&:nameString)
          proposed_items.zip(minimum_items).each do |proposed, minimum|
            next if minimum.nil?

            current = safe_value(reader, proposed)
            floor = safe_value(reader, minimum)
            next if current.nil? || floor.nil?
            next if current >= floor - TOLERANCE

            audit.warn(:check_part5,
                       "#{label} #{current.round(3)} is BELOW the NECB #{vintage} minimum #{floor.round(3)}",
                       target: proposed.nameString, article: '5.2.12.; Table 5.2.12.1.')
          end
        end
      end

      def safe_value(reader, item)
        value = reader.call(item)
        value = value.get if value.respond_to?(:is_initialized) && value.is_initialized
        value.is_a?(Numeric) ? value : nil
      rescue StandardError
        nil
      end
    end

    def self.check_part5(model, **kwargs)
      Checker.check_part5(model, **kwargs)
    end
  end
end
