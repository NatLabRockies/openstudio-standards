require_relative 'test_helper'

# NECB reference heat pump variants (sys1/3/4 ASHP). The legacy regional-fuel lookup is
# unnecessary here: the supplemental/reheat fuel is encoded in the descriptive name.
class TestReferenceHp < Minitest::Test
  include FixtureHelper

  SYS3_ASHP = 'PSZ RTU ASHP with Gas and ASHP with Gas Supp. Heat Coils and Electric Baseboard'.freeze
  SYS4_ASHP = 'PSZ RTU with exhaust ASHP with Electric and ASHP with Electric Supp. Heat Coils and Hot Water Baseboard'.freeze
  SYS1_ASHP = 'PSZ RTU ASHP with Gas and ASHP Coils and Electric Baseboard with Gas Reheat'.freeze

  def test_sys3_ashp_dx_heat_with_gas_supplemental
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, SYS3_ASHP, zones, namer: :necb_pipe_name)

    assert_equal 1, result.air_loops.size, 'NECB shared-unit convention'
    # ASHP DX coils with the load-bearing _ashp names + NECB curves
    clg = model.getCoilCoolingDXSingleSpeeds.first
    htg = model.getCoilHeatingDXSingleSpeeds.first
    assert_equal 'CoilCoolingDXSingleSpeed_ashp', clg.nameString
    assert_equal 'CoilHeatingDXSingleSpeed_ashp', htg.nameString
    assert_in_delta(-10.0, htg.minimumOutdoorDryBulbTemperatureforCompressorOperation, 1e-6)
    assert_equal 1, model.getCoilHeatingGass.size, 'gas supplemental coil on the loop'
    # DX sizing factors 1.0/1.3
    sz = zones.first.sizingZone
    assert_equal 1.0, sz.zoneCoolingSizingFactor.get
    assert_equal 1.3, sz.zoneHeatingSizingFactor.get
    # legacy naming: sc>ashp + sh>ashp>c-g
    assert_equal 'sys_3|mixed|shr>none|sc>ashp|sh>ashp>c-g|ssf>cv|zh>b-e|zc>none|srf>none|',
                 result.air_loops.first.nameString
  end

  def test_sys4_ashp_electric_supp_hot_water_baseboards
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, SYS4_ASHP, zones)

    assert_equal 1, model.getCoilHeatingDXSingleSpeeds.size
    assert_equal 1, model.getCoilHeatingElectrics.size, 'electric supplemental'
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert_equal 2, model.getBoilerHotWaters.size
  end

  def test_sys1_ashp_mau_with_cav_reheat_terminals
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, SYS1_ASHP, zones, namer: :necb_pipe_name)

    air_loop = result.air_loops.first
    # MAU: ASHP DX heat/cool, warmest SPM 13-20, Total load sizing
    assert_equal 1, model.getCoilHeatingDXSingleSpeeds.size
    spms = model.getSetpointManagerWarmests
    assert_equal 1, spms.size
    assert_in_delta 20.0, spms.first.maximumSetpointTemperature, 1e-6
    assert_equal 'Total', air_loop.sizingSystem.typeofLoadtoSizeOn

    # zones: CAV reheat terminals with gas reheat (fuel from the name), NO PTACs
    terminals = model.getAirTerminalSingleDuctConstantVolumeReheats
    assert_equal zones.size, terminals.size
    assert_equal zones.size, model.getCoilHeatingGass.size, 'gas reheat coil per terminal'
    assert_empty model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size

    # legacy naming: sys_oa 'mixed' for the ref-HP variant, zc>none
    assert_equal 'sys_1|mixed|shr>none|sc>ashp|sh>ashp>c-g|ssf>cv|zh>b-e|zc>none|srf>none|',
                 air_loop.nameString
  end
end
