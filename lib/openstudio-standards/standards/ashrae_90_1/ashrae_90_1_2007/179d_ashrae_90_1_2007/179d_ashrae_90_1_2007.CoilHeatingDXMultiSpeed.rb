class ACM179dASHRAE9012007
  # @!group CoilHeatingDXMultiSpeed

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_heating_dx_multi_speed [OpenStudio::Model::CoilHeatingDXMultiSpeed] coil heating dx multi speed object
  # @return [Bool] returns true if successful, false if not
  def coil_heating_dx_multi_speed_apply_efficiency_and_curves(coil_heating_dx_multi_speed, sql_db_vars_map)
    successfully_set_all_properties = true

    # Define the criteria to find the unitary properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template

    # Determine supplemental heating type if unitary
    heat_pump = false
    suppl_heating_type = nil
    if coil_heating_dx_multi_speed.airLoopHVAC.empty?
      if coil_heating_dx_multi_speed.containingHVACComponent.is_initialized
        containing_comp = coil_heating_dx_multi_speed.containingHVACComponent.get
        if containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized
          heat_pump = true
          htg_coil = containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get.supplementalHeatingCoil
          suppl_heating_type = if htg_coil.to_CoilHeatingElectric.is_initialized
                                 'Electric Resistance or None'
                               else
                                 'All Other'
                               end
        end
        # @todo Add other unitary systems
      end
    end

    # @todo Standards - add split system vs single package to model
    # For now, assume single package
    subcategory = 'Single Package'
    search_criteria['subcategory'] = subcategory

    # Get the coil capacity
    clg_capacity = nil
    if heat_pump == true
      containing_comp = coil_heating_dx_multi_speed.containingHVACComponent.get
      heat_pump_comp = containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
      ccoil = heat_pump_comp.coolingCoil
      dxcoil = ccoil.to_CoilCoolingDXMultiSpeed.get
      dxcoil_name = dxcoil.name.to_s
      if sql_db_vars_map
        if sql_db_vars_map[dxcoil_name]
          dxcoil.setName(sql_db_vars_map[dxcoil_name])
        end
      end
      clg_stages = dxcoil.stages
      if clg_stages.last.grossRatedTotalCoolingCapacity.is_initialized
        clg_capacity = clg_stages.last.grossRatedTotalCoolingCapacity.get
      elsif dxcoil.autosizedSpeed4GrossRatedTotalCoolingCapacity.is_initialized
        clg_capacity = dxcoil.autosizedSpeed4GrossRatedTotalCoolingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name} capacity is not available, cannot apply efficiency standard.")
        successfully_set_all_properties = false
        return successfully_set_all_properties
      end
      dxcoil.setName(dxcoil_name)
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(clg_capacity, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(clg_capacity, 'W', 'kBtu/hr').get

    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    hp_props = model_find_object(standards_data['heat_pumps'], search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if hp_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultipeed', "For #{coil_heating_dx_multi_speed.name}, cannot find efficiency info using #{search_criteria}, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the HEAT-CAP-FT curve
    htg_stages = stages
    heat_cap_ft = model_add_curve(model, hp_props['heat_cap_ft'], standards)
    if heat_cap_ft
      htg_stages.each do |istage|
        istage.setHeatingCapacityFunctionofTemperatureCurve(heat_cap_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name}, cannot find heat_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-CAP-FFLOW curve
    heat_cap_fflow = model_add_curve(model, hp_props['heat_cap_fflow'], standards)
    if heat_cap_fflow
      htg_stages.each do |istage|
        istage.setHeatingCapacityFunctionofFlowFractionCurve(heat_cap_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name}, cannot find heat_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FT curve
    heat_eir_ft = model_add_curve(model, hp_props['heat_eir_ft'], standards)
    if heat_eir_ft
      htg_stages.each do |istage|
        istage.setEnergyInputRatioFunctionofTemperatureCurve(heat_eir_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name}, cannot find heat_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-EIR-FFLOW curve
    heat_eir_fflow = model_add_curve(model, hp_props['heat_eir_fflow'], standards)
    if heat_eir_fflow
      htg_stages.each do |istage|
        istage.setEnergyInputRatioFunctionofFlowFractionCurve(heat_eir_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name}, cannot find heat_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the HEAT-PLF-FPLR curve
    heat_plf_fplr = model_add_curve(model, hp_props['heat_plf_fplr'], standards)
    if heat_plf_fplr
      htg_stages.each do |istage|
        istage.setPartLoadFractionCorrelationCurve(heat_plf_fplr)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name}, cannot find heat_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    htg_capacity = nil
    flow_rate4 = nil
    htg_stages = coil_heating_dx_multi_speed.stages
    if htg_stages.last.grossRatedHeatingCapacity.is_initialized
      htg_capacity = htg_stages.last.grossRatedHeatingCapacity.get
    elsif coil_heating_dx_multi_speed.autosizedSpeed4GrossRatedHeatingCapacity.is_initialized
      htg_capacity = coil_heating_dx_multi_speed.autosizedSpeed4GrossRatedHeatingCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name} capacity is not available, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end
    if htg_stages.last.ratedAirFlowRate.is_initialized
      flow_rate4 = htg_stages.last.ratedAirFlowRate.get
    elsif coil_heating_dx_multi_speed.autosizedSpeed4RatedAirFlowRate.is_initialized
      flow_rate4 = coil_heating_dx_multi_speed.autosizedSpeed4RatedAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{coil_heating_dx_multi_speed.name} capacity is not available, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(htg_capacity, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(htg_capacity, 'W', 'kBtu/hr').get

    # Get the minimum efficiency standards
    cop = nil

    # If specified as SEER
    unless hp_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = hp_props['minimum_seasonal_energy_efficiency_ratio']
      cop = seer_to_cop_cooling_no_fan(min_seer)
      coil_heating_dx_multi_speed.setName("#{coil_heating_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{template}: #{coil_heating_dx_multi_speed.name}: #{suppl_heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless hp_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = hp_props['minimum_energy_efficiency_ratio']
      cop = eer_to_cop(min_eer)
      coil_heating_dx_multi_speed.setName("#{coil_heating_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingDXMultiSpeed', "For #{template}: #{coil_heating_dx_multi_speed.name}:  #{suppl_heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Set the efficiency values
    return false if cop.nil?

    htg_stages.each do |istage|
      istage.setGrossRatedHeatingCOP(cop)
    end
    return true
  end
end
