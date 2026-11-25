class Standard
  # @!group CoilCoolingWaterToAirHeatPumpEquationFit

  # Finds the efficiency requirements that apply to water-to-air (water source) heat pump coils.
  # Water source heat pump requirements are stored in the heat_pumps (cooling) and
  # heat_pumps_heating (heating) tables with cooling_type 'WaterSource'.
  # Water-to-water rows are excluded, since they do not apply to water-to-air coils.
  # Standards whose heat pump tables do not contain water source rows (e.g. DOE Ref 1980-2004)
  # fall back to the legacy water_source_heat_pumps and water_source_heat_pumps_heating tables.
  #
  # @param table_name [String] the standards data table to search, 'heat_pumps' (cooling) or 'heat_pumps_heating' (heating)
  # @param capacity_btu_per_hr [Double] coil capacity in Btu/hr. If nil, capacity is not used in the search.
  # @return [Array<Hash>] matching efficiency objects, empty if none are found
  def water_to_air_heat_pump_find_efficiency_objects(table_name, capacity_btu_per_hr = nil)
    table = standards_data[table_name] || []
    unless table.any? { |row| row['cooling_type'] == 'WaterSource' }
      legacy_table_name = "water_source_#{table_name}"
      table = standards_data[legacy_table_name] || []
    end

    # Exclude water-to-water rows before the capacity search, otherwise they can match the capacity
    # and prevent the search from rounding the capacity down when it falls between two water-to-air rows.
    table = table.reject { |row| row['configuration'] == 'Water to Water' }

    search_criteria = { 'equipment_type' => 'Heat Pumps', 'cooling_type' => 'WaterSource' }
    return model_find_objects(table, search_criteria, capacity_btu_per_hr, Date.today)
  end

  # Finds the efficiency requirement that applies to a water-to-air (water source) heat pump coil.
  # If the coil capacity is larger than the maximum capacity in the data (e.g. because of zone multipliers),
  # the issue is logged and the requirement for the largest capacity range in the data is used.
  #
  # @param table_name [String] the standards data table to search, 'heat_pumps' (cooling) or 'heat_pumps_heating' (heating)
  # @param capacity_btu_per_hr [Double] coil capacity in Btu/hr
  # @param coil_name [String] coil name, used in log messages
  # @return [Hash, nil] the matching efficiency object, nil if none is found
  def water_to_air_heat_pump_find_efficiency_object(table_name, capacity_btu_per_hr, coil_name)
    coil_props = water_to_air_heat_pump_find_efficiency_objects(table_name, capacity_btu_per_hr).first
    return coil_props unless coil_props.nil?

    # Not found for this capacity, check if the capacity is above the largest capacity in the data
    all_objects = water_to_air_heat_pump_find_efficiency_objects(table_name)
    return nil if all_objects.empty?

    max_capacity_btu_per_hr = all_objects.map { |obj| obj['maximum_capacity'].to_f }.max
    if capacity_btu_per_hr > max_capacity_btu_per_hr
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilWaterToAirHeatPumpEquationFit', "The capacity of coil '#{coil_name}' is #{capacity_btu_per_hr.round} Btu/hr, which is larger than the maximum capacity of #{max_capacity_btu_per_hr.round} Btu/hr listed in the #{table_name} efficiency data for #{template}. This may be because of zone loads, zone size, or because zone equipment sizing in EnergyPlus includes zone multipliers. Will use the efficiency requirement for the largest capacity range.")
      coil_props = water_to_air_heat_pump_find_efficiency_objects(table_name, max_capacity_btu_per_hr).first
    end

    return coil_props
  end

  # Finds lookup object in standards and return efficiency.
  # Water source heat pump requirements are found with {#water_to_air_heat_pump_find_efficiency_object}.
  # If the coil capacity is larger than the largest capacity in the data, the requirement for the
  # largest capacity range is used and a warning is logged.
  #
  # @param coil_cooling_water_to_air_heat_pump [OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit] coil cooling object
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @param computer_room_air_conditioner [Boolean] if true, the coil is a water-cooled computer room air conditioner
  #   and the requirement is taken from the computer_room_acs data instead of the water source heat pump data
  # @return [Double, Boolean, nil] full load efficiency (COP), false if no efficiency requirement is found,
  #   nil if the coil capacity cannot be determined
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
      coil_props = model_find_object(standards_data['computer_room_acs'], search_criteria, capacity_btu_per_hr, Date.today)
    else
      coil_props = water_to_air_heat_pump_find_efficiency_object('heat_pumps', capacity_btu_per_hr, coil_cooling_water_to_air_heat_pump.name.to_s)
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
    # minimum_energy_efficiency_ratio is used by the heat_pumps table,
    # minimum_full_load_efficiency by the legacy water_source_heat_pumps table
    min_eer = coil_props['minimum_energy_efficiency_ratio'] || coil_props['minimum_full_load_efficiency']
    unless min_eer.nil?
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
  # The efficiency is found with {#coil_cooling_water_to_air_heat_pump_standard_minimum_cop}.
  #
  # @param coil_cooling_water_to_air_heat_pump [OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit] coil cooling object
  # @param sql_db_vars_map [Hash] hash map
  # @return [Hash] hash of coil objects
  def coil_cooling_water_to_air_heat_pump_apply_efficiency_and_curves(coil_cooling_water_to_air_heat_pump, sql_db_vars_map)
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_water_to_air_heat_pump_get_capacity(coil_cooling_water_to_air_heat_pump)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Look up the efficiency characteristics
    coil_props = water_to_air_heat_pump_find_efficiency_objects('heat_pumps', capacity_btu_per_hr).first

    # Check to make sure properties were found
    if coil_props.nil?
      # search again without capacity
      matching_objects = water_to_air_heat_pump_find_efficiency_objects('heat_pumps')
      if matching_objects.empty?
        # This proves that the search_criteria has issue finding the correct coil prop
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingWaterToAirHeatPumpEquationFit', "For #{coil_cooling_water_to_air_heat_pump.name}, cannot find efficiency info for a water source heat pump with capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
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
