module OpenStudioEnvelope
  module Costing
    # Costed-assembly selection: which BTAP-* assembly catalog (constructions.json)
    # each surface type is priced against. Port of BTAP::Constructions
    # .costed_assembly + btap/attributes.rb default tables. The wall assembly
    # follows the building structure (framing/cladding/finish) and the requested
    # performance tier; everything else is a fixed default (the catalogs carry the
    # RSI range, so U-value variation is handled by interpolation, not by assembly
    # choice).
    module Assemblies
      module_function

      MASS2 = 'BTAP-ExteriorWall-Mass-2'.freeze
      MASSB = 'BTAP-ExteriorWall-Mass-2b'.freeze
      MASS4 = 'BTAP-ExteriorWall-Mass-4'.freeze
      MASS8 = 'BTAP-ExteriorWall-Mass-8c'.freeze
      WOOD5 = 'BTAP-ExteriorWall-WoodFramed-5'.freeze
      WOOD7 = 'BTAP-ExteriorWall-WoodFramed-7'.freeze
      STEL1 = 'BTAP-ExteriorWall-SteelFramed-1'.freeze
      STEL2 = 'BTAP-ExteriorWall-SteelFramed-2'.freeze
      ROOF = 'BTAP-ExteriorRoof-IEAD-4'.freeze
      FLOOR = 'BTAP-ExteriorFloor-SteelFramed-1'.freeze

      # Legacy default assemblies for the non-structural surface types
      # (btap/attributes.rb @default_surface_constructions_by_type).
      DEFAULTS = {
        'ExteriorFixedWindow' => 'BTAP-ExteriorWindow-FixedWindow-1',
        'ExteriorOperableWindow' => 'BTAP-ExteriorWindow-OperableWindow-5b',
        'ExteriorSkylight' => 'BTAP-Skylight-2',
        'ExteriorTubularDaylightDiffuser' => 'BTAP-Skylight-2',
        'ExteriorTubularDaylightDome' => 'BTAP-Skylight-2',
        'ExteriorDoor' => 'BTAP-ExteriorDoor-Metal-1',
        'ExteriorGlassDoor' => 'BTAP-ExteriorWindow-GlazedDoor-4',
        'ExteriorOverheadDoor' => 'BTAP-ExteriorOverheadDoor-Metal-1',
        'GroundContactWall' => 'BTAP-GroundContactWall-Mass-2',
        'GroundContactRoof' => 'BTAP-GroundContactRoof-Mass-2',
        'GroundContactFloor' => 'BTAP-GroundContactFloor-Unheated-1'
      }.freeze

      # Surface type -> constructions.json sheet (btap/attributes.rb).
      SHEETS = {
        'ExteriorWall' => 'wall',
        'ExteriorRoof' => 'roof',
        'ExteriorFloor' => 'floor',
        'InterzonalRoof' => 'roof',
        'InterzonalSkylightWalls' => 'wall',
        'ExteriorFixedWindow' => 'window',
        'ExteriorOperableWindow' => 'window',
        'ExteriorSkylight' => 'skylight',
        'ExteriorTubularDaylightDiffuser' => 'skylight',
        'ExteriorTubularDaylightDome' => 'skylight',
        'ExteriorDoor' => 'door',
        'ExteriorGlassDoor' => 'door_glass',
        'ExteriorOverheadDoor' => 'door',
        'GroundContactWall' => 'bg_wall',
        'GroundContactRoof' => 'bg_roof',
        'GroundContactFloor' => 'slab'
      }.freeze

      GLAZING_SHEETS = %w[door_glass skylight window].freeze

      # Structural wall/roof/floor assembly (port of costed_assembly).
      # @param structure [Hash] { framing: :steel|:wood|:cmu, cladding:, finish: }
      # @param surface_type [Symbol] :walls, :roofs or :floors
      # @param performance [Symbol] :lp or :hp
      def costed_assembly(structure, surface_type, performance)
        surface_type = :walls unless %i[roofs floors].include?(surface_type)
        performance = :lp unless performance == :hp
        return ROOF if surface_type == :roofs
        return FLOOR if surface_type == :floors
        return STEL1 if structure.nil? || structure.empty?

        low, high =
          case structure[:framing]
          when :wood then [WOOD5, WOOD7]
          when :cmu then [MASS2, MASSB]
          else
            if structure[:cladding] == :heavy && structure[:finish] == :heavy
              [MASS4, MASS8]
            else
              [STEL1, STEL2]
            end
          end
        performance == :lp ? low : high
      end

      # Assembly name for any of the 16 costed surface types.
      def for_surface_type(surface_type, structure, performance)
        case surface_type
        when 'ExteriorWall', 'InterzonalSkylightWalls'
          costed_assembly(structure, :walls, performance)
        when 'ExteriorRoof', 'InterzonalRoof'
          costed_assembly(structure, :roofs, performance)
        when 'ExteriorFloor'
          costed_assembly(structure, :floors, performance)
        else
          DEFAULTS.fetch(surface_type)
        end
      end
    end
  end
end
