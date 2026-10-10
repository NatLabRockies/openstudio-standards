module OpenstudioStandards
  # The Occupancy module provides methods to create, modify, and get information about occupancy
  module Occupancy
    # @!group Create Typical Occupancy
    # Methods to create typical occupancy

    # Fields an occupancy override entry may set, named as the load_overrides people section
    # names them.
    OCCUPANCY_OVERRIDE_FIELDS = [:people_per_1000_ft2].freeze

    # Apply runtime occupancy overrides to the occupant density resolved for a space type.
    #
    # Entries are matched the way the other override families are: by schedule set name,
    # standards space type, ventilation space type, or the '*' wildcard, with a specific entry
    # winning over the wildcard. An override applies whether or not the lookup found data, so it
    # is also the way to occupy a space type the data gives no density for.
    #
    # @param occupancy [Hash, nil] the density from the space type data, or nil where none was found
    # @param space_type [OpenStudio::Model::SpaceType] the space type being resolved
    # @param standards_space_type [String, nil] the space type's standardsSpaceType
    # @param ventilation_space_type [String, nil] the space type's ventilation_space_type property
    # @param overrides [Array<Hash>, nil] override entries, each with a matching key and an
    #   `occupancy` hash of fields
    # @return [Hash, nil] the density with any override applied
    def self.apply_occupancy_overrides(occupancy, space_type, standards_space_type, ventilation_space_type, overrides)
      return occupancy if overrides.nil? || overrides.empty?

      matched = OpenstudioStandards::CreateTypical.resolve_overrides(overrides, space_type,
                                                                    section_keys: [:occupancy],
                                                                    extra_names: [standards_space_type, ventilation_space_type])[:occupancy]
      return occupancy if matched.nil? || matched.empty?

      applied = matched.select { |field, _| OCCUPANCY_OVERRIDE_FIELDS.include?(field) }
      return occupancy unless applied.key?(:people_per_1000_ft2)

      { per_area: applied[:people_per_1000_ft2].to_f,
        source: [occupancy && occupancy[:source], 'override(people_per_1000_ft2)'].compact.join(' + ') }
    end

    # Create typical occupancy (People) objects in a model.
    #
    # Creates a People object for each space type from the occupancy data in
    # lib/openstudio-standards/occupancy/data/typical_space_type_occupancy.json, looked up by the
    # space type's 'ventilation_space_type' additional property (see
    # SpaceType.set_standards_space_type_additional_properties) and the template. That data
    # carries one entry per distinct occupant density, listing the templates it covers, so the
    # template string and the ventilation space type together are the whole lookup.
    #
    # Densities come from the ASHRAE 62.1 tables where the standard tabulates one for the space
    # type, and from the template's own standards space type data where it does not. Each entry
    # records which in its source.
    #
    # Space types with no density, and plenums, receive no People object. Occupancy schedules are
    # not assigned here; they come from the space type default schedule set, e.g. through
    # Schedules.space_type_apply_parametric_internal_load_schedules.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param template [String] optional OpenStudio Standards template, e.g. '90.1-2019'. Selects
    #   among the entries for a ventilation space type; the newest is used when none is given.
    # @param occupancy_overrides [Array<Hash>, nil] runtime occupancy overrides. Each entry is
    #   keyed by `space_type` (matched against the schedule set name, all-level space type, or
    #   ventilation space type) or `"*"`, with an `occupancy` hash accepting
    #   `people_per_1000_ft2`. An override wins over the data and applies even where the lookup
    #   found none.
    #
    #   A density alone only survives on a space type whose schedule set defines an occupancy
    #   schedule. The not-regularly-occupied schedule sets - corridors, restrooms, stairwells,
    #   attics, plenums, shafts, interior parking, storage, data centers - declare none by
    #   design, and Schedules.space_type_apply_parametric_internal_load_schedules removes a
    #   People object that would otherwise reach EnergyPlus without a schedule and terminate the
    #   run. To occupy one of those, pair this with a schedule_overrides entry naming an
    #   occupancy schedule: `{ space_type: 'restroom', occupancy: { schedule: 'office occupancy' } }`.
    # @return [Array<OpenStudio::Model::People>] Array of OpenStudio People objects
    def self.create_typical_occupancy(model, template: nil, occupancy_overrides: nil)
      peoples = []

      data_path = "#{File.dirname(__FILE__)}/data/typical_space_type_occupancy.json"
      occupancy_data = JSON.parse(File.read(data_path), symbolize_names: true)
      if occupancy_data.nil? || occupancy_data.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', 'Unable to load typical occupancy data. No occupancy will be added to model.')
        return peoples
      end

      model.getSpaceTypes.sort.each do |space_type|
        # remove existing people objects, on the space type and on its spaces
        space_type.people.sort.each(&:remove)
        space_type.spaces.each { |space| space.people.sort.each(&:remove) }

        # skip plenums
        next if space_type.name.get.to_s.downcase.include?('plenum')
        next if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')

        standards_space_type = nil
        if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
          standards_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
        elsif space_type.standardsSpaceType.is_initialized
          standards_space_type = space_type.standardsSpaceType.get
        end

        ventilation_space_type = nil
        if space_type.additionalProperties.hasFeature('ventilation_space_type')
          ventilation_space_type = space_type.additionalProperties.getFeatureAsString('ventilation_space_type').to_s
        end

        occupancy = nil
        if ventilation_space_type.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', "Space type '#{space_type.name}' does not have a ventilation_space_type property assigned. Occupancy will only be added if an override matches.")
        elsif ventilation_space_type == 'na'
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Occupancy', "Space type '#{space_type.name}' has ventilation_space_type 'na'. Occupancy will only be added if an override matches.")
        else
          entries = occupancy_data[ventilation_space_type.to_sym]
          entry = OpenstudioStandards::Ventilation.template_entry(entries, template)
          if entry.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', "Unable to find typical occupancy data for ventilation space type '#{ventilation_space_type}'#{template.nil? ? '' : " and template '#{template}'"}. No occupancy will be added for space type '#{space_type.name}'.")
          elsif entry[:occupancy_per_area_unit].to_s != 'ppl/1000 ft2'
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Occupancy', "Typical occupancy data for '#{ventilation_space_type}' has unrecognized unit '#{entry[:occupancy_per_area_unit]}'; expected 'ppl/1000 ft2'. No occupancy will be added for space type '#{space_type.name}'.")
          else
            occupancy = { per_area: entry[:occupancy_per_area].to_f, source: entry[:source].to_s }
          end
        end

        occupancy = OpenstudioStandards::Occupancy.apply_occupancy_overrides(occupancy, space_type, standards_space_type,
                                                                            ventilation_space_type, occupancy_overrides)
        next if occupancy.nil?

        if occupancy[:per_area].zero?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Occupancy', "Ventilation space type '#{ventilation_space_type}' defines no occupancy. No occupancy will be added for space type '#{space_type.name}'.")
          next
        end

        definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
        definition.setName("#{space_type.name} People Definition")
        definition.setPeopleperSpaceFloorArea(OpenStudio.convert(occupancy[:per_area] / 1000.0, 'people/ft^2', 'people/m^2').get)
        definition.setFractionRadiant(0.3)
        definition.additionalProperties.setFeature('occupancy_source', occupancy[:source].to_s)
        instance = OpenStudio::Model::People.new(definition)
        instance.setName("#{space_type.name} People")
        instance.setSpaceType(space_type)
        peoples << instance

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Occupancy', "Setting space type '#{space_type.name}' occupancy from '#{ventilation_space_type}' to #{occupancy[:per_area]} people/1000 ft^2 per #{occupancy[:source]}.")
      end

      return peoples
    end
  end
end
