require_relative 'test_helper'

# Costing on a GENERAL OSM: systems: is optional. Loops are classified automatically —
# exactly for recognizable names, structurally for foreign models — so any OSM gets
# full ventilation/distribution costing, not just plant/zonal.
class TestCostingForeign < Minitest::Test
  include FixtureHelper

  def sized_vav_model
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    result.air_loops.each { |al| al.setDesignSupplyAirFlowRate(2.0) }
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(60_000.0) }
    model.getChillerElectricEIRs.each { |c| c.setReferenceCapacity(100_000.0) }
    (model.getPumpConstantSpeeds + model.getPumpVariableSpeeds).each { |p| p.setRatedPowerConsumption(1000.0) }
    model.getCoilHeatingWaterBaseboards.each { |c| c.setHeatingDesignCapacity(4_000.0) }
    model.getAirTerminalSingleDuctVAVReheats.each { |t| t.setMaximumAirFlowRate(0.4) }
    [model, result]
  end

  def item_signature(report)
    report.items.map { |i| [i['id'], i['quantity'].round(4)] }.sort
  end

  # systems: omitted on a gem-built model -> identical costing (names recognized exactly)
  def test_cost_without_systems_matches_cost_with_systems
    model, result = sized_vav_model
    with = OpenStudioHVAC.cost(model, systems: [result], city: 'TORONTO', province_state: 'ONTARIO')
    without = OpenStudioHVAC.cost(model, city: 'TORONTO', province_state: 'ONTARIO')

    assert_equal item_signature(with), item_signature(without)
    assert_in_delta with.total, without.total, 0.01
    assert_empty without.warnings.select { |w| w.include?('guessed structurally') },
                 'recognized names need no structural guess'
  end

  # fully foreign loop names -> structural classification, same AHU class, loud about it
  def test_foreign_osm_costed_via_structural_classification
    model, result = sized_vav_model
    with = OpenStudioHVAC.cost(model, systems: [result], city: 'TORONTO', province_state: 'ONTARIO')

    model.getAirLoopHVACs.each_with_index { |al, i| al.setName("Imported AHU #{i + 1}") }
    foreign = OpenStudioHVAC.cost(model, city: 'TORONTO', province_state: 'ONTARIO')

    assert_in_delta with.total, foreign.total, 0.01, 'structural guess lands the same sys6 assembly class'
    assert foreign.warnings.any? { |w| w.include?("guessed structurally") && w.include?('vav_reheat') }
    assert_empty foreign.warnings.select { |w| w.include?('was not built by this gem') },
                 'foreign loop is costed, not skipped'
  end

  # legacy NECB pipe-named loops (openstudio-standards output) -> exact family mapping
  def test_legacy_pipe_named_osm_costed
    model, result = sized_vav_model
    with = OpenStudioHVAC.cost(model, systems: [result], city: 'TORONTO', province_state: 'ONTARIO')

    model.getAirLoopHVACs.each do |al|
      al.setName('sys_6|mixed|shr>none|sh>c-hw|sc>c-chw|ssf>vv|zh>b-hw|zc>none|srf>vv|')
    end
    legacy = OpenStudioHVAC.cost(model, city: 'TORONTO', province_state: 'ONTARIO')

    assert_in_delta with.total, legacy.total, 0.01
    assert_empty legacy.warnings.select { |w| w.include?('guessed structurally') },
                 'pipe names map exactly, no guess needed'
  end

  # the costing audit log: classification, selection math, per-item decisions,
  # geometry evidence and mirrored warnings — same contract as reference generation
  def test_costing_audit_log
    model, = sized_vav_model
    model.getAirLoopHVACs.each_with_index { |al, i| al.setName("Imported AHU #{i + 1}") }
    report = OpenStudioHVAC.cost(model, city: 'TORONTO', province_state: 'ONTARIO')

    audit = report.audit
    refute_nil audit
    steps = audit.entries.map { |e| e[:step] }.uniq
    assert_includes steps, :costing_classification, 'classification decisions logged'
    assert_includes steps, :costing_equipment, 'plant/zonal item decisions logged'
    assert_includes steps, :costing_ventilation, 'ventilation item decisions logged'
    assert_includes steps, :costing_geometry, 'geometry evidence logged'

    guess = audit.entries.find { |e| e[:action].include?('guessed structurally') }
    assert_equal 'vav_reheat', guess[:value]

    ahu = audit.entries.find { |e| e[:action].include?('AHU assembly selected') }
    assert ahu[:inputs][:bucket_lps].positive?
    assert_match(/scaled to/, ahu[:value])

    # every warning string is mirrored into the audit
    report.warnings.each do |w|
      assert audit.warnings.any? { |e| e[:action] == w }, "warning not mirrored: #{w}"
    end
    assert JSON.parse(audit.to_json).size.positive?
  end

  # ONE audit for compliance + costing: thread a single AuditLog through
  # reference_hvac and cost and get one chronological narrative.
  def test_unified_audit_across_reference_and_costing
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }

    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, building: { storeys: 1, zone_types: types, winter_design_temp_c: -20 }, audit: audit
    )
    ref = result.model
    ref.getBoilerHotWaters.each { |b| b.setNominalCapacity(60_000.0) }
    ref.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(15_000.0) }
    report = OpenStudioHVAC.cost(ref, city: 'TORONTO', province_state: 'ONTARIO', audit: audit)

    assert report.audit.equal?(result.audit), 'one AuditLog object end to end'
    steps = audit.entries.map { |e| e[:step] }.uniq
    # compliance narrative first, costing narrative after — one chronological log
    %i[characterize selection build rules efficiency coverage costing_equipment costing].each do |step|
      assert_includes steps, step
    end
    assert_operator steps.index(:coverage), :<, steps.index(:costing_equipment),
                    'reference generation precedes costing in the same log'
    assert JSON.parse(audit.to_json).size > 50
  end
end
