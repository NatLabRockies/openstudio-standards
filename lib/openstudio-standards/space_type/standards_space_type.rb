module OpenstudioStandards
  # The SpaceType module provides methods to modify, get, and set information about model space types
  module SpaceType
    # @!group SpaceType

    # Resolve a space type's properties, preferring a record qualified by the building type
    # it sits in.
    #
    # Some space types behave differently depending on the building around them: a school
    # corridor runs a school-year schedule, an office corridor does not. That axis lives in
    # the taxonomy as its own record - `corridor - primary school` alongside `corridor` - so
    # a building-type-qualified record wins when one exists and the plain name is the
    # fallback. Building types are CamelCase in the model and spaced-lowercase in the
    # taxonomy, matching how the rest of the space type names read.
    #
    # @param space_types_data [Array<Hash>] parsed all_level_space_types data
    # @param space_type_name [String] standards space type name from the model
    # @param space_type [OpenStudio::Model::SpaceType] the space type being resolved
    # @return [Hash, nil] the matching properties record, or nil when the name is unknown
    def self.resolve_space_type_properties(space_types_data, space_type_name, space_type)
      # NOTE: standardsBuildingType falls back to the Building-level value when the space
      # type does not set one, so this does not need to check whether it was set locally.
      if space_type.standardsBuildingType.is_initialized
        building_type = space_type.standardsBuildingType.get.to_s
        suffix = building_type.gsub(/([a-z\d])([A-Z])/, '\1 \2').downcase
        qualified = space_types_data.find { |s| s[:space_type_name] == "#{space_type_name} - #{suffix}" }
        return qualified unless qualified.nil?
      end

      space_types_data.find { |s| s[:space_type_name] == space_type_name }
    end

    # Assign standards space type additional properties to all space types in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param space_type_field [String] where the standards space type is stored, either 'StandardsSpaceType' or 'AdditionalProperties'
    # @param reset_standards_space_type [Boolean] if true, resets the Standards Space Type to match the new space type names
    # @return [Boolean] returns true if successful, false if not
    def self.set_standards_space_type_additional_properties(model, space_type_field: 'StandardsSpaceType', reset_standards_space_type: false)
      # load space types data
      space_types_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/all_level_space_types.json"), symbolize_names: true)

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
          ventilation_space_type_name = space_type_properties[:ventilation_space_type_name].nil? ? 'na' : space_type_properties[:ventilation_space_type_name]
          space_type.additionalProperties.setFeature('ventilation_space_type', ventilation_space_type_name)
          schedule_set_name = space_type_properties[:schedule_set_name].nil? ? 'na' : space_type_properties[:schedule_set_name]
          space_type.additionalProperties.setFeature('schedule_set', schedule_set_name)
          # stamped from the data so a runtime override can replace it in place, and so the
          # HVAC operation schedule derivation reads one property rather than the data
          space_type.additionalProperties.setFeature('critical_operation', space_type_properties[:critical_operation] == true)
        end
      end

      return true
    end

    # Whether a space type's systems run continuously regardless of occupancy.
    #
    # Patient rooms, operating rooms, recovery, emergency rooms, nurses stations and data
    # centers carry the flag in all_level_space_types.json; a spec states it for any space
    # type through the continuous_operation field of a thermostat_overrides entry. The
    # occupancy schedule derivation behind air loop and zone equipment operation returns
    # always-on for anything serving a flagged space type.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @return [Boolean] true when the space type is flagged, by override or by data
    def self.space_type_critical_operation?(space_type)
      stamped = space_type.additionalProperties.getFeatureAsBoolean('critical_operation')
      return stamped.get if stamped.is_initialized

      name = space_type.additionalProperties.getFeatureAsString('standards_space_type')
      name = space_type.standardsSpaceType if name.empty?
      return false if name.empty?

      @all_level_space_types_data ||= JSON.parse(File.read("#{File.dirname(__FILE__)}/data/all_level_space_types.json"), symbolize_names: true)
      record = OpenstudioStandards::SpaceType.resolve_space_type_properties(@all_level_space_types_data, name.get, space_type)
      !record.nil? && record[:critical_operation] == true
    end
  end
end
