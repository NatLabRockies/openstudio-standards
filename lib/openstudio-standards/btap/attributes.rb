# BTAP Attributes: Currently stores model attributes related to envelopes. 
require "openstudio"

module BTAP

  # Class modifications to simplyify post-analysis functions
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

    def <<(space)
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

  class Attributes
    attr_reader :model
    attr_reader :zones
    attr_reader :spaces
    attr_reader :surface_types
    
    def initialize(model, prototype_creator)
      @model             = model
      @prototype_creator = prototype_creator
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

      @zones  = [] 
      @spaces = [] 

      self.compile
    end

    # Compile all the pertinent data into the data structures of this class while also appending
    # to the exisitng OpenStudio ones. 
    def compile
      template_type = @prototype_creator.template
      num_of_above_ground_stories = @model.getBuilding.standardsNumberOfAboveGroundStories.to_i
      
      # Iterate through the data structures while also saving their sorted order later for reference.
      @model.instance_variable_set(:@zones_sorted, [])

      @model.getThermalZones.sort.each do |zone|
        @model << zone
        @zones << zone
        zone.instance_variable_set(:@spaces_sorted, [])

        zone.spaces.sort.each do |space|
          if space.spaceType.empty? or space.spaceType.get.standardsSpaceType.empty? or space.spaceType.get.standardsBuildingType.empty?
            raise ("standards Space type and building type is not defined for space:#{space.name.get}. Skipping this space.")
          end
          zone    << space
          @spaces << space

          space_type    = space.spaceType.get.standardsSpaceType
          building_type = space.spaceType.get.standardsBuildingType

          # Compile a list of construction sets for each space.
          construction_set = @costing_database["raw"]["construction_sets"].select { |data|
            data["template"].to_s.gsub(/\s*/, "") == template_type               and
            data["building_type"].to_s.downcase   == building_type.to_s.downcase and
            data["space_type"].to_s.downcase      == space_type.to_s.downcase    and
            data["min_stories"].to_i              <= num_of_above_ground_stories and
            data["max_stories"].to_i              >= num_of_above_ground_stories
          }.first
          space.instance_variable_set(:@construction_set, construction_set)
          
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
      end
    end
  end
end
