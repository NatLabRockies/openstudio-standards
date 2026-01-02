class Standard
  # @!group CoilCoolingWaterToAirHeatPumpEquationFit

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_cooling_water_to_air_heat_pump [OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit] coil cooling object
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @return [Double] full load efficiency (COP)
  def coil_cooling_water_to_air_heat_pump_standard_minimum_cop(coil_cooling_water_to_air_heat_pump, rename = false, computer_room_air_conditioner = false)
    search_criteria = {}
    search_criteria['template'] = template
    if computer_room_air_conditioner
      search_criteria['cooling_type'] = 'WaterCooled'
      search_criteria['standard_model'] = 'Downflow units'
      cooling_type = search_criteria['cooling_type']
      heating_type = 'All Other'
      sub_category = 'CRAC'
    end
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_water_to_air_heat_pump_get_capacity(coil_cooling_water_to_air_heat_pump)

    # Check to make sure properties were found
    if capacity_w.nil? || capacity_w < 1
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "For #{coil_cooling_water_to_air_heat_pump.name}, cannot determine capacity.")
      return nil
    end
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    if computer_room_air_conditioner
      equipment_type = 'computer_room_acs'
    else
      equipment_type = 'water_source_heat_pumps'
    end
    coil_props = model_find_object(standards_data[equipment_type], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if coil_props.nil?
      # search again without capacity
      matching_objects = model_find_objects(standards_data[equipment_type], search_criteria, nil, Date.today)
      if !matching_objects.empty? && (equipment_type == 'water_source_heat_pumps') && (capacity_btu_per_hr > 135000)
        # Issue warning indicate the coil size is may be too large
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "The capacity of coil '#{coil_cooling_water_to_air_heat_pump.name}' is #{capacity_btu_per_hr.round} Btu/hr, which is larger than the 135,000 Btu/hr maximum capacity listed in the efficiency standard. This may be because of zone loads, zone size, or because zone equipment sizing in EnergyPlus includes zone multipliers. Will assume a capacity of 134,999 Btu/hr for the efficiency lookup.")
        coil_props = model_find_object(standards_data[equipment_type], search_criteria, 134999, Date.today)
      end
    end

    # Check to make sure properties were found
    if coil_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "For #{coil_cooling_water_to_air_heat_pump.name}, cannot find efficiency info using #{search_criteria}  and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Get the minimum efficiency standards
    cop = nil

    # If specified as EER (heat pump)
    unless coil_props['minimum_full_load_efficiency'].nil?
      min_eer = coil_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer, capacity_w = nil)
      new_comp_name = "#{coil_cooling_water_to_air_heat_pump.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "For #{template}: #{coil_cooling_water_to_air_heat_pump.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as SCOP (water-cooled Computer Room Air Conditioned (CRAC))
    if computer_room_air_conditioner
      crac_minimum_scop = coil_props['minimum_scop']
      unless crac_minimum_scop.nil?
        # cop = scop / sensible heat ratio
        # sensible heat ratio = sensible cool capacity / total cool capacity
        if coil_cooling_water_to_air_heat_pump.ratedSensibleCoolingCapacity.is_initialized
          crac_sensible_cool = coil_cooling_water_to_air_heat_pump.ratedSensibleCoolingCapacity.get
          crac_total_cool = coil_cooling_water_to_air_heat_pump.ratedTotalCoolingCapacity.get
          crac_sensible_cool_ratio = crac_sensible_cool / crac_total_cool
        elsif coil_cooling_water_to_air_heat_pump.autosizedRatedSensibleCoolingCapacity.is_initialized
          crac_sensible_cool = coil_cooling_water_to_air_heat_pump.autosizedRatedSensibleCoolingCapacity.get
          crac_total_cool = coil_cooling_water_to_air_heat_pump.autosizedRatedTotalCoolingCapacity.get
          crac_sensible_heat_ratio = crac_sensible_cool / crac_total_cool
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', 'Failed to get autosized sensible cool capacity')
        end
        cop = crac_minimum_scop / crac_sensible_heat_ratio
        cop = cop.round(2)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "For #{coil_cooling_water_to_air_heat_pump.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SCOP = #{crac_minimum_scop}")
      end
    end

    # Rename
    if rename
      coil_cooling_water_to_air_heat_pump.setName(new_comp_name)
    end

    return cop
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_cooling_water_to_air_heat_pump [OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit] coil cooling object
  # @param sql_db_vars_map [Hash] hash map
  # @return [Hash] hash of coil objects
  def coil_cooling_water_to_air_heat_pump_apply_efficiency_and_curves(coil_cooling_water_to_air_heat_pump, sql_db_vars_map)
    # Get the search criteria
    search_criteria = {}
    search_criteria['template'] = template
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_water_to_air_heat_pump_get_capacity(coil_cooling_water_to_air_heat_pump)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Look up the efficiency characteristics
    coil_props = model_find_object(standards_data['water_source_heat_pumps'], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if coil_props.nil?
      # search again without capacity
      matching_objects = model_find_objects(standards_data['water_source_heat_pumps'], search_criteria, nil, Date.today)
      if matching_objects.empty?
        # This proves that the search_criteria has issue finding the correct coil prop
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "For #{coil_cooling_water_to_air_heat_pump.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
        return sql_db_vars_map
      end
    end

    # Preserve the original name
    orig_name = coil_cooling_water_to_air_heat_pump.name.to_s

    # Find the minimum COP and rename with efficiency rating
    cop = coil_cooling_water_to_air_heat_pump_standard_minimum_cop(coil_cooling_water_to_air_heat_pump, true)

    # Map the original name to the new name
    sql_db_vars_map[coil_cooling_water_to_air_heat_pump.name.to_s] = orig_name

    # Set the efficiency values
    unless cop.nil?
      coil_cooling_water_to_air_heat_pump.setRatedCoolingCoefficientofPerformance(cop)
    end

    return sql_db_vars_map
  end
end
