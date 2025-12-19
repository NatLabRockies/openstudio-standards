class Standard
  # @!group ChillerElectricEIR

  # Finds the search criteria
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @return [Hash] has for search criteria to be used for find object
  def chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    search_criteria = {}
    search_criteria['template'] = template

    # Determine if WaterCooled or AirCooled by
    # checking if the chiller is connected to a condenser
    # water loop or not.  Use name as fallback for exporting HVAC library.
    cooling_type = chiller_electric_eir.condenserType

    search_criteria['cooling_type'] = cooling_type

    # @todo Standards replace this with a mechanism to store this
    # data in the chiller object itself.
    # For now, retrieve the condenser type from the name
    name = chiller_electric_eir.name.get
    condenser_type = nil
    compressor_type = nil
    absorption_type = nil
    if cooling_type == 'AirCooled'
      if name.include?('WithCondenser')
        condenser_type = 'WithCondenser'
      elsif name.include?('WithoutCondenser')
        condenser_type = 'WithoutCondenser'
      else
        # default to 'WithCondenser' if not an absorption chiller
        condenser_type = 'WithCondenser' if absorption_type.nil?
      end
    elsif cooling_type == 'WaterCooled'
      # use the chiller additional properties compressor type if defined
      if chiller_electric_eir.additionalProperties.hasFeature('compressor_type')
        compressor_type = chiller_electric_eir.additionalProperties.getFeatureAsString('compressor_type').get
      else
        # try to lookup by chiller name
        if name.include?('Reciprocating')
          compressor_type = 'Reciprocating'
        elsif name.include?('Rotary Screw')
          compressor_type = 'Rotary Screw'
        elsif name.include?('Scroll')
          compressor_type = 'Scroll'
        elsif name.include?('Centrifugal')
          compressor_type = 'Centrifugal'
        end
      end
    end
    unless condenser_type.nil?
      search_criteria['condenser_type'] = condenser_type
    end
    unless compressor_type.nil?
      search_criteria['compressor_type'] = compressor_type
    end

    # @todo Find out what compliance path is desired
    # perhaps this could be set using additional
    # properties when the chiller is created
    # Assume path a by default for now
    search_criteria['compliance_path'] = 'Path A'

    return search_criteria
  end

  # Finds lookup object in standards and return full load efficiency
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @return [Double] full load efficiency (COP)
  def chiller_electric_eir_standard_minimum_full_load_efficiency(chiller_electric_eir)
    # Get the chiller properties
    search_criteria = chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)
    return nil unless capacity_w

    capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get
    chlr_props = model_find_object(standards_data['chillers'], search_criteria, capacity_tons, Date.today)

    if chlr_props.nil?
      search_criteria.delete('compliance_path')
      chlr_props = model_find_object(standards_data['chillers'], search_criteria, capacity_tons, Date.today)
    end
    if chlr_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency.")
      return nil
    else
      cop = nil
      if !chlr_props['minimum_coefficient_of_performance'].nil?
        cop = chlr_props['minimum_coefficient_of_performance']
      elsif !chlr_props['minimum_energy_efficiency_ratio'].nil?
        cop = OpenstudioStandards::HVAC.eer_to_cop(chlr_props['minimum_energy_efficiency_ratio'])
      elsif !chlr_props['minimum_kilowatts_per_tons'].nil?
        cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(chlr_props['minimum_kilowatts_per_tons'])
      end
      if cop.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency.")
        return nil
      end
    end

    return cop
  end

  # Get applicable performance curve for capacity as a function of temperature
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param compressor_type [String] compressor type
  # @param cooling_type [String] cooling type ('AirCooled' or 'WaterCooled')
  # @param chiller_tonnage [Double] chiller capacity in ton
  # @return [String] name of applicable cuvre, nil if not found
  # @todo the current assingment is meant to replicate what was in the data, it probably needs to be reviewed
  def chiller_electric_eir_get_cap_f_t_curve_name(chiller_electric_eir, compressor_type, cooling_type, chiller_tonnage, compliance_path)
    curve_name = nil
    case cooling_type
    when 'AirCooled'
      curve_name = 'AirCooled_Chiller_2010_PathA_CAPFT'
    when 'WaterCooled'
      case compressor_type
      when 'Centrifugal'
        if chiller_tonnage >= 150
          curve_name = 'WaterCooled_Centrifugal_Chiller_GT150_2004_CAPFT'
        else
          curve_name = 'WaterCooled_Centrifugal_Chiller_LT150_2004_CAPFT'
        end
      when 'Reciprocating', 'Rotary Screw', 'Scroll'
        curve_name = 'ChlrWtrPosDispPathAAllQRatio_fTchwsTcwsSI'
      end
    end
    return curve_name
  end

  # Get applicable performance curve for EIR as a function of temperature
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param compressor_type [String] compressor type
  # @param cooling_type [String] cooling type ('AirCooled' or 'WaterCooled')
  # @param chiller_tonnage [Double] chiller capacity in ton
  # @return [String] name of applicable cuvre, nil if not found
  # @todo the current assingment is meant to replicate what was in the data, it probably needs to be reviewed
  def chiller_electric_eir_get_eir_f_t_curve_name(chiller_electric_eir, compressor_type, cooling_type, chiller_tonnage, compliance_path)
    case cooling_type
    when 'AirCooled'
      return 'AirCooled_Chiller_2010_PathA_EIRFT'
    when 'WaterCooled'
      case compressor_type
      when 'Centrifugal'
        return 'WaterCooled_Centrifugal_Chiller_GT150_2004_EIRFT' if chiller_tonnage >= 150

        return 'WaterCooled_Centrifugal_Chiller_LT150_2004_EIRFT'
      when 'Reciprocating', 'Rotary Screw', 'Scroll'
        return 'ChlrWtrPosDispPathAAllEIRRatio_fTchwsTcwsSI'
      else
        return nil
      end
    else
      return nil
    end
  end

  # Get applicable performance curve for EIR as a function of part load ratio
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param compressor_type [String] compressor type
  # @param cooling_type [String] cooling type ('AirCooled' or 'WaterCooled')
  # @param chiller_tonnage [Double] chiller capacity in ton
  # @return [String] name of applicable cuvre, nil if not found
  # @todo the current assingment is meant to replicate what was in the data, it probably needs to be reviewed
  def chiller_electric_eir_get_eir_f_plr_curve_name(chiller_electric_eir, compressor_type, cooling_type, chiller_tonnage, compliance_path)
    case cooling_type
    when 'AirCooled'
      return 'AirCooled_Chiller_AllCapacities_2004_2010_EIRFPLR'
    when 'WaterCooled'
      case compressor_type
      when 'Centrifugal', 'Reciprocating', 'Rotary Screw', 'Scroll'
        return 'ChlrWtrCentPathAAllEIRRatio_fQRatio'
      else
        return nil
      end
    else
      return nil
    end
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
  # @param clg_tower_objs [Array] cooling towers, currently unused
  # @return [Boolean] returns true if successful, false if not
  # @todo remove clg_tower_objs parameter if unused
  def chiller_electric_eir_apply_efficiency_and_curves(chiller_electric_eir, clg_tower_objs)
    chillers = standards_data['chillers']

    # Define the criteria to find the chiller properties
    # in the hvac standards data set.
    search_criteria = chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    cooling_type = search_criteria['cooling_type']
    condenser_type = search_criteria['condenser_type']
    compressor_type = search_criteria['compressor_type']
    compliance_path = search_criteria['compliance_path']

    # Get the chiller capacity
    capacity_w = OpenstudioStandards::HVAC.chiller_electric_get_capacity(chiller_electric_eir)

    # Convert capacity to tons
    capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get

    # Get the chiller properties
    chlr_props = model_find_object(chillers, search_criteria, capacity_tons, Date.today)
    cop = nil
    if chlr_props.nil?
      search_criteria.delete('compliance_path')
      compliance_path = nil
      chlr_props = model_find_object(standards_data['chillers'], search_criteria, capacity_tons, Date.today)
    end
    if chlr_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller properties using #{search_criteria}, cannot apply standard efficiencies or curves.")
      return false
    else
      if !chlr_props['minimum_coefficient_of_performance'].nil?
        cop = chlr_props['minimum_coefficient_of_performance']
      elsif !chlr_props['minimum_energy_efficiency_ratio'].nil?
        cop = OpenstudioStandards::HVAC.eer_to_cop(chlr_props['minimum_energy_efficiency_ratio'])
      elsif !chlr_props['minimum_kilowatts_per_tons'].nil?
        cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(chlr_props['minimum_kilowatts_per_tons'])
      end
      if cop.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency.")
        return false
      end
    end

    # Make the CAPFT curve
    cool_cap_f_t_name = chiller_electric_eir_get_cap_f_t_curve_name(chiller_electric_eir, compressor_type, cooling_type, capacity_tons, compliance_path)
    if cool_cap_f_t_name.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find performance curve describing the capacity of the chiller as a function of temperature, will not be set.")
      successfully_set_all_properties = false
    else
      cool_cap_f_t = model_add_curve(chiller_electric_eir.model, cool_cap_f_t_name)
      if cool_cap_f_t
        chiller_electric_eir.setCoolingCapacityFunctionOfTemperature(cool_cap_f_t)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, the performance curve describing the capacity of the chiller as a function of temperature could not be found.")
        successfully_set_all_properties = false
      end
    end

    # Make the EIRFT curve
    cool_eir_f_t_name = chiller_electric_eir_get_eir_f_t_curve_name(chiller_electric_eir, compressor_type, cooling_type, capacity_tons, compliance_path)
    if cool_eir_f_t_name.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find performance curve describing the EIR of the chiller as a function of temperature, will not be set.")
      successfully_set_all_properties = false
    else
      cool_eir_f_t = model_add_curve(chiller_electric_eir.model, cool_eir_f_t_name)
      if cool_eir_f_t
        chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfTemperature(cool_eir_f_t)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, the performance curve describing the EIR of the chiller as a function of temperature could not be found.")
        successfully_set_all_properties = false
      end
    end

    # Make the EIRFPLR curve
    cool_eir_f_plr_name = chiller_electric_eir_get_eir_f_plr_curve_name(chiller_electric_eir, compressor_type, cooling_type, capacity_tons, compliance_path)
    if cool_eir_f_plr_name.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find performance curve describing the EIR of the chiller as a function of part load ratio, will not be set.")
      successfully_set_all_properties = false
    else
      cool_plf_f_plr = model_add_curve(chiller_electric_eir.model, cool_eir_f_plr_name)
      if cool_plf_f_plr
        chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfPLR(cool_plf_f_plr)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, the performance curve describing the EIR of the chiller as a function of part load ratio could not be found.")
        successfully_set_all_properties = false
      end
    end

    # Set the efficiency value
    if cop.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency, will not be set.")
      successfully_set_all_properties = false
    else
      chiller_electric_eir.setReferenceCOP(cop)
      kw_per_ton = OpenstudioStandards::HVAC.cop_to_kw_per_ton(cop)
    end

    # Append the name with size and kw/ton
    chiller_electric_eir.setName("#{chiller_electric_eir.name} #{capacity_tons.round}tons #{kw_per_ton.round(3)}kW/ton")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ChillerElectricEIR', "For #{template}: #{chiller_electric_eir.name}: #{cooling_type} #{condenser_type} #{compressor_type} Capacity = #{capacity_tons.round}tons; COP = #{cop.round(1)} (#{kw_per_ton.round(3)}kW/ton)")

    return successfully_set_all_properties
  end
end
