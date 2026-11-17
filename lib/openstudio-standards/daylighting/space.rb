module OpenstudioStandards
  # The Daylighting module provides methods to add daylighting to a Space
  module Daylighting
    # @!group Space

    # add a daylight sensor to a space
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @param name [String] name of sensor, if nil, will use "<space name> daylight sensor"
    # @param position [OpenStudio::Point3d] point to place daylight sensor, defaults to 1 meter above the center of the space
    # @param phi_rotation_around_z_axis [Double] Rotation around z-axis
    # @param illuminance_setpoint [Double] illuminance setpoint in lux, default 430 lux is roughly 40 foot-candles
    # @param lighting_control_type [String] Options are 'None', 'Continuous', Stepped', 'Continuous/Off'
    # @param minimum_input_power_fraction_continuous [Double] minimum input power fraction for continuous dimming control
    # @param minimum_light_output_fraction_continuous [Double] minimum light output fraction for continuous dimming control
    # @param number_of_stepped_control_steps [Integer] number of steps if stepped control
    # @return [OpenStudio::Model::DaylightingControl] daylight sensor
    def self.space_add_daylight_sensor(space,
                                       name: nil,
                                       position: nil,
                                       phi_rotation_around_z_axis: 0.0,
                                       illuminance_setpoint: 430.0,
                                       lighting_control_type: 'Continuous',
                                       minimum_input_power_fraction_continuous: 0.3,
                                       minimum_light_output_fraction_continuous: 0.2,
                                       number_of_stepped_control_steps: 1)
      daylight_sensor = OpenStudio::Model::DaylightingControl.new(space.model)
      daylight_sensor.setSpace(space)
      sensor_name = name.nil? ? "#{space.name} Daylight Sensor" : name
      daylight_sensor.setName(sensor_name)
      if position.nil?
        position = OpenstudioStandards::Geometry.space_create_point_at_center_of_floor(space, 1.0)
      end
      daylight_sensor.setPosition(position)
      daylight_sensor.setPhiRotationAroundZAxis(phi_rotation_around_z_axis) unless phi_rotation_around_z_axis.nil?
      daylight_sensor.setIlluminanceSetpoint(illuminance_setpoint)
      daylight_sensor.setLightingControlType(lighting_control_type)
      daylight_sensor.setMinimumInputPowerFractionforContinuousDimmingControl(minimum_input_power_fraction_continuous)
      daylight_sensor.setMinimumLightOutputFractionforContinuousDimmingControl(minimum_light_output_fraction_continuous)
      daylight_sensor.setNumberofSteppedControlSteps(number_of_stepped_control_steps)

      return daylight_sensor
    end
  end
end
