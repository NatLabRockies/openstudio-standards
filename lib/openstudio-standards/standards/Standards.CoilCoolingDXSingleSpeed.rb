class Standard
  # @!group CoilCoolingDXSingleSpeed

  include CoilDX

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @param necb_ref_hp [Boolean] for compatability with NECB ruleset only.
  # @param equipment_type [Boolean] indicate that equipment_type should be in the search criteria.
  # @return [Double] full load efficiency (COP)
  def coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed, rename = false, necb_ref_hp = false, equipment_type = false)
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_single_speed, necb_ref_hp, equipment_type)
    cooling_type = search_criteria['cooling_type']
    heating_type = search_criteria['heating_type']
    sub_category = search_criteria['subcategory']
    equipment_type = nil

    # Define database
    if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
      database = standards_data['heat_pumps']
    else
      database = standards_data['unitary_acs']
    end


    # Additional search criteria
    if database[0].keys.include?('equipment_type') || ((template == 'NECB2011') || (template == 'NECB2015') || (template == 'NECB2017') || (template == 'NECB2020') || (template == 'BTAPPRE1980') ||
      (template == 'BTAP1980TO2010'))
      if search_criteria.keys.include?('equipment_type')
        equipment_type = search_criteria['equipment_type']
        if ['PTAC', 'PTHP'].include?(equipment_type) && template.include?('90.1')
          search_criteria['application'] = coil_dx_packaged_terminal_application(coil_cooling_dx_single_speed)
        end
      elsif !OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
        search_criteria['equipment_type'] = 'Air Conditioners'
      end
    end
    if database[0].keys.include?('region')
      search_criteria['region'] = nil # non-nil values are currently used for residential products
    end

    if ['PTAC', 'PTHP'].include?(equipment_type) || ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_single_speed))
      thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil_cooling_dx_single_speed)
      multiplier = thermal_zone.multiplier if !thermal_zone.nil?
    end
    # Get the capacity
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    ac_props = nil
    ac_props = model_find_object(database, search_criteria, capacity_btu_per_hr, Date.today)
    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return false
    end

    # Get the minimum efficiency standards
    cop = nil

    # If PTHP, use equations if coefficients are specified
    pthp_eer_coeff_1 = ac_props['pthp_eer_coefficient_1']
    pthp_eer_coeff_2 = ac_props['pthp_eer_coefficient_2']
    if equipment_type == 'PTHP' && !pthp_eer_coeff_1.nil? && !pthp_eer_coeff_2.nil?
      # TABLE 6.8.1D
      # EER = pthp_eer_coeff_1 - (pthp_eer_coeff_2 * Cap / 1000)
      # Note c: Cap means the rated cooling capacity of the product in Btu/h.
      # If the unit's capacity is less than 7000 Btu/h, use 7000 Btu/h in the calculation.
      # If the unit's capacity is greater than 15,000 Btu/h, use 15,000 Btu/h in the calculation.
      eer_calc_cap_btu_per_hr = capacity_btu_per_hr
      eer_calc_cap_btu_per_hr = 7000 if capacity_btu_per_hr < 7000
      eer_calc_cap_btu_per_hr = 15_000 if capacity_btu_per_hr > 15_000
      pthp_eer = pthp_eer_coeff_1 - (pthp_eer_coeff_2 * eer_calc_cap_btu_per_hr / 1000.0)
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(pthp_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{pthp_eer.round(1)}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{pthp_eer.round(1)}")
    end

    # If PTAC, use equations if coefficients are specified
    ptac_eer_coeff_1 = ac_props['ptac_eer_coefficient_1']
    ptac_eer_coeff_2 = ac_props['ptac_eer_coefficient_2']
    if equipment_type == 'PTAC' && !ptac_eer_coeff_1.nil? && !ptac_eer_coeff_2.nil?
      # TABLE 6.8.1D
      # EER = ptac_eer_coeff_1 - (ptac_eer_coeff_2 * Cap / 1000)
      # Note c: Cap means the rated cooling capacity of the product in Btu/h.
      # If the unit's capacity is less than 7000 Btu/h, use 7000 Btu/h in the calculation.
      # If the unit's capacity is greater than 15,000 Btu/h, use 15,000 Btu/h in the calculation.
      eer_calc_cap_btu_per_hr = capacity_btu_per_hr
      eer_calc_cap_btu_per_hr = 7000 if capacity_btu_per_hr < 7000
      eer_calc_cap_btu_per_hr = 15_000 if capacity_btu_per_hr > 15_000
      ptac_eer = ptac_eer_coeff_1 - (ptac_eer_coeff_2 * eer_calc_cap_btu_per_hr / 1000.0)
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(ptac_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{ptac_eer.round(1)}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{ptac_eer.round(1)}")
    end

    # If CRAC, use equations if coefficients are specified
    crac_minimum_scop = ac_props['minimum_scop']
    if sub_category == 'CRAC' && !crac_minimum_scop.nil?
      # TABLE 6.8.1K in 90.1-2010, TABLE 6.8.1-10 in 90.1-2019
      # cop = scop/sensible heat ratio
      if coil_cooling_dx_single_speed.ratedSensibleHeatRatio.is_initialized
        crac_sensible_heat_ratio = coil_cooling_dx_single_speed.ratedSensibleHeatRatio.get
      elsif coil_cooling_dx_single_speed.autosizedRatedSensibleHeatRatio.is_initialized
        # Though actual inlet temperature is very high (thus basically no dehumidification),
        # sensible heat ratio can't be pre-assigned as 1 because it should be the value at conditions defined in ASHRAE Standard 127 => 26.7 degC drybulb/19.4 degC wetbulb.
        crac_sensible_heat_ratio = coil_cooling_dx_single_speed.autosizedRatedSensibleHeatRatio.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CoilCoolingDXSingleSpeed', 'Failed to get autosized sensible heat ratio')
      end
      cop = crac_minimum_scop / crac_sensible_heat_ratio
      cop = cop.round(2)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{crac_minimum_scop}SCOP #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SCOP = #{crac_minimum_scop}")
    end

    # If specified as SEER
    unless ac_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as SEER2
    # TODO: assumed to be the same as SEER for now
    unless ac_props['minimum_seasonal_energy_efficiency_ratio_2'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio_2']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless ac_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as EER2
    # TODO: assumed to be the same as EER for now
    unless ac_props['minimum_energy_efficiency_ratio_2'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio_2']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specific as IEER
    if !ac_props['minimum_integrated_energy_efficiency_ratio'].nil? && cop.nil?
      min_ieer = ac_props['minimum_integrated_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.ieer_to_cop_no_fan(min_ieer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_ieer}IEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXTwoSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as SEER
    unless ac_props['minimum_seasonal_efficiency'].nil?
      min_seer = ac_props['minimum_seasonal_efficiency']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless ac_props['minimum_full_load_efficiency'].nil?
      min_eer = ac_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Rename
    if rename
      coil_cooling_dx_single_speed.setName(new_comp_name)
    end

    return cop
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param sql_db_vars_map [Hash] hash map
  # @param necb_ref_hp [Boolean] for compatability with NECB ruleset only.
  # @return [Hash] hash of coil objects
  def coil_cooling_dx_single_speed_apply_efficiency_and_curves(coil_cooling_dx_single_speed, sql_db_vars_map, necb_ref_hp = false)
    # Get efficiencies data depending on whether it is a unitary AC or a heat pump
    coil_efficiency_data = if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
                             standards_data['heat_pumps']
                           else
                             standards_data['unitary_acs']
                           end

    # Get the search criteria
    equipment_type = coil_efficiency_data[0].keys.include?('equipment_type') ? true : false
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_single_speed, necb_ref_hp, equipment_type)

    # Additional search criteria
    if coil_efficiency_data[0].keys.include?('equipment_type') || ((template == 'NECB2011') || (template == 'NECB2015') || (template == 'NECB2017') || (template == 'NECB2020') || (template == 'BTAPPRE1980') ||
      (template == 'BTAP1980TO2010'))
      if search_criteria.keys.include?('equipment_type')
        equipment_type = search_criteria['equipment_type']
        if ['PTAC', 'PTHP'].include?(equipment_type) && template.include?('90.1')
          search_criteria['application'] = coil_dx_packaged_terminal_application(coil_cooling_dx_single_speed)
        end
      elsif !OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
        search_criteria['equipment_type'] = 'Air Conditioners'
      end
    end
    if coil_efficiency_data[0].keys.include?('region')
      search_criteria['region'] = nil # non-nil values are currently used for residential products
    end

    # Get the capacity
    if ['PTAC', 'PTHP'].include?(equipment_type) || ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_single_speed))
      thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil_cooling_dx_single_speed)
      multiplier = thermal_zone.multiplier if !thermal_zone.nil?
    end
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Lookup efficiency
    ac_props = model_find_object(coil_efficiency_data, search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return sql_db_vars_map
    end

    equipment_type_field = search_criteria['equipment_type']
    # Make the COOL-CAP-FT curve
    cool_cap_ft = nil
    if ac_props['cool_cap_ft']
      cool_cap_ft = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_cap_ft'])
    else
      cool_cap_ft_curve_name = coil_dx_cap_ft(coil_cooling_dx_single_speed, equipment_type_field)
      cool_cap_ft = model_add_curve(coil_cooling_dx_single_speed.model, cool_cap_ft_curve_name)
    end
    if cool_cap_ft
      coil_cooling_dx_single_speed.setTotalCoolingCapacityFunctionOfTemperatureCurve(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_cap_ft curve, will not be set.")
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = nil
    if ac_props['cool_cap_fflow']
      cool_cap_fflow = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_cap_fflow'])
    else
      cool_cap_fflow_curve_name = coil_dx_cap_fflow(coil_cooling_dx_single_speed, equipment_type_field)
      cool_cap_fflow = model_add_curve(coil_cooling_dx_single_speed.model, cool_cap_fflow_curve_name)
    end
    if cool_cap_fflow
      coil_cooling_dx_single_speed.setTotalCoolingCapacityFunctionOfFlowFractionCurve(cool_cap_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = nil
    if ac_props['cool_eir_ft']
      cool_eir_ft = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_eir_ft'])
    else
      cool_eir_ft_curve_name = coil_dx_eir_ft(coil_cooling_dx_single_speed, equipment_type_field)
      cool_eir_ft = model_add_curve(coil_cooling_dx_single_speed.model, cool_eir_ft_curve_name)
    end
    if cool_eir_ft
      coil_cooling_dx_single_speed.setEnergyInputRatioFunctionOfTemperatureCurve(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_eir_ft curve, will not be set.")
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = nil
    if ac_props['cool_eir_fflow']
      cool_eir_fflow = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_eir_fflow'])
    else
      cool_eir_fflow_curve_name = coil_dx_eir_fflow(coil_cooling_dx_single_speed, equipment_type_field)
      cool_eir_fflow = model_add_curve(coil_cooling_dx_single_speed.model, cool_eir_fflow_curve_name)
    end
    if cool_eir_fflow
      coil_cooling_dx_single_speed.setEnergyInputRatioFunctionOfFlowFractionCurve(cool_eir_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = nil
    if ac_props['cool_plf_fplr']
      cool_plf_fplr = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_plf_fplr'])
    else
      cool_plf_fplr_curve_name = coil_dx_plf_fplr(coil_cooling_dx_single_speed, equipment_type_field)
      cool_plf_fplr = model_add_curve(coil_cooling_dx_single_speed.model, cool_plf_fplr_curve_name)
    end
    if cool_plf_fplr
      coil_cooling_dx_single_speed.setPartLoadFractionCorrelationCurve(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
    end

    # Preserve the original name
    orig_name = coil_cooling_dx_single_speed.name.to_s

    # Find the minimum COP and rename with efficiency rating
    cop = coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed, true, necb_ref_hp, equipment_type)

    # Map the original name to the new name
    sql_db_vars_map[coil_cooling_dx_single_speed.name.to_s] = orig_name

    # Set the efficiency values
    unless cop.nil?
      coil_cooling_dx_single_speed.setRatedCOP(OpenStudio::OptionalDouble.new(cop))
    end

    return sql_db_vars_map
  end
end
