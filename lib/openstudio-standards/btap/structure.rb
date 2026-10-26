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
    # ... or auto-assigned based on the prevalence of model space types:
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
    # use, peak demand assessments, GHG emissions, thermal resilience and
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
    #        supported by BTAP at this stage, e.g.:
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
    # load-bearing "cmu" wall, a "metal" building's structure and envelope are
    # indistinguishable, i.e. no mixing/matching of STRUCTURE vs envelope.
    #
    # There are of course several other (smaller scale) structural options,
    # often load-bearing envelopes like adobe/hemp/straw bale construction. Most
    # would agree that these are fairly rare occurrences - rare enough to avoid
    # shortlisting them for commercial building stock assessments. One could
    # state the same when it comes to the current (marginal) use of "clt". Yet
    # as the latter is rapidly becoming a robust low-carbon alternative to
    # "steel" and "concrete" options, its inclusion seems justified. Additional
    # options may be added in the future.
    @@data = {structure: {}, cladding: {}, finish: {}, category: {}, tags: []}

    # Admissible AdditionalProperty keys for customization.
    @@data[:tags] << "btap_structure"
    @@data[:tags] << "btap_framing"
    @@data[:tags] << "btap_cladding"
    @@data[:tags] << "btap_finish"

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
    #   - similar engineered wood rafters + FINISH (when flat or cathedral roof)
    #   - anchored engineered wood joist balconies
    #
    # FRAMING may also determine above-grade exterior wall composition (e.g.
    # wool-insulated wood-framed exterior walls, when FRAMING == "wood"). This
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
    # "clt" walls, and again bare "cmu" walls.
    @@data[:cladding] = [:none, :light, :medium, :heavy]
    @@data[:finish  ] = [:none, :light, :medium, :heavy]

    # An above-grade building STRUCTURE would normally be auto-assigned based on
    # the prevalence of space type selections in the model (see activity.rb).
    # Note that all below-grade STRUCTUREs remain "concrete", e.g.:
    #   - basement slabs and slabs-on-grade
    #   - load-bearing basement walls
    #   - basement columns, shear walls, etc. (internal mass)
    #
    # BTAP users can also explicitely assign STRUCTURE, FRAMING, CLADDING &
    # FINISH options per OpenStudio's building-to-space hierarchy, e.g.:
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
    @@data[:structure][:steel   ][:frames] = [:steel, :wood        ]
    @@data[:structure][:metal   ][:frames] = [:metal               ]
    @@data[:structure][:concrete][:frames] = [:steel, :wood, :cmu  ]
    @@data[:structure][:cmu     ][:frames] = [:cmu,   :wood, :steel]
    @@data[:structure][:wood    ][:frames] = [:wood,  :steel       ]
    @@data[:structure][:clt     ][:frames] = [:wood,  :clt,  :steel]

    # --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- #
    # To simplify data management, building TYPES (e.g. those listed in Table
    # A-8.4.3.2.(2)-A of the NECB 2020) fall into more general building
    # CATEGORIES (see activity.rb & btap_building_types.csv):
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
    # Each CATEGORY holds default "small"-scale and "large"-scale STRUCTURE
    # options, set based on building characteristics.
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

    # @return [String] default building type CATEGORY (e.g. "public")
    attr_reader :category

    # @return [Symbol] default building STRUCTURE selection (e.g. :steel)
    attr_reader :structure

    # @return [Symbol] default building framing (e.g. :steel)
    attr_reader :framing

    # @return [Symbol] default building cladding (e.g. :medium)
    attr_reader :cladding

    # @return [Symbol] default building finish (e.g. :light)
    attr_reader :finish

    # @return [Hash] customized STRUCTURE, FRAMING, CLADDING & FINISH per space
    attr_reader :spaces

    # @return [Float] default building dead load, in floor kg/m2
    attr_reader :deadload

    # @return [Float] default building non-occupant live load, in floor kg/m2
    attr_reader :liveload

    # @return [Hash] default building STRUCTURE embodied carbon (CO2-e kg)
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

      cat   = activity.category
      lload = activity.liveload

      if cat.respond_to?(:to_sym)
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

      bldg       = model.getBuilding
      @category  = cat
      @structure = data[:category][cat][:small]
      @spaces    = {}

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
      @finish = :none  if @framing  == :cmu
      @finish = :heavy if @category == "robust"

      # Validate customization requests - override if user requests are invalid.
      # Custom cladding and finish options are caught and held in memory, yet
      # aren't fully supported for all costed constructions - may be ignored.
      [:structure, :framing, :cladding, :finish].each do |item|
        tag = "btap_" + item.to_s
        opt = case item
              when :framing  then @framing
              when :cladding then @cladding
              when :finish   then @finish
              else                @structure
              end

        if bldg.additionalProperties.hasFeature(tag)
          prp = bldg.additionalProperties.getFeatureAsString(tag)

          if prp.empty?
            bldg.additionalProperties.setFeature(tag, opt.to_s)
          else
            prp = prp.get.downcase.to_sym

            case item
            when :structure
              if data[:structure].key?(prp)
                @structure = prp

                # Reset :clt and :metal structure selections for now - @todo
                @structure = :steel    if @structure == :metal
                @structure = :concrete if @structure == :clt

                # Conditionally reset framing, cladding and/or finish.
                @framing  = data[:structure][@structure][:framing]
                @cladding = :medium if @structure == :cmu
                @finish   = :none   if @framing   == :cmu
              else
                bldg.additionalProperties.setFeature(tag, @structure.to_s)
              end
            when :framing
              if data[:structure][@structure][:frames].include?(prp)
                @framing = prp

                # Conditionally reset finish.
                @finish = :none if @framing == :cmu
              else
                bldg.additionalProperties.setFeature(tag, @framing.to_s)
              end
            when :cladding
              if data[:cladding].include?(prp)
                @cladding = prp
              else
                bldg.additionalProperties.setFeature(tag, @cladding.to_s)
              end
            when :finish
              if data[:finish].include?(prp)
                @finish = prp
              else
                bldg.additionalProperties.setFeature(tag, @finish.to_s)
              end
            end
          end
        else
          bldg.additionalProperties.setFeature(tag, opt.to_s)
        end
      end

      # Track CONDITIONED spaces, e.g. rooms & plenums - ignore vented attics.
      cspaces = model.getSpaces.reject { |sp| TBD.unconditioned?(sp) }

      if cspaces.empty?
        lgs << "Only UNCONDITIONED spaces (#{mth})"
        return
      end

      # Customized space-specific STRUCTURE attributes, overriding
      # default/custom building-wide attributes.
      data[:tags].each do |tag|
        cspaces.each do |space|
          id = space.nameString
          zn = space.thermalZone
          next if zn.empty?
          next unless space.floorArea > 0

          # Retrieve/validate tagged AdditionalProperty (if assigned to story,
          # spacetype or space).
          prp = property(space, tag)
          next unless prp

          # Skip if same as building.
          next if tag == "btap_structure" && prp == @structure
          next if tag == "btap_framing"   && prp == @framing
          next if tag == "btap_cladding"  && prp == @cladding
          next if tag == "btap_finish"    && prp == @finish

          unless @spaces.key?(id)
            @spaces[id]       = {}
            @spaces[id][:m2 ] = space.floorArea
            @spaces[id][:h  ] = BTAP::Geometry::Spaces.space_height(space)
            @spaces[id][:co2] = {columns: 0, partitions: 0}

            # Initialized with building attributes by default.
            @spaces[id][:structure] = @structure
            @spaces[id][:framing  ] = @framing
            @spaces[id][:cladding ] = @cladding
            @spaces[id][:finish   ] = @finish
          end

          # Reset if compatible.
          case tag
          when "btap_structure"
            @spaces[id][:structure] = prp

            # Conditionally reset framing, cladding and/or finish.
            @spaces[id][:framing ] = data[:structure][prp][:framing]
            @spaces[id][:cladding] = :medium if @spaces[id][:structure] == :cmu
            @spaces[id][:finish  ] = :none   if @spaces[id][:framing  ] == :cmu
          when "btap_framing"
            @spaces[id][:framing] = prp

            # Conditionally reset finish.
            @spaces[id][:finish] = :none if @spaces[id][:framing] == :cmu
          when "btap_cladding"
            @spaces[id][:cladding] = prp
          when "btap_finish"
            @spaces[id][:finish] = prp
          else
          end
        end
      end

      # Prune customized spaces from common collection.
      @spaces.keys.each { |id| cspaces.delete(model.getSpaceByName(id).get) }

      # Only customized spaces left? Base building STRUCTURE on most common one.
      if cspaces.empty?
        custom = []
        id     = @spaces.keys.first
        sp     = @spaces.values.first
        espace = model.getSpaceByName(id).get

        first             = {}
        first[:spaces   ] = [espace]
        first[:structure] = sp[:structure]
        first[:framing  ] = sp[:framing]
        first[:cladding ] = sp[:cladding]
        first[:finish   ] = sp[:finish]
        first[:m2       ] = sp[:m2] * espace.multiplier
        custom           << first

        @spaces.each do |id, sp|
          match = false
          space = model.getSpaceByName(id).get
          next if space == espace

          custom.each do |csp|
            break if match

            if sp[:structure] == csp[:structure] &&
               sp[:framing  ] == sp[:framing   ] &&
               sp[:cladding ] == sp[:cladding  ] &&
               sp[:finish   ] == sp[:finish    ]
              csp[:spaces] << space
              csp[:m2    ] += sp[:m2] * space.multiplier
              match = true
            end
          end

          unless match
            spx             = {}
            spx[:spaces   ] = [space]
            spx[:structure] = sp[:structure]
            spx[:framing  ] = sp[:framing]
            spx[:cladding ] = sp[:cladding]
            spx[:finish   ] = sp[:finish]
            spx[:m2       ] = sp[:m2] * space.multiplier
            custom         << spx
          end
        end

        if custom.empty?
          lgs << "Unknown UNCONDITIONED spaces (#{mth})?"
          return
        end

        csp = custom.sort_by { |sp| sp[:m2] }.reverse.first

        cspaces    = csp[:spaces]
        @structure = csp[:structure]
        @framing   = csp[:framing]
        @cladding  = csp[:cladding]
        @finish    = csp[:finish]
        bldg.additionalProperties.setFeature("btap_structure", @structure.to_s)
        bldg.additionalProperties.setFeature("btap_framing", @framing.to_s)
        bldg.additionalProperties.setFeature("btap_cladding", @cladding.to_s)
        bldg.additionalProperties.setFeature("btap_finish", @finish.to_s)

        cspaces.each { |space| @spaces.delete(space.nameString) }
      end

      if cspaces.empty?
        lgs << "Invalid # CONDITIONED spaces (#{mth})?"
        return
      end

      # Isolate OCCUPIED spaces.
      ospaces = cspaces.select { |space| space.partofTotalFloorArea }

      # Scenario A - no space customization, i.e. default BTAP scenario:
      #   - take-off areas below (m2) reflect all CONDITIONED spaces
      #
      # Scenario B - one or more spaces are customized, e.g. :framing
      #   - take-off areas below (m2) reflect non-customized spaces only
      #   - look up @spaces to retrieve custom space-specific take-offs.
      m2  = cspaces.sum(&:floorArea)
      om2 = ospaces.sum(&:floorArea)

      # --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- #
      # 'Dead load' refers to the self-weight of structural elements of a
      # building, as well as non-structural fixtures that are permanently
      # attached to the building. They are considered 'dead' as they typically
      # do not move around during the life of the building. Once a building
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
      # interzone surfaces. Rough estimates of embodied carbon (in CO2-e kg of
      # surface m2) can be reasonably associated to selected construction
      # assemblies, such as the embodied carbon of chosen insulation materials
      # or framing options. Other dead load, like lighting and HVAC, are not
      # modelled explicitly. Here, the 'deadload' attribute represents a mass
      # floor area density estimate (kg/m2) of non-modelled structural and
      # non-structural items like fixed furniture, columns, beams, shear walls
      # and bracing, as well as 'partitions'.
      #
      # Note that OpenStudio supports an InteriorPartitionSurface class, useful
      # mainly for daylighting. Although similar, 'partition' (within the scope
      # of BTAP::Structure) more generally refers to any non-modelled wall, e.g.
      # those surrounding lobbies, stairwells, WCs and technical rooms, as well
      # as separations between similar rooms (e.g. multiple, side-by-side
      # enclosed offices, a row of hotel rooms). Comparing BTAP prototype models
      # and samples of building plans for similar facilities suggests matching
      # modelled partition m2 with floor m2 as a suitable basis to estimate the
      # mass of non-modelled partitions. As this estimate may be more on the
      # high side for many prototype models, fixed appliances (e.g. fixtures,
      # counters, doors and windows) are considered included. Adjusting for
      # larger spaces, based on building category.
      partition_m2 = case @category
                     when "commerce"   then m2 / 2
                     when "industry"   then m2 / 4
                     when "recreation" then m2 / 3
                     else                   m2
                     end

      # For wood-framed partitions, representative material mass (per m2):
      #  - 16% wood-framing: 0.0224 m3/m2 x 540 kg/m3 =  12.1 kg/m2 (35.7%)
      #  - 84% insulation  : 0.1176 m3/m2 x  19 kg/m3 =   2.2 kg/m2 ( 6.5%)
      #  - drywall (2x)    : 0.0250 m3/m2 x 785 kg/m3 =  19.6 kg/m2 (57.8%)
      #                                               =  33.9 kg/m2
      #
      # For steel-framed partitions, representative material mass (per m2):
      #  - 1% steel-framing:   1.25 x 2.5 x 1.5 kg/m  =   4.7 kg/m2 (17.3%)
      #  - 99% insulation  : 0.1504 m3/m2 x  19 kg/m3 =   2.9 kg/m2 (10.7%)
      #  - drywall (2x)    : 0.0250 m3/m2 x 785 kg/m3 =  19.6 kg/m2 (72.0%)
      #                                               =  27.2 kg/m2
      #
      # For CMU partitions, representative material mass (per m2):
      #  - 10" medium weight CMU                      = 250.0 kg/m2 (approx.)
      partition_rho = case @framing
                      when :cmu  then 250.0
                      when :wood then  33.9
                      else             27.2
                      end

      # Partition kg / floor area.
      partition_kgm2 = 0
      partition_kgm2 = partition_rho * partition_m2 / m2 if m2 > 0

      # Repeat for customized spaces.
      @spaces.each do |id, sp|
        sp[:partition_m2] = case @category
                            when "commerce"   then sp[:m2] / 2
                            when "industry"   then sp[:m2] / 4
                            when "recreation" then sp[:m2] / 3
                            else                   sp[:m2]
                            end

        if sp.key?(:framing)
          p_rho = case sp[:framing]
                  when :cmu  then 250.0
                  when :wood then  33.9
                  else             27.2
                  end
        else
          p_rho = partition_rho
        end

        sp[:partition_kgm2] = p_rho * sp[:partition_m2] / sp[:m2]
      end

      # Structural dead load - not explicitly modelled - include columns,
      # bracing, connectors, etc. For BTAP purposes, some basic assumptions are
      # required:
      #   - 9m x 9m spans
      #   - approx. 15 columns / 1000 m2 of floor area
      #   - approx. 14" x 14" columns (0.126 m2)
      #     - if structure :steel or :metal (W10x49)
      #       - 73 kg/m (x 125% for bracing, etc.)    =  91 kg/m
      #     - if structure :concrete
      #       - concrete: 2240 kg/m3 x 0.126 m2 x 97% = 274 kg/m
      #       - rebar:    7850 kg/m3 x 0.126 m2 x  3% =  30 kg/m
      #                                               = 304 kg/m
      #       - x 125% for shear walls, etc.          = 380 kg/m
      #     - if structure :cmu (mix of load bearing walls + smaller pours)
      #       - 1/2 :concrete                         = 190 kg/m
      #     - if structure :clt
      #       - wood:     540 kg/m3 x 0.126 m2 x 97%  =  66 kg/m
      #       - anchors: 7850 kg/m3 x 0.126 m2 x 3%   =  30 kg/m
      #                                               =  96 kg/m
      #       - x 125% for shear walls, etc.          = 120 kg/m
      #     - if structure :wood
      #       - 1/2 :clt                              =  60 kg/m

      # Fetch approx. total column height (m) and linear density.
      column_m   = 0
      column_rho = case @structure
                   when :steel then  91
                   when :metal then  91
                   when :cmu   then 190
                   when :wood  then  60
                   when :clt   then 120
                   else             380
                   end

      cspaces.each do |space|
        zn = space.thermalZone
        next if zn.empty?

        fm2 = space.floorArea
        next unless fm2 > 0

        column_m += BTAP::Geometry::Spaces.space_height(space) * fm2 * 15 / 1000
      end

      column_kgm2 = 0
      column_kgm2 = column_rho * column_m / m2 if m2 > 0
      @deadload   = partition_kgm2 + column_kgm2

      # Repeat for customized spaces.
      @spaces.values.each do |sp|
        col_m = sp[:h] * sp[:m2] * 15 / 1000

        if sp.key?(:structure)
          c_rho = case sp[:structure]
                  when :steel then  91
                  when :metal then  91
                  when :cmu   then 190
                  when :wood  then  60
                  when :clt   then 120
                  else             380
                  end
        else
          c_rho = column_rho
        end

        sp[:column_kgm2] = c_rho * col_m / sp[:m2]
        sp[:deadload   ] = sp[:partition_kgm2] + sp[:column_kgm2]
      end

      # The 'liveload' attribute represents the mass area density (kg/m2) of
      # dynamic, yet uniform floor live load from non-permanent items like
      # furniture, documents, copiers and computers, i.e. not real estate
      # assets. Architects and engineers deal with (fixed) live load as design
      # constraint - not as potential design option. Non-occupant live load is
      # taken into account when setting internal mass. Yet as a non-real estate
      # item, live load is not considered when tallying embodied carbon.
      #
      # Within BTAP, non-occupant live load estimates are stored in the
      # "btap_building_types.csv" file, parsed/stored in a BTAP::Activity
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

      # Cap internal mass density to 1000 kg/m3, and thickness to 6".
      rho = 1000.0
      th  = 0.150

      # Add internal mass objects, 1x instance per CONDITIONED space.
      cspaces.each do |space|
        break unless massive

        id = space.nameString

        matID = "#{id} : Mass Material"
        conID = "#{id} : Mass Construction"
        defID = "#{id} : Mass Definition"
        mssID = "#{id} : Mass"

        # Calculate total internal mass (kg), then thickness.
        if @spaces.key?(id)
          load_kgm2  = @liveload + @spaces[id][:deadload]
        else
          load_kgm2  = @deadload
          load_kgm2 += @liveload if ospaces.include?(space)
        end

        kg  = space.floorArea * load_kgm2
        im2 = kg / rho / th

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
        df.setSurfaceArea(im2)

        mass = OpenStudio::Model::InternalMass.new(df)
        mass.setName(mssID)
        mass.setSpace(space)
      end

      # Embodied CO2-e kg (A1-A3?) of a model's structure is broken down into:
      #   - non-modelled above grade items COLUMNS
      #   - non-modelled PARTITIONS
      #
      # COLUMN and PARTITION CO2-e kg estimates are limited to non-customized
      # spaces (look for equivalent entries in customized @spaces). Yet
      # all COLUMN and PARTITION estimates (for both custom and non-custom
      # spaces) are ultimately tallied in the STRUCTURE CO2-e kg entry.
      #
      # Note that below-grade structures (rebar + poured concrete) are ignored,
      # as there are no alternative BTAP options (e.g. low carbon concrete mix).
      @co2 = {}

      # Add columns.
      column_kgco2kg = case @structure
                       when :steel then  0.854         #  0.854 kgCO2-e/kg
                       when :metal then  0.854         #  0.854 kgCO2-e/kg
                       when :wood  then 55.000 / 540.0 # 55.000 kgCO2-e/m3
                       when :clt   then 55.000 / 540.0 # 55.000 kgCO2-e/m3
                       else              0.268         #  0.268 kgCO2-e/kg
                       end

      @co2[:columns] = column_kgco2kg * column_m * column_rho

      # Add interior partitions, based on framing options only. Other partition
      # components are ignored for now (e.g. drywall, acoustic insulation).
      partition_kgco2m2 = case @framing
                          when :wood then  55.000 * 12.1 / 540.0
                          when :cmu  then 200.000 * 0.250
                          else              0.854 * 4.7
                          end

      @co2[:partitions] = partition_kgco2m2 * partition_m2
      @co2[:structure ] = @co2[:columns] + @co2[:partitions]

      # Repeat for customized spaces.
      @spaces.each do |id, sp|
        if sp.key?(:structure)
          c_kgco2kg = case sp[:structure]
                      when :steel then  0.854         #  0.854 kgCO2-e/kg
                      when :metal then  0.854         #  0.854 kgCO2-e/kg
                      when :wood  then 55.000 / 540.0 # 55.000 kgCO2-e/m3
                      when :clt   then 55.000 / 540.0 # 55.000 kgCO2-e/m3
                      else              0.268         #  0.268 kgCO2-e/kg
                      end
        else
          c_kgco2kg = column_kgco2kg
        end

        if sp.key?(:framing)
          p_kgco2m2 = case sp[:framing]
                      when :wood then  55.000 * 12.1 / 540.0
                      when :cmu  then 200.000 * 0.250
                      else              0.854 * 4.7
                      end
        else
          p_kgco2m2 = partition_kgco2m2
        end

        sp[:co2][:columns   ] = c_kgco2kg * sp[:column_kgm2] * sp[:m2]
        sp[:co2][:partitions] = p_kgco2m2 * sp[:partition_m2]

        @co2[:structure] += sp[:co2][:columns] + sp[:co2][:partitions]
      end

      # Set an AdditionalProperty for tallied CO2-e [kg] (A1-A3):
      tag = "co2_structure"
      bldg.additionalProperties.setFeature(tag, @co2[:structure])

      true
    end

    ##
    # Returns an (inherited) AdditionalProperty, applicable to a given space.
    # Four admissible STRUCTURE AdditionalProperty keys: "btap_structure",
    # "btap_framing", "btap_cladding", "btap_finish". If an AdditionalProperty
    # key is correctly identified yet its value invalid (per BTAP::Structure
    # rules), its value is reset to building defaults.
    #
    # @param space [OpenStudio::Model::Space] a space
    # @param tag [String] AdditionalProperty key, e.g. "btap_structure"
    #
    # @return [Symbol] AdditionalProperty value (nil if invalid inputs)
    def property(space = nil, tag = "")
      mth = "BTAP::Structure::#{__callee__}"
      lgs = @feedback[:logs]
      prp = nil

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return prp
      end

      unless tag.respond_to?(:to_sym)
        lgs << "Invalid STRUCTURE AddtionalProperty tag (#{mth})"
        return prp
      end

      tag = tag.to_s.downcase

      unless data[:tags].include?(tag)
        lgs << "Unrecognized STRUCTURE AddtionalProperty '#{tag}' (#{mth})"
        return prp
      end

      # Check if the AdditionalProperty is assigned to the space itself.
      if space.additionalProperties.hasFeature(tag)
        prp = space.additionalProperties.getFeatureAsString(tag)

        if prp.empty?
          lgs << "Unknown space AddtionalProperty '#{tag}' (#{mth})"
          prp = nil
        else
          prp = prp.get.downcase.to_sym
        end
      end

      # Check if the AdditionalProperty is instead assigned to the spacetype.
      unless prp
        type = space.spaceType

        unless type.empty?
          type = type.get

          if type.additionalProperties.hasFeature(tag)
            prp = type.additionalProperties.getFeatureAsString(tag)

            if prp.empty?
              lgs << "Unknown spacetype AddtionalProperty '#{tag}' (#{mth})"
              prp = nil
            else
              prp = prp.get.downcase.to_sym
            end
          end
        end
      end

      # Check if the AdditionalProperty is instead assigned to building story.
      unless prp
        story = space.buildingStory

        unless story.empty?
          story = story.get

          if story.additionalProperties.hasFeature(tag)
            prp = story.additionalProperties.getFeatureAsString(tag)

            if prp.empty?
              lgs << "Unknown story AddtionalProperty '#{tag}' (#{mth})"
              prp = nil
            else
              prp = prp.get.downcase.to_sym
            end
          end
        end
      end

      # Validate, based on STRUCTURE rules - attempt to fix if invalid.
      if prp
        case tag
        when "btap_structure"
          if data[:structure].key?(prp)
            prp = :steel    if prp == :metal # temporary - @todo
            prp = :concrete if prp == :clt   # temporary - @todo
          else
            prp = @structure
            space.additionalProperties.setFeature(tag, prp.to_s)
          end
        when "btap_framing"
          structure = property(space, "btap_structure")
          structure = @structure unless structure

          if data[:structure].key?(structure)
            unless data[:structure][structure][:frames].include?(prp)
              prp = data[:structure][structure][:framing]
              space.additionalProperties.setFeature(tag, prp.to_s)
            end
          else
            prp = data[:structure][@structure][:framing]
            bldg.additionalProperties.setFeature(tag, prp.to_s)
          end
        when "btap_cladding"
          unless data[:cladding].include?(prp)
            prp = @cladding
            space.additionalProperties.setFeature(tag, prp.to_s)
          end
        when "btap_finish"
          unless data[:finish].include?(prp)
            prp = @finish
            space.additionalProperties.setFeature(tag, prp.to_s)
          end
        else
          lgs << "Unknown AddtionalProperty '#{tag}' (#{mth})"
          prp = nil
        end
      end

      prp
    end
  end
end
