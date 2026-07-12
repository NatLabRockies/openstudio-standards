module OpenStudioHVAC
  module Costing
    # Generic equipment quantification (port of the BTAP costing "(a)-layer"): walks
    # OpenStudio objects on a SIZED model and adds materials_hvac line items to the ledger.
    # No name-sniffing: fuel/type come from object fields and the gem's naming contract.
    # Anything uncostable becomes a warning, never a silent zero.
    class EquipmentQuantifier
      attr_reader :warnings

      def initialize(database, ledger, mech_room_name: nil, audit: nil)
        @db = database
        @ledger = ledger
        @mech_room_name = mech_room_name
        @audit = audit
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

        # legacy get_vent_system_mult: N units of a smaller row that covers size/N
        units = (size.to_f / max_size).ceil.to_f
        per_unit = size.to_f / units
        row = rows.select { |r| r['Size'].to_f >= per_unit }.min_by { |r| r['Size'].to_f } || largest
        [row, units]
      end

      def add(lookup, size, tags, context, count: 1.0)
        picked = pick(lookup, size, context)
        return unless picked

        row, units = picked
        @ledger.add(id: row['id'], quantity: units * count, tags: tags,
                    material_mult: row['material_mult'].to_f.zero? ? 1.0 : row['material_mult'].to_f,
                    labour_mult: row['labour_mult'].to_f.zero? ? 1.0 : row['labour_mult'].to_f,
                    note: context)
        @audit&.decision(:costing_equipment, context,
                         inputs: { lookup: lookup, size: size.is_a?(Numeric) ? size.round(2) : size },
                         value: "item #{row['id']} x #{(units * count).round(3)}",
                         evidence: row['description'].to_s[0, 70],
                         article: 'materials_hvac (next-largest-size rule)')
        units
      end

      # Building geometry data (legacy getGeometryData), memoized per model.
      def geo(model)
        return @geo if defined?(@geo_model) && @geo_model == model

        @geo_model = model
        @geo = Geometry.building_data(model, mech_room_name: @mech_room_name)
        if @geo.nil?
          @warnings << 'building geometry could not be resolved (no conditioned spaces?) — utility runs/flues/header piping not costed'
        else
          @audit&.decision(:costing_geometry, 'building geometry resolved for distance-based items',
                           target: @geo[:mech_room][:space].nameString,
                           inputs: { storeys: @geo[:storeys], mech_room_in_basement: @geo[:mech_room_in_basement] },
                           value: "utility #{@geo[:util_dist_ft].round(1)} ft, roof #{@geo[:ht_roof_ft].round(1)} ft, " \
                                  "horizontal #{@geo[:horz_dist_ft].round(1)} ft, floor height #{@geo[:flr_height_ft].round(1)} ft",
                           article: 'legacy getGeometryData port')
        end
        @geo
      end

      # ---- capacity helpers (sized model: hard values or autosized accessors) ----

      def optional_f(value)
        return nil if value.nil?
        return value.to_f unless value.respond_to?(:is_initialized)
        value.is_initialized ? value.get.to_f : nil
      end

      # Zone design heating load from the ZoneSizes SQL table (legacy zonalsys_costing
      # capacity source) — fallback when a zonal coil's autosized capacity is empty.
      def sql_zone_heating_kw(model, zone_name)
        return nil unless model.sqlFile.is_initialized

        query = "SELECT UserDesLoad FROM ZoneSizes WHERE ZoneName='#{zone_name.upcase}' AND LoadType='Heating'"
        value = model.sqlFile.get.execAndReturnFirstDouble(query)
        value.is_initialized && value.get.positive? ? value.get / 1000.0 : nil
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

        quantify_plant_geometry(model)
      end

      # ---- geometry-derived plant costs (legacy boiler/chiller/tower costing:
      #      flues, fuel lines, electrical runs, piping to pumps, header piping) ----

      def quantify_plant_geometry(model)
        data = geo(model)
        return if data.nil?

        model.getPlantLoops.sort_by(&:nameString).each do |loop|
          boilers = []
          chillers = []
          towers = []
          pumps = []
          loop.supplyComponents.each do |comp|
            boilers << comp.to_BoilerHotWater.get if comp.to_BoilerHotWater.is_initialized
            chillers << comp.to_ChillerElectricEIR.get if comp.to_ChillerElectricEIR.is_initialized
            towers << comp.to_CoolingTowerSingleSpeed.get if comp.to_CoolingTowerSingleSpeed.is_initialized
            pumps << comp.to_PumpConstantSpeed.get if comp.to_PumpConstantSpeed.is_initialized
            pumps << comp.to_PumpVariableSpeed.get if comp.to_PumpVariableSpeed.is_initialized
          end
          if !boilers.empty?
            cost_boiler_loop_geometry(loop, boilers, pumps, data)
          elsif !chillers.empty?
            cost_chiller_loop_geometry(loop, chillers, pumps, data)
          elsif !towers.empty?
            cost_tower_loop_geometry(loop, towers, pumps, data)
          end
        end
      end

      # Legacy boiler_costing geometry items: flue (6" venting up past the roof, elbow and
      # top; header when multiple combustion boilers), fuel line + electrical run over the
      # mech-room utility distance, piping to pumps, and hot-water header distribution.
      def cost_boiler_loop_geometry(loop, boilers, pumps, data)
        note = "plant utilities (#{loop.nameString})"
        util = data[:util_dist_ft]
        combustion = boilers.reject { |b| b.fuelType == 'Electricity' }

        unless combustion.empty?
          add('Venting', 6, %w[HEATING_COOLING], "boiler flue #{note}", count: data[:ht_roof_ft])
          add('VentingElbow', 6, %w[HEATING_COOLING], "boiler flue elbow #{note}")
          add('VentingTop', 6, %w[HEATING_COOLING], "boiler flue top #{note}")
          if combustion.size > 1 # flue header: 20 ft + an elbow per connected boiler
            add('Venting', 6, %w[HEATING_COOLING], "boiler flue header #{note}", count: 20.0 * combustion.size)
            add('VentingElbow', 6, %w[HEATING_COOLING], "boiler flue header elbows #{note}", count: combustion.size.to_f)
          end
          gas_line(util, combustion.size, note)
          oil = combustion.select { |b| b.fuelType.to_s =~ /Oil/i }
          unless oil.empty?
            add('OilLine', nil, %w[HEATING_COOLING], "oil filtering system #{note}")
            add('OilTanks', 2000, %w[HEATING_COOLING], "oil tank #{note}")
          end
        end
        electrical_run(util, note)
        piping_to_pumps(pumps.size, boilers.size, note)
        header_distribution(pumps, data, note)
      end

      # Legacy chiller_costing geometry items (electric chillers): electrical run,
      # piping to pumps, and chilled-water header distribution.
      def cost_chiller_loop_geometry(loop, chillers, pumps, data)
        note = "plant utilities (#{loop.nameString})"
        electrical_run(data[:util_dist_ft], note)
        piping_to_pumps(pumps.size, chillers.size, note)
        header_distribution(pumps, data, note)
      end

      # Legacy coolingtower_costing geometry items: electrical run up to the roof and the
      # 4" condenser piping riser.
      def cost_tower_loop_geometry(loop, towers, pumps, data)
        note = "condenser utilities (#{loop.nameString})"
        run = data[:ht_roof_ft] + 20.0
        towers.each do
          add('Wiring', 14, %w[HEATING_COOLING], "tower electrical #{note}", count: run / 100.0)
          add('Conduit', nil, %w[HEATING_COOLING], "tower conduit #{note}", count: run)
        end
        length = data[:ht_roof_ft] * 2 + 10.0 * pumps.size
        add('SteelPipe', 4, %w[HEATING_COOLING], "condenser riser piping #{note}", count: length)
        add('PipeInsulation', 4, %w[HEATING_COOLING], "condenser riser insulation #{note}", count: length)
        add('SteelPipeTee', 4, %w[HEATING_COOLING], "condenser piping tees #{note}", count: pumps.size.to_f)
        add('ValvesBFly', 4, %w[HEATING_COOLING], "condenser butterfly valves #{note}", count: pumps.size.to_f)
      end

      def gas_line(util_dist_ft, unit_count, note)
        add('GasLine', nil, %w[HEATING_COOLING], "fuel line #{note}", count: util_dist_ft) # L.F. row
        add('GasLine', 4, %w[HEATING_COOLING], "fuel line fittings #{note}", count: unit_count.to_f) # 'each' row
      end

      def electrical_run(util_dist_ft, note)
        add('Wiring', 14, %w[HEATING_COOLING], "electrical wire #{note}", count: util_dist_ft / 100.0)
        add('Conduit', nil, %w[HEATING_COOLING], "electrical conduit #{note}", count: util_dist_ft)
      end

      # Legacy: 10 ft of 1" pipe + insulation, 2 elbows and a gate valve per pump, times
      # the number of primary units on the loop.
      def piping_to_pumps(pump_count, unit_count, note)
        return if pump_count.zero? || unit_count.zero?

        factor = pump_count * unit_count
        add('SteelPipe', 1, %w[HEATING_COOLING], "piping to pumps #{note}", count: 10.0 * factor)
        add('PipeInsulation', 1, %w[HEATING_COOLING], "pump piping insulation #{note}", count: 10.0 * factor)
        add('SteelPipeElbow', 1, %w[HEATING_COOLING], "pump piping elbows #{note}", count: 2.0 * factor)
        add('ValvesGate', 1, %w[HEATING_COOLING], "pump gate valves #{note}", count: 1.0 * factor)
      end

      # Legacy getHeaderPipingDistributionCost: supply+return header piping sized by pump
      # flow (>2 storeys) plus the electrical header (conduit/wiring/box per storey).
      def header_distribution(pumps, data, note)
        storeys = data[:storeys] + (data[:mech_room_in_basement] ? 1 : 0)
        flr = data[:flr_height_ft]
        if storeys < 3
          length = storeys * flr
          dia = 1.25
        else
          flow = pumps.sum do |pump|
            optional_f(pump.ratedFlowRate) || optional_f(pump.autosizedRatedFlowRate) || 0.0
          end
          dia = if flow <= 0.0001262 then 0.5
                elsif flow <= 0.0002524 then 0.75
                elsif flow <= 0.0005047 then 1.0
                elsif flow <= 0.0010090 then 1.25
                elsif flow <= 0.0015773 then 1.5
                elsif flow <= 0.0031545 then 2.0
                else 2.5
                end
          length = data[:horz_dist_ft] + flr * storeys
        end
        # supply + return headers (x2)
        add('SteelPipe', dia, %w[HEATING_COOLING], "header piping #{note}", count: 2.0 * length)
        add('PipeInsulation', dia, %w[HEATING_COOLING], "header pipe insulation #{note}", count: 2.0 * length)
        add('ValvesGate', dia, %w[HEATING_COOLING], "header gate valves #{note}", count: 2.0)
        add('SteelPipeTee', dia, %w[HEATING_COOLING], "header tees #{note}", count: 2.0)
        # electrical header for zonal units
        hdr = storeys * flr
        add('Conduit', nil, %w[HEATING_COOLING], "header conduit #{note}", count: hdr)
        add('Wiring', 10, %w[HEATING_COOLING], "header wiring #{note}", count: hdr / 100.0)
        add('Box', 4, %w[HEATING_COOLING], "header boxes #{note}", count: storeys.to_f)
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
              units = add('PTAC', kw, %w[ZONAL], "PTAC #{ptac.nameString}", count: mult) || 1.0
              # legacy: one electrical junction box per PTAC unit
              add('Box', 1, %w[ZONAL], "PTAC junction box #{ptac.nameString}", count: units * mult)
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
              bb = equipment.to_ZoneHVACBaseboardConvectiveElectric.get
              kw = capacity_kw(bb.nominalCapacity, bb.autosizedNominalCapacity, "electric baseboard #{bb.nameString}")
              cost_electric_baseboard(model, zone, kw, mult)
            elsif equipment.to_ZoneHVACBaseboardConvectiveWater.is_initialized
              bb = equipment.to_ZoneHVACBaseboardConvectiveWater.get
              coil = bb.heatingCoil.to_CoilHeatingWaterBaseboard.get
              kw = optional_f(coil.heatingDesignCapacity) || optional_f(coil.autosizedHeatingDesignCapacity)
              kw = kw.nil? || kw.zero? ? sql_zone_heating_kw(model, zone.nameString) : kw / 1000.0
              if kw.nil?
                @warnings << "no capacity available for hot water baseboard #{bb.nameString} (model not sized?) — item not costed"
              else
                cost_hw_baseboard(model, zone, kw, mult)
              end
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

      # Legacy convector-count rule: ratio rounds up only when the fractional part
      # exceeds 0.10 (otherwise the fractional count is used as-is).
      def legacy_unit_count(ratio)
        (ratio - ratio.to_i) > 0.10 ? (ratio + 0.5).round.to_f : ratio
      end

      # Legacy zonalsys_costing 'Baseboard Convective Water': copper convector core at
      # 0.425 kW/ft with an isolation valve, 2 tees and 2 elbows per 8-ft convector, plus
      # perimeter supply/return distribution piping along the exterior wall.
      def cost_hw_baseboard(model, zone, kw, mult)
        return if kw.nil? || kw <= 0.0

        note = "hot water baseboard #{zone.nameString}"
        conv_length = (kw / 0.425).round.to_f
        convectors = legacy_unit_count(conv_length / 8.0)
        add('ConvectCopper', 1.25, %w[ZONAL], "#{note} convector", count: conv_length * mult)
        add('ValvesGate', 1.25, %w[ZONAL], "#{note} valves", count: convectors * mult)
        add('CopperPipeTee', 1.25, %w[ZONAL], "#{note} tees", count: 2 * convectors * mult)
        add('CopperPipeElbow', 1.25, %w[ZONAL], "#{note} elbows", count: 2 * convectors * mult)

        data = geo(model)
        return if data.nil? || data[:flr_height_ft] <= 0.0

        perim_ft = Geometry.zone_exterior_wall_area_ft2(zone) / data[:flr_height_ft] * mult
        add('SteelPipe', 1.25, %w[ZONAL], "#{note} perimeter piping", count: perim_ft)
        add('PipeInsulation', 1.25, %w[ZONAL], "#{note} perimeter pipe insulation", count: perim_ft)
      end

      # Legacy zonalsys_costing 'Baseboard Convective Electric': 0.935 kW units, each
      # with a junction box, plus perimeter wiring/conduit along the exterior wall.
      def cost_electric_baseboard(model, zone, kw, mult)
        return if kw.nil? || kw <= 0.0

        note = "electric baseboard #{zone.nameString}"
        units = legacy_unit_count(kw / 0.935)
        add('ElectricBaseboard', nil, %w[ZONAL], note, count: units * mult)
        add('Box', 1, %w[ZONAL], "#{note} junction boxes", count: units * mult)

        data = geo(model)
        return if data.nil? || data[:flr_height_ft] <= 0.0

        perim_ft = Geometry.zone_exterior_wall_area_ft2(zone) / data[:flr_height_ft] * mult
        add('Conduit', nil, %w[ZONAL], "#{note} perimeter conduit", count: perim_ft)
        add('Wiring', 10, %w[ZONAL], "#{note} perimeter wiring", count: perim_ft / 100.0)
      end
    end
  end
end
