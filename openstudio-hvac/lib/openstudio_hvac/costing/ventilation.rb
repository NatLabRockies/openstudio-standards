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
        cfm = flow_m3s * 2118.88
        htg, clg = coil_keys(air_loop)
        rows = @db.ahu_assemblies.select do |r|
          r['Sys_type'].to_i == sys_type && r['Htg'] == htg && r['Clg'] == clg
        end
        if rows.empty?
          @warnings << "no AHU assembly for sys_type #{sys_type} htg=#{htg} clg=#{clg} (#{air_loop.nameString}) — AHU not costed"
          return
        end
        candidates = rows.select { |r| r['Supply_air'].to_f >= cfm }
        row = candidates.min_by { |r| r['Supply_air'].to_f } || rows.max_by { |r| r['Supply_air'].to_f }
        # legacy get_ahu_mult scales ALL layer quantities by airflow / bucket airflow
        # (confirmed by ledger parity: fractional quantities like 0.648 = cfm/Supply_air)
        base_quantity = cfm / row['Supply_air'].to_f
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
          @ledger.add(id: material['id'], quantity: base_quantity * (mult || 1.0),
                      tags: %w[VENTILATION],
                      material_mult: material['material_mult'].to_f.zero? ? 1.0 : material['material_mult'].to_f,
                      labour_mult: material['labour_mult'].to_f.zero? ? 1.0 : material['labour_mult'].to_f,
                      note: "#{note} [#{material['Material']}]")
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
