class Standard
  # @!group CoilCoolingDXMultiSpeed

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_cooling_dx_multi_speed [OpenStudio::Model::CoilCoolingDXMultiSpeed] coil cooling dx multi speed object
  # @param sql_db_vars_map [Hash] hash map
  # @return [Hash] hash of coil objects
  def coil_cooling_dx_multi_speed_apply_efficiency_and_curves(coil_cooling_dx_multi_speed, sql_db_vars_map)
    # Define the criteria to find the cooling coil properties in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template
    cooling_type = coil_cooling_dx_multi_speed.condenserType
    search_criteria['cooling_type'] = cooling_type

    # @todo Standards - add split system vs single package to model
    # For now, assume single package as default
    sub_category = 'Single Package'

    # Determine the heating type if unitary or zone hvac
    heat_pump = false
    heating_type = nil
    containing_comp = nil
    if coil_cooling_dx_multi_speed.airLoopHVAC.empty?
      if coil_cooling_dx_multi_speed.containingHVACComponent.is_initialized
        containing_comp = coil_cooling_dx_multi_speed.containingHVACComponent.get
        if containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized
          htg_coil = containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get.heatingCoil
          if htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized
            heat_pump = true
            heating_type = 'Electric Resistance or None'
          elsif htg_coil.to_CoilHeatingGasMultiStage.is_initialized
            heating_type = 'All Other'
          end
          # @todo Add other unitary systems
        end
      elsif coil_cooling_dx_multi_speed.containingZoneHVACComponent.is_initialized
        containing_comp = coil_cooling_dx_multi_speed.containingZoneHVACComponent.get
        if containing_comp.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          sub_category = 'PTAC'
          htg_coil = containing_comp.to_ZoneHVACPackagedTerminalAirConditioner.get.heatingCoil
          if htg_coil.to_CoilHeatingElectric.is_initialized
            heating_type = 'Electric Resistance or None'
          elsif htg_coil.to_CoilHeatingWater.is_initialized || htg_coil.to_CoilHeatingGas.is_initialized || htg_col.to_CoilHeatingGasMultiStage
            heating_type = 'All Other'
          end
          # @todo Add other zone hvac systems
        end
      end
    end

    # Add the heating type to the search criteria
    unless heating_type.nil?
      search_criteria['heating_type'] = heating_type
    end

    search_criteria['subcategory'] = sub_category

    # Get the coil capacity
    capacity_w = nil
    clg_stages = stages
    if clg_stages.last.grossRatedTotalCoolingCapacity.is_initialized
      capacity_w = clg_stages.last.grossRatedTotalCoolingCapacity.get
    elsif coil_cooling_dx_multi_speed.autosizedSpeed4GrossRatedTotalCoolingCapacity.is_initialized
      capacity_w = coil_cooling_dx_multi_speed.autosizedSpeed4GrossRatedTotalCoolingCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name} capacity is not available, cannot apply efficiency standard.")
      return false
    end

    # Volume flow rate
    flow_rate4 = nil
    if clg_stages.last.ratedAirFlowRate.is_initialized
      flow_rate4 = clg_stages.last.ratedAirFlowRate.get
    elsif coil_cooling_dx_multi_speed.autosizedSpeed4RatedAirFlowRate.is_initialized
      flow_rate4 = coil_cooling_dx_multi_speed.autosizedSpeed4RatedAirFlowRate.get
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Get efficiencies data depending on whether it is a unitary AC or a heat pump
    coil_efficiency_data = if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_multi_speed)
                             standards_data['heat_pumps']
                           else
                             standards_data['unitary_acs']
                           end

    # Additional search criteria
    if (coil_efficiency_data[0].keys.include?('equipment_type') || ((template == 'NECB2011') || (template == 'NECB2015') || (template == 'NECB2017') || (template == 'NECB2020') || (template == 'BTAPPRE1980') ||
      (template == 'BTAP1980TO2010'))) && !OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_multi_speed)
      search_criteria['equipment_type'] = 'Air Conditioners'
    end
    if coil_efficiency_data[0].keys.include?('region')
      search_criteria['region'] = nil # non-nil values are currently used for residential products
    end

    # Lookup efficiency
    ac_props = model_find_object(coil_efficiency_data, search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return false
    end

    # Make the COOL-CAP-FT curve
    cool_cap_ft = nil
    if ac_props['cool_cap_ft']
      cool_cap_ft = model_add_curve(coil_cooling_dx_multi_speed.model, ac_props['cool_cap_ft'])
    else
      cool_cap_ft_curve_name = coil_dx_cap_ft(coil_cooling_dx_multi_speed)
      cool_cap_ft = model_add_curve(coil_cooling_dx_multi_speed.model, cool_cap_ft_curve_name)
    end
    if cool_cap_ft
      clg_stages.each do |stage|
        stage.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_cap_ft curve, will not be set.")
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = nil
    if ac_props['cool_cap_fflow']
      cool_cap_fflow = model_add_curve(coil_coolingcoil_cooling_dx_multi_speed_dx_two_speed.model, ac_props['cool_cap_fflow'])
    else
      cool_cap_fflow_curve_name = coil_dx_cap_fflow(coil_cooling_dx_multi_speed)
      cool_cap_fflow = model_add_curve(coil_cooling_dx_multi_speed.model, cool_cap_fflow_curve_name)
    end
    if cool_cap_fflow
      clg_stages.each do |stage|
        stage.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = nil
    if ac_props['cool_eir_ft']
      cool_eir_ft = model_add_curve(coil_cooling_dx_multi_speed.model, ac_props['cool_eir_ft'])
    else
      cool_eir_ft_curve_name = coil_dx_eir_ft(coil_cooling_dx_multi_speed)
      cool_eir_ft = model_add_curve(coil_cooling_dx_multi_speed.model, cool_eir_ft_curve_name)
    end
    if cool_eir_ft
      clg_stages.each do |stage|
        stage.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_eir_ft curve, will not be set.")
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = nil
    if ac_props['cool_eir_fflow']
      cool_eir_fflow = model_add_curve(coil_cooling_dx_multi_speed.model, ac_props['cool_eir_fflow'])
    else
      cool_eir_fflow_curve_name = coil_dx_eir_fflow(coil_cooling_dx_multi_speed)
      cool_eir_fflow = model_add_curve(coil_cooling_dx_multi_speed.model, cool_eir_fflow_curve_name)
    end
    if cool_eir_fflow
      clg_stages.each do |stage|
        stage.setEnergyInputRatioFunctionofFlowFractionCurve(cool_eir_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = nil
    if ac_props['cool_plf_fplr']
      cool_plf_fplr = model_add_curve(coil_cooling_dx_multi_speed.model, ac_props['cool_plf_fplr'])
    else
      cool_plf_fplr_curve_name = coil_dx_plf_fplr(coil_cooling_dx_multi_speed)
      cool_plf_fplr = model_add_curve(coil_cooling_dx_multi_speed.model, cool_plf_fplr_curve_name)
    end
    if cool_plf_fplr
      clg_stages.each do |stage|
        stage.setPartLoadFractionCorrelationCurve(cool_plf_fplr)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
    end

    # Get the minimum efficiency standards
    cop = nil

    if coil_dx_subcategory(coil_cooling_dx_multi_speed) == 'PTAC'
      ptac_eer_coeff_1 = ac_props['ptac_eer_coefficient_1']
      ptac_eer_coeff_2 = ac_props['ptac_eer_coefficient_2']
      capacity_btu_per_hr = 7000 if capacity_btu_per_hr < 7000
      capacity_btu_per_hr = 15_000 if capacity_btu_per_hr > 15_000
      ptac_eer = ptac_eer_coeff_1 + (ptac_eer_coeff_2 * capacity_btu_per_hr)
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(ptac_eer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{ptac_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{ptac_eer}")
    end

    # Preserve the original name
    orig_name = coil_cooling_dx_single_speed.name.to_s

    # Find the minimum COP and rename with efficiency rating
    new_comp_name, cop = coil_cooling_dx_multi_speed_standard_minimum_cop(coil_cooling_dx_multi_speed)

    sql_db_vars_map[new_comp_name] = orig_name

    # Set the new name
    coil_cooling_dx_multi_speed.setName(new_comp_name)

    # Set the efficiency values
    unless cop.nil?
      clg_stages.each do |istage|
        istage.setGrossRatedCoolingCOP(cop)
      end
    end

    return sql_db_vars_map
  end

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_cooling_dx_multi_speed [OpenStudio::Model::CoilCoolingDXMultiSpeed] coil cooling dx multi speed object
  # @return [Array] array of full load efficiency (COP), new object name
  # @todo align the method arguments and return types
  def coil_cooling_dx_multi_speed_standard_minimum_cop(coil_cooling_dx_multi_speed)
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_multi_speed)
    cooling_type = search_criteria['cooling_type']
    heating_type = search_criteria['heating_type']
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_multi_speed_get_capacity(coil_cooling_dx_multi_speed)

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Define database
    if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_multi_speed)
      database = standards_data['heat_pumps']
    else
      database = standards_data['unitary_acs']
    end

    # Additional search criteria
    if (database[0].keys.include?('equipment_type') || ((template == 'NECB2011') || (template == 'NECB2015') || (template == 'NECB2017') || (template == 'NECB2020') || (template == 'BTAPPRE1980') ||
      (template == 'BTAP1980TO2010'))) && !OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_multi_speed)
      search_criteria['equipment_type'] = 'Air Conditioners'
    end
    if database[0].keys.include?('region')
      search_criteria['region'] = nil # non-nil values are currently used for residential products
    end

    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    ac_props = nil
    ac_props = model_find_object(database, search_criteria, capacity_btu_per_hr, Date.today)

    # Get the minimum efficiency standards
    cop = nil

    # If specified as SEER
    unless ac_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_multi_speed)} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as SEER2
    # TODO: assumed to be the same as SEER for now
    unless ac_props['minimum_seasonal_energy_efficiency_ratio_2'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio_2']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXTwoSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_multi_speed)} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless ac_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_multi_speed)} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as EER2
    # TODO: assumed to be the same as EER for now
    unless ac_props['minimum_energy_efficiency_ratio_2'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio_2']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXTwoSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_multi_speed)} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specific as IEER
    if !ac_props['minimum_integrated_energy_efficiency_ratio'].nil? && cop.nil?
      min_ieer = ac_props['minimum_integrated_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.ieer_to_cop_no_fan(min_ieer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_ieer}IEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXTwoSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; IEER = #{min_ieer}")
    end

    # if specified as SEER (heat pump)
    unless ac_props['minimum_seasonal_efficiency'].nil?
      min_seer = ac_props['minimum_seasonal_efficiency']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_multi_speed)} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless ac_props['minimum_full_load_efficiency'].nil?
      min_eer = ac_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_multi_speed)} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    return cop, new_comp_name
  end
end
