# BTAP Attributes
#
# This file extends some of the OpenStudio classes to add some new methods
# and parameters for convenience. Additionally, it also houses methods
# involving the pre-processing of an OpenStudio model for shared use in one
# of BTAP's facilities, for now BTAP Costing and BTAP Carbon. Currently, this
# pre-processing involves retrieving the correct constructions for envelopes and
# a few attributes for thermal bridging.

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

    class << self
      attr_reader :surface_types_to_assembly_names   # [Hash]
    end

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
        "InterzonalFloor",
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

      @surface_types_to_envelope_type = {
        "ExteriorWall"                    => "wall",
        "ExteriorRoof"                    => "roof",
        "ExteriorFloor"                   => "floor",
        "InterzonalRoof"                  => "roof",
        "InterzonalFloor"                 => "floor",

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
      @constructions = {}

      self.compile_model
      self.compile_constructions
    end

    # Fetch the additional properties in each default construction set which
    # reflects the attributes of all the surfaces of a type. Populate the
    # members of the `@constructions` and `@surface_types_to_assembly_tallies`
    # hashes.
    def compile_constructions

      @model.getDefaultConstructionSets.each do |set|

        # Plenum construction sets don't contain any information pertinent to
        # costing, skip them.
        if set.nameString =~ /PLENUM$/
          next

        # Attic construction sets concern insulated interzonal surfaces. This
        # also concerns crawlspaces, of which the interzonal floors will be
        # tallied.
        elsif set.nameString =~ /ATTIC$/

          compile_construction_by_type(
            construction: set.defaultInteriorSurfaceConstructions.get.wallConstruction.get,
            surface_type: "InterzonalSkylightWalls")

          compile_construction_by_type(
            construction: set.defaultInteriorSurfaceConstructions.get.floorConstruction.get,
            surface_type: "InterzonalRoof")

          compile_construction_by_type(
            construction: set.defaultInteriorSurfaceConstructions.get.roofCeilingConstruction.get,
            surface_type: "InterzonalFloor")

        # The following default construction sets concern the surfaces of the
        # whole building:
        elsif set.nameString =~ /BLDG$/
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
            construction: set.defaultGroundContactSurfaceConstructions.get.wallConstruction.get,
            surface_type: "GroundContactWall")

          # The presence of ground contact walls implies a basement which means
          # ground contact floors would be uninsulated and such should not be
          # costed.
          if @surface_types_to_assembly_tallies["GroundContactWall"].empty?
            compile_construction_by_type(
              construction: set.defaultGroundContactSurfaceConstructions.get.floorConstruction.get,
              surface_type: "GroundContactFloor")

            # From NECB2011 to NECB2025, ground contact floors only need to be
            # insulated wholly in climate zone 8. Otherwise, they need to be
            # insulated only for 1.2m about the perimeter. Insulation for the
            # low-conductnace ground contact floor U-factor variant have been
            # manually seperated into its own assembly below. Also check for the
            # presence of the perimeter additional property which denotes that
            # there are slab on grade ground contact floors.
            if @standard.get_necb_hdd18(model: @model) < 7000
              isoboard_name = "BTAP-GroundContactFloor-Isoboard"
              compile_construction_attributes(
                construction: set.defaultGroundContactSurfaceConstructions.get.floorConstruction.get,
                name: isoboard_name,
                entry: @costing_database["constructions"]["slab"][isoboard_name])

              @surface_types_to_assembly_tallies["GroundContactFloor"][isoboard_name] = {}
              @surface_types_to_assembly_tallies["GroundContactFloor"][isoboard_name]["area"] = \
                @model.getBuilding.additionalProperties.getFeatureAsDouble("btap_slab_perimeter_m2").get

            end
          end

          compile_construction_by_type(
            construction: set.defaultGroundContactSurfaceConstructions.get.roofCeilingConstruction.get,
            surface_type: "GroundContactRoof")

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

        # Any remaining construction sets will be custom and defined
        # by the user by manually adding additional properties to
        # spaces and will only comprise exterior-facing surfaces.
        # (see NECB2011/building_envelope.rb:add_construction_sets())
        else
          compile_construction_by_type(
            construction: set.defaultExteriorSurfaceConstructions.get.wallConstruction.get,
            surface_type: "ExteriorWall")

          compile_construction_by_type(
            construction: set.defaultExteriorSurfaceConstructions.get.roofCeilingConstruction.get,
            surface_type: "ExteriorRoof")

          compile_construction_by_type(
            construction: set.defaultExteriorSurfaceConstructions.get.floorConstruction.get,
            surface_type: "ExteriorFloor")

        end
      end
    end

    # @param construction: [OpenStudio::Model::ConstructionBase]
    # @param surface_type: [String]
    def compile_construction_by_type(construction:, surface_type:)
      assembly_name = construction.additionalProperties.getFeatureAsString("btap_id").get

      # If the construction isn't already present in the  `@constructions` hash,
      # add it in.
      unless @constructions.key?(assembly_name)
        compile_construction_attributes(
          construction: construction,
          name: assembly_name,
          entry: @costing_database["constructions"][@surface_types_to_envelope_type[surface_type]][assembly_name])
      end

      # Only include the assembly in the tallies hash if its area is non-zero.
      area = construction.additionalProperties.getFeatureAsDouble("btap_area").get
      unless area == 0
        @surface_types_to_assembly_tallies[surface_type][assembly_name] = {}
        @surface_types_to_assembly_tallies[surface_type][assembly_name]["area"] = area
      end
    end

    # @param construction: [OpenStudio::Model::ConstructionBase]
    # @param name:         [Hash] Assembly name.
    # @param entry:        [Hash] BTAP construction attributes.
    def compile_construction_attributes(construction:, name:, entry:)
        construction_btap            = {}
        construction_btap["type"]    = entry["type"]
        construction_btap["rsi"]     = 1 / construction.additionalProperties.getFeatureAsDouble("btap_uo").get
        construction_btap["subsets"] = \
          entry["usi"].transform_keys { |usi| 1 / usi.to_f }.map { |rsi, hash| hash["rsi"] = rsi; hash }

        construction_btap["shgc"] = OpenstudioStandards::Constructions.construction_get_solar_transmittance(
          construction.to_Construction.get) unless construction.isOpaque

        @constructions[name] = construction_btap
    end

    # Add new accessors for zones, spaces, and surfaces while keeping them
    # sorted for future accesses.
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
        end
      end
    end

    # Only relevant surface-specific tally is window perimeter for BTAP
    # Carbon. Add surface-specific tallies for underatable surfaces.
    # Currently only windows have emissions data for frames.
    def compile_window_perimeter
      windows = ["ExteriorFixedWindow", "ExteriorOperableWindow"]
      windows.each do |window|
        @surface_types_to_assembly_tallies[window][self.class.surface_types_to_assembly_names[window]]["perimeter"] = 0
      end

      @spaces.each do |space|
        windows.each do |window|
          assembly_name = self.class.surface_types_to_assembly_names[window]
          space.surfaces_hash[window].each do |surface|
            @surface_types_to_assembly_tallies[window][assembly_name]["perimeter"] += \
              BTAP::Geometry::Surfaces.getSurfacePerimeterFromVertices(vertices: surface.vertices)

          end
        end
      end
    end
  end
end

