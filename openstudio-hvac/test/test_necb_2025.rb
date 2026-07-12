require_relative 'test_helper'

# NECB 2025 vintage: same reference-rule VALUES as 2020 but the performance path moved
# from Subsection 8.4.4 to 8.4.5 (verified via the codes MCP edition diff). Selections
# must be identical across vintages while citations carry the 2025 article numbers.
# Efficiencies are native 2025 (efficiencies_2025.json, transcribed from Tables
# 5.2.12.1.-K/-N/-O/-A): chillers/boilers/furnaces/unitary-AC ladder verified identical
# to 2020; the two real changes are HP cooling <19 kW EER 11.0 -> SEER 15 and
# split-system HP heating HSPF 7.4 -> 7.8.
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
    assert_nil rules['provenance']['efficiency_vintage_fallback'], 'fallback lifted'
  end

  # end-to-end reference_hvac at vintage 2025: correct topology, native efficiencies,
  # and NO fallback warning
  def test_reference_hvac_2025_native_efficiencies
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }

    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2025',
                                                 building: { storeys: 1, zone_types: types })

    assert_equal [3], result.assignments.map(&:reference_system).uniq
    refute_empty result.model.getAirLoopHVACs
    selection = result.audit.entries.find { |e| e[:step] == :selection && e[:level] == :decision }
    assert_match(/8\.4\.5/, selection[:article])
    assert_empty result.audit.warnings.select { |w| w[:action].include?('fall back') },
                 '2025 efficiencies are native — no fallback warning'
  end

  def test_effective_vintage_native_for_both
    %w[2020 2025].each do |v|
      vintage, reason = OpenStudioHVAC::NECB::Efficiency.effective_vintage(v)
      assert_equal v, vintage
      assert_nil reason
    end
  end

  # The two REAL 2025 efficiency changes (everything else verified identical to 2020):
  # HP cooling < 19 kW: EER 11.0 (2020) -> SEER 15 (2025 Table 5.2.12.1.-A merged class)
  def test_2025_small_heat_pump_cooling_is_seer_15
    cops = {}
    %w[2020 2025].each do |vintage|
      model = load_fixture
      zones = model.getThermalZones.sort_by(&:nameString)
      OpenStudioHVAC.build_system(model, 'PSZ RTU ASHP with Electric and ASHP with Electric Supp. Heat Coils and Electric Baseboard', zones)
      model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(12_000.0) }
      model.getCoilHeatingDXSingleSpeeds.each { |c| c.setRatedTotalHeatingCapacity(12_000.0) }
      OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: vintage)
      coil = model.getCoilCoolingDXSingleSpeeds.min_by(&:nameString)
      cops[vintage] = coil.ratedCOP.respond_to?(:is_initialized) ? coil.ratedCOP.get : coil.ratedCOP
    end
    # 2020: eer_to_cop_no_fan(11.0) = ((11*0.29307)+0.12)/0.88 ~= 3.800
    assert_in_delta 3.800, cops['2020'], 0.01
    # 2025: seer_to_cop_no_fan(15) = -0.0076*225 + 0.3796*15 = 3.984
    assert_in_delta 3.984, cops['2025'], 0.01
    # heating side unchanged: 7.4 HSPF (Single Package) both vintages
  end

  def test_2025_boiler_and_chiller_values_unchanged
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(100_000.0) }
    model.getChillerElectricEIRs.each { |c| c.setReferenceCapacity(200_000.0) }
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2025')

    primary = model.getBoilerHotWaters.find { |b| b.nameString.include?('Primary') }
    assert_in_delta 0.90, primary.nominalThermalEfficiency, 1e-6 # -N: AFUE 90, unchanged
    chiller = model.getChillerElectricEIRs.min_by(&:nameString)
    assert_in_delta 3.517 / 0.77927, chiller.referenceCOP, 1e-3 # -K Path B, unchanged
  end
end
