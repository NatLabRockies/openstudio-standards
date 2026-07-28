require_relative 'test_helper'

# P4 gate: NECB.reference_hvac golden scenarios — proposed -> reference topology per
# Table 8.4.4.7.-A/-B, fan specs per 8.4.4.18, oversizing caps per 8.4.4.8, HP rules
# per 8.4.4.13, with the article-tagged audit trail.
class TestNecbReference < Minitest::Test
  include FixtureHelper

  def proposed(name, &block)
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, name, zones)
    block&.call(model)
    model
  end

  def types(model, type)
    model.getThermalZones.to_h { |z| [z.nameString, type] }
  end

  # small office, electric heat -> System 3, electric variant; supply fans 640 Pa/40%
  def test_small_office_to_sys3_electric
    model = proposed('Baseboard electric')
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types(model, 'Office - enclosed') })

    assert_equal [3], result.assignments.map(&:reference_system).uniq
    assert_equal ['electric'], result.assignments.map(&:energy_type).uniq
    refute_empty result.model.getAirLoopHVACs, 'reference builds PSZ RTUs'
    assert_empty model.getAirLoopHVACs, 'proposed model untouched'
    result.model.getFanConstantVolumes.each do |fan|
      assert_in_delta 640.0, fan.pressureRise, 0.1
      assert_in_delta 0.40, fan.fanTotalEfficiency, 1e-6
    end
    # electric reference has no gas: heating from electric coil + electric baseboards
    assert_empty result.model.getCoilHeatingGass
  end

  # 3-storey gas VAV office -> System 6; supply 1000 Pa/55%, return 250 Pa/30%
  def test_three_storey_office_to_sys6
    model = proposed('MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard')
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 3, zone_types: types(model, 'Office - open plan') })

    assert_equal [6], result.assignments.map(&:reference_system).uniq
    assert_equal ['gas'], result.assignments.map(&:energy_type).uniq, 'energy type follows proposed boiler fuel'
    supply = result.model.getFanVariableVolumes.reject { |f| f.nameString =~ /return/i }
    returns = result.model.getFanVariableVolumes.select { |f| f.nameString =~ /return/i }
    refute_empty supply
    refute_empty returns
    supply.each { |f| assert_in_delta 1000.0, f.pressureRise, 0.1 }
    returns.each do |f|
      assert_in_delta 250.0, f.pressureRise, 0.1
      assert_in_delta 0.30, f.fanTotalEfficiency, 1e-6
    end
  end

  # D-34 (A1 ruled follow-legacy): residential PTHP is a HEAT PUMP -> the
  # 8.4.4.7.(4) ASHP redirect wins over the Table -A "(or heat pumps)"
  # identical-to-proposed parenthetical.
  def test_residential_pthp_redirects_to_ashp_reference
    model = proposed('PTHP')
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types(model, 'Multi-unit residential') })

    assert_equal ['hp'], result.assignments.map(&:reference_system).uniq
    assert_equal [:build], result.assignments.map(&:action).uniq
    assert_empty result.model.getZoneHVACPackagedTerminalHeatPumps, 'proposed PTHPs replaced by the ASHP reference'
    refute_empty result.model.getAirLoopHVACs, 'ASHP RTU reference built'
  end

  # D-37 (A2 ruled: printed 8.4.4.13 split per Note A-8.4.4.13): the catalog
  # 'Water source heat pumps' system is by the note's definitions a
  # water-LOOP HP — internal loop with aux boiler + evaporative fluid cooler —
  # so it KEEPS its Table -A selection (office 1-storey -> System 3), with the
  # retention audited. Swapping the loop's internal sources for a ground HX
  # makes it ground-SOURCE -> the 8.4.4.13.(2) ASHP redirect fires.
  def test_water_loop_hp_keeps_selection_ground_source_redirects
    model = proposed('Water source heat pumps')
    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(model, audit: audit,
                                                 building: { storeys: 1, zone_types: types(model, 'Office - enclosed') })
    assert_equal [3], result.assignments.map(&:reference_system).uniq,
                 'internal boiler+fluid-cooler loop = water-loop HP -> Table -A selection retained'
    assert(audit.entries.any? { |e| e[:article].to_s.include?('Note A-8.4.4.13') },
           'retention decision cites the note')

    ground = proposed('Water source heat pumps')
    loop_ = ground.getPlantLoops.find { |l| l.nameString =~ /Heat Pump/i }
    loop_.supplyComponents.each do |c|
      c.to_BoilerHotWater.get.remove if c.to_BoilerHotWater.is_initialized
      c.to_EvaporativeFluidCoolerSingleSpeed.get.remove if c.to_EvaporativeFluidCoolerSingleSpeed.is_initialized
    end
    ghx = OpenStudio::Model::GroundHeatExchangerVertical.new(ground)
    loop_.addSupplyBranchForComponent(ghx)
    result = OpenStudioHVAC::NECB.reference_hvac(ground,
                                                 building: { storeys: 1, zone_types: types(ground, 'Office - enclosed') })
    assert_equal ['hp'], result.assignments.map(&:reference_system).uniq,
                 'ground HX on the source loop = ground-source HP -> ASHP redirect'
  end

  # D-39 (A4 ruled conditional): an UNHEATED refrigerated proposed block gets
  # the Table -B literal — a cooling-only TPFC reference (no boiler, no MAU
  # heating coil, zone heating a zero-capacity always-off placeholder); a
  # HEATED one keeps the two-pipe changeover per 8.4.4.1.(5).
  def test_system5_cooling_only_when_proposed_unheated
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    # cooling-only proposed: DX + fan air loop, no heating coil anywhere
    loop_ = OpenStudio::Model::AirLoopHVAC.new(model)
    OpenStudio::Model::FanConstantVolume.new(model, model.alwaysOnDiscreteSchedule).addToNode(loop_.supplyInletNode)
    OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model).addToNode(loop_.supplyInletNode)
    zones.each do |z|
      loop_.addBranchForZone(z, OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(
        model, model.alwaysOnDiscreteSchedule
      ).to_StraightComponent)
    end

    result = OpenStudioHVAC::NECB.reference_hvac(
      model, building: { storeys: 1, zone_types: types(model, 'Warehouse - refrigerated'),
                         refrigerated_zones: zones.map(&:nameString) }
    )
    assert_equal [5], result.assignments.map(&:reference_system).uniq
    ref = result.model
    assert_empty ref.getBoilerHotWaters, 'Table -B "None": no heating plant'
    refute_empty ref.getChillerElectricEIRs, 'chilled-water cooling present'
    refute_empty ref.getZoneHVACFourPipeFanCoils
    assert_empty ref.getCoilHeatingWaters, 'no hydronic heating coils anywhere'
    ref.getCoilHeatingElectrics.each do |c|
      assert_in_delta 0.0, c.nominalCapacity.get, 1e-9, 'placeholder zone heating coil at zero capacity'
    end
  end

  def test_system5_keeps_heating_when_proposed_heated
    model = proposed('Baseboard electric')
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, building: { storeys: 1, zone_types: types(model, 'Warehouse - refrigerated'),
                         refrigerated_zones: zones.map(&:nameString) }
    )
    assert_equal [5], result.assignments.map(&:reference_system).uniq
    refute_empty result.model.getBoilerHotWaters, '8.4.4.1.(5): proposed heated -> reference heats (changeover kept)'
  end

  # residential PTAC (compatible NON-heat-pump cooling) -> reference identical
  # to proposed (copy rule): nothing rebuilt
  def test_residential_ptac_copies_proposed
    model = proposed('PTAC with baseboard electric')
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types(model, 'Multi-unit residential') })

    assert_equal [:copy_proposed], result.assignments.map(&:action).uniq
    refute_empty result.model.getZoneHVACPackagedTerminalAirConditioners, 'PTACs retained'
    assert_empty result.model.getAirLoopHVACs
  end

  # data centre with >20 kW cooling -> System 2 (4PFC + water-cooled chiller)
  def test_data_centre_to_sys2
    model = proposed('PSZ RTU Electric and DX Coils and Electric Baseboard') do |m|
      m.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(30_000.0) }
    end
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types(model, 'Data centre') })

    assert_equal [2], result.assignments.map(&:reference_system).uniq
    refute_empty result.model.getZoneHVACFourPipeFanCoils, 'System 2 = four-pipe fan coils'
    refute_empty result.model.getChillerElectricEIRs
  end

  # proposed AIR-SOURCE heat pumps -> Table 8.4.4.13 ASHP reference with the
  # -10 degC heating cutoff. (D-37: was 'Water source heat pumps', which is by
  # Note A-8.4.4.13 a water-LOOP system that now correctly keeps Table -A —
  # see test_water_loop_hp_keeps_selection_ground_source_redirects.)
  def test_heat_pump_proposed_to_ashp_reference
    model = proposed('PTHP')
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types(model, 'Office - enclosed') })

    assert_equal ['hp'], result.assignments.map(&:reference_system).uniq
    hp_coils = result.model.getCoilHeatingDXSingleSpeeds
    refute_empty hp_coils
    hp_coils.each { |c| assert_in_delta(-10.0, c.minimumOutdoorDryBulbTemperatureforCompressorOperation, 1e-6) }
  end

  # 8.4.4.8: oversizing = lesser of proposed and 30%/10% caps
  def test_oversizing_caps_and_audit_trail
    model = proposed('Baseboard gas boiler')
    model.getSizingParameters.setHeatingSizingFactor(1.5)
    model.getSizingParameters.setCoolingSizingFactor(1.25)
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types(model, 'Office - enclosed') })

    assert_in_delta 1.3, result.model.getSizingParameters.heatingSizingFactor, 1e-6
    assert_in_delta 1.1, result.model.getSizingParameters.coolingSizingFactor, 1e-6

    entry = result.audit.entries.find { |e| e[:action].include?('oversizing capped') }
    assert_match(/min\(proposed 1\.5, cap 1\.3\)/, entry[:value])
    assert_equal '8.4.4.8.(1)-(2)', entry[:article]

    # the audit narrates the whole pipeline and serializes
    steps = result.audit.entries.map { |e| e[:step] }.uniq
    %i[characterize selection build rules efficiency].each { |s| assert_includes steps, s }
    assert JSON.parse(result.audit.to_json).size.positive?
  end
end
