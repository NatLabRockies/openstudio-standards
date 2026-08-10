require_relative 'test_helper'

class TestHpPlantFanCoils < Minitest::Test
  include FixtureHelper

  def test_hs14_gshp_plants_and_fancoils
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'hs14_cgshp_fancoils', zones, namer: :necb_pipe_name)

    # zone side: 4-pipe fan coils + diffusers
    assert_equal zones.size, model.getZoneHVACFourPipeFanCoils.size
    assert_equal zones.size, model.getAirTerminalSingleDuctUncontrolleds.size

    # HW plant: W2W equation-fit HP with structural curves + electric boiler in series
    hps = model.getHeatPumpWaterToWaterEquationFitHeatings
    assert_equal 1, hps.size
    assert_equal 'HEATPUMP_WATERTOWATER_HCAPF', hps.first.heatingCapacityCurve.nameString
    assert_equal 1, model.getBoilerHotWaters.size

    # CHW plant: water-cooled + series air-cooled chillers
    chillers = model.getChillerElectricEIRs
    assert_equal %w[ChillerAirCooled ChillerWaterCooled], chillers.map(&:nameString).sort

    # GLHX condenser loop: district heating + cooling in series, HP + chiller on demand
    glhx = model.getPlantLoops.find { |pl| pl.nameString.include?('GLHX') }
    refute_nil glhx
    assert_equal 1, model.getDistrictCoolings.size
    demand_types = glhx.demandComponents.map { |c| c.iddObjectType.valueName }
    assert(demand_types.any? { |t| t.include?('HeatPump') })
    assert(demand_types.any? { |t| t.include?('Chiller') })
    assert_equal 3, model.getPlantLoops.size, 'HW + CHW + GLHX'

    # all water coils (air loop + fan coils) attached to the HP plants
    assert(model.getCoilHeatingWaters.all? { |c| c.plantLoop.is_initialized })
    assert(model.getCoilCoolingWaters.all? { |c| c.plantLoop.is_initialized })

    # legacy naming (coil_chw segment dropped by the namer; sh>none for coil_hw; raw fancoil tokens)
    assert_equal 'sys_1|doas|shr>none|sh>none|ssf>cv|zh>fancoil_4pipe|zc>fancoil_4pipe|srf>none|',
                 result.air_loops.first.nameString
  end

  def test_hs15_cawhp_companion_heat_pumps
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'hs15_cawhp_fancoils', zones)

    htg_hps = model.getHeatPumpPlantLoopEIRHeatings
    clg_hps = model.getHeatPumpPlantLoopEIRCoolings
    assert_equal 1, htg_hps.size
    assert_equal 1, clg_hps.size
    hp = htg_hps.first
    assert_equal 'AirSource', hp.condenserType, "condenser type correct (legacy 'AirSoure' typo, fixed both sides since #2119)"
    assert_in_delta(-15.0, hp.minimumSourceInletTemperature, 1e-6)
    assert hp.companionCoolingHeatPump.is_initialized
    assert_equal 'CAWHP-HS15-HCAPFT', hp.capacityModifierFunctionofTemperatureCurve.nameString
    assert_equal 1, model.getBoilerHotWaters.size
    assert_equal 2, model.getPlantLoops.size, 'HW + CHW (no ground loop)'
    assert_empty model.getChillerElectricEIRs
  end

  def test_hs16_uses_ashp_doas
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'hs16_ashp_cawhp_fancoils', zones)

    assert_equal 1, model.getCoilCoolingDXSingleSpeeds.count { |c| c.nameString.include?('ASHP') }
    assert_equal 1, model.getCoilHeatingDXSingleSpeeds.count { |c| c.nameString.include?('ASHP') }
    # supplemental electric coil on the DOAS + CAWHP plants below
    assert_equal 1, model.getHeatPumpPlantLoopEIRHeatings.size
    # fan-coil water coils go to the CAWHP plants (air loop uses DX, so counts = zones)
    assert_equal zones.size, model.getCoilHeatingWaters.size
    assert(model.getCoilHeatingWaters.all? { |c| c.plantLoop.is_initialized })
  end
end
