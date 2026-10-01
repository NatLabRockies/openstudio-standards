require_relative '../helpers/minitest_helper'

# EnergyPlus enforces only the input a VAV terminal's Zone Minimum Air Flow Input Method
# selects and ignores the other with a warning; there is no larger-of-the-two behavior.
# These cover the standards code that has to pick the method so the minimum it intends is
# the one EnergyPlus reads: apply_minimum_damper_position choosing between the damper
# fraction and a supplied zone OA floor, and set_minimum_damper_position routing a raised
# minimum through whichever input the terminal's method makes live.
class TestVAVTerminalMinimumFlow < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
  end

  def make_terminal(model)
    sch = model.alwaysOnDiscreteSchedule
    coil = OpenStudio::Model::CoilHeatingElectric.new(model, sch)
    OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, sch, coil)
  end

  def test_damper_fraction_governs_when_larger_than_the_oa_floor
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(1.0)

    # 0.3 fraction on 1.0 m3/s beats a 0.1 m3/s OA floor
    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal, 0.1)
    assert_equal('Constant', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.3, terminal.constantMinimumAirFlowFraction.get, 0.001)
    assert_in_delta(0.1, terminal.fixedMinimumAirFlowRate.get, 0.001, 'the OA floor is still recorded')
  end

  def test_oa_floor_governs_when_larger_than_the_damper_fraction
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(1.0)

    # a 0.5 m3/s OA floor beats the 0.3 fraction on 1.0 m3/s
    @std.air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(terminal, 0.5)
    assert_equal('FixedFlowRate', terminal.zoneMinimumAirFlowInputMethod)
    assert_in_delta(0.5, terminal.fixedMinimumAirFlowRate.get, 0.001)
  end

  def test_oa_floor_wins_the_method_when_the_design_flow_is_unknown
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    # maximum flow left autosized with no sizing run: nothing to compare against, and a
    # supplied ventilation floor that EnergyPlus silently ignores is the worse failure
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

    # the ventilation-effectiveness adjustment raises the minimum to a fraction; on this
    # terminal that has to arrive as a fixed rate or EnergyPlus never sees it
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
