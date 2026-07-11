require_relative 'test_helper'

# End-to-end costing: build -> (hard-)size -> cost. Uses hard-sized values so the test is
# standalone and fast; a full sizing-run flow behaves identically via autosized accessors.
class TestCostingE2E < Minitest::Test
  include FixtureHelper

  def test_family_ahu_manifest_covers_air_loop_families
    air_loop_families = OpenStudioHVAC::Builder::FAMILIES.keys - %w[baseboards zone_terminal unit_heaters wshp vrf zone_ervs]
    air_loop_families.each do |family|
      assert OpenStudioHVAC::Costing::VentilationQuantifier::FAMILY_SYS_TYPE.key?(family),
             "family '#{family}' missing from the AHU manifest"
    end
  end

  def test_psz_system_costs_end_to_end
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'PSZ RTU Electric and DX Coils and Electric Baseboard', zones)

    # hard-size in lieu of a sizing run
    result.air_loops.each { |al| al.setDesignSupplyAirFlowRate(2.0) } # m3/s (~4238 cfm)
    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(40_000.0) }

    report = OpenStudioHVAC.cost(model, systems: [result], city: 'TORONTO', province_state: 'ONTARIO')

    assert_operator report.total, :>, 0
    assert_operator report.by_category['VENTILATION'].to_f, :>, 0, 'AHU assembly costed'
    assert_operator report.by_category['DISTRIBUTION'].to_f, :>, 0, 'zone duct/diffusers costed'
    assert_operator report.by_category['ZONAL'].to_f, :>, 0, 'electric baseboards costed'
    assert(report.items.any? { |i| i['note'].to_s.include?('AHU') })
    assert(report.warnings.any? { |w| w.include?('trunk duct') }, 'deferred geometry is a warning, not silence')
  end

  def test_hydronic_vav_costs_plant_and_ahu
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)

    result.air_loops.each { |al| al.setDesignSupplyAirFlowRate(3.0) }
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(80_000.0) }
    model.getChillerElectricEIRs.each { |c| c.setReferenceCapacity(120_000.0) }
    model.getPumpVariableSpeeds.each { |p| p.setRatedPowerConsumption(1500.0) }
    model.getCoilHeatingWaterBaseboards.each { |c| c.setHeatingDesignCapacity(4000.0) }

    report = OpenStudioHVAC.cost(model, systems: [result], city: 'VANCOUVER', province_state: 'BRITISH COLUMBIA')

    assert_operator report.by_category['HEATING_COOLING'].to_f, :>, 0, 'boilers + chillers + tower + pumps'
    assert_operator report.by_category['VENTILATION'].to_f, :>, 0, 'sys6 HW/CHW AHU assembly'
    assert(report.items.any? { |i| i['note'].to_s.include?('chiller') })
    assert(report.items.any? { |i| i['note'].to_s.include?('boiler') })
  end

  def test_foreign_air_loop_warns_but_still_costs_plant
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    model.getBoilerHotWaters.each { |b| b.setNominalCapacity(50_000.0) }
    # a hand-made air loop the gem did not build
    foreign = OpenStudio::Model::AirLoopHVAC.new(model)
    foreign.setName('SomeoneElsesLoop')
    foreign.setDesignSupplyAirFlowRate(1.0)

    report = OpenStudioHVAC.cost(model, city: 'TORONTO', province_state: 'ONTARIO')
    assert_operator report.by_category['HEATING_COOLING'].to_f, :>, 0
    assert(report.warnings.any? { |w| w.include?('SomeoneElsesLoop') })
  end

  def test_city_inferred_from_site
    model = load_fixture
    model.getSite.setLatitude(43.65)
    model.getSite.setLongitude(-79.38)
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Electric unit heaters', zones)
    model.getCoilHeatingElectrics.each { |c| c.setNominalCapacity(5000.0) }
    report = OpenStudioHVAC.cost(model)
    assert_equal 'TORONTO', report.city.upcase
  end
end
