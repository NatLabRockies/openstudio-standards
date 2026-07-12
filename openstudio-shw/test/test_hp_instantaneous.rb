require_relative 'test_helper'

# HP + instantaneous water heaters (the last SHW backlog item minus vintages).
class TestHPInstantaneous < Minitest::Test
  include FixtureHelper

  def instantaneous_heater(model, fuel, capacity_w)
    heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    heater.setTankVolume(0.005) # 5 L -> instantaneous bound (<= 7.6 L)
    heater.setHeaterMaximumCapacity(capacity_w)
    heater.setHeaterFuelType(fuel)
    heater
  end

  def test_instantaneous_bins
    model = OpenStudio::Model::Model.new
    audit = OpenStudioSHW::AuditLog.new

    small_gas = instantaneous_heater(model, 'NaturalGas', 40_000)
    OpenStudioSHW::NECB.apply_water_heater_efficiency(small_gas, vintage: '2020', audit: audit)
    assert_in_delta 0.86, small_gas.heaterThermalEfficiency.get, 1e-9, 'gas < 59 kW: conservative UEF row'
    assert_in_delta 0.0, small_gas.offCycleLossCoefficienttoAmbientTemperature.get, 1e-9, 'tankless: zero UA'

    big_gas = instantaneous_heater(model, 'NaturalGas', 100_000)
    OpenStudioSHW::NECB.apply_water_heater_efficiency(big_gas, vintage: '2020', audit: audit)
    assert_in_delta 0.94, big_gas.heaterThermalEfficiency.get, 1e-9, 'gas all others: Et 0.94'

    oil = instantaneous_heater(model, 'FuelOilNo2', 40_000)
    OpenStudioSHW::NECB.apply_water_heater_efficiency(oil, vintage: '2020', audit: audit)
    assert_in_delta 0.80, oil.heaterThermalEfficiency.get, 1e-9

    assert(audit.entries.any? { |e| e[:article].to_s.include?('instantaneous rows') })
    assert(audit.entries.any? { |e| e[:evidence].to_s.include?('conservative') }, 'flow assumption audited')
  end

  def test_heat_pump_water_heater_build_and_floor
    model = tagged_model
    audit = OpenStudioSHW::AuditLog.new
    loop = OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: 'HeatPump', audit: audit)

    refute_nil loop
    hpwhs = model.getWaterHeaterHeatPumps
    assert_equal 1, hpwhs.size, 'pumped-condenser HPWH built'
    hpwh = hpwhs.first
    tank = hpwh.tank.to_WaterHeaterMixed.get
    assert_equal 'Electricity', tank.heaterFuelType
    assert_operator tank.tankVolume.get, :>, 0, 'loop tank wrapped (not the default throwaway tank)'
    assert hpwh.thermalZone.is_initialized, 'compressor placed in a zone'

    coil = hpwh.dXCoil.to_CoilWaterHeatingAirToWaterHeatPump.get
    assert_in_delta 2.1, coil.ratedCOP, 1e-9, '2020 EF floor as rated COP'
    assert(audit.entries.any? { |e| e[:action].include?('conservative') && e[:article].to_s.include?('heat pump') })
  end

  def test_2025_uef_floor
    model = tagged_model
    OpenStudioSHW.apply_shw(model, vintage: '2025', fuel: 'HeatPump')
    coil = model.getWaterHeaterHeatPumps.first.dXCoil.to_CoilWaterHeatingAirToWaterHeatPump.get
    assert_in_delta 2.23, coil.ratedCOP, 1e-9, '2025 UEF floor'
  end

  def test_hphw_costing_detection
    model = tagged_model
    OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: 'HeatPump')
    audit = OpenStudioSHW::AuditLog.new
    report = OpenStudioSHW.cost(model, city: 'TORONTO', province_state: 'ONTARIO', audit: audit)
    assert_operator report.shw[:hphw], :>=, 1, 'HPWH tank costed as HPHW_Heater'
    assert_equal 0, report.shw[:elec], 'not double-counted as a plain electric tank'
    decisions = audit.entries.select { |e| e[:step] == :costing_equipment }.map { |e| e[:action] }
    refute(decisions.any? { |d| d.include?('flue') }, 'no flue for HPWH')
    # legacy: HPHW tanks are EXCLUDED from the electric utility wire/conduit run
    refute(decisions.any? { |d| d.include?('utility conduit') }, 'HPHW excluded from the electric utility run')
  end
end
