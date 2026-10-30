module OpenstudioStandards
  # The CreateTypical module provides methods to create and modify an entire building energy model of a typical building
  module CreateTypical
    # @!group CreateCustom
    # Create a complete typical model of a custom building type from a single specification

    # Create a custom building in the model from a specification hash or JSON string.
    # A custom building is a named mix of space types with custom area ratios,
    # building form, schedule overrides, internal load overrides, and thermostat setpoint
    # overrides. The specification is validated before the model is modified; on validation
    # failure the model is untouched.
    #
    # Space type ratio entries come in two forms that cannot be mixed:
    # standard entries with a building_type and space_type from the standards data for the
    # template, whose internal loads come from the standards space type data; or typical
    # entries with only a space_type naming a typical space type from
    # lib/openstudio-standards/space_type/data/all_level_space_types.json -- the level-1
    # names such as 'office' plus the building-type-qualified variants such as
    # 'corridor - hospital' -- whose internal loads come from the typical lighting,
    # equipment, and ventilation data.
    # Typical entries use the same space type vocabulary as schedule_overrides and
    # load_overrides and require a top-level primary_building_type.
    #
    # The specification structure is documented by the JSON Schema at
    # lib/openstudio-standards/create_typical/data/custom_building_spec_schema.json.
    # Example specifications are in lib/openstudio-standards/create_typical/data/examples/.
    #
    # Steps: validate spec -> create bar geometry from space type ratios ->
    # set building location and site properties -> create typical building.
    #
    # The location step uses the climate zone representative weather file unless the spec
    # carries a :site section with a :weather_file_path. Callers modelling a real building
    # stock should supply one: the representative file would otherwise replace theirs, and
    # since equipment is sized during the create typical stage, the design days set here are
    # what sizing runs against.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object, typically empty
    # @param spec [Hash, String] custom building specification as a Hash (symbol or string keys)
    #   or a JSON string. Required keys: :template, :climate_zone, :space_type_ratios.
    #   Optional keys: :name, :primary_building_type, :form, :site, :schedule_overrides,
    #   :load_overrides, :thermostat_overrides, :service_water_heating_overrides, :exhaust_overrides,
    #   :ventilation_overrides, :occupancy_overrides, :constructions,
    #   :typical_options.
    # @return [Boolean] returns true if successful, false if not
    def self.create_custom_building_from_spec(model, spec)
      # accept a JSON string
      if spec.is_a?(String)
        begin
          spec = JSON.parse(spec, symbolize_names: true)
        rescue JSON::ParserError => e
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', "Could not parse custom building spec JSON string: #{e.message}")
          return false
        end
      end
      unless spec.is_a?(Hash)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', 'Custom building spec must be a hash or a JSON string encoding one.')
        return false
      end
      spec = spec.transform_keys(&:to_sym)

      # validate before touching the model
      errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(spec)
      unless errors.empty?
        errors.each do |error|
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', "Custom building spec invalid: #{error}")
        end
        return false
      end

      template = spec[:template]
      climate_zone = spec[:climate_zone]

      # ratio entries without a building_type name typical (level-1) space types and switch
      # create_typical_building_from_model to the typical internal load path, which builds
      # lighting, equipment, and ventilation from module data instead of standards space type data.
      # Validation guarantees the entries are all one form or the other.
      typical_space_types = spec[:space_type_ratios].all? do |entry|
        entry.is_a?(Hash) && entry.transform_keys(&:to_sym)[:building_type].to_s.empty?
      end
      space_type_load_method = typical_space_types ? 'typical' : 'standards'

      # bar geometry from space type ratios and form arguments
      bar_args = spec[:form].is_a?(Hash) ? spec[:form].transform_keys(&:to_sym) : {}
      if bar_args[:building_form_defaults].is_a?(Hash)
        bar_args[:building_form_defaults] = bar_args[:building_form_defaults].transform_keys(&:to_sym)
      end
      bar_args[:template] = template
      bar_args[:space_type_ratios] = spec[:space_type_ratios]
      bar_args[:primary_building_type] = spec[:primary_building_type] unless spec[:primary_building_type].to_s.empty?
      unless OpenstudioStandards::Geometry.create_bar_from_space_type_ratios(model, bar_args)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', 'Custom building geometry stage failed, see previous errors.')
        return false
      end

      # Weather file, site information, design days, water mains and ground temperatures.
      # A spec :site section with a :weather_file_path places the building on that specific
      # file; without one the climate zone representative file is used. Callers working from
      # a building stock must supply the path, both because the representative file would
      # otherwise replace theirs and because create_typical_building_from_model sizes
      # equipment below, so the design days set here are the ones sizing runs against.
      site = spec[:site].is_a?(Hash) ? spec[:site].transform_keys(&:to_sym) : {}
      weather_file_path = site[:weather_file_path]
      ddy_list = site[:ddy_list]
      ddy_list = ddy_list.map { |entry| entry.is_a?(Regexp) ? entry : Regexp.new(entry) } if ddy_list.is_a?(Array)

      location_set = if weather_file_path.to_s.empty?
                       OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone, ddy_list: ddy_list)
                     else
                       unless File.file?(weather_file_path)
                         OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', "Custom building spec site weather_file_path not found: #{weather_file_path}")
                         return false
                       end
                       OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path, climate_zone: climate_zone, ddy_list: ddy_list)
                     end
      if location_set == false
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', 'Custom building location stage failed, see previous errors.')
        return false
      end

      # Terrain sets the wind speed profile and so how much infiltration the building sees.
      # EnergyPlus defaults to Suburbs, which is a materially different heating load than a
      # city site, so it is worth stating rather than inheriting. The schema enumerates the
      # values, so a spec typo fails validation; the setter is still checked for callers
      # assembling the site hash in code, where a bad value would otherwise silently leave
      # the EnergyPlus default in place.
      unless site[:terrain].to_s.empty?
        unless model.getSite.setTerrain(site[:terrain].to_s)
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', "Custom building spec site terrain '#{site[:terrain]}' is not a valid terrain. Options are Country, Suburbs, City, Ocean, and Urban.")
          return false
        end
      end

      # Site properties that live on the building rather than in the weather data. These are
      # read by downstream tooling (emissions reporting, ground source heat pump modelling)
      # rather than by the model itself, so they are only set when supplied.
      building_properties = model.getBuilding.additionalProperties
      building_properties.setFeature('grid_region', site[:grid_region].to_s) unless site[:grid_region].to_s.empty?
      building_properties.setFeature('Soil Conductivity', site[:soil_conductivity].to_f) unless site[:soil_conductivity].nil?
      building_properties.setFeature('Undisturbed Ground Temperature', site[:undisturbed_ground_temperature].to_f) unless site[:undisturbed_ground_temperature].nil?

      # typical building articulation
      typical_options = spec[:typical_options].is_a?(Hash) ? spec[:typical_options].transform_keys(&:to_sym) : {}
      result = OpenstudioStandards::CreateTypical.create_typical_building_from_model(model, template,
                                                                                     climate_zone: climate_zone,
                                                                                     primary_building_type: spec[:primary_building_type],
                                                                                     building_name: spec[:name],
                                                                                     schedule_overrides: spec[:schedule_overrides],
                                                                                     load_overrides: spec[:load_overrides],
                                                                                     thermostat_overrides: spec[:thermostat_overrides],
                                                                                     service_water_heating_overrides: spec[:service_water_heating_overrides],
                                                                                     exhaust_overrides: spec[:exhaust_overrides],
                                                                                     ventilation_overrides: spec[:ventilation_overrides],
                                                                                     occupancy_overrides: spec[:occupancy_overrides],
                                                                                     constructions: spec[:constructions],
                                                                                     space_type_load_method: space_type_load_method,
                                                                                     **typical_options)
      unless result
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CreateTypical', 'Custom building typical model stage failed, see previous errors.')
        return false
      end

      true
    end
  end
end
