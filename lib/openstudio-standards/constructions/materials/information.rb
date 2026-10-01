module OpenstudioStandards
  # The Constructions module provides methods create, modify, and get information about model Constructions
  module Constructions
    # The Materials module provides methods create, modify, and get information about Materials
    module Materials
      # @!group Information
      # Methods to get information about Materials

      # Return the thermal conductance for an OpenStudio Material object, a parent object to all kinds of materials
      #
      # @param material [OpenStudio::Model::Material] OpenStudio Material object
      # @param temperature [Double] Temperature in Celsius, used for gas or gas mixture thermal conductance
      # @return [Double] thermal conductance in W/m^2*K
      def self.material_get_conductance(material, temperature: 0.0)
        conductance = nil
        conductance = material.to_OpaqueMaterial.get.thermalConductance unless material.to_OpaqueMaterial.empty?

        # ShadingMaterial
        conductance = material.to_Shade.get.thermalConductance unless material.to_Shade.empty?
        conductance = material.to_Screen.get.thermalConductance unless material.to_Screen.empty?
        conductance = 9999.9 unless material.to_Blind.empty?

        # Glazing
        conductance = material.to_SimpleGlazing.get.uFactor unless material.to_SimpleGlazing.empty?
        conductance = material.to_StandardGlazing.get.thermalConductance unless material.to_StandardGlazing.empty?
        conductance = material.to_RefractionExtinctionGlazing.get.thermalConductance unless material.to_RefractionExtinctionGlazing.empty?

        # Gas
        # Convert C to K
        temperature_k = temperature + 273.0
        conductance = material.to_Gas.get.getThermalConductance(temperature_k) unless material.to_Gas.empty?
        conductance = material.to_GasMixture.get.getThermalConductance(temperature_k) unless material.to_GasMixture.empty?

        if conductance.nil?
          OpenStudio.logFree(OpenStudio::Error, 'OpenstudioStandards::Constructions::Materials', "Unable to determinte conductance for material #{material.name}.")
          return nil
        end

        return conductance
      end

      # @!endgroup Information
    end
  end
end
