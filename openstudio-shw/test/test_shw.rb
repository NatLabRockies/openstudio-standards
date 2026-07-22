require_relative 'test_helper'

# P1-P3 gates: rules data, demand/plant construction, and the efficiency bins.
class TestSHW < Minitest::Test
  include FixtureHelper

  def test_rules_and_coverage_lint
    %w[2020 2025].each do |vintage|
      rules = OpenStudioSHW::NECB.rules(vintage)
      assert_equal 0.82, rules['efficiency']['fuel_fired']['burner_efficiency']
      assert_equal [0.7576, 1.0071, -1.4443, 0.6844], rules['efficiency']['part_load_curve']['coefficients']
      coverage = rules['article_coverage']['articles']
      assert_operator coverage.size, :>=, 6
      coverage.each { |a| assert(a['how'] || a['gaps']) }
    end
    # Vintage aliasing is owned by openstudio-loads (OpenStudioLoads::NECB.data_vintage,
    # called directly from necb/demand.rb) — shw does not vendor its own
    # data_vintage_alias key (removed as dead config; see provenance.note).
    assert_nil OpenStudioSHW::NECB.rules('2025')['data_vintage_alias']
    assert_match(/UEF >= 2.23/, OpenStudioSHW::NECB.rules('2025')['changes_vs_2020']['heat_pump_storage_water_heater'])
  end

  def test_apply_shw_builds_loop_and_demand
    model = tagged_model
    audit = OpenStudioSHW::AuditLog.new
    loop = OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: 'NaturalGas', audit: audit)

    refute_nil loop
    heater = model.getWaterHeaterMixeds.first
    refute_nil heater
    assert_operator heater.tankVolume.get, :>, 0
    assert_operator heater.heaterMaximumCapacity.get, :>, 0
    assert_equal 'NaturalGas', heater.heaterFuelType
    assert heater.partLoadFactorCurve.is_initialized, 'SWH-EFFFPLR curve applied'
    assert_match(/Therm Eff/, heater.nameString, 'efficiency applied on the sized heater')

    equipment = model.getWaterUseEquipments
    assert_equal 5, equipment.size, 'one water use per demanding space'
    equipment.each do |wue|
      assert wue.space.is_initialized
      assert wue.flowRateFractionSchedule.is_initialized
      assert_match(/^NECB-A-Service Water Heating/, wue.flowRateFractionSchedule.get.nameString)
      assert_operator wue.waterUseEquipmentDefinition.peakFlowRate, :>, 0
    end
    assert_equal 5, model.getWaterUseConnectionss.size
    assert(audit.entries.any? { |e| e[:action].include?('auto-sized') })
    assert(audit.warnings.empty? || audit.warnings.none? { |w| w[:action].include?('schedule') })
  end

  def test_no_demand_no_loop
    model = load_fixture # untagged: no space types -> no SHW demand
    audit = OpenStudioSHW::AuditLog.new
    result = OpenStudioSHW.apply_shw(model, vintage: '2020', audit: audit)
    assert_nil result
    assert_empty model.getPlantLoops.to_a
    assert(audit.entries.any? { |e| e[:action].include?('no SHW loop added') })
  end

  def test_efficiency_bins_golden
    model = OpenStudio::Model::Model.new
    # gas 150 L / 15 kW -> 76-208 L ladder; FHR = 0.7x150+151 = 256 -> 193-284 bin
    heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    heater.setTankVolume(0.150)
    heater.setHeaterMaximumCapacity(15_000)
    heater.setHeaterFuelType('NaturalGas')
    audit = OpenStudioSHW::AuditLog.new
    OpenStudioSHW::NECB.apply_water_heater_efficiency(heater, vintage: '2020', audit: audit)

    assert_in_delta 0.82, heater.heaterThermalEfficiency.get, 1e-9, 'burner efficiency'
    uef = 0.6483 - 0.00045 * 150
    decision = audit.entries.find { |e| e[:step] == :shw_efficiency && e[:level] == :decision }
    assert_match(/UEF #{uef.round(4)}/, decision[:evidence])
    assert_operator heater.offCycleLossCoefficienttoAmbientTemperature.get, :>, 0

    # electric small: 12 kW / 200 L -> SL = 40 + 0.2x200 = 80 W
    electric = OpenStudio::Model::WaterHeaterMixed.new(model)
    electric.setTankVolume(0.200)
    electric.setHeaterMaximumCapacity(11_000)
    electric.setHeaterFuelType('Electricity')
    OpenStudioSHW::NECB.apply_water_heater_efficiency(electric, vintage: '2020', audit: audit)
    assert_in_delta 1.0, electric.heaterThermalEfficiency.get, 1e-9
    expected_ua = OpenStudio.convert(80.0, 'W', 'Btu/hr').get / 70.0
    expected_ua_si = OpenStudio.convert(expected_ua, 'Btu/hr*R', 'W/K').get
    assert_in_delta expected_ua_si, electric.offCycleLossCoefficienttoAmbientTemperature.get, 1e-6

    # large gas: 100 kW / 500 L -> Et 0.9 + SL formula
    large = OpenStudio::Model::WaterHeaterMixed.new(model)
    large.setTankVolume(0.500)
    large.setHeaterMaximumCapacity(100_000)
    large.setHeaterFuelType('NaturalGas')
    OpenStudioSHW::NECB.apply_water_heater_efficiency(large, vintage: '2020', audit: audit)
    assert_operator large.heaterThermalEfficiency.get, :>, 0.9, 'Et + UA/capacity adjustment'
  end

  def test_reference_shw_coverage
    model = tagged_model
    OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: 'Electricity')
    audit = OpenStudioSHW::AuditLog.new
    OpenStudioSHW::NECB.reference_shw(model, vintage: '2020', audit: audit)
    assert(audit.entries.any? { |e| e[:article] == '8.4.4.20.(1)' })
    coverage = audit.entries.select { |e| e[:step] == :coverage }
    assert_operator coverage.size, :>=, 6
    assert(coverage.any? { |e| e[:level] == :warning }, 'gaps warn')
  end
end
