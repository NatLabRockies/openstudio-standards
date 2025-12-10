# This file extends some of the OpenStudio classes to add some new methods
# and parameters for convenience. Additionally, it also houses methods
# involving the pre-processing of an OpenStudio model for shared use in one
# of BTAP's facilities, for now BTAP Costing and BTAP Carbon. Currently,
# this pre-processing involves retrieving the correct constructions for
# envelopes and a few attributes for thermal bridging.

require "openstudio"

module BTAP
  class OpenStudio::Model::Model
    def getThermalZonesSorted
      return @zones_sorted
    end

    def <<(zone) # Override the append operator to compile the sorted zones
      @zones_sorted << zone
    end
  end

  class OpenStudio::Model::ThermalZone
    def getSpacesSorted
      return @spaces_sorted
    end

    def <<(space) # Override the append operator to compile the sorted spaces
      @spaces_sorted << space
    end
  end

  class OpenStudio::Model::Space
    attr_reader :surfaces_hash
  end

  # For surfaces and subsurfaces, BTAP Costing requires a list of constructions
  # for each RSI value in order to perform a linear regression to best estimate
  # the respective cost and carbon emissions per surface. BTAP Carbon requires
  # only the construction with the closest RSI value since constructions
  # have to be calculated per-surface to account for window frame perimeters.
  # TODO: BTAP Carbon could use the same regression technique as BTAP Costing,
  # but that isn't implemented yet.
  class OpenStudio::Model::Surface
    attr_reader :rsi                       # [Float]
    attr_reader :btap_construction_closest # [BTAP::Construction]
    attr_reader :btap_constructions        # [Array[BTAP::Construction]]
  end

  class OpenStudio::Model::SubSurface
    attr_reader :rsi                       # [Float]
    attr_reader :btap_construction_closest # [BTAP::Construction]
    attr_reader :btap_constructions        # [Array[BTAP::Construction]]
  end

  # Wrapper class for construction parameters. Note the "cost"  parameter, these
  # aren't populated until costing is done. Carbon emissions aren't stored
  # per-construction since they vary per surface due to window perimeter
  # differences, and this class is stored as a reference in the Surface and
  # SubSurfaces classes.
  class Construction
    attr_reader   :name
    attr_reader   :id
    attr_reader   :description
    attr_reader   :type
    attr_reader   :id_layers
    attr_reader   :rsi
    attr_accessor :cost

    # @param name        [String]
    # @param description [String]
    # @param type        [String] Material type, either "opaque" or "glazing".
    # @param id_layers   [Array[Integer]]
    # @param rsi         [Float]
    # @param cost        [Float]
    # @param carbon      [Float]
    def initialize(name, id, description, type, id_layers, rsi)
      @name        = name
      @id          = id
      @description = description
      @type        = type
      @id_layers   = id_layers
      @rsi         = rsi
      @cost        = nil
    end

    # Fenestration-related accessor methods.
    # TODO: implement these
    def get_fenestration_type
    end
    def get_frame_material
    end
    def get_number_of_panes
    end
  end

  # Class for accessing and pre-processing model attributes.
  class Attributes
    attr_reader :model
    attr_reader :zones
    attr_reader :spaces
    attr_reader :surface_types
    attr_reader :surface_types_to_assemblies
    attr_reader :use_tbd
    
    # @param model    [OpenStudio::Model::Model]
    # @param standard [Standard]
    def initialize(model, standard)
      @model            = model
      @standard         = standard
      @costing_database = BTAPDatabase.instance

      # Surfaces considered for envelope costing and carbon.
      @surface_types = [ 
        "ExteriorWall",
        "ExteriorRoof",
        "ExteriorFloor",
        "ExteriorFixedWindow",
        "ExteriorOperableWindow",
        "ExteriorSkylight",
        "ExteriorTubularDaylightDiffuser",
        "ExteriorTubularDaylightDome",
        "ExteriorDoor",
        "ExteriorGlassDoor",
        "ExteriorOverheadDoor",
        "GroundContactWall",
        "GroundContactRoof",
        "GroundContactFloor"
      ]

      # Surface type map for converting between surface type strings and TBD
      # `stypes`.
      # TODO: This is a work-in-progress--most of the construction files
      # are not being used and of the constructions only a small subset. The
      # `costed_assembly` function in the TBD module needs to be updated as
      # such.
      @surface_type_tbd_map = {
        "ExteriorWall"  => :walls,
        "ExteriorRoof"  => :roofs,
        "ExteriorFloor" => :floors
      }

      @zones         = [] 
      @spaces        = [] 
      @constructions = {}

      @use_tbd = !(@standard.tbd.nil?)

      self.compile_model
      self.compile_constructions(@use_tbd)
    end

    # Helper method which retrieves all compiled constructions.
    def get_constructions
      return @constructions.values
    end

    # Compile all the constructions associated with each surface and subsurface.
    #
    # @param use_tbd [Bool] Use TBD takeoffs for surfaces where available.
    def compile_constructions(use_tbd)

      # Create a hash of surface types referencing construction type names.
      # These references are shared across all surfaces of the same type because
      # the `costed_assembly` method assigns assemblies according to building
      # categories.
      if use_tbd
        @surface_types_to_assemblies = @surface_type_tbd_map.keys.map { |surface_type| 
          [surface_type, @standard.tbd.costed_assembly(
            @standard.structure, 
            @surface_type_tbd_map[surface_type], 
            @standard.tbd.model[:perform])]}.to_h
      end

      @spaces.each do |space|
        @surface_types.each do |surface_type|
          space.surfaces_hash[surface_type].each do |surface|
            if @surface_type_tbd_map.has_key?(surface_type)
              compile_construction_tbd(surface, surface_type)
            else
              puts "[BTAP Attributes] Surface takeoff for #{surface.handle} " \
                   "with surface type #{surface_type} is unavailable."
            end
          end
        end
      end
    end

    # Get the RSI and constructions for each RSI value for a given surface
    # using the BTAP::Structure and BTAP::Bridging classes. The calculated RSI
    # and a reference to a wrapper class [BTAP::Construction] is assigned to
    # each surface.
    # TODO: If surface types always have the same constructions, this should be
    # refactored and separated to be simpler.
    # 
    # @param surface      [OpenStudio::Model::Surface]
    # @param surface_type [String] One of @surface_types
    def compile_construction_tbd(surface, surface_type)
      tbd_surface_type          = @surface_type_tbd_map[surface_type]
      construction_name         = @surface_types_to_assemblies[surface_type]
      construction_candidates   = @costing_database["constructions"][tbd_surface_type.to_s][construction_name]["rsi"]
      surface_rsi               = TBD.rsi(surface.construction.get.to_LayeredConstruction.get, surface.filmResistance)
      closest_rsi               = construction_candidates.keys.map(&:to_f).min_by { |rsi| 
                                    (surface_rsi - rsi).abs }.to_s
      btap_constructions        = []
      construction_hash_closest = construction_candidates[closest_rsi]

      # Initialize the construction with the closest RSI if it doesn't exist
      # yet.
      unless @constructions.has_key?(construction_hash_closest["id"])
        @constructions[construction_hash_closest["id"]] = BTAP::Construction.new(
          construction_name,
          construction_hash_closest["id"],
          construction_hash_closest["description"],
          construction_hash_closest["type"],
          construction_hash_closest["id_layers"],
          closest_rsi)

        btap_construction_closest = @constructions[construction_hash_closest["id"]]
      end

      construction_candidates.each do |construction_rsi, construction_hash|

        # Hash a list of constructions by their ID. If a construction was
        # already initialized, assign the reference of the already created one.
        unless @constructions.has_key?(construction_hash["id"])
          @constructions[construction_hash["id"]] = BTAP::Construction.new(
            construction_name,
            construction_hash["id"],
            construction_hash["description"],
            construction_hash["type"],
            construction_hash["id_layers"],
            construction_rsi)
        end
        btap_constructions << @constructions[construction_hash["id"]]
      end

      surface.instance_variable_set(:@btap_construction_closest, btap_construction_closest)
      surface.instance_variable_set(:@btap_constructions, btap_constructions)
      surface.instance_variable_set(:@rsi, surface_rsi)
    end

    # Get the construction for a given surface using legacy takeoffs. Currently
    # not being used.
    #
    # @param space   [OpenStudio::Model::Space]
    # @param surface [OpenStudio::Model::Surface]
    def compile_construction_legacy(space, surface)
      construction_set = @costing_database["raw"]["construction_sets"].select { |data|
        data["template"].to_s.gsub(/\s*/, "") == @standard.template                                          and
        data["building_type"].to_s.downcase   == space.spaceType.get.standardsBuildingType.to_s.downcase     and
        data["space_type"].to_s.downcase      == space.spaceType.get.standardsSpaceType.to_s.downcase        and
        data["min_stories"].to_i              <= @model.getBuilding.standardsNumberOfAboveGroundStories.to_i and
        data["max_stories"].to_i              >= @model.getBuilding.standardsNumberOfAboveGroundStories.to_i
      }.first
      space.instance_variable_set(:@construction_set, construction_set)

      if construction_set.nil?
        return
      end

      @surface_types.each do |surface_type|
        space.surfaces_hash[surface_type].each do |surface|

          # Search for a matching opaque or glazing construction and append the type to the hash.
          construction_hash = @costing_database["raw"]["constructions_opaque"].find { |construction|
            construction["construction_type_name"] == construction_set[surface_type]
          }
          if not construction_hash.nil?
            construction_hash["type"] = "opaque"
            surface.instance_variable_set(:@construction_hash, construction_hash)
          else
            construction_hash = @costing_database["raw"]["constructions_glazing"].find { |construction|
              construction["construction_type_name"] == construction_set[surface_type]
            }
            if not construction_hash.nil?
              construction_hash["type"] = "glazing"
              surface.instance_variable_set(:@construction_hash, construction_hash)
            end
          end
        end
      end
    end

    # Compile all the pertinent OpenStudio-related data into the data structures
    # of this class while also appending to the exisitng OpenStudio ones. This
    # adds accessors for zones, spaces, and surfaces while keeping them sorted
    # for future accesses.
    def compile_model
      template_type = @standard.template
      num_of_above_ground_stories = @model.getBuilding.standardsNumberOfAboveGroundStories.to_i
      
      # Iterate through the data structures while also saving their sorted order later for reference.
      @model.instance_variable_set(:@zones_sorted, [])

      @model.getThermalZones.sort.each do |zone|
        @model << zone
        @zones << zone
        zone.instance_variable_set(:@spaces_sorted, [])

        zone.spaces.sort.each do |space|
          if space.spaceType.empty? or 
             space.spaceType.get.standardsSpaceType.empty? or 
             space.spaceType.get.standardsBuildingType.empty?
            raise (
              "standards Space type and building type is not defined for space:#{space.name.get}. Skipping this space.")
          end
          zone    << space
          @spaces << space
          
          surfaces_hash = {}

          # Exterior
          exterior_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, "Outdoors")
          surfaces_hash["ExteriorWall"]  = BTAP::Geometry::Surfaces::filter_by_surface_types(exterior_surfaces, "Wall").sort
          surfaces_hash["ExteriorRoof"]  = BTAP::Geometry::Surfaces::filter_by_surface_types(exterior_surfaces, "RoofCeiling").sort
          surfaces_hash["ExteriorFloor"] = BTAP::Geometry::Surfaces::filter_by_surface_types(exterior_surfaces, "Floor").sort

          # Exterior Subsurfaces
          exterior_subsurfaces = exterior_surfaces.flat_map(&:subSurfaces)
          surfaces_hash["ExteriorFixedWindow"]             = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["FixedWindow"]).sort
          surfaces_hash["ExteriorOperableWindow"]          = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["OperableWindow"]).sort
          surfaces_hash["ExteriorSkylight"]                = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["Skylight"]).sort
          surfaces_hash["ExteriorTubularDaylightDiffuser"] = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["TubularDaylightDiffuser"]).sort
          surfaces_hash["ExteriorTubularDaylightDome"]     = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["TubularDaylightDome"]).sort
          surfaces_hash["ExteriorDoor"]                    = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["Door"]).sort
          surfaces_hash["ExteriorGlassDoor"]               = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["GlassDoor"]).sort
          surfaces_hash["ExteriorOverheadDoor"]            = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(exterior_subsurfaces, ["OverheadDoor"]).sort

          # Ground Surfaces
          ground_surfaces  = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, "Ground")
          ground_surfaces += BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, "Foundation")
          surfaces_hash["GroundContactWall"]  = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "Wall").sort
          surfaces_hash["GroundContactRoof"]  = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "RoofCeiling").sort
          surfaces_hash["GroundContactFloor"] = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "Floor").sort

          space.instance_variable_set(:@surfaces_hash, surfaces_hash)
        end
      end
    end
  end
end
