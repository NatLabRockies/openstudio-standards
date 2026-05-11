module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects


    # Return the capacity in W of a CoilHeatingGasMultiStage
    #
    # @param coil_heating_gas_multi_stage [OpenStudio::Model::CoilHeatingGasMultiStage] coil heating gas multi stage object
    # @return [Double] capacity in W
    def self.coil_heating_gas_multi_stage_get_capacity(coil_heating_gas_multi_stage)
      capacity_w = nil
      htg_stages = coil_heating_gas_multi_stage.stages
      if htg_stages.last.nominalCapacity.is_initialized
        capacity_w = htg_stages.last.nominalCapacity.get
      elsif (htg_stages.size == 1) && coil_heating_gas_multi_stage.stages[0].autosizedNominalCapacity.is_initialized
        capacity_w = coil_heating_gas_multi_stage.stages[0].autosizedNominalCapacity.get
      elsif (htg_stages.size == 2) && coil_heating_gas_multi_stage.stages[1].autosizedNominalCapacity.is_initialized
        capacity_w = coil_heating_gas_multi_stage.stages[1].autosizedNominalCapacity.get
      elsif (htg_stages.size == 3) && coil_heating_gas_multi_stage.stages[2].autosizedNominalCapacity.is_initialized
        capacity_w = coil_heating_gas_multi_stage.stages[2].autosizedNominalCapacity.get
      elsif (htg_stages.size == 4) && coil_heating_gas_multi_stage.stages[3].autosizedNominalCapacity.is_initialized
        capacity_w = coil_heating_gas_multi_stage.stages[3].autosizedNominalCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_heating_gas_multistage', "For #{coil_heating_gas_multi_stage.name} capacity is not available.")
        return capacity_w
      end

      return capacity_w
    end
  end
end
