require_relative 'test_helper'

# P2 gate (standalone half): lookup semantics — legacy-exact bin scan, piecewise FDWR,
# SRR, HDD resolution from explicit/table-C1/.stat sources.
class TestLookups < Minitest::Test
  include FixtureHelper

  # "first value where hdd < bin ceiling" — spot values from NECB 2020 Table 3.2.2.2
  def test_max_u_bin_semantics
    n = OpenStudioEnvelope::NECB
    assert_in_delta 0.290, n.max_u(vintage: '2020', surface: 'wall', boundary: 'outdoors', hdd: 2999), 1e-9
    assert_in_delta 0.265, n.max_u(vintage: '2020', surface: 'wall', boundary: 'outdoors', hdd: 3000), 1e-9, 'hdd == bin ceiling falls to the NEXT bin (strict <)'
    assert_in_delta 0.215, n.max_u(vintage: '2020', surface: 'wall', boundary: 'outdoors', hdd: 5000), 1e-9
    assert_in_delta 0.165, n.max_u(vintage: '2020', surface: 'wall', boundary: 'outdoors', hdd: 7000), 1e-9
    # beyond the last bin: legacy fallback 0.110
    assert_in_delta 0.110, n.max_u(vintage: '2020', surface: 'wall', boundary: 'outdoors', hdd: 9999), 1e-9
    # ground + fenestration
    assert_in_delta 0.379, n.max_u(vintage: '2020', surface: 'floor', boundary: 'ground', hdd: 7500), 1e-9
    assert_in_delta 1.90, n.max_u(vintage: '2020', surface: 'window', boundary: 'outdoors', hdd: 3500), 1e-9
    assert_raises(ArgumentError) { n.max_u(vintage: '2020', surface: 'porthole', boundary: 'outdoors', hdd: 1) }
    assert_raises(ArgumentError) { n.max_u(vintage: '2020', surface: 'window', boundary: 'ground', hdd: 1) }
  end

  # 3.2.1.4.(1): 0.40 / linear / 0.20 with continuity at the boundaries
  def test_max_fdwr_piecewise
    n = OpenStudioEnvelope::NECB
    assert_in_delta 0.4, n.max_fdwr(vintage: '2020', hdd: 3999), 1e-9
    assert_in_delta 0.4, n.max_fdwr(vintage: '2020', hdd: 4000), 1e-9, 'continuous at 4000'
    assert_in_delta (2000 - 0.2 * 5000) / 3000.0, n.max_fdwr(vintage: '2020', hdd: 5000), 1e-9
    assert_in_delta 0.2, n.max_fdwr(vintage: '2020', hdd: 7000), 1e-9
    assert_in_delta 0.2, n.max_fdwr(vintage: '2020', hdd: 12_000), 1e-9
  end

  def test_max_srr
    assert_in_delta 0.02, OpenStudioEnvelope::NECB.max_srr(vintage: '2020'), 1e-9
    assert_in_delta 0.02, OpenStudioEnvelope::NECB.max_srr(vintage: '2025'), 1e-9
  end

  def test_hdd_explicit_wins
    audit = OpenStudioEnvelope::AuditLog.new
    assert_equal 4321, OpenStudioEnvelope::Climate.hdd18(load_fixture, hdd: 4321, audit: audit)
    assert audit.entries.any? { |e| e[:action].include?('explicitly') }
  end

  def test_hdd_from_table_c1_for_toronto
    model = attach_weather!(load_fixture)
    audit = OpenStudioEnvelope::AuditLog.new
    hdd = OpenStudioEnvelope::Climate.hdd18(model, audit: audit)
    decision = audit.entries.find { |e| e[:action].include?('Table C-1') }
    refute_nil decision, 'Toronto is well within the 500 km tolerance'
    # the EPW is Toronto Intl AP = Pearson, whose Table C-1 row is Mississauga
    assert_match(/Toronto|Mississauga|Pearson/i, decision[:inputs][:city])
    assert_operator hdd, :>, 3000
    assert_operator hdd, :<, 4500
  end

  def test_hdd_from_stat_file
    hdd = OpenStudioEnvelope::Climate.stat_hdd18(FixtureHelper::EPW, nil)
    assert_equal 3579, hdd, 'annual (wthr file) heating degree-days, 18 C baseline'
  end

  def test_hdd_unresolvable_warns
    audit = OpenStudioEnvelope::AuditLog.new
    assert_nil OpenStudioEnvelope::Climate.hdd18(load_fixture, audit: audit)
    assert audit.warnings.any? { |w| w[:action].include?('no weather file') }
  end
end
