class ACM179dASHRAE9012007
  # @!group PlantLoop

  # Applies the chilled water pumping controls to the loop based on Appendix G.
  # NOTE: 179D overrides it only because there is a bug related to control_type for Headered Pumps
  # Backports: https://github.com/NREL/openstudio-standards/pull/1749
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @return [Bool] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_chilled_water_pumping_type(plant_loop)
    # Determine the pumping type.
    minimum_cap_tons = 300.0

    # Determine the capacity
    cap_w = plant_loop_total_cooling_capacity(plant_loop)
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
        pump_variable_speed_set_control_type(pump, pri_control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        headered_pumps_variable_speed_set_control_type(pump, pri_control_type) # NOTE: fix here
      end
    end

    # Modify all the secondary pumps besides constant pumps
    plant_loop.demandComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        pump_variable_speed_set_control_type(pump, sec_control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        headered_pumps_variable_speed_set_control_type(pump, pri_control_type) # NOTE: fix here
      end
    end

    return true
  end
end
