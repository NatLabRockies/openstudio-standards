class Standard
  # @!group PlantLoop

  # Apply all standard required controls to the plant loop
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_standard_controls(plant_loop, climate_zone)
    # Supply water temperature reset
    # plant_loop_enable_supply_water_temperature_reset(plant_loop) if plant_loop_supply_water_temperature_reset_required?(plant_loop)
  end

  # Set configuration in model for chilled water primary/secondary loop interface
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] common_pipe or heat_exchanger
  def plant_loop_set_chw_pri_sec_configuration(model)
    pri_sec_config = 'common_pipe'
    return pri_sec_config
  end

  # apply prm baseline pump power
  # @note I think it makes more sense to sense the motor efficiency right there...
  #   But actually it's completely irrelevant...
  #   you could set at 0.9 and just calculate the pressure rise to have your 19 W/GPM or whatever
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_pump_power(plant_loop)
    # Determine the pumping power per
    # flow based on loop type.
    pri_w_per_gpm = nil
    sec_w_per_gpm = nil

    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType

    case loop_type
      when 'Heating'

        has_district_heating = false
        plant_loop.supplyComponents.each do |sc|
          if sc.iddObjectType.valueName.to_s.include?('DistrictHeating')
            has_district_heating = true
          end
        end

        pri_w_per_gpm = if has_district_heating # District HW
                          14.0
                        else # HW
                          19.0
                        end

      when 'Cooling'

        has_district_cooling = false
        plant_loop.supplyComponents.each do |sc|
          if sc.to_DistrictCooling.is_initialized
            has_district_cooling = true
          end
        end

        has_secondary_pump = false
        plant_loop.demandComponents.each do |sc|
          if sc.to_PumpConstantSpeed.is_initialized || sc.to_PumpVariableSpeed.is_initialized
            has_secondary_pump = true
          end
        end

        if has_district_cooling # District CHW
          pri_w_per_gpm = 16.0
        elsif has_secondary_pump # Primary/secondary CHW
          pri_w_per_gpm = 9.0
          sec_w_per_gpm = 13.0
        else # Primary only CHW
          pri_w_per_gpm = 22.0
        end

      when 'Condenser'

        # @todo prm condenser loop pump power
        pri_w_per_gpm = 19.0

    end

    # Modify all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpConstantSpeed.is_initialized
        pump = sc.to_PumpConstantSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, pri_w_per_gpm)
      elsif sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, pri_w_per_gpm)
      elsif sc.to_HeaderedPumpsConstantSpeed.is_initialized
        pump = sc.to_HeaderedPumpsConstantSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, pri_w_per_gpm)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, pri_w_per_gpm)
      end
    end

    # Modify all the secondary pumps
    plant_loop.demandComponents.each do |sc|
      if sc.to_PumpConstantSpeed.is_initialized
        pump = sc.to_PumpConstantSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, sec_w_per_gpm)
      elsif sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, sec_w_per_gpm)
      elsif sc.to_HeaderedPumpsConstantSpeed.is_initialized
        pump = sc.to_HeaderedPumpsConstantSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, pri_w_per_gpm)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, pri_w_per_gpm)
      end
    end

    return true
  end

  # Applies the temperatures to the plant loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_temperatures(plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType
    case loop_type
      when 'Heating'
        plant_loop_apply_prm_baseline_hot_water_temperatures(plant_loop)
      when 'Cooling'
        plant_loop_apply_prm_baseline_chilled_water_temperatures(plant_loop)
      when 'Condenser'
        plant_loop_apply_prm_baseline_condenser_water_temperatures(plant_loop)
    end

    return true
  end

  # Applies the hot water temperatures to the plant loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_hot_water_temperatures(plant_loop)
    sizing_plant = plant_loop.sizingPlant

    # Loop properties
    # G3.1.3.3 - HW Supply at 180F, return at 130F
    hw_temp_f = 180
    hw_delta_t_r = 50
    min_temp_f = 50

    hw_temp_c = OpenStudio.convert(hw_temp_f, 'F', 'C').get
    hw_delta_t_k = OpenStudio.convert(hw_delta_t_r, 'R', 'K').get
    min_temp_c = OpenStudio.convert(min_temp_f, 'F', 'C').get

    sizing_plant.setDesignLoopExitTemperature(hw_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(hw_delta_t_k)
    plant_loop.setMinimumLoopTemperature(min_temp_c)

    # ASHRAE Appendix G - G3.1.3.4 (for ASHRAE 90.1-2004, 2007 and 2010)
    # HW reset: 180F at 20F and below, 150F at 50F and above
    plant_loop_enable_supply_water_temperature_reset(plant_loop)

    # Boiler properties
    if plant_loop.model.version < OpenStudio::VersionString.new('3.0.0')
      plant_loop.supplyComponents.each do |sc|
        if sc.to_BoilerHotWater.is_initialized
          boiler = sc.to_BoilerHotWater.get
          boiler.setDesignWaterOutletTemperature(hw_temp_c)
        end
      end
    end
    return true
  end

  # Applies the chilled water temperatures to the plant loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_chilled_water_temperatures(plant_loop)
    sizing_plant = plant_loop.sizingPlant

    # Loop properties
    # G3.1.3.8 - LWT 44 / EWT 56
    chw_temp_f = 44
    chw_delta_t_r = 12
    min_temp_f = 34
    max_temp_f = 200
    # For water-cooled chillers this is the water temperature entering the condenser (e.g., leaving the cooling tower).
    ref_cond_wtr_temp_f = 85

    chw_temp_c = OpenStudio.convert(chw_temp_f, 'F', 'C').get
    chw_delta_t_k = OpenStudio.convert(chw_delta_t_r, 'R', 'K').get
    min_temp_c = OpenStudio.convert(min_temp_f, 'F', 'C').get
    max_temp_c = OpenStudio.convert(max_temp_f, 'F', 'C').get
    ref_cond_wtr_temp_c = OpenStudio.convert(ref_cond_wtr_temp_f, 'F', 'C').get

    sizing_plant.setDesignLoopExitTemperature(chw_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(chw_delta_t_k)
    plant_loop.setMinimumLoopTemperature(min_temp_c)
    plant_loop.setMaximumLoopTemperature(max_temp_c)

    # ASHRAE Appendix G - G3.1.3.9 (for ASHRAE 90.1-2004, 2007 and 2010)
    # ChW reset: 44F at 80F and above, 54F at 60F and below
    plant_loop_enable_supply_water_temperature_reset(plant_loop)

    # Chiller properties
    plant_loop.supplyComponents.each do |sc|
      if sc.to_ChillerElectricEIR.is_initialized
        chiller = sc.to_ChillerElectricEIR.get
        chiller.setReferenceLeavingChilledWaterTemperature(chw_temp_c)
        chiller.setReferenceEnteringCondenserFluidTemperature(ref_cond_wtr_temp_c)
      end
    end

    return true
  end

  # Applies the condenser water temperatures to the plant loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_condenser_water_temperatures(plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType
    return true unless loop_type == 'Condenser'

    # Much of the thought in this section came from @jmarrec

    # Determine the design OATwb from the design days.
    # Per https://unmethours.com/question/16698/which-cooling-design-day-is-most-common-for-sizing-rooftop-units/
    # the WB=>MDB day is used to size cooling towers.
    summer_oat_wbs_f = []
    plant_loop.model.getDesignDays.sort.each do |dd|
      next unless dd.dayType == 'SummerDesignDay'
      next unless dd.name.get.to_s.include?('WB=>MDB')

      if plant_loop.model.version < OpenStudio::VersionString.new('3.3.0')
        if dd.humidityIndicatingType == 'Wetbulb'
          summer_oat_wb_c = dd.humidityIndicatingConditionsAtMaximumDryBulb
          summer_oat_wbs_f << OpenStudio.convert(summer_oat_wb_c, 'C', 'F').get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{dd.name}, humidity is specified as #{dd.humidityIndicatingType}; cannot determine Twb.")
        end
      else
        if dd.humidityConditionType == 'Wetbulb' && dd.wetBulbOrDewPointAtMaximumDryBulb.is_initialized
          summer_oat_wbs_f << OpenStudio.convert(dd.wetBulbOrDewPointAtMaximumDryBulb.get, 'C', 'F').get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{dd.name}, humidity is specified as #{dd.humidityConditionType}; cannot determine Twb.")
        end
      end
    end

    # Use the value from the design days or 78F, the CTI rating condition, if no design day information is available.
    design_oat_wb_f = nil
    if summer_oat_wbs_f.empty?
      design_oat_wb_f = 78
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, no design day OATwb conditions were found.  CTI rating condition of 78F OATwb will be used for sizing cooling towers.")
    else
      # Take worst case condition
      design_oat_wb_f = summer_oat_wbs_f.max
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "The maximum design wet bulb temperature from the Summer Design Day WB=>MDB is #{design_oat_wb_f} F")
    end

    # There is an EnergyPlus model limitation that the design_oat_wb_f < 80F for cooling towers
    ep_max_design_oat_wb_f = 80
    if design_oat_wb_f > ep_max_design_oat_wb_f
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, reduced design OATwb from #{design_oat_wb_f.round(1)} F to E+ model max input of #{ep_max_design_oat_wb_f} F.")
      design_oat_wb_f = ep_max_design_oat_wb_f
    end

    # Determine the design CW temperature, approach, and range
    design_oat_wb_c = OpenStudio.convert(design_oat_wb_f, 'F', 'C').get
    leaving_cw_t_c, approach_k, range_k = plant_loop_prm_baseline_condenser_water_temperatures(plant_loop, design_oat_wb_c)

    # Convert to IP units
    leaving_cw_t_f = OpenStudio.convert(leaving_cw_t_c, 'C', 'F').get
    approach_r = OpenStudio.convert(approach_k, 'K', 'R').get
    range_r = OpenStudio.convert(range_k, 'K', 'R').get

    # Report out design conditions
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, design OATwb = #{design_oat_wb_f.round(1)} F, approach = #{approach_r.round(1)} deltaF, range = #{range_r.round(1)} deltaF, leaving condenser water temperature = #{leaving_cw_t_f.round(1)} F.")

    # Set the CW sizing parameters
    sizing_plant.setDesignLoopExitTemperature(leaving_cw_t_c)
    sizing_plant.setLoopDesignTemperatureDifference(range_k)

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
    plant_loop.supplyComponents.each do |sc|
      if sc.to_CoolingTowerVariableSpeed.is_initialized
        ct = sc.to_CoolingTowerVariableSpeed.get
        # E+ has a minimum limit of 68F (20C) for this field.
        # Check against limit before attempting to set value.
        eplus_design_oat_wb_c_lim = 20
        if design_oat_wb_c < eplus_design_oat_wb_c_lim
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, a design OATwb of 68F will be used for sizing the cooling towers because the actual design value is below the limit EnergyPlus accepts for this input.")
          design_oat_wb_c = eplus_design_oat_wb_c_lim
        end
        ct.setDesignInletAirWetBulbTemperature(design_oat_wb_c)
        ct.setDesignApproachTemperature(approach_k)
        ct.setDesignRangeTemperature(range_k)
      end
    end

    # Set the min and max CW temps
    # Typical design of min temp is really around 40F
    # (that's what basin heaters, when used, are sized for usually)
    min_temp_f = 34
    max_temp_f = 200
    min_temp_c = OpenStudio.convert(min_temp_f, 'F', 'C').get
    max_temp_c = OpenStudio.convert(max_temp_f, 'F', 'C').get
    plant_loop.setMinimumLoopTemperature(min_temp_c)
    plant_loop.setMaximumLoopTemperature(max_temp_c)

    # Cooling Tower operational controls
    # G3.1.3.11 - Tower shall be controlled to maintain a 70F LCnWT where weather permits,
    # floating up to leaving water at design conditions.
    float_down_to_f = 70
    float_down_to_c = OpenStudio.convert(float_down_to_f, 'F', 'C').get

    cw_t_stpt_manager = nil
    plant_loop.supplyOutletNode.setpointManagers.each do |spm|
      if spm.to_SetpointManagerFollowOutdoorAirTemperature.is_initialized && spm.name.get.include?('Setpoint Manager Follow OATwb')
        cw_t_stpt_manager = spm.to_SetpointManagerFollowOutdoorAirTemperature.get
      end
    end
    if cw_t_stpt_manager.nil?
      cw_t_stpt_manager = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(plant_loop.model)
      cw_t_stpt_manager.addToNode(plant_loop.supplyOutletNode)
    end
    cw_t_stpt_manager.setName("#{plant_loop.name} Setpoint Manager Follow OATwb with #{approach_r.round(1)}F Approach")
    cw_t_stpt_manager.setReferenceTemperatureType('OutdoorAirWetBulb')
    # At low design OATwb, it is possible to calculate
    # a maximum temperature below the minimum.  In this case,
    # make the maximum and minimum the same.
    if leaving_cw_t_c < float_down_to_c
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, the maximum leaving temperature of #{leaving_cw_t_f.round(1)} F is below the minimum of #{float_down_to_f.round(1)} F.  The maximum will be set to the same value as the minimum.")
      leaving_cw_t_c = float_down_to_c
    end
    cw_t_stpt_manager.setMaximumSetpointTemperature(leaving_cw_t_c)
    cw_t_stpt_manager.setMinimumSetpointTemperature(float_down_to_c)
    cw_t_stpt_manager.setOffsetTemperatureDifference(approach_k)
    return true
  end

  # Determine the performance rating method specified design condenser water temperature, approach, and range
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] the condenser water loop
  # @param design_oat_wb_c [Double] the design OA wetbulb temperature (C)
  # @return [Array<Double>] [leaving_cw_t_c, approach_k, range_k]
  def plant_loop_prm_baseline_condenser_water_temperatures(plant_loop, design_oat_wb_c)
    design_oat_wb_f = OpenStudio.convert(design_oat_wb_c, 'C', 'F').get

    # G3.1.3.11 - CW supply temp = 85F or 10F approaching design wet bulb temperature,
    # whichever is lower.  Design range = 10F
    # Design Temperature rise of 10F => Range: 10F
    range_r = 10

    # Determine the leaving CW temp
    max_leaving_cw_t_f = 85
    leaving_cw_t_10f_approach_f = design_oat_wb_f + 10
    leaving_cw_t_f = [max_leaving_cw_t_f, leaving_cw_t_10f_approach_f].min

    # Calculate the approach
    approach_r = leaving_cw_t_f - design_oat_wb_f

    # Convert to SI units
    leaving_cw_t_c = OpenStudio.convert(leaving_cw_t_f, 'F', 'C').get
    approach_k = OpenStudio.convert(approach_r, 'R', 'K').get
    range_k = OpenStudio.convert(range_r, 'R', 'K').get

    return [leaving_cw_t_c, approach_k, range_k]
  end

  # Determine if temperature reset is required.
  # Required if heating or cooling capacity is greater than 300,000 Btu/hr.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if required, false if not
  def plant_loop_supply_water_temperature_reset_required?(plant_loop)
    reset_required = false

    # Not required for service water heating systems
    if OpenstudioStandards::HVAC.plant_loop_swh_loop?(plant_loop)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset not required for service water heating systems.")
      return reset_required
    end

    # Not required for variable flow systems
    if OpenstudioStandards::HVAC.plant_loop_variable_flow_system?(plant_loop)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset not required for variable flow systems per 6.5.4.3 Exception b.")
      return reset_required
    end

    # Determine the capacity of the system
    heating_capacity_w = OpenstudioStandards::HVAC.plant_loop_total_heating_capacity(plant_loop)
    cooling_capacity_w = OpenstudioStandards::HVAC.plant_loop_total_cooling_capacity(plant_loop)

    heating_capacity_btu_per_hr = OpenStudio.convert(heating_capacity_w, 'W', 'Btu/hr').get
    cooling_capacity_btu_per_hr = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get

    # Compare against capacity minimum requirement
    min_cap_btu_per_hr = 300_000
    if heating_capacity_btu_per_hr > min_cap_btu_per_hr
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is required because heating capacity of #{heating_capacity_btu_per_hr.round} Btu/hr exceeds the minimum threshold of #{min_cap_btu_per_hr.round} Btu/hr.")
      reset_required = true
    elsif cooling_capacity_btu_per_hr > min_cap_btu_per_hr
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is required because cooling capacity of #{cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum threshold of #{min_cap_btu_per_hr.round} Btu/hr.")
      reset_required = true
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is not required because capacity is less than minimum of #{min_cap_btu_per_hr.round} Btu/hr.")
    end

    return reset_required
  end

  # Enable reset of hot or chilled water temperature based on outdoor air temperature.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_enable_supply_water_temperature_reset(plant_loop)
    # Get the current setpoint manager on the outlet node
    # and determine if already has temperature reset
    spms = plant_loop.supplyOutletNode.setpointManagers
    spms.each do |spm|
      if spm.to_SetpointManagerOutdoorAirReset.is_initialized
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is already enabled.")
        return false
      end
    end

    # Get the design water temperature
    sizing_plant = plant_loop.sizingPlant
    design_temp_c = sizing_plant.designLoopExitTemperature
    design_temp_f = OpenStudio.convert(design_temp_c, 'C', 'F').get
    loop_type = sizing_plant.loopType

    # Apply the reset, depending on the type of loop.
    case loop_type
      when 'Heating'

        # Hot water as-designed when cold outside
        hwt_at_lo_oat_f = design_temp_f
        hwt_at_lo_oat_c = OpenStudio.convert(hwt_at_lo_oat_f, 'F', 'C').get
        # 30F decrease when it's hot outside,
        # and therefore less heating capacity is likely required.
        decrease_f = 30.0
        hwt_at_hi_oat_f = hwt_at_lo_oat_f - decrease_f
        hwt_at_hi_oat_c = OpenStudio.convert(hwt_at_hi_oat_f, 'F', 'C').get

        # Define the high and low outdoor air temperatures
        lo_oat_f = 20
        lo_oat_c = OpenStudio.convert(lo_oat_f, 'F', 'C').get
        hi_oat_f = 50
        hi_oat_c = OpenStudio.convert(hi_oat_f, 'F', 'C').get

        # Create a setpoint manager
        hwt_oa_reset = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(plant_loop.model)
        hwt_oa_reset.setName("#{plant_loop.name} HW Temp Reset")
        hwt_oa_reset.setControlVariable('Temperature')
        hwt_oa_reset.setSetpointatOutdoorLowTemperature(hwt_at_lo_oat_c)
        hwt_oa_reset.setOutdoorLowTemperature(lo_oat_c)
        hwt_oa_reset.setSetpointatOutdoorHighTemperature(hwt_at_hi_oat_c)
        hwt_oa_reset.setOutdoorHighTemperature(hi_oat_c)
        hwt_oa_reset.addToNode(plant_loop.supplyOutletNode)

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: hot water temperature reset from #{hwt_at_lo_oat_f.round}F to #{hwt_at_hi_oat_f.round}F between outdoor air temps of #{lo_oat_f.round}F and #{hi_oat_f.round}F.")

      when 'Cooling'

        # Chilled water as-designed when hot outside
        chwt_at_hi_oat_f = design_temp_f
        chwt_at_hi_oat_c = OpenStudio.convert(chwt_at_hi_oat_f, 'F', 'C').get
        # 10F increase when it's cold outside,
        # and therefore less cooling capacity is likely required.
        increase_f = 10.0
        chwt_at_lo_oat_f = chwt_at_hi_oat_f + increase_f
        chwt_at_lo_oat_c = OpenStudio.convert(chwt_at_lo_oat_f, 'F', 'C').get

        # Define the high and low outdoor air temperatures
        lo_oat_f = 60
        lo_oat_c = OpenStudio.convert(lo_oat_f, 'F', 'C').get
        hi_oat_f = 80
        hi_oat_c = OpenStudio.convert(hi_oat_f, 'F', 'C').get

        # Create a setpoint manager
        chwt_oa_reset = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(plant_loop.model)
        chwt_oa_reset.setName("#{plant_loop.name} CHW Temp Reset")
        chwt_oa_reset.setControlVariable('Temperature')
        chwt_oa_reset.setSetpointatOutdoorLowTemperature(chwt_at_lo_oat_c)
        chwt_oa_reset.setOutdoorLowTemperature(lo_oat_c)
        chwt_oa_reset.setSetpointatOutdoorHighTemperature(chwt_at_hi_oat_c)
        chwt_oa_reset.setOutdoorHighTemperature(hi_oat_c)
        chwt_oa_reset.addToNode(plant_loop.supplyOutletNode)

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: chilled water temperature reset from #{chwt_at_hi_oat_f.round}F to #{chwt_at_lo_oat_f.round}F between outdoor air temps of #{hi_oat_f.round}F and #{lo_oat_f.round}F.")

      else

        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: cannot enable supply water temperature reset for a #{loop_type} loop.")
        return false
    end
    return true
  end

  # Applies the pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_pumping_type(plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType

    case loop_type
      when 'Heating'
        plant_loop_apply_prm_baseline_hot_water_pumping_type(plant_loop)
      when 'Cooling'
        plant_loop_apply_prm_baseline_chilled_water_pumping_type(plant_loop)
      when 'Condenser'
        plant_loop_apply_prm_baseline_condenser_water_pumping_type(plant_loop)
    end

    return true
  end

  # Applies the chilled water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_chilled_water_pumping_type(plant_loop)
    # Determine the pumping type.
    minimum_cap_tons = 300.0

    # Determine the capacity
    cap_w = OpenstudioStandards::HVAC.plant_loop_total_cooling_capacity(plant_loop)
    cap_tons = OpenStudio.convert(cap_w, 'W', 'ton').get

    # Determine if it a district cooling system
    has_district_cooling = false
    plant_loop.supplyComponents.each do |sc|
      if sc.to_DistrictCooling.is_initialized
        has_district_cooling = true
      end
    end

    # Determine the primary and secondary pumping types
    pri_control_type = nil
    sec_control_type = nil
    if has_district_cooling
      pri_control_type = if cap_tons > minimum_cap_tons
                           'VSD No Reset'
                         else
                           'Riding Curve'
                         end
    else
      pri_control_type = 'Constant Flow'
      sec_control_type = if cap_tons > minimum_cap_tons
                           'VSD No Reset'
                         else
                           'Riding Curve'
                         end
    end

    # Report out the pumping type
    unless pri_control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, primary pump type is #{pri_control_type}.")
    end

    unless sec_control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, secondary pump type is #{sec_control_type}.")
    end

    # Modify all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: pri_control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: pri_control_type)
      end
    end

    # Modify all the secondary pumps besides constant pumps
    plant_loop.demandComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: sec_control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: sec_control_type)
      end
    end

    return true
  end

  # Applies the hot water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] hot water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_hot_water_pumping_type(plant_loop)
    # Determine the minimum area to determine
    # pumping type.
    minimum_area_ft2 = 120_000

    # Determine the area served
    area_served_m2 = OpenstudioStandards::HVAC.plant_loop_total_floor_area_served(plant_loop)
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

    # Determine the pump type
    control_type = 'Riding Curve'
    if area_served_ft2 > minimum_area_ft2
      control_type = 'VSD No Reset'
    end

    # Modify all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type)
      end
    end

    # Report out the pumping type
    unless control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, pump type is #{control_type}.")
    end

    return true
  end

  # Applies the condenser water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] condenser water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_condenser_water_pumping_type(plant_loop)
    # All condenser water loops are constant flow
    control_type = 'Constant Flow'

    # Report out the pumping type
    unless control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, pump type is #{control_type}.")
    end

    # Modify all primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type)
      end
    end

    return true
  end

  # Splits the single boiler used for the initial sizing run
  # into multiple separate boilers based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] hot water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_number_of_boilers(plant_loop)
    # Skip non-heating plants
    return true unless plant_loop.sizingPlant.loopType == 'Heating'

    # Determine the minimum area to determine
    # number of boilers.
    minimum_area_ft2 = 15_000

    # Determine the area served
    area_served_m2 = OpenstudioStandards::HVAC.plant_loop_total_floor_area_served(plant_loop)
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

    # Do nothing if only one boiler is required
    return true if area_served_ft2 < minimum_area_ft2

    # Get all existing boilers
    boilers = []
    plant_loop.supplyComponents.each do |sc|
      if sc.to_BoilerHotWater.is_initialized
        boilers << sc.to_BoilerHotWater.get
      end
    end

    # Ensure there is only 1 boiler to start
    first_boiler = nil
    return true if boilers.empty?

    if boilers.size > 1
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{boilers.size}, cannot split up per performance rating method baseline requirements.")
    else
      first_boiler = boilers[0]
    end

    # Clone the existing boiler and create
    # a new branch for it
    second_boiler = first_boiler.clone(plant_loop.model)
    if second_boiler.to_BoilerHotWater.is_initialized
      second_boiler = second_boiler.to_BoilerHotWater.get
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, could not clone boiler #{first_boiler.name}, cannot apply the performance rating method number of boilers.")
      return false
    end
    plant_loop.addSupplyBranchForComponent(second_boiler)
    final_boilers = [first_boiler, second_boiler]
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, added a second boiler.")

    # Rename boilers and set the sizing factor
    sizing_factor = (1.0 / final_boilers.size).round(2)
    final_boilers.each_with_index do |boiler, i|
      boiler.setName("#{plant_loop.name} Boiler #{i + 1} of #{final_boilers.size}")
      boiler.setSizingFactor(sizing_factor)
    end

    # Set the equipment to stage sequentially
    plant_loop.setLoadDistributionScheme('SequentialLoad')

    return true
  end

  # Splits the single chiller used for the initial sizing run
  # into multiple separate chillers based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @param sizing_run_dir [String] sizing run directory
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_number_of_chillers(plant_loop, sizing_run_dir = nil)
    # Skip non-cooling plants
    return true unless plant_loop.sizingPlant.loopType == 'Cooling'

    # Determine the number and type of chillers
    num_chillers = nil
    chiller_cooling_type = nil
    chiller_compressor_type = nil

    # Determine the capacity of the loop
    cap_w = OpenstudioStandards::HVAC.plant_loop_total_cooling_capacity(plant_loop)
    cap_tons = OpenStudio.convert(cap_w, 'W', 'ton').get
    if cap_tons <= 300
      num_chillers = 1
      chiller_cooling_type = 'WaterCooled'
      chiller_compressor_type = 'Rotary Screw'
    elsif cap_tons > 300 && cap_tons < 600
      num_chillers = 2
      chiller_cooling_type = 'WaterCooled'
      chiller_compressor_type = 'Rotary Screw'
    else
      # Max capacity of a single chiller
      max_cap_ton = 800.0
      num_chillers = (cap_tons / max_cap_ton).floor + 1
      # Must be at least 2 chillers
      num_chillers += 1 if num_chillers == 1
      chiller_cooling_type = 'WaterCooled'
      chiller_compressor_type = 'Centrifugal'
    end

    # Get all existing chillers and pumps
    chillers = []
    pumps = []
    plant_loop.supplyComponents.each do |sc|
      if sc.to_ChillerElectricEIR.is_initialized
        chillers << sc.to_ChillerElectricEIR.get
      elsif sc.to_PumpConstantSpeed.is_initialized
        pumps << sc.to_PumpConstantSpeed.get
      elsif sc.to_PumpVariableSpeed.is_initialized
        pumps << sc.to_PumpVariableSpeed.get
      end
    end

    # Ensure there is only 1 chiller to start
    first_chiller = nil
    return true if chillers.empty?

    if chillers.size > 1
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{chillers.size} chillers, cannot split up per performance rating method baseline requirements.")
    else
      first_chiller = chillers[0]
    end

    # Ensure there is only 1 pump to start
    orig_pump = nil
    if pumps.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{pumps.size} pumps.  A loop must have at least one pump.")
      return false
    elsif pumps.size > 1
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{pumps.size} pumps, cannot split up per performance rating method baseline requirements.")
      return false
    else
      orig_pump = pumps[0]
    end

    # Determine the per-chiller capacity
    # and sizing factor
    per_chiller_sizing_factor = (1.0 / num_chillers).round(2)
    # This is unused
    per_chiller_cap_tons = cap_tons / num_chillers

    # Set the sizing factor and the chiller type: could do it on the first chiller before cloning it, but renaming warrants looping on chillers anyways

    # Add any new chillers
    final_chillers = [first_chiller]
    (num_chillers - 1).times do
      new_chiller = first_chiller.clone(plant_loop.model)
      if new_chiller.to_ChillerElectricEIR.is_initialized
        new_chiller = new_chiller.to_ChillerElectricEIR.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, could not clone chiller #{first_chiller.name}, cannot apply the performance rating method number of chillers.")
        return false
      end
      # Connect the new chiller to the same CHW loop
      # as the old chiller.
      plant_loop.addSupplyBranchForComponent(new_chiller)
      # Connect the new chiller to the same CW loop
      # as the old chiller, if it was water-cooled.
      cw_loop = first_chiller.secondaryPlantLoop
      if cw_loop.is_initialized
        cw_loop.get.addDemandBranchForComponent(new_chiller)
      end

      final_chillers << new_chiller
    end

    # If there is more than one cooling tower,
    # replace the original pump with a headered pump
    # of the same type and properties.
    if final_chillers.size > 1
      num_pumps = final_chillers.size
      new_pump = nil
      if orig_pump.to_PumpConstantSpeed.is_initialized
        new_pump = OpenStudio::Model::HeaderedPumpsConstantSpeed.new(plant_loop.model)
        new_pump.setNumberofPumpsinBank(num_pumps)
        new_pump.setName("#{orig_pump.name} Bank of #{num_pumps}")
        new_pump.setRatedPumpHead(orig_pump.ratedPumpHead)
        new_pump.setMotorEfficiency(orig_pump.motorEfficiency)
        new_pump.setFractionofMotorInefficienciestoFluidStream(orig_pump.fractionofMotorInefficienciestoFluidStream)
        new_pump.setPumpControlType(orig_pump.pumpControlType)
      elsif orig_pump.to_PumpVariableSpeed.is_initialized
        new_pump = OpenStudio::Model::HeaderedPumpsVariableSpeed.new(plant_loop.model)
        new_pump.setNumberofPumpsinBank(num_pumps)
        new_pump.setName("#{orig_pump.name} Bank of #{num_pumps}")
        new_pump.setRatedPumpHead(orig_pump.ratedPumpHead)
        new_pump.setMotorEfficiency(orig_pump.motorEfficiency)
        new_pump.setFractionofMotorInefficienciestoFluidStream(orig_pump.fractionofMotorInefficienciestoFluidStream)
        new_pump.setPumpControlType(orig_pump.pumpControlType)
        new_pump.setCoefficient1ofthePartLoadPerformanceCurve(orig_pump.coefficient1ofthePartLoadPerformanceCurve)
        new_pump.setCoefficient2ofthePartLoadPerformanceCurve(orig_pump.coefficient2ofthePartLoadPerformanceCurve)
        new_pump.setCoefficient3ofthePartLoadPerformanceCurve(orig_pump.coefficient3ofthePartLoadPerformanceCurve)
        new_pump.setCoefficient4ofthePartLoadPerformanceCurve(orig_pump.coefficient4ofthePartLoadPerformanceCurve)
      end
      # Remove the old pump
      orig_pump.remove
      # Attach the new headered pumps
      new_pump.addToNode(plant_loop.supplyInletNode)
    end

    # Set the sizing factor and the chiller types
    final_chillers.each_with_index do |final_chiller, i|
      final_chiller.setName("#{template} #{chiller_cooling_type} #{chiller_compressor_type} Chiller #{i + 1} of #{final_chillers.size}")
      final_chiller.setSizingFactor(per_chiller_sizing_factor)
      final_chiller.setCondenserType(chiller_cooling_type)
    end
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, there are #{final_chillers.size} #{chiller_cooling_type} #{chiller_compressor_type} chillers.")

    # Set the equipment to stage sequentially
    plant_loop.setLoadDistributionScheme('SequentialLoad')

    return true
  end

  # Splits the single cooling tower used for the initial sizing run
  # into multiple separate cooling towers based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] condenser water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_number_of_cooling_towers(plant_loop)
    # Skip non-cooling plants
    return true unless plant_loop.sizingPlant.loopType == 'Condenser'

    # Determine the number of chillers
    # already in the model
    num_chillers = plant_loop.model.getChillerElectricEIRs.size

    # Get all existing cooling towers and pumps
    clg_twrs = []
    pumps = []
    plant_loop.supplyComponents.each do |sc|
      if sc.to_CoolingTowerSingleSpeed.is_initialized
        clg_twrs << sc.to_CoolingTowerSingleSpeed.get
      elsif sc.to_CoolingTowerTwoSpeed.is_initialized
        clg_twrs << sc.to_CoolingTowerTwoSpeed.get
      elsif sc.to_CoolingTowerVariableSpeed.is_initialized
        clg_twrs << sc.to_CoolingTowerVariableSpeed.get
      elsif sc.to_PumpConstantSpeed.is_initialized
        pumps << sc.to_PumpConstantSpeed.get
      elsif sc.to_PumpVariableSpeed.is_initialized
        pumps << sc.to_PumpVariableSpeed.get
      end
    end

    # Ensure there is only 1 cooling tower to start
    orig_twr = nil
    return true if clg_twrs.empty?

    if clg_twrs.size > 1
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{clg_twrs.size} cooling towers, cannot split up per performance rating method baseline requirements.")
      return false
    else
      orig_twr = clg_twrs[0]
    end

    # Ensure there is only 1 pump to start
    orig_pump = nil
    if pumps.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{pumps.size} pumps.  A loop must have at least one pump.")
      return false
    elsif pumps.size > 1
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, found #{pumps.size} pumps, cannot split up per performance rating method baseline requirements.")
      return false
    else
      orig_pump = pumps[0]
    end

    # Determine the per-cooling_tower sizing factor
    clg_twr_sizing_factor = (1.0 / num_chillers).round(2)

    # Add a cooling tower for each chiller.
    # Add an accompanying CW pump for each cooling tower.
    final_twrs = [orig_twr]
    new_twr = nil
    (num_chillers - 1).times do
      if orig_twr.to_CoolingTowerSingleSpeed.is_initialized
        new_twr = orig_twr.clone(plant_loop.model)
        new_twr = new_twr.to_CoolingTowerSingleSpeed.get
      elsif orig_twr.to_CoolingTowerTwoSpeed.is_initialized
        new_twr = orig_twr.clone(plant_loop.model)
        new_twr = new_twr.to_CoolingTowerTwoSpeed.get
      elsif orig_twr.to_CoolingTowerVariableSpeed.is_initialized
        # @todo remove workaround after resolving
        # https://github.com/NREL/OpenStudio/issues/2212
        # Workaround is to create a new tower
        # and replicate all the properties of the first tower.
        new_twr = OpenStudio::Model::CoolingTowerVariableSpeed.new(plant_loop.model)
        new_twr.setName(orig_twr.name.get.to_s)
        new_twr.setDesignInletAirWetBulbTemperature(orig_twr.designInletAirWetBulbTemperature.get)
        new_twr.setDesignApproachTemperature(orig_twr.designApproachTemperature.get)
        new_twr.setDesignRangeTemperature(orig_twr.designRangeTemperature.get)
        new_twr.setFractionofTowerCapacityinFreeConvectionRegime(orig_twr.fractionofTowerCapacityinFreeConvectionRegime.get)
        if orig_twr.fanPowerRatioFunctionofAirFlowRateRatioCurve.is_initialized
          new_twr.setFanPowerRatioFunctionofAirFlowRateRatioCurve(orig_twr.fanPowerRatioFunctionofAirFlowRateRatioCurve.get)
        end
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, could not clone cooling tower #{orig_twr.name}, cannot apply the performance rating method number of cooling towers.")
        return false
      end

      # Connect the new cooling tower to the CW loop
      plant_loop.addSupplyBranchForComponent(new_twr)
      new_twr_inlet = new_twr.inletModelObject.get.to_Node.get

      final_twrs << new_twr
    end

    # If there is more than one cooling tower,
    # replace the original pump with a headered pump
    # of the same type and properties.
    if final_twrs.size > 1
      num_pumps = final_twrs.size
      new_pump = nil
      if orig_pump.to_PumpConstantSpeed.is_initialized
        new_pump = OpenStudio::Model::HeaderedPumpsConstantSpeed.new(plant_loop.model)
        new_pump.setNumberofPumpsinBank(num_pumps)
        new_pump.setName("#{orig_pump.name} Bank of #{num_pumps}")
        new_pump.setRatedPumpHead(orig_pump.ratedPumpHead)
        new_pump.setMotorEfficiency(orig_pump.motorEfficiency)
        new_pump.setFractionofMotorInefficienciestoFluidStream(orig_pump.fractionofMotorInefficienciestoFluidStream)
        new_pump.setPumpControlType(orig_pump.pumpControlType)
      elsif orig_pump.to_PumpVariableSpeed.is_initialized
        new_pump = OpenStudio::Model::HeaderedPumpsVariableSpeed.new(plant_loop.model)
        new_pump.setNumberofPumpsinBank(num_pumps)
        new_pump.setName("#{orig_pump.name} Bank of #{num_pumps}")
        new_pump.setRatedPumpHead(orig_pump.ratedPumpHead)
        new_pump.setMotorEfficiency(orig_pump.motorEfficiency)
        new_pump.setFractionofMotorInefficienciestoFluidStream(orig_pump.fractionofMotorInefficienciestoFluidStream)
        new_pump.setPumpControlType(orig_pump.pumpControlType)
        new_pump.setCoefficient1ofthePartLoadPerformanceCurve(orig_pump.coefficient1ofthePartLoadPerformanceCurve)
        new_pump.setCoefficient2ofthePartLoadPerformanceCurve(orig_pump.coefficient2ofthePartLoadPerformanceCurve)
        new_pump.setCoefficient3ofthePartLoadPerformanceCurve(orig_pump.coefficient3ofthePartLoadPerformanceCurve)
        new_pump.setCoefficient4ofthePartLoadPerformanceCurve(orig_pump.coefficient4ofthePartLoadPerformanceCurve)
      end
      # Remove the old pump
      orig_pump.remove
      # Attach the new headered pumps
      new_pump.addToNode(plant_loop.supplyInletNode)
    end

    # Set the sizing factors
    final_twrs.each_with_index do |final_cooling_tower, i|
      final_cooling_tower.setName("#{final_cooling_tower.name} #{i + 1} of #{final_twrs.size}")
      final_cooling_tower.setSizingFactor(clg_twr_sizing_factor)
    end
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, there are #{final_twrs.size} cooling towers, one for each chiller.")

    # Set the equipment to stage sequentially
    plant_loop.setLoadDistributionScheme('SequentialLoad')
    return true
  end

  # This methods replaces all indoor or outdoor pipes which model the heat transfer between the pipe and the
  # environement by adiabatic pipes.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful
  def plant_loop_adiabatic_pipes_only(plant_loop)
    supply_side_components = plant_loop.supplyComponents
    demand_side_components = plant_loop.demandComponents
    plant_loop_components = supply_side_components += demand_side_components
    plant_loop_components.each do |component|
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      next unless ['OS_Pipe_Indoor', 'OS_Pipe_Outdoor'].include?(obj_type)

      # Get pipe object
      pipe = nil
      case obj_type
      when 'OS_Pipe_Indoor'
        pipe = component.to_PipeIndoor.get
      when 'OS_Pipe_Outdoor'
        pipe = component.to_PipeOutdoor.get
      end

      # Get pipe node
      node = prm_get_optional_handler(pipe, @sizing_run_dir, 'to_StraightComponent', 'outletModelObject', 'to_Node')

      # Get pipe and node names
      node_name = node.name.get
      pipe_name = pipe.name.get

      # Replace indoor or outdoor pipe by an adiabatic pipe
      new_pipe = OpenStudio::Model::PipeAdiabatic.new(plant_loop.model)
      new_pipe.setName(pipe_name)
      new_pipe.addToNode(node)
      component.remove
    end
    return true
  end

  # Determine which type of fan the cooling tower will have.  Defaults to TwoSpeed Fan.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] the fan type: TwoSpeed Fan, Variable Speed Fan
  def model_cw_loop_cooling_tower_fan_type(model)
    fan_type = 'Variable Speed Fan'
    return fan_type
  end
end
