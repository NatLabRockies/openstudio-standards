class DEER
  # @!group AirLoopHVAC

  # For LA100 calibration, default to systems being left on
  # Overwritten to be required for DEER2020 and beyond
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_unoccupied_fan_shutoff_required?(air_loop_hvac)
    shutoff_required = false
    return shutoff_required
  end

  # Determines the OA flow rates above which an economizer is required.
  # Two separate rates, one for systems with an economizer and another
  # for systems without.
  # The small numbers here are to reflect that there is not a minimum
  # airflow requirement in Title 24.
  # @return [Array<Double>] [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  def air_loop_hvac_demand_control_ventilation_limits(air_loop_hvac)
    min_oa_without_economizer_cfm = 0.01
    min_oa_with_economizer_cfm = 0.01
    return [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  end

  # Determine if the standard has an exception for demand control ventilation
  # when an energy recovery device is present.
  # Unlike ASHRAE 90.1, Title 24 does not have an ERV exception to DCV.
  # This method is a copy of what is in Standards.AirLoopHVAC.rb and ensures
  # ERVs will not prevent DCV from being applied to DEER models.
  def air_loop_hvac_dcv_required_when_erv(air_loop_hvac)
    dcv_required_when_erv_present = true
    return dcv_required_when_erv_present
  end

  # Determine whether or not this system is required to have an economizer.
  # Logic inferred from MASControl3 INP files and parameters database.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if an economizer is required, false if not
  def air_loop_hvac_economizer_required?(air_loop_hvac, climate_zone)
    economizer_required = false

    # skip systems without outdoor air
    return economizer_required unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized

    # Determine if the airloop serves any computer rooms
    # / data centers, which changes the economizer.
    is_dc = false
    if OpenstudioStandards::HVAC.air_loop_hvac_data_center_area(air_loop_hvac) > 0
      is_dc = true
    end

    # Retrieve economizer limits from JSON
    search_criteria = {
      'template' => template,
      'climate_zone' => climate_zone,
      'data_center' => is_dc
    }
    econ_limits = model_find_object(standards_data['economizers'], search_criteria)
    if econ_limits.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "Cannot find economizer limits for template '#{template}' and climate zone '#{climate_zone}', assuming no economizer required.")
      return economizer_required
    end

    # Determine the minimum capacity and whether or not it is a data center
    minimum_capacity_btu_per_hr = econ_limits['capacity_limit']

    # A big number of btu per hr as the minimum requirement if nil in spreadsheet
    infinity_btu_per_hr = 999_999_999_999
    minimum_capacity_btu_per_hr = infinity_btu_per_hr if minimum_capacity_btu_per_hr.nil?

    # Check whether the system requires an economizer by comparing
    # the system capacity to the minimum capacity.
    total_cooling_capacity_w = OpenstudioStandards::HVAC.air_loop_hvac_total_cooling_capacity(air_loop_hvac)
    total_cooling_capacity_btu_per_hr = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get

    # Check whether the system has chilled water cooling
    has_chilled_water_cooling = false
    air_loop_hvac.supplyComponents.each do |equip|
      if equip.to_CoilCoolingWater.is_initialized
        has_chilled_water_cooling = true
      end
    end

    # Applicability logic from MASControl3
    if has_chilled_water_cooling
      # All systems with chilled water cooling get an economizer regardless of capacity
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because it has chilled water cooling.")
      economizer_required = true
    else
      # DX and other systems may have a capacity limit
      if total_cooling_capacity_btu_per_hr >= minimum_capacity_btu_per_hr
        if is_dc
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr for data centers.")
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr.")
        end
        economizer_required = true
      else
        if is_dc
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} does not require an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr is less than the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr for data centers.")
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} does not require an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr is less than the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr.")
        end
      end
    end

    return economizer_required
  end

  # Check the economizer type currently specified in the ControllerOutdoorAir object on this air loop
  # is acceptable per the standard.  Based on the MASControl rules, it appears that
  # only NoEconomizer and FixedDryBulb are allowed.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] Returns true if allowable, if the system has no economizer or no OA system.
  #   Returns false if the economizer type is not allowable.
  def air_loop_hvac_economizer_type_allowable?(air_loop_hvac, climate_zone)
    # EnergyPlus economizer types
    # 'NoEconomizer'
    # 'FixedDryBulb'
    # 'FixedEnthalpy'
    # 'DifferentialDryBulb'
    # 'DifferentialEnthalpy'
    # 'FixedDewPointAndDryBulb'
    # 'ElectronicEnthalpy'
    # 'DifferentialDryBulbAndEnthalpy'

    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    return true unless oa_sys.is_initialized # No OA system

    oa_sys = oa_sys.get
    oa_control = oa_sys.getControllerOutdoorAir
    economizer_type = oa_control.getEconomizerControlType

    # Return true if one of the valid choices is used, false otherwise
    case economizer_type
      when 'NoEconomizer', 'FixedDryBulb'
        return true
      else
        return false
    end
  end

  # Determine the limits for the type of economizer present on the AirLoopHVAC, if any.
  # Enthalpy limit is from MASControl3.
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Array<Double>] [drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  def air_loop_hvac_economizer_limits(air_loop_hvac, climate_zone)
    drybulb_limit_f = nil
    enthalpy_limit_btu_per_lb = nil
    dewpoint_limit_f = nil

    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    return [nil, nil, nil] unless oa_sys.is_initialized

    oa_sys = oa_sys.get
    oa_control = oa_sys.getControllerOutdoorAir
    economizer_type = oa_control.getEconomizerControlType

    case economizer_type
    when 'NoEconomizer'
      return [nil, nil, nil]
    when 'FixedDryBulb'
      enthalpy_limit_btu_per_lb = 28
      search_criteria = {
        'template' => template,
        'climate_zone' => climate_zone
      }
      econ_limits = model_find_object(standards_data['economizers'], search_criteria)
      drybulb_limit_f = econ_limits['fixed_dry_bulb_high_limit_shutoff_temp']
    end

    return [drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  end
end
