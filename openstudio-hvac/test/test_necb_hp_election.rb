require_relative 'test_helper'

# D-52 — 8.4.4.13.(2)(g): the reference heat pump's auxiliary-heating energy
# type is elected from the proposed building's annual delivered-heat data, with
# the 33% proviso, (g)(i)/(g)(ii) scoping, and the audited structural-proxy
# fallback. The election itself is pure data logic; the inventory half is
# exercised against a real SYS3-ASHP build.
class TestNecbHpElection < Minitest::Test
  include FixtureHelper

  SYS3_ASHP = 'PSZ RTU ASHP with Gas and ASHP with Gas Supp. Heat Coils and Electric Baseboard'.freeze

  HP_RULES = { 'aux_energy_type_threshold_fraction' => 0.33 }.freeze

  def group(zones: ['Zone A'], air_loop: 'Loop 1', sources: [:air], source_loops: [])
    { zones: zones, air_loop: air_loop, heat_pump: true,
      heat_pump_sources: sources, heat_pump_source_loops: source_loops }
  end

  def facts_for(*groups)
    { zone_groups: groups }
  end

  # --- the election ---------------------------------------------------------

  def test_gate_passes_and_the_largest_terminal_fuel_is_elected
    audit = OpenStudioHVAC::AuditLog.new
    g = group
    annual = { loops: { 'Loop 1' => { hp_j: 60e9, aux: [{ fuel: 'NaturalGas', j: 30e9 }] } },
               zones: { 'Zone A' => [{ fuel: 'Electricity', j: 10e9, role: :aux }] } }
    elected = OpenStudioHVAC::NECB.heat_pump_aux_energy_type(g, facts_for(g), HP_RULES, annual, audit)
    assert_equal 'gas', elected, 'gas terminal energy (30 GJ) beats electric (10 GJ); HP share 60% > 33%'
    entry = audit.entries.find { |e| e[:action].include?('ELECTED') }
    refute_nil entry
    assert_equal '8.4.4.13.(2)(g)(i)', entry[:article]
    assert_includes entry[:ruling].to_s, 'D-52'
  end

  def test_gate_fails_falls_back_to_the_structural_proxy
    audit = OpenStudioHVAC::AuditLog.new
    g = group
    annual = { loops: { 'Loop 1' => { hp_j: 10e9, aux: [{ fuel: 'NaturalGas', j: 90e9 }] } }, zones: {} }
    elected = OpenStudioHVAC::NECB.heat_pump_aux_energy_type(g, facts_for(g), HP_RULES, annual, audit)
    assert_nil elected, 'share 10% <= 33% — the proviso is unmet, sentence (g) does not elect'
    entry = audit.entries.find { |e| e[:action].include?('NOT above') }
    refute_nil entry, 'the gate failure is an audited decision naming the proxy'
  end

  def test_no_terminal_heating_falls_back
    audit = OpenStudioHVAC::AuditLog.new
    g = group
    annual = { loops: { 'Loop 1' => { hp_j: 50e9, aux: [] } }, zones: {} }
    assert_nil OpenStudioHVAC::NECB.heat_pump_aux_energy_type(g, facts_for(g), HP_RULES, annual, audit)
    assert(audit.entries.any? { |e| e[:action].include?('nothing to elect') })
  end

  def test_no_annual_data_falls_back_with_the_sizing_note
    audit = OpenStudioHVAC::AuditLog.new
    g = group
    assert_nil OpenStudioHVAC::NECB.heat_pump_aux_energy_type(g, facts_for(g), HP_RULES, nil, audit)
    assert(audit.entries.any? { |e| e[:action].include?('no proposed annual data') })
  end

  def test_g_ii_aggregates_over_groups_sharing_the_source_water_loop
    audit = OpenStudioHVAC::AuditLog.new
    a = group(zones: ['Zone A'], air_loop: 'Loop 1', sources: [:external], source_loops: ['GHX Loop'])
    b = group(zones: ['Zone B'], air_loop: 'Loop 2', sources: [:external], source_loops: ['GHX Loop'])
    annual = { loops: { 'Loop 1' => { hp_j: 40e9, aux: [{ fuel: 'Electricity', j: 10e9 }] },
                        'Loop 2' => { hp_j: 40e9, aux: [{ fuel: 'NaturalGas', j: 30e9 }] } },
               zones: {} }
    elected = OpenStudioHVAC::NECB.heat_pump_aux_energy_type(a, facts_for(a, b), HP_RULES, annual, audit)
    assert_equal 'gas', elected,
                 "(g)(ii): group A alone would elect electric; the shared-loop union brings in B's 30 GJ of gas"
    entry = audit.entries.find { |e| e[:action].include?('ELECTED') }
    assert_equal '8.4.4.13.(2)(g)(ii)', entry[:article]
    assert_equal ['Loop 1', 'Loop 2'], entry[:inputs][:scope_loops]
  end

  def test_election_wires_into_finalize_through_reference_hvac
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, SYS3_ASHP, zones)

    # Hand-built annual data naming the proposed loop: electric baseboards carry
    # far more energy than the gas supplemental, and the HP clears the gate —
    # the elected variant must be ELECTRIC even though the structural proxy
    # (gas supplemental present) would elect gas.
    loop_name = model.getAirLoopHVACs.first.nameString
    zone_data = zones.to_h do |z|
      [z.nameString, [{ fuel: 'Electricity', j: 20e9, role: :aux }]]
    end
    annual = { loops: { loop_name => { hp_j: 200e9, aux: [{ fuel: 'NaturalGas', j: 5e9 }] } },
               zones: zone_data }

    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020', audit: audit,
                                                 proposed_annual: annual)
    hp = result.assignments.find { |a| a.reference_system == 'hp' }
    refute_nil hp, 'the ASHP proposed redirects to the hp reference'
    assert_equal 'electric', hp.energy_type,
                 'annual election (electric baseboards dominate) overrides the structural gas proxy'
    without = OpenStudioHVAC::NECB.reference_hvac(load_and_build, vintage: '2020',
                                                  audit: OpenStudioHVAC::AuditLog.new)
    proxy = without.assignments.find { |a| a.reference_system == 'hp' }
    assert_equal 'gas', proxy.energy_type, 'control: the structural proxy elects gas without annual data'
  end

  def load_and_build
    model = load_fixture
    OpenStudioHVAC.build_system(model, SYS3_ASHP, model.getThermalZones.sort_by(&:nameString))
    model
  end

  # --- the inventory --------------------------------------------------------

  def test_inventory_finds_hp_aux_and_baseboards_on_a_real_build
    model = load_and_build
    inventory = OpenStudioHVAC::Classify.heating_election_inventory(model)

    loop_name = model.getAirLoopHVACs.first.nameString
    entry = inventory[:loops][loop_name]
    refute_nil entry, 'the ASHP loop appears in the inventory'
    assert(entry[:hp].any? { |n| n =~ /HeatingDX/i }, "DX heating coil in hp: #{entry[:hp].inspect}")
    assert(entry[:aux].any? { |a| a[:fuel] == 'NaturalGas' }, 'gas supplemental coil in aux')

    baseboards = inventory[:zones].values.flatten.select { |e| e[:variable] == OpenStudioHVAC::Classify::BASEBOARD_VARIABLE }
    assert baseboards.any?, 'electric baseboards inventoried per zone'
    assert(baseboards.all? { |e| e[:fuel] == 'Electricity' && e[:role] == :aux })
  end
end
