class ASHRAE901PRM < Standard
  # Keep only one cooling tower, but use one condenser pump per chiller

  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
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
    if clg_twrs.empty?
      return true
    elsif clg_twrs.size > 1
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

    final_twrs = [orig_twr]

    # return unless there is more than one chiller
    return true unless num_chillers > 1

    # If there is more than one chiller, replace the original pump with a headered pump of the same type and properties.
    num_pumps = num_chillers
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

    return true
  end

  # Splits the single chiller used for the initial sizing run
  # into multiple separate chillers based on Appendix G. Also applies
  # EMS to stage chillers properly
  # @param plant_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_number_of_chillers(plant_loop)
    # Skip non-cooling plants & secondary cooling loop
    return true unless plant_loop.sizingPlant.loopType == 'Cooling'
    # If the loop is cooling but it is a secondary loop, then skip.
    return true if plant_loop.additionalProperties.hasFeature('is_secondary_loop')

    # Set the equipment to stage sequentially or uniformload if there is secondary loop
    if plant_loop.additionalProperties.hasFeature('is_primary_loop')
      plant_loop.setLoadDistributionScheme('UniformLoad')
    else
      plant_loop.setLoadDistributionScheme('SequentialLoad')
    end

    model = plant_loop.model

    # Get all existing chillers and pumps. Copy chiller properties needed when duplicating existing settings
    chillers = []
    pumps = []
    default_cop = nil
    condenser_water_loop = nil
    dsgn_sup_wtr_temp_c = nil

    plant_loop.supplyComponents.each do |sc|
      if sc.to_ChillerElectricEIR.is_initialized
        chiller = sc.to_ChillerElectricEIR.get

        # Copy the last chillers COP, leaving chilled water temperature, and reference cooling tower. These will be the
        # default for any extra chillers.
        default_cop = chiller.referenceCOP
        dsgn_sup_wtr_temp_c = chiller.referenceLeavingChilledWaterTemperature
        condenser_water_loop = chiller.condenserWaterLoop
        chillers << chiller

      elsif sc.to_PumpConstantSpeed.is_initialized
        pumps << sc.to_PumpConstantSpeed.get
      elsif sc.to_PumpVariableSpeed.is_initialized
        pumps << sc.to_PumpVariableSpeed.get
      end
    end

    # Get existing plant loop pump. We'll copy this pumps parameters before removing it. Throw exception for multiple pumps on supply side
    if pumps.empty?
      OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{plant_loop.name}, found #{pumps.size} pumps. A loop must have at least one pump.")
      return false
    elsif pumps.size > 1
      OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{plant_loop.name}, found #{pumps.size} pumps, cannot split up per performance rating method baseline requirements.")
      return false
    else
      original_pump = pumps[0]
    end

    return true if chillers.empty?

    # Determine the capacity of the loop
    cap_w = plant_loop_total_cooling_capacity(plant_loop)
    cap_tons = OpenStudio.convert(cap_w, 'W', 'ton').get

    # Throw exception for > 2,400 tons as this breaks our staging strategy cap of 3 chillers
    if cap_tons > 2400
      OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{plant_loop.name}, the total capacity (#{cap_w}) exceeded 2400 tons and would require more than 3 chillers. The existing code base cannot accommodate the staging required for this")
    end

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

    if chillers.length > num_chillers
      OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{plant_loop.name}, the existing number of chillers exceeds the recommended amount. We have not accounted for this in the codebase yet.")
    end

    # Determine the per-chiller capacity and sizing factor
    per_chiller_sizing_factor = (1.0 / num_chillers).round(2)
    per_chiller_cap_w = cap_w / num_chillers

    # Set the sizing factor and the chiller types
    # chillers.each_with_index do |chiller, i|
    for i in 0..num_chillers - 1
      # if not enough chillers exist, create a new one. Else reference the i'th chiller
      if i <= chillers.length - 1
        chiller = chillers[i]
      else
        chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
        plant_loop.addSupplyBranchForComponent(chiller)
        chiller.setReferenceLeavingChilledWaterTemperature(dsgn_sup_wtr_temp_c)
        chiller.setLeavingChilledWaterLowerTemperatureLimit(OpenStudio.convert(36.0, 'F', 'C').get)
        chiller.setReferenceEnteringCondenserFluidTemperature(OpenStudio.convert(95.0, 'F', 'C').get)
        chiller.setMinimumPartLoadRatio(0.15)
        chiller.setMaximumPartLoadRatio(1.0)
        chiller.setOptimumPartLoadRatio(1.0)
        chiller.setMinimumUnloadingRatio(0.25)
        chiller.setChillerFlowMode('ConstantFlow')
        chiller.setReferenceCOP(default_cop)

        condenser_water_loop.get.addDemandBranchForComponent(chiller) if condenser_water_loop.is_initialized

      end

      chiller.setName("#{template} #{chiller_cooling_type} #{chiller_compressor_type} Chiller #{i + 1} of #{num_chillers}")
      chiller.setSizingFactor(per_chiller_sizing_factor)
      chiller.setReferenceCapacity(per_chiller_cap_w)
      chiller.setCondenserType(chiller_cooling_type)
      chiller.additionalProperties.setFeature('compressor_type', chiller_compressor_type)

      # Add inlet pump
      new_pump = OpenStudio::Model::PumpVariableSpeed.new(plant_loop.model)
      new_pump.setName("#{chiller.name} Inlet Pump")
      new_pump.setRatedPumpHead(original_pump.ratedPumpHead / num_chillers)

      OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(new_pump, control_type: 'Riding Curve')
      chiller_inlet_node = chiller.connectedObject(chiller.supplyInletPort).get.to_Node.get
      new_pump.addToNode(chiller_inlet_node)

    end

    # Remove original pump, dedicated chiller pumps have all been added
    original_pump.remove

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, there are #{chillers.size} #{chiller_cooling_type} #{chiller_compressor_type} chillers.")

    # Check for a heat exchanger fluid to fluid-- that lets you know if this is a primary loop
    has_secondary_plant_loop = !plant_loop.demandComponents(OpenStudio::Model::HeatExchangerFluidToFluid.iddObjectType).empty?

    if has_secondary_plant_loop
      # Add EMS to stage chillers if there's a primary/secondary configuration
      if num_chillers > 3
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{plant_loop.name} has more than 3 chillers. We do not have an EMS strategy for that yet.")
      elsif num_chillers > 1
        add_ems_for_multiple_chiller_pumps_w_secondary_plant(model, plant_loop)
      end
    end

    return true
  end

  # Adds EMS program for pumps serving 3 chillers on primary + secondary loop. This was due to an issue when modeling two
  # dedicated loops. The headered pumps or dedicated constant speed pumps operate at full flow as long as there's a
  # load on the loop unless this EMS is in place.
  # @param model [OpenStudio::Model] OpenStudio model with plant loops
  # @param primary_plant [OpenStudio::Model::PlantLoop] Primary chilled water loop with chillers
  def add_ems_for_multiple_chiller_pumps_w_secondary_plant(model, primary_plant)
    # Aggregate array of chillers on primary plant supply side
    chiller_list = []

    primary_plant.supplyComponents.each do |sc|
      if sc.to_ChillerElectricEIR.is_initialized
        chiller_list << sc.to_ChillerElectricEIR.get
      end
    end

    num_of_chillers = chiller_list.length # Either 2 or 3

    return if num_of_chillers <= 1

    plant_name = primary_plant.name.to_s

    # Make a variable to track the chilled water demand
    chw_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Plant Supply Side Cooling Demand Rate')
    chw_sensor.setKeyName(plant_name)
    chw_sensor.setName("#{plant_name.gsub(/[-\s]+/, '_')}_CHW_DEMAND")

    # Sort chillers by their reference capacity
    sorted_chiller_list = chiller_list.sort_by { |chiller| chiller.referenceCapacity.get.to_f }

    # Make pump specific parameters for EMS. Use counter
    sorted_chiller_list.each_with_index do |chiller, i|
      # Get chiller pump
      pump_name = "#{chiller.name} Inlet Pump"
      pump = model.getPumpVariableSpeedByName(pump_name).get

      # Set EMS names
      ems_pump_flow_name   =      "CHILLER_PUMP_#{i + 1}_FLOW"
      ems_pump_status_name =      "CHILLER_PUMP_#{i + 1}_STATUS"
      ems_pump_design_flow_name = "CHILLER_PUMP_#{i + 1}_DES_FLOW"

      # ---- Actuators ----

      # Pump Flow Actuator
      actuator_pump_flow = OpenStudio::Model::EnergyManagementSystemActuator.new(pump, 'Pump', 'Pump Mass Flow Rate')
      actuator_pump_flow.setName(ems_pump_flow_name)

      # Pump Status Actuator
      actuator_pump_status = OpenStudio::Model::EnergyManagementSystemActuator.new(pump,
                                                                                   'Plant Component Pump:VariableSpeed',
                                                                                   'On/Off Supervisory')
      actuator_pump_status.setName(ems_pump_status_name)

      # ---- Internal Variable ----

      internal_variable = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(model, 'Pump Maximum Mass Flow Rate')
      internal_variable.setInternalDataIndexKeyName(pump_name)
      internal_variable.setName(ems_pump_design_flow_name)
    end

    # Write EMS program
    if num_of_chillers > 3
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "EMS Code for multiple chiller pump has not been written for greater than 2 chillers. This has #{num_of_chillers} chillers")
    elsif num_of_chillers == 3
      add_ems_program_for_3_pump_chiller_plant(model, sorted_chiller_list, primary_plant)
    elsif num_of_chillers == 2
      add_ems_program_for_2_pump_chiller_plant(model, sorted_chiller_list, primary_plant)
    end

    # Update chilled water loop operation scheme to work with updated EMS ranges
    stage_chilled_water_loop_operation_schemes(model, primary_plant)
  end

  # Updates a chilled water plant's operation scheme to match the EMS written by either
  # add_ems_program_for_3_pump_chiller_plant or add_ems_program_for_2_pump_chiller_plant
  # @param model [OpenStudio::Model] OpenStudio model with plant loops
  # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop
  def stage_chilled_water_loop_operation_schemes(model, chilled_water_loop)
    # Initialize array of cooling plant systems
    chillers = []

    # Gets all associated chillers from the supply side and adds them to the chillers list
    chilled_water_loop.supplyComponents(OpenStudio::Model::ChillerElectricEIR.iddObjectType).each do |chiller|
      chillers << chiller.to_ChillerElectricEIR.get
    end

    # Skip those without chillers or only 1 (i.e., nothing to stage)
    return if chillers.empty?
    return if chillers.length == 1

    # Sort chillers by capacity
    sorted_chillers = chillers.sort_by { |chiller| chiller.referenceCapacity.get }

    primary_chiller = sorted_chillers[0]
    secondary_1_chiller = sorted_chillers[1]
    secondary_2_chiller = sorted_chillers[2] if chillers.length == 3

    equip_operation_cool_load = OpenStudio::Model::PlantEquipmentOperationCoolingLoad.new(model)

    # Calculate load ranges into the PlantEquipmentOperation:CoolingLoad
    loading_factor = 0.8
    # # when the capacity of primary chiller is larger than the capacity of secondary chiller - the loading factor
    # # will need to be adjusted to avoid load range intersect.
    # if secondary_1_chiller.referenceCapacity.get <= primary_chiller.referenceCapacity.get * loading_factor
    #   # Adjustment_factor can creates a bandwidth for step 2 staging strategy.
    #   # set adjustment_factor = 1.0 means the step 2 staging strategy is skipped
    #   adjustment_factor = 1.0
    #   loading_factor = secondary_1_chiller.referenceCapacity.get / primary_chiller.referenceCapacity.get * adjustment_factor
    # end

    if chillers.length == 3

      # Add four ranges for small, medium, and large chiller capacities
      # 1: 0 W -> 80% of smallest chiller capacity
      # 2: 80% of primary chiller -> medium size chiller capacity
      # 3: medium chiller capacity -> medium + large chiller capacity
      # 4: medium + large chiller capacity -> infinity
      # Control strategy first stage
      equipment_list = [primary_chiller]
      range = primary_chiller.referenceCapacity.get * loading_factor
      equip_operation_cool_load.addLoadRange(range, equipment_list)

      # Control strategy second stage
      equipment_list = [secondary_1_chiller]
      range = secondary_1_chiller.referenceCapacity.get
      equip_operation_cool_load.addLoadRange(range, equipment_list)

      # Control strategy third stage
      equipment_list = [secondary_1_chiller, secondary_2_chiller]
      range = secondary_1_chiller.referenceCapacity.get + secondary_2_chiller.referenceCapacity.get
      equip_operation_cool_load.addLoadRange(range, equipment_list)

      equipment_list = [primary_chiller, secondary_1_chiller, secondary_2_chiller]
      range = 999999999
      equip_operation_cool_load.addLoadRange(range, equipment_list)

    elsif chillers.length == 2

      # Add three ranges for primary and secondary chiller capacities
      # 1: 0 W -> 80% of smallest chiller capacity
      # 2: 80% of primary chiller -> secondary chiller capacity
      # 3: secondary chiller capacity -> infinity
      # Control strategy first stage
      equipment_list = [primary_chiller]
      range = primary_chiller.referenceCapacity.get * loading_factor
      equip_operation_cool_load.addLoadRange(range, equipment_list)

      # Control strategy second stage
      equipment_list = [secondary_1_chiller]
      range = secondary_1_chiller.referenceCapacity.get
      equip_operation_cool_load.addLoadRange(range, equipment_list)

      # Control strategy third stage
      equipment_list = [primary_chiller, secondary_1_chiller]
      range = 999999999
      equip_operation_cool_load.addLoadRange(range, equipment_list)

    else
      raise "Failed to stage chillers, #{chillers.length} chillers found in the loop.Logic for staging chillers has only been done for either 2 or 3 chillers"
    end

    chilled_water_loop.setPlantEquipmentOperationCoolingLoad(equip_operation_cool_load)
  end

  # Adds EMS program for pumps serving 2 chillers on primary + secondary loop. This was due to an issue when modeling two
  # dedicated loops. The headered pumps or dedicated constant speed pumps operate at full flow as long as there's a
  # load on the loop unless this EMS is in place.
  # @param model [OpenStudio::Model] OpenStudio model with plant loops
  # @param sorted_chiller_list [Array] Array of chillers in primary_plant sorted by capacity
  # @param primary_plant [OpenStudio::Model::PlantLoop] Primary chilled water loop with chillers
  def add_ems_program_for_2_pump_chiller_plant(model, sorted_chiller_list, primary_plant)
    plant_name = primary_plant.name.to_s

    # Break out sorted chillers and get their respective capacities
    small_chiller = sorted_chiller_list[0]
    large_chiller = sorted_chiller_list[1]

    capacity_small_chiller = small_chiller.referenceCapacity.get
    capacity_large_chiller = large_chiller.referenceCapacity.get

    chw_demand = "#{primary_plant.name.to_s.gsub(/[-\s]+/, '_')}_CHW_DEMAND"

    ems_pump_program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    ems_pump_program.setName("#{plant_name.gsub(/[-\s]+/, '_')}_Pump_EMS")
    ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = NULL,  !- Program Line 1')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = NULL,  !- Program Line 2')
    ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = NULL,  !- A3')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = NULL,  !- A4')
    ems_pump_program.addLine("IF #{chw_demand} <= #{0.8 * capacity_small_chiller},  !- A5")
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 0,  !- A6')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = 0,  !- A7')
    ems_pump_program.addLine("ELSEIF #{chw_demand} <= #{capacity_large_chiller},  !- A8")
    ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = 0,  !- A9')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 1,  !- A10')
    ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = 0,  !- A11')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = CHILLER_PUMP_2_DES_FLOW,  !- A12')
    ems_pump_program.addLine("ELSEIF #{chw_demand} > #{capacity_large_chiller},  !- A13")
    ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = 1,  !- A14')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 1,  !- A15')
    ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = CHILLER_PUMP_1_DES_FLOW,  !- A16')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = CHILLER_PUMP_2_DES_FLOW,  !- A17')
    ems_pump_program.addLine('ENDIF  !- A18')

    ems_pump_program_manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    ems_pump_program_manager.setName("#{plant_name.gsub(/[-\s]+/, '_')}_Pump_Program_Manager")
    ems_pump_program_manager.setCallingPoint('InsideHVACSystemIterationLoop')
    ems_pump_program_manager.addProgram(ems_pump_program)
  end

  # Adds EMS program for pumps serving 3 chillers on primary + secondary loop. This was due to an issue when modeling two
  # dedicated loops. The headered pumps or dedicated constant speed pumps operate at full flow as long as there's a
  # load on the loop unless this EMS is in place.
  # @param model [OpenStudio::Model] OpenStudio model with plant loops
  # @param sorted_chiller_list [Array] Array of chillers in primary_plant sorted by capacity
  # @param primary_plant [OpenStudio::Model::PlantLoop] Primary chilled water loop with chillers
  def add_ems_program_for_3_pump_chiller_plant(model, sorted_chiller_list, primary_plant)
    plant_name = primary_plant.name.to_s

    # Break out sorted chillers and get their respective capacities
    primary_chiller = sorted_chiller_list[0]
    medium_chiller = sorted_chiller_list[1]
    large_chiller = sorted_chiller_list[2]

    capacity_80_pct_small = 0.8 * primary_chiller.referenceCapacity.get
    capacity_medium_chiller = medium_chiller.referenceCapacity.get
    capacity_large_chiller = large_chiller.referenceCapacity.get

    if capacity_80_pct_small >= capacity_medium_chiller
      first_stage_capacity = capacity_medium_chiller
    else
      first_stage_capacity = capacity_80_pct_small
    end

    chw_demand = "#{primary_plant.name.to_s.gsub(/[-\s]+/, '_')}_CHW_DEMAND"

    ems_pump_program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    ems_pump_program.setName("#{plant_name.gsub(/[-\s]+/, '_')}_Pump_EMS")
    ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = NULL,  !- Program Line 1')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = NULL,  !- Program Line 2')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_STATUS = NULL,  !- A4')
    ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = NULL,  !- A5')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = NULL,  !- A6')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_FLOW = NULL,  !- A7')
    ems_pump_program.addLine("IF #{chw_demand} <= #{first_stage_capacity},  !- A8")
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 0,  !- A9')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_STATUS = 0,  !- A10')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = 0,  !- A11')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_FLOW = 0,  !- A12')

    if capacity_80_pct_small < capacity_medium_chiller
      ems_pump_program.addLine("ELSEIF #{chw_demand} <= #{capacity_medium_chiller},  !- A13")
      ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = 0,  !- A14')
      ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 1,  !- A15')
      ems_pump_program.addLine('SET CHILLER_PUMP_3_STATUS = 0,  !- A16')
      ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = 0,  !- A17')
      ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = CHILLER_PUMP_2_DES_FLOW,  !- A18')
      ems_pump_program.addLine('SET CHILLER_PUMP_3_FLOW = 0,  !- A19')
    end

    ems_pump_program.addLine("ELSEIF #{chw_demand} <= #{capacity_medium_chiller + capacity_large_chiller},  !- A20")
    ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = 0,  !- A21')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 1,  !- A22')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_STATUS = 1,  !- A23')
    ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = 0,  !- A24')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = CHILLER_PUMP_2_DES_FLOW,  !- A25')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_FLOW = CHILLER_PUMP_3_DES_FLOW,  !- A26')
    ems_pump_program.addLine("ELSEIF #{chw_demand} > #{capacity_medium_chiller + capacity_large_chiller},  !- A27")
    ems_pump_program.addLine('SET CHILLER_PUMP_1_STATUS = 1,  !- A28')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_STATUS = 1,  !- A29')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_STATUS = 1,  !- A30')
    ems_pump_program.addLine('SET CHILLER_PUMP_1_FLOW = CHILLER_PUMP_1_DES_FLOW,  !- A31')
    ems_pump_program.addLine('SET CHILLER_PUMP_2_FLOW = CHILLER_PUMP_2_DES_FLOW,  !- A32')
    ems_pump_program.addLine('SET CHILLER_PUMP_3_FLOW = CHILLER_PUMP_3_DES_FLOW,  !- A33')
    ems_pump_program.addLine('ENDIF  !- A34')

    ems_pump_program_manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    ems_pump_program_manager.setName("#{plant_name.gsub(/[-\s]+/, '_')}_Pump_Program_Manager")
    ems_pump_program_manager.setCallingPoint('InsideHVACSystemIterationLoop')
    ems_pump_program_manager.addProgram(ems_pump_program)
  end

  # Apply prm baseline pump power
  # @note I think it makes more sense to sense the motor efficiency right there...
  #   But actually it's completely irrelevant...
  #   you could set at 0.9 and just calculate the pressure rise to have your 19 W/GPM or whatever
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_pump_power(plant_loop)
    hot_water_pump_power = 19 # W/gpm
    hot_water_district_pump_power = 14 # W/gpm
    chilled_water_primary_pump_power = 9 # W/gpm
    chilled_water_secondary_pump_power = 13 # W/gpm
    chilled_water_district_pump_power = 16 # W/gpm
    condenser_water_pump_power = 19 # W/gpm
    # Determine the pumping power per
    # flow based on loop type.
    w_per_gpm = nil
    chiller_counter = 0

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

      w_per_gpm = if has_district_heating # District HW
                    hot_water_district_pump_power
                  else # HW
                    hot_water_pump_power
                  end

    when 'Cooling'
      has_district_cooling = false
      plant_loop.supplyComponents.each do |sc|
        if sc.to_DistrictCooling.is_initialized
          has_district_cooling = true
        elsif sc.to_ChillerElectricEIR.is_initialized
          chiller_counter += 1
        end
      end

      if has_district_cooling # District CHW
        w_per_gpm = chilled_water_district_pump_power
      elsif plant_loop.additionalProperties.hasFeature('is_primary_loop') # The primary loop of the primary/secondary CHW
        w_per_gpm = chilled_water_primary_pump_power
      elsif plant_loop.additionalProperties.hasFeature('is_secondary_loop') # The secondary loop of the primary/secondary CHW
        w_per_gpm = chilled_water_secondary_pump_power
      else # Primary only CHW combine 9W/gpm + 13W/gpm
        w_per_gpm = chilled_water_primary_pump_power + chilled_water_secondary_pump_power
      end

    when 'Condenser'
      # @todo prm condenser loop pump power
      w_per_gpm = condenser_water_pump_power
    end

    # Modify all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpConstantSpeed.is_initialized
        pump = sc.to_PumpConstantSpeed.get
        if chiller_counter > 0
          w_per_gpm /= chiller_counter
        end
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, w_per_gpm)
      elsif sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, w_per_gpm)
      elsif sc.to_HeaderedPumpsConstantSpeed.is_initialized
        pump = sc.to_HeaderedPumpsConstantSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, w_per_gpm)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        pump_apply_prm_pressure_rise_and_motor_efficiency(pump, w_per_gpm)
      end
    end
    return true
  end

  # Apply sizing and controls to chilled water loop
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @param dsgn_sup_wtr_temp [Double] design chilled water supply T
  # @param dsgn_sup_wtr_temp_delt [Double] design chilled water supply delta T
  # @return [Boolean] returns true if successful, false if not
  def chw_sizing_control(model, chilled_water_loop, dsgn_sup_wtr_temp, dsgn_sup_wtr_temp_delt)
    design_chilled_water_temperature = 44 # Loop design chilled water temperature (F)
    design_chilled_water_temperature_delta = 10.1 # Loop design chilled water temperature  (deltaF)
    chw_outdoor_temperature_high = 80 # Chilled water temperature reset at high outdoor air temperature (F)
    chw_outdoor_temperature_low = 60 # Chilled water temperature reset at low outdoor air temperature (F)
    chw_outdoor_high_setpoint = 44 # Chilled water setpoint temperature at high outdoor air temperature (F)
    chw_outdoor_low_setpoint = 54 # Chilled water setpoint temperature at low outdoor air temperature (F)
    chiller_chw_low_temp_limit = 36 # Chiller leaving chilled water lower temperature limit (F)
    chiller_chw_cond_temp = 95 # Chiller entering condenser fluid temperature (F)
    primary_pump_power = 9 # primary pump power (W/gpm)

    if dsgn_sup_wtr_temp.nil?
      dsgn_sup_wtr_temp_c = OpenStudio.convert(design_chilled_water_temperature, 'F', 'C').get
    else
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp_delt.nil?
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(design_chilled_water_temperature_delta, 'R', 'K').get
    else
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(dsgn_sup_wtr_temp_delt, 'R', 'K').get
    end
    chilled_water_loop.setMinimumLoopTemperature(1.0)
    chilled_water_loop.setMaximumLoopTemperature(40.0)

    sizing_plant = chilled_water_loop.sizingPlant
    sizing_plant.setLoopType('Cooling')
    sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)
    # Use OA reset setpoint manager
    outdoor_low_temperature_c = OpenStudio.convert(chw_outdoor_temperature_low, 'F', 'C').get.round(1)
    outdoor_high_temperature_c = OpenStudio.convert(chw_outdoor_temperature_high, 'F', 'C').get.round(1)
    setpoint_temperature_outdoor_high_c = OpenStudio.convert(chw_outdoor_high_setpoint, 'F', 'C').get.round(1)
    setpoint_temperature_outdoor_low_c = OpenStudio.convert(chw_outdoor_low_setpoint, 'F', 'C').get.round(1)

    chw_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
    chw_stpt_manager.setName("#{chilled_water_loop.name} Setpoint Manager")
    chw_stpt_manager.setOutdoorHighTemperature(outdoor_high_temperature_c) # Degrees Celsius
    chw_stpt_manager.setSetpointatOutdoorHighTemperature(setpoint_temperature_outdoor_high_c) # Degrees Celsius
    chw_stpt_manager.setOutdoorLowTemperature(outdoor_low_temperature_c) # Degrees Celsius
    chw_stpt_manager.setSetpointatOutdoorLowTemperature(setpoint_temperature_outdoor_low_c) # Degrees Celsius
    chw_stpt_manager.addToNode(chilled_water_loop.supplyOutletNode)

    return true
  end

  # Set configuration in model for chilled water primary/secondary loop interface
  # Use heat_exchanger for stable baseline
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] common_pipe or heat_exchanger
  def plant_loop_set_chw_pri_sec_configuration(model)
    pri_sec_config = 'heat_exchanger'
    return pri_sec_config
  end
end
