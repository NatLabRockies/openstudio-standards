require_relative 'test_helper'
require 'tempfile'

class TestCostingEngine < Minitest::Test
  def db
    @db ||= OpenStudioHVAC::Costing::Database.new
  end

  def test_database_loads_vendored_data
    assert db.materials_hvac.size > 1000
    assert db.ahu_assemblies.size > 500
    assert db.locations.size > 10
    assert db.mech_sizing.is_a?(Array)
    assert(db.mech_sizing.any? { |c| c['component'] == 'piping' })
  end

  def test_cost_record_and_missing_id
    rec = db.cost_record('240001')
    assert rec['materialOpCost'] > 0
    assert_raises(ArgumentError) { db.cost_record('NO_SUCH_ID') }
  end

  def test_regional_factors_match_and_fallback
    mat, inst, = db.regional_factors('ONTARIO', 'BARRIE', '017777')
    assert_equal [100.0, 100.0], [mat, inst], 'Barrie prefix 01 factors are 100/100'
    mat, inst, = db.regional_factors('NOWHERE', 'NOCITY', '017777')
    assert_equal [100.0, 100.0], [mat, inst]
    assert db.warnings.any? { |w| w.include?('NOCITY') }, 'fallback records a warning'
  end

  def test_closest_location
    loc = db.closest_location(43.65, -79.38) # downtown Toronto
    assert_equal 'TORONTO', loc['city'].upcase
  end

  def test_custom_costs_csv_overrides
    custom = Tempfile.new(['costs', '.csv'])
    custom.write("id,sheet,source,description,city,province_state,materialOpCost,laborOpCost,equipmentOpCost\n")
    custom.write("240001,materials_glazing,custom,test,,,999.0,1.0,0.0\n")
    custom.close
    custom_db = OpenStudioHVAC::Costing::Database.new(costs_csv: custom.path)
    assert_in_delta 999.0, custom_db.cost_record('240001')['materialOpCost'], 1e-6
    assert_operator custom_db.cost_record('240002')['materialOpCost'], :>, 0, 'non-overridden ids still present'
  ensure
    custom&.unlink
  end

  def test_ledger_pricing_math_and_categories
    ledger = OpenStudioHVAC::Costing::Ledger.new
    ledger.add(id: '240001', quantity: 2, tags: ['HEATING_COOLING'])
    rec = db.cost_record('240001')
    result = ledger.price(db, province_state: 'ONTARIO', city: 'TORONTO')
    mat_f, inst_f, = db.regional_factors('ONTARIO', 'TORONTO', '240001')
    expected = (rec['materialOpCost'] * mat_f / 100.0 + rec['laborOpCost'] * inst_f / 100.0) * 2
    assert_in_delta expected, result['total'], 0.01
    assert_in_delta expected, result['by_category']['HEATING_COOLING'], 0.01
  end

  def test_assembly_expansion
    ledger = OpenStudioHVAC::Costing::Ledger.new
    ledger.add_assembly(id_layers: '301,850', layer_multipliers: '1,.5',
                        base_quantity: 4, tags: ['VENTILATION'])
    quantities = ledger.items.map { |i| [i['id'], i['quantity']] }.to_h
    assert_equal 4.0, quantities['301']
    assert_equal 2.0, quantities['850']
  end

  def test_zero_quantities_skipped
    ledger = OpenStudioHVAC::Costing::Ledger.new
    ledger.add(id: '240001', quantity: 0, tags: ['ZONAL'])
    assert_empty ledger.items
  end
end
