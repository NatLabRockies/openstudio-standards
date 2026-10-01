require_relative '../../helpers/minitest_helper'

# The sizing inputs that decide how much heating airflow a VAV system's central coil is
# sized on, and how much air its terminals pass at minimum.
class TestVAVSizingInputs < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
  end

  def build_zones(model, count)
    (0...count).map do |i|
      polygon = OpenStudio::Point3dVector.new
      [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| polygon << OpenStudio::Point3d.new(x + (i * 20), y, 0) }
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space.setName("Space #{i}")
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i}")
      space.setThermalZone(zone)
      zone
    end
  end

  def set_air_changes_outdoor_air(zone, ach)
    space = zone.spaces.first
    dsoa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space.model)
    dsoa.setOutdoorAirMethod('AirChanges/Hour')
    dsoa.setOutdoorAirFlowAirChangesperHour(ach)
    space.setDesignSpecificationOutdoorAir(dsoa)
  end

  def terminal_of(zone)
    zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.get
  end

  def test_vav_systems_autosize_the_central_heating_airflow_ratio
    model = OpenStudio::Model::Model.new
    loops = [
      @std.model_add_vav_reheat(model, build_zones(model, 2), heating_type: 'Electricity', reheat_type: 'Electricity'),
      @std.model_add_pvav(model, build_zones(model, 2), electric_reheat: true),
      @std.model_add_pvav_pfp_boxes(model, build_zones(model, 2))
    ]
    loops.each do |loop|
      assert(loop.sizingSystem.isCentralHeatingMaximumSystemAirFlowRatioAutosized, "#{loop.name} should autosize its central heating maximum system air flow ratio")
    end
  end

  def test_a_pinned_ratio_is_kept
    model = OpenStudio::Model::Model.new
    loop = @std.model_add_vav_reheat(model, build_zones(model, 2), heating_type: 'Electricity', reheat_type: 'Electricity', min_sys_airflow_ratio: 0.3)
    refute(loop.sizingSystem.isCentralHeatingMaximumSystemAirFlowRatioAutosized)
    assert_in_delta(0.3, loop.sizingSystem.centralHeatingMaximumSystemAirFlowRatio.get, 1e-9)

    pvav = @std.model_add_pvav(model, build_zones(model, 2), electric_reheat: true, min_sys_airflow_ratio: 0.3)
    assert_in_delta(0.3, pvav.sizingSystem.centralHeatingMaximumSystemAirFlowRatio.get, 1e-9)
  end

  def test_terminal_minimums_rise_to_the_zone_outdoor_air
    model = OpenStudio::Model::Model.new
    zones = build_zones(model, 3)
    set_air_changes_outdoor_air(zones[0], 6.0) # 300 m3 x 6 / 3600 = 0.5 m3/s
    set_air_changes_outdoor_air(zones[1], 6.0)
    loop = @std.model_add_pvav(model, zones, electric_reheat: true)
    terminal_of(zones[0]).setMaximumAirFlowRate(1.0)
    terminal_of(zones[1]).setMaximumAirFlowRate(0.4) # outdoor air exceeds the maximum
    terminal_of(zones[2]).setMaximumAirFlowRate(1.0) # no outdoor air requirement
    before = terminal_of(zones[2]).constantMinimumAirFlowFraction.get

    assert_equal(2, @std.air_loop_hvac_apply_vav_terminal_minimum_outdoor_air(loop))
    assert_in_delta(0.5, terminal_of(zones[0]).constantMinimumAirFlowFraction.get, 1e-6)
    assert_in_delta(1.0, terminal_of(zones[1]).constantMinimumAirFlowFraction.get, 1e-6)
    assert_in_delta(before, terminal_of(zones[2]).constantMinimumAirFlowFraction.get, 1e-9)
    zones.each { |zone| assert_equal('Constant', terminal_of(zone).zoneMinimumAirFlowInputMethod.to_s) }

    # a second pass changes nothing
    assert_equal(0, @std.model_apply_vav_terminal_minimum_outdoor_air(model))
  end

  def test_a_fixed_minimum_flow_rate_rises_to_the_zone_outdoor_air
    model = OpenStudio::Model::Model.new
    zones = build_zones(model, 1)
    set_air_changes_outdoor_air(zones[0], 6.0)
    loop = @std.model_add_pvav(model, zones, electric_reheat: true)
    terminal = terminal_of(zones[0])
    terminal.setZoneMinimumAirFlowInputMethod('FixedFlowRate')
    terminal.setFixedMinimumAirFlowRate(0.1)

    assert_equal(1, @std.air_loop_hvac_apply_vav_terminal_minimum_outdoor_air(loop))
    assert_in_delta(0.5, terminal.fixedMinimumAirFlowRate.get, 1e-6)
    assert_equal('FixedFlowRate', terminal.zoneMinimumAirFlowInputMethod.to_s)
  end

  def test_an_unsized_terminal_is_left_alone
    model = OpenStudio::Model::Model.new
    zones = build_zones(model, 1)
    set_air_changes_outdoor_air(zones[0], 6.0)
    loop = @std.model_add_pvav(model, zones, electric_reheat: true)
    before = terminal_of(zones[0]).constantMinimumAirFlowFraction.get

    assert_equal(0, @std.air_loop_hvac_apply_vav_terminal_minimum_outdoor_air(loop))
    assert_in_delta(before, terminal_of(zones[0]).constantMinimumAirFlowFraction.get, 1e-9)
  end
end
