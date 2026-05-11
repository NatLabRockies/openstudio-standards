class Standard
  # Add service water heating to the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] building type
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_add_swh(model, building_type, prototype_input)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding Service Water Heating')

    # Add the main service water heating loop, if specified
    # for tall and super tall buildings, add main (multiple) and booster swh in model_custom_hvac_tweaks
    unless prototype_input['main_water_heater_volume'].nil? || (building_type == 'TallBuilding' || building_type == 'SuperTallBuilding')
      # Get the thermal zone for the water heater, if specified
      water_heater_zone = nil
      if prototype_input['main_water_heater_space_name']
        wh_space_name = prototype_input['main_water_heater_space_name']
        wh_space = model.getSpaceByName(wh_space_name)
        if wh_space.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Cannot find a space called #{wh_space_name} in the model, water heater will not be placed in a zone.")
        else
          wh_zone = wh_space.get.thermalZone
          if wh_zone.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Cannot find a zone that contains the space #{wh_space_name} in the model, water heater will not be placed in a zone.")
          else
            water_heater_zone = wh_zone.get
          end
        end
      end

      swh_fueltype = prototype_input['main_water_heater_fuel']
      # Add the main service water loop
      unless building_type == 'RetailStripmall' && template != 'NECB2011'
        main_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                   system_name: 'Main Service Water Loop',
                                                                                                   service_water_temperature: OpenStudio.convert(prototype_input['main_service_water_temperature'], 'F', 'C').get,
                                                                                                   service_water_pump_head: prototype_input['main_service_water_pump_head'].to_f,
                                                                                                   service_water_pump_motor_efficiency: prototype_input['main_service_water_pump_motor_efficiency'],
                                                                                                   water_heater_capacity: OpenStudio.convert(prototype_input['main_water_heater_capacity'], 'Btu/hr', 'W').get,
                                                                                                   water_heater_volume: OpenStudio.convert(prototype_input['main_water_heater_volume'], 'gal', 'm^3').get,
                                                                                                   water_heater_fuel: swh_fueltype,
                                                                                                   on_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['main_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get,
                                                                                                   off_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['main_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get,
                                                                                                   water_heater_thermal_zone: water_heater_zone)
      end

      # Attach the end uses if specified in prototype inputs
      # @todo remove special logic for large office SWH end uses
      # @todo remove special logic for stripmall SWH end uses and service water loops
      # @todo remove special logic for large hotel SWH end uses
      if building_type == 'LargeOffice' && template != 'NECB2011'

        # Only the core spaces have service water
        ['Core_bottom', 'Core_mid', 'Core_top'].sort.each do |space_name|
          # ['Mechanical_Bot_ZN_1','Mechanical_Mid_ZN_1','Mechanical_Top_ZN_1'].each do |space_name| # for new space type large office
          OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                    name: 'Main',
                                                                    flow_rate: OpenStudio.convert(prototype_input['main_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                    flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['main_service_water_flowrate_schedule']),
                                                                    water_use_temperature: OpenStudio.convert(prototype_input['main_water_use_temperature'], 'F', 'C').get,
                                                                    service_water_loop: main_swh_loop,
                                                                    space: model.getSpaceByName(space_name).get)
        end
      elsif building_type == 'LargeOfficeDetailed' && template != 'NECB2011'

        # Only mechanical rooms have service water
        ['Mechanical_Bot_ZN_1', 'Mechanical_Mid_ZN_1', 'Mechanical_Top_ZN_1'].sort.each do |space_name| # for new space type large office
          OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                    name: 'Main',
                                                                    flow_rate: OpenStudio.convert(prototype_input['main_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                    flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['main_service_water_flowrate_schedule']),
                                                                    water_use_temperature: OpenStudio.convert(prototype_input['main_water_use_temperature'], 'F', 'C').get,
                                                                    service_water_loop: main_swh_loop,
                                                                    space: model.getSpaceByName(space_name).get)
        end
      elsif building_type == 'RetailStripmall' && template != 'NECB2011'

        return true if template == 'DOE Ref Pre-1980' || template == 'DOE Ref 1980-2004'

        # Create a separate hot water loop & water heater for each space in the list
        swh_space_names = ['LGstore1', 'SMstore1', 'SMstore2', 'SMstore3', 'LGstore2', 'SMstore5', 'SMstore6']
        swh_sch_names = ['RetailStripmall Type1_SWH_SCH', 'RetailStripmall Type1_SWH_SCH', 'RetailStripmall Type2_SWH_SCH',
                         'RetailStripmall Type2_SWH_SCH', 'RetailStripmall Type3_SWH_SCH', 'RetailStripmall Type3_SWH_SCH',
                         'RetailStripmall Type3_SWH_SCH']
        rated_use_rate_gal_per_min = 0.03 # in gal/min
        rated_flow_rate_m3_per_s = OpenStudio.convert(rated_use_rate_gal_per_min, 'gal/min', 'm^3/s').get

        # Loop through all spaces
        swh_space_names.zip(swh_sch_names).sort.each do |swh_space_name, swh_sch_name|
          swh_thermal_zone = model.getSpaceByName(swh_space_name).get.thermalZone.get
          main_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                     system_name: "#{swh_thermal_zone.name} Service Water Loop",
                                                                                                     service_water_temperature: OpenStudio.convert(prototype_input['main_service_water_temperature'], 'F', 'C').get,
                                                                                                     service_water_pump_head: prototype_input['main_service_water_pump_head'].to_f,
                                                                                                     service_water_pump_motor_efficiency: prototype_input['main_service_water_pump_motor_efficiency'],
                                                                                                     water_heater_capacity: OpenStudio.convert(prototype_input['main_water_heater_capacity'], 'Btu/hr', 'W').get,
                                                                                                     water_heater_volume: OpenStudio.convert(prototype_input['main_water_heater_volume'], 'gal', 'm^3').get,
                                                                                                     water_heater_fuel: prototype_input['main_water_heater_fuel'],
                                                                                                     on_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['main_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get,
                                                                                                     off_cycle_parasitic_fuel_consumption_rate: OpenStudio.convert(prototype_input['main_service_water_parasitic_fuel_consumption_rate'], 'Btu/hr', 'W').get,
                                                                                                     water_heater_thermal_zone: swh_thermal_zone)

          OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                    name: 'Main',
                                                                    flow_rate: rated_flow_rate_m3_per_s,
                                                                    flow_rate_fraction_schedule: model_add_schedule(model, swh_sch_name),
                                                                    water_use_temperature: OpenStudio.convert(prototype_input['main_water_use_temperature'], 'F', 'C').get,
                                                                    service_water_loop: main_swh_loop,
                                                                    space: model.getSpaceByName(swh_space_name).get)
        end

      elsif prototype_input['main_service_water_peak_flowrate']
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Adding shw by main_service_water_peak_flowrate')

        # Attaches the end uses if specified as a lump value in the prototype_input
        OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                  name: 'Main',
                                                                  flow_rate: OpenStudio.convert(prototype_input['main_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                  flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['main_service_water_flowrate_schedule']),
                                                                  water_use_temperature: OpenStudio.convert(prototype_input['main_water_use_temperature'], 'F', 'C').get,
                                                                  service_water_loop: main_swh_loop)
      else
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Adding shw by space_type_map')

        # Attaches the end uses if specified by space type
        space_type_map = @space_type_map

        if template == 'NECB2011'
          building_type = 'Space Function'
        end

        # Log how many water fixtures are added
        water_fixtures = []

        # Loop through spaces types and add service hot water if specified
        space_type_map.sort.each do |space_type_name, space_names|
          search_criteria = {
            'template' => template,
            'building_type' => model_get_lookup_name(building_type),
            'space_type' => space_type_name
          }
          data = standards_lookup_table_first(table_name: 'space_types', search_criteria: search_criteria)

          # Skip space types with no data
          next if data.nil?

          # Skip space types with no water use, unless it is a NECB archetype (these do not have peak flow rates defined)
          next unless template == 'NECB2011' || !data['service_water_heating_peak_flow_rate'].nil? || !data['service_water_heating_peak_flow_per_area'].nil?

          # Add a service water use for each space
          space_names.sort.each do |space_name|
            space = model.getSpaceByName(space_name).get
            space_multiplier = nil
            space_multiplier = case template
                                 when 'NECB2011'
                                   # Added this to prevent double counting of zone multipliers.. space multipliers are never used in NECB archtypes.
                                   1
                                 else
                                   space.multiplier
                               end

            water_fixture = model_add_swh_end_uses_by_space(model,
                                                            main_swh_loop,
                                                            space)
            unless water_fixture.nil?
              water_fixtures << water_fixture
            end
          end
        end

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Added #{water_fixtures.size} water fixtures to model")
      end
    end

    # Add the booster water heater, if specified
    # for tall and super tall buildings, add main (multiple) and booster swh in model_custom_hvac_tweaks
    unless prototype_input['booster_water_heater_volume'].nil? || (building_type == 'TallBuilding' || building_type == 'SuperTallBuilding')
      # Add the booster water loop
      swh_booster_loop = OpenstudioStandards::ServiceWaterHeating.create_booster_water_heating_loop(model,
                                                                                                    water_heater_capacity: OpenStudio.convert(prototype_input['booster_water_heater_capacity'], 'Btu/hr', 'W').get,
                                                                                                    water_heater_volume: OpenStudio.convert(prototype_input['booster_water_heater_volume'], 'gal', 'm^3').get,
                                                                                                    water_heater_fuel: prototype_input['booster_water_heater_fuel'],
                                                                                                    service_water_temperature: OpenStudio.convert(prototype_input['booster_water_temperature'], 'F', 'C').get,
                                                                                                    service_water_loop: main_swh_loop)

      # add booster water use
      OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                name: 'Booster',
                                                                flow_rate: OpenStudio.convert(prototype_input['booster_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['booster_service_water_flowrate_schedule']),
                                                                water_use_temperature: OpenStudio.convert(prototype_input['booster_water_use_temperature'], 'F', 'C').get,
                                                                service_water_loop: swh_booster_loop)
    end

    # Add the laundry water heater, if specified
    # for tall and super tall buildings, add laundry swh in model_custom_hvac_tweaks
    unless prototype_input['laundry_water_heater_volume'].nil? || (building_type == 'TallBuilding' || building_type == 'SuperTallBuilding')
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

      # Attach the end uses if specified in prototype inputs
      OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                name: 'Laundry',
                                                                flow_rate: OpenStudio.convert(prototype_input['laundry_service_water_peak_flowrate'], 'gal/min', 'm^3/s').get,
                                                                flow_rate_fraction_schedule: model_add_schedule(model, prototype_input['laundry_service_water_flowrate_schedule']),
                                                                water_use_temperature: OpenStudio.convert(prototype_input['laundry_water_use_temperature'], 'F', 'C').get,
                                                                service_water_loop: laundry_swh_loop)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding Service Water Heating')

    return true
  end

  # This method will add a swh water fixture to the model for the space.
  # It will return a water fixture object, or NIL if there is no water load at all.
  #
  # Adds a WaterUseEquipment object representing the SWH loads of the supplied Space.
  # Attaches this WaterUseEquipment to the supplied PlantLoop via a new WaterUseConnections object.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param swh_loop [OpenStudio::Model::PlantLoop] the SWH loop to connect the WaterUseEquipment to
  # @param space [OpenStudio::Model::Space] the Space to add a WaterUseEquipment for
  # @param is_flow_per_area [Boolean] if true, use the value in the 'service_water_heating_peak_flow_per_area'
  #   field of the space_types JSON.  If false, use the value in the 'service_water_heating_peak_flow_rate' field.
  # @return [OpenStudio::Model::WaterUseEquipment] the WaterUseEquipment for the
  def model_add_swh_end_uses_by_space(model,
                                      swh_loop,
                                      space,
                                      is_flow_per_area: true)
    # SpaceType
    if space.spaceType.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Space #{space.name} does not have a Space Type assigned, cannot add SWH end uses.")
      return nil
    end
    space_type = space.spaceType.get

    # Standards Building Type
    if space_type.standardsBuildingType.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Space #{space.name}'s Space Type does not have a Standards Building Type assigned, cannot add SWH end uses.")
      return nil
    end
    stds_bldg_type = space_type.standardsBuildingType.get
    building_type = model_get_lookup_name(stds_bldg_type)

    # Standards Space Type
    if space_type.standardsSpaceType.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Space #{space.name}'s Space Type does not have a Standards Space Type assigned, cannot add SWH end uses.")
      return nil
    end
    stds_spc_type = space_type.standardsSpaceType.get

    # find the specific space_type properties from standard.json
    search_criteria = {
      'template' => template,
      'building_type' => building_type,
      'space_type' => stds_spc_type
    }
    data = standards_lookup_table_first(table_name: 'space_types', search_criteria: search_criteria)
    if data.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Could not find space type for: #{search_criteria}.")
      return nil
    end
    space_area = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get # ft2

    # If there is no service hot water load.. Don't bother adding anything.
    if data['service_water_heating_peak_flow_per_area'].to_f < 0.00001 && data['service_water_heating_peak_flow_rate'].to_f < 0.00001
      return nil
    end

    # rated flow rate
    rated_flow_rate_per_area = data['service_water_heating_peak_flow_per_area'].to_f # gal/h.ft2
    rated_flow_rate_gal_per_hour = if is_flow_per_area
                                     rated_flow_rate_per_area * space_area * space.multiplier # gal/h
                                   else
                                     data['service_water_heating_peak_flow_rate'].to_f
                                   end
    rated_flow_rate_gal_per_min = rated_flow_rate_gal_per_hour / 60 # gal/h to gal/min
    rated_flow_rate_m3_per_s = OpenStudio.convert(rated_flow_rate_gal_per_min, 'gal/min', 'm^3/s').get

    # target mixed water temperature
    mixed_water_temp_f = data['service_water_heating_target_temperature']
    mixed_water_temp_c = OpenStudio.convert(mixed_water_temp_f, 'F', 'C').get

    # flow rate fraction schedule
    flow_rate_fraction_schedule = model_add_schedule(model, data['service_water_heating_schedule'])

    # create water use
    water_fixture = OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                              name: "#{space.name}",
                                                                              flow_rate: rated_flow_rate_m3_per_s,
                                                                              flow_rate_fraction_schedule: flow_rate_fraction_schedule,
                                                                              water_use_temperature: mixed_water_temp_c,
                                                                              service_water_loop: swh_loop)

    return water_fixture
  end
end
