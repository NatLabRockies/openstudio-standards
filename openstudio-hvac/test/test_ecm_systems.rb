require_relative 'test_helper'

class TestEcmSystems < Minitest::Test
  include FixtureHelper

  def test_hs12_ashp_baseboard_doas
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'hs12_ashp_baseboard', zones, namer: :necb_pipe_name)

    assert_equal 1, result.air_loops.size
    # ASHP single-speed DX on the loop
    assert_equal 1, model.getCoilHeatingDXSingleSpeeds.count { |c| c.nameString.include?('ASHP') }
    # PTAC (electric-off heat section, DX cooling) + electric baseboards per zone
    assert_equal zones.size, model.getZoneHVACPackagedTerminalAirConditioners.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    assert_equal zones.size, model.getCoilCoolingDXSingleSpeeds.count { |c| c.nameString.include?('PTAC') }
    # legacy naming quirk: doas zone tokens read b-e/ptac
    assert_equal 'sys_1|doas|shr>none|sc>ashp|sh>ashp|ssf>cv|zh>b-e|zc>ptac|srf>none|',
                 result.air_loops.first.nameString
  end

  def test_hs09_ccashp_uses_variable_speed_dx
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'hs09_ccashp_baseboard', zones, namer: :necb_pipe_name)

    assert_equal 1, model.getCoilCoolingDXVariableSpeeds.size
    assert_equal 1, model.getCoilHeatingDXVariableSpeeds.size
    htg = model.getCoilHeatingDXVariableSpeeds.first
    assert_in_delta(-25.0, htg.minimumOutdoorDryBulbTemperatureforCompressorOperation, 1e-6)
    assert_includes result.air_loops.first.nameString, 'sc>ccashp'
    assert_includes result.air_loops.first.nameString, 'sh>ccashp'
  end

  def test_hs12_mixed_multizone_builds_vav
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'hs12_ashp_baseboard', zones,
                                config: { 'vent_type' => 'mixed' })

    # multizone mixed: VV supply + return fans, VAV terminals w/ electric reheat, no PTACs
    assert_equal 2, model.getFanVariableVolumes.size
    assert_equal zones.size, model.getAirTerminalSingleDuctVAVReheats.size
    assert_empty model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal 1, model.getSetpointManagerWarmests.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
  end

  def test_hs08_ccashp_vrf
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'hs08_ccashp_vrf', zones, namer: :necb_pipe_name)

    # outdoor VRF unit with hs08 settings + one terminal per zone
    units = model.getAirConditionerVariableRefrigerantFlows
    assert_equal 1, units.size
    unit = units.first
    assert unit.heatPumpWasteHeatRecovery
    assert_in_delta(-25.0, unit.minimumOutdoorTemperatureinHeatingMode, 1e-6)
    assert_equal 'ThermostatOffsetPriority', unit.masterThermostatPriorityControlType
    terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert_equal zones.size, terminals.size
    assert_equal zones.size, unit.terminals.size

    # DOAS with CCASHP variable-speed DX
    assert_equal 1, model.getCoilCoolingDXVariableSpeeds.size
    assert_equal 'sys_1|doas|shr>none|sc>ccashp|sh>ccashp|ssf>cv|zh>vrf|zc>vrf|srf>none|',
                 result.air_loops.first.nameString
  end

  def test_hs13_is_hs08_with_single_speed_dx
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'hs13_ashp_vrf', zones)

    assert_equal 1, model.getAirConditionerVariableRefrigerantFlows.size
    assert_empty model.getCoilCoolingDXVariableSpeeds, 'hs13 uses single-speed ASHP on the DOAS'
    assert_equal 1, model.getCoilCoolingDXSingleSpeeds.count { |c| c.nameString.include?('ASHP') }
  end
end
