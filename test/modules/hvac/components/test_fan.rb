require_relative '../../../helpers/minitest_helper'

class TestHVACFan < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_fan_on_off
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_fan_on_off(model,
                                  fan_name: 'Unleash The Archers Fan',
                                  fan_efficiency: 0.5,
                                  pressure_rise: 1.2,
                                  motor_efficiency: 0.8,
                                  motor_in_airstream_fraction: 0.9,
                                  end_use_subcategory: 'Power Metal Fans')
    assert(fan.is_a?(OpenStudio::Model::FanOnOff), 'Expected fan to be a FanOnOff object')
    assert_equal('Unleash The Archers Fan', fan.name.get)
    assert_in_delta(0.5, fan.fanEfficiency, 0.001)
    assert_in_delta(1.2, fan.pressureRise, 0.001)
    assert_in_delta(0.8, fan.motorEfficiency, 0.001)
    assert_in_delta(0.9, fan.motorInAirstreamFraction.get, 0.001)
    assert_equal('Power Metal Fans', fan.endUseSubcategory)
  end

  def test_create_fan_constant_volume
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_fan_constant_volume(model,
                                           fan_name: 'Gloryhammer Fan',
                                           fan_efficiency: 0.5,
                                           pressure_rise: 1.2,
                                           motor_efficiency: 0.8,
                                           motor_in_airstream_fraction: 0.9,
                                           end_use_subcategory: 'Power Metal Fans')
    assert(fan.is_a?(OpenStudio::Model::FanConstantVolume), 'Expected fan to be a FanConstantVolume object')
    assert_equal('Gloryhammer Fan', fan.name.get)
    assert_in_delta(0.5, fan.fanEfficiency, 0.001)
    assert_in_delta(1.2, fan.pressureRise, 0.001)
    assert_in_delta(0.8, fan.motorEfficiency, 0.001)
    assert_in_delta(0.9, fan.motorInAirstreamFraction, 0.001)
    assert_equal('Power Metal Fans', fan.endUseSubcategory)
  end

  def test_create_fan_variable_volume
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_fan_variable_volume(model,
                                           fan_name: 'DragonForce Fan',
                                           fan_efficiency: 0.5,
                                           pressure_rise: 1.2,
                                           motor_efficiency: 0.8,
                                           motor_in_airstream_fraction: 0.9,
                                           fan_curve: 'Multi Zone VAV with Static Pressure Setpoint Reset',
                                           end_use_subcategory: 'Power Metal Fans')
    assert(fan.is_a?(OpenStudio::Model::FanVariableVolume), 'Expected fan to be a FanVariableVolume object')
    assert_equal('DragonForce Fan', fan.name.get)
    assert_in_delta(0.5, fan.fanEfficiency, 0.001)
    assert_in_delta(1.2, fan.pressureRise, 0.001)
    assert_in_delta(0.8, fan.motorEfficiency, 0.001)
    assert_in_delta(0.9, fan.motorInAirstreamFraction, 0.001)
    assert_equal('Power Metal Fans', fan.endUseSubcategory)
    assert_in_delta(0.1, fan.fanPowerMinimumFlowFraction, 0.001)
    assert_in_delta(0.040759894, fan.fanPowerCoefficient1.get, 0.001)
    assert_in_delta(0.08804497, fan.fanPowerCoefficient2.get, 0.001)
    assert_in_delta(-0.07292612, fan.fanPowerCoefficient3.get, 0.001)
    assert_in_delta(0.943739823, fan.fanPowerCoefficient4.get, 0.001)
  end

  def test_create_fan_zone_exhaust
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_fan_zone_exhaust(model,
                                        fan_name: 'Wind Rose Fan',
                                        fan_efficiency: 0.5,
                                        pressure_rise: 1.2,
                                        system_availability_manager_coupling_mode: 'Decoupled',
                                        end_use_subcategory: 'Power Metal Fans')
    assert(fan.is_a?(OpenStudio::Model::FanZoneExhaust), 'Expected fan to be a FanZoneExhaust object')
    assert_equal('Wind Rose Fan', fan.name.get)
    assert_in_delta(0.5, fan.fanEfficiency, 0.001)
    assert_in_delta(1.2, fan.pressureRise, 0.001)
    assert_equal('Decoupled', fan.systemAvailabilityManagerCouplingMode.to_s)
    assert_equal('Power Metal Fans', fan.endUseSubcategory)
  end

  def test_create_fan_system_model
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_fan_system_model(model,
                                        fan_name: 'Helion Prime Fan',
                                        pressure_rise: 1.2,
                                        motor_efficiency: 0.8,
                                        motor_in_airstream_fraction: 0.9,
                                        design_power_sizing_method: 'PowerPerFlowPerPressure',
                                        power_per_flow_rate_per_pressure: 1.33,
                                        speed_control_method: 'Discrete',
                                        speeds: [[0.5, 0.25], [0.75, 0.65], [1.0, 1.0]])
    assert(fan.is_a?(OpenStudio::Model::FanSystemModel), 'Expected fan to be a FanSystemModel object')
    assert_equal('Helion Prime Fan', fan.name.get)
    assert_in_delta(1.2, fan.designPressureRise, 0.001)
    assert_in_delta(0.8, fan.motorEfficiency, 0.001)
    assert_in_delta(0.9, fan.motorInAirStreamFraction, 0.001)
    assert_equal('PowerPerFlowPerPressure', fan.designPowerSizingMethod.to_s)
    assert_in_delta(1.33, fan.electricPowerPerUnitFlowRatePerUnitPressure, 0.001)
    assert_equal('Discrete', fan.speedControlMethod.to_s)
    assert_equal(3, fan.speeds.size, 'Expected 3 speed points')
  end

  def test_create_typical_fan
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_typical_fan(model, 'CRAC_CAV_fan')
    assert(fan.is_a?(OpenStudio::Model::FanConstantVolume), 'Expected CRAC_CAV_fan to be a FanConstantVolume object')

    fan = @hvac.create_typical_fan(model, 'Constant_DOAS_Fan')
    assert(fan.is_a?(OpenStudio::Model::FanConstantVolume), 'Expected Constant_DOAS_Fan to be a FanConstantVolume object')

    fan = @hvac.create_typical_fan(model, 'Fan_Coil_Fan')
    assert(fan.is_a?(OpenStudio::Model::FanOnOff), 'Expected Fan_Coil_Fan to be a FanOnOff object')

    fan = @hvac.create_typical_fan(model, 'PSZ_VAV_Fan')
    assert(fan.is_a?(OpenStudio::Model::FanVariableVolume), 'Expected PSZ_VAV_Fan to be a FanVariableVolume object')
  end

  def test_fan_variable_volume_set_control_type
    model = OpenStudio::Model::Model.new
    fan = @hvac.create_fan_variable_volume(model)

    @hvac.fan_variable_volume_set_control_type(fan, control_type: 'Multi Zone VAV with Static Pressure Setpoint Reset')
    assert_in_delta(0.1, fan.fanPowerMinimumFlowFraction, 0.001)
    assert_in_delta(0.040759894, fan.fanPowerCoefficient1.get, 0.001)
    assert_in_delta(0.08804497, fan.fanPowerCoefficient2.get, 0.001)
    assert_in_delta(-0.07292612, fan.fanPowerCoefficient3.get, 0.001)
    assert_in_delta(0.943739823, fan.fanPowerCoefficient4.get, 0.001)

    @hvac.fan_variable_volume_set_control_type(fan, control_type: 'Multi Zone VAV with Fixed Static Pressure Setpoint')
    assert_in_delta(0.2, fan.fanPowerMinimumFlowFraction, 0.001)
    assert_in_delta(0.0013, fan.fanPowerCoefficient1.get, 0.001)
    assert_in_delta(0.1470, fan.fanPowerCoefficient2.get, 0.001)
    assert_in_delta(0.9506, fan.fanPowerCoefficient3.get, 0.001)
    assert_in_delta(-0.0998, fan.fanPowerCoefficient4.get, 0.001)

    @hvac.fan_variable_volume_set_control_type(fan, control_type: 'Single Zone VAV')
    assert_in_delta(0.1, fan.fanPowerMinimumFlowFraction, 0.001)
    assert_in_delta(0.027827882, fan.fanPowerCoefficient1.get, 0.001)
    assert_in_delta(0.026583195, fan.fanPowerCoefficient2.get, 0.001)
    assert_in_delta(-0.0870687, fan.fanPowerCoefficient3.get, 0.001)
    assert_in_delta(1.03091975, fan.fanPowerCoefficient4.get, 0.001)
  end
end
