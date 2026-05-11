module OpenstudioStandards
  # The Space module provides methods get information about model spaces
  module Space
    # @!group Space

    # Determine if the space is a plenum.
    # Assume it is a plenum if it is a supply or return plenum for an AirLoop,
    # if it is not part of the total floor area,
    # or if the space type name contains the word plenum.
    #
    # @param space [OpenStudio::Model::Space] space object
    # return [Boolean] returns true if plenum, false if not
    def self.space_plenum?(space)
      plenum_status = false

      # Check if it is designated
      # as not part of the building
      # floor area.  This method internally
      # also checks to see if the space's zone
      # is a supply or return plenum
      unless space.partofTotalFloorArea
        plenum_status = true
        return true
      end

      # @todo update to check if it has internal loads

      # Check if the space type name
      # contains the word plenum.
      space_type = space.spaceType
      if space_type.is_initialized
        space_type = space_type.get
        if space_type.name.get.to_s.downcase.include?('plenum')
          plenum_status = true
          return plenum_status
        end
        if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')
          plenum_status = true
          return plenum_status
        end
      end

      return plenum_status
    end

    # Determine if the space is residential based on the space type name assigned to the space.
    # For spaces with no space type, assume nonresidential.
    # For spaces that are plenums, base the decision on the space
    # type of the space below the largest floor in the plenum.
    # Matches residential for names including 'Apartment', 'GuestRoom', 'PatRoom', 'ResBedroom', 'ResLiving'
    #
    # @param space [OpenStudio::Model::Space] space object
    # return [Boolean] true if residential, false if nonresidential
    def self.space_residential?(space)
      is_res = false

      space_to_check = space

      # If this space is a plenum, check the space type
      # of the space below the largest floor in the space
      if space_plenum?(space)
        # Find the largest floor
        largest_floor_area = 0.0
        largest_surface = nil
        space.surfaces.each do |surface|
          next unless surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Surface'

          if surface.grossArea > largest_floor_area
            largest_floor_area = surface.grossArea
            largest_surface = surface
          end
        end
        if largest_surface.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{space.name} is a plenum, but could not find a floor with a space below it to determine if plenum should be  res or nonres.  Assuming nonresidential.")
          return is_res
        end
        # Get the space on the other side of this floor
        if largest_surface.adjacentSurface.is_initialized
          adj_surface = largest_surface.adjacentSurface.get
          if adj_surface.space.is_initialized
            space_to_check = adj_surface.space.get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{space.name} is a plenum, but could not find a space attached to the largest floor's adjacent surface #{adj_surface.name} to determine if plenum should be res or nonres.  Assuming nonresidential.")
            return is_res
          end
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{space.name} is a plenum, but could not find a floor with a space below it to determine if plenum should be  res or nonres.  Assuming nonresidential.")
          return is_res
        end
      end

      space_type = space_to_check.spaceType

      if space_type.is_initialized
        space_type = space_type.get
        # @todo need an alternate way of determining residential without standards data
        res_types = [/\sApartment/, /GuestRoom/, /PatRoom/, /ResBedroom/, /ResLiving/]
        if res_types.any? { |match| space_type.name.get =~ match }
          is_res = true
        end
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Could not find a space type for #{space_to_check.name}, assuming nonresidential.")
      end

      return is_res
    end

    # Determines heating status.
    # If the space's zone has a thermostat with a maximum heating setpoint above 5C (41F), counts as heated.
    #
    # @author Andrew Parker, Julien Marrec
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Boolean] returns true if heated, false if not
    def self.space_heated?(space)
      # Get the zone this space is inside
      zone = space.thermalZone

      # Assume unheated if not assigned to a zone
      if zone.empty?
        return false
      end

      # Get the category from the zone
      htd = OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone.get)

      return htd
    end

    # Determines cooling status.
    # If the space's zone has a thermostat with a minimum cooling setpoint above 33C (91F), counts as cooled.
    #
    # @author Andrew Parker, Julien Marrec
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Boolean] returns true if cooled, false if not
    def self.space_cooled?(space)
      # Get the zone this space is inside
      zone = space.thermalZone

      # Assume uncooled if not assigned to a zone
      if zone.empty?
        return false
      end

      # Get the category from the zone
      cld = OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone.get)

      return cld
    end

    # Determine the design internal load (W) for this space without space multipliers.
    # This include People, Lights, Electric Equipment, and Gas Equipment.
    # It assumes 100% of the wattage is converted to heat, and that the design peak schedule value is 1 (100%).
    #
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Double] the design internal load, in W
    def self.space_get_design_internal_load(space)
      load_w = 0.0

      # People
      space.people.each do |people|
        w_per_person = 125 # Initial assumption
        act_sch = people.activityLevelSchedule
        if act_sch.is_initialized
          if act_sch.get.to_ScheduleRuleset.is_initialized
            act_sch = act_sch.get.to_ScheduleRuleset.get
            w_per_person = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(act_sch)['max']
          else
            OpenStudio.logFree(OpenStudio::Warn, 'OpenstudioStandards::Space', "#{space.name} people activity schedule is not a Schedule:Ruleset.  Assuming #{w_per_person}W/person.")
          end
          OpenStudio.logFree(OpenStudio::Warn, 'OpenstudioStandards::Space', "#{space.name} people activity schedule not found.  Assuming #{w_per_person}W/person.")
        end

        num_ppl = people.getNumberOfPeople(space.floorArea)

        ppl_w = num_ppl * w_per_person

        load_w += ppl_w
      end

      # Lights
      load_w += space.lightingPower

      # Electric Equipment
      load_w += space.electricEquipmentPower

      # Gas Equipment
      load_w += space.gasEquipmentPower

      OpenStudio.logFree(OpenStudio::Debug, 'OpenstudioStandards::Space', "#{space.name} has #{load_w.round}W of design internal loads.")

      return load_w
    end

    # @todo add related related to space_hours_of_operation like set_space_hours_of_operation and shift_and_expand_space_hours_of_operation
    # @todo ideally these could take in a date range, array of dates and or days of week. Hold off until need is a bit more defined.
    # If the model has an hours of operation schedule set in default schedule set for building that looks valid it will
    # report hours of operation. Won't be a single set of values, will be a collection of rules
    # note Building, space, and spaceType can get hours of operation from schedule set, but not buildingStory
    #
    # Retrieves the default occupancy schedule assigned to the space
    # @author David Goldwasser
    # @param space [OpenStudio::Model::Space] OpenStudio Space object
    # @return [Hash]: see example
    # @example: {
    #   schedule: space hours_of_operation schedule,
    #   [rule index, -1 is default day]: {
    #     hoo_start: [float] rule operation start hour,
    #     hoo_end: [float] rule operation end hour,
    #     hoo_hours: [float] rule operation duration hours,
    #     days_used: [Array] annual day indices
    #       }
    #   }
    def self.space_hours_of_operation(space)
      default_sch_type = OpenStudio::Model::DefaultScheduleType.new('HoursofOperationSchedule')
      hours_of_operation = space.getDefaultSchedule(default_sch_type)
      if !hours_of_operation.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Hours of Operation Schedule is not set for #{space.name}.")
        return nil
      end
      hours_of_operation = hours_of_operation.get
      if !hours_of_operation.to_ScheduleRuleset.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "Hours of Operation Schedule #{hours_of_operation.name} is not a ScheduleRuleset.")
        return nil
      end
      hours_of_operation = hours_of_operation.to_ScheduleRuleset.get
      profiles = {}

      # get indices for current schedule
      year_description = hours_of_operation.model.yearDescription.get
      year = year_description.assumedYear
      year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
      year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
      indices_vector = hours_of_operation.getActiveRuleIndices(year_start_date, year_end_date)

      # add default profile to hash
      hoo_start = nil
      hoo_end = nil
      unexpected_val = false
      times = hours_of_operation.defaultDaySchedule.times
      values = hours_of_operation.defaultDaySchedule.values
      times.each_with_index do |time, i|
        if values[i] == 0 && hoo_start.nil?
          hoo_start = time.totalHours
        elsif values[i] == 1 && hoo_end.nil?
          hoo_end = time.totalHours
        elsif values[i] != 1 && values[i] != 0
          unexpected_val = true
        end
      end

      # address schedule that is always on or always off (start and end can not both be nil unless unexpected value was found)
      if !hoo_start.nil? && hoo_end.nil?
        hoo_end = hoo_start
      elsif !hoo_end.nil? && hoo_start.nil?
        hoo_start = hoo_end
      end

      # some validation
      if times.size > 3 || unexpected_val || hoo_start.nil? || hoo_end.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{hours_of_operation.name} does not look like a valid hours of operation schedule for parametric schedule generation.")
        return nil
      end

      # hours of operation start and finish
      rule_hash = {}
      rule_hash[:hoo_start] = hoo_start
      rule_hash[:hoo_end] = hoo_end
      hoo_hours = nil
      if hoo_start == hoo_end
        if values.uniq == [1]
          hoo_hours = 24
        else
          hoo_hours = 0
        end
      elsif hoo_end > hoo_start
        hoo_hours = hoo_end - hoo_start
      elsif hoo_start > hoo_end
        hoo_hours = hoo_end + 24 - hoo_start
      end
      rule_hash[:hoo_hours] = hoo_hours
      days_used = []
      indices_vector.each_with_index do |profile_index, i|
        if profile_index == -1 then days_used << (i + 1) end
      end
      rule_hash[:days_used] = days_used
      profiles[-1] = rule_hash

      hours_of_operation.scheduleRules.reverse.each do |rule|
        # may not need date and days of week, will likely refer to specific date and get rule when applying parametricformula
        rule_hash = {}

        hoo_start = nil
        hoo_end = nil
        unexpected_val = false
        times = rule.daySchedule.times
        values = rule.daySchedule.values
        times.each_with_index do |time, i|
          if values[i] == 0 && hoo_start.nil?
            hoo_start = time.totalHours
          elsif values[i] == 1 && hoo_end.nil?
            hoo_end = time.totalHours
          elsif values[i] != 1 && values[i] != 0
            unexpected_val = true
          end
        end

        # address schedule that is always on or always off (start and end can not both be nil unless unexpected value was found)
        if !hoo_start.nil? && hoo_end.nil?
          hoo_end = hoo_start
        elsif !hoo_end.nil? && hoo_start.nil?
          hoo_start = hoo_end
        end

        # some validation
        if times.size > 3 || unexpected_val || hoo_start.nil? || hoo_end.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Space', "#{hours_of_operation.name} does not look like a valid hours of operation schedule for parametric schedule generation.")
          return nil
        end

        # hours of operation start and finish
        rule_hash[:hoo_start] = hoo_start
        rule_hash[:hoo_end] = hoo_end
        hoo_hours = nil
        if hoo_start == hoo_end
          if values.uniq == [1]
            hoo_hours = 24
          else
            hoo_hours = 0
          end
        elsif hoo_end > hoo_start
          hoo_hours = hoo_end - hoo_start
        elsif hoo_start > hoo_end
          hoo_hours = hoo_end + 24 - hoo_start
        end
        rule_hash[:hoo_hours] = hoo_hours
        days_used = []
        indices_vector.each_with_index do |profile_index, i|
          if profile_index == rule.ruleIndex then days_used << (i + 1) end
        end
        rule_hash[:days_used] = days_used

        #       # todo - delete rule details below unless end up needing to use them
        #       if rule.startDate.is_initialized
        #         date = rule.startDate.get
        #         rule_hash[:start_date] = "#{date.monthOfYear.value}/#{date.dayOfMonth}"
        #       else
        #         rule_hash[:start_date] = nil
        #       end
        #       if rule.endDate.is_initialized
        #         date = rule.endDate.get
        #         rule_hash[:end_date] = "#{date.monthOfYear.value}/#{date.dayOfMonth}"
        #       else
        #         rule_hash[:end_date] = nil
        #       end
        #       rule_hash[:mon] = rule.applyMonday
        #       rule_hash[:tue] = rule.applyTuesday
        #       rule_hash[:wed] = rule.applyWednesday
        #       rule_hash[:thu] = rule.applyThursday
        #       rule_hash[:fri] = rule.applyFriday
        #       rule_hash[:sat] = rule.applySaturday
        #       rule_hash[:sun] = rule.applySunday

        # update hash
        profiles[rule.ruleIndex] = rule_hash
      end

      return profiles
    end

    # If the model has an hours of operation schedule set in default schedule set for building that looks valid it will
    # report hours of operation. Won't be a single set of values, will be a collection of rules
    # this will call space_hours_of_operation on each space in array
    # loop through all days of year to make as many rules as ncessary
    # expand hours of operation. When hours of operation do not overlap for two spaces, add logic to remove all but largest gap
    #
    # @author David Goldwasser
    # @param spaces [Array<OpenStudio::Model::Space>] An array of OpenStudio Space objects
    # @return [Hash] start and end of hours of operation, stat date, end date, bool for each day of the week
    def self.spaces_hours_of_operation(spaces)
      hours_of_operation_array = []
      space_names = []
      spaces.each do |space|
        space_names << space.name.to_s
        hoo_hash = space_hours_of_operation(space)
        if !hoo_hash.nil?
          # OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, hours of operation hash = #{hoo_hash}.")
          hours_of_operation_array << hoo_hash
        end
      end

      # @todo replace this with logic to get combined hours of operation for collection of spaces.
      # each hours_of_operation_array is hash with key for each profile.
      # each profile has hash with keys for hoo_start, hoo_end, hoo_hours, days_used
      # my goal is to compare profiles and days used across all profiles to create new entries as necessary
      # then for all days I need to extend hours of operation addressing any situations where multile occupancy gaps occur
      #
      # loop through all 365/366 days

      # OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "Evaluating hours of operation for #{space_names.join(',')}: #{hours_of_operation_array}")

      # returns the most prevalent hours of operation hash among spaces
      hours_of_operation = hours_of_operation_array.max_by { |i| hours_of_operation_array.count(i) }

      return hours_of_operation
    end

    # This method creates a new fractional schedule ruleset.
    # If occupied_percentage_threshold is set, this method will return a discrete on/off fractional schedule
    # with a value of one when occupancy across all spaces is greater than or equal to the occupied_percentage_threshold,
    # and zero all other times.  Otherwise the method will return the weighted fractional occupancy schedule.
    #
    # @param spaces [Array<OpenStudio::Model::Space>] array of spaces to generate occupancy schedule from
    # @param sch_name [String] the name of the generated occupancy schedule
    # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
    #   if this parameter is set, the returned ScheduleRuleset will be 0 = unoccupied, 1 = occupied
    #   otherwise the ScheduleRuleset will be the weighted fractional occupancy schedule based on threshold_calc_method
    # @param threshold_calc_method [String] customizes behavior of occupied_percentage_threshold
    #   fractional passes raw value through,
    #   normalized_annual_range evaluates each value against the min/max range for the year
    #   normalized_daily_range evaluates each value against the min/max range for the day.
    #   The goal is a dynamic threshold that calibrates each day.
    # @return [<OpenStudio::Model::ScheduleRuleset>] a ScheduleRuleset of fractional or discrete occupancy
    def self.spaces_get_occupancy_schedule(spaces, sch_name: nil, occupied_percentage_threshold: nil, threshold_calc_method: 'value')
      if spaces.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.space', 'Empty spaces array passed to spaces_get_occupancy_schedule method.')
        return false
      end

      model = spaces.first.model
      year = model.getYearDescription.assumedYear

      unless sch_name.nil?
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.space', "Finding space schedules for #{sch_name}.")
      end

      # create schedule
      if sch_name.nil?
        sch_name = "#{spaces.size} space(s) Occ Sch"
      end

      # Get all the occupancy schedules in spaces.
      # Include people added via the SpaceType and hard-assigned to the Space itself.
      occ_schedules_num_occ = {} # hash of People ScheduleRuleset => design occupancy for that People object
      spaces.each do |space|
        # From the space type
        if space.spaceType.is_initialized
          space.spaceType.get.people.each do |people|
            num_ppl_sch = people.numberofPeopleSchedule
            next if num_ppl_sch.empty?

            if num_ppl_sch.get.to_ScheduleRuleset.empty? # skip non-ruleset schedules
              OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.space', "People schedule #{num_ppl_sch.get.name} is not a Ruleset Schedule, it will not contribute to hours of operation")
            else
              num_ppl_sch = num_ppl_sch.get.to_ScheduleRuleset.get
              num_ppl = people.getNumberOfPeople(space.floorArea)
              occ_schedules_num_occ.key?(num_ppl_sch) ? occ_schedules_num_occ[num_ppl_sch] += num_ppl : occ_schedules_num_occ[num_ppl_sch] = num_ppl
            end
          end
        end

        # From the space
        space.people.each do |people|
          num_ppl_sch = people.numberofPeopleSchedule
          next if num_ppl_sch.empty?

          if num_ppl_sch.get.to_ScheduleRuleset.empty? # skip non-ruleset schedules
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.space', "People schedule #{num_ppl_sch.get.name} is not a Ruleset Schedule, it will not contribute to hours of operation")
          else
            num_ppl_sch = num_ppl_sch.get.to_ScheduleRuleset.get
            num_ppl = people.getNumberOfPeople(space.floorArea)
            occ_schedules_num_occ.key?(num_ppl_sch) ? occ_schedules_num_occ[num_ppl_sch] += num_ppl : occ_schedules_num_occ[num_ppl_sch] = num_ppl
          end
        end
      end

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.space', "The #{spaces.size} spaces have #{occ_schedules_num_occ.size} unique occ schedules.")
      occ_schedules_num_occ.each do |occ_sch, num_occ|
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.space', "...#{occ_sch.name} - #{num_occ.round} people")
      end

      # get nested array of 8760 values of the total occupancy at each hour of each schedule
      all_schedule_hourly_occ = []
      occ_schedules_num_occ.each do |occ_sch, num_occ|
        all_schedule_hourly_occ << OpenstudioStandards::Schedules.schedule_get_hourly_values(occ_sch).map { |i| (i * num_occ).round(6) }
      end

      # total occupancy from all people
      total_design_occ = occ_schedules_num_occ.values.sum

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.space', "Total #{total_design_occ.round} people in #{spaces.size} spaces.")

      # if design occupancy is zero, return zero schedule
      if total_design_occ.zero?
        schedule_ruleset = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(spaces[0].model, 0.0, name: sch_name)
        return schedule_ruleset
      end

      # get one 8760 array of the sum of each schedule's hourly occupancy
      combined_hourly_occ = all_schedule_hourly_occ.transpose.map(&:sum)

      # divide each hourly value by total occupancy - this is all spaces fractional occupancy
      combined_occ_frac = combined_hourly_occ.map { |i| i / total_design_occ }

      # divide 8760 array into 365(or 366)x24 arrays
      daily_combined_occ_fracs = combined_occ_frac.each_slice(24).to_a

      # If occupied_percentage_threshold is specified, schedule values are boolean
      # Otherwise use the actual spaces_occ_frac
      if occupied_percentage_threshold.nil?
        occ_status_vals = daily_combined_occ_fracs
      elsif threshold_calc_method == 'normalized_daily_range'
        # calculate max/min values in each daily occ fraction array
        daily_max_vals = daily_combined_occ_fracs.map(&:max)
        daily_min_vals = daily_combined_occ_fracs.map(&:min)
        # normalize threshold to daily min/max values
        daily_normalized_thresholds = daily_min_vals.zip(daily_max_vals).map { |min_max| min_max[0] + ((min_max[1] - min_max[0]) * occupied_percentage_threshold) }
        # if daily occ frac exceeds daily normalized threshold, set value to 1
        occ_status_vals = daily_combined_occ_fracs.each_with_index.map { |day_array, i| day_array.map { |day_val| !day_val.zero? && day_val >= daily_normalized_thresholds[i] ? 1 : 0 } }
      elsif threshold_calc_method == 'normalized_annual_range'
        # calculate annual min/max values
        annual_max = daily_combined_occ_fracs.max_by(&:max).max
        annual_min = daily_combined_occ_fracs.min_by(&:min).min
        # normalize threshold to annual min/max
        annual_normalized_threshold = annual_min + ((annual_max - annual_min) * occupied_percentage_threshold)
        # if vals exceed threshold, set val to 1
        occ_status_vals = daily_combined_occ_fracs.map { |day_array| day_array.map { |day_val| day_val >= annual_normalized_threshold ? 1 : 0 } }
      else # threshold_calc_method == 'value'
        occ_status_vals = daily_combined_occ_fracs.map { |day_array| day_array.map { |day_val| day_val >= occupied_percentage_threshold ? 1 : 0 } }
      end

      # get unique daily profiles for weekdays, saturdays and sundays
      wd_profile_days = Hash.new { |h, k| h[k] = [] }
      sat_profile_days = Hash.new { |h, k| h[k] = [] }
      sun_profile_days = Hash.new { |h, k| h[k] = [] }

      occ_status_vals.each_with_index do |day_profile, i|
        day_type = OpenStudio::Date.fromDayOfYear(i + 1, year).dayOfWeek.valueName
        if day_type == 'Saturday'
          sat_profile_days[day_profile] << (i + 1)
        elsif day_type == 'Sunday'
          sun_profile_days[day_profile] << (i + 1)
        else
          wd_profile_days[day_profile] << (i + 1)
        end
      end

      # create schedule
      schedule_ruleset = OpenStudio::Model::ScheduleRuleset.new(spaces[0].model)
      schedule_ruleset.setName(sch_name.to_s)
      # add properties to schedule
      props = schedule_ruleset.additionalProperties
      props.setFeature('max_occ_in_spaces', total_design_occ)
      props.setFeature('number_of_spaces_included', spaces.size)
      # nothing uses this but can make user be aware if this may be out of sync with current state of occupancy profiles
      props.setFeature('date_parent_object_last_edited', Time.now.getgm.to_s)
      props.setFeature('date_parent_object_created', Time.now.getgm.to_s)

      # Winter Design Day - All Occupied
      schedule_ruleset.setWinterDesignDaySchedule(schedule_ruleset.winterDesignDaySchedule)
      day_sch = schedule_ruleset.winterDesignDaySchedule
      day_sch.setName("#{sch_name} Winter Design Day")
      day_sch.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1)

      # Summer Design Day - All Occupied
      schedule_ruleset.setSummerDesignDaySchedule(schedule_ruleset.summerDesignDaySchedule)
      day_sch = schedule_ruleset.summerDesignDaySchedule
      day_sch.setName("#{sch_name} Summer Design Day")
      day_sch.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1)

      # set most used weekday profile to default day
      most_used_wd_profile = wd_profile_days.max_by { |k, v| v.size }.first
      default_day = schedule_ruleset.defaultDaySchedule
      default_day.setName("#{sch_name} Default")
      OpenstudioStandards::Schedules.schedule_day_populate_from_array_of_values(default_day, most_used_wd_profile)

      # create rules from remaining weekday, saturday and sunday profiles
      remaining_wd_profiles = wd_profile_days.slice(*wd_profile_days.keys.reject { |k| k == most_used_wd_profile })

      [remaining_wd_profiles, sat_profile_days, sun_profile_days].each do |profile_hash|
        profile_hash.each do |profile, days_used|
          rules = OpenstudioStandards::Schedules.schedule_ruleset_create_rules_from_day_list(schedule_ruleset, days_used)
          rules.each { |rule| OpenstudioStandards::Schedules.schedule_day_populate_from_array_of_values(rule.daySchedule, profile) }
        end
      end

      return schedule_ruleset
    end

    # @!endgroup Space

    # @!group SpaceLoadInstance

    # method to process load instance schedules for model_setup_parametric_schedules
    #
    # @author David Goldwasser
    # @param space_load_instance [OpenStudio::Model::SpaceLoadInstance] OpenStudio SpaceLoadInstance object
    # @param parametric_inputs [Hash]
    # @param hours_of_operation [Hash]
    # @param gather_data_only [Boolean]
    # @return [Hash]
    def self.space_load_instance_get_parametric_schedule_inputs(space_load_instance, parametric_inputs, hours_of_operation, gather_data_only)
      if space_load_instance.instance_of?(OpenStudio::Model::People)
        opt_sch = space_load_instance.numberofPeopleSchedule
      elsif space_load_instance.instance_of?(OpenStudio::Model::DesignSpecificationOutdoorAir)
        opt_sch = space_load_instance.outdoorAirFlowRateFractionSchedule
      else
        opt_sch = space_load_instance.schedule
      end
      if !opt_sch.is_initialized || !opt_sch.get.to_ScheduleRuleset.is_initialized
        return nil
      end

      OpenstudioStandards::Schedules.schedule_ruleset_get_parametric_inputs(opt_sch.get.to_ScheduleRuleset.get, space_load_instance, parametric_inputs, hours_of_operation, gather_data_only: gather_data_only, hoo_var_method: 'hours')

      return parametric_inputs
    end

    # @!endgroup SpaceLoadInstance
  end
end
