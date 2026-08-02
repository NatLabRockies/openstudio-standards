require_relative 'test_helper'
require 'json'

# D-59 — the vendored NECB 2020 equipment-efficiency values, pinned to the
# PRINTED tables they were verified against (fetched via the codes MCP,
# 2026-08-02). Each assertion states the printed value and the unit conversion
# that reaches the vendored one, so a future data regeneration that drifts
# from the code text fails HERE with the printed number in the message.
class TestEfficiencyProvenance < Minitest::Test
  DATA = JSON.parse(File.read(
                      File.expand_path('../lib/openstudio_hvac/data/necb/efficiencies_2020.json', __dir__)
                    ))
  KW_PER_TON = 3.51685

  def rows(family, **criteria)
    DATA[family].select { |r| criteria.all? { |k, v| r[k.to_s] == v } }
  end

  # Table 5.2.12.1.-K Path B: full-load COPc, vendored as kW/ton.
  def test_chillers_are_table_k_path_b_full_load_cops
    expected = {
      # positive displacement (scroll/recip/screw), bins < 264 / 264-528 / 528-1055 / 1055-2110 / >= 2110 kW
      'Scroll' => [4.513, 4.694, 5.177, 5.633, 6.018],
      'Reciprocating' => [4.513, 4.694, 5.177, 5.633, 6.018],
      'Rotary Screw' => [4.513, 4.694, 5.177, 5.633, 6.018],
      # centrifugal, bins < 528 / 528-1055 / 1055-1407 / >= 1407 kW
      'Centrifugal' => [5.065, 5.544, 5.917, 6.018]
    }
    expected.each do |compressor, cops|
      ladder = rows('chillers', cooling_type: 'WaterCooled', compressor_type: compressor)
               .sort_by { |r| r['minimum_capacity'].to_f }
      assert_equal cops.size, ladder.size, "#{compressor}: bin count vs the printed table"
      ladder.zip(cops).each do |row, cop|
        assert_in_delta cop, KW_PER_TON / row['minimum_full_load_efficiency'], 0.001,
                        "#{compressor} #{row['minimum_capacity']}: printed Table -K Path B COPc #{cop}"
      end
    end
    air = rows('chillers', cooling_type: 'AirCooled')
    assert_equal 1, air.size
    assert_in_delta 2.866, KW_PER_TON / air[0]['minimum_full_load_efficiency'], 0.001,
                    'air-cooled: printed Table -K Path B COPc 2.866'
  end

  # Table 5.2.12.1.-N boilers.
  def test_boilers_are_table_n
    gas = rows('boilers', fuel_type: 'Gas').sort_by { |r| r['maximum_capacity'].to_f }
    assert_equal [0.9, 0.9, 0.9],
                 [gas[0]['minimum_annual_fuel_utilization_efficiency'],
                  gas[1]['minimum_thermal_efficiency'],
                  gas[2]['minimum_combustion_efficiency']],
                 'printed: AFUE 90% (< 88 kW) / Et 90% (88-733) / Ec 90% (>= 733), water'
    oil = rows('boilers', fuel_type: 'Oil').sort_by { |r| r['maximum_capacity'].to_f }
    assert_equal [0.86, 0.87, 0.88],
                 [oil[0]['minimum_annual_fuel_utilization_efficiency'],
                  oil[1]['minimum_thermal_efficiency'],
                  oil[2]['minimum_combustion_efficiency']],
                 'printed: AFUE 86% / Et 87% / Ec 88%, water'
  end

  # Table 5.2.12.1.-A large AC EER ladder (electric-or-none / other heating).
  def test_unitary_acs_are_table_a
    %w[Single\ Package Split\ System].each do |sub|
      ladder = rows('unitary_acs', equipment_type: 'Air Conditioners', subcategory: sub)
               .reject { |r| r['minimum_energy_efficiency_ratio'].nil? }
               .sort_by { |r| [r['minimum_capacity'].to_f, r['heating_type']] }
               .map { |r| r['minimum_energy_efficiency_ratio'] }
      assert_equal [10.8, 11.0, 11.0, 11.2, 9.8, 10.0, 9.5, 9.7].sort,
                   ladder.sort,
                   "#{sub}: printed EER 11.2/11.0, 11.0/10.8, 10.0/9.8, 9.7/9.5 by bin"
    end
  end

  # Table 5.2.12.1.-G PTAC: EER = 14.1 - 1.0435 x Cap_kW in the middle bin,
  # vendored per kBtu/h: 1.0435 / 3.412 = 0.3058.
  def test_ptac_formula_is_table_g_unit_converted
    mid = rows('unitary_acs', equipment_type: 'PTAC').find { |r| r['minimum_capacity'].to_f.positive? }
    assert_in_delta 14.1, mid['ptac_eer_coefficient_1'], 1e-9
    assert_in_delta 1.0435 / 3.412, mid['ptac_eer_coefficient_2'], 0.0005,
                    'printed 1.0435 per kW = 0.3058 per kBtu/h'
    low, high = rows('unitary_acs', equipment_type: 'PTAC').map { |r| r['ptac_eer_coefficient_1'] }.minmax
    assert_equal [9.5, 14.1], [low, high], 'printed floor EER 9.5 and formula intercept 14.1'
  end

  # Table 5.2.12.1.-A heat pumps in heating mode.
  def test_heat_pump_heating_is_table_a
    ladder = DATA['heat_pumps_heating'].sort_by { |r| r['minimum_capacity'].to_f }
    assert_in_delta 7.4, ladder.first['minimum_heating_seasonal_performance_factor'], 1e-9,
                    'printed small single-package HSPF 7.4'
    cops = ladder.map { |r| r['minimum_coefficient_of_performance_heating'] }.compact.uniq.sort
    assert_equal [3.2, 3.3], cops, 'printed COPh 3.30 (19-40 kW) and 3.20 (>= 40 kW) at 8.3 C'
  end

  # The heat_rejection family cites ASHRAE 90.1 and is VESTIGIAL for the
  # reference path: apply_efficiencies never reads it (the tower fan comes from
  # Table 5.2.12.2 via apply_tower_rules, D-26). Pin the vestigiality so a
  # future consumer has to face the 90.1 provenance deliberately.
  def test_heat_rejection_family_is_declared_vestigial
    assert(DATA['heat_rejection'].all? { |r| r['notes'] =~ /90\.1/ },
           'every heat_rejection row cites its 90.1 source')
    efficiency_rb = File.read(File.expand_path('../lib/openstudio_hvac/necb/efficiency.rb', __dir__))
    refute_match(/heat_rejection/, efficiency_rb,
                 'apply_efficiencies grew a heat_rejection consumer — re-verify its values against ' \
                 'the printed NECB table first (they are 90.1 vintages, D-59)')
  end

  # ==================== NECB 2025 (D-60) ====================

  DATA_2025 = JSON.parse(File.read(
                           File.expand_path('../lib/openstudio_hvac/data/necb/efficiencies_2025.json', __dir__)
                         ))

  # 2025 -K/-N and the -G PTAC coefficients are byte-identical to 2020's
  # printed tables (verified 2026-08-02) — so the vendored families must stay
  # identical across editions.
  def test_2025_shared_families_are_identical_to_2020
    %w[chillers boilers heat_rejection].each do |family|
      strip = ->(rows) { rows.map { |r| r.reject { |k, _| k == 'notes' } } }
      assert_equal strip.call(DATA[family]), strip.call(DATA_2025[family]),
                   "#{family}: printed 2025 tables are identical to 2020's — the vendored data must match"
    end
    ptac = ->(d) { d['unitary_acs'].select { |r| r['equipment_type'] == 'PTAC' }.map { |r| r.reject { |k, _| k == 'notes' } } }
    assert_equal ptac.call(DATA), ptac.call(DATA_2025),
                 'Table -G (PTAC) is identical in both printed editions'
  end

  # Table -A 2025: split-system small HSPF 7.8 (printed; 2020 printed 7.4),
  # single-package stays 7.4; the COPh ladder is unchanged.
  def test_2025_heat_pump_heating_matches_printed_table_a
    small = DATA_2025['heat_pumps_heating'].select { |r| r['minimum_capacity'].to_f.zero? }
    by_sub = small.to_h { |r| [r['subcategory'], r['minimum_heating_seasonal_performance_factor']] }
    assert_in_delta 7.4, by_sub['Single Package'], 1e-9, 'printed 2025: single-package others HSPF 7.4'
    assert_in_delta 7.8, by_sub['Split System'], 1e-9, 'printed 2025: split-system others HSPF 7.8'
    low_temp = DATA_2025['heat_pumps_heating'].filter_map { |r| r['minimum_coefficient_of_performance_heating_low_temp'] }.uniq.sort
    assert_equal [2.05, 2.25], low_temp, 'printed -8.3 C COPh vendored informationally'
  end

  # 2025 small-HP cooling takes the printed -A reading (SEER 15), unlike
  # 2020's legacy -B reading (EER 11) — a documented cross-edition difference.
  def test_2025_small_heat_pump_cooling_is_seer_15
    small = DATA_2025['heat_pumps'].select { |r| r['minimum_capacity'].to_f.zero? && r['subcategory'] !~ /single-phase/ }
    assert small.any?
    assert(small.all? { |r| r['minimum_seasonal_efficiency'] == 15.0 },
           'printed 2025 -A: small air conditioners AND heat pumps, others — SEER 15')
  end

  # The SEER2 single-phase additions (printed 14.3) are INERT for the engine:
  # their subcategory never matches the Single Package lookup.
  def test_2025_seer2_rows_are_present_and_inert
    seer2 = DATA_2025['unitary_acs'].select { |r| r['minimum_seasonal_energy_efficiency_ratio_2'] }
    assert_equal 4, seer2.size
    assert(seer2.all? { |r| r['minimum_seasonal_energy_efficiency_ratio_2'] == 14.3 }, 'printed SEER2 14.3')
    assert(seer2.all? { |r| r['subcategory'] =~ /single-phase/ },
           "single-phase subcategory — never matched by the engine's 'Single Package' lookup")
  end
end
