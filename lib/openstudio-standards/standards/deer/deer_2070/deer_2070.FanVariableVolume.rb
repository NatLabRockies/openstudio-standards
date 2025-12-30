class DEER2070 < DEER
  # @!group FanVariableVolume

  # Determines whether there is a requirement to have a VSD or some other method to reduce fan power at low part load ratios.
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [Boolean] returns true if required, false if not
  def fan_variable_volume_part_load_fan_power_limitation?(fan_variable_volume)
    part_load_control_required = false

    # Check if the fan is on a multizone or single zone system.
    # If not on an AirLoop (for example, in unitary system or zone equipment), assumed to be a single zone fan
    mz_fan = false
    if fan_variable_volume.airLoopHVAC.is_initialized
      air_loop = fan_variable_volume.airLoopHVAC.get
      mz_fan = OpenstudioStandards::HVAC.air_loop_hvac_multizone_vav_system?(air_loop)
    end

    # No part load fan power control is required for single zone VAV systems
    unless mz_fan
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FanVariableVolume', "For #{fan_variable_volume.name}: No part load fan power control is required for single zone VAV systems.")
      return part_load_control_required
    end

    # Assume static pressure reset for all multi-zone fans
    part_load_control_required = true

    return part_load_control_required
  end
end
