require_relative 'test_helper'
require 'tmpdir'
require 'json'

# The umbrella pipeline: proposed -> reference (HVAC + envelope, one clone, one
# audit) -> sizing/annual EnergyPlus -> 8.4.1.2 comparison -> unified costing ->
# report.json + audit.json.
class TestCompliance < Minitest::Test
  include FixtureHelper

  def weather
    { epw: EPW, ddy: DDY, stat: STAT }
  end

  def test_none_mode_transforms_without_simulation
    result = OpenStudioNECB.performance_compliance(
      proposed_with_hvac, vintage: '2020', simulate: :none, hdd: 3890,
      building: { storeys: 1, zone_types: zone_types_for(load_fixture), winter_design_temp_c: -20 },
      run_dir: Dir.mktmpdir('osnecb-none-'))

    assert_nil result.compliant, 'compliance undetermined without annual runs'
    refute_empty result.reference_model.getAirLoopHVACs.to_a + result.reference_model.getPlantLoops.to_a,
                 'reference HVAC generated'
    wall = result.reference_model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    assert_match(/Lightweight/, wall.construction.get.nameString, 'reference envelope applied to the SAME clone')
    assert(result.audit.warnings.any? { |w| w[:action].include?('UNSIZED') }, 'unsized path warns loudly')

    report = JSON.parse(File.read(File.join(result.run_dir, 'report.json')))
    assert_nil report['compliant']
    assert File.exist?(File.join(result.run_dir, 'audit.json'))
    assert File.exist?(File.join(result.run_dir, 'audit.txt'))
  ensure
    FileUtils.remove_entry(result.run_dir) if result&.run_dir && File.exist?(result.run_dir)
  end

  def test_sizing_mode_with_costing
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-sizing-')
    result = OpenStudioNECB.performance_compliance(
      proposed_with_hvac, vintage: '2020', simulate: :sizing, weather: weather,
      building: { storeys: 1, zone_types: zone_types_for(load_fixture), winter_design_temp_c: -20 },
      costing: true, run_dir: dir)

    assert_nil result.compliant
    %w[proposed reference].each do |label|
      cost = result.report[label]['cost']
      assert_operator cost['hvac'], :>, 0, "#{label} HVAC costed on sized model"
      assert_operator cost['envelope'], :>, 0, "#{label} envelope costed"
      assert_in_delta cost['hvac'] + cost['envelope'], cost['total'], 0.02
      assert_equal 'TORONTO', cost['city'], 'cost location resolved from the EPW site'
    end
    assert result.report.key?('incremental_cost_proposed_vs_reference')

    # ONE audit spans every domain of the pipeline
    steps = result.audit.entries.map { |e| e[:step] }.uniq
    %i[compliance selection build efficiency coverage prescriptive reference costing_envelope].each do |step|
      assert_includes steps, step
    end
    assert(result.audit.entries.any? { |e| e[:step].to_s.start_with?('costing_') && e[:level] == :decision })
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_annual_mode_week_run_full_determination
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-annual-')
    result = OpenStudioNECB.performance_compliance(
      proposed_with_hvac, vintage: '2020', simulate: :annual, weather: weather,
      building: { storeys: 1, zone_types: zone_types_for(load_fixture), winter_design_temp_c: -20 },
      run_dir: dir,
      run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 })

    %w[proposed reference].each do |label|
      section = result.report[label]
      assert section['clean_run'], "#{label} EnergyPlus run is clean"
      assert_operator section['total_site_kwh'], :>, 0, "#{label} consumed energy"
      assert_operator section['end_uses_kwh']['heating'], :>, 0, "#{label} heated in a Toronto January week"
      assert section['unmet_occupied_hours']['heating'], "#{label} unmet-hours read from SQL"
      assert_operator section['eui_kwh_per_m2'], :>, 0
    end

    refute_nil result.compliant, 'a determination was made'
    assert_empty result.report['capacity_iterations'],
                 'well-sized buildings need no 8.4.1.2.(5) capacity increases'
    assert_equal false, result.report['annual'], 'shortened run period flagged'
    assert(result.audit.warnings.any? { |w| w[:action].include?('SHORTENED') },
           'week-long run loudly flagged as not code-compliant')

    target = result.audit.entries.find { |e| e[:article] == '8.4.1.2.(2)' }
    refute_nil target, 'building-energy-target decision cited'
    assert target[:inputs][:reference_building_energy_target_kwh].positive?
    assert(result.audit.entries.any? { |e| e[:article] == '8.4.1.2.(3)' })
    assert(result.audit.entries.any? { |e| e[:article] == '8.4.1.2.(4)' })

    report = JSON.parse(File.read(File.join(dir, 'report.json')))
    assert_equal report['compliant'], result.compliant
    audit_json = JSON.parse(File.read(File.join(dir, 'audit.json')))
    assert_operator audit_json.size, :>, 80, 'the unified audit is substantial'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  # 8.4.1.2.(5): a deliberately UNDERSIZED proposed building (global heating
  # sizing factor 0.25 — the reference inherits it through the min(proposed, 1.3)
  # oversizing rule, so BOTH buildings fail sentence (3) initially) must converge
  # through audited capacity increases over a 4-week Toronto January run.
  def test_capacity_iteration_converges_undersized_building
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-iter-')
    proposed = proposed_with_hvac
    proposed.getSizingParameters.setHeatingSizingFactor(0.25)

    result = OpenStudioNECB.performance_compliance(
      proposed, vintage: '2020', simulate: :annual, weather: weather,
      building: { storeys: 1, zone_types: zone_types_for(proposed), winter_design_temp_c: -20 },
      run_dir: dir, max_capacity_iterations: 3, capacity_step: 3.0,
      run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 28 })

    history = result.report['capacity_iterations']
    refute_empty history, 'the undersized building required capacity increases'
    refute history.any? { |h| h['stalled'] }, 'autosized equipment responds to sizing factors'
    first = history.first
    assert first['bumped'].key?('proposed'), 'proposed heating capacity was increased'
    assert_operator first['bumped']['proposed']['heating_sizing_factor'], :>, 0.25

    final = result.report['proposed']['unmet_occupied_hours']['heating']
    assert_operator final, :<=, 100.0, "converged: #{final} unmet heating hours after iteration"
    ref_final = result.report['reference']['unmet_occupied_hours']['heating']
    assert_operator ref_final, :<=, 100.0, 'reference converged too'

    bump_decisions = result.audit.entries.select { |e| e[:article] == '8.4.1.2.(5)' && e[:level] == :decision }
    refute_empty bump_decisions, 'every capacity increase is an audited decision'
    assert(result.audit.entries.any? { |e| e[:action].include?('converged') })
    assert Dir.exist?(File.join(dir, 'proposed_annual_iter1')), 'iteration run evidence kept'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_caller_model_never_mutated
    model = proposed_with_hvac
    before = model.getSurfaces.map { |s| s.construction.get.nameString }.sort
    OpenStudioNECB.performance_compliance(
      model, vintage: '2020', simulate: :none, hdd: 3890,
      building: { storeys: 1, zone_types: zone_types_for(model), winter_design_temp_c: -20 },
      run_dir: Dir.mktmpdir('osnecb-mut-'))
    after = model.getSurfaces.map { |s| s.construction.get.nameString }.sort
    assert_equal before, after, 'the pipeline works on its own copy'
  end
end
