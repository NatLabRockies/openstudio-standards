# A variety of DX coil methods that are the same regardless of coil type.
# These methods are available to:
# CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
module CoilDX
  # @!group CoilDX

  # Finds the search criteria
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @param necb_ref_hp [Boolean] for compatability with NECB ruleset only.
  # @param equipment_type [Boolean] indicate that equipment_type should be in the search criteria.
  # @return [Hash] has for search criteria to be used for find object
  def coil_dx_find_search_criteria(coil_dx, necb_ref_hp = false, equipment_type = false)
    search_criteria = {}
    search_criteria['template'] = template

    # Cooling type
    search_criteria['cooling_type'] = case coil_dx.iddObjectType.valueName.to_s
                                      when 'OS_Coil_Cooling_DX_SingleSpeed',
                                           'OS_Coil_Cooling_DX_TwoSpeed',
                                           'OS_Coil_Cooling_DX_VariableSpeed',
                                           'OS_Coil_Cooling_DX_MultiSpeed',
                                           'OS_AirConditioner_VariableRefrigerantFlow'
                                        coil_dx.condenserType
                                      else
                                        'AirCooled'
                                      end

    # Get the coil subcategory
    search_criteria['subcategory'] = OpenstudioStandards::HVAC.coil_dx_subcategory(coil_dx)

    # Add the heating type to the search criteria
    htg_type = OpenstudioStandards::HVAC.coil_dx_heating_type(coil_dx)
    unless htg_type.nil?
      search_criteria['heating_type'] = htg_type
    end

    # The heating side of unitary heat pumps don't have a heating type as part of the search
    if coil_dx.to_CoilHeatingDXSingleSpeed.is_initialized &&
      OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_dx) &&
       coil_dx.airLoopHVAC.empty? && coil_dx.containingHVACComponent.is_initialized
      containing_comp = coil_dx.containingHVACComponent.get
      if containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
        search_criteria['heating_type'] = nil
      end
      # @todo Add other unitary systems
    end

    # Get the equipment type
    if equipment_type && coil_dx.airLoopHVAC.empty? && coil_dx.containingZoneHVACComponent.is_initialized
      containing_comp = coil_dx.containingZoneHVACComponent.get
      # PTAC
      if containing_comp.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
        search_criteria['equipment_type'] = 'PTAC'
        search_criteria['subcategory'] = nil
        unless (template == 'NECB2011') || (template == 'NECB2015') || (template == 'NECB2017') || (template == 'NECB2020') || (template == 'BTAPPRE1980') ||
               (template == 'BTAP1980TO2010')
          search_criteria['heating_type'] = nil
        end
      end
      # PTHP
      if containing_comp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized && !((template == 'NECB2011') || (template == 'NECB2015') || (template == 'NECB2017') || (template == 'NECB2020') || (template == 'BTAPPRE1980') ||
               (template == 'BTAP1980TO2010'))
        search_criteria['subcategory'] = nil
        search_criteria['heating_type'] = nil
        search_criteria['equipment_type'] = 'PTHP'
      end
    end

    return search_criteria
  end

  # Determine what application to use for looking up the minimum efficiency requirements of PTACs
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @return [String] PTAC application
  def coil_dx_packaged_terminal_application(coil_dx)
    if template.include?('90.1-2004') || template.include?('90.1-2007')
      return 'New Construction'
    else # '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019', others
      return 'Standard Size'
    end
  end

  # Determine what electric power phase value should be used for efficiency lookups for DX coils
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @return [String] Electric power phase
  def coil_dx_electric_power_phase(coil_dx)
    case template
    when '90.1-2019', '90.1-2016'
      return 3
    else
      return nil
    end
  end

  # Determine what capacity curve to use to represent the change of the coil's capacity as a function of changes in temperatures
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @param equipment_type [String] Type of equipment
  # @param heating [Boolean] Specify if the curve to return is for heating operation
  # @return [String] Curve name
  def coil_dx_cap_ft(coil_dx, equipment_type = 'Air Conditioners', heating = false)
    case equipment_type
    when 'PTAC'
      return 'PSZ-Fine Storage DX Coil Cap-FT'
    when 'PSZ-AC', 'Air Conditioners'
      return 'CoilClgDXQRatio_fTwbToadbSI'
    when 'PTHP'
      return 'DXHEAT-NECB2011-REF-CAPFT'
    when 'PSZ-HP', 'Heat Pumps'
      return 'HPACHeatCapFT' if heating

      return 'HPACCoolCapFT'
    else
      return 'CoilClgDXQRatio_fTwbToadbSI'
    end
  end

  # Determine what capacity curve to use to represent the change of the coil's capacity as a function of changes in airflow fraction
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @param equipment_type [String] Type of equipment
  # @param heating [Boolean] Specify if the curve to return is for heating operation
  # @return [String] Curve name
  def coil_dx_cap_fflow(coil_dx, equipment_type = 'Air Conditioners', heating = false)
    case equipment_type
    when 'PTAC'
      return 'DX Coil Cap-FF'
    when 'PSZ-AC', 'Air Conditioners'
      return 'CoilClgDXSnglQRatio_fCFMRatio'
    when 'PTHP'
      return 'DXHEAT-NECB2011-REF-CAPFFLOW'
    when 'PSZ-HP', 'Heat Pumps'
      return 'HPACHeatCapFFF' if heating

      return 'HPACCoolCapFFF'
    else
      return 'CoilClgDXSnglQRatio_fCFMRatio'
    end
  end

  # Determine what EIR curve to use to represent the change of the coil's EIR as a function of changes in temperatures
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @param equipment_type [String] Type of equipment
  # @param heating [Boolean] Specify if the curve to return is for heating operation
  # @return [String] Curve name
  def coil_dx_eir_ft(coil_dx, equipment_type = 'Air Conditioners', heating = false)
    case equipment_type
    when 'PTAC'
      return 'PSZ-AC DX Coil EIR-FT'
    when 'PSZ-AC', 'Air Conditioners'
      return 'CoilClgDXEIRRatio_fTwbToadbSI'
    when 'PTHP'
      return 'DXHEAT-NECB2011-REF-EIRFT'
    when 'PSZ-HP', 'Heat Pumps'
      return 'HPACHeatEIRFT' if heating

      return 'HPACCoolEIRFT'
    else
      return 'CoilClgDXEIRRatio_fTwbToadbSI'
    end
  end

  # Determine what EIR curve to use to represent the change of the coil's EIR as a function of changes in airflow fraction
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @param equipment_type [String] Type of equipment
  # @param heating [Boolean] Specify if the curve to return is for heating operation
  # @return [String] Curve name
  def coil_dx_eir_fflow(coil_dx, equipment_type = 'Air Conditioners', heating = false)
    case equipment_type
    when 'PTAC'
      return 'Split DX Coil EIR-FF'
    when 'PSZ-AC', 'Air Conditioners'
      return 'CoilClgDXSnglEIRRatio_fCFMRatio'
    when 'PTHP'
      return 'DXHEAT-NECB2011-REF-EIRFFLOW'
    when 'PSZ-HP', 'Heat Pumps'
      return 'HPACHeatEIRFFF' if heating

      return 'HPACCoolEIRFFF'
    else
      return 'CoilClgDXSnglEIRRatio_fCFMRatio'
    end
  end

  # Determine what PLF curve to use to represent the change of the coil's PLR as a function of changes in PLR
  #
  # @param coil_dx [OpenStudio::Model::StraightComponent] coil cooling object, allowable types:
  #   CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed
  # @param equipment_type [String] Type of equipment
  # @param heating [Boolean] Specify if the curve to return is for heating operation
  # @return [String] Curve name
  def coil_dx_plf_fplr(coil_dx, equipment_type = 'Air Conditioners', heating = false)
    case equipment_type
    when 'PTAC'
      return 'HPACCOOLPLFFPLR'
    when 'PSZ-AC', 'Air Conditioners'
      return 'CoilClgDXEIRRatio_fQFrac'
    when 'PTHP'
      return 'DXHEAT-NECB2011-REF-PLFFPLR'
    when 'PSZ-HP', 'Heat Pumps'
      return 'HPACCOOLPLFFPLR'
    else
      return 'CoilClgDXEIRRatio_fQFrac'
    end
  end
end
