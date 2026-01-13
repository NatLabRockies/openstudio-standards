# Custom changes for the Hospital prototype.
# These are changes that are inconsistent with other prototype building types.
module Hospital
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
    # efficiency based on a 500 kVA transformer
    case template
    when '90.1-2004', '90.1-2007'
      transformer_efficiency = 0.979
    when '90.1-2010', '90.1-2013'
      transformer_efficiency = 0.987
    when '90.1-2016', '90.1-2019'
      transformer_efficiency = 0.991
    else
      transformer_efficiency = nil
    end

    unless transformer_efficiency.nil?
      model_add_transformer(model,
                            wired_lighting_frac: 0.022,
                            transformer_size: 500000,
                            transformer_efficiency: transformer_efficiency)
    end

    # add extra equipment for kitchen
    add_extra_equip_kitchen(model)

    system_to_space_map = define_hvac_system_map(building_type, climate_zone)

    hot_water_loop = nil
    model.getPlantLoops.sort.each do |loop|
      # If it has a boiler:hotwater, it is the correct loop
      unless loop.supplyComponents('OS:Boiler:HotWater'.to_IddObjectType).empty?
        hot_water_loop = loop
      end
    end
    if hot_water_loop
      case template
        when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
          space_names = ['ER_Exam3_Mult4_Flr_1', 'OR2_Mult5_Flr_2', 'ICU_Flr_2', 'PatRoom5_Mult10_Flr_4', 'Lab_Flr_3']
          space_names.each do |space_name|
            add_humidifier(space_name, hot_water_loop, model)
          end
        when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004'
          space_names = ['ER_Exam3_Mult4_Flr_1', 'OR2_Mult5_Flr_2']
          space_names.each do |space_name|
            add_humidifier(space_name, hot_water_loop, model)
          end
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', 'Could not find hot water loop to attach humidifier to.')
    end

    # adjust minimum damper positions
    model_adjust_vav_minimum_damper(model)

    reset_kitchen_oa(model)
    model_update_exhaust_fan_efficiency(model)
    model_reset_or_room_vav_minimum_damper(prototype_input, model)

    # adjust CAV system sizing
    model.getAirLoopHVACs.each do |air_loop|
      if air_loop.name.to_s.include? 'CAV_KITCHEN'
        # system sizing
        sizing_system = air_loop.sizingSystem
        prehtg_sa_temp_c = OpenStudio.convert(55.04, 'F', 'C').get
        htg_sa_temp_c = OpenStudio.convert(104.0, 'F', 'C').get
        sizing_system.setPreheatDesignTemperature(prehtg_sa_temp_c)
        sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_sa_temp_c)
        sizing_system.setSizingOption('NonCoincident')

        # set coil sizing
        htg_coil = model.getCoilHeatingWaterByName('CAV_KITCHEN Main Htg Coil').get
        htg_coil.setRatedInletAirTemperature(prehtg_sa_temp_c)
        htg_coil.setRatedOutletAirTemperature(htg_sa_temp_c)

        # replace main supply air fan
        air_loop.supplyFan.get.remove
        fan = OpenstudioStandards::HVAC.create_typical_fan(model,
                                                           'Hospital_CAV_Sytem_Fan',
                                                           fan_name: "#{air_loop.name} Fan",
                                                           end_use_subcategory: 'CAV System Fans')
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
        fan.addToNode(air_loop.supplyOutletNode)

        # replace AirTerminalSingleDuctVAVReheat with AirTerminalSingleDuctUncontrolled
        air_loop.thermalZones.each do |zone|
          # remove old terminal and reheat coil
          old_terminal = zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.get
          reheat_coil = old_terminal.reheatCoil
          reheat_coil.remove
          # in future, may need to remove plant loop if empty at end of this
          old_terminal.remove
          air_loop.removeBranchForZone(zone)

          # make new terminal
          new_terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
          new_terminal.setName("#{zone.name} CAV Terminal")
          air_loop.addBranchForZone(zone, new_terminal.to_StraightComponent)
          zone.setCoolingPriority(new_terminal.to_ModelObject.get, 1)
          zone.setHeatingPriority(new_terminal.to_ModelObject.get, 1)
        end

        # zone sizing
        zone_htg_sa_temp_c = OpenStudio.convert(104.0, 'F', 'C').get
        air_loop.thermalZones.each do |zone|
          sizing_zone = zone.sizingZone
          sizing_zone.setZoneHeatingDesignSupplyAirTemperature(zone_htg_sa_temp_c)
        end
      end
    end

    # Modify the condenser water pump
    if template == 'DOE Ref 1980-2004' || template == 'DOE Ref Pre-1980'
      cw_pump = model.getPumpConstantSpeedByName('Condenser Water Loop Constant Pump').get
      cw_pump_head_ft_h2o = 60.0
      cw_pump_head_press_pa = OpenStudio.convert(cw_pump_head_ft_h2o, 'ftH_{2}O', 'Pa').get
      cw_pump.setRatedPumpHead(cw_pump_head_press_pa)
    end

    return true
  end

  # add extra equipment for kitchen
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def add_extra_equip_kitchen(model)
    kitchen_space = model.getSpaceByName('Kitchen_Flr_5')
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
          elec_equip_def1.setDesignLevel(915)
          elec_equip_def2.setDesignLevel(855)
        elsif template == '90.1-2019'
          elec_equip_def1.setDesignLevel(555)
          elec_equip_def2.setDesignLevel(470)
        else
          elec_equip_def1.setDesignLevel(1031.8)
          elec_equip_def2.setDesignLevel(1277.5)
        end
        # Create the electric equipment instance and hook it up to the space type
        elec_equip1 = OpenStudio::Model::ElectricEquipment.new(elec_equip_def1)
        elec_equip2 = OpenStudio::Model::ElectricEquipment.new(elec_equip_def2)
        elec_equip1.setName('Kitchen_Reach-in-Freezer')
        elec_equip2.setName('Kitchen_Reach-in-Refrigerator')
        elec_equip1.setSpaceType(kitchen_space_type)
        elec_equip2.setSpaceType(kitchen_space_type)
        elec_equip1.setSchedule(model_add_schedule(model, 'Hospital ALWAYS_ON'))
        elec_equip2.setSchedule(model_add_schedule(model, 'Hospital ALWAYS_ON'))
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
        water_heater.setAmbientTemperatureThermalZone(model.getThermalZoneByName('Kitchen_Flr_5 ZN').get)
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

  # reset kitchen outdoor air
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def reset_kitchen_oa(model)
    space_kitchen = model.getSpaceByName('Kitchen_Flr_5').get
    ventilation = space_kitchen.designSpecificationOutdoorAir.get
    ventilation.setOutdoorAirFlowperPerson(0)
    ventilation.setOutdoorAirFlowperFloorArea(0)
    case template
      when '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        ventilation.setOutdoorAirFlowRate(3.398)
      when '90.1-2004', '90.1-2007', 'DOE Ref Pre-1980', 'DOE Ref 1980-2004'
        ventilation.setOutdoorAirFlowRate(3.776)
    end
    return true
  end

  # update exhuast fan efficiency
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_update_exhaust_fan_efficiency(model)
    case template
      when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        model.getFanZoneExhausts.sort.each do |exhaust_fan|
          exhaust_fan.setFanEfficiency(0.16)
          exhaust_fan.setPressureRise(125)
        end
      when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004'
        model.getFanZoneExhausts.sort.each do |exhaust_fan|
          exhaust_fan.setFanEfficiency(0.338)
          exhaust_fan.setPressureRise(125)
        end
    end
    return true
  end

  # add humidifier
  #
  # @param space_name [String] space name
  # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def add_humidifier(space_name, hot_water_loop, model)
    space = model.getSpaceByName(space_name).get
    zone = space.thermalZone.get
    humidistat = OpenStudio::Model::ZoneControlHumidistat.new(model)
    humidistat.setHumidifyingRelativeHumiditySetpointSchedule(model_add_schedule(model, 'Hospital MinRelHumSetSch'))
    humidistat.setDehumidifyingRelativeHumiditySetpointSchedule(model_add_schedule(model, 'Hospital MaxRelHumSetSch'))
    zone.setZoneControlHumidistat(humidistat)

    model.getAirLoopHVACs.sort.each do |air_loop|
      if air_loop.thermalZones.include? zone
        humidifier = OpenStudio::Model::HumidifierSteamElectric.new(model)
        humidifier.setRatedCapacity(3.72E-5)
        humidifier.setRatedPower(100_000)
        humidifier.setName("#{air_loop.name.get} Electric Steam Humidifier")
        # get the water heating coil and add humidifier to the outlet of heating coil (right before fan)
        htg_coil = nil
        air_loop.supplyComponents.each do |equip|
          if equip.to_CoilHeatingWater.is_initialized
            htg_coil = equip.to_CoilHeatingWater.get
          end
        end
        heating_coil_outlet_node = htg_coil.airOutletModelObject.get.to_Node.get
        supply_outlet_node = air_loop.supplyOutletNode
        humidifier.addToNode(heating_coil_outlet_node)
        humidity_spm = OpenStudio::Model::SetpointManagerSingleZoneHumidityMinimum.new(model)
        case template
        when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
          OpenstudioStandards::HVAC.create_coil_heating_electric(model,
                                                                 air_loop_node: supply_outlet_node,
                                                                 name: "#{space_name} Electric Htg Coil")
          OpenstudioStandards::HVAC.create_coil_heating_water(model,
                                                              hot_water_loop,
                                                              air_loop_node: supply_outlet_node,
                                                              name: "#{space_name} Water Htg Coil")
        end
        # humidity_spm.addToNode(supply_outlet_node)
        humidity_spm.addToNode(humidifier.outletModelObject.get.to_Node.get)
        humidity_spm.setControlZone(zone)
      end
    end
    return true
  end

  # add daylighting controls
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_add_daylighting_controls(model)
    space_names = ['Office1_Flr_5', 'Office3_Flr_5', 'Lobby_Records_Flr_1']
    space_names.each do |space_name|
      space = model.getSpaceByName(space_name).get
      space_add_daylighting_controls(space, false, false)
    end
    return true
  end

  # For operating room 1&2 in 2010 and 2013, VAV minimum air flow is set by schedule
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_adjust_vav_minimum_damper(model)
    model.getThermalZones.each do |zone|
      air_terminal = zone.airLoopHVACTerminal
      if air_terminal.is_initialized
        air_terminal = air_terminal.get
        if air_terminal.to_AirTerminalSingleDuctVAVReheat.is_initialized
          air_terminal = air_terminal.to_AirTerminalSingleDuctVAVReheat.get
          vav_name = air_terminal.name.get
          # High OA zones
          # Determine whether or not to use the high minimum guess.
          # Cutoff was determined by correlating apparent minimum guesses
          # to OA rates in prototypes since not well documented in papers.
          zone_oa_per_area = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate_per_area(zone)
          airlp = air_terminal.airLoopHVAC.get
          case template
          when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004'
            if vav_name.include?('PatRoom') || vav_name.include?('OR') || vav_name.include?('ICU') || vav_name.include?('Lab') || vav_name.include?('ER') || vav_name.include?('Kitchen')
              air_terminal.setConstantMinimumAirFlowFraction(1.0)
            end
          # Minimum damper position for Outpatient prototype
          # Based on AIA 2001 ventilation requirements
          # See Section 5.2.2.16 in Thornton et al. 2010
          # https://www.energycodes.gov/sites/default/files/documents/BECP_Energy_Cost_Savings_STD2010_May2011_v00.pdf
          when '90.1-2004', '90.1-2007'
            air_terminal.setConstantMinimumAirFlowFraction(1.0) unless airlp.name.to_s.include?('VAV_1') || airlp.name.to_s.include?('VAV_2')
          when '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
            air_terminal.setConstantMinimumAirFlowFraction(1.0) unless airlp.name.to_s.include?('VAV_1') || airlp.name.to_s.include?('VAV_2')
            air_terminal.setConstantMinimumAirFlowFraction(0.5) if vav_name.include? 'PatRoom'
          end
        end
      end
    end
    return true
  end

  # reset room vav damper minimums
  #
  # @param prototype_input [Hash] hash of prototype inputs
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_reset_or_room_vav_minimum_damper(prototype_input, model)
    case template
    when '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
      model.getAirTerminalSingleDuctVAVReheats.sort.each do |air_terminal|
        air_terminal_name = air_terminal.name.get
        if air_terminal_name.include?('OR1') || air_terminal_name.include?('OR2') || air_terminal_name.include?('OR3') || air_terminal_name.include?('OR4')
          if model.version < OpenStudio::VersionString.new('3.0.1')
            air_terminal.setZoneMinimumAirFlowMethod('Scheduled')
          else
            air_terminal.setZoneMinimumAirFlowInputMethod('Scheduled')
          end
          air_terminal.setMinimumAirFlowFractionSchedule(model_add_schedule(model, 'Hospital OR_MinSA_Sched'))
        end
      end
    end
    return true
  end

  # certain air handlers do not have an economizer
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_modify_oa_controller(model)
    model.getAirLoopHVACs.sort.each do |air_loop|
      oa_sys = air_loop.airLoopHVACOutdoorAirSystem.get
      oa_control = oa_sys.getControllerOutdoorAir
      case air_loop.name.get
        when 'VAV_ER', 'VAV_ICU', 'VAV_LABS', 'VAV_OR', 'VAV_PATRMS', 'CAV_1', 'CAV_2'
          oa_control.setEconomizerControlType('NoEconomizer')
      end
    end
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
end
