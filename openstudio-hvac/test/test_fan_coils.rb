require_relative 'test_helper'

class TestFanCoils < Minitest::Test
  include FixtureHelper

  FPFC_DX  = 'FPFC MAU DX Coils with Scroll Chiller'.freeze
  FPFC_CHW = 'FPFC MAU Chilled Water Coils with Centrifugal Chiller'.freeze
  TPFC_DX  = 'TPFC MAU DX Coils with Scroll Chiller'.freeze

  def test_fpfc_dx_builds_mau_fan_coils_and_full_plant
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    result = OpenStudioHVAC.build_system(model, FPFC_DX, zones)

    # one MAU air loop delivering to all zones through uncontrolled diffusers
    assert_equal 1, result.air_loops.size
    assert_equal zones.size, result.air_loops.first.thermalZones.size
    assert_equal zones.size, model.getAirTerminalSingleDuctUncontrolleds.size

    # per-zone four-pipe fan coils with hydronic coils on both loops
    assert_equal zones.size, model.getZoneHVACFourPipeFanCoils.size
    assert_equal zones.size, model.getCoilHeatingWaters.size
    assert_equal zones.size, model.getCoilCoolingWaters.size, 'FC cooling coils only (MAU is DX)'

    # MAU: CV fan + gas heat + DX cooling with NECB curves on the seasonal cooling schedule
    assert_equal 1 + zones.size, model.getFanConstantVolumes.size, 'MAU fan + one per fan coil'
    assert_equal 1, model.getCoilHeatingGass.size
    dx = model.getCoilCoolingDXSingleSpeeds.first
    refute_nil dx
    assert_equal 'tpfc_clg_availability', dx.availabilitySchedule.nameString, 'legacy quirk preserved'

    # full plant: HW + CHW + CW
    assert_equal 3, model.getPlantLoops.size
    assert_equal 2, model.getBoilerHotWaters.size
    assert_equal 2, model.getChillerElectricEIRs.size
    assert_equal 1, model.getCoolingTowerSingleSpeeds.size

    # MAU SPM preserved legacy min/max (13.1 / 13.0 inverted)
    spm = model.getSetpointManagerSingleZoneReheats.first
    assert_in_delta 13.1, spm.minimumSupplyAirTemperature, 1e-6
    assert_in_delta 13.0, spm.maximumSupplyAirTemperature, 1e-6
  end

  def test_tpfc_uses_seasonal_availability_schedules
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, TPFC_DX, zones)

    fc = model.getZoneHVACFourPipeFanCoils.first
    assert_equal 'tpfc_htg_availability', fc.heatingCoil.to_CoilHeatingWater.get.availabilitySchedule.nameString
    assert_equal 'tpfc_clg_availability', fc.coolingCoil.to_CoilCoolingWater.get.availabilitySchedule.nameString
  end

  def test_hydronic_mau_cooling_coil_on_chw_loop
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, FPFC_CHW, zones)

    assert_empty model.getCoilCoolingDXSingleSpeeds, 'hydronic MAU: no DX'
    assert_equal zones.size + 1, model.getCoilCoolingWaters.size, 'FC coils + MAU coil'
    assert(model.getChillerElectricEIRs.all? { |c| c.nameString.include?('Centrifugal') })
  end

  def test_pipe_names_match_legacy_convention
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    r1 = OpenStudioHVAC.build_system(model, FPFC_DX, zones, namer: :necb_pipe_name)
    assert_equal 'sys_2|doas|shr>none|sc>dx|sh>c-g|ssf>cv|zh>fpfc|zc>fpfc|srf>none|',
                 r1.air_loops.first.nameString

    m2 = load_fixture
    z2 = m2.getThermalZones.sort_by(&:nameString)
    r2 = OpenStudioHVAC.build_system(m2, TPFC_DX, z2, namer: :necb_pipe_name)
    assert_equal 'sys_5|doas|shr>none|sc>dx|sh>c-g|ssf>cv|zh>tpfc|zc>tpfc|srf>none|',
                 r2.air_loops.first.nameString
  end

  def test_remove_existing_tears_down_fan_coil_plant
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, FPFC_DX, zones)
    assert_equal 3, model.getPlantLoops.size

    OpenStudioHVAC.build_system(model, 'PSZ RTU Electric and DX Coils and Electric Baseboard',
                                zones, remove_existing: true)
    assert_empty model.getPlantLoops, 'HW + CHW + CW all reclaimed'
    assert_empty model.getZoneHVACFourPipeFanCoils
    assert_equal 1, model.getAirLoopHVACs.size
  end
end
