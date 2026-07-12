require 'json'

module OpenStudioNECB
  # Post-comparison scoring: Section 10 energy performance tiers (Table
  # 10.1.2.1, verified IDENTICAL in 2020 and 2025), the NECB 2025 Part 11
  # operational-GHG performance levels (A-F, provincial emission factors), and
  # the NECB 2025 8.4.4 archetype-EUI building energy target.
  module Tiers
    DATA_DIR = File.expand_path('data', __dir__)

    module_function

    def eui_data
      @eui_data ||= JSON.parse(File.read(File.join(DATA_DIR, 'eui_targets_2025.json')))
    end

    def ghg_data
      @ghg_data ||= JSON.parse(File.read(File.join(DATA_DIR, 'ghg_factors_2025.json')))
    end

    # Table 10.1.2.1: Tier 1 <= 100%, Tier 2 <= 75%, Tier 3 <= 50%, Tier 4 < 40%
    # of the building energy target.
    # @return [Hash] { 'percent_of_target' =>, 'tier' => Integer|nil }
    def energy_tier(proposed_kwh, target_kwh, audit: nil)
      percent = 100.0 * proposed_kwh / target_kwh
      tier = if percent < 40.0 then 4
             elsif percent <= 50.0 then 3
             elsif percent <= 75.0 then 2
             elsif percent <= 100.0 then 1
             end
      audit&.decision(:compliance,
                      tier ? "energy performance Tier #{tier} achieved" : 'no energy performance tier achieved (over the target)',
                      inputs: { percent_of_target: percent.round(1),
                                improvement_percent: (100.0 - percent).round(1) },
                      article: '10.1.2.1. (Table verified identical 2020/2025)')
      { 'percent_of_target' => percent.round(1), 'tier' => tier }
    end

    # NECB 2025 8.4.4: BET = sum(A_i x EUI_i) + PL from the archetype table.
    # @param archetype_areas [Hash{String=>Numeric,nil}] archetype name =>
    #   gross interior floor area m2 (nil = remainder of total_floor_area;
    #   8.4.4.1.(4) distributes unlisted functions proportionally, so a single
    #   archetype covering the whole area is the common case)
    # @return [Hash] { 'bet_kwh' =>, 'lines' => [...] }
    def eui_building_energy_target(archetype_areas, total_floor_area_m2, hdd:,
                                   process_loads_kwh: 0.0, audit: nil)
      table = eui_data['archetype_eui_kwh_per_m2']
      applicability = eui_data['applicability']
      lines = []
      assigned = archetype_areas.values.compact.sum
      remainder = [total_floor_area_m2 - assigned, 0.0].max

      bet = process_loads_kwh.to_f
      archetype_areas.each do |archetype, area|
        eui = table[archetype]
        raise(ArgumentError, "unknown 2025 EUI archetype '#{archetype}' (#{table.keys.join('; ')})") if eui.nil?

        area = area.nil? ? remainder : area.to_f
        bet += area * eui
        lines << { 'archetype' => archetype, 'area_m2' => area.round(1), 'eui' => eui,
                   'kwh' => (area * eui).round(1) }
      end

      if hdd && hdd >= applicability['max_hdd']
        audit&.warn(:compliance, "8.4.4 EUI path is NOT applicable at HDD #{hdd} (Table 8.4.4.1 note: HDD < #{applicability['max_hdd']})",
                    article: '8.4.4.1.')
      end
      covered = lines.sum { |l| l['area_m2'] } / total_floor_area_m2
      if covered < applicability['min_archetype_floor_fraction'] - 1e-6
        audit&.warn(:compliance,
                    "only #{(covered * 100).round(1)}% of floor area is assigned to archetypes — 8.4.4.1.(1) requires >= 90% " \
                    '(8.4.4.1.(4) permits distributing unlisted space functions proportionally among the listed archetypes)',
                    article: '8.4.4.1.(1); 8.4.4.1.(4)')
      end
      audit&.decision(:compliance, 'building energy target computed from archetype EUIs (2025 8.4.4 path)',
                      inputs: { lines: lines, process_loads_kwh: process_loads_kwh.to_f.round(1) },
                      value: "BET = #{bet.round(1)} kWh/year",
                      article: '8.4.4.1.(2); Table 8.4.4.1.')
      { 'bet_kwh' => bet.round(1), 'lines' => lines }
    end

    # NECB 2025 Part 11: operational GHG for both buildings from the annual fuel
    # totals, and the A-F performance level from the proposed/reference ratio.
    # @param energy [Hash] a Runner.energy_results hash (kWh by fuel)
    def operational_ghg_kg(energy, province_state)
      province = province_state.to_s.upcase
      elec = ghg_data['electricity_g_per_kwh'][province]
      gas = ghg_data['utility_gas_g_per_kwh'][province]
      return nil if elec.nil? || gas.nil?

      grams = (energy['electricity_kwh'] || 0) * elec +
              (energy['natural_gas_kwh'] || 0) * gas
      (grams / 1000.0).round(1)
    end

    def ghg_level(proposed_kg, reference_kg, audit: nil)
      percent = 100.0 * proposed_kg / reference_kg
      level = ghg_data['levels'].find { |_, max| percent <= max }&.first
      audit&.decision(:compliance,
                      level ? "operational GHG performance level #{level}" : 'no GHG performance level (over the reference GHG target)',
                      inputs: { proposed_kg_co2e: proposed_kg, reference_kg_co2e: reference_kg,
                                percent_of_ghg_target: percent.round(1) },
                      article: '11.4.1.1.; 11.4.2.1. (NECB 2025)')
      { 'percent_of_ghg_target' => percent.round(1), 'level' => level }
    end
  end
end
