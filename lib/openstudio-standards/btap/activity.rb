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

require "csv"
require "json"

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
    # Such mismatches make it challenging to cross-compare NECB editions. The
    # 'exact' NECB building (or space) type strings shouldn't matter - they
    # almost always reference the same real-life building 'activity' (e.g. a
    # facility where vehicles are parked/stored). Behind the scenes, BTAP should
    # only rely on abstract 'activity' designations, e.g. 'parking'. This
    # requires functionality to extract key sub-strings in user-assigned
    # building or space type designations.
    #
    # Once 'activity' assignments are completed (for spaces and building),
    # building 'categories' are auto-assigned (e.g. "housing" vs "industry").
    # For instance, multi-unit residential buildings (MURBs), university/school
    # dormitories and long-term care facilities are all grouped under "housing",
    # which in turn sets building-wide 'structural' options, e.g.
    #
    #   - wood-framed (small-scale "housing")
    #   - reinforced concrete flat slab & post-beam (mid/large-scale "housing")
    #
    # See lib/openstudio-standards/btap/structure.rb.

    # Activity data Hash.
    @@data           = {}
    @@data[:bldg   ] = {} # common BTAP building type/activity data
    @@data[:space  ] = {} # common BTAP space type/activity data
    @@data[:udef   ] = {} # common BTAP undefined/constant data
    @@data[:edition] = {} # similar entries, specific to each NECB edition

    # Quick access tables to:
    #   - 'ancillary' space types/activities
    #   - 'auxiliary' space types/activities
    #   - building activities
    #   - building categories
    @@data[:ancillaries] = []
    @@data[:auxiliaries] = []
    @@data[:activities ] = []
    @@data[:categories ] = []

    # Load common BTAP 'space_types' and 'udef' JSON file content.
    t_path = File.join(__dir__, "space_types.json")
    u_path = File.join(__dir__, "udef.json")

    t_json = JSON.parse(File.read(t_path), symbolize_names: true)
    u_json = JSON.parse(File.read(u_path), symbolize_names: true)

    # The 'bldg' Hash holds (as keys) BTAP/NECB building types/activities, e.g.:
    #   - "fastfood"
    #   - "clinic"
    #
    # Its values are unique parameters (regardless of NECB edition), e.g.:
    #   - liveload:           23.0
    #   - category:           "commerce"
    #   - necb_schedule_type: "B"
    t_json[:tables][:space_types][:table].each do |tbl|
      next unless tbl.key?(:building_type)

      type = tbl[:building_type]
      next if @@data[:bldg].key?(type)

      @@data[:bldg][type] = {}

      tbl.each do |k, v|
        @@data[:bldg][type][k] = v unless k == :building_type

        if k == :category
          unless @@data[:categories].include?(v)
            @@data[:categories] << v
          end
        end
      end

      unless @@data[:activities].include?(type)
        @@data[:activities] << type
      end
    end

    # The 'space' Hash holds (as keys) BTAP/NECB space types/activities, e.g.:
    #   - "audience::cineplex"
    #   - "meeting::common"
    #
    # Its values are similar to @@data[:bldg] entries (regardless of NECB
    # edition), except :liveload and :category, e.g.:
    #   - necb_schedule_type: "C"
    t_json[:tables][:space_types][:table].each do |tbl|
      next unless tbl.key?(:space_type)

      type = tbl[:space_type]
      next if @@data[:space].key?(type)

      @@data[:space][type] = {}

      tbl.each do |k, v|
        @@data[:space][type][k] = v unless k == :space_type

        if k == :necb_schedule_type
          if v == "*"
            @@data[:ancillaries] << type
          elsif v.include?("*")
            @@data[:auxiliaries] << type
          end
        end
      end
    end

    @@data[:activities ] << "common"
    @@data[:activities ].freeze # 35
    @@data[:categories ].freeze #  7
    @@data[:ancillaries].freeze # 12
    @@data[:auxiliaries].freeze # 39

    # puts @@data[:bldg].keys.size   #  34
    # puts @@data[:space].keys.size  # 107
    # puts @@data[:activities].size  #  35
    # puts @@data[:categories].size  #   7
    # puts @@data[:ancillaries].size #  12
    # puts @@data[:auxiliaries].size #  38

    # The common BTAP 'udef' table (Hash) holds:
    #   - all BTAP/NECB building/space type/activity data keys, e.g.:
    #       - :lighting_per_area
    #       - :lighting_fraction_radiant
    #       - :target_illuminance_setpoint
    #       - :infiltration_per_exterior_area
    #   - default values applicable to all "undefined::common" spaces, e.g.:
    #       - lighting_per_area: 0.0
    #       - target_illuminance_setpoint: null
    #   - constants applicable to all building/space types/activities, e.g.:
    #       - lighting_fraction_radiant: 0.5
    #       - infiltration_per_exterior_area: 0.049225
    u_json[:tables][:space_types][:table].first.each do |k, v|
      @@data[:udef][k] = v
    end

    # BTAP-supported NECB editions (and older vintages).
    editions = []
    editions << "BTAPPRE1980"
    editions << "BTAP1980TO2010"
    editions << "NECB2011"
    editions << "NECB2015"
    editions << "NECB2017"
    editions << "NECB2020"

    # Load 'space_types' and 'udef' JSON content for each NECB edition.
    editions.each do |ed|
      @@data[:edition][ed] = { bldg: {}, space: {}, udef: {} }

      t_str = "../standards/necb/" + ed + "/data/space_types.json"
      u_str = "../standards/necb/" + ed + "/data/udef.json"

      t_path = File.join(__dir__, t_str)
      u_path = File.join(__dir__, u_str)

      t_json = JSON.parse(File.read(t_path), symbolize_names: true)
      u_json = JSON.parse(File.read(u_path), symbolize_names: true)

      # Edition-specific building type entries.
      t_json[:tables][:space_types][:table].each do |tbl|
        next unless tbl.key?(:building_type)

        type = tbl[:building_type]
        next if @@data[:edition][ed][:bldg].key?(type)

        @@data[:edition][ed][:bldg][type] = {}

        tbl.each do |k, v|
          @@data[:edition][ed][:bldg][type][k] = v unless k == :building_type
        end
      end

      # Edition-specific space type entries.
      t_json[:tables][:space_types][:table].each do |tbl|
        next unless tbl.key?(:space_type)

        type = tbl[:space_type]
        next if @@data[:edition][ed][:space].key?(type)

        @@data[:edition][ed][:space][type] = {}

        tbl.each do |k, v|
          @@data[:edition][ed][:space][type][k] = v unless k == :space_type
        end
      end

      # Edition-specific 'udef' entries.
      u_json[:tables][:space_types][:table].first.each do |k, v|
        @@data[:edition][ed][:udef][k] = v
      end

      # puts "#{ed}: #{@@data[:edition][ed][:bldg].size} vs #{@@data[:edition][ed][:space].size}"
      # BTAPPRE1980:    33 vs 93 ... 1x "motel", 0x "care"
      # BTAP1980TO2010: 33 vs 93 ... 1x "motel", 0x "care"
      # NECB2011:       33 vs 93 ... 1x "motel", 0x "care"
      # NECB2015:       33 vs 93 ... 0x "motel", 1x "care"
      # NECB2017:       33 vs 93 ... 0x "motel", 1x "care"
      # NECB2020:       33 vs 93 ... 0x "motel", 1x "care"
    end

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
    #                               2011  2015  2017  2020
    #       "atrium::common"          C     *     *     *
    #     "audience::common"                *     *     *
    #     "computer::common"                *     *     *
    #     "corridor::common"          *     *     *     *
    #     "corridor::health"          *     *     *     *
    #     "corridor::manufacturing"   *     *     *     *
    #   "mechanical::common"          *     *     *     *
    #       "locker::common"          *     *     *     *
    #      "seating::common"                *     *     *
    #     "stairway::common"          *     *     *     *
    #      "storage::common"          *     *     *     *
    #     "washroom::common"          *     *     *     *

    # Note that NECB2011 recommends schedule set "C" for atria, while all other
    # NECB editions point to Note (1) of Table A-8.4.3.3.(2)B (on schedule set
    # inheritance). To facilitate cross-comparisons between NECB editions, the
    # NECB 2011 atrium schedule set will harmonize with other NECB editions.
    #
    # Compared to other NECB editions, NECB2011 also has a few missing entries:
    # There is neither GENERAL 'seating' (e.g. a waiting area) nor GENERAL
    # 'audience seating' types: 'seating' is either building-SPECIFIC (e.g.
    # transportation facility) or SPECIFIC 'audience seating' (e.g. theatre,
    # convention centre). Similarly, there is no entry for computer or server
    # rooms. Within the scope of BTAP::Activity, missing space types inherit
    # fallbacks (e.g. audience seating, office).

    # Parse building type data on file.
    # if File.exist?(@@data[:bldg][:file])
    #   table = CSV.open(@@data[:bldg][:file], headers: true).read
    #
    #   # 35 unique entries (rows), 10 columns per row, e.g.:
    #   #    C01  C02 C03  C04 C05 C06      C07   C08               C09        C10
    #   #   ____ ___ ____ ____ ___ ___ ________ _____ _______________ ____________
    #   #   care, 25, 1.5, 500,  j, 13, housing, care, health/clinic/, residential
    #   #
    #   #   C01: BTAP building ACTIVITY e.g. "care"
    #   #   C02: occupant density       e.g. 25.0 m2/occupant
    #   #   C03: peak equipment load    e.g. 1.5 W/m2
    #   #   C04: peak SWH load          e.g. 500.0 W/occupant
    #   #   C05: schedule set           e.g. "j"
    #   #   C06: non-occupant liveload  e.g. 13 kg/m2, ~1/12 of NBC min liveload
    #   #   C07: BTAP building CATEGORY e.g. "housing"
    #   #   C08: selected sub-string(s) e.g. "care", as in "Long-term care"
    #   #   C09: rejected sub-string(s) e.g. "health", "multi", "residential"
    #   #   C10: fallback (if missing)  e.g. "residential"
    #   #
    #   # Contrary to the aforementioned 'parking' case (where fortunately there
    #   # is an obvious one-to-one match between "Parking garage" (NECB2011) and
    #   # "Storage garage" (NECB2020)), there is no direct match here for a
    #   # long-term care facility when using the NECB2011. In this case, the
    #   # fallback 'activity' is 'residential' (COL10). So in any cross-comparison
    #   # of long-term care facilities between NECB editions, the NECB2011 variant
    #   # would be akin to a MURB.
    #   #
    #   # A "long-term care" facility (e.g. NECB2020 building type, currently
    #   # found in BTAP datasets) would be identified as belonging to activity
    #   # 'care' by catching the substring "care" (COL4) in any of the
    #   # NECB building types (e.g. JSON, CSV, XLSX files). Yet the same substring
    #   # "care" is found in both NECB building types:
    #   #
    #   #   - "Long-term care"
    #   #   - "Health-care clinic"
    #   #
    #   # ... rejected substrings (COL5) prune out unwanted picks. By selecting
    #   # COL4 substrings, then rejecting COL5 substrings, there should be a
    #   # single selected row. See NECB unit test test_necb_activities.rb.
    #   table.each do |row|
    #     key = row[0].to_s
    #
    #     @@data[:bldg][:activity][key]            = {}
    #     @@data[:bldg][:activity][key][:density ] = row[1].to_f
    #     @@data[:bldg][:activity][key][:eqpload ] = row[2].to_f
    #     @@data[:bldg][:activity][key][:swhload ] = row[3].to_f
    #     @@data[:bldg][:activity][key][:schedule] = row[4].to_s
    #     @@data[:bldg][:activity][key][:liveload] = row[5].to_f
    #     @@data[:bldg][:activity][key][:category] = row[6].to_s
    #     @@data[:bldg][:activity][key][:includes] = row[7].to_s.split("/")
    #     @@data[:bldg][:activity][key][:excludes] = row[8].to_s.split("/")
    #     @@data[:bldg][:activity][key][:fallback] = row[9].to_s
    #   end
    #
    #   # Keep CSV table. Ensure building activities & categories uniqueness. Add
    #   # "common" building type, e.g. mixed use. Freeze.
    #   @@data[:bldg][:table     ] = table
    #   @@data[:bldg][:activities] = table.by_col[0].uniq
    #   @@data[:bldg][:categories] = table.by_col[6].uniq
    #   @@data[:bldg][:activities] << "common"
    #   @@data[:bldg][:activities].freeze
    #   @@data[:bldg][:categories].freeze
    # else
    #   # raise?
    # end

    # Parse space data on file.
    # if File.exist?(@@data[:space][:file])
    #   table = CSV.open(@@data[:space][:file], headers: true).read
    #
    #   # 108 unique rows, 8 columns per row, e.g.:
    #   #          C01 C02  C03  C04  C05 C06           C07                 C08
    #   #  ___________ ___ ____ ____ ____ ____ ____________ ___________________
    #   #  units::care, 25, 2.5, 500,  j, unit, residential, units::residential
    #   #
    #   #   C01: BTAP space ACTIVITY    e.g. "units::care"
    #   #   C02: occupant density       e.g. 25.0 m2/occupant
    #   #   C03: peak equipment load    e.g. 2.5 W/m2
    #   #   C04: peak SWH load          e.g. 500.0 W/occupant
    #   #   C05: schedule set           e.g. "j"
    #   #   C06: selected sub-string(s) e.g. "unit"
    #   #   C07: rejected sub-string(s) e.g. "residential"
    #   #   C08: fallback (if missing)  e.g. "units::residential"
    #   #
    #   # First, BTAP space 'activity' entries are namespaced, e.g.:
    #   #   - "units": 1-word descriptor on the nature of the space 'activity'
    #   #   - "care": references a building 'activity', see @@data[:bldg]
    #   #
    #   # There are 2 entries for BTAP space activity "units":
    #   #   - "units::residential"
    #   #   - "units::care"
    #   #
    #   # The entries designate either typical residential dwelling 'units' or
    #   # long-term care dwelling 'units'. Both are expected to offer individual
    #   # bathroom and cooking facilities. This differs from:
    #   #   - "quarters::dorm"
    #   #   - "quarters::firehouse"
    #   #
    #   # ... which typically offer shared sleeping/bathroom/cooking facilities.
    #   # Both "units" and "quarters" differ from:
    #   #  - "rooms::motel"
    #   #  - "rooms::hotel"
    #   #  - "rooms::common"
    #   #
    #   # ... which designate short-term, rental lodgings. All three activities
    #   # share many features (e.g. sleeping, showers), yet each remains specific
    #   # to an NECB space type entry (as required).
    #   table.each do |row|
    #     key = row[0].to_s
    #     str = key.split("::")
    #
    #     activity = str[0].to_s
    #     bldgtype = str[1].to_s
    #     schedule = row[4].to_s
    #
    #     @@data[:space][:activity][key]            = {}
    #     @@data[:space][:activity][key][:activity] = activity
    #     @@data[:space][:activity][key][:bldgtype] = bldgtype
    #     @@data[:space][:activity][key][:density ] = row[1].to_f
    #     @@data[:space][:activity][key][:eqpload ] = row[2].to_f
    #     @@data[:space][:activity][key][:swhload ] = row[3].to_f
    #     @@data[:space][:activity][key][:schedule] = schedule
    #     @@data[:space][:activity][key][:includes] = row[5].to_s.split("/")
    #     @@data[:space][:activity][key][:excludes] = row[6].to_s.split("/")
    #     @@data[:space][:activity][key][:fallback] = row[7].to_s
    #
    #     if schedule == "*"
    #       @@data[:ancillaries] << key
    #     elsif schedule.include?("*")
    #       @@data[:auxiliaries] << key
    #     end
    #   end
    #
    #   @@data[:space][:table] = table
    # else
    #   # raise?
    # end

    # @@data[:types][:table].each do |tbl|
    #   next unless tbl.key?(:building_type)
    #
    #   raise "#{tbl[:building_type]} category?"          unless tbl.key?(:category)
    #   raise "#{tbl[:building_type]} liveload?"          unless tbl.key?(:liveload)
    #   raise "#{tbl[:building_type]} missing?"           unless @@data[:bldg][:activity].include?(tbl[:building_type].to_s)
    #   raise "#{tbl[:building_type]} #{tbl[:category]}?" unless @@data[:bldg][:categories].include?(tbl[:category])
    #   raise "#{tbl[:building_type]} #{tbl[:liveload]}?" unless @@data[:bldg][:activity][tbl[:building_type]][:liveload].round == tbl[:liveload].round
    # end


    ##
    # Validates whether an activity is 'ancillary' to other(s). See relevant
    # comments above, and note to Table A-8.4.3.3.(2)B. (1).
    #
    # @param activity [:to_sym] a BTAP::Activity keyword, e.g. "locker::common"
    #
    # @return [Boolean] whether activity is ancillary.
    def ancillary?(activity = "")
      return false unless activity.respond_to?(:to_sym)

      activity = activity.to_s.strip.downcase
      return true if @@data[:ancillaries].include?(activity)

      false
    end

    ##
    # Validates whether an activity is 'auxiliary' to the building activity.
    # 'Auxiliary' spaces differ from NECB 'ancillary' spaces. If requested by
    # the user (in the .osm file), the former may adopt the dominant building
    # activity schedule set, instead of the NECB suggested one. Examples include
    # a school's gymnasium, cafeteria or auditorium.
    #
    # @param activity [:to_sym] a BTAP::Activity keyword, e.g. "court::gym"
    #
    # @return [Boolean] whether activity is auxiliary.
    def auxiliary?(activity = "")
      return false unless activity.respond_to?(:to_sym)

      activity = activity.to_s.strip.downcase
      return true if @@data[:auxiliaries].include?(activity)

      false
    end

    ##
    # Validates whether an activity is considered 'wet', e.g. locker room.
    #
    # @param activity [:to_sym] a BTAP::Activity keyword, e.g. "locker::common"
    #
    # @return [Boolean] whether activity is 'wet'.
    def wet?(activity = "")
      return false unless activity.respond_to?(:to_sym)

      activity = activity.to_s.strip.downcase
      return true if activity.include?("locker")
      return true if activity.include?("washroom")

      false
    end

    ##
    # Validates whether a space is targeted by ANSI/IES Recommended Practice RP28
    # 2007 - see store.accuristech.com/standards/ies-rp-28-07?product_id=1555565.
    #
    # @param space [OpenStudio::Model::Space] an OpenStudio space
    #
    # @return [Boolean] true if RP28'ed
    def rp28?(space = nil)
      return false unless space.is_a?(OpenStudio::Model::Space)

      # First check AdditionalProperty.
      tag  = "rp28"
      rp28 = space.additionalProperties.getFeatureAsBoolean(tag)
      return rp28.get unless rp28.empty?

      # Check spacetype strings.
      variants = ["rp28", "rp-28", "rp_28", "rp 28"]

      unless space.spaceType.empty?
        type = space.spaceType.get
        tID  = type.nameString.downcase

        if variants.any? { |variant| tID.include?(variant) }
          return space.additionalProperties.setFeature(tag, true)
        end

        unless type.standardsSpaceType.empty?
          stype = type.standardsSpaceType.get.downcase

          if variants.any? { |variant| stype.include?(variant) }
            return space.additionalProperties.setFeature(tag, true)
          end
        end
      end

      # Check space identifier.
      sID = space.nameString.downcase

      if variants.any? { |variant| sID.include?(variant) }
        return space.additionalProperties.setFeature(tag, true)
      end

      space.additionalProperties.setFeature(tag, false)

      false
    end

    ##
    # Validates whether a space is targeted for occupancy-sensing lighting
    # control, per NECB2011.
    #
    # @param space [OpenStudio::Model::Space] an OpenStudio space
    #
    # @return [Boolean] true if occsensing
    def occsensing_deprecated?(space = nil)
      return false unless space.is_a?(OpenStudio::Model::Space)

      # First check AdditionalProperty.
      tag  = "occsensing"
      osns = space.additionalProperties.getFeatureAsBoolean(tag)
      return osns.get unless osns.empty?

      # Check spacetype strings.
      variants = ["occ sens", "occ-sens", "occsens"]

      unless space.spaceType.empty?
        type = space.spaceType.get
        tID  = type.nameString.downcase

        if variants.any? { |variant| tID.include?(variant) }
          space.additionalProperties.setFeature(tag, true)
          return true
        end

        unless type.standardsSpaceType.empty?
          stype = type.standardsSpaceType.get.downcase

          if variants.any? { |variant| stype.include?(variant) }
            space.additionalProperties.setFeature(tag, true)
            return true
          end
        end
      end

      # Check space identifier.
      sID = space.nameString.downcase

      if variants.any? { |variant| sID.include?(variant) }
        space.additionalProperties.setFeature(tag, true)
        return true
      end

      space.additionalProperties.setFeature(tag, false)

      false
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

    # @return [String] assigned or inferred building ACTIVITY, e.g. "warehouse"
    attr_reader :activity

    # @return [Hash] collection of space ACTIVITIES, e.g. "bulk::warehouse"
    attr_reader :activities

    # @return [String] building type CATEGORY, e.g. "industry"
    attr_reader :category

    # @return [Float] expected non-occupant liveload, e.g. 90 kg/m2
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
      @activities = self.spaceActivities(model)
      @activity   = self.buildingActivity(model)
      @liveload   = data[:bldg][:activity][@activity][:liveload]

      # Assign building category.
      unless @activity.empty?
        @category = data[:bldg][:activity][@activity][:category]
      end

      # Assign schedules to auxiliary spaces - if present.
      self.assignAuxiliarySchedules(self.buildingActivity?(model))

      # Assign schedules to ancillary spaces - if present.
      self.assignAncillarySchedules

      true
    end

    ##
    # Gather activities of occupied spaces in a model.
    #
    # @param model [OpenStudio::Model::Model] a model
    #
    # @return [Hash] a collection of space activities (see logs if empty)
    def spaceActivities(model = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid or empty OpenStudio model (#{mth})"
        return {}
      end

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
        else
          candidate = candidates.first
        end

        entry             = {}
        entry[:m2       ] = space.floorArea * space.multiplier
        entry[:spacetype] = spacetype
        entry[:standards] = standards
        entry[:keyword  ] = candidate
        entry[:activity ] = data[:space][:activity][candidate][:activity]
        entry[:bldgtype ] = data[:space][:activity][candidate][:bldgtype]
        entry[:density  ] = data[:space][:activity][candidate][:density]
        entry[:eqpload  ] = data[:space][:activity][candidate][:eqpload]
        entry[:swhload  ] = data[:space][:activity][candidate][:swhload]
        entry[:schedule ] = data[:space][:activity][candidate][:schedule]

        activities[space] = entry
      end

      activities
    end

    ##
    # Determines general building activity, either set by user or inferred.
    #
    # @param model OpenStudio::Model::Model] a model
    #
    # @return [String] a model's general activity (see logs if empty)
    def buildingActivity(model = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid or empty OpenStudio model (#{mth})"
        return "office"
      end

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
      # building type entry. For the moment, "auditorium" == "theatre".
      if activity == "common"
        activities = {}

        @activities.values.each do |v|
          next unless v.key?(:m2)
          next unless v.key?(:activity)

          activities[v[:activity]]  = 0 unless activities.key?(v[:activity])
          activities[v[:activity]] += v[:m2]
        end

        activity = case activities.sort.reverse.to_h.keys.first
                   when "audience"    then "theatre"
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

      # Log warning.
      if activity.empty?
        lgs << "Assigning building activity 'office' (#{mth})"
        activity = "office"
      end

      activity = "hospital" if activity == "health"

      activity
    end

    ##
    # Validates whether user has explicitly set a valid building activity
    # AdditionalProperty.
    #
    # @param model [OpenStudio::Model::Model] a model
    #
    # @return [Boolean] true if a valid building activity is set by user.
    def buildingActivity?(model = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid or empty OpenStudio model (#{mth})"
        return false
      end

      tag      = "btap_building_activity"
      bldg     = model.getBuilding
      activity = bldg.additionalProperties.getFeatureAsString(tag)
      return false if activity.empty?

      activity = activity.get.downcase
      return false unless data[:bldg][:activities].include?(activity)

      true
    end

    ##
    # Collects list of neighbouring (side-by-side), non-ancillary spaces.
    # Here, non-ancillary spaces include ancillary spaces that have valid
    # assigned schedule sets.
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Array] neighbouring (non-ancillary) spaces
    def neighbours(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return {}
      end

      nghbours = []

      space.surfaces.each do |s|
        next unless s.surfaceType.downcase == "wall"

        voisin = s.adjacentSurface
        next if voisin.empty?

        espace = voisin.get.space
        next if espace.empty?

        espace = espace.get
        next if espace == space
        next if nghbours.include?(espace)
        next if @activities[espace][:schedule] == "*"
        next unless @activities.key?(espace)

        nghbours << espace
      end

      nghbours
    end

    ##
    # Sets schedules to auxiliary spaces.
    #
    # @param uset [Boolean] whether user has explicitly set a building activity.
    #
    # @return [Boolean] true if successful
    def assignAuxiliarySchedules(uset = false)
      lgs  = @feedback[:logs]
      mth  = "BTAP::Activity::#{__callee__}"
      bkup = "a"
      uset = false unless [true, false].include?(uset)

      if @@data[:bldg][:activity].key?(@activity)
        bkup = @@data[:bldg][:activity][@activity][:schedule]
      end

      # Loop through auxiliary spaces (largest to smallest in floor area).
      @activities.sort_by { |space, v| v[:m2] }.reverse.each do |space, v|
        id  = space.nameString
        sch = self.schedule(space)
        next unless self.auxiliary?(v[:keyword])

        v[:schedule] = uset ? bkup : sch.delete("*")
      end

      true
    end

    ##
    # Sets schedules to ancillary spaces.
    #
    # @return [Boolean] true if successful
    def assignAncillarySchedules
      lgs  = @feedback[:logs]
      mth  = "BTAP::Activity::#{__callee__}"
      bkup = "a"

      if @@data[:bldg][:activity].key?(@activity)
        bkup = @@data[:bldg][:activity][@activity][:schedule]
      end

      # Loop through ancillary spaces (largest to smallest in floor area).
      @activities.sort_by { |space, v| v[:m2] }.reverse.each do |space, v|
        id = space.nameString
        next unless self.ancillary?(v[:keyword])

        # Retrieve each space's non-ancillary neighbours.
        schedules = {}
        schedule  = bkup

        self.neighbours(space).each do |nghbour|
          next unless @activities.key?(nghbour)

          sched = @activities[nghbour][:schedule]
          m2    = @activities[nghbour][:m2]

          schedules[sched]  = 0 unless schedules.key?(sched)
          schedules[sched] += m2
        end

        if schedules.empty?
          # Assign common building schedule if no non-ancillary adjacent spaces.
          lgs << "Assigning BUILDING schedule #{bkup} for #{id} (#{mth})"
          v[:schedule] = bkup
        else
          v[:schedule] = schedules.sort_by { |sched, m2| m2 }.reverse.first.first
        end

        # Forcing schedule set 'J' for ancillary spaces in:
        #   - short-term accomodation (e.g. hotels, firestation quarters)
        #   - housing (MURBs, dormitories)
        v[:schedule] = "j" if ["f", "g"].include?(v[:schedule])
      end

      true
    end

    ##
    # Returns a space's BTAP::Activity keyword, e.g. "corridor::hospital".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] a space's BTAP::Activity keyword - check logs if empty
    def keyword(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return ""
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return ""
      end

      @activities[space][:keyword]
    end

    ##
    # Returns a space's activity, e.g. "corridor" in "corridor::hospital".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] a space's activity - check logs if empty
    def act(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return ""
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return ""
      end

      @activities[space][:activity]
    end

    ##
    # Returns a space's building type, e.g. "hospital" in "corridor::hospital".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] a space's building type - check logs if empty
    def bldg(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return ""
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return ""
      end

      @activities[space][:bldgtype]
    end

    ##
    # Returns a space's floor area (m2), factoring a space's multiplier.
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's floor area - check logs if 0 m2
    def m2(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return 0.0
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return 0.0
      end

      @activities[space][:m2]
    end

    ##
    # Returns a space's occupant density (m2/occupant).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's occupant density - check logs if 0 m2/occupant
    def density(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return 0.0
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return 0.0
      end

      @activities[space][:density]
    end

    ##
    # Returns a space's peak receptacle load (W/m2).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's peak equipment load - check logs if 0 W/m2
    def eqpWm2(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return 0.0
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return 0.0
      end

      @activities[space][:eqpload]
    end

    ##
    # Returns a space's peak service water heating load (W/m2).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's peak SWH load - check logs if 0 W/m2
    def swhWm2(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return 0.0
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return 0.0
      end

      @activities[space][:swhload]
    end

    ##
    # Returns a space's (NECB-related) schedule set character, e.g. "a".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] schedule set. Check logs if empty string.
    def schedule(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return ""
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return ""
      end

      @activities[space][:schedule]
    end

    ##
    # Validates whether a space is targeted for occupancy-sensing lighting
    # control, per NECB2011.
    #
    # @param space [OpenStudio::Model::Space] an OpenStudio space
    #
    # @return [Boolean] true if occsensing
    def occsensing?(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return false
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return false
      end

      activity = @activities[space][:keyword]
      area = space.floorArea
      return true if activity == "classroom::common"
      return true if activity == "classroom::penitentiary"
      return true if activity == "meeting::common"
      return true if activity == "lounge::common"
      return true if activity == "lounge::health"
      return true if activity == "storage::common"  && area.round < 100
      return true if activity == "supplies::health" && area.round < 100
      return true if activity == "copiers::common"
      return true if activity == "office::common"   && area.round < 25
      return true if activity == "washroom::common"
      return true if activity == "dressing::theatre"
      return true if activity == "dressing::retail"
      return true if activity == "locker::common"

      false
    end

    ##
    # Returns a space's "factor for occupancy control" of lighting (Focc), per
    # NECB 4.3.2.10.1 (2015-2025).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's Focc of lighting - 1.0 if N/A.
    def fOCC(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return 1.0
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return 1.0
      end

      activity = @activities[space][:keyword]

      # Focc = 1 - Ca x Cocc, where:
      #   Ca   = factor to account for the relative absence of occupants
      #   Cocc = factor to account for the occupancy-sensing mechanism
      cA = case activity
           when "audience::convention"     then 0.2
           when "audience::religious"      then 0.3
           when "classroom::common"        then 0.5
           when "classroom::penitentiary"  then 0.5
           when "computer::common"         then 0.7
           when "server::common"           then 0.7
           when "meeting::common"          then 0.5
           when "copiers::common"          then 0.2
           when "tribunal::court"          then 0.2
           when "dressing::theatre"        then 0.4
           when "mechanical::common"       then 0.9
           when "emergency::common"        then 0.5
           when "teachinglab::common"      then 0.4
           when "locker::common"           then 0.5
           when "openplan::common"         then 0.2
           when "office::common"           then 0.3
           when "garage::parking"          then 0.4
           when "storage::common"          then 0.6
           when "washroom::common"         then 0.5
           when "supplies::health"         then 0.5
           when "exam::health"             then 0.3
           when "operating::health"        then 0.1
           when "patient::health"          then 0.1
           when "therapy::health"          then 0.2
           when "equipment::manufacturing" then 0.2
           when "restoration::museum"      then 0.3
           when "exhibit::museum"          then 0.2
           when "refectory::religious"     then 0.3
           when "pulpit::religious"        then 0.1
           when "dressing::retail"         then 0.4
           when "chapel::religious"        then 0.5
           when "recreation::common"       then 0.2
           when "bulk::warehouse"          then 0.5
           when "fine::warehouse"          then 0.5
           else                                 0.0
           end

      return 1.0 if cA.round(1) == 0.0

      # NECB 2025 Table 4.3.2.10.-B :                                    Cocc
      #   _____________________________________________________________  ____
      #   automatic FULL OFF (FULL ON)                                   0.67
      #   automatic FULL OFF (manual ON or automatic PARTIAL ON)         0.75
      #   automatic PARTIAL OFF (manual ON)                              0.34
      #   manual (ON/OFF or bi-level) – enclosed office less than 25 m2	 0.30
      #   manual – all other spaces	                                     0.10
      #   none	                                                         0.00
      #
      # The conditional application of lighting controls is often subject to
      # professional judgment (as described in the NECB). Automating their
      # assignment (e.g. Cocc within BTAP) becomes particularly challenging.
      #
      # The following are tentative postulates governing the automated
      # application of Cocc - needs a deeper dive, @todo:
      #
      #   - almost all spaces require manual ON
      #   - almost all spaces require automated or scheduled OFF (only)
      #   - so by default, spaces with Ca > 0 (see above): Cocc of 0.75
      #
      #   - spaces with automated PARTIAL OFF control have a Cocc of 0.34
      #
      #   - all other (unlisted) spaces: Cocc of 0.10.
      cOCC = case activity
             when "audience::convention"     then 0.75
             when "audience::religious"      then 0.75
             when "classroom::common"        then 0.75
             when "classroom::penitentiary"  then 0.75
             when "computer::common"         then 0.75
             when "server::common"           then 0.75
             when "meeting::common"          then 0.75
             when "copiers::common"          then 0.75
             when "tribunal::court"          then 0.75
             when "dressing::theatre"        then 0.75
             when "mechanical::common"       then 0.75
             when "emergency::common"        then 0.75
             when "teachinglab::common"      then 0.34 #
             when "locker::common"           then 0.75
             when "openplan::common"         then 0.75
             when "office::common"           then 0.75
             when "garage::parking"          then 0.34 #
             when "storage::common"          then 0.75
             when "washroom::common"         then 0.75
             when "supplies::health"         then 0.75
             when "exam::health"             then 0.75
             when "operating::health"        then 0.75
             when "patient::health"          then 0.75
             when "therapy::health"          then 0.75
             when "equipment::manufacturing" then 0.75
             when "restoration::museum"      then 0.75
             when "exhibit::museum"          then 0.75
             when "refectory::religious"     then 0.75
             when "pulpit::religious"        then 0.75
             when "dressing::retail"         then 0.75
             when "chapel::religious"        then 0.75
             when "recreation::common"       then 0.75
             when "bulk::warehouse"          then 0.34 #
             when "fine::warehouse"          then 0.34 #
             else                                 0.10
             end

      # Reset cOCC if small enclosed offices.
      cOCC = 0.30 if activity == "office::common" && space.floorArea < 25

      1.0 - cA * cOCC
    end

    ##
    # Returns a space's "factor for personal control" of lighting (Fpers),
    # per NECB 4.3.2.10.2 (2015-2025).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's Fpers of lighting - 1.0 if N/A.
    def fPERS(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return 1.0
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return 1.0
      end

      activity = @activities[space][:keyword]

      return 0.9 if activity == "teachinglab::common"
      return 0.9 if activity == "openplan::common"
      return 0.9 if activity == "office::common"
      return 0.9 if activity == "patient::health"

      1.0
    end

    ##
    # Validates whether a space can be considered as having 'transient'
    # occupancy, e.g. locker room, washroom, corridor.
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Boolean] whether space is 'transient' in nature.
    def transient?(space = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"

      unless space.is_a?(OpenStudio::Model::Space)
        lgs << "Invalid or empty OpenStudio space (#{mth})"
        return false
      end

      unless @activities.key?(space)
        lgs << "Unlisted space #{space.nameString} (#{mth})"
        return false
      end

      activity = @activities[space][:keyword]
      return true if activity.include?("atrium")
      return true if activity.include?("corridor")
      return true if activity.include?("mechanical")
      return true if activity.include?("lobby")
      return true if activity.include?("locker")
      return true if activity.include?("garage")
      return true if activity.include?("stairway")
      return true if activity.include?("storage")
      return true if activity.include?("washroom")
      return true if activity.include?("bulk")
      return true if activity.include?("fine")
      return true if activity.include?("computer")
      return true if activity.include?("server")
      return true if activity.include?("copiers")
      return true if activity.include?("emergency")

      false
    end
  end
end
