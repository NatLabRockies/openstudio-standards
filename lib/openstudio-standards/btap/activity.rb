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
    @@data[:edition] = {} # similar 3x entries, specific to each NECB edition

    # BTAP-supported NECB editions (and older vintages).
    @@data[:editions] = []
    @@data[:editions]editions << "BTAPPRE1980"
    @@data[:editions]editions << "BTAP1980TO2010"
    @@data[:editions]editions << "NECB2011"
    @@data[:editions]editions << "NECB2015"
    @@data[:editions]editions << "NECB2017"
    @@data[:editions]editions << "NECB2020"

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

    # Quick access lists of:
    #   - ancillary space types/activities
    #   - auxiliary space types/activities
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
    end

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
    # Validates whether a space is tagged as 'vented' (e.g. cusine::common).
    #
    # @param space [OpenStudio::Model::Space] an OpenStudio space
    #
    # @return [Boolean] true if vented
    def vented?(space = nil)
      return false unless space.is_a?(OpenStudio::Model::Space)

      # First check AdditionalProperty.
      tag  = "vented"
      rp28 = space.additionalProperties.getFeatureAsBoolean(tag)
      return vented.get unless vented.empty?

      # Check spacetype strings.
      unless space.spaceType.empty?
        type = space.spaceType.get
        tID  = type.nameString.downcase

        if tID.include?(tag)
          return space.additionalProperties.setFeature(tag, true)
        end

        unless type.standardsSpaceType.empty?
          stype = type.standardsSpaceType.get.downcase

          if stype.include?(tag)
            return space.additionalProperties.setFeature(tag, true)
          end
        end
      end

      # Check space identifier.
      sID = space.nameString.downcase

      if sID.include?(tag)
        return space.additionalProperties.setFeature(tag, true)
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

    # @return [String] user-assigned BTAP/NECB template, e.g. "NECB2011"
    attr_reader :template

    # @return [Hash] default UDEF JSON entries, specific to each template
    attr_reader :udef

    # @return [Hash] default building type JSON entries (template specific)
    attr_reader :bldg

    # @return [Hash] default space type JSON entries (template specific)
    attr_reader :space

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
    # @param template [String] a BTAP/NECB template (e.g. "NECB2011")
    def initialize(model = nil, template = "NECB2020")
      mth         = "BTAP::Activity::#{__callee__}"
      @feedback   = {logs: []}
      lgs         = @feedback[:logs]
      @activity   = ""
      @activities = {}
      @category   = ""
      @template   = ""
      @udef       = {}
      @bldg       = {}
      @space      = {}

      unless model.is_a?(OpenStudio::Model::Model)
        lgs << "Invalid or empty OpenStudio model (#{mth})"
        return
      end

      unless template.respond_to?(:to_sym)
        lgs << "Invalid template string (#{mth})"
        return
      end

      template = template.to_s.strip.upcase

      unless @@data[:editions].include?(template)
        lgs << "Unregistered template '#{template}' (#{mth})"
        return
      end

      @template = template
      @udef     = data[:edition][@template][:udef]
      @bldg     = data[:edition][@template][:bldg]
      @space    = data[:edition][@template][:space]

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
      #   - expanded to cover semi-heated and refrigerated spaces (see OSut)
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
      @liveload   = data[:bldg][@activity][:liveload]

      # Assign building category.
      unless @activity.empty?
        @category = data[:bldg][@activity][:category]
      end

      # Assign schedules to auxiliary spaces - if present.
      self.assignAuxiliarySchedules(self.buildingActivity?(model))

      # Assign schedules to ancillary spaces - if present.
      self.assignAncillarySchedules

      true
    end

    ##
    # Returns a building/space type/activity parameter, matching a registered
    # keyword (e.g. :lighting_per_area) for a model (building) or for an
    # individual space.
    #
    # @param k [#to_sym] registered keyword (e.g. :lighting_per_area)
    # @param obj [OpenStudio::Model::Model] a model
    # @param obj [OpenStudio::Model::Space] an individual space
    #
    # @return [] matching value - may be adjusted (e.g. :lighting_per_area)
    # @return [NilClass] nil if unregistered keyword
    def standards_data(k = "", obj = nil)
      lgs = @feedback[:logs]
      mth = "BTAP::Activity::#{__callee__}"
      id  = ""

      unless k.respond_to?(:to_sym)
        lgs << "Invalid keyword class '#{k.class}' (#{mth})"
        return nil
      end

      k = k.to_s.strip.downcase.to_sym

      unless data[:udef].key?(k)
        lgs << "Unregistered keyword #{k} (#{mth})"
        return nil
      end

      if obj.is_a?(OpenStudio::Model::Model)
        btap = data[:bldg][@activity]
        necb = @bldg[@activity]
        sch  = "NECB-#{btap[:necb_schedule_type]}-"

        # Search for building-level parameter, in sequence:
        #   1. NECB-specific (& building-specific) entries, e.g.:
        #        - target_illuminance_setpoint: 400
        #   2. NECB-specific (general) entries, e.g.:
        #        - ventilation_standard: "ASHRAE 62.1-2016 Table 6-1"
        #   3. NECB-independent (yet building-specific) entries, e.g.:
        #        - necb_schedule_type: "E"
        #   4. Inferred/calculated values, e.g. (based on :necb_schedule_type):
        #        - occupancy_schedule: "NECB-E-Occupancy"
        #   5. NECB-independent (general) entries, e.g.:
        #        - rgb: "255_255_255"
        return @activity                           if k == :building_type
        return necb[k]                             if necb.key?(k)          # 1.
        return @udef[k]                            if @udef.key?(k)         # 2.
        return btap[k]                             if btap.key?(k)          # 3.

        return "WholeBuilding"                     if k == :space_type      # 4.
        return @activity                           if k == :lighting_primary_space_type
        return "WholeBuilding"                     if k == :lighting_secondary_space_type
        return sch + "Lighting"                    if k == :lighting_schedule
        return @activity                           if k == :ventilation_primary_space_type
        return "WholeBuilding"                     if k == :ventilation_secondary_space_type
        return sch + "Occupancy"                   if k == :occupancy_schedule
        return sch + "Electric-Equipment"          if k == :electric_equipment_schedule
        return sch + "Thermostat Setpoint-Heating" if k == :heating_setpoint_schedule
        return sch + "Thermostat Setpoint-Cooling" if k == :cooling_setpoint_schedule
        return sch + "Service Water Heating"       if k == :service_water_heating_schedule
        return sch + "FAN"                         if k == :exhaust_schedule
        return data[:udef][k]                                               # 5.
      elsif obj.is_a?(OpenStudio::Model::Space)
        id = obj.nameString

        unless @activities.key?(id)
          return @udef.key?(k) ? @udef[k] : data[:udef][k]
        end

        type = self.keyword(space) # e.g. "corridor::common"

        if type == "undefined::common"
          return @udef.key?(k) ? @udef[k] : data[:udef][k]
        end

        unless data[:space].key?(type)
          return @udef.key?(k) ? @udef[k] : data[:udef][k]
        end

        unless @space.key?(type)
          return @udef.key?(k) ? @udef[k] : data[:udef][k]
        end

        btap = data[:space][type]
        necb = @space[type]
        sch  = "NECB-#{self.schedule(space)}-"

        # Search for space-level parameter, in sequence:
        #   1. NECB-specific (& space-specific) entries, e.g.:
        #        - target_illuminance_setpoint: 400
        #   2. NECB-specific (general) entries, e.g.:
        #        - ventilation_standard: "ASHRAE 62.1-2016 Table 6-1"
        #   3. NECB-independent (yet space-specific) entries, e.g.:
        #        - occupancy_per_area: 18.58
        #   4. Inferred/calculated values, e.g. (based on schedules):
        #        - occupancy_schedule: "NECB-E-Occupancy"
        #   5. NECB-independent (general) entries, e.g.:
        #        - rgb: "255_255_255"
        return type            if k == :space_type
        return necb[k]         if necb.key?(k) # 1.
        return @udef[k]        if @udef.key?(k) # 2.
        return btap[k]         if btap.key?(k) # 3.

        return "Space Function" if k == :building_type # 4.
        return "Space Function" if k == :lighting_primary_space_type
        return type             if k == :lighting_secondary_space_type
        return sch + "Lighting" if k == :lighting_schedule
        return "Space Function" if k == :ventilation_primary_space_type
        return type             if k == :ventilation_secondary_space_type
        return sch + "Occupancy"                   if k == :occupancy_schedule
        return sch + "Electric-Equipment"          if k == :electric_equipment_schedule
        return sch + "Thermostat Setpoint-Heating" if k == :heating_setpoint_schedule
        return sch + "Thermostat Setpoint-Cooling" if k == :cooling_setpoint_schedule
        return sch + "Service Water Heating"       if k == :service_water_heating_schedule
        return sch + "FAN"                         if k == :exhaust_schedule
        return data[:udef][k]                                               # 5.
      else
        lgs << "Invalid input #{obj.class} (#{mth})"
        return nil
      end

      nil
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
        id = space.nameString
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
        data[:space].each do |k, v|
          v[:includes].each do |kword|
            candidates << k if standards.include?(kword)
          end
        end

        # Keep track of fallbacks, if applicable.
        candidates.each do |candidate|
          fallback = data[:space][candidate][:fallback]
          next if fallback.empty?
          next unless data[:space].key?(fallback)

          fallbacks << fallback
        end

        # Reject if matching any excluded keyword.
        data[:space].each do |k, v|
          v[:excludes].each do |kword|
            candidates.delete(k) if standards.include?(kword)
          end
        end

        # Fallbacks?
        if candidates.empty?
          candidate = fallbacks.empty? ? "undefined::common" : fallbacks.first
        else
          candidate = candidates.first
        end

        str   = candidate.split("::")
        entry = {}

        entry[:m2       ] = space.floorArea * space.multiplier
        entry[:spacetype] = spacetype
        entry[:standards] = standards
        entry[:keyword  ] = candidate
        entry[:activity ] = str[0].to_s.strip
        entry[:bldgtype ] = str[1].to_s.strip
        entry[:schedule ] = data[:space][candidate][:necb_schedule_type]

        activities[id] = entry
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
        return activity if @bldg.key?(activity)
      end

      # OPTION B: Extract building activity from user-set 'building type'.
      bldgtype = model.getBuilding.standardsBuildingType

      unless bldgtype.empty?
        bldgtype   = bldgtype.get.downcase
        candidates = []
        fallbacks  = []

        return bldgtype if @bldg.key?(bldgtype)

        # Fetch matching BTAP data, if keywords included.
        data[:bldg].each do |k, v|
          v[:includes].each do |kword|
            candidates << k if bldgtype.include?(kword)
          end
        end

        # Keep track of fallbacks, if applicable.
        candidates.each do |candidate|
          fallback = data[:bldg][candidate][:fallback]
          next if fallback.empty?
          next unless data[:bldg].key?(fallback)

          fallbacks << fallback
        end

        # Reject if matching excluded keywords.
        data[:bldg].each do |k, v|
          v[:excludes].each do |kword|
            candidates.delete(k) if bldgtype.include?(kword)
          end
        end

        # Fallbacks? Building types/activities aren't expected to have JSON
        # fallback entries.
        if candidates.empty?
          return fallbacks.first unless fallbacks.empty?
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

        # Log (or raise) - @todo.
        activity = case activities.sort.reverse.to_h.keys.first
                   when "audience"    then "theatre"
                   when "seating"     then "theatre"
                   when "sales"       then "retail"
                   when "dining"      then "restaurant"
                   when "cuisine"     then "restaurant"
                   when "rooms"       then "hotel"
                   when "cell"        then "penitentiary"
                   when "classroom"   then "school"
                   when "teachinglab" then "school"
                   when "storage"     then "warehouse"
                   when "locker"      then "warehouse"
                   when "workshop"    then "workshop"
                   when "laundry"     then "retail"
                   when "lounge"      then "leisure"
                   when "pharmacy"    then "retail"
                   else                    "office"
                   end
      end

      # Log warning.
      unless activity
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
      return true if @bldg.include?(activity)

      false
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

        id = espace.nameString
        next unless @activities.key?(id)
        next if @activities[id][:schedule] == "*"

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
      uset = false unless [true, false].include?(uset)
      bkup = data[:bldg][@activity][:necb_schedule_type]

      # Loop through auxiliary spaces (largest to smallest in floor area).
      @activities.sort_by { |id, v| v[:m2] }.reverse.each do |id, v|
        k   = v[:keyword]
        sch = data[:space][k][:necb_schedule_type]
        next unless self.auxiliary?(k)

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
      bkup = @@data[:bldg][@activity][:necb_schedule_type]

      # Loop through ancillary spaces (largest to smallest in floor area).
      @activities.sort_by { |id, v| v[:m2] }.reverse.each do |id, v|
        k = v[:keyword]
        next unless self.ancillary?(k)

        # Retrieve each space's non-ancillary neighbours.
        schedules = {}
        schedule  = bkup

        self.neighbours(space).each do |nghbour|
          nom = nghbour.nameString
          next unless @activities.key?(nom)

          k2 = @activities[nom][:keyword]
          next if self.ancillary?(k2)

          sch = @activities[nom][:schedule]
          m2  = @activities[nom][:m2]

          schedules[sch]  = 0 unless schedules.key?(sch)
          schedules[sch] += m2
        end

        if schedules.empty?
          # Assign common building schedule if no non-ancillary adjacent spaces.
          lgs << "Assigning BUILDING schedule #{bkup} for #{id} (#{mth})"
          v[:schedule] = bkup
        else
          v[:schedule] = schedules.sort_by { |sch, m2| m2 }.reverse.first.first
        end

        # Forcing schedule set 'J' for ancillary spaces in:
        #   - short-term accomodation (e.g. hotels, firestation quarters)
        #   - housing (MURBs, dormitories)
        v[:schedule] = "J" if ["F", "G"].include?(v[:schedule])
      end

      true
    end

    ##
    # Returns a space's BTAP::Activity keyword, e.g. "corridor::hospital".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] a space's BTAP::Activity keyword - "" if invalid
    def keyword(space = nil)
      return "" unless space.is_a?(OpenStudio::Model::Space)

      id = space.nameString
      return "" unless @activities.key?(id)

      @activities[id][:keyword]
    end

    ##
    # Returns a space's activity, e.g. "corridor" in "corridor::hospital".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] a space's activity - "" if invalid/missing
    def act(space = nil)
      return "" unless space.is_a?(OpenStudio::Model::Space)

      id = space.nameString
      return "" unless @activities.key?(id)

      @activities[id][:activity]
    end

    ##
    # Returns a space's building type, e.g. "hospital" in "corridor::hospital".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] a space's building type - "" if invalid/missing
    def bldg(space = nil)
      return "" unless space.is_a?(OpenStudio::Model::Space)

      id = space.nameString
      return "" unless @activities.key?(id)

      @activities[id][:bldgtype]
    end

    ##
    # Returns a space's floor area (m2), factoring a space's multiplier.
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's floor area - 0 m2 if invalid/missing
    def m2(space = nil)
      return 0.0 unless space.is_a?(OpenStudio::Model::Space)

      id = space.nameString
      return 0.0 unless @activities.key?(id)

      @activities[id][:m2]
    end

    ##
    # Returns a space's (NECB-related) schedule set character, e.g. "A".
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [String] schedule set - "*" if invalid/missing
    def schedule(space = nil)
      return "*" unless space.is_a?(OpenStudio::Model::Space)

      id = space.nameString
      return "*" unless @activities.key?(id)

      @activities[id][:schedule]
    end

    ##
    # Validates whether a space is targeted for occupancy-sensing lighting
    # control, per NECB2011.
    #
    # @param space [OpenStudio::Model::Space] an OpenStudio space
    #
    # @return [Boolean] true if occsensing - false if invalid/missing
    def occsensing?(space = nil)
      return false unless space.is_a?(OpenStudio::Model::Space)

      type = self.keyword(space)
      area = space.floorArea

      return true if type == "classroom::common"
      return true if type == "classroom::penitentiary"
      return true if type == "meeting::common"
      return true if type == "lounge::common"
      return true if type == "lounge::health"
      return true if type == "copiers::common"
      return true if type == "washroom::common"
      return true if type == "dressing::theatre"
      return true if type == "dressing::retail"
      return true if type == "locker::common"
      return true if type == "storage::common"  && area.round < 100
      return true if type == "supplies::health" && area.round < 100
      return true if type == "office::common"   && area.round <  25

      false
    end

    ##
    # Returns a space's "factor for occupancy control" of lighting (Focc), per
    # NECB 4.3.2.10.1 (2015-2025).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's Focc of lighting - 1.0 if invalid/missing
    def fOCC(space = nil)
      return 1.0 unless space.is_a?(OpenStudio::Model::Space)

      type = self.keyword(space)

      # Focc = 1 - Ca x Cocc, where:
      #   Ca   = factor to account for the relative absence of occupants
      #   Cocc = factor to account for the occupancy-sensing mechanism
      cA = case type
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
      #
      # @todo: review cOCC values based on space_types JSON data.
      cOCC = case type
             when ""                         then 0.00
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
      cOCC = 0.30 if type == "office::common" && space.floorArea < 25

      1.0 - cA * cOCC
    end

    ##
    # Returns a space's "factor for personal control" of lighting (Fpers),
    # per NECB 4.3.2.10.2 (2015-2025).
    #
    # @param space [OpenStudio::Model::Space] a space
    #
    # @return [Float] space's Fpers of lighting - 1.0 if invalid/missing.
    def fPERS(space = nil)
      return 1.0 unless space.is_a?(OpenStudio::Model::Space)

      type = self.keyword(space)

      return 0.9 if type == "teachinglab::common"
      return 0.9 if type == "openplan::common"
      return 0.9 if type == "office::common"
      return 0.9 if type == "patient::health"

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
      return false unless space.is_a?(OpenStudio::Model::Space)

      type = self.act(space)

      return true if type == "atrium"
      return true if type == "corridor"
      return true if type == "mechanical"
      return true if type == "lobby"
      return true if type == "locker"
      return true if type == "garage"
      return true if type == "stairway"
      return true if type == "storage"
      return true if type == "washroom"
      return true if type == "bulk"
      return true if type == "fine"
      return true if type == "computer"
      return true if type == "server"
      return true if type == "copiers"
      return true if type == "emergency"

      false
    end
  end
end
