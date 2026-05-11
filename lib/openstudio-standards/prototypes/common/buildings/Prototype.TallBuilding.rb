# Custom changes for the TallBuilding prototype.
# These are changes that are inconsistent with other prototype building types.
module TallBuilding
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started building type specific adjustments')

    # @todomake additional parameters mutable by the user
    #   the number of floors for each function type is defined in additional_params
    additional_params = {
      num_of_floor_retail: 2,
      num_of_floor_office: 18,
      num_of_floor_residential: 9,
      num_of_floor_hotel: 9
    }

    # add tall building elevators to the elevator machine room
    add_elevator_system_loads(model, additional_params)

    # for tall and super tall buildings, add main (multiple) and booster swh here instead of model_add_swh
    add_swh_tall_bldg(model, prototype_input, additional_params)

    # update the infiltration coefficients of tall buildings based on Lisa Ng's research (from NIST)
    # The set of coefficients are not quite appropriate for tall buildings, leading to super high infiltration rate
    # @todo further infiltration research is needed
    # update_infil_coeff(model)

    # apply vertical weather variations to tall buildings
    apply_vertical_weather_variation(model)

    # add thermostat to highriseapartment corridors
    add_thermostat_to_corridor(model)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished building type specific adjustments')

    return true
  end

  # Add elevators to elevator machine room schedules:
  # Large Office BLDG ELEVATORS, OfficeLarge ELEV_LIGHT_FAN_SCH_ADD_DF
  # HotelLarge BLDG_ELEVATORS, HotelLarge ELEV_LIGHT_FAN_SCH_ADD_DF
  # ApartmentMidRise BLDG_ELEVATORS, ApartmentMidRise ELEV_LIGHT_FAN_SCH_24_7
  # Retail elevator schedule developed
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param additional_params [Hash] hash of additional parameters
  # @return [Boolean] returns true if successful, false if not
  def add_elevator_system_loads(model, additional_params)
    # get the elevator machine room space from the model
    if model.getSpaceTypeByName('Elevator Machine Room').empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No Elevator Machine Room spacetype was found.')
      return false
    else
      elev_mc_rooms = model.getSpaceTypeByName('Elevator Machine Room').get.spaces
      if elev_mc_rooms.size > 1
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'More than one elevator machine room in the model.')
        return false
      elsif elev_mc_rooms.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No elevator machine room in the model.')
        return false
      else
        elev_mc_room = elev_mc_rooms[0]
      end
    end

    # calculate the number of elevators needed for each function type
    num_retail_flr = additional_params[:num_of_floor_retail].to_i
    num_office_flr = additional_params[:num_of_floor_office].to_i
    num_resi_flr = additional_params[:num_of_floor_residential].to_i
    num_hotel_flr = additional_params[:num_of_floor_hotel].to_i
    area_per_flr = 20000 # 20000 ft2 per floor
    motor_power_per_elev = 28300 # See scorecard Tall Building
    fan_light_power_per_elev = 161.9 # See scorecard Tall Building

    num_elev_retail = (num_retail_flr * area_per_flr / 45000.0).ceil
    num_elev_office = (num_office_flr * area_per_flr / 45000.0).ceil
    num_elev_resi = (num_resi_flr * area_per_flr / 45000.0).ceil
    num_elev_hotel = (num_hotel_flr * area_per_flr / 45000.0).ceil

    # create the equipment object for elevator motor and fan/lights separately, for each function type
    # Elevator lift motor
    add_elevator_equip(model, elev_mc_room, num_elev_retail, 'Retail', motor_power_per_elev, fan_light_power_per_elev,
                       'RetailStandalone BLDG_ELEVATORS', 'RetailStandalone ELEV_LIGHT_FAN_SCH_24_7')
    add_elevator_equip(model, elev_mc_room, num_elev_office, 'Office', motor_power_per_elev, fan_light_power_per_elev,
                       'OfficeLarge BLDG_ELEVATORS', 'OfficeLarge ELEV_LIGHT_FAN_SCH_24_7')
    add_elevator_equip(model, elev_mc_room, num_elev_resi, 'Apartment', motor_power_per_elev, fan_light_power_per_elev,
                       'ApartmentMidRise BLDG_ELEVATORS', 'ApartmentHighRise ELEV_LIGHT_FAN_SCH_24_7')
    add_elevator_equip(model, elev_mc_room, num_elev_hotel, 'Hotel', motor_power_per_elev, fan_light_power_per_elev,
                       'HotelLarge BLDG_ELEVATORS', 'HotelLarge ELEV_LIGHT_FAN_SCH_24_7')
    return true
  end

  # adds elevator equipment to space
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param space [OpenStudio::Model::Space] OpenStudio space object
  # @param num_of_elev [Double] number of elevators
  # @param function_type [String] function type
  # @param motor_power_per_elev [Double] elevator motor power in watts
  # @param fan_light_power_per_elev [Double] elevator fan power in watts
  # @param elev_power_sch_name [String] schedule to use for the elevator motor
  # @param elev_fan_light_sch_name [String] schedule to use for the elevator fan
  # @return [Boolean] returns true if successful, false if not
  def add_elevator_equip(model, space, num_of_elev, function_type, motor_power_per_elev, fan_light_power_per_elev,
                         elev_power_sch_name, elev_fan_light_sch_name)
    motor_equip_frac_loss = 0.85
    motor_equip_frac_radiant = 0.05
    fan_light_equip_frac_radiant = 0.5

    elevator_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elevator_definition.setName('Elevator Motor')
    elevator_definition.setDesignLevel(motor_power_per_elev * num_of_elev)
    elevator_definition.setFractionLost(motor_equip_frac_loss)
    elevator_definition.setFractionRadiant(motor_equip_frac_radiant)

    elevator_equipment = OpenStudio::Model::ElectricEquipment.new(elevator_definition)
    elevator_equipment.setName("#{num_of_elev} Elevator Motors for #{function_type}")
    elevator_equipment.setEndUseSubcategory('Elevators')
    elevator_sch = model_add_schedule(model, elev_power_sch_name)
    elevator_equipment.setSchedule(elevator_sch)
    elevator_equipment.setSpace(space)

    # Elevator fan and lights
    elevator_fan_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elevator_fan_definition.setName('Elevator Fan')
    elevator_fan_definition.setDesignLevel(fan_light_power_per_elev * num_of_elev)
    elevator_fan_definition.setFractionRadiant(fan_light_equip_frac_radiant)

    elevator_fan_equipment = OpenStudio::Model::ElectricEquipment.new(elevator_fan_definition)
    elevator_fan_equipment.setName("#{num_of_elev} Elevator Fans for #{function_type}")
    elevator_fan_equipment.setEndUseSubcategory('Elevators')
    elevator_fan_sch = model_add_schedule(model, elev_fan_light_sch_name)
    elevator_fan_equipment.setSchedule(elevator_fan_sch)
    elevator_fan_equipment.setSpace(space)
    return true
  end

  # for tall and super tall buildings, add main (multiple) and booster swh in model_custom_hvac_tweaks
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param prototype_input [Hash] hash of prototype inputs
  # @param additional_params [Hash] hash of additional parameters
  # @return [Boolean] returns true if successful, false if not
  def add_swh_tall_bldg(model, prototype_input, additional_params)
    # get all building stories and rank based on Z-origin
    story_info = {}
    model.getBuildingStorys.sort.each do |story|
      next if story.name.to_s.include? 'ElevatorMachineRm'

      story_info[story.name.to_s] = {}
      story_info[story.name.to_s]['z_coordinate'] = story.nominalZCoordinate.get.to_f
      story_info[story.name.to_s]['multiplier'] = story.spaces[0].multiplier
    end
    stories_ranked = story_info.sort_by { |story_name, story| story['z_coordinate'] }

    # combine stories that add up to no more than 12 floors
    swh_system_stories = []
    num_of_stories = 0 # initial
    hotel_swh_loop = nil
    stories_ranked.each_with_index do |story_pair, index|
      story_multiplier = story_pair[1]['multiplier']
      combined_num_of_story = num_of_stories + story_multiplier
      # if the top story (last one), combine into the last swh loop
      if combined_num_of_story <= 12 || (index == stories_ranked.size - 1) # 12 is based on large office prototype model
        swh_system_stories.push(story_pair[0])
        num_of_stories = combined_num_of_story
      end

      # if the top story (last one), create swh loop
      if combined_num_of_story > 12 || (index == stories_ranked.size - 1)
        # when combined stories reaches limitation, create the SWH system
        swh_fueltype = prototype_input['main_water_heater_fuel']
        # Add the main service water loop
        if swh_system_stories.size == 1
          swh_loop_name = "#{swh_system_stories[0].split(' story')[0]}} Service Water Loop"
        elsif swh_system_stories.size > 1
          swh_loop_name = "#{swh_system_stories[0].split(' story')[0]} to #{swh_system_stories[-1].split(' story')[0]} Service Water Loop"
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No story info in the SWH loop.')
          return false
        end
        main_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                   system_name: swh_loop_name,
                                                                                                   service_water_temperature: OpenStudio.convert(prototype_input['main_service_water_temperature'], 'F', 'C').get,
                                                                                                   service_water_pump_head: prototype_input['main_service_water_pump_head'].to_f,
                                                                                                   service_water_pump_motor_efficiency: prototype_input['main_service_water_pump_motor_efficiency'],
                                                                                                   water_heater_capacity: OpenStudio.convert(prototype_input['main_water_heater_capacity'], 'Btu/hr', 'W').get,
                                                                                                   water_heater_volume: OpenStudio.convert(prototype_input['main_water_heater_volume'], 'gal', 'm^3').get,
                                                                                                   water_heater_fuel: swh_fueltype,
                                                                                                   on_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['main_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get,
                                                                                                   off_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['main_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get)

        # Attach the end uses based on floor function type
        # Office and retail: add to mechanical room only
        # Hotel and apartment: add to each space
        swh_system_stories.each do |story_name|
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Adding shw by story spaces for Tall Building')

          hotel_swh_loop = main_swh_loop if story_name.include? 'Hotel_top' # locate the swh loop that supplies hotel top floor, where kitchen is. For booster

          # Log how many water fixtures are added
          water_fixtures = []

          story = model.getBuildingStoryByName(story_name).get
          story.spaces.each do |space|
            next if space.name.to_s.downcase.include? 'plenum'

            search_criteria = {
              'template' => template,
              'building_type' => space.spaceType.get.standardsBuildingType.get,
              'space_type' => space.spaceType.get.standardsSpaceType.get
            }
            data = standards_lookup_table_first(table_name: 'space_types', search_criteria: search_criteria)

            # Skip space types with no data
            next if data.nil?

            # Skip space types with no water use, unless it is a NECB archetype (these do not have peak flow rates defined)
            next if data['service_water_heating_peak_flow_rate'].to_f < 0.00001 && data['service_water_heating_peak_flow_per_area'].to_f < 0.00001

            # Add a service water use for each space
            water_fixture = model_add_swh_end_uses_by_space(model,
                                                            main_swh_loop,
                                                            space)
            unless water_fixture.nil?
              water_fixtures << water_fixture
            end
          end

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Added #{water_fixtures.size} water fixtures to SWH loop #{swh_loop_name}")
        end

        # reset to
        swh_system_stories = [story_pair[0]]
        num_of_stories = story_multiplier
      end
    end

    # Add the booster water loop if there is any hotel floor
    if additional_params[:num_of_floor_hotel].to_i > 0
      swh_booster_loop = OpenstudioStandards::ServiceWaterHeating.create_booster_water_heating_loop(model,
                                                                                                    water_heater_capacity: OpenStudio.convert(prototype_input['booster_water_heater_capacity'], 'Btu/hr', 'W').get,
                                                                                                    water_heater_volume: OpenStudio.convert(prototype_input['booster_water_heater_volume'], 'gal', 'm^3').get,
                                                                                                    water_heater_fuel: prototype_input['booster_water_heater_fuel'],
                                                                                                    service_water_temperature: OpenStudio.convert(prototype_input['booster_water_temperature'], 'F', 'C').get,
                                                                                                    service_water_loop: hotel_swh_loop)

      # add booster water use
      OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                name: 'Booster',
                                                                flow_rate: OpenStudio.convert(prototype_input['booster_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['booster_service_water_flowrate_schedule']),
                                                                water_use_temperature: OpenStudio.convert(prototype_input['booster_water_use_temperature'], 'F', 'C').get,
                                                                service_water_loop: swh_booster_loop)
    end

    # for tall and super tall buildings, there is laundry only if hotel has more than 1 floors
    # hotel_bot has laundry, if only one floor, doesn't have hotel_bot
    if additional_params[:num_of_floor_hotel].to_i > 1
      # Add the laundry service water heating loop
      laundry_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                    system_name: 'Laundry Service Water Loop',
                                                                                                    service_water_temperature: OpenStudio.convert(prototype_input['laundry_service_water_temperature'], 'F', 'C').get,
                                                                                                    service_water_pump_head: prototype_input['laundry_service_water_pump_head'].to_f,
                                                                                                    service_water_pump_motor_efficiency: prototype_input['laundry_service_water_pump_motor_efficiency'],
                                                                                                    water_heater_capacity: OpenStudio.convert(prototype_input['laundry_water_heater_capacity'], 'Btu/hr', 'W').get,
                                                                                                    water_heater_volume: OpenStudio.convert(prototype_input['laundry_water_heater_volume'], 'gal', 'm^3').get,
                                                                                                    water_heater_fuel: prototype_input['laundry_water_heater_fuel'],
                                                                                                    on_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['laundry_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get,
                                                                                                    off_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['laundry_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get)

      # add water use
      OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                name: 'Laundry',
                                                                flow_rate: OpenStudio.convert(prototype_input['laundry_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['laundry_service_water_flowrate_schedule']),
                                                                water_use_temperature: OpenStudio.convert(prototype_input['laundry_water_use_temperature'], 'F', 'C').get,
                                                                service_water_loop: laundry_swh_loop)
    end
    return true
  end

  # update the infiltration coefficients of tall buildings based on Lisa Ng's research (from NIST)
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def update_infil_coeff(model)
    #       System On  | System Off
    #  A: -0.03973203 | 0
    #  B: 0.02282265  | 0.031045705
    #  D: 0.083767524 | 0.016210069
    # Step1: replace the original infiltration schedule to airloop availability schedule, change the coeff to System On set
    # Step2: add new infiltration obj, assign with HVAC off schedule, assign the coeff to System Off set.
    # hotel and apartment HVAC are always on, so just do Step1, no Step2

    coeff_a_on = -0.03973203
    coeff_b_on = 0.02282265
    coeff_d_on = 0.083767524
    coeff_a_off = 0.0
    coeff_b_off = 0.031045705
    coeff_d_off = 0.016210069
    office_hvac_sch = model_add_schedule(model, 'OfficeLarge HVACOperationSchd')
    office_hvac_off_sch = model_add_schedule(model, 'OfficeLarge HVACOperationOFFSchd')
    retail_hvac_sch = model_add_schedule(model, 'RetailStandalone HVACOperationSchd')
    retail_hvac_off_sch = model_add_schedule(model, 'RetailStandalone HVACOperationOFFSchd')
    resi_hvac_sch = model_add_schedule(model, 'Always On')
    hotel_hvac_sch = model_add_schedule(model, 'HotelLarge HVACOperationSchd')

    model.getSpaceInfiltrationDesignFlowRates.sort.each do |infiltration|
      orin_infil_name = infiltration.name.to_s
      hvac_sch = nil
      hvac_off_sch = nil
      space_name = infiltration.space.get.name.to_s
      space_name = space_name.split[-1]
      if space_name.start_with? 'Office'
        hvac_sch = office_hvac_sch
        hvac_off_sch = office_hvac_off_sch
      elsif space_name.start_with? 'Retail'
        hvac_sch = retail_hvac_sch
        hvac_off_sch = retail_hvac_off_sch
      elsif space_name.start_with? 'Resi'
        hvac_sch = resi_hvac_sch
      elsif space_name.start_with? 'Hotel'
        hvac_sch = hotel_hvac_sch
      end

      unless hvac_sch.nil?
        infiltration.setName("#{orin_infil_name} HVAC On")
        infiltration.setSchedule(hvac_sch)
      end
      # coeff will be updated anyway
      infiltration.setConstantTermCoefficient(coeff_a_on)
      infiltration.setTemperatureTermCoefficient(coeff_b_on)
      infiltration.setVelocityTermCoefficient(0)
      infiltration.setVelocitySquaredTermCoefficient(coeff_d_on)

      unless hvac_off_sch.nil?
        infiltration_hvac_off = infiltration.clone(model).to_SpaceInfiltrationDesignFlowRate.get
        infiltration_hvac_off.setName("#{orin_infil_name} HVAC Off")
        infiltration_hvac_off.setSchedule(hvac_off_sch)
        infiltration_hvac_off.setConstantTermCoefficient(coeff_a_off)
        infiltration_hvac_off.setTemperatureTermCoefficient(coeff_b_off)
        infiltration_hvac_off.setVelocityTermCoefficient(0)
        infiltration_hvac_off.setVelocitySquaredTermCoefficient(coeff_d_off)
      end
    end
    return true
  end

  # apply vertical weather variations to tall buildings
  # current method is using the E+ default variation trend by specifying the height of outdoor air nodes
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def apply_vertical_weather_variation(model)
    # @todo OA node height is not implemented OpenStudio yet.
    # @todo Temporary fix to be done via adding EnergyPlus measure.
    # model.getAirLoopHVACOutdoorAirSystems.each do |oa_system|
    #   # get the outdoor air system outdoor air node
    #   oa_node = oa_system.outdoorAirModelObject.get.to_Node.get
    #   # get the height of the plenum if any, assign to outdoor air node
    #
    # end
    return true
  end

  # HighriseApartment doesn't apply thermostat to corridor spaces
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def add_thermostat_to_corridor(model)
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermostat.setName('HighriseApartment Corridor Thermostat')
    thermostat.setHeatingSetpointTemperatureSchedule(model_add_schedule(model, 'ApartmentHighRise HTGSETP_APT_SCH'))
    thermostat.setCoolingSetpointTemperatureSchedule(model_add_schedule(model, 'ApartmentHighRise CLGSETP_APT_SCH'))

    model.getSpaceTypes.each do |space_type|
      next if space_type.standardsBuildingType.empty?
      next if space_type.standardsSpaceType.empty?

      if space_type.standardsBuildingType.get == 'HighriseApartment' && space_type.standardsSpaceType.get == 'Corridor'
        space_type.spaces.each do |space|
          thermostat_clone = thermostat.clone(model).to_ThermostatSetpointDualSetpoint.get
          space.thermalZone.get.setThermostatSetpointDualSetpoint(thermostat_clone)
        end
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
    # customized swh system is not added here, but in model_custom_hvac_tweaks instead
    # because model_custom_swh_tweaks is performed in Prototype.Model after efficiency assignment. If swh added here, efficiency can't be updated.
    # this can't be moved upwards in Prototype.Model as it will affect other building types (e.g. SmallOfficeDetailed, LargeOfficeDetailed).
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
    # @todo make additional parameters mutable by the user
    # the number of floors for each function type is defined in additional_params
    additional_params = {
      num_of_floor_retail: 2,
      num_of_floor_office: 18,
      num_of_floor_residential: 9,
      num_of_floor_hotel: 9
    }

    # get the number of floors for each function
    if additional_params.nil?
      num_retail_flr = 2
      num_office_flr = 18
      num_resi_flr = 9
      num_hotel_flr = 9
    elsif additional_params.is_a?(Hash)
      keys = [:num_of_floor_retail, :num_of_floor_office, :num_of_floor_residential, :num_of_floor_hotel]
      if (additional_params.keys & keys).any? # if any function type is assigned with number of floor
        if additional_params.key?(:num_of_floor_retail) && additional_params[:num_of_floor_retail].is_a?(Numeric)
          num_retail_flr = additional_params[:num_of_floor_retail].to_i
        else
          num_retail_flr = 0
        end
        if additional_params.key?(:num_of_floor_office) && additional_params[:num_of_floor_office].is_a?(Numeric)
          num_office_flr = additional_params[:num_of_floor_office].to_i
        else
          num_office_flr = 0
        end
        if additional_params.key?(:num_of_floor_residential) && additional_params[:num_of_floor_residential].is_a?(Numeric)
          num_resi_flr = additional_params[:num_of_floor_residential].to_i
        else
          num_resi_flr = 0
        end
        if additional_params.key?(:num_of_floor_hotel) && additional_params[:num_of_floor_hotel].is_a?(Numeric)
          num_hotel_flr = additional_params[:num_of_floor_hotel].to_i
        else
          num_hotel_flr = 0
        end
        if num_retail_flr == 0 && num_office_flr == 0 && num_resi_flr == 0 && num_hotel_flr == 0
          num_retail_flr = 2
          num_office_flr = 18
          num_resi_flr = 9
          num_hotel_flr = 9
        elsif num_retail_flr + num_office_flr + num_resi_flr + num_hotel_flr < 20
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model',
                             'The building is not eligible as a tall building because the total number of floors is less than 20')
          return false
        elsif num_retail_flr + num_office_flr + num_resi_flr + num_hotel_flr >= 75
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model',
                             "The building has #{num_retail_flr + num_office_flr + num_resi_flr + num_hotel_flr} floors, which should "\
                             'be classified as super tall building. Please select SuperTall Building as the building type instead.')
          return false
        end
      else # if no number of floor is given for any function type
        num_retail_flr = 2
        num_office_flr = 18
        num_resi_flr = 9
        num_hotel_flr = 9
      end
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'additional_params is not a Hash')
      return false
    end

    # Validate number of floors values, can't be negative
    if num_retail_flr < 0
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Number of floors for Retail is negative.')
      return false
    elsif num_office_flr < 0
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Number of floors for Office is negative.')
      return false
    elsif num_resi_flr < 0
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Number of floors for Apartment is negative.')
      return false
    elsif num_hotel_flr < 0
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Number of floors for Hotel is negative.')
      return false
    elsif num_retail_flr == 0 && num_office_flr == 0 && num_resi_flr == 0 && num_hotel_flr == 0
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Number of floors for all function types are all zero.')
      return false
    end

    # update the number of floors in additional_params
    additional_params[:num_of_floor_retail] = num_retail_flr
    additional_params[:num_of_floor_office] = num_office_flr
    additional_params[:num_of_floor_residential] = num_resi_flr
    additional_params[:num_of_floor_hotel] = num_hotel_flr

    puts '*' * 150
    puts "num_retail_flr = #{num_retail_flr}"
    puts "num_office_flr = #{num_office_flr}"
    puts "num_resi_flr = #{num_resi_flr}"
    puts "num_hotel_flr = #{num_hotel_flr}"

    f_to_f_height_retail = 4.8768
    f_to_c_height_retail = 4.2672
    f_to_f_height_non_retail = 3.5052
    f_to_c_height_non_retail = 2.7432

    # Steps:
    # 1. Determine multiplier for each basic floor (as long as not bottom/top floor, don't need to separate floor)
    # 2. Modify name and Z origins for each floor as needed
    # 3. Fix surface boundary condition, change to adiabatic for floors using multiplier,
    #    and the floors below (plenum ceiling) and above (floor) the floors with multiplier
    # 4. construct hvac system map json

    # Check sum of num_of_flr below and above the current floor (e.g. For office, check retail num_of_flr, and check apartment + hotel num_of_flr)
    # if below is 0, separate one floor as the ground floor
    # if above is 0, separate one floor as the top floor
    # For example, when number of hotel floors is 0,
    # if num_resi_flr >=3,
    # the residential mid story (n>=2) should separate one story out as top floor.
    # else if num_resi_flr == 2, the resi_mid story works as the top floor
    # else if num_resi_flr == 1, the resi_bot story works as the top floor
    # similar for office and retail

    total_num_of_flr = num_retail_flr + num_office_flr + num_resi_flr + num_hotel_flr
    model.getBuilding.setStandardsNumberOfAboveGroundStories(total_num_of_flr)
    model.getBuilding.setStandardsNumberOfStories(total_num_of_flr + 1) # one basement story

    current_story = 1
    current_height = 0

    # Retail
    retail_f1_story_orin = model.getBuildingStoryByName('Retail_F1 story').get
    retail_f2_story_orin = model.getBuildingStoryByName('Retail_F2 story').get
    if num_retail_flr == 0
      [retail_f1_story_orin, retail_f2_story_orin].each do |story|
        story.spaces.each do |space|
          space.thermalZone.get.remove
          space.remove
        end
        story.remove
      end
    else # num_retail_flr >= 1
      # deal with retail_f1_story
      retail_f1_story_orin.setNominalZCoordinate(current_height)
      retail_f1_story_orin.setNominalFloortoFloorHeight(f_to_f_height_retail)
      retail_f1_story_orin.spaces.each do |space|
        space.setName("F#{current_story} " + space.name.to_s)
      end
      current_height += f_to_f_height_retail
      current_story += 1
      # deal with retail_f2_story, deep copy as needed
      if num_retail_flr > 1
        multiplier_list = get_multiplier_list(num_retail_flr - 1)
        if multiplier_list.is_a? Numeric
          multiplier = multiplier_list
          z_origin = current_height + (f_to_f_height_retail * ((multiplier / 2.0) - 0.5))
          if multiplier == 1 && num_office_flr >= 2
            deep_copy_story(model, retail_f2_story_orin, 1, z_origin, f_to_c_height_retail, f_to_f_height_retail, current_story, if_ground_story_plenum_adiabatic: true)
          else
            deep_copy_story(model, retail_f2_story_orin, multiplier, z_origin, f_to_c_height_retail, f_to_f_height_retail, current_story)
          end

          # update the story # and height #
          current_story += multiplier
          current_height += f_to_f_height_retail * multiplier
        elsif multiplier_list.is_a? Array
          multiplier_list.each do |mpl|
            z_origin = current_height + (f_to_f_height_retail * ((mpl / 2.0) - 0.5))
            deep_copy_story(model, retail_f2_story_orin, mpl, z_origin, f_to_c_height_retail, f_to_f_height_retail, current_story)

            # update the story # and height #
            current_story += mpl
            current_height += f_to_f_height_retail * mpl
          end
        end
      end
      # remove the original RetailF2 floor
      retail_f2_story_orin.spaces.each do |space|
        space.thermalZone.get.remove
        space.remove
      end
      retail_f2_story_orin.remove
    end

    # Office
    office_story_orin = model.getBuildingStoryByName('Office story').get
    if num_office_flr == 0
      office_story_orin.spaces.each do |space|
        space.thermalZone.get.remove
        space.remove
      end
      office_story_orin.remove
    elsif num_office_flr == 1
      # only update the z origin and name
      office_story_orin.setNominalZCoordinate(current_height)
      office_story_orin.setNominalFloortoFloorHeight(f_to_f_height_non_retail)
      office_story_orin.spaces.each do |space|
        space.setName("F#{current_story} " + space.name.to_s)
        if space.name.to_s.include? 'Plenum'
          space.setZOrigin(current_height + f_to_c_height_non_retail)
        else
          space.setZOrigin(current_height)
        end
      end
      office_story_orin.setName("F#{current_story} Office story")

      # update the story # and height #
      current_height += f_to_f_height_non_retail
      current_story += 1
    else
      num_office_flr_w_mult = num_office_flr
      # If no retail, separate one floor as ground floor
      if num_retail_flr == 0
        if_ground_story_plenum_adiabatic = false
        z_origin = current_height
        num_office_flr_w_mult -= 1
        if num_office_flr_w_mult > 1
          if_ground_story_plenum_adiabatic = true
        end
        deep_copy_story(model, office_story_orin, 1, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story, if_ground_story_plenum_adiabatic: if_ground_story_plenum_adiabatic)

        # update the story # and height #
        current_story += 1
        current_height += f_to_f_height_non_retail
      end

      # if no residential and hotel, separate one floor as top floor
      if num_resi_flr + num_hotel_flr == 0
        if_top_story_floor_adiabatic = false
        z_origin = (num_retail_flr * f_to_f_height_retail) + ((num_office_flr - 1) * f_to_f_height_non_retail)
        top_story_num = num_retail_flr + num_office_flr
        num_office_flr_w_mult -= 1
        if num_office_flr_w_mult > 1
          if_top_story_floor_adiabatic = true
        end
        deep_copy_story(model, office_story_orin, 1, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, top_story_num, if_top_story_floor_adiabatic: if_top_story_floor_adiabatic)
      end

      if num_office_flr_w_mult >= 1
        multiplier_list = get_multiplier_list(num_office_flr_w_mult)
        if multiplier_list.is_a? Numeric
          multiplier = multiplier_list
          z_origin = current_height + (f_to_f_height_non_retail * ((multiplier / 2.0) - 0.5))
          deep_copy_story(model, office_story_orin, multiplier, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story)

          # update the story # and height #
          current_story += multiplier
          current_height += f_to_f_height_non_retail * multiplier
        elsif multiplier_list.is_a? Array
          multiplier_list.each do |mpl|
            z_origin = current_height + (f_to_f_height_non_retail * ((mpl / 2.0) - 0.5))
            deep_copy_story(model, office_story_orin, mpl, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story)

            # update the story # and height #
            current_story += mpl
            current_height += f_to_f_height_non_retail * mpl
          end
        end
      end

      # remove the original office floor
      office_story_orin.spaces.each do |space|
        space.thermalZone.get.remove
        space.remove
      end
      office_story_orin.remove
    end

    # Apartment
    resi_bot_story_orin = model.getBuildingStoryByName('Resi_bot story').get
    resi_mid_story_orin = model.getBuildingStoryByName('Resi_mid story').get
    if num_resi_flr == 0
      [resi_bot_story_orin, resi_mid_story_orin].each do |story|
        story.spaces.each do |space|
          space.thermalZone.get.remove
          space.remove
        end
        story.remove
      end
    else # num_resi_flr >= 1
      # deal with resi_bot story
      resi_bot_story_orin.setNominalZCoordinate(current_height)
      resi_bot_story_orin.setNominalFloortoFloorHeight(f_to_f_height_non_retail)
      resi_bot_story_orin.setName("F#{current_story} " + resi_bot_story_orin.name.to_s)
      resi_bot_story_orin.spaces.each do |space|
        space.setName("F#{current_story} " + space.name.to_s)
        if space.name.to_s.include? 'Plenum'
          space.setZOrigin(current_height + f_to_c_height_non_retail)
        else
          space.setZOrigin(current_height)
        end
      end
      current_height += f_to_f_height_non_retail
      current_story += 1

      # deal with resi_mid story, deep copy if needed
      if num_resi_flr > 1
        num_resi_mid_flr_w_mult = num_resi_flr - 1
        # if no hotel, separate one floor from resi_mid story as top floor
        if num_hotel_flr == 0
          if_top_story_floor_adiabatic = false
          z_origin = (num_retail_flr * f_to_f_height_retail) + ((num_office_flr + num_resi_flr - 1) * f_to_f_height_non_retail)
          top_story_num = num_retail_flr + num_office_flr + num_resi_flr
          num_resi_mid_flr_w_mult -= 1
          if num_resi_mid_flr_w_mult > 1
            if_top_story_floor_adiabatic = true
          end
          deep_copy_story(model, resi_mid_story_orin, 1, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, top_story_num, if_top_story_floor_adiabatic: if_top_story_floor_adiabatic)
        end

        if num_resi_mid_flr_w_mult >= 1
          multiplier_list = get_multiplier_list(num_resi_mid_flr_w_mult)
          if multiplier_list.is_a? Numeric
            multiplier = multiplier_list
            z_origin = current_height + (f_to_f_height_non_retail * ((multiplier / 2.0) - 0.5))
            deep_copy_story(model, resi_mid_story_orin, multiplier, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story)

            current_story += multiplier
            current_height += f_to_f_height_non_retail * multiplier
          elsif multiplier_list.is_a? Array
            multiplier_list.each do |mpl|
              z_origin = current_height + (f_to_f_height_non_retail * ((mpl / 2.0) - 0.5))
              deep_copy_story(model, resi_mid_story_orin, mpl, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story)

              # update the story # and height #
              current_story += mpl
              current_height += f_to_f_height_non_retail * mpl
            end
          end
        end
      end

      # remove the original resi_mid story
      resi_mid_story_orin.spaces.each do |space|
        space.thermalZone.get.remove
        space.remove
      end
      resi_mid_story_orin.remove
    end

    # Hotel
    hotel_bot_story_orin = model.getBuildingStoryByName('Hotel_bot story').get
    hotel_mid_story_orin = model.getBuildingStoryByName('Hotel_mid story').get
    hotel_top_story_orin = model.getBuildingStoryByName('Hotel_top story').get
    if num_hotel_flr == 0
      [hotel_bot_story_orin, hotel_mid_story_orin, hotel_top_story_orin].each do |story|
        story.spaces.each do |space|
          space.thermalZone.get.remove
          space.remove
        end
        story.remove
      end
    else # num_hotel_flr >= 1
      # deal with hotel_top_story
      hotel_top_origin = (num_retail_flr * f_to_f_height_retail) + ((num_office_flr + num_resi_flr + num_hotel_flr - 1) * f_to_f_height_non_retail)
      hotel_top_story_orin.setNominalZCoordinate(hotel_top_origin)
      hotel_top_story_orin.setNominalFloortoFloorHeight(f_to_f_height_non_retail)
      hotel_top_story_orin.setName("F#{total_num_of_flr} " + hotel_top_story_orin.name.to_s)
      hotel_top_story_orin.spaces.each do |space|
        space.setName("F#{total_num_of_flr} " + space.name.to_s)
        if space.name.to_s.include? 'Plenum'
          space.setZOrigin(hotel_top_origin + f_to_c_height_non_retail)
        else
          space.setZOrigin(hotel_top_origin)
        end
      end
      # deal with hotel_bot and hotel_mid stories, deep copy as needed
      if num_hotel_flr > 1
        # deal with hotel_bot_story
        hotel_bot_story_orin.setNominalZCoordinate(current_height)
        hotel_bot_story_orin.setNominalFloortoFloorHeight(f_to_f_height_non_retail)
        hotel_bot_story_orin.setName("F#{current_story} " + hotel_bot_story_orin.name.to_s)
        hotel_bot_story_orin.spaces.each do |space|
          space.setName("F#{current_story} " + space.name.to_s)
          if space.name.to_s.include? 'Plenum'
            space.setZOrigin(current_height + f_to_c_height_non_retail)
          else
            space.setZOrigin(current_height)
          end
        end

        current_story += 1
        current_height += f_to_f_height_non_retail

        if num_hotel_flr >= 3
          multiplier_list = get_multiplier_list(num_hotel_flr - 2)
          if multiplier_list.is_a? Numeric
            multiplier = multiplier_list
            z_origin = current_height + (f_to_f_height_non_retail * ((multiplier / 2.0) - 0.5))
            deep_copy_story(model, hotel_mid_story_orin, multiplier, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story)

          elsif multiplier_list.is_a? Array
            multiplier_list.each do |mpl|
              z_origin = current_height + (f_to_f_height_non_retail * ((mpl / 2.0) - 0.5))
              deep_copy_story(model, hotel_mid_story_orin, mpl, z_origin, f_to_c_height_non_retail, f_to_f_height_non_retail, current_story)

              # update the story # and height #
              current_story += mpl
              current_height += f_to_f_height_non_retail * mpl
            end
          end
        end
      else # num_hotel_flr == 1
        hotel_bot_story_orin.spaces.each do |space|
          space.thermalZone.get.remove
          space.remove
        end
        hotel_bot_story_orin.remove
      end

      # remove the original hotel_mid floor
      hotel_mid_story_orin.spaces.each do |space|
        space.thermalZone.get.remove
        space.remove
      end
      hotel_mid_story_orin.remove
    end

    # Relocate the ElevatorMachineRm story
    building_height = (num_retail_flr * f_to_f_height_retail) + ((num_office_flr + num_resi_flr + num_hotel_flr) * f_to_f_height_non_retail)
    top_elevator_machine_rm_story = model.getBuildingStoryByName('ElevatorMachineRm story').get
    top_elevator_machine_rm_story.setNominalZCoordinate(building_height)
    top_elevator_machine_rm_story.spaces.each do |space|
      space.setZOrigin(building_height)
    end

    # connect the surfaces
    spaces = OpenStudio::Model::SpaceVector.new
    model.getSpaces.sort.each do |space|
      spaces << space
    end
    OpenStudio::Model.intersectSurfaces(spaces)
    OpenStudio::Model.matchSurfaces(spaces)

    # Update the hvac system map based on updated geometry
    new_hvac_map_str = generate_new_json(model, additional_params)
    @system_to_space_map = JSON.parse(new_hvac_map_str)
    return true
  end

  # generate input json based on input parameters
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param additional_params [Hash] hash of additional parameters
  # @return [Json] json file
  def generate_new_json(model, additional_params)
    new_json = []

    # get the number of floors for each function
    num_retail_flr = additional_params[:num_of_floor_retail].to_i
    num_office_flr = additional_params[:num_of_floor_office].to_i
    num_resi_flr = additional_params[:num_of_floor_residential].to_i
    num_hotel_flr = additional_params[:num_of_floor_hotel].to_i

    # one chiller per 13 floors, +1 is basement. Ref: large office prototype model
    num_chillers = ((num_retail_flr + num_office_flr + num_resi_flr + num_hotel_flr + 1) / 13.0).ceil
    hotel_common_spaces = []
    hotel_top_plenum_space = nil
    model.getBuildingStorys.each do |story|
      story_name = story.name.to_s
      space_names = []
      plenum_space = ''
      story.spaces.sort.each do |space|
        if space.name.to_s.include? 'Plenum'
          plenum_space = space.name.to_s
        elsif (story_name.include? 'Hotel') && (!space.name.to_s.downcase.include? 'guest')
          hotel_common_spaces.push(space.name.to_s)
        else
          space_names.push(space.name.to_s)
        end
      end
      if story_name.include? 'Office'
        hvac_obj = {
          type: 'VAV',
          name: "#{story_name} VAV WITH REHEAT",
          return_plenum: plenum_space,
          operation_schedule: 'OfficeLarge HVACOperationSchd',
          oa_damper_schedule: 'OfficeLarge MinOA_MotorizedDamper_Sched',
          chw_pumping_type: 'const_pri_var_sec',
          chiller_cooling_type: 'WaterCooled',
          chiller_condenser_type: nil,
          chiller_compressor_type: 'Centrifugal',
          chw_number_chillers: num_chillers,
          number_cooling_towers: num_chillers,
          space_names: space_names
        }

      elsif story_name.include? 'Retail'
        hvac_obj = {
          type: 'VAV',
          name: "#{story_name} VAV WITH REHEAT",
          return_plenum: plenum_space,
          operation_schedule: 'RetailStandalone HVACOperationSchd',
          oa_damper_schedule: 'RetailStandalone MinOA_MotorizedDamper_Sched',
          chw_pumping_type: 'const_pri_var_sec',
          chiller_cooling_type: 'WaterCooled',
          chiller_condenser_type: nil,
          chiller_compressor_type: 'Centrifugal',
          chw_number_chillers: num_chillers,
          number_cooling_towers: num_chillers,
          space_names: space_names
        }

      elsif story_name.include? 'Hotel'
        hvac_obj = {
          type: 'DOAS Cold Supply',
          name: "#{story_name} DOAS",
          return_plenum: plenum_space,
          operation_schedule: 'HotelLarge HVACOperationSchd',
          oa_damper_schedule: 'HotelLarge MinOA_MotorizedDamper_Sched',
          chw_pumping_type: 'const_pri_var_sec',
          chiller_cooling_type: 'WaterCooled',
          chiller_condenser_type: nil,
          chiller_compressor_type: 'Centrifugal',
          chw_number_chillers: num_chillers,
          number_cooling_towers: num_chillers,
          economizer_control_method: 'DifferentialDryBulb',
          space_names: space_names
        }
        # get the top floor plenum for hotel common areas' VAV system
        hotel_top_plenum_space = plenum_space if story_name.include? 'top'

      elsif story_name.include? 'Resi'
        hvac_obj = {
          type: 'DOAS Cold Supply',
          name: "#{story_name} DOAS",
          return_plenum: plenum_space,
          operation_schedule: 'Always On',
          oa_damper_schedule: 'Always On',
          chw_pumping_type: 'const_pri_var_sec',
          chiller_cooling_type: 'WaterCooled',
          chiller_condenser_type: nil,
          chiller_compressor_type: 'Centrifugal',
          chw_number_chillers: num_chillers,
          number_cooling_towers: num_chillers,
          economizer_control_method: 'DifferentialDryBulb',
          space_names: space_names
        }

      elsif story_name.include? 'Basement'
        hvac_obj = {
          type: 'CAV',
          name: 'CAV_bas',
          operation_schedule: 'OfficeLarge HVACOperationSchd',
          oa_damper_schedule: 'OfficeLarge MinOA_MotorizedDamper_Sched',
          chw_pumping_type: 'const_pri_var_sec',
          chiller_cooling_type: 'WaterCooled',
          chiller_condenser_type: nil,
          chiller_compressor_type: 'Centrifugal',
          chw_number_chillers: num_chillers,
          number_cooling_towers: num_chillers,
          space_names: space_names
        }

      elsif story_name.include? 'ElevatorMachineRm'
        hvac_obj = {
          type: 'PSZ-AC',
          name: "#{story_name} PSZ-AC",
          operation_schedule: 'Always On',
          oa_damper_schedule: 'Always On',
          cooling_type: 'Single Speed DX AC',
          heating_type: 'Electricity',
          fan_type: 'ConstantVolume',
          space_names: space_names
        }
      end

      new_json.push(hvac_obj)
    end

    # add VAV system for all hotel common area spaces
    if num_hotel_flr >= 1
      hotel_common_hvac_obj = {
        type: 'VAV',
        name: 'Hotel Common Areas VAV WITH REHEAT',
        return_plenum: hotel_top_plenum_space,
        operation_schedule: 'HotelLarge HVACOperationSchd',
        oa_damper_schedule: 'HotelLarge MinOA_MotorizedDamper_Sched',
        chw_pumping_type: 'const_pri_var_sec',
        chiller_cooling_type: 'WaterCooled',
        chiller_condenser_type: nil,
        chiller_compressor_type: 'Centrifugal',
        chw_number_chillers: num_chillers,
        number_cooling_towers: num_chillers,
        space_names: hotel_common_spaces
      }
      new_json.push(hotel_common_hvac_obj)
    end

    return JSON.pretty_generate(new_json)
  end

  # generate multipler list from number of floors
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Array<Double>] mutiplier list
  def get_multiplier_list(num_floors)
    a = (num_floors.to_f / 10).ceil #  a = (25.0/10).ceil => 3
    return num_floors if a == 1

    multiplier_list = []
    multiplier = (num_floors.to_f / a).ceil # multiplier = (25.0/3).ceil = 9
    multiplier_rep_times = num_floors / multiplier # multiplier_rep_times = 25/9 = 2
    if num_floors % multiplier == 0
      multiplier_list.fill(multiplier, multiplier_list.size, multiplier_rep_times) # [multiplier,multiplier,multiplier...]
    else
      spare_multiplier = num_floors % multiplier # spare_multiplier = 25 % 9 = 7
      i = 0
      while i < multiplier_rep_times
        multiplier_list << multiplier
        i += 1
      end
      multiplier_list << spare_multiplier # [multiplier, multiplier, spare_multiplier]
    end
    return multiplier_list
  end

  # adjust space boundary conditions to adiabatic
  #
  # @param space [OpenStudio::Model::Space] OpenStudio space object
  # @param if_top_story_floor_adiabatic [Boolean] flag if top floor is adiabatic
  # @param if_ground_story_plenum_adiabatic [Boolean] flag if ground story plenum is adiabatic
  # @return [Boolean] returns true if successful, false if not
  def update_space_outside_boundary_to_adiabatic(space, if_top_story_floor_adiabatic: false, if_ground_story_plenum_adiabatic: false)
    if (space.name.to_s.include? 'Plenum') && !if_top_story_floor_adiabatic
      space.surfaces.each do |surface|
        next unless surface.surfaceType.to_s == 'RoofCeiling'

        surface.setOutsideBoundaryCondition('Adiabatic')

        next unless surface.outsideBoundaryCondition.to_s == 'Surface'

        unless surface.adjacentSurface.empty?
          adj_surface = surface.adjacentSurface.get
          adj_surface.setOutsideBoundaryCondition('Adiabatic')
        end
      end
    else
      # for ground floor plenum adiabatic scenario, skip floors
      unless if_ground_story_plenum_adiabatic
        space.surfaces.each do |surface|
          next unless surface.surfaceType.to_s == 'Floor'

          surface.setOutsideBoundaryCondition('Adiabatic')

          next unless surface.outsideBoundaryCondition.to_s == 'Surface'

          unless surface.adjacentSurface.empty?
            adj_surface = surface.adjacentSurface.get
            adj_surface.setOutsideBoundaryCondition('Adiabatic')
          end
        end
      end
    end
    return true
  end

  # copies a building story
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param original_story [OpenStudio::Model::BuildingStory] OpenStudio building story object
  # @param multiplier [Double] multipler for number of stories
  # @param new_z_origin [Double] new z origin height in meters
  # @param f_to_c_height [Double] floor to ceiling height in meters
  # @param f_to_f_height [Double] floor to floor height in meters
  # @param current_story [OpenStudio::Model::BuildingStory] OpenStudio building story object
  # @param if_top_story_floor_adiabatic [Boolean] flag if top floor is adiabatic
  # @param if_ground_story_plenum_adiabatic [Boolean] flag if ground story plenum is adiabatic
  # @return [Boolean] returns true if successful, false if not
  def deep_copy_story(model, original_story, multiplier, new_z_origin, f_to_c_height, f_to_f_height, current_story, if_top_story_floor_adiabatic: false, if_ground_story_plenum_adiabatic: false)
    # clone the story
    new_story = original_story.clone(model).to_BuildingStory.get
    new_story.setNominalZCoordinate(new_z_origin)
    new_story.setNominalFloortoFloorHeight(f_to_f_height)
    new_story.setNominalFloortoCeilingHeight(f_to_c_height)
    if multiplier == 1
      new_story.setName("F#{current_story} " + original_story.name.to_s)
    else
      new_story.setName("F#{current_story}-" + "F#{current_story + multiplier - 1} " + original_story.name.to_s)
    end

    # clone the spaces on the story
    original_story.spaces.each do |space|
      old_name = space.name.to_s
      if multiplier == 1
        new_name = "F#{current_story} " + old_name
      else
        new_name = "F#{current_story}-" + "F#{current_story + multiplier - 1} " + old_name
      end
      # clone space
      new_space = space.clone(model).to_Space.get
      new_space.setName(new_name)
      # assign new Z Origin
      if old_name.include? 'Plenum'
        new_space.setZOrigin(new_z_origin + f_to_c_height)
      else
        new_space.setZOrigin(new_z_origin)
      end
      # clone thermal zone and assign
      new_t_zone = space.thermalZone.get.clone(model).to_ThermalZone.get
      new_t_zone.setName("TZ-#{new_name}")
      new_t_zone.setMultiplier(multiplier * space.thermalZone.get.multiplier) # story multiplier and original thermal zone multiplier
      new_space.setThermalZone(new_t_zone)
      # assign new building story
      new_space.setBuildingStory(new_story)

      # update boundary condition to adiabatic as needed
      # for top story, when the story below has a multiplier
      # set the surface boundary condition as adiabatic for its floors (otherwise they will end up being "ground")
      if multiplier > 1 || (multiplier == 1 && if_top_story_floor_adiabatic) || (multiplier == 1 && if_ground_story_plenum_adiabatic)
        update_space_outside_boundary_to_adiabatic(new_space, if_top_story_floor_adiabatic: if_top_story_floor_adiabatic, if_ground_story_plenum_adiabatic: if_ground_story_plenum_adiabatic)
      end
    end
    return true
  end
end
