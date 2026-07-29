module OpenStudioHVAC
  module Costing
    # Manifest-driven ventilation & distribution costing (the re-architected legacy
    # "(b)-layer"): instead of parsing SYS_n from air-loop names, the AHU assembly class
    # comes from the FAMILY of the gem-built system serving the loop, and coil types are
    # read from the loop's actual components.
    #
    # Ledgered domains (tag VENTILATION — line-item parity with the legacy ledger):
    # - AHU assemblies: every hvac_vent_ahu id_layer x id_quant, scaled by the exact legacy
    #   get_ahu_mult quantity (L/s buckets, ceil unit count, re-select, flow/bucket scale)
    # - air-loop heating/cooling coil equipment (Coils/ElecHeat/FurnaceGas/ashp +
    #   DX condensing unit & refrigerant piping, gas-burner AHU adjustment)
    # - terminal mixing boxes + per-terminal hydronic piping and electrical runs sized by
    #   the storey-centroid-to-roof-centroid Manhattan distance (legacy vav_cost /
    #   reheat_coil_costing / vent_box_elec_cost)
    #
    # Geometry-derived distribution (tag DISTRIBUTION — legacy reports these as totals
    # only, never ledgered): mech-room-to-roof utility lines, central trunk duct, floor
    # trunk ducts, per-zone duct distribution.
    class VentilationQuantifier
      # family -> legacy AHU Sys_type equivalent (nil = no central AHU to cost;
      # fan_coils MAU is skipped exactly as legacy skips sys_type 2 ventilation).
      FAMILY_SYS_TYPE = {
        'mau_ptac' => 1, 'doas' => 1, 'doas_pthp' => 1,
        'ecm_ashp_baseboard' => 1, 'ecm_doas_vrf' => 1, 'ecm_hp_fancoils' => 1,
        'psz' => 3, 'furnace' => 3,
        'vav_reheat' => 6,
        'fan_coils' => nil,
        'evap_cooler' => :distribution_only # no AHU/media cost data exists (legacy never costed evap); ducts/diffusers still costed
      }.freeze

      # single-run supply duct systems (legacy: x1 for sys 1/4 — no return duct)
      SINGLE_RUN_SYS_TYPES = [1, 4].freeze

      RT_ROOF_DIST_FT = 32.8084 # legacy: 10 m allowance per rooftop unit

      attr_reader :warnings

      def initialize(database, ledger, audit: nil)
        @db = database
        @ledger = ledger
        @audit = audit
        @warnings = []
      end

      # @param model [OpenStudio::Model::Model] sized model
      # @param loop_families [Hash{String=>String}] air-loop name -> gem family (from build
      #   results / catalog); loops not in the map produce a warning (foreign ventilation)
      # @param mech_room_name [String, nil] pin the mechanical room space explicitly
      def quantify(model, loop_families, mech_room_name: nil)
        roof_cent = Geometry.highest_roof_centroid(model)
        mech = Geometry.mech_room(model, mech_room_name: mech_room_name)
        @warnings << 'no outdoor roof found — geometry-based ventilation runs not costed' if roof_cent.nil?

        heat_line_counts = Hash.new(0)
        cool_line_counts = Hash.new(0)
        rooftop_units = 0
        total_flow_m3s = 0.0
        sys_1_4 = true
        hvac_floors = {}

        model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
          family = loop_families[air_loop.nameString]
          if family.nil?
            @warnings << "air loop '#{air_loop.nameString}' was not built by this gem — ventilation not costed (plant/zonal still costed)"
            next
          end
          sys_type = FAMILY_SYS_TYPE.fetch(family, nil)
          if sys_type.nil?
            @warnings << "family '#{family}' ventilation (#{air_loop.nameString}) is not AHU-costed (matches legacy sys-2/none handling)"
            next
          end
          flow = flow_m3s(air_loop)
          next if flow.nil?

          total_flow_m3s += flow
          if sys_type == :distribution_only
            @warnings << "family '#{family}' (#{air_loop.nameString}): no unit-cost data for the air handler/media exists (legacy never costed it either); distribution costed"
            sys_type_i = 3
          else
            sys_type_i = sys_type
            units = cost_ahu(air_loop, sys_type_i, flow)
            rooftop_units += units
            cost_airloop_coils(air_loop, sys_type_i, units, flow)
            htg, clg = coil_keys(air_loop)
            heat_line_counts['Gas'] += 1 if htg == 'Gas'
            heat_line_counts['HW'] += 1 if htg == 'HW'
            cool_line_counts['CHW'] += 1 if clg == 'CHW'
          end
          sys_1_4 = false unless SINGLE_RUN_SYS_TYPES.include?(sys_type_i)
          cost_terminals(air_loop, roof_cent)
          cost_hrv(air_loop)
          collect_hvac_floors(hvac_floors, air_loop, sys_type_i)
        end

        cost_mech_to_roof(mech, roof_cent, heat_line_counts, cool_line_counts, rooftop_units) if mech && roof_cent
        cost_trunk_duct(model, total_flow_m3s, roof_cent, sys_1_4) if roof_cent && total_flow_m3s.positive?
        cost_floor_trunk_ducts(hvac_floors, roof_cent) if roof_cent
        cost_zone_distribution(hvac_floors)
      end

      private

      # ---------- shared lookups ----------

      def flow_m3s(air_loop)
        flow = air_loop.designSupplyAirFlowRate
        flow = air_loop.autosizedDesignSupplyAirFlowRate unless flow.is_initialized
        unless flow.is_initialized
          @warnings << "no design supply air flow for #{air_loop.nameString} (model not sized?) — ventilation not costed"
          return nil
        end
        flow.get
      end

      # Staged NECB reference systems hide their coils inside an
      # AirLoopHVACUnitarySystem — Coils.supply_components descends into it. A
      # staged coil costs as the same equipment as its single-speed sibling
      # (a two-stage furnace is still a furnace); capacity comes from the top
      # stage, which is the unit's total.
      def coil_keys(air_loop)
        htg = 'none'
        clg = 'none'
        Coils.supply_components(air_loop).each do |comp|
          htg = 'Gas' if comp.to_CoilHeatingGas.is_initialized || comp.to_CoilHeatingGasMultiStage.is_initialized
          htg = 'elec' if comp.to_CoilHeatingElectric.is_initialized && htg == 'none'
          htg = 'HW' if comp.to_CoilHeatingWater.is_initialized
          htg = 'HP-e' if comp.to_CoilHeatingDXSingleSpeed.is_initialized || comp.to_CoilHeatingDXMultiSpeed.is_initialized
          htg = 'CCASHP-e' if comp.to_CoilHeatingDXVariableSpeed.is_initialized
          clg = 'DX' if comp.to_CoilCoolingDXSingleSpeed.is_initialized || comp.to_CoilCoolingDXTwoSpeed.is_initialized ||
                        comp.to_CoilCoolingDXMultiSpeed.is_initialized
          clg = 'CHW' if comp.to_CoilCoolingWater.is_initialized
          clg = 'CCASHP' if comp.to_CoilCoolingDXVariableSpeed.is_initialized
        end
        [htg, clg]
      end

      # Case-insensitive materials_hvac selection: prefer exact Size, else next-largest,
      # else the largest row. Returns [row, unit_count] (count > 1 when size exceeds the
      # largest available — legacy get_vent_system_mult behavior) or nil with a warning.
      def pick_material(lookup, size, context, unit: nil, exact_size: false)
        rows = @db.materials_hvac.select { |r| r['Material'].to_s.casecmp(lookup.to_s).zero? }
        rows = rows.select { |r| r['unit'].to_s.casecmp(unit.to_s).zero? } if unit
        if rows.empty?
          @warnings << "no materials_hvac entry '#{lookup}' (#{context}) — item not costed"
          return nil
        end
        return [rows.first, 1.0] if size.nil?

        exact = rows.select { |r| r['Size'].to_f == size.to_f }
        return [exact.first, 1.0] unless exact.empty?
        return [rows.first, 1.0] if exact_size # exact requested but absent: first row

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

      def add_item(lookup, size, quantity, tags, context, unit: nil, exact_size: false)
        picked = pick_material(lookup, size, context, unit: unit, exact_size: exact_size)
        return 0.0 unless picked

        row, units = picked
        @ledger.add(id: row['id'], quantity: units * quantity, tags: tags,
                    material_mult: row['material_mult'].to_f.zero? ? 1.0 : row['material_mult'].to_f,
                    labour_mult: row['labour_mult'].to_f.zero? ? 1.0 : row['labour_mult'].to_f,
                    note: context)
        @audit&.decision(tags.include?('DISTRIBUTION') ? :costing_distribution : :costing_ventilation,
                         context,
                         inputs: { lookup: lookup, size: size.is_a?(Numeric) ? size.round(2) : size },
                         value: "item #{row['id']} x #{(units * quantity).round(3)}",
                         evidence: row['description'].to_s[0, 70])
        units
      end

      def mech_table(name)
        @db.mech_sizing.find { |c| c['component'] == name }&.fetch('table', nil)
      end

      # ---------- AHU assembly ----------

      # Exact legacy get_ahu_mult algorithm: number of units = ceil(L/s / largest bucket);
      # re-select the smallest bucket >= L/s-per-unit; scale layers by flow/bucket.
      # Every id_layer is costed with its id_quant (legacy vent_assembly_cost) — the
      # pipe/valve/controls layers ARE the AHU hydronic valve-piping items.
      # @return [Integer] the number of rooftop units
      def cost_ahu(air_loop, sys_type, flow_m3s)
        lps = flow_m3s * 1000.0 # Supply_air buckets are L/s
        htg, clg = coil_keys(air_loop)
        rows = @db.ahu_assemblies.select do |r|
          r['Sys_type'].to_i == sys_type && r['Htg'] == htg && r['Clg'] == clg
        end
        if rows.empty?
          @warnings << "no AHU assembly for sys_type #{sys_type} htg=#{htg} clg=#{clg} (#{air_loop.nameString}) — AHU not costed"
          return 1
        end
        max_bucket = rows.map { |r| r['Supply_air'].to_f }.max
        unit_count = (lps / max_bucket) > (lps / max_bucket).to_i ? (lps / max_bucket).to_i + 1 : (lps / max_bucket).round
        unit_count = 1 if unit_count < 1
        per_unit_lps = lps / unit_count
        row = rows.select { |r| r['Supply_air'].to_f >= per_unit_lps }
                  .min_by { |r| r['Supply_air'].to_f } || rows.max_by { |r| r['Supply_air'].to_f }
        base_quantity = unit_count * (per_unit_lps / row['Supply_air'].to_f)
        @audit&.decision(:costing_ventilation, 'AHU assembly selected (legacy get_ahu_mult rule)',
                         target: air_loop.nameString,
                         inputs: { flow_lps: lps.round(1), sys_type: sys_type, htg: htg, clg: clg,
                                   unit_count: unit_count, bucket_lps: row['Supply_air'].to_f },
                         value: "assembly scaled to #{base_quantity.round(3)} " \
                                "(#{unit_count} unit(s) x #{per_unit_lps.round(0)}/#{row['Supply_air']} L/s)",
                         article: 'hvac_vent_ahu (L/s buckets, ceil units, re-select)')

        # id_layers reference materials_hvac material_id -> map to the cost line-item id
        note = "AHU #{air_loop.nameString} (#{(lps * 2.11888).round} cfm, sys#{sys_type} #{htg}/#{clg})"
        ids = row['id_layers'].to_s.split(',').map(&:strip)
        mults = row['Id_layers_quantity_multipliers'].to_s.split(',').map { |m| m.strip.to_f }
        ids.zip(mults).each do |material_id, mult|
          material = @db.materials_hvac.find { |r| r['material_id'].to_s == material_id }
          if material.nil?
            @warnings << "AHU layer material_id #{material_id} not in materials_hvac — layer not costed (#{note})"
            next
          end
          @ledger.add(id: material['id'], quantity: base_quantity * (mult || 1.0),
                      tags: %w[VENTILATION],
                      material_mult: material['material_mult'].to_f.zero? ? 1.0 : material['material_mult'].to_f,
                      labour_mult: material['labour_mult'].to_f.zero? ? 1.0 : material['labour_mult'].to_f,
                      note: "#{note} [#{material['Material']}]")
        end
        unit_count
      end

      # ---------- air-loop heating/cooling coil equipment ----------

      # Legacy airloop_equipment_costing/cost_heat_cool_equip: each supply coil is costed
      # as equipment on a per-air-handler basis (capacity / unit count, quantity x units).
      def cost_airloop_coils(air_loop, sys_type, units, flow_m3s)
        coils = []
        Coils.supply_components(air_loop).each do |comp|
          if comp.to_CoilHeatingGasMultiStage.is_initialized
            c = comp.to_CoilHeatingGasMultiStage.get
            coils << { role: :heat_gas, lookup: 'FurnaceGas', kw: staged_kw(c), name: c.nameString }
          elsif comp.to_CoilHeatingDXMultiSpeed.is_initialized
            c = comp.to_CoilHeatingDXMultiSpeed.get
            coils << { role: :heat_hp, lookup: 'ashp', kw: staged_kw(c), name: c.nameString }
          elsif comp.to_CoilCoolingDXMultiSpeed.is_initialized
            c = comp.to_CoilCoolingDXMultiSpeed.get
            coils << { role: :cool_dx, lookup: 'coils', kw: staged_kw(c), name: c.nameString }
          elsif comp.to_CoilHeatingWater.is_initialized
            c = comp.to_CoilHeatingWater.get
            coils << { role: :heat, lookup: 'Coils', kw: kw_of(c.ratedCapacity, c.autosizedRatedCapacity), name: c.nameString }
          elsif comp.to_CoilHeatingElectric.is_initialized
            c = comp.to_CoilHeatingElectric.get
            coils << { role: :heat_elec, lookup: 'ElecHeat', kw: kw_of(c.nominalCapacity, c.autosizedNominalCapacity), name: c.nameString }
          elsif comp.to_CoilHeatingGas.is_initialized
            c = comp.to_CoilHeatingGas.get
            coils << { role: :heat_gas, lookup: 'FurnaceGas', kw: kw_of(c.nominalCapacity, c.autosizedNominalCapacity), name: c.nameString }
          elsif comp.to_CoilHeatingDXSingleSpeed.is_initialized
            c = comp.to_CoilHeatingDXSingleSpeed.get
            coils << { role: :heat_hp, lookup: 'ashp', kw: kw_of(c.ratedTotalHeatingCapacity, c.autosizedRatedTotalHeatingCapacity), name: c.nameString }
          elsif comp.to_CoilHeatingDXVariableSpeed.is_initialized
            c = comp.to_CoilHeatingDXVariableSpeed.get
            ccashp = c.nameString.upcase.include?('CCASHP')
            coils << { role: :heat_hp, lookup: ccashp ? 'coils' : 'ashp', ccashp: ccashp,
                       kw: kw_of(c.ratedHeatingCapacityAtSelectedNominalSpeedLevel, c.autosizedRatedHeatingCapacityAtSelectedNominalSpeedLevel), name: c.nameString }
          elsif comp.to_CoilCoolingDXSingleSpeed.is_initialized
            c = comp.to_CoilCoolingDXSingleSpeed.get
            coils << { role: :cool_dx, lookup: 'coils', kw: kw_of(c.ratedTotalCoolingCapacity, c.autosizedRatedTotalCoolingCapacity), name: c.nameString }
          elsif comp.to_CoilCoolingDXTwoSpeed.is_initialized
            c = comp.to_CoilCoolingDXTwoSpeed.get
            coils << { role: :cool_dx, lookup: 'coils', kw: kw_of(c.ratedHighSpeedTotalCoolingCapacity, c.autosizedRatedHighSpeedTotalCoolingCapacity), name: c.nameString }
          elsif comp.to_CoilCoolingDXVariableSpeed.is_initialized
            c = comp.to_CoilCoolingDXVariableSpeed.get
            coils << { role: :cool_dx, lookup: 'coils', kw: kw_of(c.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel, c.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel), name: c.nameString }
          elsif comp.to_CoilCoolingWater.is_initialized
            c = comp.to_CoilCoolingWater.get
            coils << { role: :cool_chw, lookup: 'Coils', kw: kw_of(nil, c.autosizedDesignCoilLoad), name: c.nameString }
          end
        end

        # HP merge rule (legacy): the heat pump IS the cooling unit — drop DX cooling
        # items and size the HP by the larger of the two capacities; backup electric
        # heat is costed as a duct heater.
        hp = coils.find { |c| c[:role] == :heat_hp }
        if hp
          dx = coils.find { |c| c[:role] == :cool_dx }
          hp[:kw] = [hp[:kw] || 0.0, dx ? dx[:kw] || 0.0 : 0.0].max
          coils.reject! { |c| c[:role] == :cool_dx }
          coils.each { |c| c[:lookup] = 'ElecDuct' if c[:role] == :heat_elec }
        end

        coils.each do |coil|
          coil[:kw] = sql_coil_capacity_kw(air_loop.model, coil[:name]) if coil[:kw].nil? || coil[:kw].zero?
          next @warnings << "no capacity for coil #{coil[:name]} (model not sized?) — not costed" if coil[:kw].nil?
          next if coil[:kw] <= 0.0

          per_unit_kw = coil[:kw] / units
          add_item(coil[:lookup], per_unit_kw, units.to_f, %w[VENTILATION],
                   "air-loop coil #{coil[:name]} (#{per_unit_kw.round(1)} kW x #{units})")
          if coil[:role] == :cool_dx
            add_item('CondensingUnit', per_unit_kw, units.to_f, %w[VENTILATION], "condensing unit for #{coil[:name]}")
            # refrigerant piping BOM per condensing unit (legacy cost_heat_cool_equip)
            add_item('SteelPipe', 1.25, 32.8 * units, %w[VENTILATION], "refrigerant piping for #{coil[:name]}", unit: 'L.F.')
            add_item('PipeInsulationsilica', 1.25, 32.8 * units, %w[VENTILATION], "refrigerant pipe insulation for #{coil[:name]}")
            add_item('SteelPipeElbow', 1.25, 8.0 * units, %w[VENTILATION], "refrigerant pipe elbows for #{coil[:name]}")
          end
          cost_ccashp_extras(coil, units) if coil[:ccashp]
        end

        # gas-burner AHU adjustment (legacy gas_burner_cost): the AHU assembly includes a
        # duct furnace for sys 1/4 — remove it since the gas coil is costed separately.
        gas = coils.find { |c| c[:role] == :heat_gas }
        if gas && !(sys_type == 3 || sys_type == 6)
          cfm = flow_m3s * 2118.88
          adj_kw = cfm > 1500 ? 132 : (cfm >= 1000 ? 88 : nil)
          add_item('DuctFurGasExt', adj_kw, -1.0, %w[VENTILATION], "AHU gas burner adjustment (#{air_loop.nameString})") if adj_kw
        end
      end

      # Legacy cost_ccashp_additional_components: evaporator valve, condenser, wiring and
      # the fixed material_id assembly (controller, refrigerant tubing, insulation, switch).
      def cost_ccashp_extras(coil, units)
        per_unit_kw = (coil[:kw] || 0.0) / units
        cond_units = add_item('EV_valve', per_unit_kw, units.to_f, %w[VENTILATION], "CCASHP EV valve for #{coil[:name]}")
        cond_units = add_item('ccashp_condensor', per_unit_kw, units.to_f, %w[VENTILATION], "CCASHP condenser for #{coil[:name]}") || cond_units
        cond_mult = [cond_units.to_f, 1.0].max
        add_item('Wiring', 10, 0.2 * units * cond_mult, %w[VENTILATION], "CCASHP wiring for #{coil[:name]}", unit: 'CLF', exact_size: true)
        { '1295' => cond_mult, '1662' => cond_mult, '30' => cond_mult * 40, '1415' => cond_mult }.each do |material_id, quantity|
          material = @db.materials_hvac.find { |r| r['material_id'].to_s == material_id }
          next @warnings << "CCASHP extra material_id #{material_id} missing — not costed" if material.nil?

          @ledger.add(id: material['id'], quantity: quantity * units, tags: %w[VENTILATION],
                      note: "CCASHP extras for #{coil[:name]} [#{material['Material']}]")
        end
      end

      def kw_of(hard, autosized)
        value = optional_f(hard) || optional_f(autosized)
        value.nil? ? nil : value / 1000.0
      end

      # A staged coil's TOTAL capacity is its TOP stage (EnergyPlus stages are
      # cumulative, not additive), so that is what gets costed.
      def staged_kw(coil)
        stage = coil.stages.last
        return nil if stage.nil?

        if stage.respond_to?(:grossRatedTotalCoolingCapacity)
          kw_of(stage.grossRatedTotalCoolingCapacity, stage.autosizedGrossRatedTotalCoolingCapacity)
        elsif stage.respond_to?(:grossRatedHeatingCapacity)
          kw_of(stage.grossRatedHeatingCapacity, stage.autosizedGrossRatedHeatingCapacity)
        else
          kw_of(stage.nominalCapacity, stage.autosizedNominalCapacity)
        end
      end

      def optional_f(value)
        return nil if value.nil?
        return value.to_f unless value.respond_to?(:is_initialized)
        value.is_initialized ? value.get.to_f : nil
      end

      # E+ never reports a sized 'Rated Capacity' for hot-water coils, so the autosized
      # accessor is empty even on a sized model (the same gap makes legacy misclassify
      # hydronic AHUs as heat pumps and skip their heating coils — a documented legacy
      # defect the gem corrects). Fall back to the CoilSizingDetails report.
      def sql_coil_capacity_kw(model, coil_name)
        return nil unless model.sqlFile.is_initialized

        query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName='CoilSizingDetails' " \
                "AND RowName='#{coil_name.upcase}' AND ColumnName='Coil Final Gross Total Capacity'"
        value = model.sqlFile.get.execAndReturnFirstDouble(query)
        value.is_initialized && value.get.positive? ? value.get / 1000.0 : nil
      end

      # ---------- terminals: mixing boxes + piping/electrical runs ----------

      TERMINAL_TYPES = [
        [:to_AirTerminalSingleDuctVAVReheat, 'VAVFanMixingBoxesHtg'],
        [:to_AirTerminalSingleDuctVAVNoReheat, 'VAVFanMixingBoxesClg'],
        [:to_AirTerminalSingleDuctConstantVolumeReheat, 'CVMixingBoxes']
      ].freeze

      # Legacy reheat_recool_cost: per terminal, per storey the zone spans — the mixing
      # box (sized by the storey's share of airflow), hydronic piping to the roof centroid
      # for hot boxes, an electrical run for every box, and the reheat coil for CV boxes.
      def cost_terminals(air_loop, roof_cent)
        air_loop.thermalZones.sort_by(&:nameString).each do |zone|
          tz_mult = zone.multiplier.to_f
          zone.equipment.each do |eq|
            terminal = box = nil
            TERMINAL_TYPES.each do |cast, box_name|
              optional = eq.send(cast)
              next unless optional.is_initialized

              terminal = optional.get
              box = box_name
              break
            end
            next if box.nil?

            flow = terminal.maximumAirFlowRate
            flow = terminal.autosizedMaximumAirFlowRate unless flow.is_initialized
            unless flow.is_initialized
              @warnings << "no max air flow for terminal #{terminal.nameString} — box not costed"
              next
            end
            air_m3s = flow.get / tz_mult

            stories = Geometry.zone_story_centroids(zone)
            stories = [{ story_name: 'none', spaces: zone.spaces, centroid: nil, ceiling_area: 1.0 }] if stories.empty?
            zone_area = zone.floorArea.to_f
            stories.each do |story|
              frac = zone_area.positive? ? (story[:spaces].sum { |s| s.floorArea.to_f } / zone_area).round(2) : 1.0
              cfm = frac * air_m3s * 2118.88
              add_item(box, cfm, tz_mult, %w[VENTILATION],
                       "terminal box #{terminal.nameString} (#{box}, #{cfm.round} cfm, #{story[:story_name]})")

              if box == 'CVMixingBoxes'
                cost_cv_reheat_coil(terminal, frac, tz_mult, air_m3s, story, roof_cent)
              end

              next if roof_cent.nil? || story[:centroid].nil?

              run_ft = Geometry.manhattan_xy_m(story[:centroid], roof_cent) * Geometry::M_TO_FT
              if box == 'VAVFanMixingBoxesHtg'
                cost_terminal_piping(run_ft, frac * air_m3s, tz_mult, "terminal piping #{terminal.nameString} (#{story[:story_name]})")
              end
              cost_terminal_electrical(run_ft, tz_mult, "terminal electrical #{terminal.nameString} (#{story[:story_name]})")
            end
          end
        end
      end

      def cost_cv_reheat_coil(terminal, frac, tz_mult, air_m3s, story, roof_cent)
        coil = terminal.reheatCoil
        if coil.to_CoilHeatingWater.is_initialized
          c = coil.to_CoilHeatingWater.get
          kw = kw_of(c.ratedCapacity, c.autosizedRatedCapacity)
          return @warnings << "no capacity for reheat coil #{c.nameString} — not costed" if kw.nil?

          add_item('Coils', frac * kw / tz_mult, tz_mult, %w[VENTILATION], "reheat coil #{c.nameString}")
          if roof_cent && story[:centroid]
            run_ft = Geometry.manhattan_xy_m(story[:centroid], roof_cent) * Geometry::M_TO_FT
            # legacy quirk: CV reheat piping is sized by the FULL terminal airflow
            cost_terminal_piping(run_ft, air_m3s, tz_mult, "reheat coil piping #{c.nameString}")
          end
        elsif coil.to_CoilHeatingElectric.is_initialized
          c = coil.to_CoilHeatingElectric.get
          kw = kw_of(c.nominalCapacity, c.autosizedNominalCapacity)
          return @warnings << "no capacity for reheat coil #{c.nameString} — not costed" if kw.nil?

          add_item('ElecDuct', frac * kw / tz_mult, tz_mult, %w[VENTILATION], "electric duct heater #{c.nameString}")
        end
      end

      # Legacy piping_cost: supply+return steel pipe at the heating-valve diameter from
      # the mech_sizing piping table (keyed by airflow in L/s), 2 of each fitting.
      def cost_terminal_piping(run_ft, air_m3s, quantity, context)
        piping = mech_table('piping')
        return if piping.nil?

        lps = [air_m3s * 1000.0, 15_000.0].min
        row = piping.find { |r| r['ahu_airflow_range_Literpers'][0].to_f.round < lps.round && r['ahu_airflow_range_Literpers'][1].to_f.round >= lps.round } ||
              piping.max_by { |r| r['ahu_airflow_range_Literpers'][1].to_f }
        dia = row['heat_valve_pipe_dia_inch'].to_f.round(2)

        add_item('SteelPipe', dia, 2 * run_ft * quantity, %w[VENTILATION], "#{context} (pipe #{dia}\")", unit: 'L.F.')
        add_item('SteelPipeElbow', dia, 2 * quantity, %w[VENTILATION], context)
        add_item('SteelPipeTee', dia, 2 * quantity, %w[VENTILATION], context)
        add_item('SteelPipeTeeRed', dia, 2 * quantity, %w[VENTILATION], context)
        add_item('SteelPipeRed', dia, 2 * quantity, %w[VENTILATION], context)
        add_item('SteelPipeUnion', [dia, 3.0].min, 2 * quantity, %w[VENTILATION], context)
      end

      # Legacy vent_box_elec_cost: #14 wiring (CLF) + conduit for the run, one 4" and one
      # 1" electrical box per mixing box.
      def cost_terminal_electrical(run_ft, quantity, context)
        add_item('Wiring', 14, (run_ft / 100.0) * quantity, %w[VENTILATION], context, unit: 'CLF', exact_size: true)
        add_item('Conduit', nil, run_ft * quantity, %w[VENTILATION], context, unit: 'L.F.')
        add_item('Box', 4, quantity, %w[VENTILATION], context, exact_size: true)
        add_item('Box', 1, quantity, %w[VENTILATION], context, exact_size: true)
      end

      # Legacy hrv_cost: the ERV/HRV core (flow-proportionally scaled), a duct fitting per
      # served zone, and a dedicated return fan when the loop has no return fan of its own.
      def cost_hrv(air_loop)
        hx = air_loop.oaComponents.find { |c| c.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized }
        return if hx.nil?

        hx = hx.to_HeatExchangerAirToAirSensibleAndLatent.get
        flow = optional_f(hx.nominalSupplyAirFlowRate) || optional_f(hx.autosizedNominalSupplyAirFlowRate)
        if flow.nil?
          @warnings << "no nominal flow for HRV #{hx.nameString} (model not sized?) — HRV not costed"
          return
        end
        cfm = flow * 2118.88
        note = "HRV #{hx.nameString} (#{cfm.round} cfm)"

        zones = air_loop.thermalZones.sum(&:multiplier).to_f
        add_item('Ductwork-Fitting', 8, zones, %w[VENTILATION], "#{note} zone duct fittings")

        # ERV core: legacy scales the row cost by cfm x units / row size
        picked = pick_material('ERV', cfm, note)
        if picked
          row, units = picked
          row_size = row['Size'].to_f
          adj = row_size.positive? ? cfm * units / row_size : units
          @ledger.add(id: row['id'], quantity: adj, tags: %w[VENTILATION], note: note)
        end

        return if air_loop.returnFan.is_initialized

        fan_lookup = cfm < 800 ? 'FansDD-LP' : 'FansBelt'
        add_item(fan_lookup, cfm, 1.0, %w[VENTILATION], "#{note} return fan")
      end

      # ---------- geometry-derived distribution (legacy report-only domains) ----------

      # Legacy mech_to_roof_cost: gas/hot-water/chilled-water lines and the electrical
      # run from the mechanical room to the rooftop units.
      def cost_mech_to_roof(mech, roof_cent, heat_line_counts, cool_line_counts, rooftop_units)
        util_ft = Geometry.manhattan_xyz_m(mech[:centroid], roof_cent) * Geometry::M_TO_FT
        if heat_line_counts['Gas'].positive?
          add_item('GasLine', nil, util_ft + RT_ROOF_DIST_FT * heat_line_counts['Gas'], %w[DISTRIBUTION],
                   'gas line mech room -> roof', unit: 'L.F.')
        end
        { 'HW' => heat_line_counts['HW'], 'CHW' => cool_line_counts['CHW'] }.each do |line, count|
          next unless count.positive?

          length = 2 * util_ft + 2 * RT_ROOF_DIST_FT * count
          add_item('SteelPipe', 4, length, %w[DISTRIBUTION], "#{line} line mech room -> roof", unit: 'L.F.')
          add_item('PipeInsulation', 4, length, %w[DISTRIBUTION], "#{line} line insulation")
          add_item('PipeJacket', 4, length, %w[DISTRIBUTION], "#{line} line jacket")
        end
        elec_ft = util_ft + rooftop_units * RT_ROOF_DIST_FT
        add_item('Wiring', 10, elec_ft / 100.0, %w[DISTRIBUTION], 'electrical run mech room -> roof', unit: 'CLF', exact_size: true)
        add_item('Conduit', nil, elec_ft, %w[DISTRIBUTION], 'electrical conduit mech room -> roof', unit: 'L.F.')
      end

      # Legacy vent_trunk_duct_cost: the vertical trunk from the roof centroid down to the
      # lowest conditioned ceiling; x2 runs unless a single-run (sys 1/4) building.
      def cost_trunk_duct(model, total_flow_m3s, roof_cent, sys_1_4)
        trunk = mech_table('trunk')
        low = Geometry.lowest_roof_centroid(model)
        return if trunk.nil? || low.nil?

        runs = sys_1_4 ? 1 : 2
        flow = total_flow_m3s
        max_row = trunk.max_by { |r| r['max_flow_range_m3pers'][0].to_f }
        flow = max_row['max_flow_range_m3pers'][0].to_f.round(2) if flow.round(2) > max_row['max_flow_range_m3pers'][1].to_f.round(2)
        row = trunk.find { |r| r['max_flow_range_m3pers'][0].to_f.round(2) < flow.round(2) && r['max_flow_range_m3pers'][1].to_f.round(2) >= flow.round(2) } || max_row
        dia = row['duct_dia_inch'].to_f
        length_ft = (roof_cent[2] - low[2]).abs * Geometry::M_TO_FT
        return if length_ft <= 0.0

        add_item('Ductwork-S', dia, length_ft * runs, %w[DISTRIBUTION], 'central trunk duct', unit: 'L.F.')
        add_item('Ductinsulation', 1.5, (dia / 12.0) * Math::PI * length_ft * runs, %w[DISTRIBUTION], 'central trunk duct insulation')
      end

      # Legacy gen_hvac_info_by_floor: aggregate terminal airflows per storey (return air
      # only for systems other than 1/4).
      def collect_hvac_floors(hvac_floors, air_loop, sys_type)
        air_loop.thermalZones.sort_by(&:nameString).each do |zone|
          tz_mult = zone.multiplier.to_f
          zone.equipment.each do |eq|
            terminal = nil
            TERMINAL_TYPES.each do |cast, _|
              optional = eq.send(cast)
              terminal = optional.get if optional.is_initialized
            end
            if terminal.nil? && eq.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
              terminal = eq.to_AirTerminalSingleDuctConstantVolumeNoReheat.get
            end
            next if terminal.nil?

            flow = terminal.maximumAirFlowRate
            flow = terminal.autosizedMaximumAirFlowRate unless flow.is_initialized
            next unless flow.is_initialized

            air_m3s = flow.get / tz_mult
            zone_area = zone.floorArea.to_f
            Geometry.zone_story_centroids(zone).each do |story|
              frac = zone_area.positive? ? (story[:spaces].sum { |s| s.floorArea.to_f } / zone_area).round(2) : 1.0
              supply = frac * air_m3s
              entry = (hvac_floors[story[:story_name]] ||= { story: story[:spaces].first.buildingStory.is_initialized ? story[:spaces].first.buildingStory.get : nil,
                                                             supply_m3s: 0.0, return_m3s: 0.0, tz_mult: 0.0, tz_num: 0, sys_types: [], zones: [] })
              entry[:supply_m3s] += supply
              entry[:return_m3s] += SINGLE_RUN_SYS_TYPES.include?(sys_type) ? 0.0 : supply
              entry[:tz_mult] += tz_mult
              entry[:tz_num] += 1
              entry[:sys_types] << sys_type
              entry[:zones] << { supply_m3s: supply, return_m3s: SINGLE_RUN_SYS_TYPES.include?(sys_type) ? 0.0 : supply, tz_mult: tz_mult }
            end
          end
        end
      end

      # Legacy floor_vent_dist_cost/get_floor_trunk_cost: a supply (+return) trunk across
      # each storey, sized from the storey airflow at the design velocity, run length from
      # the storey outline crossing through the roof centroid.
      def cost_floor_trunk_ducts(hvac_floors, roof_cent)
        vel_prof = mech_table('vel_prof')
        hvac_floors.each do |story_name, floor|
          next if floor[:tz_num] < 2 && floor[:sys_types].uniq == [3]
          next if floor[:story].nil?

          line = Geometry.story_cent_to_edge(floor[:story], roof_cent, full_length: true)
          next if line.nil? || line[:end_point].nil?

          run_ft = line[:end_point][:dist] * Geometry::M_TO_FT
          tz_floor_mult = floor[:tz_mult] / floor[:tz_num]
          vel_fpm = vel_prof ? vel_prof.last['vel_fpm'].to_f : 1500.0
          [[floor[:supply_m3s], 'supply'], [floor[:return_m3s], 'return']].each do |flow_m3s, role|
            next unless flow_m3s.positive?

            cfm = flow_m3s * 2118.88
            dia = 2 * Math.sqrt(((cfm / vel_fpm) * 144.0) / Math::PI)
            picked = pick_material('Ductwork-S', dia, "floor trunk duct #{story_name}", unit: 'L.F.')
            next if picked.nil?

            row, = picked
            @ledger.add(id: row['id'], quantity: run_ft * tz_floor_mult, tags: %w[DISTRIBUTION],
                        note: "floor trunk #{role} duct #{story_name} (#{row['Size']}\")")
            area_ft2 = (row['Size'].to_f / 12.0) * Math::PI * run_ft
            add_item('Ductinsulation', 1.5, area_ft2 * tz_floor_mult, %w[DISTRIBUTION], "floor trunk #{role} duct insulation #{story_name}")
          end
        end
      end

      # Legacy tz_vent_dist_cost: per zone-storey supply (+return) distribution from the
      # mech_sizing tz_dist_info table (diffusers, ducting lbs, insulation ft2, flex duct).
      def cost_zone_distribution(hvac_floors)
        table = mech_table('tz_dist_info')
        flex_table = mech_table('flex_duct')
        return if table.nil?

        hvac_floors.each do |story_name, floor|
          floor[:zones].each do |zone_flows|
            [zone_flows[:supply_m3s], zone_flows[:return_m3s]].each do |flow|
              next unless flow.positive?

              row = table.find { |r| flow > r['airflow_m3ps'][0].to_f && flow <= r['airflow_m3ps'][1].to_f }
              if row.nil? # beyond the largest range: scale the largest row by diffuser count
                largest = table.max_by { |r| r['airflow_m3ps'][1].to_f }
                diffusers = (flow / largest['diffusers'].to_f).round
                row = { 'diffusers' => diffusers,
                        'ducting_lbs' => (diffusers * largest['ducting_lbs'].to_f).round,
                        'duct_insulation_ft2' => (diffusers * largest['duct_insulation_ft2'].to_f).round,
                        'flex_duct_ft' => (diffusers * largest['flex_duct_ft'].to_f).round }
              end
              mult = zone_flows[:tz_mult]
              note = "zone distribution (#{story_name})"
              add_item('Diffusers', 36, row['diffusers'].to_f * mult, %w[DISTRIBUTION], note)
              add_item('Ductwork', row['ducting_lbs'].to_f < 200 ? 199 : 200, row['ducting_lbs'].to_f * mult, %w[DISTRIBUTION], note)
              add_item('DuctInsulation', 1.5, row['duct_insulation_ft2'].to_f * mult, %w[DISTRIBUTION], note)
              if flex_table && row['flex_duct_ft'].to_f.positive?
                flex = flex_table.find { |f| flow > f['airflow_m3ps'][0].to_f && flow <= f['airflow_m3ps'][1].to_f } || flex_table.last
                add_item('Ductwork-M', flex['diameter_in'].to_f, row['flex_duct_ft'].to_f * mult, %w[DISTRIBUTION], "#{note} flex duct", unit: 'L.F.')
              end
            end
          end
        end
      end
    end
  end
end
