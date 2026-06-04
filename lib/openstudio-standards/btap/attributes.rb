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
  # for each U-value in order to perform a linear regression to best estimate
  # the respective cost and carbon emissions per surface. Also, store the
  # R-value of each surface.
  class OpenStudio::Model::Surface
    attr_reader :rsi                # [Float]
    attr_reader :btap_constructions # [Array[Hash]]
  end

  class OpenStudio::Model::SubSurface
    attr_reader :rsi                # [Float]
    attr_reader :btap_constructions # [Array[Hash]]
  end

  # Class for accessing and pre-processing model attributes.
  class Attributes
    attr_reader :model                  # [OpenStudio::Model::Model]
    attr_reader :zones                  # [Array[OpenStudio::Model::Zone]]
    attr_reader :spaces                 # [Array[OpenStudio::Model::Space]]
    attr_reader :surface_types          # [Array]
    attr_reader :use_tbd                # [Boolean]
    attr_reader :tbd_edge_tallies       # [Hash]
    attr_reader :surface_types_to_snake # [Hash]

    # @param model                [OpenStudio::Model::Model]
    # @param standard             [Standard]
    # @param use_tbd              [Boolean]
    # @param building_performance [String]
    # @param tbd_edge_tallies     [Hash]
    def initialize(model, standard, use_tbd, building_performance, tbd_edge_tallies)
      @model                = model
      @standard             = standard
      @use_tbd              = use_tbd
      @building_performance = building_performance
      @tbd_edge_tallies     = tbd_edge_tallies
      @costing_database     = BTAPDatabase.instance

      # Surfaces considered for envelope costing and carbon.
      @surface_types = [
        "ExteriorWall",
        "ExteriorRoof",
        "ExteriorFloor",
        "InterzonalRoof",
        "InterzonalSkylightWalls",
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

      # Formatted dictionary of surface types from camel case to snake case
      # for neat reporting.
      @surface_types_to_snake = @surface_types.map { |type|
        [type, type.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase] }.to_h

      # Surface type map for converting between surface type strings and the
      # `costed_assembly()` `surface_type` parameter.
      @surface_types_to_costed_assembly = {
        "ExteriorWall"            => :walls,
        "ExteriorRoof"            => :roofs,
        "ExteriorFloor"           => :floors,
        "InterzonalRoof"          => :roofs,
        "InterzonalSkylightWalls" => :walls
      }

      # TODO: Temporary default constructions for underatable surface types.
      @default_surface_constructions_by_type = {
        "ExteriorFixedWindow"             => "BTAP-ExteriorWindow-FixedWindow-1",
        "ExteriorOperableWindow"          => "BTAP-ExteriorWindow-OperableWindow-5b",
        "ExteriorSkylight"                => "BTAP-Skylight-2",
        "ExteriorTubularDaylightDiffuser" => "BTAP-Skylight-2",
        "ExteriorTubularDaylightDome"     => "BTAP-Skylight-2",
        "ExteriorDoor"                    => "BTAP-ExteriorDoor-Metal-1",
        "ExteriorGlassDoor"               => "BTAP-ExteriorWindow-GlazedDoor-4",
        "ExteriorOverheadDoor"            => "BTAP-ExteriorOverheadDoor-Metal-1",
        "GroundContactWall"               => "BTAP-GroundContactWall-Mass-2",
        "GroundContactRoof"               => "BTAP-GroundContactRoof-Mass-2",
        "GroundContactFloor"              => "BTAP-GroundContactFloor-Unheated-1"
      }

      @surface_types_to_construction_sheet = {
        "ExteriorWall"                    => "wall",
        "ExteriorRoof"                    => "roof",
        "ExteriorFloor"                   => "floor",
        "InterzonalRoof"                  => "roof",
        "InterzonalSkylightWalls"         => "wall",
        "ExteriorFixedWindow"             => "window",
        "ExteriorOperableWindow"          => "window",
        "ExteriorSkylight"                => "skylight",
        "ExteriorTubularDaylightDiffuser" => "skylight",
        "ExteriorTubularDaylightDome"     => "skylight",
        "ExteriorDoor"                    => "door",
        "ExteriorGlassDoor"               => "door_glass",
        "ExteriorOverheadDoor"            => "door",
        "GroundContactWall"               => "bg_wall",
        "GroundContactRoof"               => "bg_roof",
        "GroundContactFloor"              => "slab"
      }

      @glazing_surface_types = Set.new(["door_glass", "skylight", "window"])

      @zones         = []
      @spaces        = []
      @constructions = {}


      self.compile_model
      self.compile_constructions
    end

    # Helper method which retrieves all compiled constructions.
    def get_constructions
      return @constructions.values
    end

    # Compile all the constructions associated with each surface and subsurface.
    #
    # @param use_tbd [Bool] Use TBD takeoffs for surfaces where available.
    def compile_constructions

      # Create a hash of surface types referencing construction type names.
      # These references are shared across all surfaces of the same type because
      # the `costed_assembly` method assigns assemblies according to building
      # categories.
      @surface_types_to_assembly_names = @surface_types.map { |surface_type|
        if @surface_types_to_costed_assembly.has_key?(surface_type)
          assembly = BTAP::Constructions.costed_assembly(
            @standard.structure,
            @surface_types_to_costed_assembly[surface_type],
            @building_performance)
        else
          assembly = @default_surface_constructions_by_type[surface_type]
        end
        [surface_type, assembly] }.to_h

      @spaces.each do |space|
        @surface_types.each do |surface_type|
          space.surfaces_hash[surface_type].each do |surface|
            compile_surface_construction(surface, surface_type)
          end
        end
      end
    end

    # Get the constructions for each RSI value for a given surface using the
    # BTAP::Structure and BTAP::Bridging classes. A reference to a hash and
    # a list of hashes containing construction attributes is assigned to each
    # surface.
    #
    # @param surface      [OpenStudio::Model::Surface]
    # @param surface_type [String] One of @surface_types
    def compile_surface_construction(surface, surface_type)

      # TODO: Currently we don't have the right assemblies to properly cost
      # skylight well walls, so don't cost them for now. Wall constructions
      # aren't suitable.
      return if surface_type == "InterzonalSkylightWalls"

      construction_sheet = @surface_types_to_construction_sheet[surface_type]
      construction_name  = @surface_types_to_assembly_names[surface_type]
      is_opaque          = !(@glazing_surface_types.include?(construction_sheet))
      btap_constructions = []

      # Construction database entries use U-factors, convert them to R-factors.
      construction_candidates = \
        @costing_database["constructions"][construction_sheet][construction_name]["usi"].transform_keys { |usi|
          1 / usi.to_f }

      # Process each construction into a hash. This hash will also store the
      # cost for the construction in `envelope_costing.rb`. Carbon emissions
      # aren't stored per-construction since they vary per surface due to
      # window perimeter differences, and this class is stored as a reference
      # in the Surface and SubSurfaces classes. Here are a list of parameters
      # of the hash:
      #
      # @param name        [String]
      # @param description [String]
      # @param type        [String] Material type, either "opaque" or "glazing".
      # @param id_layers   [Array[Integer]]
      # @param rsi         [Float]
      # @param fenestration_number_of_panes [String] ExteriorWindow only.
      # @param frame_material               [String] ExteriorWindow only.
      # @param fenestration_type            [String] ExteriorWindow only.
      construction_candidates.each do |construction_rsi, construction_hash|

        # Store all candidate constructions for reference when doing linear
        # regression for construction takeoffs.
        unless @constructions.has_key?(construction_hash["id"])
          construction_hash["name"]               = construction_name
          construction_hash["rsi"]                = construction_rsi
          @constructions[construction_hash["id"]] = construction_hash
        end

        btap_constructions << @constructions[construction_hash["id"]]
      end

      surface.instance_variable_set(:@btap_constructions, btap_constructions)
    end

    # Compile all the pertinent OpenStudio-related data into the data structures
    # of this class while also appending to the exisitng OpenStudio ones. This
    # adds accessors for zones, spaces, and surfaces while keeping them sorted
    # for future accesses. Also, store the RSI for each surface since retrieving
    # them is different for each category of surfaces.
    def compile_model

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
            raise ("Error: Space type not defined for #{space.name.get}")
          end
          zone    << space
          @spaces << space
          space.instance_variable_set(:@surfaces_hash, {})
          space.surfaces_hash["InterzonalRoof"]          = []
          space.surfaces_hash["InterzonalSkylightWalls"] = []
        end
      end

      # The following surfaces are the ones considered for costing/carbon
      # analysis. Filter them each into categories by boundary condition and
      # store their RSI as an instance variable for future reference.

      @spaces.each do |space|
        # Exterior Surfaces
        exterior_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, "Outdoors")
        space.surfaces_hash["ExteriorWall"] = BTAP::Geometry::Surfaces::filter_by_surface_types(
          exterior_surfaces, "Wall").sort

        # Interzonal Surfaces
        # In models with attics, roofs and their overhanging floors may be
        # unconditioned and as a result will not be considered for further
        # analysis. However, attic floors and skylight well walls will be
        # insulated and these surfaces will need to be properly categorized.
        # Since these are unconditioned and unaffected by TBD, get the mirrored
        # surface of these surfaces via `adjacentSurface` which is conditioned.
        # TODO: Eventually crawlspaces should also be considered, however they
        # are not present in any of the NECB template buildings.
        if space.additionalProperties.getFeatureAsString("space_conditioning_category").get == "unconditioned"
          space.surfaces_hash["ExteriorRoof"] = []
          space.surfaces_hash["ExteriorFloor"] = []

          # Roofs with overhangs for example in the SmallOffice prototype
          # don't have adjacent surfaces, so make sure the adjacentSurface for
          # interzonal roofs are initialized.
          interzonal_roof_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(
          space.surfaces, "Floor").sort.map { |surface| surface.adjacentSurface.get if
            surface.adjacentSurface.is_initialized }.filter { |surface| not surface.nil? }
          interzonal_skylight_wall_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(
          space.surfaces, "Wall").sort.map { |surface| surface.adjacentSurface.get }

          # Since the mirrored surface is used, the space type will likely be
          # different, so match the space type correctly.
          interzonal_roof_surfaces.each do |surface|
            matched_space = @spaces.find { |matching_space| surface.space.get == matching_space }
            matched_space.surfaces_hash["InterzonalRoof"] << surface
            surface.instance_variable_set(:@rsi, get_correct_rsi(surface))
          end

          interzonal_skylight_wall_surfaces.each do |surface|
            matched_space = @spaces.find { |matching_space| surface.space.get == matching_space }
            matched_space.surfaces_hash["InterzonalSkylightWalls"] << surface
            surface.instance_variable_set(:@rsi, get_correct_rsi(surface))
          end
        else

          # Only store roofs and floors if they are conditioned by assessing the
          # additional property above.
          space.surfaces_hash["ExteriorRoof"] = BTAP::Geometry::Surfaces::filter_by_surface_types(
            exterior_surfaces, "RoofCeiling").sort
          space.surfaces_hash["ExteriorFloor"] = BTAP::Geometry::Surfaces::filter_by_surface_types(
            exterior_surfaces, "Floor").sort
        end

        exterior_surfaces.each do |surface|
          surface.instance_variable_set(:@rsi, get_correct_rsi(surface))
        end

        # Exterior Subsurfaces
        exterior_subsurfaces = exterior_surfaces.flat_map(&:subSurfaces)
        space.surfaces_hash["ExteriorFixedWindow"]             = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["FixedWindow"]).sort
        space.surfaces_hash["ExteriorOperableWindow"]          = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["OperableWindow"]).sort
        space.surfaces_hash["ExteriorSkylight"]                = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["Skylight"]).sort
        space.surfaces_hash["ExteriorTubularDaylightDiffuser"] = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["TubularDaylightDiffuser"]).sort
        space.surfaces_hash["ExteriorTubularDaylightDome"]     = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["TubularDaylightDome"]).sort
        space.surfaces_hash["ExteriorDoor"]                    = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["Door"]).sort
        space.surfaces_hash["ExteriorGlassDoor"]               = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["GlassDoor"]).sort
        space.surfaces_hash["ExteriorOverheadDoor"]            = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(
          exterior_subsurfaces, ["OverheadDoor"]).sort
        exterior_subsurfaces.each do |surface|
          surface.instance_variable_set(:@rsi, TBD.rsi(surface.construction.get.to_LayeredConstruction.get))
        end

        # Ground Surfaces
        ground_surfaces  = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, "Ground")
        ground_surfaces += BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, "Foundation")
        space.surfaces_hash["GroundContactWall"]  = BTAP::Geometry::Surfaces::filter_by_surface_types(
          ground_surfaces, "Wall").sort
        space.surfaces_hash["GroundContactRoof"]  = BTAP::Geometry::Surfaces::filter_by_surface_types(
          ground_surfaces, "RoofCeiling").sort
        space.surfaces_hash["GroundContactFloor"] = BTAP::Geometry::Surfaces::filter_by_surface_types(
          ground_surfaces, "Floor").sort
        ground_surfaces.each do |surface|
          surface.instance_variable_set(:@rsi, TBD.rsi(
            surface.construction.get.to_LayeredConstruction.get, surface.filmResistance))
        end
      end
    end

    # Helper method for `compile_model()`. Whether TBD is enabled or not affects
    # the way the U-value is retrieved for exterior and interzonal surfaces.
    # If enabled, use the additional property and if not, calculate it with the
    # TBD.rsi class method.
    #
    # @param surface [OpenStudio::Model::Surface]
    # @return [Float] The RSI for the surface.
    def get_correct_rsi(surface)

      # Uninsulated surfaces are not derated by TBD. These surfaces will not
      # have a stored U-value. In those cases, use the fallback method.
      if @use_tbd and surface.additionalProperties.getFeatureAsDouble("uprated_Uo").is_initialized
        return 1 / surface.additionalProperties.getFeatureAsDouble("uprated_Uo").get
      else
        return TBD.rsi(surface.construction.get.to_LayeredConstruction.get, surface.filmResistance)
      end
    end
  end
end
