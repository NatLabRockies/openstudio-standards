class Standard
  # @!group Sizing System

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
