require_relative 'test_helper'
require 'json'

# D-58 — the proposed→reference verification matrix. Every catalog system,
# built as a PROPOSED on the 5-zone fixture, characterized and selected under
# four discriminating scenarios, must produce the ADJUDICATED reference
# assignment vendored in fixtures/reference_selection_matrix.json — in BOTH
# naming passes: 'catalog' (name resolution) and 'scrubbed' (randomized names,
# forcing the structural detector foreign models hit).
#
# The golden was adjudicated 2026-08-02 against Table 8.4.4.7.-A fetched from
# the codes MCP (all 12 category rules match the printed table) plus the
# 8.4.4.13 heat-pump rules; see D-58 in openstudio-necb/docs/necb_decisions.md.
#
# Default run: a representative subset (every family + every special-rule
# shape), ~2 min. FULL_MATRIX=1 runs all 97 (~7 min). UPDATE_GOLDEN=1
# regenerates the golden from the current code — only after re-adjudication.
class TestReferenceSelectionMatrix < Minitest::Test
  include FixtureHelper

  GOLDEN = File.expand_path('fixtures/reference_selection_matrix.json', __dir__)
  SCENARIOS = {
    'general_2storey' => { storeys: 2, type: 'office' },
    'general_3storey' => { storeys: 3, type: 'office' },
    'residential' => { storeys: 3, type: 'multi-unit residential' },
    'data_processing' => { storeys: 1, type: 'data centre' }
  }.freeze

  # One representative per family plus every special-rule shape the matrix
  # found interesting: plant HPs (hs09/14), district variants, DOAS+fan-coil
  # composite, MAU+PTAC, shared PSZ (electric AND ashp), wshp, vrf, MZ built-up.
  SUBSET = [
    'Baseboard electric', 'Baseboard district hot water', 'Forced air furnace',
    'PSZ RTU Electric and DX Coils and Electric Baseboard',
    'PSZ RTU ASHP with Gas and ASHP with Gas Supp. Heat Coils and Electric Baseboard',
    'PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC',
    'FPFC MAU Chilled Water Coils with Scroll Chiller',
    'TPFC MAU Chilled Water Coils with Scroll Chiller',
    'MZ BU RTU Electric Heating Coil Centrifugal Chiller and Electric Baseboard',
    'DOAS with fan coil air-cooled chiller with boiler',
    'DOAS with fan coil air-cooled chiller with district hot water',
    'DOAS with VRF', 'DOAS with water source heat pumps',
    'hs09_ccashp_baseboard', 'hs11_ashp_pthp', 'hs14_cgshp_fancoils',
    'hs16_ashp_cawhp_fancoils', 'Direct evap coolers with no heat',
    'Gas unit heaters', 'Window AC with baseboard electric', 'PTHP',
    'Water source heat pumps'
  ].freeze

  def golden
    @golden ||= JSON.parse(File.read(GOLDEN))
  end

  def names_under_test
    all = OpenStudioHVAC::Catalog.rows.map { |r| r['name'] }
    return all if ENV['FULL_MATRIX'] || ENV['UPDATE_GOLDEN']

    # subset entries are prefixes-or-exact against the catalog (some names carry
    # long suffixes); every subset entry must match something or the test is lying
    SUBSET.map do |want|
      all.find { |n| n == want } || all.find { |n| n.start_with?(want) } ||
        flunk("SUBSET entry '#{want}' matches no catalog name")
    end.uniq
  end

  def compute_row(name)
    row = OpenStudioHVAC::Catalog.rows.find { |r| r['name'] == name }
    record = { 'name' => name, 'family' => row['family'] }
    %w[catalog scrubbed].each do |pass|
      model = load_fixture
      zones = model.getThermalZones.sort_by(&:nameString)
      OpenStudioHVAC.build_system(model, name, zones)
      if pass == 'scrubbed'
        model.getAirLoopHVACs.each_with_index { |l, i| l.setName("Air System #{i + 1}") }
        model.getPlantLoops.each_with_index { |l, i| l.setName("Plant #{i + 1}") }
      end
      facts = OpenStudioHVAC::Classify.characterize(model, audit: nil)
      SCENARIOS.each do |label, scenario|
        zone_types = facts[:zone_groups].flat_map { |g| g[:zones] }.uniq.to_h { |z| [z, scenario[:type]] }
        info = { storeys: scenario[:storeys], zone_types: zone_types, winter_design_temp_c: -20 }
        assignments = OpenStudioHVAC::NECB.select_reference_systems(
          facts: facts, building: info, vintage: '2020', audit: nil
        ).map do |a|
          { 'system' => a.reference_system, 'action' => a.action.to_s,
            'energy_type' => a.energy_type, 'catalog' => a.catalog_name, 'zones' => a.zones.size }
        end.uniq
        record["#{pass}_#{label}"] = assignments
      end
    end
    record
  end

  def normalize(assignments)
    Array(assignments).map { |a| a.transform_keys(&:to_s).transform_values { |v| v.is_a?(Symbol) ? v.to_s : v } }
                      .map { |a| a.slice('system', 'action', 'energy_type', 'catalog', 'zones') }
  end

  def test_reference_assignments_match_the_adjudicated_golden
    names = names_under_test
    if ENV['UPDATE_GOLDEN']
      skip 'UPDATE_GOLDEN regeneration is the matrix script in scratchpad — see D-58'
    end

    names.each do |name|
      expected = golden.find { |r| r['name'] == name }
      refute_nil expected, "'#{name}' missing from the golden — regenerate and re-adjudicate (D-58)"
      actual = compute_row(name)
      %w[catalog scrubbed].each do |pass|
        SCENARIOS.each_key do |label|
          key = "#{pass}_#{label}"
          assert_equal normalize(expected[key]), normalize(actual[key]),
                       "#{name} / #{key}: reference assignment drifted from the adjudicated matrix"
        end
      end
    end
  end

  def test_catalog_and_scrubbed_passes_agree_in_the_golden
    golden.each do |row|
      SCENARIOS.each_key do |label|
        assert_equal normalize(row["catalog_#{label}"]), normalize(row["scrubbed_#{label}"]),
                     "#{row['name']} / #{label}: the golden itself carries a naming-pass divergence — " \
                     'foreign proposeds would get a different reference than gem-built ones'
      end
    end
  end

  def test_golden_covers_the_whole_catalog
    missing = OpenStudioHVAC::Catalog.rows.map { |r| r['name'] } - golden.map { |r| r['name'] }
    assert_empty missing, 'catalog systems missing from the adjudicated golden (new system added? re-run D-58)'
  end
end
