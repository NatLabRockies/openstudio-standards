class Standard
  # Maps older prototype space types (Standards Building Type / Standards Space Type) to new standards space types
  # Optionally resets the Standards Space Type and new space type informational as additional properties on the space type
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param reset_standards_space_type [Boolean] if true, resets the Standards Space Type to new space types
  # @param set_additional_properties [Boolean] if true, sets additional properties on the space type with new space type information
  # @return [Boolean] returns true if successful, false if not
  def prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: true)
    # load space types mapping data
    space_types_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/prototype_space_type_map.json"), symbolize_names: true)

    # lookup space type name for each old Standards Space Type
    model.getSpaceTypes.each do |space_type|
      standards_space_type = space_type.standardsSpaceType.get if space_type.standardsSpaceType.is_initialized
      standards_building_type = space_type.standardsBuildingType.get if space_type.standardsBuildingType.is_initialized

      if !standards_space_type.nil? && !standards_building_type.nil?
        mapping = space_types_data.find { |s| s[:standards_building_type] == standards_building_type && s[:standards_space_type] == standards_space_type }
        if mapping.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Prototypes', "No mapping found for standards building type '#{standards_building_type}' and standards space type '#{standards_space_type}'")
        else
          new_standards_space_type_name = mapping[:new_standards_space_type]
          space_type.additionalProperties.setFeature('standards_space_type', new_standards_space_type_name)
          if reset_standards_space_type
            space_type.setStandardsSpaceType(new_standards_space_type_name)
          end
        end
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Prototypes', "Space type '#{space_type.name}' is missing either Standards Space Type or Building Type")
      end
    end

    # set additional properties for each space type if requested
    if set_additional_properties
      OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model, space_type_field: 'AdditionalProperties', reset_standards_space_type: false)
    end

    return true
  end
end
