module OpenstudioStandards
  # The SpaceType module provides methods to modify, get, and set information about model space types
  module SpaceType
    # @!group SpaceType

    # Assign standards space type additional properties to all space types in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param space_type_field [String] where the standards space type is stored, either 'StandardsSpaceType' or 'AdditionalProperties'
    # @param reset_standards_space_type [Boolean] if true, resets the Standards Space Type to match the new space type names
    # @return [Boolean] returns true if successful, false if not
    def self.set_standards_space_type_additional_properties(model, space_type_field: 'StandardsSpaceType', reset_standards_space_type: false)
      # load space types data
      space_types_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/level_1_space_types.json"), symbolize_names: true)

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

        space_type_properties = space_types_data.find { |s| s[:space_type_name] == space_type_name }
        if !space_type_properties.nil?
          lighting_space_type_name = space_type_properties[:lighting_space_type_name].nil? ? 'na' : space_type_properties[:lighting_space_type_name]
          space_type.additionalProperties.setFeature('lighting_space_type', lighting_space_type_name)
          electric_equipment_space_type_name = space_type_properties[:electric_equipment_space_type_name].nil? ? 'na' : space_type_properties[:electric_equipment_space_type_name]
          space_type.additionalProperties.setFeature('electric_equipment_space_type', electric_equipment_space_type_name)
          natural_gas_equipment_space_type_name = space_type_properties[:natural_gas_equipment_space_type_name].nil? ? 'na' : space_type_properties[:natural_gas_equipment_space_type_name]
          space_type.additionalProperties.setFeature('natural_gas_equipment_space_type', natural_gas_equipment_space_type_name)
          ventilation_space_type_name = space_type_properties[:ventilation_space_type_name].nil? ? 'na' : space_type_properties[:ventilation_space_type_name]
          space_type.additionalProperties.setFeature('ventilation_space_type', ventilation_space_type_name)
          schedule_set_name = space_type_properties[:schedule_set_name].nil? ? 'na' : space_type_properties[:schedule_set_name]
          space_type.additionalProperties.setFeature('schedule_set', schedule_set_name)
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', "No space type properties found for space type #{space_type.name} with standards space type '#{space_type_name}' in building #{model.getBuilding.name}")
        end
      end

      return true
    end
  end
end
