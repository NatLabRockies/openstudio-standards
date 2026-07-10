module OpenstudioStandards
  # The Occupancy module provides methods to create, modify, and get information about occupancy
  module Occupancy
    # @!group Create Typical Occupancy
    # Methods to create typical occupancy

    # Create typical occupancy (People) objects in a model.
    # Creates a People object for each space type with occupant densities from the template
    # (code version) values in the standards space types data, resolved through the validated
    # mapping of level-1 typical space types to standards space types in
    # lib/openstudio-standards/space_type/data/level_1_standards_space_type_map.json.
    # Space types without a mapping for the template, or whose standards space type defines
    # no occupancy, receive no People object. Occupancy schedules are not assigned here;
    # they come from the space type default schedule set, e.g. through
    # Schedules.space_type_apply_parametric_internal_load_schedules.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param template [String] OpenStudio Standards template, e.g. '90.1-2013', that supplies
    #   the occupant densities from its standards space types data.
    # @return [Array<OpenStudio::Model::People>] Array of OpenStudio People objects
    def self.create_typical_occupancy(model, template: nil)
      peoples = []

      # resolve the template to a Standard
      if template.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', 'A template is required to create typical occupancy from the standards space types data. No occupancy will be added to model.')
        return peoples
      end
      begin
        standard = Standard.build(template)
      rescue RuntimeError
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', "'#{template}' is not a recognized OpenStudio Standards template. No occupancy will be added to model.")
        return peoples
      end
      if standard.standards_data['space_types'].nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', "Template '#{template}' has no standards space type data. No occupancy will be added to model.")
        return peoples
      end

      # loop over space types and apply occupancy
      model.getSpaceTypes.each do |space_type|
        # remove existing people objects
        space_type.people.sort.each(&:remove)

        # remove existing people objects from spaces
        space_type.spaces.each do |space|
          space.people.sort.each(&:remove)
        end

        # skip plenums
        next if space_type.name.get.to_s.downcase.include?('plenum')
        next if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')

        # get the level-1 standards space type name
        level_1_space_type = nil
        if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
          level_1_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
        elsif space_type.standardsSpaceType.is_initialized
          level_1_space_type = space_type.standardsSpaceType.get
        end
        next if level_1_space_type.nil?

        map_row = OpenstudioStandards::SpaceType.level_1_standards_space_type_mapping(level_1_space_type, template)
        if map_row.nil?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Occupancy', "Space type '#{space_type.name}' has no standards space type mapping for template '#{template}'. No occupancy will be added.")
          next
        end

        search_criteria = { 'building_type' => map_row['building_type'], 'space_type' => map_row['space_type'] }
        standards_properties = standard.model_find_object(standard.standards_data['space_types'], search_criteria.merge('template' => template))
        standards_properties = standard.model_find_object(standard.standards_data['space_types'], search_criteria) if standards_properties.nil?
        if standards_properties.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', "Space type '#{space_type.name}' maps to '#{map_row['building_type']} | #{map_row['space_type']}', which was not found in the standards space type data for template '#{template}'. No occupancy will be added.")
          next
        end

        occupancy_per_area = standards_properties['occupancy_per_area'].to_f
        if occupancy_per_area.zero?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Occupancy', "Space type '#{space_type.name}' standards space type '#{map_row['building_type']} | #{map_row['space_type']}' defines no occupancy. No occupancy will be added.")
          next
        end

        # create the people definition and instance
        definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
        definition.setName("#{space_type.name} People Definition")
        definition.setPeopleperSpaceFloorArea(OpenStudio.convert(occupancy_per_area / 1000.0, 'people/ft^2', 'people/m^2').get)
        definition.setFractionRadiant(0.3)
        definition.additionalProperties.setFeature('occupancy_source', "#{template} #{map_row['building_type']} | #{map_row['space_type']}")
        instance = OpenStudio::Model::People.new(definition)
        instance.setName("#{space_type.name} People")
        instance.setSpaceType(space_type)
        peoples << instance

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Occupancy', "Setting space type '#{space_type.name}' occupancy from '#{template} #{map_row['building_type']} | #{map_row['space_type']}' to #{occupancy_per_area} people/1000 ft^2.")
      end

      return peoples
    end
  end
end
