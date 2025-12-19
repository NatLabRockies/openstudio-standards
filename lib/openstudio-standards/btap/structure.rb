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

module BTAP
  module StructureData
    ##
    # @author: Denis Bourgeois
    #
    # Building STRUCTURE parameters, ultimately driving BTAP definitions of e.g.
    #   - internal mass
    #   - envelope CLADDING/FRAMING/FINISH selection
    #   - related thermal bridging calculations (and uprated insulation levels)
    #   - costing
    #   - embodied carbon tallies
    #
    # As detailed a bit further on, this determination is either via user input:
    #   - e.g. "clt" (mass timber) post/beam STRUCTURE, for a school.
    #
    # Or auto-assigned based on the prevalence of model space type assignments:
    #   - e.g. 75% of spaces are commercial in nature (see activity.rb),
    #     therefore the building STRUCTURE defaults to "steel" post/beam.
    #
    # The overarching idea is that (in most cases) OpenStudio surface
    # construction & material choices (in addition to internal mass definitions),
    # mostly stem from underlying structural design choices (which aren't
    # natively defined in OpenStudio). Structural choices have more to do with
    # fire safety, budget, durability & practicality (low-rise vs high-rise),
    # local workforce, on-site vs prefab, etc.
    #
    # Ensuring consistency between building STRUCTURE, envelope selection,
    # internal mass definitions, etc. is key to harmonizing predicted energy
    # use, peak demand assessments, GHG emissions, vs thermal resilience and
    # embodied energy/GHG tallies.
    #
    # --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --- #
    # Although "wood" framed walls constitute the load-bearing components of a
    # "wood" framed building STRUCTURE (e.g. low-rise housing), they can equally
    # be found as non-load-bearing components in a "clt" post-beam STRUCTURE.
    # Light gauge "steel" framed walls are much more common in a non-residential
    # STRUCTURE (e.g. "steel" post/frame, "concrete" post & beam, and even
    # "clt"), though rarely found in low-rise housing. Although one may observe
    # some real-world mixing of STRUCTURE vs FRAMING in a building, it remains
    # largely deterministic: designers select constructions (FRAMING,
    # insulation) while taking building classification and STRUCTURE selection
    # into consideration - the inverse is rarely true.
    #
    #   STRUCTURE   description
    #   __________  ___________________________________________________________
    #   "steel"     steel, post/frame (default)
    #   "metal"     prefab panelized steel STRUCTURE (**, ++), typically 1 story
    #   "concrete"  reinforced concrete, post/beam/slab
    #   "cmu"       load-bearing concrete masonry unit walls, typically 1-story
    #   "wood"      conventional load-bearing wood-framed and/or -engineered
    #   "clt"       prefab, post/beam mass/cross-laminated/timber (**)
    #
    #   NOTES:
    #
    #    **  Neither "metal" nor "clt" options can be considered as fully
    #        supported by BTAP, e.g.:
    #          - no range of admissible envelope Uo factors
    #          - no associated PSI-factors (thermal bridging)
    #          - no costing data
    #          - no embodied energy/carbon data
    #        They are nonetheless (minimally) maintained here as an
    #        "aide-mémoire" for future BTAP upgrades - @todo.
    #
    #    ++  ASHRAE 90.1 2022 definitions of:
    #
    #        "METAL BUILDING": a complete integrated set of mutually dependent
    #        components and assemblies that form a building, which consists of
    #        a steel-framed superSTRUCTURE and metal skin.
    #
    #        "METAL BUILDING ROOF": a roof that:
    #        a. is constructed with a metal, structural, weathering surface;
    #        b. has no ventilated cavity; and
    #        c. has the insulation entirely below deck (i.e., does not include
    #           composite concrete and metal deck construction nor a roof
    #           FRAMING system that is separated from the superSTRUCTURE by a
    #           wood substrate) and whose STRUCTURE consists of one or more of
    #           the following configurations:
    #           1. Metal roofing in direct contact with steel FRAMING members
    #           2. Metal roofing separated from steel FRAMING by insulation
    #           3. Insulated metal roofing panels installed per (a) or (b)
    #
    #        "METAL BUILDING WALL": a wall whose STRUCTURE consists of metal
    #        spanning members supported by steel structural members (i.e. does
    #        not include spandrel glass or metal panels in curtain wall systems).
    #
    # Note that there's a (growing?) need to contrast "metal" buildings against
    # the default "steel" post/beam option. Like a "wood" framed STRUCTURE or a
    # load-bearing "cmu" wall, a "metal" building's envelope structure and skin
    # are indistinguishable, i.e. no mixing/matching of STRUCTURE vs envelope.
    #
    # There are of course several other (smaller scale) structural options,
    # often load-bearing envelopes like adobe/hemp/straw bale construction. Most
    # would agree that these are fairly rare occurrences - rare enough to avoid
    # shortlisting them for commercial building stock assessments. One could
    # state the same when it comes to the current (marginal) use of "clt". Yet
    # as the latter is rapidly becoming a robust low-carbon alternative to
    # "steel" and "concrete" options, its inclusion is justified. Additional
    # options may nonetheless be added in the future.
    @@data = {structure: {}, cladding: {}, finish: {}, category: {}}

    # Each STRUCTURE inherits a default FRAMING option. Together with the
    # STRUCTURE selection, FRAMING determines inter alia:
    #   - above-grade floor assemblies
    #   - insulated roof assemblies
    #   - cantilevered balconies
    #   - interzone walls
    @@data[:structure]            = {}
    @@data[:structure][:steel   ] = {framing: :steel}
    @@data[:structure][:metal   ] = {framing: :metal}
    @@data[:structure][:concrete] = {framing: :steel}
    @@data[:structure][:cmu     ] = {framing: :cmu  }
    @@data[:structure][:wood    ] = {framing: :wood }
    @@data[:structure][:clt     ] = {framing: :wood }

    # An example. STRUCTURE == "wood" + default FRAMING == "wood", e.g. housing:
    #   - typical engineered wood joists + FINISH
    #   - similar engineered wood rafters + FINISH (if flat or cathedral roof)
    #   - anchored engineered wood joist balconies
    #
    # FRAMING may also determine above-grade exterior wall composition (e.g.
    # wool-insulated wood-framed exterior walls, if FRAMING == "wood"). This
    # may instead be determined by CLADDING selection in several cases.
    #
    # Exterior CLADDING and interior FINISH options are both limited to 4
    # generic labels. Defaults for all STRUCTUREs are "light", for both CLADDING
    # (e.g. metal siding on vented hat-channels) and FINISH (e.g. painted
    # drywall). Brick veneer is an example of "medium" CLADDING, while a 4"
    # precast concrete panel is considered "heavy" CLADDING. A "medium" FINISH
    # is akin to a 4" precast panel concrete, while a "heavy" FINISH is a
    # heftier 8" of (poured) reinforced concrete. Option "none" for CLADDING is
    # rare, even in pre-code buildings. An example would be a load-bearing,
    # "cmu" wall with 2 coats of paint in a semi-heated industrial facility. The
    # "none" FINISH option is slightly more common, e.g. exposed ceilings, bare
    # "clt" walls, and again bare "cmu" walls (or with 2 coats of paint).
    @@data[:cladding] = [:none, :light, :medium, :heavy]
    @@data[:finish  ] = [:none, :light, :medium, :heavy]

    # An above-grade building STRUCTURE would normally be auto-assigned based on
    # the prevalence of space type selections in the model (see activity.rb).
    # Note that all below-grade STRUCTUREs remain "concrete", e.g.:
    #   - basement slabs and slabs-on-grade
    #   - load-bearing basement walls
    #   - basement columns, shear walls, etc. (internal mass)
    #
    # Hopefully, users may also assign STRUCTURE, FRAMING, CLADDING & FINISH
    # options per OpenStudio's building-to-space hierarchy, e.g. - @todo:
    #
    #   Example A: Composite STRUCTURE:
    #     - "concrete" post/beam STRUCTURE for first 4 building stories
    #     - "steel" post/frame STRUCTURE for building stories > 4
    #
    #   Example B: School gym:
    #     - "cmu" gymnasium walls in an otherwise "steel" post/frame school
    #
    # An invalid user-selected STRUCTURE is however caught/logged/corrected:
    #   - no other STRUCTURE above "steel", "metal", "cmu" or "wood" STRUCTUREs
    #   - a "wood" STRUCTURE may rest upon a "clt" STRUCTURE
    #   - any other STRUCTURE may rest upon a "concrete" STRUCTURE
    #
    # With the exception of "metal" buildings, users may optionally interchange
    # some paired STRUCTURE vs FRAMING options (among available :frames above).
    # Unusual in some cases, yet not completely unheard of.
    @@data[:structure][:steel   ][:frames] = [:wood        ]
    @@data[:structure][:metal   ][:frames] = [             ]
    @@data[:structure][:concrete][:frames] = [:wood, :cmu  ]
    @@data[:structure][:cmu     ][:frames] = [:wood, :steel]
    @@data[:structure][:wood    ][:frames] = [:steel       ]
    @@data[:structure][:clt     ][:frames] = [:clt, :steel ]

    # --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- #
    # To simplify data management, building TYPES (e.g. those listed in Table
    # A-8.4.3.2.(2)-A of the NECB 2020) are proposed to fall into more general
    # building CATEGORIES (see activity.rb & NECB_building_types.csv):
    #
    #      CATEGORY   examples
    # _____________  __________________________________________________________
    #     "housing"  MURB, long-term stay, dormitory
    #     "lodging"  hotel, motel, highway lodging
    #      "public"  museum, hospital, school, theatre, terminal
    #    "commerce"  office, dining, retail, fitness, dealership, theatre
    #    "industry"  automotive, manufacturing, workshop, storage
    #  "recreation"  gymnastics, ice arena, indoor soccer/pool
    #      "robust"  penitentiary, parking garage (i.e. heavyduty, resistant)
    #
    # Each CATEGORY holds "small"-scale and "large"-scale STRUCTURE options by
    # defaults, depending on the characteristics of the building.
    @@data[:category]               = {}
    @@data[:category]["housing"   ] = {small: :wood    , large: :concrete}
    @@data[:category]["lodging"   ] = {small: :wood    , large: :concrete}
    @@data[:category]["robust"    ] = {small: :concrete, large: :concrete}
    @@data[:category]["public"    ] = {small: :steel   , large: :concrete}
    @@data[:category]["commerce"  ] = {small: :steel   , large: :steel}
    @@data[:category]["industry"  ] = {small: :cmu     , large: :metal}
    @@data[:category]["recreation"] = {small: :metal   , large: :steel}

    # What constitutes small- vs large-scale varies between CATEGORY, depending
    # either on the maximum number of stories, or the max floor-to-roof height
    # of the tallest first story space.
    @@data[:category]["housing"   ][:stories] =  4
    @@data[:category]["lodging"   ][:stories] =  2
    @@data[:category]["public"    ][:stories] =  2
    @@data[:category]["industry"  ][:height ] =  3.5
    @@data[:category]["recreation"][:height ] = 10.0

    # For instance, a multi-unit residential building (MURB) would have a
    # typical "wood" framed, load-bearing envelope/STRUCTURE up to (and
    # including) 4 stories above-grade. This default STRUCTURE assignment
    # switches to reinforced "concrete" post + flat slab beyond 4 stories.
    # Building CATEGORIES that hold neither :stories nor :height key:value pairs
    # simply retain the same STRUCTURE option by default, regardless of scale
    # (e.g. "robust", "commerce").
    #
    # Default STRUCTURE assignment per building CATEGORY does not preclude the
    # investigation of e.g. "clt" construction in MURBs, offices or sporting
    # facilities. It simply generates a reasonable reference set of structural/
    # framing options, applicable for large parts of the US and Canada. Users
    # have the option of overriding default assignments (@todo).

    ##
    # Returns BTAP Structure data.
    #
    # @return [Hash] BTAP Structure data
    def data
      @@data
    end

    def self.extended(base)
      base.send(:include, self)
    end
  end

  class BTAP::Structure
    extend StructureData

    # @return [String] building type CATEGORY (e.g. "public")
    attr_reader :category

    # @return [Symbol] building STRUCTURE selection (e.g. :steel)
    attr_reader :structure

    # @return [Symbol] building framing (e.g. :steel)
    attr_reader :framing

    # @return [Symbol] building cladding (e.g. :medium)
    attr_reader :cladding

    # @return [Symbol] building finish (e.g. :light)
    attr_reader :finish

    # @return [Float] estimated dead load, in kg/m2 of floor area
    attr_reader :deadload

    # @return [Float] estimated non-occupant live load, in kg/m2 of floor area
    attr_reader :liveload

    # @return [Hash] calculated embodied carbon (CO2-e kg)
    attr_reader :co2

    # @return [Hash] logged messages
    attr_reader :feedback

    ##
    # Initialize BTAP STRUCTURE parameters.
    #
    # @param model [OpenStudio::Model::Model] a model
    # @param activity [BTAP::Activity] a BTAP building ACTIVITY object
    # @param massive [Boolean] whether requesting internal mass generation
    def initialize(model = nil, activity = nil, massive = true)
      mth       = "BTAP::Structure::#{__callee__}"
      @feedback = {logs: []}
      lgs       = @feedback[:logs]
      massive   = false unless [true, false].include?(massive)

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid or empty OpenStudio model (#{mth})"
        return
      end

      unless activity.is_a?(BTAP::Activity)
        lgs << "Invalid or empty BTAP::Activity instance (#{mth})"
        return
      end

      cat = activity.category
      lload = activity.liveload

      if cat.respond_to?(:to_s)
        cat = cat.to_s.downcase

        if cat.empty?
          lgs << "Empty building category (#{mth})"
          return
        else
          unless data[:category].keys.include?(cat)
            lgs << "Unknown building category: #{cat} (#{mth})"
            return
          end
        end
      else
        lgs << "Invalid building category: #{cat.class} (#{mth})"
        return
      end

      if lload.respond_to?(:to_f)
        lload = lload.to_f
      else
        lgs << "Invalid live load (kg/m2): #{lload.class} (#{mth})"
        return
      end

      # Cap internal mass density to 1000 kg/m3, and thickness to 6".
      rho   = 1000.0
      th    = 0.150
      bldg  = model.getBuilding

      @category  = cat
      @structure = data[:category][cat][:small]

      # Switch to :large structure, instead of default :small.
      if data[:category][cat].key?(:stories)
        mx = data[:category][cat][:stories]
        n  = bldg.standardsNumberOfAboveGroundStories
        n  = n.empty? ? 1 : n.get

        @structure = data[:category][cat][:large] if n > mx
      elsif data[:category][cat].key?(:height)
        mx = data[:category][cat][:height]
        n  = bldg.standardsNumberOfAboveGroundStories
        n  = n.empty? ? 1 : n.get

        if n > 1
          @structure = data[:category][cat][:large]
        else
          h = 0

          model.getSpaces.each do |space|
            h = [mx, BTAP::Geometry::Spaces.space_height(space)].max
          end

          @structure = data[:category][cat][:large] if h > mx
        end
      end

      # Reset :clt and :metal structure selections - not yet available. @todo
      @structure = :steel    if @structure == :metal
      @structure = :concrete if @structure == :clt

      # Set building framing, e.g. light-gauge :steel.
      @framing = data[:structure][@structure][:framing]

      # Set exterior cladding.
      @cladding = :light
      @cladding = :medium if @structure == :cmu
      @cladding = :medium if @category  == "public"
      @cladding = :heavy  if @category  == "robust"

      # Set interior finish.
      @finish = :light
      @finish = :none  if @framing == :cmu
      @finish = :heavy if @category == "robust"

      # 'Dead load' refers to the self-weight of structural elements of a
      # building, as well as non-structural fixtures that are permanently
      # attached to the building. They are considered 'dead' as they typically
      # do not move around during the life of the building. If/once a building
      # is resold, its new owners recover dead load as 'real estate assets'.
      # Dead load typically falls under design scopes of architects/engineers.
      # Although there are obvious design constraints to consider (e.g. fire
      # safety, $), designers do get to make design decisions when it comes to
      # dead load, e.g.:
      #   - between steel vs concrete post/beam/slab structural options
      #   - between light-gauge steel vs CMU wall construction options
      #   - between foam vs fibrous insulation options
      #
      # Most dead load is modelled explicitly in OpenStudio, like envelope and
      # interzone sub/surfaces. Rough estimates of embodied carbon (in CO2-e
      # kg/m2) can be reasonably associated to selected construction assemblies
      # (based on m2), such as the embodied carbon of chosen insulation
      # materials or framing options. Other dead load, like lighting and HVAC,
      # are not modelled explicitly. Here, the 'deadload' attribute represents
      # a mass floor area density estimate (kg/m2) of non-modelled structural
      # and non-structural items like fixed furniture, partitions, columns,
      # beams, shear walls and bracing.

      # First, isolate occupied spaces & floors, as well as exposed surfaces.
      cspaces   = model.getSpaces.select { |sp| sp.partofTotalFloorArea }
      floor_m2  = TBD.facets(cspaces, "all", "floor").map(&:grossArea).sum
      ofloor_m2 = TBD.facets(cspaces, "outdoors", "floor").map(&:grossArea).sum
      ifloor_m2 = TBD.facets(cspaces, "surface", "floor").map(&:grossArea).sum
      roof_m2   = TBD.facets(cspaces, "outdoors", "roofceiling").map(&:grossArea).sum
      wall_m2   = TBD.facets(cspaces, "outdoors", "walls").map(&:grossArea).sum
      iwall_m2  = TBD.facets(cspaces, "surface", "wall").map(&:grossArea).sum

      # In OpenStudio, partitions are usually limited to interzone walls between
      # zones, in order to save on simulation times. Partitions typically absent
      # from a model include walls surrounding lobbies, stairwells, WCs and
      # technical rooms, as well as separations between similar rooms (e.g.
      # multiple, side-by-side enclosed offices, a row of hotel rooms).
      # Comparing BTAP prototype models and samples of building plans for
      # similar facilities suggest matching modelled partition m2 (or total
      # floor m2) as a suitable basis to determine the weight of non-modelled
      # partitions. As this estimate may be more on the high side for many
      # prototype models, fixed appliances (e.g. fixtures, counters, doors and
      # windows) are considered included.
      # partition_m2 = iwall_m2
      # partition_m2 = floor_m2 if partition_m2 > floor_m2
      partition_m2 = floor_m2

      # For wood-framed partitions, representative material volumes (per m2):
      #  - 16% wood-framing: 0.0224 m3/m2 x 540 kg/m3 =  12.1 kg/m2 (35.7%)
      #  - 84% insulation  : 0.1176 m3/m2 x  19 kg/m3 =   2.2 kg/m2 ( 6.5%)
      #  - drywall (2x)    : 0.0250 m3/m2 x 785 kg/m3 =  19.6 kg/m2 (57.8%)
      #                                               =  33.9 kg/m2
      #
      # For steel-framed partitions, representative material volumes (per m2):
      #  - 1% steel-framing:   1.25 x 2.5 x 1.5 kg/m  =   4.7 kg/m2 (17.3%)
      #  - 99% insulation  : 0.1504 m3/m2 x  19 kg/m3 =   2.9 kg/m2 (10.7%)
      #  - drywall (2x)    : 0.0250 m3/m2 x 785 kg/m3 =  19.6 kg/m2 (72.0%)
      #                                               =  27.2 kg/m2
      #
      # For CMU partitions, representative material volumes (per m2):
      #  - 10" medium weight CMU                      = 250.0 kg/m2 (approx.)

      case @framing
      when :cmu  then partition_kgm2 = 250.0 * partition_m2 / floor_m2
      when :wood then partition_kgm2 =  33.9 * partition_m2 / floor_m2
      else            partition_kgm2 =  27.2 * partition_m2 / floor_m2
      end

      # Structural dead load - not explicitly modelled - include columns,
      # bracing, connectors, etc. For BTAP purposes, some basic assumptions are
      # required:
      #   - 9m x 9m spans
      #   - approx. 15 columns / 1000 m2 of floor area
      #   - approx. 14" x 14" columns (0.126 m2)
      #     - if structure :steel or :metal (HP14x102):
      #       - 152 kg/m (x 125% for bracing, etc.)   = 190 kg/m
      #     - if structure :concrete
      #       - concrete: 2240 kg/m3 x 0.126 m2 x 97% = 274 kg/m
      #       - rebar:    7850 kg/m3 x 0.126 m2 x  3% =  30 kg/m
      #                                               = 304 kg/m (+11%)
      #     - if structure :cmu (mix of load bearing walls + smaller pours)
      #       - 1/2 :concrete                         = 150 kg/m
      #     - if structure :clt
      #       - wood:     540 kg/m3 x 0.126 m2 x 97%  =  66 kg/m
      #       - anchors: 7850 kg/m3 x 0.126 m2 x 3%   =  30 kg/m
      #                                               =  96 kg/m (+45%)
      #     - if structure :wood
      #       - 1/2 :clt                              =  48 kg/m

      # Fetch approx. total column height (m) in building (including plenums).
      column_m = 0

      model.getSpaces.each do |space|
        column_m += BTAP::Geometry::Spaces.space_height(space) * 15 / 1000
      end

      case @structure
      when :steel then column_kgm2 = 190 * column_m / floor_m2
      when :metal then column_kgm2 = 190 * column_m / floor_m2
      when :cmu   then column_kgm2 = 150 * column_m / floor_m2
      when :wood  then column_kgm2 =  48 * column_m / floor_m2
      when :clt   then column_kgm2 =  96 * column_m / floor_m2
      else             column_kgm2 = 304 * column_m / floor_m2
      end

      @deadload = partition_kgm2 + column_kgm2

      # The 'liveload' attribute represents the mass area density (kg/m2) of
      # dynamic, yet uniform floor live load from non-permanent items like
      # furniture, documents, copiers and computers, i.e. not real estate
      # assets. Architects and engineers deal with (fixed) live load as design
      # constraint - not as potential design option. Non-occupant live load is
      # taken into account when setting internal mass. Yet as a non-real estate
      # item, live load is not considered when tallying embodied carbon.
      #
      # Within BTAP, non-occupant live load estimates are stored in the
      # "NECB_building_types.csv" file, parsed/stored in a BTAP::Activity
      # instance (1x per building activity). These estimates are initially based
      # on NBC Part 4 minimum live load requirements (kPa), as well as data from
      # established structural engineering resources. Minimum live load kPa (or
      # psf) estimates, corresponding to hundreds of kg/m2 of floor area, are
      # strictly for structural dimensioning/safety purposes. They are not (or
      # are very rarely) representative of actual day-to-day loads. Back of the
      # envelope calculations suggest reducing live load code requirements down
      # to ~1/12th of their initial values for internal mass purposes. These
      # code requirements also include occupants, which should be set aside -
      # by subtracting the total building population mass:
      #
      #   - NECB building occupant density (occupant/m2) x avg. 80 kg/adult
      #
      # This gives for instance a resulting live load estimate of 23 kg/m2 for
      # housing (low) and a 61 kg/m2 for manufacturing (high). It is obviously
      # challenging to pin down a single-number estimate for several building
      # types, including bigbox retail and warehousing. Grain of salt.
      @liveload = lload

      # Add internal mass objects, 1x instance per occupied space.
      cspaces.each do |space|
        break unless massive

        matID = "#{space.nameString} : Mass Material"
        conID = "#{space.nameString} : Mass Construction"
        defID = "#{space.nameString} : Mass Definition"
        mssID = "#{space.nameString} : Mass"

        # Calculate total mass of internal mass (kg), then thickness.
        kg = space.floorArea * (@liveload + @deadload)
        m2 = kg / rho / th

        mat = OpenStudio::Model::StandardOpaqueMaterial.new(model)
        mat.setName(matID)
        mat.setRoughness("MediumRough")
        mat.setThickness(th)
        mat.setConductivity(1.0)
        mat.setDensity(rho)
        mat.setSpecificHeat(1000)
        mat.setThermalAbsorptance(0.9)
        mat.setSolarAbsorptance(0.7)
        mat.setVisibleAbsorptance(0.7)

        con = OpenStudio::Model::Construction.new(model)
        con.setName(conID)
        layers = OpenStudio::Model::MaterialVector.new
        layers << mat
        con.setLayers(layers)

        df = OpenStudio::Model::InternalMassDefinition.new(model)
        df.setName(defID)
        df.setConstruction(con)
        df.setSurfaceArea(space.floorArea)
        df.setSurfaceArea(m2)

        mass = OpenStudio::Model::InternalMass.new(df)
        mass.setName(mssID)
        mass.setSpace(space)
      end

      # Embodied CO2-e kg (A1-A3) of a model is tallied separately as follows:
      @co2              = {}
      @co2[:structure ] = 0
      @co2[:insulation] = 0
      @co2[:cladding  ] = 0

      # The :structure key/value pair includes above grade 'structures' (e.g.
      # slabs, columns) and 'framing' (e.g. wood-framed vs steel-framed). Why
      # grouped together? In many smaller-scale facilities, structure and
      # framing are synonymous, or at least tightly coupled, e.g.:
      #   - load-bearing wood-framed walls in small-scale residential
      #   - load-bearing CMU walls in small-scale industrial
      #   - metal buildings
      #
      # Below-grade structures (rebar + poured concrete) are ignored - no
      # alternative options are considered for the moment, e.g. lower carbon
      # concrete mixes.
      #
      # Upon initialization, only the :structure tally is set. It is assumed
      # that structure (and main framing) do not change with NECB U-factor
      # requirements, e.g.:
      #   - NECB 2011 vs 2020
      #   - Vancouver vs Calgary
      #
      # Once default construction sets are (later) established (+), followed by
      # TBD uprating assemblies as per NECB 2017 & 2020 requirements (++),
      # embodied carbon tallies can be updated/reset, which would include:
      #   - cladding
      #   - insulation
      #   - secondary framing (proportional to insulation thicknesses)
      #
      #  (+) openstudio-standards/standards/necb/NECB2011/building_envelope.rb
      # (++) openstudio-standards/btap/bridging.rb

      # Start with occupied floors & roofs (exclude slabs on grade).
      m2 = ofloor_m2 + ifloor_m2 + roof_m2

      case @structure
      when :wood     then # engineered I-joists + plywood
        floor_kg    = 50.0 * m2
        floor_m3    = floor_kg / 540.0                  # kg/m3
        floor_co2kg = floor_m3 * 55.0 / floor_kg        # kgCO2-e/kg
      when :concrete then # 200mm flat slab, 3% rebar + accessories
        floor_m3    = 0.200 * m2
        floor_kgm3  = (0.03 * 7850.0) + (0.97 * 2240.0) # kg/m3
        floor_co2kg = (0.03 * 0.854 ) + (0.97 *  0.250) # kgCO2-e/kg
        floor_kg    = floor_m3 * floor_kgm3
      else # :steel, includes joists/fasteners
        floor_m3    = 0.125 * m2
        floor_kgm3  = (0.08 * 7850.0) + (0.92 * 2240.0) # kg/m3
        floor_co2kg = (0.08 * 0.854 ) + (0.92 *  0.250) # kgCO2-e/kg
        floor_kg    = floor_m3 * floor_kgm3
      end

      @co2[:structure] += floor_co2kg * floor_kg

      # Add exposed walls and interior partitions.
      m2 = wall_m2 + iwall_m2 + partition_m2

      case @framing
      when :wood then # basic 2x6 construction, 16% of framing cavity
        wall_kg    =  12.1 * m2
        wall_co2kg =  55.0 / 540.0 # 55 kgCO2-e/m3 / density
      when :cmu  then # 250mm medium weight CMU, 200 kgCO2-e/m3
        wall_m3    = 0.250 * m2    # nominal m3
        wall_kg    = 250.0 * m2    # volume-weighted concrete/air/grout
        wall_kgm3  = 0.250 / 250.0
        wall_co2kg = 200.0 / wall_kgm3 # 200 kgCO2-e/m3 / density
      else # :steel, 1% lightweight steel-framing
        wall_kg    =   4.7 * m2
        wall_co2kg = 2.440
      end

      @co2[:structure] += wall_co2kg * wall_kg

      true
    end

    ##
    # Updates and returns embodied carbon estimates (A1-A3).
    #
    # @param model [OpenStudio::Model::Model] a model
    #
    # @return [Hash] embodied carbon tally (CO2-e kg, A1-A3)
    def tallyCO2(model)
      mth = "BTAP::Structure::#{__callee__}"
      cl  = OpenStudio::Model::Model
      lgs = @feedback[:logs]

      unless model.is_a?(cl)
        lgs << "Invalid OpenStudio model (#{mth})"
        return 0
      end

      # @todo

      @co2
    end
  end
end
