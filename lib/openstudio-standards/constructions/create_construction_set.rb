module OpenstudioStandards
  module Constructions
    ASSEMBLY_SURFACES = {
      exterior_floor: ['ExteriorFloor', :exterior_surfaces, :setFloorConstruction],
      exterior_wall: ['ExteriorWall', :exterior_surfaces, :setWallConstruction],
      exterior_roof: ['ExteriorRoof', :exterior_surfaces, :setRoofCeilingConstruction],
      ground_contact_floor: ['GroundContactFloor', :ground_surfaces, :setFloorConstruction],
      ground_contact_wall: ['GroundContactWall', :ground_surfaces, :setWallConstruction],
      ground_contact_ceiling: ['GroundContactRoof', :ground_surfaces, :setRoofCeilingConstruction],
      exterior_fixed_window: ['ExteriorWindow', :exterior_subsurfaces, :setFixedWindowConstruction],
      exterior_operable_window: ['ExteriorWindow', :exterior_subsurfaces, :setOperableWindowConstruction],
      exterior_door: ['ExteriorDoor', :exterior_subsurfaces, :setDoorConstruction],
      exterior_glass_door: ['GlassDoor', :exterior_subsurfaces, :setGlassDoorConstruction],
      exterior_overhead_door: ['ExteriorDoor', :exterior_subsurfaces, :setOverheadDoorConstruction],
      exterior_skylight: ['Skylight', :exterior_subsurfaces, :setSkylightConstruction]
    }.freeze

    NAMED_SURFACES = {
      interior_floors: [:interior_surfaces, :setFloorConstruction],
      interior_walls: [:interior_surfaces, :setWallConstruction],
      interior_ceilings: [:interior_surfaces, :setRoofCeilingConstruction],
      tubular_daylight_domes: [:exterior_subsurfaces, :setTubularDaylightDomeConstruction],
      tubular_daylight_diffusers: [:exterior_subsurfaces, :setTubularDaylightDiffuserConstruction],
      interior_fixed_windows: [:interior_subsurfaces, :setFixedWindowConstruction],
      interior_operable_windows: [:interior_subsurfaces, :setOperableWindowConstruction],
      interior_doors: [:interior_subsurfaces, :setDoorConstruction],
      interior_partitions: [:construction_set, :setInteriorPartitionConstruction],
      space_shading: [:construction_set, :setSpaceShadingConstruction],
      building_shading: [:construction_set, :setBuildingShadingConstruction],
      site_shading: [:construction_set, :setSiteShadingConstruction]
    }.freeze

    BROADCAST_TYPES = {
      exterior_wall_type: :exterior_wall,
      exterior_roof_type: :exterior_roof,
      exterior_floor_type: :exterior_floor
    }.freeze

    # Find the construction-set data row, preferring a residential-specific row when available.
    #
    # @param standard [Standard] standard used for construction lookups
    # @param model [OpenStudio::Model::Model] model used to resolve the climate-zone set
    # @param climate_zone [String] climate zone identifier
    # @param building_type [String, nil] standards building type
    # @param is_residential [String] residential flag used by standards data, usually 'Yes' or 'No'
    # @return [Hash, nil] matching construction-set row
    def self.construction_set_row(standard, model, climate_zone, building_type, is_residential)
      return nil if building_type.nil?

      climate_zone_set = standard.model_find_climate_zone_set(model, climate_zone)
      return nil unless climate_zone_set

      keys = { 'template' => standard.template, 'climate_zone_set' => climate_zone_set,
               'building_type' => building_type, 'space_type' => nil }
      standard.model_find_object(standard.standards_data['construction_sets'], keys.merge('is_residential' => is_residential)) ||
        standard.model_find_object(standard.standards_data['construction_sets'], keys)
    end

    # Create a construction set from explicit assembly types and categories, with row data as fallback.
    #
    # @param model [OpenStudio::Model::Model] model receiving the construction set
    # @param standard [Standard] standard used for construction lookups
    # @param climate_zone [String] climate zone identifier
    # @param spec [Hash] construction specification with optional assembly types, categories, and pinned names
    # @param fallback_building_type [String, nil] building type used to fill unspecified slots from standards data
    # @param name [String, nil] optional construction-set name
    # @return [OpenStudio::Model::DefaultConstructionSet, nil] created set, or nil when the climate zone cannot be resolved
    def self.create_construction_set(model, standard, climate_zone, spec,
                                     fallback_building_type: nil,
                                     name: nil)
      climate_zone_set = standard.model_find_climate_zone_set(model, climate_zone)
      if climate_zone_set.nil? || climate_zone_set == false
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Constructions',
                           "Could not find a climate zone set for #{climate_zone}. No construction set created.")
        return nil
      end

      spec = OpenstudioStandards::Constructions.symbolize_construction_spec(spec)
      surfaces = spec[:surfaces] || {}
      is_residential = spec[:is_residential] ? 'Yes' : 'No'
      row = OpenstudioStandards::Constructions.construction_set_row(standard, model, climate_zone,
                                                                    fallback_building_type, is_residential)
      if row.nil? && !fallback_building_type.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Constructions',
                           "No construction_sets row for building type #{fallback_building_type} under #{standard.template}. Every slot has to come from the construction spec.")
      end

      construction_set = OpenStudio::Model::DefaultConstructionSet.new(model)
      construction_set.setName(name || "#{standard.template} - #{climate_zone} - spec")
      groups = {
        construction_set: construction_set,
        exterior_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
        interior_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
        ground_surfaces: OpenStudio::Model::DefaultSurfaceConstructions.new(model),
        exterior_subsurfaces: OpenStudio::Model::DefaultSubSurfaceConstructions.new(model),
        interior_subsurfaces: OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
      }
      construction_set.setDefaultExteriorSurfaceConstructions(groups[:exterior_surfaces])
      construction_set.setDefaultInteriorSurfaceConstructions(groups[:interior_surfaces])
      construction_set.setDefaultGroundContactSurfaceConstructions(groups[:ground_surfaces])
      construction_set.setDefaultExteriorSubSurfaceConstructions(groups[:exterior_subsurfaces])
      construction_set.setDefaultInteriorSubSurfaceConstructions(groups[:interior_subsurfaces])

      sources = {}
      unset = []
      ASSEMBLY_SURFACES.each do |surface, (surface_type, group, setter)|
        surface_spec = surfaces[surface].is_a?(Hash) ? surfaces[surface] : {}
        construction_name = surface_spec[:construction]
        unless construction_name.nil?
          unless surface_spec[:construction_type].nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                               "#{surface} names both a construction and a construction_type. Using the pinned construction '#{construction_name}'.")
          end
          construction = resolve_construction(standard.model_add_construction(model, construction_name))
          if construction.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                               "No construction named '#{construction_name}' in the standards data. Leaving #{surface} unset.")
            unset << surface
          else
            groups[group].public_send(setter, construction)
            sources[surface] = 'pinned construction'
          end
          next
        end

        construction_type = surface_spec[:construction_type]
        source = 'surface entry' unless construction_type.nil?
        broadcast_field = BROADCAST_TYPES.key(surface)
        if construction_type.nil? && !broadcast_field.nil?
          construction_type = spec[broadcast_field]
          source = 'shorthand' unless construction_type.nil?
        end
        if construction_type.nil? && !row.nil?
          construction_type = row["#{surface}_standards_construction_type"]
          source = 'building type row' unless construction_type.nil?
        end

        building_category = surface_spec[:building_category] || spec[:building_category]
        building_category = row["#{surface}_building_category"] if building_category.nil? && !row.nil?
        if construction_type.nil? || building_category.nil?
          unset << surface
          next
        end

        construction = resolve_construction(
          standard.model_find_and_add_construction(model, climate_zone_set, surface_type,
                                                   construction_type, building_category)
        )
        if construction.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                             "No #{surface_type} construction found for type '#{construction_type}' and category '#{building_category}' in #{climate_zone_set}. Leaving #{surface} unset.")
          unset << surface
          next
        end
        groups[group].public_send(setter, construction)
        sources[surface] = source
      end

      NAMED_SURFACES.each do |surface, (group, setter)|
        surface_spec = surfaces[surface]
        construction_name = surface_spec.is_a?(Hash) ? surface_spec[:construction] : surface_spec
        source = 'surface entry' unless construction_name.nil?
        if construction_name.nil? && !row.nil?
          construction_name = row[surface.to_s]
          source = 'building type row' unless construction_name.nil?
        end
        if construction_name.nil?
          unset << surface
          next
        end

        construction = resolve_construction(standard.model_add_construction(model, construction_name))
        if construction.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                             "No construction named '#{construction_name}' in the standards data. Leaving #{surface} unset.")
          unset << surface
          next
        end
        groups[group].public_send(setter, construction)
        sources[surface] = source
      end

      sources.each { |surface, source| construction_set.additionalProperties.setFeature("#{surface} source", source) }
      unless unset.empty?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Constructions',
                           "Construction set '#{construction_set.name}' left #{unset.size} surface(s) unset, which fall back to the OpenStudio defaults: #{unset.join(', ')}.")
      end
      construction_set
    end

    # Determine whether a construction-set entry selects a space type.
    #
    # @param space_type [OpenStudio::Model::SpaceType] space type to test
    # @param entry [Hash] entry containing optional space_types and building_types selectors
    # @return [Boolean] true when the entry selects the space type
    def self.construction_set_entry_matches?(space_type, entry)
      names = Array(entry[:space_types]).map(&:to_s)
      unless names.empty?
        return true if names.include?('*')

        keys = []
        keys << space_type.standardsSpaceType.get if space_type.standardsSpaceType.is_initialized
        schedule_set = space_type.additionalProperties.getFeatureAsString('schedule_set')
        keys << schedule_set.get if schedule_set.is_initialized
        return true unless (names & keys).empty?
      end

      building_types = Array(entry[:building_types]).map(&:to_s)
      unless building_types.empty?
        return false unless space_type.standardsBuildingType.is_initialized
        return true if building_types.include?('*')
        return true if building_types.include?(space_type.standardsBuildingType.get)
      end
      false
    end

    # Merge a selected construction-set entry over the building default specification.
    #
    # @param default_spec [Hash, nil] building-level construction specification
    # @param entry [Hash] selected space-type construction-set entry
    # @return [Hash] merged construction specification without selector metadata
    def self.merge_construction_spec(default_spec, entry)
      merged = (default_spec || {}).merge(entry)
      merged.delete(:name)
      merged.delete(:space_types)
      merged.delete(:building_types)
      default_surfaces = (default_spec || {})[:surfaces]
      return merged unless default_surfaces.is_a?(Hash)

      merged[:surfaces] = default_surfaces.merge(entry[:surfaces].is_a?(Hash) ? entry[:surfaces] : {})
      merged
    end

    # Create a building construction set and assign optional sets to selected space types.
    #
    # @param model [OpenStudio::Model::Model] model receiving the construction sets
    # @param standard [Standard] standard used for construction lookups
    # @param climate_zone [String] climate zone identifier
    # @param constructions [Hash] construction specification with a default and optional sets
    # @param fallback_building_type [String, nil] building type used for unspecified slots
    # @param building_name [String, nil] label included in the generated set names
    # @return [OpenStudio::Model::DefaultConstructionSet, nil] building-level set, or nil on failure
    def self.assign_construction_sets(model, standard, climate_zone, constructions,
                                      fallback_building_type: nil,
                                      building_name: nil)
      constructions = symbolize_construction_spec(constructions)
      entries = constructions[:sets].is_a?(Array) ? constructions[:sets] : []
      default_spec = constructions[:default].is_a?(Hash) ? constructions[:default] : constructions.reject { |key, _| %i[default sets].include?(key) }
      default_spec = symbolize_construction_spec(default_spec)
      label = building_name || fallback_building_type
      building_set = create_construction_set(
        model, standard, climate_zone, default_spec,
        fallback_building_type: fallback_building_type,
        name: "#{standard.template} - #{climate_zone} - #{label}"
      )
      return nil if building_set.nil?

      model.getBuilding.setDefaultConstructionSet(building_set)
      entries.each_with_index do |entry, index|
        entry = symbolize_construction_spec(entry)
        matched = model.getSpaceTypes.sort.select { |space_type| construction_set_entry_matches?(space_type, entry) }
        entry_name = entry[:name] || "set #{index + 1}"
        if matched.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                             "Construction set '#{entry_name}' matched no space type in the model. Its selectors name space types or building types the model does not have.")
          next
        end

        matched = matched.reject do |space_type|
          next false unless space_type.defaultConstructionSet.is_initialized

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Constructions',
                             "Space type '#{space_type.name}' is already assigned construction set '#{space_type.defaultConstructionSet.get.name}'. Construction set '#{entry_name}' does not replace it.")
          true
        end
        next if matched.empty?

        set = create_construction_set(
          model, standard, climate_zone, merge_construction_spec(default_spec, entry),
          fallback_building_type: fallback_building_type,
          name: "#{standard.template} - #{climate_zone} - #{label} - #{entry_name}"
        )
        next if set.nil?

        matched.each { |space_type| space_type.setDefaultConstructionSet(set) }
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Constructions',
                           "Assigned construction set '#{set.name}' to #{matched.size} space type(s): #{matched.map { |space_type| space_type.name.to_s }.join(', ')}.")
      end
      building_set
    end

    # Unwrap construction lookups, which may return a construction or an optional construction.
    #
    # @param result [OpenStudio::Model::ConstructionBase, OpenStudio::Model::OptionalConstruction, nil] lookup result
    # @return [OpenStudio::Model::ConstructionBase, nil] construction, or nil when no result is available
    def self.resolve_construction(result)
      return nil if result.nil?
      return result unless result.respond_to?(:is_initialized)

      result.is_initialized ? result.get : nil
    end

    # Normalize top-level and surface-entry keys in a construction specification.
    #
    # @param spec [Hash, nil] construction specification with string or symbol keys
    # @return [Hash] specification with normalized symbol keys
    def self.symbolize_construction_spec(spec)
      return {} if spec.nil?

      out = spec.each_with_object({}) { |(key, value), hash| hash[key.to_sym] = value }
      return out unless out[:surfaces].is_a?(Hash)

      out[:surfaces] = out[:surfaces].each_with_object({}) do |(surface, value), hash|
        hash[surface.to_sym] = if value.is_a?(Hash)
                                 value.each_with_object({}) { |(key, item), nested| nested[key.to_sym] = item }
                               else
                                 value
                               end
      end
      out
    end
  end
end
