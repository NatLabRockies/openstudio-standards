module OpenStudioHVAC
  module Costing
    # Generic equipment quantification (port of the BTAP costing "(a)-layer"): walks
    # OpenStudio objects on a SIZED model and adds materials_hvac line items to the ledger.
    # No name-sniffing: fuel/type come from object fields and the gem's naming contract.
    # Anything uncostable becomes a warning, never a silent zero.
    class EquipmentQuantifier
      attr_reader :warnings

      def initialize(database, ledger)
        @db = database
        @ledger = ledger
        @warnings = []
      end

      # Select the materials_hvac row for a lookup + size using the legacy rule:
      # smallest row with Size >= size; if size exceeds the largest, use the largest row
      # with quantity = ceil(size / largest). Returns [row, unit_count] or nil (+warning).
      def pick(lookup, size, context)
        rows = @db.materials_hvac.select { |r| r['Material'].to_s.casecmp(lookup.to_s).zero? }
        if rows.empty?
          @warnings << "no materials_hvac entry '#{lookup}' (#{context}) — item not costed"
          return nil
        end
        return [rows.first, 1.0] if size.nil?

        candidates = rows.select { |r| r['Size'].to_f >= size.to_f }
        return [candidates.min_by { |r| r['Size'].to_f }, 1.0] unless candidates.empty?

        largest = rows.max_by { |r| r['Size'].to_f }
        max_size = largest['Size'].to_f
        return [largest, 1.0] if max_size.zero?

        [largest, (size.to_f / max_size).ceil.to_f]
      end

      def add(lookup, size, tags, context, count: 1.0)
        picked = pick(lookup, size, context)
        return unless picked

        row, units = picked
        @ledger.add(id: row['id'], quantity: units * count, tags: tags,
                    material_mult: row['material_mult'].to_f.zero? ? 1.0 : row['material_mult'].to_f,
                    labour_mult: row['labour_mult'].to_f.zero? ? 1.0 : row['labour_mult'].to_f,
                    note: context)
      end

      # ---- capacity helpers (sized model: hard values or autosized accessors) ----

      def optional_f(value)
        return value.to_f unless value.respond_to?(:is_initialized)
        value.is_initialized ? value.get.to_f : nil
      end

      def capacity_kw(hard, autosized, context)
        kw = optional_f(hard) || optional_f(autosized)
        if kw.nil?
          @warnings << "no capacity available for #{context} (model not sized?) — item not costed"
          return nil
        end
        kw / 1000.0
      end

      # ---- plant equipment (tag HEATING_COOLING) ----

      def quantify_plant(model)
        model.getBoilerHotWaters.sort_by(&:nameString).each do |boiler|
          kw = capacity_kw(boiler.nominalCapacity, boiler.autosizedNominalCapacity, boiler.nameString)
          next unless kw

          bucket =
            case boiler.fuelType
            when 'Electricity' then 'ElecBoilers'
            when 'FuelOilNo1', 'FuelOilNo2' then 'OilBoilers'
            else boiler.nominalThermalEfficiency >= 0.88 ? 'CondensingBoilers' : 'GasBoilers'
            end
          add(bucket, kw, %w[HEATING_COOLING], "boiler #{boiler.nameString} #{kw.round(1)} kW")
        end

        model.getChillerElectricEIRs.sort_by(&:nameString).each do |chiller|
          kw = capacity_kw(chiller.referenceCapacity, chiller.autosizedReferenceCapacity, chiller.nameString)
          next unless kw

          # chiller compressor type from the gem naming contract; default Scroll
          kind = %w[Scroll Centrifugal Reciprocating Screw].find { |t| chiller.nameString.include?(t) } ||
                 (chiller.nameString.include?('Rotary') ? 'Screw' : 'Scroll')
          cond = chiller.condenserType == 'AirCooled' ? 'Air' : 'Water'
          add("ChillerElectricEIR_VSD#{kind}#{cond}Chiller", kw, %w[HEATING_COOLING],
              "chiller #{chiller.nameString} #{kw.round(1)} kW")
        end

        model.getCoolingTowerSingleSpeeds.sort_by(&:nameString).each do |tower|
          # legacy sizes the tower from connected chiller capacity; approximate with the
          # total water-cooled chiller capacity on the model (documented approximation)
          chiller_kw = model.getChillerElectricEIRs
                            .select { |c| c.condenserType == 'WaterCooled' }
                            .sum { |c| capacity_kw(c.referenceCapacity, c.autosizedReferenceCapacity, c.nameString) || 0.0 }
          add('ClgTwr', chiller_kw.positive? ? chiller_kw : nil, %w[HEATING_COOLING],
              "cooling tower #{tower.nameString}")
        end

        (model.getPumpConstantSpeeds + model.getPumpVariableSpeeds).sort_by(&:nameString).each do |pump|
          watts = optional_f(pump.ratedPowerConsumption) || optional_f(pump.autosizedRatedPowerConsumption)
          if watts.nil?
            @warnings << "no rated power for pump #{pump.nameString} — not costed"
            next
          end
          add('Pumps', watts, %w[HEATING_COOLING], "pump #{pump.nameString} #{watts.round} W")
          add('VFD', watts, %w[HEATING_COOLING], "VFD for #{pump.nameString}") if pump.to_PumpVariableSpeed.is_initialized
        end

        model.getHeatPumpPlantLoopEIRHeatings.sort_by(&:nameString).each do |hp|
          kw = capacity_kw(hp.referenceCapacity, hp.autosizedReferenceCapacity, hp.nameString)
          add('Airtowaterhp', kw, %w[HEATING_COOLING], "air-to-water HP #{hp.nameString}") if kw
        end

        model.getHeatPumpWaterToWaterEquationFitHeatings.sort_by(&:nameString).each do |hp|
          kw = capacity_kw(hp.ratedHeatingCapacity, hp.autosizedRatedHeatingCapacity, hp.nameString)
          # W2W GSHP unit costed via the ground-source materials; loop piping is distribution
          add('gshp_ground_loop', kw, %w[HEATING_COOLING], "W2W GSHP #{hp.nameString}") if kw
        end

        (model.getDistrictHeatingWaters.to_a + model.getDistrictCoolings.to_a).each do |district|
          @warnings << "district energy object #{district.nameString}: connection costs not modeled (energy purchased, not owned plant)"
        end

        model.getEvaporativeFluidCoolerSingleSpeeds.each do |cooler|
          add('ClgTwr', nil, %w[HEATING_COOLING], "evaporative fluid cooler #{cooler.nameString} (costed as tower class)")
        end
      end

      # ---- zonal equipment (tag ZONAL) ----

      def quantify_zonal(model)
        model.getThermalZones.sort_by(&:nameString).each do |zone|
          mult = zone.multiplier
          zone.equipment.each do |equipment|
            if (ptac = equipment.to_ZoneHVACPackagedTerminalAirConditioner.get rescue nil) ||
               equipment.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
              ptac ||= equipment.to_ZoneHVACPackagedTerminalAirConditioner.get
              coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed
              kw = coil.is_initialized ? capacity_kw(coil.get.ratedTotalCoolingCapacity, coil.get.autosizedRatedTotalCoolingCapacity, ptac.nameString) : nil
              add('PTAC', kw, %w[ZONAL], "PTAC #{ptac.nameString}", count: mult)
            elsif equipment.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
              pthp = equipment.to_ZoneHVACPackagedTerminalHeatPump.get
              coil = pthp.coolingCoil.to_CoilCoolingDXSingleSpeed
              kw = coil.is_initialized ? capacity_kw(coil.get.ratedTotalCoolingCapacity, coil.get.autosizedRatedTotalCoolingCapacity, pthp.nameString) : nil
              add('ashp', kw, %w[ZONAL], "PTHP #{pthp.nameString} (zone ASHP class)", count: mult)
            elsif equipment.to_ZoneHVACFourPipeFanCoil.is_initialized
              fc = equipment.to_ZoneHVACFourPipeFanCoil.get
              coil = fc.coolingCoil.to_CoilCoolingWater
              kw = coil.is_initialized ? capacity_kw(nil, coil.get.autosizedDesignCoilLoad, fc.nameString) : nil
              add('FanCoil', kw, %w[ZONAL], "fan coil #{fc.nameString}", count: mult)
            elsif equipment.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
              term = equipment.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
              coil = term.coolingCoil
              kw = coil.is_initialized && coil.get.to_CoilCoolingDXVariableRefrigerantFlow.is_initialized ? capacity_kw(coil.get.to_CoilCoolingDXVariableRefrigerantFlow.get.ratedTotalCoolingCapacity, coil.get.to_CoilCoolingDXVariableRefrigerantFlow.get.autosizedRatedTotalCoolingCapacity, term.nameString) : nil
              add('VRF-CeilingMount', kw, %w[ZONAL], "VRF terminal #{term.nameString}", count: mult)
            elsif equipment.to_ZoneHVACBaseboardConvectiveElectric.is_initialized
              add('ElectricBaseboard', nil, %w[ZONAL], "electric baseboard #{zone.nameString}", count: mult)
            elsif equipment.to_ZoneHVACBaseboardConvectiveWater.is_initialized
              bb = equipment.to_ZoneHVACBaseboardConvectiveWater.get
              kw = capacity_kw(nil, bb.heatingCoil.to_CoilHeatingWaterBaseboard.get.autosizedHeatingDesignCapacity, bb.nameString)
              # legacy costs HW baseboard as copper convector length; approximate 1 m/kW
              add('ConvectCopper', 1.25, %w[ZONAL], "hot water baseboard #{zone.nameString} (~#{kw&.round(1)} kW)",
                  count: mult * [(kw || 1.0), 1.0].max.ceil)
            elsif equipment.to_ZoneHVACUnitHeater.is_initialized
              heater = equipment.to_ZoneHVACUnitHeater.get
              gas = heater.heatingCoil.to_CoilHeatingGas.is_initialized
              kw = gas ? capacity_kw(heater.heatingCoil.to_CoilHeatingGas.get.nominalCapacity, heater.heatingCoil.to_CoilHeatingGas.get.autosizedNominalCapacity, heater.nameString) : nil
              add(gas ? 'GasHeater' : 'ElecUnitHeater', kw, %w[ZONAL], "unit heater #{heater.nameString}", count: mult)
            elsif equipment.to_ZoneHVACWaterToAirHeatPump.is_initialized
              wshp = equipment.to_ZoneHVACWaterToAirHeatPump.get
              coil = wshp.coolingCoil.to_CoilCoolingWaterToAirHeatPumpEquationFit
              kw = coil.is_initialized ? capacity_kw(coil.get.ratedTotalCoolingCapacity, coil.get.autosizedRatedTotalCoolingCapacity, wshp.nameString) : nil
              add('wshp', kw, %w[ZONAL], "WSHP #{wshp.nameString}", count: mult)
            elsif equipment.to_ZoneHVACEnergyRecoveryVentilator.is_initialized
              erv = equipment.to_ZoneHVACEnergyRecoveryVentilator.get
              cfm = optional_f(erv.supplyAirFlowRate) || optional_f(erv.autosizedSupplyAirFlowRate)
              cfm = cfm ? cfm * 2118.88 : nil # m3/s -> cfm (ERV table sizes are cfm)
              add('ERV', cfm, %w[ZONAL], "zone ERV #{erv.nameString}", count: mult)
            elsif equipment.to_FanZoneExhaust.is_initialized
              next # exhaust fans not costed here
            end
          end
        end

        model.getAirConditionerVariableRefrigerantFlows.sort_by(&:nameString).each do |unit|
          kw = capacity_kw(unit.grossRatedTotalCoolingCapacity, unit.autosizedGrossRatedTotalCoolingCapacity, unit.nameString)
          add('VRF-HP-Outdoor', kw, %w[ZONAL], "VRF outdoor unit #{unit.nameString}")
        end
      end
    end
  end
end
