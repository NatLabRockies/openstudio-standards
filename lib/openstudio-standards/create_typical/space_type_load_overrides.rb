module OpenstudioStandards
  # The CreateTypical module provides methods to create and modify an entire building energy model of a typical building
  module CreateTypical
    # @!group SpaceTypeLoadOverrides
    # Runtime internal load overrides applied on top of standards space type data

    # Normalize an overrides argument that may be a Ruby array (API callers) or a
    # JSON string (flat-typed measure callers) into an array of symbol-keyed hashes.
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

      overrides.map { |entry| entry.is_a?(Hash) ? entry.transform_keys(&:to_sym) : entry }
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
      schedule_set_name = nil
      if space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized
        schedule_set_name = space_type.additionalProperties.getFeatureAsString('schedule_set').get
      end
      standards_space_type = nil
      if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
        standards_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
      end
      section_keys = %i[people lighting electric_equipment gas_equipment ventilation]
      overrides = OpenstudioStandards::Schedules.resolve_schedule_overrides(load_overrides, schedule_set_name, standards_space_type,
                                                                            section_keys: section_keys)
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
