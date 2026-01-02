# Custom changes for the SmallOfficeDetailed prototype.
# These are changes that are inconsistent with other prototype building types.
module SmallOfficeDetailed
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    # add extra infiltration for entry door
    add_door_infiltration(climate_zone, model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Added door infiltration')

    # add extra infiltration for attic
    add_attic_infiltration(template, climate_zone, model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Added attic infiltration')

    # reset defrost time fraction
    # @todo set this to a reasonable defrost time fraction based on research and implement in Prototype.CoilHeatingDXSingleSpeed
    model.getCoilHeatingDXSingleSpeeds.each(&:resetDefrostTimePeriodFraction)
    return true
  end

  # add door infiltration
  #
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def add_door_infiltration(climate_zone, model)
    # add extra infiltration for entry door in m3/s (there is no attic in 'DOE Ref Pre-1980')
    return false if template == 'DOE Ref 1980-2004' || template == 'DOE Ref Pre-1980'

    entry_space = model.getSpaceByName('Lobby').get
    infiltration_entrydoor = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
    infiltration_entrydoor.setName('entry door Infiltration')
    infiltration_per_zone_entrydoor = 0
    if template == '90.1-2004'
      infiltration_per_zone_entrydoor = 0.129785425
      infiltration_entrydoor.setSchedule(model_add_schedule(model, 'OfficeSmall INFIL_Door_Opening_SCH'))
    elsif template == '90.1-2007' || template == '90.1-2010' || template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019'
      case climate_zone
      when 'ASHRAE 169-2006-1A', 'ASHRAE 169-2006-2A', 'ASHRAE 169-2006-1B', 'ASHRAE 169-2006-2B'
        infiltration_per_zone_entrydoor = 0.129785425
        infiltration_entrydoor.setSchedule(model_add_schedule(model, 'OfficeSmall INFIL_Door_Opening_SCH'))
      else
        infiltration_per_zone_entrydoor = 0.076455414
        infiltration_entrydoor.setSchedule(model_add_schedule(model, 'OfficeSmall INFIL_Door_Opening_SCH_2013'))
      end
    end
    infiltration_entrydoor.setDesignFlowRate(infiltration_per_zone_entrydoor)
    infiltration_entrydoor.setConstantTermCoefficient(1.0)
    infiltration_entrydoor.setTemperatureTermCoefficient(0.0)
    infiltration_entrydoor.setVelocityTermCoefficient(0.0)
    infiltration_entrydoor.setVelocitySquaredTermCoefficient(0.0)
    infiltration_entrydoor.setSpace(entry_space)
    return true
  end

  # add attic infiltration
  #
  # @param template [String] the model template
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def add_attic_infiltration(template, climate_zone, model)
    # add extra infiltration for attic in m3/s (there is no attic in 'DOE Ref Pre-1980')
    return false if template == 'DOE Ref 1980-2004' || template == 'DOE Ref Pre-1980'

    if model.getSpaceByName('Attic').is_initialized
      entry_space = model.getSpaceByName('Attic').get
    elsif model.getSpaceByName('Attic 1').is_initialized
      entry_space = model.getSpaceByName('Attic 1').get
    end
    infiltration_attic = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
    infiltration_attic.setName('attic Infiltration')
    infiltration_per_zone_attic = 0.2001
    infiltration_attic.setSchedule(model_add_schedule(model, 'Always On'))
    infiltration_attic.setDesignFlowRate(infiltration_per_zone_attic)
    infiltration_attic.setConstantTermCoefficient(1.0)
    infiltration_attic.setTemperatureTermCoefficient(0.0)
    infiltration_attic.setVelocityTermCoefficient(0.0)
    infiltration_attic.setVelocitySquaredTermCoefficient(0.0)
    infiltration_attic.setSpace(entry_space)
    return true
  end

  # # daylighting adjustments specific to the prototype model
  # #
  # # @param model [OpenStudio::Model::Model] OpenStudio model object
  # # @param building_type [String the building type
  # # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # # @param prototype_input [Hash] hash of prototype inputs
  # # @return [Boolean] returns true if successful, false if not
  # def model_custom_daylighting_tweaks(model, building_type, climate_zone, prototype_input)
  #   OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Adjusting daylight sensor positions and fractions')
  #
  #   adjustments = [
  #                   { 'stds_spc_type' => 'WholeBuilding - Sm Office',
  #                     'sensor_1_frac' => 0.2399,
  #                     'sensor_2_frac' => 0.0302,
  #                   }
  #                 ]
  #
  #   # Adjust daylight sensors in each space
  #   model.getSpaces.each do |space|
  #     next if space.thermalZone.empty?
  #     zone = space.thermalZone.get
  #     next if space.spaceType.empty?
  #     spc_type = space.spaceType.get
  #     next if spc_type.standardsSpaceType.empty?
  #     stds_spc_type = spc_type.standardsSpaceType.get
  #     adjustments.each do |adj|
  #       next unless adj['stds_spc_type'] == stds_spc_type
  #       # Adjust the primary sensor
  #       if adj['sensor_1_frac'] && zone.primaryDaylightingControl.is_initialized
  #         OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "For #{zone.name}: Adjusting primary daylight sensor to control #{adj['sensor_1_frac']} of the lighting.")
  #         zone.setFractionofZoneControlledbyPrimaryDaylightingControl(adj['sensor_1_frac'])
  #         pri_ctrl = zone.primaryDaylightingControl.get
  #         if adj['sensor_1_xyz']
  #           x = adj['sensor_1_xyz'][0]
  #           y = adj['sensor_1_xyz'][1]
  #           z = adj['sensor_1_xyz'][2]
  #           OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "For #{zone.name}: Adjusting primary daylight sensor position to [#{x}, #{y}, #{z}].")
  #           pri_ctrl.setPositionXCoordinate(x)
  #           pri_ctrl.setPositionYCoordinate(y)
  #           pri_ctrl.setPositionZCoordinate(z)
  #         end
  #       end
  #       # Adjust the secondary sensor
  #       if adj['sensor_2_frac'] && zone.secondaryDaylightingControl.is_initialized
  #         OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "For #{zone.name}: Adjusting secondary daylight sensor to control #{adj['sensor_2_frac']} of the lighting.")
  #         zone.setFractionofZoneControlledbySecondaryDaylightingControl(adj['sensor_2_frac'])
  #         sec_ctrl = zone.secondaryDaylightingControl.get
  #         if adj['sensor_2_xyz']
  #           x = adj['sensor_2_xyz'][0]
  #           y = adj['sensor_2_xyz'][1]
  #           z = adj['sensor_2_xyz'][2]
  #           OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "For #{zone.name}: Adjusting secondary daylight sensor position to [#{x}, #{y}, #{z}].")
  #           sec_ctrl.setPositionXCoordinate(x)
  #           sec_ctrl.setPositionYCoordinate(y)
  #           sec_ctrl.setPositionZCoordinate(z)
  #         end
  #       end
  #     end
  #   end
  #   return true
  # end

  # update water heater loss coefficient
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def update_waterheater_loss_coefficient(model)
    case template
    when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019', 'NECB2011'
      model.getWaterHeaterMixeds.sort.each do |water_heater|
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(1.205980747)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(1.205980747)
      end
    end
    return true
  end

  # swh adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_swh_tweaks(model, building_type, climate_zone, prototype_input)
    update_waterheater_loss_coefficient(model)

    return true
  end

  # geometry adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_geometry_tweaks(model, building_type, climate_zone, prototype_input)
    # Set original building North axis
    OpenstudioStandards::Geometry.model_set_building_north_axis(model, 0.0)
    return true
  end
end
