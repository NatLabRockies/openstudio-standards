class ECMS
  # =============================================================================================================================
  # Remove existing zone equipment
  def remove_all_zone_eqpt(sys_objs)
    sys_objs.each do |isys|
      isys.thermalZones.each do |izone|
        if izone.equipment.empty? then next end

        izone.equipment.each(&:remove)
      end
    end
  end

  # =============================================================================================================================
  # Remove hot-water plant loops
  def remove_hw_loops(model)
    model.getPlantLoops.each do |iloop|
      hw_loop = false
      iloop.supplyComponents.each do |icomp|
        if icomp.to_BoilerHotWater.is_initialized
          hw_loop = true
          break
        end
      end
      if hw_loop then iloop.remove end
    end
  end

  # =============================================================================================================================
  # Remove chilled-water plant loops
  def remove_chw_loops(model)
    model.getPlantLoops.each do |iloop|
      chw_loop = false
      iloop.supplyComponents.each do |icomp|
        if icomp.to_ChillerElectricEIR.is_initialized
          chw_loop = true
          break
        end
      end
      if chw_loop then iloop.remove end
    end
  end

  # =============================================================================================================================
  # Remove condenser-water plant loops
  def remove_cw_loops(model)
    model.getPlantLoops.each do |iloop|
      cw_loop = false
      iloop.supplyComponents.each do |icomp|
        if icomp.to_CoolingTowerSingleSpeed.is_initialized
          cw_loop = true
        end
      end
      if cw_loop then iloop.remove end
    end
  end

  # =============================================================================================================================
  # Remove air loops
  def remove_air_loops(model)
    # remove air loops
    model.getAirLoopHVACs.each(&:remove)
  end

  # =============================================================================================================================
  # Return map of systems to zones and set flag for dedicated outdoor air unit for each system
  def get_map_systems_to_zones(systems)
    map_systems_to_zones = {}
    system_doas_flags = {}
    systems.each do |system|
      zones = system.thermalZones
      map_systems_to_zones[system.name.to_s] = zones
      if system.sizingSystem.typeofLoadtoSizeOn.to_s == 'VentilationRequirement'
        system_doas_flags[system.name.to_s] = true
      else
        system_doas_flags[system.name.to_s] = false
      end
    end
    return map_systems_to_zones, system_doas_flags
  end

  # =============================================================================================================================
  # Return hash of zone and cooling equipment type in the zone
  def get_zone_clg_eqpt_type(model)
    zone_clg_eqpt_type = {}
    model.getThermalZones.each do |zone|
      zone.equipment.each do |eqpt|
        if eqpt.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          zone_clg_eqpt_type[zone.name.to_s] = 'ZoneHVACPackagedTerminalAirConditioner'
          break
        end
      end
    end
    return zone_clg_eqpt_type
  end

  # =============================================================================================================================
  # Return hash of flags for whether storey is conditioned and average ceiling z-coordinates of building storeys.
  def get_storey_avg_clg_zcoords(model)
    storey_avg_clg_zcoords = {}
    model.getBuildingStorys.each do |storey|
      storey_avg_clg_zcoords[storey] = []
      storey_cond = false
      total_area = 0.0
      sum = 0.0
      raise("get_storey_avg_clg_zcoords: storey #{storey.name} has no spaces associated with it. Either delete the storey or " \
            "assign spaces to it") if storey.spaces.empty?
      storey.spaces.each do |space|
        # Determine if any of the spaces/zones of the storey are conditioned? If yes then the floor is considered to be conditioned
        if space.thermalZone.is_initialized
          zone = space.thermalZone.get
          if zone.thermostat.is_initialized
            if zone.thermostat.get.to_ThermostatSetpointDualSetpoint.is_initialized
              if zone.thermostat.get.to_ThermostatSetpointDualSetpoint.get.heatingSetpointTemperatureSchedule.is_initialized ||
                 zone.thermostat.get.to_ThermostatSetpointDualSetpoint.get.coolingSetpointTemperatureSchedule.is_initialized
                storey_cond = true
              end
            end
          end
        end
        # Find average height of z-coordinates of ceiling/roof of floor
        space.surfaces.each do |surf|
          if surf.surfaceType.to_s.upcase == 'ROOFCEILING'
            sum += (surf.centroid.z.to_f + space.zOrigin.to_f) * surf.grossArea.to_f
            total_area += surf.grossArea.to_f
          end
        end
      end
      storey_avg_clg_zcoords[storey] << storey_cond
      storey_avg_clg_zcoords[storey] << (sum / total_area)
    end

    return storey_avg_clg_zcoords
  end

  # =============================================================================================================================
  # Return x,y,z coordinates of exterior wall with largest area on the lowest floor
  def get_lowest_floor_ext_wall_centroid_coords(storeys_clg_zcoords)
    ext_wall = nil
    ext_wall_x = nil
    ext_wall_y = nil
    ext_wall_z = nil
    storeys_clg_zcoords.keys.each do |storey|
      max_area = 0.0
      sorted_spaces = storey.spaces.sort_by { |space| space.name.to_s }
      sorted_spaces.each do |space|
        ext_walls = space.surfaces.select { |surf| (surf.surfaceType.to_s.upcase == 'WALL') && (surf.outsideBoundaryCondition.to_s.upcase == 'OUTDOORS') }
        ext_walls = ext_walls.sort_by { |wall| wall.grossArea.to_f }
        if !ext_walls.empty?
          if ext_walls.last.grossArea.to_f > max_area
            max_area = ext_walls.last.grossArea.to_f
            ext_wall_x = ext_walls.last.centroid.x.to_f + space.xOrigin.to_f
            ext_wall_y = ext_walls.last.centroid.y.to_f + space.yOrigin.to_f
            ext_wall_z = ext_walls.last.centroid.z.to_f + space.zOrigin.to_f
            ext_wall = ext_walls.last
          end
        end
      end
      break unless !ext_wall
    end
    if !ext_wall
      OpenStudio.logFree(OpenStudio::Info, 'openstudiostandards.get_lowest_floor_ext_wall_centroid_coords', 'Did not find an exteior wall in the building!')
    end

    return ext_wall_x, ext_wall_y, ext_wall_z
  end

  # =============================================================================================================================
  # Return x,y,z coordinates of space centroid
  def get_space_centroid_coords(space)
    total_area = 0.0
    sum_x = 0.0
    sum_y = 0.0
    sum_z = 0.0
    space.surfaces.each do |surf|
      total_area += surf.grossArea.to_f
      sum_x += (surf.centroid.x.to_f + space.xOrigin.to_f) * surf.grossArea.to_f
      sum_y += (surf.centroid.y.to_f + space.yOrigin.to_f) * surf.grossArea.to_f
      sum_z += (surf.centroid.z.to_f + space.zOrigin.to_f) * surf.grossArea.to_f
    end
    space_centroid_x = sum_x / total_area
    space_centroid_y = sum_y / total_area
    space_centroid_z = sum_z / total_area

    return space_centroid_x, space_centroid_y, space_centroid_z
  end

  # =============================================================================================================================
  # Return x,y,z coordinates of the centroid of the roof of the storey
  def get_roof_centroid_coords(storey)
    sum_x = 0.0
    sum_y = 0.0
    sum_z = 0.0
    total_area = 0.0
    cent_x = nil
    cent_y = nil
    cent_z = nil
    storey.spaces.each do |space|
      roof_surfaces = space.surfaces.select { |surf| (surf.surfaceType.to_s.upcase == 'ROOFCEILING') && (surf.outsideBoundaryCondition.to_s.upcase == 'OUTDOORS') }
      roof_surfaces.each do |surf|
        sum_x += (surf.centroid.x.to_f + space.xOrigin.to_f) * surf.grossArea.to_f
        sum_y += (surf.centroid.y.to_f + space.yOrigin.to_f) * surf.grossArea.to_f
        sum_z += (surf.centroid.z.to_f + space.zOrigin.to_f) * surf.grossArea.to_f
        total_area += surf.grossArea.to_f
      end
    end
    if total_area > 0.0
      cent_x = sum_x / total_area
      cent_y = sum_y / total_area
      cent_z = sum_z / total_area
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudiostandards.get_roof_centroid_coords', 'Did not find a roof on the top floor!')
    end

    return cent_x, cent_y, cent_z
  end

  # =============================================================================================================================
  # Determine maximum equivalent and net vertical pipe runs for VRF model
  def get_max_vrf_pipe_lengths(model)
    # Get and sort floors average ceilings z-coordinates hash
    storeys_clg_zcoords = get_storey_avg_clg_zcoords(model)
    storeys_clg_zcoords = storeys_clg_zcoords.sort_by { |key, value| value[1] }.to_h # sort storeys hash based on ceiling/roof z-coordinate
    if storeys_clg_zcoords.values.last[0]
      # If the top floor is conditioned, then assume the top floor is not an attic floor and place the VRF outdoor unit at the roof centroid
      location_cent_x, location_cent_y, location_cent_z = get_roof_centroid_coords(storeys_clg_zcoords.keys.last)
    else
      # If the top floor is not conditioned, then assume it's an attic floor. In this case place the VRF outdoor unit next to the centroid
      # of the exterior wall with the largest area on the lowest floor.
      location_cent_x, location_cent_y, location_cent_z = get_lowest_floor_ext_wall_centroid_coords(storeys_clg_zcoords)
    end
    # Initialize distances
    max_equiv_distance = 0.0
    max_vert_distance = 0.0
    min_vert_distance = 0.0
    storeys_clg_zcoords.keys.each do |storey|
      next unless storeys_clg_zcoords[storey][0]

      storey.spaces.each do |space|
        # Is there a VRF terminal unit in the space/zone?
        vrf_term_units = []
        if space.thermalZone.is_initialized
          vrf_term_units = space.thermalZone.get.equipment.select { |eqpt| eqpt.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized }
        end
        next if vrf_term_units.empty?

        space_centroid_x, space_centroid_y, space_centroid_z = get_space_centroid_coords(space)
        # Update max horizontal and vertical distances if needed
        equiv_distance = (location_cent_x.to_f - space_centroid_x.to_f).abs +
                         (location_cent_y.to_f - space_centroid_y.to_f).abs +
                         (location_cent_z.to_f - space_centroid_z.to_f).abs
        if equiv_distance > max_equiv_distance then max_equiv_distance = equiv_distance end
        pos_vert_distance = [space_centroid_z.to_f - location_cent_z.to_f, 0.0].max
        if pos_vert_distance > max_vert_distance then max_vert_distance = pos_vert_distance end
        neg_vert_distance = [space_centroid_z.to_f - location_cent_z.to_f, 0.0].min
        if neg_vert_distance < min_vert_distance then min_vert_distance = neg_vert_distance end
      end
    end
    max_net_vert_distance = max_vert_distance + min_vert_distance

    return max_equiv_distance, max_net_vert_distance
  end

  # =============================================================================================================================
  # Add an outdoor VRF unit
  def add_outdoor_vrf_unit(model:,
                           ecm_name: nil,
                           condenser_type: 'AirCooled')
    outdoor_vrf_unit = OpenStudio::Model::AirConditionerVariableRefrigerantFlow.new(model)
    outdoor_vrf_unit.setName('VRF Outdoor Unit')
    outdoor_vrf_unit.setHeatPumpWasteHeatRecovery(true)
    outdoor_vrf_unit.setRatedHeatingCOP(4.0)
    if model.version < OpenStudio::VersionString.new('2.9.0')
      outdoor_vrf_unit.setRatedCoolingCOP(4.0)
    else
      outdoor_vrf_unit.setGrossRatedCoolingCOP(4.0)
    end
    outdoor_vrf_unit.setMinimumOutdoorTemperatureinHeatingMode(-25.0)
    outdoor_vrf_unit.setHeatingPerformanceCurveOutdoorTemperatureType('WetBulbTemperature')
    outdoor_vrf_unit.setMasterThermostatPriorityControlType('ThermostatOffsetPriority')
    outdoor_vrf_unit.setDefrostControl('OnDemand')
    outdoor_vrf_unit.setDefrostStrategy('ReverseCycle')
    outdoor_vrf_unit.autosizeResistiveDefrostHeaterCapacity
    outdoor_vrf_unit.setPipingCorrectionFactorforHeightinHeatingModeCoefficient(-0.00019231)
    outdoor_vrf_unit.setPipingCorrectionFactorforHeightinCoolingModeCoefficient(-0.00019231)
    outdoor_vrf_unit.setMinimumOutdoorTemperatureinHeatRecoveryMode(-5.0)
    outdoor_vrf_unit.setMaximumOutdoorTemperatureinHeatRecoveryMode(26.2)
    outdoor_vrf_unit.setInitialHeatRecoveryCoolingCapacityFraction(0.5)
    outdoor_vrf_unit.setHeatRecoveryCoolingCapacityTimeConstant(0.15)
    outdoor_vrf_unit.setInitialHeatRecoveryCoolingEnergyFraction(1.0)
    outdoor_vrf_unit.setHeatRecoveryCoolingEnergyTimeConstant(0.0)
    outdoor_vrf_unit.setInitialHeatRecoveryHeatingCapacityFraction(1.0)
    outdoor_vrf_unit.setHeatRecoveryHeatingCapacityTimeConstant(0.15)
    outdoor_vrf_unit.setInitialHeatRecoveryHeatingEnergyFraction(1.0)
    outdoor_vrf_unit.setHeatRecoveryCoolingEnergyTimeConstant(0.0)
    outdoor_vrf_unit.setMinimumHeatPumpPartLoadRatio(0.5)
    outdoor_vrf_unit.setCondenserType(condenser_type)
    outdoor_vrf_unit.setCrankcaseHeaterPowerperCompressor(1.0e-6)
    outdoor_vrf_unit.setMinimumOutdoorTemperatureinCoolingMode(-10)
    heat_defrost_eir_ft = nil
    if ecm_name
      search_criteria = {}
      search_criteria['name'] = 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit'
      props = model_find_object(standards_data['tables']['heat_pump_heating_ecm']['table'], search_criteria, 1.0)
      heat_defrost_eir_ft = model_add_curve(model, props['heat_defrost_eir_ft'])
    end
    if heat_defrost_eir_ft
      outdoor_vrf_unit.setDefrostEnergyInputRatioModifierFunctionofTemperatureCurve(heat_defrost_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{outdoor_vrf_unit.name}, cannot find heat_defrost_eir_ft curve, will not be set.")
    end

    return outdoor_vrf_unit
  end

  # =============================================================================================================================
  # Method to determine whether zone can have terminal vrf equipment. Zones with no vrf terminal equipment are characterized by
  # transient occupancy such is the case for corridors, stairwells, storage, ...
  def zone_with_no_vrf_eqpt?(zone)
    space_types_to_skip = {}
    space_types_to_skip['NECB2011'] = ['Atrium - H < 13m',
                                       'Atrium - H > 13m',
                                       'Audience - auditorium',
                                       'Corr. < 2.4m wide',
                                       'Corr. >= 2.4m wide',
                                       'Electrical/Mechanical',
                                       'Hospital corr. < 2.4m',
                                       'Hospital corr. >= 2.4m',
                                       'Mfg - corr. < 2.4m',
                                       'Mfg - corr. >= 2.4m',
                                       'Lobby - elevator',
                                       'Lobby - hotel',
                                       'Lobby - motion picture',
                                       'Lobby - other',
                                       'Lobby - performance arts',
                                       'Locker room',
                                       'Parking garage space',
                                       'Stairway',
                                       'Storage area',
                                       'Storage area - occsens',
                                       'Storage area - refrigerated',
                                       'Storage area - refrigerated - occsens',
                                       'Washroom',
                                       'Warehouse - fine',
                                       'Warehouse - fine - refrigerated',
                                       'Warehouse - med/blk',
                                       'Warehouse - med/blk - refrigerated',
                                       'Warehouse - med/blk2',
                                       'Warehouse - med/blk2 - refrigerated',
                                       'Hotel/Motel - lobby']

    space_types_to_skip['NECB2015'] = ['Atrium (height < 6m)',
                                       'Atrium (6 =< height <= 12m)',
                                       'Atrium (height > 12m)',
                                       'Computer/Server room-sch-A',
                                       'Copy/Print room',
                                       'Corridor/Transition area - hospital',
                                       'Corridor/Transition area - manufacturing facility',
                                       'Corridor/Transition area - space designed to ANSI/IES RP-28',
                                       'Corridor/Transition area other',
                                       'Electrical/Mechanical room',
                                       'Emergency vehicle garage',
                                       'Lobby - elevator',
                                       'Lobby - hotel',
                                       'Lobby - motion picture theatre',
                                       'Lobby - performing arts theatre',
                                       'Lobby - space designed to ANSI/IES RP-28',
                                       'Lobby - other',
                                       'Locker room',
                                       'Storage garage interior',
                                       'Storage room < 5 m2',
                                       'Storage room <= 5 m2 <= 100 m2',
                                       'Storage room > 100 m2',
                                       'Washroom - space designed to ANSI/IES RP-28',
                                       'Washroom - other',
                                       'Warehouse storage area medium to bulky palletized items',
                                       'Warehouse storage area small hand-carried items(4)']

    space_types_to_skip['NECB2017'] = ['Atrium (height < 6m)',
                                       'Atrium (6 =< height <= 12m)',
                                       'Atrium (height > 12m)',
                                       'Computer/Server room',
                                       'Copy/Print room',
                                       'Corridor/Transition area - hospital',
                                       'Corridor/Transition area - manufacturing facility',
                                       'Corridor/Transition area - space designed to ANSI/IES RP-28',
                                       'Corridor/Transition area other',
                                       'Electrical/Mechanical room',
                                       'Emergency vehicle garage',
                                       'Lobby - elevator',
                                       'Lobby - hotel',
                                       'Lobby - motion picture theatre',
                                       'Lobby - performing arts theatre',
                                       'Lobby - space designed to ANSI/IES RP-28',
                                       'Lobby - other',
                                       'Locker room',
                                       'Stairway/Stairwell',
                                       'Storage garage interior',
                                       'Storage room < 5 m2',
                                       'Storage room <= 5 m2 <= 100 m2',
                                       'Storage room > 100 m2',
                                       'Washroom - space designed to ANSI/IES RP-28',
                                       'Washroom - other',
                                       'Warehouse storage area medium to bulky palletized items',
                                       'Warehouse storage area small hand-carried items(4)']

    zone_does_not_have_vrf_eqpt = false
    zone.spaces.each do |space|
      space_types_to_skip.each do |std, spfs|
        spfs.each do |spf|
          if space.spaceType.get.name.to_s.downcase.include? spf.downcase
            zone_does_not_have_vrf_eqpt = true
            break
          end
        end
        break if zone_does_not_have_vrf_eqpt
      end
      break if zone_does_not_have_vrf_eqpt
    end
  end

  #=============================================================================================================================
  # Get building storey for a zone
  def get_zone_storey(zone)
    zone_storey = nil
    zone.model.getBuildingStorys.each do |storey|
      storey.spaces.each do |space|
        if space.thermalZone.get.name.to_s == zone.name.to_s
          zone_storey = storey
          break
        end
      end
      break if !zone_storey.nil?
    end
    return zone_storey
  end

  #==============================================================================================================================
  # Get a map of bldg storeys and zones
  def get_storey_zones_map(system_zones_map)
    storey_zones_map = {}
    system_zones_map.each do |sys,zones|
      zones.each do |zone|
        storey = get_zone_storey(zone)
        storey_zones_map[storey.name.to_s] = [] if !storey_zones_map.has_key? storey.name.to_s
        storey_zones_map[storey.name.to_s] << zone
      end
    end
    return storey_zones_map
  end

  #==============================================================================================================================
  # Update the map between systems and zones
  def update_system_zones_map(model,system_zones_map,system_zones_map_option,system_key)
    updated_system_zones_map = {}
    if system_zones_map_option == 'one_sys_per_bldg'
      system_zones_map.each do |sname,zones|
        updated_system_zones_map[system_key] = [] if !updated_system_zones_map.has_key? system_key
        updated_system_zones_map[system_key] += zones
      end
    elsif system_zones_map_option == 'one_sys_per_floor'
      storey_zones_map = get_storey_zones_map(system_zones_map)
      storey_zones_map.each do |storey_name,zones|
        sys_name = "#{system_key}_#{storey_name.gsub(' ','_')}"
        updated_system_zones_map[sys_name] = [] if !updated_system_zones_map.has_key? sys_name
        updated_system_zones_map[sys_name] += zones
      end
    end

    return updated_system_zones_map
  end

  # =============================================================================================================================
  # The first 5 letters of the air loop name designate the system type (sys_abbr). This method updates the system type designation
  # in the air loop name. At the same time the chosen air loop names are checked to avoid duplicate names from being used in the
  # hash for system to zones.
  def update_system_zones_map_keys(system_zones_map,sys_abbr)
    updated_system_zones_map = {}
    system_zones_map.each do |sname,zones|
      updated_sys_name = "#{sys_abbr}#{sname[5..-1]}"
      if !updated_system_zones_map.has_key? updated_sys_name
        updated_system_zones_map[updated_sys_name] = zones
      else
        updated_sys_name_set = false
        index = 1
        while !updated_sys_name_set
          updated_sys_name = "#{sys_abbr}#{sname[5..-1]}"
          updated_sys_name.chop! if updated_sys_name.split.size > 1
          updated_sys_name = updated_sys_name + index.to_s
          if !updated_system_zones_map.has_key? updated_sys_name
            updated_sys_name_set = true
            updated_system_zones_map[updated_sys_name] = zones
          end
          index += 1
        end
      end
    end

    return updated_system_zones_map
  end

  # =============================================================================================================================
  # Add equipment for ECM 'hs08_ccashp_vrf':
  #   -Constant-volume DOAS with air-source heat pump for heating and cooling and electric backup
  #   -Zonal terminal VRF units connected to an outdoor VRF condenser unit
  #   -Zonal electric or hot-water backup
  def add_ecm_hs08_ccashp_vrf(
    model:,
    system_zones_map:,
    system_doas_flags:,
    ecm_system_zones_map_option:,
    standard:,
    air_sys_eqpt_type: 'ccashp')

    # Get the heating fuel type from the system fuels object defined by the standards object
    heating_fuel = standard.fuel_type_set.ecm_fueltype

    # Create one hot-water loop for hot-water baseboards if required
    hw_loop = nil
    hw_loop = add_hotwater_loop(model: model, fuel_type_set: standard.fuel_type_set) if standard.fuel_type_set.baseboard_type == 'Hot Water' || standard.fuel_type_set.force_airloop_hot_water

    # Update system zones map if needed
    system_zones_map = update_system_zones_map_keys(system_zones_map,'sys_1')
    system_zones_map = update_system_zones_map(model,system_zones_map,ecm_system_zones_map_option,'sys_1') if ecm_system_zones_map_option != 'NECB_Default'
    # Add outdoor VRF unit
    outdoor_vrf_unit = add_outdoor_vrf_unit(model: model, ecm_name: 'hs08_ccashp_vrf')
    eqpt_name = 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit'
    airconditioner_variablerefrigerantflow_cooling_apply_curves(outdoor_vrf_unit,eqpt_name)
    airconditioner_variablerefrigerantflow_heating_apply_curves(outdoor_vrf_unit,eqpt_name)
    # Update system doas flags
    system_doas_flags = {}
    system_zones_map.keys.each { |sname| system_doas_flags[sname] = true }

    # use system zones map and generate new air system and zonal equipment
    system_zones_map.sort.each do |sys_name, zones|
      sys_info = air_sys_comps_assumptions(sys_name: sys_name,
                                           zones: zones,
                                           system_doas_flags: system_doas_flags)
      sys_supp_htg_eqpt_type = 'coil_electric'
      sys_supp_htg_eqpt_type = 'coil_gas' if heating_fuel == 'NaturalGas'
      sys_supp_htg_eqpt_type = 'coil_hw' if standard.fuel_type_set.force_airloop_hot_water
      airloop,clg_dx_coil,htg_dx_coil,return_fan = add_air_system(model: model,
                                           zones: zones,
                                           sys_abbr: sys_info['sys_abbr'],
                                           sys_vent_type: sys_info['sys_vent_type'],
                                           sys_heat_rec_type: sys_info['sys_heat_rec_type'],
                                           sys_htg_eqpt_type: air_sys_eqpt_type,
                                           sys_supp_htg_eqpt_type: sys_supp_htg_eqpt_type,
                                           sys_clg_eqpt_type: air_sys_eqpt_type,
                                           sys_supp_fan_type: sys_info['sys_supp_fan_type'],
                                           sys_ret_fan_type: sys_info['sys_ret_fan_type'],
                                           sys_setpoint_mgr_type: sys_info['sys_setpoint_mgr_type'],
                                           hw_loop: hw_loop)
      # Appy performance curves
      if air_sys_eqpt_type == 'ccashp'
        eqpt_name = 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit RTU'
        coil_cooling_dx_variable_speed_apply_curves(clg_dx_coil, eqpt_name)
        coil_heating_dx_variable_speed_apply_curves(htg_dx_coil, eqpt_name)
      elsif air_sys_eqpt_type == 'ashp'
        eqpt_name = 'NECB2015_ASHP'
        coil_cooling_dx_single_speed_apply_curves(clg_dx_coil, eqpt_name)
        coil_heating_dx_single_speed_apply_curves(htg_dx_coil, eqpt_name)
      else
        raise("add_ecm_hs08_ccashp_vrf: The air system equipment type is neither an ashp nor a ccashp")
      end
      # add zone equipment and diffuser
      # add terminal VRF units
      add_zone_eqpt(model: model,
                    airloop: airloop,
                    zones: zones,
                    outdoor_unit: outdoor_vrf_unit,
                    zone_diffuser_type: sys_info['zone_diffuser_type'],
                    zone_htg_eqpt_type: 'vrf',
                    zone_supp_htg_eqpt_type: 'none',
                    zone_clg_eqpt_type: 'vrf',
                    zone_fan_type: 'On_Off',
                    hw_loop: hw_loop)
      # add electric or hot-water baseboards for backup; Type of baseboard follows the primary heating fuel used in the building model.
      zone_htg_eqpt_type = 'baseboard_hotwater' if standard.fuel_type_set.baseboard_type == 'Hot Water'
      zone_htg_eqpt_type = 'baseboard_electric' if standard.fuel_type_set.baseboard_type == 'Electric'

      add_zone_eqpt(model: model,
                    airloop: airloop,
                    zones: zones,
                    outdoor_unit: nil,
                    zone_diffuser_type: nil,
                    zone_htg_eqpt_type: zone_htg_eqpt_type,
                    zone_supp_htg_eqpt_type: 'none',
                    zone_clg_eqpt_type: 'none',
                    zone_fan_type: 'none',
                    hw_loop: hw_loop)
      # Now we can find and apply maximum horizontal and vertical distances between outdoor vrf unit and zones with vrf terminal units
      max_hor_pipe_length, max_vert_pipe_length = get_max_vrf_pipe_lengths(model)
      outdoor_vrf_unit.setEquivalentPipingLengthusedforPipingCorrectionFactorinCoolingMode(max_hor_pipe_length)
      outdoor_vrf_unit.setEquivalentPipingLengthusedforPipingCorrectionFactorinHeatingMode(max_hor_pipe_length)
      outdoor_vrf_unit.setVerticalHeightusedforPipingCorrectionFactor(max_vert_pipe_length)
    end
  end

  # =============================================================================================================================
  # Apply efficiencies for ECM 'hs08_ccashp_vrf'
  def apply_efficiency_ecm_hs08_ccashp_vrf(model, standard, air_sys_eqpt_type: 'ccashp')
    # Use same performance data as ECM 'hs09_ccashpsys' for air system
    if air_sys_eqpt_type == 'ccashp'
      apply_efficiency_ecm_hs09_ccashp_baseboard(model,standard)
    elsif air_sys_eqpt_type == 'ashp'
      apply_efficiency_ecm_hs12_ashp_baseboard(model,standard)
    end
    # Apply efficiency for VRF units
    eqpt_name = 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit'
    search_criteria = {}
    search_criteria['name'] = eqpt_name
    model.getAirConditionerVariableRefrigerantFlows.sort.each do |vrf_unit|
      airconditioner_variablerefrigerantflow_cooling_apply_cop(vrf_unit, search_criteria)
      airconditioner_variablerefrigerantflow_heating_apply_cop(vrf_unit, search_criteria)
    end
    # Set fan size of VRF terminal units
    fan_power_per_flow_rate = 150.0 # based on Mitsubishi data: 100 low and 200 high (W-s/m3)
    model.getZoneHVACTerminalUnitVariableRefrigerantFlows.each do |iunit|
      fan = iunit.supplyAirFan.to_FanOnOff.get
      fan_pr_rise = fan_power_per_flow_rate * (fan.fanEfficiency * fan.motorEfficiency)
      fan.setPressureRise(fan_pr_rise)
    end
    # Set fan size of unit heaters
    model.getZoneHVACUnitHeaters.each do |iunit|
      fan = iunit.supplyAirFan.to_FanConstantVolume.get
      fan_pr_rise = fan_power_per_flow_rate * (fan.fanEfficiency * fan.motorEfficiency)
      fan.setPressureRise(fan_pr_rise)
    end

  end

  # =============================================================================================================================
  # create air loop
  def create_airloop(model, sys_vent_type)
    airloop = OpenStudio::Model::AirLoopHVAC.new(model)
    airloop.sizingSystem.setPreheatDesignTemperature(7.0)
    airloop.sizingSystem.setPreheatDesignHumidityRatio(0.008)
    airloop.sizingSystem.setPrecoolDesignTemperature(13.0)
    airloop.sizingSystem.setPrecoolDesignHumidityRatio(0.008)
    airloop.sizingSystem.setSizingOption('NonCoincident')
    airloop.sizingSystem.setCoolingDesignAirFlowMethod('DesignDay')
    airloop.sizingSystem.setCoolingDesignAirFlowRate(0.0)
    airloop.sizingSystem.setHeatingDesignAirFlowMethod('DesignDay')
    airloop.sizingSystem.setHeatingDesignAirFlowRate(0.0)
    airloop.sizingSystem.setSystemOutdoorAirMethod('ZoneSum')
    airloop.sizingSystem.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
    airloop.sizingSystem.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
    if model.version < OpenStudio::VersionString.new('2.7.0')
      airloop.sizingSystem.setMinimumSystemAirFlowRatio(1.0)
    else
      airloop.sizingSystem.setCentralHeatingMaximumSystemAirFlowRatio(1.0)
    end
    case sys_vent_type.downcase
    when 'doas'
      airloop.sizingSystem.setAllOutdoorAirinCooling(true)
      airloop.sizingSystem.setAllOutdoorAirinHeating(true)
      airloop.sizingSystem.setTypeofLoadtoSizeOn('VentilationRequirement')
      airloop.sizingSystem.setCentralCoolingDesignSupplyAirTemperature(13.0)
      airloop.sizingSystem.setCentralHeatingDesignSupplyAirTemperature(22.0)
    when 'mixed'
      airloop.sizingSystem.setAllOutdoorAirinCooling(false)
      airloop.sizingSystem.setAllOutdoorAirinHeating(false)
      airloop.sizingSystem.setTypeofLoadtoSizeOn('Sensible')
      airloop.sizingSystem.setCentralCoolingDesignSupplyAirTemperature(13.0)
      airloop.sizingSystem.setCentralHeatingDesignSupplyAirTemperature(43.0)
    end

    return airloop
  end

  # =============================================================================================================================
  # create air system setpoint manager
  def create_air_sys_spm(model,
                         setpoint_mgr_type,
                         zones)
    spm = nil
    case setpoint_mgr_type.downcase
    when 'scheduled'
      sat = 20.0
      sat_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      sat_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), sat)
      spm = OpenStudio::Model::SetpointManagerScheduled.new(model, sat_sch)
    when 'single_zone_reheat'
      spm = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
      spm.setControlZone(zones[0])
      spm.setMinimumSupplyAirTemperature(13.0)
      spm.setMaximumSupplyAirTemperature(43.0)
    when 'warmest'
      spm = OpenStudio::Model::SetpointManagerWarmest.new(model)
      spm.setMinimumSetpointTemperature(13.0)
      spm.setMaximumSetpointTemperature(22.0)
    end

    return spm
  end

  # =============================================================================================================================
  # create air system fan
  def create_air_sys_fan(model, fan_type)
    fan = nil
    case fan_type.downcase
    when 'constant_volume'
      fan = OpenStudio::Model::FanConstantVolume.new(model)
      fan.setName('FanConstantVolume')
    when 'variable_volume'
      fan = OpenStudio::Model::FanVariableVolume.new(model)
      fan.setName('FanVariableVolume')
    when 'on_off'
      fan = OpenStudio::Model::FanOnOff.new(model)
      fan.setName('FanOnOff')
    end

    return fan
  end

  # =============================================================================================================================
  # create air system cooling equipment
  def create_air_sys_clg_eqpt(model, clg_eqpt_type)
    clg_eqpt = nil
    case clg_eqpt_type.downcase
    when 'ashp'
      clg_eqpt = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
      clg_eqpt.setName('CoilCoolingDxSingleSpeed_ASHP')
      clg_eqpt.setCrankcaseHeaterCapacity(1.0e-6)
    when 'ccashp'
      clg_eqpt = OpenStudio::Model::CoilCoolingDXVariableSpeed.new(model)
      clg_eqpt.setName('CoilCoolingDXVariableSpeed_CCASHP')
      clg_eqpt_speed1 = OpenStudio::Model::CoilCoolingDXVariableSpeedSpeedData.new(model)
      clg_eqpt.addSpeed(clg_eqpt_speed1)
      clg_eqpt.setNominalSpeedLevel(1)
      clg_eqpt.setCrankcaseHeaterCapacity(1.0e-6)
    when 'coil_chw'
      clg_eqpt = OpenStudio::Model::CoilCoolingWater.new(model)
      clg_eqpt.setName('CoilCoolingWater')
    when 'vrf'
      clg_eqpt = OpenStudio::Model::CoilCoolingDXVariableRefrigerantFlow.new(model)
      clg_eqpt.setName('CoilCoolingDXVariableRefrigerantFlow')
    end

    return clg_eqpt
  end

  # =============================================================================================================================
  # create air system heating equipment
  def create_air_sys_htg_eqpt(model, htg_eqpt_type, hw_loop = nil)
    always_on = model.alwaysOnDiscreteSchedule
    htg_eqpt = nil
    case htg_eqpt_type.downcase
    when 'coil_electric'
      htg_eqpt = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      htg_eqpt.setName('CoilHeatingElectric')
    when 'coil_gas'
      htg_eqpt = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
      htg_eqpt.setName('CoilHeatingGas')
    when 'ashp'
      htg_eqpt = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
      htg_eqpt.setName('CoilHeatingDXSingleSpeed_ASHP')
      htg_eqpt.setDefrostStrategy('ReverseCycle')
      htg_eqpt.setDefrostControl('OnDemand')
      htg_eqpt.setCrankcaseHeaterCapacity(1.0e-6)
    when 'ccashp'
      htg_eqpt = OpenStudio::Model::CoilHeatingDXVariableSpeed.new(model)
      htg_eqpt.setName('CoilHeatingDXVariableSpeed_CCASHP')
      htg_eqpt_speed1 = OpenStudio::Model::CoilHeatingDXVariableSpeedSpeedData.new(model)
      htg_eqpt.addSpeed(htg_eqpt_speed1)
      htg_eqpt.setNominalSpeedLevel(1)
      htg_eqpt.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-25.0)
      htg_eqpt.setDefrostStrategy('ReverseCycle')
      htg_eqpt.setDefrostControl('OnDemand')
      htg_eqpt.setCrankcaseHeaterCapacity(1.0e-6)
    when 'coil_hw'
      htg_eqpt = OpenStudio::Model::CoilHeatingWater.new(model)
      htg_eqpt.setName('CoilHeatingWater')
      hw_loop.addDemandBranchForComponent(htg_eqpt) unless hw_loop.nil?
    end

    return htg_eqpt
  end

  # =============================================================================================================================
  # add air system with all its components
  def add_air_system(model:,
                     zones:,
                     sys_abbr:,
                     sys_vent_type:,
                     sys_heat_rec_type:,
                     sys_htg_eqpt_type:,
                     sys_supp_htg_eqpt_type:,
                     sys_clg_eqpt_type:,
                     sys_supp_fan_type:,
                     sys_ret_fan_type:,
                     sys_setpoint_mgr_type:,
                     hw_loop: nil)

    # create all the needed components and the air loop
    airloop = create_airloop(model, sys_vent_type)
    setpoint_mgr = create_air_sys_spm(model, sys_setpoint_mgr_type, zones)
    supply_fan = create_air_sys_fan(model, sys_supp_fan_type)
    supply_fan.setName('Supply Fan') if supply_fan
    return_fan = create_air_sys_fan(model, sys_ret_fan_type)
    return_fan.setName('Return Fan') if return_fan
    htg_eqpt = create_air_sys_htg_eqpt(model, sys_htg_eqpt_type)
    supp_htg_eqpt = create_air_sys_htg_eqpt(model, sys_supp_htg_eqpt_type, hw_loop)
    clg_eqpt = create_air_sys_clg_eqpt(model, sys_clg_eqpt_type)
    # add components to the air loop
    clg_eqpt.addToNode(airloop.supplyOutletNode) if clg_eqpt
    htg_eqpt.addToNode(airloop.supplyOutletNode) if htg_eqpt
    supp_htg_eqpt.addToNode(airloop.supplyOutletNode) if supp_htg_eqpt
    supply_fan.addToNode(airloop.supplyOutletNode) if supply_fan
    setpoint_mgr.addToNode(airloop.supplyOutletNode) if setpoint_mgr

    # OA controller
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.addToNode(airloop.supplyInletNode)

    # Set airloop name
    sys_name_pars = {}
    sys_name_pars['sys_hr'] = 'none'
    sys_name_pars['sys_clg'] = sys_clg_eqpt_type
    sys_name_pars['sys_htg'] = sys_htg_eqpt_type
    sys_name_pars['sys_sf'] = 'cv' if sys_supp_fan_type == 'constant_volume'
    sys_name_pars['sys_sf'] = 'vv' if sys_supp_fan_type == 'variable_volume'
    sys_name_pars['zone_htg'] = 'none'
    sys_name_pars['zone_clg'] = 'none'
    sys_name_pars['sys_rf'] = 'none'
    sys_name_pars['sys_rf'] = 'cv' if sys_ret_fan_type == 'constant_volume'
    sys_name_pars['sys_rf'] = 'vv' if sys_ret_fan_type == 'variable_volume'
    assign_base_sys_name( air_loop: airloop,
                          sys_abbr: sys_abbr,
                          sys_oa: sys_vent_type,
                          sys_name_pars: sys_name_pars)
    return airloop, clg_eqpt, htg_eqpt, return_fan
  end

  # =============================================================================================================================
  # create zone diffuser
  def create_zone_diffuser(model, zone_diffuser_type, zone)
    always_on = model.alwaysOnDiscreteSchedule
    diffuser = nil
    case zone_diffuser_type.downcase
    when 'single_duct_uncontrolled'
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
    when 'single_duct_vav_reheat'
      reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      diffuser = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, always_on, reheat_coil)
      # diffuser.setFixedMinimumAirFlowRate(0.002 * zone.floorArea )
      diffuser.setMaximumReheatAirTemperature(43.0)
      diffuser.setDamperHeatingAction('Normal')
    end

    return diffuser
  end

  # =============================================================================================================================
  # create zonal heating equipment
  def create_zone_htg_eqpt(model, zone_htg_eqpt_type, hw_loop)
    always_on = model.alwaysOnDiscreteSchedule
    always_off = model.alwaysOffDiscreteSchedule
    htg_eqpt = nil
    case zone_htg_eqpt_type.downcase
    when 'baseboard_electric'
      htg_eqpt = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
      htg_eqpt.setName('ZoneHVACBaseboardConvectiveElectric')
    when 'baseboard_hotwater'
      htg_coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model)
      htg_coil.setName("CoilHeatingWaterBaseboard")
      hw_loop.addDemandBranchForComponent(htg_coil)
      htg_eqpt = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(model, model.alwaysOnDiscreteSchedule, htg_coil)
      htg_eqpt.setName('ZoneHVACBaseboardConvectiveWater')
    when 'coil_electric', 'ptac_electric_off', 'unitheater_electric'
      htg_eqpt = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      htg_eqpt.setName('CoilHeatingElectric')
      htg_eqpt.setAvailabilitySchedule(always_off) if zone_htg_eqpt_type == 'ptac_electric_off'
    when 'fancoil_4pipe'
      htg_eqpt = OpenStudio::Model::CoilHeatingWater.new(model)
      htg_eqpt.setName('CoilHeatingWater_FanCoil')
    when 'pthp'
      htg_eqpt = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
      htg_eqpt.setName('CoilHeatingDXSingleSpeed_PTHP')
      htg_eqpt.setDefrostStrategy('ReverseCycle')
      htg_eqpt.setDefrostControl('OnDemand')
      htg_eqpt.setCrankcaseHeaterCapacity(1.0e-6)
    when 'vrf'
      htg_eqpt = OpenStudio::Model::CoilHeatingDXVariableRefrigerantFlow.new(model)
      htg_eqpt.setName('CoilHeatingDXVariableRefrigerantFlow')
    end

    return htg_eqpt
  end

  # =============================================================================================================================
  # create zonal cooling equipment
  def create_zone_clg_eqpt(model, zone_clg_eqpt_type)
    always_on = model.alwaysOnDiscreteSchedule
    clg_eqpt = nil
    case zone_clg_eqpt_type.downcase
    when 'fancoil_4pipe'
      clg_eqpt = OpenStudio::Model::CoilCoolingWater.new(model)
      clg_eqpt.setName('CoilCoolingWater_FanCoil')
    when 'ptac_electric_off', 'pthp'
      clg_eqpt = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
      clg_eqpt.setName('CoilCoolingDXSingleSpeed_PTHP') if zone_clg_eqpt_type.downcase == 'pthp'
      clg_eqpt.setName('CoilCoolingDXSingleSpeed_PTAC') if zone_clg_eqpt_type.downcase == 'ptac_electric_off'
      clg_eqpt.setCrankcaseHeaterCapacity(1.0e-6)
    when 'vrf'
      clg_eqpt = OpenStudio::Model::CoilCoolingDXVariableRefrigerantFlow.new(model)
      clg_eqpt.setName('CoilCoolingDXVariableRefrigerantFlow')
    end

    return clg_eqpt
  end

  # =============================================================================================================================
  # create zpne container eqpt
  def create_zone_container_eqpt(model:,
                                 zone_cont_eqpt_type:,
                                 zone_htg_eqpt:,
                                 zone_supp_htg_eqpt:,
                                 zone_clg_eqpt:,
                                 zone_fan:,
                                 zone_vent_off: true)

    always_on = model.alwaysOnDiscreteSchedule
    always_off = model.alwaysOffDiscreteSchedule
    zone_eqpt = nil
    case zone_cont_eqpt_type.downcase
    when 'fancoil_4pipe'
      zone_eqpt = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, always_on, zone_fan, zone_clg_eqpt, zone_htg_eqpt)
      zone_eqpt.setName('ZoneHVACFourPipeFanCoil')
      zone_eqpt.setSupplyAirFanOperatingModeSchedule(always_off)
      zone_eqpt.setMaximumOutdoorAirFlowRate(1.0e-6)
    when 'ptac_electric_off'
      zone_eqpt = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model, always_on, zone_fan, zone_htg_eqpt, zone_clg_eqpt)
      zone_eqpt.setName('ZoneHVACPackagedTerminalAirConditioner')
      zone_eqpt.setSupplyAirFanOperatingModeSchedule(always_off)
      if zone_vent_off
        zone_eqpt.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-6)
        zone_eqpt.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-6)
        zone_eqpt.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-6)
      end
    when 'pthp'
      zone_eqpt = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(model, always_on, zone_fan, zone_htg_eqpt, zone_clg_eqpt, zone_supp_htg_eqpt)
      zone_eqpt.setName('ZoneHVACPackagedTerminalHeatPump')
      if zone_vent_off
        zone_eqpt.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-6)
        zone_eqpt.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-6)
        zone_eqpt.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-6)
        zone_eqpt.setSupplyAirFanOperatingModeSchedule(always_off)
      end
    when 'unitheater_electric'
      zone_eqpt = OpenStudio::Model::ZoneHVACUnitHeater.new(model, always_on, zone_fan, zone_htg_eqpt)
      zone_eqpt.setName('ZoneHVACUnitHeater')
      zone_eqpt.setFanControlType('OnOff')
    when 'vrf'
      zone_eqpt = OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow.new(model, zone_clg_eqpt, zone_htg_eqpt, zone_fan)
      zone_eqpt.setName('ZoneHVACTerminalUnitVariableRefrigerantFlow')
      zone_eqpt.setSupplyAirFanOperatingModeSchedule(always_off)
      if zone_vent_off
        zone_eqpt.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-6)
        zone_eqpt.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-6)
        zone_eqpt.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-6)
        zone_eqpt.setZoneTerminalUnitOffParasiticElectricEnergyUse(1.0e-6)
        zone_eqpt.setZoneTerminalUnitOnParasiticElectricEnergyUse(1.0e-6)
      end
    end

    return zone_eqpt
  end

  # =============================================================================================================================
  # add zonal heating and cooling equipment
  def add_zone_eqpt(model:,
                    airloop:,
                    zones:,
                    outdoor_unit:,
                    zone_diffuser_type:,
                    zone_htg_eqpt_type:,
                    zone_supp_htg_eqpt_type:,
                    zone_clg_eqpt_type:,
                    zone_fan_type:,
                    hw_loop: nil)

    always_on = model.alwaysOnDiscreteSchedule
    zones.sort.each do |zone|
      # during the first call to this method for a zone, the diffuser type has to be specified if there is an air loop serving the zone
      if zone_diffuser_type
        zone.sizingZone.setZoneCoolingDesignSupplyAirTemperature(13.0)
        zone.sizingZone.setZoneHeatingDesignSupplyAirTemperature(43.0)
        zone.sizingZone.setZoneCoolingSizingFactor(1.1)
        zone.sizingZone.setZoneHeatingSizingFactor(1.3)
        diffuser = create_zone_diffuser(model, zone_diffuser_type, zone)
        airloop.removeBranchForZone(zone)
        airloop.addBranchForZone(zone, diffuser.to_StraightComponent)
      end
      clg_eqpt = create_zone_clg_eqpt(model, zone_clg_eqpt_type)
      htg_eqpt = create_zone_htg_eqpt(model, zone_htg_eqpt_type, hw_loop)
      supp_htg_eqpt = create_zone_htg_eqpt(model, zone_supp_htg_eqpt_type, hw_loop)
      fan = create_air_sys_fan(model, zone_fan_type)
      # for container zonal equipment call method "create_zone_container_equipment"
      this_is_container_comp = false
      if (zone_htg_eqpt_type == 'pthp') || (zone_htg_eqpt_type == 'vrf') ||
         (zone_htg_eqpt_type.include? 'unitheater') || (zone_htg_eqpt_type.include? 'ptac') ||
         (zone_htg_eqpt_type.include? 'fancoil')
        this_is_container_comp = true
        zone_cont_eqpt = create_zone_container_eqpt(model: model,
                                                    zone_cont_eqpt_type: zone_htg_eqpt_type,
                                                    zone_htg_eqpt: htg_eqpt,
                                                    zone_supp_htg_eqpt: supp_htg_eqpt,
                                                    zone_clg_eqpt: clg_eqpt,
                                                    zone_fan: fan)
      end
      if zone_cont_eqpt
        zone_cont_eqpt.addToThermalZone(zone)
        outdoor_unit.addTerminal(zone_cont_eqpt) if outdoor_unit
      elsif htg_eqpt && !this_is_container_comp
        htg_eqpt.addToThermalZone(zone)
      end
    end
    sys_name_zone_htg_eqpt_type = zone_htg_eqpt_type
    sys_name_zone_htg_eqpt_type = 'b-e' if zone_htg_eqpt_type == 'baseboard_electric' || zone_htg_eqpt_type == 'ptac_electric_off'
    sys_name_zone_htg_eqpt_type = 'b-hw' if zone_htg_eqpt_type == 'baseboard_hotwater'
    sys_name_zone_clg_eqpt_type = zone_clg_eqpt_type
    sys_name_zone_clg_eqpt_type = 'ptac' if zone_clg_eqpt_type == 'ptac_electric_off'
    update_sys_name(airloop, zone_htg: sys_name_zone_htg_eqpt_type, zone_clg: sys_name_zone_clg_eqpt_type) if zone_diffuser_type
  end

  # =============================================================================================================================
  # add plant loop pump
  def create_plantloop_pump(model, loop_pump_type)

    pump = nil
    case loop_pump_type.downcase
    when "constant_speed"
      pump = OpenStudio::Model::PumpConstantSpeed.new(model)
      pump.setName("PumpConstantSpeed")
    when "variable_speed"
      pump = OpenStudio::Model::PumpVariableSpeed.new(model)
      pump.setName("PumpVariableSpeed")
    end

    return pump
  end

  # =============================================================================================================================
  # add plant loop heating eqpt
  # created by: kamel.haddad@nrcan-rncan.gc.ca (August 2021)
  def create_plantloop_htg_eqpt(model, loop_htg_eqpt_type)

    htg_eqpt = nil
    case loop_htg_eqpt_type.downcase
    when "district_heating"
      if model.version < OpenStudio::VersionString.new('3.7.0')
        htg_eqpt = OpenStudio::Model::DistrictHeating.new(model)
      else
        htg_eqpt = OpenStudio::Model::DistrictHeatingWater.new(model)
      end
      htg_eqpt.setName("DistrictHeating")

    when "heatpump_watertowater_equationfit"
      htg_eqpt = OpenStudio::Model::HeatPumpWaterToWaterEquationFitHeating.new(model)
      htg_eqpt.setName("HeatPumpWaterToWaterEquationFitHeating")
    when "heatpump_plantloop_eir_heating"
      htg_eqpt = OpenStudio::Model::HeatPumpPlantLoopEIRHeating.new(model)
      htg_eqpt.setName("HeatPumpPlantLoopEIRHeating")
    end

    return htg_eqpt
  end

  # =============================================================================================================================
  # add plant loop cooling eqpt
  def create_plantloop_clg_eqpt(model, loop_clg_eqpt_type)

    clg_eqpt = nil
    case loop_clg_eqpt_type.downcase
    when "chiller_electric_eir"
      clg_eqpt = OpenStudio::Model::ChillerElectricEIR.new(model)
      clg_eqpt.setName("ChillerElectricEIR")
    when "district_cooling"
      clg_eqpt = OpenStudio::Model::DistrictCooling.new(model)
      clg_eqpt.setName("DistrictCooling")
    when "heatpump_watertowater_equationfit"
      clg_eqpt = OpenStudio::Model::HeatPumpWaterToWaterEquationFitCooling.new(model)
      clg_eqpt.setName("HeatPumpWaterToWaterEquationFitCooling")
    when "heatpump_plantloop_eir_cooling"
      clg_eqpt = OpenStudio::Model::HeatPumpPlantLoopEIRCooling.new(model)
      clg_eqpt.setName("HeatPumpPlantLoopEIRCooling")
    end

    return clg_eqpt

  end

  # =============================================================================================================================
  # add plant loop setpoint manager
  def create_plantloop_spm( model, loop_spm_type, loop_setpoint)

    spm = nil
    case loop_spm_type.downcase
    when "scheduled"
      sch = OpenStudio::Model::ScheduleConstant.new(model)
      sch.setValue(loop_setpoint)
      spm = OpenStudio::Model::SetpointManagerScheduled.new(model,sch)
      spm.setName("SetpointManagerScheduled")
    when "followgroundtemperature"
      spm = OpenStudio::Model::SetpointManagerFollowGroundTemperature.new(model)
      spm.setReferenceGroundTemperatureObjectType("Site:GroundTemperature:Deep")
      spm.setMinimumSetpointTemperature(0.0)
    end

    return spm
  end

  # =============================================================================================================================
  # add plant loop heat rejection equipment
  def create_plantloop_heat_rej_eqpt(model, loop_heat_rej_eqpt_type)

    heat_rej_eqpt = nil
    case loop_heat_rej_eqpt_type.downcase
    when "tower_single_speed"
      heat_rej_eqpt = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
      heat_rej_eqpt.setName("CoolingTowerSingleSpeed")
    when "vertical_ground_hx"
      heat_rej_eqpt = OpenStudio::Model::GroundHeatExchangerVertical.new(model)
      heat_rej_eqpt.setName("GroundHeatExchangerVertical")
    when "district_heating"
      if model.version < OpenStudio::VersionString.new('3.7.0')
        heat_rej_eqpt = OpenStudio::Model::DistrictHeating.new(model)
      else
        heat_rej_eqpt = OpenStudio::Model::DistrictHeatingWater.new(model)
      end
      heat_rej_eqpt.setName("DistrictHeating")
    when "district_cooling"
      heat_rej_eqpt = OpenStudio::Model::DistrictCooling.new(model)
      heat_rej_eqpt.setName("DistrictCooling")
    end

    return heat_rej_eqpt
  end

  # =============================================================================================================================
  # add plant loop with all its components
  def add_plantloop(model:,
                    loop_htg_eqpt_type:,
                    loop_clg_eqpt_type:,
                    loop_heat_rej_eqpt_type:,
                    loop_pump_type:,
                    loop_spm_type:,
                    loop_setpoint:,
                    loop_temp_diff:)

    # create all the needed components and the plant loop
    plantloop = OpenStudio::Model::PlantLoop.new(model)
    spm = create_plantloop_spm(model, loop_spm_type, loop_setpoint)
    pump = create_plantloop_pump(model, loop_pump_type)
    htg_eqpt = create_plantloop_htg_eqpt(model, loop_htg_eqpt_type)
    clg_eqpt = create_plantloop_clg_eqpt(model, loop_clg_eqpt_type)
    heat_rej_eqpt = create_plantloop_heat_rej_eqpt(model, loop_heat_rej_eqpt_type)
    if heat_rej_eqpt.nil?
      if !htg_eqpt.nil?
        plantloop.sizingPlant.setLoopType('Heating')
        plantloop.setName("HW PlantLoop")
        eqpt = htg_eqpt
      elsif !clg_eqpt.nil?
        plantloop.sizingPlant.setLoopType('Cooling')
        plantloop.setName("CHW PlantLoop")
        eqpt = clg_eqpt
      end
    elsif !heat_rej_eqpt.nil?
      plantloop.sizingPlant.setLoopType('Condenser')
      plantloop.setName("Condenser PlantLoop")
      eqpt = heat_rej_eqpt
    end
    plantloop.sizingPlant.setDesignLoopExitTemperature(loop_setpoint) if loop_setpoint != 'none'
    plantloop.sizingPlant.setLoopDesignTemperatureDifference(loop_temp_diff) if loop_temp_diff != 'none'
    bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_inlet_node = plantloop.supplyInletNode
    supply_outlet_node = plantloop.supplyOutletNode
    pump.addToNode(supply_inlet_node)
    plantloop.addSupplyBranchForComponent(eqpt)
    plantloop.addSupplyBranchForComponent(bypass_pipe)
    supply_outlet_pipe.addToNode(supply_outlet_node)
    spm.addToNode(supply_outlet_node) if loop_spm_type != 'none'

    return plantloop,eqpt
  end

  # =============================================================================================================================
  # Set assumptions for type of components for air system based on the number of zones served by the system and whether it's
  # a mixed or doas.
  def air_sys_comps_assumptions(sys_name:,
                                zones:,
                                system_doas_flags:)

    sys_info = {}
    sys_info['sys_abbr'] = sys_name.split('|')[0]
    sys_info['sys_vent_type'] = 'mixed'
    sys_info['sys_vent_type'] = 'doas' if system_doas_flags[sys_name.to_s]
    sys_info['sys_heat_rec_type'] = 'none'
    sys_info['sys_htg_eqpt_type'] = 'coil_electric'
    sys_info['sys_supp_htg_eqpt_type'] = 'none'
    sys_info['sys_clg_eqpt_type'] = 'coil_dx'
    if (zones.size == 1) || (sys_info['sys_abbr'] == 'sys_4')
      sys_info['sys_setpoint_mgr_type'] = 'single_zone_reheat'
      sys_info['sys_setpoint_mgr_type'] = 'scheduled' if system_doas_flags[sys_name.to_s]
      sys_info['sys_supp_fan_type'] = 'constant_volume'
      sys_info['sys_ret_fan_type'] = 'none'
      sys_info['zone_diffuser_type'] = 'single_duct_uncontrolled'
    elsif zones.size > 1
      if system_doas_flags[sys_name.to_s]
        sys_info['sys_setpoint_mgr_type'] = 'scheduled'
        sys_info['sys_supp_fan_type'] = 'constant_volume'
        sys_info['sys_ret_fan_type'] = 'none'
        sys_info['zone_diffuser_type'] = 'single_duct_uncontrolled'
      else
        sys_info['sys_setpoint_mgr_type'] = 'warmest'
        sys_info['sys_supp_fan_type'] = 'variable_volume'
        sys_info['sys_ret_fan_type'] = 'variable_volume'
        sys_info['zone_diffuser_type'] = 'single_duct_vav_reheat'
      end
    end

    return sys_info
  end

  # =============================================================================================================================
  # Add equipment for ecm "hs09_ccashp_baseboard":
  #   -Constant-volume reheat system for single zone systems
  #   -VAV system with reheat for non DOAS multi-zone systems
  #   -Cold-climate air-source heat pump for heating and cooling with electric backup
  #   -Electric or hot-water baseboards
  def add_ecm_hs09_ccashp_baseboard(model:,
                                    system_zones_map:,    # hash of ailoop names as keys and array of zones as values
                                    system_doas_flags:,   # hash of system names as keys and flag for DOAS as values
                                    ecm_system_zones_map_option:,
                                    standard:)

    # Get the heating fuel type from the system fuels object defined by the standards object
    heating_fuel = standard.fuel_type_set.ecm_fueltype

    # Create one hot-water loop for hot-water baseboards if required
    hw_loop = nil
    hw_loop = add_hotwater_loop(model: model, fuel_type_set: standard.fuel_type_set) if standard.fuel_type_set.baseboard_type == 'Hot Water' || standard.fuel_type_set.force_airloop_hot_water

    # Set supplemental heating for air loop
    sys_supp_htg_eqpt_type = 'coil_electric'
    sys_supp_htg_eqpt_type = 'coil_gas' if heating_fuel == 'NaturalGas'
    sys_supp_htg_eqpt_type = 'coil_hw' if standard.fuel_type_set.force_airloop_hot_water
    systems = []
    system_zones_map.sort.each do |sys_name, zones|
      sys_info = air_sys_comps_assumptions(sys_name: sys_name,
                                           zones: zones,
                                           system_doas_flags: system_doas_flags)
      # add airloop and its equipment
      airloop,clg_dx_coil,htg_dx_coil,return_fan = add_air_system(
        model: model,
        zones: zones,
        sys_abbr: sys_info['sys_abbr'],
        sys_vent_type: sys_info['sys_vent_type'],
        sys_heat_rec_type: sys_info['sys_heat_rec_type'],
        sys_htg_eqpt_type: 'ccashp',
        sys_supp_htg_eqpt_type: sys_supp_htg_eqpt_type,
        sys_clg_eqpt_type: 'ccashp',
        sys_supp_fan_type: sys_info['sys_supp_fan_type'],
        sys_ret_fan_type: sys_info['sys_ret_fan_type'],
        sys_setpoint_mgr_type: sys_info['sys_setpoint_mgr_type'],
        hw_loop: hw_loop
      )
      # Apply performance curves
      eqpt_name = 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit RTU'
      coil_cooling_dx_variable_speed_apply_curves(clg_dx_coil, eqpt_name)
      coil_heating_dx_variable_speed_apply_curves(htg_dx_coil, eqpt_name)
      # add zone equipment and diffuser
      if sys_info['sys_vent_type'] == 'doas'
        zone_htg_eqpt_type = 'ptac_electric_off'
        zone_clg_eqpt_type = 'ptac_electric_off'
        zone_fan_type = 'on_off'
      else
        zone_htg_eqpt_type = 'baseboard_electric' if standard.fuel_type_set.baseboard_type == 'Electric'
        zone_htg_eqpt_type = 'baseboard_hotwater' if standard.fuel_type_set.baseboard_type == 'Hot Water'
        zone_clg_eqpt_type = 'none'
        zone_fan_type = 'none'
      end
      add_zone_eqpt(model: model,
                    airloop: airloop,
                    zones: zones,
                    outdoor_unit: nil,
                    zone_diffuser_type: sys_info['zone_diffuser_type'],
                    zone_htg_eqpt_type: zone_htg_eqpt_type,
                    zone_supp_htg_eqpt_type: 'none',
                    zone_clg_eqpt_type: zone_clg_eqpt_type,
                    zone_fan_type: zone_fan_type,
                    hw_loop: hw_loop)
      # for doas use baseboard electric or hotwater as backup for PTAC units
      if sys_info['sys_vent_type'] == 'doas'
        zone_htg_eqpt_type = 'baseboard_electric' if standard.fuel_type_set.baseboard_type == 'Electric'
        zone_htg_eqpt_type = 'baseboard_hotwater' if standard.fuel_type_set.baseboard_type == 'Hot Water'
        add_zone_eqpt(model: model,
                      airloop: airloop,
                      zones: zones,
                      outdoor_unit: nil,
                      zone_diffuser_type: nil,
                      zone_htg_eqpt_type: zone_htg_eqpt_type,
                      zone_supp_htg_eqpt_type: 'none',
                      zone_clg_eqpt_type: 'none',
                      zone_fan_type: 'none',
                      hw_loop: hw_loop)
      end
      return_fan.addToNode(airloop.returnAirNode.get) if return_fan
      systems << airloop
    end

    return systems
  end

  # =============================================================================================================================
  # Apply effiencies for ECM "hs09_ccashp_baseboard"
  def apply_efficiency_ecm_hs09_ccashp_baseboard(model,standard)
    # fraction of electric backup heating coil capacity assigned to dx heating coil
    fr_backup_coil_cap_as_dx_coil_cap = 0.5
    model.getAirLoopHVACs.sort.each do |isys|
      clg_dx_coil = nil
      htg_dx_coil = nil
      backup_coil = nil
      fans = []
      # Find the components on the air loop
      isys.supplyComponents.sort.each do |icomp|
        if icomp.to_CoilCoolingDXVariableSpeed.is_initialized
          clg_dx_coil = icomp.to_CoilCoolingDXVariableSpeed.get
        elsif icomp.to_CoilHeatingDXVariableSpeed.is_initialized
          htg_dx_coil = icomp.to_CoilHeatingDXVariableSpeed.get
        elsif icomp.to_CoilHeatingElectric.is_initialized
          backup_coil = icomp.to_CoilHeatingElectric.get
        elsif icomp.to_CoilHeatingGas.is_initialized
          backup_coil = icomp.to_CoilHeatingGas.get
        elsif icomp.to_CoilHeatingWater.is_initialized
          backup_coil = icomp.to_CoilHeatingWater.get
        elsif icomp.to_FanConstantVolume.is_initialized
          fans << icomp.to_FanConstantVolume.get
        elsif icomp.to_FanVariableVolume.is_initialized
          fans << icomp.to_FanVariableVolume.get
        end
      end
      if clg_dx_coil && htg_dx_coil && backup_coil
        clg_dx_coil_init_name = get_hvac_comp_init_name(clg_dx_coil, false)
        clg_dx_coil.setName(clg_dx_coil_init_name)
        if clg_dx_coil.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
          max_pd = 0.0
          supply_fan = nil
          fans.each do |fan|
            if fan.pressureRise.to_f > max_pd
              max_pd = fan.pressureRise.to_f
              supply_fan = fan # assume supply fan has higher pressure drop
            end
          end
          # There is an error in EnergyPlus in the estimated capacity of the coil "CoilCoolingDXVariableSpeed".
          # Here the capacity reported by OS is adjusted to estimate an appropriate capacity for the cooling coil.
          # The autosized capacity is corrected for the actual fan flow rate and fan power.
          if supply_fan.maximumFlowRate.is_initialized
            fan_max_afr = supply_fan.maximumFlowRate.to_f
          elsif supply_fan.autosizedMaximumFlowRate.is_initialized
            fan_max_afr = supply_fan.autosizedMaximumFlowRate.to_f
          else
            raise "Fan flow rate is undefined for fan #{supply_fan.name.to_s}"
          end
          if clg_dx_coil.ratedAirFlowRateAtSelectedNominalSpeedLevel.is_initialized
            clg_dx_coil_afr = clg_dx_coil.ratedAirFlowRateAtSelectedNominalSpeedLevel.to_f
          elsif clg_dx_coil.autosizedRatedAirFlowRateAtSelectedNominalSpeedLevel.is_initialized
            clg_dx_coil_afr = clg_dx_coil.autosizedRatedAirFlowRateAtSelectedNominalSpeedLevel.to_f
          else
            raise "Rated air flow rate at selected nominal speed level is undefined for coil #{clg_dx_coil.name.to_s}"
          end
          fan_power = fan_max_afr * max_pd / supply_fan.fanTotalEfficiency.to_f
          clg_dx_coil_cap = clg_dx_coil.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f *
                            fan_max_afr / clg_dx_coil_afr + fan_power / clg_dx_coil.speeds.last.referenceUnitGrossRatedSensibleHeatRatio.to_f
        elsif clg_dx_coil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
          clg_dx_coil_cap = clg_dx_coil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f
        else
          raise "Rated total cooling capacity at selected nominal speed is undefined for coil #{clg_dx_coil.name.to_s}"
        end
        htg_dx_coil_init_name = get_hvac_comp_init_name(htg_dx_coil, false)
        htg_dx_coil.setName(htg_dx_coil_init_name)
        if (backup_coil.class.name.to_s.include? "CoilHeatingGas") || (backup_coil.class.name.to_s.include? "CoilHeatingElectric")
          if backup_coil.nominalCapacity.is_initialized
            backup_coil_cap = backup_coil.nominalCapacity.to_f
          elsif backup_coil.autosizedNominalCapacity.is_initialized
             backup_coil_cap = backup_coil.autosizedNominalCapacity.to_f
          else
            raise "Nominal capacity is undefiled for coil #{backup_coil.name.to_s}"
          end
        elsif backup_coil.class.name.to_s.include? "CoilHeatingWater"
          if backup_coil.ratedCapacity.is_initialized
            backup_coil_cap = backup_coil.ratedCapacity.to_f
          elsif backup_coil.autosizedRatedCapacity.is_initialized
            backup_coil_cap = backup_coil.autosizedRatedCapacity.to_f
          else
            raise "Rated capacity is undefiled for coil #{backup_coil.name.to_s}"
          end
        else
          raise("Backup coil type is not supported")
        end
        # Set the DX capacities to the maximum of the fraction of the backup coil capacity or the cooling capacity needed
        dx_cap = fr_backup_coil_cap_as_dx_coil_cap * backup_coil_cap
        if dx_cap < clg_dx_coil_cap then dx_cap = clg_dx_coil_cap end
        clg_dx_coil.setGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel(dx_cap)
        htg_dx_coil.setRatedHeatingCapacityAtSelectedNominalSpeedLevel(dx_cap)
        # Assign COPs
        search_criteria = {}
        search_criteria['name'] = 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit RTU'
        coil_cooling_dx_variable_speed_apply_cop(clg_dx_coil, search_criteria, false)
        coil_heating_dx_variable_speed_apply_cop(htg_dx_coil, search_criteria, false)
      end
    end
  end

  # =============================================================================================================================
  # Add equipment for ECM "hs11_ashp_pthp"
  #   -Constant volume DOAS with air-source heat pump for heating and cooling and electric backup
  #   -Packaged-Terminal air-source heat pumps with electric backup
  def add_ecm_hs11_ashp_pthp(model:,
                             system_zones_map:,
                             system_doas_flags:,
                             ecm_system_zones_map_option:,
                             standard:)
    hw_loop = nil
    if standard.fuel_type_set.force_airloop_hot_water || standard.fuel_type_set.necb_reference_hp_supp_fuel.to_s.downcase == "hot water"
      hw_loop = add_hotwater_loop(model: model, fuel_type_set: standard.fuel_type_set)
    end

    # Get the heating fuel type from the system fuels object defined by the standards object
    heating_fuel = standard.fuel_type_set.ecm_fueltype
    # Set supplemental heaing for airloop
    sys_supp_htg_eqpt_type = 'coil_electric'
    sys_supp_htg_eqpt_type = 'coil_gas' if heating_fuel == 'NaturalGas'
    sys_supp_htg_eqpt_type = 'coil_hw' if standard.fuel_type_set.force_airloop_hot_water || standard.fuel_type_set.necb_reference_hp_supp_fuel.to_s.downcase == "hot water"
    # Update system zones map if needed
    system_zones_map = update_system_zones_map_keys(system_zones_map,'sys_1')
    system_zones_map = update_system_zones_map(model,system_zones_map,ecm_system_zones_map_option,'sys_1') if ecm_system_zones_map_option != 'NECB_Default'
    # Update system doas flags
    system_doas_flags = {}
    system_zones_map.keys.each { |sname| system_doas_flags[sname] = true }
    # use system zones map and generate new air system and zonal equipment
    systems = []
    system_zones_map.sort.each do |sys_name, zones|
      sys_info = air_sys_comps_assumptions(sys_name: sys_name,
                                           zones: zones,
                                           system_doas_flags: system_doas_flags)
      airloop,clg_dx_coil,htg_dx_coil,return_fan = add_air_system(model: model,
                                           zones: zones,
                                           sys_abbr: sys_info['sys_abbr'],
                                           sys_vent_type: sys_info['sys_vent_type'],
                                           sys_heat_rec_type: sys_info['sys_heat_rec_type'],
                                           sys_htg_eqpt_type: 'ashp',
                                           sys_supp_htg_eqpt_type: sys_supp_htg_eqpt_type,
                                           sys_clg_eqpt_type: 'ashp',
                                           sys_supp_fan_type: sys_info['sys_supp_fan_type'],
                                           sys_ret_fan_type: sys_info['sys_ret_fan_type'],
                                           sys_setpoint_mgr_type: sys_info['sys_setpoint_mgr_type'],
                                           hw_loop: hw_loop)
      eqpt_name = 'HS11_PTHP'
      coil_cooling_dx_single_speed_apply_curves(clg_dx_coil,eqpt_name)
      coil_heating_dx_single_speed_apply_curves(htg_dx_coil,eqpt_name)
      # add zone equipment and diffuser
      zone_htg_eqpt_type = 'pthp'
      zone_clg_eqpt_type = 'pthp'
      zone_supp_htg_eqpt_type = 'coil_electric'
      zone_fan_type = 'on_off'
      add_zone_eqpt(model: model,
                    airloop: airloop,
                    zones: zones,
                    outdoor_unit: nil,
                    zone_diffuser_type: sys_info['zone_diffuser_type'],
                    zone_htg_eqpt_type: zone_htg_eqpt_type,
                    zone_supp_htg_eqpt_type: zone_supp_htg_eqpt_type,
                    zone_clg_eqpt_type: zone_clg_eqpt_type,
                    zone_fan_type: zone_fan_type,
                    hw_loop: hw_loop)
      zones.each do |zone|
        zone.equipment.each do |comp|
          if comp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
            if comp.to_ZoneHVACPackagedTerminalHeatPump.get.heatingCoil.to_CoilHeatingDXSingleSpeed.is_initialized
              htg_coil = comp.to_ZoneHVACPackagedTerminalHeatPump.get.heatingCoil.to_CoilHeatingDXSingleSpeed.get
              coil_heating_dx_single_speed_apply_curves(htg_coil,eqpt_name)
            end
            if comp.to_ZoneHVACPackagedTerminalHeatPump.get.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized
              clg_coil = comp.to_ZoneHVACPackagedTerminalHeatPump.get.coolingCoil.to_CoilCoolingDXSingleSpeed.get
              coil_cooling_dx_single_speed_apply_curves(clg_coil,eqpt_name)
            end
          end
        end
      end
      return_fan.addToNode(airloop.returnAirNode.get) if return_fan
      systems << airloop
    end

    return systems
  end

  # =============================================================================================================================
  # Apply efficiencies and performance curves for ECM "hs11_ashp_pthp"
  def apply_efficiency_ecm_hs11_ashp_pthp(model,standard)
    fr_backup_coil_cap_as_dx_coil_cap = 0.5 # fraction of electric or hot-water backup heating coil capacity assigned to dx heating coil
    apply_efficiency_ecm_hs12_ashp_baseboard(model,standard)
    pthp_eqpt_name = 'HS11_PTHP'
    model.getAirLoopHVACs.sort.each do |isys|
      isys.thermalZones.each do |zone|
        clg_dx_coil = nil
        htg_dx_coil = nil
        backup_coil = nil
        fan = nil
        zone.equipment.sort.each do |icomp|
          if icomp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
            if icomp.to_ZoneHVACPackagedTerminalHeatPump.get.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized
              clg_dx_coil = icomp.to_ZoneHVACPackagedTerminalHeatPump.get.coolingCoil.to_CoilCoolingDXSingleSpeed.get
            end
            if icomp.to_ZoneHVACPackagedTerminalHeatPump.get.heatingCoil.to_CoilHeatingDXSingleSpeed.is_initialized
              htg_dx_coil = icomp.to_ZoneHVACPackagedTerminalHeatPump.get.heatingCoil.to_CoilHeatingDXSingleSpeed.get
            end
            if icomp.to_ZoneHVACPackagedTerminalHeatPump.get.supplementalHeatingCoil.to_CoilHeatingElectric.is_initialized
              backup_coil = icomp.to_ZoneHVACPackagedTerminalHeatPump.get.supplementalHeatingCoil.to_CoilHeatingElectric.get
            end
            if icomp.to_ZoneHVACPackagedTerminalHeatPump.get.supplyAirFan.to_FanOnOff.is_initialized
              fan = icomp.to_ZoneHVACPackagedTerminalHeatPump.get.supplyAirFan.to_FanOnOff.get
            end
          end
          if clg_dx_coil && htg_dx_coil && backup_coil && fan
            clg_dx_coil_init_name = get_hvac_comp_init_name(clg_dx_coil, false)
            clg_dx_coil.setName(clg_dx_coil_init_name)
            if clg_dx_coil.ratedTotalCoolingCapacity.is_initialized
              clg_dx_coil_cap = clg_dx_coil.ratedTotalCoolingCapacity.to_f
            elsif clg_dx_coil.autosizedRatedTotalCoolingCapacity.is_initialized
              clg_dx_coil_cap = clg_dx_coil.autosizedRatedTotalCoolingCapacity.to_f
            else
              raise "The total cooling capacity is undefined for coil #{clg_dx_coil_cap.name.to_s}"
            end
            htg_dx_coil_init_name = get_hvac_comp_init_name(htg_dx_coil, true)
            htg_dx_coil.setName(htg_dx_coil_init_name)
            if backup_coil.nominalCapacity.is_initialized
              backup_coil_cap = backup_coil.nominalCapacity.to_f
            elsif backup_coil.autosizedNominalCapacity.is_initialized
              backup_coil_cap = backup_coil.autosizedNominalCapacity.to_f
            else
              raise "The nominal capacity is undefined for coil #{backup_coil.name.to_s}"
            end
            # Set the DX capacities to the maximum of the fraction of the backup coil capacity or the cooling capacity needed
            dx_cap = fr_backup_coil_cap_as_dx_coil_cap * backup_coil_cap
            if dx_cap < clg_dx_coil_cap then dx_cap = clg_dx_coil_cap end
            clg_dx_coil.setRatedTotalCoolingCapacity(dx_cap)
            htg_dx_coil.setRatedTotalHeatingCapacity(dx_cap)
            # assign COPs
            search_criteria = {}
            search_criteria['name'] = pthp_eqpt_name
            coil_cooling_dx_single_speed_apply_cop(clg_dx_coil, search_criteria)
            coil_heating_dx_single_speed_apply_cop(htg_dx_coil, search_criteria)
            # Set fan power
            fan_power_per_flow_rate = 150.0 # based on Mitsubishi data: 100 low and 200 high (W-s/m3)
            fan_pr_rise = fan_power_per_flow_rate * (fan.fanEfficiency * fan.motorEfficiency)
            fan.setPressureRise(fan_pr_rise)
          end
        end
      end
    end
  end

  # =============================================================================================================================
  # Add equipment for ecm "hs12_ashp_baseboard":
  #   -Constant-volume reheat system for single zone systems
  #   -VAV system with reheat for non DOAS multi-zone systems
  #   -Air-source heat pump for heating and cooling with electric backup
  #   -Electric or hot-water baseboards
  def add_ecm_hs12_ashp_baseboard(model:,
                                  system_zones_map:,
                                  system_doas_flags:,
                                  ecm_system_zones_map_option:,
                                  standard:)

    # Get the heating fuel type from the system fuels object defined by the standards object
    heating_fuel = standard.fuel_type_set.ecm_fueltype

    # Create one hot-water loop for hot-water baseboards if required
    hw_loop = nil
    hw_loop = add_hotwater_loop(model: model, fuel_type_set: standard.fuel_type_set) if standard.fuel_type_set.baseboard_type == 'Hot Water' || standard.fuel_type_set.force_airloop_hot_water

    # Set supplemental heating fuel for airloop
    sys_supp_htg_eqpt_type = 'coil_electric'
    sys_supp_htg_eqpt_type = 'coil_gas' if heating_fuel == 'NaturalGas'
    sys_supp_htg_eqpt_type = 'coil_hw' if standard.fuel_type_set.force_airloop_hot_water
    systems = []
    system_zones_map.sort.each do |sys_name, zones|
      sys_info = air_sys_comps_assumptions(sys_name: sys_name,
                                           zones: zones,
                                           system_doas_flags: system_doas_flags)
      # add air loop and its equipment
      airloop,clg_dx_coil,htg_dx_coil,return_fan = add_air_system(model: model,
                                           zones: zones,
                                           sys_abbr: sys_info['sys_abbr'],
                                           sys_vent_type: sys_info['sys_vent_type'],
                                           sys_heat_rec_type: sys_info['sys_heat_rec_type'],
                                           sys_htg_eqpt_type: 'ashp',
                                           sys_supp_htg_eqpt_type: sys_supp_htg_eqpt_type,
                                           sys_clg_eqpt_type: 'ashp',
                                           sys_supp_fan_type: sys_info['sys_supp_fan_type'],
                                           sys_ret_fan_type: sys_info['sys_ret_fan_type'],
                                           sys_setpoint_mgr_type: sys_info['sys_setpoint_mgr_type'],
                                           hw_loop: hw_loop)
      eqpt_name = 'NECB2015_ASHP'
      coil_cooling_dx_single_speed_apply_curves(clg_dx_coil,eqpt_name)
      coil_heating_dx_single_speed_apply_curves(htg_dx_coil,eqpt_name)
      # add zone equipment and diffuser
      if sys_info['sys_vent_type'] == 'doas'
        zone_htg_eqpt_type = 'ptac_electric_off'
        zone_clg_eqpt_type = 'ptac_electric_off'
        zone_fan_type = 'on_off'
      else
        zone_htg_eqpt_type = 'baseboard_electric' if standard.fuel_type_set.baseboard_type == 'Electric'
        zone_htg_eqpt_type = 'baseboard_hotwater' if standard.fuel_type_set.baseboard_type == 'Hot Water'
        zone_clg_eqpt_type = 'none'
        zone_fan_type = 'none'
      end
      add_zone_eqpt(model: model,
                    airloop: airloop,
                    zones: zones,
                    outdoor_unit: nil,
                    zone_diffuser_type: sys_info['zone_diffuser_type'],
                    zone_htg_eqpt_type: zone_htg_eqpt_type,
                    zone_supp_htg_eqpt_type: 'none',
                    zone_clg_eqpt_type: zone_clg_eqpt_type,
                    zone_fan_type: zone_fan_type,
                    hw_loop: hw_loop)
      # for doas use baseboard electric or hotwater as backup for PTAC units
      if sys_info['sys_vent_type'] == 'doas'
        zone_htg_eqpt_type = 'baseboard_electric' if standard.fuel_type_set.baseboard_type == 'Electric'
        zone_htg_eqpt_type = 'baseboard_hotwater' if standard.fuel_type_set.baseboard_type == 'Hot Water'
        add_zone_eqpt(model: model,
                      airloop: airloop,
                      zones: zones,
                      outdoor_unit: nil,
                      zone_diffuser_type: nil,
                      zone_htg_eqpt_type: zone_htg_eqpt_type,
                      zone_supp_htg_eqpt_type: 'none',
                      zone_clg_eqpt_type: 'none',
                      zone_fan_type: 'none',
                      hw_loop: hw_loop)
      end
      return_fan.addToNode(airloop.returnAirNode.get) if return_fan
      systems << airloop
    end

    return systems
  end

  # =============================================================================================================================
  # Name of HVAC component might have been updated by standards methods for setting efficiency. Here original name of the component
  # is restored.
  def get_hvac_comp_init_name(obj, htg_flag)
    return obj.name.to_s if obj.name.to_s.split.size <= 2

    init_name = obj.name.to_s.split[0]
    range = obj.name.to_s.split.size - 3
    range = obj.name.to_s.split.size - 5 if htg_flag
    for i in 1..range
      init_name += " #{obj.name.to_s.split[i]}"
    end
    return init_name
  end

  # =============================================================================================================================
  # Apply efficiencies and performance curves for ECM "hs12_ashp_baseboard"
  def apply_efficiency_ecm_hs12_ashp_baseboard(model,standard)
    fr_backup_coil_cap_as_dx_coil_cap = 0.5 # fraction of electric backup heating coil capacity assigned to dx heating coil
    ashp_eqpt_name = 'NECB2015_ASHP'
    model.getAirLoopHVACs.sort.each do |isys|
      clg_dx_coil = nil
      htg_dx_coil = nil
      backup_coil = nil
      # Find the coils on the air loop
      isys.supplyComponents.sort.each do |icomp|
        if icomp.to_CoilCoolingDXSingleSpeed.is_initialized
          clg_dx_coil = icomp.to_CoilCoolingDXSingleSpeed.get
        elsif icomp.to_CoilHeatingDXSingleSpeed.is_initialized
          htg_dx_coil = icomp.to_CoilHeatingDXSingleSpeed.get
        elsif icomp.to_CoilHeatingElectric.is_initialized
          backup_coil = icomp.to_CoilHeatingElectric.get
        elsif icomp.to_CoilHeatingGas.is_initialized
          backup_coil = icomp.to_CoilHeatingGas.get
        elsif icomp.to_CoilHeatingWater.is_initialized
          backup_coil = icomp.to_CoilHeatingWater.get
        end
      end
      if clg_dx_coil && htg_dx_coil && backup_coil
        # update names of dx coils
        clg_dx_coil_init_name = get_hvac_comp_init_name(clg_dx_coil, false)
        clg_dx_coil.setName(clg_dx_coil_init_name)
        if clg_dx_coil.ratedTotalCoolingCapacity.is_initialized
          clg_dx_coil_cap = clg_dx_coil.ratedTotalCoolingCapacity.to_f
        elsif clg_dx_coil.autosizedRatedTotalCoolingCapacity.is_initialized
          clg_dx_coil_cap = clg_dx_coil.autosizedRatedTotalCoolingCapacity.to_f
        else
          raise "Rated total cooling capacity is undefined for coil #{clg_dx_coil.name.to_s}"
        end
        htg_dx_coil_init_name = get_hvac_comp_init_name(htg_dx_coil, true)
        htg_dx_coil.setName(htg_dx_coil_init_name)
        if (backup_coil.class.name.include? "CoilHeatingElectric") || (backup_coil.class.name.include? "CoilHeatingGas")
          if backup_coil.nominalCapacity.is_initialized
            backup_coil_cap = backup_coil.nominalCapacity.to_f
          elsif backup_coil.autosizedNominalCapacity.is_initialized
            backup_coil_cap = backup_coil.autosizedNominalCapacity.to_f
          else
            raise "Nominal capacity is undefined for coil #{backup_coil.name.to_s}"
          end
        elsif backup_coil.class.name.include? "CoilHeatingWater"
          if backup_coil.ratedCapacity.is_initialized
            backup_coil_cap = backup_coil.ratedCapacity.to_f
          elsif backup_coil.autosizedRatedCapacity.is_initialized
            backup_coil_cap = backup_coil.autosizedRatedCapacity.to_f
          else
            raise "Rated capacity is undefined for coil #{backup_coil.name.to_s}"
          end
        else
          raise("Backup coil type is not supported")
        end
        # set the DX capacities to the maximum of the fraction of the backup coil capacity or the cooling capacity needed
        dx_cap = fr_backup_coil_cap_as_dx_coil_cap * backup_coil_cap
        if dx_cap < clg_dx_coil_cap then dx_cap = clg_dx_coil_cap end
        clg_dx_coil.setRatedTotalCoolingCapacity(dx_cap)
        htg_dx_coil.setRatedTotalHeatingCapacity(dx_cap)
        # assign COPs
        search_criteria = {}
        search_criteria['name'] = ashp_eqpt_name
        coil_cooling_dx_single_speed_apply_cop(clg_dx_coil, search_criteria)
        coil_heating_dx_single_speed_apply_cop(htg_dx_coil, search_criteria)
      end
    end
  end

  # =============================================================================================================================
  # Add equipment for ecm "hs13_ashp_vrf":
  #   -Constant-volume dedicated-outside air system
  #   -Air-source heat pump for heating and cooling with electric backup
  #   -Zonal VRF terminal units for heating and cooling with electric baseboards
  def add_ecm_hs13_ashp_vrf(model:,
                            system_zones_map:,
                            system_doas_flags:,
                            ecm_system_zones_map_option:,
                            standard:)
    # call method for ECM hs08 with ASHP in the air system
    add_ecm_hs08_ccashp_vrf(model: model,
                            system_zones_map: system_zones_map,
                            system_doas_flags: system_doas_flags,
                            ecm_system_zones_map_option: ecm_system_zones_map_option,
                            standard: standard,
                            air_sys_eqpt_type: 'ashp')
  end

  # =============================================================================================================================
  # Apply efficiencies and performance curves for ECM "hs12_ashp_vrf"
  def apply_efficiency_ecm_hs13_ashp_vrf(model,standard)
    # call method for ECM hs08 with ASHP in air system
    apply_efficiency_ecm_hs08_ccashp_vrf(model, standard, air_sys_eqpt_type: 'ashp')
  end

  # =============================================================================================================================
  # Add equipment for ECM "hs14_cgshp_fancoils"
  #   -Constant volume DOAS with hydronic htg and clg coils.
  #   -Zonal terminal fan coil (4-pipe) connected to central ground-source heat pump.
  #   -Plant has a heating loop with water-to-water heat pump with a backup boiler. It also has a water-cooled chiller with a
  #    backup air-cooled chiller. Water-source heat pump and water-cooled chiller are connected to a ground-loop.
  def add_ecm_hs14_cgshp_fancoils(model:,
                                  system_zones_map:,
                                  system_doas_flags:,
                                  ecm_system_zones_map_option:,
                                  standard:)

    # Get the heating fuel type from the system fuels object defined by the standards object
    heating_fuel = standard.fuel_type_set.ecm_fueltype

    # Set supplemental heaing for airloop
    sys_supp_htg_eqpt_type = 'coil_electric'
    sys_supp_htg_eqpt_type = 'coil_gas' if heating_fuel == 'NaturalGas'
    # Update system zones map if needed
    system_zones_map = update_system_zones_map_keys(system_zones_map,'sys_1')
    system_zones_map = update_system_zones_map(model,system_zones_map,ecm_system_zones_map_option,'sys_1') if ecm_system_zones_map_option != 'NECB_Default'
    # Update system doas flags
    system_doas_flags = {}
    system_zones_map.keys.each { |sname| system_doas_flags[sname] = true }
    # use system zones map and generate new air system and zonal equipment
    systems = []
    system_zones_map.sort.each do |sys_name, zones|
      sys_info = air_sys_comps_assumptions(sys_name: sys_name,
                                           zones: zones,
                                           system_doas_flags: system_doas_flags)
      airloop,clg_coil,htg_coil,return_fan = add_air_system(model: model,
                                           zones: zones,
                                           sys_abbr: sys_info['sys_abbr'],
                                           sys_vent_type: sys_info['sys_vent_type'],
                                           sys_heat_rec_type: sys_info['sys_heat_rec_type'],
                                           sys_htg_eqpt_type: 'coil_hw',
                                           sys_supp_htg_eqpt_type: 'none',
                                           sys_clg_eqpt_type: 'coil_chw',
                                           sys_supp_fan_type: sys_info['sys_supp_fan_type'],
                                           sys_ret_fan_type: sys_info['sys_ret_fan_type'],
                                           sys_setpoint_mgr_type: 'warmest')

      # add zone equipment and diffuser
      zone_htg_eqpt_type = 'fancoil_4pipe'
      zone_clg_eqpt_type = 'fancoil_4pipe'
      zone_supp_htg_eqpt_type = 'none'
      zone_fan_type = 'on_off'
      add_zone_eqpt(model: model,
                    airloop: airloop,
                    zones: zones,
                    outdoor_unit: nil,
                    zone_diffuser_type: sys_info['zone_diffuser_type'],
                    zone_htg_eqpt_type: zone_htg_eqpt_type,
                    zone_supp_htg_eqpt_type: zone_supp_htg_eqpt_type,
                    zone_clg_eqpt_type: zone_clg_eqpt_type,
                    zone_fan_type: zone_fan_type)

      return_fan.addToNode(airloop.returnAirNode.get) if return_fan
      systems << airloop
    end

    # add hot-water loop
    hw_loop,hw_loop_htg_eqpt = add_plantloop(model: model,
                                             loop_htg_eqpt_type: 'HeatPump_WaterToWater_EquationFit',
                                             loop_clg_eqpt_type: 'none',
                                             loop_heat_rej_eqpt_type: 'none',
                                             loop_pump_type: 'variable_speed',
                                             loop_spm_type: 'Scheduled',
                                             loop_setpoint: 60.0,
                                             loop_temp_diff: 5.0)
    model.getCoilHeatingWaters.sort.each {|coil| hw_loop.addDemandBranchForComponent(coil)}
    hcapf_curve_name = "HEATPUMP_WATERTOWATER_HCAPF"
    hcapf_curve = model_add_curve(model, hcapf_curve_name)
    if hcapf_curve
      hw_loop_htg_eqpt.setHeatingCapacityCurve(hcapf_curve)
    else
      raise("Can not find curve hcapf for  #{hw_loop_htg_eqpt.name}")
    end
    hpowerf_curve_name = "HEATPUMP_WATERTOWATER_HPOWERF"
    hpowerf_curve = model_add_curve(model, hpowerf_curve_name)
    if hpowerf_curve
      hw_loop_htg_eqpt.setHeatingCompressorPowerCurve(hpowerf_curve)
    else
      raise("Can not find curve hpowerf for #{hw_loop_htg_eqpt.name}")
    end
    # Add one boiler if the primary and backup boiler fuel types are the same.  Add two boilers if the primary and
    # secondary boiler fuel types differ.
    boiler_fuels = []
    boiler_fuels[0] = standard.fuel_type_set.boiler_fueltype
    boiler_fuels[1] = standard.fuel_type_set.backup_boiler_fueltype unless standard.fuel_type_set.backup_boiler_fueltype == boiler_fuels[0]
    hw_loop_htg_eqpt_outlet_node = hw_loop_htg_eqpt.supplyOutletModelObject.get.to_Node.get
    hw_boilers = []
    boiler_fuels.each do |boiler_fuel|
      boiler = OpenStudio::Model::BoilerHotWater.new(model)
      boiler.setFuelType(boiler_fuel)
      hw_boilers << boiler
    end
    hw_boilers.reverse().each {|boiler| boiler.addToNode(hw_loop_htg_eqpt_outlet_node)}
    # add chilled-water loop
    chw_loop,chw_loop_clg_eqpt = add_plantloop(model: model,
                                               loop_htg_eqpt_type: 'none',
                                               loop_clg_eqpt_type: 'chiller_electric_eir',
                                               loop_heat_rej_eqpt_type: 'none',
                                               loop_pump_type: 'variable_speed',
                                               loop_spm_type: 'Scheduled',
                                               loop_setpoint: 7.0,
                                               loop_temp_diff: 6.0)

    chw_loop_clg_eqpt.setName('ChillerWaterCooled')
    chw_loop_clg_eqpt.setCondenserType("WaterCooled")
    model.getCoilCoolingWaters.sort.each {|coil| chw_loop.addDemandBranchForComponent(coil)}
    sec_chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chw_loop_clg_eqpt_outlet_node = chw_loop_clg_eqpt.supplyOutletModelObject.get.to_Node.get
    sec_chiller.addToNode(chw_loop_clg_eqpt_outlet_node)
    sec_chiller.setName('ChillerAirCooled')

    # add ground HX loop with district heating and cooling plant to represent the ground HX
    heat_rej_loop,heat_rej_loop_eqpt = add_plantloop(model: model,
                                                     loop_htg_eqpt_type: 'none',
                                                     loop_clg_eqpt_type: 'none',
                                                     loop_heat_rej_eqpt_type: 'District_Heating',
                                                     loop_pump_type: 'variable_speed',
                                                     loop_spm_type: 'none',
                                                     loop_setpoint: 'none',
                                                     loop_temp_diff: 10.0)
    heat_rej_loop_eqpt.setName('DistrictHeating GLHX')
    htg_eqpt_outlet_node = heat_rej_loop_eqpt.outletModelObject.get.to_Node.get
    clg_eqpt = create_plantloop_clg_eqpt(model, 'District_Cooling')
    clg_eqpt.setName('DistrictCooling GLHX')
    clg_eqpt.addToNode(htg_eqpt_outlet_node)
    htg_spm = create_plantloop_spm( model, 'Scheduled', 5.0)
    htg_spm.addToNode(htg_eqpt_outlet_node)
    clg_eqpt_outlet_node = clg_eqpt.outletModelObject.get.to_Node.get
    clg_spm = create_plantloop_spm( model, 'Scheduled', 25.0)
    clg_spm.addToNode(heat_rej_loop.supplyOutletNode)
    heat_rej_loop.setName("#{heat_rej_loop.name.to_s} GLHX")
    heat_rej_loop.addDemandBranchForComponent(hw_loop_htg_eqpt)
    heat_rej_loop.addDemandBranchForComponent(chw_loop_clg_eqpt)

    # add output variables for district heating and cooling
    model.getOutputVariables.each {|ivar| ivar.remove}
    dist_htg_var = OpenStudio::Model::OutputVariable.new("District Heating Water Rate",model)
    dist_htg_var.setReportingFrequency("hourly")
    dist_htg_var.setKeyValue("*")
    dist_clg_var = OpenStudio::Model::OutputVariable.new("District Cooling Water Rate",model)
    dist_clg_var.setReportingFrequency("hourly")
    dist_clg_var.setKeyValue("*")

    return systems
  end

  #=============================================================================================================================
  # Appy efficiencies for ECM "hs14_cgshp_fancoils"
  def apply_efficiency_ecm_hs14_cgshp_fancoils(model,standard)
    heatpump_siz_f = 0.4  # sizing factor for water-source heat pump (heating mode)
    chiller_siz_f = 0.4  # sizing factor for water-cooled chiller
    # get water-source heat pump and boiler
    hw_loops = model.getPlantLoops.select {|loop| loop.sizingPlant.loopType.to_s.downcase == 'heating'}
    hw_heatpump_loop = nil
    hw_heatpump = nil
    hw_boilers = nil
    hw_loops.each do |hw_loop|
      hw_heatpumps = hw_loop.supplyComponents.select {|comp| comp.to_HeatPumpWaterToWaterEquationFitHeating.is_initialized}
      if !hw_heatpumps.empty?
        hw_heatpump_loop = hw_loop
        hw_heatpump = hw_heatpumps[0].to_HeatPumpWaterToWaterEquationFitHeating.get
      end
      hw_boilers = hw_loop.supplyComponents.select {|comp| comp.to_BoilerHotWater.is_initialized}
      break if !hw_heatpump_loop.nil? && !hw_heatpump.nil? && !hw_boilers.empty?
    end
    raise("apply_efficiency_ecm_hs14_cgshp_fancoils: no water-source heat pump found in heating loop #{hw_loops.name.to_s}") if hw_heatpump.nil?
    cw_loop = model.getPlantLoops.select {|loop| loop.sizingPlant.loopType.to_s.downcase == 'condenser'}[0]
    # condenser flow rate is set based on heating loop flow rate and cooling loop flow rate (adjusted for sizing factors)
    cw_loop_max_flow = 0.0
    if hw_heatpump_loop.maximumLoopFlowRate.is_initialized
      cw_loop_max_flow += heatpump_siz_f*hw_heatpump_loop.maximumLoopFlowRate.to_f
    elsif hw_heatpump_loop.autosizedMaximumLoopFlowRate.is_initialized
      cw_loop_max_flow += heatpump_siz_f*hw_heatpump_loop.autosizedMaximumLoopFlowRate.to_f
    else
      raise("apply_efficiency_ecm_hs14_cgshp_fancoils: heating loop #{hw_heatpump_loop.name.to_s} flow rate is not defined")
    end
    chw_loop = model.getPlantLoops.select {|loop| loop.sizingPlant.loopType.to_s.downcase == 'cooling'}[0]
    if chw_loop.maximumLoopFlowRate.is_initialized
      cw_loop_max_flow += chiller_siz_f*chw_loop.maximumLoopFlowRate.to_f
    elsif chw_loop.autosizedMaximumLoopFlowRate.is_initialized
      cw_loop_max_flow += chiller_siz_f*chw_loop.autosizedMaximumLoopFlowRate.to_f
    else
      raise("apply_efficiency_ecm_hs14_cgshp_fancoils: cooling loop #{chw_loop.name.to_s} is not defined")
    end
    cw_loop.setMaximumLoopFlowRate(cw_loop_max_flow)
    cw_loop_pump = cw_loop.supplyComponents.select {|comp| comp.to_PumpVariableSpeed.is_initialized}[0].to_PumpVariableSpeed.get
    cw_loop_pump.setRatedFlowRate(cw_loop_max_flow)
    # set heating capacity of water-source heat pump and boiler
    if hw_heatpump.autosizedRatedHeatingCapacity.is_initialized
      cap = hw_heatpump.autosizedRatedHeatingCapacity.to_f
    elsif hw_heatpump.ratedHeatingCapacity.is_initialized
      cap = hw_heatpump.ratedHeatingCapacity.to_f
    else
      raise("apply_efficiency_ecm_hs14_cgshp_fancoils: capacity of water-source heat pump #{hw_heatpump.name.to_s} is not defined")
    end
    hw_heatpump.setRatedHeatingCapacity(heatpump_siz_f*cap)
    # If two boilers are present set their capacities by multiplying the capacity not handled by the GSHP by the defined
    # primary and secondary boiler capacity ratios, respectively. If one boiler is defined then set its capacity to the
    # amount not handled by the GSHP.
    tot_hw_boiler_cap = (1.0-heatpump_siz_f)*cap
    hw_boiler_cap = [ 1.0 ]
    if hw_boilers.size > 1
      standard.fuel_type_set.primary_boiler_cap_frac.nil? ? hw_boiler_cap[0] = 0.75 : hw_boiler_cap[0] = standard.fuel_type_set.primary_boiler_cap_frac
      standard.fuel_type_set.secondary_boiler_cap_frac.nil? ? hw_boiler_cap[1] = 1.0 - hw_boiler_cap[0] : hw_boiler_cap[1] = standard.fuel_type_set.secondary_boiler_cap_frac
    end
    hw_boilers.each_with_index do |hw_boiler, boiler_index|
      hw_boiler.to_BoilerHotWater.get.setNominalCapacity((tot_hw_boiler_cap*hw_boiler_cap[boiler_index]))
    end
    # set cooling capacity of chillers
    chillers = chw_loop.supplyComponents.select {|comp| comp.to_ChillerElectricEIR.is_initialized}
    chiller_water_cooled = nil
    chiller_air_cooled = nil
    chillers.each do |comp|
      chlr = comp.to_ChillerElectricEIR.get
      chiller_water_cooled = chlr if chlr.name.to_s.include? 'ChillerWaterCooled'
      chiller_air_cooled = chlr if chlr.name.to_s.include? 'ChillerAirCooled'
      break if !chiller_water_cooled.nil? && !chiller_air_cooled.nil?
    end
    raise("apply_efficiency_ecm_hs14_cgshp_fancoils: no water-cooled chiller found in cooling loop #{chw_loop.name.to_s}") if chiller_water_cooled.nil?
    raise("apply_efficiency_ecm_hs14_cgshp_fancoils: no air-cooled chiller found in cooling loop #{chw_loop.name.to_s}") if chiller_air_cooled.nil?
    if chiller_water_cooled.autosizedReferenceCapacity.is_initialized
      cap = chiller_water_cooled.autosizedReferenceCapacity.to_f
    elsif chiller_water_cooled.referenceCapacity.is_initialized
      cap = chiller_water_cooled.referenceCapacity.to_f
    else
      raise("apply_efficiency_ecm_hs14_cgshp_fancoils: cooling capacity of chiller #{chiller_water_cooled.name.to_s} is not defined")
    end
    chiller_water_cooled.setReferenceCapacity(chiller_siz_f*cap)
    chiller_air_cooled.setReferenceCapacity((1.0-chiller_siz_f)*cap)
    # call standard efficiency method again for water-cooled chiller
    new_chlr_name = chiller_water_cooled.name.to_s.chomp!(chiller_water_cooled.name.to_s.split.last).strip
    new_chlr_name = new_chlr_name.chomp!(new_chlr_name.split.last).strip
    new_chlr_name = new_chlr_name.chomp!(new_chlr_name.split.last).strip
    chiller_water_cooled.setName(new_chlr_name)
    standard.chiller_electric_eir_apply_efficiency_and_curves(chiller_water_cooled,nil)
    # set curves and cop of air-cooled chiller
    chlr_cap_w = (1.0-chiller_siz_f)*cap
    chlr_cap_ton = OpenStudio.convert(chlr_cap_w, 'W', 'ton').get
    search_criteria = {}
    search_criteria['cooling_type'] = 'AirCooled'
    chlr_props = model_find_object(standards_data['tables']['chiller_types_ecm']['table'], search_criteria, chlr_cap_ton)
    chiller_air_cooled.setName("ChillerAirCooled #{chlr_props['compressor_type']}")
    search_criteria = {}
    search_criteria['name'] = 'NECB2020_AirCooledChiller'
    search_criteria['compressor_type'] = chlr_props['compressor_type']
    chiller_electric_eir_apply_curves_and_cop(chiller_air_cooled, search_criteria)
  end

  #=============================================================================================================================
  def set_ghx_loop_district_cap(model)
    # The autosized values for the district heating and cooling objects on a condenser loop are the sum of the peak heating and
    # cooling loads. Here the capacity of the district heating object of the condenser loop is set to the maximum district heating
    # rate on the winter design day. Similarily the capacity of the district cooling object of the condenser loop is set to the
    # maximum district cooling rate on the summer design day.

    cw_loops = model.getPlantLoops.select{|loop| loop.sizingPlant.loopType.to_s.downcase == 'condenser'}
    ghx_loops = cw_loops.select { |loop| loop.name.to_s.downcase.include? 'glhx' }
    return if ghx_loops.empty?
    ghx_loop = ghx_loops[0]
    dist_htg_eqpts = ghx_loop.supplyComponents.select { |comp| comp.iddObjectType.valueName.to_s.include?('DistrictHeating') }
    if !dist_htg_eqpts.empty?
      case dist_htg_eqpts[0].iddObjectType.valueName.to_s
      when 'OS_DistrictHeating'
        dist_htg_eqpt = dist_htg_eqpts[0].to_DistrictHeating.get
      when 'OS_DistrictHeating_Water'
        dist_htg_eqpt = dist_htg_eqpts[0].to_DistrictHeatingWater.get
      when 'OS_DistrictHeating_Steam'
        dist_htg_eqpt = dist_htg_eqpts[0].to_DistrictHeatingSteam.get
      end
    end
    dist_clg_eqpts = ghx_loop.supplyComponents.select {|comp| comp.to_DistrictCooling.is_initialized}
    dist_clg_eqpt = dist_clg_eqpts[0].to_DistrictCooling.get if !dist_clg_eqpts.empty?
    raise("set_cond_loop_district_cap: condenser loop doesn't have a district heating and district cooling objects") if dist_htg_eqpts.empty? || dist_clg_eqpts.empty?
    # District Heating
    sql_command = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary
               WHERE VariableName='District Heating Water Rate'"
    dhtg_index = model.sqlFile.get.execAndReturnFirstString(sql_command).get
    raise("set_ghx_loop_district_cap: EnergyPlus sql results file has no data for district heating hot water rate") if dhtg_index.nil?
    sql_command = "SELECT Value FROM ReportVariableWithTime
               WHERE ReportDataDictionaryIndex=#{dhtg_index} AND DayType='WinterDesignDay'"
    dist_htg_w = model.sqlFile.get.execAndReturnVectorOfString(sql_command).get
    sql_command = "SELECT Value FROM ReportVariableWithTime
               WHERE ReportDataDictionaryIndex=#{dhtg_index} AND DayType='SummerDesignDay'"
    dist_htg_s = model.sqlFile.get.execAndReturnVectorOfString(sql_command).get
    # District Cooling
    sql_command = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary
               WHERE VariableName='District Cooling Water Rate'"
    dclg_index = model.sqlFile.get.execAndReturnFirstString(sql_command).get
    raise("set_ghx_loop_district_cap: EnergyPlus sql results file has no data for district cooling chilled water rate") if dclg_index.nil?
    sql_command = "SELECT Value FROM ReportVariableWithTime
               WHERE ReportDataDictionaryIndex=#{dclg_index} AND DayType='SummerDesignDay'"
    dist_clg_s = model.sqlFile.get.execAndReturnVectorOfString(sql_command).get
    sql_command = "SELECT Value FROM ReportVariableWithTime
               WHERE ReportDataDictionaryIndex=#{dclg_index} AND DayType='WinterDesignDay'"
    dist_clg_w = model.sqlFile.get.execAndReturnVectorOfString(sql_command).get
    # Assign peak heating and cooling loads to capacities of district objects
    max_htg_load = 0.0
    max_clg_load = 0.0
    for hour in 1..24
      htg_load = [dist_htg_w[hour-1].to_f-dist_clg_w[hour-1].to_f,0.0].max
      clg_load = [dist_clg_s[hour-1].to_f-dist_htg_s[hour-1].to_f,0.0].max
      max_htg_load = [max_htg_load,htg_load].max
      max_clg_load = [max_clg_load,clg_load].max
    end
    dist_htg_eqpt.setNominalCapacity(max_htg_load)
    dist_clg_eqpt.setNominalCapacity(max_clg_load)
  end

  #=============================================================================================================================
  # Add equipment for ECM "hs15_cawhp_fancoils"
  #   -Constant volume DOAS with hydronic htg and clg coils served by central air-to-water heat pump.
  #   -Zonal terminal fan coil (4-pipe) connected to central air-to-water heat pump.
  #   -Plant has a heating loop with air-to-water heat pump with one or two backup boiler(s).
  def add_ecm_hs15_cawhp_fancoils(model:,
                               system_zones_map:,
                               system_doas_flags:,
                               ecm_system_zones_map_option:,
                               standard:,
                               sys_htg_eqpt_type: 'coil_hw',
                               sys_clg_eqpt_type: 'coil_chw',
                               sys_supp_htg_eqpt_type: 'none')
    # Update system zones map if needed
    system_zones_map = update_system_zones_map_keys(system_zones_map,'sys_1')
    system_zones_map = update_system_zones_map(model,system_zones_map,ecm_system_zones_map_option,'sys_1') if ecm_system_zones_map_option != 'NECB_Default'
    # Update system doas flags
    system_doas_flags = {}
    system_zones_map.keys.each { |sname| system_doas_flags[sname] = true }
    # generate new air system and zonal equipment
    systems = []
    system_zones_map.sort.each do |sys_name, zones|
      sys_info = air_sys_comps_assumptions(sys_name: sys_name,
             zones: zones,
             system_doas_flags: system_doas_flags)
      airloop,clg_coil,htg_coil,return_fan = add_air_system(model: model,
             zones: zones,
             sys_abbr: sys_info['sys_abbr'],
             sys_vent_type: sys_info['sys_vent_type'],
             sys_heat_rec_type: sys_info['sys_heat_rec_type'],
             sys_htg_eqpt_type: sys_htg_eqpt_type,
             sys_supp_htg_eqpt_type: sys_supp_htg_eqpt_type,
             sys_clg_eqpt_type: sys_clg_eqpt_type,
             sys_supp_fan_type: sys_info['sys_supp_fan_type'],
             sys_ret_fan_type: sys_info['sys_ret_fan_type'],
             sys_setpoint_mgr_type: 'warmest')
      if sys_htg_eqpt_type == 'ashp' && sys_clg_eqpt_type == 'ashp'
        eqpt_name = 'NECB2015_ASHP'
        coil_cooling_dx_single_speed_apply_curves(clg_coil,eqpt_name)
        coil_heating_dx_single_speed_apply_curves(htg_coil,eqpt_name)
      end
      # add zone fan coil equipment and diffuser
      zone_htg_eqpt_type = 'fancoil_4pipe'
      zone_clg_eqpt_type = 'fancoil_4pipe'
      zone_supp_htg_eqpt_type = 'none'
      zone_fan_type = 'on_off'
      add_zone_eqpt(model: model,
      airloop: airloop,
      zones: zones,
      outdoor_unit: nil,
      zone_diffuser_type: sys_info['zone_diffuser_type'],
      zone_htg_eqpt_type: zone_htg_eqpt_type,
      zone_supp_htg_eqpt_type: zone_supp_htg_eqpt_type,
      zone_clg_eqpt_type: zone_clg_eqpt_type,
      zone_fan_type: zone_fan_type)
      return_fan.addToNode(airloop.returnAirNode.get) if return_fan
      systems << airloop
    end
    # add hot-water loop with heat pump for heating
    hw_loop,hw_loop_htg_eqpt = add_plantloop(model: model,
           loop_htg_eqpt_type: 'HeatPump_PlantLoop_EIR_Heating',
           loop_clg_eqpt_type: 'none',
           loop_heat_rej_eqpt_type: 'none',
           loop_pump_type: 'variable_speed',
           loop_spm_type: 'Scheduled',
           loop_setpoint: 60.0,
           loop_temp_diff: 5.0)
    # set additional parameters for heating heat pump
    hw_loop_htg_eqpt.setCondenserType('AirSoure')
    hw_loop_htg_eqpt.setMinimumSourceInletTemperature(-15.0)
    hw_loop_htg_eqpt.setReferenceCoefficientofPerformance(3.0)
    hw_loop_htg_eqpt.setHeatPumpSizingMethod('CoolingCapacity')
    hw_loop_htg_eqpt.setHeatPumpDefrostControl('OnDemand')
    hw_loop_htg_eqpt.setFlowMode('VariableSpeedPumping')
    hw_loop_htg_eqpt.setControlType('Setpoint')
    hw_loop_htg_eqpt.setMinimumPartLoadRatio(0.2)
    hw_loop.setLoadDistributionScheme('SequentialLoad')
    model.getCoilHeatingWaters.sort.each {|coil| hw_loop.addDemandBranchForComponent(coil)}
    # add one boiler if the primary and backup boiler fuel types are the same.  Add two boilers if the primary and
    # secondary boiler fuel types differ.
    hw_loop_htg_eqpt_outlet_node = hw_loop_htg_eqpt.supplyOutletModelObject.get.to_Node.get
    boiler_fuels = []
    boiler_fuels[0] = standard.fuel_type_set.boiler_fueltype
    boiler_fuels[1] = standard.fuel_type_set.backup_boiler_fueltype unless standard.fuel_type_set.backup_boiler_fueltype == boiler_fuels[0]
    hw_boilers = []
    boiler_fuels.each do |boiler_fuel|
      boiler = OpenStudio::Model::BoilerHotWater.new(model)
      boiler.setFuelType(boiler_fuel)
      hw_boilers << boiler
    end
    hw_boilers.reverse().each {|boiler| boiler.addToNode(hw_loop_htg_eqpt_outlet_node)}
    # add setpoint manager at the exit of the heat pump heating comp
    sch = OpenStudio::Model::ScheduleConstant.new(model)
    sch.setValue(60.0)
    spm = OpenStudio::Model::SetpointManagerScheduled.new(model,sch)
    spm.setName("HeatPumpHtgSetpointManager")
    spm.addToNode(hw_loop_htg_eqpt_outlet_node)
    # add chilled-water loop with heat pump for cooling
    chw_loop,chw_loop_clg_eqpt = add_plantloop(model: model,
           loop_htg_eqpt_type: 'none',
           loop_clg_eqpt_type: 'HeatPump_PlantLoop_EIR_Cooling',
           loop_heat_rej_eqpt_type: 'none',
           loop_pump_type: 'variable_speed',
           loop_spm_type: 'Scheduled',
           loop_setpoint: 7.0,
           loop_temp_diff: 6.0)
    # set additional parameter for heat pump for cooling
    chw_loop_clg_eqpt.setCondenserType('AirSource')
    chw_loop_clg_eqpt.setFlowMode('VariableSpeedPumping')
    chw_loop_clg_eqpt.setReferenceCoefficientofPerformance(3.0)
    chw_loop_clg_eqpt.setFlowMode('VariableSpeedPumping')
    chw_loop_clg_eqpt.setControlType('Load')
    chw_loop_clg_eqpt.setMinimumPartLoadRatio(0.2)
    hw_loop_htg_eqpt.setCompanionCoolingHeatPump(chw_loop_clg_eqpt)
    model.getCoilCoolingWaters.sort.each {|coil| chw_loop.addDemandBranchForComponent(coil)}
    # use performance curves given in one of the E+ examples for a central air-to-water heat pump from Trane
    # heating capft curve
    hcapft = OpenStudio::Model::CurveBiquadratic.new(model)
    hcapft.setCoefficient1Constant(0.794900878202383)
    hcapft.setCoefficient2x(0.00388524034840032)
    hcapft.setCoefficient3xPOW2(-0.0000575169230965453)
    hcapft.setCoefficient4y(0.0278109488428528)
    hcapft.setCoefficient5yPOW2(0.000318168)
    hcapft.setCoefficient6xTIMESY(-0.000130572089253355)
    hcapft.setMinimumValueofx(15.0)
    hcapft.setMaximumValueofx(70.0)
    hcapft.setMinimumValueofy(-17.0)
    hcapft.setMaximumValueofy(37.22)
    hcapft.setMinimumCurveOutput(0.0)
    hcapft.setMaximumCurveOutput(1.55)
    hw_loop_htg_eqpt.setCapacityModifierFunctionofTemperatureCurve(hcapft)
    # heating eirft curve
    heirft = OpenStudio::Model::CurveBiquadratic.new(model)
    heirft.setCoefficient1Constant(0.530730392560108)
    heirft.setCoefficient2x(0.00655164780603528)
    heirft.setCoefficient3xPOW2(0.000263599226028026)
    heirft.setCoefficient4y(-0.03620668194737)
    heirft.setCoefficient5yPOW2(0.00126617163409192)
    heirft.setCoefficient6xTIMESY(-0.000791224057761721)
    heirft.setMinimumValueofx(15.0)
    heirft.setMaximumValueofx(70.0)
    heirft.setMinimumValueofy(-17.0)
    heirft.setMaximumValueofy(37.22)
    heirft.setMinimumCurveOutput(0.4)
    heirft.setMaximumCurveOutput(1.48)
    hw_loop_htg_eqpt.setElectricInputtoOutputRatioModifierFunctionofTemperatureCurve(heirft)
    # cooling capft curves
    ccapft = OpenStudio::Model::CurveBiquadratic.new(model)
    ccapft.setCoefficient1Constant(1.06722728893252)
    ccapft.setCoefficient2x(0.0460678063570057)
    ccapft.setCoefficient3xPOW2(0.00034604993757372)
    ccapft.setCoefficient4y(-0.0069704934525177)
    ccapft.setCoefficient5yPOW2(-0.0000288618548923695)
    ccapft.setCoefficient6xTIMESY(-0.000475762640861958)
    ccapft.setMinimumValueofx(2.0)
    ccapft.setMaximumValueofx(20.0)
    ccapft.setMinimumValueofy(4.2)
    ccapft.setMaximumValueofy(37.0)
    ccapft.setMinimumCurveOutput(0.0)
    ccapft.setMaximumCurveOutput(1.55)
    chw_loop_clg_eqpt.setCapacityModifierFunctionofTemperatureCurve(ccapft)
    # cooling eirft curve
    ceirft = OpenStudio::Model::CurveBiquadratic.new(model)
    ceirft.setCoefficient1Constant(0.440305821838175)
    ceirft.setCoefficient2x(-0.0241323110030793)
    ceirft.setCoefficient3xPOW2(0.000537914626055751)
    ceirft.setCoefficient4y(0.0118716162533228)
    ceirft.setCoefficient5yPOW2(0.000305785618883187)
    ceirft.setCoefficient6xTIMESY(-0.000617329632749052)
    ceirft.setMinimumValueofx(2.0)
    ceirft.setMaximumValueofx(20.0)
    ceirft.setMinimumValueofy(4.2)
    ceirft.setMaximumValueofy(37.0)
    ceirft.setMinimumCurveOutput(0.4)
    ceirft.setMaximumCurveOutput(1.48)
    chw_loop_clg_eqpt.setElectricInputtoOutputRatioModifierFunctionofTemperatureCurve(ceirft)
    return
  end

  #=============================================================================================================================
  # Apply efficiency for ECM 'hs15_cawhp_fancoils'
  def apply_efficiency_ecm_hs15_cawhp_fancoils(model, standard)
    heatpump_siz_f = 0.4 # heating heat pump sizing fraction
    # get heat pump heating and boiler objects
    hw_loop = model.getPlantLoops.select {|loop| loop.sizingPlant.loopType.to_s.downcase == 'heating'}
    raise("apply_efficiency_ecm_hs15_cawhp_fancoils: no hot-water loop is found") if hw_loop.empty?
    hw_loop = hw_loop[0].to_PlantLoop.get
    heatpump_htg = hw_loop.supplyComponents.select {|comp| comp.to_HeatPumpPlantLoopEIRHeating.is_initialized}
    hw_boilers = hw_loop.supplyComponents.select {|comp| comp.to_BoilerHotWater.is_initialized}
    raise("apply_efficiency_ecm_hs15_cawhp_fancoils: no air-source heat pump found on hot-water loop #{hw_loop.name.to_s}") if heatpump_htg.empty?
    raise("apply_efficiency_ecm_hs15_cawhp_fancoils: no boiler found on hot-water loop #{hw_loop.name.to_s}") if hw_boilers.empty?
    heatpump_htg = heatpump_htg[0].to_HeatPumpPlantLoopEIRHeating.get
    primary_boiler = hw_boilers[0].to_BoilerHotWater.get
    # boiler total capacity
    if primary_boiler.autosizedNominalCapacity.is_initialized
      tot_hw_boiler_cap = primary_boiler.autosizedNominalCapacity.to_f
    elsif primary_boiler.nominalCapacity.is_initialized
      tot_hw_boiler_cap = primary_boiler.nominalCapacity.to_f
    else
      raise("apply_efficiency_ecm_hs15_cawhp_fancoils: capacity of boiler #{primary_boiler.name.to_s} is not defined")
    end
    # If two boilers are present set their capacities by multiplying the total capacity by the defined primary and secondary
    # boiler capacity ratios, respectively.
    hw_boiler_cap = [ 1.0 ]
    if hw_boilers.size > 1
      standard.fuel_type_set.primary_boiler_cap_frac.nil? ? hw_boiler_cap[0] = 0.75 : hw_boiler_cap[0] = standard.fuel_type_set.primary_boiler_cap_frac
      standard.fuel_type_set.secondary_boiler_cap_frac.nil? ? hw_boiler_cap[1] = 1.0 - hw_boiler_cap[0] : hw_boiler_cap[1] = standard.fuel_type_set.secondary_boiler_cap_frac
    end
    hw_boilers.each_with_index do |hw_boiler, boiler_index|
      hw_boiler.to_BoilerHotWater.get.setNominalCapacity((tot_hw_boiler_cap*hw_boiler_cap[boiler_index]))
    end
    # get heat pump cooling object
    chw_loop = model.getPlantLoops.select {|loop| loop.sizingPlant.loopType.to_s.downcase == 'cooling'}
    raise("apply_efficiency_ecm_hs15_cawhp_fancoils: no chilled-water loop is found") if chw_loop.empty?
    chw_loop = chw_loop[0].to_PlantLoop.get
    heatpump_clg = chw_loop.supplyComponents.select {|comp| comp.to_HeatPumpPlantLoopEIRCooling.is_initialized}
    raise("apply_efficiency_ecm_hs15_cawhp_fancoils: no heat pump on chilled-water loop #{chw_loop.name} is found") if heatpump_clg.empty?
    heatpump_clg = heatpump_clg[0].to_HeatPumpPlantLoopEIRCooling.get
    # get cooling capacity of air-source heat pump
    if heatpump_clg.autosizedReferenceCapacity.is_initialized
      hp_clg_cap = heatpump_clg.autosizedReferenceCapacity.to_f
    elsif heatpump_clg.ratedReferenceCapacity.is_initialized
      hp_clg_cap = heatpump_clg.ratedReferenceCapacity.to_f
    else
      raise("apply_efficiency_ecm_hs15_cawhp_fancoils: capacity of air-source heat pump #{heatpump_htg.name.to_s} is not defined")
    end
    # set final heating capacity and cooling capacities of air-source heat pump
    hp_htg_cap = heatpump_siz_f*tot_hw_boiler_cap
    hp_htg_cap = hp_clg_cap if hp_clg_cap > hp_htg_cap
    heatpump_htg.setReferenceCapacity(hp_htg_cap)
    heatpump_clg.setReferenceCapacity(hp_htg_cap)
    # sensor for heat pump cooling load side heat transfer
    heatpump_clg_load_s = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Heat Pump Load Side Heat Transfer Rate')
    heatpump_clg_load_s.setName('HeatPumpClgLoad')
    heatpump_clg_load_s.setKeyName(heatpump_clg.name.to_s)
    # actuator for heat pump heating outlet node setpoint schedule
    heatpump_htg_outlet_node = heatpump_htg.supplyOutletModelObject.get.to_Node.get
    heatpump_htg_sch = heatpump_htg_outlet_node.setpointManagers[0].to_SetpointManagerScheduled.get.schedule.to_ScheduleConstant.get
    heatpump_htg_sch_a = OpenStudio::Model::EnergyManagementSystemActuator.new(heatpump_htg_sch, 'Schedule:Constant', 'Schedule Value')
    heatpump_htg_sch_a.setName('heatpump_htg_sch_a')
    # energy management program to turn off heat pump heating side when the cooling side is on
    heatpump_cltr_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    heatpump_cltr_prg.setName('HeatPumpCtrlPrg')
    body = <<-EMS
      IF (HeatPumpClgLoad > 0.0)
        SET heatpump_htg_sch_a = -99.0
      ELSE
        SET heatpump_htg_sch_a = 50.0
      ENDIF
    EMS
    heatpump_cltr_prg.setBody(body)
    heat_pump_ctlr_pcm = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    heat_pump_ctlr_pcm.setName('HeatPumpCtrlPCM')
    heat_pump_ctlr_pcm.setCallingPoint('InsideHVACSystemIterationLoop')
    heat_pump_ctlr_pcm.addProgram(heatpump_cltr_prg)

    return
  end

  #=============================================================================================================================
  # Add equipment for ECM "hs16_ashp_cawhp_fancoils"
  #   -Constant volume DOAS with ashp for heating and cooling with a backup heating coil.
  #   -Zonal terminal fan coil (4-pipe) connected to central air-to-water heat pump.
  #   -Plant has a heating loop with air-to-water heat pump with one or two backup boiler(s).
  def add_ecm_hs16_ashp_cawhp_fancoils(model:,
                                    system_zones_map:,
                                    system_doas_flags:,
                                    ecm_system_zones_map_option:,
                                    standard:)
    # Get the heating fuel type from the system fuels object defined by the standards object
    heating_fuel = standard.fuel_type_set.ecm_fueltype
    # Set supplemental heaing for airloop
    sys_supp_htg_eqpt_type = 'coil_electric'
    sys_supp_htg_eqpt_type = 'coil_gas' if heating_fuel == 'NaturalGas'
    sys_supp_htg_eqpt_type = 'coil_hw' if standard.fuel_type_set.force_airloop_hot_water
    # call ecm HS15 to add the air loop
    add_ecm_hs15_cawhp_fancoils(model: model,
                             system_zones_map: system_zones_map,
                             system_doas_flags: system_doas_flags,
                             ecm_system_zones_map_option: ecm_system_zones_map_option,
                             standard: standard,
                             sys_htg_eqpt_type: 'ashp',
                             sys_clg_eqpt_type: 'ashp',
                             sys_supp_htg_eqpt_type: sys_supp_htg_eqpt_type)
    return
  end

  #=============================================================================================================================
  # Apply efficiency for ECM 'hs16_ashp_cawhp_fancoils'
  def apply_efficiency_ecm_hs16_ashp_cawhp_fancoils(model, standard)
    # The air loop is the same as in ECM HS12
    apply_efficiency_ecm_hs12_ashp_baseboard(model, standard)
    # The plant loop is the same as in ECM HS15
    apply_efficiency_ecm_hs15_cawhp_fancoils(model, standard)
    return
  end

  # =============================================================================================================================
  # Applies the performance curves "CoilCoolingDXSingleSpeed" object.
  def coil_cooling_dx_single_speed_apply_curves(coil_cooling_dx_single_speed, eqpt_name)
    successfully_set_all_properties = true

    search_criteria = {}
    search_criteria['name'] = eqpt_name

    # Get the capacity
    multiplier = nil
    if ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_single_speed))
      thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil_cooling_dx_single_speed)
      multiplier = thermal_zone.multiplier if !thermal_zone.nil?
    end
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_w = capacity_w.nil? ? 1.0 : [1.0, capacity_w].max
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Lookup efficiencies
    ac_props = model_find_object(standards_data['tables']['heat_pump_cooling_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria}, cannot apply efficiency.")
      successfully_set_all_properties = false
    end
    # Make the COOL-CAP-FT curve
    cool_cap_ft = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_cap_ft'])

    if cool_cap_ft
      coil_cooling_dx_single_speed.setTotalCoolingCapacityFunctionOfTemperatureCurve(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_cap_fflow'])
    if cool_cap_fflow
      coil_cooling_dx_single_speed.setTotalCoolingCapacityFunctionOfFlowFractionCurve(cool_cap_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_eir_ft'])
    if cool_eir_ft
      coil_cooling_dx_single_speed.setEnergyInputRatioFunctionOfTemperatureCurve(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_eir_fflow'])
    if cool_eir_fflow
      coil_cooling_dx_single_speed.setEnergyInputRatioFunctionOfFlowFractionCurve(cool_eir_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_plf_fplr'])
    if cool_plf_fplr
      coil_cooling_dx_single_speed.setPartLoadFractionCorrelationCurve(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_Single_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Applies the performance curves to "CoilHeatingSingleSpeed" object.
  def coil_heating_dx_single_speed_apply_curves(coil_heating_dx_single_speed, eqpt_name)
    successfully_set_all_properties = true

    # Get the search criteria
    search_criteria = {}
    search_criteria['name'] = eqpt_name

    # Get the capacity
    capacity_w = OpenstudioStandards::HVAC.coil_heating_get_paired_coil_cooling_capacity(coil_heating_dx_single_speed)
    capacity_w = capacity_w.nil? ? 1.0 : [1.0, capacity_w].max
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Lookup efficiencies
    props = model_find_object(standards_data['tables']['heat_pump_heating_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FT curve
    heat_cap_ft = model_add_curve(coil_heating_dx_single_speed.model, props['heat_cap_ft'])
    if heat_cap_ft
      coil_heating_dx_single_speed.setTotalHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find heat_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FFLOW curve
    heat_cap_fflow = model_add_curve(coil_heating_dx_single_speed.model, props['heat_cap_fflow'])
    if heat_cap_fflow
      coil_heating_dx_single_speed.setTotalHeatingCapacityFunctionofFlowFractionCurve(heat_cap_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find heat_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FT curve
    heat_eir_ft = model_add_curve(coil_heating_dx_single_speed.model, props['heat_eir_ft'])
    if heat_eir_ft
      coil_heating_dx_single_speed.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find heat_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FFLOW curve
    heat_eir_fflow = model_add_curve(coil_heating_dx_single_speed.model, props['heat_eir_fflow'])
    if heat_eir_fflow
      coil_heating_dx_single_speed.setEnergyInputRatioFunctionofFlowFractionCurve(heat_eir_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find heat_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-PLF-FPLR curve
    heat_plf_fplr = model_add_curve(coil_heating_dx_single_speed.model, props['heat_plf_fplr'])
    if heat_plf_fplr
      coil_heating_dx_single_speed.setPartLoadFractionCorrelationCurve(heat_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find heat_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-DEFROST-EIR-FT curve
    heat_defrost_eir_ft = model_add_curve(coil_heating_dx_single_speed.model, props['heat_defrost_eir_ft'])
    if heat_defrost_eir_ft
      coil_heating_dx_single_speed.setDefrostEnergyInputRatioFunctionofTemperatureCurve(heat_defrost_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, can not find heat_defrost_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Applies the performance curves "ChillerElectricEIR" object.
  def chiller_electric_eir_apply_curves_and_cop(chiller_electric_eir, search_criteria)
    successfully_set_all_properties = true

    # Get the capacity
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)
    capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get

    # Lookup performance curves
    chlr_props = model_find_object(standards_data['tables']['chillers_ecm']['table'], search_criteria, capacity_tons)

    # Check to make sure properties were found
    if chlr_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find efficiency info using #{search_criteria}")
      successfully_set_all_properties = false
    end

    # CAP-FT curve
    capft = model_add_curve(chiller_electric_eir.model, chlr_props['capft'])
    if capft
      chiller_electric_eir.setCoolingCapacityFunctionOfTemperature(capft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # EIR-FT curve
    eirft = model_add_curve(chiller_electric_eir.model, chlr_props['eirft'])
    if eirft
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfTemperature(eirft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # EIR-FPLR curve
    eirfplr = model_add_curve(chiller_electric_eir.model, chlr_props['eirfplr'])
    if eirfplr
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfPLR(eirfplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find eir_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # set COP
    cop = chlr_props['minimum_coefficient_of_performance_cooling'].to_f
    if cop
      chiller_electric_eir.setReferenceCOP(cop)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cop, will not be set.")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Applies the performance curves "CoilCoolingDXVariableSpeed" object.
  def coil_cooling_dx_variable_speed_apply_curves(coil_cooling_dx_variable_speed, eqpt_name)
    successfully_set_all_properties = true

    # Get the capacity
    capacity_w = coil_cooling_dx_variable_speed_find_capacity(coil_cooling_dx_variable_speed)
    capacity_w = [1.0,capacity_w].max
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Lookup performance curves
    search_criteria = {}
    search_criteria['name'] = eqpt_name
    ac_props = model_find_object(standards_data['tables']['heat_pump_cooling_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find efficiency info using #{search_criteria}, cannot apply efficiency.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FT curve
    cool_cap_ft = model_add_curve(coil_cooling_dx_variable_speed.model, ac_props['cool_cap_ft'])
    if cool_cap_ft
      coil_cooling_dx_variable_speed.speeds.each { |speed| speed.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = model_add_curve(coil_cooling_dx_variable_speed.model, ac_props['cool_cap_fflow'])
    if cool_cap_fflow
      coil_cooling_dx_variable_speed.speeds.each { |speed| speed.setTotalCoolingCapacityFunctionofAirFlowFractionCurve(cool_cap_fflow) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = model_add_curve(coil_cooling_dx_variable_speed.model, ac_props['cool_eir_ft'])
    if cool_eir_ft
      coil_cooling_dx_variable_speed.speeds.each { |speed| speed.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = model_add_curve(coil_cooling_dx_variable_speed.model, ac_props['cool_eir_fflow'])
    if cool_eir_fflow
      coil_cooling_dx_variable_speed.speeds.each { |speed| speed.setEnergyInputRatioFunctionofAirFlowFractionCurve(cool_eir_fflow) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = model_add_curve(coil_cooling_dx_variable_speed.model, ac_props['cool_plf_fplr'])
    if cool_plf_fplr
      coil_cooling_dx_variable_speed.setEnergyPartLoadFractionCurve(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Applies performance curves to "CoilHeatingVariableSpeed" object.
  def coil_heating_dx_variable_speed_apply_curves(coil_heating_dx_variable_speed, eqpt_name)
    successfully_set_all_properties = true

    # Get the search criteria
    search_criteria = {}
    search_criteria['name'] = eqpt_name

    # Get the capacity
    capacity_w = coil_heating_dx_variable_speed_find_capacity(coil_heating_dx_variable_speed)
    capacity_w = [1.0,capacity_w].max
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Lookup performance curves
    props = model_find_object(standards_data['tables']['heat_pump_heating_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FT curve
    heat_cap_ft = model_add_curve(coil_heating_dx_variable_speed.model, props['heat_cap_ft'])
    if heat_cap_ft
      coil_heating_dx_variable_speed.speeds.each { |speed| speed.setHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find heat_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FFLOW curve
    heat_cap_fflow = model_add_curve(coil_heating_dx_variable_speed.model, props['heat_cap_fflow'])
    if heat_cap_fflow
      coil_heating_dx_variable_speed.speeds.each { |speed| speed.setTotalHeatingCapacityFunctionofAirFlowFractionCurve(heat_cap_fflow) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find heat_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FT curve
    heat_eir_ft = model_add_curve(coil_heating_dx_variable_speed.model, props['heat_eir_ft'])
    if heat_eir_ft
      coil_heating_dx_variable_speed.speeds.each { |speed| speed.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSingleSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find heat_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FFLOW curve
    heat_eir_fflow = model_add_curve(coil_heating_dx_variable_speed.model, props['heat_eir_fflow'])
    if heat_eir_fflow
      coil_heating_dx_variable_speed.speeds.each { |speed| speed.setEnergyInputRatioFunctionofAirFlowFractionCurve(heat_eir_fflow) }
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find heat_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-PLF-FPLR curve
    heat_plf_fplr = model_add_curve(coil_heating_dx_variable_speed.model, props['heat_plf_fplr'])
    if heat_plf_fplr
      coil_heating_dx_variable_speed.setEnergyPartLoadFractionCurve(heat_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find heat_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the heat_defrost_eir_ft
    heat_defrost_eir_ft = model_add_curve(coil_heating_dx_variable_speed.model, props['heat_defrost_eir_ft'])
    if heat_defrost_eir_ft
      coil_heating_dx_variable_speed.setDefrostEnergyInputRatioFunctionofTemperatureCurve(heat_defrost_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find heat_defrost_eir_ft curve, will not be set")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Applies the cooling performance curves to "AirConditionerVariableRefrigerantFlow" object.
  def airconditioner_variablerefrigerantflow_cooling_apply_curves(airconditioner_variablerefrigerantflow, eqpt_name)
    successfully_set_all_properties = true

    search_criteria = {}
    search_criteria['name'] = eqpt_name
    # Get the capacity
    capacity_w = airconditioner_variablerefrigerantflow_cooling_find_capacity(airconditioner_variablerefrigerantflow)
    capacity_w = [1.0,capacity_w].max
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Lookup performance curves
    props = model_find_object(standards_data['tables']['heat_pump_cooling_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find efficiency info using #{search_criteria}, cannot apply efficiency.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FT Low curve
    cool_cap_ft_low = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_cap_ft_low'])
    if cool_cap_ft_low
      airconditioner_variablerefrigerantflow.setCoolingCapacityRatioModifierFunctionofLowTemperatureCurve(cool_cap_ft_low)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_cap_ft_low curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FT boundary curve
    cool_cap_ft_boundary = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_cap_ft_boundary'])
    if cool_cap_ft_boundary
      airconditioner_variablerefrigerantflow.setCoolingCapacityRatioBoundaryCurve(cool_cap_ft_boundary)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_cap_ft_boundary curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FT high curve
    cool_cap_ft_high = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_cap_ft_high'])
    if cool_cap_ft_high
      airconditioner_variablerefrigerantflow.setCoolingCapacityRatioModifierFunctionofHighTemperatureCurve(cool_cap_ft_high)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_cap_ft_high curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FT low curve
    cool_eir_ft_low = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_eir_ft_low'])
    if cool_eir_ft_low
      airconditioner_variablerefrigerantflow.setCoolingEnergyInputRatioModifierFunctionofLowTemperatureCurve(cool_eir_ft_low)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_eir_ft_low curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FT boundary curve
    cool_eir_ft_boundary = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_eir_ft_boundary'])
    if cool_eir_ft_boundary
      airconditioner_variablerefrigerantflow.setCoolingEnergyInputRatioBoundaryCurve(cool_eir_ft_boundary)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_eir_ft_boundary curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FT high curve
    cool_eir_ft_high = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_eir_ft_high'])
    if cool_eir_ft_high
      airconditioner_variablerefrigerantflow.setCoolingEnergyInputRatioModifierFunctionofHighTemperatureCurve(cool_eir_ft_high)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_eir_ft_high curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FPLR low curve
    cool_eir_fplr_low = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_eir_fplr_low'])
    if cool_eir_fplr_low
      airconditioner_variablerefrigerantflow.setCoolingEnergyInputRatioModifierFunctionofLowPartLoadRatioCurve(cool_eir_fplr_low)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_eir_fplr_low curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FPLR high curve
    cool_eir_fplr_high = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_eir_fplr_high'])
    if cool_eir_fplr_high
      airconditioner_variablerefrigerantflow.setCoolingEnergyInputRatioModifierFunctionofHighPartLoadRatioCurve(cool_eir_fplr_high)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_eir_fplr_high curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CCR curve
    cool_ccr = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_ccr'])
    if cool_ccr
      airconditioner_variablerefrigerantflow.setCoolingCombinationRatioCorrectionFactorCurve(cool_ccr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_ccr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_plf_fplr'])
    if cool_plf_fplr
      airconditioner_variablerefrigerantflow.setCoolingPartLoadFractionCorrelationCurve(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_plf_fplr'])
    if cool_plf_fplr
      airconditioner_variablerefrigerantflow.setCoolingPartLoadFractionCorrelationCurve(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FPL curve
    cool_cap_fpl = model_add_curve(airconditioner_variablerefrigerantflow.model, props['cool_cap_fpl'])
    if cool_cap_fpl
      airconditioner_variablerefrigerantflow.setPipingCorrectionFactorforLengthinCoolingModeCurve(cool_cap_fpl)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_cap_fpl curve, will not be set.")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Applies the heating performance curves to "AirConditionerVariableRefrigerantFlow" object.
  def airconditioner_variablerefrigerantflow_heating_apply_curves(airconditioner_variablerefrigerantflow, eqpt_name)
    successfully_set_all_properties = true

    search_criteria = {}
    search_criteria['name'] = eqpt_name
    # Get the capacity
    capacity_w = airconditioner_variablerefrigerantflow_heating_find_capacity(airconditioner_variablerefrigerantflow)
    capacity_w = [1.0,capacity_w].max
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Lookup performance curves
    props = model_find_object(standards_data['tables']['heat_pump_heating_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heating efficiency info using #{search_criteria}, cannot apply efficiency.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FT Low curve
    heat_cap_ft_low = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_cap_ft_low'])
    if heat_cap_ft_low
      airconditioner_variablerefrigerantflow.setHeatingCapacityRatioModifierFunctionofLowTemperatureCurve(heat_cap_ft_low)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_cap_ft_low curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FT boundary curve
    heat_cap_ft_boundary = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_cap_ft_boundary'])
    if heat_cap_ft_boundary
      airconditioner_variablerefrigerantflow.setHeatingCapacityRatioBoundaryCurve(heat_cap_ft_boundary)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standard.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_cap_ft_boundary curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FT high curve
    heat_cap_ft_high = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_cap_ft_high'])
    if heat_cap_ft_high
      airconditioner_variablerefrigerantflow.setHeatingCapacityRatioModifierFunctionofHighTemperatureCurve(heat_cap_ft_high)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_cap_ft_high curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FT low curve
    heat_eir_ft_low = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_eir_ft_low'])
    if heat_eir_ft_low
      airconditioner_variablerefrigerantflow.setHeatingEnergyInputRatioModifierFunctionofLowTemperatureCurve(heat_eir_ft_low)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_eir_ft_low curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FT boundary curve
    heat_eir_ft_boundary = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_eir_ft_boundary'])
    if heat_eir_ft_boundary
      airconditioner_variablerefrigerantflow.setHeatingEnergyInputRatioBoundaryCurve(heat_eir_ft_boundary)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_eir_ft_boundary curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FT high curve
    heat_eir_ft_high = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_eir_ft_high'])
    if heat_eir_ft_high
      airconditioner_variablerefrigerantflow.setHeatingEnergyInputRatioModifierFunctionofHighTemperatureCurve(heat_eir_ft_high)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_eir_ft_high curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FPLR low curve
    heat_eir_fplr_low = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_eir_fplr_low'])
    if heat_eir_fplr_low
      airconditioner_variablerefrigerantflow.setHeatingEnergyInputRatioModifierFunctionofLowPartLoadRatioCurve(heat_eir_fplr_low)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_eir_fplr_low curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FPLR high curve
    heat_eir_fplr_high = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_eir_fplr_high'])
    if heat_eir_fplr_high
      airconditioner_variablerefrigerantflow.setHeatingEnergyInputRatioModifierFunctionofHighPartLoadRatioCurve(heat_eir_fplr_high)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_eir_fplr_high curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-HCR curve
    heat_hcr = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_hcr'])
    if heat_hcr
      airconditioner_variablerefrigerantflow.setHeatingCombinationRatioCorrectionFactorCurve(heat_hcr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_hcr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-PLF-FPLR curve
    heat_plf_fplr = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_plf_fplr'])
    if heat_plf_fplr
      airconditioner_variablerefrigerantflow.setHeatingPartLoadFractionCorrelationCurve(heat_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FPL curve
    heat_cap_fpl = model_add_curve(airconditioner_variablerefrigerantflow.model, props['heat_cap_fpl'])
    if heat_cap_fpl
      airconditioner_variablerefrigerantflow.setPipingCorrectionFactorforLengthinHeatingModeCurve(heat_cap_fpl)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heat_cap_fpl curve, will not be set.")
      successfully_set_all_properties = false
    end

  end

  # =============================================================================================================================
  # Find efficiency for "CoilCoolingDXSingleSpeed" object
  def coil_cooling_dx_single_speed_apply_cop(coil_cooling_dx_single_speed,
                                             search_criteria,
                                             rename = false)
    multiplier = nil
    if ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_single_speed))
      thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil_cooling_dx_single_speed)
      multiplier = thermal_zone.multiplier if !thermal_zone.nil?
    end
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    ac_props = model_find_object(standards_data['tables']['heat_pump_cooling_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency
    cop = nil

    # If specified as SEER
    unless ac_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless ac_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as SEER (heat pump)
    unless ac_props['minimum_seasonal_efficiency'].nil?
      min_seer = ac_props['minimum_seasonal_efficiency']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless ac_props['minimum_full_load_efficiency'].nil?
      min_eer = ac_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as COP
    unless ac_props['minimum_coefficient_of_performance_cooling'].nil?
      cop = ac_props['minimum_coefficient_of_performance_cooling']
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; COP = #{cop}")
    end

    # Rename
    if rename
      coil_cooling_dx_single_speed.setName(new_comp_name)
    end

    # Set COP
    coil_cooling_dx_single_speed.setRatedCOP(cop.to_f) unless cop.nil?

  end

  # =============================================================================================================================
  # Find efficiency for "CoilHeatingDXSingleSpeed" object
  def coil_heating_dx_single_speed_apply_cop(coil_heating_dx_single_speed,
                                             search_criteria,
                                             rename = false)

    capacity_w = OpenstudioStandards::HVAC.coil_heating_get_paired_coil_cooling_capacity(coil_heating_dx_single_speed)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    props = model_find_object(standards_data['tables']['heat_pump_heating_ecm'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{coil_heating_dx_single_speed.name}, cannot find efficiency info using #{search_criteria}")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency
    cop = nil

    # If specified as EER
    unless props['minimum_energy_efficiency_ratio'].nil?
      min_eer = props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_heating_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{template}: #{coil_heating_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as HSPF (heat pump)
    unless props['minimum_heating_seasonal_performance_factor'].nil?
      min_hspf = props['minimum_heating_seasonal_performance_factor']
      cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(min_hspf)
      new_comp_name = "#{coil_heating_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}HSPF"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{template}: #{coil_heating_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless props['minimum_full_load_efficiency'].nil?
      min_eer = props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_heating_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{template}: #{coil_heating_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as COP
    unless props['minimum_coefficient_of_performance_heating'].nil?
      cop_min = props['minimum_coefficient_of_performance_heating']
      cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(cop_min, capacity_w)
      new_comp_name = "#{coil_heating_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXSingleSpeed', "For #{template}: #{coil_heating_dx_single_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Rename
    if rename
      coil_heating_dx_single_speed.setName(new_comp_name)
    end

    # Set COP
    coil_heating_dx_single_speed.setRatedCOP(cop.to_f) unless cop.nil?

  end

  # =============================================================================================================================
  # Find efficiency for "CoilCoolingDXVariableSpeed" object
  def coil_cooling_dx_variable_speed_apply_cop(coil_cooling_dx_variable_speed,
                                               search_criteria,
                                               rename = false)

    capacity_w = coil_cooling_dx_variable_speed_find_capacity(coil_cooling_dx_variable_speed)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    ac_props = model_find_object(standards_data['tables']['heat_pump_cooling_ecm']['table'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name}, cannot find efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency
    cop = nil

    # If specified as SEER
    unless ac_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{template}: #{coil_cooling_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless ac_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{template}: #{coil_cooling_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as SEER (heat pump)
    unless ac_props['minimum_seasonal_efficiency'].nil?
      min_seer = ac_props['minimum_seasonal_efficiency']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{template}: #{coil_cooling_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless ac_props['minimum_full_load_efficiency'].nil?
      min_eer = ac_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{template}: #{coil_cooling_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as COP
    unless ac_props['minimum_coefficient_of_performance_cooling'].nil?
      cop = ac_props['minimum_coefficient_of_performance_cooling']
      new_comp_name = "#{coil_cooling_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{template}: #{coil_cooling_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; COP = #{cop}")
    end

    # Rename
    if rename
      coil_cooling_dx_variable_speed.setName(new_comp_name)
    end

    # Set COP values
    coil_cooling_dx_variable_speed.speeds.each { |speed| speed.setReferenceUnitGrossRatedCoolingCOP(cop.to_f) } unless cop.nil?

  end

  # =============================================================================================================================
  # Find efficiency for "CoilHeatingDXVariableSpeed" object
  def coil_heating_dx_variable_speed_apply_cop(coil_heating_dx_variable_speed,
                                               search_criteria,
                                               rename = false)

    capacity_w = coil_heating_dx_variable_speed_find_capacity(coil_heating_dx_variable_speed)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    props = model_find_object(standards_data['tables']['heat_pump_heating_ecm'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name}, cannot find efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency
    cop = nil

    # If specified as EER
    unless props['minimum_energy_efficiency_ratio'].nil?
      min_eer = props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_heating_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{template}: #{coil_heating_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as HSPF (heat pump)
    unless props['minimum_heating_seasonal_performance_factor'].nil?
      min_hspf = props['minimum_heating_seasonal_performance_factor']
      cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(min_hspf)
      new_comp_name = "#{coil_heating_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}HSPF"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{template}: #{coil_heating_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless props['minimum_full_load_efficiency'].nil?
      min_eer = props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_heating_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{template}: #{coil_heating_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as COP
    unless props['minimum_coefficient_of_performance_heating'].nil?
      min_cop = props['minimum_coefficient_of_performance_heating']
      cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(min_cop, capacity_w)
      new_comp_name = "#{coil_heating_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{template}: #{coil_heating_dx_variable_speed.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Rename
    if rename
      coil_heating_dx_variable_speed.setName(new_comp_name)
    end

    # Set COP values
    coil_heating_dx_variable_speed.speeds.each { |speed| speed.setReferenceUnitGrossRatedHeatingCOP(cop.to_f) } unless cop.nil?

  end

  # =============================================================================================================================
  # Find cooling efficiency for "AirConditionerVariableRefrigerantFlow" object
  def airconditioner_variablerefrigerantflow_cooling_apply_cop(airconditioner_variablerefrigerantflow,
                                                               search_criteria,
                                                               rename = false)

    capacity_w = airconditioner_variablerefrigerantflow_cooling_find_capacity(airconditioner_variablerefrigerantflow)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    props = model_find_object(standards_data['tables']['heat_pump_cooling_ecm'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency
    cop = nil

    # If specified as EER
    unless props['minimum_energy_efficiency_ratio'].nil?
      min_eer = props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{airconditioner_variablerefrigerantflow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as HSPF (heat pump)
    unless props['minimum_heating_seasonal_performance_factor'].nil?
      min_hspf = props['minimum_heating_seasonal_performance_factor']
      cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(min_hspf)
      new_comp_name = "#{coil_heating_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}HSPF"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless props['minimum_full_load_efficiency'].nil?
      min_eer = props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{airconditioner_variablerefrigerantflow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as COP
    unless props['minimum_coefficient_of_performance_cooling'].nil?
      cop = props['minimum_coefficient_of_performance_cooling']
      new_comp_name = "#{airconditioner_variablerefrigerantflow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Rename
    if rename
      airconditioner_variablerefrigerantflow.setName(new_comp_name)
    end

    # Set COP
    unless cop.nil?
      if airconditioner_variablerefrigerantflow.model.version < OpenStudio::VersionString.new('2.9.0')
        airconditioner_variablerefrigerantflow.setRatedCoolingCOP(cop.to_f)
      else
        airconditioner_variablerefrigerantflow.setGrossRatedCoolingCOP(cop.to_f)
      end
    end
  end

  # =============================================================================================================================
  # Find heating efficiency for "AirConditionerVariableRefrigerantFlow" object
  def airconditioner_variablerefrigerantflow_heating_apply_cop(airconditioner_variablerefrigerantflow,
                                                               search_criteria,
                                                               rename = false)

    capacity_w = airconditioner_variablerefrigerantflow_heating_find_capacity(airconditioner_variablerefrigerantflow)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    props = model_find_object(standards_data['tables']['heat_pump_heating_ecm'], search_criteria, capacity_btu_per_hr)

    # Check to make sure properties were found
    if props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name}, cannot find heating efficiency info using #{search_criteria}.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency
    cop = nil

    # If specified as EER
    unless props['minimum_energy_efficiency_ratio'].nil?
      min_eer = props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{airconditioner_variablerefrigerantflow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as HSPF (heat pump)
    unless props['minimum_heating_seasonal_performance_factor'].nil?
      min_hspf = props['minimum_heating_seasonal_performance_factor']
      cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(min_hspf)
      new_comp_name = "#{coil_heating_dx_variable_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}HSPF"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless props['minimum_full_load_efficiency'].nil?
      min_eer = props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{airconditioner_variablerefrigerantflow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as COP
    unless props['minimum_coefficient_of_performance_heating'].nil?
      min_cop = props['minimum_coefficient_of_performance_heating']
      cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(min_cop, capacity_w)
      new_comp_name = "#{airconditioner_variablerefrigerantflow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{airconditioner_variablerefrigerantflow.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Rename
    if rename
      airconditioner_variablerefrigerantflow.setName(new_comp_name)
    end

    # Set COP
    airconditioner_variablerefrigerantflow.setRatedHeatingCOP(cop.to_f) unless cop.nil?

  end

  # =============================================================================================================================
  # Find cooling capacity for "CoilCoolingDXVariableSpeed" object
  def coil_cooling_dx_variable_speed_find_capacity(coil_cooling_dx_variable_speed)
    capacity_w = nil
    if coil_cooling_dx_variable_speed.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
      capacity_w = coil_cooling_dx_variable_speed.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.get
    elsif coil_cooling_dx_variable_speed.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
      capacity_w = coil_cooling_dx_variable_speed.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXVariableSpeed', "For #{coil_cooling_dx_variable_speed.name} capacity is not available.")
      return 0.0
    end

    return capacity_w
  end

  # =============================================================================================================================
  # Find heating capacity for "CoilHeatingDXVariableSpeed" object
  def coil_heating_dx_variable_speed_find_capacity(coil_heating_dx_variable_speed)
    capacity_w = nil
    if coil_heating_dx_variable_speed.ratedHeatingCapacityAtSelectedNominalSpeedLevel.is_initialized
      capacity_w = coil_heating_dx_variable_speed.ratedHeatingCapacityAtSelectedNominalSpeedLevel.get
    elsif coil_heating_dx_variable_speed.autosizedRatedHeatingCapacityAtSelectedNominalSpeedLevel.is_initialized
      capacity_w = coil_heating_dx_variable_speed.autosizedRatedHeatingCapacityAtSelectedNominalSpeedLevel.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXVariableSpeed', "For #{coil_heating_dx_variable_speed.name} capacity is not available.")
      return 0.0
    end

    return capacity_w
  end

  # =============================================================================================================================
  # Find cooling capacity for "AirConditionerVariableRefrigerantFlow" object
  def airconditioner_variablerefrigerantflow_cooling_find_capacity(airconditioner_variablerefrigerantflow)
    capacity_w = nil
    if airconditioner_variablerefrigerantflow.ratedTotalCoolingCapacity.is_initialized
      capacity_w = airconditioner_variablerefrigerantflow.ratedTotalCoolingCapacity.get
    elsif airconditioner_variablerefrigerantflow.autosizedRatedTotalCoolingCapacity.is_initialized
      capacity_w = airconditioner_variablerefrigerantflow.autosizedRatedTotalCoolingCapacity.get
      airconditioner_variablerefrigerantflow.setRatedTotalCoolingCapacity(capacity_w)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name} cooling capacity is not available.")
      return 0.0
    end

    return capacity_w
  end

  # =============================================================================================================================
  # Find heating capacity for "AirConditionerVariableRefrigerantFlow" object
  def airconditioner_variablerefrigerantflow_heating_find_capacity(airconditioner_variablerefrigerantflow)
    capacity_w = nil
    if airconditioner_variablerefrigerantflow.ratedTotalHeatingCapacity.is_initialized
      capacity_w = airconditioner_variablerefrigerantflow.ratedTotalHeatingCapacity.get
    elsif airconditioner_variablerefrigerantflow.autosizedRatedTotalHeatingCapacity.is_initialized
      capacity_w = airconditioner_variablerefrigerantflow.autosizedRatedTotalHeatingCapacity.get
      airconditioner_variablerefrigerantflow.setRatedTotalHeatingCapacity(capacity_w)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{airconditioner_variablerefrigerantflow.name} heating capacity is not available.")
      return 0.0
    end

    return capacity_w
  end

  # ============================================================================================================================
  # Apply boiler efficiency
  # This model takes an OS model and a boiler efficiency string or hash sent to it with the following form:
  #    "boiler_eff": {
  #        "name" => "NECB 88% Efficient Condensing Boiler",
  #        "efficiency" => 0.88,
  #        "part_load_curve" => "BOILER-EFFPLR-COND-NECB2011",
  #        "notes" => "From NECB 2011."
  #    }
  # If boiler_eff is nill then it does nothing.  If both "efficiency" and "part_load_curve" are nil then it does
  # nothing.  If a boiler_eff is passed as a string and not a hash then it looks for a "name" field in the
  # boiler_set.json file that matches boiler_eff and gets the associated boiler performance details from the file.
  # If an efficiency is set but is not between 0.01 and 1.0 it returns an error.  Otherwise, it looks for plant loop
  # supply components that match the "OS_BoilerHotWater" type.  If it finds one it then calls the
  # "reset_boiler_efficiency method which resets the the boiler efficiency and looks for the part load efficiency curve
  # in the curves.json file.  If it finds a curve it sets the part load curve to that, otherwise it returns an error.
  # It also renames the boiler to include the "boiler_eff"["name"].
  def modify_boiler_efficiency(model:, boiler_eff: nil)
    return if boiler_eff.nil?

    # If boiler_eff is a string rather than a hash then assume it is the name of a boiler efficiency package and look
    # for a package with that name in boiler_set.json.
    if boiler_eff.is_a?(String)
      eff_packages = @standards_data['tables']['boiler_eff_ecm']['table']
      eff_package = eff_packages.select { |eff_pack_info| eff_pack_info['name'] == boiler_eff }

      raise "Cannot not find #{boiler_eff} in the ECMS boiler_set.json file.  Please check that the name is correctly spelled in the ECMS class boiler_set.json and in the code calling (directly or through another method) the ECMS class modify_boiler_efficiency method." if eff_package.empty?
      raise "More than one boiler efficiency package with the name #{boiler_eff} was found.  Please check the ECMS class boiler_set.json file and make sure that each boiler efficiency package has a unique name." if eff_package.size > 1

      ecm_name = boiler_eff
      boiler_eff = {
        'name' => ecm_name,
        'efficiency' => eff_package[0]['efficiency'],
        'part_load_curve' => eff_package[0]['part_load_curve']
      }
    end
    # If nothing is passed in the boiler_eff hash then assume this was not supposed to be used and return without doing
    # anything.
    return if boiler_eff['name'].nil? && boiler_eff['efficiency'].nil? && boiler_eff['part_load_curve'].nil?
    # If no efficiency or partload curve are found (either passed directly or via the boiler_set.json file) then assume
    # that the current SHW setting should not be changed.  Return without changing anything.
    return if boiler_eff['efficiency'].nil? && boiler_eff['part_load_curve'].nil?
    raise 'You attempted to set the efficiency of boilers in this model to nil. Please check the ECMS class boiler_set.json and make sure the efficiency is properly set' if boiler_eff['efficiency'].nil?
    raise "You attempted to set the efficiency of boilers in this model to: #{boiler_eff['efficiency']}. Please check the ECMS class boiler_set.json and make sure the efficiency you set is between 0.01 and 1.0." if boiler_eff['efficiency'] < 0.01 || boiler_eff['efficiency'] > 1.0
    raise 'You attempted to set the part load curve of boilers in this model to nil.  Please check the ECMS class boiler_set.json file and ensure that both the efficiency and part load curve are set.' if boiler_eff['part_load_curve'].nil?

    model.getBoilerHotWaters.sort.each do |mod_boiler|
      if mod_boiler.fuelType.to_s.downcase == 'electricity'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.BoilerHotWater', "The boiler #{mod_boiler.name.to_s} is electrically powered.  Only the efficiencies of fuel fired boilers are modified.  The efficiency of this boiler will not be changed.")
        next
      end
      reset_boiler_efficiency(model: model, component: mod_boiler.to_BoilerHotWater.get, eff: boiler_eff)
    end
  end

  # This method takes an OS model, a "OS_BoilerHotWater" type compenent, condensing efficiency limit and an efficiency
  # hash which looks like:
  #    "eff": {
  #        "name": "NECB 88% Efficient Condensing Boiler",
  #        "efficiency" => 0.88,
  #        "part_load_curve" => "BOILER-EFFPLR-COND-NECB2011",
  #        "notes" => "From NECB 2011."
  #    }
  # This method sets efficiency of the boiler to whatever is entered in eff["efficiency"].  It then looks for the
  # "part_load_curve" value in the curves.json file. If it does not find one it returns an error.  If it finds one it
  # reset the part load curve to whatever was found. It then determines the nominal capacity of the boiler.  If the
  # nominal capacity is greater than 1W the boiler is considered a primary boiler (for the name only) if the capacity is
  # less than 1W the boiler is considered a secondary boiler (for the name only).  It then renames the boiler according
  # to the following pattern:
  # "Primary/Secondary eff["name"] capacity kBtu/hr".
  def reset_boiler_efficiency(model:, component:, eff:)
    component.setNominalThermalEfficiency(eff['efficiency'])
    part_load_curve_name = eff['part_load_curve'].to_s
    existing_curve = @standards_data['curves'].select { |curve| curve['name'] == part_load_curve_name }
    raise "No boiler with the name #{part_load_curve_name} could be found in the ECMS class curves.json file.  Please check both the ECMS class boiler_set.json and class curves.json files to ensure the curve is entered and referenced correctly." if existing_curve.empty?

    part_load_curve_data = (@standards_data['curves'].select { |curve| curve['name'] == part_load_curve_name })[0]
    if part_load_curve_data['independent_variable_1'].to_s.upcase == 'TEnteringBoiler'.upcase || part_load_curve_data['independent_variable_2'].to_s.upcase == 'TEnteringBoiler'.upcase
      component.setEfficiencyCurveTemperatureEvaluationVariable('EnteringBoiler')
    elsif part_load_curve_data['independent_variable_1'].to_s.upcase == 'TLeavingBoiler'.upcase || part_load_curve_data['independent_variable_2'].to_s.upcase == 'TLeavingBoiler'.upcase
      component.setEfficiencyCurveTemperatureEvaluationVariable('LeavingBoiler')
    end
    part_load_curve = model_add_curve(model, part_load_curve_name)
    raise "There was a problem setting the boiler part load curve named #{part_load_curve_name} for #{component.name}.  Please ensure that the curve is entered and referenced correctly in the ECMS class curves.json and boiler_set.json files." unless part_load_curve

    component.setNormalizedBoilerEfficiencyCurve(part_load_curve)
    if component.nominalCapacity.is_initialized
      boiler_size_w = component.nominalCapacity.to_f
    elsif component.isNominalCapacityAutosized
      boiler_size_w = component.autosizedNominalCapacity.get
    end
    boiler_size_kbtu_per_hour = OpenStudio.convert(boiler_size_w, 'W', 'kBtu/h').get
    boiler_primacy = 'Primary '
    if boiler_size_w < 1.0 || component.name.to_s.upcase.include?("SECONDARY")
      boiler_primacy = 'Secondary '
    end
    if eff['name'].nil?
      eff_measure_name = 'Revised Performance Boiler'
    else
      eff_measure_name = eff['name']
    end
    old_boiler_name = component.name.to_s
    new_boiler_name = (boiler_primacy + eff_measure_name + " #{boiler_size_kbtu_per_hour.round(0)}kBtu/hr #{component.nominalThermalEfficiency} Thermal Eff").strip
    component.setName(new_boiler_name)
  end

  # ============================================================================================================================
  # Apply Furnace efficiency
  # This model takes an OS model and a furnace efficiency string or hash sent to it with the following form:
  #    "furnace_eff": {
  #        "name" => "NECB 85% Efficient Condensing Furnace",
  #        "efficiency" => 0.85,
  #        "part_load_curve" => "FURNACE-EFFPLR-COND-NECB2011",
  #        "notes" => "From NECB 2011."
  #    }
  # If furnace_eff is nil then it does nothing.  If both "efficiency" and "part_load_curve" are nil then it does
  # nothing.  If a furnace_eff is a string it looks for furnace_eff as a "name" in the furnace_set.json file to find
  # the performance details.  If an efficiency is set but is not between 0.01 and 1.0 it returns an error.  Otherwise,
  # it looks for air loop supply components that match the "OS_CoilHeatingGas" type.  If it finds one it then calls the
  # reset_furnace_efficiency method which resets the the furnace efficiency and looks for the part load efficiency curve
  # in the curves.json file.  If it finds a curve it sets the part load curve to that, otherwise it returns an error. It
  # also renames the furnace to include the "furnace_eff"["name"].
  def modify_furnace_efficiency(model:, furnace_eff: nil)
    return if furnace_eff.nil?

    # If furnace_eff is a string rather than a hash then assume it is the name of a furnace efficiency package and look
    # for a package with that name in furnace_set.json.
    if furnace_eff.is_a?(String)
      eff_packages = @standards_data['tables']['furnace_eff_ecm']['table']
      eff_package = eff_packages.select { |eff_pack_info| eff_pack_info['name'] == furnace_eff }

      raise "Cannot not find #{furnace_eff} in the ECMS furnace_set.json file.  Please check that the name is correctly spelled in the ECMS class furnace_set.json and in the code calling (directly or through another method) the ECMS class modify_furnace_efficiency method." if eff_package.empty?
      raise "More than one furnace efficiency package with the name #{furnace_eff} was found.  Please check the ECMS class furnace_set.json file and make sure that each furnace efficiency package has a unique name." if eff_package.size > 1

      ecm_name = furnace_eff
      furnace_eff = {
        'name' => ecm_name,
        'efficiency' => eff_package[0]['efficiency'],
        'part_load_curve' => eff_package[0]['part_load_curve']
      }
    end
    # If nothing is passed in the furnace_eff hash then assume this was not supposed to be used and return without doing
    # anything.
    return if furnace_eff['name'].nil? && furnace_eff['efficiency'].nil? && furnace_eff['part_load_curve'].nil?
    # If no efficiency or partload curve are found (either passed directly or via the furnace_set.json file) then assume
    # that the current furance performance settings should not be changed.  Return without changing anything.
    return if furnace_eff['efficiency'].nil? && furnace_eff['part_load_curve'].nil?
    raise 'You attempted to set the efficiency of furnaces in this model to nil.  Please check the ECMS class furnace_set.json file and make sure the efficiency is set' if furnace_eff['efficiency'].nil?
    raise "You attempted to set the efficiency of furnaces in this model to: #{furnace_eff['efficiency']}. Please check the ECMS class furnace_set.json file and make sure the efficiency you set is between 0.01 and 1.0." if furnace_eff['efficiency'] < 0.01 || furnace_eff['efficiency'] > 1.0
    raise 'You attempted to set the part load curve of furnaces in this model to nil.  Please check the ECMS class furnace_set.json file and ensure that both the efficiency and part load curve are set.' if furnace_eff['part_load_curve'].nil?

    model.getCoilHeatingGass.sort.each do |mod_furnace|
      reset_furnace_efficiency(model: model, component: mod_furnace.to_CoilHeatingGas.get, eff: furnace_eff)
    end
  end

  # This method takes an OS model, a "OS_CoilHeatingGas" type compenent, and an efficiency hash which looks like:
  #    "eff": {
  #        "name": "NECB 85% Efficient Condensing Furnace",
  #        "efficiency" => 0.85,
  #        "part_load_curve" => "FURNACE-EFFPLR-COND-NECB2011",
  #        "notes" => "From NECB 2011."
  #    }
  # This method sets the efficiency of the furnace to whatever is entered in eff["efficiency"].  It then looks for the
  # "part_load_curve" value in the curves.json file.  If it does not find one it returns an error.  If it finds one it
  # reset the part load curve to whatever was found.  It then renames the furnace according to the following pattern:
  # "eff["name"] + <furnace number (whatever was there before)>".
  def reset_furnace_efficiency(model:, component:, eff:)
    component.setGasBurnerEfficiency(eff['efficiency'])
    part_load_curve_name = eff['part_load_curve'].to_s
    existing_curve = @standards_data['curves'].select { |curve| curve['name'] == part_load_curve_name }
    raise "No furnace part load curve with the name #{part_load_curve_name} could be found in the ECMS class curves.json file.  Please check both the ECMS class curves.json and the measure furnace_set.json files to ensure the curve is entered and referenced correctly." if existing_curve.empty?

    part_load_curve = model_add_curve(model, part_load_curve_name)
    raise "There was a problem setting the furnace part load curve named #{part_load_curve_name} for #{component.name}.  Please ensure that the curve is entered and referenced correctly in the ECMS class curves.json or measure furnace_set.json files." unless part_load_curve

    component.setPartLoadFractionCorrelationCurve(part_load_curve)
    if eff['name'].nil?
      ecm_package_name = 'Revised Performance Furnace'
    else
      ecm_package_name = eff['name']
    end
    furnace_num = component.name.to_s.gsub(/[^0-9]/, '')
    new_furnace_name = (ecm_package_name + " #{furnace_num}").strip
    component.setName(new_furnace_name)
  end

  # ============================================================================================================================
  # Apply shw efficiency
  # This model takes an OS model and a shw efficiency string or hash sent to it with the following form:
  #    "shw_eff": {
  #        "name" => "Natural Gas Power Vent with Electric Ignition",
  #        "efficiency" => 0.94,
  #        "part_load_curve" => "SWH-EFFFPLR-NECB2011"
  #        "notes" => "From NECB 2011."
  #    }
  # If shw_eff is nil then it does nothing.  If both "efficiency" and "part_load_curve" are nil then it does nothing.
  # If shw_eff is a string then it looks for shw_eff as a "name" in the shw_set.json file for the details on the tank.
  # If an efficiency is set but is not between 0.01 and 1.0 it returns an error.  Otherwise, it looks for mixed water
  # heaters.  If it finds any it then calls the reset_shw_efficiency method which resets the the shw efficiency and the
  # part load curve. It also renames the shw tank with the following pattern:
  #   {volume}Gal {eff_name} Water Heater - {Capacity}kBtu/hr {efficiency} Therm Eff
  def modify_shw_efficiency(model:, shw_eff: nil)
    return if shw_eff.nil?

    # If shw_eff is a string rather than a hash then assume it is the name of a shw efficiency package and look
    # for a package with that name in shw_set.json.
    if shw_eff.is_a?(String)
      eff_packages = @standards_data['tables']['shw_eff_ecm']['table']
      eff_package = eff_packages.select { |eff_pack_info| eff_pack_info['name'] == shw_eff }

      raise "Cannot not find #{shw_eff} in the ECMS shw_set.json file.  Please check that the name is correctly spelled in the ECMS class shw_set.json and in the code calling (directly or through another method) the ECMS class modify_shw_efficiency method." if eff_package.empty?
      raise "More than one shw tank efficiency package with the name #{shw_eff} was found.  Please check the ECMS class shw_set.json file and make sure that each shw tank efficiency package has a unique name." if eff_package.size > 1

      ecm_name = shw_eff
      shw_eff = {
        'name' => ecm_name,
        'efficiency' => eff_package[0]['efficiency'],
        'part_load_curve' => eff_package[0]['part_load_curve']
      }
    end
    # If nothing is passed in the shw_eff hash then assume this was not supposed to be used and return without doing
    # anything.
    return if shw_eff['name'].nil? && shw_eff['efficiency'].nil? && shw_eff['part_load_curve'].nil?
    # If no efficiency or partload curve are found (either passed directly or via the shw_set.json file) then assume
    # that the current shw performance settings should not be changed.  Return without changing anything.
    return if shw_eff['efficiency'].nil? && shw_eff['part_load_curve'].nil?
    raise 'You attempted to set the efficiency of shw tanks in this model to nil.  Please check the ECMS class shw_set.json file and make sure the efficiency is set' if shw_eff['efficiency'].nil?
    raise "You attempted to set the efficiency of shw tanks in this model to: #{shw_eff['efficiency']}. Please check the ECMS class shw_set.json and make sure the efficiency you set is between 0.01 and 1.0." if shw_eff['efficiency'] < 0.01 || shw_eff['efficiency'] > 1.0
    raise 'You attempted to set the part load curve of shw tanks in this model to nil.  Please check the ECMS class shw_set.json file and ensure that both the efficiency and part load curve are set.' if shw_eff['part_load_curve'].nil?

    model.getWaterHeaterMixeds.sort.each do |shw_mod|
      reset_shw_efficiency(model: model, component: shw_mod, eff: shw_eff)
    end
  end

  # This method takes an OS model, a "OS_WaterHeaterMixed" type compenent, and an efficiency hash which looks like:
  #    "eff": {
  #        "name": "Natural Gas Power Vent with Electric Ignition",
  #        "efficiency" => 0.94,
  #        "part_load_curve" => "SWH-EFFFPLR-NECB2011",
  #        "notes" => "From NECB 2011."
  #    }
  # This method sets the efficiency of the shw heater to whatever is entered in eff["efficiency"].  It then looks for the
  # "part_load_curve" value in the curves.json file.  If it does not find one it returns an error.  If it finds one it
  # resets the part load curve to whatever was found.  It then renames the shw tank according to the following pattern:
  #   {volume}Gal {eff_name} Water Heater - {Capacity}kBtu/hr {efficiency} Therm Eff
  def reset_shw_efficiency(model:, component:, eff:)
    return if component.heaterFuelType.to_s.upcase == 'ELECTRICITY'

    eff_result = component.setHeaterThermalEfficiency(eff['efficiency'].to_f)
    raise "There was a problem setting the efficiency of the SHW #{component.name}.  Please check the ECMS class shw_set.json file or the model." unless eff_result

    part_load_curve_name = eff['part_load_curve'].to_s
    existing_curve = @standards_data['curves'].select { |curve| curve['name'] == part_load_curve_name }
    raise "No shw tank part load curve with the name #{part_load_curve_name} could be found in the ECMS class curves.json file.  Please check both the ECMS class curves.json and the measure shw_set.json files to ensure the curve is entered and referenced correctly." if existing_curve.empty?

    part_load_curve = model_add_curve(model, part_load_curve_name)
    raise "There was a problem setting the shw tank part load curve named #{part_load_curve_name} for #{component.name}.  Please ensure that the curve is entered and referenced correctly in the ECMS class curves.json and shw_set.json files." unless part_load_curve

    component.setPartLoadFactorCurve(part_load_curve)
    # Get the volume and capacity of the SHW tank.
    if component.tankVolume.is_initialized
      shw_vol_m3 = component.tankVolume.to_f
      shw_vol_gal = OpenStudio.convert(shw_vol_m3, 'm^3', 'gal').get.to_f.round(0)
    elsif component.isTankVolumeAutosized
      shw_vol_gal = 'auto_size'
    end
    if component.heaterMaximumCapacity.is_initialized
      shw_capacity_W = component.heaterMaximumCapacity.to_f
      shw_capacity_kBtu_hr = OpenStudio.convert(shw_capacity_W, 'W', 'kBtu/h').get.to_f.round(0)
    elsif component.isHeaterMaximumCapacityAutosized
      shw_capacity_kBtu_hr = 'auto_cap'
    end
    # Set a default revised shw tank name if no name is present in the eff hash.
    if eff['name'].nil?
      shw_ecm_package_name = 'Revised'
    else
      shw_ecm_package_name = eff['name']
    end
    shw_name = ("#{shw_vol_gal} Gal #{shw_ecm_package_name} Water Heater - #{shw_capacity_kBtu_hr}kBtu/hr #{eff['efficiency']} Therm Eff").strip
    component.setName(shw_name)
  end

  # ============================================================================================================================
  # Method to update the cop and/or the performance curves of unitary dx coils. The method input 'unitary_cop' can either be a
  # string or a hash. When it's a string it's used to find a hash in the json table 'unitary_cop_ecm'. When it's a hash it holds
  # the parameters needed to update the cop and/or the performance curves of the unitary coil.
  def modify_unitary_cop(model:, unitary_cop:, sizing_done:, sql_db_vars_map:)
    return if unitary_cop.nil? || (unitary_cop.to_s == 'NECB_Default')

    coils = model.getCoilCoolingDXSingleSpeeds.select {|coil| coil.name.to_s.include? '_dx'}
    coils += model.getCoilCoolingDXMultiSpeeds.select {|coil| coil.name.to_s.include? '_dx'}
    unitary_cop_copy = unitary_cop.dup
    coils.sort.each do |coil|
      coil_type = 'SingleSpeed'
      coil_type = 'MultiSpeed' if coil.class.name.to_s.include? 'CoilCoolingDXMultiSpeed'
      # if the parameter 'unitary_cop' is a string then get the information on the new parameters for the coils from
      # the json table 'unitary_cop_ecm'
      if unitary_cop_copy.is_a?(String)
        search_criteria = {}
        search_criteria['name'] = unitary_cop_copy
        coil_name = coil.name.to_s
        if (sql_db_vars_map.has_key? coil_name) && !sizing_done then coil.setName(sql_db_vars_map[coil_name]) end

        multiplier = nil
        if ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil))
          thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil)
          multiplier = thermal_zone.multiplier if !thermal_zone.nil?
        end

        if coil_type == 'SingleSpeed'
          capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil, multiplier: multiplier)
        elsif coil_type == 'MultiSpeed'
          capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_multi_speed_get_capacity(coil, multiplier: multiplier)
        end
        coil.setName(coil_name)
        cop_package = model_find_object(@standards_data['tables']['unitary_cop_ecm'], search_criteria, capacity_w)
        raise "Cannot find #{unitary_cop_ecm} in the ECMS unitary_acs.json file.  Please check that the name is correctly spelled in the ECMS class unitary_acs.json file and in the code calling (directly or through another method) the ECMS class modify_unitary_eff method." if cop_package.empty?

        ecm_name = unitary_cop_copy
        unitary_cop = {
          'name' => ecm_name,
          'maximum_capacity' => cop_package['maximum_capacity'],
          'minimum_energy_efficiency_ratio' => cop_package['minimum_energy_efficiency_ratio'],
          'minimum_seasonal_energy_efficiency_ratio' => cop_package['minimum_seasonal_energy_efficiency_ratio'],
          'minimum_coefficient_of_performance_cooling' => cop_package['minimum_coefficient_of_performance_cooling'],
          'ref_flow_rate_m3_per_sec' => cop_package['ref_flow_rate_m3_per_sec'],
          'cool_cap_ft' => cop_package['cool_cap_ft'],
          'cool_cap_fflow' => cop_package['cool_cap_fflow'],
          'cool_eir_ft' => cop_package['cool_eir_ft'],
          'cool_eir_fflow' => cop_package['cool_eir_fflow'],
          'cool_plf_fplr' => cop_package['cool_plf_fplr']
        }
      end
      next if unitary_cop['minimum_energy_efficiency_ratio'].nil? && unitary_cop['minimum_seasonal_energy_efficiency_ratio'].nil? &&
              unitary_cop['minimum_coefficient_of_performance_cooling'].nil? && unitary_cop['cool_cap_ft'].nil? && unitary_cop['cool_cap_fflow'].nil? &&
              unitary_cop['cool_eir_ft'].nil? && unitary_cop['cool_eir_fflow'].nil? && unitary_cop['cool_plf_fplr'].nil? && unitary_cop['ref_flow_rate_m3_per_sec'].nil?

      # If the dx coil is on an air loop then update its cop and the performance curves when these are specified in the ecm data
      if (coil_type == 'SingleSpeed' && coil.airLoopHVAC.is_initialized && (!coil.name.to_s.include? "_ASHP")) ||
         (coil_type == 'MultiSpeed' && coil.containingHVACComponent.get.airLoopHVAC.is_initialized)
        # Set COP if sizing run is done
        if sizing_done
          cop = nil
          if unitary_cop['minimum_energy_efficiency_ratio']
            cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(unitary_cop['minimum_energy_efficiency_ratio'].to_f)
          elsif unitary_cop['minimum_seasonal_energy_efficiency_ratio']
            cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(unitary_cop['minimum_seasonal_energy_efficiency_ratio'].to_f)
          elsif unitary_cop['minimum_coefficient_of_performance_cooling']
            cop = unitary_cop['minimum_coefficient_of_performance_cooling'].to_f
          end
          if coil_type == 'SingleSpeed'
            coil.setRatedCOP(cop) if cop
          elsif coil_type == 'MultiSpeed'
            coil.stages.sort.each do |stage|
              stage.setGrossRatedCoolingCOP(cop) if cop
            end
          end
          coil.setName('CoilCoolingDXSingleSpeed_dx-adv') if coil_type == 'SingleSpeed'
          coil.setName('CoilCoolingDXMultiSpeed_dx-adv') if coil_type == 'MultiSpeed'
        else
        # Set performance curves before sizing run
          cool_cap_ft = nil
          cool_cap_ft = @standards_data['curves'].select { |curve| curve['name'] == unitary_cop['cool_cap_ft'] }[0] if unitary_cop['cool_cap_ft']
          cool_cap_ft = model_add_curve(model, unitary_cop['cool_cap_ft']) if cool_cap_ft
          cool_cap_fflow = nil
          cool_cap_fflow = @standards_data['curves'].select { |curve| curve['name'] == unitary_cop['cool_cap_fflow'] }[0] if unitary_cop['cool_cap_fflow']
          cool_cap_fflow = model_add_curve(model, unitary_cop['cool_cap_fflow']) if cool_cap_fflow
          cool_eir_ft = nil
          cool_eir_ft = @standards_data['curves'].select { |curve| curve['name'] == unitary_cop['cool_eir_ft'] }[0] if unitary_cop['cool_eir_ft']
          cool_eir_ft = model_add_curve(model, unitary_cop['cool_eir_ft']) if cool_eir_ft
          cool_eir_fflow = nil
          cool_eir_fflow = @standards_data['curves'].select { |curve| curve['name'] == unitary_cop['cool_eir_fflow'] }[0] if unitary_cop['cool_eir_fflow']
          cool_eir_fflow = model_add_curve(model, unitary_cop['cool_eir_fflow']) if cool_eir_fflow
          cool_plf_fplr = nil
          cool_plf_fplr = @standards_data['curves'].select { |curve| curve['name'] == unitary_cop['cool_plf_fplr'] }[0] if unitary_cop['cool_plf_fplr']
          cool_plf_fplr = model_add_curve(model, unitary_cop['cool_plf_fplr']) if cool_plf_fplr
          rated_flow_rate = nil
          rated_flow_rate = unitary_cop['ref_flow_rate_m3_per_sec'] * (capacity_w / unitary_cop['maximum_capacity']) if unitary_cop['ref_flow_rate_m3_per_sec']
          if coil_type == 'SingleSpeed'
            coil.setTotalCoolingCapacityFunctionOfTemperatureCurve(cool_cap_ft) if cool_cap_ft
            coil.setTotalCoolingCapacityFunctionOfFlowFractionCurve(cool_cap_fflow) if cool_cap_fflow
            coil.setEnergyInputRatioFunctionOfTemperatureCurve(cool_eir_ft) if cool_eir_ft
            coil.setEnergyInputRatioFunctionOfFlowFractionCurve(cool_eir_fflow) if cool_eir_fflow
            coil.setPartLoadFractionCorrelationCurve(cool_plf_fplr) if cool_plf_fplr
            coil.setRatedAirFlowRate(rated_flow_rate) if rated_flow_rate
          elsif coil_type == 'MultiSpeed'
            coil.stages.sort.each do |stage|
              stage.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft) if cool_cap_ft
              stage.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fflow) if cool_cap_fflow
              stage.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft) if cool_eir_ft
              stage.setEnergyInputRatioFunctionofFlowFractionCurve(cool_eir_fflow) if cool_eir_fflow
              stage.setPartLoadFractionCorrelationCurve(cool_plf_fplr) if cool_plf_fplr
            end
          end
        end
      end
    end
  end

  # ============================================================================================================================
  # Despite the name, this method does not actually remove any air loops.  All air loops, hot water loops, cooling and
  # any existing baseboard heaters should already be gone.  The name is an artifact of the way ECM methods are named and
  # used.  With everything gone, this method adds a hot water loop (if required) and baseboard heating back in to all
  # zones requiring heating.  Originally, code was included in the 'apply_systems' method which would prevent the air
  # loops and other stuff from being created if someone did not want them.  But others felt that that was not a clear
  # way of doing things and did not feel the performance penalty of creating objects, then removing them, then creating
  # them again was significant.
  def add_ecm_remove_airloops_add_zone_baseboards(model:,
                                                  system_zones_map:,
                                                  system_doas_flags: nil,
                                                  ecm_system_zones_map_option:,
                                                  standard:)
    # Set the primary fuel set to default to to specific fuel type.
    standards_info = standard.standards_data

    # Assign fuel sources.
    boiler_fueltype = standard.fuel_type_set.boiler_fueltype
    backup_boiler_fueltype = standard.fuel_type_set.backup_boiler_fueltype
    baseboard_type = standard.fuel_type_set.baseboard_type
    heating_coil_type_sys2 = standard.fuel_type_set.heating_coil_type_sys2
    heating_coil_type_sys3 = standard.fuel_type_set.heating_coil_type_sys3
    heating_coil_type_sys4 = standard.fuel_type_set.heating_coil_type_sys4
    heating_coil_type_sys6 = standard.fuel_type_set.heating_coil_type_sys6
    mau_heating_coil_type = 'none'

    # Create the hot water loop if necessary.
    hw_loop = standard.create_hw_loop_if_required(
      baseboard_type: baseboard_type,
      boiler_fueltype: boiler_fueltype,
      backup_boiler_fueltype: backup_boiler_fueltype,
      mau_heating_coil_type: mau_heating_coil_type,
      model: model,
      heating_coil_type_sys2: heating_coil_type_sys2,
      heating_coil_type_sys3: heating_coil_type_sys3,
      heating_coil_type_sys4: heating_coil_type_sys4,
      heating_coil_type_sys6: heating_coil_type_sys6
    )

    # Add baseboard heaters to each heated zone.
    system_zones_map.sort.each do |sname, zones|
      zones.each do |zone|
        standard.add_zone_baseboards(baseboard_type: baseboard_type,
                                     hw_loop: hw_loop,
                                     model: model,
                                     zone: zone)
      end
    end
  end

  # ============================================================================================================================
  # Apply advanced chiller measure
  def modify_chiller_efficiency(model:, chiller_type:)
    return if chiller_type.nil? || chiller_type == false || chiller_type == 'none' || chiller_type == 'NECB_Default'

    model.getChillerElectricEIRs.sort.each do |mod_chiller|
      ref_capacity_w = mod_chiller.referenceCapacity
      ref_capacity_w = ref_capacity_w.to_f

      ##### Look for a chiller set in chiller_set.json (with a capacity close to that of the existing chiller)
      chiller_set, chiller_min_cap, chiller_max_cap = find_chiller_set(chiller_type: chiller_type, ref_capacity_w: ref_capacity_w)

      ##### No need to replace any chillers with capacity = 0.001 W as per Kamel Haddad's comment
      if ref_capacity_w > 0.0011
        reset_chiller_efficiency(model: model, component: mod_chiller.to_ChillerElectricEIR.get, cop: chiller_set)
      end
    end

    ##### Change fan power of single-speed Cooling towers from 'Hard Sized' to Autosized (Otherwise, E+ gives the fatal error 'Autosizing of cooling tower UA failed for tower')
    model.getCoolingTowerSingleSpeeds.sort.each(&:autosizeFanPoweratDesignAirFlowRate)
  end

# ========================================================================================================================
  def find_chiller_set(chiller_type:, ref_capacity_w:)
    if chiller_type.is_a?(String)
      ##### Find the chiller that has the required capacity
      search_criteria = {}
      search_criteria['name'] = chiller_type
      capacity_w = ref_capacity_w
      chiller_packages = model_find_object(@standards_data['tables']['chiller_eff_ecm'], search_criteria, capacity_w)
      chiller_name = chiller_packages['notes']
      ecm_name = chiller_name
      chiller_set = {
        'notes' => ecm_name,
        'capacity_w' => chiller_packages['capacity_w'],
        'cop_w_by_w' => chiller_packages['cop_w_by_w'],
        'ref_leaving_chilled_water_temp_c' => chiller_packages['ref_leaving_chilled_water_temp_c'],
        'ref_entering_condenser_fluid_temp_c' => chiller_packages['ref_entering_condenser_fluid_temp_c'],
        'ref_chilled_water_flow_rate_m3_s' => chiller_packages['ref_chilled_water_flow_rate_m3_s'],
        'ref_condenser_fluid_flow_rate_m3_s' => chiller_packages['ref_condenser_fluid_flow_rate_m3_s'],
        'capft_curve' => chiller_packages['capft_curve'],
        'eirft_curve' => chiller_packages['eirft_curve'],
        'eirfplr_curve' => chiller_packages['eirfplr_curve'],
        'min_part_load_ratio' => chiller_packages['min_part_load_ratio'],
        'max_part_load_ratio' => chiller_packages['max_part_load_ratio'],
        'opt_part_load_ratio' => chiller_packages['opt_part_load_ratio'],
        'min_unloading_ratio' => chiller_packages['min_unloading_ratio'],
        'condenser_type' => chiller_packages['condenser_type'],
        'fraction_of_compressor_electric_consumption_rejected_by_condenser' => chiller_packages['fraction_of_compressor_electric_consumption_rejected_by_condenser'],
        'leaving_chilled_water_lower_temperature_limit_c' => chiller_packages['leaving_chilled_water_lower_temperature_limit_c'],
        'chiller_flow_mode' => chiller_packages['chiller_flow_mode'],
        'design_heat_recovery_water_flow_rate_m3_s' => chiller_packages['design_heat_recovery_water_flow_rate_m3_s']
      }
      chiller_min_cap = chiller_packages['minimum_capacity']
      chiller_max_cap = chiller_packages['maximum_capacity']
    end
    return chiller_set, chiller_min_cap, chiller_max_cap
  end

  # ============================================================================================================================
  def reset_chiller_efficiency(model:, component:, cop:)
    # Note that all parameters (except for the capacity) of an existing chiller are replaced with the ones of the VSD chiller, as per Kamel Haddad's comment.
    component.setName('ChillerElectricEIR_VSDCentrifugalWaterChiller')
    component.setReferenceCOP(cop['cop_w_by_w'])
    component.setReferenceLeavingChilledWaterTemperature(cop['ref_leaving_chilled_water_temp_c'])
    component.setReferenceEnteringCondenserFluidTemperature(cop['ref_entering_condenser_fluid_temp_c'])
    component.isReferenceChilledWaterFlowRateAutosized
    component.isReferenceCondenserFluidFlowRateAutosized
    component.setMinimumPartLoadRatio(cop['min_part_load_ratio'])
    component.setMaximumPartLoadRatio(cop['max_part_load_ratio'])
    component.setOptimumPartLoadRatio(cop['opt_part_load_ratio'])
    component.setMinimumUnloadingRatio(cop['min_unloading_ratio'])
    component.setCondenserType(cop['condenser_type'])
    component.setFractionofCompressorElectricConsumptionRejectedbyCondenser(cop['fraction_of_compressor_electric_consumption_rejected_by_condenser'])
    component.setLeavingChilledWaterLowerTemperatureLimit(cop['leaving_chilled_water_lower_temperature_limit_c'])
    component.setChillerFlowMode(cop['chiller_flow_mode'])
    component.setDesignHeatRecoveryWaterFlowRate(cop['design_heat_recovery_water_flow_rate_m3_s'])

    # set other fields of this object to nothing #Note that this could not be done for the 'Condenser Heat Recovery Relative Capacity Fraction' field as there is no 'reset' for this field.
    component.resetCondenserFanPowerRatio
    component.resetSizingFactor
    component.resetBasinHeaterCapacity
    component.resetBasinHeaterSetpointTemperature
    component.resetBasinHeaterSchedule
    component.resetHeatRecoveryInletHighTemperatureLimitSchedule
    component.resetHeatRecoveryLeavingTemperatureSetpointNode

    ##### Replace cooling_capacity_function_of_temperature (CAPFT) curve
    capft_curve_name = cop['capft_curve'].to_s
    existing_curve = @standards_data['curves'].select { |curve| curve['name'] == capft_curve_name }
    raise "No chiller with the name #{capft_curve_name} could be found in the ECMS class curves.json file.  Please check both the ECMS class chiller_set.json and curves.json files to ensure the curve is entered and referenced correctly." if existing_curve.empty?

    capft_curve_data = (@standards_data['curves'].select { |curve| curve['name'] == capft_curve_name })[0]
    capft_curve = model_add_curve(model, capft_curve_name)
    component.setCoolingCapacityFunctionOfTemperature(capft_curve) if capft_curve
    raise "There was a problem setting the CoolingCapacityFunctionOfTemperature curve named #{capft_curve_name} for #{component.name}.  Please ensure that the curve is entered and referenced correctly in the ECMS class curves.json and chiller_set.json files." if !capft_curve

    ##### Replace electric_input_to_cooling_output_ratio_function_of_temperature (EIRFT) curve
    eirft_curve_name = cop['eirft_curve'].to_s
    existing_curve = @standards_data['curves'].select { |curve| curve['name'] == eirft_curve_name }
    raise "No chiller with the name #{eirft_curve_name} could be found in the ECMS class curves.json file.  Please check both the ECMS class chiller_set.json and curves.json files to ensure the curve is entered and referenced correctly." if existing_curve.empty?

    eirft_curve_data = (@standards_data['curves'].select { |curve| curve['name'] == eirft_curve_name })[0]
    eirft_curve = model_add_curve(model, eirft_curve_name)
    component.setElectricInputToCoolingOutputRatioFunctionOfTemperature(eirft_curve) if eirft_curve
    raise "There was a problem setting the ElectricInputToCoolingOutputRatioFunctionOfTemperature curve named #{eirft_curve_name} for #{component.name}.  Please ensure that the curve is entered and referenced correctly in the ECMS class curves.json and chiller_set.json files." if !eirft_curve

    ##### Replace electric_input_to_cooling_output_ratio_function_of_part_load_ratio (EIRFPLR) curve
    eirfplr_curve_name = cop['eirfplr_curve'].to_s
    existing_curve = @standards_data['curves'].select { |curve| curve['name'] == eirfplr_curve_name }
    raise "No chiller with the name #{eirfplr_curve_name} could be found in the ECMS class curves.json file.  Please check both the ECMS class chiller_set.json and curves.json files to ensure the curve is entered and referenced correctly." if existing_curve.empty?

    eirfplr_curve_data = (@standards_data['curves'].select { |curve| curve['name'] == eirfplr_curve_name })[0]
    eirfplr_curve = model_add_curve(model, eirfplr_curve_name)
    component.setElectricInputToCoolingOutputRatioFunctionOfPLR(eirfplr_curve) if eirfplr_curve
    raise "There was a problem setting the ElectricInputToCoolingOutputRatioFunctionOfPLR curve named #{eirfplr_curve_name} for #{component.name}.  Please ensure that the curve is entered and referenced correctly in the ECMS class curves.json and chiller_set.json files." if !eirfplr_curve
  end

  # ============================================================================================================================
  # Add air side economizer for each airloop
  def add_airloop_economizer(model:, airloop_economizer_type:)
    return if airloop_economizer_type.nil? || (airloop_economizer_type.to_s == 'NECB_Default')

    if airloop_economizer_type.downcase == "differentialenthalpy"
      economizer_type = 'DifferentialEnthalpy'
    elsif airloop_economizer_type.downcase == "differentialdrybulb"
      economizer_type = 'DifferentialDryBulb'
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.airLoopHVACOutdoorAirSystem', "The air loop economizer type #{airloop_economizer_type} is not recognized.  Please make sure that the economizer being applied by the ECM is either a DifferentialEnthalpy or DifferentialDryBulb type.  No economizer will be applied.")
      return
    end

    model.getAirLoopHVACs.sort.each do |air_loop|
      oa_sys = air_loop.airLoopHVACOutdoorAirSystem
      if oa_sys.is_initialized
        oa_sys = oa_sys.get
        oa_control = oa_sys.getControllerOutdoorAir
        oa_control.setEconomizerControlType(economizer_type)
      end
    end
  end
  # ============================================================================================================================
  # Add one hot-water loop for hot-water baseboards if required
  def add_hotwater_loop(model:, fuel_type_set:)
    primary_boiler_fueltype = fuel_type_set.boiler_fueltype
    backup_boiler_fueltype = fuel_type_set.backup_boiler_fueltype
    plant_loop_names = []
    model.getPlantLoops.sort.each do |plant_loop|
      plant_loop_names << plant_loop.name.to_s
    end
    unless plant_loop_names.include? 'Hot Water Loop'
      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      setup_hw_loop_with_components(model, hw_loop, primary_boiler_fueltype, backup_boiler_fueltype, model.alwaysOnDiscreteSchedule)
    end
    return hw_loop
  end
  # ============================================================================================================================

end
