require_relative 'test_helper'

class TestZoneTerminal < Minitest::Test
  include FixtureHelper

  def test_ptac_with_baseboard_electric
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'PTAC with baseboard electric', zones)

    assert_empty result.air_loops, 'self-ventilating: no central air system'
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal zones.size, ptacs.size
    # no-heat PTAC: always-off zero-capacity electric section (baseboards do the heating)
    ptacs.each do |ptac|
      coil = ptac.heatingCoil.to_CoilHeatingElectric.get
      assert_equal 0.0, coil.nominalCapacity.get
      assert_includes coil.availabilitySchedule.nameString, 'Off'
    end
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    assert_empty model.getBoilerHotWaters
  end

  def test_ptac_with_baseboard_gas_boiler
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PTAC with baseboard gas boiler', zones)

    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert_equal 2, model.getBoilerHotWaters.size
    assert(model.getBoilerHotWaters.all? { |b| b.fuelType == 'NaturalGas' })
  end

  def test_pthp
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PTHP', zones)

    pthps = model.getZoneHVACPackagedTerminalHeatPumps
    assert_equal zones.size, pthps.size
    pthps.each do |pthp|
      assert pthp.heatingCoil.to_CoilHeatingDXSingleSpeed.is_initialized
      assert pthp.supplementalHeatingCoil.to_CoilHeatingElectric.is_initialized
    end
  end

  def test_window_ac
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Window AC with baseboard electric', zones)

    acs = model.getZoneHVACPackagedTerminalAirConditioners
    assert_equal zones.size, acs.size
    coil = acs.first.coolingCoil.to_CoilCoolingDXSingleSpeed.get
    cop = coil.ratedCOP.respond_to?(:is_initialized) ? coil.ratedCOP.get : coil.ratedCOP
    assert_in_delta 2.49, cop, 0.01, 'EER 8.5 -> COP ~2.49'
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
  end

  def test_unit_heaters
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Gas unit heaters', zones)

    heaters = model.getZoneHVACUnitHeaters
    assert_equal zones.size, heaters.size
    assert_equal zones.size, model.getCoilHeatingGass.size
  end

  def test_composite_psz_gas_boiler
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, 'PSZ-AC with gas boiler', zones)

    assert_equal zones.size, result.air_loops.size, 'per-zone packaged units'
    assert_equal zones.size, model.getCoilHeatingWaters.size, 'hot-water coils on each unit'
    assert_equal 2, model.getBoilerHotWaters.size
    assert(model.getBoilerHotWaters.all? { |b| b.fuelType == 'NaturalGas' })
  end

  def test_composite_vav_chiller_gas_boiler_reheat
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'VAV chiller with gas boiler reheat', zones)

    assert_equal zones.size, model.getAirTerminalSingleDuctVAVReheats.size
    assert_equal 1 + zones.size, model.getCoilHeatingWaters.size, 'main + reheat coils'
    refute_empty model.getChillerElectricEIRs
    assert(model.getBoilerHotWaters.all? { |b| b.fuelType == 'NaturalGas' })
  end
end
