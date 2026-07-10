module OpenstudioStandards
  # The Ventilation module provides methods to create, modify, and get information about outdoor air ventilation
  module Ventilation
    # @!group Create Typical Ventilation
    # Methods to create typical ventilation

    # Create typical outdoor air ventilation objects in a model.
    # Creates a DesignSpecificationOutdoorAir object for each space type based on its
    # standards space type, which is expected to be a level-1 typical space type
    # (see lib/openstudio-standards/space_type/data/level_1_space_types.json).
    #
    # When a template is provided, ventilation rates default to the template (code version)
    # values from the standards space types data, resolved through the validated mapping of
    # level-1 space types to standards space types in
    # lib/openstudio-standards/space_type/data/level_1_standards_space_type_map.json.
    # Space types without a mapping for the template, and all space types when no template is
    # provided, fall back to the typical ventilation data in
    # lib/openstudio-standards/ventilation/data/ventilation_space_types.json, with rates
    # derived from ASHRAE 62.1 (ASHRAE 170 for health care space types), matched through the
    # 'ventilation_space_type' additional property.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param template [String] optional OpenStudio Standards template, e.g. '90.1-2013'.
    #   When provided, ventilation rates come from the standards space types data for this template.
    # @return [Array<OpenStudio::Model::DesignSpecificationOutdoorAir>] Array of OpenStudio DesignSpecificationOutdoorAir objects
    def self.create_typical_ventilation(model, template: nil)
      design_specification_outdoor_airs = []

      # load typical ventilation space types data (the fallback source)
      ventilation_space_type_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/ventilation_space_types.json"), symbolize_names: true)
      if ventilation_space_type_data.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', 'Unable to load ventilation space types data. No ventilation will be added to model.')
        return design_specification_outdoor_airs
      end

      # resolve the template to a Standard. The mapping of level-1 space types to standards
      # space types is keyed by base template labels, so e.g. 'ComStock 90.1-2013' resolves
      # through the '90.1-2013' rows while the rate lookup uses the ComStock standards data.
      standard = nil
      ventilation_method = 'Sum'
      unless template.nil?
        begin
          standard = Standard.build(template)
          ventilation_method = standard.model_ventilation_method(model)
        rescue RuntimeError
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "'#{template}' is not a recognized OpenStudio Standards template. Using the typical ventilation data for all space types.")
          standard = nil
        end
        if !standard.nil? && standard.standards_data['space_types'].nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Template '#{template}' has no standards space type data. Using the typical ventilation data for all space types.")
          standard = nil
        end
      end

      # loop over space types and apply ventilation
      model.getSpaceTypes.each do |space_type|
        # get the level-1 standards space type name
        level_1_space_type = nil
        if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
          level_1_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
        elsif space_type.standardsSpaceType.is_initialized
          level_1_space_type = space_type.standardsSpaceType.get
        end

        # template (code version) ventilation rates from the standards space types data
        ventilation_properties = nil
        source = nil
        unless standard.nil? || level_1_space_type.nil?
          map_row = OpenstudioStandards::SpaceType.level_1_standards_space_type_mapping(level_1_space_type, template)
          unless map_row.nil?
            search_criteria = { 'building_type' => map_row['building_type'], 'space_type' => map_row['space_type'] }
            standards_properties = standard.model_find_object(standard.standards_data['space_types'], search_criteria.merge('template' => template))
            standards_properties = standard.model_find_object(standard.standards_data['space_types'], search_criteria) if standards_properties.nil?
            if standards_properties.nil?
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Space type '#{space_type.name}' maps to '#{map_row['building_type']} | #{map_row['space_type']}', which was not found in the standards space type data for template '#{template}'. Using the typical ventilation data.")
            else
              ventilation_properties = {
                ventilation_per_person: standards_properties['ventilation_per_person'],
                ventilation_per_area: standards_properties['ventilation_per_area'],
                ventilation_air_changes: standards_properties['ventilation_air_changes'],
                ventilation_standard: standards_properties['ventilation_standard']
              }
              source = "#{template} #{map_row['building_type']} | #{map_row['space_type']}"
            end
          end
        end

        # fall back to the typical ventilation data, matched through the ventilation_space_type property
        if ventilation_properties.nil?
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

          typical_properties = ventilation_space_type_data.find { |r| r[:ventilation_space_type_name] == ventilation_space_type }
          if typical_properties.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Unable to find ventilation space type data for '#{ventilation_space_type}'. Ignoring space type #{space_type.name}.")
            next
          end
          unless standard.nil?
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Ventilation', "Space type '#{space_type.name}' has no standards space type mapping for template '#{template}'. Using the typical ventilation data.")
          end
          ventilation_properties = typical_properties
          source = ventilation_space_type
        end

        ventilation_per_person = ventilation_properties[:ventilation_per_person].to_f
        ventilation_per_area = ventilation_properties[:ventilation_per_area].to_f
        ventilation_ach = ventilation_properties[:ventilation_air_changes].to_f
        ventilation_standard = ventilation_properties[:ventilation_standard].to_s

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
        ventilation.setOutdoorAirMethod(ventilation_method)
        ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(ventilation_per_person, 'ft^3/min*person', 'm^3/s*person').get)
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(ventilation_per_area, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        ventilation.setOutdoorAirFlowAirChangesperHour(ventilation_ach)
        ventilation.additionalProperties.setFeature('ventilation_source', source)
        ventilation.additionalProperties.setFeature('ventilation_standard', ventilation_standard)
        design_specification_outdoor_airs << ventilation

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Ventilation', "Setting space type '#{space_type.name}' ventilation from '#{source}' to #{ventilation_per_person} cfm/person, #{ventilation_per_area} cfm/ft^2, #{ventilation_ach} ACH per #{ventilation_standard}.")
      end

      return design_specification_outdoor_airs
    end
  end
end
