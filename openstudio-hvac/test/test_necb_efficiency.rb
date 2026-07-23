require_relative 'test_helper'

# P3 gate (standalone half): NECB.apply_efficiencies sets Table 5.2.12.1 values on a
# hard-sized model. The other half is the scratchpad parity harness vs legacy
# model_apply_hvac_efficiency_standard (0 mismatches on sys3/sys6/ref-HP).
class TestNecbEfficiency < Minitest::Test
  include FixtureHelper

  def test_boiler_chiller_dx_gas_values_and_audit
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(100_000.0) } # 100 kW < 176 kW
    model.getChillerElectricEIRs.each { |c| c.setReferenceCapacity(200_000.0) } # ~57 tons: first scroll bin

    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)

    # NECB 2020 gas boiler < 300 kBtu/hr: 0.90 AFUE -> thermal efficiency 0.90
    primary = model.getBoilerHotWaters.find { |b| b.nameString.include?('Primary') }
    secondary = model.getBoilerHotWaters.find { |b| b.nameString.include?('Secondary') }
    assert_in_delta 0.90, primary.nominalThermalEfficiency, 1e-6
    # < 176 kW: primary keeps capacity, secondary parked at 0.001 W (legacy staging rule)
    assert_in_delta 100_000.0, primary.nominalCapacity.get, 1.0
    assert_in_delta 0.001, secondary.nominalCapacity.get, 1e-6
    assert primary.normalizedBoilerEfficiencyCurve.is_initialized
    assert_match(/BOILER-EFFFPLR/, primary.normalizedBoilerEfficiencyCurve.get.nameString)

    # Water-cooled scroll chiller 200 kW (~57 tons, 0-75 ton bin): 0.77927 kW/ton
    chiller = model.getChillerElectricEIRs.min_by(&:nameString)
    assert_in_delta 3.517 / 0.77927, chiller.referenceCOP, 1e-3
    assert_equal 'LeavingSetpointModulated', chiller.chillerFlowMode
    assert_in_delta 0.25, chiller.minimumPartLoadRatio, 1e-6
    assert_match(/CAPFT/, chiller.coolingCapacityFunctionOfTemperature.nameString)

    # every decision carries a code citation: Table 5.2.12 minimums, or the
    # 8.4.4.14/8.4.4.17 pump/fan curve articles the pass also applies
    decisions = audit.entries.select { |e| e[:step] == :efficiency && e[:level] == :decision }
    refute_empty decisions
    assert decisions.all? { |e| e[:article].to_s.match?(/5\.2\.12|8\.4\.[45]\.1[47]/) },
           "uncited decision: #{decisions.find { |e| !e[:article].to_s.match?(/5\.2\.12|8\.4\.[45]\.1[47]/) }&.dig(:action)}"
  end

  def test_dx_and_gas_coil_and_ashp
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PSZ RTU Gas and DX Coils and Electric Baseboard', zones)
    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(15_000.0) }
    model.getCoilHeatingGass.each { |c| c.setNominalCapacity(20_000.0) }

    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020')

    # gas heat on the loop -> 'All Other' heating type; 15 kW (~51 kBtu/hr) bin
    coil = model.getCoilCoolingDXSingleSpeeds.min_by(&:nameString)
    cop = coil.ratedCOP.respond_to?(:is_initialized) ? coil.ratedCOP.get : coil.ratedCOP
    assert_operator cop, :>, 2.5
    assert_match(/SEER|EER/, coil.nameString)
    # Exact value, hand-derived the same way as the ASHP heating COP below:
    # efficiencies_2020.json's unitary_acs table, AirCooled/All Other/Single
    # Package, 0-65000 Btu/hr bin (15 kW = ~51,182 Btu/hr) declares SEER 15.0;
    # seer_to_cop_no_fan(seer) = -0.0076*seer^2 + 0.3796*seer (efficiency.rb).
    assert_in_delta((-0.0076 * 15.0 * 15.0) + (0.3796 * 15.0), cop, 1e-6,
                    '15.0 SEER (0-65 kBtu/hr AirCooled/All Other/Single Package bin) -> COP 3.984')
    assert_match(/15\.0SEER/, coil.nameString)

    gas = model.getCoilHeatingGass.min_by(&:nameString)
    assert_operator gas.gasBurnerEfficiency, :>=, 0.90 # NECB 2020 furnace >= 0.95 AFUE band
    assert gas.partLoadFractionCorrelationCurve.is_initialized

    # ASHP pair: heating COP from heat_pumps_heating
    model2 = load_fixture
    zones2 = model2.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model2, 'PSZ RTU ASHP with Electric and ASHP with Electric Supp. Heat Coils and Electric Baseboard', zones2)
    model2.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(12_000.0) }
    model2.getCoilHeatingDXSingleSpeeds.each { |c| c.setRatedTotalHeatingCapacity(12_000.0) }
    OpenStudioHVAC::NECB.apply_efficiencies(model2, vintage: '2020')
    hp = model2.getCoilHeatingDXSingleSpeeds.min_by(&:nameString)
    # 7.4 HSPF -> -0.0296*7.4^2 + 0.7134*7.4 = 3.658
    assert_in_delta 3.658, hp.ratedCOP, 0.01
  end

  def test_unsized_model_warns_never_silent
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PSZ RTU Gas and DX Coils and Electric Baseboard', zones)
    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)
    assert audit.warnings.any? { |w| w[:action].include?('not sized') }
  end
end
