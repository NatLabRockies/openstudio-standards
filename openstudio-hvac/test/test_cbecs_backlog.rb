require_relative 'test_helper'

# Final CBECS tranche: furnace/central AC, district hot water, PVAV, evap coolers,
# WSHP, and the DOAS composites.
class TestCbecsBacklog < Minitest::Test
  include FixtureHelper

  def test_forced_air_furnace
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'Forced air furnace', zones)

    assert_equal zones.size, result.air_loops.size, 'one furnace loop per zone'
    assert_equal zones.size, model.getCoilHeatingGass.size
    assert_empty model.getCoilCoolingDXSingleSpeeds, 'heating only'
    assert_equal zones.size, model.getAirLoopHVACOutdoorAirSystems.size, 'ventilating'
  end

  def test_residential_ac_composite
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'Residential AC with baseboard electric', zones)

    assert_equal 'composite', result.family
    assert_equal zones.size, result.air_loops.size
    assert_equal zones.size, model.getCoilCoolingDXSingleSpeeds.size
    assert_empty model.getCoilHeatingGass, 'cooling-only central AC'
    assert_empty model.getAirLoopHVACOutdoorAirSystems, 'no OA on residential AC'
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
  end

  def test_baseboard_district_hot_water
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard district hot water', zones)

    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert_empty model.getBoilerHotWaters, 'district source, no boilers'
    districts = model.getDistrictHeatingWaters.size + (model.respond_to?(:getDistrictHeatings) ? model.getDistrictHeatings.size : 0)
    assert_operator districts, :>=, 1
  end

  def test_pvav_dx_cooling
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PVAV with gas boiler reheat', zones)

    assert_equal 1, model.getCoilCoolingDXTwoSpeeds.size, 'packaged DX cooling'
    assert_empty model.getChillerElectricEIRs, 'no chiller plant'
    assert_equal zones.size, model.getAirTerminalSingleDuctVAVReheats.size
    assert_equal 1 + zones.size, model.getCoilHeatingWaters.size, 'HW main + reheat from gas boiler'
    assert(model.getBoilerHotWaters.all? { |b| b.fuelType == 'NaturalGas' })
  end

  def test_direct_evap_coolers_with_baseboards
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Direct evap coolers with baseboard electric', zones)

    assert_equal zones.size, model.getEvaporativeCoolerDirectResearchSpecials.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    spms = model.getSetpointManagerFollowOutdoorAirTemperatures
    assert_equal zones.size, spms.size
    assert_equal 'OutdoorAirWetBulb', spms.first.referenceTemperatureType
  end

  def test_doas_with_wshp_composite
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'DOAS with water source heat pumps fluid cooler with boiler', zones)

    # DOAS half
    assert_equal 1, result.air_loops.size
    assert_equal zones.size, model.getAirTerminalSingleDuctUncontrolleds.size
    # WSHP half: per-zone units on the heat pump loop
    wshps = model.getZoneHVACWaterToAirHeatPumps
    assert_equal zones.size, wshps.size
    hp_loop = model.getPlantLoops.find { |pl| pl.nameString == 'Heat Pump Loop' }
    refute_nil hp_loop
    assert_equal 1, model.getEvaporativeFluidCoolerSingleSpeeds.size
    assert_equal 1, model.getBoilerHotWaters.size
    assert_equal zones.size, model.getCoilHeatingWaterToAirHeatPumpEquationFits.size
    assert(model.getCoilHeatingWaterToAirHeatPumpEquationFits.all? { |c| c.plantLoop.is_initialized })
  end

  def test_doas_with_fan_coils_composite
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'DOAS with fan coil chiller with boiler', zones)

    # exactly ONE air loop (the DOAS) — the fan-coil part must not build its MAU
    assert_equal 1, result.air_loops.size
    assert_equal 1, model.getAirLoopHVACs.size
    assert_equal zones.size, model.getZoneHVACFourPipeFanCoils.size
    # full hydronic plant from the fan-coil part
    assert_equal 2, model.getChillerElectricEIRs.size
    assert_equal 2, model.getBoilerHotWaters.size
    assert_equal 1, model.getCoolingTowerSingleSpeeds.size
  end
end
