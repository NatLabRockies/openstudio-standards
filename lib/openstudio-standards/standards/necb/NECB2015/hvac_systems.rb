class NECB2015
  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Boolean] true if successful, false if not
  def chiller_electric_eir_apply_efficiency_and_curves(chiller_electric_eir, clg_tower_objs)
    chillers = standards_data['chillers']

    # Define the criteria to find the chiller properties
    # in the hvac standards data set.
    search_criteria = chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    cooling_type = search_criteria['cooling_type']
    condenser_type = search_criteria['condenser_type']
    compressor_type = search_criteria['compressor_type']

    # Get the chiller capacity
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)

    # All chillers must be modulating down to 25% of their capacity
    chiller_electric_eir.setChillerFlowMode('LeavingSetpointModulated')
    chiller_electric_eir.setMinimumPartLoadRatio(0.25)
    chiller_electric_eir.setMinimumUnloadingRatio(0.25)
    chiller_capacity = capacity_w
    if (chiller_electric_eir.name.to_s.include? 'Primary') || (chiller_electric_eir.name.to_s.include? 'Secondary')
      if (capacity_w / 1000.0) < 2100.0
        if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
          chiller_capacity = capacity_w
        elsif chiller_electric_eir.name.to_s.include? 'Secondary Chiller'
          chiller_capacity = 0.001
        end
      else
        chiller_capacity = capacity_w / 2.0
      end
    end
    chiller_electric_eir.setReferenceCapacity(chiller_capacity)

    # Convert capacity to tons
    capacity_tons = OpenStudio.convert(chiller_capacity, 'W', 'ton').get

    # Get chiller compressor type if needed
    chiller_types = ['reciprocating','scroll','rotary screw','centrifugal']
    chiller_name_has_type = chiller_types.any? {|type| chiller_electric_eir.name.to_s.downcase.include? type}
    unless chiller_name_has_type
      chlr_type_search_criteria = {}
      chlr_type_search_criteria['cooling_type'] = cooling_type
      chlr_types_table = @standards_data['chiller_types']
      chlr_type_props = model_find_object(chlr_types_table, chlr_type_search_criteria, capacity_tons)
      unless chlr_type_props
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller types information")
        successfully_set_all_properties = false
        return successfully_set_all_properties
      end
      compressor_type = chlr_type_props['compressor_type']
      chiller_electric_eir.setName(chiller_electric_eir.name.to_s + ' ' + compressor_type)
    end
    # Get the chiller properties
    search_criteria['compressor_type'] = compressor_type
    chlr_table = @standards_data['chillers']
    chlr_props = model_find_object(chlr_table, search_criteria, capacity_tons, Date.today)
    unless chlr_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller properties, cannot apply standard efficiencies or curves.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the CAPFT curve
    cool_cap_ft = model_add_curve(chiller_electric_eir.model, chlr_props['capft'])
    if cool_cap_ft
      chiller_electric_eir.setCoolingCapacityFunctionOfTemperature(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFT curve
    cool_eir_ft = model_add_curve(chiller_electric_eir.model, chlr_props['eirft'])
    if cool_eir_ft
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfTemperature(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFPLR curve
    # which may be either a CurveBicubic or a CurveQuadratic based on chiller type
    cool_plf_fplr = model_add_curve(chiller_electric_eir.model, chlr_props['eirfplr'])
    if cool_plf_fplr
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfPLR(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Set the efficiency value
    kw_per_ton = nil
    cop = nil
    if chlr_props['minimum_full_load_efficiency']
      kw_per_ton = chlr_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
      chiller_electric_eir.setReferenceCOP(cop)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency, will not be set.")
      successfully_set_all_properties = false
    end

    # Set cooling tower properties now that the new COP of the chiller is set
    if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
      # Get the cooling tower based on the condenser water loop rather than assume that there is only one cooling tower loop.
      clg_towers = []
      tower_cap = capacity_w * (1.0 + 1.0 / chiller_electric_eir.referenceCOP)
      condenser_loop = chiller_electric_eir.condenserWaterLoop.get
      condenser_loop.supplyComponents.each do |supply_comp|
        if supply_comp.to_CoolingTowerSingleSpeed.is_initialized
          clg_towers << supply_comp.to_CoolingTowerSingleSpeed.get
        end
      end
      # Single speed tower model assumes 25% extra for compressor power
      if (tower_cap / 1000.0) < 1750
        clg_towers[0].setNumberofCells(1)
      else
        clg_towers[0].setNumberofCells((tower_cap / (1000 * 1750) + 0.5).round)
      end
      # Only apply cooling tower fan power if power is greater than 13kW.  This is to avoid EnergyPlus issues with some small cooling towers.
      clg_towers[0].setFanPoweratDesignAirFlowRate(0.013 * tower_cap) if (tower_cap * 0.013 > 13000.0)
    end

    # Append the name with size and kw/ton
    chiller_electric_eir.setName("#{chiller_electric_eir.name} #{capacity_tons.round}tons #{kw_per_ton.round(1)}kW/ton")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.ChillerElectricEIR', "For #{template}: #{chiller_electric_eir.name}: #{cooling_type} #{condenser_type} #{compressor_type} Capacity = #{capacity_tons.round}tons; COP = #{cop.round(1)} (#{kw_per_ton.round(1)}kW/ton)")

    return successfully_set_all_properties
  end

  # Searches through any hydronic loops and applies the maxmimum total pump power by modifying the pump design power consumption.
  # This is as per NECB2015 5.2.6.3.(1)
  def apply_maximum_loop_pump_power(model)
    plant_loops = model.getPlantLoops
    plant_loops.each do |plantloop|
      next if plant_loop_swh_loop?(plantloop) == true

      pumps = []
      max_powertoload = 0
      total_pump_power = 0
      # This cycles through the plant loop supply side components to determine if there is a heat pump present or a pump
      # If a heat pump is present the pump power to total demand ratio is set to what NECB 2015 table 5.2.6.3. say it should be.
      # If a pump is present, this is a handy time to grab it for modification later.  Also, it adds the pump power consumption
      # to a total which will be used to determine how much to modify the pump power consumption later.
      max_total_loop_pump_power_table = @standards_data['max_total_loop_pump_power']
      plantloop.supplyComponents.each do |supplycomp|
        case supplycomp.iddObjectType.valueName.to_s
          when 'OS_CentralHeatPumpSystem', 'OS_Coil_Heating_WaterToAirHeatPump_EquationFit', 'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeedEquationFit',
            'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeedEquationFit_SpeedData', 'OS_HeatPump_PlantLoop_EIR_Heating', 'OS_HeatPump_PlantLoop_EIR_Cooling'
            search_hash = { 'hydronic_system_type' => 'WSHP' }
            max_powertoload = model_find_object(max_total_loop_pump_power_table, search_hash)['total_normalized_pump_power_wperkw']
          when 'OS_GroundHeatExchanger_Vertical'
            max_powertoload = 21.0
          when 'OS_Pump_VariableSpeed'
            pump = supplycomp.to_PumpVariableSpeed.get
            pumps << pump
            total_pump_power += pump.autosizedRatedPowerConsumption.get
          when 'OS_Pump_ConstantSpeed'
            pump = supplycomp.to_PumpConstantSpeed.get
            pumps << pump
            total_pump_power += pump.autosizedRatedPowerConsumption.get
          when 'OS_HeaderedPumps_ConstantSpeed'
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "A pump used in the plant loop named #{plantloop.name} is headered.  This may result in an error and cause a failure.")
            pump = supplycomp.to_HeaderedPumpsConstantSpeed.get
            pumps << pump
            total_pump_power += pump.autosizedRatedPowerConsumption.get
          when 'OS_HeaderedPumps_VariableSpeed'
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "A pump used in the plant loop named #{plantloop.name} is headered.  This may result in an error and cause a failure.")
            pump = supplycomp.to_HeaderedPumpsVariableSpeed.get
            pumps << pump
            total_pump_power += pump.autosizedRatedPowerConsumption.get
        end
      end
      var_spd_pumps = pumps.select {|pump| pump.to_PumpVariableSpeed.is_initialized}
      # EnergyPlus doesn't currently properly account for variable speed pumps operation in the condenser loop.
      # This code is an approximation for a correction to the pump head when the loop has variable speed pumps for ground-source condenser loops.
      # These estimates were confirmed with OS runs using Montreal weather file for offices, schoold, and apartment bldgs. Office estimates are
      # then for other bldg types.
      if plantloop.name.to_s.upcase.include? "GLHX"
        max_powertoload = 21.0
        if !var_spd_pumps.empty?
          if model.getBuilding.standardsBuildingType.to_s.include? 'Office'
            max_powertoload = 21.0/4.0
          elsif model.getBuilding.standardsBuildingType.to_s.include? 'School'
            max_powertoload = 21.0/18.0
          elsif model.getBuilding.standardsBuildingType.to_s.include? 'Apartment'
             max_powertoload = 21.0/3.0
          else
            max_powertoload = 21.0/4.0
          end
        end
      end
      # If no pumps were found then there is nothing to set so go to the next plant loop
      next if pumps.empty?

      # If a heat pump was found then the pump power to total demand ratio should have been set to what NECB 2015 table 5.2.6.3 says.
      # If the pump power to total demand ratio was not set then no heat pump was present so set according to if the plant loop is
      # used for heating, cooling, or heat rejection (condeser as OpenStudio calls it).
      unless max_powertoload > 0
        case plantloop.sizingPlant.loopType
        when 'Heating'
          search_hash = { 'hydronic_system_type' => 'Heating' }
          max_powertoload = model_find_object(max_total_loop_pump_power_table, search_hash)['total_normalized_pump_power_wperkw']
        when 'Cooling'
          search_hash = { 'hydronic_system_type' => 'Cooling' }
          max_powertoload = model_find_object(max_total_loop_pump_power_table, search_hash)['total_normalized_pump_power_wperkw']
        when 'Condenser'
          search_hash = { 'hydronic_system_type' => 'Heat_rejection' }
          max_powertoload = model_find_object(max_total_loop_pump_power_table, search_hash)['total_normalized_pump_power_wperkw']
        end
      end
      # If nothing was found then do nothing (though by this point if nothing was found then an error should have been thrown).
      next if max_powertoload == 0

      # Get the capacity of the loop (using the more general method of calculating via maxflow*temp diff*density*heat capacity)
      # This is more general than the other method in Standards.PlantLoop.rb which only looks at heat and cooling.  Also,
      # that method looks for spceific equipment and would be thrown if other equipment was present.  However my method
      # only works for water for now.
      plantloop_capacity = plant_loop_capacity_w_by_maxflow_and_delta_t_forwater(plantloop)
      # Sizing factor is pump power (W)/ zone demand (in kW, as approximated using plant loop capacity).
      necb_pump_power_cap = plantloop_capacity * max_powertoload / 1000
      pump_power_adjustment = necb_pump_power_cap / total_pump_power
      # Update rated pump head to make pump power in line with NECB 2015.
      pumps.each do |pump|
        if pump.designPowerSizingMethod != "PowerPerFlowPerPressure" then OpenStudio::logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', 'Design power sizing method for pump ',pump.name.to_s,' not set to PowerPerFlowPerPressure') end
        new_pump_head = pump_power_adjustment*pump.ratedPumpHead.to_f
        pump.setRatedPumpHead(new_pump_head)
      end
    end
    return model
  end
end
