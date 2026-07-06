module OpenstudioStandards
  # The Ventilation module provides methods to create, modify, and get information about outdoor air ventilation
  module Ventilation
    # @!group Create Typical Ventilation
    # Methods to create typical ventilation

    # Create typical outdoor air ventilation objects in a model.
    # Creates a DesignSpecificationOutdoorAir object for each space type based on the
    # 'ventilation_space_type' additional property, with rates from ventilation space
    # type data derived from ASHRAE 62.1 (ASHRAE 170 for health care space types).
    # Every space type receives a design specification outdoor air object, even if the
    # rates are all zero, so that ventilation controls work correctly.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Array<OpenStudio::Model::DesignSpecificationOutdoorAir>] Array of OpenStudio DesignSpecificationOutdoorAir objects
    def self.create_typical_ventilation(model)
      design_specification_outdoor_airs = []

      # load ventilation space types data
      ventilation_space_type_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/ventilation_space_types.json"), symbolize_names: true)
      if ventilation_space_type_data.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', 'Unable to load ventilation space types data. No ventilation will be added to model.')
        return design_specification_outdoor_airs
      end

      # loop over space types and apply ventilation
      model.getSpaceTypes.each do |space_type|
        # get ventilation space type from the object
        has_ventilation_space_type = space_type.additionalProperties.hasFeature('ventilation_space_type')
        unless has_ventilation_space_type
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Space type '#{space_type.name}' does not have a ventilation_space_type property assigned. Ignoring space type.")
          next
        end
        ventilation_space_type = space_type.additionalProperties.getFeatureAsString('ventilation_space_type').to_s

        if ventilation_space_type == 'na'
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Ventilation', "Space type '#{space_type.name}' has ventilation_space_type 'na'. Ignoring space type.")
          next
        end

        # get ventilation properties for the ventilation space type
        ventilation_space_type_properties = ventilation_space_type_data.find { |r| r[:ventilation_space_type_name] == ventilation_space_type }
        if ventilation_space_type_properties.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Unable to find ventilation space type data for '#{ventilation_space_type}'. Ignoring space type #{space_type.name}.")
          next
        end

        ventilation_per_person = ventilation_space_type_properties[:ventilation_per_person].to_f
        ventilation_per_area = ventilation_space_type_properties[:ventilation_per_area].to_f
        ventilation_ach = ventilation_space_type_properties[:ventilation_air_changes].to_f
        ventilation_standard = ventilation_space_type_properties[:ventilation_standard].to_s

        # get the design specification outdoor air or create a new one if none exists
        ventilation = space_type.designSpecificationOutdoorAir
        if ventilation.is_initialized
          ventilation = ventilation.get
        else
          ventilation = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
          ventilation.setName("#{space_type.name} Ventilation")
          space_type.setDesignSpecificationOutdoorAir(ventilation)
        end

        # set the ventilation rates. Rates not present in the data are set to zero so that
        # a previously assigned design specification outdoor air object is fully overwritten.
        ventilation.setOutdoorAirMethod('Sum')
        ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(ventilation_per_person, 'ft^3/min*person', 'm^3/s*person').get)
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(ventilation_per_area, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        ventilation.setOutdoorAirFlowAirChangesperHour(ventilation_ach)
        ventilation.additionalProperties.setFeature('ventilation_space_type', ventilation_space_type)
        ventilation.additionalProperties.setFeature('ventilation_standard', ventilation_standard)
        design_specification_outdoor_airs << ventilation

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Ventilation', "Setting space type '#{space_type.name}' with ventilation space type '#{ventilation_space_type}' to #{ventilation_per_person} cfm/person, #{ventilation_per_area} cfm/ft^2, #{ventilation_ach} ACH per #{ventilation_standard}.")
      end

      return design_specification_outdoor_airs
    end
  end
end
