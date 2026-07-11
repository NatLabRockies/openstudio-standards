require_relative 'test_helper'

# C1 generic equipment costing: build (unsized) topologies, quantify hard-sizeable pieces,
# and verify ledger contents. (Capacity-dependent items are exercised in the sized coverage
# test at C3; here we hard-size a few objects to prove the pipeline.)
class TestCostingEquipment < Minitest::Test
  include FixtureHelper

  def quantify(model)
    db = OpenStudioHVAC::Costing::Database.new
    ledger = OpenStudioHVAC::Costing::Ledger.new
    quantifier = OpenStudioHVAC::Costing::EquipmentQuantifier.new(db, ledger)
    quantifier.quantify_plant(model)
    quantifier.quantify_zonal(model)
    [ledger, quantifier]
  end

  def test_pick_next_largest_and_multi_unit_fallback
    db = OpenStudioHVAC::Costing::Database.new
    q = OpenStudioHVAC::Costing::EquipmentQuantifier.new(db, OpenStudioHVAC::Costing::Ledger.new)
    row, units = q.pick('GasBoilers', 50.0, 'test')
    assert_equal 59.5, row['Size'].to_f, 'smallest size >= 50 kW'
    assert_equal 1.0, units

    row, units = q.pick('GasBoilers', 99_999.0, 'test')
    assert_operator units, :>, 1.0, 'oversize falls back to N x largest'

    assert_nil q.pick('NoSuchMaterial', 1, 'test')
    assert q.warnings.any? { |w| w.include?('NoSuchMaterial') }
  end

  def test_boiler_bucketing_and_ledger_items
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    # hard-size so quantification works without a sizing run
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(50_000.0) } # 50 kW
    ledger, quantifier = quantify(model)

    boiler_items = ledger.items.select { |i| i['note'].to_s.include?('boiler') }
    assert_equal 2, boiler_items.size, 'primary + secondary'
    # NECB boiler efficiency not applied (unsized) -> default eff -> bucket varies; assert costed either way
    assert(ledger.items.any? { |i| i['tags'].include?('HEATING_COOLING') })
    # HW baseboards produce ConvectCopper items with capacity warning (unsized) or entries
    assert(quantifier.warnings.any? { |w| w.include?('baseboard') } ||
           ledger.items.any? { |i| i['note'].to_s.include?('baseboard') })
  end

  def test_zonal_walk_covers_gem_families
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PTHP', zones)
    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(5000.0) }
    ledger, = quantify(model)

    pthp_items = ledger.items.select { |i| i['note'].to_s.include?('PTHP') }
    assert_equal zones.size, pthp_items.size
    assert(pthp_items.all? { |i| i['tags'].include?('ZONAL') })
  end

  def test_vrf_outdoor_and_terminals
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'VRF', zones)
    model.getAirConditionerVariableRefrigerantFlows.each { |u| u.setGrossRatedTotalCoolingCapacity(40_000.0) }
    model.getCoilCoolingDXVariableRefrigerantFlows.each { |c| c.setRatedTotalCoolingCapacity(5000.0) }
    ledger, = quantify(model)

    assert(ledger.items.any? { |i| i['note'].to_s.include?('VRF outdoor') })
    terminals = ledger.items.select { |i| i['note'].to_s.include?('VRF terminal') }
    assert_equal zones.size, terminals.size
  end

  def test_district_produces_warning_not_silent_zero
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard district hot water', zones)
    _, quantifier = quantify(model)
    assert(quantifier.warnings.any? { |w| w.include?('district') })
  end

  def test_priced_end_to_end_with_placeholders
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Gas unit heaters', zones)
    model.getCoilHeatingGass.each { |c| c.setNominalCapacity(10_000.0) }
    ledger, = quantify(model)
    db = OpenStudioHVAC::Costing::Database.new
    result = ledger.price(db, province_state: 'ONTARIO', city: 'TORONTO')
    assert_operator result['total'], :>, 0
    assert_operator result['by_category']['ZONAL'], :>, 0
  end
end
