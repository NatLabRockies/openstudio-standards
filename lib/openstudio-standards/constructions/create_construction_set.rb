module OpenstudioStandards
  # The Constructions module provides methods to create, modify, and get information about constructions
  module Constructions
    # @!group Create Construction Set
    # Methods to build a default construction set from named construction types rather than from
    # a building type lookup.

    # Assembly-lookup surfaces, whose construction comes from the standards construction
    # properties data. Each entry is [intended surface type, the group it belongs to, the setter
    # on that group]. These are the surfaces where a construction type and a building category
    # select an assembly; each also accepts a construction name pinned directly.
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

    # Named-construction surfaces, whose construction is a construction name looked up
    # directly. Each entry is [the group it belongs to, the setter on that group].
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

    # Top-level shorthand fields that fill a surface's construction type when the surface
    # entry does not name its own.
    BROADCAST_TYPES = {
      exterior_wall_type: :exterior_wall,
      exterior_roof_type: :exterior_roof,
      exterior_floor_type: :exterior_floor
    }.freeze

    # Find the construction_sets row a building type would resolve to.
    #
    # This is the same lookup model_add_construction_set does, exposed so a spec-driven set can
    # fall back to it slot by slot.
    #
    # @param standard [Standard] a Standard object
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param climate_zone [String] climate zone
    # @param building_type [String, nil] standards building type
    # @param is_residential [String] 'Yes' or 'No'
    # @return [Hash, nil] the construction_sets row, or nil where the building type has none
    def self.construction_set_row(standard, model, climate_zone, building_type, is_residential)
      return nil if building_type.nil?

      climate_zone_set = standard.model_find_climate_zone_set(model, climate_zone)
      return nil unless climate_zone_set

      keys = { 'template' => standard.template, 'climate_zone_set' => climate_zone_set,
               'building_type' => building_type, 'space_type' => nil }
      standard.model_find_object(standard.standards_data['construction_sets'], keys.merge('is_residential' => is_residential)) ||
        standard.model_find_object(standard.standards_data['construction_sets'], keys)
    end

    # Build a default construction set from a construction spec, falling back to a building type's
    # construction_sets row for anything the spec does not name.
    #
    # model_add_construction_set reads a row keyed on (template, climate zone set, building type)
    # and does nothing with it but call model_find_and_add_construction once per surface slot. The
    # row carries no assembly properties of its own -- those live in construction_properties, keyed
    # on the construction type and building category that the row merely selects. Naming those
    # directly reaches the same assemblies without going through the building type at all, which is
    # what lets a model be built under a template whose construction_sets table has no row for its
    # building type.
    #
    # Resolution is per field, in this order:
    #   1. spec[:surfaces][<surface>], the explicit per-surface value. A :construction pins a
    #      named construction directly; a :construction_type resolves an assembly.
    #   2. the shorthand fields: building_category, exterior_wall_type, exterior_roof_type,
    #      exterior_floor_type
    #   3. the fallback building type's row, where one was found
    #   4. nothing, and the surface is left unset
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a Standard object, for the construction properties lookups
    # @param climate_zone [String] climate zone
    # @param spec [Hash] the construction spec
    # @param fallback_building_type [String, nil] building type whose row fills in unnamed surfaces
    # @param name [String, nil] name for the construction set
    # @return [OpenStudio::Model::DefaultConstructionSet, nil] the set, or nil if it could not be built
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

      # Which source supplied each surface, stamped on the set as additional properties so
      # "why is this wall R-11?" is answered by reading '<surface> source' off the set rather
      # than re-deriving the resolution order by hand.
      sources = {}
      unset = []
      ASSEMBLY_SURFACES.each do |surface, (surface_type, group, setter)|
        surface_spec = surfaces[surface].is_a?(Hash) ? surfaces[surface] : {}
        broadcast_field = BROADCAST_TYPES.key(surface)

        # A pinned construction name wins over an assembly lookup. Spec validation rejects an
        # entry carrying both; a direct caller who passes both is warned and gets the pin,
        # which is the more specific statement of intent.
        construction_name = surface_spec[:construction]
        unless construction_name.nil?
          unless surface_spec[:construction_type].nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                               "#{surface} names both a construction and a construction_type. Using the pinned construction '#{construction_name}'.")
          end
          construction = OpenstudioStandards::Constructions.resolve_construction(standard.model_add_construction(model, construction_name))
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

        construction = OpenstudioStandards::Constructions.resolve_construction(
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

        construction = OpenstudioStandards::Constructions.resolve_construction(standard.model_add_construction(model, construction_name))
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

    # Whether a construction set entry's selectors pick out this space type.
    #
    # space_types matches the way every override family matches: against the space type's
    # schedule set name, its standards space type, or the '*' wildcard. building_types matches
    # the standards building type, which is how a mixed-use bar built from bldg_type_a..d keeps
    # its parts apart.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @param entry [Hash] a construction set entry with symbol keys
    # @return [Boolean] true where the entry applies to this space type
    def self.construction_set_entry_matches?(space_type, entry)
      names = Array(entry[:space_types]).map(&:to_s)
      unless names.empty?
        return true if names.include?('*')

        keys = []
        keys << space_type.standardsSpaceType.get if space_type.standardsSpaceType.is_initialized
        if space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized
          keys << space_type.additionalProperties.getFeatureAsString('schedule_set').get
        end
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

    # Merge a construction set entry over the default construction spec.
    #
    # A mixed-use building states only what differs -- a residential tower's wall type and
    # category -- and takes the other twenty-odd surfaces from the default, so no entry has to
    # restate the whole envelope.
    #
    # @param default_spec [Hash] the default construction spec, with symbol keys
    # @param entry [Hash] a construction set entry, with symbol keys
    # @return [Hash] the merged spec
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

    # Build the model's construction sets and assign them, one to the building and one to each
    # collection of space types that differs from it.
    #
    # Constructions resolve up a hierarchy -- space, space type, building story, building -- so a
    # set on a space type governs the surfaces of its spaces and the building's set governs
    # everything else. That is how a mixed-use building carries more than one envelope, and it is
    # what the DOE prototype builder has always done; create_typical only ever set the building
    # level, so a retail podium and the apartments above it got the same walls.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a Standard object
    # @param climate_zone [String] climate zone
    # @param constructions [Hash] the constructions section: either a bare construction spec, or
    #   a hash with a `default` spec and a `sets` array of entries carrying selectors
    # @param fallback_building_type [String, nil] building type whose construction_sets row fills
    #   in anything the spec leaves unnamed
    # @param building_name [String, nil] label used in the set names
    # @return [OpenStudio::Model::DefaultConstructionSet, nil] the building's set, or nil on failure
    def self.assign_construction_sets(model, standard, climate_zone, constructions,
                                      fallback_building_type: nil,
                                      building_name: nil)
      constructions = OpenstudioStandards::Constructions.symbolize_construction_spec(constructions)
      entries = constructions[:sets].is_a?(Array) ? constructions[:sets] : []
      default_spec = constructions[:default].is_a?(Hash) ? constructions[:default] : constructions.reject { |k, _| [:default, :sets].include?(k) }
      default_spec = OpenstudioStandards::Constructions.symbolize_construction_spec(default_spec)
      label = building_name || fallback_building_type

      building_set = OpenstudioStandards::Constructions.create_construction_set(
        model, standard, climate_zone, default_spec,
        fallback_building_type: fallback_building_type,
        name: "#{standard.template} - #{climate_zone} - #{label}"
      )
      return nil if building_set.nil?

      model.getBuilding.setDefaultConstructionSet(building_set)

      entries.each_with_index do |entry, index|
        entry = OpenstudioStandards::Constructions.symbolize_construction_spec(entry)
        matched = model.getSpaceTypes.sort.select do |space_type|
          OpenstudioStandards::Constructions.construction_set_entry_matches?(space_type, entry)
        end
        entry_name = entry[:name] || "set #{index + 1}"

        if matched.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Constructions',
                             "Construction set '#{entry_name}' matched no space type in the model. Its selectors name space types or building types the model does not have.")
          next
        end

        # A space type already claimed by an earlier entry keeps it, so the order of `sets` is the
        # precedence order rather than whichever entry happens to be evaluated last.
        matched = matched.reject do |space_type|
          next false unless space_type.defaultConstructionSet.is_initialized

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Constructions',
                             "Space type '#{space_type.name}' is already assigned construction set '#{space_type.defaultConstructionSet.get.name}'. Construction set '#{entry_name}' does not replace it.")
          true
        end
        next if matched.empty?

        set = OpenstudioStandards::Constructions.create_construction_set(
          model, standard, climate_zone,
          OpenstudioStandards::Constructions.merge_construction_spec(default_spec, entry),
          fallback_building_type: fallback_building_type,
          name: "#{standard.template} - #{climate_zone} - #{label} - #{entry_name}"
        )
        next if set.nil?

        matched.each { |space_type| space_type.setDefaultConstructionSet(set) }
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Constructions',
                           "Assigned construction set '#{set.name}' to #{matched.size} space type(s): #{matched.map { |st| st.name.to_s }.join(', ')}.")
      end

      building_set
    end

    # Unwrap what the standards construction lookups return, which is a construction, an optional
    # holding one, or an empty optional where the data had no match.
    #
    # @param result [OpenStudio::Model::ConstructionBase, OpenStudio::Model::OptionalConstruction, nil]
    # @return [OpenStudio::Model::ConstructionBase, nil] the construction, or nil where there was none
    def self.resolve_construction(result)
      return nil if result.nil?
      return result unless result.respond_to?(:is_initialized)

      result.is_initialized ? result.get : nil
    end

    # Normalize a construction spec's keys to symbols, one level into surfaces.
    #
    # @param spec [Hash] a construction spec with string or symbol keys
    # @return [Hash] the spec with symbol keys
    def self.symbolize_construction_spec(spec)
      return {} if spec.nil?

      out = spec.each_with_object({}) { |(key, value), hash| hash[key.to_sym] = value }
      return out unless out[:surfaces].is_a?(Hash)

      out[:surfaces] = out[:surfaces].each_with_object({}) do |(surface, value), hash|
        hash[surface.to_sym] = value.is_a?(Hash) ? value.each_with_object({}) { |(k, v), h| h[k.to_sym] = v } : value
      end
      out
    end
  end
end
