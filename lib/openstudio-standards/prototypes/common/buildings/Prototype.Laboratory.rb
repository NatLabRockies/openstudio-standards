# Custom changes for the Laboratory prototype.
# These are changes that are inconsistent with other prototype building types.
module Laboratory
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started building type specific adjustments')

    # get the fume hood space type and exhaust ACH
    fume_hood_exhaust_ach = nil
    model.getSpaceTypes.each do |spc_type|
      next unless spc_type.name.get.to_s.downcase.include? 'fume hood'

      spc_type_properties = space_type_get_standards_data(spc_type)
      fume_hood_exhaust_ach = spc_type_properties['ventilation_air_changes'].to_f
    end

    # For fume hood, the OA rate varies with the fume hood schedule
    # So add "Proportional Control Minimum Outdoor Air Flow Rate Schedule"
    # at the mean time, modify "Outdoor Air Method" to "ProportionalControlBasedOnDesignOARate" in Controller:MechanicalVentilation of the DOAS
    model.getSpaces.each do |space|
      next unless space.name.get.to_s.include? 'fumehood'

      ventilation = space.designSpecificationOutdoorAir.get
      ventilation.setOutdoorAirFlowRateFractionSchedule(model_add_schedule(model, 'Lab_FumeHood_Sch'))

      # add exhaust fan to fume hood zone
      fume_hood_zone_volume = space.volume
      flow_rate_fume_hood = fume_hood_zone_volume * fume_hood_exhaust_ach / 3600.0
      flow_fraction_schedule = model_add_schedule(model, 'Lab_FumeHood_Sch')
      OpenstudioStandards::HVAC.model_add_exhaust_fan(model, [space.thermalZone.get], flow_rate: flow_rate_fume_hood, flow_fraction_schedule: flow_fraction_schedule)
    end

    # adjust doas sizing
    model.getAirLoopHVACs.each do |air_loop|
      if air_loop.name.to_s.include? 'OA'
        # system sizing
        sizing_system = air_loop.sizingSystem
        sizing_system.setTypeofLoadtoSizeOn('Sensible')
      end
    end

    # control lab air terminals for outdoor air
    model.getAirTerminalSingleDuctVAVReheats.sort.each do |air_terminal|
      air_terminal_name = air_terminal.name.get
      if air_terminal_name.include?('Lab')
        air_terminal.setControlForOutdoorAir(true)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished building type specific adjustments')
    return true
  end

  # lab zones don't have economizer, the air flow rate is determined by the ventilation requirement
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_modify_oa_controller(model)
    model.getAirLoopHVACs.sort.each do |air_loop|
      oa_sys = air_loop.airLoopHVACOutdoorAirSystem.get
      oa_control = oa_sys.getControllerOutdoorAir
      if air_loop.name.get.include?('DOAS')
        oa_control.setEconomizerControlType('NoEconomizer')
      end
    end
    return true
  end

  # swh adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_swh_tweaks(model, building_type, climate_zone, prototype_input)
    return true
  end

  # geometry adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_geometry_tweaks(model, building_type, climate_zone, prototype_input)
    return true
  end
end
