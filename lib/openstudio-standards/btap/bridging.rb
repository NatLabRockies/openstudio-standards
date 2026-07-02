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
    # BTAP/TBD data below is based on BTAP costing data:
    #   - range of clear-field Uo factors
    #   - range of PSI factors (i.e. MAJOR thermal bridging), e.g. corners
    #
    # Ref: EVOKE BTAP costing spreadsheet modifications (2022), synced with:
    #      - Building Envelope Thermal Bridging Guide (BETBG)
    #      - ASHRAE RP-1365, ISO-12011, etc.
    #
    # This module also rests on structure/envelope data model/classes.

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # BTAP/TBD data is limited to the following wall assemblies (as paired LP
    # & HP variants), which eventually should be located in a shared file
    # (e.g. CSV, JSON, YAML).
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
    # NECB2017/2020/2025. See below, and additional NoteS at the very end.

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

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # There are 2 distinct BTAP "building_envelope.rb" files to enrich with
    # TBD functionality (whether BTAP users choose to activate TBD or not):
    #
    #   1. BTAPPRE1980
    #      - superclass for BTAP1980TO2010
    #   2. NECB2011
    #      - superclass for NECB2015
    #      - superclass for NECB2017 (inherits from NECB2015)
    #      - superclass for NECB2020 (inherits from NECB2017)
    #      - superclass for ECMS
    #
    # In both files, a BTAP/TBD option switch allows BTAP users to activate
    # or deactivate TBD functionality :
    #   - "none" : TBD is deactivated, i.e. no up/de-rating
    #   - "bad" or "good": (BTAP-costed) PSI factor sets, i.e. derating only
    #   - "uprate": iteratively determine initial Uo ... prior to derating
    #
    # For NECB editions prior to NECB2017, the current BTAP policy is to switch
    # off TBD, i.e. 'none' (see the Note on this topic at the end of this
    # document). To instead assess prescriptive Ut compliance for NECB editions
    # 2017 through 2025, BTAP/TBD must be set to "uprate" so it can iteratively
    # reset combined Uo & PSI factors towards finding the least expensive, yet
    # compliant, Ut combination. Why? Improved Uo assembly variants are
    # necessarily required, given:
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
    # combinations (prescriptive path) for EVERY OpenStudio model.
    # Read here as to "why?":
    #
    #   github.com/rd2/tbd/blob/f34ec6a017fcc0f6022f2a46e056b46b9d036b3b/
    #   spec/tbd_tests_spec.rb#L9219
    #
    # For these reasons, BTAP's use of TBD rests on an ITERATIVE uprating
    # solution for NECB2017+:
    #
    #   1. TBD attempts to achieve NECB-required area-weighted Ut factors
    #      for above-grade walls (then for roofs and exposed floors),
    #      starting with the least expensive combination:
    #        - highest admissible Uo factors for the climate zone
    #        - "bad" (LP) thermal bridging details
    #
    #   2. If, for a given OpenStudio model, required area-weighted Ut
    #      factors cannot be achieved, TBD then switches over to "good"
    #      (HP) thermal bridging detailing for that same assembly, and
    #      repeats the exercise.
    #
    #   3. A subsequent failed attempt triggers a switch over to improved HP Uo
    #      assemblies. For instance:
    #        - "BTAP-ExteriorWall-WoodFramed-5" ... switches over to:
    #        - "BTAP-ExteriorWall-WoodFramed-7"
    #
    #      ... switching over to another assembly this way also means
    #      reverting back to "bad" (LP) thermal bridging PSI factors.
    #
    #   4. A final switch to "good" (HP) details is available (last resort).
    #
    # If NONE of the available combinations are sufficient:
    #   - TBD red-flags a failed attempt at NECB2017 or NECB2020 compliance
    #   - TBD keeps iteration #4 Uo + PSI combo, then derates before a
    #     BTAP simulation run (giving some performance gap indication)

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # Notes:
    #
    #   - Steel-framed assemblies: the selected HP variant has metal
    #     cladding. The only LP steel-framed BTAP option is wood-clad -
    #     something of an anomaly in commercial construction. By making the
    #     switch earlier to metal cladding, everywhere in Canada except
    #     (milder) SW BC and SW NS, it is hoped that a more consistent,
    #     apples-to-apples comparison is ensured.
    #
    #   - ROOF and (exposed) floor surfaces refer to a single LP/HP selection
    #     respectively. This is expected to change in the future @todo.

    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # Preset BTAP/TBD wall assembly parameters.
    @@data = {}

    # Construction sub-variant identified strictly by Uo, e.g. 0.314 W/m2.K.
    @@data[MASS2] = {uos: [0.314, 0.278, 0.247, 0.210, 0.183]}
    @@data[MASSB] = {uos: [0.130, 0.100]}

    @@data[MASS4] = {uos: [0.314, 0.278, 0.247, 0.210, 0.183]}
    @@data[MASS8] = {uos: [0.130, 0.100]}

    @@data[WOOD5] = {uos: [0.314, 0.278, 0.247, 0.210, 0.183]}
    @@data[WOOD7] = {uos: [0.130]}

    @@data[STEL1] = {uos: [0.314, 0.278]}
    @@data[STEL2] = {uos: [0.247, 0.210, 0.183, 0.130, 0.100, 0.080]}

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
    # Retrieves BTAP-costed assembly. Defaults to STEL1 if invalid input.
    #
    # @param [Hash] argh structure-linked options
    # @option argh [Symbol] :stype (:walls, :floors or :roofs)
    # @option argh [Symbol] :perform (:lp or :hp) wall variant
    # @option argh [Symbol] :framing (:steel, :wood, :cmu)
    # @option argh [Symbol] :cladding (:heavy)
    # @option argh [Symbol] :finish (:heavy)
    #
    # @return [String] BTAP assembly identifier for costing
    def costed_assembly(argh = {})
      return STEL1 unless argh.respond_to?(:keys)
      return STEL1 unless argh.key?(:stype)
      return STEL1 unless argh.key?(:perform)

      # Key inputs.
      stype   = argh[:stype]
      stype   = :walls unless [:roofs, :floors].include?(stype)
      perform = :lp    unless perform == :hp

      # Optionals.
      framing  = argh.key?(:framing)  ? argh[:framing ] : :light
      cladding = argh.key?(:cladding) ? argh[:cladding] : :light
      finish   = argh.key?(:finish)   ? argh[:finish  ] : :light

      framing  = :steel unless [:wood, :cmu].include?(framing)
      cladding = :light unless cladding == :heavy
      finish   = :light unless finish   == :heavy

      # Select BTAP-costed assembly, matching:
      #   - BTAP::Structure generated construction parameters (e.g. framing)
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
      # Highly conductive building structural materials (e.g. steel, concrete)
      # exacerbate thermal bridging - building structural choices should matter.
      #
      # The BTAP::Structure module generates such attributes, yet BTAP's costed
      # thermal bridging database doesn't yet distinguish between building
      # structures - @todo. For the moment, BTAP PSI set selection is strictly
      # based on BTAP::Structure's :framing, :cladding and :finish attributes,
      # which are usually set prior to initiating BTAP's TBD solution.
      case stype
      when :roofs  then return ROOF
      when :floors then return FLOOR
      else
        case framing
        when :wood
          c1 = WOOD5
          c2 = WOOD7
        when :cmu
          c1 = MASS2
          c2 = MASSB
        else
          if cladding == :heavy && finish == :heavy
            c1 = MASS4
            c2 = MASS8
          else
            c1 = STEL1
            c2 = STEL2
          end
        end
      end

      perform == :lp ? c1 : c2
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
      # btp       = BTAP::Resources::Envelope::Constructions # alias
      mth       = "BTAP::Bridging::#{__callee__}"
      tag       = "uprated_Uo"
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
      @model[:constructions].values.each do |v|
        args[:io_path] = v[combo] if v.key?(combo)
      end

      return false if args[:io_path].nil?

      args[:option] = ""

      loop do
        if initial
          initial = false
        else
          # Subsequent uprating runs. Upgrade technologies. Reset TBD args.
          if quality == :bad
            quality = :good
            combo   = "#{perform.to_s}_#{quality.to_s}".to_sym

            @model[:constructions].values.each do |v|
              args[:io_path] = v[combo] if v.key?(combo)
            end
          elsif perform == :lp
            # Switch 'perform' from :lp to :hp - reset quality to :bad.
            perform = :hp
            quality = :bad
            combo   = "#{perform.to_s}_#{quality.to_s}".to_sym

            @model[:constructions].values.each do |v|
              args[:io_path] = v[combo] if v.key?(combo)
            end
          end

          # Delete previously-generated TBD args Uo key/value pairs.
          @model[:stypes].each do |stypes|
            next unless comply.key?(stypes)

            uo = "#{stypes.to_s.chop}_uo".to_sym
            args.delete(uo) if args.key?(uo)
          end
        end

        # Run TBD on cloned OpenStudio model - compliant combo?
        mdl = OpenStudio::Model::Model.new
        mdl.addObjects(model.toIdfFile.objects)
        TBD.clean!

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

          # TBD-estimated Uo target to meet NECB-required Ut - nil if invalid.
          stype_uo = "#{stypes.to_s.chop}_uo".to_sym
          target   = args.key?(stype_uo) ? args[stype_uo] : nil
          assembly = self.costed_assembly(argh[:structure], stypes, perform)

          uo = target ? self.costed_uo(assembly, target) : nil

          if uo
            uo = target if argh[:interpolate]
            comply[stypes] = true
          else
            uo = self.lowest_uo(assembly)
            comply[stypes] = false
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
        @model[:constructions].each do |ide, v|
          lc = model.getConstructionByName(ide)

          if lc.empty?
            lgs << "Mismatched construction: #{ide} (#{mth})?"
            return false
          end

          lc = lc.get.to_LayeredConstruction

          if lc.empty?
            lgs << "Mismatched layered construction: #{ide} (#{mth})?"
            return false
          end

          lc = lc.get
          next unless v[:stypes] == stypes

          v[:r] = TBD.resetUo(lc, v[:filmRSI], v[:index], v[:uo])

          # Maintain initial uprated Uo as AdditionalProperty.
          v[:surfaces].each do |id|
            surface = model.getSurfaceByName(id)
            next if surface.empty?

            surface = surface.get
            next unless surface.additionalProperties.getFeatureAsDouble(tag).empty?

            surface.additionalProperties.setFeature(tag, v[:uo])
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
        unless argh[:structure].is_a?(BTAP::Structure)
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
      stc = argh[:structure]
      mdl = OpenStudio::Model::Model.new
      mdl.addObjects(model.toIdfFile.objects)
      TBD.clean!
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

      # Generate TBD input hashes for both :good & :bad PSI factor sets. This
      # depends solely on assigned wall constructions (e.g. steel- vs wood-
      # framed) - not roof or floor constructions. By default, a single PSI
      # factor set is assigned for the building. If users request customized,
      # space-specific structural/envelope, matching PSI-factor sets are added.
      #   - 1x set as the building-wide default
      #   - ?x set(s) for user-customized spaces
      #   - see NECB2011/building_envelope.rb's "add_construction_sets"
      @model[:psi]           = {}
      @model[:psi][:lp_bad ] = self.inputs(stc, :lp, :bad)
      @model[:psi][:lp_good] = self.inputs(stc, :lp, :good)
      @model[:psi][:hp_bad ] = self.inputs(stc, :hp, :bad)
      @model[:psi][:hp_good] = self.inputs(stc, :hp, :good)

      # Only process surfaces deemed 'deratable' by TBD. Match PSI factor sets
      # with generated BTAP default construction sets:
      res[:surfaces].each do |id, surface|
        next unless surface.key?(:type)      # :wall, :ceiling or :floor
        next unless surface.key?(:filmRSI)   # surface air film resistances
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

        fR = surface[:filmRSI]
        m2 = surface[:net]
        next if stypes.empty?

        # Track surface type.
        @model[:stypes] << stypes unless @model[:stypes].include?(stypes)

        # Track TBD-targeted constructions for uprating/derating.
        srf = model.getSurfaceByName(id)

        if srf.empty?
          lgs << "Mismatched surface: #{id} (#{mth})?"
          return false
        end

        srf   = srf.get
        space = srf.space

        # Fetch default construction set.
        if srf.isConstructionDefaulted
          set = TBD.defaultConstructionSet(srf)
          set = bset unless set
        else
          set = bset
        end

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

        lc  = lc.get
        ide = lc.nameString

        unless @model[:constructions].key?(ide)
          @model[:constructions][ide]             = {}
          @model[:constructions][ide][:index    ] = surface[:index] # material
          @model[:constructions][ide][:r        ] = surface[:r]     # material
          @model[:constructions][ide][:uo       ] = nil             # assembly
          @model[:constructions][ide][:compliant] = nil             # assembly
          @model[:constructions][ide][:set      ] = set             # assembly
          @model[:constructions][ide][:m2       ] = 0               # cumulative
          @model[:constructions][ide][:fA       ] = 0               # cumulative
          @model[:constructions][ide][:filmRSI  ] = 0               # weighted
          @model[:constructions][ide][:stypes   ] = []
          @model[:constructions][ide][:surfaces ] = []
          @model[:constructions][ide][:spaces   ] = []

          # Map ... @todo.
        end

        @model[:constructions][ide][:m2      ] += m2
        @model[:constructions][ide][:fA      ] += m2 / fR
        @model[:constructions][ide][:stypes  ] << stypes
        @model[:constructions][ide][:surfaces] << id
        @model[:constructions][ide][:spaces  ] << space.nameString
      end

      # Area-weighted surface air film resistances.
      @model[:constructions].values.each { |v| v[:filmRSI] = v[:m2] / v[:fA] }

      # Loop through all tracked deratable constructions. Ensure a single
      # surface type per construction. Ensure at least one wall construction.
      @model[:constructions].values.each { |v| v[:stypes].uniq! }
      nb = 0

      @model[:constructions].each do |ide, v|
        if v[:stypes].size != 1

          # @todo : Revise if multiple surface types per construction.
          # Clone construction as needed to ensure surface type uniqueness.
          lgs << "Multiple surface types per construction (#{mth})?"
          return false
        else
          v[:stypes] = v[:stypes].first
          lc = model.getConstructionByName(ide)

          if lc.empty?
            lgs << "Mismatched construction: #{ide} (#{mth})?"
            return false
          end

          lc = lc.get.to_LayeredConstruction

          if lc.empty?
            lgs << "Mismatched layered construction: #{ide} (#{mth})?"
            return false
          end

          lc = lc.get

          # Hard-set construction to each deratable surface.
          v[:surfaces].each do |id|
            surface = model.getSurfaceByName(id)
            next if surface.empty?

            surface.get.setConstruction(lc)
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
#       variants ignore the effects of MAJOR thermal bridging, such as
#       intermediate slab edges. This does not imply that NECB2011 and NECB2015
#       do not hold prescriptive requirements for MAJOR thermal bridging. There
#       are indeed a handful of general, qualitative requirements (those of the
#       MNECB1997) that would make NECB2011- and NECB2015-compliant buildings
#       slightly better than BTAPPRE1980 "bottom-of-the-barrel" construction,
#       but likely not any better than circa 1990s "run-of-the-mill" commercial
#       construction. Currently, BTAP does not assess the impact of MAJOR
#       thermal bridging for vintages < NECB2017. But ideally it SHOULD, if the
#       goal remains a fair assessment of the (relative) contribution of more
#       recent NECB requirements (e.g. 2020).

# Note: The BTAP costing spreadsheet holds entries for curtain wall (CW)
#       spandrel inserts above/below fenestration for certain spacetypes, see:
#
#         test/necb/unit_tests/resources/btap_spandrels.png
#
#       This is yet to be implemented. This note is an "aide-mémoire" for future
#       consideration. The BETBG does not hold any CW glazed spandrels achieving
#       U factors ANYWHERE near NECB requirements, regardless of NECB vintage or
#       NECB climate zone. Same for the Guide to Low Thermal Energy Demand for
#       Large Buildings. The original intention was to rely on BTAP variants
#       "Metal-2" and "Metal-3" as HP CW spandrels ACTUALLY achieving NECB
#       prescriptive targets, which could only be possible in practice at
#       great cost and effort (e.g. a 2nd insulated wall behind the spandrel).
#
#       If TBD's uprating calculations (e.g. NECB 2017) were in theory no longer
#       required, BTAP's treatment of HP CW spandrels could be implemented
#       strictly as a costing adjustment: energy simulation models wouldn't have
#       to be altered. Otherwise, adaptations would be required. PSI factors are
#       noticeably different for spandrels (obviously no lintels/shelf-angles).
#       More importantly, the default assumption with CW technology is that
#       there wouldn't be any additional linear conductances to consider along
#       vision vs spandrel sections (as perimeter heat loss would already have
#       been considered as per NFRC or CSA rating methodologies). On the other
#       hand, vision jambs along non-CW assemblies (i.e. original BTAP
#       intention) most certainly constitute (new) MAJOR thermal bridges to
#       consider (just as with shared edges between spandrels and other wall
#       assemblies). Again, none of these features are currently implemented
#       within BTAP. Recommended (future) solution, if desired:
#
#         - Automated OSM façade-splitting feature
#           - insert spandrels above/below windows
#             > ~200 lines of Ruby code
#           - simple cases only e.g., vertical, no overlaps, h > 200mm
#             > split above/below plenum walls as well
#             > potentially another 200 lines to catch invalid input
#
#        - Further develop PSI sets to cover CWs (see below)
#          - e.g. PSI factors for CW vision "jamb" transitions
#          - e.g. PSI factors for CW spandrel "jamb" transitions
#
#       These added features would simplify the process tremendously. Yet
#       without admissible CW spandrel U factors down to 0.130 or 0.100 W/m2.K,
#       TBD's uprating features would necessarily push OTHER wall constructions
#       to compensate - noticeably for climate zone 7 (or colder). This would
#       make it MUCH MORE difficult to identify NECB2017 or NECB2020 compliant
#       combinations of Uo+PSI factors if ever HP CW spandrels were integrated
#       within BTAP.

# Note: Some of the aforementioned constructions have exterior brick veneer.
#       For 2-story OpenStudio models with punch windows (i.e. not strip
#       windows), one would NOT expect a continuous steel shelf angle along the
#       intermediate floor slab edge (typically a MAJOR thermal bridge). One
#       would instead expect loose lintels above punch windows, just as with
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
#
# Note: BTAP costing: In addition to the listed items for parapets as MAJOR
#       thermal bridges (eventually generating an overall $ per linear meter),
#       BTAP costing requires extending the areas (m2) of OpenStudio wall
#       surfaces (along parapet edges) by 3'-6" (1.1 m) x parapet lengths, to
#       account for the extra cost of completely wrapping the parapet in
#       insulation for "good" (HP) details. See final TBD tally - @todo.
