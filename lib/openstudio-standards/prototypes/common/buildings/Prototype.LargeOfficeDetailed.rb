# Custom changes for the LargeOffice prototype.
# These are changes that are inconsistent with other prototype building types.
module LargeOfficeDetailed
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Boolean] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    system_to_space_map = define_hvac_system_map(building_type, climate_zone)

    system_to_space_map.each do |system|
      # find all zones associated with these spaces
      thermal_zones = []
      system['space_names'].each do |space_name|
        space = model.getSpaceByName(space_name)
        if space.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No space called #{space_name} was found in the model")
          return false
        end
        space = space.get
        zone = space.thermalZone
        if zone.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No thermal zone was created for the space called #{space_name}")
          return false
        end
        thermal_zones << zone.get
      end

      return_plenum = nil
      unless system['return_plenum'].nil?
        return_plenum_space = model.getSpaceByName(system['return_plenum'])
        if return_plenum_space.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No space called #{system['return_plenum']} was found in the model")
          return false
        end
        return_plenum_space = return_plenum_space.get
        return_plenum = return_plenum_space.thermalZone
        if return_plenum.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No thermal zone was created for the space called #{system['return_plenum']}")
          return false
        end
        return_plenum = return_plenum.get
      end
    end

    # replace EvaporativeFluidCoolerSingleSpeed with CoolingTowerTwoSpeed
    model.getPlantLoops.each do |plant_loop|
      next unless plant_loop.name.to_s.include? 'Heat Pump Loop'

      sup_wtr_high_temp_f = 65.0
      sup_wtr_low_temp_f = 41.0
      sup_wtr_high_temp_c = OpenStudio.convert(sup_wtr_high_temp_f, 'F', 'C').get
      sup_wtr_low_temp_c = OpenStudio.convert(sup_wtr_low_temp_f, 'F', 'C').get
      hp_high_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                         sup_wtr_high_temp_c,
                                                                                         name: "#{plant_loop.name} High Temp - #{sup_wtr_high_temp_f.round(0)}F",
                                                                                         schedule_type_limit: 'Temperature')
      hp_low_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                        sup_wtr_low_temp_c,
                                                                                        name: "#{plant_loop.name} Low Temp - #{sup_wtr_low_temp_f.round(0)}F",
                                                                                        schedule_type_limit: 'Temperature')

      # add cooling tower object
      cooling_tower = OpenStudio::Model::CoolingTowerTwoSpeed.new(model)
      cooling_tower.setName("#{plant_loop.name} Central Tower")
      plant_loop.addSupplyBranchForComponent(cooling_tower)
      #### Add SPM Scheduled Dual Setpoint to outlet of Fluid Cooler so correct Plant Operation Scheme is generated
      cooling_tower_stpt_manager = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
      cooling_tower_stpt_manager.setName("#{plant_loop.name} Fluid Cooler Scheduled Dual Setpoint")
      cooling_tower_stpt_manager.setHighSetpointSchedule(hp_high_temp_sch)
      cooling_tower_stpt_manager.setLowSetpointSchedule(hp_low_temp_sch)
      cooling_tower_stpt_manager.addToNode(cooling_tower.outletModelObject.get.to_Node.get)

      # remove EvaporativeFluidCoolerSingleSpeed object
      model.getEvaporativeFluidCoolerSingleSpeeds.each do |fluid_cooler|
        if fluid_cooler.plantLoop.get.name.to_s == plant_loop.name.to_s
          fluid_cooler.remove
          break
        end
      end
    end

    remove_basement_infiltration(model)

    return true
  end

  # remove basement infiltration
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def remove_basement_infiltration(model)
    space_infltrations = model.getSpaceInfiltrationDesignFlowRates
    space_infltrations.each do |space_inf|
      if space_inf.name.to_s.include? 'Basement'
        space_inf = nil
      end
    end
    return true
  end

  # update water heater loss coefficient
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def update_waterheater_loss_coefficient(model)
    case template
      when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019', 'NECB2011'
        model.getWaterHeaterMixeds.sort.each do |water_heater|
          water_heater.setOffCycleLossCoefficienttoAmbientTemperature(11.25413987)
          water_heater.setOnCycleLossCoefficienttoAmbientTemperature(11.25413987)
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
