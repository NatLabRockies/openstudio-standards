# **************************************************************************** /
# *  Copyright (c) 2008-2026, Natural Resources Canada
# *  All rights reserved.
# *
# *  This library is free software; you can redistribute it and/or
# *  modify it under the terms of the GNU Lesser General Public
# *  License as published by the Free Software Foundation; either
# *  version 2.1 of the License, or (at your option) any later version.
# *
# *  This library is distributed in the hope that it will be useful,
# *  but WITHOUT ANY WARRANTY; without even the implied warranty of
# *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# *  Lesser General Public License for more details.
# *
# *  You should have received a copy of the GNU Lesser General Public
# *  License along with this library; if not, write to the Free Software
# *  Foundation Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
# **************************************************************************** /

require 'tbd'
require 'json'

module BTAP
  # ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- #
  module BridgingData
    ##
    # BTAP module/class for Thermal Bridging & Derating (TBD) functionality
    # for linear thermal bridges, e.g. corners, balconies (rd2.github.io/tbd).
    #
    # @author: Denis Bourgeois

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # BTAP/TBD parameters are based on BTAP costing data:
    #   - paired low-performance (LP) vs high-performance (HP) wall variants
    #   - range of clear-field Uo factors for each variant
    #   - paired "bad" vs "good" PSI factor sets for each variant
    #
    # Ref: BTAP costing data modifications (2022), synced with:
    #      - Building Envelope Thermal Bridging Guide (BETBG)
    #      - ASHRAE RP-1365, ISO-12011, etc.
    #
    # STRUCTURE parameters set paired constructions - see btap/structure.rb.

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # BTAP/TBD data groups above-grade wall assemblies as paired LP/HP variants.
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
    # NECB2017/2020/2025. See below, and additional Notes at the very end.

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

    # Insulated roofs, exposed floors (and attic floors) are also up/de-rated.
    ROOF       = "BTAP-ExteriorRoof-IEAD-4"         # no LP/HP variants
    FLOOR      = "BTAP-ExteriorFloor-SteelFramed-1" # no LP/HP variants

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # BTAP/TBD is de/activated by setting the NECB 'tbd_option' as follows:
    #   - "none"         : TBD is deactivated, i.e. no uprating
    #   - "bad" or "good": TBD derates envelope
    #   - "uprate"       : TBD uprates initial Uo ... prior to derating
    #
    #   - (see necb_2011.rb/apply_thermal_bridging)
    #
    # For NECB editions prior to NECB2017, the current recommended BTAP policy
    # is to switch off TBD (i.e. 'none') - see Note on this topic at the end of
    # this document. To instead assess prescriptive Ut compliance for NECB
    # editions 2017 through 2025, BTAP/TBD must be set to "uprate" so it can
    # iteratively reset combined Uo & PSI factors towards finding the most
    # affordable (yet compliant) Ut combination. Why? Improved Uo assembly
    # variants are necessarily required, given:
    #
    #   Ut = Uo + ( ∑psi x L )/A + ( ∑khi x n )/A   (ref: rd2.github.io/tbd)
    #
    # If one ignores linear ("( ∑psi x L )/A") and point ("( ∑khi x n )/A")
    # conductances, Ut simply equates to Uo. Yet for ANY added linear or point
    # conductance, Uo factors must necessarily be lower than required NECB2017+
    # Ut factor requirements. BTAP HP wall assembly variants indeed offer much
    # lower Uo factors (than required Ut), down to 0.1 W/m2.K or ~R70. These
    # BTAP upgrades certainly provide more options for attaining required Ut
    # factors. In practice, this simply implies a thicker insulation layer. For
    # others, it involves more radical assembly changes, such as switching over
    # to the latest commercially-available HP thermally-broken cladding clips.
    # While some solutions are simple (free) detailing changes, most
    # improvements increase construction costs. Despite adding new BTAP HP
    # assemblies, it is unlikely that TBD will find NECB2017+ compliant
    # combinations (prescriptive path) for EVERY OpenStudio model. Why?
    #
    #   github.com/rd2/tbd/blob/dd6f12f8f2c24950485918c7eaca57d8f091a64d/spec/
    #   tbd_tests_spec.rb#L1674
    #
    # For these reasons, BTAP's use of TBD rests on an ITERATIVE uprating
    # solution for NECB2017+:
    #
    #   1. TBD attempts to achieve NECB-required area-weighted Ut factors
    #      for above-grade walls (then for roofs and exposed floors),
    #      starting with the least expensive combination:
    #        - LP variant
    #        - "bad" thermal bridging details
    #
    #   2. If, for a given OpenStudio model, required area-weighted Ut
    #      factors cannot be achieved, TBD then switches over to "good"
    #      thermal bridging detailing for that same assembly, and repeats the
    #      exercise.
    #
    #   3. A subsequent failed attempt triggers a switch over to HP variants.
    #      For instance:
    #        - "BTAP-ExteriorWall-WoodFramed-5" ... switches over to:
    #        - "BTAP-ExteriorWall-WoodFramed-7"
    #
    #      ... switching over to another assembly this way also means
    #      reverting back to "bad" thermal bridging PSI factors.
    #
    #   4. A final switch to "good" details is triggered if needed.
    #
    # If NONE of the available combinations are sufficient:
    #   - TBD red-flags a failed attempt at NECB2017+ compliance
    #   - TBD keeps iteration #4 (HP Uo + "good" PSI combo), then derates before
    #     a BTAP simulation run (giving some performance gap indication)

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # Notes:
    #
    #   - Steel-framed assemblies: the costed HP variant has metal cladding.
    #     The costed LP variant is wood-clad - something of an anomaly in
    #     commercial construction. By making the switch earlier to metal
    #     cladding, everywhere in Canada except (milder) SW BC and SW NS, it is
    #     hoped that a more consistent, apples-to-apples comparison is ensured.
    #
    #   - ROOF and FOOR surfaces refer to a single LP/HP selection respectively.

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # Preset BTAP/TBD wall assembly parameters.
    @@data = {}

    # Construction sub-variant identified strictly by Uo, e.g. 0.314 W/m2.K.
    @@data[MASS2] = {uos: [0.314, 0.278, 0.247, 0.210, 0.183]}        # :lp
    @@data[MASSB] = {uos: [0.130, 0.100]}                             # :hp

    @@data[MASS4] = {uos: [0.314, 0.278, 0.247, 0.210, 0.183]}        # :lp
    @@data[MASS8] = {uos: [0.130, 0.100]}                             # :hp

    @@data[WOOD5] = {uos: [0.314, 0.278, 0.247, 0.210, 0.183]}        # :lp
    @@data[WOOD7] = {uos: [0.130]}                                    # :hp

    @@data[STEL1] = {uos: [0.314, 0.278]}                             # :lp
    @@data[STEL2] = {uos: [0.247, 0.210, 0.183, 0.130, 0.100, 0.080]} # :hp

    @@data[FLOOR] = {uos: [0.227, 0.183, 0.162, 0.142, 0.116, 0.101]}
    @@data[ROOF ] = {uos: [0.227, 0.193, 0.183, 0.162, 0.156, 0.142, 0.138, 0.121, 0.100]}

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # Initialize PSI factor qualities per wall assembly.
    @@data.values.each do |construction|
      construction[:bad ] = {}
      construction[:good] = {}
    end

    # Thermal bridge types :balcony, :party and :joint are NOT expected to
    # be processed soon within BTAP. They are neither costed out, nor are carbon
    # intensities (kgCO2-eq/linear meter) associated to them. At some point, it
    # may be wise to do so (notably cantilevered balconies in MURBs) - @todo.
    # Default, generic BETBG PSI factors are nonetheless provided here:
    #   - for "bad" BTAP cases : generic BETBG set "bad"
    #   - for "good" BTAP cases: generic BETBG set "efficient"

    @@data[MASS2][ :bad][:id          ] = MASS2_BAD
    @@data[MASS2][ :bad][:rimjoist    ] = { psi: 0.470 }
    @@data[MASS2][ :bad][:parapet     ] = { psi: 0.500 }
    @@data[MASS2][ :bad][:fenestration] = { psi: 0.350 }
    @@data[MASS2][ :bad][:door        ] = { psi: 0.000 }
    @@data[MASS2][ :bad][:corner      ] = { psi: 0.150 }
    @@data[MASS2][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[MASS2][ :bad][:party       ] = { psi: 0.850 }
    @@data[MASS2][ :bad][:grade       ] = { psi: 0.520 }
    @@data[MASS2][ :bad][:joint       ] = { psi: 0.300 }

    @@data[MASS2][:good][:id          ] = MASS2_GOOD
    @@data[MASS2][:good][:rimjoist    ] = { psi: 0.100 }
    @@data[MASS2][:good][:parapet     ] = { psi: 0.230 }
    @@data[MASS2][:good][:fenestration] = { psi: 0.078 }
    @@data[MASS2][:good][:door        ] = { psi: 0.000 }
    @@data[MASS2][:good][:corner      ] = { psi: 0.090 }
    @@data[MASS2][:good][:balcony     ] = { psi: 0.200 }
    @@data[MASS2][:good][:party       ] = { psi: 0.200 }
    @@data[MASS2][:good][:grade       ] = { psi: 0.090 }
    @@data[MASS2][:good][:joint       ] = { psi: 0.100 }

    @@data[MASSB][ :bad][:id          ] = MASSB_BAD
    @@data[MASSB][ :bad][:rimjoist    ] = { psi: 0.470 }
    @@data[MASSB][ :bad][:parapet     ] = { psi: 0.500 }
    @@data[MASSB][ :bad][:fenestration] = { psi: 0.350 }
    @@data[MASSB][ :bad][:door        ] = { psi: 0.000 }
    @@data[MASSB][ :bad][:corner      ] = { psi: 0.150 }
    @@data[MASSB][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[MASSB][ :bad][:party       ] = { psi: 0.850 }
    @@data[MASSB][ :bad][:grade       ] = { psi: 0.520 }
    @@data[MASSB][ :bad][:joint       ] = { psi: 0.300 }

    @@data[MASSB][:good][:id          ] = MASSB_GOOD
    @@data[MASSB][:good][:rimjoist    ] = { psi: 0.100 }
    @@data[MASSB][:good][:parapet     ] = { psi: 0.230 }
    @@data[MASSB][:good][:fenestration] = { psi: 0.078 }
    @@data[MASSB][:good][:door        ] = { psi: 0.000 }
    @@data[MASSB][:good][:corner      ] = { psi: 0.090 }
    @@data[MASSB][:good][:balcony     ] = { psi: 0.200 }
    @@data[MASSB][:good][:party       ] = { psi: 0.200 }
    @@data[MASSB][:good][:grade       ] = { psi: 0.090 }
    @@data[MASSB][:good][:joint       ] = { psi: 0.100 }

    @@data[MASS4][ :bad][:id          ] = MASS4_BAD
    @@data[MASS4][ :bad][:rimjoist    ] = { psi: 0.200 }
    @@data[MASS4][ :bad][:parapet     ] = { psi: 0.650 }
    @@data[MASS4][ :bad][:fenestration] = { psi: 0.078 }
    @@data[MASS4][ :bad][:door        ] = { psi: 0.000 }
    @@data[MASS4][ :bad][:corner      ] = { psi: 0.370 }
    @@data[MASS4][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[MASS4][ :bad][:party       ] = { psi: 0.850 }
    @@data[MASS4][ :bad][:grade       ] = { psi: 0.800 }
    @@data[MASS4][ :bad][:joint       ] = { psi: 0.300 }

    @@data[MASS4][:good][:id          ] = MASS4_GOOD
    @@data[MASS4][:good][:rimjoist    ] = { psi: 0.020 }
    @@data[MASS4][:good][:parapet     ] = { psi: 0.240 }
    @@data[MASS4][:good][:fenestration] = { psi: 0.078 }
    @@data[MASS4][:good][:door        ] = { psi: 0.000 }
    @@data[MASS4][:good][:corner      ] = { psi: 0.160 }
    @@data[MASS4][:good][:balcony     ] = { psi: 0.200 }
    @@data[MASS4][:good][:party       ] = { psi: 0.200 }
    @@data[MASS4][:good][:grade       ] = { psi: 0.320 }
    @@data[MASS4][:good][:joint       ] = { psi: 0.100 }

    @@data[MASS8][ :bad][:id          ] = MASS8_BAD
    @@data[MASS8][ :bad][:rimjoist    ] = { psi: 0.200 }
    @@data[MASS8][ :bad][:parapet     ] = { psi: 0.650 }
    @@data[MASS8][ :bad][:fenestration] = { psi: 0.078 }
    @@data[MASS8][ :bad][:door        ] = { psi: 0.000 }
    @@data[MASS8][ :bad][:corner      ] = { psi: 0.370 }
    @@data[MASS8][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[MASS8][ :bad][:party       ] = { psi: 0.850 }
    @@data[MASS8][ :bad][:grade       ] = { psi: 0.800 }
    @@data[MASS8][ :bad][:joint       ] = { psi: 0.300 }

    @@data[MASS8][:good][:id          ] = MASS8_GOOD
    @@data[MASS8][:good][:rimjoist    ] = { psi: 0.020 }
    @@data[MASS8][:good][:parapet     ] = { psi: 0.240 }
    @@data[MASS8][:good][:fenestration] = { psi: 0.078 }
    @@data[MASS8][:good][:door        ] = { psi: 0.000 }
    @@data[MASS8][:good][:corner      ] = { psi: 0.160 }
    @@data[MASS8][:good][:balcony     ] = { psi: 0.200 }
    @@data[MASS8][:good][:party       ] = { psi: 0.200 }
    @@data[MASS8][:good][:grade       ] = { psi: 0.320 }
    @@data[MASS8][:good][:joint       ] = { psi: 0.100 }

    @@data[WOOD5][ :bad][:id          ] = WOOD5_BAD
    @@data[WOOD5][ :bad][:rimjoist    ] = { psi: 0.050 }
    @@data[WOOD5][ :bad][:parapet     ] = { psi: 0.050 }
    @@data[WOOD5][ :bad][:fenestration] = { psi: 0.270 }
    @@data[WOOD5][ :bad][:door        ] = { psi: 0.000 }
    @@data[WOOD5][ :bad][:corner      ] = { psi: 0.040 }
    @@data[WOOD5][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[WOOD5][ :bad][:party       ] = { psi: 0.850 }
    @@data[WOOD5][ :bad][:grade       ] = { psi: 0.550 }
    @@data[WOOD5][ :bad][:joint       ] = { psi: 0.300 }

    @@data[WOOD5][:good][:id          ] = WOOD5_GOOD
    @@data[WOOD5][:good][:rimjoist    ] = { psi: 0.030 }
    @@data[WOOD5][:good][:parapet     ] = { psi: 0.050 }
    @@data[WOOD5][:good][:fenestration] = { psi: 0.078 }
    @@data[WOOD5][:good][:door        ] = { psi: 0.000 }
    @@data[WOOD5][:good][:corner      ] = { psi: 0.040 }
    @@data[WOOD5][:good][:balcony     ] = { psi: 0.200 }
    @@data[WOOD5][:good][:party       ] = { psi: 0.200 }
    @@data[WOOD5][:good][:grade       ] = { psi: 0.090 }
    @@data[WOOD5][:good][:joint       ] = { psi: 0.100 }

    @@data[WOOD7][ :bad][:id          ] = WOOD7_BAD
    @@data[WOOD7][ :bad][:rimjoist    ] = { psi: 0.050 }
    @@data[WOOD7][ :bad][:parapet     ] = { psi: 0.050 }
    @@data[WOOD7][ :bad][:fenestration] = { psi: 0.270 }
    @@data[WOOD7][ :bad][:door        ] = { psi: 0.000 }
    @@data[WOOD7][ :bad][:corner      ] = { psi: 0.040 }
    @@data[WOOD7][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[WOOD7][ :bad][:party       ] = { psi: 0.850 }
    @@data[WOOD7][ :bad][:grade       ] = { psi: 0.550 }
    @@data[WOOD7][ :bad][:joint       ] = { psi: 0.300 }

    @@data[WOOD7][:good][:id          ] = WOOD7_GOOD
    @@data[WOOD7][:good][:rimjoist    ] = { psi: 0.030 }
    @@data[WOOD7][:good][:parapet     ] = { psi: 0.050 }
    @@data[WOOD7][:good][:fenestration] = { psi: 0.078 }
    @@data[WOOD7][:good][:door        ] = { psi: 0.000 }
    @@data[WOOD7][:good][:corner      ] = { psi: 0.040 }
    @@data[WOOD7][:good][:balcony     ] = { psi: 0.200 }
    @@data[WOOD7][:good][:party       ] = { psi: 0.200 }
    @@data[WOOD7][:good][:grade       ] = { psi: 0.090 }
    @@data[WOOD7][:good][:joint       ] = { psi: 0.100 }

    @@data[STEL1][ :bad][:id          ] = STEL1_BAD
    @@data[STEL1][ :bad][:rimjoist    ] = { psi: 0.280 }
    @@data[STEL1][ :bad][:parapet     ] = { psi: 0.650 }
    @@data[STEL1][ :bad][:fenestration] = { psi: 0.270 }
    @@data[STEL1][ :bad][:door        ] = { psi: 0.000 }
    @@data[STEL1][ :bad][:corner      ] = { psi: 0.150 }
    @@data[STEL1][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[STEL1][ :bad][:party       ] = { psi: 0.850 }
    @@data[STEL1][ :bad][:grade       ] = { psi: 0.720 }
    @@data[STEL1][ :bad][:joint       ] = { psi: 0.300 }

    @@data[STEL1][:good][:id          ] = STEL1_GOOD
    @@data[STEL1][:good][:rimjoist    ] = { psi: 0.090 }
    @@data[STEL1][:good][:parapet     ] = { psi: 0.350 }
    @@data[STEL1][:good][:fenestration] = { psi: 0.078 }
    @@data[STEL1][:good][:door        ] = { psi: 0.000 }
    @@data[STEL1][:good][:corner      ] = { psi: 0.090 }
    @@data[STEL1][:good][:balcony     ] = { psi: 0.200 }
    @@data[STEL1][:good][:party       ] = { psi: 0.200 }
    @@data[STEL1][:good][:grade       ] = { psi: 0.470 }
    @@data[STEL1][:good][:joint       ] = { psi: 0.100 }

    @@data[STEL2][ :bad][:id          ] = STEL2_BAD
    @@data[STEL2][ :bad][:rimjoist    ] = { psi: 0.280 }
    @@data[STEL2][ :bad][:parapet     ] = { psi: 0.650 }
    @@data[STEL2][ :bad][:fenestration] = { psi: 0.270 }
    @@data[STEL2][ :bad][:door        ] = { psi: 0.000 }
    @@data[STEL2][ :bad][:corner      ] = { psi: 0.150 }
    @@data[STEL2][ :bad][:balcony     ] = { psi: 1.000 }
    @@data[STEL2][ :bad][:party       ] = { psi: 0.850 }
    @@data[STEL2][ :bad][:grade       ] = { psi: 0.720 }
    @@data[STEL2][ :bad][:joint       ] = { psi: 0.300 }

    @@data[STEL2][:good][:id          ] = STEL2_GOOD
    @@data[STEL2][:good][:rimjoist    ] = { psi: 0.090 }
    @@data[STEL2][:good][:parapet     ] = { psi: 0.100 }
    @@data[STEL2][:good][:fenestration] = { psi: 0.078 }
    @@data[STEL2][:good][:door        ] = { psi: 0.000 }
    @@data[STEL2][:good][:corner      ] = { psi: 0.090 }
    @@data[STEL2][:good][:balcony     ] = { psi: 0.200 }
    @@data[STEL2][:good][:party       ] = { psi: 0.200 }
    @@data[STEL2][:good][:grade       ] = { psi: 0.470 }
    @@data[STEL2][:good][:joint       ] = { psi: 0.100 }
    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #

    ##
    # Returns paired low-performance (LP) & high-performance (HP) BTAP-costed
    # wall assembly identifiers, based on user-provided assembly ID. If valid,
    # solution returns a Hash holding 2 keys (:lp and :hp).
    #
    # @param id [String] a valid BTAP-costed wall assembly identifier
    #
    # @return [Hash] assembly :lp & :hp identifiers (empty if invalid input)
    def assembly_id(id = "")
      return {} unless @@data.key?(id)
      pair = {}

      if id == MASS2 || id == MASSB
        pair[:lp] = MASS2
        pair[:hp] = MASSB
      elsif id == MASS4 || id == MASS8
        pair[:lp] = MASS4
        pair[:hp] = MASS8
      elsif id == WOOD5 || id == WOOD7
        pair[:lp] = WOOD5
        pair[:hp] = WOOD7
      elsif id == STEL1 || id == STEL2
        pair[:lp] = STEL1
        pair[:hp] = STEL2
      end

      pair
    end

    ##
    # Returns an above-grade (opaque) BTAP-costed assembly identifier that
    # matches selection criteria. Solution may return an assembly's low
    # performance (:lp) or its paired high-performance (:hp) variant. Defaults
    # to STEL2 (walls) if invalid input.
    #
    # @param [Hash] argh options
    # @option argh [Symbol] :stype (:walls, :floors or :roofs)
    # @option argh [Symbol] :perform (:lp or :hp) wall variant, optional
    # @option argh [Symbol] :framing (:steel, :wood, :cmu), optional
    # @option argh [Symbol] :cladding (:heavy), optional
    # @option argh [Symbol] :finish (:heavy), optional
    # @option argh [String] :id a BTAP-costed assembly (often :lp)
    # @option argh [Float] :uo desired U-factor, optional
    #
    # @return [String] BTAP costed assembly identifier
    def costed_assembly(argh = {})
      return STEL2 unless argh.respond_to?(:keys)

      # Key input.
      stype = argh.key?(:stype) ? argh[:stype] : :walls
      stype = :walls unless [:roofs, :floors].include?(stype)

      # No BTAP variants yet for roofs or floors.
      return ROOF  if argh[:stype] == :roofs
      return FLOOR if argh[:stype] == :floors

      # Low-performance (:lp) or high-performance (:hp) variant?
      perform = argh.key?(:perform) ? argh[:perform] : :lp
      perform = :lp unless perform == :hp

      # Valid identifier?
      if argh.key?(:id)
        pair = assembly_id(argh[:id])

        unless pair.empty?
          if argh.key?(:uo)
            uo = costed_uo(pair[perform], argh[:uo])
            perform = :hp if uo.nil?
          end

          return pair[perform]
        end
      end

      # Relying on STRUCTURE-based parameters.
      framing  = argh.key?(:framing)  ? argh[:framing ] : :steel
      cladding = argh.key?(:cladding) ? argh[:cladding] : :light
      finish   = argh.key?(:finish)   ? argh[:finish  ] : :light

      framing  = :steel unless [:wood, :cmu].include?(framing)
      cladding = :light unless cladding == :heavy
      finish   = :light unless finish   == :heavy

      # Select BTAP-costed wall assembly, matching:
      #   - BTAP::Structure generated construction parameters (e.g. framing)
      #   - requested high- (:hp) vs low-performance (:lp) variant
      pair = {}

      # Note: Chosen PSI factor sets and matching OpenStudio constructions
      # shouldn't strictly be based on selected BTAP-costed assemblies (e.g.
      # wood-framed vs steel-framed, cladding choice), but also on selected
      # building STRUCTURE, e.g.:
      #
      #   - "wood-framed" MURB
      #   - "steel post/beam" office building
      #   - "reinforced concrete post/beam" public library
      #   - "metal(-building)" warehouse
      #   - "mass-timber (CLT)" university pavilion
      #
      # Linear thermal bridges often consist of structural elements that
      # transmit envelope structural loads (and by the same token, 'heat') to a
      # building's main structure. Examples include balconies, parapets and
      # shelf angles. Highly conductive building structural materials (e.g.
      # steel, concrete) exacerbate thermal bridging - building structural
      # choices should matter.
      #
      # The BTAP::Structure module generates such attributes, yet BTAP's costed
      # thermal bridging database doesn't yet distinguish between building
      # structures - @todo. For the moment, BTAP PSI set selection is strictly
      # based on BTAP::Structure's :framing, :cladding and :finish attributes,
      # which are set prior to initiating BTAP's TBD solution.
      case framing
      when :wood then pair = assembly_id(WOOD5)
      when :cmu  then pair = assembly_id(MASS2)
      else
        pair = assembly_id(STEL1)
        pair = assembly_id(MASS4) if cladding == :heavy && finish == :heavy
      end

      if argh.key?(:uo)
        uo = costed_uo(pair[perform], argh[:uo])
        perform = :hp if uo.nil?
      end

      pair[perform]
    end

    ##
    # Retrieves nearest assembly Uo factor.
    #
    # @param assembly [String] BTAP assembly identifier
    # @param uo [Double] target Uo in W/m2.K
    #
    # @return [Double] costed BTAP assembly Uo factor (nil if fail)
    def costed_uo(assembly = "", uo = nil)
      return nil unless @@data.key?(assembly)
      return nil unless uo.is_a?(Numeric)

      uo = uo.clamp(TBD::UMIN, TBD::UMAX)

      @@data[assembly][:uos].each { |u| return u if u.round(3) <= uo.round(3) }

      nil
    end

    ##
    # Retrieves lowest costed assembly Uo factor.
    #
    # @param assembly [String] BTAP assembly identifier
    #
    # @return [Double] lowest costed BTAP assembly Uo factor (nil if fail)
    def lowest_uo(assembly = "")
      return nil unless @@data.key?(assembly)

      @@data[assembly][:uos].min
    end

    ##
    # Retrieves assembly-specific PSI factor set.
    #
    # @param assembly [String] BTAP/TBD wall construction identifier
    # @param quality [Symbol] BTAP/TBD PSI quality (:bad or :good)
    #
    # @return [Hash] BTAP/TBD PSI factor set (defaults to STEL2, :good)
    def set(assembly = STEL2, quality = :good)
      assembly = STEL2 unless @@data.key?(assembly)
      quality  = :good unless @@data[assembly].key?(quality)

      chx = @@data[assembly][quality]
      psi = {}

      psi[:id          ] = chx[:id          ]
      psi[:rimjoist    ] = chx[:rimjoist    ][:psi]
      psi[:parapet     ] = chx[:parapet     ][:psi]
      psi[:fenestration] = chx[:fenestration][:psi]
      psi[:door        ] = chx[:door        ][:psi]
      psi[:corner      ] = chx[:corner      ][:psi]
      psi[:balcony     ] = chx[:balcony     ][:psi]
      psi[:party       ] = chx[:party       ][:psi]
      psi[:grade       ] = chx[:grade       ][:psi]
      psi[:joint       ] = chx[:joint       ][:psi]

      psi
    end

    ##
    # Return BTAP/TBD data.
    #
    # @return [Hash] preset BTAP/TBD data
    def data
      @@data
    end

    def self.extended(base)
      base.send(:include, self)
    end
  end

  # ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- #
  class BTAP::Bridging
    extend BridgingData

    TOL  = TBD::TOL
    TOL2 = TBD::TOL2
    DBG  = TBD::DBG
    INF  = TBD::INF
    WRN  = TBD::WRN
    ERR  = TBD::ERR
    FTL  = TBD::FTL

    # @return [Hash] BTAP/TBD hash, specific to an OpenStudio model
    attr_reader :model

    # @return [Hash] logged messages TBD reports back to BTAP
    attr_reader :feedback

    # @return [Hash] TBD tallies e.g. total lengths of linear thermal bridges
    attr_reader :tally

    ##
    # Initializes OpenStudio model-specific BTAP/TBD data - uprates/derates.
    #
    # @param model [OpenStudio::Model::Model] a model
    # @param [Hash] argh BTAP/TBD argument hash
    # @option argh [BTAP::Structure] :structure a BTAP STRUCTURE instance
    # @option argh [Hash] :walls exterior wall parameters (:uo, :ut)
    # @option argh [Hash] :floors exposed floor parameters (:uo, :ut)
    # @option argh [Hash] :roofs exterior roof parameters (:uo, :ut)
    # @option argh [:good, :bad] :quality of thermal bridging (derating only)
    # @option argh [Boolean] :interpolate between costed Uo (uprate only)
    def initialize(model = nil, argh = {})
      mth       = "BTAP::Bridging::#{__callee__}"
      @model    = {}
      @tally    = {}
      @feedback = {logs: []}
      lgs       = @feedback[:logs]

      # Populate and validate BTAP/TBD & OpenStudio model parameters. This does
      # a safe TBD trial run, returning true if successful. If false, TBD leaves
      # the model unaltered. Check @feedback logs.
      return unless self.populate(model, argh)

      # Initialize loop controls and flags.
      initial  = true
      complies = false
      comply   = {} # specific to :walls, :floors & :roofs (if uprating)
      perform  = :lp
      quality  = argh[:quality] == :good ? :good : :bad
      combo    = "#{perform.to_s}_#{quality.to_s}".to_sym # e.g. :lp_bad
      args     = {} # TBD's own argument hash

      # Initialize surface types & TBD arguments for iterative uprating runs.
      @model[:stypes].each do |stypes|
        next unless argh[stypes].key?(:ut)

        stype  = stypes.to_s.chop
        uprate = "uprate_#{stypes.to_s}".to_sym
        option = "#{stype}_option".to_sym
        ut     = "#{stype}_ut".to_sym

        args[uprate] = true
        args[option] = "ALL #{stype} constructions"
        args[ut    ] = argh[stypes][:ut]

        comply[stypes] = false
      end

      # Building-wide PSI set.
      args[:option ] = ""
      args[:io_path] = @model[:psi][combo]
      return false if args[:io_path].nil?

      loop do
        if initial
          initial = false
        else
          # Subsequent uprating runs. Upgrade technologies. Reset TBD args.
          # Switch 'perform' from :lp to :hp - reset quality to :bad.
          if quality == :bad
            quality = :good
            combo   = "#{perform.to_s}_#{quality.to_s}".to_sym
          elsif perform == :lp
            perform = :hp
            quality = :bad
            combo   = "#{perform.to_s}_#{quality.to_s}".to_sym
          end

          args[:io_path] = @model[:psi][combo]

          # Delete previously-generated TBD args Uo key/value pairs.
          @model[:stypes].each do |stypes|
            next unless comply.key?(stypes)

            uo = "#{stypes.to_s.chop}_uo".to_sym
            args.delete(uo) if args.key?(uo)
          end
        end

        # Run TBD on cloned OpenStudio model - compliant combo?
        TBD.clean!
        mdl = OpenStudio::Model::Model.new
        mdl.addObjects(model.toIdfFile.objects)
        res = TBD.process(mdl, args)

        # Halt all processes if fatal errors raised by TBD (e.g. badly formatted
        # TBD arguments, poorly-structured OpenStudio models).
        if TBD.fatal?
          TBD.logs.each { |lg| lgs << lg[:message] if lg[:level] == TBD::FTL }
          break
        end

        complies = true
        # Check if TBD-uprated Uo factors are valid: TBD args hash holds (new)
        # uprated Uo keys/values for :walls, :floors and/or :roofs if uprating
        # is successful. In most cases, uprating tends to fail for wall
        # constructions rather than roof or floor constructions, due to the
        # typically larger density of linear thermal bridging per surface area
        # Yet even if all constructions were successfully uprated by TBD, one
        # must then determine if BTAP holds admissible (i.e. costed) assembly
        # variants with corresponding Uo factors. If TBD-uprated Uo factors are
        # lower than any of these admissible BTAP Uo factors, then no
        # commercially available solution can been identified.
        @model[:stypes].each do |stypes|
          next unless comply.key?(stypes) # true only if uprating

          opt            = {}
          opt[:stype   ] = stypes
          opt[:perform ] = perform
          opt[:framing ] = argh[:structure].framing
          opt[:cladding] = argh[:structure].cladding
          opt[:finish  ] = argh[:structure].finish

          # NONONO rely on btap_id   = lc.additionalProperties.getFeatureAsString("btap_id")

          assembly = self.costed_assembly(opt)
          stype_uo = "#{stypes.to_s.chop}_uo".to_sym
          target   = args.key?(stype_uo) ? args[stype_uo] : nil

          # TBD-estimated Uo target to meet NECB-required Ut - nil if invalid.
          uo = target ? self.costed_uo(assembly, target) : nil

          if uo
            uo = target if argh[:interpolate]
            comply[stypes] = true
          else
            uo = self.lowest_uo(assembly)
            comply[stypes] = false
          end

          # Repeat for custom spaces.
          argh[:structure].spaces.each do |id, space|
            opt[:framing ] = space[:framing]
            opt[:cladding] = space[:cladding]
            opt[:finish  ] = space[:finish]

            assembly = self.costed_assembly(opt)
            uo = target ? self.costed_uo(assembly, target) : nil

            if uo
              uo = target if argh[:interpolate]
            else
              uo = self.lowest_uo(assembly)
              comply[stypes] = false
            end
          end

          @model[:constructions].values.each do |v|
            next unless v[:stypes] == stypes

            v[:uo] = uo
            v[:compliant] = comply[stypes]
          end

          complies = false unless comply[stypes]
        end

        # Exit if successful or if final BTAP uprating option.
        break if combo == :hp_good
        break if complies
      end

      # Post-loop steps (if uprating).
      @model[:stypes].each do |stypes|
        next unless comply.key?(stypes) # true only if uprating

        # Cancel uprating request before final derating.
        stype  = stypes.to_s.chop
        uprate = "uprate_#{stypes.to_s}".to_sym
        option = "#{stype}_option".to_sym
        ut     = "#{stype}_ut".to_sym
        args.delete(uprate)
        args.delete(option)
        args.delete(ut)

        # Reset uprated Uo factor for each 'deratable' construction.
        @model[:constructions].each do |id, v|
          next unless v[:stypes] == stypes

          lc = model.getConstructionByName(id)

          if lc.empty?
            lgs << "Mismatched construction: #{id} (#{mth})?"
            return false
          end

          lc = lc.get.to_LayeredConstruction

          if lc.empty?
            lgs << "Mismatched layered construction: #{id} (#{mth})?"
            return false
          end

          lc = lc.get

          v[:r] = TBD.resetUo(lc, v[:btap_film], v[:index], v[:uo])

          # Re/set to each construction the following AdditionalProperties:
          lc.additionalProperties.setFeature("btap_uo", v[:uo])

          v[:surfaces].each do |name|
            surface = model.getSurfaceByName(name)
            next if surface.empty?

            surface.get.additionalProperties.setFeature("btap_uo", v[:uo])
          end
        end
      end

      @model[:comply  ] = comply
      @model[:complies] = complies
      @model[:perform ] = perform
      @model[:quality ] = quality
      @model[:combo   ] = combo

      # Run "process" TBD one last time, on "model" (not cloned "mdl").
      TBD.clean!
      res = TBD.process(model, args)

      @model[:io      ] = res[:io      ] # TBD outputs (i.e. "tbd.out.json")
      @model[:surfaces] = res[:surfaces] # TBD derated surface data
      @model[:argh    ] = argh           # method argument hash
      @model[:args    ] = args           # last TBD inputs (i.e. "tbd.json")

      self.gen_tallies                   # tallies for BTAP costing
      self.gen_feedback                  # log success messages for BTAP
    end

    ##
    # Populates and validates BTAP/TBD & OpenStudio model parameters for thermal
    # bridging. This also does a safe TBD trial run, returning true if
    # successful. Check @feedback logs if false.
    #
    # @param model [OpenStudio::Model::Model] a model
    # @param [Hash] argh BTAP/TBD argument hash
    # @option argh [BTAP::Structure] :structure a BTAP STRUCTURE instance
    # @option argh [Hash] :walls exterior wall parameters (:uo, :ut)
    # @option argh [Hash] :floors exposed floor parameters (:uo, :ut)
    # @option argh [Hash] :roofs exterior roof parameters (:uo, :ut)
    # @option argh [:good, :bad] :quality of thermal bridging (derating only)
    # @option argh [Boolean] :interpolate between costed Uo (uprate only)
    #
    # @return [Boolean] true if valid (check @feedback logs if false)
    def populate(model = nil, argh = {})
      mth  = "BTAP::Bridging::#{__callee__}"
      args = { option: "(non thermal bridging)" } # for initial TBD dry run
      lgs  = @feedback[:logs]
      cl   = OpenStudio::Model::LayeredConstruction

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid OpenStudio model to de/up-rate (#{mth})"
        return false
      end

      unless argh.is_a?(Hash)
        lgs << "Invalid BTAP/TBD argument Hash (#{mth})"
        return false
      end

      if argh.key?(:structure)
        stc = argh[:structure]

        unless stc.is_a?(BTAP::Structure)
          lgs << "Invalid BTAP::Structure (#{mth})"
          return false
        end
      else
        lgs << "Missing STRUCTURE key (#{mth})"
        return false
      end

      argh[:interpolate] = false unless argh.key?(:interpolate)
      argh[:interpolate] = false unless [true, false].include?(argh[:interpolate])

      [:walls, :floors, :roofs].each do |stypes|
        unless argh.key?(stypes)
          lgs << "Missing BTAP/TBD #{stypes} (#{mth})"
          return false
        end

        unless argh[stypes].key?(:uo)
          lgs << "Missing BTAP/TBD #{stypes} Uo (#{mth})"
          return false
        end

        uo = argh[stypes][:uo]

        unless uo.is_a?(Numeric) && uo.between?(TBD::UMIN, TBD::UMAX)
          lgs << "Invalid BTAP/TBD #{stypes} Uo (#{mth})"
          return false
        end

        next unless argh[stypes].key?(:ut)

        ut = argh[stypes][:ut]

        unless ut.is_a?(Numeric) && ut.between?(TBD::UMIN, TBD::UMAX)
          lgs << "Invalid BTAP/TBD #{stypes} Ut (#{mth})"
          return false
        end
      end

      # Run TBD on a cloned OpenStudio model (dry run).
      TBD.clean!
      mdl = OpenStudio::Model::Model.new
      mdl.addObjects(model.toIdfFile.objects)
      res = TBD.process(mdl, args)

      # TBD validation of the OpenStudio model.
      if TBD.fatal? || TBD.error?
        lgs << "TBD-identified FATAL error(s):"     if TBD.fatal?
        lgs << "TBD-identified non-FATAL error(s):" if TBD.error?

        TBD.logs.each { |log| lgs << log[:message] }
        return false if TBD.fatal?
      end

      if res[:surfaces].nil?
        lgs << "No deratable surfaces in model (#{mth})"
        return false
      end

      # Within BTAP, a building must reference a default construction set.
      if model.getBuilding.defaultConstructionSet.empty?
        lgs << "No BUILDING default construction set (#{mth})"
        return false
      else
        bset = model.getBuilding.defaultConstructionSet.get
      end

      # Fetch number of stories.
      stories = model.getBuilding.standardsNumberOfAboveGroundStories
      stories = stories.get                  unless stories.empty?
      stories = model.getBuildingStorys.size unless stories.is_a?(Integer)

      @model[:stories] = stories.clamp(1, 999)

      # Initialize deratable constructions, spaces & surface types.
      @model[:constructions] = {}
      @model[:spaces       ] = {}
      @model[:stypes       ] = []

      # Generate TBD input hashes for both :good & :bad PSI factor sets. These
      # depend solely on assigned wall constructions (e.g. steel- vs wood-
      # framed) - not roof or floor construction. By default, a single PSI
      # factor set is assigned for the building. If users request customized,
      # space-specific structural/envelope, matching PSI-factor sets are added.
      #   - 1x set as the building-wide default
      #   - ?x set(s) for user-customized spaces
      #   - see NECB2011/building_envelope.rb's "add_construction_sets"
      #
      # ADAPT SO IT CAN TAKE pre-set btap_id as :identifier hash key.
      @model[:psi]           = {}
      @model[:psi][:lp_bad ] = self.inputs(stc, :lp, :bad)
      @model[:psi][:lp_good] = self.inputs(stc, :lp, :good)
      @model[:psi][:hp_bad ] = self.inputs(stc, :hp, :bad)
      @model[:psi][:hp_good] = self.inputs(stc, :hp, :good)

      # Process surfaces deemed 'deratable' by TBD. Match PSI factor sets with
      # generated BTAP default construction sets.
      res[:surfaces].each do |identifier, surface|
        next unless surface.key?(:type)      # :wall, :ceiling or :floor
        next unless surface.key?(:net)       # surface net area
        next unless surface.key?(:index)     # deratable layer index
        next unless surface.key?(:r)         # deratable layer RSi
        next unless surface.key?(:deratable) # true or false
        next unless surface[:deratable]
        next unless surface[:index]

        stypes = case surface[:type]
                 when :wall    then :walls
                 when :floor   then :floors
                 when :ceiling then :roofs
                 else ""
                 end

        next if stypes.empty?

        # Track surface types.
        @model[:stypes] << stypes unless @model[:stypes].include?(stypes)

        # Track TBD-targeted constructions for uprating/derating.
        srf = model.getSurfaceByName(identifier)

        if srf.empty?
          lgs << "Mismatched surface: #{identifier} (#{mth})?"
          return false
        end

        srf   = srf.get
        space = srf.space

        if space.empty?
          lgs << "Missing space: #{id} (#{mth})?"
          return false
        end

        space = space.get
        spID  = space.nameString
        lc    = srf.construction

        if lc.empty?
          lgs << "Mismatched construction: #{id} (#{mth})?"
          return false
        end

        lc = lc.get.to_LayeredConstruction

        if lc.empty?
          lgs << "Mismatched layered construction: #{id} (#{mth})?"
          return false
        end

        lc = lc.get
        id = lc.nameString

        # Deratable constructions may have previously inherited the following
        # AdditionalProperties, if constructions were generated based on
        # 'structural' options or customized (see BTAP::Structure):
        #   - "btap_type" : TBD surface type ("walls", "roofs" or "floors")
        #   - "btap_film" : area-weighted surface air film resistances
        #   - "btap_uo"   : NECB-prescribed U-factor (clear-field OR total)
        #   - "btap_id"   : BTAP costed construction ID (e.g. MASS2)
        btap_type = lc.additionalProperties.getFeatureAsString("btap_type")
        btap_film = lc.additionalProperties.getFeatureAsDouble("btap_film")
        btap_uo   = lc.additionalProperties.getFeatureAsDouble("btap_uo")
        btap_id   = lc.additionalProperties.getFeatureAsString("btap_id")

        if btap_type.empty?
          btap_type = stypes
        else
          btap_type = btap_type.get.downcase.to_sym
          btap_type = stypes unless btap_type == stypes # vet instead? @todo
        end

        btap_film = btap_film.empty? ? filmR(lc)            : btap_film.get
        btap_uo   = btap_uo.empty?   ? argh[btap_type][:uo] : btap_uo.get

        if btap_id.empty?
          opts           = {}
          opts[:stype  ] = btap_type
          opts[:perform] = :lp

          if stc[:spaces].key?(spID)
            opts[:framing ] = stc[:spaces][spID][:framing]
            opts[:cladding] = stc[:spaces][spID][:cladding]
            opts[:finish  ] = stc[:spaces][spID][:finish]
          else
            opts[:framing ] = stc.framing
            opts[:cladding] = stc.cladding
            opts[:finish  ] = stc.finish
          end

          btap_id = costed_assembly(opts)

          unless costed_uo(id, btap_uo)
            opts[:perform] = :hp
            btap_id = costed_assembly(opts)
          end
        else
          btap_id = btap_id.get

          unless data.key?(btap_id)
            opts           = {}
            opts[:stype  ] = btap_type
            opts[:perform] = :lp

            if stc[:spaces].key?(spID)
              opts[:framing ] = stc[:spaces][spID][:framing]
              opts[:cladding] = stc[:spaces][spID][:cladding]
              opts[:finish  ] = stc[:spaces][spID][:finish]
            else
              opts[:framing ] = stc.framing
              opts[:cladding] = stc.cladding
              opts[:finish  ] = stc.finish
            end

            btap_id = costed_assembly(opts)

            unless costed_uo(id, btap_uo)
              opts[:perform] = :hp
              btap_id = costed_assembly(opts)
            end
          end
        end

        unless @model[:constructions].key?(id)
          @model[:constructions][id]             = {}
          @model[:constructions][id][:index    ] = surface[:index] # material
          @model[:constructions][id][:r        ] = surface[:r]     # material
          @model[:constructions][id][:uo       ] = btap_uo         # assembly
          @model[:constructions][id][:compliant] = nil             # assembly
          @model[:constructions][id][:btap_id  ] = btap_id         # assembly
          @model[:constructions][id][:m2       ] = 0               # cumulative
          @model[:constructions][id][:btap_film] = btap_film       # weighted
          @model[:constructions][id][:stypes   ] = []
          @model[:constructions][id][:surfaces ] = []
          @model[:constructions][id][:spaces   ] = []
        end

        @model[:constructions][id][:m2      ] += surface[:net]
        @model[:constructions][id][:stypes  ] << stypes
        @model[:constructions][id][:surfaces] << identifier
        @model[:constructions][id][:spaces  ] << spID
      end

      nb = 0 # number of deratable walls in the model

      # Loop through all tracked deratable constructions. Ensure a single
      # surface type per construction. Ensure at least one wall construction.
      @model[:constructions].values.each { |v| v[:stypes].uniq! }
      @model[:constructions].values.each { |v| v[:spaces].uniq! }

      @model[:constructions].each do |id, v|
        if v[:stypes].size != 1
          # @todo : Revise if multiple surface types per construction.
          # Clone construction as needed to ensure surface type uniqueness.
          lgs << "Multiple surface types rely on #{id} (#{mth})?"
          return false
        else
          v[:stypes] = v[:stypes].first
          lc = model.getConstructionByName(id)

          if lc.empty?
            lgs << "Mismatched construction: #{id} (#{mth})?"
            return false
          end

          lc = lc.get.to_LayeredConstruction

          if lc.empty?
            lgs << "Mismatched layered construction: #{id} (#{mth})?"
            return false
          end

          lc = lc.get

          # Hard-set construction to each deratable surface.
          v[:surfaces].each do |name|
            surface = model.getSurfaceByName(name)
            next if surface.empty?

            surface.get.setConstruction(lc)
            lc.additionalProperties.setFeature("btap_type", v[:stypes].to_s)
            lc.additionalProperties.setFeature("btap_film", v[:btap_film])
            lc.additionalProperties.setFeature("btap_uo",   v[:btap_uo])
            lc.additionalProperties.setFeature("btap_id",   v[:btap_id])
          end
        end

        nb += 1 if v[:stypes] == :walls
      end

      if nb < 1
        lgs << "No deratable walls (#{mth})?"
        return false
      end

      @model[:osm] = model

      true
    end

    ##
    # Generate TBD input hash.
    #
    # @param structure [BTAP::Structure] BTAP::Structure object
    # @option perform [Symbol] performance variant (:lp or :hp)
    # @option quality [Symbol] PSI-factor set selection (:bad or :good)
    #
    # @return [Hash] TBD inputs (empty if invalid input)
    def inputs(structure = nil, perform = :hp, quality = :good)
      input   = {}
      psis    = {} # construction-specific PSI sets
      spaces  = {} # custom space-specific PSI references
      perform = :hp   unless [:lp, :hp   ].include?(perform)
      quality = :good unless [:bad, :good].include?(quality)
      return input    unless structure.is_a?(BTAP::Structure)

      argh            = {}
      argh[:stype   ] = :walls
      argh[:perform ] = perform
      argh[:framing ] = structure.framing
      argh[:cladding] = structure.cladding
      argh[:finish  ] = structure.finish

      assembly = self.costed_assembly(argh)
      bldg_psi = self.set(assembly, quality)

      # A single PSI-factor set for the building.
      psis[bldg_psi[:id]] = bldg_psi

      # Add PSI-factor sets for customized spaces, e.g.
      #   - "cmu" gymnasium walls in an otherwise "steel" post/frame school
      structure.spaces.each do |id, csp|
        argh[:framing ] = csp[:framing]
        argh[:cladding] = csp[:cladding]
        argh[:finish  ] = csp[:finish]

        cassembly = self.costed_assembly(argh)
        next if cassembly == assembly

        space_psi = self.set(cassembly, quality)
        next if psis.key?(space_psi[:id])

        # Append customized PSI-factor set.
        psis[space_psi[:id]] = space_psi

        # Add reference to customized space PSI-factor set.
        spaces[id] = { id: id, psi: space_psi[:id] }
      end

      # TBD JSON schema added as a reminder. No schema validation in BTAP.
      schema = "https://github.com/rd2/tbd/blob/master/tbd.schema.json"

      input[:schema     ] = schema
      input[:description] = "TBD input for BTAP"
      input[:psis       ] = psis.values
      input[:spaces     ] = spaces.values
      input[:building   ] = { psi: bldg_psi[:id] }

      input
    end

    ##
    # Generate BTAP/TBD tallies
    #
    # @return [Boolean] true if BTAP/TBD tally is successful
    def gen_tallies
      edges = {}
      return false unless @model.key?(:io)
      return false unless @model.key?(:constructions)
      return false unless @model[:io].key?(:edges)

      @model[:io][:edges].each do |e|
        # Content of TBD-generated 'edges' (hashes):
        #      psi: BTAP PSI set ID, e.g. "BTAP-ExteriorWall-Mass-6 good"
        #     type: thermal bridge type, e.g. :corner
        #   length: (in m)
        # surfaces: linked OpenStudio surface IDs
        edges[e[:type]]           = {} unless edges.key?(e[:type])
        edges[e[:type]][e[:psi]]  = 0  unless edges[e[:type]].key?(e[:psi])
        edges[e[:type]][e[:psi]] += e[:length]
      end

      return false if edges.empty?

      @tally[:edges] = edges
      @tally[:constructions] = @model[:constructions]

      true
    end

    ##
    # Generate BTAP/TBD post-processing feedback.
    #
    # @return [Boolean] true if valid BTAP/TBD model
    def gen_feedback
      lgs = @feedback[:logs]
      return false unless @model.key?(:complies) # all model constructions
      return false unless @model.key?(:comply)   # surface type specific ...
      return false unless @model.key?(:argh)     # BTAP/TBD inputs + ouputs
      return false unless @model.key?(:stypes)   # :walls, :roofs, :floors

      argh = @model[:argh]

      # Uprating. Report first on surface types (compliant or not).
      @model[:stypes].each do |stypes|
        next unless @model[:comply].key?(stypes)

        ut  = format("%.3f", argh[stypes][:ut])
        lg  = @model[:comply][stypes] ? "Compliant " : "Non-compliant "
        lg += "#{stypes}: Ut #{ut} W/m2.K"
        lgs << lg

        # Report then on required Uo factor per construction (compliant or not).
        @model[:constructions].each do |ide, v|
          next unless v.key?(:stypes)
          next unless v.key?(:uo)
          next unless v.key?(:compliant)
          next unless v.key?(:surfaces)
          next unless v[:stypes  ] == stypes
          next     if v[:surfaces].empty?

          uo  = format("%.3f", v[:uo])
          lg  = v[:compliant] ? "   Compliant " : "   Non-compliant "
          lg += "#{ide} Uo #{uo} (W/K.m2)"
          lgs << lg
        end
      end

      # Summary of TBD-derated constructions.
      @model[:osm].getSurfaces.each do |s|
        next if s.construction.empty?
        next if s.construction.get.to_LayeredConstruction.empty?

        lc = s.construction.get.to_LayeredConstruction.get
        id = lc.nameString
        next unless id.include?(" c tbd")

        rsi  = TBD.rsi(lc, s.filmResistance)
        usi  = format("%.3f", 1/rsi)
        rsi  = format("%.1f", rsi)
        area = format("%.1f", lc.getNetArea) + " m2"

        lgs << "~ '#{id}' derated Rsi: #{rsi} [Usi #{usi} x #{area}]"
      end

      # Log PSI factor tallies (per thermal bridge type).
      if @tally.key?(:edges)
        @tally[:edges].each do |type, e|
          next if type == :transition

          lgs << "# '#{type}' (#{e.size}x):"

          e.each do |psi, length|
            lgs << "... PSI set '#{psi}' : #{format("%.2f", length)} m"
          end
        end
      end

      true
    end

    # Retrieve the material quantities for the values in the tbd.edges
    # parameter.
    # @return [Hash] IDs mapped to their quantities in feet.
    def get_material_quantities_for_edges
      cp                  = CommonPaths.instance
      csv                 = CSV.read(cp.thermal_bridging_path, headers: true)
      material_quantities = {}

      # The "convex/concave" suffix on tally edges can be safely ignored since
      # they currently aren't relevant to any NECB standard, but they are to
      # ASHRAE 90.1.
      tally_edges = @tally[:edges].transform_keys { |key| key.to_s.gsub(/concave|convex/, '') }
      tally_edges.each do |edge_type, value|
        value.each do |wall_reference_and_quality, quantity|

          # "transition" edges aren't considered.
          if edge_type == "transition"
            next

          # "jamb", "sill", and "head" may all be grouped under fenestration
          # when referencing the thermal bridging CSV. Same for "skylightjamb",
          # "skylightsill", and "skylighthead".
          elsif edge_type.match?(/^(skylight)?(jamb|sill|head)$/)
            edge_type = "fenestration"
          end

          result = csv.find do |row|
            row["edge_type"]      == edge_type &&
            row["wall_reference"] == wall_reference_and_quality
          end

          if result.nil?
            puts("Wall with type #{edge_type} and reference #{wall_reference_and_quality}" \
                 " could not be found in the thermal bridging database")
            next
          end

          material_opaque_id_layers = result['material_opaque_id_layers'].split(",")
          id_layers_quantity_multipliers = result['id_layers_quantity_multipliers'].split(",")
          material_opaque_id_layers.zip(id_layers_quantity_multipliers).each do |id, scale|
            if material_quantities[id].nil?
              material_quantities[id] = 0.0
            end

            material_quantities[id] = material_quantities[id] + scale.to_f * quantity
          end
        end
      end

      return material_quantities
    end

    # Remove most instance variables from the TBD object. This is a temporary
    # workaround for getting caching to work since the TBD object is very deeply
    # nested with member attributes. A bug exists in ruby which causes the
    # `inspect` method to hang for such objects:
    # https://bugs.ruby-lang.org/issues/6783

    # This prevents inspecting the object in an interactive debug shell without
    # a file pager and prevents writing the object to a file.
    def shorten_instance_variables
      self.instance_variables.filter { |variable| variable != :@tally and variable != :@model }.each do |variable|
        remove_instance_variable(variable)
      end
      @model.keys.filter { |value| value != :perform }.each do |value|
        @model.delete(value)
      end
      @tally.delete(:constructions)
    end
  end
end

# ----- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----- #
# Note: BTAP supports Uo variants for each of the aforementioned wall
#       constructions, e.g. meeting NECB2011 and NECB2015 prescriptive "Uo"
#       requirements for each NECB climate zone. By definition, these Uo
#       variants ignore the effects of MAJOR linear thermal bridging, such as
#       intermediate slab edges. This does not imply that NECB2011 and NECB2015
#       do not hold prescriptive requirements for MAJOR linear thermal bridging.
#       There are indeed a handful of general, descriptive requirements (those
#       of the MNECB1997) that would make NECB2011- and NECB2015-compliant
#       buildings slightly better than BTAPPRE1980 bottom-of-the-barrel
#       construction, but likely not any better than circa 1990s run-of-the-mill
#       commercial construction. Currently, BTAP does not assess the impact of
#       MAJOR linear thermal bridging for vintages < NECB2017. But ideally it
#       SHOULD, if the goal remains a fair assessment of the (relative)
#       contribution of more recent NECB requirements (e.g. 2025).

# Note: The original BTAP costing database holds entries for curtain wall (CW)
#       spandrel inserts above/below fenestration for certain spacetypes. This
#       is yet to be implemented. This note is an "aide-mémoire" for future
#       consideration. The BETBG does not hold any CW glazed spandrels achieving
#       U-factors ANYWHERE near NECB requirements, regardless of NECB vintage or
#       NECB climate zone. Same for the 'Guide to Low Thermal Energy Demand for
#       Large Buildings'. It seems the original intent was to rely on BTAP
#       variants "Metal-2" and "Metal-3" as HP CW spandrels ACTUALLY achieving
#       NECB prescriptive targets, which could only be possible in practice at
#       great cost and effort (e.g. a 2nd insulated wall behind the spandrel).
#
#       If TBD's uprating calculations (e.g. NECB 2017) were in theory no longer
#       required, BTAP's treatment of HP CW spandrels could be implemented
#       strictly as a costing adjustment: energy simulation models wouldn't have
#       to be altered. Otherwise, adaptations would be required. PSI factors are
#       noticeably different for spandrels (obviously no lintels/shelf-angles).
#       More importantly, the default assumption with CW technology is that
#       there wouldn't be any linear thermal bridges along shared vision vs
#       spandrel edges (as perimeter heat loss would already have been taken
#       into as consideration, as per NFRC or CSA rating methodologies). On the
#       other hand, CW vision jambs along non-CW assemblies (i.e. original BTAP
#       goal) most certainly constitute (new) MAJOR linear thermal bridges to
#       consider (just as with shared edges between spandrels and other wall
#       assemblies). Again, none of these features are currently implemented
#       within BTAP. Recommended (future) solution, if desired:
#
#         - Automated OSM façade-splitting feature
#           - insert spandrels above/below windows
#           - simple cases only e.g., vertical, no overlaps, h > 200mm
#             - split above/below plenum walls as well
#
#        - Further develop PSI sets to cover CWs (see below)
#          - e.g. PSI factors for CW vision "jamb" transitions
#          - e.g. PSI factors for CW spandrel "jamb" transitions
#
#       These added features would simplify the process tremendously. Yet
#       without admissible CW spandrel U-factors down to 0.130 or 0.100 W/m2.K,
#       this would make it pretty much impossible to identify NECB2017 through
#       NECB2025 compliant combinations of Uo+PSI factors.

# Note: Some of the aforementioned constructions have exterior brick veneer.
#       For 2-story OpenStudio models with punch windows (i.e. not strip
#       windows), one would NOT expect a continuous steel shelf angle along the
#       intermediate floor slab edge (typically a MAJOR linear thermal bridge).
#       One would instead expect loose lintels above punch windows, just as with
#       doors. Loose lintels usually compound heat loss along window head edges,
#       but are currently considered as factored in the retained PSI factors for
#       window and door head details (a postulate that likely needs revision).
#       For taller builings, shelf angles are indeed expected. And if windows
#       are instead strip windows (not punch windows), then loose lintels would
#       typically be cast aside in favour of an offset shelf angle (even for
#       1-story buildings).
#
#       Many of the US DOE Commercial Benchmark Building and BTAP models are
#       1-story or 2-stories in height, yet they ALL have strip windows as their
#       default fenestration layout. As a result, BTAP/TBD presumes continuous
#       shelf angles, offset by the height difference between slab edge and
#       window head. Loose lintels are however included in the clear field
#       costing ($/m2), yet should be limited to doors (@todo). A more flexible,
#       general solution would be required for 3rd-party OpenStudio models
#       (without strip windows as a basic fenestration layout).
