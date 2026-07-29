module OpenStudioHVAC
  module NECB
    # Part 5 prescriptive QAQC checker (first slice) — WARNINGS ONLY, never
    # modifies the model. Checks a PROPOSED design against:
    #   5.2.2.8  air economizer capability on mechanically-cooled air systems
    #   5.2.10.1 heat/energy recovery where the Table 5.2.10.1.-A/-B airflow
    #            thresholds are met (the same table trigger the reference pass
    #            uses; needs hdd: and SIZED supply/OA flows)
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

      # @param hdd [Numeric, nil] heating degree-days — enables the 5.2.10.1
      #   heat-recovery check (skipped with an info note otherwise)
      # @param building [Hash, nil] unused (kept for call-site compatibility;
      #   the old 150 kW trigger read winter_design_temp_c from it)
      # @return [AuditLog]
      def check_part5(model, vintage: '2020', building: nil, hdd: nil, audit: nil)
        audit ||= AuditLog.new
        check_economizers(model, audit)
        check_heat_recovery(model, vintage, hdd, audit)
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

          cooled = Coils.supply_components(air_loop).any? { |c| c.iddObjectType.valueName =~ /Coil_Cooling|CoilSystem_Cooling/ }
          next unless cooled

          controller = oa_system.get.getControllerOutdoorAir
          if controller.getEconomizerControlType == 'NoEconomizer'
            # D-56: cooling with outside air can be satisfied INDIRECTLY. Where the
            # loop's chilled water already carries a 5.2.2.9 water-side economizer,
            # 5.2.2.9 is the applicable article and the absence of an AIR economizer
            # is not a finding — the old warning fired on exactly the loops the
            # reference builder now equips.
            if (economized = water_economizer_loops(air_loop)).any?
              audit.info(:check_part5, 'no air economizer, but the chilled water is cooled by a 5.2.2.9 water-side ' \
                                       'economizer — cooling with outside air is provided indirectly',
                         target: air_loop.nameString, inputs: { plant_loops: economized },
                         article: '5.2.2.9.', ruling: 'D-56')
              next
            end
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

      # Names of the chilled-water loops feeding this air loop's water cooling coils
      # that carry a water-side economizer heat exchanger (D-56).
      def water_economizer_loops(air_loop)
        Coils.supply_components(air_loop).filter_map do |component|
          next unless component.respond_to?(:to_CoilCoolingWater) && component.to_CoilCoolingWater.is_initialized

          plant = component.to_CoilCoolingWater.get.plantLoop
          next unless plant.is_initialized
          next unless plant.get.supplyComponents(OpenStudio::Model::HeatExchangerFluidToFluid.iddObjectType).any?

          plant.get.nameString
        end.uniq
      end

      # 5.2.10.1: same Table 5.2.10.1.-A/-B trigger as the reference ERV rule.
      def check_heat_recovery(model, vintage, hdd, audit)
        if hdd.nil?
          audit.info(:check_part5, '5.2.10.1 heat-recovery check skipped — pass hdd: to evaluate the ' \
                                   'Table 5.2.10.1.-A/-B airflow thresholds')
          return
        end

        rule = NECB.rules(vintage)['energy_recovery']
        return if rule.nil?

        model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
          oa_system = air_loop.airLoopHVACOutdoorAirSystem
          next if oa_system.empty?

          supply = NECB.optional_flow(air_loop.designSupplyAirFlowRate) ||
                   NECB.optional_flow(air_loop.autosizedDesignSupplyAirFlowRate)
          ctrl = oa_system.get.getControllerOutdoorAir
          min_oa = NECB.optional_flow(ctrl.minimumOutdoorAirFlowRate) ||
                   NECB.optional_flow(ctrl.autosizedMinimumOutdoorAirFlowRate)
          if supply.nil? || min_oa.nil? || supply.zero?
            audit.info(:check_part5, '5.2.10.1 heat-recovery check needs SIZED supply/OA flows — not evaluated ' \
                                     '(run sizing first)', target: air_loop.nameString)
            next
          end

          oa_pct = 100.0 * min_oa / supply
          hours = NECB.annual_availability_hours(air_loop)
          mode = hours.nil? || hours >= rule['continuous_hours_per_year'] ? 'continuous' : 'non_continuous'
          required, threshold_desc = NECB.erv_threshold_verdict(rule, mode, hdd, oa_pct, supply * 1000.0)
          next unless required

          has_recovery = oa_system.get.oaComponents.any? { |c| c.iddObjectType.valueName =~ /HeatExchanger/ }
          next if has_recovery

          audit.warn(:check_part5,
                     "supply #{(supply * 1000).round} L/s at #{oa_pct.round(1)}% OA (#{mode.tr('_', '-')}) meets the " \
                     "Table 5.2.10.1 trigger (#{threshold_desc}) but NO heat/energy recovery is present — " \
                     '5.2.10.1 requires it',
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
        unsized += model.getCoilCoolingDXMultiSpeeds.count do |c|
          top = c.stages.last
          top.nil? || (top.grossRatedTotalCoolingCapacity.empty? && !top.autosizedGrossRatedTotalCoolingCapacity.is_initialized)
        end
        if unsized.positive?
          audit.info(:check_part5, "#{unsized} DX coil(s) unsized — capacity-binned 5.2.12 minimums cannot be " \
                                   'checked for them; run sizing first for full coverage')
        end

        pairs = [
          [:getBoilerHotWaters, ->(b) { b.nominalThermalEfficiency }, 'boiler nominal thermal efficiency'],
          [:getChillerElectricEIRs, ->(c) { c.referenceCOP }, 'chiller reference COP'],
          [:getCoilCoolingDXSingleSpeeds, ->(c) { c.ratedCOP.respond_to?(:get) && c.ratedCOP.is_initialized ? c.ratedCOP.get : c.ratedCOP }, 'DX cooling rated COP'],
          [:getCoilHeatingDXSingleSpeeds, ->(c) { c.ratedCOP }, 'DX heating rated COP'],
          [:getCoilHeatingGass, ->(c) { c.gasBurnerEfficiency }, 'gas coil burner efficiency'],
          # staged coils carry their performance on the STAGES; the efficiency
          # pass writes one row's value to every stage, so the top stage is
          # representative of the whole coil
          [:getCoilCoolingDXMultiSpeeds, ->(c) { c.stages.last&.grossRatedCoolingCOP }, 'staged DX cooling rated COP'],
          [:getCoilHeatingDXMultiSpeeds, ->(c) { c.stages.last&.grossRatedHeatingCOP }, 'staged DX heating rated COP'],
          [:getCoilHeatingGasMultiStages, ->(c) { c.stages.last&.gasBurnerEfficiency }, 'staged gas coil burner efficiency']
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
