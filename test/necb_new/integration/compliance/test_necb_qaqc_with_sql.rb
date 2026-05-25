require_relative '../../test_helper'
require_relative '../../fixtures/sized_model_fixture_manager'

# Integration tests for NECB QAQC that exercise the SQL-backed pieces of the
# pipeline using cached sized fixtures.
#
# The full qaqc_only() pipeline relies on a NECB prototype model with fully
# populated standards space-type lookups; our fixtures use simplified
# generic NECB space types, so the downstream compliance methods (e.g.
# necb_space_compliance) cannot resolve every space-type row. The tests
# below focus on the layers that DO work with the simplified fixture:
#   - create_base_data (extracts SQL data, envelope geometry, etc.)
#   - load_qaqc_database_new (CSV/YAML lookup table loader)
#   - get_qaqc_table (table search by criteria)
class TestNecbQaqcWithSql < Minitest::Test
  def setup
    @standard = Standard.build('NECB2011')
  end

  def test_create_base_data_runs_for_system1
    model = load_fixture_model(system_type: 'System1')
    qaqc = @standard.create_base_data(model)
    assert qaqc.is_a?(Hash)
    refute qaqc.empty?, "create_base_data should populate the qaqc hash"
  end

  def test_create_base_data_runs_for_system3
    model = load_fixture_model(system_type: 'System3')
    qaqc = @standard.create_base_data(model)
    assert qaqc.is_a?(Hash)
    refute qaqc.empty?
  end

  def test_create_base_data_runs_for_system6
    model = load_fixture_model(system_type: 'System6')
    qaqc = @standard.create_base_data(model)
    assert qaqc.is_a?(Hash)
    refute qaqc.empty?
  end

  def test_create_base_data_populates_canonical_sections
    model = load_fixture_model(system_type: 'System1')
    qaqc = @standard.create_base_data(model)
    # create_base_data should put at least one of the canonical section keys
    # into the hash.
    canonical = [:envelope, :spaces, :building, :unmet_hours, :sql,
                 :economizer, :thermal_zones, :air_loops, :plant_loops]
    assert canonical.any? { |k| qaqc.key?(k) },
           "Expected at least one canonical section, got: #{qaqc.keys.inspect}"
  end

  def test_init_qaqc_returns_base_hash
    model = load_fixture_model(system_type: 'System1')
    qaqc = @standard.init_qaqc(model)
    assert qaqc.is_a?(Hash)
  end

  def test_load_qaqc_database_new_returns_hash
    db = @standard.load_qaqc_database_new
    assert db.is_a?(Hash), "load_qaqc_database_new should return a hash"
  end

  def test_get_qaqc_table_raises_for_unknown_table
    @standard.load_qaqc_database_new
    err = assert_raises(RuntimeError) do
      @standard.get_qaqc_table(table_name: 'nonexistent_table_xyz')
    end
    assert_match(/could not find nonexistent_table_xyz/, err.message)
  end

  private

  def load_fixture_model(system_type:)
    fixture = SizedModelFixtureManager.get_or_create_sized_model(
      template: 'NECB2011', system_type: system_type, climate: 'toronto'
    )
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(fixture[:osm_path]).get
    sql = OpenStudio::SqlFile.new(OpenStudio::Path.new(fixture[:sql_path]))
    model.setSqlFile(sql)
    model
  end
end
