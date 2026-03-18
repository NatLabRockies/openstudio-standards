# This module deals with constructions used by BTAP for costing and carbon
# analysis. These constructions are separate from the ones used in the actual
# OpenStudio model.

module BTAP
  module Constructions
    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # BTAP/TBD data initially extracted from the BTAP costing spreadsheet:
    #
    #   - range of clear-field Uo factors
    #   - range of PSI factors (i.e. MAJOR thermal bridging), e.g. corners
    #
    # Ref: EVOKE BTAP costing spreadsheet modifications (2022), synced with:
    #      - Building Envelope Thermal Bridging Guide (BETBG)
    #      - ASHRAE RP-1365, ISO-12011, etc.
    #
    # This module has been subsequently adapted following the adoption of new
    # BTAP structure/envelope data model/classes.

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # BTAP costing data (both original BTAP envelope entries and EVOKE add-ons)
    # hold sub-variants based on cladding/veneer, e.g.:
    #
    #   - "BTAP-ExteriorWall-WoodFramed-5" ... brick veneer
    #   - "BTAP-ExteriorWall-WoodFramed-1" ... wood siding
    #
    # Not all of these sub-variants are currently used within BTAP, e.g.
    # "BTAP-ExteriorWall-WoodFramed-1" is unused. BTAP/TBD data is limited
    # to the following wall assemblies (paired LP & HP variants), which
    # eventually should be located in a shared file (e.g. CSV, JSON).
    #
    #   -----   Low Performance (LP) assemblies
    #   ID    : layers
    #   -----   ------------------------------------------
    #   STEL1 : cladding | board   | wool | frame | gypsum
    #   WOOD5 : brick    | board   | wool | frame | gypsum
    #   MASS2 : brick    | xps     |      | cmu   |
    #   MASS4 : precast  | xps     | wool | frame | gypsum
    #
    #   -----   High Performance (HP) variants
    #   ID    : layers
    #   -----   ------------------------------------------
    #   STEL2 : cladding | board   | wool | frame | gypsum ... switch from STEL1
    #   WOOD7 : brick    | mineral | wool | frame | gypsum ... switch from WOOD5
    #   MASSB : brick    | mineral | cmu  | foam  | gypsum ... switch from MASS2
    #   MASS8 : precast  | xps     | wool | frame | gypsum ... switch from MASS4
    #
    # Paired LPs & HPs vall variants are critical for 'uprating' cases, e.g.
    # NECB2017/2020. See below, and end of this document for additional NOTES.

    MASS2      = "BTAP-ExteriorWall-Mass-2"              # LP wall
    MASS2_BAD  = "BTAP-ExteriorWall-Mass-2 bad"          # LP "bad" PSI factors
    MASS2_GOOD = "BTAP-ExteriorWall-Mass-2 good"         # LP "good" PSI factors
    MASSB      = "BTAP-ExteriorWall-Mass-2b"             # HP, from @Uo < 0.183
    MASSB_BAD  = "BTAP-ExteriorWall-Mass-2b bad"         # HP "bad" PSI factors
    MASSB_GOOD = "BTAP-ExteriorWall-Mass-2b good"        # HP "good" PSI factors

    MASS4      = "BTAP-ExteriorWall-Mass-4"
    MASS4_BAD  = "BTAP-ExteriorWall-Mass-4 bad"
    MASS4_GOOD = "BTAP-ExteriorWall-Mass-4 good"
    MASS8      = "BTAP-ExteriorWall-Mass-8c"             # HP, from @Uo < 0.183
    MASS8_BAD  = "BTAP-ExteriorWall-Mass-8c bad"
    MASS8_GOOD = "BTAP-ExteriorWall-Mass-8c good"

    WOOD5      = "BTAP-ExteriorWall-WoodFramed-5"
    WOOD5_BAD  = "BTAP-ExteriorWall-WoodFramed-5 bad"
    WOOD5_GOOD = "BTAP-ExteriorWall-WoodFramed-5 good"
    WOOD7      = "BTAP-ExteriorWall-WoodFramed-7"        # HP, from @Uo < 0.183
    WOOD7_BAD  = "BTAP-ExteriorWall-WoodFramed-7 bad"
    WOOD7_GOOD = "BTAP-ExteriorWall-WoodFramed-7 good"

    STEL1      = "BTAP-ExteriorWall-SteelFramed-1"
    STEL1_BAD  = "BTAP-ExteriorWall-SteelFramed-1 bad"
    STEL1_GOOD = "BTAP-ExteriorWall-SteelFramed-1 good"
    STEL2      = "BTAP-ExteriorWall-SteelFramed-2"        # HP from @Uo < 0.278
    STEL2_BAD  = "BTAP-ExteriorWall-SteelFramed-2 bad"
    STEL2_GOOD = "BTAP-ExteriorWall-SteelFramed-2 good"

    ROOF       = "BTAP-ExteriorRoof-IEAD-4"
    FLOOR      = "BTAP-ExteriorFloor-SteelFramed-1"

    ##
    # Retrieves BTAP-costed assembly.
    #
    # @param structure    [BTAP::Structure] BTAP Structure object
    # @param surface_type [:walls, :floors or :roofs] surface type
    # @param performance  [false or true] false for low performance, true for
    #                                     high
    #
    # @return [String] BTAP assembly identifier for costing
    def self.costed_assembly(structure = nil, surface_type = :walls, performance = false)
      surface_type = :walls unless [:roofs, :floors].include?(surface_type)
      return STEL1 unless structure.is_a?(BTAP::Structure)

      # Select BTAP-costed assembly, matching:
      #   - BTAP::Structure generated construction parameters
      #   - requested high (HP) vs low-performance (LP) PSI-factor level
      #
      # Ideally, chosen PSI factor sets and matching OpenStudio constructions
      # shouldn't strictly be based on selected BTAP assemblies (e.g.
      # wood-framed vs steel-framed, cladding choice), but also on selected
      # building 'structure', e.g.:
      #
      #   - "wood-framed" MURB
      #   - "steel post/beam" office building
      #   - "reinforced concrete post/beam" public library
      #   - "metal(-building)" warehouse
      #   - "mass-timber (CLT)" university pavilion
      #
      # Major thermal bridges often consist of anchors or supports that transmit
      # structural loads (and by the same token, 'heat') to a building's main
      # structure. Examples include balconies, parapets and shelf angles.
      # Highly conductive building structures (e.g. steel, aluminium) exacerbate
      # thermal bridging effects - so building structural selection matters.
      #
      # The BTAP::Structure module generates such attributes, yet BTAP's costed
      # thermal bridging database doesn't yet distinguish between building
      # structures - @todo. For the moment, BTAP PSI set selection is strictly
      # based on BTAP::Structure's :framing, :cladding and :finish attributes,
      # which must be set prior to initiating BTAP's TBD's thermal bridging
      # solution:

      # Light gauge steel framing by default. Override if wood, cmu or precast.
      case surface_type
      when :roofs  then return ROOF
      when :floors then return FLOOR
      else
        case structure.framing
        when :wood
          c1 = WOOD5
          c2 = WOOD7
        when :cmu
          c1 = MASS2
          c2 = MASSB
        else
          if structure.cladding == :heavy && structure.finish == :heavy
            c1 = MASS4
            c2 = MASS8
          else
            c1 = STEL1
            c2 = STEL2
          end
        end
      end

      performance ? c2 : c1
    end
  end
end
