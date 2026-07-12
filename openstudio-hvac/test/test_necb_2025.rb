require_relative 'test_helper'

# NECB 2025 vintage: same rule VALUES as 2020 but the performance path moved from
# Subsection 8.4.4 to 8.4.5 (verified via the codes MCP edition diff). Selections must
# be identical across vintages while citations carry the 2025 article numbers; the
# efficiency pass falls back to 2020 tables with an explicit audit warning until the
# restructured 2025 Table 5.2.12.1 series is transcribed.
class TestNecb2025 < Minitest::Test
  include FixtureHelper

  def group(zones: ['Z1'], heated: true, cooled: true, heat_fuels: ['NaturalGas'],
            heat_pump: false, cooling_kw: 10.0)
    { zones: zones, air_loop: 'L1', family: nil, catalog_name: nil, family_guess: nil,
      heated: heated, cooled: cooled, heating_energy_types: heat_fuels,
      cooling_energy_types: cooled ? ['Electricity'] : [], heat_pump: heat_pump,
      terminal_type: :none, design_cooling_kw: cooling_kw, evidence: [] }
  end

  def select(groups, zone_types:, storeys: 1, vintage: '2025')
    OpenStudioHVAC::NECB.select_reference_systems(
      facts: { built_by_gem: false, zone_groups: groups, plants: [],
               purchased_energy: { heating: false, cooling: false } },
      building: { storeys: storeys, zone_types: zone_types }, vintage: vintage
    )
  end

  # selections are identical across 2020/2025 for a spread of scenarios
  def test_2025_selections_match_2020
    scenarios = [
      [[group], { 'Z1' => 'Office - enclosed' }, 2],
      [[group], { 'Z1' => 'Office - enclosed' }, 5],
      [[group(cooling_kw: 25.0)], { 'Z1' => 'Data centre' }, 1],
      [[group], { 'Z1' => 'Warehouse - med/blk' }, 1],
      [[group(heat_pump: true)], { 'Z1' => 'Office - enclosed' }, 1],
      [[group(heated: true, cooled: false, cooling_kw: 0.0)], { 'Z1' => 'Multi-unit residential' }, 3]
    ]
    scenarios.each do |groups, types, storeys|
      a20 = select(groups.map(&:dup), zone_types: types, storeys: storeys, vintage: '2020')
      a25 = select(groups.map(&:dup), zone_types: types, storeys: storeys, vintage: '2025')
      assert_equal a20.map(&:reference_system), a25.map(&:reference_system),
                   "selection diverged for #{types.values.first} @ #{storeys} storeys"
      assert_equal a20.map(&:catalog_name), a25.map(&:catalog_name)
      assert_equal a20.map(&:action), a25.map(&:action)
    end
  end

  # 2025 citations carry the renumbered articles (8.4.5.x, Table 8.4.5.7.-A)
  def test_2025_article_renumbering
    a = select([group(heat_pump: true)], zone_types: { 'Z1' => 'Office - enclosed' }).first
    joined = a.articles.join('; ')
    assert_match(/8\.4\.5\.7/, joined)
    assert_match(/8\.4\.5\.13/, joined)
    refute_match(/8\.4\.4\.\d/, joined, '2020 article numbers must not leak into 2025 output')

    rules = OpenStudioHVAC::NECB.rules('2025')
    assert_equal '8.4.5.8.(1)-(2)', rules['oversizing']['article']
    assert_equal '2025', rules['provenance']['edition']
    assert_equal '2020', rules['provenance']['efficiency_vintage_fallback']
  end

  # end-to-end reference_hvac at vintage 2025: correct topology + fallback warning
  def test_reference_hvac_2025_with_efficiency_fallback
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }

    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2025',
                                                 building: { storeys: 1, zone_types: types })

    assert_equal [3], result.assignments.map(&:reference_system).uniq
    refute_empty result.model.getAirLoopHVACs
    # decisions cite 2025 articles
    selection = result.audit.entries.find { |e| e[:step] == :selection && e[:level] == :decision }
    assert_match(/8\.4\.5/, selection[:article])
    # efficiency fallback is loud, never silent
    fallback = result.audit.warnings.find { |w| w[:action].include?('fall back to NECB 2020') }
    refute_nil fallback, 'expected the 2025->2020 efficiency fallback warning'
    assert_match(/5\.2\.12\.1\.-A.*changed significantly/, fallback[:action])
  end

  def test_2020_unaffected_by_fallback_machinery
    vintage, reason = OpenStudioHVAC::NECB::Efficiency.effective_vintage('2020')
    assert_equal '2020', vintage
    assert_nil reason
  end
end
