module OpenStudioHVAC
  module Costing
    # Manifest-driven ventilation & distribution costing (the re-architected legacy
    # "(b)-layer"): instead of parsing SYS_n from air-loop names, the AHU assembly class
    # comes from the FAMILY of the gem-built system serving the loop, and coil types are
    # read from the loop's actual components.
    #
    # Covered: AHU assemblies (hvac_vent_ahu layers x quantities) + per-zone distribution
    # (diffusers, ductwork lbs, duct insulation ft2 from the mech_sizing tz_dist_info
    # table). Trunk-duct/flue/utility-run geometry costing is deferred with explicit
    # warnings (documented approximation vs legacy).
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

      # duct-run multiplier (legacy: x1 for sys 1/4, x2 otherwise) as manifest data
      SINGLE_RUN_SYS_TYPES = [1].freeze

      attr_reader :warnings

      def initialize(database, ledger)
        @db = database
        @ledger = ledger
        @warnings = []
      end

      # @param model [OpenStudio::Model::Model] sized model
      # @param loop_families [Hash{String=>String}] air-loop name -> gem family (from build
      #   results / catalog); loops not in the map produce a warning (foreign ventilation)
      def quantify(model, loop_families)
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

          if sys_type == :distribution_only
            @warnings << "family '#{family}' (#{air_loop.nameString}): no unit-cost data for the air handler/media exists (legacy never costed it either); distribution costed"
          else
            cost_ahu(air_loop, sys_type, flow)
          end
          cost_terminal_boxes(air_loop)
          cost_zone_distribution(air_loop)
        end
      end

      private

      def flow_m3s(air_loop)
        flow = air_loop.designSupplyAirFlowRate
        flow = air_loop.autosizedDesignSupplyAirFlowRate unless flow.is_initialized
        unless flow.is_initialized
          @warnings << "no design supply air flow for #{air_loop.nameString} (model not sized?) — ventilation not costed"
          return nil
        end
        flow.get
      end

      def coil_keys(air_loop)
        htg = 'none'
        clg = 'none'
        air_loop.supplyComponents.each do |comp|
          htg = 'Gas' if comp.to_CoilHeatingGas.is_initialized
          htg = 'elec' if comp.to_CoilHeatingElectric.is_initialized && htg == 'none'
          htg = 'HW' if comp.to_CoilHeatingWater.is_initialized
          htg = 'HP-e' if comp.to_CoilHeatingDXSingleSpeed.is_initialized
          htg = 'CCASHP-e' if comp.to_CoilHeatingDXVariableSpeed.is_initialized
          clg = 'DX' if comp.to_CoilCoolingDXSingleSpeed.is_initialized || comp.to_CoilCoolingDXTwoSpeed.is_initialized
          clg = 'CHW' if comp.to_CoilCoolingWater.is_initialized
          clg = 'CCASHP' if comp.to_CoilCoolingDXVariableSpeed.is_initialized
        end
        [htg, clg]
      end

      def cost_ahu(air_loop, sys_type, flow_m3s)
        lps = flow_m3s * 1000.0 # Supply_air buckets are L/s (legacy get_ahu_mult semantics)
        htg, clg = coil_keys(air_loop)
        rows = @db.ahu_assemblies.select do |r|
          r['Sys_type'].to_i == sys_type && r['Htg'] == htg && r['Clg'] == clg
        end
        if rows.empty?
          @warnings << "no AHU assembly for sys_type #{sys_type} htg=#{htg} clg=#{clg} (#{air_loop.nameString}) — AHU not costed"
          return
        end
        # Exact legacy get_ahu_mult algorithm: number of units = ceil(L/s / largest bucket);
        # re-select the smallest bucket >= L/s-per-unit; scale layers by flow/bucket.
        max_bucket = rows.map { |r| r['Supply_air'].to_f }.max
        unit_count = (lps / max_bucket) > (lps / max_bucket).to_i ? (lps / max_bucket).to_i + 1 : (lps / max_bucket).round
        unit_count = 1 if unit_count < 1
        per_unit_lps = lps / unit_count
        row = rows.select { |r| r['Supply_air'].to_f >= per_unit_lps }
                  .min_by { |r| r['Supply_air'].to_f } || rows.max_by { |r| r['Supply_air'].to_f }
        base_quantity = unit_count * (per_unit_lps / row['Supply_air'].to_f)
        cfm = lps * 2.11888

        # Pipe-class layers inside id_layers are unused variants; legacy costs AHU valve
        # piping through a dedicated BOM sized from the mech_sizing valve-diameter table
        # (empirically: range evaluated in cfm, cool-valve diameter, next-largest material
        # size). Reproduced in cost_ahu_piping below.
        pipe_classes = /pipe|valve|insulation|plug|strainer|circuitsetter|balancing|controls/i
        cost_ahu_piping(air_loop, cfm, base_quantity) if %w[HW CHW].include?(htg) || clg == 'CHW'

        # id_layers reference materials_hvac material_id -> map to the cost line-item id
        note = "AHU #{air_loop.nameString} (#{cfm.round} cfm, sys#{sys_type} #{htg}/#{clg})"
        ids = row['id_layers'].to_s.split(',').map(&:strip)
        mults = row['Id_layers_quantity_multipliers'].to_s.split(',').map { |m| m.strip.to_f }
        ids.zip(mults).each do |material_id, mult|
          material = @db.materials_hvac.find { |r| r['material_id'].to_s == material_id }
          if material.nil?
            @warnings << "AHU layer material_id #{material_id} not in materials_hvac — layer not costed (#{note})"
            next
          end
          next if material['Material'].to_s =~ pipe_classes # handled by cost_ahu_piping
          @ledger.add(id: material['id'], quantity: base_quantity * (mult || 1.0),
                      tags: %w[VENTILATION],
                      material_mult: material['material_mult'].to_f.zero? ? 1.0 : material['material_mult'].to_f,
                      labour_mult: material['labour_mult'].to_f.zero? ? 1.0 : material['labour_mult'].to_f,
                      note: "#{note} [#{material['Material']}]")
        end
      end

      # AHU hydronic valve-piping BOM (empirically matched to the legacy sys6 ledger):
      # per AHU, scaled by the AHU airflow scale — 32.8 LF pipe + insulation, 2 each of
      # valve/elbow/tee/reducer/union, 1 each of plug/strainer/circuit setter/balancing/
      # controls — sized next-largest from the cool-valve diameter (range keyed in cfm).
      AHU_PIPING_BOM = [
        ['SteelPipe', :dia, 32.8], ['PipeInsulation', :dia, 32.8],
        ['ValvesBig', :dia, 2.0], ['SteelPipeElbow', :dia, 2.0], ['SteelPipeTee', :dia, 2.0],
        ['SteelPipeRed', :dia, 2.0], ['SteelPipeUnion', :dia, 2.0],
        ['SteelPlug', 0.75, 1.0], ['Strainers', :dia, 1.0], ['CircuitSetter', :dia, 1.0],
        ['Balancing', nil, 1.0], ['Controls', nil, 1.0]
      ].freeze

      def cost_ahu_piping(air_loop, cfm, scale)
        piping = @db.mech_sizing.find { |c| c['component'] == 'piping' }&.fetch('table', [])
        pipe_row = piping.find { |r| cfm >= r['ahu_airflow_range_Literpers'][0].to_f && cfm < r['ahu_airflow_range_Literpers'][1].to_f } ||
                   piping.max_by { |r| r['ahu_airflow_range_Literpers'][1].to_f }
        dia = pipe_row ? pipe_row['cool_valve_pipe_dia_inch'].to_f : 2.0

        AHU_PIPING_BOM.each do |material, size_key, qty_per|
          size = size_key == :dia ? dia : size_key
          rows = @db.materials(material)
          row = if size
                  rows.select { |r| r['Size'].to_f >= size }.min_by { |r| r['Size'].to_f } ||
                    rows.max_by { |r| r['Size'].to_f }
                else
                  rows.first
                end
          next @warnings << "no materials_hvac entry '#{material}' — AHU piping item not costed" if row.nil?

          @ledger.add(id: row['id'], quantity: qty_per * scale, tags: %w[VENTILATION],
                      material_mult: row['material_mult'].to_f.zero? ? 1.0 : row['material_mult'].to_f,
                      labour_mult: row['labour_mult'].to_f.zero? ? 1.0 : row['labour_mult'].to_f,
                      note: "AHU piping #{air_loop.nameString} (#{material} #{size || '-'}\")")
        end
      end

      # Terminal mixing boxes per air terminal (legacy get_airloop_terminal_type mapping):
      # VAV Reheat -> VAVFanMixingBoxesHtg, VAV NoReheat -> VAVFanMixingBoxesClg,
      # CV Reheat -> CVMixingBoxes. Sized by the terminal's max air flow (per zone unit).
      def cost_terminal_boxes(air_loop)
        air_loop.thermalZones.sort_by(&:nameString).each do |zone|
          mult = zone.multiplier.to_f
          zone.equipment.each do |eq|
            terminal, box = nil, nil
            if eq.to_AirTerminalSingleDuctVAVReheat.is_initialized
              terminal = eq.to_AirTerminalSingleDuctVAVReheat.get
              box = 'VAVFanMixingBoxesHtg'
              flow = terminal.maximumAirFlowRate
              flow = terminal.autosizedMaximumAirFlowRate unless flow.is_initialized
            elsif eq.to_AirTerminalSingleDuctVAVNoReheat.is_initialized
              terminal = eq.to_AirTerminalSingleDuctVAVNoReheat.get
              box = 'VAVFanMixingBoxesClg'
              flow = terminal.maximumAirFlowRate
              flow = terminal.autosizedMaximumAirFlowRate unless flow.is_initialized
            elsif eq.to_AirTerminalSingleDuctConstantVolumeReheat.is_initialized
              terminal = eq.to_AirTerminalSingleDuctConstantVolumeReheat.get
              box = 'CVMixingBoxes'
              flow = terminal.maximumAirFlowRate
              flow = terminal.autosizedMaximumAirFlowRate unless flow.is_initialized
            end
            next if box.nil?

            unless flow.is_initialized
              @warnings << "no max air flow for terminal #{terminal.nameString} — box not costed"
              next
            end
            cfm = (flow.get / mult) * 2118.88
            rows = @db.materials(box)
            row = rows.select { |r| r['Size'].to_f >= cfm }.min_by { |r| r['Size'].to_f } ||
                  rows.max_by { |r| r['Size'].to_f }
            if row.nil?
              @warnings << "no materials_hvac entry '#{box}' — terminal box not costed"
              next
            end
            @ledger.add(id: row['id'], quantity: mult, tags: %w[VENTILATION],
                        material_mult: row['material_mult'].to_f.zero? ? 1.0 : row['material_mult'].to_f,
                        labour_mult: row['labour_mult'].to_f.zero? ? 1.0 : row['labour_mult'].to_f,
                        note: "terminal box #{terminal.nameString} (#{box}, #{cfm.round} cfm)")
          end
        end
      end

      # Per-zone distribution from the mech_sizing tz_dist_info table (diffusers count,
      # ductwork lbs, duct insulation ft2) selected by the zone's share of loop airflow.
      def cost_zone_distribution(air_loop)
        table = @db.mech_sizing.find { |c| c['component'] == 'tz_dist_info' }&.fetch('table', nil)
        return if table.nil?

        zones = air_loop.thermalZones
        return if zones.empty?

        per_zone_flow = (flow_m3s(air_loop) || return) / zones.size
        # airflow_m3ps entries are [min, max] ranges
        row = table.find { |r| per_zone_flow >= r['airflow_m3ps'][0].to_f && per_zone_flow < r['airflow_m3ps'][1].to_f } ||
              table.max_by { |r| r['airflow_m3ps'][1].to_f }

        zones.each do |zone|
          mult = zone.multiplier.to_f
          note = "distribution #{zone.nameString}"
          add_material('Diffusers', nil, row['diffusers'].to_f * mult, note)
          add_material('Ductwork', nil, row['ducting_lbs'].to_f * mult, note)
          add_material('DuctInsulation', 1.5, row['duct_insulation_ft2'].to_f * mult, note)
        end
        @warnings << "trunk duct/flue/utility-run geometry costing not yet modeled for #{air_loop.nameString} (distribution covers zone-level duct/diffusers)"
      end

      def add_material(lookup, size, quantity, note)
        rows = @db.materials(lookup, size: size)
        rows = @db.materials(lookup) if rows.empty?
        if rows.empty?
          @warnings << "no materials_hvac entry '#{lookup}' — #{note} not costed"
          return
        end
        row = rows.first
        @ledger.add(id: row['id'], quantity: quantity, tags: %w[DISTRIBUTION], note: "#{note} (#{lookup})")
      end
    end
  end
end
