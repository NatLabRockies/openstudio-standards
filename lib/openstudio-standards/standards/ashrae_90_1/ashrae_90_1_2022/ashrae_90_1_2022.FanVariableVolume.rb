class ASHRAE9012022 < ASHRAE901
  # @!group FanVariableVolume

  # The threhold horsepower below which part load control is not required.
  # Per 90.1-2019, table 6.5.3.2.1: the fan motor size for chiller-water
  # and evaporative cooling is 0.25 hp as of 1/1/2014 instead of 5 hp
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [Double] the limit, in horsepower. Return nil for no limit by default.
  def fan_variable_volume_part_load_fan_power_limitation_hp_limit(fan_variable_volume)
    hp_limit = case fan_variable_volume_cooling_system_type(fan_variable_volume)
               when 'dx'
                 0.0
               when 'chw', 'evap'
                 0.25
               end

    return hp_limit
  end

  # The threhold capacity below which part load control is not required.
  # Per 90.1-2019, table 6.5.3.2.1: the cooling capacity threshold is 75000
  # instead of 110000 as of 1/1/2014
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [Double] the limit, in Btu/hr. Return nil for no limit by default.
  def fan_variable_volume_part_load_fan_power_limitation_capacity_limit(fan_variable_volume)
    cap_limit_btu_per_hr = case fan_variable_volume_cooling_system_type(fan_variable_volume)
                           when 'dx'
                             65_000
                           end

    return cap_limit_btu_per_hr
  end
end

