require_relative 'test_helper'

# The consolidated canonical naming grammar: <primary>[ + <zone equipment>][ (<plant>)],
# GENERATED from each row's structured config, resolvable alongside the legacy names.
class TestCanonical < Minitest::Test
  include FixtureHelper

  def test_all_canonical_names_unique_and_disjoint_from_legacy
    rows = OpenStudioHVAC::Catalog.rows
    canon = rows.map { |r| OpenStudioHVAC::Canonical.name(r) }
    assert_equal rows.size, canon.uniq.size,
                 "canonical collisions: #{canon.tally.select { |_, c| c > 1 }.keys}"
    legacy = rows.map { |r| r['name'] }
    assert_empty(canon & legacy, 'canonical names must not shadow legacy names')
  end

  def test_consolidation_examples
    # the user's example pair: CBECS fuel-first vs NECB medium-first now share one grammar
    assert_equal 'hot water baseboards (gas boiler)',
                 canonical_for('Baseboard gas boiler')
    assert_equal 'packaged single-zone DX with gas heat + hot water baseboards (gas boiler)',
                 canonical_for('PSZ RTU Gas and DX Coils and Hot Water Baseboard')
    assert_equal 'DOAS ASHP + zone PTHPs', canonical_for('hs11_ashp_pthp')
    assert_equal 'electric baseboards', canonical_for('Baseboard electric')
  end

  def test_composites_derive_from_parts
    canon = canonical_for('DOAS with fan coil chiller with boiler')
    assert_includes canon, 'DOAS ventilation'
    assert_includes canon, 'four-pipe fan coils'
  end

  def test_listing_includes_canonical_and_filter_matches_it
    rows = OpenStudioHVAC.systems
    assert(rows.all? { |r| r['canonical_name'].is_a?(String) && !r['canonical_name'].empty? })
    hits = OpenStudioHVAC.systems(filter: 'packaged single-zone')
    assert hits.any?, 'filter should match canonical names too'
  end

  def test_resolve_and_build_by_canonical_name
    config = OpenStudioHVAC::Catalog.resolve('hot water baseboards (gas boiler)')
    assert_equal 'Baseboard gas boiler', config['name']

    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'hot water baseboards (gas boiler)', zones)
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert_equal 2, model.getBoilerHotWaters.size
  end

  private

  def canonical_for(legacy_name)
    row = OpenStudioHVAC::Catalog.rows.find { |r| r['name'] == legacy_name }
    refute_nil row, "no catalog row named '#{legacy_name}'"
    OpenStudioHVAC::Canonical.name(row)
  end
end
