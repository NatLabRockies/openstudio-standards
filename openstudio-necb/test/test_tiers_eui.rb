require_relative 'test_helper'
require 'tmpdir'

# Coverage-loop gate: Section 10 tiers, the 2025 archetype-EUI path (8.4.4),
# and the 2025 Part 11 GHG levels.
class TestTiersEUI < Minitest::Test
  include FixtureHelper

  def weather
    { epw: EPW, ddy: DDY, stat: STAT }
  end

  def test_tier_arithmetic
    audit = OpenStudioNECB::AuditLog.new
    assert_equal 1, OpenStudioNECB::Tiers.energy_tier(95_000, 100_000, audit: audit)['tier']
    assert_equal 2, OpenStudioNECB::Tiers.energy_tier(70_000, 100_000)['tier']
    assert_equal 3, OpenStudioNECB::Tiers.energy_tier(50_000, 100_000)['tier']
    assert_equal 4, OpenStudioNECB::Tiers.energy_tier(39_000, 100_000)['tier']
    assert_nil OpenStudioNECB::Tiers.energy_tier(101_000, 100_000)['tier']
    assert(audit.entries.any? { |e| e[:article].to_s.include?('10.1.2.1') })
  end

  def test_eui_bet_arithmetic
    audit = OpenStudioNECB::AuditLog.new
    target = OpenStudioNECB::Tiers.eui_building_energy_target(
      { 'Office' => nil }, 1600.0, hdd: 3890, process_loads_kwh: 5000.0, audit: audit)
    assert_in_delta 1600.0 * 175 + 5000.0, target['bet_kwh'], 0.1, 'BET = A x EUI + PL'
    assert_raises(ArgumentError) do
      OpenStudioNECB::Tiers.eui_building_energy_target({ 'Casino' => 100 }, 1600.0, hdd: 3890)
    end
    cold = OpenStudioNECB::AuditLog.new
    OpenStudioNECB::Tiers.eui_building_energy_target({ 'Office' => nil }, 1600.0, hdd: 9500, audit: cold)
    assert(cold.warnings.any? { |w| w[:action].include?('HDD') }, 'HDD >= 9000 inapplicability warns')
  end

  def test_ghg_levels
    energy = { 'electricity_kwh' => 10_000.0, 'natural_gas_kwh' => 50_000.0 }
    kg = OpenStudioNECB::Tiers.operational_ghg_kg(energy, 'ONTARIO')
    assert_in_delta (10_000 * 57.9 + 50_000 * 185) / 1000.0, kg, 0.1
    audit = OpenStudioNECB::AuditLog.new
    level = OpenStudioNECB::Tiers.ghg_level(kg, kg * 4, audit: audit)
    assert_equal 'B', level['level'], '25% of target -> level B (<= 25%)'
    assert_equal 'F', OpenStudioNECB::Tiers.ghg_level(99.0, 100.0)['level']
    assert_nil OpenStudioNECB::Tiers.ghg_level(101.0, 100.0)['level']
  end

  def test_eui_path_end_to_end
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-eui-')
    result = OpenStudioNECB.performance_compliance(
      proposed_with_hvac, vintage: '2025', path: :eui,
      archetypes: { 'Office' => :all }, weather: weather, run_dir: dir,
      run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 },
      province_state: 'ONTARIO')

    assert_nil result.reference_model, 'no reference building on the EUI path'
    bet = result.report['reference']['building_energy_target_kwh']
    area = result.proposed_model.getBuilding.floorArea
    assert_in_delta area * 175, bet, 1.0, 'BET from the Office archetype EUI (areas computed from the model)'
    refute result.report['eui']['conformant_to_8_4_4_2'], 'bare fixture does not carry Table 8.4.4.2 inputs'
    assert result.report['eui']['normalized'], 'proposed normalized to Table 8.4.4.2 before the run'
    assert(result.audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.2.(1)') },
           'normalization audited under 8.4.4.2.(1)')
    refute_nil result.compliant, 'determination made against the BET'
    assert result.report.key?('tier'), 'Section 10 tier computed against the BET'
    assert result.report['proposed'].key?('ghg_kg_co2e'), '2025 GHG computed with a province'
    assert(result.audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.1.') })
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_eui_path_guards
    assert_raises(ArgumentError) do
      OpenStudioNECB.performance_compliance(proposed_with_hvac, vintage: '2020', path: :eui,
                                            archetypes: { 'Office' => :all },
                                            run_dir: Dir.mktmpdir('osnecb-x-'))
    end
  end

  # 8.4.4.1.(1)/Table-note applicability now REFUSES on the pure :eui path — a
  # verdict outside applicability is not a determination.
  def test_eui_path_refuses_outside_applicability
    error = assert_raises(ArgumentError) do
      OpenStudioNECB.performance_compliance(
        proposed_with_hvac, vintage: '2025', path: :eui, simulate: :none, hdd: 9500,
        archetypes: { 'Office' => :all }, run_dir: Dir.mktmpdir('osnecb-hdd-'))
    end
    assert_includes error.message, 'NOT applicable'
    assert_includes error.message, 'HDD 9500'
  end
end
