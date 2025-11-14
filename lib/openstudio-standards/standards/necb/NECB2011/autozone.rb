class NECB2011
  # Creates thermal zones to contain each space, as defined for each building in the
  # system_to_space_map inside the Prototype.building_name
  # e.g. (Prototype.secondary_school.rb) file.
  #
  # @param (see #add_constructions)
  # @return [Boolean] returns true if successful, false if not
  def model_create_thermal_zones(model, space_multiplier_map = nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started creating thermal zones')
    space_multiplier_map = {} if space_multiplier_map.nil?

    # Remove any Thermal zones assigned
    model.getThermalZones.each(&:remove)

    # Create a thermal zone for each space in the self
    model.getSpaces.sort.each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("#{space.name} ZN")
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      space.setThermalZone(zone)

      # Skip thermostat for spaces with no space type
      next if space.spaceType.empty?

      # Add a thermostat
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished creating thermal zones')
  end

  # Top level method that merges spaces into zones where possible. This requires a sizing run. This follows the spirit of
  # the EE4 modelling manual found here https://www.nrcan.gc.ca/energy/software-tools/7457 where the
  # A zone includes those areas in the building that meet three criteria:
  # * Served by the same HVAC system
  # * Similar operation and function
  # * Similar heating/cooling loads
  # Some expections are dwelling units wet zone and wild zones.  These spaces will have special considerations when autozoning a
  # building.

  def apply_auto_zoning(model:, sizing_run_dir: Dir.pwd, lights_type: 'NECB_Default', lights_scale: 1.0)
    raise('validation of model failed.') unless validate_initial_model(model)

    # Check to see if model is using another vintage of spacetypes. If so overwrite the @standards for the object with the
    # other spacetype data. This is required for correct system mapping.
    template = determine_spacetype_vintage(model)
    unless template == self.class.name
      # Frankenstein the standards data wrt spacetype data.
      @standards_data['space_types'] = Standard.build(template).standards_data['space_types']
    end

    # The first thing we need to do is get a sizing run to determine the heating loads of all the spaces. The default
    # btap geometry has a one to one relationship of zones to spaces.. So we simply create the thermal zones for all the spaces.
    # to do this we need to create thermals zone for each space.

    # Remove any Thermal zones assigned before
    model.getThermalZones.each(&:remove)
    # create new thermal zones one to one with spaces.
    model_create_thermal_zones(model, space_multiplier_map)
    # do a sizing run.
    try_sizing_run(model: model, sizing_run_dir: sizing_run_dir, sizing_run_subdir: 'autozone')

    # collect sizing information on each space.
    store_space_sizing_loads(model)
    # Remove any Thermal zones assigned again to start fresh.
    model.getThermalZones.each(&:remove)
    auto_zone_dwelling_units(model)
    auto_zone_wet_spaces(model: model, lights_type: lights_type, lights_scale: lights_scale)
    auto_zone_all_other_spaces(model)
    auto_zone_wild_spaces(model: model, lights_type: lights_type, lights_scale: lights_scale)
    # This will color the spaces and zones.
    random = Random.new(1234)
    # Set ideal hvac in case we want to not implement the hvac yet and still run osm right after this function.
    # model.getThermalZones.each { |zone| zone.setUseIdealAirLoads(true) }
    model.getThermalZones.sort.each { |item| item.setRenderingColor(set_random_rendering_color(item, random)) }
    model.getSpaceTypes.sort.each { |item| item.setRenderingColor(set_random_rendering_color(item, random)) }
  end

  # Organizes Zones and assigns them to appropriate systems according to NECB 2011-17 systems spacetype rules in Sec 8.
  # requires requires fuel type to be assigned for each system aspect. Defaults to gas hydronic.
  def apply_systems(model:,
                    hvac_system_primary:,
                    hvac_system_dwelling_units:,
                    hvac_system_washrooms:,
                    hvac_system_corridor:,
                    hvac_system_storage:,
                    sizing_run_dir:,
                    shw_scale:,
                    baseline_system_zones_map_option:)
    raise('validation of model failed.') unless validate_initial_model(model)
    # Store fuel type information in case hvac_system_primary requires a reset
    init_fuel_type = get_fuel_type_information()
    # Check to see if model is using another vintage of spacetypes. If so overwrite the @standards for the object with the
    # other spacetype data. This is required for correct system mapping.
    template = determine_spacetype_vintage(model)
    unless template == self.class.name
      # Frankenstein the standards data wrt spacetype data.
      @standards_data['space_types'] = Standard.build(template).standards_data['space_types']
    end

    # do a sizing run.
    try_sizing_run(model: model, sizing_run_dir: sizing_run_dir, sizing_run_subdir: 'autozone_systems')

    # collect sizing information on each space.
    store_space_sizing_loads(model)

    # remove idealair from zones if any.
    model.getZoneHVACIdealLoadsAirSystems.each(&:remove)
    @hw_loop = create_hw_loop_if_required(baseboard_type: self.fuel_type_set.baseboard_type,
                                          boiler_fueltype: self.fuel_type_set.boiler_fueltype,
                                          backup_boiler_fueltype: self.fuel_type_set.backup_boiler_fueltype,
                                          mau_heating_coil_type: self.fuel_type_set.mau_heating_coil_type,
                                          heating_coil_type_sys2: self.fuel_type_set.heating_coil_type_sys2,
                                          heating_coil_type_sys3: self.fuel_type_set.heating_coil_type_sys3,
                                          heating_coil_type_sys4: self.fuel_type_set.heating_coil_type_sys4,
                                          heating_coil_type_sys6: self.fuel_type_set.heating_coil_type_sys6,
                                          model: model,
                                          hvac_system_primary: hvac_system_primary,
                                          hvac_system_dwelling_units: hvac_system_dwelling_units,
                                          hvac_system_washrooms: hvac_system_washrooms,
                                          hvac_system_corridor: hvac_system_corridor,
                                          hvac_system_storage: hvac_system_storage
                                          )
    # Determine if dwelling units, wet spaces, storage spaces, and wild spaces should have their own space or be part of common spaces
    common_system_spaces = spaces_to_add_to_common_system(model: model, hvac_system_dwelling_units: hvac_system_dwelling_units, hvac_system_washrooms: hvac_system_washrooms, hvac_system_corridor: hvac_system_corridor, hvac_system_storage: hvac_system_storage)
    # Rule that all dwelling units have their own zone and system.
    auto_system_dwelling_units(model: model,
                               hvac_system_dwelling_units: hvac_system_dwelling_units,
                               necb_reference_hp: self.fuel_type_set.necb_reference_hp,
                               necb_reference_hp_supp_fuel: self.fuel_type_set.necb_reference_hp_supp_fuel,
                               baseboard_type: self.fuel_type_set.baseboard_type,
                               boiler_fueltype: self.fuel_type_set.boiler_fueltype,
                               chiller_type: self.fuel_type_set.chiller_type,
                               fan_type: self.fuel_type_set.fan_type,
                               heating_coil_type_sys3: self.fuel_type_set.heating_coil_type_sys3,
                               heating_coil_type_sys4: self.fuel_type_set.heating_coil_type_sys4,
                               hw_loop: @hw_loop,
                               heating_coil_type_sys6: self.fuel_type_set.heating_coil_type_sys6,
                               mau_cooling_type: self.fuel_type_set.mau_cooling_type,
                               mau_heating_coil_type: self.fuel_type_set.mau_heating_coil_type,
                               mau_type: self.fuel_type_set.mau_type,
                               baseline_system_zones_map_option: baseline_system_zones_map_option,
                               init_fuel_type: init_fuel_type)

    # Assign a single system 4 for all wet spaces.. and assign the control zone to the one with the largest load.
    auto_system_wet_spaces(hvac_system_washrooms: hvac_system_washrooms,
                           baseboard_type: self.fuel_type_set.baseboard_type,
                           necb_reference_hp: self.fuel_type_set.necb_reference_hp,
                           necb_reference_hp_supp_fuel: self.fuel_type_set.necb_reference_hp_supp_fuel,
                           boiler_fueltype: self.fuel_type_set.boiler_fueltype,
                           heating_coil_type_sys4: self.fuel_type_set.heating_coil_type_sys4,
                           model: model,
                           init_fuel_type: init_fuel_type)

    # Assign a single system 4 for all storage spaces.. and assign the control zone to the one with the largest load.
    auto_system_storage_spaces(hvac_system_storage: hvac_system_storage,
                               baseboard_type: self.fuel_type_set.baseboard_type,
                               necb_reference_hp: self.fuel_type_set.necb_reference_hp,
                               necb_reference_hp_supp_fuel: self.fuel_type_set.necb_reference_hp_supp_fuel,
                               boiler_fueltype: self.fuel_type_set.boiler_fueltype,
                               heating_coil_type_sys4: self.fuel_type_set.heating_coil_type_sys4,
                               model: model,
                               init_fuel_type: init_fuel_type)

    # Assign the wild spaces to a single system 4 system with a control zone with the largest load.
    auto_system_wild_spaces(hvac_system_corridor: hvac_system_corridor,
                            baseboard_type: self.fuel_type_set.baseboard_type,
                            necb_reference_hp: self.fuel_type_set.necb_reference_hp,
                            necb_reference_hp_supp_fuel: self.fuel_type_set.necb_reference_hp_supp_fuel,
                            heating_coil_type_sys4: self.fuel_type_set.heating_coil_type_sys4,
                            model: model,
                            init_fuel_type: init_fuel_type)
    # do the regular assignment for the rest and group where possible.
    auto_system_all_other_spaces(model: model,
                                 hvac_system_primary: hvac_system_primary,
                                 necb_reference_hp: self.fuel_type_set.necb_reference_hp,
                                 necb_reference_hp_supp_fuel: self.fuel_type_set.necb_reference_hp_supp_fuel,
                                 baseboard_type: self.fuel_type_set.baseboard_type,
                                 boiler_fueltype: self.fuel_type_set.boiler_fueltype,
                                 chiller_type: self.fuel_type_set.chiller_type,
                                 fan_type: self.fuel_type_set.fan_type,
                                 heating_coil_type_sys2: self.fuel_type_set.heating_coil_type_sys2,
                                 heating_coil_type_sys3: self.fuel_type_set.heating_coil_type_sys3,
                                 heating_coil_type_sys4: self.fuel_type_set.heating_coil_type_sys4,
                                 hw_loop: @hw_loop,
                                 heating_coil_type_sys6: self.fuel_type_set.heating_coil_type_sys6,
                                 mau_cooling_type: self.fuel_type_set.mau_cooling_type,
                                 mau_heating_coil_type: self.fuel_type_set.mau_heating_coil_type,
                                 mau_type: self.fuel_type_set.mau_type,
                                 common_system_spaces: common_system_spaces,
                                 init_fuel_type: init_fuel_type
    )
    model_add_swh(model: model,
                  shw_scale: shw_scale)
    model_apply_sizing_parameters(model)
    # set a larger tolerance for unmet hours from default 0.2 to 1.0C
    model.getOutputControlReportingTolerances.setToleranceforTimeHeatingSetpointNotMet(1.0)
    model.getOutputControlReportingTolerances.setToleranceforTimeCoolingSetpointNotMet(1.0)
  end

  # Method to store space sizing loads. This is needed because later when the zones are destroyed this information will be lost.
  def store_space_sizing_loads(model)
    @stored_space_heating_sizing_loads = {}
    @stored_space_cooling_sizing_loads = {}
    model.getSpaces.sort.each do |space|
      space_type = space.spaceType.get.standardsSpaceType.get

      # error if zone design load methods are not available
      if space.model.version < OpenStudio::VersionString.new('3.6.0')
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.autozone', "Required ThermalZone methods .autosizedHeatingDesignLoad and .autosizedCoolingDesignLoad are not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.")
      end

      @stored_space_heating_sizing_loads[space] = space_type == '- undefined -' ? 0.0 : space.thermalZone.get.autosizedHeatingDesignLoad.get / space.floorArea
      @stored_space_cooling_sizing_loads[space] = space_type == '- undefined -' ? 0.0 : space.thermalZone.get.autosizedCoolingDesignLoad.get / space.floorArea
    end
  end

  # Returns heating load per area for space after sizing run has been done.
  def stored_space_heating_load(space)
    if @stored_space_heating_sizing_loads.nil?
      # do a sizing run.
      try_sizing_run(model: space.model, sizing_run_dir: "#{Dir.pwd}", sizing_run_subdir: 'autozone')

      # collect sizing information on each space.
      store_space_sizing_loads(space.model)
    end
    @stored_space_heating_sizing_loads[space]
  end

  # Returns the cooling load per area for space after sizing runs has been done.
  def stored_space_cooling_load(space)
    if @stored_space_cooling_sizing_loads.nil?
      # do a sizing run.
      try_sizing_run(model: space.model, sizing_run_dir: "#{Dir.pwd}", sizing_run_subdir: 'autozone')

      # collect sizing information on each space.
      store_space_sizing_loads(space.model)
    end
    @stored_space_cooling_sizing_loads[space]
  end

  # # Returns the heating load per area for zone after sizing runs has been done.
  def stored_zone_heating_load(zone)
    total = 0.0
    zone.spaces.each do |space|
      total += stored_space_heating_load(space)
    end
    return total
  end

  # Returns the cooling load per area for zone after sizing runs has been done.
  def stored_zone_cooling_load(zone)
    total = 0.0
    zone.spaces.each do |space|
      total += stored_space_cooling_load(space)
    end
    return total
  end

  # Dwelling unit spaces need to have their own HVAC system. Thankfully NECB defines what spacetypes are considering
  # dwelling units and have been defined as spaces that are
  # openstudio-standards/standards/necb/NECB2011/data/necb_hvac_system_selection_type.json as spaces that are Residential/Accomodation and Sleeping area'
  # this is determine by the is_a_necb_dwelling_unit? method. The thermostat is set by the space-type schedule. This will return an array of TZ.
  def auto_zone_dwelling_units(model)
    dwelling_tz_array = []
    # ----Dwelling units----------- will always have their own system per unit, so they should have their own thermal zone.
    model.getSpaces.select { |space| is_a_necb_dwelling_unit?(space) }.each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("DU_BT=#{space.spaceType.get.standardsBuildingType.get}_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory.get.name}_SCH#{determine_dominant_schedule([space])}")
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      space.setThermalZone(zone)

      # Add a thermostat based on the space type.
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model).addToThermalZone(zone)
      end
      dwelling_tz_array << zone
    end
    return dwelling_tz_array
  end

  # Something that the code is silent on are smelly humid areas that should not be on the same system as the rest of the
  #  building.. These are the 'wet' spaces and have been defined as locker and washroom areas.. These will be put under
  # their own single system 4 system. These will be set to the dominant floor schedule.

  def auto_zone_wet_spaces(model:, lights_type: 'NECB_Default', lights_scale: 1.0)
    wet_zone_array = []
    model.getSpaces.select { |space| is_an_necb_wet_space?(space) }.each do |space|
      # if this space was already assigned to something skip it.
      next unless space.thermalZone.empty?

      # get space to dominant schedule
      dominant_schedule = determine_dominant_schedule(space.model.getSpaces)
      # create new TZ and set space to the zone.
      zone = OpenStudio::Model::ThermalZone.new(model)
      space.setThermalZone(zone)
      tz_name = "WET_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory.get.name}_SCH#{dominant_schedule}"
      zone.setName(tz_name)
      # Set multiplier from the original tz multiplier.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end

      # this method will determine if the right schedule was used for this wet & wild space if not.. it will reset the space
      # to use the correct schedule version of the wet and wild space type.
      adjust_wildcard_spacetype_schedule(space: space, schedule: dominant_schedule, lights_type: lights_type, lights_scale: lights_scale)

      # Find spacetype thermostat and assign it to the zone.
      thermostat_name = space.spaceType.get.name.get + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}-")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      wet_zone_array << zone
    end
    return wet_zone_array
  end

  # This method will find all the spaces that are not wet, wild or dwelling units and zone them. It will try to determine
  # if the spaces are similar based on exposure and load and blend those spaces into the same zone.  It will not merge spaces
  # from different floors, since this will impact Chris Kirneys costing algorithms.
  def auto_zone_all_other_spaces(model)
    other_tz_array = []
    # iterate through all non wildcard spaces.
    model.getSpaces.select { |space| !is_a_necb_dwelling_unit?(space) && !is_an_necb_wildcard_space?(space) }.each do |space|
      # skip if already assigned to a thermal zone.
      next unless space.thermalZone.empty?

      # create new zone for this space based on the space name.
      zone = OpenStudio::Model::ThermalZone.new(model)
      tz_name = "ALL_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory.get.name}_SCH=#{determine_dominant_schedule([space])}"
      zone.setName(tz_name)
      # sets space mulitplier unless it is nil or 1.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      # Assign space to the new zone.
      space.setThermalZone(zone)

      # Add a thermostat
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      other_tz_array << zone
    end
    return other_tz_array
  end

  # This will take all the wildcard spaces and merge them to be supported by a system 4. The control zone will be the
  # zone that has the largest heating load per area.
  def auto_zone_wild_spaces(model:, lights_type: 'NECB_Default', lights_scale: 1.0)
    other_tz_array = []
    # iterate through wildcard spaces.
    model.getSpaces.select { |space| is_an_necb_wildcard_space?(space) && !is_an_necb_wet_space?(space) }.each do |space|
      # skip if already assigned to a thermal zone.
      next unless space.thermalZone.empty?

      # create new zone for this space based on the space name.
      zone = OpenStudio::Model::ThermalZone.new(model)
      tz_name = "WILD_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory.get.name}_SCH=#{determine_dominant_schedule(space.model.getSpaces)}"
      zone.setName(tz_name)
      # sets space mulitplier unless it is nil or 1.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      # Assign space to the new zone.
      space.setThermalZone(zone)

      # lets keep the wild schedules to be the same as what dominate the floor.
      dominant_floor_schedule = determine_dominant_schedule(space.model.getSpaces)

      adjust_wildcard_spacetype_schedule(space: space,
                                         schedule: dominant_floor_schedule,
                                         lights_type: lights_type,
                                         lights_scale: lights_scale)

      # Add a thermostat
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      other_tz_array << zone
    end
    return other_tz_array

    wild_zone_array = []
    # Get a list of all the wild spaces.
    model.getSpaces.select { |space| is_an_necb_wildcard_space?(space) && !is_an_necb_wet_space?(space) }.each do |space|
      # if this space was already assigned to something skip it.
      next unless space.thermalZone.empty?

      # find adjacent spaces to the current space.
      adj_spaces = OpenstudioStandards::Geometry.space_get_adjacent_spaces_with_shared_wall_areas(space, true)
      adj_spaces = adj_spaces.map { |key, value| key }

      # find unassigned adjacent wild spaces that have not been assigned that have the same multiplier these will be
      # lumped together in the same zone.
      wild_adjacent_spaces = adj_spaces.select do |adj_space|
        is_an_necb_wildcard_space?(adj_space) &&
          !is_an_necb_wet_space?(adj_space) &&
          adj_space.thermalZone.empty? &&
          (space_multiplier_map[space.name.to_s] == space_multiplier_map[adj_space.name.to_s])
      end
      # put them all together.
      wild_adjacent_spaces << space

      # Get adjacent candidate foster zones. Must not be a wildcard space and must not be linked to another space incase
      # it is part of a mirrored space.
      other_adjacent_spaces = adj_spaces.select do |adj_space|
        (is_an_necb_wildcard_space?(adj_space) == false) &&
          (adj_space.thermalZone.get.spaces.size == 1) &&
          (space_multiplier_map[space.name.to_s] == space_multiplier_map[adj_space.name.to_s])
      end

      # If there are adjacent spaces that fit the above criteria.
      # We will need to set each space to the dominant floor schedule by setting the spaces spacetypes to that
      # schedule version and eventually set it to a system 4
      unless other_adjacent_spaces.empty?
        # assign the space(s) to the adjacent thermal zone.
        schedule_type = determine_dominant_schedule(space.buildingStory.get.spaces)
        zone = other_adjacent_spaces.first.thermalZone.get
        wild_adjacent_spaces.each do |curr_space|
          adjust_wildcard_spacetype_schedule(curr_space, schedule_type, @lights_type, @lights_scale, @space_height)
          curr_space.setThermalZone(zone)
        end
      end

      # create new TZ and set space to the zone.
      zone = OpenStudio::Model::ThermalZone.new(model)
      space.setThermalZone(zone)
      zone.setName("Wild-ZN:BT=#{space.spaceType.get.standardsBuildingType.get}:ST=#{space.spaceType.get.standardsSpaceType.get}:FL=#{space.buildingStory.get.name}:")
      # Set multiplier from the original tz multiplier.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end

      # Set space to dominant

      dominant_floor_schedule = determine_dominant_schedule(space.buildingStory.get.spaces)
      # this method will determine if the right schedule was used for this wet & wild space if not.. it will reset the space
      # to use the correct schedule version of the wet and wild space type.
      adjust_wildcard_spacetype_schedule(space: space, schedule: dominant_floor_schedule, lights_type: @lights_type, lights_scale: @lights_scale)
      # Find spacetype thermostat and assign it to the zone.
      thermostat_name = space.spaceType.get.name.get + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      wild_zone_array << zone
    end
    return wild_zone_array
  end

  # This method will determine if the loads on a zone are similar. (Exposure, space type, space loads, and schedules, etc)
  def are_zone_loads_similar?(zone_1:, zone_2:)
    # make sure they have the same number of spaces.
    truthes = []
    return false if zone_1.spaces.size != zone_2.spaces.size

    zone_1.spaces.each do |space_1|
      zone_2.spaces.each do |space_2|
        if are_space_loads_similar?(space_1: space_1, space_2: space_2)
          truthes << true
        end
      end
    end
    # truthes sizes should be the same as the # of spaces if all spaces are similar.
    return truthes.size == zone_1.spaces.size
  end

  # This method will determine if the loads on a space are similar. (Exposure, space type, space loads, and schedules, etc)
  def are_space_loads_similar?(space_1:,
                               space_2:,
                               surface_percent_difference_tolerance: 0.01,
                               angular_percent_difference_tolerance: 0.001,
                               heating_load_percent_difference_tolerance: 15.0)
    # Do they have the same space type?
    return false unless space_1.multiplier == space_2.multiplier
    # Ensure that they both have defined spacetypes
    return false if space_1.spaceType.empty?
    return false if space_2.spaceType.empty?
    # ensure that they have the same spacetype.
    return false unless space_1.spaceType.get == space_2.spaceType.get

    # Perform surface comparision. If ranges are within percent_difference_tolerance.. they can be considered the same.
    space_1_floor_area = space_1.floorArea
    space_2_floor_area = space_2.floorArea
    space_1_surface_report = space_surface_report(space_1)
    space_2_surface_report = space_surface_report(space_2)
    # Spaces should have the same number of surface orientations.
    return false unless space_1_surface_report.size == space_2_surface_report.size
    # spaces should have similar loads
    return false unless percentage_difference(stored_space_heating_load(space_1), stored_space_heating_load(space_2)) <= heating_load_percent_difference_tolerance

    # Each surface should match
    space_1_surface_report.each do |space_1_surface|
      surface_match = space_2_surface_report.detect do |space_2_surface|
        space_1_surface[:surface_type] == space_2_surface[:surface_type] &&
          space_1_surface[:boundary_condition] == space_2_surface[:boundary_condition] &&
          percentage_difference(space_1_surface[:tilt], space_2_surface[:tilt]) <= angular_percent_difference_tolerance &&
          percentage_difference(space_1_surface[:azimuth], space_2_surface[:azimuth]) <= angular_percent_difference_tolerance &&
          percentage_difference(space_1_surface[:surface_area_to_floor_ratio],
                                space_2_surface[:surface_area_to_floor_ratio]) <= surface_percent_difference_tolerance &&
          percentage_difference(space_1_surface[:glazed_subsurface_area_to_floor_ratio],
                                space_2_surface[:glazed_subsurface_area_to_floor_ratio]) <= surface_percent_difference_tolerance &&
          percentage_difference(space_1_surface[:opaque_subsurface_area_to_floor_ratio],
                                space_2_surface[:opaque_subsurface_area_to_floor_ratio]) <= surface_percent_difference_tolerance
      end
      return false if surface_match.nil?
    end
    return true
  end

  # This method gathers the surface information for the space to determine if spaces are the same.
  def space_surface_report(space)
    surface_report = []
    space_floor_area = space.floorArea
    ['Outdoors', 'Ground'].each do |bc|
      surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(space.surfaces, [bc]).each do |surface|
        # sum wall area and subsurface area by direction. This is the old way so excluding top and bottom surfaces.
        # new way
        glazings = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(surface.subSurfaces, ['FixedWindow',
                                                                                              'OperableWindow',
                                                                                              'GlassDoor',
                                                                                              'Skylight',
                                                                                              'TubularDaylightDiffuser',
                                                                                              'TubularDaylightDome'])
        doors = BTAP::Geometry::Surfaces.filter_subsurfaces_by_types(surface.subSurfaces, ['Door',
                                                                                           'OverheadDoor'])
        azimuth = (surface.azimuth() * 180.0 / Math::PI)
        tilt = (surface.tilt() * 180.0 / Math::PI)
        surface_data = surface_report.detect do |curr_surface_data|
          curr_surface_data[:surface_type] == surface.surfaceType &&
            curr_surface_data[:azimuth] == azimuth &&
            curr_surface_data[:tilt] == tilt &&
            curr_surface_data[:boundary_condition] == bc
        end

        if surface_data.nil?
          surface_data = {
            surface_type: surface.surfaceType,
            azimuth: azimuth,
            tilt: tilt,
            boundary_condition: bc,
            surface_area: 0,
            surface_area_to_floor_ratio: 0,
            glazed_subsurface_area: 0,
            glazed_subsurface_area_to_floor_ratio: 0,
            opaque_subsurface_area: 0,
            opaque_subsurface_area_to_floor_ratio: 0
          }
          surface_report << surface_data
        end
        surface_data[:surface_area] += surface.grossArea.to_i
        surface_data[:surface_area_to_floor_ratio] += surface.grossArea / space.floorArea

        surface_data[:glazed_subsurface_area] += glazings.map { |subsurface| subsurface.grossArea * subsurface.multiplier }.inject(0) { |sum, x| sum + x }.to_i
        surface_data[:glazed_subsurface_area_to_floor_ratio] += glazings.map { |subsurface| subsurface.grossArea * subsurface.multiplier }.inject(0) { |sum, x| sum + x } / space.floorArea

        surface_data[:surface_area] += doors.map { |subsurface| subsurface.grossArea * subsurface.multiplier }.inject(0) { |sum, x| sum + x }.to_i
        surface_data[:surface_area_to_floor_ratio] += doors.map { |subsurface| subsurface.grossArea * subsurface.multiplier }.inject(0) { |sum, x| sum + x } / space.floorArea
      end
    end
    surface_report.sort! { |a, b| [a[:surface_type], a[:azimuth], a[:tilt], a[:boundary_condition]] <=> [b[:surface_type], b[:azimuth], b[:tilt], b[:boundary_condition]] }

    return surface_report
  end

  # Check to see if this is a wildcard space that the NECB does not have a specified schedule or system for.
  def is_an_necb_wildcard_space?(space)
    # Avoid including washrooms and locker rooms as both wildcard and wet spaces
    return nil if space.spaceType.get.standardsSpaceType.get.include?('Locker room') || space.spaceType.get.standardsSpaceType.get.include?('Washroom')
    space_type_table = @standards_data['space_types']
    space_type_data = model_find_object(space_type_table,
                                        'template' => self.class.name,
                                        'space_type' => space.spaceType.get.standardsSpaceType.get,
                                        'building_type' => space.spaceType.get.standardsBuildingType.get)
    raise(space.to_s) if space_type_data.nil?

    return space_type_data['necb_hvac_system_selection_type'] == 'Wildcard'
  end

  # Check to see if this is a wet space that the NECB does not have a specified schedule or system for. Currently hardcoded to
  # Locker room and washroom.
  def is_an_necb_wet_space?(space)
    # Hack! Should replace this with a proper table lookup.
    return space.spaceType.get.standardsSpaceType.get.include?('Locker room') || space.spaceType.get.standardsSpaceType.get.include?('Washroom')
  end

  # Check to see if this is a wet space that the NECB does not have a specified schedule or system for. Currently hardcoded to
  # Locker room and washroom.
  def is_an_necb_storage_space?(space)
    # Hack! Should replace this with a proper table lookup.
    return space.spaceType.get.standardsSpaceType.get.include?('Storage')
  end

  # Check if the space spactype is a dwelling unit as per NECB.
  def is_a_necb_dwelling_unit?(space)
    space_type_table = @standards_data['space_types']
    space_type_data = model_find_object(space_type_table,
                                        'template' => self.class.name,
                                        'space_type' => space.spaceType.get.standardsSpaceType.get,
                                        'building_type' => space.spaceType.get.standardsBuildingType.get)

    necb_hvac_system_selection_table = @standards_data['necb_hvac_system_selection_type']
    necb_hvac_system_select = necb_hvac_system_selection_table.detect do |curr_necb_hvac_system_select|
      curr_necb_hvac_system_select['necb_hvac_system_selection_type'] == space_type_data['necb_hvac_system_selection_type'] &&
        curr_necb_hvac_system_select['min_stories'] <= space.model.getBuilding.standardsNumberOfAboveGroundStories.get &&
        curr_necb_hvac_system_select['max_stories'] >= space.model.getBuilding.standardsNumberOfAboveGroundStories.get
    end
    return necb_hvac_system_select['dwelling'] == true
  end

  # Determines what system index number is required for the space's spacetype by NECB rules.
  def get_necb_spacetype_system_selection(space)
    space_type_table = @standards_data['space_types']
    space_type_data = model_find_object(space_type_table, 'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                          'building_type' => space.spaceType.get.standardsBuildingType.get)
    if space_type_data.nil?
      raise("Could not find space_type_data for #{{ 'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                    'building_type' => space.spaceType.get.standardsBuildingType.get }} ")
    end

    # identify space-system_index and assign the right NECB system type 1-7.
    necb_hvac_system_selection_table = @standards_data['necb_hvac_system_selection_type']
    necb_hvac_system_select = necb_hvac_system_selection_table.detect do |curr_necb_hvac_system_select|
      curr_necb_hvac_system_select['necb_hvac_system_selection_type'] == space_type_data['necb_hvac_system_selection_type'] &&
        curr_necb_hvac_system_select['min_stories'] <= space.model.getBuilding.standardsNumberOfAboveGroundStories.get &&
        curr_necb_hvac_system_select['max_stories'] >= space.model.getBuilding.standardsNumberOfAboveGroundStories.get &&
        curr_necb_hvac_system_select['min_cooling_capacity_kw'] <= stored_space_cooling_load(space) &&
        curr_necb_hvac_system_select['max_cooling_capacity_kw'] >= stored_space_cooling_load(space)
    end
    raise('could not find system for given spacetype') if necb_hvac_system_select.nil?

    return necb_hvac_system_select['system_type']
  end

  # Determines what system index number is required for the thermal zone based on the spacetypes it contains
  def get_necb_thermal_zone_system_selection(tz)
    systems = []
    tz.spaces.each do |space|
      systems << get_necb_spacetype_system_selection(space)
    end
    systems.uniq!
    systems.compact!
    raise('This thermal zone spaces require different systems.') if systems.size > 1

    return systems.first
  end

  # Math fundtion to determine percent difference.
  def percentage_difference(value_1, value_2)
    return 0.0 if value_1 == value_2

    return ((value_1 - value_2).abs / ((value_1 + value_2) / 2) * 100)
  end

  # Set wildcard spactype schedule to NECB letter index.
  def adjust_wildcard_spacetype_schedule(space:, schedule:, lights_type: 'NECB_Default', lights_scale: 1.0)
    if space.spaceType.empty?
      OpenStudio.logFree(OpenStudio::Error, "Error: No spacetype assigned for #{space.name.get}. This must be assigned. Aborting.")
    end
    # Get current spacetype name
    space_type_name = space.spaceType.get.standardsSpaceType.get.to_s
    # Determine new spacetype name.
    regex = /^(.*sch-)(\S)$/
    new_spacetype_name = "#{space_type_name.match(regex).captures.first}#{schedule}"
    new_spacetype = nil

    # if the new spacetype does not match the old space type. we gotta update the space with the new spacetype.
    if space_type_name != new_spacetype_name
      new_spacetype = space.model.getSpaceTypes.detect do |spacetype|
        !spacetype.standardsBuildingType.empty? && # need to do this to prevent an exception.
          (spacetype.standardsBuildingType.get == space.spaceType.get.standardsBuildingType.get) &&
          !spacetype.standardsSpaceType.empty? && # need to do this to prevent an exception.
          (spacetype.standardsSpaceType.get == new_spacetype_name)
      end
      if new_spacetype.nil?
        # Space type is not in model. need to create from scratch.
        new_spacetype = OpenStudio::Model::SpaceType.new(space.model)
        new_spacetype.setStandardsBuildingType(space.spaceType.get.standardsBuildingType.get)
        new_spacetype.setStandardsSpaceType(new_spacetype_name)
        new_spacetype.setName("#{space.spaceType.get.standardsBuildingType.get} #{new_spacetype_name}")
        space_type_apply_internal_loads(space_type: new_spacetype, lights_type: lights_type, lights_scale: lights_scale)
        space_type_apply_internal_load_schedules(new_spacetype)
        space_type_apply_thermostat_schedules(new_spacetype)
      end
      space.setSpaceType(new_spacetype)
      # sanity check.
      raise 'could not reassign space type schedule.' if schedule != space.spaceType.get.name.get.match(regex)[2]
    end
    return space
  end

  def set_wildcard_schedules_to_dominant_building_schedule(model, runner = nil)
    # Get rid of.
  end

  def determine_dominant_schedule(spaces)
    # lookup necb space type properties
    space_type_properties = @standards_data['space_types']
    # Here is a hash to keep track of the m2 running total of spacetypes for each
    # sched type.
    # 2018-04-11:  Not sure if this is still used but the list was expanded to incorporate additional existing or potential
    # future schedules.
    schedule_hash = Hash[
        'A', 0,
        'B', 0,
        'C', 0,
        'D', 0,
        'E', 0,
        'F', 0,
        'G', 0,
        'H', 0,
        'I', 0,
        'J', 0,
        'K', 0,
        'L', 0,
        'M', 0,
        'N', 0,
        'O', 0,
        'P', 0,
        'Q', 0
    ]
    # iterate through spaces in building.
    spaces.select { |space| !is_an_necb_wildcard_space?(space) && (space.spaceType.get.standardsSpaceType.get != '- undefined -') }.each do |space|
      # Ensure space floors are multiplied.
      mult = @space_multiplier_map[space.name.to_s].nil? ? 1.0 : @space_multiplier_map[space.name.to_s]
      # puts "this #{determine_necb_schedule_type(space)}"
      schedule_hash[determine_necb_schedule_type(space)] += space.floorArea * mult
    end
    # finds max value and returns NECB schedule letter.
    # determine dominant letter schedule.
    return schedule_hash.max_by(&:last).first
  end

  # This model determines the dominant NECB schedule type
  # @param model [OpenStudio::Model::Model] A model object
  # return s.each [String]
  def determine_dominant_necb_schedule_type(model)
    return determine_dominant_schedule(model.getSpaces)
  end

  # This method determines the spacetype schedule type. This will re
  # @author phylroy.lopez@nrcan.gc.ca
  # @param space [String]
  # @return [String]:["A","B","C","D","E","F","G","H","I"] spacetype
  def determine_necb_schedule_type(space)
    spacetype_data = @standards_data['space_types']
    raise "Spacetype not defined for space #{space.get.name}) if space.spaceType.empty?" if space.spaceType.empty?
    raise "Undefined standardsSpaceType or StandardsBuildingType for space #{space.spaceType.get.name}) if space.spaceType.empty?" if space.spaceType.get.standardsSpaceType.empty? | space.spaceType.get.standardsBuildingType.empty?

    space_type_properties = spacetype_data.detect { |st| (st['space_type'] == space.spaceType.get.standardsSpaceType.get) && (st['building_type'] == space.spaceType.get.standardsBuildingType.get) }
    return space_type_properties['necb_schedule_type'].strip
  end

  ################################################# NECB Systems

  # Method will create a hot water loop if systems default fuel and medium sources require it.
  def create_hw_loop_if_required(baseboard_type:, boiler_fueltype:, backup_boiler_fueltype:, mau_heating_coil_type:, model:, hvac_system_primary: nil, hvac_system_dwelling_units: nil, hvac_system_washrooms: nil, hvac_system_corridor: nil, hvac_system_storage: nil, heating_coil_type_sys2:, heating_coil_type_sys3:, heating_coil_type_sys4:, heating_coil_type_sys6:)
    # get systems that will be used in the model based on the space types to determine if a hw_loop is required.

    hw_loop_needed = false

    # Create a boiler if the air loop will use fancoils for heating
    hw_loop_needed = true if self.fuel_type_set.force_airloop_hot_water

    # Create a boiler if one is forced by the user
    hw_loop_needed = true if self.fuel_type_set.force_boiler

    # Find Dwelling Units and determine if a HW loop is needed
    dwelling_units = model.getSpaces.select { |space| is_a_necb_dwelling_unit?(space) }
    unless dwelling_units.empty?
      # If no dwelling unit hvac system is defined then check if a HW loop is needed based on the system type.
      if hvac_system_dwelling_units.nil? || hvac_system_dwelling_units.to_s.downcase == 'necb_default'
        hw_loop_needed = hw_loop_required_from_spaces(spaces: dwelling_units, mau_heating_coil_type: mau_heating_coil_type, baseboard_type: baseboard_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      else
        # If a dwelling unit hvac system is defined then find it in the hvac_types array and check if it requires a HW loop based on the 'needs_boiler' item.
        hvac_system_data = self.standards_data['hvac_types'].find { |system| system['description'] == hvac_system_dwelling_units }
        hw_loop_needed = true if hvac_system_data["needs_boiler"].to_bool unless hw_loop_needed
        hw_loop_needed = boiler_required_from_heating_coils(sys_type: hvac_system_data["system"].to_s, mau_heating_coil_type: mau_heating_coil_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      end
    end

    # Find washrooms and determine if a HW loop is needed
    washroom_spaces = model.getSpaces.select { |space| is_an_necb_wet_space?(space) }
    unless washroom_spaces.empty?
      # If no washroom hvac system is defined then check if a HW loop is needed based on the system type.
      if hvac_system_washrooms.nil? || hvac_system_washrooms.to_s.downcase == 'necb_default'
        hw_loop_needed = hw_loop_required_from_spaces(spaces: washroom_spaces, mau_heating_coil_type: mau_heating_coil_type, baseboard_type: baseboard_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      else
        # If a washroom hvac system is defined then find it in the hvac_types array and check if it requires a HW loop based on the 'needs_boiler' item.
        hvac_system_data = self.standards_data['hvac_types'].find { |system| system['description'] == hvac_system_washrooms }
        hw_loop_needed = true if hvac_system_data["needs_boiler"].to_bool unless hw_loop_needed
        hw_loop_needed = boiler_required_from_heating_coils(sys_type: hvac_system_data["system"].to_s, mau_heating_coil_type: mau_heating_coil_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      end
    end

    # Find corridors and determine if a HW loop is needed
    corridor_spaces = model.getSpaces.select { |space| is_an_necb_wildcard_space?(space) }
    unless corridor_spaces.empty?
      # If no corridor hvac system is defined then check if a HW loop is needed based on the system type.
      if hvac_system_corridor.nil? || hvac_system_corridor.to_s.downcase == 'necb_default'
        hw_loop_needed = hw_loop_required_from_spaces(spaces: corridor_spaces, mau_heating_coil_type: mau_heating_coil_type, baseboard_type: baseboard_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      else
        # If a corridor hvac system is defined then find it in the hvac_types array and check if it requires a HW loop based on the 'needs_boiler' item.
        hvac_system_data = self.standards_data['hvac_types'].find { |system| system['description'] == hvac_system_corridor }
        hw_loop_needed = true if hvac_system_data["needs_boiler"].to_bool unless hw_loop_needed
        hw_loop_needed = boiler_required_from_heating_coils(sys_type: hvac_system_data["system"].to_s, mau_heating_coil_type: mau_heating_coil_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      end
    end

    # Find storage spaces and determine if a HW loop is needed
    storage_spaces = model.getSpaces.select { |space| is_an_necb_storage_space?(space) }
    unless storage_spaces.empty?
      # If no storage space hvac system is defined then check if a HW loop is needed based on the system type.
      if hvac_system_storage.nil? || hvac_system_storage.to_s.downcase == 'necb_default'
        hw_loop_needed = hw_loop_required_from_spaces(spaces: storage_spaces, mau_heating_coil_type: mau_heating_coil_type, baseboard_type: baseboard_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      else
        # If a storage space hvac system is defined then find it in the hvac_types array and check if it requires a HW loop based on the 'needs_boiler' item.
        hvac_system_data = self.standards_data['hvac_types'].find { |system| system['description'] == hvac_system_storage }
        hw_loop_needed = true if hvac_system_data["needs_boiler"].to_bool unless hw_loop_needed
        hw_loop_needed = boiler_required_from_heating_coils(sys_type: hvac_system_data["system"].to_s, mau_heating_coil_type: mau_heating_coil_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      end
    end

    # Find if a HW loop is needed for the remaining spaces
    other_spaces = model.getSpaces.select do |space|
      !is_an_necb_wet_space?(space) &&
      !is_a_necb_dwelling_unit?(space) &&
      !is_an_necb_wildcard_space?(space) &&
      !is_an_necb_storage_space?(space)
    end
    unless other_spaces.empty?
      # If a hvac system is defined for the remaining spaces then check if a HW loop is needed based on the system type
      if hvac_system_primary.nil? || hvac_system_primary.to_s.downcase == 'necb_default'
        hw_loop_needed = hw_loop_required_from_spaces(spaces: other_spaces, mau_heating_coil_type: mau_heating_coil_type, baseboard_type: baseboard_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      else
        # If an hvac system is defined for the remaining spaces then find it in the hvac_types array and check if it requires a HW loop based on the 'needs_boiler' item.
        hvac_system_data = self.standards_data['hvac_types'].find { |system| system['description'] == hvac_system_primary }
        hw_loop_needed = true if hvac_system_data["needs_boiler"].to_bool unless hw_loop_needed
        hw_loop_needed = boiler_required_from_heating_coils(sys_type: hvac_system_data["system"].to_s, mau_heating_coil_type: mau_heating_coil_type, heating_coil_type_sys2: heating_coil_type_sys2, heating_coil_type_sys3: heating_coil_type_sys3, heating_coil_type_sys4: heating_coil_type_sys4, heating_coil_type_sys6: heating_coil_type_sys6) unless hw_loop_needed
      end
    end

    # create hw_loop as needed.. Assuming one loop per model.
    if hw_loop_needed
      @hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      setup_hw_loop_with_components(model, @hw_loop, boiler_fueltype, backup_boiler_fueltype, always_on)
    end
    return @hw_loop
  end

  # Default method to create a necb system and assign array of zones to be supported by it. It will try to bring zones with
  # similar loads on the same airloops and set control zones where possible for single zone systems and will create monolithic
  # system 6 multizones where possible.
  def create_necb_system(hvac_system_primary: 'NECB_Default',
                         baseboard_type:,
                         boiler_fueltype:,
                         chiller_type:,
                         fan_type:,
                         hw_loop:,
                         heating_coil_type_sys2:,
                         heating_coil_type_sys3:,
                         heating_coil_type_sys4:,
                         heating_coil_type_sys6:,
                         mau_cooling_type:,
                         mau_heating_coil_type:,
                         mau_type:,
                         model:,
                         zones:,
                         necb_reference_hp:false,
                         necb_reference_hp_supp_fuel:'DefaultFuel')
    # The goal is to minimize the number of system when possible.
    system_zones_hash = {}
    system_selection = nil
    zones.each do |zone|
      # Define the system type based on the space type data or use the custom one (hvac_system_primary) if is defined.
      if hvac_system_primary.nil? || hvac_system_primary.to_s.downcase == 'necb_default'
        system_selection = get_necb_thermal_zone_system_selection(zone)
      else
        zone_space_count = 0
        null_space_count = 0
        zone.spaces.sort.each do |space|
          zone_space_count += 1
          null_space_count += 1 if space.spaceType.get.name.to_s.downcase.include?("undefined")
        end
        system_data = @standards_data['hvac_types']
        selected_systems = system_data.select { |ind_system| ind_system["description"].to_s.downcase == hvac_system_primary.to_s.downcase }
        raise ("Could not find the provided HVAC system name in the HVAC system library. Please check the spelling of HVAC system name you defined. Provided HVAC system name: #{hvac_system_primary}") if selected_systems.empty?
        raise ("More than one HVAC systems match the provided HVAC system name.  Please check the spelling of the provided HVAC system name. Provided HVAC system name: #{hvac_system_primary}") if selected_systems.size > 1
        system_selection = selected_systems[0]["system"][4].to_i
        # Do not inculde zones exclusively containing undefined spaces
        system_selection = nil if null_space_count > 0 && zone_space_count == null_space_count
      end
      system_zones_hash[system_selection] = [] if system_zones_hash[system_selection].nil?
      system_zones_hash[system_selection] << zone
    end
    # puts JSON.pretty_generate(system_zones_hash)
    # go through each system and zones pairs to
    system_zones_hash.each_pair do |system, sys_zones|
      case system
      when 0, nil
        # Do nothing no system assigned to zone. Used for Unconditioned spaces
      when 1
        group_similar_zones_together(sys_zones).each do |curr_zones|
          if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
            mau_air_loop = add_sys1_unitary_ac_baseboard_heating(model: model,
                                                                necb_reference_hp: necb_reference_hp,
                                                                necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                zones: curr_zones,
                                                                mau_type: mau_type,
                                                                mau_heating_coil_type: mau_heating_coil_type,
                                                                baseboard_type: baseboard_type,
                                                                hw_loop: @hw_loop,
                                                                multispeed: false)
          else
            create_hvac_by_name( model: model,
                                 hvac_system_name: hvac_system_primary,
                                 hw_loop: @hw_loop,
                                 zones: curr_zones
            )
          end
        end

      when 2
        group_similar_zones_together(sys_zones).each do |curr_zones|
          if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
            add_sys2_FPFC_sys5_TPFC(model: model,
                                    zones: curr_zones,
                                    chiller_type: chiller_type,
                                    mau_cooling_type: mau_cooling_type,
                                    fan_coil_type: 'FPFC',
                                    hw_loop: @hw_loop)
          else
            create_hvac_by_name( model: model,
                                 hvac_system_name: hvac_system_primary,
                                 hw_loop: @hw_loop,
                                 zones: curr_zones
            )
          end
        end
      when 3
        group_similar_zones_together(sys_zones).each do |curr_zones|
          if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
            add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(model: model,
                                                                                  necb_reference_hp: necb_reference_hp,
                                                                                  necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                                  zones: curr_zones,
                                                                                  heating_coil_type: heating_coil_type_sys3,
                                                                                  baseboard_type: baseboard_type,
                                                                                  hw_loop: @hw_loop,
                                                                                  multispeed: false)
          else
            create_hvac_by_name( model: model,
                                 hvac_system_name: hvac_system_primary,
                                 hw_loop: @hw_loop,
                                 zones: curr_zones
            )
          end
        end

      when 4
        group_similar_zones_together(sys_zones).each do |curr_zones|
          if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
            add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model: model,
                                                                        necb_reference_hp: necb_reference_hp,
                                                                        necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                        zones: curr_zones,
                                                                        heating_coil_type: heating_coil_type_sys4,
                                                                        baseboard_type: baseboard_type,
                                                                        hw_loop: @hw_loop)
          else
            create_hvac_by_name( model: model,
                                 hvac_system_name: hvac_system_primary,
                                 hw_loop: @hw_loop,
                                 zones: curr_zones
            )
          end
        end

      when 5
        group_similar_zones_together(sys_zones).each do |curr_zones|
          if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
            add_sys2_FPFC_sys5_TPFC(model: model,
                                    zones: curr_zones,
                                    chiller_type: chiller_type,
                                    mau_cooling_type: mau_cooling_type,
                                    fan_coil_type: 'TPFC',
                                    hw_loop: @hw_loop)
          else
            create_hvac_by_name( model: model,
                                 hvac_system_name: hvac_system_primary,
                                 hw_loop: @hw_loop,
                                 zones: curr_zones
            )
          end
        end

      when 6
        if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
          if necb_reference_hp
            add_sys6_multi_zone_reference_hp_with_baseboard_heating(model: model,
                                                                    zones: sys_zones,
                                                                    heating_coil_type: heating_coil_type_sys6,
                                                                    baseboard_type: baseboard_type,
                                                                    hw_loop:@hw_loop,
                                                                    necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel)
          else
            add_sys6_multi_zone_built_up_system_with_baseboard_heating(model: model,
                                                                      zones: sys_zones,
                                                                      heating_coil_type: heating_coil_type_sys6,
                                                                      baseboard_type: baseboard_type,
                                                                      chiller_type: chiller_type,
                                                                      fan_type: fan_type,
                                                                      hw_loop: @hw_loop)
          end
        else
          create_hvac_by_name( model: model,
                               hvac_system_name: hvac_system_primary,
                               hw_loop: @hw_loop,
                               zones: sys_zones
          )
        end

      when 7
        group_similar_zones_together(sys_zones).each do |curr_zones|
          if hvac_system_primary == 'NECB_Default' or hvac_system_primary.nil?
            add_sys2_FPFC_sys5_TPFC(model: model,
                                    zones: curr_zones,
                                    chiller_type: chiller_type,
                                    fan_coil_type: 'FPFC',
                                    mau_cooling_type: mau_cooling_type,
                                    hw_loop: @hw_loop)
          else
            create_hvac_by_name( model: model,
                                 hvac_system_name: hvac_system_primary,
                                 hw_loop: @hw_loop,
                                 zones: curr_zones
            )
          end
        end
      end
    end
  end

  # This method will deal with all non wet, non-wild, and non-dwelling units thermal zones.
  def auto_system_all_other_spaces(baseboard_type:,
                                   hvac_system_primary:,
                                   necb_reference_hp: false,
                                   necb_reference_hp_supp_fuel: 'DefaultFuel',
                                   boiler_fueltype:,
                                   chiller_type:,
                                   fan_type:,
                                   heating_coil_type_sys2:,
                                   heating_coil_type_sys3:,
                                   heating_coil_type_sys4:,
                                   heating_coil_type_sys6:,
                                   hw_loop:,
                                   mau_cooling_type:,
                                   mau_heating_coil_type:,
                                   mau_type:,
                                   model:,
                                   common_system_spaces: [],
                                   init_fuel_type:)
    # Reset fuel type set to those defined by the user
    fuel_type_set.reset_default_fuel_info(init_fuel_type: init_fuel_type)
    # Set fuel type info based on hvac_system_primary (if set)
    unless hvac_system_primary.nil? || hvac_system_primary.to_s.downcase == 'necb_default'
      fuel_type_set.set_fuel_to_hvac_system_primary(hvac_system_primary: hvac_system_primary, standards_data: @standards_data)
      mau_type = fuel_type_set.mau_type unless fuel_type_set.mau_type.nil?
      mau_heating_coil_type = fuel_type_set.mau_heating_coil_type unless fuel_type_set.mau_heating_coil_type.nil? || fuel_type_set.force_airloop_hot_water
      necb_reference_hp = fuel_type_set.necb_reference_hp unless fuel_type_set.necb_reference_hp.nil?
      necb_reference_hp_supp_fuel = fuel_type_set.necb_reference_hp_supp_fuel unless fuel_type_set.necb_reference_hp_supp_fuel.nil? || fuel_type_set.force_airloop_hot_water
      heating_coil_type_sys4 = fuel_type_set.heating_coil_type_sys4 unless fuel_type_set.heating_coil_type_sys4.nil? || fuel_type_set.force_airloop_hot_water
    end
    zones = []
    other_spaces = model.getSpaces.select do |space|
      !is_an_necb_wet_space?(space) &&
      !is_a_necb_dwelling_unit?(space) &&
        !is_an_necb_wildcard_space?(space) &&
        !is_an_necb_storage_space?(space)
    end
    # Add any dwelling units, washrooms, cooridors, or storage spaces to the list of other spaces if a non-default system type was assigned to them
    unless common_system_spaces.empty? || common_system_spaces.nil?
      other_spaces = other_spaces + common_system_spaces
    end
    other_spaces.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!

    # since dwelling units are all zoned 1:1 to space:zone we simply add the zone to the appropriate btap system.
    create_necb_system(hvac_system_primary: hvac_system_primary,
                       baseboard_type: baseboard_type,
                       boiler_fueltype: boiler_fueltype,
                       chiller_type: chiller_type,
                       fan_type: fan_type,
                       heating_coil_type_sys2: heating_coil_type_sys2,
                       heating_coil_type_sys3: heating_coil_type_sys3,
                       heating_coil_type_sys4: heating_coil_type_sys4,
                       heating_coil_type_sys6: heating_coil_type_sys6,
                       hw_loop: @hw_loop,
                       mau_cooling_type: mau_cooling_type,
                       mau_heating_coil_type: mau_heating_coil_type,
                       mau_type: mau_type,
                       model: model,
                       zones: zones,
                       necb_reference_hp: necb_reference_hp,
                       necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel)
    # Reset fuel type set back to those defined by the user
    fuel_type_set.reset_default_fuel_info(init_fuel_type: init_fuel_type)
  end

  # This method will ensure that all dwelling units are assigned to a system 1 or 3.
  # There is an option to have a shared AHU or not.

  def auto_system_dwelling_units(
                                 hvac_system_dwelling_units:,
                                 baseboard_type:,
                                 necb_reference_hp:false,
                                 necb_reference_hp_supp_fuel:'DefaultFuel',
                                 boiler_fueltype:,
                                 chiller_type:,
                                 fan_type:,
                                 heating_coil_type_sys3:,
                                 heating_coil_type_sys4:,
                                 heating_coil_type_sys6:,
                                 hw_loop:,
                                 mau_cooling_type:,
                                 mau_heating_coil_type:,
                                 mau_type:,
                                 model:,
                                 baseline_system_zones_map_option:,
                                 init_fuel_type:)
    # Reset fuel type set to those defined by the user
    fuel_type_set.reset_default_fuel_info(init_fuel_type: init_fuel_type)
    system_zones_hash = {}
    # Determine if dwelling units have a shared AHU.  If user entered building stories > 4 then set to true.
    if baseline_system_zones_map_option == 'one_sys_per_dwelling_unit'
      dwelling_shared_ahu = false
    elsif baseline_system_zones_map_option == 'one_sys_per_bldg' || baseline_system_zones_map_option == 'NECB_Default' || baseline_system_zones_map_option == 'none' || baseline_system_zones_map_option == nil || necb_reference_hp
      dwelling_shared_ahu = true
    end
    # store dwelling zones into array
    zones = []
    model.getSpaces.select { |space| is_a_necb_dwelling_unit?(space) }.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!

    if hvac_system_dwelling_units.to_s.downcase == 'necb_default' || hvac_system_dwelling_units.nil?

      # sort system 1 or 3 used for each dwelling unit as per T8.4.4.8.A NECB 2011-17
      zones.each do |zone|
        system_zones_hash[get_necb_thermal_zone_system_selection(zone)] = [] if system_zones_hash[get_necb_thermal_zone_system_selection(zone)].nil?
        system_zones_hash[get_necb_thermal_zone_system_selection(zone)] << zone
      end # zone

      # go through each system and zones pairs to
      system_zones_hash.each_pair do |system, sys_zones|
        case system
        when 1
          if dwelling_shared_ahu
            add_sys1_unitary_ac_baseboard_heating(model: model,
                                                  necb_reference_hp: necb_reference_hp,
                                                  necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                  zones: sys_zones,
                                                  mau_type: mau_type,
                                                  mau_heating_coil_type: mau_heating_coil_type,
                                                  baseboard_type: baseboard_type,
                                                  hw_loop: @hw_loop,
                                                  multispeed: false)
          else
            # Create a separate air loop for each unit.
            sys_zones.each do |zone|
              add_sys1_unitary_ac_baseboard_heating(model: model,
                                                    necb_reference_hp: necb_reference_hp,
                                                    necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                    zones: [zone],
                                                    mau_type: mau_type,
                                                    mau_heating_coil_type: mau_heating_coil_type,
                                                    baseboard_type: baseboard_type,
                                                    hw_loop: @hw_loop,
                                                    multispeed: false)
            end # if
          end # when 1

        when 3
          if dwelling_shared_ahu
            add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(model: model,
                                                                                  necb_reference_hp: necb_reference_hp,
                                                                                  necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                                  zones: sys_zones,
                                                                                  heating_coil_type: heating_coil_type_sys3,
                                                                                  baseboard_type: baseboard_type,
                                                                                  hw_loop: @hw_loop,
                                                                                  multispeed: false)
          else

            # Create a separate air loop for each unit.
            sys_zones.each do |zone|
              add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(model: model,
                                                                                    necb_reference_hp: necb_reference_hp,
                                                                                    necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                                    zones: [zone],
                                                                                    heating_coil_type: heating_coil_type_sys3,
                                                                                    baseboard_type: baseboard_type,
                                                                                    hw_loop: @hw_loop,
                                                                                    multispeed: false)
            end # end zone
          end # end if
        end # end when 3
      end # Sys_zone loop
#    else # New HVAC system
#      system_zones_hash.each_pair do |system, sys_zones|
#        if dwelling_shared_ahu
#          create_hvac_by_name( model: model,
#                                      hvac_system_name: hvac_system_dwelling_units,
#                                      zones: sys_zones,
#                                      hw_loop: @hw_loop) # Add this method to create the system.
#        else
#          # Create a separate air loop for each unit.
#          sys_zones.each do |zone|
#            create_hvac_by_name( model: model,
#                                 hvac_system_name: hvac_system_dwelling_units,
#                                 zones: [zone],
#                                 hw_loop: @hw_loop) # Add this method to create the system.
#          end # zone
#        end # if
#      end # Sys_zone loop
    end # if new HVAC system
  end

  # All wet spaces will be on their own system 4 AHU.
  def auto_system_wet_spaces(hvac_system_washrooms: 'NECB_Default',
                             baseboard_type:,
                             necb_reference_hp:false,
                             necb_reference_hp_supp_fuel:'DefaultFuel',
                             boiler_fueltype:,
                             heating_coil_type_sys4:,
                             model:,
                             init_fuel_type:)
    # Reset fuel type set to those defined by the user
    fuel_type_set.reset_default_fuel_info(init_fuel_type: init_fuel_type)
    # Determine what zones are wet zones.
    wet_tz = []
    wet_spaces = model.getSpaces.select { |space| is_an_necb_wet_space?(space) }
    wet_spaces.each { |space| wet_tz << space.thermalZone.get }
    wet_tz.uniq!
    # create a system 4 for the wet zones.
    return if wet_tz.empty?
    if hvac_system_washrooms.to_s.downcase == 'necb_default' || hvac_system_washrooms.nil?
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model: model,
                                                                  necb_reference_hp: necb_reference_hp,
                                                                  necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                  zones: wet_tz,
                                                                  heating_coil_type: heating_coil_type_sys4,
                                                                  baseboard_type: baseboard_type,
                                                                  hw_loop: @hw_loop)
    #else
    #  create_hvac_by_name( model: model,
    #                              hvac_system_name: hvac_system_washrooms,
    #                              zones: wet_tz,
    #                              hw_loop: @hw_loop) # Add this method to create the system.
    end
  end

  # All wet spaces will be on their own system 4 AHU.
  def auto_system_storage_spaces(hvac_system_storage: 'NECB_Default',
                                 baseboard_type:,
                                 necb_reference_hp:false,
                                 necb_reference_hp_supp_fuel:'DefaultFuel',
                                 boiler_fueltype:,
                                 heating_coil_type_sys4:,
                                 model:,
                                 init_fuel_type:)
    # Reset fuel type set to those defined by the user
    fuel_type_set.reset_default_fuel_info(init_fuel_type: init_fuel_type)
    # Determine what zones are storage zones.
    tz = []
    storage_spaces = model.getSpaces.select { |space| is_an_necb_storage_space?(space) }
    storage_spaces.each { |space| tz << space.thermalZone.get }
    tz.uniq!

    return if tz.empty?
    if hvac_system_storage.to_s.downcase == 'necb_default' || hvac_system_storage.nil?
      # create a system 4 for the  zones.
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model: model,
                                                                  necb_reference_hp: necb_reference_hp,
                                                                  necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                  zones: tz,
                                                                  heating_coil_type: heating_coil_type_sys4,
                                                                  baseboard_type: baseboard_type,
                                                                  hw_loop: @hw_loop)
    #else
    #  create_hvac_by_name(model: model,
    #                      hvac_system_name: hvac_system_storage,
    #                      zones: tz,
    #                      hw_loop: @hw_loop) # Add this method to create the system.
    end

  end

  # All wild spaces will be on a single system 4 ahu with the largests heating load zone being the control zone.
  def auto_system_wild_spaces(hvac_system_corridor: 'NECB_Default',
                              baseboard_type:,
                              necb_reference_hp: false,
                              necb_reference_hp_supp_fuel: 'Defaultfuel',
                              heating_coil_type_sys4:,
                              model:,
                              init_fuel_type:)
    # Reset fuel type set to those defined by the user
    fuel_type_set.reset_default_fuel_info(init_fuel_type: init_fuel_type)

    zones = []
    wild_spaces = model.getSpaces.select { |space| !is_an_necb_wet_space?(space) && is_an_necb_wildcard_space?(space) }
    wild_spaces.each { |space| zones << space.thermalZone.get }
    zones.uniq!

    return if zones.empty?

    if hvac_system_corridor.to_s.downcase == 'necb_default' || hvac_system_corridor.nil?
      # create a system 4 for the wild zones.
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model: model,
                                                                  necb_reference_hp: necb_reference_hp,
                                                                  necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                  zones: zones,
                                                                  heating_coil_type: heating_coil_type_sys4,
                                                                  baseboard_type: baseboard_type,
                                                                  hw_loop: @hw_loop)
    #else
    #  create_hvac_by_name( model: model,
    #                              hvac_system_name: hvac_system_corridor,
    #                              zones: zones,
    #                              hw_loop: @hw_loop) # Add this method to create the system.
    end
  end

  # This method will determine the control zone from the last sizing run space loads.
  def determine_control_zone(zones)
    # In this case the control zone is the load with the largest heating loads. This may cause overheating of some zones.
    # but this is preferred to unmet heating.
    # Iterate through zones.
    zone_heating_load_hash = {}
    zones.each { |zone| zone_heating_load_hash[zone] = stored_zone_heating_load(zone) }
    return zone_heating_load_hash.max_by(&:last).first
  end

  # This method is used to determine if there are single zones that can be grouped with zones of similar loads.
  def group_similar_zones_together(zones)
    total_zones_input = zones.size
    array_of_array_of_zones = []
    accounted_for = []
    # Go through other zones to see if there are similar zones with similar loads on the same floor that can be grouped.
    zones.each do |zone|
      similar_array_of_zones = []
      next if accounted_for.include?(zone.name.to_s)

      similar_array_of_zones << zone
      accounted_for << zone.name.to_s
      zones.each do |zone_target|
        unless accounted_for.include?(zone_target.name.to_s)
          if are_zone_loads_similar?(zone_1: zone,
                                     zone_2: zone_target)
            similar_array_of_zones << zone_target
            accounted_for << zone_target.name.to_s
          end
        end
      end
      array_of_array_of_zones << similar_array_of_zones
    end
    total_zones_output = 0
    array_of_array_of_zones.each do |curr_zones|
      total_zones_output += curr_zones.size
    end
    # puts total_zones_output
    # puts accounted_for.sort
    # sanity check.
    if total_zones_output != total_zones_input
      # puts JSON.pretty_generate(array_of_array_of_zones)
      # puts JSON.pretty_generate(accounted_for.sort)
      raise('')
    end

    return array_of_array_of_zones
  end

  # This method will create a color object used in SU, 3D Viewer and Floorspace.js
  def set_random_rendering_color(object, random)
    rendering_color = OpenStudio::Model::RenderingColor.new(object.model)
    rendering_color.setName(object.name.get)
    rendering_color.setRenderingRedValue(random.rand(255))
    rendering_color.setRenderingGreenValue(random.rand(255))
    rendering_color.setRenderingBlueValue(random.rand(255))
    return rendering_color
  end

  def create_hvac_by_name(model:, hvac_system_name:, zones:, hw_loop: nil)
    # Get the HVAC system properties
    # Get the HVAC system properties from  lib/openstudio-standards/standards/necb/NECB2011/data/systems.json from description field.
    hvac_system_data = self.standards_data['hvac_types'].find { |system| system['description'] == hvac_system_name }
    raise("Could not find hvac_system_data for #{hvac_system_name}") if hvac_system_data.nil?
    necb_reference_hp_supp_fuel = hvac_system_data['necb_reference_hp_supp_fuel']
    necb_reference_hp_supp_fuel = 'Hot Water' if self.fuel_type_set.force_airloop_hot_water
    mau_heating_coil_type = hvac_system_data['mau_heating_type']
    baseboard_type = hvac_system_data['baseboard_type']
    baseboard_type = self.fuel_type_set.baseboard_type if self.fuel_type_set.force_boiler
    heating_coil_type = hvac_system_data['heating_coil_type']

    case hvac_system_data['system']
    when 'sys_1'
      mau_heating_coil_type = self.fuel_type_set.mau_heating_coil_type if self.fuel_type_set.force_airloop_hot_water && mau_heating_coil_type != 'DX'
      add_sys1_unitary_ac_baseboard_heating_single_speed(
            model: model,
            necb_reference_hp: hvac_system_data['necb_reference_hp'],
            necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
            zones: zones,
            mau_type: hvac_system_data['mau_type'],
            mau_heating_coil_type: mau_heating_coil_type,
            baseboard_type: baseboard_type,
            hw_loop: hw_loop
            )
    when 'sys_2'
      add_sys2_FPFC_sys5_TPFC( model: model,
                                            zones:zones,
                                            chiller_type: hvac_system_data['chiller_type'],
                                            fan_coil_type: hvac_system_data['fan_coil_type'],
                                            mau_cooling_type: hvac_system_data['mau_cooling_type'],
                                            hw_loop: hw_loop)
    when 'sys_3'
      heating_coil_type = self.fuel_type_set.heating_coil_type_sys3 if self.fuel_type_set.force_airloop_hot_water && heating_coil_type != 'DX'
      add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
              model: model,
              necb_reference_hp: hvac_system_data['necb_reference_hp'],
              necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
              zones: zones,
              heating_coil_type: heating_coil_type,
              baseboard_type: baseboard_type,
              hw_loop: hw_loop,
              new_auto_zoner: true)
    when 'sys_4'
      heating_coil_type = self.fuel_type_set.heating_coil_type_sys4 if self.fuel_type_set.force_airloop_hot_water && heating_coil_type != 'DX'
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model: model,
                                                                   necb_reference_hp: hvac_system_data['necb_reference_hp'],
                                                                   necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                                   zones: zones,
                                                                   heating_coil_type: heating_coil_type,
                                                                   baseboard_type: baseboard_type,
                                                                   hw_loop: hw_loop)
    when 'sys_5'
      add_sys2_FPFC_sys5_TPFC( model: model,
                                                zones:zones,
                                                chiller_type: hvac_system_data['chiller_type'],
                                                fan_coil_type: hvac_system_data['fan_coil_type'],
                                                mau_cooling_type: hvac_system_data['mau_cooling_type'],
                                                hw_loop: hw_loop)
    when 'sys_6'
      heating_coil_type = self.fuel_type_set.heating_coil_type_sys6 if self.fuel_type_set.force_airloop_hot_water && heating_coil_type != 'DX'
      if heating_coil_type == 'DX'
        add_sys6_multi_zone_reference_hp_with_baseboard_heating(model: model,
                                                              zones: zones,
                                                              heating_coil_type: heating_coil_type,
                                                              baseboard_type: baseboard_type,
                                                              hw_loop: hw_loop,
                                                              necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel)
      else
        add_sys6_multi_zone_built_up_system_with_baseboard_heating(
          model:model,
          zones:zones,
          heating_coil_type: heating_coil_type,
          baseboard_type: baseboard_type,
          chiller_type: hvac_system_data['chiller_type'],
          fan_type: hvac_system_data['fan_type'],
          hw_loop: hw_loop
          )
      end
    end

  end

  # Method will check if the spaces passed to it will require a hot water loop based on their associated system type.
  def hw_loop_required_from_spaces(spaces:, mau_heating_coil_type:, baseboard_type:, heating_coil_type_sys2:, heating_coil_type_sys3:, heating_coil_type_sys4:, heating_coil_type_sys6:)
    hw_loop_needed = false
    systems_used = []

    # Find the space type for each space and get the system type associated with each space type
    spaces.sort.each do |space|
      space_system = get_necb_spacetype_system_selection(space)
      space_system = 4 if space_system.nil? && (is_an_necb_storage_space?(space) || is_an_necb_wet_space?(space) || is_an_necb_wildcard_space?(space))
      systems_used << space_system
      systems_used.uniq!
    end

    # See if we need to create a hot water loop based on fueltype and systems used.
    systems_used.each do |system|
      case system.to_s
      when '2', '5', '7'
        hw_loop_needed = true
      when '1', '6'
        if (mau_heating_coil_type == 'Hot Water') || (baseboard_type == 'Hot Water') || (mau_heating_coil_type == 'HotWater') || baseboard_type == 'HotWater' || (heating_coil_type_sys6 == 'HotWater') || (heating_coil_type_sys6 == 'Hot Water')
          hw_loop_needed = true
        end
      when '3', '4'
        if (mau_heating_coil_type == 'Hot Water') || (baseboard_type == 'Hot Water') || (mau_heating_coil_type == 'HotWater') || baseboard_type == 'HotWater' || (heating_coil_type_sys4 == 'HotWater') || (heating_coil_type_sys4 == 'Hot Water') || (heating_coil_type_sys3 == 'HotWater') || (heating_coil_type_sys3 == 'Hot Water')
          hw_loop_needed = true if baseboard_type == 'Hot Water'
          hw_loop_needed = true if (mau_heating_coil_type == 'Hot Water') || (mau_heating_coil_type == 'HotWater') || (heating_coil_type_sys4 == 'HotWater') || (heating_coil_type_sys4 == 'Hot Water') || (heating_coil_type_sys3 == 'HotWater') || (heating_coil_type_sys3 == 'Hot Water')
        end
      end
      if hw_loop_needed
        # just need one true condition to need a boiler.
        break
      end
      # each
    end
    return hw_loop_needed
  end

  # Method to determine if dwelling_units, washrooms, corridors, or storage spaces should be added to the common HVAC system.
  def spaces_to_add_to_common_system(model:, hvac_system_dwelling_units: nil, hvac_system_washrooms: nil, hvac_system_corridor: nil, hvac_system_storage: nil)
    common_spaces = []
    # Find Dwelling Units and determine if they should be added
    dwelling_units = model.getSpaces.select { |space| is_a_necb_dwelling_unit?(space) }
    unless dwelling_units.empty? || hvac_system_dwelling_units.nil? || hvac_system_dwelling_units.to_s.downcase == 'necb_default'
      # If a dwelling unit hvac system is defined and dwelling units are present then add them to them to the common_spaces
      common_spaces = common_spaces + dwelling_units
    end

    # Find washrooms and determine if they should be added
    washroom_spaces = model.getSpaces.select { |space| is_an_necb_wet_space?(space) }
    unless washroom_spaces.empty? || hvac_system_washrooms.nil? || hvac_system_washrooms.to_s.downcase == 'necb_default'
      # If a washroom hvac system is defined and washrooms/wet spaces are present then add them to the common_spaces
      common_spaces = common_spaces + washroom_spaces
    end

    # Find corridors and determine if they should be added
    corridor_spaces = model.getSpaces.select { |space| is_an_necb_wildcard_space?(space) }
    unless corridor_spaces.empty? || hvac_system_corridor.nil? || hvac_system_corridor.to_s.downcase == 'necb_default'
      # If a corridor hvac system is defined and corridors are present then add them to the common spaces
      common_spaces = common_spaces + corridor_spaces
    end

    # Find storage spaces and determine if they should be added
    storage_spaces = model.getSpaces.select { |space| is_an_necb_storage_space?(space) }
    unless storage_spaces.empty? || hvac_system_storage.nil? || hvac_system_storage.to_s.downcase == 'necb_default'
      # If a storage space hvac system is defined and storage spaces are present then add them to the common spaces
      common_spaces = common_spaces + storage_spaces
    end
    return common_spaces
  end

  def get_fuel_type_information()
    init_fuel_type = {
      name: fuel_type_set.name,
      boiler_fueltype: fuel_type_set.boiler_fueltype,
      backup_boiler_fueltype: fuel_type_set.backup_boiler_fueltype,
      primary_boiler_cap_frac: fuel_type_set.primary_boiler_cap_frac,
      secondary_boiler_cap_frac: fuel_type_set.secondary_boiler_cap_frac,
      baseboard_type: fuel_type_set.baseboard_type,
      mau_type: fuel_type_set.mau_type,
      mau_heating_coil_type: fuel_type_set.mau_heating_coil_type,
      mau_cooling_type: fuel_type_set.mau_cooling_type,
      chiller_type: fuel_type_set.chiller_type,
      heating_coil_type_sys2: fuel_type_set.heating_coil_type_sys2,
      heating_coil_type_sys3: fuel_type_set.heating_coil_type_sys3,
      heating_coil_type_sys4: fuel_type_set.heating_coil_type_sys4,
      heating_coil_type_sys6: fuel_type_set.heating_coil_type_sys6,
      necb_reference_hp: fuel_type_set.necb_reference_hp,
      necb_reference_hp_supp_fuel: fuel_type_set.necb_reference_hp_supp_fuel,
      fan_type: fuel_type_set.fan_type,
      ecm_fueltype: fuel_type_set.ecm_fueltype,
      swh_fueltype: fuel_type_set.swh_fueltype,
      force_boiler: fuel_type_set.force_boiler,
      force_airloop_hot_water: fuel_type_set.force_airloop_hot_water
    }
    return init_fuel_type
  end

  def boiler_required_from_heating_coils(sys_type:, mau_heating_coil_type:, heating_coil_type_sys2:, heating_coil_type_sys3:, heating_coil_type_sys4:, heating_coil_type_sys6:)
    requires_boiler = false
    case sys_type.to_s
    when 'sys_1'
      requires_boiler = true if mau_heating_coil_type.to_s == "Hot Water" || mau_heating_coil_type.to_s == "HotWater"
    when 'sys_2'
      requires_boiler = true if heating_coil_type_sys2.to_s == "Hot Water" || heating_coil_type_sys2.to_s == "HotWater"
    when 'sys_3'
      requires_boiler = true if heating_coil_type_sys3.to_s == "Hot Water" || heating_coil_type_sys3.to_s == "HotWater"
    when 'sys_4'
      requires_boiler = true if heating_coil_type_sys4.to_s == "Hot Water" || heating_coil_type_sys4.to_s == "HotWater"
    when 'sys_6'
      requires_boiler = true if heating_coil_type_sys6.to_s == "Hot Water" || heating_coil_type_sys6.to_s == "HotWater"
    else
      requires_boiler = false
    end
    return requires_boiler
  end

end
