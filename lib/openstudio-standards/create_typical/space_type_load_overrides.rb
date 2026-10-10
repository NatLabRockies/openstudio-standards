module OpenstudioStandards
  # The CreateTypical module provides methods to create and modify an entire building energy model of a typical building
  module CreateTypical
    # @!group SpaceTypeLoadOverrides
    # Runtime internal load overrides applied on top of standards space type data

    # Normalize an overrides argument that may be a Ruby array (API callers) or a
    # JSON string (flat-typed measure callers) into an array of symbol-keyed hashes.
    #
    # Symbolizing runs all the way down, not just over each entry's own keys. Every
    # consumer reads the section hashes by symbol -- overrides[:people][:cfm_per_person],
    # overrides[:thermostat][:cooling_setpoint_c] -- so a caller passing a Ruby hash built
    # with string keys, as a measure assembling a spec naturally does, would have its
    # entries matched and its fields then silently ignored. A JSON string never showed this
    # because JSON.parse symbolizes the whole tree.
    #
    # @param overrides [Array<Hash>, String, nil] overrides input
    # @param argument_name [String] argument name used in log messages
    # @return [Array<Hash>, nil] normalized overrides, or nil if absent or unparsable
    def self.parse_overrides_argument(overrides, argument_name)
      if overrides.is_a?(String)
        return nil if overrides.strip.empty?

        begin
          overrides = JSON.parse(overrides, symbolize_names: true)
        rescue JSON::ParserError => e
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', "Could not parse #{argument_name} JSON string: #{e.message}")
          return nil
        end
      end
      return nil unless overrides.is_a?(Array)

      overrides.map { |entry| OpenstudioStandards::CreateTypical.deep_symbolize_keys(entry) }
    end

    # Parse a construction set spec argument, which is a hash rather than the array the override
    # families use, and may arrive as a JSON string from a measure.
    #
    # @param constructions [Hash, String, nil] the construction spec
    # @return [Hash, nil] the spec with symbol keys, or nil when there is none
    def self.parse_constructions_argument(constructions)
      if constructions.is_a?(String)
        return nil if constructions.strip.empty?

        begin
          constructions = JSON.parse(constructions, symbolize_names: true)
        rescue JSON::ParserError => e
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', "Could not parse constructions JSON string: #{e.message}")
          return nil
        end
      end
      return nil unless constructions.is_a?(Hash)
      return nil if constructions.empty?

      OpenstudioStandards::CreateTypical.deep_symbolize_keys(constructions)
    end

    # Symbolize the keys of a hash and of every hash nested inside it. Values are left
    # alone; only keys are converted.
    #
    # @param object [Object] hash, array, or scalar
    # @return [Object] the same structure with symbol keys throughout
    def self.deep_symbolize_keys(object)
      case object
      when Hash
        object.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = OpenstudioStandards::CreateTypical.deep_symbolize_keys(value)
        end
      when Array
        object.map { |element| OpenstudioStandards::CreateTypical.deep_symbolize_keys(element) }
      else
        object
      end
    end

    # Names an override entry may be keyed by. All of them are typical-path vocabulary: the
    # override families exist for the 'typical' space type load method, where a model is built
    # from the all-level space types and their typical data. The 'standards' method builds from
    # the standards data as the standard defines it and is not overridden here, so a standards
    # space type is deliberately not among these.
    #
    # `space_type` matches any of the names a space type answers to, which is what most callers
    # want; the others target one of them explicitly.
    OVERRIDE_MATCH_KEYS = %i[space_type schedule_set ventilation_space_type].freeze

    # The names a space type answers to when an override entry is matched against it: its
    # parametric schedule set, its all-level space type name, and its ventilation space type.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @return [Array<String>] the names, without duplicates
    def self.space_type_override_names(space_type)
      names = %w[schedule_set standards_space_type ventilation_space_type].map do |feature|
        value = space_type.additionalProperties.getFeatureAsString(feature)
        value.is_initialized ? value.get : nil
      end
      names << (space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil)
      names.compact.map(&:to_s).uniq
    end

    # Resolve runtime overrides for one space type into a merged hash of per-section fields.
    #
    # Every override family shares this: entries are keyed by one of OVERRIDE_MATCH_KEYS or the
    # `"*"` wildcard, the wildcard is applied first and a specific match second so a specific
    # entry's fields win field by field, and each family reads its own sections out of the
    # result. Only the section names differ between families.
    #
    # @param overrides [Array<Hash>, nil] override entries
    # @param space_type [OpenStudio::Model::SpaceType] the space type being resolved
    # @param section_keys [Array<Symbol>] the section names this family reads
    # @param extra_names [Array<String, nil>] further names to match on, beyond the ones the
    #   space type answers to
    # @return [Hash] merged sections, e.g. { ventilation: {...} }, empty when nothing matched
    def self.resolve_overrides(overrides, space_type, section_keys:, extra_names: [])
      # A caller reaching a module method directly can hand over the JSON string form that
      # parse_overrides_argument would have normalized, so say so rather than failing on
      # String#find several frames down.
      unless overrides.is_a?(Array)
        unless overrides.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CreateTypical',
                             "Overrides must be an array of entries, got a #{overrides.class}. Parse a JSON string with CreateTypical.parse_overrides_argument first. Ignoring overrides.")
        end
        return {}
      end
      return {} if overrides.empty?

      # Entries reaching a module method directly can carry string keys, which a measure
      # assembling a spec produces naturally; only parse_overrides_argument symbolizes. Reading
      # either form keeps a string-keyed entry from matching on its key and then having every
      # field in it silently ignored.
      field = ->(hash, name) { hash[name].nil? ? hash[name.to_s] : hash[name] }

      specific = (OpenstudioStandards::CreateTypical.space_type_override_names(space_type) + Array(extra_names)).compact.map(&:to_s)
      merged = {}
      [['*'], specific].each do |match_names|
        matches = overrides.select do |candidate|
          next false unless candidate.is_a?(Hash)

          key = OVERRIDE_MATCH_KEYS.map { |match_key| field.call(candidate, match_key) }.compact.first.to_s
          match_names.include?(key)
        end
        entry = matches.first
        # Only the first match is read, so a second entry reaching the same space type --
        # a duplicate key, or two entries matching through different names -- would be
        # silently dead without this.
        if matches.size > 1
          matched_keys = matches.map { |candidate| OVERRIDE_MATCH_KEYS.map { |match_key| field.call(candidate, match_key) }.compact.first.to_s }
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CreateTypical',
                             "#{matches.size} override entries (#{matched_keys.uniq.join(', ')}) match space type '#{space_type.name}'. Only the first is applied; merge them into one entry.")
        end
        next if entry.nil?

        section_keys.each do |section_key|
          section = field.call(entry, section_key)
          next unless section.is_a?(Hash)

          section = section.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
          merged[section_key] = (merged[section_key] || {}).merge(section)
        end
      end

      merged
    end

    # Apply a runtime continuous-operation override to a space type.
    #
    # A thermostat_overrides entry may carry `thermostat: { continuous_operation: true }`
    # (or false) alongside or instead of setpoints. It is matched like every other
    # override - by schedule set, all-level space type, ventilation space type, or '*' -
    # and stamps the space type's 'critical_operation' property, which the data set from
    # all_level_space_types.json when the space type was resolved. The occupancy schedule
    # derivation behind air loop and zone equipment operation reads that property and
    # returns always-on for anything serving a flagged space type, so a spec can hold a
    # loop continuous for a space type the data does not flag, or release one it does.
    #
    # @param space_type [OpenStudio::Model::SpaceType] space type object
    # @param thermostat_overrides [Array<Hash>, nil] thermostat override entries
    # @return [Boolean, nil] the value stamped, or nil when no entry spoke to it
    def self.space_type_apply_operation_overrides(space_type, thermostat_overrides)
      return nil if thermostat_overrides.nil? || thermostat_overrides.empty?

      section = OpenstudioStandards::CreateTypical.resolve_overrides(thermostat_overrides, space_type, section_keys: [:thermostat])[:thermostat]
      return nil if section.nil? || section[:continuous_operation].nil?

      value = section[:continuous_operation]
      unless [true, false].include?(value)
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CreateTypical',
                           "continuous_operation for space type '#{space_type.name}' must be true or false, got #{value.inspect}. Ignoring it.")
        return nil
      end

      space_type.additionalProperties.setFeature('critical_operation', value)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical',
                         "Space type '#{space_type.name}' #{value ? 'runs continuously' : 'follows occupancy'} by override.")
      value
    end

    # Apply continuous-operation overrides to every space type in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermostat_overrides [Array<Hash>, nil] thermostat override entries
    # @return [Integer] the number of space types an entry spoke to
    def self.model_apply_operation_overrides(model, thermostat_overrides)
      return 0 if thermostat_overrides.nil? || thermostat_overrides.empty?

      model.getSpaceTypes.count do |space_type|
        !OpenstudioStandards::CreateTypical.space_type_apply_operation_overrides(space_type, thermostat_overrides).nil?
      end
    end

    # Apply runtime internal load overrides to a space type on top of the loads
    # created from standards data by space_type_apply_internal_loads.
    #
    # Override entries use the same matching semantics as schedule_overrides: an entry is
    # keyed by `space_type` (matched against the space type's 'schedule_set' or
    # 'standards_space_type' additional property) or the `"*"` wildcard, and a specific
    # entry's fields win over the wildcard's field-by-field.
    #
    # Supported sections and fields (IP units, matching standards data conventions):
    #   people:             { people_per_1000_ft2: Numeric, keep_standard_design_level: Boolean }
    #   lighting:           { w_per_area: Numeric (W/ft^2), w_per_person: Numeric (W/person) }
    #   electric_equipment: { w_per_area: Numeric (W/ft^2) }
    #   gas_equipment:      { btu_per_hr_per_area: Numeric (Btu/hr*ft^2) }
    #   ventilation:        { cfm_per_person: Numeric, cfm_per_area: Numeric (cfm/ft^2), ach: Numeric }
    #
    # When an override targets a load the standards data created no instance for
    # (e.g. adding people to a space type with zero standard occupant density), the
    # load instance and definition are created.
    #
    # When the people override sets keep_standard_design_level true, the design occupancy
    # level from the standard input is kept, and the space type's occupancy schedule peak is
    # instead adjusted so that the peak occupancy (design level * peak schedule value) matches
    # people_per_1000_ft2. The adjustment is stored as an 'occupancy_peak_override' additional
    # property on the space type and consumed by
    # Schedules.space_type_apply_parametric_internal_load_schedules, so it only takes effect
    # with the parametric schedule method applied after this method.
    #
    # @param space_type [OpenStudio::Model::SpaceType] space type object
    # @param load_overrides [Array<Hash>] override entries
    # @return [Boolean] returns true if successful, false if not
    def self.space_type_apply_load_overrides(space_type, load_overrides)
      return true if load_overrides.nil? || load_overrides.empty?

      # resolve overrides for this space type using the same keys as schedule overrides
      section_keys = %i[people lighting electric_equipment gas_equipment ventilation]
      overrides = OpenstudioStandards::CreateTypical.resolve_overrides(load_overrides, space_type, section_keys: section_keys)
      return true if overrides.empty?

      # people
      if overrides[:people].is_a?(Hash) && overrides[:people][:people_per_1000_ft2].is_a?(Numeric)
        people_per_1000_ft2 = overrides[:people][:people_per_1000_ft2]
        keep_standard_design_level = overrides[:people][:keep_standard_design_level] == true
        instance = space_type.people.min_by { |i| i.name.to_s }

        if keep_standard_design_level
          # keep the standard design occupancy level and adjust the occupancy schedule peak
          # so that the peak occupancy matches the override
          standard_density_si = instance.nil? ? nil : instance.peopleDefinition.peopleperSpaceFloorArea
          if standard_density_si.nil? || standard_density_si.empty? || standard_density_si.get <= 0.0
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CreateTypical', "#{space_type.name} load override requested keep_standard_design_level but there is no standard occupancy design level to keep. Setting the occupancy level directly.")
            keep_standard_design_level = false
          else
            standard_per_1000_ft2 = OpenStudio.convert(standard_density_si.get, 'people/m^2', 'people/ft^2').get * 1000.0
            occupancy_peak = people_per_1000_ft2 / standard_per_1000_ft2
            if occupancy_peak > 1.0
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CreateTypical', "#{space_type.name} load override peak occupancy of #{people_per_1000_ft2} people/1000 ft^2 exceeds the standard design level of #{standard_per_1000_ft2.round(2)} people/1000 ft^2, requiring an occupancy schedule peak of #{occupancy_peak.round(3)} above 1.0.")
            end
            space_type.additionalProperties.setFeature('occupancy_peak_override', occupancy_peak)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override keeping standard occupancy design level of #{standard_per_1000_ft2.round(2)} people/1000 ft^2 and setting the occupancy schedule peak to #{occupancy_peak.round(3)} so peak occupancy matches #{people_per_1000_ft2} people/1000 ft^2.")
          end
        end

        unless keep_standard_design_level
          if instance.nil?
            definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
            definition.setName("#{space_type.name} People Definition")
            instance = OpenStudio::Model::People.new(definition)
            instance.setName("#{space_type.name} People")
            instance.setSpaceType(space_type)
            definition.setFractionRadiant(0.3)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} had no people, created one for the load override.")
          end
          instance.peopleDefinition.setPeopleperSpaceFloorArea(OpenStudio.convert(people_per_1000_ft2 / 1000.0, 'people/ft^2', 'people/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set occupancy to #{people_per_1000_ft2} people/1000 ft^2.")
        end
      end

      # lighting
      if overrides[:lighting].is_a?(Hash)
        w_per_area = overrides[:lighting][:w_per_area]
        w_per_person = overrides[:lighting][:w_per_person]
        if w_per_area.is_a?(Numeric) || w_per_person.is_a?(Numeric)
          instance = space_type.lights.min_by { |i| i.name.to_s }
          if instance.nil?
            definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
            definition.setName("#{space_type.name} Lights Definition")
            instance = OpenStudio::Model::Lights.new(definition)
            instance.setName("#{space_type.name} Lights")
            instance.setSpaceType(space_type)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} had no lights, created one for the load override.")
          end
          if w_per_area.is_a?(Numeric)
            instance.lightsDefinition.setWattsperSpaceFloorArea(OpenStudio.convert(w_per_area, 'W/ft^2', 'W/m^2').get)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set LPD to #{w_per_area} W/ft^2.")
          end
          if w_per_person.is_a?(Numeric)
            instance.lightsDefinition.setWattsperPerson(w_per_person)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set lighting to #{w_per_person} W/person.")
          end
        end
      end

      # electric equipment
      if overrides[:electric_equipment].is_a?(Hash) && overrides[:electric_equipment][:w_per_area].is_a?(Numeric)
        w_per_area = overrides[:electric_equipment][:w_per_area]
        instance = space_type.electricEquipment.min_by { |i| i.name.to_s }
        if instance.nil?
          definition = OpenStudio::Model::ElectricEquipmentDefinition.new(space_type.model)
          definition.setName("#{space_type.name} Elec Equip Definition")
          instance = OpenStudio::Model::ElectricEquipment.new(definition)
          instance.setName("#{space_type.name} Elec Equip")
          instance.setSpaceType(space_type)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} had no electric equipment, created one for the load override.")
        end
        instance.electricEquipmentDefinition.setWattsperSpaceFloorArea(OpenStudio.convert(w_per_area, 'W/ft^2', 'W/m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set EPD to #{w_per_area} W/ft^2.")
      end

      # gas equipment
      if overrides[:gas_equipment].is_a?(Hash) && overrides[:gas_equipment][:btu_per_hr_per_area].is_a?(Numeric)
        btu_per_hr_per_area = overrides[:gas_equipment][:btu_per_hr_per_area]
        instance = space_type.gasEquipment.min_by { |i| i.name.to_s }
        if instance.nil?
          definition = OpenStudio::Model::GasEquipmentDefinition.new(space_type.model)
          definition.setName("#{space_type.name} Gas Equip Definition")
          instance = OpenStudio::Model::GasEquipment.new(definition)
          instance.setName("#{space_type.name} Gas Equip")
          instance.setSpaceType(space_type)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} had no gas equipment, created one for the load override.")
        end
        instance.gasEquipmentDefinition.setWattsperSpaceFloorArea(OpenStudio.convert(btu_per_hr_per_area, 'Btu/hr*ft^2', 'W/m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set gas equipment to #{btu_per_hr_per_area} Btu/hr*ft^2.")
      end

      # ventilation
      if overrides[:ventilation].is_a?(Hash)
        cfm_per_person = overrides[:ventilation][:cfm_per_person]
        cfm_per_area = overrides[:ventilation][:cfm_per_area]
        ach = overrides[:ventilation][:ach]
        if cfm_per_person.is_a?(Numeric) || cfm_per_area.is_a?(Numeric) || ach.is_a?(Numeric)
          ventilation = space_type.designSpecificationOutdoorAir
          if ventilation.is_initialized
            ventilation = ventilation.get
          else
            ventilation = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
            ventilation.setName("#{space_type.name} Ventilation")
            space_type.setDesignSpecificationOutdoorAir(ventilation)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} had no ventilation specification, created one for the load override.")
          end
          if cfm_per_person.is_a?(Numeric)
            ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(cfm_per_person, 'ft^3/min', 'm^3/s').get)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set ventilation to #{cfm_per_person} cfm/person.")
          end
          if cfm_per_area.is_a?(Numeric)
            ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(cfm_per_area, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set ventilation to #{cfm_per_area} cfm/ft^2.")
          end
          if ach.is_a?(Numeric)
            ventilation.setOutdoorAirFlowAirChangesperHour(ach)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CreateTypical', "#{space_type.name} load override set ventilation to #{ach} ACH.")
          end
        end
      end

      return true
    end
  end
end
