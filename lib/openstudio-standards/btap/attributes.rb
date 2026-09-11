# BTAP Attributes
#
# This file extends some of the OpenStudio classes to add some new methods
# and parameters for convenience. Additionally, it also houses methods
# involving the pre-processing of an OpenStudio model for shared use in one
# of BTAP's facilities, for now BTAP Costing and BTAP Carbon. Currently,
# this pre-processing involves retrieving the correct constructions for
# envelopes and a few attributes for thermal bridging.

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
  # TODO: Remove
  class OpenStudio::Model::Surface
    attr_reader :rsi                # [Float]
    attr_reader :btap_constructions # [Array[Hash]]
  end

  # TODO: Remove
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
    attr_reader :constructions          # [Hash]
    attr_reader :surface_types_to_assembly_tallies # [Hash]

    # @param model                [OpenStudio::Model::Model]
    # @param standard             [Standard]
    # @param use_tbd              [Boolean]
    # @param building_performance [String]
    # @param tbd_edge_tallies     [Hash]
    def initialize(model:, standard:, use_tbd:, building_performance:, tbd_edge_tallies:)

      @model                = model
      @standard             = standard
      @use_tbd              = use_tbd
      @building_performance = building_performance
      @tbd_edge_tallies     = tbd_edge_tallies
      @costing_database     = Database.instance

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
      @surface_types_to_assembly_names = {
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

      # Copy of the keys of the initial hash containing only underatable surface
      # types. The "GroundContactFloor" has additional properties defined so
      # it's removed.
      @underatable_surface_types = @surface_types_to_assembly_names.keys.to_set.filter! { |surface_type|
        surface_type != "GroundContactFloor" }

      @surface_types_to_envelope_type = {
        "ExteriorWall"                    => "wall",
        "ExteriorRoof"                    => "roof",
        "ExteriorFloor"                   => "floor",
        "InterzonalRoof"                  => "roof",

        # TODO: Although we don't have specific constructions on interzonal
        # skylight walls, using external wall constructions is better than
        # ignoring them.
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

      # Store area, cost, and carbon emission tallies of assemblies by surface
      # type, stored as hashes as some surface types may have different
      # assemblies.
      @surface_types_to_assembly_tallies = @surface_types.to_h { |surface_type| [surface_type, {}] }

      @zones         = []
      @spaces        = []

      # Constructions which will be considered in costing/carbon calculation.
      # Member attributes generated in this hash:
      # TODO: fix this incorrect
      # name        [String]
      # description [String]
      # type        [String] Material type, either "opaque" or "glazing".
      # id_layers   [Array[Integer]]
      # rsi         [Float]
      # fenestration_number_of_panes [String] ExteriorWindow only.
      # frame_material               [String] ExteriorWindow only.
      # fenestration_type            [String] ExteriorWindow only.
      @constructions = {}


      self.compile_model
      self.compile_constructions
    end

    def compile_constructions

      # Fetch the additional properties for deratable surface types stored
      # in the default construction sets and populate the members of the
      # `@constructions` hash.
      # TODO: test later with warehouse
      @model.getDefaultConstructionSets.each do |set|
        if set.nameString =~ /BLDG$/

          # The following have additional properties defined by TBD:
          compile_construction_by_type(
            construction: set.defaultExteriorSurfaceConstructions.get.wallConstruction.get,
            surface_type: "ExteriorWall")

          compile_construction_by_type(
            construction: set.defaultExteriorSurfaceConstructions.get.roofCeilingConstruction.get,
            surface_type: "ExteriorRoof")

          compile_construction_by_type(
            construction: set.defaultExteriorSurfaceConstructions.get.floorConstruction.get,
            surface_type: "ExteriorFloor")

          compile_construction_by_type(
            construction: set.defaultGroundContactSurfaceConstructions.get.floorConstruction.get,
            surface_type: "GroundContactFloor")

          # The remaining do not have additional properties defined, they are
          # contained in the `@underatable_surface_types` variable:
          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.fixedWindowConstruction.get,
            surface_type: "ExteriorFixedWindow")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.operableWindowConstruction.get,
            surface_type: "ExteriorOperableWindow")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.skylightConstruction.get,
            surface_type: "ExteriorSkylight")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.tubularDaylightDiffuserConstruction.get,
            surface_type: "ExteriorTubularDaylightDiffuser")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.tubularDaylightDomeConstruction.get,
            surface_type: "ExteriorTubularDaylightDome")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.doorConstruction.get,
            surface_type: "ExteriorDoor")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.glassDoorConstruction.get,
            surface_type: "ExteriorGlassDoor")

          compile_construction_by_type(
            construction: set.defaultExteriorSubSurfaceConstructions.get.overheadDoorConstruction.get,
            surface_type: "ExteriorOverheadDoor")

          compile_construction_by_type(
            construction: set.defaultGroundContactSurfaceConstructions.get.wallConstruction.get,
            surface_type: "GroundContactWall")

          compile_construction_by_type(
            construction: set.defaultGroundContactSurfaceConstructions.get.roofCeilingConstruction.get,
            surface_type: "GroundContactRoof")

        elsif set.nameString =~ /ATTIC$/

          # Interzonal surfaces also have additional properties defined by TBD:
          compile_construction_by_type(
            construction: set.defaultInteriorSurfaceConstructions.get.wallConstruction.get,
            surface_type: "InterzonalSkylightWalls")

          compile_construction_by_type(
            construction: set.defaultInteriorSurfaceConstructions.get.floorConstruction.get,
            surface_type: "InterzonalRoof")
        end
      end
    end

    # @param construction: [OpenStudio::Model::ConstructionBase]
    # @param surface_type: [String]
    def compile_construction_by_type(construction:, surface_type:)
      underatable   = @underatable_surface_types.include?(surface_type)
      envelope_type = @surface_types_to_envelope_type[surface_type]

      # TODO: GroundContactFloor is underatable but it is and exception as it
      # still has U-factors and area defined, otherwise this should instead
      # check for the `underatable` variable.
      if construction.additionalProperties.hasFeature("btap_id")
        assembly_name = construction.additionalProperties.getFeatureAsString("btap_id").get
      else
        assembly_name = @surface_types_to_assembly_names[surface_type]
      end

      # If the construction isn't already present in the  `@constructions` hash,
      # add it in.
      unless @constructions.key?(assembly_name)
        construction_entry = @costing_database["constructions"][envelope_type][assembly_name]
        construction_btap  = {}
        construction_btap["type"] = construction_entry["type"]
        construction_btap["subsets"] = \
          construction_entry["usi"].transform_keys { |usi| 1 / usi.to_f }.map { |rsi, hash| hash["rsi"] = rsi; hash }

        if underatable
          construction_btap["rsi"] = TBD.rsi(construction)
          unless construction.isOpaque
            construction_btap["shgc"] = OpenstudioStandards::Constructions.construction_get_solar_transmittance(
              construction.to_Construction.get)
          end
        else
          construction_btap["rsi"] = 1 / construction.additionalProperties.getFeatureAsDouble("btap_uo").get
        end
        @constructions[assembly_name] = construction_btap
      end

      # Only include the assembly in the tallies hash if its area is non-zero.
      area = underatable ? construction.getNetArea : construction
        .additionalProperties.getFeatureAsDouble("btap_area").get

      unless area == 0
        @surface_types_to_assembly_tallies[surface_type][assembly_name] = {}
        @surface_types_to_assembly_tallies[surface_type][assembly_name]["area"] = area
      end
    end

    # Compile all the pertinent OpenStudio-related data into the data structures
    # of this class while also appending to the exisitng OpenStudio ones. This
    # adds accessors for zones, spaces, and surfaces while keeping them sorted
    # for future accesses. Also, store the RSI for each surface since retrieving
    # them is different for each category of surfaces.
    # TODO: Remove RSI storage
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
            raise("Error: Space type not defined for #{space.name.get}")
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
    # TODO: remove/fix: additional props always added by tbd now regardless of tbd_option
    def get_correct_rsi(surface)

      # Uninsulated surfaces are not derated by TBD. These surfaces will not
      # have a stored U-value. In those cases, use the fallback method.
      if @use_tbd and surface.additionalProperties.hasFeature("uprated_Uo")
        return 1 / surface.additionalProperties.getFeatureAsDouble("uprated_Uo").get
      else
        return TBD.rsi(surface.construction.get.to_LayeredConstruction.get, surface.filmResistance)
      end
    end
  end

  # Only relevant surface-specific tally is window perimeter for BTAP
  # Carbon. Add surface-specific tallies for underatable surfaces.
  # Currently only windows have emissions data for frames.
  def compile_window_perimeter
    @spaces.each do |space|
      ["ExteriorFixedWindow", "ExteriorOperableWindow"].each do |surface_type|
        assembly_name = @surface_types_to_assembly_names[surface_type]
        @surface_types_to_assembly_tallies[surface_type][assembly_name]["perimeter"] = 0
        space.surfaces_hash[surface_type].each do |surface|
          @surface_types_to_assembly_tallies[surface_type][assembly_name]["perimeter"] += \
            BTAP::Geometry::Surfaces.getSurfacePerimeterFromVertices(vertices: surface.vertices)

        end
      end
    end
  end
end

