require_relative 'test_helper'

# C3 coverage gate: every family produces an itemized cost (or explained warnings) —
# costing is available to ALL systems and families, not just NECB/ECM.
class TestCostingCoverage < Minitest::Test
  include FixtureHelper

  REPRESENTATIVES = {
    'baseboards' => 'Baseboard gas boiler',
    'psz' => 'PSZ RTU Gas and DX Coils and Electric Baseboard',
    'vav_reheat' => 'MZ BU RTU Electric Heating Coil Scroll Chiller and Electric Baseboard',
    'fan_coils' => 'FPFC MAU DX Coils with Scroll Chiller',
    'mau_ptac' => 'PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC',
    'zone_terminal' => 'PTHP',
    'unit_heaters' => 'Gas unit heaters',
    'furnace' => 'Forced air furnace',
    'evap_cooler' => 'Direct evap coolers with no heat',
    'wshp' => 'Water source heat pumps',
    'doas' => 'DOAS ventilation only',
    'vrf' => 'VRF',
    'zone_ervs' => 'Zone ERVs',
    'doas_pthp' => 'hs11_ashp_pthp',
    'ecm_ashp_baseboard' => 'hs12_ashp_baseboard',
    'ecm_doas_vrf' => 'hs08_ccashp_vrf',
    'ecm_hp_fancoils' => 'hs15_cawhp_fancoils'
  }.freeze

  def hard_size(model)
    model.getAirLoopHVACs.each { |al| al.setDesignSupplyAirFlowRate(2.0) }
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(60_000.0) }
    model.getChillerElectricEIRs.each { |c| c.setReferenceCapacity(100_000.0) }
    (model.getPumpConstantSpeeds + model.getPumpVariableSpeeds).each { |p| p.setRatedPowerConsumption(1000.0) }
    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(20_000.0) }
    model.getCoilCoolingDXVariableRefrigerantFlows.each { |c| c.setRatedTotalCoolingCapacity(5_000.0) }
    model.getAirConditionerVariableRefrigerantFlows.each { |u| u.setGrossRatedTotalCoolingCapacity(40_000.0) }
    model.getCoilHeatingGass.each { |c| c.setNominalCapacity(15_000.0) }
    model.getCoilHeatingElectrics.each { |c| c.setNominalCapacity(10_000.0) }
    model.getCoilHeatingWaterBaseboards.each { |c| c.setHeatingDesignCapacity(4_000.0) }
    model.getCoilCoolingWaterToAirHeatPumpEquationFits.each { |c| c.setRatedTotalCoolingCapacity(6_000.0) }
    model.getHeatPumpPlantLoopEIRHeatings.each { |h| h.setReferenceCapacity(80_000.0) }
    model.getHeatPumpWaterToWaterEquationFitHeatings.each { |h| h.setRatedHeatingCapacity(80_000.0) }
    model.getZoneHVACEnergyRecoveryVentilators.each { |e| e.setSupplyAirFlowRate(0.5) }
  end

  def test_every_family_produces_an_itemized_cost
    failures = []
    REPRESENTATIVES.each do |family, name|
      model = load_fixture
      zones = model.getThermalZones.sort_by(&:nameString)
      result = OpenStudioHVAC.build_system(model, name, zones)
      hard_size(model)
      report = OpenStudioHVAC.cost(model, systems: [result], city: 'TORONTO', province_state: 'ONTARIO')

      failures << "#{family} (#{name}): no items" if report.items.empty?
      failures << "#{family} (#{name}): zero total" unless report.total.positive?
    rescue StandardError => e
      failures << "#{family} (#{name}): #{e.class} #{e.message}"
    end
    assert_empty failures, failures.join("\n")
  end
end
