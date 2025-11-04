Standard.class_eval do
  # @!group Model

  # creates an openstudio standards version of PNNL/DOE prototype buildings
  #
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param epw_file []
  # @param sizing_run_dir [String]
  # @param debug
  # @param measure_model
  # @return
  def model_create_prototype_model(climate_zone, epw_file, sizing_run_dir = Dir.pwd, debug = false, measure_model = nil)
    building_type = @instvarbuilding_type
    raise 'no building_type!' if @instvarbuilding_type.nil?

    model = nil
    # There are no reference models for HighriseApartment and data centers at vintages Pre-1980 and 1980-2004,
    # nor for NECB2011. This is a quick check.
    case @instvarbuilding_type
    when 'HighriseApartment', 'SmallDataCenterLowITE', 'SmallDataCenterHighITE', 'LargeDataCenterLowITE', 'LargeDataCenterHighITE', 'Laboratory', 'TallBuilding', 'SuperTallBuilding'
      if template == 'DOE Ref Pre-1980' || template == 'DOE Ref 1980-2004'
        OpenStudio.logFree(OpenStudio::Error, 'Not available', "DOE Reference models for #{@instvarbuilding_type} at   are not available, the measure is disabled for this specific type.")
        return false
      end
    end
    # optionally  determine the climate zone from the epw and stat files.
    if climate_zone == 'NECB HDD Method'
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
      stat_file_path = weather_file_path.gsub('.epw', '.stat')
      stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
      climate_zone = OpenstudioStandards::Weather.get_climate_zone_from_degree_days(stat_file.hdd18, stat_file.cdd10)
    else
      # this is required to be blank otherwise it may cause side effects.
      epw_file = ''
    end
    model = load_geometry_osm(@geometry_file)
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)
    model_custom_geometry_tweaks(model, building_type, climate_zone, @prototype_input)
    model.getThermostatSetpointDualSetpoints(&:remove)

    # set building name and standards building type
    model.getBuilding.setName(self.class.to_s)
    unless model.getBuilding.standardsBuildingType.is_initialized
      model.getBuilding.setStandardsBuildingType(@instvarbuilding_type)
    end

    # save new basefile to new geometry folder as class name.
    model.getBuilding.setName("-#{@instvarbuilding_type}-#{climate_zone} created: #{Time.new}")
    model_add_loads(model)
    OpenstudioStandards::Infiltration.model_set_nist_infiltration(model)
    model_add_door_infiltration(model, climate_zone)
    model_modify_surface_convection_algorithm(model)
    model_create_thermal_zones(model, @space_multiplier_map)
    model_add_hvac(model, @instvarbuilding_type, climate_zone, @prototype_input)
    model.getAirLoopHVACs.each do |air_loop|
      next unless air_loop_hvac_multizone_vav_system?(air_loop)

      model_system_outdoor_air_sizing_vrp_method(air_loop)
      air_loop_hvac_apply_vav_damper_action(air_loop)
    end
    model_add_constructions(model, @instvarbuilding_type, climate_zone)
    model_fenestration_orientation(model, climate_zone)
    model_custom_hvac_tweaks(model, @instvarbuilding_type, climate_zone, @prototype_input)
    model_add_transfer_air(model)
    model_add_internal_mass(model, @instvarbuilding_type)
    model_add_swh(model, @instvarbuilding_type, @prototype_input)
    model_add_exterior_lights(model, @instvarbuilding_type, climate_zone, @prototype_input)
    model_add_occupancy_sensors(model, @instvarbuilding_type, climate_zone)
    model_add_daylight_savings(model)
    model_apply_sizing_parameters(model, @instvarbuilding_type)
    model.yearDescription.get.setDayofWeekforStartDay('Sunday')
    model.getBuilding.setStandardsBuildingType(@instvarbuilding_type)
    model_add_lights_shutoff(model)
    # Perform a sizing model_run(model)
    return false if model_run_sizing_run(model, "#{sizing_run_dir}/SR1") == false

    # If there are any multizone systems, reset damper positions
    # to achieve a 60% ventilation effectiveness minimum for the system
    # following the ventilation rate procedure from 62.1
    model_apply_multizone_vav_outdoor_air_sizing(model)
    # Apply the prototype HVAC assumptions
    # which include sizing the fan pressure rises based
    # on the flow rate of the system.
    model_apply_prototype_hvac_assumptions(model, @instvarbuilding_type, climate_zone)
    # custom economizer controls
    # For 90.1-2010 Outpatient, AHU1 doesn't have economizer and AHU2 set minimum outdoor air flow rate as 0
    model_modify_oa_controller(model)
    # For operating room 1&2 in 2010, 2013, 2016, and 2019, VAV minimum air flow is set by schedule
    model_reset_or_room_vav_minimum_damper(@prototype_input, model)
    # Apply the HVAC efficiency standard
    model_apply_hvac_efficiency_standard(model, climate_zone)
    # Apply prototype changes that supersede the HVAC efficiency standard
    model_apply_prototype_hvac_efficiency_adjustments(model)
    model_custom_swh_tweaks(model, @instvarbuilding_type, climate_zone, @prototype_input)
    # adjust infiltration schedules to match HVAC operating schedule
    OpenstudioStandards::Infiltration.model_set_nist_infiltration_schedules(model)
    # Fix EMS references.
    # Temporary workaround for OS issue #2598
    model_temp_fix_ems_references(model)
    # Add daylighting controls per standard
    # only four zones in large hotel have daylighting controls
    # @todo YXC to merge to the main function
    model_add_daylighting_controls(model)
    model_custom_daylighting_tweaks(model, @instvarbuilding_type, climate_zone, @prototype_input)
    model_update_exhaust_fan_efficiency(model)
    model_update_fan_efficiency(model)
    # rename air loop and plant loop nodes for readability
    OpenstudioStandards::HVAC.rename_air_loop_nodes(model)
    OpenstudioStandards::HVAC.rename_plant_loop_nodes(model)
    # remove unused objects
    model_remove_unused_resource_objects(model)
    # Add output variables for debugging
    model_request_timeseries_outputs(model) if debug
    # If measure model is passed, then replace measure model with new model created here.
    return model if measure_model.nil?

    model_replace_model(measure_model, model)
    return measure_model
  end

  # Loads a JSON file containing the space type map into a hash
  #
  # @param hvac_map_file [String] path to JSON file, relative to the /data folder
  # @return [Hash] returns a hash that contains the space type map
  def load_hvac_map(hvac_map_file)
    # Load the geometry .osm from relative to the data folder
    rel_path_to_hvac_map = "../../../../../data/#{hvac_map_file}"

    # Load the JSON depending on whether running from normal gem location
    # or from the embedded location in the OpenStudio CLI
    if File.dirname(__FILE__)[0] == ':'
      # running from embedded location in OpenStudio CLI
      hvac_map_string = load_resource_relative(rel_path_to_hvac_map)
      hvac_map = JSON.parse(hvac_map_string)
    else
      abs_path = File.join(File.dirname(__FILE__), rel_path_to_hvac_map)
      hvac_map = JSON.parse(File.read(abs_path)) if File.exist?(abs_path)
    end

    return hvac_map
  end

  # Replaces the contents of 'model_to_replace' with the contents of 'new_model.'
  # This method can be used when the memory location of model_to_replace needs
  # to be preserved, for example, when a measure is passed.
  #
  # @param model_to_replace [OpenStudio::Model::Model] OpenStudio model object
  # @param new_model [OpenStudio::Model::Model] OpenStudio model object
  # @return [OpenStudio::Model::Model] OpenStudio model object
  def model_replace_model(model_to_replace, new_model, runner = nil)
    # remove existing objects from model
    handles = OpenStudio::UUIDVector.new
    model_to_replace.objects.each do |obj|
      handles << obj.handle
    end
    model_to_replace.removeObjects(handles)

    # put contents of new_model into model_to_replace
    model_to_replace.addObjects(new_model.toIdfFile.objects)
    BTAP.runner_register('Info', "Model name is now #{model_to_replace.building.get.name}.", runner)
    return model_to_replace
  end

  # Replaces all objects in the current model
  # with the objects in the .osm.  Typically used to
  # load a model as a starting point.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param rel_path_to_osm [String] the path to an .osm file, relative to this file
  # @return [Boolean] returns true if successful, false if not
  def model_replace_model_from_osm(model, rel_path_to_osm)
    # Take the existing model and remove all the objects
    # (this is cheesy), but need to keep the same memory block
    handles = OpenStudio::UUIDVector.new
    model.objects.each { |objects| handles << objects.handle }
    model.removeObjects(handles)
    model = nil
    if File.dirname(__FILE__)[0] == ':'
      # running from embedded location

      # Load geometry from the saved geometry.osm
      geom_model_string = load_resource_relative(rel_path_to_osm)
      puts geom_model_string
      # version translate from string
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      geom_model = version_translator.loadModelFromString(geom_model_string)

    else
      abs_path = File.join(File.dirname(__FILE__), rel_path_to_osm)

      # version translate from string
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      geom_model = version_translator.loadModel(abs_path)
      raise
    end

    if geom_model.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Version translation failed for #{rel_path_to_osm}")
      return false
    end
    geom_model = geom_model.get

    # Add the objects from the geometry model to the working model
    model.addObjects(geom_model.toIdfFile.objects)
    return true
  end


  # load a model into OS & version translates, exiting and erroring if a problem is found
  #
  # @param model_path_string [String] file path to OpenStudio model file
  # @return [OpenStudio::Model::Model] OpenStudio model object
  def safe_load_model(model_path_string)
    model_path = OpenStudio::Path.new(model_path_string)
    if OpenStudio.exists(model_path)
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      model = version_translator.loadModel(model_path)
      if model.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Version translation failed for #{model_path_string}")
        return false
      else
        model = model.get
      end
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "#{model_path_string} couldn't be found")
      return false
    end
    return model
  end

  # Remove all resource objects in the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [OpenStudio::Model::Model] OpenStudio model object
  def strip_model(model)
    # remove all materials
    model.getMaterials.each(&:remove)

    # remove all constructions
    model.getConstructions.each(&:remove)

    # remove performance curves
    model.getCurves.each do |curve|
      model.removeObject(curve.handle)
    end

    # remove all zone equipment
    model.getThermalZones.sort.each do |zone|
      zone.equipment.each(&:remove)
    end

    # remove all thermostats
    model.getThermostatSetpointDualSetpoints.each(&:remove)

    # remove all people
    model.getPeoples.each(&:remove)
    model.getPeopleDefinitions.each(&:remove)

    # remove all lights
    model.getLightss.each(&:remove)
    model.getLightsDefinitions.each(&:remove)

    # remove all electric equipment
    model.getElectricEquipments.each(&:remove)
    model.getElectricEquipmentDefinitions.each(&:remove)

    # remove all gas equipment
    model.getGasEquipments.each(&:remove)
    model.getGasEquipmentDefinitions.each(&:remove)

    # remove all outdoor air
    model.getDesignSpecificationOutdoorAirs.each(&:remove)

    # remove all infiltration
    model.getSpaceInfiltrationDesignFlowRates.each(&:remove)

    # Remove all internal mass
    model.getInternalMasss.each(&:remove)

    # Remove all internal mass defs
    model.getInternalMassDefinitions.each(&:remove)

    # Remove all thermal zones
    model.getThermalZones.each(&:remove)

    # Remove all schedules
    model.getSchedules.each(&:remove)

    # Remove all schedule type limits
    model.getScheduleTypeLimitss.each(&:remove)

    # Remove the sizing parameters
    model.getSizingParameters.remove

    # Remove the design days
    model.getDesignDays.each(&:remove)

    # Remove the rendering colors
    model.getRenderingColors.each(&:remove)

    # Remove the daylight controls
    model.getDaylightingControls.each(&:remove)

    return model
  end

  # Read the space type to space map from the model
  # instead of relying on an externally-defined mapping.
  def get_space_type_maps_from_model(model)
    # Do all spaces have Spacetypes?
    # @todo is this necessary?
    # all_spaces_have_space_types = true
    # Do all spacetypes have StandardSpaceTypes
    all_space_types_have_standard_space_types = true
    space_type_map = {}
    model.getSpaces.each do |space|
      if space.spaceType.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Space #{space.name} does not have a Space Type assigned.")
      else
        if space.spaceType.get.standardsSpaceType.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "SpaceType #{space.spaceType.get.name} does not have a standardsSpaceType assigned.")
          all_space_types_have_standard_space_types = false
        else
          space_type_map[space.spaceType.get.standardsSpaceType.get.to_s] = [] if space_type_map[space.spaceType.get.standardsSpaceType.get.to_s].nil?
          space_type_map[space.spaceType.get.standardsSpaceType.get.to_s] << space.name.get
        end
      end
    end
    if all_space_types_have_standard_space_types
      return space_type_map
    end

    return nil
  end

  def model_add_full_space_type_libs(model)
    space_type_properties_list = standards_lookup_table_many(table_name: 'space_types')
    space_type_properties_list.each do |space_type_property|
      stub_space_type = OpenStudio::Model::SpaceType.new(model)
      stub_space_type.setStandardsBuildingType(space_type_property['building_type'])
      stub_space_type.setStandardsSpaceType(space_type_property['space_type'])
      stub_space_type.setName("-#{space_type_property['building_type']}-#{space_type_property['space_type']}")
      space_type_apply_rendering_color(stub_space_type)
    end
    model_add_loads(model)
  end

  # Adds the loads and associated schedules for each space type
  # as defined in the OpenStudio_Standards_space_types.json file.
  # This includes lights, plug loads, occupants, ventilation rate requirements,
  # gas equipment (for kitchens, etc.) and typical schedules for each.
  # Some loads are governed by the standard, others are typical values
  # pulled from sources such as the DOE Reference and DOE Prototype Buildings.
  #
  # @return [Boolean] returns true if successful, false if not
  def model_add_loads(model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying space types (loads)')

    # Loop through all the space types currently in the model,
    # which are placeholders, and give them appropriate loads and schedules
    model.getSpaceTypes.sort.each do |space_type|
      # Rendering color
      space_type_apply_rendering_color(space_type)

      # Loads
      space_type_apply_internal_loads(space_type)

      # Schedules
      space_type_apply_internal_load_schedules(space_type)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying space types (loads)')

    return true
  end

  # Adds code-minimum constructions based on the building type
  # as defined in the OpenStudio_Standards_construction_sets.json file.
  # Where there is a separate construction set specified for the
  # individual space type, this construction set will be created and applied
  # to this space type, overriding the whole-building construction set.
  #
  # @param model[OpenStudio::Model::Model] OpenStudio Model
  # @param building_type [String] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if successful, false if not
  def model_add_constructions(model, building_type, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying constructions')
    is_residential = 'No' # default is nonresidential for building level

    # The constructions lookup table uses a slightly different list of building types.
    @lookup_building_type = model_get_lookup_name(building_type)
    # @todo this is a workaround.  Need to synchronize the building type names
    #   across different parts of the code, including splitting of Office types
    case building_type
      when 'SmallOffice', 'MediumOffice', 'LargeOffice', 'SmallOfficeDetailed', 'MediumOfficeDetailed', 'LargeOfficeDetailed'
        new_lookup_building_type = building_type
      else
        new_lookup_building_type = model_get_lookup_name(building_type)
    end

    # Construct adiabatic constructions
    floor_adiabatic_construction = OpenstudioStandards::Constructions.model_get_adiabatic_floor_construction(model)
    wall_adiabatic_construction = OpenstudioStandards::Constructions.model_get_adiabatic_wall_construction(model)

    cp02_carpet_pad = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
    cp02_carpet_pad.setName('CP02 CARPET PAD')
    cp02_carpet_pad.setRoughness('VeryRough')
    cp02_carpet_pad.setThermalResistance(0.21648)
    cp02_carpet_pad.setThermalAbsorptance(0.9)
    cp02_carpet_pad.setSolarAbsorptance(0.7)
    cp02_carpet_pad.setVisibleAbsorptance(0.8)

    m10_200mm_concrete_block_basement_wall = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    m10_200mm_concrete_block_basement_wall.setName('M10 200mm concrete block basement wall')
    m10_200mm_concrete_block_basement_wall.setRoughness('MediumRough')
    m10_200mm_concrete_block_basement_wall.setThickness(0.2032)
    m10_200mm_concrete_block_basement_wall.setThermalConductivity(1.326)
    m10_200mm_concrete_block_basement_wall.setDensity(1842)
    m10_200mm_concrete_block_basement_wall.setSpecificHeat(912)

    basement_wall_construction = OpenStudio::Model::Construction.new(model)
    basement_wall_construction.setName('Basement Wall construction')
    basement_wall_layers = OpenStudio::Model::MaterialVector.new
    basement_wall_layers << m10_200mm_concrete_block_basement_wall
    basement_wall_construction.setLayers(basement_wall_layers)

    basement_floor_construction = OpenStudio::Model::Construction.new(model)
    basement_floor_construction.setName('Basement Floor construction')
    basement_floor_layers = OpenStudio::Model::MaterialVector.new
    basement_floor_layers << m10_200mm_concrete_block_basement_wall
    basement_floor_layers << cp02_carpet_pad
    basement_floor_construction.setLayers(basement_floor_layers)

    # Constructs all relevant ground FC factor method constructions
    model_set_below_grade_wall_constructions(model, @lookup_building_type, climate_zone)
    model_set_floor_constructions(model, @lookup_building_type, climate_zone)

    # Set all remaining wall and floor constructions
    model.getSurfaces.sort.each do |surface|
      if surface.outsideBoundaryCondition.to_s == 'Adiabatic'
        if surface.surfaceType.to_s == 'Wall'
          surface.setConstruction(wall_adiabatic_construction)
        else
          surface.setConstruction(floor_adiabatic_construction)
        end
      elsif surface.outsideBoundaryCondition.to_s == 'OtherSideCoefficients'
        # Ground
        if surface.surfaceType.to_s == 'Wall'
          surface.setOutsideBoundaryCondition('Ground')
          surface.setConstruction(basement_wall_construction)
        else
          surface.setOutsideBoundaryCondition('Ground')
          surface.setConstruction(basement_floor_construction)
        end
      end
    end

    # Make the default construction set for the building
    spc_type = nil
    spc_type = 'WholeBuilding' if template == 'NECB2011'
    bldg_def_const_set = model_add_construction_set(model, climate_zone, new_lookup_building_type, spc_type, is_residential)

    if bldg_def_const_set.is_initialized
      model.getBuilding.setDefaultConstructionSet(bldg_def_const_set.get)
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Could not create default construction set for the building.')
      return false
    end

    # Make a construction set for each space type, if one is specified
    model.getSpaceTypes.sort.each do |space_type|
      # Get the standards building type
      stds_building_type = nil
      if space_type.standardsBuildingType.is_initialized
        stds_building_type = space_type.standardsBuildingType.get
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Space type called '#{space_type.name}' has no standards building type.")
      end

      # Get the standards space type
      stds_spc_type = nil
      if space_type.standardsSpaceType.is_initialized
        stds_spc_type = space_type.standardsSpaceType.get
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Space type called '#{space_type.name}' has no standards space type.")
      end

      # If the standards space type is Attic the building type should be blank.
      if stds_spc_type == 'Attic'
        stds_building_type = ''
      end

      # Attempt to make a construction set for this space type and assign it if it can be created.
      spc_type_const_set = model_add_construction_set(model, climate_zone, stds_building_type, stds_spc_type, is_residential)
      if spc_type_const_set.is_initialized
        space_type.setDefaultConstructionSet(spc_type_const_set.get)
      end
    end

    # Add construction from story level, especially for the case when there are residential and nonresidential construction in the same building
    if new_lookup_building_type == 'SmallHotel' && template != 'NECB2011'
      model.getBuildingStorys.sort.each do |story|
        next if story.name.get == 'AtticStory'

        # puts "story = #{story.name}"
        is_residential = 'No' # default for building story level
        exterior_spaces_area = 0
        story_exterior_residential_area = 0

        # calculate the propotion of residential area in exterior spaces, see if this story is residential or not
        story.spaces.each do |space|
          next if space.exteriorWallArea.zero?

          space_type = space.spaceType.get
          if space_type.standardsSpaceType.is_initialized
            space_type_name = space_type.standardsSpaceType.get
          end
          data = standards_lookup_table_first(table_name: 'space_types', search_criteria: { 'template' => template,
                                                                                            'building_type' => new_lookup_building_type,
                                                                                            'space_type' => space_type_name })
          exterior_spaces_area += space.floorArea
          story_exterior_residential_area += space.floorArea if data['is_residential'] == 'Yes' # "Yes" is residential, "No" or nil is nonresidential
        end
        is_residential = 'Yes' if story_exterior_residential_area / exterior_spaces_area >= 0.5
        next if is_residential == 'No'

        # if the story is identified as residential, assign residential construction set to the spaces on this story.
        building_story_const_set = model_add_construction_set(model, climate_zone, new_lookup_building_type, nil, is_residential)
        if building_story_const_set.is_initialized
          story.spaces.each do |space|
            space.setDefaultConstructionSet(building_story_const_set.get)
          end
        end
      end
      # Standards: For whole buildings or floors where 50% or more of the spaces adjacent to exterior walls are used primarily for living and sleeping quarters
    end

    # loop through ceiling surfaces and assign the plenum acoustical tile construction if the adjacent surface is a plenum floor
    model.getSurfaces.each do |surface|
      next unless surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Surface' && surface.adjacentSurface.is_initialized

      adj_surface = surface.adjacentSurface.get
      adj_space = adj_surface.space.get
      if adj_space.spaceType.is_initialized && adj_space.spaceType.get.standardsSpaceType.is_initialized
        adj_std_space_type = adj_space.spaceType.get.standardsSpaceType.get
        if adj_std_space_type.downcase == 'plenum'
          plenum_construction = adj_surface.construction
          if plenum_construction.is_initialized
            plenum_construction = plenum_construction.get
            surface.setConstruction(plenum_construction)
          end
        end
      end
    end

    # Make skylights have the same construction as fixed windows
    # sub_surface = self.getBuilding.defaultConstructionSet.get.defaultExteriorSubSurfaceConstructions.get
    # window_construction = sub_surface.fixedWindowConstruction.get
    # sub_surface.setSkylightConstruction(window_construction)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying constructions')

    return true
  end

  # Creates and sets below grade wall constructions for 90.1 prototype building models. These utilize
  # CFactorUndergroundWallConstruction and require some additional parameters when compared to Construction
  #
  # @param model[OpenStudio::Model::Model] OpenStudio Model
  # @param climate_zone [String] climate zone as described for prototype models. C-Factor is based on this parameter
  # @param building_type [String] the building type
  # @return [Boolean] returns true if successful, false if not
  def model_set_below_grade_wall_constructions(model, building_type, climate_zone)
    # Find ground contact wall building category
    construction_set_data = model_get_construction_set(building_type)

    # If no construction data, return and allow code to use default constructions
    return false if construction_set_data.nil?

    # Find wall C factor
    building_type_category = construction_set_data['exterior_wall_building_category']
    wall_construction_properties = model_get_construction_properties(model, 'GroundContactWall', 'Mass', building_type_category, climate_zone)

    # If no construction properties are found at all, return and allow code to use default constructions
    return false if wall_construction_properties.nil?

    c_factor_ip = wall_construction_properties['assembly_maximum_c_factor']

    # If no c-factor is found in construction properties, return and allow code to use defaults
    return false if c_factor_ip.nil?

    # convert to SI
    c_factor_si = c_factor_ip * OpenStudio.convert(1.0, 'Btu/ft^2*h*R', 'W/m^2*K').get

    # iterate through spaces and set any necessary CFactorUndergroundWallConstructions
    model.getSpaces.each do |space|
      # Get height of the first below grade wall in this space. Will return nil if none are found.
      below_grade_wall_height = OpenstudioStandards::Geometry.space_get_below_grade_wall_height(space)
      next if below_grade_wall_height.nil?

      c_factor_wall_name = "Basement Wall C-Factor #{c_factor_si.round(2)} Height #{below_grade_wall_height.round(2)}"

      # Check if the wall construction has been constructed already. If so, look it up in the model
      if model.getCFactorUndergroundWallConstructionByName(c_factor_wall_name).is_initialized
        basement_wall_construction = model.getCFactorUndergroundWallConstructionByName(c_factor_wall_name).get
      else
        # Create CFactorUndergroundWallConstruction objects
        basement_wall_construction = OpenStudio::Model::CFactorUndergroundWallConstruction.new(model)
        basement_wall_construction.setCFactor(c_factor_si)
        basement_wall_construction.setName(c_factor_wall_name)
        basement_wall_construction.setHeight(below_grade_wall_height)
      end

      # Set surface construction for walls adjacent to ground (i.e. basement walls)
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'OtherSideCoefficients'
          surface.setConstruction(basement_wall_construction)
          surface.setOutsideBoundaryCondition('GroundFCfactorMethod')
        end
      end
    end

    return true
  end

  # Searches a model for spaces adjacent to ground. If the slab's perimeter is adjacent to ground, the length is
  # calculated. Used for F-Factor floors that require additional parameters.
  #
  # @param model [OpenStudio Model] OpenStudio model being modified
  # @param building_type [String the building type
  # @param climate_zone [String climate zone as described for prototype models. F-Factor is based on this parameter
  # @return [Boolean] returns true if successful, false if not
  def model_set_floor_constructions(model, building_type, climate_zone)
    # Find ground contact wall building category
    construction_set_data = model_get_construction_set(building_type)

    # If no construction data, return and allow code to use default constructions
    return false if construction_set_data.nil?

    # Find floor F factor
    building_type_category = construction_set_data['ground_contact_floor_building_category']
    floor_construction_properties = model_get_construction_properties(model, 'GroundContactFloor', 'Unheated', building_type_category, climate_zone)

    # If no construction properties are found at all, return and allow code to use default constructions
    return false if floor_construction_properties.nil?

    f_factor_ip = floor_construction_properties['assembly_maximum_f_factor']

    # If no f-factor is found in construction properties, return and allow code to use defaults
    return false if f_factor_ip.nil?

    f_factor_si = f_factor_ip * OpenStudio.convert(1.0, 'Btu/ft*h*R', 'W/m*K').get

    # iterate through spaces and set FFactorGroundFloorConstruction to surfaces if applicable
    model.getSpaces.each do |space|
      # Find this space's exposed floor area and perimeter. NOTE: this assumes only only floor per space.
      perimeter = OpenstudioStandards::Geometry.space_get_f_floor_perimeter(space)
      area = OpenstudioStandards::Geometry.space_get_f_floor_area(space)
      next if area == 0 # skip floors not adjacent to ground

      # Record combination of perimeter and area. Each unique combination requires a FFactorGroundFloorConstruction.
      f_floor_const_name = "Foundation F #{f_factor_si.round(2)}W/m*K Perim #{perimeter.round(2)}m Area #{area.round(2)}m2"

      # Check if the floor construction has been constructed already. If so, look it up in the model
      if model.getFFactorGroundFloorConstructionByName(f_floor_const_name).is_initialized
        f_floor_construction = model.getFFactorGroundFloorConstructionByName(f_floor_const_name).get
      else
        f_floor_construction = OpenStudio::Model::FFactorGroundFloorConstruction.new(model)
        f_floor_construction.setName(f_floor_const_name)
        f_floor_construction.setFFactor(f_factor_si)
        f_floor_construction.setArea(area)
        f_floor_construction.setPerimeterExposed(perimeter)
      end

      # Set surface construction for floors adjacent to ground
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Ground'
          surface.setConstruction(f_floor_construction)
          surface.setOutsideBoundaryCondition('GroundFCfactorMethod')
        end
      end
    end

    return true
  end

  # Adds internal mass objects and constructions based on the building type
  #
  # @param model[OpenStudio::Model::Model] OpenStudio Model
  # @param building_type [String] the building type
  # @return [Boolean] returns true if successful, false if not
  def model_add_internal_mass(model, building_type)
    # Assign a material to all internal mass objects
    material = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    material.setName('Std Wood 6inch')
    material.setRoughness('MediumSmooth')
    material.setThickness(0.15)
    material.setThermalConductivity(0.12)
    material.setDensity(540)
    material.setSpecificHeat(1210)
    material.setThermalAbsorptance(0.9)
    material.setSolarAbsorptance(0.7)
    material.setVisibleAbsorptance(0.7)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setName('InteriorFurnishings')
    layers = OpenStudio::Model::MaterialVector.new
    layers << material
    construction.setLayers(layers)

    # Assign the internal mass construction to existing internal mass objects
    model.getSpaces.sort.each do |space|
      internal_masses = space.internalMass
      internal_masses.each do |internal_mass|
        internal_mass.internalMassDefinition.setConstruction(construction)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Set internal mass construction for internal mass '#{internal_mass.name}' in space '#{space.name}'.")
      end
    end

    # add internal mass
    # not required for NECB2011
    unless template == 'NECB2011' ||
           building_type.include?('DataCenter') ||
           ((building_type == 'SmallHotel') &&
            (template == '90.1-2004' || template == '90.1-2007' || template == '90.1-2010' || template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019' || template == 'NREL ZNE Ready 2017'))
      internal_mass_def = OpenStudio::Model::InternalMassDefinition.new(model)
      internal_mass_def.setSurfaceAreaperSpaceFloorArea(2.0)
      internal_mass_def.setConstruction(construction)
      model.getSpaces.each do |space|
        # only add internal mass objects to conditioned spaces
        next unless OpenstudioStandards::Space.space_cooled?(space)
        next unless OpenstudioStandards::Space.space_heated?(space)

        internal_mass = OpenStudio::Model::InternalMass.new(internal_mass_def)
        internal_mass.setName("#{space.name} Mass")
        internal_mass.setSpace(space)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Added internal mass '#{internal_mass.name}' to space '#{space.name}'.")
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding internal mass')

    return true
  end

  # Creates thermal zones to contain each space, as defined for each building in the
  # system_to_space_map inside the Prototype.building_name
  # e.g. (Prototype.secondary_school.rb) file.
  #
  # @param (see #add_constructions)
  # @return [Boolean] returns true if successful, false if not
  def model_create_thermal_zones(model, space_multiplier_map = nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started creating thermal zones')

    # Retrieve zone multipliers if non assigned via the space_multiplier_map
    if space_multiplier_map.nil?
      space_multiplier_map = {}
      model.getSpaces.each do |spc|
        space_multiplier_map.store(spc.name.to_s, spc.thermalZone.get.multiplier.to_int)
      end
    end

    # Remove any Thermal zones assigned
    model.getThermalZones.each(&:remove)

    # Create a thermal zone for each space in the self
    thermostat_to_offset = []
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
      thermostat_name = "#{space_type_name} Thermostat"
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        if template == 'NECB2011'
          # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
          ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
          ideal_loads.addToThermalZone(zone)
        end
      end

      # Modify thermostat schedules if space
      # has standby mode occupancy requirements
      if space_occupancy_standby_mode_required?(space)
        next if thermostat_to_offset.include?(thermostat_clone.name)

        space_occupancy_standby_mode(thermostat_clone)
        thermostat_to_offset << thermostat_name
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished creating thermal zones')
  end

  # Add exhaust fans and makeup air to the model
  #
  # @param makeup_source [String] Valid choices are 'None', 'Adjacent'
  #   'None' (default) does not add makeup air
  #   'Adjacent' makeup air provided from the thermal zone of the largest adjacent dining, cafe, or cafeteria space of the same building type
  # @param remove_existing_exhaust_fans [Boolean] remove existing exhaust fans
  # @return [Array<OpenStudio::Model::FanZoneExhaust>] Array of zone exhuast fans
  def model_add_exhaust(model,
                        makeup_source: 'None',
                        remove_existing_exhaust_fans: true)
    # remove existing exhaust fans
    if remove_existing_exhaust_fans
      model.getThermalZones.sort.each do |thermal_zone|
        thermal_zone.equipment.each { |equip| equip.remove if equip.to_FanZoneExhaust.is_initialized }
      end
    end

    # placeholder for zone exhaust fans
    zone_exhaust_fans = []

    # populate standard_space_types_with_makup_air
    standard_space_types_with_makup_air = {}
    standard_space_types_with_makup_air[['FullServiceRestaurant', 'Kitchen']] = ['FullServiceRestaurant', 'Dining']
    standard_space_types_with_makup_air[['QuickServiceRestaurant', 'Kitchen']] = ['QuickServiceRestaurant', 'Dining']
    standard_space_types_with_makup_air[['Hospital', 'Kitchen']] = ['Hospital', 'Dining']
    standard_space_types_with_makup_air[['SecondarySchool', 'Kitchen']] = ['SecondarySchool', 'Cafeteria']
    standard_space_types_with_makup_air[['PrimarySchool', 'Kitchen']] = ['PrimarySchool', 'Cafeteria']
    standard_space_types_with_makup_air[['LargeHotel', 'Kitchen']] = ['LargeHotel', 'Cafe']

    # apply make up air kitchen spaces
    if makeup_source == 'Adjacent'
      # loop through thermal zones and add exhaust
      model.getThermalZones.sort.each do |thermal_zone|
        has_exhaust_fan = false
        thermal_zone.equipment.each { |equip| has_exhaust_fan = true if equip.to_FanZoneExhaust.is_initialized }

        if has_exhaust_fan
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.Prototype.Model', "Thermal zone #{thermal_zone.name} already has an exhaust fan. None will be added.")
          next
        end

        # loop through space types and add exhaust fans to kitchen spaces
        thermal_zone.spaces.each do |space|
          next unless space.spaceType.is_initialized
          next unless space.partofTotalFloorArea

          space_type = space.spaceType.get
          next unless space_type.standardsBuildingType.is_initialized
          next unless space_type.standardsSpaceType.is_initialized

          standards_building_type = space_type.standardsBuildingType.get
          standards_space_type = space_type.standardsSpaceType.get

          # get makeup air source
          makeup_target_space_type = [standards_building_type, standards_space_type]
          makeup_source_space_type = standard_space_types_with_makup_air[makeup_target_space_type]

          # skip if nil
          next if makeup_source_space_type.nil?

          # get largest adjacent zone matching the makeup_source_space_type
          makeup_space = nil
          adjacent_zones = OpenstudioStandards::Geometry.thermal_zone_get_adjacent_zones_with_shared_walls(thermal_zone)
          adjacent_zones.each do |adjacent_zone|
            adjacent_zone.spaces.each do |adjacent_space|
              next unless adjacent_space.spaceType.is_initialized
              next unless adjacent_space.partofTotalFloorArea

              adjacent_space_type = adjacent_space.spaceType.get
              next unless adjacent_space_type.standardsBuildingType.is_initialized
              next unless adjacent_space_type.standardsSpaceType.is_initialized

              adjacent_standards_building_type = adjacent_space_type.standardsBuildingType.get
              adjacent_standards_space_type = adjacent_space_type.standardsSpaceType.get

              # filter out adjacent spaces not matching the makeup_source_space_type criteria
              next unless (makeup_source_space_type[0] == adjacent_standards_building_type) && (makeup_source_space_type[1] == adjacent_standards_space_type)

              # set makeup_space if not set or if adjacent space is larger
              if makeup_space.nil? || (adjacent_space.floorArea > makeup_space.floorArea)
                makeup_space = adjacent_space
              end
            end
          end

          if makeup_space.nil?
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.Prototype.Model', "Model has zone #{thermal_zone.name} with standards types #{makeup_target_space_type} but no adjacent zone with #{makeup_source_space_type}. Exhaust will be added, but no makeup air.")
            makeup_thermal_zone = nil
          else
            makeup_thermal_zone = makeup_space.thermalZone.get
          end

          zone_exhaust_fan = OpenstudioStandards::HVAC.create_exhaust_fan(thermal_zone, make_up_air_source_zone: makeup_thermal_zone)
          unless zone_exhaust_fan.nil?
            # set fan pressure rise
            fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)

            # update efficiency and pressure rise
            prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)

            zone_exhaust_fans << zone_exhaust_fan
          end
        end
      end
    end

    # loop through thermal zones and add exhaust fans
    model.getThermalZones.sort.each do |thermal_zone|
      has_exhaust_fan = false
      thermal_zone.equipment.each { |equip| has_exhaust_fan = true if equip.to_FanZoneExhaust.is_initialized }

      if has_exhaust_fan
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Prototype.Model', "Thermal zone #{thermal_zone.name} already has an exhaust fan. None will be added.")
        next
      end

      zone_exhaust_fan = OpenstudioStandards::HVAC.create_exhaust_fan(thermal_zone)
      unless zone_exhaust_fan.nil?
        # set fan pressure rise
        fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)

        # update efficiency and pressure rise
        prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)

        zone_exhaust_fans << zone_exhaust_fan
      end
    end

    return zone_exhaust_fans
  end

  # Add guestroom vacancy controls
  # @note code_sections [90.1-2016_6.4.3.3.5]
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] the building type
  # @return [Boolean] Returns true if successful, false otherwise
  def model_add_guestroom_vacancy_controls(model, building_type)
    # Guestrooms are currently only included in the small and large hotel prototypes
    return true unless (building_type == 'LargeHotel') || (building_type == 'SmallHotel')

    # Guestrooms controls only required for 90.1-2016 and onward
    return true unless (template == '90.1-2016') || (template == '90.1-2019')

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding Guestroom Vacancy Controls')

    # Define guestroom vacancy maps
    # List of all spaces that represent vacant rooms
    guestroom_vacancy_map = {
      'LargeHotel' => [
        'Room_3_Mult19_Flr_3'
      ],
      'SmallHotel' => [
        'GuestRoom101',
        'GuestRoom102',
        'GuestRoom201',
        'GuestRoom215_218',
        'GuestRoom301',
        'GuestRoom302_305',
        'GuestRoom313',
        'GuestRoom319',
        'GuestRoom324',
        'GuestRoom402_405',
        'GuestRoom406_408',
        'GuestRoom413',
        'GuestRoom414'
      ]
    }

    # Iterate through spaces and apply for guestroom vacancy controls
    thermostat_schedules = {}
    thermostat_schedules['Heating'] = []
    thermostat_schedules['Cooling'] = []
    model.getSpaces.sort.each do |space|
      # Get space name
      space_name = space.name

      # Get space type
      space_type = space.spaceType.get

      # Skip space types with no standards building type
      next if space_type.standardsBuildingType.empty?

      stds_bldg_type = space_type.standardsBuildingType.get

      # Skip space types with no standards space type
      next if space_type.standardsSpaceType.empty?

      stds_spc_type = space_type.standardsSpaceType.get

      # Skip building types and space types that aren't listed in the guestroom vacancy maps
      next unless guestroom_vacancy_map.key?(stds_bldg_type)
      next unless guestroom_vacancy_map[stds_bldg_type].include?(space_name.to_s)

      # Get thermal zone and thermostat schedules associated with space
      thermal_zone = space.thermalZone.get
      if thermal_zone.thermostatSetpointDualSetpoint.is_initialized
        thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
        if thermostat.heatingSetpointTemperatureSchedule.is_initialized && thermostat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.is_initialized
          thermostat_schedules['Heating'] << thermostat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
        end
        if thermostat.coolingSetpointTemperatureSchedule.is_initialized && thermostat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.is_initialized
          thermostat_schedules['Cooling'] << thermostat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
        end
      end

      # Get zone equipment fan
      # Currently prototypes with guestrooms use PTAC and 4PFC
      # @todo Implement additional system type (zonal and air loop-based)
      thermal_zone.equipment.sort.each do |zone_equipment|
        if zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          equipment = zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.get
        elsif zone_equipment.to_ZoneHVACFourPipeFanCoil.is_initialized
          equipment = zone_equipment.to_ZoneHVACFourPipeFanCoil.get
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "#{thermal_zone} is not served by either a packaged terminal air-conditioner or four pipe fan coil, vacancy fan schedule has not been adjusted")
          next
        end

        # Change fan operation schedule
        fan = if equipment.supplyAirFan.to_FanConstantVolume.is_initialized
                equipment.supplyAirFan.to_FanConstantVolume.get
              elsif equipment.supplyAirFan.to_FanVariableVolume.is_initialized
                equipment.supplyAirFan.to_FanVariableVolume.get
              elsif equipment.supplyAirFan.to_FanOnOff.is_initialized
                equipment.supplyAirFan.to_FanOnOff.get
              end
        fan.setAvailabilitySchedule(model_add_schedule(model, 'GuestroomVacantFanSchedule'))
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished Adding Guestroom Vacancy Controls')
    end

    # Adjust thermostat schedules:
    # Increase set-up/back to comply with code requirements
    thermostat_schedules.each_key do |sch_type|
      thermostat_schedules[sch_type].uniq.each do |sch|
        # Skip non-ruleset schedules
        next if sch.to_ScheduleRuleset.empty?

        # Get schedule modifier
        case template
          when '90.1-2016', '90.1-2019'
            case sch_type
              when 'Heating'
                sch_mult = 15.556 / 18.889 # Set thermostat to 15.556
              when 'Cooling'
                sch_mult = 26.667 / 23.333 # Set thermostat to 26.667
              else
                sch_mult = 1 # No adjustments
            end
          else
            shc_mult = 1 # No adjustments
        end

        # Modify schedules
        OpenstudioStandards::Schedules.schedule_day_multiply_by_value(sch.defaultDaySchedule, sch_mult)
      end
    end
  end

  # Add guestroom ventilation availability schedules based on the thermostat heating setpoint schedules (to infer setback)
  # Call to this method needs to be place before purge hour implementation of zone ventilation (if any)
  #
  # @code_sections [90.1-2019_6.4.3.3.5.2]
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio Model
  # @param building_type [String] Building type
  def model_add_guestroom_vent_sch(model, building_type)
    return true unless (template == '90.1-2016') || (template == '90.1-2019')

    # Guestrooms are currently only included in the small and large hotel prototypes
    return true unless (building_type == 'LargeHotel') || (building_type == 'SmallHotel')

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding Guestroom Ventilation Schedules')

    # Define guestroom occupied maps
    # List of all spaces that represent vacant rooms
    guestroom_occupied_map = {
      'LargeHotel' => [
        'Room_1_Flr_3',
        'Room_1_Flr_6',
        'Room_2_Flr_3',
        'Room_2_Flr_6',
        'Room_3_Mult9_Flr_6',
        'Room_4_Mult19_Flr_3',
        'Room_5_Flr_3',
        'Room_6_Flr_3'
      ],
      'SmallHotel' => [
        'GuestRoom103',
        'GuestRoom104',
        'GuestRoom105',
        'GuestRoom202_205',
        'GuestRoom206_208',
        'GuestRoom209_212',
        'GuestRoom213',
        'GuestRoom214',
        'GuestRoom219',
        'GuestRoom220_223',
        'GuestRoom224',
        'GuestRoom306_308',
        'GuestRoom309_312',
        'GuestRoom314',
        'GuestRoom315_318',
        'GuestRoom320_323',
        'GuestRoom401',
        'GuestRoom409_412',
        'GuestRoom415_418',
        'GuestRoom419',
        'GuestRoom420_423',
        'GuestRoom424'
      ]
    }

    # Extract thermostat schedule as the base for ventilation schedule
    if building_type == 'LargeHotel'
      # thermostat_name = 'LargeHotel GuestRoom Thermostat'
      air_terminals = model.getAirTerminalSingleDuctConstantVolumeNoReheats.sort
    elsif building_type == 'SmallHotel'
      # thermostat_name = 'SmallHotel GuestRoom4Occ Thermostat'
      air_terminals = model.getZoneHVACPackagedTerminalAirConditioners.sort
    end

    guestroom_htg_schrst, guestroom_clg_schrst = get_occ_guestroom_setpoint_schedules(model)

    # intentionally no check so if anything is wrong, this will break
    guestroom_htg_sch = guestroom_htg_schrst.to_ScheduleRuleset.get.defaultDaySchedule
    guestroom_clg_sch = guestroom_clg_schrst.to_ScheduleRuleset.get.defaultDaySchedule

    if guestroom_htg_sch.times != guestroom_clg_sch.times
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "#{building_type} Guestroom heating and cooling schedule has different setback times, will use htg for generating the ventilation binary schedule")
    end

    # Build ventilation binary schedule
    htg_sch_values = guestroom_htg_sch.values
    htg_sch_times = guestroom_htg_sch.times

    vent_schrst = OpenStudio::Model::ScheduleRuleset.new(model)
    vent_schrst.setName("#{building_type}_GuestRoom_Vent_Ctrl_Sch")
    # add design day values (1)
    vent_winterdesignday_sch = OpenStudio::Model::ScheduleDay.new(model)
    vent_winterdesignday_sch.setName("#{building_type}_GuestRoom_Vent_Ctrl_Sch Winter Design Day")
    model_add_vals_to_sch(model, vent_winterdesignday_sch, 'Constant', [1])
    vent_schrst.setSummerDesignDaySchedule(vent_winterdesignday_sch)
    vent_summerdesignday_sch = OpenStudio::Model::ScheduleDay.new(model)
    vent_summerdesignday_sch.setName("#{building_type}_GuestRoom_Vent_Ctrl_Sch Summer Design Day")
    model_add_vals_to_sch(model, vent_summerdesignday_sch, 'Constant', [1])
    vent_schrst.setWinterDesignDaySchedule(vent_summerdesignday_sch)

    # add default ventilation schedule
    vent_day_sch = vent_schrst.defaultDaySchedule
    vent_day_sch.setName("#{building_type}_GuestRoom_Vent_Ctrl_Sch Default")
    vent_day_binary_values = []
    off_value = htg_sch_values.min
    htg_sch_values.each do |value|
      vent_day_binary_values << if value > off_value
                                  1.0
                                else
                                  0.0
                                end
    end
    vent_day_binary_values.each_with_index do |binary_value, i|
      vent_day_sch.addValue(htg_sch_times[i], binary_value)
    end

    # link vent schedule to guest room air terminals
    modified_zones = []
    air_terminals.each do |airterminal|
      zone_name = airterminal.name.to_s.strip.split[0]
      if guestroom_occupied_map[building_type].include? zone_name
        if building_type == 'LargeHotel'
          airterminal.setAvailabilitySchedule(vent_schrst)
        elsif building_type == 'SmallHotel'
          airterminal.setSupplyAirFanOperatingModeSchedule(vent_schrst)
        end
        modified_zones << zone_name
      end
    end
  end

  # Reduce thermostat temperature setpoint delay (when switching from occupied to unoccupied ) by 10 mins
  #
  # @code_sections [90.1-2019_6.4.3.3.5.1]
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio Model
  # @param building_type [String] Building type
  def model_reduce_setback_sch_delay(model, building_type)
    # Guestrooms are currently only included in the small and large hotel prototypes
    return true unless (building_type == 'LargeHotel') || (building_type == 'SmallHotel')

    # Guestrooms setback schedule delay modifications are only added to 2019
    return true unless template == '90.1-2019'

    heating_schrst, cooling_schrst = get_occ_guestroom_setpoint_schedules(model)
    heating_default_day_sch = heating_schrst.defaultDaySchedule
    schedule_reduce_reset_delay_10min(heating_default_day_sch, heating_default_day_sch.values.min)
    cooling_default_day_sch = cooling_schrst.defaultDaySchedule
    schedule_reduce_reset_delay_10min(cooling_default_day_sch, cooling_default_day_sch.values.max)
  end

  # Helper method for model_add_guestroom_vent_sch and model_reduce_setback_sch_delay
  # @author Xuechen (Jerry) Lei, PNNL
  #
  def get_occ_guestroom_setpoint_schedules(model)
    thermostats = model.getThermostatSetpointDualSetpoints.sort
    thermostats.each do |thermostat|
      next unless thermostat.name.to_s.include? 'GuestRoom'

      heating_schrst = thermostat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
      cooling_schrst = thermostat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
      next unless heating_schrst.name.to_s.include? 'Occ'
      next unless cooling_schrst.name.to_s.include? 'Occ'

      return heating_schrst, cooling_schrst
    end
    return false
  end

  # Helper method for model_reduce_setback_sch_delay
  # @author Xuechen (Jerry) Lei, PNNL
  #
  def schedule_reduce_reset_delay_10min(sch, off_value)
    sch_values = sch.values
    sch_times = sch.times
    ten_mins = OpenStudio::Time.new(0, 0, 10, 0)
    new_times = []
    (0..(sch_values.length - 2)).each do |i|
      current_time = sch_times[i]
      current_value = sch_values[i]
      next_value = sch_values[i + 1]
      if ((current_value - off_value).abs >= 0.01) && ((next_value - off_value).abs < 0.01) # reduce occupied (current) time by 10 min if next value is off_value
        new_times << (current_time - ten_mins)
      else
        new_times << current_time
      end
    end
    new_times << sch_times[-1]

    # remove old values
    sch_times.each do |old_time|
      sch.removeValue(old_time)
    end

    # add new time
    (0..(new_times.length - 1)).each do |i|
      sch.addValue(new_times[i], sch_values[i])
    end
  end

  # Adds occupancy sensors to certain space types per
  # the PNNL documentation.
  #
  # @param (see #add_constructions)
  # @return [Boolean] returns true if successful, false if not
  # @todo genericize and move this method to Standards.Space
  def model_add_occupancy_sensors(model, building_type, climate_zone)
    # Only add occupancy sensors for 90.1-2010
    # Currently deactivated for all 90.1 versions
    # of the prototype because occupancy sensor is
    # currently modeled using different schedules
    # hence this code double counts savings from
    # sensors.
    # @todo Move occupancy sensor modeling from
    # schedule to code.
    case template
      when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004', '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        return true
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding Occupancy Sensors')

    space_type_reduction_map = {
      'SecondarySchool' => { 'Classroom' => 0.32, 'Restroom' => 0.34, 'Office' => 0.22 },
      'PrimarySchool' => { 'Classroom' => 0.32, 'Restroom' => 0.34, 'Office' => 0.22 }
    }

    # Loop through all the space types and reduce lighting operation schedule fractions as-specified
    model.getSpaceTypes.sort.each do |space_type|
      # Skip space types with no standards building type
      next if space_type.standardsBuildingType.empty?

      stds_bldg_type = space_type.standardsBuildingType.get

      # Skip space types with no standards space type
      next if space_type.standardsSpaceType.empty?

      stds_spc_type = space_type.standardsSpaceType.get

      # Skip building types and space types that aren't listed in the hash
      next unless space_type_reduction_map.key?(stds_bldg_type)
      next unless space_type_reduction_map[stds_bldg_type].key?(stds_spc_type)

      # Get the reduction fraction multiplier
      red_multiplier = 1 - space_type_reduction_map[stds_bldg_type][stds_spc_type]

      lights_sch_names = []
      lights_schs = {}
      reduced_lights_schs = {}

      # Get all of the lights in this space type
      # and determine the list of schedules they use.
      space_type.lights.each do |light|
        # Skip lights that don't have a schedule
        next if light.schedule.empty?

        lights_sch = light.schedule.get
        lights_schs[lights_sch.name.to_s] = lights_sch
        lights_sch_names << lights_sch.name.to_s
      end

      # Loop through the unique list of lighting schedules, cloning
      # and reducing schedule fraction before and after the specified times
      lights_sch_names.uniq.each do |lights_sch_name|
        lights_sch = lights_schs[lights_sch_name]
        # Skip non-ruleset schedules
        next if lights_sch.to_ScheduleRuleset.empty?

        # Clone the schedule (so that we don't mess with lights in
        # other space types that might be using the same schedule).
        new_lights_sch = lights_sch.clone(model).to_ScheduleRuleset.get
        new_lights_sch.setName("#{lights_sch_name} OccSensor Reduction")
        reduced_lights_schs[lights_sch_name] = new_lights_sch

        # Reduce default day schedule
        OpenstudioStandards::Schedules.schedule_day_multiply_by_value(new_lights_sch.defaultDaySchedule, red_multiplier, lower_apply_limit: 0.25)

        # Reduce all other rule schedules
        new_lights_sch.scheduleRules.each do |sch_rule|
          OpenstudioStandards::Schedules.schedule_day_multiply_by_value(sch_rule.daySchedule, red_multiplier, lower_apply_limit: 0.25)
        end
      end

      # Loop through all lights instances, replacing old lights
      # schedules with the reduced schedules.
      space_type.lights.each do |light|
        # Skip lights that don't have a schedule
        next if light.schedule.empty?

        old_lights_sch_name = light.schedule.get.name.to_s
        if reduced_lights_schs[old_lights_sch_name]
          light.setSchedule(reduced_lights_schs[old_lights_sch_name])
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Occupancy sensor reduction added to '#{light.name}'")
        end
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished Adding Occupancy Sensors')

    return true
  end

  # add occupancy sensors

  # Adds exterior lights to the building, as specified
  # in OpenStudio_Standards_prototype_inputs
  #
  # @param (see #add_constructions)
  # @return [Boolean] returns true if successful, false if not
  # @todo translate w/linear foot of facade, door, parking, etc
  #   into lookup table and implement that way instead of hard-coding as
  #   inputs in the spreadsheet.
  def model_add_exterior_lights(model, building_type, climate_zone, prototype_input)
    # @todo Standards - translate w/linear foot of facade, door, parking, etc
    #   into lookup table and implement that way instead of hard-coding as
    #   inputs in the spreadsheet.
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started adding exterior lights')

    # Occupancy Sensing Exterior Lights
    # which reduce to 70% power when no one is around.
    unless prototype_input['occ_sensing_exterior_lighting_power'].nil?
      occ_sens_ext_lts_power = prototype_input['occ_sensing_exterior_lighting_power']
      occ_sens_ext_lts_sch_name = prototype_input['occ_sensing_exterior_lighting_schedule']
      occ_sens_ext_lts_name = 'Occ Sensing Exterior Lights'
      occ_sens_ext_lts_def = OpenStudio::Model::ExteriorLightsDefinition.new(model)
      occ_sens_ext_lts_def.setName("#{occ_sens_ext_lts_name} Def")
      occ_sens_ext_lts_def.setDesignLevel(occ_sens_ext_lts_power)
      occ_sens_ext_lts_sch = model_add_schedule(model, occ_sens_ext_lts_sch_name)
      occ_sens_ext_lts = OpenStudio::Model::ExteriorLights.new(occ_sens_ext_lts_def, occ_sens_ext_lts_sch)
      occ_sens_ext_lts.setName("#{occ_sens_ext_lts_name} Def")
      occ_sens_ext_lts.setControlOption('AstronomicalClock')
    end

    # Building Facade and Landscape Lights
    # that don't dim at all at night.
    unless prototype_input['nondimming_exterior_lighting_power'].nil?
      nondimming_ext_lts_power = prototype_input['nondimming_exterior_lighting_power']
      nondimming_ext_lts_sch_name = prototype_input['nondimming_exterior_lighting_schedule']
      nondimming_ext_lts_name = 'NonDimming Exterior Lights'
      nondimming_ext_lts_def = OpenStudio::Model::ExteriorLightsDefinition.new(model)
      nondimming_ext_lts_def.setName("#{nondimming_ext_lts_name} Def")
      nondimming_ext_lts_def.setDesignLevel(nondimming_ext_lts_power)
      nondimming_ext_lts_sch = model_add_schedule(model, nondimming_ext_lts_sch_name)
      nondimming_ext_lts = OpenStudio::Model::ExteriorLights.new(nondimming_ext_lts_def, nondimming_ext_lts_sch)
      nondimming_ext_lts.setName("#{nondimming_ext_lts_name} Def")
      nondimming_ext_lts.setControlOption('AstronomicalClock')
    end

    # Fuel Equipment being used to model external elevators
    unless prototype_input['exterior_fuel_equipment1_power'].nil?
      fuel_ext_power = prototype_input['exterior_fuel_equipment1_power']
      fuel_ext_sch_name = prototype_input['exterior_fuel_equipment1_schedule']
      fuel_ext_name = 'Fuel equipment 1'
      fuel_ext_def = OpenStudio::Model::ExteriorFuelEquipmentDefinition.new(model)
      fuel_ext_def.setName("#{fuel_ext_name} Def")
      fuel_ext_def.setDesignLevel(fuel_ext_power)
      fuel_ext_sch = model_add_schedule(model, fuel_ext_sch_name)
      fuel_ext_lts = OpenStudio::Model::ExteriorFuelEquipment.new(fuel_ext_def, fuel_ext_sch)
      fuel_ext_lts.setFuelType('Electricity')
      fuel_ext_lts.setName(fuel_ext_name.to_s)
    end

    unless prototype_input['exterior_fuel_equipment2_power'].nil?
      fuel_ext_power = prototype_input['exterior_fuel_equipment2_power']
      fuel_ext_sch_name = prototype_input['exterior_fuel_equipment2_schedule']
      fuel_ext_name = 'Fuel equipment 2'
      fuel_ext_def = OpenStudio::Model::ExteriorFuelEquipmentDefinition.new(model)
      fuel_ext_def.setName("#{fuel_ext_name} Def")
      fuel_ext_def.setDesignLevel(fuel_ext_power)
      fuel_ext_sch = model_add_schedule(model, fuel_ext_sch_name)
      fuel_ext_lts = OpenStudio::Model::ExteriorFuelEquipment.new(fuel_ext_def, fuel_ext_sch)
      fuel_ext_lts.setFuelType('Electricity')
      fuel_ext_lts.setName(fuel_ext_name.to_s)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding exterior lights')

    return true
  end

  # Sets the inside and outside convection algorithms for different vintages
  #
  # @param (see #add_constructions)
  # @return [Boolean] returns true if successful, false if not
  # @todo Consistency - make prototype and reference vintages consistent
  def model_modify_surface_convection_algorithm(model)
    inside = model.getInsideSurfaceConvectionAlgorithm
    outside = model.getOutsideSurfaceConvectionAlgorithm

    case template
      when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004'
        inside.setAlgorithm('TARP')
        outside.setAlgorithm('DOE-2')
      else
        inside.setAlgorithm('TARP')
        outside.setAlgorithm('TARP')
    end
  end

  # Set up daylight savings
  def model_add_daylight_savings(model)
    start_date = '2nd Sunday in March'
    end_date = '1st Sunday in November'

    runperiodctrl_daylgtsaving = model.getRunPeriodControlDaylightSavingTime
    runperiodctrl_daylgtsaving.setStartDate(start_date)
    runperiodctrl_daylgtsaving.setEndDate(end_date)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Set Daylight Saving Start Date to #{start_date} and end date to #{end_date}.")
  end

  # Adds holidays to the model.
  # @todo enable holidays once supported inside OpenStudio schedules
  def model_add_holidays(model)
    newyear = OpenStudio::Model::RunPeriodControlSpecialDays.new('1/1', model)
    newyear.setName('New Years')
    newyear.setSpecialDayType('Holiday')

    fourth = OpenStudio::NthDayOfWeekInMonth.new(4)
    thurs = OpenStudio::DayOfWeek.new('Thursday')
    nov = OpenStudio::MonthOfYear.new('November')
    thanksgiving = OpenStudio::Model::RunPeriodControlSpecialDays.new(fourth, thurs, nov, model)
    thanksgiving.setName('Thanksgiving')
    thanksgiving.setSpecialDayType('Holiday')

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', 'Added holidays: New Years, Thanksgiving.')
  end

  # Changes the infiltration coefficients for the prototype vintages.
  #
  # @param (see #add_constructions)
  # @return [Boolean] returns true if successful, false if not
  # @todo Consistency - make sizing factors consistent
  #   between building types, climate zones, and vintages?
  def model_apply_sizing_parameters(model, building_type)
    # Default unless otherwise specified
    clg = 1.2
    htg = 1.2
    case template
      when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004'
        case building_type
          when 'PrimarySchool', 'SecondarySchool', 'Outpatient'
            clg = 1.5
            htg = 1.5
          when 'LargeHotel'
            clg = 1.33
            htg = 1.33
        end
      when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        # exit if is one of the 90.1 templates as their sizing paramters are explicitly specified in geometry osms
        return
      when 'CBES Pre-1978', 'CBES T24 1978', 'CBES T24 1992', 'CBES T24 2001', 'CBES T24 2005', 'CBES T24 2008'
        case building_type
          when 'Hospital', 'LargeHotel', 'MediumOffice', 'LargeOffice', 'MediumOfficeDetailed', 'LargeOfficeDetailed', 'Outpatient', 'PrimarySchool'
            clg = 1.0
            htg = 1.0
        end
      when 'NECB2011'
        raise('do not use this method for NECB')
      else
        # Use the sizing factors from 90.1 PRM
        clg = 1.15
        htg = 1.25
    end

    sizing_params = model.getSizingParameters
    sizing_params.setHeatingSizingFactor(htg)
    sizing_params.setCoolingSizingFactor(clg)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Set sizing factors to #{htg} for heating and #{clg} for cooling.")
  end

  def model_apply_prototype_hvac_assumptions(model, building_type, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying prototype HVAC assumptions.')

    # Fan pressure rise
    model.getFanConstantVolumes.sort.each { |obj| fan_constant_volume_apply_prototype_fan_pressure_rise(obj) }
    model.getFanVariableVolumes.sort.each { |obj| fan_variable_volume_apply_prototype_fan_pressure_rise(obj) }
    model.getFanOnOffs.sort.each { |obj| fan_on_off_apply_prototype_fan_pressure_rise(obj) }
    model.getFanZoneExhausts.sort.each { |obj| fan_zone_exhaust_apply_prototype_fan_pressure_rise(obj) }

    # Fan motor efficiency
    model.getFanConstantVolumes.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }
    model.getFanVariableVolumes.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }
    model.getFanOnOffs.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }
    model.getFanZoneExhausts.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }

    # Add Economizers
    apply_economizers(climate_zone, model)

    # Pump part load performances
    model.getPumpVariableSpeeds.sort.each { |obj| pump_variable_speed_control_type(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying prototype HVAC assumptions.')
  end

  # Applies the Prototype Building assumptions that contradict/supersede
  # the given standard.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def model_apply_prototype_hvac_efficiency_adjustments(model)
    building_data = model_get_building_properties(model)
    building_type = building_data['building_type']
    climate_zone = building_data['climate_zone']

    # ERVs
    if building_type == 'MidriseApartment' || building_type == 'HighriseApartment'
      # Use standalone ERV in dwelling units to provide OA
      # Loads are met by mechanical cooling and the heating system with a cycling fan
      model.getAirLoopHVACs.each do |air_loop_hvac|
        # Find out if air loop has an ERV (i.e. if heat recovery is required)
        has_erv = false
        has_erv = true if air_loop_hvac_energy_recovery?(air_loop_hvac)

        serves_res_spc = false

        air_loop_hvac.thermalZones.each do |zone|
          next unless OpenstudioStandards::ThermalZone.thermal_zone_residential?(zone)

          # Exception 3 to 6.5.6.1.1
          case template
          when '90.1-2019'
            case climate_zone
            when 'ASHRAE 169-2006-0A',
              'ASHRAE 169-2006-0B',
              'ASHRAE 169-2006-1A',
              'ASHRAE 169-2006-1B',
              'ASHRAE 169-2006-2A',
              'ASHRAE 169-2006-2B',
              'ASHRAE 169-2006-3A',
              'ASHRAE 169-2006-3B',
              'ASHRAE 169-2006-3C',
              'ASHRAE 169-2006-4A',
              'ASHRAE 169-2006-4B',
              'ASHRAE 169-2006-4C',
              'ASHRAE 169-2006-5A',
              'ASHRAE 169-2006-5B',
              'ASHRAE 169-2006-5C',
              'ASHRAE 169-2013-0A',
              'ASHRAE 169-2013-0B',
              'ASHRAE 169-2013-1A',
              'ASHRAE 169-2013-1B',
              'ASHRAE 169-2013-2A',
              'ASHRAE 169-2013-2B',
              'ASHRAE 169-2013-3A',
              'ASHRAE 169-2013-3B',
              'ASHRAE 169-2013-3C',
              'ASHRAE 169-2013-4A',
              'ASHRAE 169-2013-4B',
              'ASHRAE 169-2013-4C',
              'ASHRAE 169-2013-5A',
              'ASHRAE 169-2013-5B',
              'ASHRAE 169-2013-5C'
              if zone.floorArea <= OpenStudio.convert(500.0, 'ft^2', 'm^2').get
                has_erv = false
                OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Energy recovery will not be modeled for the ERV serving #{zone.name}.")
              end
            end
          end

          oa_cfm_per_ft2 = 0.0578940512546562
          oa_m3_per_m2 = OpenStudio.convert(OpenStudio.convert(oa_cfm_per_ft2, 'cfm', 'm^3/s').get, '1/ft^2', '1/m^2').get
          if has_erv
            model_add_residential_erv(model, [zone], oa_m3_per_m2)
          else
            model_add_residential_ventilator(model, [zone], oa_m3_per_m2)
          end

          # Shut-off air loop level OA intake
          oa_controller = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
          oa_controller.setMinimumOutdoorAirSchedule(model.alwaysOffDiscreteSchedule)

          serves_res_spc = true
        end

        if has_erv & serves_res_spc
          # Remove air loop ERV
          air_loop_hvac_remove_erv(air_loop_hvac)
        elsif has_erv
          # Apply regular adjustment if the ERV doesn't serve a residential space
          oa_sys = nil
          if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
            oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
          else
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV cannot be removed because the system has no OA intake.")
            return false
          end

          # Get the existing ERV or create an ERV and add it to the OA system
          oa_sys.oaComponents.each do |oa_comp|
            if oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized
              erv = oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.get
              heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency(erv)
            end
          end
        end
      end
    else
      # Applies the DOE Prototype Building assumption that ERVs use
      # enthalpy wheels and therefore exceed the minimum effectiveness specified by 90.1
      model.getHeatExchangerAirToAirSensibleAndLatents.each { |obj| heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency(obj) }
    end

    # Update COP for large office CRAC
    # Applies the DOE Prototype Building Model (Large Office only)
    if @instvarbuilding_type == 'LargeOffice'
      model.getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each do |coil_cooling_water_to_air_heat_pump|
        if coil_cooling_water_to_air_heat_pump.name.get.downcase.include?('datacenter')
          cop = coil_cooling_water_to_air_heat_pump_standard_minimum_cop(coil_cooling_water_to_air_heat_pump, rename = false, computer_room_air_conditioner = true)
          if cop.nil?
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "COP for #{coil_cooling_water_to_air_heat_pump.name} is not changed")
          else
            coil_cooling_water_to_air_heat_pump.setRatedCoolingCoefficientofPerformance(cop)
          end
        end
      end
    end

    return true
  end

  def model_add_debugging_variables(model, type)
    # 'detailed'
    # 'timestep'
    # 'hourly'
    # 'daily'
    # 'monthly'

    vars = []
    case type
      when 'service_water_heating'
        var_names << ['Water Heater Water Volume Flow Rate', 'timestep']
        var_names << ['Water Use Equipment Hot Water Volume Flow Rate', 'timestep']
        var_names << ['Water Use Equipment Cold Water Volume Flow Rate', 'timestep']
        var_names << ['Water Use Equipment Hot Water Temperature', 'timestep']
        var_names << ['Water Use Equipment Cold Water Temperature', 'timestep']
        var_names << ['Water Use Equipment Mains Water Volume', 'timestep']
        var_names << ['Water Use Equipment Target Water Temperature', 'timestep']
        var_names << ['Water Use Equipment Mixed Water Temperature', 'timestep']
        var_names << ['Water Heater Tank Temperature', 'timestep']
        var_names << ['Water Heater Use Side Mass Flow Rate', 'timestep']
        var_names << ['Water Heater Heating Rate', 'timestep']
        var_names << ['Water Heater Water Volume Flow Rate', 'timestep']
        var_names << ['Water Heater Water Volume', 'timestep']
    end

    var_names.each do |var_name, reporting_frequency|
      output_var = OpenStudio::Model::OutputVariable.new(var_name, model)
      output_var.setReportingFrequency(reporting_frequency)
    end
  end

  def model_run(model, run_dir = "#{Dir.pwd}/Run")
    # If the model_run(model)  directory is not specified
    # model_run(model)  in the current working directory

    # Make the directory if it doesn't exist
    FileUtils.mkdir_p(run_dir)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation in '#{run_dir}'")

    # Change the simulation to only model_run(model)  the weather file
    # and not model_run(model)  the sizing day simulations
    sim_control = model.getSimulationControl
    sim_control.setRunSimulationforSizingPeriods(false)
    sim_control.setRunSimulationforWeatherFileRunPeriods(true)

    # Save the model to energyplus idf
    idf_name = 'in.idf'
    osm_name = 'in.osm'
    forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
    idf = forward_translator.translateModel(model)
    idf_path = OpenStudio::Path.new("#{run_dir}/#{idf_name}")
    osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
    idf.save(idf_path, true)
    save(osm_path, true)

    # Set up the sizing simulation
    # Find the weather file
    epw_path = nil
    if model.weatherFile.is_initialized
      epw_path = model.weatherFile.get.path
      if epw_path.is_initialized
        if File.exist?(epw_path.get.to_s)
          epw_path = epw_path.get
        else
          # If this is an always-run Measure, need to check a different path
          alt_weath_path = File.expand_path(File.join(File.dirname(__FILE__), '../../../resources'))
          alt_epw_path = File.expand_path(File.join(alt_weath_path, epw_path.get.to_s))
          if File.exist?(alt_epw_path)
            epw_path = OpenStudio::Path.new(alt_epw_path)
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "Model has been assigned a weather file, but the file is not in the specified location of '#{epw_path.get}'.")
            return false
          end
        end
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', 'Model has a weather file assigned, but the weather file path has been deleted.')
        return false
      end
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', 'Model has not been assigned a weather file.3')
      return false
    end

    # If running on a regular desktop, use RunManager.
    # If running on OpenStudio Server, use WorkFlowMananger
    # to avoid slowdown from the sizing run.
    use_runmanager = true

    begin
      require 'openstudio-workflow'
      use_runmanager = false
    rescue LoadError
      use_runmanager = true
    end

    sql_path = nil
    if use_runmanager
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', 'Running sizing model_run(model)  with RunManager.')

      # Find EnergyPlus
      ep_dir = OpenStudio.getEnergyPlusDirectory
      ep_path = OpenStudio.getEnergyPlusExecutable
      ep_tool = OpenStudio::Runmanager::ToolInfo.new(ep_path)
      idd_path = OpenStudio::Path.new("#{ep_dir}/Energy+.idd")
      output_path = OpenStudio::Path.new("#{run_dir}/")

      # Make a run manager and queue up the sizing model_run(model)
      run_manager_db_path = OpenStudio::Path.new("#{run_dir}/run.db")
      run_manager = OpenStudio::Runmanager::RunManager.new(run_manager_db_path, true, false, false, false)
      job = OpenStudio::Runmanager::JobFactory.createEnergyPlusJob(ep_tool,
                                                                   idd_path,
                                                                   idf_path,
                                                                   epw_path,
                                                                   output_path)

      run_manager.enqueue(job, true)

      # Start the sizing model_run(model)  and wait for it to finish.
      while run_manager.workPending
        sleep 1
        OpenStudio::Application.instance.processEvents
      end

      sql_path = OpenStudio::Path.new("#{run_dir}/Energyplus/eplusout.sql")

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Finished sizing model_run(model)  in #{(Time.new - start_time).round}sec.")

    else # Use the openstudio-workflow gem
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', 'Running sizing model_run(model)  with openstudio-workflow gem.')

      # Copy the weather file to this directory
      FileUtils.copy(epw_path.to_s, run_dir)

      # Run the simulation
      sim = OpenStudio::Workflow.run_energyplus('Local', run_dir)
      final_state = model_run(sim)

      if final_state == :finished
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Finished sizing model_run(model)  in #{(Time.new - start_time).round}sec.")
      end

      sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")

    end

    # Load the sql file created by the sizing model_run(model)
    sql_path = OpenStudio::Path.new("#{run_dir}/Energyplus/eplusout.sql")
    if OpenStudio.exists(sql_path)
      sql = OpenStudio::SqlFile.new(sql_path)
      # Check to make sure the sql file is readable,
      # which won't be true if EnergyPlus crashed during simulation.
      unless sql.connectionOpen
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The model_run(model)  failed.  Look at the eplusout.err file in #{File.dirname(sql_path.to_s)} to see the cause.")
        return false
      end
      # Attach the sql file from the model_run(model)  to the sizing model
      model.setSqlFile(sql)
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Results for the sizing model_run(model)  couldn't be found here: #{sql_path}.")
      return false
    end

    # Check that the model_run(model)  finished without severe errors
    error_query = "SELECT ErrorMessage
        FROM Errors
        WHERE ErrorType='1'"

    errs = model.sqlFile.get.execAndReturnVectorOfString(error_query)
    if errs.is_initialized
      errs = errs.get
      unless errs.empty?
        errs = errs.get
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The model_run(model)  failed with the following severe errors: #{errs.join('\n')}.")
        return false
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation in '#{run_dir}'")

    return true
  end

  def model_request_timeseries_outputs(model)
    # "detailed"
    # "timestep"
    # "hourly"
    # "daily"
    # "monthly"

    vars = []
    # vars << ['Heating Coil Gas Rate', 'detailed']
    # vars << ['Zone Thermostat Air Temperature', 'detailed']
    # vars << ['Zone Thermostat Heating Setpoint Temperature', 'detailed']
    # vars << ['Zone Thermostat Cooling Setpoint Temperature', 'detailed']
    # vars << ['Zone Air System Sensible Heating Rate', 'detailed']
    # vars << ['Zone Air System Sensible Cooling Rate', 'detailed']
    # vars << ['Fan Electric Power', 'detailed']
    # vars << ['Zone Mechanical Ventilation Standard Density Volume Flow Rate', 'detailed']
    # vars << ['Air System Outdoor Air Mass Flow Rate', 'detailed']
    # vars << ['Air System Outdoor Air Flow Fraction', 'detailed']
    # vars << ['Air System Outdoor Air Minimum Flow Fraction', 'detailed']

    # vars << ['Water Use Equipment Hot Water Volume Flow Rate', 'hourly']
    # vars << ['Water Use Equipment Cold Water Volume Flow Rate', 'hourly']
    # vars << ['Water Use Equipment Total Volume Flow Rate', 'hourly']
    # vars << ['Water Use Equipment Hot Water Temperature', 'hourly']
    # vars << ['Water Use Equipment Cold Water Temperature', 'hourly']
    # vars << ['Water Use Equipment Target Water Temperature', 'hourly']
    # vars << ['Water Use Equipment Mixed Water Temperature', 'hourly']

    # vars << ['Water Use Connections Hot Water Volume Flow Rate', 'hourly']
    # vars << ['Water Use Connections Cold Water Volume Flow Rate', 'hourly']
    # vars << ['Water Use Connections Total Volume Flow Rate', 'hourly']
    # vars << ['Water Use Connections Hot Water Temperature', 'hourly']
    # vars << ['Water Use Connections Cold Water Temperature', 'hourly']
    # vars << ['Water Use Connections Plant Hot Water Energy', 'hourly']
    # vars << ['Water Use Connections Return Water Temperature', 'hourly']

    # vars << ['Air System Outdoor Air Economizer Status','timestep']
    # vars << ['Air System Outdoor Air Heat Recovery Bypass Status','timestep']
    # vars << ['Air System Outdoor Air High Humidity Control Status','timestep']
    # vars << ['Air System Outdoor Air Flow Fraction','timestep']
    # vars << ['Air System Outdoor Air Minimum Flow Fraction','timestep']
    # vars << ['Air System Outdoor Air Mass Flow Rate','timestep']
    # vars << ['Air System Mixed Air Mass Flow Rate','timestep']

    # vars << ['Heating Coil Gas Rate','timestep']
    vars << ['Boiler Part Load Ratio', 'timestep']
    vars << ['Boiler Gas Rate', 'timestep']
    # vars << ['Boiler Gas Rate','timestep']
    # vars << ['Fan Electric Power','timestep']

    vars << ['Pump Electric Power', 'timestep']
    vars << ['Pump Outlet Temperature', 'timestep']
    vars << ['Pump Mass Flow Rate', 'timestep']

    # vars << ['Zone Air Terminal VAV Damper Position','timestep']
    # vars << ['Zone Air Terminal Minimum Air Flow Fraction','timestep']
    # vars << ['Zone Air Terminal Outdoor Air Volume Flow Rate','timestep']
    # vars << ['Zone Lights Electric Power','hourly']
    # vars << ['Daylighting Lighting Power Multiplier','hourly']
    # vars << ['Schedule Value','hourly']

    vars.each do |var, freq|
      output_var = OpenStudio::Model::OutputVariable.new(var, model)
      output_var.setReportingFrequency(freq)
    end
  end

  def model_clear_and_set_example_constructions(model)
    # Define Materials
    opaque_mat = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.0127, 0.16, 0.1, 100)
    insulation_mat = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.05, 0.043, 0.1, 100)
    simple_glazing_mat = OpenStudio::Model::SimpleGlazing.new(model, 3.236460, 0.25)
    simple_glazing_mat.setThickness(0.003)
    simple_glazing_mat.setVisibleTransmittance(0.16)
    standard_glazing_mat = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
    standard_glazing_mat.setSolarTransmittanceatNormalIncidence(0.5)

    # Define Constructions
    # # Surfaces
    ext_wall = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionExtWall', [opaque_mat, insulation_mat], insulation_mat)
    ext_roof = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionExtRoof', [opaque_mat, insulation_mat], insulation_mat)
    ext_floor = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionExtFloor', [opaque_mat, insulation_mat], insulation_mat)
    grnd_wall = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionGrndWall', [opaque_mat, insulation_mat], insulation_mat)
    grnd_roof = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionGrndRoof', [opaque_mat, insulation_mat], insulation_mat)
    grnd_floor = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionGrndFloor', [opaque_mat, insulation_mat], insulation_mat)
    int_wall = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionIntWall', [opaque_mat, insulation_mat], insulation_mat)
    int_roof = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionIntRoof', [opaque_mat, insulation_mat], insulation_mat)
    int_floor = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionIntFloor', [opaque_mat, insulation_mat], insulation_mat)
    # # Subsurfaces
    fixed_window = BTAP::Resources::Envelope::Constructions.create_construction(model, 'FenestrationConstructionFixed', [simple_glazing_mat])
    operable_window = BTAP::Resources::Envelope::Constructions.create_construction(model, 'FenestrationConstructionOperable', [simple_glazing_mat])
    glass_door = BTAP::Resources::Envelope::Constructions.create_construction(model, 'FenestrationConstructionDoor', [standard_glazing_mat])
    door = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionDoor', [opaque_mat, insulation_mat], insulation_mat)
    overhead_door = BTAP::Resources::Envelope::Constructions.create_construction(model, 'OpaqueConstructionOverheadDoor', [opaque_mat, insulation_mat], insulation_mat)
    skylt = BTAP::Resources::Envelope::Constructions.create_construction(model, 'FenestrationConstructionSkylight', [standard_glazing_mat])
    daylt_dome = BTAP::Resources::Envelope::Constructions.create_construction(model, 'FenestrationConstructionDomeConstruction', [standard_glazing_mat])
    daylt_diffuser = BTAP::Resources::Envelope::Constructions.create_construction(model, 'FenestrationConstructionDiffuserConstruction', [standard_glazing_mat])

    # Define Construction Sets
    # # Surface
    exterior_construction_set = BTAP::Resources::Envelope::ConstructionSets.create_default_surface_constructions(model, 'ExteriorSet', ext_wall, ext_roof, ext_floor)
    interior_construction_set = BTAP::Resources::Envelope::ConstructionSets.create_default_surface_constructions(model, 'InteriorSet', int_wall, int_roof, int_floor)
    ground_construction_set = BTAP::Resources::Envelope::ConstructionSets.create_default_surface_constructions(model, 'GroundSet', grnd_wall, grnd_roof, grnd_floor)

    # # Subsurface
    subsurface_exterior_construction_set = BTAP::Resources::Envelope::ConstructionSets.create_subsurface_construction_set(model, fixed_window, operable_window, door, glass_door, overhead_door, skylt, daylt_dome, daylt_diffuser)
    subsurface_interior_construction_set = BTAP::Resources::Envelope::ConstructionSets.create_subsurface_construction_set(model, fixed_window, operable_window, door, glass_door, overhead_door, skylt, daylt_dome, daylt_diffuser)

    # Define default construction sets.
    name = 'Construction Set 1'
    default_construction_set = BTAP::Resources::Envelope::ConstructionSets.create_default_construction_set(model, name, exterior_construction_set, interior_construction_set, ground_construction_set, subsurface_exterior_construction_set, subsurface_interior_construction_set)

    # Assign default to the model.
    model.getBuilding.setDefaultConstructionSet(default_construction_set)

    return default_construction_set
  end

  # Return the dominant standards building type
  def model_get_standards_building_type(model)
    # determine areas of each building type
    building_type_areas = {}
    model.getSpaces.each do |space|
      # ignore space if not part of total area
      next unless space.partofTotalFloorArea

      if space.spaceType.is_initialized
        space_type = space.spaceType.get
        if space_type.standardsBuildingType.is_initialized
          building_type = space_type.standardsBuildingType.get
          if building_type_areas[building_type].nil?
            building_type_areas[building_type] = space.floorArea
          else
            building_type_areas[building_type] += space.floorArea
          end
        end
      end
    end

    # return largest building type area
    building_type = building_type_areas.key(building_type_areas.values.max)

    if building_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', 'Model has no dominant standards building type.')
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "#{building_type} is the dominant standards building type.")
    end

    return building_type
  end

  # Determine the prototypical economizer type for the model.
  # Defaults to FixedDryBulb based on anecdotal evidence of this being
  # the most common type encountered in the field, combined
  # with this being the default option for many equipment manufacturers,
  # and being the strategy recommended in the 2010 ASHRAE journal article
  # "Economizer High Limit Devices and Why Enthalpy Economizers Don't Work"
  # by Steven Taylor and Hwakong Cheng.
  # https://tayloreng.egnyte.com/dl/mN0c9t4WSO/ASHRAE_Journal_-_Economizer_High_Limit_Devices_and_Why_Enthalpy_Economizers_Dont_Work.pdf_
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] the economizer type.  Possible values are:
  # 'NoEconomizer'
  # 'FixedDryBulb'
  # 'FixedEnthalpy'
  # 'DifferentialDryBulb'
  # 'DifferentialEnthalpy'
  # 'FixedDewPointAndDryBulb'
  # 'ElectronicEnthalpy'
  # 'DifferentialDryBulbAndEnthalpy'
  def model_economizer_type(model, climate_zone)
    economizer_type = 'FixedDryBulb'
    return economizer_type
  end

  def apply_economizers(climate_zone, model)
    # Create an economizer maximum OA fraction of 70%
    # to reflect damper leakage per PNNL
    econ_max_70_pct_oa_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    econ_max_70_pct_oa_sch.setName('Economizer Max OA Fraction 70 pct')
    econ_max_70_pct_oa_sch.defaultDaySchedule.setName('Economizer Max OA Fraction 70 pct Default')
    econ_max_70_pct_oa_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.7)

    # Store original climate zones
    climate_zone_code = climate_zone

    # Check each airloop
    model.getAirLoopHVACs.sort.each do |air_loop|
      economizer_required = false

      if air_loop_hvac_humidifier_count(air_loop) > 0
        # If airloop includes a humidifier it is assumed
        # that exception c to 90.1-2004/7 Section 6.5.1 applies.
        if template == '90.1-2004' || template == '90.1-2007'
          economizer_required = false
        end
        # This exception exist through 90.1-2019, for hospitals
        # see Section 6.5.1 exception 4
        if @instvarbuilding_type == 'Hospital' &&
           (template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019')
          economizer_required = false
        end
      elsif @instvarbuilding_type == 'LargeOffice' &&
            air_loop.name.to_s.downcase.include?('datacenter') &&
            air_loop.name.to_s.downcase.include?('basement') &&
            !(template == '90.1-2004' || template == '90.1-2007')
        # System serving the data center in the basement of the large
        # office is assumed to be always large enough to require an
        # economizer when economizer requirement is based on equipment
        # size.
        #
        # No economizer modeled for 90.1-2004 and 2007:
        # Specific economizer requirements for computer rooms were
        # introduced in 90.1-2010. Before that, although not explicitly
        # specified, economizer requirements were aimed at comfort
        # cooling, not computer room cooling (as per input from the MSC).

        # Process climate zone:
        # Moisture regime is not needed for climate zone 8
        climate_zone = climate_zone.split('-')[-1]
        climate_zone = '8' if climate_zone.include?('8')

        # Get the size threshold requirement
        search_criteria = {
          'template' => template,
          'climate_zone' => climate_zone,
          'data_center' => true
        }
        econ_limits = model_find_object(standards_data['economizers'], search_criteria)
        minimum_capacity_btu_per_hr = econ_limits['minimum_capacity']
        economizer_required = !minimum_capacity_btu_per_hr.nil?
      elsif @instvarbuilding_type == 'LargeOffice' && air_loop_hvac_include_wshp?(air_loop)
        # WSHP serving the IT closets are assumed to always be too
        # small to require an economizer
        economizer_required = false
      elsif air_loop_hvac_economizer_required?(air_loop, climate_zone)
        economizer_required = true
      end

      if economizer_required
        # If an economizer is required, determine the economizer type
        # in the prototype buildings, which depends on climate zone.
        economizer_type = model_economizer_type(model, climate_zone_code)

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
        # oa_control.setMaximumFractionofOutdoorAirSchedule(econ_max_70_pct_oa_sch)

        # Check that the economizer type set by the prototypes
        # is not prohibited by code.  If it is, change to no economizer.
        unless air_loop_hvac_economizer_type_allowable?(air_loop, climate_zone_code)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but the type chosen, #{economizer_type} is prohibited by code for climate zone #{climate_zone}. Economizer type will be switched to No Economizer.")
          oa_control.setEconomizerControlType('NoEconomizer')
        end

      end
    end
  end

  # Implement occupancy based lighting level threshold (0.02 W/sqft). This is only for ASHRAE 90.1 2016 onwards.
  # @note code_sections [90.1-2016_9.4.1.1.h/i]
  # @author Xuechen (Jerry) Lei, PNNL
  #
  # @param model [OpenStudio::Model::Model] OpenStudio Model
  # @return [Boolean] returns true if successful, false if not
  def model_add_lights_shutoff(model)
    return false
  end

  # Get building door information to update infiltration
  #
  # @param model [OpenStudio::Model::Model] OpenStudio Model
  # return [Hash] Door infiltration information
  def get_building_door_info(model)
    get_building_door_info = {}

    return get_building_door_info
  end

  # Metal coiling door code minimum infiltration rate at 75 Pa
  #
  # @param [String] Climate zone
  # @return [Double] Minimum infiltration rate for metal coiling doors
  def model_door_infil_flow_rate_metal_coiling_cfm_ft2(climate_zone)
    case climate_zone
      when 'ASHRAE 169-2006-7A',
           'ASHRAE 169-2006-7B',
           'ASHRAE 169-2006-8A',
           'ASHRAE 169-2006-8B'
        return 0.4
      else
        return 4.4
    end
  end

  # Metal rollup door code minimum infiltration rate at 75 Pa
  #
  # @param [String] Climate zone
  # @return [Double] Minimum infiltration rate for metal coiling doors
  def model_door_infil_flow_rate_rollup_cfm_ft2(climate_zone)
    return 0.4
  end

  # Open door infiltration rate at 75 Pa
  #
  # @param [String] Climate zone
  # @return [Double] Open door infiltration rate
  def model_door_infil_flow_rate_open_cfm_ft2(climate_zone)
    return 9.7875
  end

  # Add door infiltration
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] Returns true if successful, false otherwise or not applicable
  def model_add_door_infiltration(model, climate_zone)
    # Get door parameters for the building model
    bldg_door_types = get_building_door_info(model)
    return false if bldg_door_types.empty?

    bldg_door_types.each do |door_type, door_info|
      # Get infiltration flow rate at 75 Pa
      case door_type
        when 'Metal coiling'
          door_infil_flow_rate_cfm_per_ft2 = model_door_infil_flow_rate_metal_coiling_cfm_ft2(climate_zone)
        when 'Rollup'
          door_infil_flow_rate_cfm_per_ft2 = model_door_infil_flow_rate_rollup_cfm_ft2(climate_zone)
        when 'Open'
          door_infil_flow_rate_cfm_per_ft2 = model_door_infil_flow_rate_open_cfm_ft2(climate_zone)
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.Model', "The #{door_type.downcase} type of door is not currently supported.")
          next
      end

      # Calculate door infiltration
      door_infil_cfm = door_info['number_of_doors'] * door_info['door_area_ft2'] * door_infil_flow_rate_cfm_per_ft2

      # Conversion factor
      conv_fact = OpenStudio.convert(1, 'm^3/s', 'ft^3/min').to_f

      # Adjust the infiltration rate to the average pressure for the prototype buildings.
      adj_door_infil_cfm = OpenstudioStandards::Infiltration.adjust_infiltration_to_prototype_building_conditions(door_infil_cfm)
      adj_door_infil_m3_per_s = adj_door_infil_cfm / conv_fact

      # Create door infiltration object
      door_infil_obj = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
      door_infil_obj.setName("#{door_info['number_of_doors']} #{door_info['door_area_ft2']} ft2 #{door_type.downcase} Door Infiltration")
      door_infil_obj.setSchedule(door_info['schedule'])
      door_infil_obj.setDesignFlowRate(adj_door_infil_m3_per_s)
      door_infil_obj.setSpace(model.getSpaceByName(door_info['space']).get)
      door_infil_obj.setConstantTermCoefficient(0.0)
      door_infil_obj.setTemperatureTermCoefficient 0.0
      door_infil_obj.setVelocityTermCoefficient(0.224)
      door_infil_obj.setVelocitySquaredTermCoefficient(0.0)
    end

    return true
  end

  # Calculate a model's window or WWR
  # Disregard space conditioning (assume all spaces are conditioned)
  # which is true for most of not all prototypes
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param wwr [Boolean]
  # @return [Numeric] Returns window to wall ratio (percentage) or window area.
  def model_get_window_area_info(model, wwr = true)
    window_area = 0
    wall_area = 0

    model.getSpaces.each do |space|
      # Get zone multipler
      multiplier = space.thermalZone.get.multiplier
      space.surfaces.each do |surface|
        next if surface.surfaceType != 'Wall'
        next if surface.outsideBoundaryCondition != 'Outdoors'

        # Get wall and window area
        wall_area += surface.grossArea * multiplier
        surface.subSurfaces.each do |subsurface|
          subsurface_type = subsurface.subSurfaceType.to_s.downcase
          # Do not count doors
          next unless (subsurface_type.include? 'window') || (subsurface_type.include? 'glass')

          window_area += subsurface.grossArea * subsurface.multiplier * multiplier
        end
      end
    end

    # check wall area is non-zero
    if wwr && wall_area > 0
      return window_area / wall_area * 100
    end

    # else
    return window_area
  end

  # Adjust model to comply with fenestration orientation
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] Returns true if successful, false otherwise
  def model_fenestration_orientation(model, climate_zone)
    return true
  end

  # Is transfer air required?
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] true if transfer air is required, false otherwise
  def model_transfer_air_required?(model)
    return false
  end

  # List transfer air target and source zones, and air flow (cfm)
  #
  # code_sections [90.1-2019_6.5.7.1], [90.1-2016_6.5.7.1]
  # @return [Hash] target zones (key) and source zones (value) and air flow (value)
  def model_transfer_air_target_and_source_zones(model)
    model_transfer_air_target_and_source_zones_hash = {}

    return model_transfer_air_target_and_source_zones_hash
  end

  # Add transfer to prototype for spaces that require it
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_add_transfer_air(model)
    # Do not add transfer air if not required
    return true unless model_transfer_air_required?(model)

    # Get target and source zones
    target_and_source_zones = model_transfer_air_target_and_source_zones(model)
    return true if target_and_source_zones.empty?

    model.getFanZoneExhausts.sort.each do |exhaust_fan|
      # Target zone (zone with exhaust fan)
      target_zone = exhaust_fan.thermalZone.get

      # Get zone name of an exhaust fan
      exhaust_fan_zone_name = target_zone.name.to_s

      # Go to next exhaust fan if this zone isn't using transfer air
      next unless target_and_source_zones.keys.include? exhaust_fan_zone_name

      # Add dummy exhaust fan in source zone
      source_zone_name, transfer_air_flow_cfm = target_and_source_zones[exhaust_fan_zone_name]
      source_zone = model.getThermalZoneByName(source_zone_name).get
      transfer_air_source_zone_exhaust_fan = OpenStudio::Model::FanZoneExhaust.new(model)
      transfer_air_source_zone_exhaust_fan.setName("#{source_zone.name} Dummy Transfer Air (Source) Fan")
      transfer_air_source_zone_exhaust_fan.setAvailabilitySchedule(exhaust_fan.availabilitySchedule.get)
      # Convert transfer air flow to m3/s
      transfer_air_flow_m3s = OpenStudio.convert(transfer_air_flow_cfm, 'cfm', 'm^3/s').get
      transfer_air_source_zone_exhaust_fan.setMaximumFlowRate(transfer_air_flow_m3s)
      transfer_air_source_zone_exhaust_fan.setFanEfficiency(1.0)
      transfer_air_source_zone_exhaust_fan.setPressureRise(0.0)
      transfer_air_source_zone_exhaust_fan.addToThermalZone(source_zone)

      # Set exhaust fan balanced air flow schedule to only consider the transfer air to be balanced air flow
      balanced_air_flow_schedule = exhaust_fan.availabilitySchedule.get.clone(model).to_ScheduleRuleset.get
      balanced_air_flow_schedule.setName("#{exhaust_fan_zone_name} Exhaust Fan Balanced Air Flow Schedule")
      OpenstudioStandards::Schedules.schedule_day_multiply_by_value(balanced_air_flow_schedule.defaultDaySchedule, transfer_air_flow_m3s / exhaust_fan.maximumFlowRate.get)
      balanced_air_flow_schedule.scheduleRules.each do |sch_rule|
        OpenstudioStandards::Schedules.schedule_day_multiply_by_value(sch_rule.daySchedule, transfer_air_flow_m3s / exhaust_fan.maximumFlowRate.get)
      end
      transfer_air_source_zone_exhaust_fan.setBalancedExhaustFractionSchedule(balanced_air_flow_schedule)

      # Modify design specification OA to take into account transfer air for sizing only
      # OA is zero'd out for other days
      target_zone.spaces.sort.each do |space|
        target_zone_ventilation = space.designSpecificationOutdoorAir.get
        target_zone_ventilation.setOutdoorAirFlowperPerson(0)
        target_zone_ventilation.setOutdoorAirFlowperFloorArea(0)
        target_zone_ventilation.setOutdoorAirFlowRate(exhaust_fan.maximumFlowRate.get - transfer_air_flow_m3s)
        target_zone_ventilation.setOutdoorAirFlowRateFractionSchedule(model_add_schedule(model, 'DesignDaysOnly'))
      end
    end

    return true
  end

  # Offset values of a schedule
  # Main usage is for modeling occupancy standby mode
  # where the thermostat schedule in these mode are
  # required to setup/back their thermostat setpoints
  #
  # @param time_offset_hash [Hash] Hash providing time (key) and schedule value offset (values)
  # @param schedule [OpenStudio::Model::ScheduleRuleset] OpenStudio schedule object
  # @return [OpenStudio::Model::ScheduleRuleset] Modified OpenStudio schedule object
  def model_offset_schedule_value(schedule, time_offset_hash)
    offset_sch = schedule.clone(schedule.model).to_ScheduleRuleset.get

    # Get day schedule
    day_schedules = []
    default_day_schedule = offset_sch.defaultDaySchedule
    day_schedules << default_day_schedule
    offset_sch.scheduleRules.each do |rule|
      day_schedules << rule.daySchedule
    end

    # Offset schedule values
    day_schedules.each do |day_schedule|
      (0..23).each do |hr|
        next if !time_offset_hash.key?(hr.to_s)

        t = OpenStudio::Time.new(0, hr, 0, 0)

        # Get schedule value
        value = day_schedule.getValue(t)

        # Offset schedule value
        day_schedule.addValue(t, value)
        t_p_1 = OpenStudio::Time.new(0, hr + 1, 0, 0)
        day_schedule.addValue(t_p_1, value + time_offset_hash[hr.to_s])
      end
    end

    offset_sch.setName("#{schedule.name} - offset")
    return offset_sch
  end

  # Set/change values of a schedule
  # Main usage is for modeling occupancy standby mode
  # where the thermostat schedule in these mode are
  # required to setup/back their thermostat setpoints
  #
  # @param time_offset_hash [Hash] Hash providing time (key) and schedule value offset (values)
  # @param schedule [OpenStudio::Model::ScheduleRuleset] OpenStudio schedule object
  # @return [OpenStudio::Model::ScheduleRuleset] Modified OpenStudio schedule object
  def model_set_schedule_value(schedule, time_value_hash)
    return nil unless schedule.to_ScheduleRuleset.is_initialized

    new_sch = schedule.clone(schedule.model).to_ScheduleRuleset.get

    # Get day schedule
    day_schedules = []
    default_day_schedule = new_sch.defaultDaySchedule
    day_schedules << default_day_schedule
    new_sch.scheduleRules.each do |rule|
      day_schedules << rule.daySchedule
    end

    # Set schedule values
    day_schedules.each do |day_schedule|
      (0..23).each do |hr|
        next if !time_value_hash.key?(hr.to_s)

        t = OpenStudio::Time.new(0, hr, 0, 0)

        # Get schedule value
        value = day_schedule.getValue(t)

        # Set schedule value
        day_schedule.addValue(t, value)
        t_p_1 = OpenStudio::Time.new(0, hr + 1, 0, 0)
        day_schedule.addValue(t_p_1, time_value_hash[hr.to_s])
      end
    end

    new_sch.setName("#{schedule.name} - adjusted")
    return new_sch
  end

  # Modify thermostat schedule to account for a thermostat setback/up
  #
  # @param thermostat [OpenStudio::Model::ThermostatSetpointDualSetpoint] OpenStudio ThermostatSetpointDualSetpoint object
  # @return [Boolean] returns true if successful, false if not
  def space_occupancy_standby_mode(thermostat)
    return false
  end
end
