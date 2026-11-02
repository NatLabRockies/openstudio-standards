module OpenstudioStandards
  # The SpaceType module provides methods to modify, get, and set information about model space types
  module SpaceType
    # @!group SpaceType

    # Resolve catalog properties, preferring a building-qualified subtype over the base name.
    #
    # @param space_types_data [Array<Hash>] parsed space_types.json data with symbol keys
    # @param space_type_name [String] standards space type name from the model
    # @param space_type [OpenStudio::Model::SpaceType] space type being resolved
    # @return [Hash, nil] matching properties, or nil when the name is unknown
    def self.resolve_space_type_properties(space_types_data, space_type_name, space_type)
      if space_type.standardsBuildingType.is_initialized
        building_type = space_type.standardsBuildingType.get.to_s
        suffix = building_type.gsub(/([a-z\d])([A-Z])/, '\1 \2').downcase
        qualified = space_types_data.find { |s| s[:space_type_name] == "#{space_type_name} - #{suffix}" }
        return qualified unless qualified.nil?
      end

      space_types_data.find { |s| s[:space_type_name] == space_type_name }
    end

    # Assign standards space type additional properties to all space types in the model.
    # Base space types and detailed subtypes share the space_types.json catalog.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param space_type_field [String] where the standards space type is stored, either 'StandardsSpaceType' or 'AdditionalProperties'
    # @param reset_standards_space_type [Boolean] if true, resets the Standards Space Type to match the new space type names
    # @return [Boolean] returns true if successful, false if not
    def self.set_standards_space_type_additional_properties(model, space_type_field: 'StandardsSpaceType', reset_standards_space_type: false)
      # load space types data
      space_types_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/space_types.json"), symbolize_names: true)

      # set additional properties for each space type
      model.getSpaceTypes.each do |space_type|
        if space_type_field == 'StandardsSpaceType'
          if space_type.standardsSpaceType.is_initialized
            space_type_name = space_type.standardsSpaceType.get
            space_type.additionalProperties.setFeature('standards_space_type', space_type_name)
          end
        elsif space_type_field == 'AdditionalProperties'
          if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
            space_type_name = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
            space_type.setStandardsSpaceType(space_type_name) if reset_standards_space_type
          end
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SpaceType', "space_type_field must be either 'StandardsSpaceType' or 'AdditionalProperties'")
          return false
        end

        space_type_properties = OpenstudioStandards::SpaceType.resolve_space_type_properties(space_types_data, space_type_name, space_type)
        if space_type_properties.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', "No space type properties found for space type #{space_type.name} with standards space type '#{space_type_name}' in building #{model.getBuilding.name}")
        else
          lighting_space_type_name = space_type_properties[:lighting_space_type_name].nil? ? 'na' : space_type_properties[:lighting_space_type_name]
          space_type.additionalProperties.setFeature('lighting_space_type', lighting_space_type_name)
          electric_equipment_space_type_name = space_type_properties[:electric_equipment_space_type_name].nil? ? 'na' : space_type_properties[:electric_equipment_space_type_name]
          space_type.additionalProperties.setFeature('electric_equipment_space_type', electric_equipment_space_type_name)
          natural_gas_equipment_space_type_name = space_type_properties[:natural_gas_equipment_space_type_name].nil? ? 'na' : space_type_properties[:natural_gas_equipment_space_type_name]
          space_type.additionalProperties.setFeature('natural_gas_equipment_space_type', natural_gas_equipment_space_type_name)
          refrigeration_space_type_name = space_type_properties[:refrigeration_space_type_name].nil? ? 'na' : space_type_properties[:refrigeration_space_type_name]
          space_type.additionalProperties.setFeature('refrigeration_space_type', refrigeration_space_type_name)
          service_water_space_type_name = space_type_properties[:service_water_space_type_name].nil? ? 'na' : space_type_properties[:service_water_space_type_name]
          space_type.additionalProperties.setFeature('service_water_space_type', service_water_space_type_name)
          ventilation_space_type_name = space_type_properties[:ventilation_space_type_name].nil? ? 'na' : space_type_properties[:ventilation_space_type_name]
          space_type.additionalProperties.setFeature('ventilation_space_type', ventilation_space_type_name)
          schedule_set_name = space_type_properties[:schedule_set_name].nil? ? 'na' : space_type_properties[:schedule_set_name]
          space_type.additionalProperties.setFeature('schedule_set', schedule_set_name)
          space_type.additionalProperties.setFeature('critical_operation', space_type_properties[:critical_operation] == true)
        end
      end

      return true
    end

    # Whether a space type requires continuous system operation regardless of occupancy.
    # A stamped additional property takes precedence over the catalog.
    #
    # @param space_type [OpenStudio::Model::SpaceType] space type to check
    # @return [Boolean] true when the property or catalog flags critical operation
    def self.space_type_critical_operation?(space_type)
      stamped = space_type.additionalProperties.getFeatureAsBoolean('critical_operation')
      return stamped.get if stamped.is_initialized

      name = space_type.additionalProperties.getFeatureAsString('standards_space_type')
      name = space_type.standardsSpaceType if name.empty?
      return false if name.empty?

      @space_types_data ||= JSON.parse(File.read("#{File.dirname(__FILE__)}/data/space_types.json"), symbolize_names: true)
      record = OpenstudioStandards::SpaceType.resolve_space_type_properties(@space_types_data, name.get, space_type)
      !record.nil? && record[:critical_operation] == true
    end
  end
end
