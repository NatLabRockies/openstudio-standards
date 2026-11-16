# A variety of cooling tower methods that are the same regardless of type.
# These methods are available to CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, and CoolingTowerVariableSpeed
module CoolingTower
  # @!group CoolingTower

  # Apply approach temperature sizing criteria to a condenser water loop
  #
  # @param condenser_loop [<OpenStudio::Model::PlantLoop>] a condenser loop served by a cooling tower
  # @param design_wet_bulb_c [Double] the outdoor design wetbulb conditions in degrees Celsius
  # @return [Boolean] returns true if successful, false if not
  def prototype_apply_condenser_water_temperatures(condenser_loop,
                                                   design_wet_bulb_c: nil)
    sizing_plant = condenser_loop.sizingPlant
    loop_type = sizing_plant.loopType
    return false unless loop_type == 'Condenser'

    # if values are absent, use the CTI rating condition 78F
    if design_wet_bulb_c.nil?
      design_wet_bulb_c = OpenStudio.convert(78.0, 'F', 'C').get
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', "For condenser loop #{condenser_loop.name}, no design day OATwb conditions given.  CTI rating condition of 78F OATwb will be used for sizing cooling towers.")
    end

    # EnergyPlus has a minimum limit of 68F and maximum limit of 80F for cooling towers
    design_wet_bulb_f = OpenStudio.convert(design_wet_bulb_c, 'C', 'F').get
    eplus_min_design_wet_bulb_f = 68.0
    eplus_max_design_wet_bulb_f = 80.0
    if design_wet_bulb_f < eplus_min_design_wet_bulb_f
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.CoolingTower', "For condenser loop #{condenser_loop.name}, increased design OATwb from #{design_wet_bulb_f.round(1)} F to EneryPlus model minimum limit of #{eplus_min_design_wet_bulb_f} F.")
      design_wet_bulb_f = eplus_min_design_wet_bulb_f
    elsif design_wet_bulb_f > eplus_max_design_wet_bulb_f
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.CoolingTower', "For condenser loop #{condenser_loop.name}, reduced design OATwb from #{design_wet_bulb_f.round(1)} F to EneryPlus model maximum limit of #{eplus_max_design_wet_bulb_f} F.")
      design_wet_bulb_f = eplus_max_design_wet_bulb_f
    end
    design_wet_bulb_c = OpenStudio.convert(design_wet_bulb_f, 'F', 'C').get

    # Determine the design CW temperature, approach, and range
    leaving_cw_t_c, approach_k, range_k = prototype_condenser_water_temperatures(design_wet_bulb_c)

    # Convert to IP units
    leaving_cw_t_f = OpenStudio.convert(leaving_cw_t_c, 'C', 'F').get
    approach_r = OpenStudio.convert(approach_k, 'K', 'R').get
    range_r = OpenStudio.convert(range_k, 'K', 'R').get

    # Report out design conditions
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Prototype.CoolingTower', "For condenser loop #{condenser_loop.name}, design OATwb = #{design_wet_bulb_f.round(1)} F, approach = #{approach_r.round(1)} deltaF, range = #{range_r.round(1)} deltaF, leaving condenser water temperature = #{leaving_cw_t_f.round(1)} F.")

    # Set Cooling Tower sizing parameters.
    # Only the variable speed cooling tower in E+ allows you to set the design temperatures.
    #
    # Per the documentation
    # http://bigladdersoftware.com/epx/docs/8-4/input-output-reference/group-condenser-equipment.html#field-design-u-factor-times-area-value
    # for CoolingTowerSingleSpeed and CoolingTowerTwoSpeed
    # E+ uses the following values during sizing:
    # 95F entering water temp
    # 95F OATdb
    # 78F OATwb
    # range = loop design delta-T aka range (specified above)
    condenser_loop.supplyComponents.each do |sc|
      if sc.to_CoolingTowerVariableSpeed.is_initialized
        ct = sc.to_CoolingTowerVariableSpeed.get
        ct.setDesignInletAirWetBulbTemperature(design_wet_bulb_c)
        ct.setDesignApproachTemperature(approach_k)
        ct.setDesignRangeTemperature(range_k)
      end
    end

    # Set the CW sizing parameters
    # EnergyPlus autosizing routine assumes 85F and 10F temperature difference
    energyplus_design_loop_exit_temperature_c = OpenStudio.convert(85.0, 'F', 'C').get
    sizing_plant.setDesignLoopExitTemperature(energyplus_design_loop_exit_temperature_c)
    sizing_plant.setLoopDesignTemperatureDifference(OpenStudio.convert(10.0, 'R', 'K').get)

    # Cooling Tower operational controls
    # G3.1.3.11 - Tower shall be controlled to maintain a 70F LCnWT where weather permits,
    # floating up to leaving water at design conditions.
    float_down_to_f = 70.0
    float_down_to_c = OpenStudio.convert(float_down_to_f, 'F', 'C').get

    # get or create a setpoint manager
    cw_t_stpt_manager = nil
    condenser_loop.supplyOutletNode.setpointManagers.each do |spm|
      if spm.to_SetpointManagerFollowOutdoorAirTemperature.is_initialized && spm.name.get.include?('Setpoint Manager Follow OATwb')
        cw_t_stpt_manager = spm.to_SetpointManagerFollowOutdoorAirTemperature.get
      end
    end
    if cw_t_stpt_manager.nil?
      cw_t_stpt_manager = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(condenser_loop.model)
      cw_t_stpt_manager.addToNode(condenser_loop.supplyOutletNode)
    end

    cw_t_stpt_manager.setName("#{condenser_loop.name} Setpoint Manager Follow OATwb with #{approach_r.round(1)}F Approach")
    cw_t_stpt_manager.setReferenceTemperatureType('OutdoorAirWetBulb')
    # At low design OATwb, it is possible to calculate
    # a maximum temperature below the minimum.  In this case,
    # make the maximum and minimum the same.
    if leaving_cw_t_c < float_down_to_c
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{condenser_loop.name}, the maximum leaving temperature of #{leaving_cw_t_f.round(1)} F is below the minimum of #{float_down_to_f.round(1)} F.  The maximum will be set to the same value as the minimum.")
      leaving_cw_t_c = float_down_to_c
    end
    cw_t_stpt_manager.setMaximumSetpointTemperature(leaving_cw_t_c)
    cw_t_stpt_manager.setMinimumSetpointTemperature(float_down_to_c)
    cw_t_stpt_manager.setOffsetTemperatureDifference(approach_k)

    return true
  end

  # Determine the performance rating method specified design condenser water temperature, approach, and range
  #
  # @param design_oat_wb_c [Double] the design OA wetbulb temperature (C)
  # @return [Array<Double>] [leaving_cw_t_c, approach_k, range_k]
  def prototype_condenser_water_temperatures(design_oat_wb_c)
    design_oat_wb_f = OpenStudio.convert(design_oat_wb_c, 'C', 'F').get

    # 90.1-2010 G3.1.3.11 - CW supply temp = 85F or 10F approaching design wet bulb temperature, whichever is lower.
    # Design range = 10F
    # Design Temperature rise of 10F => Range: 10F
    range_r = 10.0

    # Determine the leaving CW temp
    max_leaving_cw_t_f = 85.0
    leaving_cw_t_10f_approach_f = design_oat_wb_f + 10.0
    leaving_cw_t_f = [max_leaving_cw_t_f, leaving_cw_t_10f_approach_f].min

    # Calculate the approach
    approach_r = leaving_cw_t_f - design_oat_wb_f

    # Convert to SI units
    leaving_cw_t_c = OpenStudio.convert(leaving_cw_t_f, 'F', 'C').get
    approach_k = OpenStudio.convert(approach_r, 'R', 'K').get
    range_k = OpenStudio.convert(range_r, 'R', 'K').get

    return [leaving_cw_t_c, approach_k, range_k]
  end

  # Set the cooling tower fan power such that the tower
  # hits the minimum performance (gpm/hp) specified by the standard.
  # Note that in this case hp is motor nameplate hp, per 90.1.
  # This method assumes that the fan brake horsepower is 90%
  # of the motor nameplate hp.
  # This method determines the minimum motor efficiency
  # for the nameplate motor hp and sets the actual
  # fan power by multiplying the brake horsepower
  # by the efficiency.  Thus the fan power used as
  # an input to the simulation divided by the design flow
  # rate will not (and should not)
  # exactly equal the minimum tower performance.
  #
  # @param cooling_tower [OpenStudio::Model::StraightComponent] cooling tower object, allowable types:
  #   CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, and CoolingTowerVariableSpeed
  # @return [Boolean] returns true if successful, false if not
  def cooling_tower_apply_minimum_power_per_flow(cooling_tower)
    # Get the design water flow rate
    design_water_flow_m3_per_s = nil
    if cooling_tower.designWaterFlowRate.is_initialized
      design_water_flow_m3_per_s = cooling_tower.designWaterFlowRate.get
    elsif cooling_tower.autosizedDesignWaterFlowRate.is_initialized
      design_water_flow_m3_per_s = cooling_tower.autosizedDesignWaterFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoolingTower', "For #{cooling_tower.name} design water flow rate is not available, cannot apply efficiency standard.")
      return false
    end
    design_water_flow_gpm = OpenStudio.convert(design_water_flow_m3_per_s, 'm^3/s', 'gal/min').get

    # Get the table of cooling tower efficiencies
    heat_rejection = standards_data['heat_rejection']

    # Define the criteria to find the cooling tower properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template

    # By definition cooling towers in E+ are open.
    # Closed cooling towers are the fluidcooler objects.
    search_criteria['equipment_type'] = 'Open Cooling Tower'

    # @todo Standards replace this with a mechanism to store this
    # data in the cooling tower object itself.
    # For now, retrieve the fan type from the name
    name = cooling_tower.name.get
    fan_type = nil
    if name.include?('Centrifugal')
      fan_type = 'Centrifugal'
    elsif name.include?('Propeller') || name.include?('Axial')
      fan_type = 'Propeller or Axial'
    else
      fan_type = 'Propeller or Axial'
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoolingTower', "#{cooling_tower.name} fan type is not discernible from the name. Defaulting to Propeller or Axial.")
    end

    # Limit on Centrifugal Fan
    # Open Circuit Cooling Towers.
    if fan_type == 'Centrifugal'
      gpm_limit = cooling_tower_apply_minimum_power_per_flow_gpm_limit(cooling_tower)
      if gpm_limit && design_water_flow_gpm >= gpm_limit
        fan_type = 'Propeller or Axial'
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoolingTower', "For #{cooling_tower.name}, the design flow rate of #{design_water_flow_gpm.round} gpm is higher than the limit of #{gpm_limit.round} gpm for open centrifugal towers.  This tower must meet the minimum performance of #{fan_type} instead.")
      end
    end

    # Get the cooling tower properties
    search_criteria['fan_type'] = fan_type
    ct_props = model_find_object(heat_rejection, search_criteria)
    unless ct_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoolingTower', "For #{cooling_tower.name}, cannot find heat rejection properties, cannot apply standard efficiencies or curves.")
      return false
    end

    # Get cooling tower efficiency
    min_gpm_per_hp = ct_props['minimum_performance_gpm_per_hp']
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoolingTower', "For #{cooling_tower.name}, design water flow = #{design_water_flow_gpm.round} gpm, minimum performance = #{min_gpm_per_hp} gpm/hp (nameplate).")

    # Calculate the allowed fan brake horsepower
    # per method used in PNNL prototype buildings.
    # Assumes that the fan brake horsepower is 90%
    # of the fan nameplate rated motor power.
    # Source: Thornton et al. (2011), Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010, Section 4.5.4
    nominal_hp = design_water_flow_gpm / min_gpm_per_hp
    fan_bhp = 0.9 * nominal_hp
    fan_motor_eff = 0.85

    if nominal_hp <= 0.75
      motor_type = motor_type(nominal_hp)
      motor_properties = motor_fractional_hp_efficiencies(nominal_hp, motor_type = motor_type)
    else
      # Lookup the minimum motor efficiency
      motors = standards_data['motors']

      # Assuming all fan motors are 4-pole Enclosed
      search_criteria = {
        'template' => template,
        'number_of_poles' => 4.0,
        'type' => 'Enclosed'
      }

      # Use the efficiency largest motor efficiency when BHP is greater than the largest size for which a requirement is provided
      data = model_find_objects(motors, search_criteria)
      if data.empty?
        search_criteria = {
          'template' => template,
          'type' => nil
        }
        data = model_find_objects(motors, search_criteria)
      end
      maximum_capacity = model_find_maximum_value(data, 'maximum_capacity')
      if fan_bhp > maximum_capacity
        fan_bhp = maximum_capacity
      end

      motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = Date.today, area = nil, num_floors = nil, fan_motor_bhp = fan_bhp)

      if motor_properties.nil?
        # Retry without the date
        motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = nil, area = nil, num_floors = nil, fan_motor_bhp = fan_bhp)
      end
    end

    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CoolingTower', "For #{cooling_tower.name}, could not find motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp. Using a default value of #{fan_motor_eff}.")
    end

    unless motor_properties.nil?
      fan_motor_eff = motor_properties['nominal_full_load_efficiency']
      nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    end
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    # Calculate the fan motor power
    fan_motor_actual_power_hp = fan_bhp / fan_motor_eff
    # Convert to W
    fan_motor_actual_power_w = fan_motor_actual_power_hp * 745.7 # 745.7 W/HP

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoolingTower', "For #{cooling_tower.name}, allowed fan motor nameplate hp = #{nominal_hp.round(1)} hp, fan brake horsepower = #{fan_bhp.round(1)}, and fan motor actual power = #{fan_motor_actual_power_hp.round(1)} hp (#{fan_motor_actual_power_w.round} W) at #{fan_motor_eff} motor efficiency.")

    # Append the efficiency to the name
    cooling_tower.setName("#{cooling_tower.name} #{min_gpm_per_hp.to_f.round(1)} gpm/hp")

    # Hard size the design fan power.
    # Leave the water flow and air flow autosized.
    if cooling_tower.to_CoolingTowerSingleSpeed.is_initialized
      cooling_tower.setFanPoweratDesignAirFlowRate(fan_motor_actual_power_w)
    elsif cooling_tower.to_CoolingTowerTwoSpeed.is_initialized
      cooling_tower.setHighFanSpeedFanPower(fan_motor_actual_power_w)
      cooling_tower.setLowFanSpeedFanPower(0.3 * fan_motor_actual_power_w)
    elsif cooling_tower.to_CoolingTowerVariableSpeed.is_initialized
      cooling_tower.setDesignFanPower(fan_motor_actual_power_w)
    end

    return true
  end

  # Above this point, centrifugal fan cooling towers must meet the limits of propeller or axial cooling towers instead.
  #
  # @param cooling_tower [OpenStudio::Model::StraightComponent] cooling tower object, allowable types:
  #   CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, CoolingTowerVariableSpeed
  # @return [Double] the limit, in gallons per minute.  Return nil for no limit.
  def cooling_tower_apply_minimum_power_per_flow_gpm_limit(cooling_tower)
    gpm_limit = nil
    return gpm_limit
  end
end
