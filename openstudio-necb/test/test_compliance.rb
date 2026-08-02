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

  # A run that aborts mid-pipeline must still flush its audit trail to run_dir
  # (a broken proposed dies before the reference is even built). The missing
  # weather[:ddy] raises the existing ArgumentError at the weather guard, which
  # now sits inside the diagnostics-capturing begin.
  def test_failed_run_still_writes_audit_trail
    dir = Dir.mktmpdir('osnecb-fail-')
    error = assert_raises(ArgumentError) do
      OpenStudioNECB.performance_compliance(
        proposed_with_hvac, vintage: '2020', simulate: :annual,
        weather: { epw: EPW }, # deliberately missing :ddy
        building: { storeys: 1, zone_types: zone_types_for(load_fixture), winter_design_temp_c: -20 },
        run_dir: dir)
    end
    assert_match(/ddy/, error.message, 'original error propagates unchanged')

    assert File.exist?(File.join(dir, 'audit.txt')), 'audit.txt written despite the failure'
    assert File.exist?(File.join(dir, 'audit.json')), 'audit.json written despite the failure'
    assert File.exist?(File.join(dir, 'report.json')), 'partial report.json written'
    audit_txt = File.read(File.join(dir, 'audit.txt'))
    assert_includes audit_txt, 'ABORTED', 'the abort is recorded in the audit trail'
    assert_includes audit_txt, 'performance-path run started',
                    'the pre-failure narrative is preserved for debugging'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  # Pre-flight gate (defect #1): a space type that does not resolve against the
  # NECB catalog must abort the run BEFORE any transform — an unresolvable type
  # silently keeps the proposed's lighting/loads in the reference (the clone),
  # waiving the allowance. The refusal must be actionable (nearest catalog
  # names) and must still flush the audit trail.
  def test_preflight_rejects_unresolvable_space_type_with_suggestions
    dir = Dir.mktmpdir('osnecb-preflight-')
    model = proposed_with_hvac
    model.getSpaceTypes.select { |st| st.spaces.any? }.each do |st|
      st.setStandardsSpaceType('Office - enclosed') # legacy name, NOT in the catalog
    end
    error = assert_raises(ArgumentError) do
      OpenStudioNECB.performance_compliance(
        model, vintage: '2020', simulate: :none, hdd: 3890,
        building: { storeys: 1, zone_types: zone_types_for(load_fixture), winter_design_temp_c: -20 },
        run_dir: dir)
    end
    assert_includes error.message, 'pre-flight FAILED'
    assert_includes error.message, 'Office - enclosed', 'names the offending type'
    assert_includes error.message, 'Office enclosed > 25 m2', 'suggests the nearest real catalog names'
    audit_txt = File.read(File.join(dir, 'audit.txt'))
    assert_includes audit_txt, 'UNRESOLVABLE', 'refusal recorded in the flushed audit trail'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
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
    assert(result.audit.entries.any? { |e| e[:article] == '8.4.3.2.(1)-(2)' },
           '8.4.3.2 loads-identity satisfied-by-clone note in the audit')
    assert(result.audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.5.') && e[:building] == 'reference building' },
           'reference_lighting Part 4 allowance cited, stamped reference building')
    assert(result.audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.20.') && e[:building] == 'reference building' },
           'reference_shw Part 6 efficiencies cited, stamped reference building')
    # D-51: reference daylighting is ON by default, so the pipeline builds the
    # 8.4.4.5.(9)-(12) photocontrols and reference_lighting must NOT claim
    # (5)-(12) are unmodeled (that warning is now conditional on the transform
    # having been skipped).
    d51 = result.audit.entries.find do |e|
      e[:step] == :compliance && e[:ruling].to_s.include?('D-51') && e[:building] == 'reference building'
    end
    refute_nil d51, 'reference daylighting ran by default, cited as D-51 and stamped reference building'
    assert_equal :decision, d51[:level], 'daylighting ON is a decision, not a warning'
    assert_includes d51[:article].to_s, '8.4.4.5.(9)-(12)'
    refute(result.audit.warnings.any? do |w|
             w[:step] == :lighting_reference && w[:article].to_s.include?('8.4.4.5.(5)-(12)')
           end,
           'the "(5)-(12) NOT modeled" warning is silenced when reference_daylighting ran')
    # the transform really ran (whether it PLACES controls depends on the 4.2.2
    # threshold selection, which excepts this fixture's spaces — see D-51)
    assert(result.audit.entries.any? { |e| e[:step] == :daylighting && e[:building] == 'reference building' },
           'the reference daylighting transform ran and audited itself')

    # The umbrella's OWN manifest is emitted at runtime (D-09): real pipeline
    # limitations warn; gap_owner "modeller" entries are info scope notes.
    umbrella_coverage = result.audit.entries.select { |e| e[:step] == :coverage }
    calc = umbrella_coverage.find { |e| e[:article] == '8.4.2.2.' }
    refute_nil calc, 'umbrella 8.4.2.2 Calculation Methods coverage emitted'
    assert_equal :warning, calc[:level], '8.4.2.2 has a real pipeline limitation (elevators) — warns'
    climate = umbrella_coverage.find { |e| e[:article] == '8.4.2.3.' }
    refute_nil climate, 'umbrella 8.4.2.3 Climatic Data coverage emitted'
    assert_equal :info, climate[:level], 'modeller-scope gap is a scope note, NOT a warning'
    assert_equal 'modeller', climate[:inputs][:gap_owner]
    assert_includes climate[:action], 'modeller scope'
    determination = umbrella_coverage.find { |e| e[:article] == '8.4.1.2.' }
    assert_equal :info, determination&.dig(:level), 'umbrella 8.4.1.2 implemented — info'

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

    # D-44: ruled code paths name the decision that governs them, in the
    # persisted audit and in the human-readable narrative. D-14 (reference air
    # systems inherit the proposed operating schedule) fires on every run that
    # builds a reference air system.
    rulings = audit_json.filter_map { |e| e['ruling'] }
    refute_empty rulings, 'ruling tags reach audit.json'
    assert_includes rulings.flat_map { |r| OpenStudioNECB::Decisions.ids_in(r) }.uniq, 'D-14',
                    'D-14 (operating-schedule inheritance) fired and was tagged'
    rulings.flat_map { |r| OpenStudioNECB::Decisions.ids_in(r) }.uniq.each do |id|
      refute_nil OpenStudioNECB::Decisions.lookup(id), "audited ruling #{id} resolves in the registry"
    end
    assert_match(/\| ruling D-\d{2}/, File.read(File.join(dir, 'audit.txt')),
                 'audit.txt narrative carries the ruling segment')
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  # D-52: an HP proposed drives the 8.4.4.13.(2)(g) machinery end to end —
  # the proposed annual runs BEFORE the reference build, the per-equipment
  # heating energy is extracted from its SQL, and the election (or its audited
  # fallback) decides the reference hp variant's aux fuel.
  def test_hp_proposed_runs_the_2g_election_machinery
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-hp-election-')
    result = OpenStudioNECB.performance_compliance(
      proposed_with_hvac('PSZ RTU ASHP with Gas and ASHP with Gas Supp. Heat Coils and Electric Baseboard'),
      vintage: '2020', simulate: :annual, weather: weather,
      building: { storeys: 1, zone_types: zone_types_for(load_fixture), winter_design_temp_c: -20 },
      run_dir: dir,
      run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 })

    extraction = result.audit.entries.find { |e| e[:action].include?('per-equipment heating energy extracted') }
    refute_nil extraction, 'the election data was extracted from the proposed annual SQL'
    assert_operator extraction[:inputs][:heat_pump_gj], :>=, 0.0
    assert_operator extraction[:inputs][:air_loops], :>=, 1, 'the ASHP loop was inventoried'

    election = result.audit.entries.select { |e| e[:article].to_s.include?('8.4.4.13.(2)(g)') }
    refute_empty election, 'a (2)(g) determination fired — elected or audited fallback'
    assert(election.all? { |e| e[:ruling].to_s.include?('D-52') })
    # Whatever path elected, the reference hp system was actually built with a
    # concrete variant (the fixture ASHP redirects per Table 8.4.4.13).
    assert(result.audit.entries.any? { |e| e[:action].include?('air-source heat pump (Table 8.4.4.13)') })
    assert result.report['proposed']['clean_run'], 'proposed ran clean with the requested output variables'
    assert result.report['reference']['clean_run']
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  # 8.4.1.2.(5) unit mechanics (no EnergyPlus): the secant step extrapolates the
  # next sizing factor from a zone's own (factor, unmet-hours) history, clamped
  # to stay incremental; without a usable slope it falls back to the geometric
  # step.
  def test_next_sizing_factor_secant_and_fallback
    call = ->(history, f, h, target, step) do
      OpenStudioNECB::Compliance.send(:next_sizing_factor, history, f, h, target, step)
    end

    # First bump: no history -> geometric step.
    assert_in_delta 1.25, call.call([], 1.0, 400.0, 90.0, 1.25), 1e-9

    # Two observations with a real slope -> secant lands the hours on target:
    # (1.0, 400 h) then (3.0, 150 h); slope -125 h/factor; target 90 h -> 3.48.
    assert_in_delta 3.48, call.call([[1.0, 400.0]], 3.0, 150.0, 90.0, 1.25), 1e-6

    # A wild extrapolation is clamped to max(step, 2.0)x the current factor.
    clamped = call.call([[1.0, 400.0]], 1.1, 399.0, 90.0, 1.25)
    assert_in_delta 1.1 * 2.0, clamped, 1e-9, 'per-round growth capped'
    clamped_step = call.call([[1.0, 400.0]], 1.1, 399.0, 90.0, 3.0)
    assert_in_delta 1.1 * 3.0, clamped_step, 1e-9, 'cap never undercuts the configured step'

    # Perverse slope (hours went UP as the factor rose) -> geometric fallback.
    assert_in_delta 2.0 * 1.25, call.call([[1.0, 100.0]], 2.0, 300.0, 90.0, 1.25), 1e-9

    # Flat history (no >= 1 h difference) cannot support a slope -> fallback.
    assert_in_delta 2.0 * 1.25, call.call([[1.0, 300.4]], 2.0, 300.0, 90.0, 1.25), 1e-9
  end

  # 8.4.1.2.(5) targeting (no EnergyPlus): with per-zone unmet hours available,
  # only the failing thermal blocks get Sizing:Zone factor bumps; without them
  # the bump falls back to the global SizingParameters; a gate no single zone
  # explains gets the global fallback ALONGSIDE the zonal bumps (mixed).
  def test_bump_capacities_targets_failing_zones
    model = OpenStudio::Model::Model.new
    z_bad = OpenStudio::Model::ThermalZone.new(model)
    z_bad.setName('Zone Bad')
    z_ok = OpenStudio::Model::ThermalZone.new(model)
    z_ok.setName('Zone Ok')

    report = {
      'proposed' => { 'zone_unmet_occupied_hours' => {
        'ZONE BAD' => { 'heating' => 400.0, 'cooling' => 300.0 },
        'ZONE OK' => { 'heating' => 50.0, 'cooling' => 100.0 }
      } },
      'reference' => { 'zone_unmet_occupied_hours' => {
        'ZONE BAD' => { 'heating' => 10.0, 'cooling' => 100.0 },
        'ZONE OK' => { 'heating' => 10.0, 'cooling' => 100.0 }
      } }
    }
    global_heating = model.getSizingParameters.heatingSizingFactor
    global_cooling = model.getSizingParameters.coolingSizingFactor
    trace = {}
    factors = OpenStudioNECB::Compliance.send(
      :bump_capacities, model, 'proposed', report,
      { heating: true, cooling: true }, '2020', step: 1.4, trace: trace)

    assert_equal 'zonal', factors['mode']
    assert_equal ['ZONE BAD'], factors['zones'].keys,
                 'only the failing thermal block is bumped (heating > 100 h; cooling > reference +10%)'
    sz_bad = z_bad.sizingZone
    assert sz_bad.zoneHeatingSizingFactor.is_initialized, 'failing zone got a heating factor'
    assert_in_delta global_heating * 1.4, sz_bad.zoneHeatingSizingFactor.get, 1e-6,
                    'first bump = the effective (global) factor x step'
    assert sz_bad.zoneCoolingSizingFactor.is_initialized, 'failing zone got a cooling factor'
    assert_in_delta global_cooling * 1.4, sz_bad.zoneCoolingSizingFactor.get, 1e-6
    refute z_ok.sizingZone.zoneHeatingSizingFactor.is_initialized, 'passing zone untouched'
    refute z_ok.sizingZone.zoneCoolingSizingFactor.is_initialized
    assert_in_delta global_heating, model.getSizingParameters.heatingSizingFactor, 1e-6, 'global factor untouched'
    assert_equal [['proposed', 'ZONE BAD', :heating]], trace.keys.select { |k| k[2] == :heating },
                 'history recorded per zone/metric for the next round secant'

    # No per-zone data at all -> global fallback, flagged as such.
    bare = OpenStudio::Model::Model.new
    OpenStudio::Model::ThermalZone.new(bare)
    bare_global = bare.getSizingParameters.heatingSizingFactor
    factors = OpenStudioNECB::Compliance.send(
      :bump_capacities, bare, 'proposed',
      { 'proposed' => {}, 'reference' => {} },
      { heating: true, cooling: false }, '2020', step: 1.4, trace: {})
    assert_equal 'global', factors['mode']
    assert_in_delta bare_global * 1.4, bare.getSizingParameters.heatingSizingFactor, 1e-6

    # Heating attributable to a zone, cooling gate failing with NO zone over its
    # per-zone allowance (facility union) -> mixed: zonal heating + global cooling.
    mixed_model = OpenStudio::Model::Model.new
    mz = OpenStudio::Model::ThermalZone.new(mixed_model)
    mz.setName('Zone Bad')
    mixed_report = {
      'proposed' => { 'zone_unmet_occupied_hours' => {
        'ZONE BAD' => { 'heating' => 400.0, 'cooling' => 105.0 }
      } },
      'reference' => { 'zone_unmet_occupied_hours' => {
        'ZONE BAD' => { 'heating' => 10.0, 'cooling' => 100.0 }
      } }
    }
    mixed_gc = mixed_model.getSizingParameters.coolingSizingFactor
    mixed_gh = mixed_model.getSizingParameters.heatingSizingFactor
    factors = OpenStudioNECB::Compliance.send(
      :bump_capacities, mixed_model, 'proposed', mixed_report,
      { heating: true, cooling: true }, '2020', step: 1.4, trace: {})
    assert_equal 'mixed', factors['mode']
    assert factors['zones'].key?('ZONE BAD')
    assert_in_delta mixed_gc * 1.4, factors['global']['cooling_sizing_factor'], 1e-3
    assert_in_delta mixed_gc * 1.4, mixed_model.getSizingParameters.coolingSizingFactor, 1e-6
    assert_in_delta mixed_gh, mixed_model.getSizingParameters.heatingSizingFactor, 1e-6,
                    'heating stays zonal — global heating untouched'
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
    assert_equal 'zonal', first['bumped']['proposed']['mode'],
                 'per-zone unmet hours attributed the failure to specific thermal blocks'
    refute_empty first['bumped']['proposed']['zones'], 'the failing zones are named in the history'
    assert(result.proposed_model.getThermalZones.any? { |z| z.sizingZone.zoneHeatingSizingFactor.is_initialized },
           'Sizing:Zone heating factors set on the failing zones of the model')

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

  # The bare-geometry on-ramp: strip the fixture of loads AND HVAC, hand the
  # pipeline only geometry + a space-type map, and get a full compliance run.
  def test_bare_geometry_on_ramp
    skip 'openstudio CLI not available' unless openstudio_cli?
    bare = load_fixture
    bare.getThermostatSetpointDualSetpoints.each(&:remove)
    bare.getPeoples.each(&:remove)
    bare.getPeopleDefinitions.each(&:remove)
    bare.getLightss.each(&:remove)
    bare.getLightsDefinitions.each(&:remove)
    bare.getElectricEquipments.each(&:remove)
    bare.getElectricEquipmentDefinitions.each(&:remove)
    bare.getSpaceTypes.each(&:remove)

    map = bare.getSpaces.to_h { |s| [s.nameString, ['Space Function', 'Office enclosed > 25 m2']] }
    dir = Dir.mktmpdir('osnecb-onramp-')
    result = OpenStudioNECB.performance_compliance(
      bare, vintage: '2020', simulate: :sizing, weather: weather,
      building: { storeys: 1, zone_types: zone_types_for(bare), winter_design_temp_c: -20 },
      necb_loads: { space_type_map: map, shw_fuel: 'NaturalGas', hvac_system: 'Baseboard gas boiler' },
      run_dir: dir)

    refute_empty result.proposed_model.getPeoples.to_a, 'loads applied'
    refute_empty result.proposed_model.getLightss.to_a, 'lighting applied'
    refute_empty result.proposed_model.getWaterUseEquipments.to_a, 'SHW applied'
    refute_empty result.proposed_model.getPlantLoops.to_a, 'HVAC built'
    steps = result.audit.entries.map { |e| e[:step] }.uniq
    %i[loads lighting shw selection].each { |s| assert_includes steps, s, 'on-ramp steps in ONE audit' }
    wall = result.reference_model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    assert_match(/Lightweight/, wall.construction.get.nameString, 'reference generated from the on-ramped proposed')
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
