require_relative '../helpers/minitest_helper'

class TestVAVTerminalMinimumFlow < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
  end

  def make_terminal(model)
    schedule = model.alwaysOnDiscreteSchedule
    coil = OpenStudio::Model::CoilHeatingElectric.new(model, schedule)
    OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, schedule, coil)
  end

  def test_damper_fraction_governs_when_larger_than_the_oa_floor
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(1.0)

    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal, 0.1)
    assert_equal('Constant', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.3, terminal.constantMinimumAirFlowFraction.get, 0.001)
    assert_in_delta(0.1, terminal.fixedMinimumAirFlowRate.get, 0.001)
  end

  def test_oa_floor_governs_when_larger_than_the_damper_fraction
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(1.0)

    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal, 0.5)
    assert_equal('FixedFlowRate', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.5, terminal.fixedMinimumAirFlowRate.get, 0.001)
  end

  def test_oa_floor_wins_the_method_when_the_design_flow_is_unknown
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)

    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal, 0.2)
    assert_equal('FixedFlowRate', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.2, terminal.fixedMinimumAirFlowRate.get, 0.001)
  end

  def test_no_oa_floor_keeps_the_constant_method
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal)
    assert_equal('Constant', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.3, terminal.constantMinimumAirFlowFraction.get, 0.001)
  end

  def test_raised_minimum_reaches_a_fixed_flow_rate_terminal
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(2.0)
    zone = OpenStudio::Model::ThermalZone.new(model)
    loop = OpenStudio::Model::AirLoopHVAC.new(model)
    loop.addBranchForZone(zone, terminal.to_StraightComponent)

    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal, 1.0)
    assert_equal('FixedFlowRate', terminal.zoneMinimumAirFlowInputMethod)
    @std.air_loop_hvac_set_minimum_damper_position(zone, 0.6)
    assert_equal('FixedFlowRate', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(1.2, terminal.fixedMinimumAirFlowRate.get, 0.001)
  end

  def test_raised_minimum_reaches_a_constant_terminal_as_a_fraction
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(2.0)
    zone = OpenStudio::Model::ThermalZone.new(model)
    loop = OpenStudio::Model::AirLoopHVAC.new(model)
    loop.addBranchForZone(zone, terminal.to_StraightComponent)

    @std.air_loop_hvac_set_minimum_damper_position(zone, 0.45)
    assert_equal('Constant', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.45, terminal.constantMinimumAirFlowFraction.get, 0.001)
  end
end
