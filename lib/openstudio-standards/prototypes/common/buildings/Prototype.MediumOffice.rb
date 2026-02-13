# Custom changes for the MediumOffice prototype.
# These are changes that are inconsistent with other prototype building types.
module MediumOffice
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started building type specific HVAC adjustments')

    # add transformer
    # efficiency based on a 45 kVA transformer
    case template
    when '90.1-2004', '90.1-2007'
      transformer_efficiency = 0.961
    when '90.1-2010', '90.1-2013'
      transformer_efficiency = 0.977
    when '90.1-2016', '90.1-2019'
      transformer_efficiency = 0.984
    else
      transformer_efficiency = nil
    end
    return true if transformer_efficiency.nil?

    # Change to output variable name in E+ 9.4 (OS 3.1.0)
    excluded_interiorequip_variable = if model.version < OpenStudio::VersionString.new('3.1.0')
                                        'Electric Equipment Electric Energy'
                                      else
                                        'Electric Equipment Electricity Energy'
                                      end

    OpenstudioStandards::Equipment.create_transformer(model,
                                                      wired_lighting_frac: 0.0281,
                                                      transformer_size: 45000,
                                                      transformer_efficiency: transformer_efficiency,
                                                      excluded_interiorequip_key: '2 Elevator Lift Motors',
                                                      excluded_interiorequip_meter: excluded_interiorequip_variable)

    model.getSpaces.sort.each do |space|
      if space.name.get.to_s == 'Core_bottom'
        model_add_elevator(model,
                           space,
                           prototype_input['number_of_elevators'],
                           prototype_input['elevator_type'],
                           prototype_input['elevator_schedule'],
                           prototype_input['elevator_fan_schedule'],
                           prototype_input['elevator_fan_schedule'],
                           building_type)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished building type specific adjustments')

    # add extra infiltration for entry door
    add_door_infiltration(climate_zone, model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Added door infiltration')

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

    entry_space = model.getSpaceByName('Perimeter_bot_ZN_1').get
    infiltration_entrydoor = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
    infiltration_entrydoor.setName('entry door Infiltration')
    infiltration_per_zone_entrydoor = 0
    if template == '90.1-2004'
      infiltration_per_zone_entrydoor = 1.04300287
      infiltration_entrydoor.setSchedule(model_add_schedule(model, 'OfficeMedium INFIL_Door_Opening_SCH'))
    elsif template == '90.1-2007' || template == '90.1-2010' || template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019'
      case climate_zone
        when 'ASHRAE 169-2006-0A',
             'ASHRAE 169-2006-1A',
             'ASHRAE 169-2006-0B',
             'ASHRAE 169-2006-1B',
             'ASHRAE 169-2006-2A',
             'ASHRAE 169-2006-2B',
             'ASHRAE 169-2013-0A',
             'ASHRAE 169-2013-1A',
             'ASHRAE 169-2013-0B',
             'ASHRAE 169-2013-1B',
             'ASHRAE 169-2013-2A',
             'ASHRAE 169-2013-2B'
          infiltration_per_zone_entrydoor = 1.04300287
          infiltration_entrydoor.setSchedule(model_add_schedule(model, 'OfficeMedium INFIL_Door_Opening_SCH'))
        else
          infiltration_per_zone_entrydoor = 0.678659786
          infiltration_entrydoor.setSchedule(model_add_schedule(model, 'OfficeMedium INFIL_Door_Opening_SCH'))
      end
    end
    infiltration_entrydoor.setDesignFlowRate(infiltration_per_zone_entrydoor)
    infiltration_entrydoor.setSpace(entry_space)
    return true
  end

  def model_custom_daylighting_tweaks(building_type, climate_zone, prototype_input, model)
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

  # @!group AirTerminalSingleDuctVAVReheat
  # Set the initial minimum damper position based on OA rate of the space and the template.
  # Zones with low OA per area get lower initial guesses.
  # Final position will be adjusted upward as necessary by Standards.AirLoopHVAC.apply_minimum_vav_damper_positions
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @param zone_oa_per_area [Double] the zone outdoor air per area in m^3/s*m^2
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_vav_reheat_apply_initial_prototype_damper_position(air_terminal_single_duct_vav_reheat, zone_oa_per_area)
    min_damper_position = template == '90.1-2010' || template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019' ? 0.2 : 0.3

    # Set the minimum flow fraction
    air_terminal_single_duct_vav_reheat.setConstantMinimumAirFlowFraction(min_damper_position)

    return true
  end

  # Type of SAT reset for this building type
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [String] Returns type of SAT reset
  def air_loop_hvac_supply_air_temperature_reset_type(air_loop_hvac)
    return 'oa'
  end
end
