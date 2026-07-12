require_relative 'test_helper'
require 'tmpdir'

# Envelope + thermal-bridging costing: database resolution, interpolation
# semantics, per-surface costing, SHGC film, TB id-matching (legacy defect fixed),
# parapet allowance, and the unified compliance+costing audit.
class TestCosting < Minitest::Test
  include FixtureHelper

  CITY = 'TORONTO'.freeze
  PROVINCE = 'ONTARIO'.freeze

  def costed_model
    model = load_fixture
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890,
                                                audit: OpenStudioEnvelope::AuditLog.new)
    model
  end

  def test_database_loads_and_resolves_priced_tables
    db = OpenStudioEnvelope::Costing::Database.new
    refute_empty db.materials_opaque
    refute_empty db.materials_glazing
    refute_empty db.thermal_bridging
    refute_empty db.constructions
    # priced tables resolved from the sibling openstudio-hvac vendored copies
    record = db.cost_record('070026')
    assert_operator record['materialOpCost'] + record['laborOpCost'], :>, 0
    # vendored materials sheets are UNPRICED (reference columns blanked at vendoring)
    assert db.materials_opaque.all? { |r| r['material_cost'].to_s.strip.empty? }
    assert db.materials_glazing.all? { |r| r['material_cost'].to_s.strip.empty? }
  end

  def test_costs_csv_override
    db = OpenStudioEnvelope::Costing::Database.new
    base = db.cost_record('070026')
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'override.csv')
      File.write(path, "id,sheet,source,description,city,province_state,materialOpCost,laborOpCost,equipmentOpCost\n" \
                       "070026,materials_opaque,test,override,,,999.0,111.0,0.0\n")
      injected = OpenStudioEnvelope::Costing::Database.new(costs_csv: path)
      assert_in_delta 999.0, injected.cost_record('070026')['materialOpCost'], 1e-9
      refute_in_delta base['materialOpCost'], injected.cost_record('070026')['materialOpCost'], 1e-9
    end
  end

  def test_interpolate_semantics
    interp = OpenStudioEnvelope::Costing::Interpolate
    points = [[1.0, 10.0], [2.0, 20.0], [4.0, 30.0]]
    assert_in_delta 15.0, interp.interpolate(x_y_array: points, x2: 1.5).value, 1e-9
    assert_in_delta 25.0, interp.interpolate(x_y_array: points, x2: 3.0).value, 1e-9
    # below data but within clamp band -> linear extrapolation from first two points
    assert_in_delta 9.9, interp.interpolate(x_y_array: points, x2: 0.99).value, 1e-9
    # beyond the +2% clamp -> clamped bound + the honest flag (legacy adds $10^12 instead)
    high = interp.interpolate(x_y_array: points, x2: 5.0)
    assert high.upper_bound_exceeded
    assert_in_delta 30.6, high.value, 1e-9 # 1.02 x 30
    low = interp.interpolate(x_y_array: points, x2: 0.5)
    refute low.upper_bound_exceeded
    assert_in_delta 9.8, low.value, 1e-9 # 0.98 x 10
    assert_in_delta 7.0, interp.interpolate(x_y_array: [[3.0, 7.0]], x2: 99.0).value, 1e-9
  end

  def test_envelope_costing_covers_all_present_surface_types
    audit = OpenStudioEnvelope::AuditLog.new
    report = OpenStudioEnvelope.cost(costed_model, city: CITY, province_state: PROVINCE, audit: audit)

    assert_operator report.total, :>, 0
    types = report.envelope['surface_types']
    %w[exterior_wall exterior_roof ground_contact_floor].each do |type|
      assert_operator types[type]['cost'], :>, 0, "#{type} costed"
      assert_operator types[type]['area_m2'], :>, 0
      assert_in_delta types[type]['cost'] / types[type]['area_m2'], types[type]['cost_per_m2'], 0.01
    end
    assert_in_delta 273.6, types['exterior_wall']['area_m2'], 1.0
    assert_in_delta 800.0, types['exterior_roof']['area_m2'], 1.0

    total_from_types = types.values.sum { |v| v['cost'] }
    assert_in_delta report.envelope['total_envelope_cost'], total_from_types, 0.5

    decision = audit.entries.find { |e| e[:step] == :costing_envelope && e[:action].include?('cost-curve interpolation') }
    refute_nil decision
    assert_equal 0, report.warnings.count { |w| w.include?('regional adjustment') },
                 'canonical TORONTO/ONTARIO resolves every prefix'
  end

  def test_glazing_film_cost_applies_to_windows
    model = costed_model
    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    wall.setWindowToWallRatio(0.4)
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890,
                                                audit: OpenStudioEnvelope::AuditLog.new)
    report = OpenStudioEnvelope.cost(model, city: CITY, province_state: PROVINCE)

    window = report.envelope['surface_types']['exterior_fixed_window']
    assert_operator window['cost'], :>, 0, 'windows costed (assembly curve + SHGC film premium)'
    row = report.envelope['construction_costs'].find { |r| r['surface_type'] == 'ExteriorFixedWindow' }
    assert_equal 'BTAP-ExteriorWindow-FixedWindow-1', row['assembly_name']
  end

  def test_zone_multiplier_scales_cost
    base_model = costed_model
    base = OpenStudioEnvelope.cost(base_model, city: CITY, province_state: PROVINCE)

    scaled_model = costed_model
    scaled_model.getThermalZones.each { |z| z.setMultiplier(3) }
    scaled = OpenStudioEnvelope.cost(scaled_model, city: CITY, province_state: PROVINCE)
    assert_in_delta base.total * 3.0, scaled.total, base.total * 0.01
  end

  def test_thermal_bridging_costed_by_material_id_not_first_row
    tallies = { 'parapet' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 100.0 },
                'jamb' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 50.0 },
                'transition' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 500.0 },
                'ceiling' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 500.0 } }
    audit = OpenStudioEnvelope::AuditLog.new
    report = OpenStudioEnvelope.cost(costed_model, city: CITY, province_state: PROVINCE,
                                     tb_tallies: tallies, audit: audit)

    tb = report.thermal_bridging
    assert_operator tb['total_thermal_bridging_cost'], :>, 0
    descriptions = tb['by_material'].map { |m| m['description'] }
    refute descriptions.all? { |d| d.include?('gypsum wallboard') },
           'legacy defect: every edge priced as materials_opaque row 1 (gypsum); the port matches BY id'
    ids = tb['by_material'].map { |m| m['materials_opaque_id'] }
    assert_equal ids.uniq, ids
    decision = audit.entries.find { |e| e[:step] == :costing_thermal_bridging && e[:level] == :decision }
    assert_match(/matched BY ID/, decision[:action])
    assert_match(/gypsum/, decision[:evidence])

    # parapet allowance rides on the envelope side (length x wall $/m2)
    assert_operator report.envelope['parapet_cost'], :>, 0
    wall = report.envelope['surface_types']['exterior_wall']
    assert_in_delta 100.0 * wall['cost_per_m2'], report.envelope['parapet_cost'], 1.0
  end

  def test_unknown_wall_reference_and_id_zero_warn_never_silent
    tallies = { 'corner' => { 'No-Such-Assembly good' => 10.0 } }
    audit = OpenStudioEnvelope::AuditLog.new
    OpenStudioEnvelope.cost(costed_model, city: CITY, province_state: PROVINCE,
                            tb_tallies: tallies, audit: audit)
    assert(audit.warnings.any? { |w| w[:action].include?("wall reference 'No-Such-Assembly good'") })

    # corner rows for SteelFramed-1 reference material id '0' (no materials_opaque row)
    tallies2 = { 'corner' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 10.0 } }
    audit2 = OpenStudioEnvelope::AuditLog.new
    OpenStudioEnvelope.cost(costed_model, city: CITY, province_state: PROVINCE,
                            tb_tallies: tallies2, audit: audit2)
    assert(audit2.warnings.any? { |w| w[:action].include?("material id '0'") },
           "id '0' rows are skipped LOUDLY")
  end

  def test_tallies_from_tbd_result
    tbd_result = { io: { edges: [
      { type: :parapetconvex, length: 12.0 },
      { type: :cornerconcave, length: 4.0 },
      { type: :jamb, length: 2.0 },
      { type: :transition, length: 9.0 }
    ] } }
    tallies = OpenStudioEnvelope::Costing::ThermalBridgingCosts.tallies_from_tbd(
      tbd_result, 'BTAP-ExteriorWall-SteelFramed-1 good')
    assert_in_delta 12.0, tallies['parapet']['BTAP-ExteriorWall-SteelFramed-1 good'], 1e-9
    assert_in_delta 4.0, tallies['corner']['BTAP-ExteriorWall-SteelFramed-1 good'], 1e-9
    assert tallies.key?('transition'), 'kept in tallies; skipped at costing time'
  end

  def test_unified_audit_spans_compliance_and_costing
    model = load_fixture
    audit = OpenStudioEnvelope::AuditLog.new
    OpenStudioEnvelope::NECB.reference_envelope(model, vintage: '2020', hdd: 3890, audit: audit)
    OpenStudioEnvelope.cost(model, city: CITY, province_state: PROVINCE,
                            tb_tallies: { 'parapet' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 10.0 } },
                            audit: audit)
    steps = audit.entries.map { |e| e[:step] }.uniq
    %i[prescriptive reference coverage costing_envelope costing_thermal_bridging].each do |step|
      assert_includes steps, step, 'ONE audit spans reference generation + costing'
    end
    assert JSON.parse(audit.to_json).size > 30
  end
end
