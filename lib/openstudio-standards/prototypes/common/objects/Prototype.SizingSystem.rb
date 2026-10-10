class Standard
  # @!group Sizing System

  # Prototype SizingSystem object
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param dsgn_temps [Hash] a hash of design temperature lookups from standard_design_sizing_temperatures
  # @param type_of_load_sizing [String] Sizing:System type of load to size on
  # @param min_sys_airflow_ratio [Double, Symbol] the central heating maximum system air flow ratio: the
  #   fraction of the cooling design flow the central heating coil is sized to heat. A number pins it;
  #   :autosize lets EnergyPlus derive it from the sum of the zones' heating design flows over the
  #   cooling design flow, which is the airflow VAV terminals actually pass in heating once their
  #   minimum outdoor air and reverse action are counted. A pinned 0.3 under-sized a hospital's
  #   central coil by a third in a validation run, since its laboratory and patient zones
  #   carry minimum outdoor air well above 30% of their peaks.
  # @param sizing_option [String] Coincident or NonCoincident
  # @return [OpenStudio::Model::SizingSystem] sizing system object
  def adjust_sizing_system(air_loop_hvac,
                           dsgn_temps,
                           type_of_load_sizing: 'Sensible',
                           min_sys_airflow_ratio: 0.3,
                           sizing_option: 'Coincident')

    # adjust sizing system defaults
    sizing_system = air_loop_hvac.sizingSystem
    sizing_system.setTypeofLoadtoSizeOn(type_of_load_sizing)
    sizing_system.autosizeDesignOutdoorAirFlowRate
    sizing_system.setPreheatDesignTemperature(dsgn_temps['prehtg_dsgn_sup_air_temp_c'])
    sizing_system.setPrecoolDesignTemperature(dsgn_temps['preclg_dsgn_sup_air_temp_c'])
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(dsgn_temps['clg_dsgn_sup_air_temp_c'])
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(dsgn_temps['htg_dsgn_sup_air_temp_c'])
    sizing_system.setPreheatDesignHumidityRatio(0.008)
    sizing_system.setPrecoolDesignHumidityRatio(0.008)
    sizing_system.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
    sizing_system.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
    adjust_sizing_system_heating_airflow_ratio(sizing_system, min_sys_airflow_ratio)
    sizing_system.setSizingOption(sizing_option)
    sizing_system.setAllOutdoorAirinCooling(false)
    sizing_system.setAllOutdoorAirinHeating(false)
    sizing_system.setSystemOutdoorAirMethod('ZoneSum')
    sizing_system.setCoolingDesignAirFlowMethod('DesignDay')
    sizing_system.setHeatingDesignAirFlowMethod('DesignDay')

    return sizing_system
  end

  # Set or autosize the central heating maximum system air flow ratio on a Sizing:System.
  #
  # @param sizing_system [OpenStudio::Model::SizingSystem] sizing system object
  # @param min_sys_airflow_ratio [Double, Symbol, nil] a number pins the ratio; :autosize or nil
  #   lets EnergyPlus derive it from the zones' heating design flows
  # @return [Boolean] returns true if successful, false if not
  def adjust_sizing_system_heating_airflow_ratio(sizing_system, min_sys_airflow_ratio)
    autosize = min_sys_airflow_ratio.nil? || min_sys_airflow_ratio == :autosize
    if sizing_system.model.version < OpenStudio::VersionString.new('2.7.0')
      if autosize
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.SizingSystem', "The minimum system air flow ratio cannot be autosized before OpenStudio 2.7.0; #{sizing_system.name} keeps 0.3.")
        sizing_system.setMinimumSystemAirFlowRatio(0.3)
      else
        sizing_system.setMinimumSystemAirFlowRatio(min_sys_airflow_ratio)
      end
    elsif autosize
      sizing_system.autosizeCentralHeatingMaximumSystemAirFlowRatio
    else
      sizing_system.setCentralHeatingMaximumSystemAirFlowRatio(min_sys_airflow_ratio)
    end

    return true
  end

  # adjust the outdoor air sizing to the use the ventilation rate procedure
  # @todo this needs to be changed in both the sizing system and controller mechanical ventilation objects
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] returns true if successful, false if not
  def model_system_outdoor_air_sizing_vrp_method(air_loop_hvac)
    # Do not apply the adjustment to some of the system in
    # the hospital and outpatient which have their minimum
    # damper position determined based on AIA 2001 ventilation
    # requirements
    if (@instvarbuilding_type == 'Hospital' && (air_loop_hvac.name.to_s.include?('VAV_ER') || air_loop_hvac.name.to_s.include?('VAV_ICU') ||
       air_loop_hvac.name.to_s.include?('VAV_OR') || air_loop_hvac.name.to_s.include?('VAV_LABS') ||
       air_loop_hvac.name.to_s.include?('VAV_PATRMS'))) ||
       (@instvarbuilding_type == 'Outpatient' && air_loop_hvac.name.to_s.include?('Outpatient F1'))
      return true
    end

    sizing_system = air_loop_hvac.sizingSystem
    if air_loop_hvac.model.version < OpenStudio::VersionString.new('3.3.0')
      sizing_system.setSystemOutdoorAirMethod('VentilationRateProcedure')
    else
      sizing_system.setSystemOutdoorAirMethod('Standard62.1VentilationRateProcedure')
    end

    # Set the minimum zone ventilation efficiency
    min_ventilation_efficiency = air_loop_hvac_minimum_zone_ventilation_efficiency(air_loop_hvac)
    air_loop_hvac.thermalZones.sort.each do |zone|
      sizing_zone = zone.sizingZone
      if air_loop_hvac.model.version < OpenStudio::VersionString.new('3.0.0')
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.SizingSystem', "The design minimum zone ventilation efficiency cannot be set for #{sizing_system.name}. It can only be set OpenStudio 3.0.0 and later.")
      else
        sizing_zone.setDesignMinimumZoneVentilationEfficiency(min_ventilation_efficiency)
      end
    end

    return true
  end
end
