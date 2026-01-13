class Standard
  # @!group FanVariableVolume

  include Fan

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
      mz_fan = air_loop_hvac_multizone_vav_system?(air_loop)
    end

    # No part load fan power control is required for single zone VAV systems
    unless mz_fan
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FanVariableVolume', "For #{fan_variable_volume.name}: No part load fan power control is required for single zone VAV systems.")
      return part_load_control_required
    end

    # Determine the motor and capacity size limits
    hp_limit = fan_variable_volume_part_load_fan_power_limitation_hp_limit(fan_variable_volume)
    cap_limit_btu_per_hr = fan_variable_volume_part_load_fan_power_limitation_capacity_limit(fan_variable_volume)

    # Check against limits
    if hp_limit && cap_limit_btu_per_hr
      air_loop = fan_variable_volume.airLoopHVAC
      unless air_loop.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.FanVariableVolume', "For #{fan_variable_volume.name}: Could not find the air loop to get cooling capacity for determining part load fan power control requirement.")
        return part_load_control_required
      end
      air_loop = air_loop.get
      clg_cap_w = air_loop_hvac_total_cooling_capacity(air_loop)
      clg_cap_btu_per_hr = OpenStudio.convert(clg_cap_w, 'W', 'Btu/hr').get
      fan_hp = fan_motor_horsepower(fan_variable_volume)
      if fan_hp >= hp_limit && clg_cap_btu_per_hr >= cap_limit_btu_per_hr
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FanVariableVolume', "For #{fan_variable_volume.name}: part load fan power control is required for #{fan_hp.round(1)} HP fan, #{clg_cap_btu_per_hr.round} Btu/hr cooling capacity.")
        part_load_control_required = true
      end
    elsif hp_limit
      fan_hp = fan_motor_horsepower(fan_variable_volume)
      if fan_hp >= hp_limit
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FanVariableVolume', "For #{fan_variable_volume.name}: Part load fan power control is required for #{fan_hp.round(1)} HP fan.")
        part_load_control_required = true
      end
    end

    return part_load_control_required
  end

  # The threhold horsepower below which part load control is not required.
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [Double] the limit, in horsepower. Return nil for no limit by default.
  def fan_variable_volume_part_load_fan_power_limitation_hp_limit(fan_variable_volume)
    hp_limit = nil # No minimum limit
    return hp_limit
  end

  # The threhold capacity below which part load control is not required.
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [Double] the limit, in Btu/hr. Return nil for no limit by default.
  def fan_variable_volume_part_load_fan_power_limitation_capacity_limit(fan_variable_volume)
    cap_limit_btu_per_hr = nil # No minimum limit
    return cap_limit_btu_per_hr
  end

  # Determine if the cooling system is DX, CHW, evaporative, or a mixture.
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @return [String] the cooling system type.  Possible options are:
  #   dx, chw, evaporative, mixed, unknown.
  def fan_variable_volume_cooling_system_type(fan_variable_volume)
    clg_sys_type = 'unknown'

    # Get the air loop this fan is connected to
    air_loop = fan_variable_volume.airLoopHVAC
    return clg_sys_type unless air_loop.is_initialized

    air_loop = air_loop.get

    # Check the types of coils on the AirLoopHVAC
    has_dx = false
    has_chw = false
    has_evap = false
    air_loop.supplyComponents.each do |sc|
      # CoilCoolingDXSingleSpeed
      if sc.to_CoilCoolingDXSingleSpeed.is_initialized || sc.to_CoilCoolingDXTwoSpeed.is_initialized || sc.to_CoilCoolingDXMultiSpeed.is_initialized || sc.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
        has_dx = true
      # CoilCoolingWater
      elsif sc.to_CoilCoolingWater.is_initialized
        has_chw = true
      # UnitarySystem
      elsif sc.to_AirLoopHVACUnitarySystem.is_initialized
        unitary = sc.to_AirLoopHVACUnitarySystem.get
        if unitary.coolingCoil.is_initialized
          clg_coil = unitary.coolingCoil.get
          # CoilCoolingDXSingleSpeed
          if clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized || clg_coil.to_CoilCoolingDXTwoSpeed.is_initialized || clg_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
            has_dx = true
          # CoilCoolingWater
          elsif clg_coil.to_CoilCoolingWater.is_initialized
            has_chw = true
          end
        end
      # UnitaryHeatPumpAirToAir
      elsif sc.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
        unitary = sc.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
        clg_coil = unitary.coolingCoil
        # CoilCoolingDXSingleSpeed
        if clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized || clg_coil.to_CoilCoolingDXTwoSpeed.is_initialized
          has_dx = true
        # CoilCoolingWater
        elsif clg_coil.to_CoilCoolingWater.is_initialized
          has_chw = true
        end
      # EvaporativeCoolerDirectResearchSpecial
      elsif sc.to_EvaporativeCoolerDirectResearchSpecial.is_initialized || sc.to_EvaporativeCoolerIndirectResearchSpecial.is_initialized
        has_evap = true
      elsif sc.to_CoilCoolingCooledBeam.is_initialized ||
            sc.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.is_initialized ||
            sc.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized ||
            sc.to_AirLoopHVACUnitarySystem.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.FanVariableVolume', "#{air_loop.name} has a cooling coil named #{sc.name}, whose type is not yet covered by cooling system type checks.")
      end
    end

    # Determine the type
    if (has_chw && has_dx && has_evap) ||
       (has_chw && has_dx) ||
       (has_chw && has_evap) ||
       (has_dx && has_evap)
      clg_sys_type = 'mixed'
    elsif has_chw
      clg_sys_type = 'chw'
    elsif has_dx
      clg_sys_type = 'dx'
    elsif has_evap
      clg_sys_type = 'evap'
    end

    return clg_sys_type
  end
end
