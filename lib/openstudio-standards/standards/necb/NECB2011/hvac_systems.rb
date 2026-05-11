class NECB2011
  def model_add_hvac(model:)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding HVAC')
    system_fuel_defaults = get_canadian_system_defaults_by_weatherfile_name(model)
    necb_autozone_and_autosystem(model: model, runner: nil, use_ideal_air_loads: false, system_fuel_defaults: system_fuel_defaults)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding HVAC')
    return true
  end

  # NECB does not change damper positions
  #
  # return [Boolean] returns true if successful, false if not
  def air_loop_hvac_apply_multizone_vav_outdoor_air_sizing(air_loop_hvac)
    # Do not change anything.
    return true
  end

  # Determine whether or not this system
  # is required to have an economizer.
  #
  # @return [Boolean] returns true if an economizer is required, false if not
  def air_loop_hvac_economizer_required?(air_loop_hvac)
    economizer_required = false

    # need a better way to determine if an economizer is needed.
    return economizer_required if ((air_loop_hvac.name.to_s.include? 'Outpatient F1' ) ||
                                   (air_loop_hvac.sizingSystem.typeofLoadtoSizeOn.to_s == "VentilationRequirement"))

    # A big number of btu per hr as the minimum requirement
    infinity_btu_per_hr = 999_999_999_999
    minimum_capacity_btu_per_hr = infinity_btu_per_hr

    # Determine if the airloop serves any computer rooms
    # / data centers, which changes the economizer.
    is_dc = false
    if air_loop_hvac_data_center_area_served(air_loop_hvac) > 0
      is_dc = true
    end

    # Determine the minimum capacity that requires an economizer
    minimum_capacity_btu_per_hr = 68_243 # NECB requires economizer for cooling cap > 20 kW

    # puts air_loop_hvac.name.to_s
    # Design Supply Air Flow Rate: This method below reads the value from the sql file.
    dsafr_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate
    min_dsafr_l_per_s = 1500
    unless dsafr_m3_per_s.empty?
      dsafr_l_per_s = dsafr_m3_per_s.get * 1000
      if dsafr_l_per_s > min_dsafr_l_per_s
        economizer_required = true
        puts "economizer_required = true for #{air_loop_hvac.name} because dsafr_l_per_s(#{dsafr_l_per_s}) > 1500"
        if is_dc
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the 'Design Supply Air Flow Rate' of #{dsafr_l_per_s} L/s exceeds the minimum air flow rate of #{min_dsafr_l_per_s} L/s for data centers.")
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the 'Design Supply Air Flow Rate' of #{dsafr_l_per_s} L/s exceeds the minimum air flow rate of #{min_dsafr_l_per_s} L/s.")
        end
      end
    end
    # Check whether the system requires an economizer by comparing
    # the system capacity to the minimum capacity.
    total_cooling_capacity_w = air_loop_hvac_total_cooling_capacity(air_loop_hvac)
    total_cooling_capacity_btu_per_hr = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    if total_cooling_capacity_btu_per_hr >= minimum_capacity_btu_per_hr
      if is_dc
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr for data centers.")
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr.")
      end
      puts "economizer_required = true for #{air_loop_hvac.name} because total_cooling_capacity_btu_per_hr(#{total_cooling_capacity_btu_per_hr}) >= #{minimum_capacity_btu_per_hr}"
      economizer_required = true
    else
      if is_dc
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} does not require an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr is less than the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr for data centers.")
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} does not require an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr is less than the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr.")
      end
    end

    return economizer_required
  end

  # NECB always requires an integrated economizer
  # (NoLockout); as per 5.2.2.8(3)
  # this means that compressor allowed to turn on when economizer is open
  #
  # @note this method assumes you previously checked that an economizer is required at all
  #   via #economizer_required?
  # @param (see #economizer_required?)
  # @return [Boolean] returns true if successful, false if not
  def air_loop_hvac_apply_economizer_integration(air_loop_hvac, climate_zone)
    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    # No OA system
    return false if !oa_sys.is_initialized

    oa_sys = oa_sys.get
    oa_control = oa_sys.getControllerOutdoorAir

    # Apply integrated economizer
    oa_control.setLockoutType('NoLockout')

    return true
  end

  # Check if ERV is required on this airloop.
  #
  # @param (see #economizer_required?)
  # @return [Boolean] Returns true if required, false if not.
  # @todo Add exception logic for systems serving parking garage, warehouse, or multifamily
  def air_loop_hvac_energy_recovery_ventilator_required?(air_loop_hvac, climate_zone)
    # ERV Not Applicable for AHUs that serve
    # parking garage, warehouse, or multifamily
    # if space_types_served_names.include?('PNNL_Asset_Rating_Apartment_Space_Type') ||
    # space_types_served_names.include?('PNNL_Asset_Rating_LowRiseApartment_Space_Type') ||
    # space_types_served_names.include?('PNNL_Asset_Rating_ParkingGarage_Space_Type') ||
    # space_types_served_names.include?('PNNL_Asset_Rating_Warehouse_Space_Type')
    # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.AirLoopHVAC", "For #{self.name}, ERV not applicable because it because it serves parking garage, warehouse, or multifamily.")
    # return false
    # end

    erv_required = nil
    # ERV not applicable for medical AHUs (AHU1 in Outpatient), per AIA 2001 - 7.31.D2.
    if air_loop_hvac.name.to_s.include? 'Outpatient F1'
      erv_required = false
      return erv_required
    end

    # ERV not applicable for medical AHUs, per AIA 2001 - 7.31.D2.
    if air_loop_hvac.name.to_s.include? 'VAV_ER'
      erv_required = false
      return erv_required
    elsif air_loop_hvac.name.to_s.include? 'VAV_OR'
      erv_required = false
      return erv_required
    end

    # ERV Not Applicable for AHUs that have DCV
    # or that have no OA intake.
    controller_oa = nil
    controller_mv = nil
    oa_system = nil
    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      controller_mv = controller_oa.controllerMechanicalVentilation
      if controller_mv.demandControlledVentilation == true
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not applicable because DCV enabled.")
        return false
      end
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not applicable because it has no OA intake.")
      return false
    end

    # Get the AHU design supply air flow rate
    dsn_flow_m3_per_s = nil
    if air_loop_hvac.designSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
    elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} design supply air flow rate is not available, cannot apply efficiency standard.")
      return false
    end
    dsn_flow_cfm = OpenStudio.convert(dsn_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Get the minimum OA flow rate
    min_oa_flow_m3_per_s = nil
    if controller_oa.minimumOutdoorAirFlowRate.is_initialized
      min_oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
    elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
      min_oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{controller_oa.name}: minimum OA flow rate is not available, cannot apply efficiency standard.")
      return false
    end
    min_oa_flow_cfm = OpenStudio.convert(min_oa_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Calculate the percent OA at design airflow
    pct_oa = min_oa_flow_m3_per_s / dsn_flow_m3_per_s

    # The NECB2011 requirement is that systems with an exhaust heat content > 150 kW require an HRV
    # The calculation for this is done below, to modify erv_required
    # erv_cfm set to nil here as placeholder, will lead to erv_required = false
    erv_cfm = nil

    # Determine if an ERV is required
    # erv_required = nil
    if erv_cfm.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not required based on #{(pct_oa * 100).round}% OA flow, design supply air flow of #{dsn_flow_cfm.round}cfm, and climate zone #{climate_zone}.")
      erv_required = false
    elsif dsn_flow_cfm < erv_cfm
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not required based on #{(pct_oa * 100).round}% OA flow, design supply air flow of #{dsn_flow_cfm.round}cfm, and climate zone #{climate_zone}. Does not exceed minimum flow requirement of #{erv_cfm}cfm.")
      erv_required = false
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV required based on #{(pct_oa * 100).round}% OA flow, design supply air flow of #{dsn_flow_cfm.round}cfm, and climate zone #{climate_zone}. Exceeds minimum flow requirement of #{erv_cfm}cfm.")
      erv_required = true
    end

    # This code modifies erv_required for NECB2011
    # Calculation of exhaust heat content and check whether it is > 150 kW

    # get all zones in the model
    zones = air_loop_hvac.thermalZones

    # initialize counters
    sum_zone_oa = 0.0
    sum_zone_oa_times_heat_design_t = 0.0

    # zone loop
    zones.each do |zone|
      # get design heat temperature for each zone; this is equivalent to design exhaust temperature
      heat_design_t = 21.0
      zone_thermostat = zone.thermostat.get
      if zone_thermostat.to_ThermostatSetpointDualSetpoint.is_initialized
        dual_thermostat = zone_thermostat.to_ThermostatSetpointDualSetpoint.get
        if dual_thermostat.heatingSetpointTemperatureSchedule.is_initialized
          htg_temp_sch = dual_thermostat.heatingSetpointTemperatureSchedule.get
          htg_temp_sch_ruleset = htg_temp_sch.to_ScheduleRuleset.get
          winter_dd_sch = htg_temp_sch_ruleset.winterDesignDaySchedule
          heat_design_t = winter_dd_sch.values.max
        end
      end
      # initialize counter
      zone_oa = 0.0
      # outdoor defined at space level; get OA flow for all spaces within zone
      spaces = zone.spaces

      # space loop
      spaces.each do |space|
        unless space.designSpecificationOutdoorAir.empty? # if empty, don't do anything
          outdoor_air = space.designSpecificationOutdoorAir.get
          # in bTAP, outdoor air specified as outdoor air per
          oa_flow_per_floor_area = outdoor_air.outdoorAirFlowperFloorArea
          oa_flow = oa_flow_per_floor_area * space.floorArea * zone.multiplier # oa flow for the space
          zone_oa += oa_flow # add up oa flow for all spaces to get zone air flow
        end
        # space loop
      end
      sum_zone_oa += zone_oa # sum of all zone oa flows to get system oa flow
      sum_zone_oa_times_heat_design_t += (zone_oa * heat_design_t) # calculated to get oa flow weighted average of design exhaust temperature
      # zone loop
    end

    # Calculate average exhaust temperature (oa flow weighted average)
    avg_exhaust_temp = sum_zone_oa_times_heat_design_t / sum_zone_oa

    # for debugging/testing
    #      puts "average exhaust temp = #{avg_exhaust_temp}"
    #      puts "sum_zone_oa = #{sum_zone_oa}"

    # Get January winter design temperature
    # get model weather file name
    weather_file_path = air_loop_hvac.model.weatherFile.get.path.get.to_s
    stat_file_path = weather_file_path.gsub('.epw', '.stat')
    stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)

    # get winter(heating) design temp stored in array
    # Note that the NECB2011 specifies using the 2.5% january design temperature
    # The outdoor temperature used here is the 0.4% heating design temperature of the coldest month, available in stat file
    outdoor_temp = stat_file.heating_design_info[1]

    #      for debugging/testing
    #      puts "outdoor design temp = #{outdoor_temp}"

    # Calculate exhaust heat content
    exhaust_heat_content = 0.00123 * sum_zone_oa * 1000.0 * (avg_exhaust_temp - outdoor_temp)

    # for debugging/testing
    #      puts "exhaust heat content = #{exhaust_heat_content}"

    # Modify erv_required based on exhaust heat content
    if exhaust_heat_content > 150.0
      erv_required = true
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV required based on exhaust heat content.")
    else
      erv_required = false
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not required based on exhaust heat content.")
    end

    return erv_required
  end

  # Add an ERV to this airloop.
  # Will be a rotary-type HX
  #
  # @param (see #economizer_required?)
  # @return [Boolean] Returns true if required, false if not.
  # @todo Add exception logic for systems serving parking garage, warehouse, or multifamily
  def air_loop_hvac_apply_energy_recovery_ventilator(air_loop_hvac, climate = nil)
    # Get the oa system
    oa_system = nil
    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV cannot be added because the system has no OA intake.")
      return false
    end

    # Create an ERV
    erv = OpenstudioStandards::HVAC.create_heat_exchanger_air_to_air_sensible_and_latent(air_loop_hvac.model,
                                                                                         name: "#{air_loop_hvac.name} ERV",
                                                                                         type: "Rotary",
                                                                                         economizer_lockout: true,
                                                                                         supply_air_outlet_temperature_control: true,
                                                                                         frost_control_type: 'ExhaustOnly',
                                                                                         sensible_heating_100_eff: 0.5,
                                                                                         sensible_heating_75_eff: 0.5,
                                                                                         latent_heating_100_eff: 0.5,
                                                                                         latent_heating_75_eff: 0.5,
                                                                                         sensible_cooling_100_eff: 0.5,
                                                                                         sensible_cooling_75_eff: 0.5,
                                                                                         latent_cooling_100_eff: 0.5,
                                                                                         latent_cooling_75_eff: 0.5)

    erv.setThresholdTemperature(-23.3) # -10F
    erv.setInitialDefrostTimeFraction(0.167)
    erv.setRateofDefrostTimeFractionIncrease(1.44)

    # Add the ERV to the OA system
    erv.addToNode(oa_system.outboardOANode.get)

    # Add a setpoint manager OA pretreat
    # to control the ERV
    spm_oa_pretreat = OpenStudio::Model::SetpointManagerOutdoorAirPretreat.new(air_loop_hvac.model)
    spm_oa_pretreat.setMinimumSetpointTemperature(-99.0)
    spm_oa_pretreat.setMaximumSetpointTemperature(99.0)
    spm_oa_pretreat.setMinimumSetpointHumidityRatio(0.00001)
    spm_oa_pretreat.setMaximumSetpointHumidityRatio(1.0)
    # Reference setpoint node and
    # Mixed air stream node are outlet
    # node of the OA system
    mixed_air_node = oa_system.mixedAirModelObject.get.to_Node.get
    spm_oa_pretreat.setReferenceSetpointNode(mixed_air_node)
    spm_oa_pretreat.setMixedAirStreamNode(mixed_air_node)
    # Outdoor air node is
    # the outboard OA node of teh OA system
    spm_oa_pretreat.setOutdoorAirStreamNode(oa_system.outboardOANode.get)
    # Return air node is the inlet
    # node of the OA system
    return_air_node = oa_system.returnAirModelObject.get.to_Node.get
    spm_oa_pretreat.setReturnAirStreamNode(return_air_node)
    # Attach to the outlet of the ERV
    erv_outlet = erv.primaryAirOutletModelObject.get.to_Node.get
    spm_oa_pretreat.addToNode(erv_outlet)

    # Apply the prototype Heat Exchanger power assumptions.
    heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_nominal_electric_power(erv)

    # Determine if the system is a DOAS based on
    # whether there is 100% OA in heating and cooling sizing.
    is_doas = false
    sizing_system = air_loop_hvac.sizingSystem
    if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating
      is_doas = true
    end

    # Set the bypass control type
    # If DOAS system, BypassWhenWithinEconomizerLimits
    # to disable ERV during economizing.
    # Otherwise, BypassWhenOAFlowGreaterThanMinimum
    # to disable ERV during economizing and when OA
    # is also greater than minimum.
    bypass_ctrl_type = if is_doas
                         'BypassWhenWithinEconomizerLimits'
                       else
                         'BypassWhenOAFlowGreaterThanMinimum'
                       end
    oa_system.getControllerOutdoorAir.setHeatRecoveryBypassControlType(bypass_ctrl_type)

    return true
  end

  # Sets the minimum effectiveness of the heat exchanger per
  # the standard.
  def heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness(heat_exchanger_air_to_air_sensible_and_latent, erv_name = nil)
    # Assumed to be sensible and latent at all flow
    # This will now get data of the erv from the json file instead of hardcoding it. Defaults to NECB2011 erv we have been using.
    erv_name = 'NECB_Default' if erv_name.nil?
    erv_info = @standards_data['tables']['erv']['table'].detect { |item| item['erv_name'] == erv_name }
    raise("Could not find #{erv_name} in #{self.class.name} class' erv.json file or it's parents. The available ervs are #{@standards_data['tables']['erv']['table'].map { |item| item['erv_name'] }}") if erv_info.nil?

    heat_exchanger_air_to_air_sensible_and_latent.setHeatExchangerType(erv_info['HeatExchangerType'])
    if heat_exchanger_air_to_air_sensible_and_latent.model.version < OpenStudio::VersionString.new('3.8.0')
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100HeatingAirFlow(erv_info['SensibleEffectivenessat100HeatingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100HeatingAirFlow(erv_info['LatentEffectivenessat100HeatingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100CoolingAirFlow(erv_info['SensibleEffectivenessat100CoolingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100CoolingAirFlow(erv_info['LatentEffectivenessat100CoolingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75HeatingAirFlow(erv_info['SensibleEffectivenessat75HeatingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75HeatingAirFlow(erv_info['LatentEffectivenessat75HeatingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75CoolingAirFlow(erv_info['SensibleEffectivenessat75CoolingAirFlow'])
      heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75CoolingAirFlow(erv_info['LatentEffectivenessat75CoolingAirFlow'])
    else
      values = Hash.new{|hash, key| hash[key] = Hash.new}
      values['Sensible Heating'][0.75] = erv_info['SensibleEffectivenessat75HeatingAirFlow']
      values['Sensible Heating'][1.0] = erv_info['SensibleEffectivenessat100HeatingAirFlow']
      values['Latent Heating'][0.75] = erv_info['LatentEffectivenessat75HeatingAirFlow']
      values['Latent Heating'][1.0] = erv_info['LatentEffectivenessat100HeatingAirFlow']
      values['Sensible Cooling'][0.75] = erv_info['SensibleEffectivenessat75CoolingAirFlow']
      values['Sensible Cooling'][1.0] = erv_info['SensibleEffectivenessat100CoolingAirFlow']
      values['Latent Cooling'][0.75] = erv_info['LatentEffectivenessat75CoolingAirFlow']
      values['Latent Cooling'][1.0] = erv_info['LatentEffectivenessat100CoolingAirFlow']
      heat_exchanger_air_to_air_sensible_and_latent = OpenstudioStandards::HVAC.heat_exchanger_air_to_air_set_effectiveness_values(heat_exchanger_air_to_air_sensible_and_latent, defaults: false, values: values)
    end
    heat_exchanger_air_to_air_sensible_and_latent.setSupplyAirOutletTemperatureControl(erv_info['SupplyAirOutletTemperatureControl'])
    heat_exchanger_air_to_air_sensible_and_latent.setFrostControlType(erv_info['FrostControlType'])
    heat_exchanger_air_to_air_sensible_and_latent.setEconomizerLockout(erv_info['EconomizerLockout'])
    heat_exchanger_air_to_air_sensible_and_latent.setThresholdTemperature(erv_info['ThresholdTemperature'])
    heat_exchanger_air_to_air_sensible_and_latent.setInitialDefrostTimeFraction(erv_info['InitialDefrostTimeFraction'])
    update_sys_name(heat_exchanger_air_to_air_sensible_and_latent.airLoopHVAC.get, sys_hr: 'erv')

    return true
  end

  # Determine if demand control ventilation (DCV) is
  # required for this air loop.
  #
  # @param (see #economizer_required?)
  # @return [Boolean] Returns true if required, false if not.
  # @todo Add exception logic for
  #   systems that serve multifamily, parking garage, warehouse
  def air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{template} #{climate_zone}:  #{air_loop_hvac.name}: DCV is not required for any system.")
    dcv_required = false
    return dcv_required
  end

  # Set the VAV damper control to single maximum or
  # dual maximum control depending on the standard.
  #
  # @return [Boolean] Returns true if successful, false if not
  # @todo see if this impacts the sizing run.
  def air_loop_hvac_apply_vav_damper_action(air_loop_hvac)
    damper_action = 'Single Maximum'

    # Interpret this as an EnergyPlus input
    damper_action_eplus = nil
    if damper_action == 'Single Maximum'
      damper_action_eplus = 'Normal'
    elsif damper_action == 'Dual Maximum'
      # EnergyPlus 8.7 changed the meaning of 'Reverse'.
      # For versions of OpenStudio using E+ 8.6 or lower
      damper_action_eplus = if air_loop_hvac.model.version < OpenStudio::VersionString.new('2.0.5')
                              'Reverse'
                              # For versions of OpenStudio using E+ 8.7 or higher
                            else
                              'ReverseWithLimits'
                            end
    end

    # Set the control for any VAV reheat terminals
    # on this airloop.
    control_type_set = false
    air_loop_hvac.demandComponents.each do |equip|
      if equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
        term = equip.to_AirTerminalSingleDuctVAVReheat.get
        # Dual maximum only applies to terminals with HW reheat coils
        if damper_action == 'Dual Maximum'
          if term.reheatCoil.to_CoilHeatingWater.is_initialized
            term.setDamperHeatingAction(damper_action_eplus)
            control_type_set = true
          end
        else
          term.setDamperHeatingAction(damper_action_eplus)
          control_type_set = true
          term.setMaximumFlowFractionDuringReheat(0.5)
        end
      end
    end

    if control_type_set
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: VAV damper action was set to #{damper_action} control.")
    end

    return true
  end

  # NECB has no single zone air loop control requirements
  #
  # @return [Boolean] returns true if successful, false if not
  def air_loop_hvac_apply_single_zone_controls(air_loop_hvac, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: No special economizer controls were modeled.")
    return true
  end

  # NECB doesn't require static pressure reset.
  #
  # return [Boolean] returns true if static pressure reset is required, false if not
  def air_loop_hvac_static_pressure_reset_required?(air_loop_hvac, has_ddc)
    # static pressure reset not required
    sp_reset_required = false
    return sp_reset_required
  end

  # Determine the air flow and number of story limits
  # for whether motorized OA damper is required.
  # @return [Array<Double>] [minimum_oa_flow_cfm, maximum_stories].
  # If both nil, never required
  def air_loop_hvac_motorized_oa_damper_limits(air_loop_hvac, climate_zone)
    minimum_oa_flow_cfm = 0
    maximum_stories = 0
    return [minimum_oa_flow_cfm, maximum_stories]
  end

  # find search criteria
  #
  # @param boiler_hot_water [OpenStudio::Model::BoilerHotWater] hot water boiler object
  # @return [Hash] used for standards_lookup_table(model)
  def boiler_hot_water_find_search_criteria(boiler_hot_water)
    # Define the criteria to find the boiler properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template
    # Get fuel type
    fuel_type = nil
    case boiler_hot_water.fuelType
    when 'NaturalGas'
      fuel_type = 'Gas'
    when 'Electricity'
      fuel_type = 'Electric'
    when 'FuelOilNo1', 'FuelOilNo2'
      fuel_type = 'Oil'
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.BoilerHotWater', "For #{boiler_hot_water.name}, a fuel type of #{fuel_type} is not yet supported.  Assuming 'Gas.'")
      fuel_type = 'Gas'
    end

    search_criteria['fuel_type'] = fuel_type
    # Get the fluid type
    fluid_type = 'Hot Water'
    search_criteria['fluid_type'] = fluid_type
    return search_criteria
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param boiler_hot_water [OpenStudio::Model::BoilerHotWater] the object to modify
  # @return [Boolean] true if successful, false if not
  def boiler_hot_water_apply_efficiency_and_curves(boiler_hot_water)
    successfully_set_all_properties = false

    # Define the criteria to find the boiler properties
    # in the hvac standards data set.
    search_criteria = boiler_hot_water_find_search_criteria(boiler_hot_water)
    fuel_type = search_criteria['fuel_type']
    fluid_type = search_criteria['fluid_type']

    # Get the capacity
    capacity_w = OpenstudioStandards::HVAC.boiler_hot_water_get_capacity(boiler_hot_water)

    boiler_capacity = capacity_w
    # Use the NECB capacities if the SystemFuels class is not defined (i.e. this method was not called from something
    # that created a SystemFuels object) or if either primary or secondary boiler capacity fractions are not defined.
    if !self.fuel_type_set.is_a?(SystemFuels) || self.fuel_type_set.primary_boiler_cap_frac.nil? || self.fuel_type_set.secondary_boiler_cap_frac.nil?
      # Check if secondary and/or modulating boiler required
      # If boiler names include 'Primary Boiler' or 'Secondary Boiler' then NECB rules are applied
      if boiler_hot_water.name.to_s.include?('Primary Boiler') || boiler_hot_water.name.to_s.include?('Secondary Boiler')
        if capacity_w / 1000.0 >= 352.0
          if boiler_hot_water.name.to_s.include?('Primary Boiler')
            boiler_capacity = capacity_w
            boiler_hot_water.setBoilerFlowMode('LeavingSetpointModulated')
            boiler_hot_water.setMinimumPartLoadRatio(0.25)
          elsif boiler_hot_water.name.to_s.include?('Secondary Boiler')
            boiler_capacity = 0.001
          end
        elsif ((capacity_w / 1000.0) >= 176.0) && ((capacity_w / 1000.0) < 352.0)
          boiler_capacity = capacity_w / 2
        elsif (capacity_w / 1000.0) <= 176.0
          if boiler_hot_water.name.to_s.include?('Primary Boiler')
            if capacity_w <= 1.0
              boiler_capacity = 1.0
            else
              boiler_capacity = capacity_w
            end
          elsif boiler_hot_water.name.to_s.include?('Secondary Boiler')
            boiler_capacity = 0.001
          end
        end
      end
    else
      boiler_capacity = capacity_w * self.fuel_type_set.primary_boiler_cap_frac if boiler_hot_water.name.to_s.include?('Primary Boiler')
      boiler_capacity = capacity_w * self.fuel_type_set.secondary_boiler_cap_frac if boiler_hot_water.name.to_s.include?('Secondary Boiler')
    end
    boiler_hot_water.setNominalCapacity(boiler_capacity)

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(boiler_capacity, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(boiler_capacity, 'W', 'kBtu/hr').get

    # Get the boiler properties
    boiler_table = @standards_data['boilers']
    blr_props = model_find_object(boiler_table, search_criteria, capacity_btu_per_hr)
    unless blr_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.BoilerHotWater', "For #{boiler_hot_water.name}, cannot find boiler properties, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the EFFFPLR curve
    eff_fplr = model_add_curve(boiler_hot_water.model, blr_props['efffplr'])
    if eff_fplr
      boiler_hot_water.setNormalizedBoilerEfficiencyCurve(eff_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.BoilerHotWater', "For #{boiler_hot_water.name}, cannot find eff_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Get the minimum efficiency standards
    thermal_eff = nil

    # If specified as AFUE
    unless blr_props['minimum_annual_fuel_utilization_efficiency'].nil?
      min_afue = blr_props['minimum_annual_fuel_utilization_efficiency']
      thermal_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(min_afue)
      new_comp_name = "#{boiler_hot_water.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_afue} AFUE"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{boiler_hot_water.name}: #{fuel_type} #{fluid_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; AFUE = #{min_afue}")
    end

    # If specified as thermal efficiency
    unless blr_props['minimum_thermal_efficiency'].nil?
      thermal_eff = blr_props['minimum_thermal_efficiency']
      new_comp_name = "#{boiler_hot_water.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{thermal_eff} Thermal Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{boiler_hot_water.name}: #{fuel_type} #{fluid_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Thermal Efficiency = #{thermal_eff}")
    end

    # If specified as combustion efficiency
    unless blr_props['minimum_combustion_efficiency'].nil?
      min_comb_eff = blr_props['minimum_combustion_efficiency']
      thermal_eff = OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff(min_comb_eff)
      new_comp_name = "#{boiler_hot_water.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_comb_eff} Combustion Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{boiler_hot_water.name}: #{fuel_type} #{fluid_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Combustion Efficiency = #{min_comb_eff}")
    end

    # Set the name
    boiler_hot_water.setName(new_comp_name)

    # Set the efficiency values
    unless thermal_eff.nil?
      boiler_hot_water.setNominalThermalEfficiency(thermal_eff)
    end

    return successfully_set_all_properties
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Boolean] true if successful, false if not
  def chiller_electric_eir_apply_efficiency_and_curves(chiller_electric_eir, clg_tower_objs)
    # Define the criteria to find the chiller properties
    # in the hvac standards data set.
    search_criteria = chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    cooling_type = search_criteria['cooling_type']
    condenser_type = search_criteria['condenser_type']
    compressor_type = search_criteria['compressor_type']

    # Get the chiller capacity
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)

    # All chillers must be modulating down to 25% of their capacity
    chiller_electric_eir.setChillerFlowMode('LeavingSetpointModulated')
    chiller_electric_eir.setMinimumPartLoadRatio(0.25)
    chiller_electric_eir.setMinimumUnloadingRatio(0.25)
    chiller_capacity = capacity_w
    # If the chiller name includes 'Primary' or 'Secondary' then apply NECB rules
    if (chiller_electric_eir.name.to_s.include? 'Primary') || (chiller_electric_eir.name.to_s.include? 'Secondary')
      if (capacity_w / 1000.0) < 2100.0
        if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
          chiller_capacity = capacity_w
        elsif chiller_electric_eir.name.to_s.include? 'Secondary Chiller'
          chiller_capacity = 0.001
        end
      else
        chiller_capacity = capacity_w / 2.0
      end
    end
    chiller_electric_eir.setReferenceCapacity(chiller_capacity)

    # Convert capacity to tons
    capacity_tons = OpenStudio.convert(chiller_capacity, 'W', 'ton').get

    # Get chiller compressor type if needed
    chiller_types = ['reciprocating','scroll','rotary screw','centrifugal']
    chiller_name_has_type = chiller_types.any? {|type| chiller_electric_eir.name.to_s.downcase.include? type}
    unless chiller_name_has_type
      chlr_type_search_criteria = {}
      chlr_type_search_criteria['cooling_type'] = cooling_type
      chlr_types_table = @standards_data['chiller_types']
      chlr_type_props = model_find_object(chlr_types_table, chlr_type_search_criteria, capacity_tons)
      unless chlr_type_props
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller type information")
        successfully_set_all_properties = false
        return successfully_set_all_properties
      end
      compressor_type = chlr_type_props['compressor_type']
      chiller_electric_eir.setName(chiller_electric_eir.name.to_s + ' ' + compressor_type)
    end
    # Get the chiller properties
    search_criteria['compressor_type'] = compressor_type
    chlr_table = @standards_data['chillers']
    chlr_props = model_find_object(chlr_table, search_criteria, capacity_tons, Date.today)
    unless chlr_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller properties, cannot apply standard efficiencies or curves.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the CAPFT curve
    cool_cap_ft = model_add_curve(chiller_electric_eir.model, chlr_props['capft'])
    if cool_cap_ft
      chiller_electric_eir.setCoolingCapacityFunctionOfTemperature(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFT curve
    cool_eir_ft = model_add_curve(chiller_electric_eir.model, chlr_props['eirft'])
    if cool_eir_ft
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfTemperature(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFPLR curve
    # which may be either a CurveBicubic or a CurveQuadratic based on chiller type
    cool_plf_fplr = model_add_curve(chiller_electric_eir.model, chlr_props['eirfplr'])
    if cool_plf_fplr
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfPLR(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Set the efficiency value
    kw_per_ton = nil
    cop = nil
    if chlr_props['minimum_full_load_efficiency']
      kw_per_ton = chlr_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
      chiller_electric_eir.setReferenceCOP(cop)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency, will not be set.")
      successfully_set_all_properties = false
    end

    # Set cooling tower properties now that the new COP of the chiller is set
    if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
      # Get the cooling tower based on the condenser water loop rather than assume that there is only one cooling tower loop.
      clg_towers = []
      tower_cap = capacity_w * (1.0 + 1.0 / chiller_electric_eir.referenceCOP)
      condenser_loop = chiller_electric_eir.condenserWaterLoop.get
      condenser_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_CoolingTowerSingleSpeed.is_initialized
          clg_towers << supply_comp.to_CoolingTowerSingleSpeed.get
        end
      end
      # Single speed tower model assumes 25% extra for compressor power
      tower_cap = capacity_w * (1.0 + 1.0 / chiller_electric_eir.referenceCOP)
      if (tower_cap / 1000.0) < 1750
        clg_towers[0].setNumberofCells(1)
      else
        clg_towers[0].setNumberofCells((tower_cap / (1000 * 1750) + 0.5).round)
      end
            # Only apply cooling tower fan power if power is greater than 13kW.  This is to avoid EnergyPlus issues with some small cooling towers.
      clg_towers[0].setFanPoweratDesignAirFlowRate(0.015 * tower_cap) if (tower_cap * 0.015 > 13000.0)
    end

    # Append the name with size and kw/ton
    chiller_electric_eir.setName("#{chiller_electric_eir.name} #{capacity_tons.round}tons #{kw_per_ton.round(1)}kW/ton")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.ChillerElectricEIR', "For #{template}: #{chiller_electric_eir.name}: #{cooling_type} #{condenser_type} #{compressor_type} Capacity = #{capacity_tons.round}tons; COP = #{cop.round(1)} (#{kw_per_ton.round(1)}kW/ton)")

    return successfully_set_all_properties
  end

  # find search criteria
  #
  # @return [Hash] used for standards_lookup_table(model)
  def coil_heating_gas_find_search_criteria
    # Define the criteria to find the furnace properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['fluid_type'] = 'Air'
    search_criteria['fuel_type'] = 'Gas'

    return search_criteria
  end

  # Finds lookup object in standards and return minimum thermal efficiency
  #
  # @return [Double] minimum thermal efficiency
  def coil_heating_gas_standard_minimum_thermal_efficiency(coil_heating_gas, rename = false)
    # Get the coil properties
    search_criteria = coil_heating_gas_find_search_criteria
    capacity_w = OpenstudioStandards::HVAC.coil_heating_gas_get_capacity(coil_heating_gas)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Get the minimum efficiency standards
    thermal_eff = nil

    # Get the coil properties
    coil_table = @standards_data['furnaces']
    coil_props = model_find_object(coil_table, search_criteria, [capacity_btu_per_hr, 0.001].max)

    unless coil_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find coil props, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # New name initial value
    new_comp_name = coil_heating_gas.name

    # If specified as AFUE
    unless coil_props['minimum_annual_fuel_utilization_efficiency'].nil?
      min_afue = coil_props['minimum_annual_fuel_utilization_efficiency']
      thermal_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(min_afue)
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_afue} AFUE"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; AFUE = #{min_afue}")
    end

    # If specified as thermal efficiency
    unless coil_props['minimum_thermal_efficiency'].nil?
      thermal_eff = coil_props['minimum_thermal_efficiency']
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{thermal_eff} Thermal Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Thermal Efficiency = #{thermal_eff}")
    end

    # If specified as combustion efficiency
    unless coil_props['minimum_combustion_efficiency'].nil?
      min_comb_eff = coil_props['minimum_combustion_efficiency']
      thermal_eff = OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff(min_comb_eff)
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_comb_eff} Combustion Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Combustion Efficiency = #{min_comb_eff}")
    end

    unless thermal_eff
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{CoilHeatingGas.name}, cannot find coil efficiency, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Rename
    if rename
      coil_heating_gas.setName(new_comp_name)
    end

    return thermal_eff
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Boolean] true if successful, false if not
  def coil_heating_gas_apply_efficiency_and_curves(coil_heating_gas)
    successfully_set_all_properties = true

    # Define the search criteria
    search_criteria = coil_heating_gas_find_search_criteria

    # Get the coil capacity
    capacity_w = OpenstudioStandards::HVAC.coil_heating_gas_get_capacity(coil_heating_gas)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # lookup properties
    coil_table = @standards_data['furnaces']
    coil_props = model_find_object(coil_table, search_criteria, [capacity_btu_per_hr, 0.001].max, Date.today)

    # Check to make sure properties were found
    if coil_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      successfully_set_all_properties = false
    end

    # Make the plf vs plr curve
    plffplr_curve = model_add_curve(coil_heating_gas.model, coil_props['efffplr'])
    if plffplr_curve
      coil_heating_gas.setPartLoadFractionCorrelationCurve(plffplr_curve)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find plffplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Thermal efficiency
    thermal_eff = coil_heating_gas_standard_minimum_thermal_efficiency(coil_heating_gas)

    # Set the efficiency values
    coil_heating_gas.setGasBurnerEfficiency(thermal_eff.to_f)

    return successfully_set_all_properties
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Boolean] true if successful, false if not
  def coil_cooling_dx_multi_speed_apply_efficiency_and_curves(coil_cooling_dx_multi_speed, sql_db_vars_map)
    successfully_set_all_properties = true
    model = coil_cooling_dx_multi_speed.model
    multi_speed_heat_pump = coil_cooling_dx_multi_speed.containingHVACComponent.get.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
    airloop = multi_speed_heat_pump.airLoopHVAC.get

    # Define the criteria to find the properties in the hvac standards data set
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_multi_speed)
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_multi_speed_get_capacity(coil_cooling_dx_multi_speed)

    # Find design outside air flow rate and flow fraction
    controller_oa = nil
    if airloop.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = airloop.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
    end
    min_oa_flow_rate = 0.0
    oaf = 0.0

    if controller_oa
      min_oa_flow_rate = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        min_oa_flow_rate = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        min_oa_flow_rate = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      end
      if min_oa_flow_rate then oaf = min_oa_flow_rate.to_f / airloop.autosizedDesignSupplyAirFlowRate.to_f end
    end

    # Find required capacity of each stage and total number of stages based on NECB rules
    # This implementation is limited to 4 stages only. The capacity of stages 1-3 is set to
    # 66 kW as stipulated by NECB. The capacity of the 4th stage is then allowed to exceed 66 kW
    # up to the design capacity.
    stage_cap = []
    num_stages = (capacity_w / (66.0 * 1000.0) + 0.5).round
    max_cap = 66.0 * 1000.0 * num_stages
    final_num_stages = num_stages
    case num_stages
    when 1
      stage_cap[0] = capacity_w / 2.0
      stage_cap[1] = 2.0 * stage_cap[0]
      final_num_stages = 2
    else
      stage_cap[0] = 66.0 * 1000.0
      stage_cap[1] = 2.0 * stage_cap[0]
      case num_stages
      when 2
      when 3
        stage_cap[2] = 3.0 * stage_cap[0]
      else
        final_num_stages = 4
        stage_cap[2] = 3.0 * stage_cap[0]
        stage_cap[3] = max_cap
      end
    end

    # Set final number of cooling stages and create missing stages if needed
    for istage in 2..final_num_stages - 1
      new_clg_stage = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      coil_cooling_dx_multi_speed.addStage(new_clg_stage)
    end
    multi_speed_heat_pump.setNumberofSpeedsforCooling(final_num_stages)

    # Set final capacities for each of the stages. The flow rate for each of the stages
    # is maintained above the outside air flow rate
    coil_cooling_dx_multi_speed.stages[0].setGrossRatedTotalCoolingCapacity(stage_cap[0])
    coil_cooling_dx_multi_speed.stages[1].setGrossRatedTotalCoolingCapacity(stage_cap[1])
    case coil_cooling_dx_multi_speed.stages.size
    when 2
      if oaf > 0.5 then multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate) end
    when 3
      coil_cooling_dx_multi_speed.stages[2].setGrossRatedTotalCoolingCapacity(stage_cap[2])
      if (oaf > 0.333) && (oaf <= 0.666)
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
      elsif oaf > 0.666
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed2SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
      end
    when 4
      coil_cooling_dx_multi_speed.stages[2].setGrossRatedTotalCoolingCapacity(stage_cap[2])
      coil_cooling_dx_multi_speed.stages[3].setGrossRatedTotalCoolingCapacity(stage_cap[3])
      if (oaf > 0.25) && (oaf <= 0.5)
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
      elsif (oaf > 0.5) && (oaf <= 0.75)
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed2SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
      elsif oaf > 0.75
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed2SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed3SupplyAirFlowRateDuringCoolingOperation(min_oa_flow_rate)
      end
    end

    capacity_btu_per_hr = OpenStudio.convert(stage_cap.last, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(stage_cap.last, 'W', 'kBtu/hr').get

    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    ac_props = nil
    ac_props = if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_multi_speed)
                 model_find_object(standards_data['heat_pumps'], search_criteria, capacity_btu_per_hr, Date.today)
               else
                 model_find_object(standards_data['unitary_acs'], search_criteria, capacity_btu_per_hr, Date.today)
               end

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find efficiency info, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # get clg stages
    clg_stages = coil_cooling_dx_multi_speed.stages

    # Make the COOL-CAP-FT curve
    cool_cap_ft = model_add_curve(model, ac_props['cool_cap_ft'])
    if cool_cap_ft
      clg_stages.sort.each do |stage|
        stage.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = model_add_curve(model, ac_props['cool_cap_fflow'])
    if cool_cap_fflow
      clg_stages.sort.each do |stage|
        stage.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = model_add_curve(model, ac_props['cool_eir_ft'])
    if cool_eir_ft
      clg_stages.sort.each do |stage|
        stage.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = model_add_curve(model, ac_props['cool_eir_fflow'])
    if cool_eir_fflow
      clg_stages.sort.each do |stage|
        stage.setEnergyInputRatioFunctionofFlowFractionCurve(cool_eir_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = model_add_curve(model, ac_props['cool_plf_fplr'])
    if cool_plf_fplr
      clg_stages.sort.each do |stage|
        stage.setPartLoadFractionCorrelationCurve(cool_plf_fplr)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # Set the COP values
    cop, new_comp_name = coil_cooling_dx_multi_speed_standard_minimum_cop(coil_cooling_dx_multi_speed)
    unless cop.nil?
      clg_stages.sort.each do |curr_istage|
        curr_istage.setGrossRatedCoolingCOP(cop)
      end
    end
    sql_db_vars_map[new_comp_name] = coil_cooling_dx_multi_speed.name.to_s
    coil_cooling_dx_multi_speed.setName(new_comp_name)

    # It was found that the heat pump OS object doesn't respond to the call to turn on from the
    # system availability manager night cycle. This EMS script is then implemented to check the status
    # of the system availability manager night cycle and force the heat pump to turn on when needed. The
    # heat pump is still turned on when its availability schedule calls for it.
    create_ems_to_turn_on_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed_for_night_cycle(multi_speed_heat_pump)

    return sql_db_vars_map
  end

  # Create EMS to turn on "AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed" in response to a call
  # from the night cycle availability manager of the air loop. It was found that this object
  # doesn't respond properly to this call from the night cycle
  def create_ems_to_turn_on_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed_for_night_cycle(multi_speed_heat_pump)
    model = multi_speed_heat_pump.model
    avail_manager_name = nil
    if multi_speed_heat_pump.airLoopHVAC.is_initialized
      if !multi_speed_heat_pump.airLoopHVAC.get.availabilityManagers.empty?
        avail_manager_name = multi_speed_heat_pump.airLoopHVAC.get.availabilityManagers[0].name.to_s
      end
    end
    return unless avail_manager_name

    avail_manager_out_var_name = 'Availability Manager Night Cycle Control Status'
    avail_manager_out_var = OpenStudio::Model::OutputVariable.new(avail_manager_out_var_name, model)
    avail_manager_out_var.setKeyValue(avail_manager_name)
    avail_manager_out_var.setReportingFrequency('Timestep')
    night_cycle_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, avail_manager_out_var)
    heat_pump_avail_sch = nil
    if multi_speed_heat_pump.availabilitySchedule.is_initialized
      heat_pump_avail_sch = multi_speed_heat_pump.availabilitySchedule.get
    elsif multi_speed_heat_pump.airLoopHVAC.get.availabilitySchedule.is_initialized
      heat_pump_avail_sch = multi_speed_heat_pump.airLoopHVAC.get.availabilitySchedule.get
    else
      heat_pump_avail_sch = OpenStudio::Model::ScheduleConstant.new(model)
      heat_pump_avail_sch.setValue(1.0)
    end
    heat_pump_avail_sch_var = OpenStudio::Model::OutputVariable.new('Schedule Value', model)
    heat_pump_avail_sch_var.setKeyValue(heat_pump_avail_sch.name.to_s)
    heat_pump_avail_sch_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, heat_pump_avail_sch_var)
    updated_heat_pump_avail_sch = OpenStudio::Model::ScheduleConstant.new(model)
    multi_speed_heat_pump.setAvailabilitySchedule(updated_heat_pump_avail_sch)
    # This method will seem like an error in number of args..but this is due to swig voodoo.
    heat_pump_avail_sch_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(updated_heat_pump_avail_sch, 'Schedule:Constant', 'Schedule Value')
    heat_pump_avail_sch_prog = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    heat_pump_avail_sch_prog.setName("#{OpenstudioStandards::HVAC.ems_friendly_name(multi_speed_heat_pump.name)} Availability Schedule Program by Line")
    heat_pump_avail_sch_prog_body = <<-EMS
        IF #{heat_pump_avail_sch_sensor.handle} > 0.0
          SET #{heat_pump_avail_sch_actuator.handle} = #{heat_pump_avail_sch_sensor.handle}
        ELSEIF #{night_cycle_sensor.handle} == 2.0
          SET #{heat_pump_avail_sch_actuator.handle} = 1.0
        ELSE
          SET #{heat_pump_avail_sch_actuator.handle} = 0.0
        ENDIF
    EMS
    heat_pump_avail_sch_prog.setBody(heat_pump_avail_sch_prog_body)
    pcm = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    pcm.setName("#{heat_pump_avail_sch_prog.name} Calling Manager")
    pcm.setCallingPoint('InsideHVACSystemIterationLoop')
    pcm.addProgram(heat_pump_avail_sch_prog)
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Boolean] true if successful, false if not
  def coil_heating_gas_multi_stage_apply_efficiency_and_curves(coil_heating_gas_multi_stage)
    successfully_set_all_properties = true
    model = coil_heating_gas_multi_stage.model

    # get multi speed heat pump and air loop
    multi_speed_heat_pump = nil
    multi_speed_heat_pumps = model.getAirLoopHVACUnitaryHeatPumpAirToAirMultiSpeeds
    multi_speed_heat_pumps.sort.each do |iheat_pump|
      htg_coil = iheat_pump.heatingCoil
      if htg_coil.name.to_s.strip == coil_heating_gas_multi_stage.name.to_s.strip
        multi_speed_heat_pump = iheat_pump
        break
      end
    end
    airloop = multi_speed_heat_pump.airLoopHVAC.get

    # Define the criteria to find the properties in the hvac standards data set.
    search_criteria = coil_heating_gas_multi_stage_find_search_criteria(coil_heating_gas_multi_stage)
    fuel_type = search_criteria['fuel_type']
    capacity_w = OpenstudioStandards::HVAC.coil_heating_gas_multi_stage_get_capacity(coil_heating_gas_multi_stage)

    # Find system design outside air flow rate and fraction
    controller_oa = nil
    if airloop.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = airloop.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
    end
    min_oa_flow_rate = 0.0
    oaf = 0.0
    if controller_oa
      min_oa_flow_rate = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        min_oa_flow_rate = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        min_oa_flow_rate = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      end
      if min_oa_flow_rate then oaf = min_oa_flow_rate.to_f / airloop.autosizedDesignSupplyAirFlowRate.to_f end
    end

    # Find capacities of each of the stages and the total number of stages required based on NECB rules.
    # This implementation is limited to 4 stages. The capacity of stages 1-3 is set to 66 kW as stipulated
    # by NECB. The capacity of the 4th stage can exceed 66 kW up to the design capacity.
    htg_stages = coil_heating_gas_multi_stage.stages
    num_stages = (capacity_w / (66.0 * 1000.0) + 0.5).round
    max_cap = 66.0 * 1000.0 * num_stages
    stage_cap = []
    final_num_stages = num_stages
    if capacity_w == 0.001
      final_num_stages = 1
      stage_cap[0] = capacity_w
    else
      case num_stages
      when 1
        stage_cap[0] = capacity_w / 2.0
        stage_cap[1] = 2.0 * stage_cap[0]
        final_num_stages = 2
      else
        stage_cap[0] = 66.0 * 1000.0
        stage_cap[1] = 2.0 * stage_cap[0]
        case num_stages
        when 2
        when 3
          stage_cap[2] = 3.0 * stage_cap[0]
        else
          final_num_stages = 4
          stage_cap[2] = 3.0 * stage_cap[0]
          stage_cap[3] = max_cap
        end
      end
    end

    # Set final number of stages and create missing stages if needed
    for istage in 1..final_num_stages - 1
      new_htg_stage = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      coil_heating_gas_multi_stage.addStage(new_htg_stage)
    end
    multi_speed_heat_pump.setNumberofSpeedsforHeating(final_num_stages)

    # Set final capacities for each of the stages. The air flow rate for each of the stages
    # is maintained above the outside air flow rate
    coil_heating_gas_multi_stage.stages[0].setNominalCapacity(stage_cap[0])
    case coil_heating_gas_multi_stage.stages.size
    when 2
      coil_heating_gas_multi_stage.stages[1].setNominalCapacity(stage_cap[1])
      if oaf > 0.5 then multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate) end
    when 3
      coil_heating_gas_multi_stage.stages[1].setNominalCapacity(stage_cap[1])
      coil_heating_gas_multi_stage.stages[2].setNominalCapacity(stage_cap[2])
      if (oaf > 0.333) && (oaf <= 0.666)
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
      elsif oaf > 0.666
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed2SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
      end
    when 4
      coil_heating_gas_multi_stage.stages[1].setNominalCapacity(stage_cap[1])
      coil_heating_gas_multi_stage.stages[2].setNominalCapacity(stage_cap[2])
      coil_heating_gas_multi_stage.stages[3].setNominalCapacity(stage_cap[3])
      if (oaf > 0.25) && (oaf <= 0.5)
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
      elsif (oaf > 0.5) && (oaf <= 0.75)
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed2SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
      elsif oaf > 0.75
        multi_speed_heat_pump.setSpeed1SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed2SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
        multi_speed_heat_pump.setSpeed3SupplyAirFlowRateDuringHeatingOperation(min_oa_flow_rate)
      end
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(stage_cap.last, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(stage_cap.last, 'W', 'kBtu/hr').get

    # Lookup efficiencies
    heater_props = nil
    heater_props = model_find_object(standards_data['furnaces'], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if heater_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGasMultiSpeed', "For #{coil_heating_gas_multi_stage.name}, cannot find efficiency info, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the EFFPLR curve
    efffplr = model_add_curve(coil_heating_gas_multi_stage.model, heater_props['efffplr'])
    if efffplr
      coil_heating_gas_multi_stage.setPartLoadFractionCorrelationCurve(efffplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGasMultiStage', "For #{coil_heating_gas_multi_stage.name}, cannot find efffplr curve, will not be set.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency standards
    thermal_eff = nil

    # If specified as AFUE
    unless heater_props['minimum_annual_fuel_utilization_efficiency'].nil?
      min_afue = heater_props['minimum_annual_fuel_utilization_efficiency']
      thermal_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(min_afue)
      new_comp_name = "#{coil_heating_gas_multi_stage.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_afue} AFUE"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGasMultiStage', "For #{template}: #{coil_heating_gas_multi_stage.name}: #{fuel_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; AFUE = #{min_afue}")
    end

    # If specified as thermal efficiency
    unless heater_props['minimum_thermal_efficiency'].nil?
      thermal_eff = heater_props['minimum_thermal_efficiency']
      new_comp_name = "#{coil_heating_gas_multi_stage.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{thermal_eff} Thermal Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGasMultiStage', "For #{template}: #{coil_heating_gas_multi_stage.name}: #{fuel_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Thermal Efficiency = #{thermal_eff}")
    end

    # If specified as combustion efficiency
    unless heater_props['minimum_combustion_efficiency'].nil?
      min_comb_eff = heater_props['minimum_combustion_efficiency']
      thermal_eff = OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff(min_comb_eff)
      new_comp_name = "#{coil_heating_gas_multi_stage.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_comb_eff} Combustion Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{coil_heating_gas_multi_stage.name}: #{fuel_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Combustion Efficiency = #{min_comb_eff}")
    end
    coil_heating_gas_multi_stage.setName(new_comp_name)

    # Set the name
    coil_heating_gas_multi_stage.setName(new_comp_name)

    # Get heating stages
    htg_stages = coil_heating_gas_multi_stage.stages

    # Set the efficiency values
    unless thermal_eff.nil?
      htg_stages.sort.each do |stage|
        stage.setGasBurnerEfficiency(thermal_eff)
      end
    end

    return successfully_set_all_properties
  end

  # Determines the baseline fan impeller efficiency
  # based on the specified fan type.
  #
  # @return [Double] impeller efficiency (0.0 to 1.0)
  # @todo Add fan type to data model and modify this method
  def fan_baseline_impeller_efficiency(fan)
    # Assume that the fan efficiency is 65% for normal fans
    # @todo add fan type to fan data model
    # and infer impeller efficiency from that?
    # or do we always assume a certain type of
    # fan impeller for the baseline system?
    # @todo check COMNET and T24 ACM and PNNL 90.1 doc
    fan_impeller_eff = 0.65

    return fan_impeller_eff
  end

  # Determines the minimum fan motor efficiency and nominal size
  # for a given motor bhp.  This should be the total brake horsepower with
  # any desired safety factor already included.  This method picks
  # the next nominal motor catgory larger than the required brake
  # horsepower, and the efficiency is based on that size.  For example,
  # if the bhp = 6.3, the nominal size will be 7.5HP and the efficiency
  # for 90.1-2010 will be 91.7% from Table 10.8B.  This method assumes
  # 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)
    fan_motor_eff = 0.85
    nominal_hp = motor_bhp

    # Don't attempt to look up motor efficiency
    # for zero-hp fans, which may occur when there is no
    # airflow required for a particular system, typically
    # heated-only spaces with high internal gains
    # and no OA requirements such as elevator shafts.
    return [fan_motor_eff, 0] if motor_bhp == 0.0

    # Lookup the minimum motor efficiency
    motors_table = @standards_data['motors']

    # Assuming all fan motors are 4-pole ODP
    motor_use = 'FAN'
    motor_type = ''
    if (fan.class.name == 'OpenStudio::Model::FanConstantVolume') || (fan.class.name == 'OpenStudio::Model::FanOnOff')
      motor_type = 'CONSTANT'
    elsif fan.class.name == 'OpenStudio::Model::FanVariableVolume'
      # Is this a return or supply fan
      if fan.name.to_s.include?('Supply')
        motor_type += 'VARIABLE-SUPPLY'
      elsif fan.name.to_s.include?('Return')
        motor_type += 'VARIABLE-RETURN'
      end
      # 0.909 corrects for 10% over sizing implemented upstream
      # 0.7457 is to convert from bhp to kW
      fan_power_kw = 0.909 * 0.7457 * motor_bhp
      power_vs_flow_curve_name = if fan_power_kw >= 25.0
                                   'VarVolFan-FCInletVanes-NECB2011-FPLR'
                                 elsif fan_power_kw >= 7.5 && fan_power_kw < 25
                                   'VarVolFan-AFBIInletVanes-NECB2011-FPLR'
                                 else
                                   'VarVolFan-AFBIFanCurve-NECB2011-FPLR'
                                 end
      power_vs_flow_curve = model_add_curve(fan.model, power_vs_flow_curve_name)
      fan.setFanPowerMinimumFlowRateInputMethod('Fraction')
      fan.setFanPowerCoefficient5(0.0)
      fan.setFanPowerMinimumFlowFraction(power_vs_flow_curve.minimumValueofx)
      fan.setFanPowerCoefficient1(power_vs_flow_curve.coefficient1Constant)
      fan.setFanPowerCoefficient2(power_vs_flow_curve.coefficient2x)
      fan.setFanPowerCoefficient3(power_vs_flow_curve.coefficient3xPOW2)
      fan.setFanPowerCoefficient4(power_vs_flow_curve.coefficient4xPOW3)
    elsif fan.class.name == 'OpenStudio::Model::FanZoneExhaust'
      motor_type = 'CONSTANT-RETURN'
    else
      raise('')
    end

    search_criteria = {
      'motor_use' => motor_use,
      'motor_type' => motor_type,
      'number_of_poles' => 4.0,
      'type' => 'Enclosed'
    }

    # Exception for small fans, including
    # zone exhaust, fan coil, and fan powered terminals.
    # In this case, use the 0.5 HP for the lookup.
    if fan_small_fan?(fan)
      nominal_hp = 0.5
    else
      motor_properties = model_find_object(motors_table, search_criteria, motor_bhp)
      if motor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
        return [fan_motor_eff, nominal_hp]
      end

      nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
      # If the biggest fan motor size is hit, use the highest category efficiency
      if nominal_hp == 9999.0
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Fan', "For #{fan.name}, there is no greater nominal HP.  Use the efficiency of the largest motor category.")
        nominal_hp = motor_bhp
      end

      # Round to nearest whole HP for niceness
      if nominal_hp >= 2
        nominal_hp = nominal_hp.round
      end
    end

    # Get the efficiency based on the nominal horsepower
    # Add 0.01 hp to avoid search errors.
    motor_properties = model_find_object(motors_table, search_criteria, nominal_hp + 0.01)

    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
      return [fan_motor_eff, nominal_hp]
    end
    fan_motor_eff = motor_properties['nominal_full_load_efficiency']

    return [fan_motor_eff, nominal_hp]
  end

  # Determines the minimum pump motor efficiency and nominal size
  # for a given motor bhp.  This should be the total brake horsepower with
  # any desired safety factor already included.  This method picks
  # the next nominal motor catgory larger than the required brake
  # horsepower, and the efficiency is based on that size.  For example,
  # if the bhp = 6.3, the nominal size will be 7.5HP and the efficiency
  # for 90.1-2010 will be 91.7% from Table 10.8B.  This method assumes
  # 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def pump_standard_minimum_motor_efficiency_and_size(pump, motor_bhp)
    motor_eff = 0.85
    nominal_hp = motor_bhp

    # Don't attempt to look up motor efficiency
    # for zero-hp pumps (required for circulation-pump-free
    # service water heating systems).
    return [1.0, 0] if motor_bhp == 0.0

    # Lookup the minimum motor efficiency
    motors = @standards_data['motors']

    # Assuming all pump motors are 4-pole ODP
    search_criteria = {
      'motor_use' => 'PUMP',
      'number_of_poles' => 4.0,
      'type' => 'Enclosed'
    }

    motor_properties = model_find_object(motors, search_criteria, motor_bhp)
    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Pump', "For #{pump.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
      return [motor_eff, nominal_hp]
    end

    motor_eff = motor_properties['nominal_full_load_efficiency']
    nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    # Get the efficiency based on the nominal horsepower
    # Add 0.01 hp to avoid search errors.
    motor_properties = model_find_object(motors, search_criteria, nominal_hp + 0.01)
    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{pump.name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
      return [motor_eff, nominal_hp]
    end
    motor_eff = motor_properties['nominal_full_load_efficiency']

    return [motor_eff, nominal_hp]
  end

  # Determines whether there is a requirement to have a
  # VSD or some other method to reduce fan power
  # at low part load ratios.
  def fan_variable_volume_part_load_fan_power_limitation?(fan_variable_volume)
    part_load_control_required = false
    return part_load_control_required
  end

  # Determine if demand control ventilation (DCV) is
  # required for this zone based on area and occupant density.
  # Does not account for System requirements like ERV, economizer, etc.
  # Those are accounted for in the AirLoopHVAC method of the same name.
  #
  # @return [Boolean] Returns true if required, false if not.
  # @todo Add exception logic for 90.1-2013
  #   for cells, sickrooms, labs, barbers, salons, and bowling alleys
  def thermal_zone_demand_control_ventilation_required?(thermal_zone, climate_zone)
    return false
  end

  def model_apply_sizing_parameters(model)
    model.getSizingParameters.setHeatingSizingFactor(get_standards_constant('sizing_factor_max_heating'))
    model.getSizingParameters.setCoolingSizingFactor(get_standards_constant('sizing_factor_max_cooling'))
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Set sizing factors to #{get_standards_constant('sizing_factor_max_heating')} for heating and #{get_standards_constant('sizing_factor_max_heating')} for cooling.")
  end

  def fan_constant_volume_apply_prototype_fan_pressure_rise(fan_constant_volume)
    fan_constant_volume.setPressureRise(get_standards_constant('fan_constant_volume_pressure_rise_value'))
    return true
  end

  # Determine and set type of part load control type for heating and chilled
  # water variable speed pumps
  #
  # @param pump [OpenStudio::Model::PumpVariableSpeed] OpenStudio pump object
  # @return [Boolean] Returns true if applicable, false otherwise
  def pump_variable_speed_control_type(pump)
    return false
  end

  # Sets the fan pressure rise based on the Prototype buildings inputs
  # which are governed by the flow rate coming through the fan
  # and whether the fan lives inside a unit heater, PTAC, etc.
  def fan_variable_volume_apply_prototype_fan_pressure_rise(fan_variable_volume)
    # 1000 Pa for supply fan and 458.33 Pa for return fan (accounts for efficiency differences between two fans)
    if fan_variable_volume.name.to_s.include?('Supply')
      sfan_deltaP = get_standards_constant('supply_fan_variable_volume_pressure_rise_value')
      fan_variable_volume.setPressureRise(sfan_deltaP)
    elsif fan_variable_volume.name.to_s.include?('Return')
      rfan_deltaP = get_standards_constant('return_fan_variable_volume_pressure_rise_value')
      fan_variable_volume.setPressureRise(rfan_deltaP)
    end
    return true
  end

  def apply_economizers(climate_zone, model)
    # NECB2011 prescribes ability to provide 100% OA (5.2.2.7-5.2.2.9)
    econ_max_100_pct_oa_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    econ_max_100_pct_oa_sch.setName('Economizer Max OA Fraction 100 pct')
    econ_max_100_pct_oa_sch.defaultDaySchedule.setName('Economizer Max OA Fraction 100 pct Default')
    econ_max_100_pct_oa_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)

    # Check each airloop
    model.getAirLoopHVACs.sort.each do |air_loop|
      if air_loop_hvac_economizer_required?(air_loop) == true
        # If an economizer is required, determine the economizer type
        # in the prototype buildings, which depends on climate zone.
        economizer_type = nil

        # NECB 5.2.2.8 states that economizer can be controlled based on difference betweeen
        # return air temperature and outside air temperature OR return air enthalpy
        # and outside air enthalphy; latter chosen to be consistent with MNECB and CAN-QUEST implementation
        economizer_type = 'DifferentialEnthalpy'
        # Set the economizer type
        # Get the OA system and OA controller
        oa_sys = air_loop.airLoopHVACOutdoorAirSystem
        if oa_sys.is_initialized
          oa_sys = oa_sys.get
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but it has no OA system.")
          next
        end
        oa_control = oa_sys.getControllerOutdoorAir
        oa_control.setEconomizerControlType(economizer_type)
      end
    end
  end

  def set_zones_thermostat_schedule_based_on_space_type_schedules(model, runner = nil)
    puts 'in set_zones_thermostat_schedule_based_on_space_type_schedules'
    BTAP.runner_register('DEBUG', 'Start-set_zones_thermostat_schedule_based_on_space_type_schedules', runner)
    model.getThermalZones.sort.each do |zone|
      BTAP.runner_register('DEBUG', "Zone = #{zone.name} Spaces =#{zone.spaces.size} ", runner)
      array = []

      zone.spaces.sort.each do |space|
        schedule_type = determine_necb_schedule_type(space).to_s
        BTAP.runner_register('DEBUG', "space name/type:#{space.name}/#{schedule_type}", runner)

        # if wildcard space type, need to get dominant schedule type
        if '*'.to_s == schedule_type
          dominant_sched_type = determine_dominant_necb_schedule_type(model)
          schedule_type = dominant_sched_type
        end

        array << schedule_type
      end
      array.uniq!
      if array.size > 1
        BTAP.runner_register('Error', "#{zone.name} has spaces with different schedule types. Please ensure that all the spaces are of the same schedule type A to I.", runner)
        return false
      end

      htg_search_string = "NECB-#{array[0]}-Thermostat Setpoint-Heating"
      clg_search_string = "NECB-#{array[0]}-Thermostat Setpoint-Cooling"

      if model.getScheduleRulesetByName(htg_search_string).empty? == false
        htg_sched = model.getScheduleRulesetByName(htg_search_string).get
      else
        BTAP.runner_register('ERROR', "heating_thermostat_setpoint_schedule NECB-#{array[0]} does not exist", runner)
        return false
      end

      if model.getScheduleRulesetByName(clg_search_string).empty? == false
        clg_sched = model.getScheduleRulesetByName(clg_search_string).get
      else
        BTAP.runner_register('ERROR', "cooling_thermostat_setpoint_schedule NECB-#{array[0]} does not exist", runner)
        return false
      end

      name = "NECB-#{array[0]}-Thermostat Dual Setpoint Schedule"

      # If dual setpoint already exists, use that one, else create one
      ds = if model.getThermostatSetpointDualSetpointByName(name).empty? == false
             model.getThermostatSetpointDualSetpointByName(name).get
           else
             BTAP::Resources::Schedules.create_annual_thermostat_setpoint_dual_setpoint(model, name, htg_sched, clg_sched)
           end

      thermostat_clone = ds.clone.to_ThermostatSetpointDualSetpoint.get
      zone.setThermostatSetpointDualSetpoint(thermostat_clone)
      BTAP.runner_register('Info', "ThermalZone #{zone.name} set to DualSetpoint Schedule NECB-#{array[0]}", runner)
    end

    BTAP.runner_register('DEBUG', 'END-set_zones_thermostat_schedule_based_on_space_type_schedules', runner)
    return true
  end

  # Helper method to find out which climate zone set contains a specific climate zone.
  # Returns climate zone set name as String if success, nil if not found.
  def model_find_climate_zone_set(model, clim)
    return 'NECB-CNEB ClimatZone 4-8'
  end

  def setup_hw_loop_with_components(model,
                                    hw_loop,
                                    boiler_fueltype,
                                    backup_boiler_fueltype,
                                    pump_flow_sch)
    hw_loop.setName('Hot Water Loop')
    sizing_plant = hw_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    sizing_plant.setDesignLoopExitTemperature(82.0) #@todo units
    sizing_plant.setLoopDesignTemperatureDifference(16.0)

    # pump (set to variable speed for now till fix to run away plant temperature is found)
    # pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    # @todo the keyword "setPumpFlowRateSchedule" does not seem to work. A message
    # was sent to NREL to let them know about this. Once there is a fix for this,
    # use the proper pump schedule depending on whether we have two-pipe or four-pipe
    # fan coils.
    #            pump.resetPumpFlowRateSchedule()
    #            pump.setPumpFlowRateSchedule(pump_flow_sch)

    # boiler
    boiler1 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler2 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler1.setFuelType(boiler_fueltype)
    boiler2.setFuelType(backup_boiler_fueltype)
    boiler1.setName('Primary Boiler')
    boiler2.setName('Secondary Boiler')

    # boiler_bypass_pipe
    boiler_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # supply_outlet_pipe
    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # Add the components to the hot water loop
    hw_supply_inlet_node = hw_loop.supplyInletNode
    hw_supply_outlet_node = hw_loop.supplyOutletNode
    pump.addToNode(hw_supply_inlet_node)

    hw_loop.addSupplyBranchForComponent(boiler1)
    hw_loop.addSupplyBranchForComponent(boiler2)
    hw_loop.addSupplyBranchForComponent(boiler_bypass_pipe)
    supply_outlet_pipe.addToNode(hw_supply_outlet_node)

    # Add a setpoint manager to control the
    # hot water based on outdoor temperature
    hw_oareset_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
    hw_oareset_stpt_manager.setControlVariable('Temperature')
    hw_oareset_stpt_manager.setSetpointatOutdoorLowTemperature(82.0)
    hw_oareset_stpt_manager.setOutdoorLowTemperature(-16.0)
    hw_oareset_stpt_manager.setSetpointatOutdoorHighTemperature(60.0)
    hw_oareset_stpt_manager.setOutdoorHighTemperature(0.0)
    hw_oareset_stpt_manager.addToNode(hw_supply_outlet_node)
  end

  # of setup_hw_loop_with_components

  def setup_chw_loop_with_components(model, chw_loop, chiller_type)
    chw_loop.setName('Chilled Water Loop')
    sizing_plant = chw_loop.sizingPlant
    sizing_plant.setLoopType('Cooling')
    sizing_plant.setDesignLoopExitTemperature(7.0)
    sizing_plant.setLoopDesignTemperatureDifference(6.0)

    # Note: pump of 'chilled water loop' has been changed to the variable one as the constant one caused fatal errors for LargeOffice-Yellowknife-NaturalGas for some ECMs and inputs.
    # Fatal error was: 'CheckForRunawayPlantTemps: Simulation terminated because of run away plant temperatures, too cold' OR '..., too hot' for the PlantLoop of 'Chilled Water Loop'.
    # Note that the variable speed pump has been already used for 'Hot Water Loop'.
    chw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)

    chiller1 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller2 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller1.setCondenserType('WaterCooled')
    chiller2.setCondenserType('WaterCooled')
    chiller1_name = "Primary Chiller WaterCooled #{chiller_type}".strip
    chiller1.setName(chiller1_name)
    chiller2_name = "Secondary Chiller WaterCooled #{chiller_type}".strip
    chiller2.setName(chiller2_name)

    chiller_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    chw_supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # Add the components to the chilled water loop
    chw_supply_inlet_node = chw_loop.supplyInletNode
    chw_supply_outlet_node = chw_loop.supplyOutletNode
    chw_pump.addToNode(chw_supply_inlet_node)
    chw_loop.addSupplyBranchForComponent(chiller1)
    chw_loop.addSupplyBranchForComponent(chiller2)
    chw_loop.addSupplyBranchForComponent(chiller_bypass_pipe)
    chw_supply_outlet_pipe.addToNode(chw_supply_outlet_node)

    # Add a setpoint manager to control the
    # chilled water to a constant temperature
    chw_t_c = 7.0
    chw_t_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(model, 'CHW Temp', 'Temperature', chw_t_c)
    chw_t_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, chw_t_sch)
    chw_t_stpt_manager.addToNode(chw_supply_outlet_node)

    return chiller1, chiller2
  end

  # of setup_chw_loop_with_components

  def setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)
    cw_loop.setName('Condenser Water Loop')
    cw_sizing_plant = cw_loop.sizingPlant
    cw_sizing_plant.setLoopType('Condenser')
    cw_sizing_plant.setDesignLoopExitTemperature(29.0)
    cw_sizing_plant.setLoopDesignTemperatureDifference(6.0)

    # Note: pump of 'Condenser water loop' has been changed to the variable one as the constant one caused fatal errors for LargeOffice-Montreal-NaturalGas for some ECMs and inputs.
    # Fatal error was: 'Plant temperatures are getting far too cold, check controls and relative loads and capacities'.
    # Note that the variable speed pump has been already used for 'Hot Water Loop' and 'Chilled Water Loop'.
    cw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)

    clg_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)

    # TO DO: Need to define and set cooling tower curves

    clg_tower_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    cw_supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # Add the components to the condenser water loop
    cw_supply_inlet_node = cw_loop.supplyInletNode
    cw_supply_outlet_node = cw_loop.supplyOutletNode
    cw_pump.addToNode(cw_supply_inlet_node)
    clg_tower.setDesignInletAirWetBulbTemperature(24.0)
    clg_tower.setDesignInletAirDryBulbTemperature(35.0)
    clg_tower.setDesignApproachTemperature(5.0)
    clg_tower.setDesignRangeTemperature(6.0)
    cw_loop.addSupplyBranchForComponent(clg_tower)
    cw_loop.addSupplyBranchForComponent(clg_tower_bypass_pipe)
    cw_supply_outlet_pipe.addToNode(cw_supply_outlet_node)
    cw_loop.addDemandBranchForComponent(chiller1)
    cw_loop.addDemandBranchForComponent(chiller2)

    # Add a setpoint manager to control the
    # condenser water to constant temperature
    cw_t_c = 29.0
    cw_t_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(model, 'CW Temp', 'Temperature', cw_t_c)
    cw_t_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, cw_t_sch)
    cw_t_stpt_manager.addToNode(cw_supply_outlet_node)

    return clg_tower
  end

  # This method cycles through the spaces in a thermal zone and then sorts them by story.  The method then cycles
  # through the spaces on a story and then calculates the centroid of the spaces in the thermal zone on that floor.  The
  # method returns an array of hashes, one for each story.  Each hash has the following structure:
  #           {
  #               story_name: Name of a given story.
  #               spaces: Array containing all of the spaces in the thermal zone on the story in story_name.
  #               centroid: Array containing the x, y, and z coordinates of the centroid of the ceilings of the spaces
  #                         listed in 'spaces:' above.
  #               ceiling_area: Total area of the ceilings of the spaces in 'spaces:' above.
  #           }
  # Only spaces which are conditioned (heated or cooled) and are not plenums are included.
  def thermal_zone_get_centroid_per_floor(thermal_zone)
    stories = []
    thermal_zone.spaces.sort.each do |space|
      spaceType_name = space.spaceType.get.nameString
      sp_type = spaceType_name[15..-1]
      # Including regular expressions in the following match for cases where extra characters, which do not belong, are
      # added to either the space type in the model or the space type reference file.
      sp_type_info = @standards_data['space_types'].detect do |data|
        (Regexp.new(data['space_type'].to_s.upcase).match(sp_type.upcase) || Regexp.new(sp_type.upcase).match(data['space_type'].to_s.upcase) || (data['space_type'].to_s.upcase == sp_type.upcase)) &&
          (data['building_type'].to_s == 'Space Function')
      end
      if sp_type_info.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.thermal_zone_get_centroid_per_floor', "The space type called #{sp_type} could not be found.  Please check that the schedules.json file is available and that the space types are spelled correctly")
        next
      end
      # Determine if space is heated or cooled via spacetype heating or cooling setpoints also checking if the space is
      # a plenum by checking if there is a hvac system associtated with it
      if sp_type_info['heating_setpoint_schedule'].nil?
        heated = false
      else
        heated = true
      end
      if sp_type_info['cooling_setpoint_schedule'].nil?
        cooled = false
      else
        cooled = true
      end
      if (sp_type_info['necb_hvac_system_selection_type'] == '- undefined -') || /undefined/.match(sp_type_info['necb_hvac_system_selection_type'])
        not_plenum = false
      else
        not_plenum = true
      end
      # If the spaces are heated or cooled and are not a plenum then continue
      if (heated || cooled) && not_plenum
        # Get the story name and sit it to none if there is no story name
        story_name = space.buildingStory.get.nameString
        story_name = 'none' if story_name.nil?
        # If this is the first story in the arry then add a new one.
        if stories.empty?
          stories << {
            story_name: story_name,
            spaces: [space],
            centroid: [0, 0, 0],
            ceiling_area: 0
          }
          next
        else
          # If this is not the first story in the array check if the story already is in the array.
          i = nil
          stories.each_with_index do |storycheck, index|
            if storycheck[:story_name] == story_name
              i = index
            end
          end
          # If the story is not in the array then add it.
          if i.nil?
            stories << {
              story_name: story_name,
              spaces: [space],
              centroid: [0, 0, 0],
              ceiling_area: 0
            }
          else
            # If the story is already in the arry then add the space to the array of spaces for that story
            stories[i][:spaces] << space
          end
        end
      end
    end
    # Go through each story in the array above
    stories.each do |story|
      tz_centre = [0, 0, 0, 0]
      # Go through each space in a given story
      story[:spaces].each do |space|
        # Determine the top surface of the space and calculate it's centroid.
        # Get the coordinates of the origin for the space (the coordinates of points in the space are relative to this).
        xOrigin = space.xOrigin
        yOrigin = space.yOrigin
        zOrigin = space.zOrigin
        # Go through each surface in the space and find ceilings by determining which is called 'RoofCeiing'.  Find the
        # overall centroid of all the ceilings in the spaces.  Find centroid by multiplying the centroid of the surfaces
        # multiplied by the area of the surface and add them all up.  Then divide this by the overall area.  This is the
        # area weighted average of the centroid coordinates.
        ceiling_centroid = [0, 0, 0, 0]
        space.surfaces.each do |sp_surface|
          if sp_surface.surfaceType.to_s.upcase == 'ROOFCEILING'
            ceiling_centroid[0] = ceiling_centroid[0] + sp_surface.centroid.x.to_f * sp_surface.grossArea.to_f
            ceiling_centroid[1] = ceiling_centroid[1] + sp_surface.centroid.y.to_f * sp_surface.grossArea.to_f
            ceiling_centroid[2] = ceiling_centroid[2] + sp_surface.centroid.z.to_f * sp_surface.grossArea.to_f
            ceiling_centroid[3] = ceiling_centroid[3] + sp_surface.grossArea
          end
        end

        ceiling_centroid[0] = ceiling_centroid[0] / ceiling_centroid[3]
        ceiling_centroid[1] = ceiling_centroid[1] / ceiling_centroid[3]
        ceiling_centroid[2] = ceiling_centroid[2] / ceiling_centroid[3]

        # This part is used to determine the overall x, y centre of the thermal zone.  This is determined by summing the
        # x and y components times the ceiling area and diving by the total ceiling area.  I also added z since the
        # ceilings may not be all have the same height.
        tz_centre[0] += (ceiling_centroid[0] + xOrigin) * ceiling_centroid[3]
        tz_centre[1] += (ceiling_centroid[1] + yOrigin) * ceiling_centroid[3]
        tz_centre[2] += (ceiling_centroid[2] + zOrigin) * ceiling_centroid[3]
        tz_centre[3] += (ceiling_centroid[3])
      end
      tz_centre[0] /= tz_centre[3]
      tz_centre[1] /= tz_centre[3]
      tz_centre[2] /= tz_centre[3]
      # Update the :centroid and :ceiling_area hashes for the story to reflect the x, y, and z coordinates of the
      # overall centroid of spaces on that floor.
      story[:centroid] = tz_centre[0..2]
      story[:ceiling_area] = tz_centre[3]
    end
    return stories
  end

  # Create a new DX cooling coil with NECB curve characteristics
  def add_onespeed_DX_coil(model, always_on)
    # clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    # clg_cap_f_of_temp = model_add_curve("DXCOOL-NECB2011-REF-CAPFT")
    clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    clg_cap_f_of_temp.setCoefficient1Constant(0.867905)
    clg_cap_f_of_temp.setCoefficient2x(0.0142459)
    clg_cap_f_of_temp.setCoefficient3xPOW2(0.000554364)
    clg_cap_f_of_temp.setCoefficient4y(-0.00755748)
    clg_cap_f_of_temp.setCoefficient5yPOW2(3.3048e-05)
    clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.000191808)
    clg_cap_f_of_temp.setMinimumValueofx(13.0)
    clg_cap_f_of_temp.setMaximumValueofx(24.0)
    clg_cap_f_of_temp.setMinimumValueofy(24.0)
    clg_cap_f_of_temp.setMaximumValueofy(46.0)

    # clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    clg_cap_f_of_flow.setCoefficient1Constant(1.0)
    clg_cap_f_of_flow.setCoefficient2x(0.0)
    clg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
    clg_cap_f_of_flow.setMinimumValueofx(0.0)
    clg_cap_f_of_flow.setMaximumValueofx(1.0)

    # clg_energy_input_ratio_f_of_temp = = model_add_curve(""DXCOOL-NECB2011-REF-COOLEIRFT")
    # clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.116936)
    clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.0284933)
    clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.000411156)
    clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.0214108)
    clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.000161028)
    clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.000679104)
    clg_energy_input_ratio_f_of_temp.setMinimumValueofx(13.0)
    clg_energy_input_ratio_f_of_temp.setMaximumValueofx(24.0)
    clg_energy_input_ratio_f_of_temp.setMinimumValueofy(24.0)
    clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.0)

    # clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    # clg_energy_input_ratio_f_of_flow = = model_add_curve("DXCOOL-NECB2011-REF-CAPFFLOW")
    clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.0)
    clg_energy_input_ratio_f_of_flow.setCoefficient2x(0.0)
    clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0)
    clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.0)
    clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.0)

    # NECB curve modified to take into account how PLF is used in E+, and PLF ranges (> 0.7)
    # clg_part_load_ratio = model_add_curve("DXCOOL-NECB2011-REF-COOLPLFFPLR")
    clg_part_load_ratio = OpenStudio::Model::CurveCubic.new(model)
    clg_part_load_ratio.setCoefficient1Constant(0.0277)
    clg_part_load_ratio.setCoefficient2x(4.9151)
    clg_part_load_ratio.setCoefficient3xPOW2(-8.184)
    clg_part_load_ratio.setCoefficient4xPOW3(4.2702)
    clg_part_load_ratio.setMinimumValueofx(0.7)
    clg_part_load_ratio.setMaximumValueofx(1.0)

    return OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model,
                                                           always_on,
                                                           clg_cap_f_of_temp,
                                                           clg_cap_f_of_flow,
                                                           clg_energy_input_ratio_f_of_temp,
                                                           clg_energy_input_ratio_f_of_flow,
                                                           clg_part_load_ratio)
  end

  def add_onespeed_htg_DX_coil(model, sch)


    htg_cap_f_of_temp = OpenStudio::Model::CurveCubic.new(model)
    htg_cap_f_of_temp.setCoefficient1Constant(0.729009)
    htg_cap_f_of_temp.setCoefficient2x(0.0319275)
    htg_cap_f_of_temp.setCoefficient3xPOW2(0.000136404)
    htg_cap_f_of_temp.setCoefficient4xPOW3(-8.748e-06)
    htg_cap_f_of_temp.setMinimumValueofx(-20.0)
    htg_cap_f_of_temp.setMaximumValueofx(20.0)

    htg_cap_f_of_flow = OpenStudio::Model::CurveCubic.new(model)
    htg_cap_f_of_flow.setCoefficient1Constant(0.84)
    htg_cap_f_of_flow.setCoefficient2x(0.16)
    htg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
    htg_cap_f_of_flow.setCoefficient4xPOW3(0.0)
    htg_cap_f_of_flow.setMinimumValueofx(0.5)
    htg_cap_f_of_flow.setMaximumValueofx(1.5)

    htg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveCubic.new(model)
    htg_energy_input_ratio_f_of_temp.setCoefficient1Constant(1.2183)
    htg_energy_input_ratio_f_of_temp.setCoefficient2x(-0.03612)
    htg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(0.00142)
    htg_energy_input_ratio_f_of_temp.setCoefficient4xPOW3(-2.68e-05)
    htg_energy_input_ratio_f_of_temp.setMinimumValueofx(-20.0)
    htg_energy_input_ratio_f_of_temp.setMaximumValueofx(20.0)

    htg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    htg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.3824)
    htg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.4336)
    htg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0512)
    htg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.0)
    htg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.0)

    htg_part_load_ratio = OpenStudio::Model::CurveCubic.new(model)
    htg_part_load_ratio.setCoefficient1Constant(0.3696)
    htg_part_load_ratio.setCoefficient2x(2.3362)
    htg_part_load_ratio.setCoefficient3xPOW2(-2.9577)
    htg_part_load_ratio.setCoefficient4xPOW3(1.2596)
    htg_part_load_ratio.setMinimumValueofx(0.7)
    htg_part_load_ratio.setMaximumValueofx(1.0)

    dx_htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model,
                                                                  sch,
                                                                  htg_cap_f_of_temp,
                                                                  htg_cap_f_of_flow,
                                                                  htg_energy_input_ratio_f_of_temp,
                                                                  htg_energy_input_ratio_f_of_flow,
                                                                  htg_part_load_ratio)
    dx_htg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-10)

    return dx_htg_coil
  end

  # Zonal systems
  def add_zone_baseboards(baseboard_type:,
                          hw_loop:,
                          model:,
                          zone:)
    always_on = model.alwaysOnDiscreteSchedule
    if baseboard_type == 'Electric'
      zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
      zone_elec_baseboard.addToThermalZone(zone)
    end

    return unless baseboard_type == 'Hot Water'

    baseboard_coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model)
    # Connect baseboard coil to hot water loop
    hw_loop.addDemandBranchForComponent(baseboard_coil)
    zone_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(model, always_on, baseboard_coil)
    # add zone_baseboard to zone
    zone_baseboard.addToThermalZone(zone)
  end

  def add_ptac_dx_cooling(model, zone, zero_outdoor_air)
    # Create a PTAC for each zone:
    # PTAC DX Cooling with electric heating coil; electric heating coil is always off

    # TO DO: need to apply this system to space types:
    # (1) data processing area: control room, data centre
    # when cooling capacity <= 20kW and
    # (2) residential/accommodation: murb, hotel/motel guest room
    # when building/space heated only (this as per NECB; apply to
    # all for initial work? CAN-QUEST limitation)

    # TO DO: PTAC characteristics: sizing, fan schedules, temperature setpoints, interaction with MAU
    always_on = model.alwaysOnDiscreteSchedule
    always_off = BTAP::Resources::Schedules::StandardSchedules::ON_OFF.always_off(model)
    htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_off)

    # Set up PTAC DX coil with NECB performance curve characteristics;
    clg_coil = add_onespeed_DX_coil(model, always_on)

    # Set up PTAC constant volume supply fan
    fan = OpenStudio::Model::FanOnOff.new(model)
    fan.setPressureRise(640)

    # This method will seem like an error in number of args..but this is due to swig voodoo.
    ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                         always_on,
                                                                         fan,
                                                                         htg_coil,
                                                                         clg_coil)
    ptac.setName("#{zone.name} PTAC")
    ptac.setSupplyAirFanOperatingModeSchedule(always_off)
    if zero_outdoor_air
      ptac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded 1.0e-5
      ptac.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-5)
      ptac.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-5)
    end
    ptac.addToThermalZone(zone)
  end

  def common_air_loop(model:, system_data:)
    mau_air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    mau_air_loop.setName(system_data[:name])
    air_loop_sizing = mau_air_loop.sizingSystem
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setPreheatDesignTemperature(system_data[:PreheatDesignTemperature]) unless system_data[:PreheatDesignTemperature].nil?
    air_loop_sizing.setPreheatDesignHumidityRatio(system_data[:PreheatDesignHumidityRatio]) unless system_data[:PreheatDesignHumidityRatio].nil?
    air_loop_sizing.setPrecoolDesignTemperature(system_data[:PrecoolDesignTemperature]) unless system_data[:PrecoolDesignTemperature].nil?
    air_loop_sizing.setPrecoolDesignHumidityRatio(system_data[:PrecoolDesignHumidityRatio]) unless system_data[:PrecoolDesignHumidityRatio].nil?
    air_loop_sizing.setSizingOption(system_data[:SizingOption]) unless system_data[:SizingOption].nil?
    air_loop_sizing.setCoolingDesignAirFlowMethod(system_data[:CoolingDesignAirFlowMethod]) unless system_data[:CoolingDesignAirFlowMethod].nil?
    air_loop_sizing.setCoolingDesignAirFlowRate(system_data[:CoolingDesignAirFlowRate]) unless system_data[:CoolingDesignAirFlowRate].nil?
    air_loop_sizing.setHeatingDesignAirFlowMethod(system_data[:HeatingDesignAirFlowMethod]) unless system_data[:HeatingDesignAirFlowMethod].nil?
    air_loop_sizing.setHeatingDesignAirFlowRate(system_data[:HeatingDesignAirFlowRate]) unless system_data[:HeatingDesignAirFlowRate].nil?
    air_loop_sizing.setSystemOutdoorAirMethod(system_data[:SystemOutdoorAirMethod]) unless system_data[:SystemOutdoorAirMethod].nil?
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(system_data[:CentralCoolingDesignSupplyAirHumidityRatio]) unless system_data[:CentralCoolingDesignSupplyAirHumidityRatio].nil?
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(system_data[:CentralHeatingDesignSupplyAirHumidityRatio]) unless system_data[:CentralHeatingDesignSupplyAirHumidityRatio].nil?
    air_loop_sizing.setTypeofLoadtoSizeOn(system_data[:TypeofLoadtoSizeOn]) unless system_data[:TypeofLoadtoSizeOn].nil?
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(system_data[:CentralCoolingDesignSupplyAirTemperature]) unless system_data[:CentralCoolingDesignSupplyAirTemperature].nil?
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(system_data[:CentralHeatingDesignSupplyAirTemperature]) unless system_data[:CentralHeatingDesignSupplyAirTemperature].nil?
    air_loop_sizing.setAllOutdoorAirinCooling(system_data[:AllOutdoorAirinCooling]) unless system_data[:AllOutdoorAirinCooling].nil?
    air_loop_sizing.setAllOutdoorAirinHeating(system_data[:AllOutdoorAirinHeating]) unless system_data[:AllOutdoorAirinHeating].nil?
    if model.version < OpenStudio::VersionString.new('2.7.0')
      air_loop_sizing.setMinimumSystemAirFlowRatio(system_data[:MinimumSystemAirFlowRatio]) unless system_data[:MinimumSystemAirFlowRatio].nil?
    else
      air_loop_sizing.setCentralHeatingMaximumSystemAirFlowRatio(system_data[:MinimumSystemAirFlowRatio]) unless system_data[:MinimumSystemAirFlowRatio].nil?
    end
    return mau_air_loop
  end

  def create_heating_cooling_on_off_availability_schedule(model)
    # @todo Create a feature to derive start and end heating and cooling seasons from weather file.
    avail_data = [{ start_month: 1, start_day: 1, end_month: 6, end_day: 30, htg_value: 1, clg_value: 0 },
                  { start_month: 7, start_day: 1, end_month: 10, end_day: 31, htg_value: 0, clg_value: 1 },
                  { start_month: 11, start_day: 1, end_month: 12, end_day: 31, htg_value: 1, clg_value: 0 }]

    # Heating coil availability schedule for tpfc
    htg_availability_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_availability_sch.setName('tpfc_htg_availability')
    # Cooling coil availability schedule for tpfc
    clg_availability_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    clg_availability_sch.setName('tpfc_clg_availability')
    avail_data.each do |data|
      htg_availability_sch_rule = OpenStudio::Model::ScheduleRule.new(htg_availability_sch)
      htg_availability_sch_rule.setName('tpfc_htg_availability_sch_rule')
      htg_availability_sch_rule.setStartDate(model.getYearDescription.makeDate(data[:start_month], data[:start_day]))
      htg_availability_sch_rule.setEndDate(model.getYearDescription.makeDate(data[:end_month], data[:end_day]))
      htg_availability_sch_rule.setApplySunday(true)
      htg_availability_sch_rule.setApplyMonday(true)
      htg_availability_sch_rule.setApplyTuesday(true)
      htg_availability_sch_rule.setApplyWednesday(true)
      htg_availability_sch_rule.setApplyThursday(true)
      htg_availability_sch_rule.setApplyFriday(true)
      htg_availability_sch_rule.setApplySaturday(true)
      day_schedule = htg_availability_sch_rule.daySchedule
      day_schedule.setName('tpfc_htg_availability_sch_rule_day')
      day_schedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), data[:htg_value])

      clg_availability_sch_rule = OpenStudio::Model::ScheduleRule.new(clg_availability_sch)
      clg_availability_sch_rule.setName('tpfc_clg_availability_sch_rule')
      clg_availability_sch_rule.setStartDate(model.getYearDescription.makeDate(data[:start_month], data[:start_day]))
      clg_availability_sch_rule.setEndDate(model.getYearDescription.makeDate(data[:end_month], data[:end_day]))
      clg_availability_sch_rule.setApplySunday(true)
      clg_availability_sch_rule.setApplyMonday(true)
      clg_availability_sch_rule.setApplyTuesday(true)
      clg_availability_sch_rule.setApplyWednesday(true)
      clg_availability_sch_rule.setApplyThursday(true)
      clg_availability_sch_rule.setApplyFriday(true)
      clg_availability_sch_rule.setApplySaturday(true)
      day_schedule = clg_availability_sch_rule.daySchedule
      day_schedule.setName('tpfc_clg_availability_sch_rule_day')
      day_schedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), data[:clg_value])
    end
    return clg_availability_sch, htg_availability_sch
  end

  # Method to set the base system name based on the following syntax:
  # |sys_abbr|sys_oa|shr>?|sc>?|sh>?|ssf>?|zh>?|zc>?|srf>?|
  # "sys_abbr" designates the NECB system type ("sys_1, sys_2, ... sys_6")
  # "sys_oa": "mixed" or "doas"
  # "sys_name_pars" is a hash for the remaining system name parts for heat recovery,
  # heating, cooling, supply fan, zone heating, zone cooling, and return fan
  def assign_base_sys_name(air_loop:, sys_abbr:, sys_oa:, sys_name_pars:)
    sys_name = "#{sys_abbr}|#{sys_oa}|"
    sys_name_pars.each do |key, value|
      case key.downcase
      when 'sys_hr'
        case value.downcase
        when 'none'
          sys_name += 'shr>none'
        end

      when 'sys_htg'
        case value.downcase
        when 'none'
          sys_name += 'sh>none'
        when 'electric'
          sys_name += 'sh>c-e'
        when 'hot water'
          sys_name += 'sh>c-hw'
        when 'gas', 'g'
          sys_name += 'sh>c-g'
        when 'dx' , 'ashp'
          sys_name += 'sh>ashp'
        when 'ashp>c-g'
          sys_name += 'sh>ashp>c-g'
        when 'ashp>c-e'
          sys_name += 'sh>ashp>c-e'
        when 'ashp>c-hw'
          sys_name += 'sh>ashp>c-hw'
        when 'ccashp'
          sys_name += 'sh>ccashp'
        when 'ccashp>c-g'
          sys_name += 'sh>ccashp>c-g'
        when 'ccashp>c-e'
          sys_name += 'sh>ccashp>c-e'
        when 'ccashp>c-hw'
          sys_name += 'sh>ccashp>c-hw'
        else
          sys_name += 'sh>none'
        end

      when 'sys_clg'
        case value.downcase
        when 'none'
          sys_name += 'sc>none'
        when 'chilled water','hydronic'
          sys_name += 'sc>c-chw'
        when 'dx'
          if sys_name_pars['sys_htg'] == 'dx' || sys_name_pars['sys_htg'] == 'ashp>c-g' || sys_name_pars['sys_htg'] == 'ashp>c-e' || sys_name_pars['sys_htg'] == 'ashp>c-hw'
            sys_name += 'sc>ashp'
          else
            sys_name += 'sc>dx'
          end
        when 'ccashp'
          sys_name += 'sc>ccashp'
        when 'ashp'
          sys_name += 'sc>ashp'
        end

      when 'sys_sf'
        case value.downcase
        when 'none'
          sys_name += 'ssf>none'
        when 'cv'
          sys_name += 'ssf>cv'
        when 'vv'
          sys_name += 'ssf>vv'
        end

      when 'zone_htg'
        case value.downcase
        when 'none'
          sys_name += 'zh>none'
        when 'electric'
          sys_name += 'zh>b-e'
        when 'hot water'
          sys_name += 'zh>b-hw'
        when 'tpfc'
          sys_name += 'zh>tpfc'
        when 'fpfc'
          sys_name += 'zh>fpfc'
        when 'pthp'
          sys_name += 'zh>pthp'
        end

      when 'zone_clg'
        case value.downcase
        when 'none'
          sys_name += 'zc>none'
        when 'tpfc'
          sys_name += 'zc>tpfc'
        when 'fpfc'
          sys_name += 'zc>fpfc'
        when 'ptac'
          sys_name += 'zc>ptac'
        when 'pthp'
          sys_name += 'zc>pthp'
        end

      when 'sys_rf'
        case value.downcase
        when 'none'
          sys_name += 'srf>none'
        when 'cv'
          sys_name += 'srf>cv'
        when 'vv'
          sys_name += 'srf>vv'
        end
      end
      sys_name += '|'
    end

    air_loop.setName(sys_name)
    return detect_air_system_type(air_loop: air_loop,
                                  old_system_name: sys_name,
                                  sys_abbr: sys_abbr)
  end

  # Method to update the base system name based on the inputs provided.
  # Only the parts of the name with string inputs are updated
  def update_sys_name(airloop,
                      sys_abbr: nil,
                      sys_oa: nil,
                      sys_hr: nil,
                      sys_htg: nil,
                      sys_clg: nil,
                      sys_sf: nil,
                      zone_htg: nil,
                      zone_clg: nil,
                      sys_rf: nil)
    name_parts = airloop.name.to_s.split('|').reject(&:empty?)
    if sys_abbr.is_a? String then name_parts[0] = sys_abbr end
    if sys_oa.is_a? String then name_parts[1] = sys_oa end
    for i in 0..name_parts.size - 1
      if (name_parts[i].include? 'shr>') && (sys_hr.is_a? String)
        name_parts[i] = "shr>#{sys_hr}"
      elsif (name_parts[i].include? 'sh>') && (sys_htg.is_a? String)
        name_parts[i] = "sh>#{sys_htg}"
      elsif (name_parts[i].include? 'sc>') && (sys_clg.is_a? String)
        name_parts[i] = "sc>#{sys_clg}"
      elsif (name_parts[i].include? 'ssf') && (sys_sf.is_a? String)
        name_parts[i] = "ssf>#{sys_sf}"
      elsif (name_parts[i].include? 'zh>') && (zone_htg.is_a? String)
        name_parts[i] = "zh>#{zone_htg}"
      elsif (name_parts[i].include? 'zc>') && (zone_clg.is_a? String)
        name_parts[i] = "zc>#{zone_clg}"
      elsif (name_parts[i].include? 'srf>') && (sys_rf.is_a? String)
        name_parts[i] = "srf>#{sys_rf}"
      end
    end
    sys_name = ''
    name_parts.each { |part| sys_name += "#{part}|" }

    # Check if the last part of the system name is an integer.  If it is, then remove the last part from the system name.
    check_int = begin
                  Integer(name_parts.last.strip)
                rescue StandardError
                  nil
                end
    sys_name = sys_name.chop unless check_int.nil?

    airloop.setName(sys_name)
  end

  # NECB reference heat pump system
  # heating type rules need to be flexible to account for
  # 1.  DX htg/cooling + gas supplement htg
  # 2.  Potential lack of AirLoopHVACUnitaryHeatPumpAirToAir or AirLoopHVACUnitarySystem
  # @param necb_reference_hp [Boolean] if true, NECB reference model rules for heat pumps will be used.
  def coil_dx_heating_type(coil_dx, necb_reference_hp: false)
    supp_htg_type = nil

    # If not heat pump reference case use the standard implementation.
    if !necb_reference_hp
      return super(coil_dx)
    else
      if coil_dx.airLoopHVAC.empty?
        if coil_dx.containingHVACComponent.is_initialized
          containing_comp = coil_dx.containingHVACComponent.get
          if containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
            supp_htg_coil = containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.get.supplementalHeatingCoil
            if supp_htg_coil.to_CoilHeatingElectric.is_initialized
              supp_htg_type = 'Electric Resistance or None'
            elsif supp_htg_coil.to_CoilHeatingGas.is_initialized or supp_htg_coil.to_CoilHeatingWater.is_initialized
              supp_htg_type = 'All Other'
            else # None
              supp_htg_type = 'Electric Resistance or None'
            end
          else
            # For other virtual wrapper, use method in Standard.DXCoil
            # Or add future wrappers here
            return super
          end
        end

      elsif coil_dx.airLoopHVAC.is_initialized # Heat pumps without a wrapper (lone DX coils in the air loop)
        airloop = coil_dx.airLoopHVAC.get
        num_of_DX_Coils = 0
        num_of_supp_coils = 0
        supp_htg_type = ''
        # Go through and determine number of each type of coils in air loop to determine supp_htg_type
        airloop.supplyComponents.each do |supply_component|
          if supply_component.to_CoilHeatingDXSingleSpeed.is_initialized or supply_component.to_CoilHeatingDXMultiSpeed.is_initialized
            supply_component.to_CoilHeatingDXVariableSpeed.is_initialized
            num_of_DX_Coils = num_of_DX_Coils + 1
          elsif supply_component.to_CoilCoolingDXSingleSpeed.is_initialized or supply_component.to_CoilCoolingDXTwoSpeed.is_initialized or
            supply_component.to_CoilCoolingDXTwoSpeed.is_initialized or supply_component.to_CoilCoolingDXVariableSpeed.is_initialized or
            supply_component.to_CoilCoolingDXMultiSpeed.is_initialized or
            supply_component.to_CoilCoolingDXCurveFitPerformance.is_initialized or
            supply_component.to_CoilCoolingDXTwoStageWithHumidityControlMode.is_initialized
            num_of_DX_Coils = num_of_DX_Coils + 1
          elsif supply_component.to_CoilHeatingGas.is_initialized or supply_component.to_CoilHeatingGasMultiStage.is_initialized or
            supply_component.to_CoilHeatingWater.is_initialized
            num_of_supp_coils = num_of_supp_coils + 1
            supp_htg_type = 'All Other'
          elsif supply_component.to_CoilHeatingElectric.is_initialized
            num_of_supp_coils = num_of_supp_coils + 1
            supp_htg_type = 'Electric Resistance or None'
          end
        end

        #Two possible heat pump configuration
        if num_of_DX_Coils == 2 && num_of_supp_coils == 1 #Scenario 1: 1 DX htg + 1 DX clg + 1 Non-DX htg coil
          puts "scenario 1 supp_htg_type #{supp_htg_type}"
          return supp_htg_type # return supplmental heating type
        else #Scenario 2: num_of_DX_Coils < 2 or num_of_supp_coils = 0;
          puts "scenario 2 supp_htg_type #{supp_htg_type}"
          puts "num_of_DX_Coils #{num_of_DX_Coils}"
          puts "num_of_supp_coils #{num_of_supp_coils}"
          return supp_htg_type = 'Electric Resistance or None'
        end
      end
    end
  end

  # Sets the capacity of the reheat coil based on the minimum flow fraction, and the maximum flow rate.
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_vav_reheat_set_heating_cap(air_terminal_single_duct_vav_reheat)
    flow_rate_fraction = 0.0
    if air_terminal_single_duct_vav_reheat.constantMinimumAirFlowFraction.is_initialized
      flow_rate_fraction = air_terminal_single_duct_vav_reheat.constantMinimumAirFlowFraction.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirTerminalSingleDuctVAVReheat', \
      "Minimum flow fraction is not defined for terminal device #{air_terminal_single_duct_vav_reheat.name}")
      return false
    end
    cap = 1.2 * 1000.0 * flow_rate_fraction * air_terminal_single_duct_vav_reheat.autosizedMaximumAirFlowRate.to_f * (43.0 - 13.0)
    if air_terminal_single_duct_vav_reheat.reheatCoil.to_CoilHeatingElectric.is_initialized
      reheat_coil = air_terminal_single_duct_vav_reheat.reheatCoil.to_CoilHeatingElectric.get
      reheat_coil.setNominalCapacity(cap)
    elsif air_terminal_single_duct_vav_reheat.reheatCoil.to_CoilHeatingWater.is_initialized
      reheat_coil = air_terminal_single_duct_vav_reheat.reheatCoil.to_CoilHeatingWater.get
      reheat_coil.setPerformanceInputMethod('NominalCapacity')
      reheat_coil.setRatedCapacity(cap)
    end
    air_terminal_single_duct_vav_reheat.setMaximumReheatAirTemperature(43.0)
    return true
  end

  # Using a dummy method to overload the NREL one which applies VRF defaults.  This is to avoid the NREL method
  # conflicting with NRCan's VRF ECMs.
  def air_conditioner_variable_refrigerant_flow_apply_efficiency_and_curves(air_conditioner_variable_refrigerant_flow)
    return
  end
end
