require_relative 'test_helper'

class TestMauPtac < Minitest::Test
  include FixtureHelper

  ELEC = 'PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC'.freeze
  HW   = 'PSZ MAU Hot Water and DX Coils and Hot Water Baseboard with PTAC'.freeze

  def test_electric_mau_ptac_builds
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, ELEC, zones)

    # one 100% OA MAU + per-zone PTAC + baseboards + diffusers
    assert_equal 1, result.air_loops.size
    air_loop = result.air_loops.first
    assert_equal zones.size, air_loop.thermalZones.size
    assert_equal zones.size, model.getZoneHVACPackagedTerminalAirConditioners.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    assert_equal zones.size, model.getAirTerminalSingleDuctUncontrolleds.size
    assert_equal zones.size + 1, model.getCoilCoolingDXSingleSpeeds.size, 'MAU DX + one per PTAC'
    assert_empty model.getBoilerHotWaters

    # MAU sizing: 100% OA on ventilation requirement, 20C constant supply
    s = air_loop.sizingSystem
    assert s.allOutdoorAirinCooling
    assert s.allOutdoorAirinHeating
    assert_equal 'VentilationRequirement', s.typeofLoadtoSizeOn
    assert_equal 43.0, s.centralHeatingDesignSupplyAirTemperature
    sat = model.getScheduleRulesets.find { |sch| sch.nameString == 'Makeup-Air Unit Supply Air Temp' }
    refute_nil sat

    # PTAC details: always-off heating section + fan op schedule, ~zero OA
    ptac = model.getZoneHVACPackagedTerminalAirConditioners.first
    fan_op_sch = ptac.supplyAirFanOperatingModeSchedule
    fan_op_sch = fan_op_sch.get if fan_op_sch.respond_to?(:get)
    assert_equal 'Always Off', fan_op_sch.nameString
    assert_equal 'Always Off', ptac.heatingCoil.to_CoilHeatingElectric.get.availabilitySchedule.nameString
    assert_in_delta 1.0e-5, ptac.outdoorAirFlowRateDuringCoolingOperation.get, 1e-9
  end

  def test_hot_water_variant_builds_boiler_for_mau_and_baseboards
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, HW, zones)

    assert_equal 2, model.getBoilerHotWaters.size
    assert_equal 1, model.getCoilHeatingWaters.size, 'MAU hot-water coil'
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
  end

  def test_pipe_name_matches_legacy_convention
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, ELEC, zones, namer: :necb_pipe_name)
    assert_equal 'sys_1|doas|shr>none|sc>dx|sh>c-e|ssf>cv|zh>b-e|zc>ptac|srf>none|',
                 result.air_loops.first.nameString
  end
end
