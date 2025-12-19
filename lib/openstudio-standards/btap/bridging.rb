# **************************************************************************** /
# *  Copyright (c) 2008-2025, Natural Resources Canada
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

module BTAP
  # ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- #
  module BridgingData
    ##
    # BTAP module/class for Thermal Bridging & Derating (TBD) functionality
    # for linear thermal bridges, e.g. corners, balconies (rd2.github.io/tbd).
    #
    # @author: Denis Bourgeois

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
    # For vintages < NECB2017, the default BTAP policy is to switch off TBD,
    # i.e. 'none' (see the NOTE on this topic at the end of this document). To
    # instead assess prescriptive Ut compliance for vintages NECB2017 and
    # NECB2020, the BTAP/TBD must be set to "uprate" so it can iteratively reset
    # combined Uo & PSI factors towards finding the least expensive, yet
    # compliant, combination. Why? Improved Uo assembly variants are necessarily
    # required, given:
    #
    #   Ut = Uo + ( ∑psi x L )/A + ( ∑khi x n )/A   (ref: rd2.github.io/tbd)
    #
    # If one ignores linear ("( ∑psi x L )/A") and point ("( ∑khi x n )/A")
    # conductances, Ut simply equates to Uo. Yet for ANY added linear or
    # point conductance, Uo factors must necessarily be lower than required
    # NECB2017 or NECB2020 Ut factors. EVOKE's 2022 contribution extends
    # initial (pre-2022) BTAP wall assembly variants, offering much
    # lower Uo factors (in some cases slightly below 0.1 W/m2.K or ~R70).
    # These BTAP upgrades provide more options for attaining required Ut
    # factors. For some variants, this simply implies a thicker insulation
    # layer. For others, it involves more radical assembly changes, such
    # as switching over to the latest commercially-available HP
    # thermally-broken cladding clips. While some solutions are simple
    # (free) detailing changes, most improvements increase construction
    # costs. Despite adding new HP assemblies, it is unlikely that TBD
    # will find NECB2017 or NECB2020 compliant combinations (prescriptive
    # path) for EVERY OpenStudio model. Read here as to "why?":
    #
    #   github.com/rd2/tbd/blob/f34ec6a017fcc0f6022f2a46e056b46b9d036b3b/
    #   spec/tbd_tests_spec.rb#L9219
    #
    # For these reasons, BTAP's use of TBD rests on an ITERATIVE uprating
    # solution for NECB2017 and NECB2020:
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
    #   3. A subsequent failed attempt triggers a switch over to EVOKE's
    #      HP (improved Uo) assemblies. For instance:
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
    # intensities (kg CO2eq/linear meter) associated to them. At some point, it
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
    # Retrieves BTAP-costed assembly.
    #
    # @param structure [BTAP::Structure] BTAP Structure object
    # @param stype [:walls, :floors or :roofs] surface type
    # @param perform [:hp or :lp] high- or low-performance variant
    #
    # @return [String] BTAP assembly identifier for costing
    def costed_assembly(structure = nil, stype = :walls, perform = :lp)
      stype   = :walls unless [:roofs, :floors].include?(stype)
      perform = :lp    unless perform == :hp
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
      case stype
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
    # @option argh [BTAP::Structure] structure a BTAP STRUCTURE object
    # @option argh [Hash] walls exterior wall parameters e.g. :uo, :ut
    # @option argh [Hash] floors exposed floor parameters e.g. :uo, :ut
    # @option argh [Hash] roofs exterior roof parameters e.g. :uo, :ut
    # @option argh [:good, :bad] quality derating option (if not uprating)
    # @option argh [Boolean] interpolate if TBD interpolates among Uo (uprate)
    def initialize(model = nil, argh = {})
      btp       = BTAP::Resources::Envelope::Constructions # alias
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
      @model[:constructions].values.each do |v|
        args[:io_path] = v[combo] if v.key?(combo)
      end

      return false if args[:io_path].nil?

      args[:option ] = ""

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

        # fil = File.join("/Users/rd2/Desktop/test.osm")
        # mdl.save(fil, true)

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

          @model[:constructions].each do |lc, v|
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
        @model[:constructions].each do |lc, v|
          next unless v[:stypes] == stypes

          v[:r] = TBD.resetUo(lc, v[:filmRSI], v[:index], v[:uo])
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
    # @option argh [BTAP::Structure] structure a BTAP STRUCTURE object
    # @option argh [Hash] walls exterior wall parameters e.g. :uo, :ut
    # @option argh [Hash] floors exposed floor parameters e.g. :uo, :ut
    # @option argh [Hash] roofs exterior roof parameters e.g. :uo, :ut
    # @option argh [Symbol] quality derating option (if not uprating)
    # @option argh [Boolean] interpolate if TBD should pick between Uo values
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

      # Building-wide envelope (e.g. assemblies, U-factors, PSI-factors) options
      # depend on building structure-dependent features such as framing,
      # cladding, etc. This will need to adapt to upcoming story/space
      # construction/PSI customization - @todo.
      strc = argh[:structure]

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
      mdl = OpenStudio::Model::Model.new
      mdl.addObjects(model.toIdfFile.objects)
      TBD.clean!
      res = TBD.process(mdl, args)

      # TBD validation of OpenStudio model.
      if TBD.fatal? || TBD.error?
        lgs << "TBD-identified FATAL error(s):"     if TBD.fatal?
        lgs << "TBD-identified non-FATAL error(s):" if TBD.error?

        TBD.logs.each { |log| lgs << log[:message] }
        return false if TBD.fatal?
      end

      # Fetch number of stories in OpenStudio model.
      stories = model.getBuilding.standardsNumberOfAboveGroundStories
      stories = stories.get                  unless stories.empty?
      stories = model.getBuildingStorys.size unless stories.is_a?(Integer)

      # Story/space construction/PSI customization is yet to be implemented.
      # Keeping placeholders for now - @todo.
      @model[:stories] = stories.clamp(1, 999)
      @model[:spaces ] = {}

      # Initialize deratable opaque, layered constructions & surface types.
      @model[:constructions] = {}
      @model[:stypes       ] = []

      if res[:surfaces].nil?
        lgs << "No deratable surfaces in model (#{mth})"
        return false
      end

      # TBD surface objects hold certain attributes (keys) to signal if they're
      # deratable. Concentrating only on those. Relying on reported strings
      # (e.g. surface identifier) or integers (e.g. a layer :index) seems fine.
      # Yet referecing TBD-cloned OpenStudio objects (e.g. key :construction)
      # is a no-no (e.g. seg faults).
      res[:surfaces].each do |id, surface|
        next unless surface.key?(:type)      # :wall, :ceiling or :floor
        next unless surface.key?(:filmRSI)   # sum of air film resistances
        next unless surface.key?(:index)     # deratable layer index
        next unless surface.key?(:r)         # deratable layer RSi
        next unless surface.key?(:deratable) # true or false

        next unless surface[:deratable]
        next unless surface[:index    ]

        stypes = case surface[:type]
                 when :wall    then :walls
                 when :floor   then :floors
                 when :ceiling then :roofs
                 else ""
                 end

        next if stypes.empty?

        # Track surface type.
        @model[:stypes] << stypes unless @model[:stypes].include?(stypes)

        # Track TBD-targeted constructions for uprating/derating.
        srf = model.getSurfaceByName(id)

        if srf.empty?
          lgs << "Mismatched surface: #{id} (#{mth})?"
          return false
        end

        srf = srf.get
        space = srf.space

        if space.empty?
          lgs << "Missing space: #{id} (#{mth})?"
          return false
        end

        space = space.get
        lc = srf.construction

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

        unless @model[:constructions].key?(lc)
          @model[:constructions][lc]             = {}
          @model[:constructions][lc][:index    ] = surface[:index]   # material
          @model[:constructions][lc][:r        ] = surface[:r]       # material
          @model[:constructions][lc][:filmRSI  ] = surface[:filmRSI] # assembly
          @model[:constructions][lc][:uo       ] = nil               # assembly
          @model[:constructions][lc][:compliant] = nil               # assembly
          @model[:constructions][lc][:stypes   ] = []
          @model[:constructions][lc][:surfaces ] = []
          @model[:constructions][lc][:spaces   ] = []

          # Generate TBD input hashes for both :good & :bad PSI factor sets.
          # This depends solely on assigned wall constructions (e.g. steel- vs
          # wood-framed) - not roof or floor constructions. Until space- and
          # storey-specific structure/construction customization is enabled in
          # BTAP, this is set for the entire building. In other words - for now
          # - there should be a single assigned layered construction for all
          # walls in a BTAP-altered OpenStudio model.
          if stypes == :walls
            @model[:constructions][lc][:lp_bad ] = self.inputs(strc, :lp, :bad )
            @model[:constructions][lc][:lp_good] = self.inputs(strc, :lp, :good)
            @model[:constructions][lc][:hp_bad ] = self.inputs(strc, :hp, :bad )
            @model[:constructions][lc][:hp_good] = self.inputs(strc, :hp, :good)
          end
        end

        # Select lowest applicable air film resistances (given surface slope).
        film = [@model[:constructions][lc][:filmRSI], surface[:filmRSI]].min

        @model[:constructions][lc][:filmRSI ] = film
        @model[:constructions][lc][:stypes  ] << stypes           # 1x
        @model[:constructions][lc][:surfaces] << id               # many
        @model[:constructions][lc][:spaces  ] << space.nameString # less
      end

      # Loop through all tracked deratable constructions. Ensure a single
      # surface type per construction. Ensure at least one wall construction.
      @model[:constructions].values.each { |v| v[:stypes].uniq! }
      nb = 0

      @model[:constructions].each do |lc, v|
        if v[:stypes].size != 1
          lgs << "Multiple surface types per construction (#{mth})?"
          return false
        else
          v[:stypes] = v[:stypes].first

          # Assign construction for each deratable surface.
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
    # @param structure [BTAP::Structure] a BTAP STRUCTURE object
    # @param perform [Symbol] :lp or :hp wall variant
    # @param quality [Symbol] :bad or :good PSI-factor
    #
    # @return [Hash] TBD inputs
    def inputs(structure = nil, perform = :hp, quality = :good)
      input   = {}
      psis    = {} # construction-specific PSI sets
      perform = :hp   unless [:lp, :hp].include?(perform)
      quality = :good unless [:bad, :good].include?(quality)

      # A single PSI set for the entire building, based strictly on exterior
      # wall selection. Adapt once BTAP::Structure supports STRUCTURE
      # assignements per OpenStudio's building-to-space hierarchy, e.g. "cmu"
      # gymnasium walls in an otherwise "steel"post/frame school. @todo
      assembly = self.costed_assembly(structure, :walls, perform)
      building_psi = self.set(assembly, quality)

      psis[ building_psi[:id] ] = building_psi

      # TBD JSON schema added as a reminder. No schema validation in BTAP.
      schema = "https://github.com/rd2/tbd/blob/master/tbd.schema.json"

      input[:schema     ] = schema
      input[:description] = "TBD input for BTAP" # append run # ?
      input[:psis       ] = psis.values          # maybe more than 1 in future
      input[:building   ] = { psi: building_psi[:id] }

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
        @model[:constructions].each do |lc, v|
          next unless v.key?(:stypes)
          next unless v.key?(:uo)
          next unless v.key?(:compliant)
          next unless v.key?(:surfaces)
          next unless v[:stypes  ] == stypes
          next     if v[:surfaces].empty?

          uo  = format("%.3f", v[:uo])
          lg  = v[:compliant] ? "   Compliant " : "   Non-compliant "
          lg += "#{lc.nameString} Uo #{uo} (W/K.m2)"
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
            l = format("%.2f", length)
            lgs << "... PSI set '#{psi}' : #{l} m"
          end
        end
      end

      true
    end

    # def get_material_quantities()
    #   material_quantities = {}
    #   csv = CSV.read("#{File.dirname(__FILE__)}/../../../data/inventory/thermal_bridging.csv", headers: true)
    #   tally_edges = @tally[:edges].transform_keys(&:to_s)
    #
    #   tally_edges.each do |edge_type_full, value|
    #     edge_type = edge_type_full.delete_suffix('convex')
    #     edge_type = 'fenestration' if ['head', 'jamb', 'sill'].include?(edge_type)
    #
    #     value.each do |wall_ref_and_quality, quantity|
    #       /(.*)\s(.*)/ =~ wall_ref_and_quality
    #       wall_reference = $1
    #       quality = $2
    #
    #       if wall_reference =='BTAP-ExteriorWall-SteelFramed-1'
    #         wall_reference = 'BTAP-ExteriorWall-SteelFramed-2'
    #       end
    #
    #       next if edge_type == 'transition'
    #
    #       result = csv.find { |row| row['edge_type'] == edge_type &&
    #         row['quality'] == quality &&
    #         row['wall_reference'] == wall_reference
    #       }
    #
    #       if result.nil?
    #         puts ("#{edge_type}-#{wall_reference}-#{quality}")
    #         puts "not found in tb database"
    #         next
    #       end
    #
    #       # Split
    #       material_opaque_id_layers = result['material_opaque_id_layers'].split(",")
    #       id_layers_quantity_multipliers = result['id_layers_quantity_multipliers'].split(",")
    #
    #       material_opaque_id_layers.zip(id_layers_quantity_multipliers).each do |id, scale|
    #         material_quantities[id] = 0.0 if material_quantities[id].nil?
    #         material_quantities[id] = material_quantities[id] + scale.to_f * quantity.to_f
    #       end
    #     end
    #   end
    #
    #   material_opaque_id_quantities = []
    #
    #   material_quantities.each do |id,quantity|
    #     material_opaque_id_quantities << { 'materials_opaque_id' => id, 'quantity' => quantity, 'domain'=> 'thermal_bridging' }
    #   end
    #
    #   return material_opaque_id_quantities
    # end
  end
end

# ----- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----- #
# NOTE: BTAP supports Uo variants for each of the aforementioned wall
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

# NOTE: The BTAP costing spreadsheet holds entries for curtain wall (CW)
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

# NOTE: Some of the aforementioned constructions have exterior brick veneer.
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
# NOTE: BTAP costing: In addition to the listed items for parapets as MAJOR
#       thermal bridges (eventually generating an overall $ per linear meter),
#       BTAP costing requires extending the areas (m2) of OpenStudio wall
#       surfaces (along parapet edges) by 3'-6" (1.1 m) x parapet lengths, to
#       account for the extra cost of completely wrapping the parapet in
#       insulation for "good" (HP) details. See final TBD tally - @todo.
