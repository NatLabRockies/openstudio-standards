require_relative 'test_helper'

# D-63 — Table 6.2.2.1 solar-thermal + pool-heater minimums, apply-when-present.
# The printed rows were LOST from the extraction in both editions (hbix table
# audit 2026-08-02); values come from the vendored solar_pool_minimums block.
class TestSolarPoolMinimums < Minitest::Test
  def spec
    OpenStudioSHW::NECB.rules('2020')['solar_pool_minimums']
  end

  def pool_model(fuel)
    model = OpenStudio::Model::Model.new
    # A floor surface to host the indoor pool.
    space = OpenStudio::Model::Space.new(model)
    pts = OpenStudio::Point3dVector.new
    [[0, 0, 0], [0, 5, 0], [5, 5, 0], [5, 0, 0]].each { |x, y, z| pts << OpenStudio::Point3d.new(x, y, z) }
    floor = OpenStudio::Model::Surface.new(pts, model)
    floor.setSpace(space)
    floor.setSurfaceType('Floor')

    pool = OpenStudio::Model::SwimmingPoolIndoor.new(model, floor)
    heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    heater.setHeaterFuelType(fuel)
    heater.setHeaterThermalEfficiency(0.95)

    loop = OpenStudio::Model::PlantLoop.new(model)
    loop.addSupplyBranchForComponent(heater)
    loop.addDemandBranchForComponent(pool)
    [model, heater]
  end

  def test_vendored_values_match_the_printed_rows
    assert_equal 0.82, spec['pool_gas_thermal_efficiency']
    assert_equal 0.78, spec['pool_oil_thermal_efficiency']
    assert_equal 4.0, spec['pool_heat_pump_cop']
    assert_equal 1.4, spec['solar_sef_aux_electric']
    assert_equal 0.9, spec['solar_sef_aux_gas']
  end

  def test_gas_pool_heater_takes_the_printed_minimum
    model, heater = pool_model('NaturalGas')
    audit = OpenStudioSHW::AuditLog.new
    OpenStudioSHW::NECB::Efficiency.apply_solar_pool_minimums(model, vintage: '2020', audit: audit)
    assert_in_delta 0.82, heater.heaterThermalEfficiency.get, 1e-9
    entry = audit.entries.find { |e| e[:action].include?('pool heater set to the Table 6.2.2.1 minimum') }
    refute_nil entry
    assert_includes entry[:ruling].to_s, 'D-63'
  end

  def test_oil_pool_heater_takes_its_row_and_electric_is_audited_not_forced
    model, heater = pool_model('FuelOilNo2')
    OpenStudioSHW::NECB::Efficiency.apply_solar_pool_minimums(model, vintage: '2020',
                                                              audit: OpenStudioSHW::AuditLog.new)
    assert_in_delta 0.78, heater.heaterThermalEfficiency.get, 1e-9

    model, heater = pool_model('Electricity')
    audit = OpenStudioSHW::AuditLog.new
    OpenStudioSHW::NECB::Efficiency.apply_solar_pool_minimums(model, vintage: '2020', audit: audit)
    assert_in_delta 0.95, heater.heaterThermalEfficiency.get, 1e-9, 'no printed electric pool row — left as cloned'
    assert(audit.entries.any? { |e| e[:action].include?('no Table 6.2.2.1 pool row') })
  end

  def test_solar_collectors_get_the_rating_level_determination
    model = OpenStudio::Model::Model.new
    OpenStudio::Model::SolarCollectorFlatPlateWater.new(model)
    audit = OpenStudioSHW::AuditLog.new
    OpenStudioSHW::NECB::Efficiency.apply_solar_pool_minimums(model, vintage: '2020', audit: audit)
    entry = audit.entries.find { |e| e[:action].include?('Solar Energy') }
    refute_nil entry, 'solar SEF determination recorded'
    assert_includes entry[:action], 'RATING'
    assert_includes entry[:ruling].to_s, 'D-63'
  end

  def test_no_op_without_pools_or_collectors
    model = OpenStudio::Model::Model.new
    OpenStudio::Model::WaterHeaterMixed.new(model)
    audit = OpenStudioSHW::AuditLog.new
    OpenStudioSHW::NECB::Efficiency.apply_solar_pool_minimums(model, vintage: '2020', audit: audit)
    assert_empty audit.entries.select { |e| e[:ruling].to_s.include?('D-63') }, 'apply-when-present: silent no-op'
  end
end
