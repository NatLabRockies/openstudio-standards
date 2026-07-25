require_relative 'test_helper'

# Audit 2026-07-25 fixes (T-list): behavioural pins.
class TestAuditFixes < Minitest::Test
  include FixtureHelper

  def build_reference(system = 'Baseboard gas boiler')
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, system, zones)
    model.getSizingParameters.setHeatingSizingFactor(1.0) # proposed has NO oversizing
    model.getSizingParameters.setCoolingSizingFactor(1.0)
    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, vintage: '2020',
      building: { storeys: 1, zone_types: model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] } },
      audit: audit)
    [result, audit]
  end

  # T1: the 8.4.4.8 cap must actually govern — generic zone factors cleared.
  def test_oversizing_cap_binds_zone_factors_cleared
    result, audit = build_reference
    ref = result.model
    assert_in_delta 1.0, ref.getSizingParameters.heatingSizingFactor, 1e-9, 'min(proposed 1.0, cap 1.3)'
    generic = ref.getSizingZones.count do |sz|
      h = begin sz.zoneHeatingSizingFactor; rescue StandardError; nil; end
      h.respond_to?(:is_initialized) ? (h.is_initialized && (h.get - 1.3).abs < 1e-9) : (h && (h - 1.3).abs < 1e-9)
    end
    assert_equal 0, generic, 'no zone carries the generic 1.3 heating factor that would override the cap'
    decision = audit.entries.find { |e| e[:action] == 'equipment oversizing capped' }
    assert_operator decision[:inputs][:generic_zone_factors_cleared], :>, 0
  end

  # T3: below the 5.2.2.7 trigger the economizer is REMOVED post-sizing.
  def test_economizer_removed_below_trigger
    result, = build_reference # sys3 PSZ with DX
    ref = result.model
    ref.getAirLoopHVACs.each do |l|
      l.setDesignSupplyAirFlowRate(0.5) # 500 L/s <= 1500
      l.supplyComponents.each do |c|
        coil = c.to_CoilCoolingDXSingleSpeed
        coil.get.setRatedTotalCoolingCapacity(10_000.0) if coil.is_initialized # 10 kW <= 20
      end
    end
    audit = OpenStudioHVAC::NECB.apply_economizer_thresholds(ref)
    ref.getAirLoopHVACs.each do |l|
      oa = l.airLoopHVACOutdoorAirSystem
      next if oa.empty?
      assert_equal 'NoEconomizer', oa.get.getControllerOutdoorAir.getEconomizerControlType
    end
    assert(audit.entries.any? { |e| e[:action].include?('economizer REMOVED') && e[:article].include?('5.2.2.7') })
  end

  # T3: above the trigger it stays.
  def test_economizer_retained_above_trigger
    result, = build_reference
    ref = result.model
    ref.getAirLoopHVACs.each { |l| l.setDesignSupplyAirFlowRate(2.0) } # 2000 L/s > 1500
    OpenStudioHVAC::NECB.apply_economizer_thresholds(ref)
    kept = ref.getAirLoopHVACs.any? do |l|
      oa = l.airLoopHVACOutdoorAirSystem
      oa.is_initialized && oa.get.getControllerOutdoorAir.getEconomizerControlType == 'DifferentialEnthalpy'
    end
    assert kept, 'economizer retained above 1500 L/s'
  end

  # T4: paired DX HP heating capacity pinned to cooling capacity post-sizing.
  def test_hp_heating_capacity_pinned_to_cooling
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PSZ RTU ASHP with Electric and ASHP with Electric Supp. Heat Coils and Electric Baseboard', zones)
    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(14_000.0) }
    model.getCoilHeatingDXSingleSpeeds.each { |c| c.setRatedTotalHeatingCapacity(9_000.0) } # wrong on purpose
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)
    hp = model.getCoilHeatingDXSingleSpeeds.min_by(&:nameString)
    assert_in_delta 14_000.0, hp.ratedTotalHeatingCapacity.get, 1.0, '8.4.4.13.(2)(c): heating = cooling'
    assert(audit.entries.any? { |e| e[:article] == '8.4.4.13.(2)(c)' })
  end
end
