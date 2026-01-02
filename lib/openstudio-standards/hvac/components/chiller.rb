module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Chiller
    # Methods to create, modify, and get information about chillers

    # Return the capacity in W of a ChillerElectricEIR
    #
    # @param chiller_electric_eir [OpenStudio::Model::ChillerElectricEIR] chiller object
    # @return [Double] capacity in W
    def self.chiller_electric_get_capacity(chiller_electric_eir)
      capacity_w = nil
      if chiller_electric_eir.referenceCapacity.is_initialized
        capacity_w = chiller_electric_eir.referenceCapacity.get
      elsif chiller_electric_eir.autosizedReferenceCapacity.is_initialized
        capacity_w = chiller_electric_eir.autosizedReferenceCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.chiller', "For #{chiller_electric_eir.name} capacity is not available.")
        return capacity_w
      end

      return capacity_w
    end
  end
end
