class ASHRAE9012004 < ASHRAE901
  # @!group AirLoopHVAC

  # Determine if an economizer is required per the PRM.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_prm_baseline_economizer_required?(air_loop_hvac, climate_zone)
    economizer_required = false

    # A big number of ft2 as the minimum requirement
    infinity_ft2 = 999_999_999_999
    min_int_area_served_ft2 = infinity_ft2
    min_ext_area_served_ft2 = infinity_ft2

    # Determine the minimum capacity that requires an economizer
    case climate_zone
    when 'ASHRAE 169-2006-0A',
         'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-0B',
         'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-4A',
         'ASHRAE 169-2013-0A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-0B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-4A'
      min_int_area_served_ft2 = infinity_ft2 # No requirement
      min_ext_area_served_ft2 = infinity_ft2 # No requirement
    when 'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-5A',
         'ASHRAE 169-2006-6A',
         'ASHRAE 169-2006-7A',
         'ASHRAE 169-2006-7B',
         'ASHRAE 169-2006-8A',
         'ASHRAE 169-2006-8B',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-5A',
         'ASHRAE 169-2013-6A',
         'ASHRAE 169-2013-7A',
         'ASHRAE 169-2013-7B',
         'ASHRAE 169-2013-8A',
         'ASHRAE 169-2013-8B'
      min_int_area_served_ft2 = 15_000
      min_ext_area_served_ft2 = infinity_ft2 # No requirement
    when 'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2006-4B',
         'ASHRAE 169-2006-4C',
         'ASHRAE 169-2006-5B',
         'ASHRAE 169-2006-5C',
         'ASHRAE 169-2006-6B',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C',
         'ASHRAE 169-2013-4B',
         'ASHRAE 169-2013-4C',
         'ASHRAE 169-2013-5B',
         'ASHRAE 169-2013-5C',
         'ASHRAE 169-2013-6B'
      min_int_area_served_ft2 = 10_000
      min_ext_area_served_ft2 = 25_000
    end

    # Check whether the system requires an economizer by comparing
    # the system capacity to the minimum capacity.
    min_int_area_served_m2 = OpenStudio.convert(min_int_area_served_ft2, 'ft^2', 'm^2').get
    min_ext_area_served_m2 = OpenStudio.convert(min_ext_area_served_ft2, 'ft^2', 'm^2').get

    # Get the interior and exterior area served
    int_area_served_m2 = OpenstudioStandards::HVAC.air_loop_hvac_floor_area_interior_zones(air_loop_hvac)
    ext_area_served_m2 = OpenstudioStandards::HVAC.air_loop_hvac_floor_area_exterior_zones(air_loop_hvac)

    # Check the floor area exception
    if int_area_served_m2 < min_int_area_served_m2 && ext_area_served_m2 < min_ext_area_served_m2
      if min_int_area_served_ft2 == infinity_ft2 && min_ext_area_served_ft2 == infinity_ft2
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Economizer not required for climate zone #{climate_zone}.")
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Economizer not required for because the interior area served of #{int_area_served_m2} ft2 is less than the minimum of #{min_int_area_served_m2} and the perimeter area served of #{ext_area_served_m2} ft2 is less than the minimum of #{min_ext_area_served_m2} for climate zone #{climate_zone}.")
      end
      return economizer_required
    end

    # If here, economizer required
    economizer_required = true
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Economizer required for the performance rating method baseline.")

    return economizer_required
  end

  # Determines the OA flow rates above which an economizer is required.
  # Two separate rates, one for systems with an economizer and another for systems without.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Array<Double>] [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  def air_loop_hvac_demand_control_ventilation_limits(air_loop_hvac)
    min_oa_without_economizer_cfm = 3000
    min_oa_with_economizer_cfm = 0
    return [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  end

  # Determine whether the VAV damper control is single maximum or dual maximum control.
  # Single Maximum for 90.1-2004.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [String] the damper control type: Single Maximum, Dual Maximum
  def air_loop_hvac_vav_damper_action(air_loop_hvac)
    damper_action = 'Single Maximum'
    return damper_action
  end

  # Determine the air flow and number of story limits for whether motorized OA damper is required.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Array<Double>] [minimum_oa_flow_cfm, maximum_stories]. If both nil, never required
  def air_loop_hvac_motorized_oa_damper_limits(air_loop_hvac, climate_zone)
    case climate_zone
    when 'ASHRAE 169-2006-0A',
         'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-0B',
         'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2013-0A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-0B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C'
      minimum_oa_flow_cfm = 0
      maximum_stories = 999 # Any number of stories
    else
      minimum_oa_flow_cfm = 0
      maximum_stories = 3
    end

    return [minimum_oa_flow_cfm, maximum_stories]
  end

  # Determine the number of stages that should be used as controls for single zone DX systems.
  # 90.1-2004 requires 1 stage.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Integer] the number of stages: 0, 1, 2
  def air_loop_hvac_single_zone_controls_num_stages(air_loop_hvac, climate_zone)
    num_stages = 1
    return num_stages
  end

  # Determines supply air temperature (SAT) temperature.
  # For 90.1-2007, 10 delta-F (R)
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Double] the SAT reset amount in degrees Rankine
  def air_loop_hvac_enable_supply_air_temperature_reset_delta(air_loop_hvac)
    sat_reset_r = 10.0
    return sat_reset_r
  end

  # Determine the airflow limits that govern whether or not an ERV is required.
  # Based on climate zone and % OA.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param pct_oa [Double] percentage of outdoor air
  # @return [Double] the flow rate above which an ERV is required. if nil, ERV is never required.
  def air_loop_hvac_energy_recovery_ventilator_flow_limit(air_loop_hvac, climate_zone, pct_oa)
    erv_cfm = if pct_oa < 0.7
                nil
              else
                # @todo Add exceptions (eg: e. cooling systems in climate zones 3C, 4C, 5B, 5C, 6B, 7 and 8 | d. Heating systems in climate zones 1 to 3)
                5000
              end

    return erv_cfm
  end
end
