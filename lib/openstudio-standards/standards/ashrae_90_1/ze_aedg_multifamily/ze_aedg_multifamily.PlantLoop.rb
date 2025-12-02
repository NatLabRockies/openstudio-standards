class ZEAEDGMultifamily < ASHRAE901
  # @!group PlantLoop

  # Applies the chilled water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_chilled_water_pumping_type(plant_loop)
    pri_control_type = 'VSD DP Reset'
    sec_control_type = 'VSD DP Reset'
    has_secondary_pump = false

    # Modify all the secondary pumps
    plant_loop.demandComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: sec_control_type)
        has_secondary_pump = true
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: sec_control_type)
        has_secondary_pump = true
      end
    end

    # Primary is constant flow if primary/secondary setup
    pri_control_type = 'Constant Flow' if has_secondary_pump

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

    # Report out the pumping type
    unless pri_control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{plant_loop.name}, primary pump type is #{pri_control_type}.")
    end

    if has_secondary_pump
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{plant_loop.name}, secondary pump type is #{sec_control_type}.")
    end

    return true
  end

  # Applies the hot water pumping controls to the loop
  def plant_loop_apply_prm_baseline_hot_water_pumping_type(plant_loop)
    control_type = 'VSD DP Reset'

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
end
