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

require "csv"

module BTAP
  module ActivityData
    ##
    # @author: Denis Bourgeois
    #
    # BTAP module/class for general purpose 'activities' and building
    # 'categories' - more abstract than NECB-specific building/space types.
    #
    # Consider the following: the NECB2011 designates as "Parking garage"
    # (building type) what subsequent NECB editions refer to as "Storage garage".
    # From the NECB2020 definitions:
    #
    #   'Storage garage' means a building or part thereof intended for the
    #   storage or parking of motor vehicles and containing no provision for
    #   the repair or servicing of such vehicles.
    #
    # This mismatch, and other related issues of a similar nature, make it
    # challenging to cross-compare NECB editions, for instance. The 'exact' NECB
    # labels shouldn't matter - they almost always reference the same
    # building 'activity' (e.g. a facility where vehicles are parked/stored).
    # BTAP should instead rely on abstract 'activity' designations, e.g.
    # 'parking'. This requires module/class methods to extract specific keywords
    # embedded in existing BTAP NECB building/space type datasets - see below.
    #
    # Once 'activity' assignments are completed (for spaces and building),
    # building 'categories' are auto-assigned (e.g. "housing" vs "industry").
    # For instance, multi-unit residential buildings (MURBs), university/school
    # dormitories and long-term care facilities are all grouped under "housing",
    # which in turn sets building-wide 'structural' options, e.g. wood-framed
    # (small-scale) vs reinforced concrete flat slab & post-beam (mid- & large-
    # scale) "housing". See lib/openstudio-standards/btap/structure.rb.
    @@data = {bldg: {}, space: {}, ancillaries: []}

    # Hard setting path for both files (temporary @todo).
    @@data[:bldg ][:file      ] = File.join(__dir__, "btap_building_types.csv")
    @@data[:space][:file      ] = File.join(__dir__, "btap_space_types.csv")
    @@data[:bldg ][:table     ] = nil
    @@data[:space][:table     ] = nil
    @@data[:bldg ][:activity  ] = {}
    @@data[:space][:activity  ] = {}
    @@data[:bldg ][:activities] = []
    @@data[:bldg ][:categories] = []

    # Key notes, common to NECB editions.
    #
    #   Note to NECB Table 8.4.4.7.-A: (2) Small individual spaces in the
    #   proposed building that are located among larger spaces of another space
    #   type shall be considered ANCILLARY to that larger space: for example, a
    #   conference room serving office spaces would be grouped with the office
    #   spaces as one space type.
    #
    #   A-8.4.3.2.(1): Tables [...] contain default values of operating
    #   schedules of building parameters for simulation purposes. These
    #   schedules MAY be used with Table A-8.4.3.2.(2)-B IF more accurate
    #   information IS NOT AVAILABLE.
    #
    #   A-8.4.3.2.(2): Tables [...] contain representative internal and service
    #   water heating loads, operating schedules, and illuminance levels to be
    #   used as modeling GUIDANCE when actual values are not known.
    #
    #   Note to Table A-8.4.3.3.(2)B. (1): An asterisk (*) in this column
    #   indicates that there is no recommended default schedule for the space
    #   type listed. In general, such space types will be simulated using a
    #   schedule that is similar to the ADJACENT spaces served: e.g. a corridor
    #   space serving an adjacent office space will be simulated using a
    #   schedule that is similar to that of the office space.
    #
    # This last note refers to the following NECB 'ancillary' spacetypes:
    #
    #                                                     2011  2015  2017  2020
    @@data[:ancillaries] <<     "atrium::common"        #   C     *     *     *
    @@data[:ancillaries] <<   "audience::common"        #         *     *     *
    @@data[:ancillaries] <<   "computer::common"        #         *     *     *
    @@data[:ancillaries] <<   "corridor::common"        #   *     *     *     *
    @@data[:ancillaries] <<   "corridor::hospital"      #   *     *     *     *
    @@data[:ancillaries] <<   "corridor::manufacturing" #   *     *     *     *
    @@data[:ancillaries] << "mechanical::common"        #   *     *     *     *
    @@data[:ancillaries] <<     "locker::common"        #   *     *     *     *
    @@data[:ancillaries] <<    "seating::common"        #         *     *     *
    @@data[:ancillaries] <<   "stairway::common"        #   *     *     *     *
    @@data[:ancillaries] <<    "storage::common"        #   *     *     *     *
    @@data[:ancillaries] <<   "washroom::common"        #   *     *     *     *

    # NECB2011 recommends schedule set "C" for atria, while all other NECB
    # editions point to Note (1) of Table A-8.4.3.3.(2)B (on schedule set
    # inheritance). To facilitate cross-comparisons between NECB editions, the
    # NECB 2011 atrium schedule set will harmonize with other NECB editions.
    #
    # With respect to other NECB editions, NECB2011 also has a few missing
    # entries: There is neither GENERAL 'seating' (e.g. a waiting area) nor
    # GENERAL 'audience seating' types: 'seating' is either building-SPECIFIC
    # (e.g. transportation facility) or SPECIFIC 'audience seating' (e.g.
    # theatre, convention centre). And there is no entry for computer or server
    # rooms. Within the scope of BTAP::Activity, missing space types inherit
    # fallbacks (e.g. audience seating, office).

    # Parse building type data on file.
    if File.exist?(@@data[:bldg][:file])
      table = CSV.open(@@data[:bldg][:file], headers: true).read

      # 35 unique entries (rows), 10 columns per row, e.g.:
      #    C01  C02 C03  C04 C05 C06      C07   C08               C09        C10
      #   ____ ___ ____ ____ ___ ___ ________ _____ _______________ ____________
      #   care, 25, 1.5, 500,  j, 13, housing, care, health/clinic/, residential
      #
      #   C01: BTAP building ACTIVITY e.g. "care"
      #   C02: occupant density       e.g. 25.0 m2/occupant
      #   C03: peak equipment load    e.g. 1.5 W/m2
      #   C04: peak SWH load          e.g. 500.0 W/occupant
      #   C05: schedule set           e.g. "j"
      #   C06: non-occupant liveload  e.g. 13 kg/m2, ~1/12 of NBC min liveload
      #   C07: BTAP building CATEGORY e.g. "housing"
      #   C08: selected sub-string(s) e.g. "care", as in "Long-term care"
      #   C09: rejected sub-string(s) e.g. "health", "multi", "residential"
      #   C10: fallback (if missing)  e.g. "residential"
      #
      # Contrary to the aforementioned 'parking' case (where fortunately there
      # is an obvious one-to-one match between "Parking garage" (NECB2011) and
      # "Storage garage" (NECB2020)), there is no direct match here for a
      # long-term care facility when using the NECB2011. In this case, the
      # fallback 'activity' is 'residential' (COL10). So in any cross-comparison
      # of long-term care facilities between NECB editions, the NECB2011 variant
      # would be akin to a MURB.
      #
      # A "long-term care" facility (e.g. NECB2020 building type, currently
      # found in BTAP datasets) would be identified as belonging to activity
      # 'care' by catching the substring "care" (COL4) in any of the
      # NECB building types (e.g. JSON, CSV, XLSX files). Yet the same substring
      # "care" is found in both NECB building types:
      #
      #   - "Long-term care"
      #   - "Health-care clinic"
      #
      # ... rejected substrings (COL5) prune out unwanted picks. By selecting
      # COL4 substrings, then rejecting COL5 substrings, there should be a
      # single selected row. See NECB unit test test_necb_activities.rb.
      table.each do |row|
        key = row[0]

        @@data[:bldg][:activity][key]              = {}
        @@data[:bldg][:activity][key][:occdensity] = row[1].to_f
        @@data[:bldg][:activity][key][:eqpload   ] = row[2].to_f
        @@data[:bldg][:activity][key][:swhload   ] = row[3].to_f
        @@data[:bldg][:activity][key][:schedule  ] = row[4].to_s
        @@data[:bldg][:activity][key][:liveload  ] = row[5].to_f
        @@data[:bldg][:activity][key][:category  ] = row[6].to_s
        @@data[:bldg][:activity][key][:includes  ] = row[7].to_s.split("/")
        @@data[:bldg][:activity][key][:excludes  ] = row[8].to_s.split("/")
        @@data[:bldg][:activity][key][:fallback  ] = row[9].to_s
      end

      # Keep CSV table. Ensure building activities & categories uniqueness. Add
      # "common" building type, e.g. mixed use. Freeze.
      @@data[:bldg][:table     ] = table
      @@data[:bldg][:activities] = table.by_col[0].uniq
      @@data[:bldg][:categories] = table.by_col[1].uniq
      @@data[:bldg][:activities] << "common"
      @@data[:bldg][:activities].freeze
      @@data[:bldg][:categories].freeze
    else
      # raise?
    end

    # Parse space data on file.
    if File.exist?(@@data[:space][:file])
      table = CSV.open(@@data[:space][:file], headers: true).read

      # 108 unique rows, 8 columns per row, e.g.:
      #          C01 C02  C03  C04  C05 C06           C07                 C08
      #  ___________ ___ ____ ____ ____ ____ ____________ ___________________
      #  units::care, 25, 2.5, 500,  j, unit, residential, units::residential
      #
      #   C01: BTAP space ACTIVITY    e.g. "units::care"
      #   C02: occupant density       e.g. 25.0 m2/occupant
      #   C03: peak equipment load    e.g. 2.5 W/m2
      #   C04: peak SWH load          e.g. 500.0 W/occupant
      #   C05: schedule set           e.g. "j"
      #   C06: selected sub-string(s) e.g. "unit"
      #   C07: rejected sub-string(s) e.g. "residential"
      #   C08: fallback (if missing)  e.g. "units::residential"
      #
      # First, BTAP space 'activity' entries are namespaced, e.g.:
      #   - "units": 1-word descriptor on the nature of the space 'activity'
      #   - "care": references a building 'activity', see @@data[:bldg]
      #
      # There are 2 entries for BTAP space activity "units":
      #   - "units::residential"
      #   - "units::care"
      #
      # The entries designate either typical residential dwelling 'units' or
      # long-term care dwelling 'units'. Both are expected to offer individual
      # bathroom and cooking facilities. This differs from:
      #   - "quarters::dorm"
      #   - "quarters::firehouse"
      #
      # ... which typically offer shared sleeping/bathroom/cooking facilities.
      # Both "units" and "quarters" differ from:
      #  - "rooms::motel"
      #  - "rooms::hotel"
      #  - "rooms::common"
      #
      # ... which designate short-term, rental lodgings. All three activities
      # share many features (e.g. sleeping, showers), yet each remains specific
      # to an NECB space type entry (as required).
      table.each do |row|
        key = row[0]
        str = key.split("::")

        activity = str[0].to_s
        bldgtype = str[1].to_s

        @@data[:space][:activity][key]              = {}
        @@data[:space][:activity][key][:activity  ] = activity
        @@data[:space][:activity][key][:bldgtype  ] = bldgtype
        @@data[:space][:activity][key][:occdensity] = row[1].to_f
        @@data[:space][:activity][key][:eqpload   ] = row[2].to_f
        @@data[:space][:activity][key][:swhload   ] = row[3].to_f
        @@data[:space][:activity][key][:schedule  ] = row[4].to_s
        @@data[:space][:activity][key][:includes  ] = row[5].to_s.split("/")
        @@data[:space][:activity][key][:excludes  ] = row[6].to_s.split("/")
        @@data[:space][:activity][key][:fallback  ] = row[7].to_s
      end

      @@data[:space][:table] = table
    else
      # raise?
    end

    ##
    # Validates whether an activity is 'ancillary' to other(s).
    #
    # @param activity [:to_sym] a BTAP::Activity item, e.g. "corridor::common"
    #
    # @return [Boolean] whether activity is ancillary.
    def ancillary?(activity = "")
      return false unless activity.respond_to?(:to_sym)

      activity = activity.to_s.strip.downcase
      return false unless @@data[:space][:activity].include?(activity)
      return false unless @@data[:ancillaries].include?(activity)

      true
    end

    ##
    # Returns BTAP Activity data.
    #
    # @return [Hash] BTAP Activity data
    def data
      @@data
    end

    def self.extended(base)
      base.send(:include, self)
    end
  end

  class BTAP::Activity
    extend ActivityData

    # @return [String] assigned or inferred building ACTIVITY (e.g. "warehouse")
    attr_reader :activity

    # @return [Hash] collection of space ACTIVITIES (e.g. "bulk::warehouse")
    attr_reader :activities

    # @return [String] building type CATEGORY (e.g. "industry")
    attr_reader :category

    # @return [Float] expected non-occupant liveload (e.g. 90 kg/m2)
    attr_reader :liveload

    # @return [Hash] logged messages
    attr_reader :feedback


    ##
    # Initialize BTAP Activity parameters.
    #
    # @param model [OpenStudio::Model::Model] a model
    def initialize(model = nil)
      mth         = "BTAP::Activity::#{__callee__}"
      @feedback   = {logs: []}
      lgs         = @feedback[:logs]
      @activity   = ""
      @activities = {}
      @category   = ""

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid or empty OpenStudio model (#{mth})"
        return
      end

      # Tag spaces as un/conditioned with "space_conditioning_category". For
      # now, this is simply determined based on whether spaces are:
      #   - part of the total floor area (i.e. occupied)
      #   - have "attic" included in their identifiers (i.e. unconditioned)
      #
      # As per ASHRE 90.1, OpenStudio-Standards distinguishes between:
      #   - "nonresconditioned" vs
      #   - "resconditioned"
      #
      # Sticking to "nonresconditioned" - NECBs do not distinguish between "res"
      # vs "non-res" (for e.g. envelope), as opposed to ASHRAE 90.1.
      #
      # The solution could be further refined in future BTAP versions by e.g.:
      #   - relying on user-defined thermostats
      #   - expanded to cover semi-heated and refrigerated spaces
      tag = "space_conditioning_category"

      model.getSpaces.each do |space|
        next unless space.additionalProperties.getFeatureAsString(tag).empty?

        if space.partofTotalFloorArea
          space.additionalProperties.setFeature(tag, "nonresconditioned")
        else
          if space.nameString.downcase.include?("attic")
            space.additionalProperties.setFeature(tag, "unconditioned")
          else # treat all other cases as indirectly-conditioned e.g. plenums
            space.additionalProperties.setFeature(tag, "nonresconditioned")
          end
        end
      end

      # Determine activities of occupied spaces in the model, then building.
      @activities = self.getSpaceActivities(model)
      @activity   = self.getBuildingActivity(model)
      @liveload   = data[:bldg][:activity][@activity][:liveload]

      # Assign building category.
      unless @activity.empty?
        @category = data[:bldg][:activity][@activity][:category]
      end

      true
    end

    ##
    # Gather activities of occupied spaces in a model.
    #
    # @param model [OpenStudio::Model::Model] a model
    #
    # @return [Hash] a collection of space activities (see logs if empty)
    def getSpaceActivities(model = nil)
      mth = "BTAP::Activity::#{__callee__}"
      cl  = OpenStudio::Model::Model
      return mismatch("model", model, cl, mth, DBG, {}) unless model.is_a?(cl)

      activities = {}

      model.getSpaces.each do |space|
        next unless space.partofTotalFloorArea

        # Defaulted values (if missing or invalid entries).
        spacetype  = nil
        standards  = ""
        activity   = ""
        bldgtype   = ""
        fallbacks  = []
        candidates = []

        # Recover user-set space types?
        unless space.spaceType.empty?
          spacetype = space.spaceType.get
          stdstype  = spacetype.standardsSpaceType
          standards = stdstype.get.downcase unless stdstype.empty?
        end

        # Fetch matching BTAP data, if keywords included.
        data[:space][:activity].each do |k, v|
          v[:includes].each do |kword|
            candidates << k if standards.include?(kword)
          end
        end

        # Keep track of fallbacks, if applicable.
        candidates.each do |candidate|
          fallback = data[:space][:activity][candidate][:fallback]
          fallbacks << fallback unless fallback.empty?
        end

        # Reject if matching any excluded keyword.
        data[:space][:activity].each do |k, v|
          v[:excludes].each do |kword|
            candidates.delete(k) if standards.include?(kword)
          end
        end

        # Fallbacks?
        if candidates.empty?
          candidate = ""

          fallbacks.each do |fallback|
            break unless candidate.empty?

            candidate = fallback if data[:space][:activity].key?(fallback)
          end

          candidate = data[:space][:activity].keys.first if candidate.empty?

          # Halt if:
          #   - space is part of the total floor area
          #   - 'candidate' spacetype is undefined
          if space.partofTotalFloorArea && candidate == "undefined::common"
            id = space.nameString
            raise("Unrecognized spacetype #{stdstype} for #{id}. Revise.")
          end
        else
          candidate = candidates.first
        end

        entry              = {}
        entry[:m2        ] = space.floorArea
        entry[:spacetype ] = spacetype
        entry[:standards ] = standards
        entry[:keyword   ] = candidate
        entry[:activity  ] = data[:space][:activity][candidate][:activity]
        entry[:bldgtype  ] = data[:space][:activity][candidate][:bldgtype]
        entry[:occdensity] = data[:space][:activity][candidate][:occdensity]
        entry[:eqpload   ] = data[:space][:activity][candidate][:eqpload]
        entry[:swhload   ] = data[:space][:activity][candidate][:swhload]
        entry[:schedule  ] = data[:space][:activity][candidate][:schedule]

        activities[space] = entry
      end

      activities
    end

    ##
    # Determines general building activity, either set by user or inferred.
    #
    # @param model OpenStudio::Model::Model] a model
    #
    # @return [String] keyword describing a model's general activity
    def getBuildingActivity(model = nil)
      mth = "BTAP::Activity::#{__callee__}"
      cl  = OpenStudio::Model::Model
      return mismatch("model", model, cl, mth, DBG, "") unless model.is_a?(cl)

      # OPTION A: Extract building activity from user-set 'additionalProperty'.
      tag      = "btap_building_activity"
      bldg     = model.getBuilding
      activity = bldg.additionalProperties.getFeatureAsString(tag)

      if activity.empty?
        activity = ""
      else
        activity = activity.get.downcase
        return activity if data[:bldg][:activities].include?(activity)
      end

      # OPTION B: Extract building activity from user-set 'building type'.
      bldgtype = model.getBuilding.standardsBuildingType

      unless bldgtype.empty?
        bldgtype   = bldgtype.get.downcase
        candidates = []
        fallbacks  = []

        # Fetch matching BTAP data, if keywords included.
        data[:bldg][:activity].each do |k, v|
          v[:includes].each do |kword|
            candidates << k if bldgtype.include?(kword)
          end
        end

        # Keep track of fallbacks, if applicable.
        candidates.each do |candidate|
          fallback = data[:bldg][:activity][candidate][:fallback]
          fallbacks << fallback unless fallback.empty?
        end

        # Reject if matching excluded keywords.
        data[:bldg][:activity].each do |k, v|
          v[:excludes].each do |kword|
            candidates.delete(k) if bldgtype.include?(kword)
          end
        end

        # Fallbacks?
        if candidates.empty?
          fallbacks.each do |fallback|
            return fallback if data[:bldg][:activity].key?(fallback)
          end
        else
          return candidates.first
        end
      end

      # OPTION C: Infer building activity from distribution of spacetypes.
      bldgtypes = {}

      @activities.values.each do |v|
        next unless v.key?(:m2)
        next unless v.key?(:bldgtype)

        bldgtypes[v[:bldgtype]]  = 0 unless bldgtypes.include?(v[:bldgtype])
        bldgtypes[v[:bldgtype]] += v[:m2]
      end

      activity = bldgtypes.sort.reverse.to_h.keys.first unless bldgtypes.empty?
      # Many NECB space types are listed as "common". Examples include spaces
      # that are educational in nature (e.g. "classroom", "teachinglabs") and
      # typical office spaces (e.g. "openplan", "office"). This is odd, as NECBs
      # list "school/university" and "office" as admissible building types.
      # Inferring an overall building type/activity (e.g. "school"), based on
      # the prevalence of space types (e.g. "classrooms") in a model, becomes
      # unnecessarily challenging. A fallback solution is needed when
      # predominant space types end up as "common" for a given model.
      #
      # One odd exception is 'audience' seating for an "auditorium", which is
      # found in all NECB editions. All listed 'audience' seating space types
      # are linked to a listed building type, e.g.:
      #   - "religious building"
      #   - "sports arena"
      #   - "motion picture theatre"
      #
      # ... except for "auditorium". No NECB edition holds an "auditorium"
      # building type entry. For the moment, "auditorium" will be associated
      # with the ubiquitous high-school or college auditorium.
      if activity == "common"
        activities = {}

        @activities.values.each do |v|
          next unless v.key?(:m2)
          next unless v.key?(:activity)

          activities[v[:activity]]  = 0 unless activities.key?(v[:activity])
          activities[v[:activity]] += v[:m2]
        end

        activity = case activities.sort.reverse.to_h.keys.first
                   when "audience"    then "school"
                   when "sales"       then "retail"
                   when "dining"      then "restaurant"
                   when "cuisine"     then "restaurant"
                   when "rooms"       then "hotel"
                   when "recreation"  then "exercise"
                   when "cell"        then "penitentiary"
                   when "classroom"   then "school"
                   when "teachinglab" then "school"
                   when "storage"     then "warehouse"
                   when "laundry"     then "retail"
                   when "lounge"      then "leisure"
                   when "pharmacy"    then "retail"
                   else                    "office"
                   end
      end

      activity = "office" if activity.empty?

      activity
    end
  end
end
