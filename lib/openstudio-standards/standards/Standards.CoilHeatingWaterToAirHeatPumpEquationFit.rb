class Standard
  # @!group CoilHeatingWaterToAirHeatPumpEquationFit

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_heating_water_to_air_heat_pump [OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit] coil heating object
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @return [Double] full load efficiency (COP)
  def coil_heating_water_to_air_heat_pump_standard_minimum_cop(coil_heating_water_to_air_heat_pump, rename = false)
    search_criteria = {}
    search_criteria['template'] = template
    capacity_w = OpenstudioStandards::HVAC.coil_heating_get_paired_coil_cooling_capacity(coil_heating_water_to_air_heat_pump)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    coil_props = model_find_object(standards_data['water_source_heat_pumps_heating'], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if coil_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingWaterToAirHeatPumpEquationFit', "For #{coil_heating_water_to_air_heat_pump.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency standards
    cop = nil

    # If specified as EER
    unless coil_props['minimum_coefficient_of_performance_heating'].nil?
      cop = coil_props['minimum_coefficient_of_performance_heating']
      new_comp_name = "#{coil_heating_water_to_air_heat_pump.name} #{capacity_kbtu_per_hr.round} Clg kBtu/hr #{cop.round(1)}COPH"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingWaterToAirHeatPumpEquationFit', "For #{template}: #{coil_heating_water_to_air_heat_pump.name}: Cooling Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; COPH = #{cop}")
    end

    # Rename
    if rename
      coil_heating_water_to_air_heat_pump.setName(new_comp_name)
    end

    return cop
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_heating_water_to_air_heat_pump [OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit] coil heating object
  # @param sql_db_vars_map [Hash] hash map
  # @return [Hash] hash of coil objects
  def coil_heating_water_to_air_heat_pump_apply_efficiency_and_curves(coil_heating_water_to_air_heat_pump, sql_db_vars_map)
    successfully_set_all_properties = true

    # Get the search criteria
    search_criteria = {}
    search_criteria['template'] = template
    capacity_w = OpenstudioStandards::HVAC.coil_heating_get_paired_coil_cooling_capacity(coil_heating_water_to_air_heat_pump)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Look up the efficiency characteristics
    coil_props = model_find_object(standards_data['water_source_heat_pumps_heating'], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if coil_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingWaterToAirHeatPumpEquationFit', "For #{coil_heating_water_to_air_heat_pump.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return sql_db_vars_map
    end

    # @todo Add methods to set coefficients, and add coefficients to data spreadsheet
    # using OS defaults for now
    # heat_cap_coeff1 = coil_props['heat_cap_coeff1']
    # if heat_cap_coeff1
    #   coil_heating_water_to_air_heat_pump.setHeatingCapacityCoefficient1(heat_cap_coeff1)
    # else
    #   OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingWaterToAirHeatPumpEquationFit', "For #{coil_heating_water_to_air_heat_pump.name}, cannot find heat_cap_coeff1, will not be set.")
    #   successfully_set_all_properties = false
    # end

    # Preserve the original name
    orig_name = coil_heating_water_to_air_heat_pump.name.to_s

    # Find the minimum COP and rename with efficiency rating
    cop = coil_heating_water_to_air_heat_pump_standard_minimum_cop(coil_heating_water_to_air_heat_pump, true)

    # Map the original name to the new name
    sql_db_vars_map[coil_heating_water_to_air_heat_pump.name.to_s] = orig_name

    # Set the efficiency values
    unless cop.nil?
      coil_heating_water_to_air_heat_pump.setRatedHeatingCoefficientofPerformance(cop)
    end

    return sql_db_vars_map
  end
end
