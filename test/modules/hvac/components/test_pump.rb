require_relative '../../../helpers/minitest_helper'

class TestHVACPump < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_pump
    model = OpenStudio::Model::Model.new
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump_tot_hd_pa = OpenStudio.convert(60.0, 'ftH_{2}O', 'Pa').get
    pump.setRatedPumpHead(pump_tot_hd_pa)
    pump.setRatedFlowRate(0.25)
    pump.setMotorEfficiency(0.92)
    pump.setRatedPowerConsumption(62_500.0)

    flow_rate = @hvac.pump_get_rated_flow_rate(pump)
    power = @hvac.pump_get_power(pump)
    bhp = @hvac.pump_get_brake_horsepower(pump)
    mhp = @hvac.pump_get_motor_horsepower(pump)
    rwgpm = @hvac.pump_get_rated_w_per_gpm(pump)
    @hvac.pump_variable_speed_set_control_type(pump, control_type: 'VSD No Reset')

    assert_in_delta(0.25, flow_rate, 0.01, 'Expected flow rate to be 0.25 m3/s')
    assert_in_delta(62480, power, 1.0, 'Expected power to be 62.5 kW')
    assert_in_delta(77, bhp, 1.0, 'Expected brake horsepower to be 77 HP')
    assert_in_delta(84, mhp, 1.0, 'Expected motor horsepower to be 84 HP')
    assert_in_delta(15.8, rwgpm, 0.1, 'Expected rated watts per gpm to be 15.8 W/gpm')
    assert_in_delta(0.0, pump.coefficient1ofthePartLoadPerformanceCurve, 0.01, 'Expected coefficient1ofthePartLoadPerformanceCurve to be 0.0')
    assert_in_delta(0.5726, pump.coefficient2ofthePartLoadPerformanceCurve, 0.001, 'Expected coefficient2ofthePartLoadPerformanceCurve to be 0.5726')
    assert_in_delta(-0.301, pump.coefficient3ofthePartLoadPerformanceCurve, 0.001, 'Expected coefficient3ofthePartLoadPerformanceCurve to be -0.301')
    assert_in_delta(0.7347, pump.coefficient4ofthePartLoadPerformanceCurve, 0.001, 'Expected coefficient4ofthePartLoadPerformanceCurve to be 0.7347')
  end
end
