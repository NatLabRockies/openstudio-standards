module OpenstudioStandards
  # The Ventilation module provides methods to create, modify, and get information about outdoor air ventilation
  module Ventilation
    # @!group Create Typical Ventilation
    # Methods to create typical ventilation

    # Fields a ventilation override entry may set, in the same units and with the same names the
    # load_overrides ventilation section uses.
    VENTILATION_OVERRIDE_FIELDS = %i[cfm_per_person cfm_per_area ach].freeze

    # Select the entry covering a template from data grouped by a 'templates' array, e.g. the
    # typical ventilation or typical occupancy entries for one ventilation space type.
    #
    # An exact match on the template label wins, then the label with any 'ComStock ' prefix
    # dropped. Otherwise candidates are narrowed to the requested template's family - 90.1,
    # DOE Ref, DEER, CBES - falling back to every template present when the family has none,
    # and the nearest vintage at or before the requested one wins, then the nearest after it.
    # A candidate matching the request's ComStock-ness breaks the remaining tie, so a ComStock
    # template prefers ComStock data where a template carries both.
    #
    # @param entries [Array<Hash>] data entries for one space type, each with a :templates array
    # @param template [String] OpenStudio Standards template, e.g. '90.1-2013', or nil
    # @return [Hash, nil] the selected entry, or nil when entries is empty
    def self.template_entry(entries, template)
      return nil if entries.nil? || entries.empty?

      by_template = {}
      entries.each { |entry| Array(entry[:templates]).each { |label| by_template[label.to_s] = entry } }
      return nil if by_template.empty?

      requested = template.to_s
      return by_template[requested] if by_template.key?(requested)

      base = requested.sub(/\AComStock /, '')
      return by_template[base] if by_template.key?(base)

      family_of = lambda do |label|
        bare = label.sub(/\AComStock /, '')
        %w[DEER DOE\ Ref CBES].find { |f| bare.start_with?(f) } || '90.1'
      end
      year_of = ->(label) { label.scan(/(?:19|20)\d{2}/).last.to_i }

      candidates = by_template.keys.select { |label| family_of.call(label) == family_of.call(base) }
      candidates = by_template.keys if candidates.empty?
      return by_template[candidates.max_by { |label| year_of.call(label) }] if requested.empty?

      year = year_of.call(base)
      comstock = requested.start_with?('ComStock ')
      best = candidates.min_by do |label|
        [year_of.call(label) <= year ? 0 : 1,
         (year_of.call(label) - year).abs,
         label.start_with?('ComStock ') == comstock ? 0 : 1,
         label]
      end
      by_template[best]
    end

    # Apply runtime ventilation overrides to the rates resolved for a space type.
    #
    # Entries are matched the way the schedule, load, thermostat, service water heating and
    # exhaust override families are: by schedule set name, all-level space type, ventilation
    # space type, or the '*' wildcard, with a specific entry winning over the wildcard.
    #
    # This is the escape hatch for a building whose ventilation does not follow the space type
    # data, and the only way to give a space type ventilation when no data covers it at all -
    # an override applies whether or not the lookup found anything.
    #
    # @param rates [Hash, nil] the rates from the space type data, or nil where none were found
    # @param space_type [OpenStudio::Model::SpaceType] the space type being resolved
    # @param standards_space_type [String, nil] the space type's standardsSpaceType
    # @param ventilation_space_type [String, nil] the space type's ventilation_space_type property
    # @param overrides [Array<Hash>, nil] override entries, each with a matching key and a
    #   `ventilation` hash of fields
    # @return [Hash, nil] the rates with any override applied
    def self.apply_ventilation_overrides(rates, space_type, standards_space_type, ventilation_space_type, overrides)
      return rates if overrides.nil? || overrides.empty?

      matched = OpenstudioStandards::CreateTypical.resolve_overrides(overrides, space_type,
                                                                    section_keys: [:ventilation],
                                                                    extra_names: [standards_space_type, ventilation_space_type])[:ventilation]
      return rates if matched.nil? || matched.empty?

      applied = matched.select { |field, _| VENTILATION_OVERRIDE_FIELDS.include?(field) }
      return rates if applied.empty?

      overridden = (rates || { per_person: 0.0, per_area: 0.0, air_changes: 0.0, source: nil }).dup
      overridden[:per_person] = applied[:cfm_per_person].to_f if applied.key?(:cfm_per_person)
      overridden[:per_area] = applied[:cfm_per_area].to_f if applied.key?(:cfm_per_area)
      overridden[:air_changes] = applied[:ach].to_f if applied.key?(:ach)
      overridden[:source] = [overridden[:source], "override(#{applied.keys.join(', ')})"].compact.join(' + ')
      overridden
    end

    # Create typical outdoor air ventilation objects in a model.
    #
    # Creates a DesignSpecificationOutdoorAir object for each space type from the ventilation
    # space type data in lib/openstudio-standards/ventilation/data/ventilation_space_type_data.json,
    # looked up by the space type's 'ventilation_space_type' additional property (see
    # SpaceType.set_standards_space_type_additional_properties) and the template.
    #
    # That data carries one entry per distinct set of rates, listing the templates it covers, so
    # the template string and the ventilation space type together are the whole lookup. Rates
    # come from the ASHRAE 62.1 tables where the standard covers the space type, from the
    # template's own standards space type data where it does not, and from curated values for
    # the deliberate deviations - ASHRAE 170 health care rates, the exhaust-driven spaces, and
    # unoccupied spaces that receive no outdoor air. Each entry records which in its source.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param template [String] optional OpenStudio Standards template, e.g. '90.1-2013'. Selects
    #   among the entries for a ventilation space type; the newest is used when none is given.
    # @param ventilation_overrides [Array<Hash>, nil] runtime ventilation overrides. Each entry is
    #   keyed by `space_type` (matched against the schedule set name, all-level space type, or
    #   ventilation space type) or `"*"`, with a `ventilation` hash accepting
    #   `cfm_per_person`, `cfm_per_area` and `ach`. An override wins over the data and applies
    #   even where the lookup found none.
    # @return [Array<OpenStudio::Model::DesignSpecificationOutdoorAir>] Array of OpenStudio DesignSpecificationOutdoorAir objects
    def self.create_typical_ventilation(model, template: nil, ventilation_overrides: nil)
      design_specification_outdoor_airs = []

      data_path = "#{File.dirname(__FILE__)}/data/ventilation_space_type_data.json"
      ventilation_data = JSON.parse(File.read(data_path), symbolize_names: true)
      if ventilation_data.nil? || ventilation_data.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', 'Unable to load ventilation space type data. No ventilation will be added to model.')
        return design_specification_outdoor_airs
      end

      # The outdoor air method is a property of the standard rather than of the space type data:
      # DEER and CBES take the greatest of the rates where 90.1 sums them.
      ventilation_method = 'Sum'
      unless template.nil?
        begin
          ventilation_method = Standard.build(template).model_ventilation_method(model)
        rescue RuntimeError
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "'#{template}' is not a recognized OpenStudio Standards template. Using the 'Sum' outdoor air method.")
        end
      end

      model.getSpaceTypes.sort.each do |space_type|
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

        rates = nil
        if ventilation_space_type.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Space type '#{space_type.name}' does not have a ventilation_space_type property assigned. Ventilation will only be added if an override matches.")
        elsif ventilation_space_type == 'na'
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Ventilation', "Space type '#{space_type.name}' has ventilation_space_type 'na'. Ventilation will only be added if an override matches.")
        else
          entries = ventilation_data[ventilation_space_type.to_sym]
          entry = OpenstudioStandards::Ventilation.template_entry(entries, template)
          if entry.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Ventilation', "Unable to find ventilation data for ventilation space type '#{ventilation_space_type}'#{template.nil? ? '' : " and template '#{template}'"}. Ignoring space type '#{space_type.name}'.")
          else
            rates = { per_person: entry[:ventilation_per_person].to_f,
                      per_area: entry[:ventilation_per_area].to_f,
                      air_changes: entry[:ventilation_air_changes].to_f,
                      source: entry[:source].to_s }
          end
        end

        rates = OpenstudioStandards::Ventilation.apply_ventilation_overrides(rates, space_type, standards_space_type,
                                                                            ventilation_space_type, ventilation_overrides)
        next if rates.nil?

        ventilation = space_type.designSpecificationOutdoorAir
        if ventilation.is_initialized
          ventilation = ventilation.get
        else
          ventilation = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
          ventilation.setName("#{space_type.name} Ventilation")
          space_type.setDesignSpecificationOutdoorAir(ventilation)
        end

        # rates absent from the data are set to zero so a previously assigned design
        # specification outdoor air object is fully overwritten
        ventilation.setOutdoorAirMethod(ventilation_method)
        ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(rates[:per_person], 'ft^3/min*person', 'm^3/s*person').get)
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(rates[:per_area], 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        ventilation.setOutdoorAirFlowAirChangesperHour(rates[:air_changes])
        ventilation.additionalProperties.setFeature('ventilation_source', ventilation_space_type.to_s)
        ventilation.additionalProperties.setFeature('ventilation_standard', rates[:source].to_s)
        design_specification_outdoor_airs << ventilation

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Ventilation', "Setting space type '#{space_type.name}' ventilation from '#{ventilation_space_type}' to #{rates[:per_person]} cfm/person, #{rates[:per_area]} cfm/ft^2, #{rates[:air_changes]} ACH per #{rates[:source]}.")
      end

      return design_specification_outdoor_airs
    end
  end
end
