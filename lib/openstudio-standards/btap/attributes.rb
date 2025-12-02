# This file extends some of the OpenStudio classes to add some new methods
# and parameters for convenience. Additionally, it also houses methods
# involving the pre-processing of an OpenStudio model for shared use in one
# of BTAP's facilities, for now BTAP Costing and BTAP Carbon. Currently,
# this pre-processing only involves retrieving the correct constructions for
# envelopes.

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
    attr_reader :construction_set
    attr_reader :surfaces_hash
  end

  class OpenStudio::Model::Surface
    attr_reader :construction_hash # Stores the construction for this surface.
  end

  class OpenStudio::Model::SubSurface
    attr_reader :construction_hash # Same as the previous.
  end

  # Class for accessing and pre-processing model attributes.
  class Attributes
    attr_reader :model
    attr_reader :zones
    attr_reader :spaces
    attr_reader :surface_types
    
    # @param model    [OpenStudio::Model::Model]
    # @param standard [Standard]
    def initialize(model, standard)
      @model             = model
      @standard          = standard
      @costing_database  = CostingDatabase.instance

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
      @surface_type_tbd_map = {
        "ExteriorWall"       => :wall,
        "ExteriorRoof"       => :roof,
        "ExteriorFloor"      => :floor,
        "GroundContactWall"  => :wall,
        "GroundContactRoof"  => :roof,
        "GroundContactFloor" => :floor
      }

      @zones  = [] 
      @spaces = [] 

      self.compile_model
      self.compile_constructions(not @standard.tbd.nil?)
    end

    # Compile all the constructions associated with each surface and subsurface.
    #
    # @param use_tbd [Bool] Use TBD takeoffs for surfaces where available.
    def compile_constructions(use_tbd)
      takeoffs = @standard.tbd.tally[:takeoffs]
      @spaces.each do |space|
        @surface_types.each do |surface_type|
          space.surfaces_hash[surface_type].each do |surface|
            if takeoffs.has_key?(surface) and @surface_type_tbd_map.has_key?(surface_type)
              compile_construction_tbd(surface, @surface_type_tbd_map[surface_type])
            else
              puts "[BTAP Attributes] Surface takeoff for #{surface.handle} with surface type #{surface_type} unavailable, defaulting to legacy takeoff."
              compile_construction(surface)
            end
          end
        end
      end
    end

    # Get the construction for a given surface using the TBD-defined takeoffs.
    # 
    # @param surface          [OpenStudio::Model::Surface]
    # @param tbd_surface_type [String]
    def compile_construction_tbd(surface, tbd_surface_type)
      construction_set = @standard.tbd.costed_assembly(@standard,structure, , @standard.tbd.model[], :lp) # TODO: Need tbd.model[:perform] attribute in the cache
      surface.instance_variable_set(:@construction_set, construction_set)
    end

    # Get the construction for a given surface using legacy takeoffs.
    # 
    # @param surface [OpenStudio::Model::Surface]
    def compile_construction(surface)
      construction_set = @costing_database["raw"]["construction_sets"].select { |data|
        data["template"].to_s.gsub(/\s*/, "") == template_type               and
        data["building_type"].to_s.downcase   == building_type.to_s.downcase and
        data["space_type"].to_s.downcase      == space_type.to_s.downcase    and
        data["min_stories"].to_i              <= num_of_above_ground_stories and
        data["max_stories"].to_i              >= num_of_above_ground_stories
      }.first
      surface.instance_variable_set(:@construction_set, construction_set)

      if construction_set.nil?
        next
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
