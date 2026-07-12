require_relative 'test_helper'

# P3b gate: NECB 3.1.1.7 effective transmittance via TBD — assemblies are uprated so
# the derated Ut meets the table targets; unavailability/omission is loud, never silent.
class TestThermalBridging < Minitest::Test
  include FixtureHelper

  HDD = 3890

  def tbd_available?
    OpenStudioEnvelope::NECB::ThermalBridging.available?
  end

  def test_not_requested_warns
    model = load_fixture
    audit = OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: HDD)
    warning = audit.warnings.find { |w| w[:action].include?('thermal bridging not requested') }
    refute_nil warning
    assert_equal '3.1.1.7.', warning[:article]
  end

  def test_unavailable_is_loud
    ENV['OPENSTUDIO_ENVELOPE_DISABLE_TBD'] = '1'
    audit = OpenStudioEnvelope::AuditLog.new
    result = OpenStudioEnvelope::NECB::ThermalBridging.apply(load_fixture, vintage: '2020', hdd: HDD, audit: audit)
    assert_equal false, result
    assert audit.warnings.any? { |w| w[:action].include?("NOT accounted") && w[:article] == '3.1.1.7.' }
  ensure
    ENV.delete('OPENSTUDIO_ENVELOPE_DISABLE_TBD')
  end

  def test_uprate_derate_meets_effective_targets
    skip 'tbd gem not available (run under the repo bundle)' unless tbd_available?

    model = load_fixture
    audit = OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: HDD,
                                                        thermal_bridging: 'efficient (BETBG)',
                                                        audit: OpenStudioEnvelope::AuditLog.new)

    decision = audit.entries.find { |e| e[:step] == :thermal_bridging && e[:level] == :decision }
    refute_nil decision, 'TBD uprate/derate decision logged'
    assert_operator decision[:inputs][:surfaces_derated], :>, 0
    assert_match(/Σψ/, decision[:article])

    # ROOFS: uprating succeeds — the derated effective U lands at/below the target
    roof = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'RoofCeiling' }
    roof_u = roof.construction.get.to_Construction.get.thermalConductance.to_f
    assert_operator roof_u, :<=, 0.156 + 1e-3,
                    "derated roof U (#{roof_u.round(4)}) meets the effective target 0.156"

    # WALLS: this fixture's tiny walls have edge losses alone above the target —
    # physically infeasible — and TBD's refusal must be LOUD in the audit
    infeasible = audit.warnings.find { |w| w[:action].include?('Unable to uprate') }
    refute_nil infeasible, 'infeasible uprate must surface as an audit warning'

    per_surface = audit.entries.select { |e| e[:action].include?('surface derated') }
    refute_empty per_surface, 'per-surface derating evidence in the audit'
  end

  def test_coverage_manifest_reflects_tbd_status
    %w[2020 2025].each do |v|
      art = OpenStudioEnvelope::NECB.rules(v)['article_coverage']['articles']
                                    .find { |a| a['article'] == '3.1.1.7.' }
      assert_equal 'implemented', art['status']
      assert_match(/tbd gem/, art['gaps'])
    end
  end
end
