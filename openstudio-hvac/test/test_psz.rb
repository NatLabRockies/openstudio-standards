require_relative 'test_helper'

class TestPSZ < Minitest::Test
  include FixtureHelper

  ELECTRIC = 'PSZ RTU Electric and DX Coils and Electric Baseboard'.freeze
  GAS_HW   = 'PSZ RTU Gas and DX Coils and Hot Water Baseboard'.freeze
  SYS4     = 'PSZ RTU with exhaust Gas and DX Coils and Electric Baseboard'.freeze

  def test_electric_psz_builds_on_bare_zones
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, ELECTRIC, zones)

    assert_equal 1, result.air_loops.size
    air_loop = result.air_loops.first
    assert_equal 1, model.getAirLoopHVACs.size
    assert_equal zones.size, air_loop.thermalZones.size

    # topology: CV fan + electric coil + DX coil + OA system + SZR setpoint manager
    assert_equal 1, model.getFanConstantVolumes.size
    assert_equal 1, model.getCoilHeatingElectrics.size
    assert_equal 1, model.getCoilCoolingDXSingleSpeeds.size
    assert_equal 1, model.getAirLoopHVACOutdoorAirSystems.size
    spms = model.getSetpointManagerSingleZoneReheats
    assert_equal 1, spms.size
    assert_equal 13.0, spms.first.minimumSupplyAirTemperature
    assert_equal 43.0, spms.first.maximumSupplyAirTemperature
    assert_equal result.control_zone.handle.to_s, spms.first.controlZone.get.handle.to_s

    # zone equipment: one electric baseboard + one uncontrolled diffuser per zone
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    assert_equal zones.size, model.getAirTerminalSingleDuctUncontrolleds.size
    assert_empty model.getBoilerHotWaters, 'all-electric system must not create a boiler'

    # NECB curves on the DX coil
    coil = model.getCoilCoolingDXSingleSpeeds.first
    assert_equal 'DXCOOL-NECB2011-REF-CAPFT', coil.totalCoolingCapacityFunctionOfTemperatureCurve.nameString
    assert_equal 'CoilCoolingDXSingleSpeed_dx', coil.nameString
  end

  def test_zone_and_system_sizing_applied
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, ELECTRIC, zones)

    s = result.air_loops.first.sizingSystem
    assert_equal 13.0, s.centralCoolingDesignSupplyAirTemperature
    assert_equal 43.0, s.centralHeatingDesignSupplyAirTemperature
    assert_equal 'ZoneSum', s.systemOutdoorAirMethod
    refute s.allOutdoorAirinCooling

    zones.each do |zone|
      sz = zone.sizingZone
      assert_equal 'TemperatureDifference', sz.zoneCoolingDesignSupplyAirTemperatureInputMethod
      assert_equal 11.0, sz.zoneCoolingDesignSupplyAirTemperatureDifference
      assert_equal 21.0, sz.zoneHeatingDesignSupplyAirTemperatureDifference
      assert_equal 1.1, sz.zoneCoolingSizingFactor.get
      assert_equal 1.3, sz.zoneHeatingSizingFactor.get
    end

    oa = model.getControllerOutdoorAirs.first
    assert_equal 'ZoneSum', oa.controllerMechanicalVentilation.systemOutdoorAirMethod
  end

  def test_gas_hot_water_builds_and_reuses_hw_loop
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, GAS_HW, zones)

    assert_equal 1, model.getCoilHeatingGass.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveWaters.size
    assert_equal 2, model.getBoilerHotWaters.size, 'primary + secondary boiler'
    assert_equal %w[Primary\ Boiler Secondary\ Boiler].sort, model.getBoilerHotWaters.map(&:nameString).sort
    assert_equal 1, model.getPlantLoops.size

    # second hydronic system on other zones reuses the loop (no boiler proliferation)
    OpenStudioHVAC.build_system(model, GAS_HW, [zones.first], control_zone: zones.first, remove_existing: true)
    assert_equal 2, model.getBoilerHotWaters.size
    assert_equal 1, model.getPlantLoops.size
  end

  def test_sys4_control_zone_and_pipe_naming
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, SYS4, zones,
                                         control_zone: zones[2], namer: :necb_pipe_name)
    assert_equal zones[2], result.control_zone
    assert_equal 'sys_4|mixed|shr>none|sc>dx|sh>c-g|ssf>cv|zh>b-e|zc>none|srf>none|',
                 result.air_loops.first.nameString
  end

  def test_remove_existing_replaces
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, GAS_HW, zones)
    refute_empty model.getBoilerHotWaters

    OpenStudioHVAC.build_system(model, ELECTRIC, zones, remove_existing: true)
    assert_empty model.getBoilerHotWaters, 'orphaned boiler loop torn down'
    assert_equal 1, model.getAirLoopHVACs.size
    assert_equal zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size
    assert_empty model.getZoneHVACBaseboardConvectiveWaters
  end

  def test_validation_errors
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)

    outsider = OpenStudio::Model::ThermalZone.new(model)
    err = assert_raises(ArgumentError) do
      OpenStudioHVAC.build_system(model, ELECTRIC, zones, control_zone: outsider)
    end
    assert_match(/control_zone/, err.message)
    outsider.remove

    model.getThermostatSetpointDualSetpoints.each(&:remove)
    err = assert_raises(ArgumentError) do
      OpenStudioHVAC.build_system(model, ELECTRIC, model.getThermalZones.to_a)
    end
    assert_match(/thermostat/, err.message)
  end
end
