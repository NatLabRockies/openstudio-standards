module OpenstudioStandards
  # The CreateTypical module provides methods to create and modify an entire building energy model of a typical building
  module CreateTypical
    # @!group SpecValidation
    # Validation for custom building specifications against the shipped JSON Schema and live standards data

    # Path to the JSON Schema describing the custom building specification
    CUSTOM_BUILDING_SPEC_SCHEMA_PATH = File.join(__dir__, 'data', 'custom_building_spec_schema.json')

    # Load the custom building specification JSON Schema
    #
    # @return [Hash] the parsed schema
    def self.custom_building_spec_schema
      JSON.parse(File.read(CUSTOM_BUILDING_SPEC_SCHEMA_PATH))
    end

    # Path to the level-1 typical space types data in the SpaceType module
    LEVEL_1_SPACE_TYPES_PATH = File.join(__dir__, '..', 'space_type', 'data', 'level_1_space_types.json')

    # Names of the level-1 typical space types, the valid space_type values for
    # spec space_type_ratios entries without a building_type
    #
    # @return [Array<String>] typical space type names, e.g. 'office'
    def self.level_1_space_type_names
      JSON.parse(File.read(LEVEL_1_SPACE_TYPES_PATH)).map { |row| row['space_type_name'] }
    end

    # Validate a custom building specification for create_custom_building_from_spec.
    # Structural rules (required keys, types, ranges, unknown keys) come from the shipped
    # JSON Schema; checks the schema cannot express (template resolvable, space type pairs
    # present in standards data, ratios summing to 1.0, typical_options keys) run against
    # live standards data afterwards.
    #
    # @param spec [Hash] custom building specification, see the schema file for structure
    # @return [Array<String>] error messages; empty when the spec is valid
    def self.validate_custom_building_spec(spec)
      errors = []
      unless spec.is_a?(Hash)
        errors << 'spec must be a hash'
        return errors
      end

      # structural validation against the shipped schema.
      # round-trip through JSON to get string keys/values matching the schema.
      schema = custom_building_spec_schema
      string_spec = JSON.parse(JSON.generate(spec))
      validate_spec_node(string_spec, schema, schema, 'spec', errors)
      return errors unless errors.empty?

      # template must resolve to a Standard; later checks need it
      template = string_spec['template']
      begin
        standard = Standard.build(template)
      rescue RuntimeError
        errors << "spec.template: '#{template}' is not a recognized OpenStudio Standards template"
        return errors
      end

      # ratios should sum to 1.0
      ratios = string_spec['space_type_ratios'].map { |entry| entry['ratio'] }
      ratio_sum = ratios.sum
      if (ratio_sum - 1.0).abs > 0.001
        errors << "spec.space_type_ratios: ratios sum to #{ratio_sum.round(4)}, expected 1.0"
      end

      # ratio entries come in two forms: standard entries carrying a building_type, checked
      # against the standards space type data, and typical entries without one, checked
      # against the level-1 typical space type names. The two forms drive different internal
      # load paths in create_typical_building_from_model, so they cannot be mixed.
      standard_entries, typical_entries = string_spec['space_type_ratios'].each_with_index.partition { |entry, _| !entry['building_type'].to_s.empty? }
      if !standard_entries.empty? && !typical_entries.empty?
        errors << 'spec.space_type_ratios: entries mix standard building_type | space_type pairs with typical space types (no building_type). Use one form for all entries.'
        return errors
      end

      # standard entries: building_type | space_type pairs should exist in the standards space type data.
      # Entries carrying their own geometry metadata only warn, since geometry can proceed without a match.
      metadata_keys = %w[story_height wwr default circ space_type_gen]
      standard_entries.each do |entry, i|
        building_type = entry['building_type']
        space_type = entry['space_type']
        search_criteria = {
          'template' => template,
          'building_type' => standard.model_get_lookup_name(building_type),
          'space_type' => space_type
        }
        next unless standard.model_find_object(standard.standards_data['space_types'], search_criteria).nil?

        message = "spec.space_type_ratios[#{i}]: '#{building_type} | #{space_type}' was not found in the standards space type data for template '#{template}'"
        if (entry.keys & metadata_keys).empty?
          errors << message
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CreateTypical', "#{message}. Geometry will be generated from the entry metadata, but no internal loads or schedules will be applied.")
        end
      end

      # typical entries: space types should exist in the level-1 typical space type data,
      # and a primary_building_type is required since no building type is available to infer from
      unless typical_entries.empty?
        level_1_space_type_names = OpenstudioStandards::CreateTypical.level_1_space_type_names
        typical_entries.each do |entry, i|
          space_type = entry['space_type']
          next if level_1_space_type_names.include?(space_type)

          errors << "spec.space_type_ratios[#{i}]: '#{space_type}' is not a typical space type. See lib/openstudio-standards/space_type/data/level_1_space_types.json for valid names."
        end
        if string_spec['primary_building_type'].to_s.empty?
          errors << 'spec.primary_building_type: required when space_type_ratios entries are typical space types, to drive the building form defaults and construction set.'
        end
      end

      # primary_building_type must be a standard building type: it drives the construction
      # set and other standards lookups in create_typical_building_from_model
      primary_building_type = string_spec['primary_building_type']
      if !primary_building_type.nil? && OpenstudioStandards::Geometry.building_form_defaults(primary_building_type).nil?
        errors << "spec.primary_building_type: '#{primary_building_type}' is not a recognized standard building type. Use the 'name' key to label a custom building."
      end

      # typical_options keys must be keyword arguments of create_typical_building_from_model,
      # excluding the ones managed by top-level spec keys
      typical_options = string_spec['typical_options']
      if typical_options.is_a?(Hash)
        allowed_keys = OpenstudioStandards::CreateTypical.method(:create_typical_building_from_model).parameters
                                                         .select { |param_type, _| %i[key keyreq].include?(param_type) }
                                                         .map { |_, name| name.to_s }
        managed_keys = %w[climate_zone primary_building_type building_name schedule_overrides load_overrides]
        typical_options.each_key do |key|
          if managed_keys.include?(key)
            errors << "spec.typical_options.#{key}: managed by the corresponding top-level spec key, set it there instead"
          elsif key == 'space_type_load_method'
            errors << 'spec.typical_options.space_type_load_method: determined from the space_type_ratios entry form (entries without a building_type use the typical load method)'
          elsif !allowed_keys.include?(key)
            errors << "spec.typical_options.#{key}: not an argument of create_typical_building_from_model"
          end
        end
      end

      errors
    end

    # Validate a value against a node of the custom building spec schema.
    # Interprets the subset of JSON Schema keywords the shipped schema uses:
    # $ref, type, required, properties, additionalProperties: false, anyOf (of required
    # clauses), items, minItems, minimum, maximum, exclusiveMinimum, exclusiveMaximum,
    # minLength, and enum. Appends messages to errors.
    #
    # @param value [Object] value to validate (string-keyed structures)
    # @param node [Hash] schema node
    # @param root [Hash] schema root, for $ref resolution
    # @param path [String] human-readable location for error messages
    # @param errors [Array<String>] error message accumulator
    # @return [Void]
    def self.validate_spec_node(value, node, root, path, errors)
      while node.is_a?(Hash) && node.key?('$ref')
        ref = node['$ref']
        resolved = ref.sub('#/', '').split('/').reduce(root) { |n, key| n.is_a?(Hash) ? n[key] : nil }
        if resolved.nil?
          errors << "#{path}: could not resolve schema reference '#{ref}'"
          return
        end
        node = resolved
      end
      return unless node.is_a?(Hash)

      if node.key?('type')
        type_ok = case node['type']
                  when 'object' then value.is_a?(Hash)
                  when 'array' then value.is_a?(Array)
                  when 'string' then value.is_a?(String)
                  when 'number' then value.is_a?(Numeric)
                  when 'integer' then value.is_a?(Integer)
                  when 'boolean' then value == true || value == false
                  else true
                  end
        unless type_ok
          errors << "#{path}: must be a #{node['type']}"
          return
        end
      end

      if node.key?('enum') && !node['enum'].include?(value)
        errors << "#{path}: must be one of #{node['enum'].join(', ')}"
      end

      if value.is_a?(Hash)
        (node['required'] || []).each do |key|
          errors << "#{path}: missing required key '#{key}'" unless value.key?(key)
        end
        properties = node['properties'] || {}
        if node['additionalProperties'] == false
          value.each_key do |key|
            errors << "#{path}: unknown key '#{key}'" unless properties.key?(key)
          end
        end
        properties.each do |key, sub_node|
          validate_spec_node(value[key], sub_node, root, "#{path}.#{key}", errors) if value.key?(key)
        end
        if node['anyOf'].is_a?(Array) && node['anyOf'].all? { |branch| branch.is_a?(Hash) && branch.key?('required') }
          satisfied = node['anyOf'].any? { |branch| branch['required'].all? { |key| value.key?(key) } }
          unless satisfied
            errors << "#{path}: must include one of #{node['anyOf'].map { |branch| branch['required'].join(' + ') }.join(', ')}"
          end
        end
      end

      if value.is_a?(Array)
        if node.key?('minItems') && value.size < node['minItems']
          errors << "#{path}: must have at least #{node['minItems']} item(s)"
        end
        if node.key?('items')
          value.each_with_index do |item, i|
            validate_spec_node(item, node['items'], root, "#{path}[#{i}]", errors)
          end
        end
      end

      if value.is_a?(Numeric)
        errors << "#{path}: must be >= #{node['minimum']}" if node.key?('minimum') && value < node['minimum']
        errors << "#{path}: must be <= #{node['maximum']}" if node.key?('maximum') && value > node['maximum']
        errors << "#{path}: must be > #{node['exclusiveMinimum']}" if node.key?('exclusiveMinimum') && value <= node['exclusiveMinimum']
        errors << "#{path}: must be < #{node['exclusiveMaximum']}" if node.key?('exclusiveMaximum') && value >= node['exclusiveMaximum']
      end

      if value.is_a?(String) && node.key?('minLength') && value.length < node['minLength']
        errors << "#{path}: must not be empty"
      end
    end
  end
end
