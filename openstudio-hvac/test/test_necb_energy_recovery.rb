require_relative 'test_helper'

# 8.4.4.19/8.4.5.19 energy recovery + the article-coverage completeness gate.
#
# The 5.2.10.1 trigger is the NECB 2020/2025 Table 5.2.10.1.-A/-B airflow
# thresholds: climate row by HDD, band by %OA, table by operating mode
# (continuous = fan availability >= 8000 h/yr). It is evaluated POST-SIZING
# (`NECB.apply_energy_recovery`) because it needs the sized supply and
# minimum-OA flows — the umbrella calls it after the reference sizing run.
# Tests hard-size the flows instead of running EnergyPlus.
#
# This REPLACED the NECB 2011 150 kW exhaust-heat-content trigger, which was
# the wrong vintage — and permissive exactly where it matters (see the first
# test: a small high-%OA system is "R" under 2020, waved through by 2011).
class TestNecbEnergyRecovery < Minitest::Test
  include FixtureHelper

  HDD_TORONTO = 3890 # Table -A row "3000 <= HDD < 5000"; Table -B row "all other zones >= 3000"

  def proposed_office
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    model
  end

  def reference(model, vintage: '2020', extra: {})
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }
    OpenStudioHVAC::NECB.reference_hvac(model, vintage: vintage,
                                        building: { storeys: 3, zone_types: types }.merge(extra))
  end

  # Hard-size every reference air loop (the trigger needs sized flows), set the
  # OA fraction, and optionally cap fan availability below the 8000 h/yr
  # continuous threshold (06:00-18:00 daily = 4380 h -> non-continuous).
  def size_loops!(model, supply_m3s:, oa_fraction:, non_continuous: false)
    model.getAirLoopHVACs.each do |loop|
      loop.setDesignSupplyAirFlowRate(supply_m3s)
      ctrl = loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
      ctrl.setMinimumOutdoorAirFlowRate(supply_m3s * oa_fraction)
      next unless non_continuous

      schedule = OpenStudio::Model::ScheduleRuleset.new(model)
      day = schedule.defaultDaySchedule
      day.addValue(OpenStudio::Time.new(0, 6, 0, 0), 0.0)
      day.addValue(OpenStudio::Time.new(0, 18, 0, 0), 1.0)
      day.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.0)
      loop.setAvailabilitySchedule(schedule)
    end
  end

  # THE divergence that motivated replacing the 2011 trigger: a small DOAS-like
  # system at >= 80% OA. Table -A row 3000-5000 HDD, 80% band = "R (required at
  # all flow rates)" — while the 2011 formula (EHC = 0.00123 x 200 L/s x 41 K
  # ~= 10 kW << 150) would wave it through.
  def test_high_oa_small_system_required_at_all_flow_rates
    result = reference(proposed_office)
    size_loops!(result.model, supply_m3s: 0.25, oa_fraction: 0.85, non_continuous: true)
    audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)

    hxs = result.model.getHeatExchangerAirToAirSensibleAndLatents
    refute_empty hxs, '85% OA non-continuous: Table 5.2.10.1.-A says R at any flow'
    hx = hxs.first
    assert_equal 'Rotary', hx.heatExchangerType
    assert_in_delta 0.5, hx.sensibleEffectivenessat100HeatingAirFlow, 1e-6
    assert_in_delta(-23.3, hx.thresholdTemperature, 1e-6)
    refute_empty result.model.getSetpointManagerOutdoorAirPretreats, 'OA pretreat SPM controls the ERV'

    decision = audit.entries.find { |e| e[:action].include?('energy recovery added') }
    assert_match(/8\.4\.4\.19/, decision[:article])
    assert_match(/5\.2\.10\.1/, decision[:article])
    assert_equal 'non_continuous', decision[:inputs][:operation]
    assert_equal 'R (required at all flow rates)', decision[:inputs][:threshold]
    assert_equal 4380, decision[:inputs][:annual_hours], 'ruleset availability hours counted over the year'
  end

  def test_below_threshold_not_required_but_decision_logged
    result = reference(proposed_office)
    # 500 L/s at 15% OA, non-continuous: Table -A row 3000-5000, 10% band -> 12 270 L/s
    size_loops!(result.model, supply_m3s: 0.5, oa_fraction: 0.15, non_continuous: true)
    audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)

    assert_empty result.model.getHeatExchangerAirToAirSensibleAndLatents
    decision = audit.entries.find { |e| e[:action].include?('energy recovery not required') }
    refute_nil decision, 'below-threshold outcome must still be a logged decision'
    assert_equal '>= 12270 L/s', decision[:inputs][:threshold]
    assert_equal 500, decision[:inputs][:supply_l_s]
  end

  # Builders leave availability at Always On -> 8760 h -> CONTINUOUS -> Table
  # -B "all other zones >= 3000 HDD" = R at every band. The same system that
  # test_below_threshold waves through as non-continuous is required here.
  def test_always_on_default_classifies_continuous_and_requires
    result = reference(proposed_office)
    size_loops!(result.model, supply_m3s: 0.5, oa_fraction: 0.15)
    audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)

    refute_empty result.model.getHeatExchangerAirToAirSensibleAndLatents
    decision = audit.entries.find { |e| e[:action].include?('energy recovery added') }
    assert_equal 'continuous', decision[:inputs][:operation]
    assert_equal 8760, decision[:inputs][:annual_hours]
    assert_equal 'R (required at all flow rates)', decision[:inputs][:threshold]
  end

  def test_below_10_pct_oa_is_outside_the_tables
    result = reference(proposed_office)
    size_loops!(result.model, supply_m3s: 2.0, oa_fraction: 0.05) # even continuous
    audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)

    assert_empty result.model.getHeatExchangerAirToAirSensibleAndLatents
    decision = audit.entries.find { |e| e[:action].include?('energy recovery not required') }
    assert_match(/below 10% OA/, decision[:inputs][:threshold])
  end

  def test_unsized_flows_warn_never_silent
    result = reference(proposed_office) # no hard sizes, no sizing run
    audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)

    assert_empty result.model.getHeatExchangerAirToAirSensibleAndLatents
    warning = audit.warnings.find { |w| w[:action].include?('needs SIZED supply/OA flows') }
    refute_nil warning
    assert_match(/5\.2\.10\.1/, warning[:article])
  end

  def test_idempotent_second_pass_adds_nothing
    result = reference(proposed_office)
    size_loops!(result.model, supply_m3s: 0.25, oa_fraction: 0.85)
    OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)
    count = result.model.getHeatExchangerAirToAirSensibleAndLatents.size
    OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: HDD_TORONTO)
    assert_equal count, result.model.getHeatExchangerAirToAirSensibleAndLatents.size
  end

  def test_2025_erv_cites_renumbered_article
    result = reference(proposed_office, vintage: '2025')
    size_loops!(result.model, supply_m3s: 0.25, oa_fraction: 0.85)
    audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, vintage: '2025', hdd: HDD_TORONTO)
    decision = audit.entries.find { |e| e[:action].include?('energy recovery added') }
    assert_match(/8\.4\.5\.19/, decision[:article])
  end

  # ---- the completeness gate the ERV gap motivated ----

  # Every article of the reference subsection appears in every audit, with a status;
  # partial/not_implemented articles surface as warnings.
  def test_article_coverage_emitted_for_all_20_articles
    result = reference(proposed_office)
    coverage = result.audit.entries.select { |e| e[:step] == :coverage }
    # 20 Subsection 8.4.4 articles + '8.4.1.1. (HVAC)' + '8.4.2.10.' (the
    # covered_by manifest entries reconciling cross-gem delegations)
    assert_equal 22, coverage.size, 'all declared articles accounted for'
    (1..20).each do |n|
      assert coverage.any? { |e| e[:article] == "8.4.4.#{n}." }, "article 8.4.4.#{n}. missing from coverage"
    end
    # honesty: known gaps are warnings, not buried info lines
    gaps = coverage.select { |e| e[:level] == :warning }
    assert gaps.any? { |e| e[:article] == '8.4.4.12.' }, 'economizer gap (8.4.4.12) must be a warning'
    # 8.4.4.16 is re-manifested modeller-scope (D-11): (2) is identical by
    # construction, (1) binds only when the modeller approximates radiant
    # convectively — an info scope note, NOT a warning.
    stc = coverage.find { |e| e[:article] == '8.4.4.16.' }
    assert_equal :info, stc[:level], '8.4.4.16 is a modeller scope note, not a warning'
    assert_equal 'modeller', stc[:inputs][:gap_owner]
    assert_includes stc[:action], 'modeller scope'
    # implemented articles report how many decisions cited them this run
    selection = coverage.find { |e| e[:article] == '8.4.4.7.' }
    assert_operator selection[:inputs][:decisions_citing], :>, 0
    # 8.4.4.19 is now a POST-SIZING determination: 0 citations during the
    # build is correct; the manifest line must still declare it implemented.
    erv = coverage.find { |e| e[:article] == '8.4.4.19.' }
    assert_equal 'implemented', erv[:inputs][:status]
    assert_match(/POST-SIZING/i, erv[:action])
  end

  def test_coverage_manifest_lint_both_vintages
    valid = %w[implemented partial not_implemented satisfied_by_clone host_scope]
    %w[2020 2025].each do |vintage|
      manifest = OpenStudioHVAC::NECB.rules(vintage)['article_coverage']['articles']
      assert_equal 22, manifest.size # 20 reference articles + 8.4.1.1.(HVAC) + 8.4.2.10.
      manifest.each do |art|
        assert_includes valid, art['status'], "#{art['article']} has invalid status"
        assert art['title'], "#{art['article']} missing title"
        if %w[partial not_implemented].include?(art['status'])
          assert art['gaps'], "#{art['article']} is #{art['status']} but declares no gaps"
        end
      end
      prefix = vintage == '2020' ? '8.4.4' : '8.4.5'
      shared = ['8.4.1.1. (HVAC)', '8.4.2.10.']
      assert manifest.all? { |a| a['article'].start_with?(prefix) || shared.include?(a['article']) }
    end
  end

  # 8.4.4.6.(2): purchased cooling -> air-cooled electric chiller in the reference
  def test_purchased_cooling_forces_air_cooled_chiller
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'DOAS with fan coil district chilled water with boiler', zones)
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Museum archives'] } # -> System 2
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types })

    sys2 = result.assignments.find { |a| a.reference_system == 2 }
    refute_nil sys2
    assert_equal 'air_cooled', sys2.config['chw_source']
    chillers = result.model.getChillerElectricEIRs
    refute_empty chillers
    assert chillers.all? { |c| c.condenserType == 'AirCooled' }
    assert result.audit.entries.any? { |e| e[:action].include?('air-cooled electric chiller') }
  end
end
