require_relative 'test_helper'

class TestVAVReheat < Minitest::Test
  include FixtureHelper

  ELECTRIC_SCROLL = 'MZ BU RTU Electric Heating Coil Scroll Chiller and Electric Baseboard'.freeze
  HW_CENTRIFUGAL  = 'MZ BU RTU Hot Water Heating Coil Centrifugal Chiller and Hot Water Baseboard'.freeze

  def test_electric_vav_builds_full_plant_and_air_side
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, ELECTRIC_SCROLL, zones)

    # fixture has one story containing all zones -> one air loop
    assert_equal 1, result.air_loops.size
    air_loop = result.air_loops.first
    assert_equal zones.size, air_loop.thermalZones.size

    # supply + return VAV fans with load-bearing names
    fans = model.getFanVariableVolumes
    assert_equal 2, fans.size
    assert fans.any? { |f| f.nameString.include?('Supply') }
    assert fans.any? { |f| f.nameString.include?('Return') }

    # chilled-water cooling coil on the CHW loop; electric heat (1 main + 5 reheat)
    assert_equal 1, model.getCoilCoolingWaters.size
    assert_equal 1 + zones.size, model.getCoilHeatingElectrics.size

    # chilled + condenser plant with named chillers and a cooling tower
    chillers = model.getChillerElectricEIRs
    assert_equal 2, chillers.size
    assert_equal ['Primary Chiller WaterCooled Scroll', 'Secondary Chiller WaterCooled Scroll'],
                 chillers.map(&:nameString).sort
    assert_equal 1, model.getCoolingTowerSingleSpeeds.size
    assert_equal 2, model.getPlantLoops.size, 'CHW + CW loops (no boiler for all-electric)'
    assert_empty model.getBoilerHotWaters

    # VAV terminals with NECB minimums
    terminals = model.getAirTerminalSingleDuctVAVReheats
    assert_equal zones.size, terminals.size
    terminals.each do |t|
      assert_equal 43.0, t.maximumReheatAirTemperature
      assert_equal 'Normal', t.damperHeatingAction
      assert t.fixedMinimumAirFlowRate.get > 0.0
    end

    # constant 13C supply-air setpoint
    spm = model.getSetpointManagerScheduleds.find { |m| m.setpointNode.get.handle.to_s == air_loop.supplyOutletNode.handle.to_s }
    refute_nil spm

    # sizing: sparse sys6 block (13/13.1 SATs, 0.3 min flow ratio)
    s = air_loop.sizingSystem
    assert_equal 13.0, s.centralCoolingDesignSupplyAirTemperature
    assert_equal 13.1, s.centralHeatingDesignSupplyAirTemperature
    assert_in_delta 0.3, s.centralHeatingMaximumSystemAirFlowRatio.to_f, 1e-6
  end

  def test_hot_water_variant_builds_boiler_and_hydronic_coils
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, HW_CENTRIFUGAL, zones)

    assert_equal 2, model.getBoilerHotWaters.size
    assert_equal 3, model.getPlantLoops.size, 'HW + CHW + CW'
    # 1 main + 5 reheat hot-water coils, all on the HW loop
    assert_equal 1 + zones.size, model.getCoilHeatingWaters.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert(model.getChillerElectricEIRs.all? { |c| c.nameString.include?('Centrifugal') })
  end

  def test_pipe_name_uses_sys6_token_order
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, ELECTRIC_SCROLL, zones, namer: :necb_pipe_name)
    # sys6 legacy order: sh> BEFORE sc> (observed from legacy build)
    assert_equal 'sys_6|mixed|shr>none|sh>c-e|sc>c-chw|ssf>vv|zh>b-e|zc>none|srf>vv|',
                 result.air_loops.first.nameString
  end

  def test_remove_existing_replaces_vav_with_psz
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, HW_CENTRIFUGAL, zones)
    refute_empty model.getChillerElectricEIRs

    OpenStudioHVAC.build_system(model, 'PSZ RTU Electric and DX Coils and Electric Baseboard',
                                zones, remove_existing: true)
    assert_empty model.getChillerElectricEIRs, 'chiller + condenser chain torn down'
    assert_empty model.getCoolingTowerSingleSpeeds
    assert_empty model.getBoilerHotWaters
    assert_equal 1, model.getAirLoopHVACs.size
  end
end
