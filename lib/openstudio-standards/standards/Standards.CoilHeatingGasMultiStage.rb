class Standard
  # @!group CoilHeatingGasMultiStage

  # find search criteria
  #
  # @param coil_heating_gas_multi_stage [OpenStudio::Model::CoilHeatingGasMultiStage] coil heating gas multi stage object
  # @return [Hash] used for model_find_object(model)
  def coil_heating_gas_multi_stage_find_search_criteria(coil_heating_gas_multi_stage)
    # Define the criteria to find the coil heating gas multi-stage properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template
    search_criteria['fuel_type'] = 'Gas'
    search_criteria['fluid_type'] = 'Air'

    return search_criteria
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_heating_gas_multi_stage [OpenStudio::Model::CoilHeatingGasMultiStage] coil heating gas multi stage object
  # @return [Boolean] returns true if successful, false if not
  def coil_heating_gas_multi_stage_apply_efficiency_and_curves(coil_heating_gas_multi_stage)
    successfully_set_all_properties = true

    # Get the coil capacity
    capacity_w = nil
    htg_stages = stages
    if htg_stages.last.nominalCapacity.is_initialized
      capacity_w = htg_stages.last.nominalCapacity.get
    elsif coil_heating_gas_multi_stage.autosizedStage4NominalCapacity.is_initialized
      capacity_w = coil_heating_gas_multi_stage.autosizedStage4NominalCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGasMultiStage', "For #{coil_heating_gas_multi_stage.name} capacity is not available, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # plf vs plr curve for furnace
    furnace_plffplr_curve = model_add_curve(model, furnace_plffplr_curve_name, standards)
    if furnace_plffplr_curve
      coil_heating_gas_multi_stage.setPartLoadFractionCorrelationCurve(furnace_plffplr_curve)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGasMultiStage', "For #{coil_heating_gas_multi_stage.name}, cannot find plffplr curve, will not be set.")
      successfully_set_all_properties = false
    end
  end
end
