# Custom changes for the LargeHotel prototype.
# These are changes that are inconsistent with other prototype building types.
module LargeHotel
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started building type specific HVAC adjustments')

    # add transformer
    # efficiency based on a 150 kVA transformer
    case template
    when '90.1-2004', '90.1-2007'
      transformer_efficiency = 0.971
    when '90.1-2010', '90.1-2013'
      transformer_efficiency = 0.983
    when '90.1-2016', '90.1-2019'
      transformer_efficiency = 0.988
    else
      transformer_efficiency = nil
    end
    return true if transformer_efficiency.nil?

    OpenstudioStandards::Equipment.create_transformer(model,
                                                      wired_lighting_frac: 0.0352,
                                                      transformer_size: 150000,
                                                      transformer_efficiency: transformer_efficiency)

    # add extra equipment for kitchen
    add_extra_equip_kitchen(model)

    # adjust VAV system sizing
    model.getAirLoopHVACs.each do |air_loop|
      if air_loop.name.to_s.include? 'VAV WITH REHEAT'
        # economizer type
        oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
        oa_intake_controller = oa_system.getControllerOutdoorAir
        oa_intake_controller.setEconomizerControlType('DifferentialEnthalpy')

        # zone sizing
        rht_sa_temp_c = OpenStudio.convert(90.0, 'F', 'C').get
        air_loop.thermalZones.each do |zone|
          air_terminal = zone.airLoopHVACTerminal
          if air_terminal.is_initialized
            air_terminal = air_terminal.get
            if air_terminal.to_AirTerminalSingleDuctVAVReheat.is_initialized
              air_terminal = air_terminal.to_AirTerminalSingleDuctVAVReheat.get
              air_terminal.setMaximumReheatAirTemperature(rht_sa_temp_c)
              reheat_coil = air_terminal.reheatCoil
              reheat_coil = reheat_coil.to_CoilHeatingWater.get
              reheat_coil.setRatedOutletAirTemperature(rht_sa_temp_c)
            end
          end
        end
      end
    end

    # Update Sizing Zone
    zone_sizing = model.getSpaceByName('Kitchen_Flr_6').get.thermalZone.get.sizingZone
    zone_sizing.setCoolingMinimumAirFlowFraction(0.7)

    zone_sizing = model.getSpaceByName('Laundry_Flr_1').get.thermalZone.get.sizingZone
    zone_sizing.setCoolingMinimumAirFlow(0.23567919336)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished building type specific adjustments')

    # Guestroom vacancy controls
    model_add_guestroom_vacancy_controls(model, 'LargeHotel')

    # Guestroom temperature reset schedule delay reduction from 30 min to 20 min
    model_reduce_setback_sch_delay(model, 'LargeHotel')

    # Guestroom ventilation availability schedule setup
    model_add_guestroom_vent_sch(model, 'LargeHotel')

    return true
  end

  # add extra equipment for kitchen
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def add_extra_equip_kitchen(model)
    kitchen_space = model.getSpaceByName('Kitchen_Flr_6')
    kitchen_space = kitchen_space.get
    kitchen_space_type = kitchen_space.spaceType.get
    elec_equip_def1 = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elec_equip_def2 = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elec_equip_def1.setName('Kitchen Electric Equipment Definition1')
    elec_equip_def2.setName('Kitchen Electric Equipment Definition2')
    case template
      when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        elec_equip_def1.setFractionLatent(0)
        elec_equip_def1.setFractionRadiant(0.25)
        elec_equip_def1.setFractionLost(0)
        elec_equip_def2.setFractionLatent(0)
        elec_equip_def2.setFractionRadiant(0.25)
        elec_equip_def2.setFractionLost(0)
        if template == '90.1-2013' || template == '90.1-2016'
          elec_equip_def1.setDesignLevel(457.7)
          elec_equip_def2.setDesignLevel(285)
        elsif template == '90.1-2019'
          elec_equip_def1.setDesignLevel(277.5)
          elec_equip_def2.setDesignLevel(156.7)
        else
          elec_equip_def1.setDesignLevel(515.917)
          elec_equip_def2.setDesignLevel(425.8)
        end
        # Create the electric equipment instance and hook it up to the space type
        elec_equip1 = OpenStudio::Model::ElectricEquipment.new(elec_equip_def1)
        elec_equip2 = OpenStudio::Model::ElectricEquipment.new(elec_equip_def2)
        elec_equip1.setName('Kitchen_Reach-in-Freezer')
        elec_equip2.setName('Kitchen_Reach-in-Refrigerator')
        elec_equip1.setSpaceType(kitchen_space_type)
        elec_equip2.setSpaceType(kitchen_space_type)
        elec_equip1.setSchedule(model_add_schedule(model, 'HotelLarge ALWAYS_ON'))
        elec_equip2.setSchedule(model_add_schedule(model, 'HotelLarge ALWAYS_ON'))
      # elec_equip2.setSchedule(model.alwaysOnDiscreteSchedule)
      # elec_equip2.setSchedule(model.alwaysOffDiscreteSchedule)
    end
    return true
  end

  # Add the daylighting controls for lobby, cafe, dinning and banquet
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_add_daylighting_controls(model)
    space_names = ['Banquet_Flr_6', 'Dining_Flr_6', 'Cafe_Flr_1', 'Lobby_Flr_1']
    space_names.each do |space_name|
      space = model.getSpaceByName(space_name).get
      space_add_daylighting_controls(space, false, false)
    end
    return true
  end

  # update water heater ambient conditions
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def update_waterheater_ambient_parameters(model)
    model.getWaterHeaterMixeds.sort.each do |water_heater|
      if water_heater.name.to_s.include?('300gal')
        water_heater.resetAmbientTemperatureSchedule
        water_heater.setAmbientTemperatureIndicator('ThermalZone')
        water_heater.setAmbientTemperatureThermalZone(model.getThermalZoneByName('Basement ZN').get)
      elsif water_heater.name.to_s.include?('6.0gal')
        water_heater.resetAmbientTemperatureSchedule
        water_heater.setAmbientTemperatureIndicator('ThermalZone')
        water_heater.setAmbientTemperatureThermalZone(model.getThermalZoneByName('Kitchen_Flr_6 ZN').get)
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
    update_waterheater_ambient_parameters(model)
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

  # List transfer air target and source zones, and airflow (cfm)
  # code_sections [90.1-2019_6.5.7.1], [90.1-2016_6.5.7.1]
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] target zones (key) and source zones (value) and air flow (value)
  def model_transfer_air_target_and_source_zones(model)
    model_transfer_air_target_and_source_zones_hash = {
      'Laundry_Flr_1 ZN' => ['Lobby_Flr_1 ZN', 500.0]
    }
    return model_transfer_air_target_and_source_zones_hash
  end
end
