class AppendixGPRMTests < Minitest::Test

  # Add exhaust fan object to each lab zone in model
  # @param model
  def add_exhaust_fan_per_lab_zone(model)
    model.getThermalZones.sort.each do |thermal_zone|
      lab_is_found = false
      zone_area = 0
      thermal_zone.spaces.each do |space|
        space_type = space.spaceType.get.standardsSpaceType.get
        if space_type == 'laboratory'
          lab_is_found = true
          zone_area += space.floorArea
        end
      end
      if lab_is_found
        # add an exhaust fan
        zone_exhaust_fan = OpenStudio::Model::FanZoneExhaust.new(model)
        zone_exhaust_fan.setName(thermal_zone.name.to_s + ' Exhaust Fan')
        zone_exhaust_fan.setFanEfficiency(0.6)
        zone_exhaust_fan.setPressureRise(200)

        # set air flow above threshold for isolation of lab spaces on separate hvac system
        # A rate of 0.5 cfm/sf gives 17,730 cfm total exhaust
        exhaust_cfm = 0.5 * zone_area
        maximum_flow_rate = OpenStudio.convert(exhaust_cfm, 'cfm', 'm^3/s').get
        zone_exhaust_fan.setMaximumFlowRate(maximum_flow_rate)
        zone_exhaust_fan.setEndUseSubcategory('Zone Exhaust Fans')
        zone_exhaust_fan.addToThermalZone(thermal_zone)
      end
    end
  end

  # Change fenestration area in a model
  # This function will remove the fenestration in all orientations and add new windows by defined WWR
  #
  # @param model [OpenStudio::Model::Model] model
  # @param [Double] window to wall ratio
  def change_wwr_model(model, arguments)
    target_wwr_north = arguments[0]
    target_wwr_south = arguments[1]
    target_wwr_east = arguments[2]
    target_wwr_west = arguments[3]

    model.getSurfaces.each do |ss|
      # determine orientation
      space = ss.space.get
      # Get model object
      model = ss.model
      # Calculate azimuth
      surface_azimuth_rel_space = OpenStudio.convert(ss.azimuth, 'rad', 'deg').get
      space_dir_rel_north = space.directionofRelativeNorth
      building_dir_rel_north = model.getBuilding.northAxis
      surface_abs_azimuth = surface_azimuth_rel_space + space_dir_rel_north + building_dir_rel_north
      surface_abs_azimuth -= 360.0 until surface_abs_azimuth < 360.0

      unless ss.subSurfaces.empty?
        # get subsurface construction
        orig_construction = nil
        door_list = []
        ss.subSurfaces.sort.each do |sub|
          if sub.subSurfaceType == 'Door'
            door = {}
            door['name'] = sub.name.get
            door['vertices'] = sub.vertices
            door['construction'] = sub.construction.get
            door_list << door
          else
            orig_construction = sub.construction.get
          end
        end
        # remove all existing surfaces
        ss.subSurfaces.sort.each(&:remove)
        # Determine the surface's cardinal direction
        if surface_abs_azimuth >= 0 && surface_abs_azimuth <= 45
          helper_add_window_to_wwr_with_door(target_wwr_north, ss, orig_construction, door_list, model)
        elsif surface_abs_azimuth > 315 && surface_abs_azimuth <= 360
          helper_add_window_to_wwr_with_door(target_wwr_north, ss, orig_construction, door_list, model)
        elsif surface_abs_azimuth > 45 && surface_abs_azimuth <= 135 &&
              helper_add_window_to_wwr_with_door(target_wwr_east, ss, orig_construction, door_list, model)
        elsif surface_abs_azimuth > 135 && surface_abs_azimuth <= 225
          helper_add_window_to_wwr_with_door(target_wwr_south, ss, orig_construction, door_list, model)
        elsif surface_abs_azimuth > 225 && surface_abs_azimuth <= 315 && target_wwr_west > 0.0
          helper_add_window_to_wwr_with_door(target_wwr_west, ss, orig_construction, door_list, model)
        end
      end
    end
    return model
  end

  # Increase the size of the skylights in a model
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] List of arguments
  def increase_skylight_size(model, arguments)
    mult = arguments[0]
    model.getSpaces.sort.each do |space|
      next if @prototype_creator.space_conditioning_category(space) == 'Unconditioned'

      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'

        # Skip non-walls
        next unless surface.surfaceType == 'RoofCeiling'

        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          next unless ss.subSurfaceType == 'Skylight'

          # increase the size of the skylight
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(ss, mult)
        end
      end
    end

    return model
  end

  # Add piping insulation to service heating water systems
  def add_piping_insulation(model, arguments)
    std = Standard.build('90.1-PRM-2019')
    model.getPlantLoops.each do |plant_loop|
      if std.plant_loop_swh_loop?(plant_loop)
        OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_piping_losses(model, plant_loop)
      end
    end

    return model
  end

  # Change the building name in the model
  def set_model_building_name(model, arguments)
    model.getBuilding.setName(arguments)
    return model
  end

  # Convert specified space types to laboratory space type
  # @param model, from_bldg_space is name of existing space type to convert to laboratory
  def convert_spaces_from_to(model, arguments)
    from_bldg_space, to_bldg_space = arguments
    # Convert all spaces of type to convert to laboratory
    model.getSpaceTypes.sort.each do |space_type|
      next if space_type.floorArea == 0

      standards_space_type = if space_type.standardsSpaceType.is_initialized
                               space_type.standardsSpaceType.get
                             end
      std_bldg_type = space_type.standardsBuildingType.get
      bldg_type_space_type = std_bldg_type + space_type.standardsSpaceType.get
      if bldg_type_space_type == from_bldg_space
        space_type.setStandardsSpaceType(to_bldg_space)
        # Populate hash to allow this space type to persist when protoype space types are replaced later
        @lpd_space_types_alt[std_bldg_type + to_bldg_space] = to_bldg_space
      end
    end
    return model
  end

  # Add people object to a specific zone with a long occupancy schedule
  # for testing 40 EFLH check of zones that differ for multizone systems
  # @author Doug Maddox, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param params [Array] zone_name, new equipment power density
  # @return [OpenStudio::Model::Model]
  def change_to_long_occ_sch(model, params)
    zone_name = params[0]
    # Create new long schedule for occupancy for each space in the zone
    # and assign to the spaces
    act_sch = nil
    ppl_sch_type_limits = nil
    model.getThermalZones.each do |zone|
      if zone.name.get == zone_name
        zone.spaces.each do |space|
          # Get existing activity schedule to use for new schedule
          space.spaceType.get.people.each do |people|
            act_sch = people.activityLevelSchedule
            if act_sch.is_initialized
              if act_sch.get.to_ScheduleRuleset.is_initialized
                act_sch = act_sch.get.to_ScheduleRuleset.get
              end
            end
            # Get existing schedule type limits to use for new schedule
            occ_sch = people.numberofPeopleSchedule
            if people.isNumberofPeopleScheduleDefaulted
              # Check default schedule set
              unless space.spaceType.get.defaultScheduleSet.empty?
                unless space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule.empty?
                  occ_sch = space.spaceType.get.defaultScheduleSet.get.numberofPeopleSchedule
                end
              end
            end
            ppl_sch_type_limits = occ_sch.get.scheduleTypeLimits.get
          end

          # Create new schedule always occupied
          ppl_values = Array.new(8760, 1)
          ppl_sch_name = space.name.get + 'ppl_sch_long'
          ppl_long_sch = @prototype_creator.make_ruleset_sched_from_8760(model, ppl_values, ppl_sch_name, ppl_sch_type_limits)

          # Create new people object and apply to the space
          peopledef = OpenStudio::Model::PeopleDefinition.new(model)
          peopledef.setName(space.name.get + 'ppl-long-def')
          peopledef.setNumberofPeople(10)
          peopledef.setFractionRadiant(0.3000)
          people = OpenStudio::Model::People.new(peopledef)
          people.setName(space.name.get + 'ppl-long')
          people.setMultiplier(1)
          people.setActivityLevelSchedule(act_sch)
          people.setNumberofPeopleSchedule(ppl_long_sch)
          people.setSpace(space)
        end
      end
    end

    # Also need to set the fan of the system serving that zone to run 24/7

    model.getAirLoopHVACs.each do |air_loop|
      air_loop.thermalZones.each do |zone|
        if zone.name.get == zone_name
          air_loop.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
        end
      end
    end

    return model
  end

  # Change equipment power density of a specific zone in a model to a specific value
  # @author Doug Maddox, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param params [Array] zone_name, new equipment power density
  # @return [OpenStudio::Model::Model]
  def change_zone_epd(model, params)
    zone_name = params[0]
    new_epd = params[1]

    model.getThermalZones.each do |zone|
      if zone.name.get == zone_name
        zone.spaces.each do |space|
          elec_eqp = space.spaceType.get.electricEquipment
          elec_sch = space.spaceType.get.defaultScheduleSet.get.electricEquipmentSchedule.get
          elec_name = 'special_plug_load'

          # elec_eqp[0].electricEquipmentDefinition.setWattsperSpaceFloorArea(new_epd)
          eqp_before = elec_eqp[0].getDesignLevel(space.floorArea, 0)
          # elec_eqp[0].electricEquipmentDefinition.setWattsperSpaceFloorArea(new_epd)
          elecdef = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
          elecdef.setWattsperSpaceFloorArea(new_epd)
          elecdef.setName(elec_name + '-def')
          elec = OpenStudio::Model::ElectricEquipment.new(elecdef)
          elec.setSpace(space)
          elec.setName(elec_name)
          elec.setMultiplier(1)
          elec.setSchedule(elec_sch)
          eqp_after = elec_eqp[0].getDesignLevel(space.floorArea, 0)
          istop = 1
        end
      end
    end
    return model
  end

  # Change (medium) office space types to computer room
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] Not used
  def convert_spaces_to_cmp_rms(model, arguments)
    convert_spaces_from_to(model, ['OfficeWholeBuilding - Md Office', 'computer room'])
    return model
  end

  # Change classroom space types to laboratory
  # Resulting in > 15,000 cfm lab exhaust
  # @param model, arguments[]
  def make_lab_high_system_exh(model, arguments)
    # Convert all classrooms to laboratory
    convert_spaces_from_to(model, ['PrimarySchoolClassroom', 'laboratory'])

    # reset OA make lab space OA exceed 17,000 cfm
    oa_name = 'PrimarySchool Classroom Ventilation'
    model.getDesignSpecificationOutdoorAirs.sort.each do |oa_def|
      if oa_def.name.to_s == oa_name
        oa_area = oa_def.outdoorAirFlowperFloorArea
        oa_def.setOutdoorAirFlowperFloorArea(0.0029)
      end
    end
    return model
  end

  # Change classroom space types to laboratory
  # Resulting in > 15,000 cfm lab exhaust
  # Add an exhaust fan to each zone
  # @param model, arguments[]
  def make_lab_high_distrib_zone_exh(model, arguments)
    # Convert all classrooms to laboratory
    convert_spaces_from_to(model, ['PrimarySchoolClassroom', 'laboratory'])

    # add exhaust fans to lab zones
    add_exhaust_fan_per_lab_zone(model)

    return model
  end

  # Change computer classroom space types to laboratory
  # Resulting in < 15,000 cfm lab exhaust
  # Add an exhaust fan to each zone
  # @param model, arguments[]
  def make_lab_low_distrib_zone_exh(model, arguments)
    convert_spaces_from_to(model, ['PrimarySchoolComputerRoom', 'laboratory'])
    # Populate hash to allow this space type to persist when protoype space types are replaced later
    # add exhaust fans to lab zones
    add_exhaust_fan_per_lab_zone(model)

    return model
  end

  # Applies a multipler to increase the design cooling load of datacenters
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param epd_multiplier [Array] EPD multiplier
  # @returns [OpenStudio::Model::Model]
  def increase_computer_rooms_epd(model, epd_multiplier)
    model.getThermalZones.each do |zone|
      zone.spaces.each do |space|
        if space.spaceType.get.standardsSpaceType.get.to_s.downcase.include?('data center') ||
           space.spaceType.get.standardsSpaceType.get.to_s.downcase.include?('computer room')
          elec_eqp = space.spaceType.get.electricEquipment
          elec_eqp[0].setMultiplier(epd_multiplier[0])
        end
      end
    end
    return model
  end

  # Remove cooling coil from air loops in model
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param params [Array] zone_name, new equipment power density
  # @return [OpenStudio::Model::Model]
  def remove_cooling_coils(model, params)
    model.getAirLoopHVACs.each do |air_loop|
      air_loop.supplyComponents.each do |supply_comp|
        if supply_comp.iddObjectType.valueName.to_s.include?('OS_Coil_Cooling')
          supply_comp.remove
        elsif supply_comp.iddObjectType.valueName.to_s.include?('OS_AirLoopHVAC_UnitarySystem')
          unitary_sys = supply_comp.to_AirLoopHVACUnitarySystem.get
          cooling_coil = unitary_sys.coolingCoil
          if cooling_coil.is_initialized
            cooling_coil = cooling_coil.get
            unitary_sys.resetCoolingCoil
            cooling_coil.remove
            controller_oa = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
            controller_oa.setEconomizerControlType('FixedDryBulb')
          end
        end
      end
    end
    return model
  end

  # Add return and relief fans to air loops
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param params [Array] zone_name, new equipment power density
  # @return [OpenStudio::Model::Model]
  def return_relief_fan(model, params)
    std = Standard.build('90.1-PRM-2019')
    model.getAirLoopHVACs.each do |air_loop|
      # Add return fan
      return_fan = OpenStudio::Model::FanVariableVolume.new(model, model.alwaysOnDiscreteSchedule)
      return_fan.setName("#{air_loop.name} return fan")
      return_fan.addToNode(air_loop.returnAirNode.get)

      # Add relief fan
      relief_fan = OpenStudio::Model::FanVariableVolume.new(model, model.alwaysOnDiscreteSchedule)
      relief_fan.setName("#{air_loop.name} relief fan")
      relief_fan.addToNode(air_loop.reliefAirNode.get)

      # Get supply fan
      supply_fan = air_loop.supplyFan.get
      if supply_fan.to_FanConstantVolume.is_initialized
        supply_fan = supply_fan.to_FanConstantVolume.get
      elsif supply_fan.to_FanVariableVolume.is_initialized
        supply_fan = supply_fan.to_FanVariableVolume.get
      elsif supply_fan.to_FanOnOff.is_initialized
        supply_fan = supply_fan.to_FanOnOff.get
      elsif supply_fan.to_FanSystemModel.is_initialized
        supply_fan = supply_fan.to_FanSystemModel.get
      end

      # Adjust return and relief fan power
      # Get the current pressure rise (Pa)
      return_fan.setPressureRise(supply_fan.pressureRise * 2)
      relief_fan.setPressureRise(supply_fan.pressureRise * 3)

      # Get the total fan efficiency
      return_fan.setFanEfficiency(supply_fan.fanEfficiency)
      relief_fan.setFanEfficiency(supply_fan.fanEfficiency)
    end
    return model
  end

  # Change the weather used in the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] List of arguments
  # return [OpenStudio::Model::Model] OpenStudio model object
  def change_weather_file(model, arguments)
    # Define new weather file
    weather_file = File.join(@@json_dir, 'USA_VA_Arlington-Ronald.Reagan.Washington.Natl.AP.724050_TMY3.epw')
    epw_file = OpenStudio::EpwFile.new(weather_file)

    # Assign new weather file
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file).get

    return model
  end

  # Change cooling thermostat to 24C
  # This is used to converted a heated only zone to heated and cooled
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] Not used
  def change_clg_therm(model, arguments)
    std = Standard.build("90.1-2019")
    thermal_zone = model.getThermalZoneByName(arguments[0]).get
    tstat = thermal_zone.thermostat.get
    tstat = tstat.to_ThermostatSetpointDualSetpoint.get
    cooling_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, 24, name: "#{thermal_zone.name.to_s} Cooling Schedule.", schedule_type_limit: 'Temperature')
    tstat.setCoolingSetpointTemperatureSchedule(cooling_schedule)

    return model
  end

  # Change model to different building type
  # @param model, arguments => new building type
  def change_bldg_type(model, arguments)
    bldg_type_new = arguments[0]
    @bldg_type_alt_now = bldg_type_new
    return model
  end

  # Set ZoneMultiplier to passed value for all zones
  #
  # @param model, arguments[]
  def set_zone_multiplier(model, arguments)
    mult = arguments[0]
    model.getAirLoopHVACs.each do |air_loop|
      air_loop.thermalZones.each do |thermal_zone|
        thermal_zone.setMultiplier(mult)
      end
    end
    return model
  end

  # Multiply the zone outdoor air flow rate per area
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] Multiplier
  def mult_oa_per_area(model, arguments)
    # Get multiplier
    mult = arguments[0]

    # Multiply the outdoor air flow rate per area
    model.getDesignSpecificationOutdoorAirs.each do |dsn_oa|
      dsn_oa.setOutdoorAirFlowperFloorArea(dsn_oa.outdoorAirFlowperFloorArea * mult)
    end

    return model
  end

  # Add a AirLoopHVACDedicatedOutdoorAirSystem in the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] Not used
  def add_ahu_doas(model, arguments)
    # Create new objects
    oa_ctrl = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_sys = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_ctrl)
    ahu_doas = OpenStudio::Model::AirLoopHVACDedicatedOutdoorAirSystem.new(oa_sys)
    ahu_doas.setName('AHU_DOAS')
    fan = OpenStudio::Model::FanSystemModel.new(model)

    # Assign fan and air loops
    fan.addToNode(oa_sys.outboardOANode.get)
    model.getAirLoopHVACs.each do |air_loop|
      ahu_doas.addAirLoop(air_loop)
    end

    return model
  end

  # Remove transformer from model
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] List of arguments
  def remove_transformer(model, arguments)
    model.getElectricLoadCenterTransformers.each(&:remove)
    return model
  end

  # This assigns the test case index for the DCV unit tests
  # @param arguments [array of string] list of test case identifiers
  def mark_test_case_no(model, arguments)
    arguments
    return model
  end

  def enable_airloop_dcv(model, arguments)
    # arguments contains a list of air loop names to enable dcv
    arguments.each do |air_loop_name|
      air_loop_hvac = model.getAirLoopHVACByName(air_loop_name).get
      # following logic is adopted from Standard.air_loop_hvac_enable_demand_control_ventilation
      controller_oa = nil
      controller_mv = nil
      if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
        oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
        controller_oa = oa_system.getControllerOutdoorAir
        controller_mv = controller_oa.controllerMechanicalVentilation
      end
      # Change the min flow rate in the controller outdoor air
      controller_oa.setMinimumOutdoorAirFlowRate(0.0)

      # Enable DCV in the controller mechanical ventilation
      controller_mv.setDemandControlledVentilation(true)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Enabled DCV.")
    end
    return model
  end

  def change_zone_num_ppl(model, arguments)
    # arguments contains an array with two elements, of which the first element is thermal zone name,
    # the second element is the number of people this zone is modified to
    zone_name, num_ppl = arguments
    thermal_zone = model.getThermalZoneByName(zone_name).get
    space0 = thermal_zone.spaces[0] # assume only change number of people in the first space
    space0.setNumberOfPeople(num_ppl)
    return model
  end
end
