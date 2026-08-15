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
    # @option argh [Symbol] :perform (:lp or :hp) wall variant
    # @option argh [Symbol] :framing (:steel, :wood, :cmu)
    # @option argh [Symbol] :cladding (:heavy)
    # @option argh [Symbol] :finish (:heavy)
    # @option argh [String] :id a BTAP-costed assembly (often :lp)
    # @option argh [Float] :uo desired U-factor
    #
    # @return [String] BTAP costed assembly identifier
    def costed_assembly(argh = {})
      return STEL2 unless argh.respond_to?(:keys)

      # Key input.
      stype = argh.key?(:stype) ? argh[:stype] : :walls
      stype = :walls unless [:roofs, :floors].include?(stype)

      # No BTAP variants yet for roofs or floors.
      return ROOF  if stype == :roofs
      return FLOOR if stype == :floors

      # Low-performance (:lp) or high-performance (:hp) variant?
      perform = argh.key?(:perform) ? argh[:perform] : :lp
      perform = :lp unless perform == :hp

      # Prioritizing BTAP-costed wall assembly identifiers.
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

      # Relying instead on STRUCTURE-based parameters.
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
    # Initializes BTAP/TBD data, uprates/derates, generates output.
    #
    # @param model [OpenStudio::Model::Model] a model
    # @param [Hash] argh BTAP/TBD argument hash
    # @option argh [BTAP::Structure] :structure a BTAP STRUCTURE instance
    # @option argh [Hash] :walls exterior wall parameters (:uo, :ut)
    # @option argh [Hash] :floors exposed floor parameters (:uo, :ut)
    # @option argh [Hash] :roofs exterior roof parameters (:uo, :ut)
    # @option argh [:good, :bad] :quality of thermal bridging (derating)
    # @option argh [Boolean] :interpolate between costed Uo factors (uprating)
    def initialize(model = nil, argh = {})
      mth = "BTAP::Bridging::#{__callee__}"

      # Track warnings & errors.
      @feedback = {logs: []}
      lgs = @feedback[:logs]

      # Store model & arguments.
      @model = {osm: model, argh: argh}

      # Validate and populate BTAP/TBD & OpenStudio model parameters. This does
      # a safe TBD trial run, returning true if successful. If false, TBD leaves
      # the model unaltered. Check @feedback logs.
      return unless populate

      # Tracking uprating success, separately for :walls, :roofs vs :floors.
      comply = {}

      # TRUE if TBD successfully uprates all surface types.
      complies = false

      # Initialize TBD's own argument hash.
      args = {option: "", io_path: inputs( @model[:quality] )}

      # Uprating? Possibly 2x trial runs to identify candidate constructions.
      2.times do |i|
        break unless @model[:uprating]
        break if complies
        break if @model[:quality] == :good && i > 0

        # Reset overall PSI factor quality.
        @model[:quality] = :good unless i.zero?

        # Reset TBD arguments.
        args = {option: "", io_path: inputs( @model[:quality] )}

        # Add surface type (uprating) inputs to TBD argument hash.
        @model[:stypes].each do |stypes, u|
          stype  = stypes.to_s.chop               # e.g. "wall" (from :walls)
          uprate = "uprate_#{stypes.to_s}".to_sym # e.g. :uprate_walls
          option = "#{stype}_option".to_sym       # e.g. :wall_option
          ut     = "#{stype}_ut".to_sym           # e.g. :wall_ut

          args[uprate] = true
          args[option] = "ALL #{stype} constructions"
          args[ut    ] = u[:ut]

          comply[stypes] = false
        end

        # Trial runs on cloned OpenStudio model.
        mdl = OpenStudio::Model::Model.new
        mdl.addObjects(model.toIdfFile.objects)
        TBD.clean!
        TBD.process(mdl, args)

        # If uprating is successful, TBD 'args' hash holds (new) uprated Uo
        # keys/values for :walls, :floors and/or :roofs.
        complies = true

        # Even if all constructions were successfully uprated by TBD, BTAP
        # may not hold costed assembly variants that match required targets.
        # If TBD-uprated Uo factors are lower than any of these admissible
        # BTAP Uo factors, the solution logs the failed attempt and defaults
        # to the lowest Uo factors in the BTAP costing database.
        @model[:stypes].keys.each do |stypes|
          break unless complies

          # Initialize.
          comply[stypes] = true

          stype_uo = "#{stypes.to_s.chop}_uo".to_sym
          target   = args.key?(stype_uo) ? args[stype_uo] : nil

          unless target
            comply[stypes] = false
            complies = false
            next
          else
            bOPTs         = {} # building
            bOPTs[:id   ] = @model[:building][stypes][:id]
            bOPTs[:stype] = stypes
            bOPTs[:uo   ] = target
            bID = costed_assembly(bOPTs)

            unless costed_uo(bID, target)
              comply[stypes] = false
              complies = false
              next
            end

            unless @model[:attic][stypes].empty?
              types = case stypes
                      when :roofs  then :floors
                      when :floors then :roofs
                      else              :walls
                      end

              aOPTs         = {} # attic(s)
              aOPTs[:id   ] = @model[:attic][types][:id]
              aOPTs[:stype] = types
              aOPTs[:uo   ] = target
              aID = costed_assembly(aOPTs)

              unless costed_uo(aID, target)
                comply[types] = false
                complies = false
                next
              end
            end

            @model[:spaces].each do |id, sp|
              break unless comply[stypes]

              sOPTs         = {} # customized spaces
              sOPTs[:id   ] = sp[stypes][:id]
              sOPTs[:stype] = stypes
              sOPTs[:uo   ] = target
              sID = costed_assembly(sOPTs)

              unless costed_uo(sID, target)
                comply[stypes] = false
                complies = false
                next
              end
            end
          end
        end

        # Skip if first iteration fails.
        next if i.zero? && complies == false

        @model[:stypes].each do |stypes, u|
          stype_uo = "#{stypes.to_s.chop}_uo".to_sym
          target   = args.key?(stype_uo) ? args[stype_uo] : nil

          if target
            u[:uo] = target

            bOPTs         = {} # building
            bOPTs[:id   ] = @model[:building][stypes][:id]
            bOPTs[:stype] = stypes
            bOPTs[:uo   ] = target
            bID = costed_assembly(bOPTs)

            @model[:building][stypes][:id] = bID
            bUo = costed_uo(bID, target)

            if bUo
              bUo = target if @model[:interpolate]

              # Candidate construction successfully identified.
              @model[:building][stypes][:compliant] = true
              @model[:building][stypes][:uo       ] = bUo
            else
              bUo = lowest_uo(bID)
              comply[stypes] = false
              complies = false

              # Fallback.
              @model[:building][stypes][:compliant] = false
              @model[:building][stypes][:uo       ] = bUo
            end

            unless @model[:attic][stypes].empty?
              types = case stypes
                      when :roofs  then :floors
                      when :floors then :roofs
                      else              :walls
                      end

              aOPTs         = {} # attic
              aOPTs[:id   ] = @model[:attic][types][:id]
              aOPTs[:stype] = types
              aOPTs[:uo   ] = target
              aID = costed_assembly(aOPTs)

              @model[:attic][types][:id] = aID
              aUo = costed_uo(aID, target)

              if aUo
                aUo = target if @model[:interpolate]

                # Candidate construction successfully identified.
                @model[:attic][types][:compliant] = true
                @model[:attic][types][:uo       ] = aUo
              else
                aUo = lowest_uo(aID)
                comply[types] = false
                complies = false

                # Fallback.
                @model[:attic][types][:compliant] = false
                @model[:attic][types][:uo       ] = aUo
              end
            end

            @model[:spaces].each do |id, sp|
              sOPTs         = {} # customized space(s)
              sOPTs[:id   ] = sp[stypes][:id]
              sOPTs[:stype] = stypes
              sOPTs[:uo   ] = target
              sID = costed_assembly(sOPTs)

              sp[stypes][:id] = sID
              sUo = costed_uo(sID, target)

              if sUo
                sUo = target if @model[:interpolate]

                # Candidate construction successfully identified.
                sp[stypes][:compliant] = true
                sp[stypes][:uo       ] = sUo
              else
                sUo = lowest_uo(sID)
                comply[stypes] = false
                complies = false

                # Fallback.
                sp[stypes][:compliant] = false
                sp[stypes][:uo] = sUo
              end
            end
          else
            comply[stypes] = false
            complies = false

            bID = @model[:building][stypes][:id]
            bUo = lowest_uo(bID)

            bOPTs         = {}
            bOPTs[:id   ] = bID
            bOPTs[:stype] = stypes
            bOPTs[:uo   ] = bUo
            bID = costed_assembly(bOPTs)
            bUo = costed_uo(bID, bUo)

            @model[:building][stypes][:compliant] = false
            @model[:building][stypes][:id       ] = bID
            @model[:building][stypes][:uo       ] = bUo

            u[:uo] = bUo

            unless @model[:attic][stypes].empty?
              types = case stypes
                      when :roofs  then :floors
                      when :floors then :roofs
                      else              :walls
                      end

              aID = @model[:building][types][:id]
              aUo = lowest_uo(aID)

              aOPTs         = {}
              aOPTs[:id   ] = aID
              aOPTs[:stype] = types
              aOPTs[:uo   ] = aUo
              aID = costed_assembly(aOPTs)
              aUo = costed_uo(aID, aUo)

              @model[:attic][types][:compliant] = false
              @model[:attic][types][:id       ] = aID
              @model[:attic][types][:uo       ] = aUo
            end

            @model[:spaces].each do |id, sp|
              sID = sp[stypes][:id]
              sUo = lowest_uo(sID)

              sOPTs         = {}
              sOPTs[:id   ] = sID
              sOPTs[:stype] = stypes
              sOPTs[:uo   ] = sUo
              sID = costed_assembly(sOPTs)
              sUo = costed_uo(sID, sUo)

              sp[stypes][:compliant] = false
              sp[stypes][:id       ] = sID
              sp[stypes][:uo       ] = sUo
            end
          end
        end
      end

      # Post-loop steps (if uprating).
      @model[:stypes].each do |stypes, u|
        next unless comply.key?(stypes) # true only if uprating

        # Reset uprated Uo factor for each 'deratable' construction.
        bLC  = @model[:building][stypes][:lc]
        bFr  = @model[:building][stypes][:film]
        bIx  = @model[:building][stypes][:indx]
        bUo  = @model[:building][stypes][:uo]
        bRSI = TBD.resetUo(bLC, bFr, bIx, bUo)

        # Re/set Uo as AdditionalProperty:
        addprop(bLC, "btap_uo", bUo)

        # Repeat for attics (if applicable).
        unless @model[:attic][stypes].empty?
          types = case stypes
                  when :roofs  then :floors
                  when :floors then :roofs
                  else              :walls
                  end

          aLC  = @model[:attic][types][:lc]
          aFr  = @model[:attic][types][:film]
          aIx  = @model[:attic][types][:indx]
          aUo  = @model[:attic][types][:uo]
          aRSI = TBD.resetUo(aLC, aFr, aIx, aUo)

          # Re/set Uo as AdditionalProperty:
          addprop(aLC, "btap_uo", aUo)
        end

        # Repeat for customized spaces (if applicable).
        @model[:spaces].values.each do |sp|
          sLC = sp[stypes][:lc]
          sFr = sp[stypes][:film]
          sIx = sp[stypes][:indx]
          sUo = sp[stypes][:uo]
          sRSI = TBD.resetUo(sLC, sFr, sIx, sUo)

          # Re/set Uo as AdditionalProperty:
          addprop(sLC, "btap_uo", sUo)
        end
      end

      complies = true unless @model[:uprating]
      @model[:comply  ] = comply   # true/false, specific to surface type
      @model[:complies] = complies # true/false for entire model

      # Run "process" TBD one last time, on "model" (not cloned "mdl").
      args = {option: "", io_path: inputs( @model[:quality] )}
      TBD.clean!
      TBD.process(model, args)

      @model[:args    ] = args # last TBD inputs (i.e. "tbd.json")
      @model[:io      ] = args[:io]
      @model[:surfaces] = args[:surfaces]

      gen_tallies  # tallies for BTAP costing
      gen_feedback # log success messages for BTAP
    end

    ##
    # Minimally validates an OpenStudio model, as well as BTAP/TBD parameters,
    # towards thermal bridging calculations. This also does a safe TBD trial
    # run, returning true if successful. Check @feedback logs if false.
    # AdditionalProperties may be re/set in the OpenStudio model.
    #
    # @return [Boolean] true if valid (check @feedback logs if false)
    def populate()
      mth = "BTAP::Bridging::#{__callee__}"
      lgs = @feedback[:logs]
      cl  = OpenStudio::Model::LayeredConstruction

      model = @model[:osm]
      argh  = @model[:argh]

      # Valid model?
      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid OpenStudio model to de/up-rate (#{mth})"
        return false
      end

      # Valid argument hash?
      unless argh.is_a?(Hash)
        lgs << "Invalid BTAP/TBD argument Hash (#{mth})"
        return false
      end

      # Valid BTAP::Structure instance?
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

      # Uprating? Initialize.
      @model[:uprating] = false

      # All 3 surface types initiated?
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

        # Uprating!
        @model[:uprating] = true if stypes == :walls
        ut = argh[stypes][:ut]

        unless ut.is_a?(Numeric) && ut.between?(TBD::UMIN, TBD::UMAX)
          lgs << "Invalid BTAP/TBD #{stypes} Ut (#{mth})"
          return false
        end
      end

      # When uprating: interpolating between discrete Uo factors?
      @model[:interpolate] = argh.key?(:interpolate) ? argh[:interpolate] : true
      @model[:interpolate] = false unless @model[:interpolate] == true

      # Selected PSI factor quality (:good or :bad):
      #   - required when strictly derating
      #   - iteratively reset when uprating
      @model[:quality] = argh.key?(:quality) ? argh[:quality] : :bad
      @model[:quality] = :bad unless @model[:quality] == :good

      # NECB 2011-2015 Uo targets.
      wUo = argh[:walls ][:uo]
      rUo = argh[:roofs ][:uo]
      fUo = argh[:floors][:uo]

      # NECB 2017-2025 Ut targets - Uo is reset when uprating.
      wUt = argh[:walls ].key?(:ut) ? argh[:walls ][:ut] : wUo
      rUt = argh[:roofs ].key?(:ut) ? argh[:roofs ][:ut] : rUo
      fUt = argh[:floors].key?(:ut) ? argh[:floors][:ut] : fUo

      # Track building, attic(s), customized spaces & actual surface types.
      @model[:building] = {walls: {}, roofs: {}, floors: {}}
      @model[:attic   ] = {walls: {}, roofs: {}, floors: {}}
      @model[:spaces  ] = {}
      @model[:stypes  ] = {}

      # Track constructions. REMOVE @todo.
      @model[:constructions] = {}

      # Track 'building' default construction set.
      bldg = model.getBuilding
      bset = bldg.defaultConstructionSet

      if bset.empty?
        lgs << "No BUILDING default construction set (#{mth})"
        return false
      end

      bset = bset.get
      extC = bset.defaultExteriorSurfaceConstructions

      if extC.empty?
        lgs << "No BUILDING default exterior constructions (#{mth})"
        return false
      end

      wallC   = extC.get.wallConstruction
      roofC   = extC.get.roofCeilingConstruction
      floorC  = extC.get.floorConstruction

      if wallC.empty? || roofC.empty? || floorC.empty?
        lgs << "Missing BUILDING default exterior constructions (#{mth})"
        return false
      end

      wallC   = wallC.get.to_LayeredConstruction
      roofC   = roofC.get.to_LayeredConstruction
      floorC  = floorC.get.to_LayeredConstruction

      if wallC.empty? || roofC.empty? || floorC.empty?
        lgs << "BUILDING default exterior layered constructions (#{mth})"
        return false
      end

      wallC   = wallC.get
      roofC   = roofC.get
      floorC  = floorC.get
      walliL  = TBD.insulatingLayer(wallC)
      roofiL  = TBD.insulatingLayer(roofC)
      flooriL = TBD.insulatingLayer(floorC)

      if walliL[:index].nil? || roofiL[:index].nil? || flooriL.nil?
        lgs << "Missing BUILDING insulating layer(s) (#{mth})"
        return false
      end

      # Previously-assigned BTAP-costed surface air film resistances?
      wFR = prop(wallC,  "btap_film", Float)
      rFR = prop(roofC,  "btap_film", Float)
      fFR = prop(floorC, "btap_film", Float)
      wFR = 0 unless wFR
      rFR = 0 unless rFR
      fFR = 0 unless fFR

      # Previously-assigned construction net area?
      wM2 = prop(wallC,  "btap_area", Float)
      rM2 = prop(roofC,  "btap_area", Float)
      fM2 = prop(floorC, "btap_area", Float)

      wM2 = wallC.getNetArea  unless wM2
      rM2 = roofC.getNetArea  unless rM2
      fM2 = floorC.getNetArea unless fM2

      # Previously-assigned BTAP-costed construction IDs?
      wID = prop(wallC,  "btap_id", String)
      rID = prop(roofC,  "btap_id", String)
      fID = prop(floorC, "btap_id", String)
      wID = "" unless wID
      rID = "" unless rID
      fID = "" unless fID
      wID = "" unless data.include?(wID)
      rID = "" unless data.include?(rID)
      fID = "" unless data.include?(fID)

      # Fallback: BTAP-costed wall construction from STRUCTURE parameters.
      if wID.empty?
        opts            = {}
        opts[:framing ] = stc.framing
        opts[:cladding] = stc.cladding
        opts[:finish  ] = stc.finish
        opts[:perform ] = :lp
        opts[:stype   ] = :walls
        opts[:uo      ] = wUo
        wID = BTAP::Bridging.costed_assembly(argh)
      end

      # Fallback: BTAP-costed roof construction from STRUCTURE parameters.
      if rID.empty?
        opts            = {}
        opts[:framing ] = stc.framing
        opts[:cladding] = stc.cladding
        opts[:finish  ] = stc.finish
        opts[:perform ] = :lp
        opts[:stype   ] = :roofs
        opts[:uo      ] = rUo
        rID = BTAP::Bridging.costed_assembly(argh)
      end

      # Fallback: BTAP-costed floor construction from STRUCTURE parameters.
      if fID.empty?
        opts            = {}
        opts[:framing ] = stc.framing
        opts[:cladding] = stc.cladding
        opts[:finish  ] = stc.finish
        opts[:perform ] = :lp
        opts[:stype   ] = :floors
        opts[:uo      ] = fUo
        fID = BTAP::Bridging.costed_assembly(argh)
      end

      addprop(bldg,   "btap_ut",   wUt)
      addprop(bldg,   "btap_uo",   wUo)
      addprop(bldg,   "btap_id",   wID)
      addprop(bldg,   "btap_area", wM2)
      addprop(bldg,   "btap_film", wFR)
      addprop(wallC,  "btap_ut",   wUt)
      addprop(wallC,  "btap_uo",   wUo)
      addprop(wallC,  "btap_id",   wID)
      addprop(wallC,  "btap_area", wM2)
      addprop(wallC,  "btap_film", wFR)
      addprop(roofC,  "btap_ut",   rUt)
      addprop(roofC,  "btap_uo",   rUo)
      addprop(roofC,  "btap_id",   rID)
      addprop(roofC,  "btap_area", rM2)
      addprop(roofC,  "btap_film", rFR)
      addprop(floorC, "btap_ut",   fUt)
      addprop(floorC, "btap_uo",   fUo)
      addprop(floorC, "btap_id",   fID)
      addprop(floorC, "btap_area", fM2)
      addprop(floorC, "btap_film", fFR)

      # Building shortcuts.
      @model[:building][:walls ][:lc  ] = wallC
      @model[:building][:roofs ][:lc  ] = roofC
      @model[:building][:floors][:lc  ] = floorC
      @model[:building][:walls ][:indx] = walliL[:index]
      @model[:building][:roofs ][:indx] = roofiL[:index]
      @model[:building][:floors][:indx] = flooriL[:index]
      @model[:building][:walls ][:area] = wM2
      @model[:building][:roofs ][:area] = rM2
      @model[:building][:floors][:area] = fM2
      @model[:building][:walls ][:id  ] = wID
      @model[:building][:roofs ][:id  ] = rID
      @model[:building][:floors][:id  ] = fID
      @model[:building][:walls ][:film] = wFR
      @model[:building][:roofs ][:film] = rFR
      @model[:building][:floors][:film] = fFR
      @model[:building][:walls ][:ut  ] = wUt
      @model[:building][:roofs ][:ut  ] = rUt
      @model[:building][:floors][:ut  ] = fUt
      @model[:building][:walls ][:uo  ] = wUo
      @model[:building][:roofs ][:uo  ] = rUo
      @model[:building][:floors][:uo  ] = fUo

      # Repeat for unoccupied, unconditioned spaces (e.g. crawlspaces, attics).
      attics = []

      model.getSpaces.each do |space|
        next if space.partofTotalFloorArea
        next unless TBD.unconditioned?(space)

        attics << space
      end

      # All attic/crawlspace spaces reference the same default construction set.
      unless attics.empty?
        attic = attics.first
        aset  = attic.defaultConstructionSet

        unless aset.empty?
          aset = aset.get

          if aset == bset
            lgs << "BUILDING/ATTIC shared default construction set (#{mth})"
            return false
          end

          # Attic/crawlspace interzone constructions are insulated.
          intC = aset.defaultInteriorSurfaceConstructions

          if intC.empty?
            lgs << "No ATTIC default interior constructions (#{mth})"
            return false
          end

          wallC  = intC.get.wallConstruction
          roofC  = intC.get.roofCeilingConstruction
          floorC = intC.get.floorConstruction

          if wallC.empty? || roofC.empty? || floorC.empty?
            lgs << "Missing ATTIC default exterior constructions (#{mth})"
            return false
          end

          wallC   = wallC.get.to_LayeredConstruction
          roofC   = roofC.get.to_LayeredConstruction
          floorC  = floorC.get.to_LayeredConstruction

          if wallC.empty? || roofC.empty? || floorC.empty?
            lgs << "ATTIC default interior layered constructions (#{mth})"
            return false
          end

          wallC   = wallC.get
          roofC   = roofC.get
          floorC  = floorC.get
          walliL  = TBD.insulatingLayer(wallC)
          roofiL  = TBD.insulatingLayer(roofC)
          flooriL = TBD.insulatingLayer(floorC)

          if walliL[:index].nil? || roofiL[:index].nil? || flooriL.nil?
            lgs << "Missing ATTIC insulating layer(s) (#{mth})"
            return false
          end

          # Previously-assigned BTAP-costed surface air film resistances?
          wFR = prop(wallC,  "btap_film", Float)
          rFR = prop(roofC,  "btap_film", Float)
          fFR = prop(floorC, "btap_film", Float)
          wFR = 0 unless wFR
          rFR = 0 unless rFR
          fFR = 0 unless fFR

          # Previously-assigned construction net area?
          wM2 = prop(wallC,  "btap_area", Float)
          rM2 = prop(roofC,  "btap_area", Float)
          fM2 = prop(floorC, "btap_area", Float)
          wM2 = wallC.getNetArea  unless wM2
          rM2 = roofC.getNetArea  unless rM2
          fM2 = floorC.getNetArea unless fM2

          # Previously-assigned BTAP-costed wall construction ID?
          wID = prop(wallC,  "btap_id", String)
          rID = prop(roofC,  "btap_id", String)
          fID = prop(floorC, "btap_id", String)
          wID = "" unless wID
          rID = "" unless rID
          fID = "" unless fID
          wID = "" unless data.include?(wID)
          rID = "" unless data.include?(rID)
          fID = "" unless data.include?(fID)

          # Fallback: BTAP-costed wall construction from STRUCTURE parameters.
          if wID.empty?
            opts            = {}
            opts[:framing ] = stc.framing
            opts[:cladding] = stc.cladding
            opts[:finish  ] = stc.finish
            opts[:perform ] = :lp
            opts[:stype   ] = :walls
            opts[:uo      ] = wUo
            wID = BTAP::Bridging.costed_assembly(argh)
          end

          # Fallback: BTAP-costed roof construction from STRUCTURE parameters.
          if rID.empty?
            opts            = {}
            opts[:framing ] = stc.framing
            opts[:cladding] = stc.cladding
            opts[:finish  ] = stc.finish
            opts[:perform ] = :lp
            opts[:stype   ] = :floors # not roofs:
            opts[:uo      ] = fUo     # not rUo
            rID = BTAP::Bridging.costed_assembly(argh)
          end

          # Fallback: BTAP-costed floor construction from STRUCTURE parameters.
          if fID.empty?
            opts            = {}
            opts[:framing ] = stc.framing
            opts[:cladding] = stc.cladding
            opts[:finish  ] = stc.finish
            opts[:perform ] = :lp
            opts[:stype   ] = :roofs # not floors
            opts[:uo      ] = rUo    # not fUo
            fID = BTAP::Bridging.costed_assembly(argh)
          end

          # Re/set AdditionalProperties of ATTIC interior constructions.
          addprop(wallC,  "btap_ut",   wUt)
          addprop(wallC,  "btap_uo",   wUo)
          addprop(wallC,  "btap_id",   wID)
          addprop(wallC,  "btap_area", wM2)
          addprop(wallC,  "btap_film", wFR)
          addprop(roofC,  "btap_ut",   fUt) # not roof Ut
          addprop(roofC,  "btap_uo",   fUo) # not roof Uo
          addprop(roofC,  "btap_id",   rID)
          addprop(roofC,  "btap_area", rM2)
          addprop(roofC,  "btap_film", rFR)
          addprop(floorC, "btap_ut",   rUt) # not floor Ut
          addprop(floorC, "btap_uo",   rUo) # not floor Uo
          addprop(floorC, "btap_id",   fID)
          addprop(floorC, "btap_area", fM2)
          addprop(floorC, "btap_film", fFR)

          # Add interior wall parameters to attic spaces.
          attics.each do |att|
            addprop(att, "btap_ut",   wUt)
            addprop(att, "btap_uo",   wUo)
            addprop(att, "btap_id",   wID)
            addprop(att, "btap_area", wM2)
            addprop(att, "btap_film", wFR)
          end

          # Shortcuts.
          @model[:attic][:walls ][:lc  ] = wallC
          @model[:attic][:roofs ][:lc  ] = roofC
          @model[:attic][:floors][:lc  ] = floorC
          @model[:attic][:walls ][:indx] = walliL[:index]
          @model[:attic][:roofs ][:indx] = roofiL[:index]
          @model[:attic][:floors][:indx] = flooriL[:index]
          @model[:attic][:walls ][:area] = wM2
          @model[:attic][:roofs ][:area] = rM2
          @model[:attic][:floors][:area] = fM2
          @model[:attic][:walls ][:id  ] = wID
          @model[:attic][:roofs ][:id  ] = rID
          @model[:attic][:floors][:id  ] = fID
          @model[:attic][:walls ][:film] = wFR
          @model[:attic][:roofs ][:film] = rFR
          @model[:attic][:floors][:film] = fFR
          @model[:attic][:walls ][:ut  ] = wUt
          @model[:attic][:roofs ][:ut  ] = fUt
          @model[:attic][:floors][:ut  ] = rUt
          @model[:attic][:walls ][:uo  ] = wUo
          @model[:attic][:roofs ][:uo  ] = fUo
          @model[:attic][:floors][:uo  ] = rUo
        end
      end

      # Repeat for customized spaces.
      stc.spaces.each do |id, sp|
        space = model.getSpaceByName(id)
        next if space.empty?

        space = space.get
        sset  = space.defaultConstructionSet
        next if sset.empty?

        sset = sset.get
        next if sset == bset

        extC = sset.defaultExteriorSurfaceConstructions
        next if extC.empty?

        wallC  = extC.get.wallConstruction
        roofC  = extC.get.roofCeilingConstruction
        floorC = extC.get.floorConstruction
        next if wallC.empty?
        next if roofC.empty?
        next if floorC.empty?

        wallC   = wallC.get.to_LayeredConstruction
        roofC   = roofC.get.to_LayeredConstruction
        floorC  = floorC.get.to_LayeredConstruction
        next if wallC.empty?
        next if roofC.empty?
        next if floorC.empty?

        wallC   = wallC.get
        roofC   = roofC.get
        floorC  = floorC.get
        walliL  = TBD.insulatingLayer(wallC)
        roofiL  = TBD.insulatingLayer(roofC)
        flooriL = TBD.insulatingLayer(floorC)
        next if walliL[:index].nil?
        next if roofiL[:index].nil?
        next if flooriL[:index].nil?

        # Previously-assigned BTAP-costed surface air film resistances?
        wFR = prop(wallC,  "btap_film", Float)
        rFR = prop(roofC,  "btap_film", Float)
        fFR = prop(floorC, "btap_film", Float)
        wFR = 0 unless wFR
        rFR = 0 unless rFR
        fFR = 0 unless fFR

        # Previously-assigned construction net area?
        wM2 = prop(wallC,  "btap_area", Float)
        rM2 = prop(roofC,  "btap_area", Float)
        fM2 = prop(floorC, "btap_area", Float)
        wM2 = wallC.getNetArea  unless wM2
        rM2 = roofC.getNetArea  unless rM2
        fM2 = floorC.getNetArea unless fM2

        # Previously-assigned BTAP-costed construction IDs?
        wID = prop(wallC,  "btap_id", String)
        rID = prop(roofC,  "btap_id", String)
        fID = prop(floorC, "btap_id", String)
        wID = "" unless wID
        rID = "" unless rID
        fID = "" unless fID
        wID = "" unless data.include?(wID)
        rID = "" unless data.include?(rID)
        fID = "" unless data.include?(fID)

        # Fallback: BTAP-costed wall construction from STRUCTURE parameters.
        if wID.empty?
          opts            = {}
          opts[:framing ] = sp[:framing]
          opts[:cladding] = sp[:cladding]
          opts[:finish  ] = sp[:finish]
          opts[:perform ] = :lp
          opts[:stype   ] = :walls
          opts[:uo      ] = wUo
          wID = BTAP::Bridging.costed_assembly(argh)
        end

        # Fallback: BTAP-costed roof construction from STRUCTURE parameters.
        if rID.empty?
          opts            = {}
          opts[:framing ] = sp[:framing]
          opts[:cladding] = sp[:cladding]
          opts[:finish  ] = sp[:finish]
          opts[:perform ] = :lp
          opts[:stype   ] = :roofs
          opts[:uo      ] = rUo
          rID = BTAP::Bridging.costed_assembly(argh)
        end

        # Fallback: BTAP-costed floor construction from STRUCTURE parameters.
        if fID.empty?
          opts            = {}
          opts[:framing ] = sp[:framing]
          opts[:cladding] = sp[:cladding]
          opts[:finish  ] = sp[:finish]
          opts[:perform ] = :lp
          opts[:stype   ] = :floors
          opts[:uo      ] = fUo
          fID = BTAP::Bridging.costed_assembly(argh)
        end

        # Re/set AdditionalProperties to space exterior constructions.
        addprop(space,  "btap_ut",   wUt)
        addprop(space,  "btap_uo",   wUo)
        addprop(space,  "btap_id",   wID)
        addprop(space,  "btap_area", wM2)
        addprop(space,  "btap_film", wFR)
        addprop(wallC,  "btap_ut",   wUt)
        addprop(wallC,  "btap_uo",   wUo)
        addprop(wallC,  "btap_id",   wID)
        addprop(wallC,  "btap_area", wM2)
        addprop(wallC,  "btap_film", wFR)
        addprop(roofC,  "btap_ut",   rUt)
        addprop(roofC,  "btap_uo",   rUo)
        addprop(roofC,  "btap_id",   rID)
        addprop(roofC,  "btap_area", rM2)
        addprop(roofC,  "btap_film", rFR)
        addprop(floorC, "btap_ut",   fUt)
        addprop(floorC, "btap_uo",   fUo)
        addprop(floorC, "btap_id",   fID)
        addprop(floorC, "btap_area", fM2)
        addprop(floorC, "btap_film", fFR)

        @model[:spaces][id] = {walls: {}, roofs: {}, floors: {}}

        # Custom space shortcuts.
        @model[:spaces][id][:walls ][:lc  ] = wallC
        @model[:spaces][id][:roofs ][:lc  ] = roofC
        @model[:spaces][id][:floors][:lc  ] = floorC
        @model[:spaces][id][:walls ][:indx] = walliL[:index]
        @model[:spaces][id][:roofs ][:indx] = roofiL[:index]
        @model[:spaces][id][:floors][:indx] = flooriL[:index]
        @model[:spaces][id][:walls ][:area] = wM2
        @model[:spaces][id][:roofs ][:area] = rM2
        @model[:spaces][id][:floors][:area] = fM2
        @model[:spaces][id][:walls ][:id  ] = wID
        @model[:spaces][id][:roofs ][:id  ] = rID
        @model[:spaces][id][:floors][:id  ] = fID
        @model[:spaces][id][:walls ][:film] = wFR
        @model[:spaces][id][:roofs ][:film] = rFR
        @model[:spaces][id][:floors][:film] = fFR
        @model[:spaces][id][:walls ][:ut  ] = wUt
        @model[:spaces][id][:roofs ][:ut  ] = rUt
        @model[:spaces][id][:floors][:ut  ] = fUt
        @model[:spaces][id][:walls ][:uo  ] = wUo
        @model[:spaces][id][:roofs ][:uo  ] = rUo
        @model[:spaces][id][:floors][:uo  ] = fUo
      end

      # Dry TBD run on a clone of the OpenStudio model.
      mdl = OpenStudio::Model::Model.new
      mdl.addObjects(model.toIdfFile.objects)

      args = {option: "", io_path: inputs( @model[:quality] )}
      TBD.clean!
      TBD.process(mdl, args)

      if TBD.fatal? || TBD.error?
        lgs << "TBD-identified FATAL error(s):"     if TBD.fatal?
        lgs << "TBD-identified non-FATAL error(s):" if TBD.error?
        TBD.logs.each { |log| lgs << log[:message] }
        return false if TBD.fatal?
      end

      if args[:surfaces].nil? || args[:surfaces].empty?
        lgs << "No deratable surfaces in model (#{mth})"
        return false
      end

      if args[:io][:edges].empty?
        lgs << "No deratable linear thermal bridge edges in model (#{mth})"
        return false
      end

      # Process surfaces deemed 'deratable' by TBD.
      args[:surfaces].each do |identifier, surface|
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
                 else next
                 end

        # Track deratable surface types, e.g. any exposed :floors?
        unless @model[:stypes].include?(stypes)
          @model[:stypes][stypes] = {uo: argh[stypes][:uo]}

          if argh[stypes].key?(:ut)
            @model[:stypes][stypes][:ut] = argh[stypes][:ut]
          else
            @model[:stypes][stypes][:ut] = argh[stypes][:uo]
          end
        end
      end

      true
    end

    ##
    # Assigns a BTAP attribute (as AdditionalProperty) to an OpenStudio Model
    # object, e.g. a building, one or more spaces, layered constructions.
    #
    # @param obj [-] one or more OpenStudio::Model objects
    # @param tag [#to_sym] attribute identifier
    # @param prp [#to_sym or Numeric] attribute (or property)
    #
    # @return [Boolean] true if successful
    def addprop(obj = nil, tag = "", prp = "")
      return false unless tag.respond_to?(:to_sym)

      # 1x OpenStudio::Model object, or multiple similar objects?
      obj = obj.respond_to?(:to_a) ? obj.to_a : [obj]
      return false unless obj.first.respond_to?(:model)

      cls = obj.first.class
      tag = tag.to_s
      return false if tag.empty?

      obj.each { |ob| return false unless ob.is_a?(cls) }

      if prp.respond_to?(:to_sym)
        prp = prp.to_s
        return false if prp.empty?
      else
        return false unless prp.is_a?(Numeric)
      end

      obj.each { |ob| ob.additionalProperties.setFeature(tag, prp) }

      true
    end

    ##
    # Fetches a BTAP attribute (as AdditionalProperty), from an OpenStudio Model
    # object, e.g. a building, a space, a layered construction.
    #
    # @param obj [#model] an OpenStudio::Model object
    # @param tag [#to_sym] attribute tag
    # @param typ [-] attribute type, e.g. String, Symbol, Integer
    #
    # @return [String or Float] attribute value (nil if invalid input)
    def prop(obj = nil, tag = "", typ = nil)
      return nil unless obj.respond_to?(:model)
      return nil unless tag.respond_to?(:to_sym)

      tag = tag.to_s
      return nil if tag.empty?

      if typ == Integer
        prp = obj.additionalProperties.getFeatureAsInteger(tag)
      elsif typ <= Numeric
        prp = obj.additionalProperties.getFeatureAsDouble(tag)
      else
        prp = obj.additionalProperties.getFeatureAsString(tag)
      end

      prp.empty? ? nil : prp.get
    end

    ##
    # Generates TBD input hash. Relies on OpenStudio model, BTAP::Structure
    # attributes and additional parameters set at initialization.
    #
    # @param quality [:good, :bad] thermal bridging PSI set quality
    #
    # @return [Hash] TBD inputs (empty if invalid input)
    def inputs(quality = :good)
      argh = @model[:argh]
      mdl  = @model[:osm]

      # PSI set quality?
      quality = :good unless quality == :bad

      # Initialize TBD input hash.
      input  = {}
      psis   = {} # construction-specific PSI sets
      spaces = {} # custom space-specific PSI references

      # A single, default PSI-factor set for the building.
      bldg = @model[:building]
      bID  = bldg[:walls][:id]
      bPSI = set(bID, quality)
      psis[ bPSI[:id] ] = bPSI

      # Repeat for customized spaces, e.g.
      #   - "cmu" gymnasium walls in an otherwise "steel" post/frame school
      @model[:spaces].each do |id, sp|
        cID = sp[:walls ][:id]
        next if cID == bID

        # Fetch BTAP PSI factor set identifier, e.g. STEL1_GOOD
        cPSI = set(cID, quality)
        next if psis.key?( cPSI[:id] )

        # Append customized PSI-factor set.
        psis[ cPSI[:id] ] = cPSI

        # Add reference to customized space PSI-factor set.
        spaces[id] = { id: id, psi: cPSI[:id] }
      end

      # TBD JSON schema added as a reminder. No schema validation in BTAP.
      schema = "https://github.com/rd2/tbd/blob/master/tbd.schema.json"

      input[:schema     ] = schema
      input[:description] = "TBD input for BTAP"
      input[:psis       ] = psis.values
      input[:spaces     ] = spaces.values unless spaces.empty?
      input[:building   ] = { psi: bPSI[:id] }

      input
    end

    ##
    # Generate BTAP/TBD tallies, namely for QAQC, costing & embodied carbon.
    #
    # @return [Boolean] true if BTAP/TBD tally is successful
    def gen_tallies
      return false unless @model.key?(:io)
      return false unless @model[:io][:edges]

      # Initialize.
      @tally = {edges: {}}
      model  = @model[:osm]
      bldg   = @model[:osm].getBuilding

      # TBD/BTAP track a wider range of thermal bridge types than BTAP costing
      # currently supports. Current BTAP-costed, linear thermal bridge types:
      @model[:bridges] = [:rimjoist, :parapet, :fenestration, :corner, :grade]

      @model[:io][:edges].each do |e|
        pID = e[:psi]
        next if e[:length] < 0.025

        # Prune away concave/convex suffixes.
        type = e[:type].to_s.gsub(/concave|convex/, "")

        # Recast linear bridge types: match ~limited costed options.
        type = case type
               when /balcony/ then :rimjoist
               when /roof/    then :parapet
               when /sky/     then :fenestration
               when /sill/    then :fenestration
               when /jamb/    then :fenestration
               when /head/    then :fenestration
               when /door/    then ""
               when /party/   then ""
               when /joint/   then ""
               else type.to_sym
               end

        next unless @model[:bridges].include?(type)

        # Split PSI identifier: construction 'ID' + PSI 'quality'.
        cID, quality = pID.split(" ")

        # Valid?
        quality = quality.to_sym
        next unless data.key?(cID)
        next unless data[cID].key?(quality)
        next unless data[cID][quality].key?(type)
        next unless data[cID][quality][:id] == pID

        # Determine multiplier(s).
        mSb = 1
        mSp = 1

        # SubSurface multiplier.
        e[:surfaces].each do |srf|
          if type == :fenestration
            unless model.getSubSurfaceByName(srf).empty?
              mlt = model.getSubSurfaceByName(srf).get.multiplier
              mSb = mlt if mlt > mSb
            end
          end

          next if model.getSurfaceByName(srf).empty?
          next if model.getSurfaceByName(srf).get.space.empty?

          # Space multiplier.
          mlt = model.getSurfaceByName(srf).get.space.get.multiplier
          mSp = mlt if mlt > mSp
        end

        @tally[:edges][type]       = {} unless @tally[:edges].key?(type)
        @tally[:edges][type][pID]  = 0  unless @tally[:edges][type].key?(pID)
        @tally[:edges][type][pID] += e[:length] * mSb * mSp
      end

      addprop(bldg, "psi_quality", @model[:quality])

      # Add (to a model's building) PSI tallies as AdditionalProperties.
      @tally[:edges].each do |type, edge|
        edge.each.with_index(1) do |(pID, m), i|
          next if m < 0.025

          tag = "PSI" + type.to_s + i.to_s
          val = "#{pID} #{m.round(2)}"
          addprop(bldg, tag, val)
        end
      end

      # Update other related parameters (as building AdditionalProperties).
      addprop(bldg, "btap_uo", @model[:building][:walls][:uo])
      addprop(bldg, "btap_id", @model[:building][:walls][:id])

      # Repeat for attic(s) - if applicable.
      unless @model[:attic][:walls].empty?
        model.getSpaces.each do |space|
          next if space.partofTotalFloorArea
          next unless TBD.unconditioned?(space)

          addprop(space, "btap_uo", @model[:attic][:walls][:uo])
          addprop(space, "btap_id", @model[:attic][:walls][:id])
        end
      end

      # Repeat for customized spaces.
      @model[:spaces].each do |id, sp|
        space = model.getSpaceByName(id)
        next if space.empty?

        space = space.get
        addprop(space, "btap_uo", sp[:walls][:uo])
        addprop(space, "btap_id", sp[:walls][:id])
      end

      @tally[:edges].empty? ? false : true
    end

    ##
    # Generate BTAP/TBD post-processing feedback.
    #
    # @return [Boolean] true if valid BTAP/TBD model
    def gen_feedback
      lgs = @feedback[:logs]
      return false unless @model.key?(:complies) # all model constructions
      return false unless @model.key?(:comply)   # surface type specific ...
      return false unless @model.key?(:stypes)   # :walls, :roofs, :floors

      # Uprating. Report first on surface types (compliant or not).
      @model[:stypes].each do |stypes, u|
        next unless @model[:uprating]
        next unless @model[:comply].key?(stypes)

        lg  = @model[:comply][stypes] ? "Compliant " : "Non-compliant "
        lg += stypes.to_s
        lgs << lg

        bUt  = format("%.3f", @model[:building][stypes][:ut])
        bUo  = format("%.3f", @model[:building][stypes][:uo])
        bCP  = @model[:building][stypes][:compliant]
        bID  = @model[:building][stypes][:id]
        lg   = "  - "
        lg  += bCP ? " Compliant " : " Non-compliant "
        lg  += "BUILDING: Ut #{bUt} W/m2.K "
        lg  += "(Uo #{bUo} W/m2.K, #{bID})"
        lg  += " - #{@model[:quality]}" if stypes == :walls
        lgs << lg

        unless @model[:attic][stypes].empty?
          types = case stypes
                  when :roofs  then :floors
                  when :floors then :roofs
                  else              :walls
                  end

          aUt  = format("%.3f", @model[:attic][types][:ut])
          aUo  = format("%.3f", @model[:attic][types][:uo])
          aCP  = @model[:attic][types][:compliant]
          aID  = @model[:attic][types][:id]
          lg   = "  - "
          lg  += aCP ? " Compliant " : " Non-compliant "
          lg  += "ATTIC: Ut #{aUt} W/m2.K "
          lg  += "(Uo #{aUo} W/m2.K, #{aID})"
          lg  += " - #{@model[:quality]}" if stypes == :walls
          lgs << lg
        end

        @model[:spaces].each do |id, sp|
          sUt  = format("%.3f", sp[stypes][:ut])
          sUo  = format("%.3f", sp[stypes][:uo])
          sCP  = sp[stypes][:compliant]
          sID  = sp[stypes][:id]
          sQY  =
          lg   = "  - "
          lg  += sCP ? " Compliant " : " Non-compliant "
          lg  += "SPACE #{id}: Ut #{sUt} W/m2.K "
          lg  += "(Uo #{sUo} W/m2.K, #{sID})"
          lg  += " - #{@model[:quality]}" if stypes == :walls
          lgs << lg
        end
      end

      # Report on edges (as linear thermal bridges).
      lgs << "Edges (i.e. linear thermal bridges):"

      @tally[:edges].each do |type, edge|
        edge.each.with_index(1) do |(pID, m), i|
          next if m < 0.025

          lgs << " #{type}: ".rjust(15) + pID.ljust(37) + " #{m.round(1)} m".rjust(9)

          # LargeOffice (without factoring space/subsurface multipliers):
          #      fenestration: BTAP-ExteriorWall-SteelFramed-2 good  1802.1 m
          #             grade: BTAP-ExteriorWall-SteelFramed-2 good   243.7 m
          #          rimjoist: BTAP-ExteriorWall-SteelFramed-2 good   487.4 m
          #           parapet: BTAP-ExteriorWall-SteelFramed-2 good   243.7 m
          #            corner: BTAP-ExteriorWall-SteelFramed-2 good    47.6 m

          # LargeOffice (with factoring space/subsurface multipliers):
          #      fenestration: BTAP-ExteriorWall-SteelFramed-2 good  6280.0 m
          #             grade: BTAP-ExteriorWall-SteelFramed-2 good   243.7 m
          #          rimjoist: BTAP-ExteriorWall-SteelFramed-2 good  2680.6 m
          #           parapet: BTAP-ExteriorWall-SteelFramed-2 good   243.7 m
          #            corner: BTAP-ExteriorWall-SteelFramed-2 good   190.2 m
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
