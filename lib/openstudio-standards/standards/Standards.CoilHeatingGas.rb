class Standard
  # @!group CoilHeatingGas

  # Applies the standard efficiency ratings to CoilHeatingGas.
  #
  # @param coil_heating_gas [OpenStudio::Model::CoilHeatingGas] coil heating gas object
  # @param search_criteria [Hash] search criteria for looking up furnace data
  # @return [Hash] updated search criteria
  def coil_heating_gas_additional_search_criteria(coil_heating_gas, search_criteria)
    return search_criteria
  end

  # Applies the standard efficiency ratings to CoilHeatingGas.
  #
  # @param coil_heating_gas [OpenStudio::Model::CoilHeatingGas] coil heating gas object
  # @return [Boolean] returns true if successful, false if not
  def coil_heating_gas_apply_efficiency_and_curves(coil_heating_gas)
    successfully_set_all_properties = false
    # Initialize search criteria
    search_criteria = {}
    search_criteria['template'] = template
    search_criteria['equipment_type'] = 'Warm Air Furnace'
    search_criteria['fuel_type'] = 'NaturalGas'
    search_criteria = coil_heating_gas_additional_search_criteria(coil_heating_gas, search_criteria)

    # Get the capacity, but return false if not available
    capacity_w = OpenstudioStandards::HVAC.coil_heating_gas_get_capacity(coil_heating_gas)

    # Return false if the coil does not have a heating capacity associated with it. Cannot apply the standard if without
    # it.
    return successfully_set_all_properties if capacity_w == false

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    return false unless capacity_btu_per_hr > 0

    # Get the boiler properties, if it exists for this template
    return false unless standards_data.include?('furnaces')

    furnace_props = model_find_object(standards_data['furnaces'], search_criteria, capacity_btu_per_hr)
    unless furnace_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find furnace properties with search criteria #{search_criteria}, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency standards
    thermal_eff = nil

    # If specified as thermal efficiency, this takes precedent
    if furnace_props['minimum_thermal_efficiency'].nil?
      # If not thermal efficiency, check other parameters

      # If specified as AFUE
      unless furnace_props['minimum_annual_fuel_utilization_efficiency'].nil?
        min_afue = furnace_props['minimum_annual_fuel_utilization_efficiency']
        thermal_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(min_afue)
        new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_afue} AFUE"
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: = #{capacity_kbtu_per_hr.round}kBtu/hr; AFUE = #{min_afue}")
      end

      # If specified as combustion efficiency
      unless furnace_props['minimum_combustion_efficiency'].nil?
        min_comb_eff = furnace_props['minimum_combustion_efficiency']
        thermal_eff = OpenstudioStandards::HVAC.combustion_eff_to_thermal_eff(min_comb_eff)
        new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_comb_eff} Combustion Eff"
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: = #{capacity_kbtu_per_hr.round}kBtu/hr; Combustion Efficiency = #{min_comb_eff}")
      end
    else
      thermal_eff = furnace_props['minimum_thermal_efficiency']
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{thermal_eff} Thermal Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: = #{capacity_kbtu_per_hr.round}kBtu/hr; Thermal Efficiency = #{thermal_eff}")
    end

    # Set the efficiency values
    unless thermal_eff.nil?

      # Set the name
      coil_heating_gas.setName(new_comp_name)
      coil_heating_gas.setGasBurnerEfficiency(thermal_eff)
      successfully_set_all_properties = true
    end

    return successfully_set_all_properties
  end
end
