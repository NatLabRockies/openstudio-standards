class Standard
  # @!group AirConditionerVariableRefrigerantFlow

  # find search criteria
  #
  # @param air_conditioner_variable_refrigerant_flow [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] vrf object
  # @return [Hash] used for standards_lookup_table(model)
  def air_conditioner_variable_refrigerant_flow_find_search_criteria(air_conditioner_variable_refrigerant_flow)
    # Define the criteria to find the boiler properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template

    search_criteria['subcategory'] = 'VRF multisplit system'
    if air_conditioner_variable_refrigerant_flow.condenserType == 'AirCooled'
      search_criteria['equipment_type'] = 'AirCooled'
    elsif air_conditioner_variable_refrigerant_flow.condenserType == 'WaterCooled'
      search_criteria['equipment_type'] = 'WaterSource'
    else
      search_criteria['equipment_type'] = ''
    end

    return search_criteria
  end

  # Finds lookup object in standards and return minimum thermal efficiency
  #
  # @param air_conditioner_variable_refrigerant_flow [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] vrf unit
  # @return [Boolean] returns true if successful, false if not
  def air_conditioner_variable_refrigerant_flow_apply_efficiency_and_curves(air_conditioner_variable_refrigerant_flow)
    successfully_set_all_properties = false

    # Define the criteria to find the vrf properties
    # in the hvac standards data set.
    search_criteria = air_conditioner_variable_refrigerant_flow_find_search_criteria(air_conditioner_variable_refrigerant_flow)

    # Get the capacity
    capacity_w = OpenstudioStandards::HVAC.air_conditioner_variable_refrigerant_flow_get_capacity(air_conditioner_variable_refrigerant_flow)

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Get the vrf properties
    search_criteria['equipment_type'] << 'CoolingMode'
    vrf_props_cooling = model_find_object(standards_data['vrfs'], search_criteria, capacity_btu_per_hr)
    unless vrf_props_cooling
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{air_conditioner_variable_refrigerant_flow.name}, cannot find VRF cooling properties with search criteria #{search_criteria}, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end
    search_criteria['equipment_type'].sub('Cooling', 'Heating')
    vrf_props_heating = model_find_object(standards_data['vrfs'], search_criteria, capacity_btu_per_hr)
    unless vrf_props_heating
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{air_conditioner_variable_refrigerant_flow.name}, cannot find VRF heating properties with search criteria #{search_criteria}, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency standards
    cooling_cop = nil
    heating_cop = nil

    # If specified as SEER
    unless vrf_props_cooling['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = vrf_props_cooling['minimum_seasonal_energy_efficiency_ratio']
      cooling_cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as SEER2
    # TODO: assumed to be the same as SEER for now
    unless vrf_props_cooling['minimum_seasonal_energy_efficiency_ratio_2'].nil?
      min_seer = vrf_props_cooling['minimum_seasonal_energy_efficiency_ratio_2']
      cooling_cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless vrf_props_cooling['minimum_energy_efficiency_ratio'].nil?
      min_eer = vrf_props_cooling['minimum_energy_efficiency_ratio']
      cooling_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as EER2
    # TODO: assumed to be the same as EER for now
    unless vrf_props_cooling['minimum_energy_efficiency_ratio_2'].nil?
      min_eer = vrf_props_cooling['minimum_energy_efficiency_ratio_2']
      cooling_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as HSPF
    unless vrf_props_heating['minimum_heating_seasonal_performance_factor'].nil?
      min_hspf = vrf_props_heating['minimum_heating_seasonal_performance_factor']
      heating_cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(min_hspf)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round} Clg kBtu/hr #{min_hspf.round(1)}HSPF"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; HSPF = #{min_hspf}")
    end

    # If specified as HSPF2
    # TODO: assumed to be the same as HSPF for now
    unless vrf_props_heating['minimum_heating_seasonal_performance_factor_2'].nil?
      min_hspf = vrf_props_heating['minimum_heating_seasonal_performance_factor_2']
      heating_cop = OpenstudioStandards::HVAC.hspf_to_cop_no_fan(min_hspf)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round} Clg kBtu/hr #{min_hspf.round(1)}HSPF"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; HSPF = #{min_hspf}")
    end

    # If specified as COP
    unless vrf_props_heating['minimum_coefficient_of_performance_heating'].nil?
      min_coph = vrf_props_heating['minimum_coefficient_of_performance_heating']
      heating_cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(min_coph, OpenStudio.convert(capacity_kbtu_per_hr, 'kBtu/hr', 'W').get)
      new_comp_name = "#{air_conditioner_variable_refrigerant_flow.name} #{capacity_kbtu_per_hr.round} Clg kBtu/hr #{min_coph.round(1)}COPH"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirConditionerVariableRefrigerantFlow', "For #{template}: #{air_conditioner_variable_refrigerant_flow.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; COPH = #{min_coph}")
    end

    # Set the name
    air_conditioner_variable_refrigerant_flow.setName(new_comp_name)

    # Set the efficiency values
    unless cooling_cop.nil?
      air_conditioner_variable_refrigerant_flow.setGrossRatedCoolingCOP(cooling_cop)
    end
    unless heating_cop.nil?
      air_conditioner_variable_refrigerant_flow.setGrossRatedHeatingCOP(heating_cop)
    end

    return successfully_set_all_properties
  end
end
