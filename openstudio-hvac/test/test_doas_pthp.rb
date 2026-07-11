require_relative 'test_helper'

class TestDoasPthp < Minitest::Test
  include FixtureHelper

  HS11 = 'hs11_ashp_pthp'.freeze

  def test_hs11_builds_doas_and_zone_pthps
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, HS11, zones)

    # one DOAS loop serving all zones through uncontrolled diffusers
    assert_equal 1, result.air_loops.size
    air_loop = result.air_loops.first
    assert_equal zones.size, air_loop.thermalZones.size
    assert_equal zones.size, model.getAirTerminalSingleDuctUncontrolleds.size

    # DOAS sizing: 100% OA on ventilation requirement, 13/22 SATs
    s = air_loop.sizingSystem
    assert s.allOutdoorAirinCooling
    assert s.allOutdoorAirinHeating
    assert_equal 'VentilationRequirement', s.typeofLoadtoSizeOn
    assert_equal 22.0, s.centralHeatingDesignSupplyAirTemperature

    # air-loop ASHP: DX heat + DX cool + electric supplemental + CV supply fan
    assert_equal 1, model.getCoilCoolingDXSingleSpeeds.count { |c| c.nameString.include?('ASHP') }
    assert_equal 1, model.getCoilHeatingDXSingleSpeeds.count { |c| c.nameString.include?('ASHP') }
    ashp_htg = model.getCoilHeatingDXSingleSpeeds.find { |c| c.nameString.include?('ASHP') }
    assert_equal 'ReverseCycle', ashp_htg.defrostStrategy
    assert(model.getFanConstantVolumes.any? { |f| f.nameString.include?('Supply') })

    # per-zone PTHPs with DX coils + electric supplemental, ~zero OA
    pthps = model.getZoneHVACPackagedTerminalHeatPumps
    assert_equal zones.size, pthps.size
    pthps.each do |pthp|
      assert pthp.heatingCoil.to_CoilHeatingDXSingleSpeed.is_initialized
      assert pthp.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized
      assert pthp.supplementalHeatingCoil.to_CoilHeatingElectric.is_initialized
      assert_in_delta 1.0e-6, pthp.outdoorAirFlowRateDuringCoolingOperation.get, 1e-10
    end

    # ECM zone sizing: ABSOLUTE supply temps (not TemperatureDifference)
    sz = zones.first.sizingZone
    assert_equal 'SupplyAirTemperature', sz.zoneCoolingDesignSupplyAirTemperatureInputMethod
    assert_equal 13.0, sz.zoneCoolingDesignSupplyAirTemperature
    assert_equal 43.0, sz.zoneHeatingDesignSupplyAirTemperature

    assert_empty model.getPlantLoops, 'electric supplemental: no boiler'
  end

  def test_hs11_pipe_name_matches_legacy_format
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, HS11, zones, namer: :necb_pipe_name)
    assert_equal 'sys_1|doas|shr>none|sc>ashp|sh>ashp|ssf>cv|zh>pthp|zc>pthp|srf>none|',
                 result.air_loops.first.nameString
  end
end
