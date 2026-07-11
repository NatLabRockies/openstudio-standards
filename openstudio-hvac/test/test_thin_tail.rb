require_relative 'test_helper'

# The final thin tail: VRF names, zone ERVs, GSHP/cooling-tower WSHP variants, and the
# air-cooled/district chilled-water fan-coil composite matrix.
class TestThinTail < Minitest::Test
  include FixtureHelper

  def test_standalone_vrf_self_ventilates
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'VRF', zones)

    assert_equal 1, model.getAirConditionerVariableRefrigerantFlows.size
    terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert_equal zones.size, terminals.size
    assert terminals.first.isOutdoorAirFlowRateDuringCoolingOperationAutosized,
           'standalone VRF terminals ventilate (autosized OA)'
    assert_empty model.getAirLoopHVACs
  end

  def test_doas_with_vrf_zeroes_terminal_oa
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'DOAS with VRF', zones)

    assert_equal 1, result.air_loops.size, 'the DOAS'
    terminal = model.getZoneHVACTerminalUnitVariableRefrigerantFlows.first
    assert_in_delta 1.0e-6, terminal.outdoorAirFlowRateDuringCoolingOperation.get, 1e-10,
                    'DOAS ventilates; terminal OA ~zero'
  end

  def test_gshp_variant_ground_hx_no_boiler
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'DOAS with water source heat pumps with ground source heat pump', zones)

    assert_equal 1, model.getGroundHeatExchangerVerticals.size
    assert_empty model.getBoilerHotWaters, 'GSHP loop has no boiler'
    assert_equal zones.size, model.getZoneHVACWaterToAirHeatPumps.size
  end

  def test_cooling_tower_wshp_variant
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'DOAS with water source heat pumps cooling tower with boiler', zones)

    assert_equal 1, model.getCoolingTowerSingleSpeeds.size
    assert_empty model.getEvaporativeFluidCoolerSingleSpeeds
    assert_equal 1, model.getBoilerHotWaters.size
  end

  def test_fan_coil_air_cooled_chiller_district_hot_water
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'DOAS with fan coil air-cooled chiller with district hot water', zones)

    chillers = model.getChillerElectricEIRs
    assert_equal 1, chillers.size, 'single air-cooled chiller'
    assert_equal 'AirCooled', chillers.first.condenserType
    assert_empty model.getCoolingTowerSingleSpeeds, 'no condenser loop for air-cooled'
    assert_empty model.getBoilerHotWaters, 'district hot water, no boilers'
    districts = model.getDistrictHeatingWaters.size
    assert_operator districts, :>=, 1
    assert_equal zones.size, model.getZoneHVACFourPipeFanCoils.size
  end

  def test_fan_coil_district_chilled_water
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'DOAS with fan coil district chilled water with boiler', zones)

    assert_empty model.getChillerElectricEIRs
    assert_equal 1, model.getDistrictCoolings.size
    assert_equal 2, model.getBoilerHotWaters.size
  end

  def test_zone_ervs
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Zone ERVs', zones)

    ervs = model.getZoneHVACEnergyRecoveryVentilators
    assert_equal zones.size, ervs.size
    assert_equal zones.size, model.getHeatExchangerAirToAirSensibleAndLatents.size
  end
end
