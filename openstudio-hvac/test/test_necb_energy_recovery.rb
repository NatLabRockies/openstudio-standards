require_relative 'test_helper'

# 8.4.4.19/8.4.5.19 energy recovery + the article-coverage completeness gate.
#
# The 5.2.10.1 trigger is specification-based: exhaust heat content [kW] =
# 0.00123 x OA(L/s) x (avg exhaust T - winter design T). No sizing run needed —
# OA comes from DesignSpecificationOutdoorAir, exhaust T from heating setpoints,
# winter design T from the .stat file or the building override.
class TestNecbEnergyRecovery < Minitest::Test
  include FixtureHelper

  def proposed_office(oa_per_area: nil)
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    if oa_per_area
      model.getSpaces.each do |space|
        spec = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
        spec.setOutdoorAirFlowperFloorArea(oa_per_area)
        space.setDesignSpecificationOutdoorAir(spec)
      end
    end
    model
  end

  def reference(model, vintage: '2020', extra: {})
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }
    OpenStudioHVAC::NECB.reference_hvac(model, vintage: vintage,
                                        building: { storeys: 3, zone_types: types,
                                                    winter_design_temp_c: -20.0 }.merge(extra))
  end

  # Trigger check with hand-computed heat content: fixture floor area ~460 m2 total.
  # OA 0.02 m3/s.m2 -> ~9.2 m3/s; EHC = 0.00123 * 9200 L/s * (21 - (-20)) ~= 464 kW > 150
  def test_erv_added_when_exhaust_heat_content_exceeds_150_kw
    result = reference(proposed_office(oa_per_area: 0.02))

    hxs = result.model.getHeatExchangerAirToAirSensibleAndLatents
    refute_empty hxs, 'ERV required per 5.2.10.1 (EHC >> 150 kW)'
    hx = hxs.first
    assert_equal 'Rotary', hx.heatExchangerType
    assert_in_delta 0.5, hx.sensibleEffectivenessat100HeatingAirFlow, 1e-6
    assert_in_delta(-23.3, hx.thresholdTemperature, 1e-6)
    refute_empty result.model.getSetpointManagerOutdoorAirPretreats, 'OA pretreat SPM controls the ERV'

    decision = result.audit.entries.find { |e| e[:action].include?('energy recovery added') }
    assert_match(/8\.4\.4\.19/, decision[:article])
    assert_match(/5\.2\.10\.1/, decision[:article])
    assert_operator decision[:inputs][:exhaust_heat_content_kw], :>, 150
  end

  def test_no_erv_below_threshold_but_decision_logged
    result = reference(proposed_office(oa_per_area: 0.001)) # ~23 kW EHC

    assert_empty result.model.getHeatExchangerAirToAirSensibleAndLatents
    decision = result.audit.entries.find { |e| e[:action].include?('energy recovery not required') }
    refute_nil decision, 'below-threshold outcome must still be a logged decision'
    assert_operator decision[:inputs][:exhaust_heat_content_kw], :<, 150
  end

  def test_missing_oa_specs_warns_never_silent
    result = reference(proposed_office) # no DesignSpecificationOutdoorAir anywhere
    warning = result.audit.warnings.find { |w| w[:action].include?('no DesignSpecificationOutdoorAir') }
    refute_nil warning
    assert_equal '5.2.10.1.', warning[:article]
  end

  def test_2025_erv_cites_renumbered_article
    result = reference(proposed_office(oa_per_area: 0.02), vintage: '2025')
    decision = result.audit.entries.find { |e| e[:action].include?('energy recovery added') }
    assert_match(/8\.4\.5\.19/, decision[:article])
  end

  # ---- the completeness gate the ERV gap motivated ----

  # Every article of the reference subsection appears in every audit, with a status;
  # partial/not_implemented articles surface as warnings.
  def test_article_coverage_emitted_for_all_20_articles
    result = reference(proposed_office(oa_per_area: 0.02))
    coverage = result.audit.entries.select { |e| e[:step] == :coverage }
    assert_equal 20, coverage.size, 'all Subsection 8.4.4 articles accounted for'
    (1..20).each do |n|
      assert coverage.any? { |e| e[:article] == "8.4.4.#{n}." }, "article 8.4.4.#{n}. missing from coverage"
    end
    # honesty: known gaps are warnings, not buried info lines
    gaps = coverage.select { |e| e[:level] == :warning }
    assert gaps.any? { |e| e[:article] == '8.4.4.12.' }, 'economizer gap (8.4.4.12) must be a warning'
    assert gaps.any? { |e| e[:article] == '8.4.4.16.' }, 'radiant gap (8.4.4.16) must be a warning'
    # implemented articles report how many decisions cited them this run
    selection = coverage.find { |e| e[:article] == '8.4.4.7.' }
    assert_operator selection[:inputs][:decisions_citing], :>, 0
    erv = coverage.find { |e| e[:article] == '8.4.4.19.' }
    assert_operator erv[:inputs][:decisions_citing], :>, 0
  end

  def test_coverage_manifest_lint_both_vintages
    valid = %w[implemented partial not_implemented satisfied_by_clone host_scope]
    %w[2020 2025].each do |vintage|
      manifest = OpenStudioHVAC::NECB.rules(vintage)['article_coverage']['articles']
      assert_equal 20, manifest.size
      manifest.each do |art|
        assert_includes valid, art['status'], "#{art['article']} has invalid status"
        assert art['title'], "#{art['article']} missing title"
        if %w[partial not_implemented].include?(art['status'])
          assert art['gaps'], "#{art['article']} is #{art['status']} but declares no gaps"
        end
      end
      prefix = vintage == '2020' ? '8.4.4' : '8.4.5'
      assert manifest.all? { |a| a['article'].start_with?(prefix) }
    end
  end

  # 8.4.4.6.(2): purchased cooling -> air-cooled electric chiller in the reference
  def test_purchased_cooling_forces_air_cooled_chiller
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'DOAS with fan coil district chilled water with boiler', zones)
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Museum archives'] } # -> System 2
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types,
                                                                    winter_design_temp_c: -20.0 })

    sys2 = result.assignments.find { |a| a.reference_system == 2 }
    refute_nil sys2
    assert_equal 'air_cooled', sys2.config['chw_source']
    chillers = result.model.getChillerElectricEIRs
    refute_empty chillers
    assert chillers.all? { |c| c.condenserType == 'AirCooled' }
    assert result.audit.entries.any? { |e| e[:action].include?('air-cooled electric chiller') }
  end
end
