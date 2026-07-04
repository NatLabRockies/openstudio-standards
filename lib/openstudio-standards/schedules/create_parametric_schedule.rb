module OpenstudioStandards
  module Schedules
    # @!group Schedule Derivation Methods
    # Apply the smootherstep function to a given input located beetween a starting and ending value range between start/end values will be unitized
    #
    # @param edge0 [Float] lower limit
    # @param edge1 [FLoat] upper limit
    # @param x [Float] input value
    # @return [Float] evaluated value
    def self.smootherstep(edge0, edge1, x)
      if x < edge0 && x > edge1
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', 'Cannot apply smootherstep to an input outside of range')
        return false
      end

      if edge0 == edge1
        return 0.0
      end

      # fractionalize input over unitized input range, then apply the easing family
      x_i = ((x - edge0) / (edge1 - edge0))

      return smootherstep_easing(x_i)
    end

    # Smootherstep easing function on a normalized input. This is the default,
    # pluggable interpolation easing used by {smooth_schedule_from_time_values}.
    #
    # smootherstep, 6x^5 - 15x^4 + 10x^3, is exactly the regularized incomplete
    # beta function I_x(3,3) - i.e. the CDF of a symmetric Beta(3,3) distribution -
    # so a transition is the cumulative fraction of a symmetric arrival/departure
    # time distribution across the window. The sanctioned extension path is the
    # integer-parameter Beta CDF I_x(alpha, beta), which reproduces this exactly at
    # alpha = beta = 3 and adds a skew lever; swap easing families by passing a
    # different `easing` callable to {smooth_schedule_from_time_values}.
    #
    # @param x_i [Float] normalized input in [0, 1]
    # @return [Float] eased value in [0, 1]
    def self.smootherstep_easing(x_i)
      x_i * x_i * x_i * ((x_i * ((6.0 * x_i) - 15.0)) + 10.0)
    end

    # Applies an easing function to the input set of <24 time_value_pairs to interpolate missing points
    #
    # @param time_value_pairs [Array] array of time value pairs
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @param easing [#call] easing function mapping a normalized input in [0, 1] to an
    #   eased value in [0, 1]. Defaults to {smootherstep_easing}. Pass a different
    #   callable (e.g. an integer-parameter Beta CDF) to swap the interpolation family.
    # @return [<Array>] Returns an expanded array of 24 time value pairs
    def self.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour, easing: nil)
      easing ||= method(:smootherstep_easing)
      return_arry = []
      if time_value_pairs[0][0] != 0
        time_value_pairs.unshift([0, time_value_pairs[0][1]])
      end
      if time_value_pairs[-1][0] < 24
        time_value_pairs << [24, time_value_pairs[-1][1]]
      end

      time_value_pairs.each_cons(2) do |this_pair, next_pair|
        this_time = this_pair[0].to_f
        this_val = this_pair[1]
        next_time = next_pair[0].to_f
        next_val = next_pair[1]
        last_time = time_value_pairs[-1][0]

        next_time == last_time ? exclude_end = false : exclude_end = true

        Range.new(this_time, next_time, exclude_end).step(1.0 / timesteps_per_hour).each do |time|
          # normalize the input within this segment, then apply the easing family.
          # equal endpoints yield 0.0, matching the original smootherstep guard.
          val_frac = this_time == next_time ? 0.0 : easing.call((time - this_time) / (next_time - this_time))
          if next_val < this_val
            val_actual = this_val - (val_frac * (next_val - this_val).abs)
          else
            val_actual = this_val + (val_frac * (next_val - this_val).abs)
          end
          return_arry << [time, val_actual]
        end
      end
      return_arry
    end

    # Wrap time value pairs to 24 hours
    #
    # @param time_value_pairs [Array] array of time value pairs
    # @return [Array] array of wrapped time value pairs
    def self.wrap_schedule_pairs(time_value_pairs)
      # divide the time value pairs at 24 hours
      wrap_group = []
      normal_group = []

      time_value_pairs.each do |time, value|
        if time >= 24
          wrap_group << [time - 24.0, value]
        end
        if time <= 24.0
          normal_group << [time, value]
        end
      end

      # merge both groups by time. If the same time exists, sum the values
      merged = {}

      (wrap_group + normal_group).each do |time, value|
        key = merged.keys.find { |k| (k - time).abs < 1e-6 } || time
        merged[key] ||= []
        merged[key] << value
      end

      result = merged.map do |time, values|
        combined = values.size > 1 ? values.reduce(:+) / [values.sum, 1.0].max : values[0]
        [time, combined]
      end

      result.sort_by { |time, _| time }
    end

    # Wrap time/value rows to a bounded hour range while preserving row count.
    # This mirrors the helper used by the slope-based schedule expansion workflow.
    #
    # @param time_value_pairs [Array] array of [time, value] pairs
    # @param upper_bound [Float] upper time bound (typically 24)
    # @return [Array] adjusted array of [time, value] pairs
    def self.wrap_around_time_values(time_value_pairs, upper_bound)
      keep = time_value_pairs.select { |pair| pair[0] > 0 && pair[0] <= upper_bound }.map(&:dup)
      remove_below = time_value_pairs.select { |pair| pair[0] <= 0 }.map(&:dup)
      remove_above = time_value_pairs.select { |pair| pair[0] > upper_bound }.map(&:dup)

      if !remove_below.empty? && remove_below[0][0] == 0
        remove_below.shift
      end

      if !remove_below.empty? && !keep.empty?
        start_index = keep.length - remove_below.length
        remove_below.each_with_index do |pair, i|
          idx = start_index + i
          next if idx.negative? || idx >= keep.length

          keep[idx][1] = pair[1]
        end
      end

      if !remove_above.empty? && !keep.empty?
        remove_above.each_with_index do |pair, i|
          break if i >= keep.length

          keep[i][1] = pair[1]
        end
      end

      keep
    end

    # Evaluate a control-point schedule definition into sorted [time, value] anchor
    # pairs, BEFORE any wrap or smoothing. Times may legitimately exceed 24 (next-day
    # spillover) or fall below 0 (previous-day spillover).
    #
    # @param schedule_data [Hash] hash of schedule data
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @param start_time [Float] input start time
    # @param end_time [Float] input end time
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Array] sorted array of [time, value] anchor pairs
    def self.evaluate_schedule_control_points(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      # proc to round to timestep
      round_to_timestep = ->(val) { (val * timesteps_per_hour).round / timesteps_per_hour.to_f }

      # adjust end time to be after start time
      if end_time < start_time
        end_time += 24
      end

      # calculate baseline duration and relative adjustment multiplier
      standard_duration = schedule_data[:et_std] - schedule_data[:st_std]
      adjustment_multiplier = (end_time - start_time) / standard_duration

      # evaluate control points with inputs
      time_value_pairs = []

      control_points = schedule_data[:control_points]
      control_points.each do |point|
        # control points are an array of two strings describing the time and value modifiers relative to start and end time (st/et) and base and peak values
        # e.g. ['st-1', 'base*0.5']
        parser = /([a-z]+)(?:([+\-*])(\d+(?:\.\d+)?))?/
        time_point = point[0].scan(parser)[0]
        value_point = point[1].scan(parser)[0]
        case time_point[0]
        when 'st'
          time = start_time
        when 'et'
          time = end_time
        end

        # adjust time modifier by ratio of given duration to standard duration
        unless time_point[1].nil? && time_point[2].nil?
          time = time.send(time_point[1], time_point[2].to_i * adjustment_multiplier)
        end
        # ensure time lands on timestep
        time = round_to_timestep.call(time)

        # evaluate value point
        case value_point[0]
        when 'base'
          val = base
        when 'peak'
          val = peak
        end

        unless value_point[1].nil? && value_point[2].nil?
          val = val.send(value_point[1], value_point[2].to_f)
        end

        # limit value between 0 and 1 (clamp is non-mutating, so reassign)
        val = val.clamp(0, 1)

        time_value_pairs << [time, val]
      end
      time_value_pairs.sort_by! { |pair| pair[0] }
      time_value_pairs
    end

    # Clip control-point anchors to an absolute [start_time, end_time] window for
    # truncate mode: anchors outside the window are dropped, the window edges are
    # forced to base, and smootherstep then ramps in/out. Multi-hump profiles thus lose
    # whole humps that fall outside the window instead of compressing.
    #
    # @param anchors [Array] sorted [time, value] anchors at absolute (standard) times
    # @param start_time [Float] clip window start (hours)
    # @param end_time [Float] clip window end (hours)
    # @param base [Float] base value forced outside the window
    # @return [Array] clipped, sorted [time, value] anchors
    def self.clip_control_point_anchors(anchors, start_time, end_time, base)
      st = start_time
      et = end_time
      et += 24 if et < st
      kept = anchors.select { |t, _| t > st && t < et }
      ([[st, base]] + kept + [[et, base]]).sort_by { |t, _| t }
    end

    # Expands parametric schedule control points
    #
    # @param schedule_data [Hash] hash of schedule data
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @param start_time [Float] input start time
    # @param end_time [Float] input end time
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Array] array of time value pairs
    def self.expand_schedule_control_points(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      mode = (schedule_data[:adjustment_mode] || 'stretch').to_s
      if mode == 'truncate'
        # Truncate: anchor humps to their absolute standard wall-clock positions
        # (evaluate at st_std/et_std so offsets are unscaled), then clip to the building
        # [start_time, end_time] window, forcing outside-window to base.
        anchors = OpenstudioStandards::Schedules.evaluate_schedule_control_points(schedule_data, base, peak, schedule_data[:st_std], schedule_data[:et_std], timesteps_per_hour)
        time_value_pairs = OpenstudioStandards::Schedules.clip_control_point_anchors(anchors, start_time, end_time, base)
      else
        # Stretch (default): anchor to st/et and scale offsets by the duration ratio.
        time_value_pairs = OpenstudioStandards::Schedules.evaluate_schedule_control_points(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      end

      if time_value_pairs[-1][0] > 24
        time_value_pairs = OpenstudioStandards::Schedules.wrap_schedule_pairs(time_value_pairs)
      end

      # apply smoothing to intermediate values between
      OpenstudioStandards::Schedules.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour)
    end

    # Compute the cross-midnight spillover of a control-point profile as time-value
    # pairs anchored in the adjacent calendar day. The smoothed profile is
    # evaluated across its full (un-wrapped) range; the portion past 24h becomes the
    # early hours of the NEXT day, the portion before 0h becomes the late hours of the
    # PREVIOUS day.
    #
    # @param schedule_data [Hash] hash of schedule data
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @param start_time [Float] input start time
    # @param end_time [Float] input end time
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Hash] { next_day: [[t, v], ...], prev_day: [[t, v], ...] } (times 0..24 in the adjacent day)
    def self.schedule_control_points_spillover(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      result = { next_day: [], prev_day: [] }

      # truncate profiles are clipped to the [start_time, end_time] window, so
      # they do not spill past it into an adjacent day.
      mode = (schedule_data[:adjustment_mode] || 'stretch').to_s
      return result if mode == 'truncate'

      anchors = OpenstudioStandards::Schedules.evaluate_schedule_control_points(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      return result unless anchors[-1][0] > 24 || anchors[0][0] < 0

      smoothed = OpenstudioStandards::Schedules.smooth_schedule_from_time_values(anchors, timesteps_per_hour)
      result[:next_day] = smoothed.select { |t, _| t > 24 }.map { |t, v| [(t - 24).round(6), v] }
      result[:prev_day] = smoothed.select { |t, _| t < 0 }.map { |t, v| [(t + 24).round(6), v] }
      result
    end

    # Expands a profile using start/end times with start/end slopes.
    # Methodology is aligned with the notebook's expand_schedule_profile_from_start_end_slope flow.
    #
    # @param schedule_data [Hash] hash of schedule data containing :start_slope and :end_slope
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @param start_time [Float] input start time
    # @param end_time [Float] input end time
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Array] array of time value pairs
    def self.expand_schedule_start_end_slope(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      start_slope = schedule_data[:start_slope]
      end_slope = schedule_data[:end_slope]

      if start_slope.nil? || end_slope.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Schedule '#{schedule_data[:name]}' is missing start_slope and/or end_slope.")
        return nil
      end

      timestep = 1.0 / timesteps_per_hour.to_f
      round_to_nearest = ->(val) { (val / timestep).round * timestep }

      st = start_time.clamp(0, 24)
      et = end_time.clamp(0, 24)
      start_slope = [start_slope.to_f, 0.001].max
      end_slope = [end_slope.to_f, 0.001].max

      st = round_to_nearest.call(st)
      et = round_to_nearest.call(et)

      start_range = (start_slope * (et - st)).round(0)
      end_range = (end_slope * (et - st)).round(0)

      start_lower = st - round_to_nearest.call(start_range / 2.0)
      start_upper = st + round_to_nearest.call(start_range / 2.0)
      end_lower = et - round_to_nearest.call(end_range / 2.0)
      end_upper = et + round_to_nearest.call(end_range / 2.0)

      startup = OpenstudioStandards::Schedules.smooth_schedule_from_time_values([[start_lower, 0], [start_upper, 1], [start_upper + timestep, 0]], timesteps_per_hour)
      endup = OpenstudioStandards::Schedules.smooth_schedule_from_time_values([[end_lower - timestep, 1], [end_lower, 0], [end_upper, 1]], timesteps_per_hour)
      endup = endup.map { |time, value| [time, 1 + (value * -1)] }

      start_wrap = OpenstudioStandards::Schedules.wrap_around_time_values(startup, 24.0)
      end_wrap = OpenstudioStandards::Schedules.wrap_around_time_values(endup, 24.0)

      if start_wrap.size != end_wrap.size
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Slope profile expansion failed due to incompatible array lengths for '#{schedule_data[:name]}'.")
        return nil
      end

      combined = start_wrap.each_with_index.map do |pair, i|
        sum_val = pair[1] + end_wrap[i][1]
        max_val = [sum_val, 1.0].max
        [pair[0], sum_val / max_val]
      end

      start_upper_mod = start_upper % 24.0
      end_lower_mod = end_lower % 24.0
      combined.each do |pair|
        pair[1] = 1 if pair[0] >= start_upper_mod && pair[0] <= end_lower_mod
      end

      combined.map do |time, value|
        [time, base + ((peak - base) * value)]
      end
    end

    # Add time value pairs to OpenStudio ScheduleDay
    #
    # @param day_sch [OpenStudio::Model::ScheduleDay] OpenStudio ScheduleDay object
    # @param time_value_pairs [Array] array of time value pairs
    # @return [Boolean] true if successful, false if not
    def self.add_time_value_pairs_to_schedule(day_sch, time_value_pairs)
      time_value_pairs.each_with_index do |pair, i|
        # p pair
        if i != (time_value_pairs.size - 1) && pair[1] == time_value_pairs[i + 1][1]
          next
        end

        hr = pair[0].to_i
        min = (pair[0].modulo(1) * 60).to_i

        day_sch.addValue(OpenStudio::Time.new(0, hr, min, 0), pair[1])
      end
    end

    # Calendar day-of-week order used for cross-day spillover adjacency.
    DAY_OF_WEEK_ORDER = %w[Mon Tue Wed Thu Fri Sat Sun].freeze

    # Days of the week (Mon..Sun) that a schedule day type applies to.
    #
    # @param day_type [String] one of Default, Wkdy, Wknd, Sat, Sun, Mon..Fri
    # @return [Array<String>] applied day-of-week abbreviations
    def self.day_type_applied_days(day_type)
      case day_type
      when 'Wkdy' then %w[Mon Tue Wed Thu Fri]
      when 'Wknd' then %w[Sat Sun]
      when 'Default' then %w[Mon Tue Wed Thu Fri Sat Sun]
      else DAY_OF_WEEK_ORDER.include?(day_type) ? [day_type] : []
      end
    end

    # @param day [String] day-of-week abbreviation
    # @return [String] the following calendar day-of-week
    def self.next_day_of_week(day)
      DAY_OF_WEEK_ORDER[(DAY_OF_WEEK_ORDER.index(day) + 1) % 7]
    end

    # Value of a sorted [time, value] profile at a given time (step function: the value
    # of the last anchor at or before the time; the first value before the first anchor).
    #
    # @param pairs [Array] sorted [time, value] pairs
    # @param time [Float] query time in hours
    # @return [Float] value at the time
    def self.profile_value_at(pairs, time)
      return 0.0 if pairs.nil? || pairs.empty?

      val = pairs.first[1]
      pairs.each do |t, v|
        break if t > time

        val = v
      end
      val
    end

    # Combine a next-day spillover tail with a boundary day's typical profile.
    # In the spilled early hours the result is the max of the spillover and the typical
    # value (occupancy is present if either source says so); after the spill the typical
    # profile is used unchanged.
    #
    # @param spill_pairs [Array] spillover [time, value] pairs anchored in the boundary day (times from 0)
    # @param base_pairs [Array] the boundary day's typical reduced [time, value] pairs
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Array] reduced [time, value] pairs for the combined boundary day
    def self.combine_spillover_with_base(spill_pairs, base_pairs, timesteps_per_hour)
      return base_pairs if spill_pairs.nil? || spill_pairs.empty?

      spill_end = spill_pairs.map(&:first).max
      step = 1.0 / timesteps_per_hour
      combined = []
      t = 0.0
      while t < 24.0 + (step / 2.0)
        tt = (t * timesteps_per_hour).round / timesteps_per_hour.to_f
        base_val = OpenstudioStandards::Schedules.profile_value_at(base_pairs, tt)
        val = if tt <= spill_end
                [OpenstudioStandards::Schedules.profile_value_at(spill_pairs, tt), base_val].max
              else
                base_val
              end
        combined << [tt, val]
        t += step
      end

      # reduce consecutive duplicate values
      combined.reject.with_index { |e, i| e[1] == combined[i + 1][1] unless i == (combined.size - 1) }
    end

    # The typical reduced [time, value] profile that normally applies to a given day,
    # read from an in-progress create_complex_schedule options hash (a matching rule if
    # present, otherwise the default day).
    #
    # @param options [Hash] create_complex_schedule options under assembly
    # @param day [String] day-of-week abbreviation
    # @return [Array] reduced [time, value] pairs
    def self.boundary_day_base_profile(options, day)
      rule = (options['rules'] || []).find { |r| OpenstudioStandards::Schedules.day_type_applied_days(r[2]).include?(day) }
      if rule
        rule[3..]
      elsif options['default_day']
        options['default_day'][1..]
      else
        []
      end
    end

    # Build a day-specific create_complex_schedule rule combining a next-day spillover
    # tail with the boundary day's typical profile.
    #
    # @param options [Hash] create_complex_schedule options under assembly
    # @param day [String] boundary day-of-week abbreviation
    # @param spill_pairs [Array] spillover [time, value] pairs anchored in the boundary day
    # @param obj [Hash] source profile object (for the rule date range)
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Array] a create_complex_schedule rule array
    def self.build_spillover_rule(options, day, spill_pairs, obj, timesteps_per_hour)
      base_pairs = OpenstudioStandards::Schedules.boundary_day_base_profile(options, day)
      combined = OpenstudioStandards::Schedules.combine_spillover_with_base(spill_pairs, base_pairs, timesteps_per_hour)
      start_date = DateTime.strptime(obj[:start_date]).strftime('%m/%d')
      end_date = DateTime.strptime(obj[:end_date]).strftime('%m/%d')
      [day, "#{start_date}-#{end_date}", day] + combined
    end

    # Expand a single parametric profile object to time-value pairs, selecting the
    # expander explicitly via the profile `expansion` field (`control_points` | `slope`)
    # or by inference (slope iff both start_slope and end_slope are present).
    #
    # @param obj [Hash] parametric profile object
    # @param base [Float] base value
    # @param peak [Float] peak value
    # @param st [Float] start time in hours
    # @param et [Float] end time in hours
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @param start_slope [Float, nil] start slope (slope expander)
    # @param end_slope [Float, nil] end slope (slope expander)
    # @return [Array, nil] array of time-value pairs, or nil if expansion was skipped/failed
    def self.expand_parametric_profile(obj, base, peak, st, et, timesteps_per_hour, start_slope: nil, end_slope: nil)
      use_slope =
        case obj[:expansion]
        when 'slope'
          true
        when 'control_points'
          false
        else
          !start_slope.nil? && !end_slope.nil?
        end

      if use_slope
        if start_slope.nil? || end_slope.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Schedule '#{obj[:name]}' requests slope expansion but is missing start_slope and/or end_slope.")
          return nil
        end
        obj_with_slope = obj.merge(start_slope: start_slope, end_slope: end_slope)
        OpenstudioStandards::Schedules.expand_schedule_start_end_slope(obj_with_slope, base, peak, st, et, timesteps_per_hour)
      else
        OpenstudioStandards::Schedules.expand_schedule_control_points(obj, base, peak, st, et, timesteps_per_hour)
      end
    end

    # Revised method to construct ScheduleRulesets from data in parametric form, which uses the existing Schedules module method
    # Constructs all day schedules and assign appropriate rules
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param schedule_array [Array] array of default schedule data objects to load from - TODO: extract this part out
    # @param schedule_name [String] name of schedule to create
    # @param params [Hash] optional schedule input overrides used during expansion.
    #   Supported keys:
    #   - :st [Float] weekday start time in hours. Drives Default/Wkdy profiles. Defaults to schedule object :st_std.
    #   - :et [Float] weekday end time in hours. Drives Default/Wkdy profiles. Defaults to schedule object :et_std.
    #   - :wknd_st [Float] weekend start time in hours. Drives Wknd/Sat/Sun profiles. Defaults to :st_std.
    #   - :wknd_et [Float] weekend end time in hours. Drives Wknd/Sat/Sun profiles. Defaults to :et_std.
    #   - :base [Float] base schedule value (typically 0.0..1.0). Defaults to :base_std.
    #   - :peak [Float] peak schedule value (typically 0.0..1.0). Defaults to :peak_std.
    #   - :start_slope [Float] optional start transition slope factor for slope-based profile expansion.
    #     If provided together with :end_slope, uses expand_schedule_start_end_slope.
    #   - :end_slope [Float] optional end transition slope factor for slope-based profile expansion.
    #     If omitted (or :start_slope omitted), falls back to expand_schedule_control_points.
    #
    #   Notes:
    #   - All keys are optional and apply to every matching schedule object in schedule_array.
    #   - When a key is omitted, the method uses the corresponding value from the schedule object.
    #
    #   Expander selection: each profile may set an explicit `expansion` field to
    #   `'control_points'` (use {expand_schedule_control_points}) or `'slope'`
    #   (use {expand_schedule_start_end_slope}). When `expansion` is omitted, the
    #   expander is inferred for back-compatibility: slope iff both start_slope and
    #   end_slope are present, otherwise control points.
    # @param category [String, nil] optional schedule category (`Occupancy`, `Lighting`,
    #   `Equipment`, `Diurnal`). The generalized parametric-schedules file is keyed by
    #   `name` + `category`; when supplied, profiles are matched on both so the same
    #   name can exist under different categories. When nil, matching is by name only.
    # @return [ScheduleRuleset] the resulting schedule ruleset
    def self.create_parametric_schedule_full(model, schedule_array, schedule_name, params, category: nil)
      timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour
      schedule_objs = schedule_array.select do |o|
        o[:name].to_s == schedule_name && (category.nil? || o[:category].to_s == category.to_s)
      end

      if schedule_objs.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "No parametric schedule found for name '#{schedule_name}'#{category.nil? ? '' : " and category '#{category}'"}.")
        return nil
      end

      options = {}
      options['name'] = schedule_objs[0][:name]
      options['rules'] = []
      spillover_sources = []
      schedule_objs.each do |obj|
        base = params[:base].nil? ? obj[:base_std] : params[:base]
        peak = params[:peak].nil? ? obj[:peak_std] : params[:peak]
        start_slope = params[:start_slope].nil? ? obj[:start_slope] : params[:start_slope]
        end_slope = params[:end_slope].nil? ? obj[:end_slope] : params[:end_slope]

        day_types = obj[:day_types].split('|')

        # Weekday vs weekend timing: weekend day types use the weekend building
        # hours when supplied; everything else uses the weekday building hours. The
        # standard timings (st_std/et_std) are the fallback when building hours are not
        # supplied, so standalone expansion (empty params) is unchanged.
        is_weekend = (day_types & %w[Wknd Sat Sun]).any? && (day_types & %w[Default Wkdy]).empty?
        st = if is_weekend
               params[:wknd_st].nil? ? obj[:st_std] : params[:wknd_st]
             else
               params[:st].nil? ? obj[:st_std] : params[:st]
             end
        et = if is_weekend
               params[:wknd_et].nil? ? obj[:et_std] : params[:wknd_et]
             else
               params[:et].nil? ? obj[:et_std] : params[:et]
             end

        # Expand the regular (default/rule) profile at the resolved building hours.
        regular_pairs = OpenstudioStandards::Schedules.expand_parametric_profile(obj, base, peak, st, et, timesteps_per_hour, start_slope: start_slope, end_slope: end_slope)
        next if regular_pairs.nil?

        # Design days are unaffected by building hours: expand them at the standard
        # timing. This is identical to regular_pairs when no building hours are supplied.
        design_pairs =
          if st == obj[:st_std] && et == obj[:et_std]
            regular_pairs
          else
            OpenstudioStandards::Schedules.expand_parametric_profile(obj, base, peak, obj[:st_std], obj[:et_std], timesteps_per_hour, start_slope: start_slope, end_slope: end_slope)
          end

        reduce_pairs = ->(pairs) { pairs.reject.with_index { |e, i| e[1] == pairs[i + 1][1] unless i == (pairs.size - 1) } }
        regular_reduced = reduce_pairs.call(regular_pairs)
        design_reduced = design_pairs.nil? ? regular_reduced : reduce_pairs.call(design_pairs)

        # Capture cross-midnight spillover for control-point profiles so boundary-day
        # rules can be added after all type profiles are assembled. Design-day
        # types do not spill (they are stand-alone peak days).
        if obj[:control_points] && !(day_types & %w[SmrDsn WntrDsn Hol]).any?
          spill = OpenstudioStandards::Schedules.schedule_control_points_spillover(obj, base, peak, st, et, timesteps_per_hour)
          unless spill[:next_day].empty? && spill[:prev_day].empty?
            spillover_sources << { obj: obj, day_types: day_types, next_day: spill[:next_day], prev_day: spill[:prev_day] }
          end
        end

        day_types.each do |day_type|
          case day_type
          when 'Default'
            options['default_day'] = ['default'] + regular_reduced
          when 'WntrDsn'
            options['winter_design_day'] = design_reduced
          when 'SmrDsn'
            options['summer_design_day'] = design_reduced
          when 'Hol'
            # do nothing
          else
            start_date = DateTime.strptime(obj[:start_date]).strftime('%m/%d')
            end_date = DateTime.strptime(obj[:end_date]).strftime('%m/%d')
            rule_a = [day_type]
            rule_a << "#{start_date}-#{end_date}"
            rule_a << day_type
            rule_a += regular_reduced
            options['rules'] << rule_a
          end
        end
      end

      # Cross-day spillover: when a control-point profile runs past midnight (or
      # before hour 0) into a DIFFERENT day type, add a day-specific rule for the boundary
      # calendar day combining the spilled tail with that day's typical profile. Same-type
      # spillover (e.g. Tue->Wed within Wkdy) keeps the in-profile wrap already applied by
      # the expander, so only one extra rule per contiguous run is added. Boundary rules are
      # appended last so they take priority on their single day, leaving all other days of
      # the type unchanged.
      boundary_rules = []
      spillover_sources.each do |src|
        applied = src[:day_types].flat_map { |dt| OpenstudioStandards::Schedules.day_type_applied_days(dt) }.uniq
        next if applied.empty?

        # forward spill lands on the day after an applied day; only act when that day is a
        # different day type (not already part of this profile's applied days)
        unless src[:next_day].empty?
          applied.each do |d|
            nd = OpenstudioStandards::Schedules.next_day_of_week(d)
            next if applied.include?(nd)

            boundary_rules << OpenstudioStandards::Schedules.build_spillover_rule(options, nd, src[:next_day], src[:obj], timesteps_per_hour)
          end
        end
      end
      boundary_rules.each { |r| options['rules'] << r }

      schedule = OpenstudioStandards::Schedules.create_complex_schedule(model, options)
      return schedule
    end

    # Infer start and end times from a time-value profile.
    #
    # @param time_value_pairs [Array] array of [time, value] pairs
    # @param threshold [Float] minimum value considered active
    # @return [Array<Float>] [start_time, end_time]
    def self.infer_start_end_times_from_profile(time_value_pairs, threshold = 0.0)
      active_pairs = time_value_pairs.select { |pair| pair[1].to_f > threshold }
      return [0.0, 24.0] if active_pairs.empty?

      [active_pairs.first[0].to_f, active_pairs.last[0].to_f]
    end

    # Method to derive time-value pairs from a set of time-value pairs. The derived values are determined by applying the given parameters and derivation type.
    #
    # @param derivation_type [String] type of derivation to perform. Options are 'linear', 'exponential', 'exponential-inverse', and 'up_down'
    # @param base [Float] base value for schedule derivation
    # @param peak [Float] peak value for schedule derivation
    # @param response [Float] response factor for schedule derivation, which modifies the influence for non up_down derivation types
    # @param initial_values [Array] array of time value pairs to derive from
    # @param start_slope [Float, nil] optional start slope used by 'up_down'
    # @param end_slope [Float, nil] optional end slope used by 'up_down'
    # @param start_time [Float, nil] optional explicit start time used by 'up_down'
    # @param end_time [Float, nil] optional explicit end time used by 'up_down'
    # @param timesteps_per_hour [Integer] timestep resolution used by 'up_down'
    # @param schedule_name [String, nil] optional schedule name for logging used by 'up_down'
    # @param base_peak_mode [String] 'absolute' (default) rescales the presence source by the
    #   occupancy base/peak so `base`/`peak` are absolute output endpoints; 'relative' uses the
    #   raw presence value (legacy behavior). Does not affect 'up_down' (already absolute).
    # @param occupancy_base [Float, nil] occupancy floor used to normalize presence in absolute
    #   mode; inferred from initial_values.min when nil
    # @param occupancy_peak [Float, nil] occupancy peak used to normalize presence in absolute
    #   mode; inferred from initial_values.max when nil
    # @return [Array] array of derived time value pairs
    def self.derive_values(derivation_type, base, peak, response, initial_values, start_slope: nil, end_slope: nil, start_time: nil, end_time: nil, timesteps_per_hour: 1, schedule_name: nil, base_peak_mode: 'absolute', occupancy_base: nil, occupancy_peak: nil)
      # Guard against inverted inputs (base > peak), which would otherwise produce a negative
      # derivation range. Rather than swapping the two, this collapses them onto a single value:
      # when base is the dominant (> 0.5) input, peak is raised to base; when peak is the small
      # (< 0.5) input, base is lowered to peak. The net effect is a flat profile at the dominant
      # value, which is the intended fallback for malformed base/peak pairs.
      # NOTE: this only fires when base > peak; well-formed inputs (base <= peak) are untouched.
      peak = base if (base > peak) && (base > 0.5)
      base = peak if (peak < base) && (peak < 0.5)

      # Presence normalization. The occupancy presence value fed to the derivation ranges over
      # the occupancy schedule's own base/peak (e.g. 0.25..1.0), not 0..1. In 'absolute' mode
      # (the default) the presence is rescaled from [occupancy_base, occupancy_peak] to [0, 1]
      # so `base`/`peak` are the absolute output endpoints: presence at the occupancy floor maps
      # to `base` and presence at the occupancy peak maps to `peak`. In 'relative' mode (legacy)
      # the raw presence value is used, so the derived base/peak come out relative to the
      # occupancy schedule's base/peak. The occupancy range is taken from occupancy_base/
      # occupancy_peak when supplied, otherwise inferred from the initial_values min/max.
      absolute = base_peak_mode.to_s != 'relative'
      occ_lo = occupancy_base
      occ_hi = occupancy_peak
      if absolute && !initial_values.empty?
        vals = initial_values.map { |p| p[1] }
        occ_lo = vals.min if occ_lo.nil?
        occ_hi = vals.max if occ_hi.nil?
      end
      occ_range = (occ_lo.nil? || occ_hi.nil?) ? nil : (occ_hi.to_f - occ_lo.to_f)
      presence = lambda do |v|
        return v unless absolute
        # flat occupancy (or unknown range): fall back to the raw value so design days and
        # constant profiles behave as before.
        return v.to_f.clamp(0.0, 1.0) if occ_range.nil? || occ_range.abs < 1e-9

        ((v.to_f - occ_lo) / occ_range).clamp(0.0, 1.0)
      end

      # derive time-value pairs
      derived_pairs = []
      case derivation_type
      when 'linear'
        initial_values.each do |initial_pair|
          derived_value = base + ((peak - base) * (presence.call(initial_pair[1]) * response))
          derived_pairs << [initial_pair[0], derived_value]
        end
      when 'exponential'
        initial_values.each do |initial_pair|
          derived_value = base + ((peak - base) * (presence.call(initial_pair[1])**response.to_f))
          derived_pairs << [initial_pair[0], derived_value]
        end
      when 'exponential-inverse'
        initial_values.each do |initial_pair|
          derived_value = base + ((peak - base) * (presence.call(initial_pair[1])**(1 / response.to_f)))
          derived_pairs << [initial_pair[0], derived_value]
        end
      when 'up_down'
        if start_slope.nil? || end_slope.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Cannot derive 'up_down' schedule#{schedule_name.nil? ? '' : " '#{schedule_name}'"} without start_slope and end_slope.")
          return []
        end

        st = start_time
        et = end_time
        if st.nil? || et.nil?
          st, et = OpenstudioStandards::Schedules.infer_start_end_times_from_profile(initial_values)
        end

        slope_schedule_data = {
          name: schedule_name || 'derived up_down schedule',
          start_slope: start_slope,
          end_slope: end_slope
        }

        derived_pairs = OpenstudioStandards::Schedules.expand_schedule_start_end_slope(
          slope_schedule_data,
          base,
          peak,
          st,
          et,
          timesteps_per_hour
        )

        return [] if derived_pairs.nil?
      end
      return derived_pairs
    end

    # Build a diurnal gate from a named `category: Diurnal` curve. Returns a
    # lambda that gates occupancy [time, value] pairs by the time-of-day awake/asleep
    # signal d(t): presence' = presence * gate, where gate = 1 - weight*d
    # (`off_when_asleep`, e.g. room lights low while occupants sleep) or weight*d
    # (`on_when_asleep`, e.g. night security lighting). The gate is sampled at timestep
    # resolution so it suppresses occupancy even inside flat overnight presence regions.
    # Returns nil when no diurnal profile is requested or the curve is missing.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param diurnal_profile [String, nil] name of a category: Diurnal profile
    # @param diurnal_mode [String] 'off_when_asleep' (default) or 'on_when_asleep'
    # @param diurnal_weight [Float] intensity in [0, 1]; 1.0 = full gate, 0.0 = none
    # @param timesteps_per_hour [Integer] number of timesteps per hour
    # @return [Proc, nil] lambda(occ_pairs) -> gated [time, value] pairs, or nil
    def self.build_diurnal_gate(model, diurnal_profile, diurnal_mode, diurnal_weight, timesteps_per_hour)
      return nil if diurnal_profile.nil?

      parametric_schedules = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_parametric_schedules.json"), symbolize_names: true)
      diurnal_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, parametric_schedules, diurnal_profile, {}, category: 'Diurnal')
      if diurnal_sch.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules', "Diurnal profile '#{diurnal_profile}' not found; skipping diurnal modifier.")
        return nil
      end

      dday = diurnal_sch.defaultDaySchedule
      dpairs = dday.times.map(&:totalHours).zip(dday.values)
      on_when_asleep = diurnal_mode.to_s == 'on_when_asleep'
      step = 1.0 / timesteps_per_hour
      steps = 24 * timesteps_per_hour

      # precompute the gate value at each timestep
      gate_values = (0...steps).map do |k|
        d = OpenstudioStandards::Schedules.profile_value_at(dpairs, k * step)
        g = on_when_asleep ? (diurnal_weight * d) : (1.0 - (diurnal_weight * d))
        g.clamp(0.0, 1.0)
      end

      lambda do |occ_pairs|
        (0...steps).map do |k|
          t = (k * step).round(6)
          [t, OpenstudioStandards::Schedules.profile_value_at(occ_pairs, t) * gate_values[k]]
        end
      end
    end

    # Add a schedule derived from an occupancy schedule and parametric inputs. The derived schedule is created by modifying the occupancy schedule time-value pairs according to the given parameters.
    #
    # @param occupancy_schedule [OpenStudio::Model::ScheduleRuleset] input occupancy schedule to derive information from
    # @param params [Hash] hash of schedule input parameters.
    #   Supported keys include:
    #   - :derivation_type [String] required; one of 'linear', 'exponential', 'exponential-inverse', 'up_down'
    #   - :base [Float] required
    #   - :peak [Float] required
    #   - :response [Float] required for non up_down derivation types
    #   - :base_peak_mode [String] optional 'absolute' (default) or 'relative'. In 'absolute'
    #     mode base/peak are absolute output endpoints (the presence is rescaled by the
    #     occupancy schedule's base/peak); 'relative' is the legacy behavior.
    #   - :start_slope [Float] required for up_down
    #   - :end_slope [Float] required for up_down
    #   - :st [Float] optional explicit start time for up_down
    #   - :et [Float] optional explicit end time for up_down
    #   - :diurnal_profile [String] optional name of a category: Diurnal curve to gate the
    #     presence source before derivation. Not applied to design days.
    #   - :diurnal_mode [String] optional 'off_when_asleep' (default) or 'on_when_asleep'
    #   - :diurnal_weight [Float] optional intensity in [0, 1]; default 1.0
    # @return [ScheduleRuleset] the resulting schedule ruleset
    def self.create_derived_schedule_from_occupancy_schedule(occupancy_schedule, params)
      # get model object from existing schedule
      model = occupancy_schedule.model
      timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour

      # diurnal modifier: gates the presence source for the default/rule days (not design
      # days) so derived loads can diverge from occupancy by a time-of-day signal
      diurnal_gate = OpenstudioStandards::Schedules.build_diurnal_gate(model, params[:diurnal_profile], params[:diurnal_mode] || 'off_when_asleep', params[:diurnal_weight].nil? ? 1.0 : params[:diurnal_weight], timesteps_per_hour)

      # get values from params
      derivation_type = params[:derivation_type]
      base = params[:base]
      peak = params[:peak]
      response = params[:response]
      start_slope = params[:start_slope]
      end_slope = params[:end_slope]
      derivation_start_time = params[:st]
      derivation_end_time = params[:et]
      winter_design_day_base = params[:winter_design_day_base].nil? ? base : params[:winter_design_day_base]
      winter_design_day_peak = params[:winter_design_day_peak].nil? ? peak : params[:winter_design_day_peak]
      winter_design_day_response = params[:winter_design_day_response].nil? ? response : params[:winter_design_day_response]
      summer_design_day_base = params[:summer_design_day_base].nil? ? base : params[:summer_design_day_base]
      summer_design_day_peak = params[:summer_design_day_peak].nil? ? peak : params[:summer_design_day_peak]
      summer_design_day_response = params[:summer_design_day_response].nil? ? response : params[:summer_design_day_response]

      # base/peak interpretation: 'absolute' (default) rescales the occupancy presence by the
      # occupancy schedule's own base/peak so the derived base/peak are absolute output values;
      # 'relative' keeps the legacy behavior. The occupancy range is the occupancy schedule's
      # realized default-day min/max (its base/peak), applied uniformly to the default, rule,
      # and design-day derivations so a single occupancy peak maps to the load peak everywhere.
      base_peak_mode = params[:base_peak_mode].nil? ? 'absolute' : params[:base_peak_mode]
      occ_default_values = occupancy_schedule.defaultDaySchedule.values
      occupancy_base = occ_default_values.empty? ? nil : occ_default_values.min
      occupancy_peak = occ_default_values.empty? ? nil : occ_default_values.max

      # create a new schedule ruleset
      derived_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
      derived_schedule.setName(params[:name])

      # create default day schedules
      default_occ_day_sch = occupancy_schedule.defaultDaySchedule
      default_occ_times = default_occ_day_sch.times.map(&:totalHours)
      occ_time_values = default_occ_times.zip(default_occ_day_sch.values)
      occ_time_values = diurnal_gate.call(occ_time_values) unless diurnal_gate.nil?
      derived_pairs = OpenstudioStandards::Schedules.derive_values(
        derivation_type, base, peak, response, occ_time_values,
        start_slope: start_slope, end_slope: end_slope,
        start_time: derivation_start_time, end_time: derivation_end_time,
        timesteps_per_hour: timesteps_per_hour, schedule_name: params[:name],
        base_peak_mode: base_peak_mode, occupancy_base: occupancy_base, occupancy_peak: occupancy_peak
      )
      default_day = derived_schedule.defaultDaySchedule
      default_day.setName("#{params[:name]} Default Day")
      OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(default_day, derived_pairs)

      # create summer design day schedule
      smr_occ_day_sch = occupancy_schedule.summerDesignDaySchedule
      smr_occ_times = smr_occ_day_sch.times.map(&:totalHours)
      occ_time_values = smr_occ_times.zip(smr_occ_day_sch.values)
      derived_pairs = OpenstudioStandards::Schedules.derive_values(
        derivation_type, summer_design_day_base, summer_design_day_peak, summer_design_day_response, occ_time_values,
        start_slope: start_slope, end_slope: end_slope,
        start_time: derivation_start_time, end_time: derivation_end_time,
        timesteps_per_hour: timesteps_per_hour, schedule_name: params[:name],
        base_peak_mode: base_peak_mode, occupancy_base: occupancy_base, occupancy_peak: occupancy_peak
      )
      summer_day = OpenStudio::Model::ScheduleDay.new(model)
      summer_day.setName("#{params[:name]} Summer Design Day")
      OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(summer_day, derived_pairs)
      derived_schedule.setSummerDesignDaySchedule(summer_day)

      # create winter design day schedule
      wnt_occ_day_sch = occupancy_schedule.winterDesignDaySchedule
      wnt_occ_times = wnt_occ_day_sch.times.map(&:totalHours)
      occ_time_values = wnt_occ_times.zip(wnt_occ_day_sch.values)
      derived_pairs = OpenstudioStandards::Schedules.derive_values(
        derivation_type, winter_design_day_base, winter_design_day_peak, winter_design_day_response, occ_time_values,
        start_slope: start_slope, end_slope: end_slope,
        start_time: derivation_start_time, end_time: derivation_end_time,
        timesteps_per_hour: timesteps_per_hour, schedule_name: params[:name],
        base_peak_mode: base_peak_mode, occupancy_base: occupancy_base, occupancy_peak: occupancy_peak
      )
      winter_day = OpenStudio::Model::ScheduleDay.new(model)
      winter_day.setName("#{params[:name]} Winter Design Day")
      OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(winter_day, derived_pairs)
      derived_schedule.setWinterDesignDaySchedule(winter_day)

      # get rules from existing schedule
      occupancy_schedule.scheduleRules.each do |rule|
        # get occ schedule time value pairs
        occ_day_sch = rule.daySchedule
        occ_times = occ_day_sch.times.map(&:totalHours)
        occ_time_values = occ_times.zip(occ_day_sch.values)
        occ_time_values = diurnal_gate.call(occ_time_values) unless diurnal_gate.nil?

        # derive time-value pairs
        derived_pairs = OpenstudioStandards::Schedules.derive_values(
          derivation_type, base, peak, response, occ_time_values,
          start_slope: start_slope, end_slope: end_slope,
          start_time: derivation_start_time, end_time: derivation_end_time,
          timesteps_per_hour: timesteps_per_hour, schedule_name: params[:name],
          base_peak_mode: base_peak_mode, occupancy_base: occupancy_base, occupancy_peak: occupancy_peak
        )

        # Make the Rule
        sch_rule = OpenStudio::Model::ScheduleRule.new(derived_schedule)
        sch_rule.setName("#{rule.name} Derived #{params[:category]} Rule")
        day_sch = sch_rule.daySchedule
        day_sch.setName("#{rule.name} Derived #{params[:category]} Day Sch")
        OpenstudioStandards::Schedules.add_time_value_pairs_to_schedule(day_sch, derived_pairs)

        # Set the dates when the rule applies
        sch_rule.setStartDate(rule.startDate.get) if rule.startDate.is_initialized
        sch_rule.setEndDate(rule.endDate.get) if rule.endDate.is_initialized

        # Set the days when the rule applies
        sch_rule.setApplyMonday(rule.applyMonday) if rule.applyMonday
        sch_rule.setApplyTuesday(rule.applyTuesday) if rule.applyTuesday
        sch_rule.setApplyWednesday(rule.applyWednesday) if rule.applyWednesday
        sch_rule.setApplyThursday(rule.applyThursday) if rule.applyThursday
        sch_rule.setApplyFriday(rule.applyFriday) if rule.applyFriday
        sch_rule.setApplySaturday(rule.applySaturday) if rule.applySaturday
        sch_rule.setApplySunday(rule.applySunday) if rule.applySunday

        # add params to schedule additional properties
        props = day_sch.additionalProperties
        props.setFeature('base', base)
        props.setFeature('peak', peak)
        props.setFeature('response', response)
        props.setFeature('derived_from', rule.name.get)
      end

      return derived_schedule
    end

    # Resolve a load schedule reference to either a DIRECT parametric schedule (a
    # parametric-schedules entry matching name + category, built via
    # {create_parametric_schedule_full}) or an occupancy-DERIVED schedule (a derivation
    # parameter set transformed from the occupancy schedule). Selection is by which
    # file/category the name resolves to: a name found among the parametric schedules of
    # the given category is built directly; otherwise it is derived from the occupancy
    # schedule. Direct loads inherit the building hours, offsets, and adjustment mode for
    # free; derived loads require an occupancy schedule.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param parametric_schedules [Array] loaded parametric-schedules data
    # @param name [String, nil] the load schedule/parameter reference
    # @param category [String] direct-lookup category ('Lighting' or 'Equipment')
    # @param derived_data_path [String] path to the derivation parameter JSON
    # @param occupancy_sch [OpenStudio::Model::ScheduleRuleset, nil] occupancy schedule for derivation
    # @param params [Hash] expansion params (st/et/offsets) applied to direct schedules
    # @param derived_timing [Hash] timing carried into derived loads
    # @param load_override [Hash] runtime override fields merged last (highest precedence)
    # @return [OpenStudio::Model::ScheduleRuleset, nil] the resulting schedule, or nil
    def self.resolve_load_schedule(model, parametric_schedules, name, category, derived_data_path, occupancy_sch, params, derived_timing, load_override = {})
      return nil if name.nil?

      load_override ||= {}

      # Direct path: the reference resolves to a parametric schedule of this category.
      if parametric_schedules.any? { |o| o[:name].to_s == name.to_s && o[:category].to_s == category }
        return OpenstudioStandards::Schedules.create_parametric_schedule_full(model, parametric_schedules, name, params.merge(load_override), category: category)
      end

      # Derived path: transform the occupancy schedule using its derivation parameters.
      if occupancy_sch.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules', "Load schedule '#{name}' is not a direct parametric schedule and there is no occupancy schedule to derive it from; skipping.")
        return nil
      end

      data = JSON.parse(File.read(derived_data_path), symbolize_names: true)
      load_params = data.find { |s| s[:name] == name }
      if load_params.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Could not find load derivation parameters '#{name}'.")
        return nil
      end

      # precedence: runtime override (load_override) > standard JSON params
      OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occupancy_sch, load_params.merge(derived_timing).merge(load_override))
    end

    # Resolve runtime schedule overrides for one space use into a merged hash of
    # per-section override fields. An override entry is keyed by `space_type`
    # (matched against either the schedule set name or the standards space type) or the
    # `"*"` wildcard. The wildcard is applied first and a specific match second, so a
    # specific entry's fields win. Precedence overall: override > building hours + offsets > standard.
    #
    # @param schedule_overrides [Array<Hash>, nil] caller-supplied overrides
    # @param schedule_set_name [String, nil] resolved schedule set name
    # @param standards_space_type [String, nil] resolved standards space type
    # @param section_keys [Array<Symbol>] override section names to merge. Defaults to the
    #   parametric schedule sections; CreateTypical.space_type_apply_load_overrides passes
    #   its internal load sections instead.
    # @return [Hash] merged overrides, e.g. { occupancy: {...}, lighting: {...}, ... }
    def self.resolve_schedule_overrides(schedule_overrides, schedule_set_name, standards_space_type,
                                        section_keys: %i[occupancy lighting electric_equipment gas_equipment hot_water_equipment])
      return {} if schedule_overrides.nil? || schedule_overrides.empty?

      key_fields = %i[space_type schedule_set standards_space_type]
      merged = {}

      [['*'], [schedule_set_name, standards_space_type].compact.map(&:to_s)].each do |match_keys|
        entry = schedule_overrides.find do |o|
          entry_key = key_fields.map { |kf| o[kf] }.compact.first.to_s
          match_keys.include?(entry_key)
        end
        next if entry.nil?

        section_keys.each do |sk|
          next unless entry[sk].is_a?(Hash)

          merged[sk] = (merged[sk] || {}).merge(entry[sk])
        end
      end

      merged
    end

    # Sets the schedules for the selected internal loads to typical schedules.
    # Uses parametric formulations for the occupancy schedule and derives interior lighting and equipment schedules from the occupancy schedule. If set_people is false, the occupancy schedule will not be applied but will still be used as the basis for deriving the lighting and equipment schedules.
    #
    # @param space_type [OpenStudio::Model::SpaceType] space type object
    # @param set_people [Boolean] if true, set the occupancy and activity schedules
    # @param set_lights [Boolean] if true, set the interior lighting schedule
    # @param set_electric_equipment [Boolean] if true, set the electric schedule schedule
    # @param set_gas_equipment [Boolean] if true, set the gas equipment schedule
    # @param set_hot_water_equipment [Boolean] if true, set the hot water equipment schedule
    # @param wkdy_start_time [Float, nil] building weekday hours-of-operation start time (decimal hours).
    #   When supplied, all space schedules shift to the building's weekday hours (plus this space
    #   use's authored offsets); when nil, the standalone st_std/et_std standards are used.
    # @param wkdy_duration [Float, nil] building weekday hours-of-operation duration (decimal hours).
    # @param wknd_start_time [Float, nil] building weekend hours-of-operation start time (decimal hours).
    # @param wknd_duration [Float, nil] building weekend hours-of-operation duration (decimal hours).
    # @param schedule_overrides [Array<Hash>, nil] runtime overrides. Each entry is
    #   keyed by `space_type` (matched against the schedule set name or standards space type) or `"*"`,
    #   with optional `occupancy`/`lighting`/`electric_equipment`/`gas_equipment`/`hot_water_equipment`
    #   field hashes that override the standard params at field granularity (precedence: override >
    #   building hours + offsets > standard).
    # @return [Boolean] returns true if successful, false if not
    def self.space_type_apply_parametric_internal_load_schedules(space_type, set_people: true, set_lights: true, set_electric_equipment: true, set_gas_equipment: true, set_hot_water_equipment: true,
                                                                 wkdy_start_time: nil, wkdy_duration: nil, wknd_start_time: nil, wknd_duration: nil, schedule_overrides: nil)
      # Get the default schedule set or create a new one if none exists
      default_sch_set = nil
      if space_type.defaultScheduleSet.is_initialized
        default_sch_set = space_type.defaultScheduleSet.get
      else
        default_sch_set = OpenStudio::Model::DefaultScheduleSet.new(space_type.model)
        default_sch_set.setName("#{space_type.name} Schedule Set")
        space_type.setDefaultScheduleSet(default_sch_set)
      end

      # Load the default schedule set information
      default_parametric_sch_set = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_parametric_schedule_set.json"), symbolize_names: true)

      # Get the default parametric schedule set for this space type
      standards_building_type = nil
      if space_type.standardsBuildingType.is_initialized
        standards_building_type = space_type.standardsBuildingType.get
      end

      if space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized
        schedule_set_name = space_type.additionalProperties.getFeatureAsString('schedule_set').get
        possible_schedule_sets = default_parametric_sch_set.select { |s| s[:schedule_set_name] == schedule_set_name }

        if standards_building_type.nil?
          space_type_properties = possible_schedule_sets.find { |s| s[:standards_building_type].nil? }
        else
          space_type_properties = possible_schedule_sets.find { |s| s[:standards_building_type] == standards_building_type }
          space_type_properties = possible_schedule_sets.find { |s| s[:standards_building_type].nil? } if space_type_properties.nil?
        end

        space_type_properties = possible_schedule_sets[0] if space_type_properties.nil?

        if space_type_properties.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Unable to find schedule set '#{schedule_set_name}' for #{space_type.name} with standards building type '#{standards_building_type}'.")
          return false
        end
      else
        standards_space_type = 'not defined'
        if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
          standards_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
        end

        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Unable to find schedule set for #{space_type.name} with standards space type '#{standards_space_type}'. Please ensure the space type additional property 'schedule_set' is set to a valid schedule set name. Refer to the documentation for more information on parametric schedule sets.")
        return false
      end

      # Resolve runtime overrides for this space use. Standards space type
      # is used (alongside the schedule set name) to match override entries.
      override_standards_space_type = nil
      if space_type.additionalProperties.getFeatureAsString('standards_space_type').is_initialized
        override_standards_space_type = space_type.additionalProperties.getFeatureAsString('standards_space_type').get
      end
      overrides = OpenstudioStandards::Schedules.resolve_schedule_overrides(schedule_overrides, schedule_set_name, override_standards_space_type)

      # Build expansion params from the building hours of operation plus this space
      # use's authored offsets. When building hours are not supplied,
      # params stay empty and expansion falls back to the standalone st_std/et_std.
      start_time_offset = space_type_properties[:start_time_offset].nil? ? 0.0 : space_type_properties[:start_time_offset]
      end_time_offset = space_type_properties[:end_time_offset].nil? ? 0.0 : space_type_properties[:end_time_offset]
      occ_params = {}
      unless wkdy_start_time.nil? || wkdy_duration.nil?
        occ_params[:st] = wkdy_start_time + start_time_offset
        occ_params[:et] = wkdy_start_time + wkdy_duration + end_time_offset
      end
      unless wknd_start_time.nil? || wknd_duration.nil?
        occ_params[:wknd_st] = wknd_start_time + start_time_offset
        occ_params[:wknd_et] = wknd_start_time + wknd_duration + end_time_offset
      end

      # An occupancy override wins over building hours + offsets and the standards.
      occ_params = occ_params.merge(overrides[:occupancy]) if overrides[:occupancy].is_a?(Hash)

      # Timing carried into derived loads (used by the 'up_down' derivation; other
      # derivation types inherit timing from the occupancy schedule they transform).
      derived_timing = {}
      derived_timing[:st] = occ_params[:st] unless occ_params[:st].nil?
      derived_timing[:et] = occ_params[:et] unless occ_params[:et].nil?

      # Find occupancy schedule. The generalized parametric-schedules file is keyed
      # by name + category, so match on the Occupancy category explicitly. A null
      # occupancy schedule (not-regularly-occupied sets) is expected; those loads use
      # the direct path below.
      parametric_schedules = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/default_parametric_schedules.json"), symbolize_names: true)
      occupancy_sch = nil
      unless space_type_properties[:occupancy_schedule].nil?
        occupancy_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(space_type.model, parametric_schedules, space_type_properties[:occupancy_schedule], occ_params, category: 'Occupancy')
      end

      # Add occupancy schedule to the default schedule set. Not-regularly-occupied sets
      # have a null occupancy schedule (their loads use the direct path below), so skip
      # people and the activity schedule when there is no occupancy.
      if set_people && !occupancy_sch.nil?
        default_sch_set.setNumberofPeopleSchedule(occupancy_sch)

        # Set the activity schedule. Use a default 120 W/person
        occupancy_activity_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(space_type.model, 120.0, name: "#{space_type.name} Occupant Activity Schedule")
        default_sch_set.setPeopleActivityLevelSchedule(occupancy_activity_sch)
      end

      data_dir = "#{File.dirname(__FILE__)}/data"

      # Interior lighting: direct parametric schedule or occupancy-derived parameters
      if set_lights && !space_type_properties[:derived_interior_lighting_parameters].nil?
        light_sch = OpenstudioStandards::Schedules.resolve_load_schedule(space_type.model, parametric_schedules, space_type_properties[:derived_interior_lighting_parameters], 'Lighting', "#{data_dir}/default_lighting_parameters.json", occupancy_sch, occ_params, derived_timing, overrides[:lighting] || {})
        default_sch_set.setLightingSchedule(light_sch) unless light_sch.nil?
      end

      # Electric equipment
      if set_electric_equipment && !space_type_properties[:derived_electric_equipment_parameters].nil?
        equip_sch = OpenstudioStandards::Schedules.resolve_load_schedule(space_type.model, parametric_schedules, space_type_properties[:derived_electric_equipment_parameters], 'Equipment', "#{data_dir}/default_electric_equipment_parameters.json", occupancy_sch, occ_params, derived_timing, overrides[:electric_equipment] || {})
        default_sch_set.setElectricEquipmentSchedule(equip_sch) unless equip_sch.nil?
      end

      # Gas equipment
      if set_gas_equipment && !space_type_properties[:derived_gas_equipment_parameters].nil?
        gas_sch = OpenstudioStandards::Schedules.resolve_load_schedule(space_type.model, parametric_schedules, space_type_properties[:derived_gas_equipment_parameters], 'Equipment', "#{data_dir}/default_gas_equipment_parameters.json", occupancy_sch, occ_params, derived_timing, overrides[:gas_equipment] || {})
        default_sch_set.setGasEquipmentSchedule(gas_sch) unless gas_sch.nil?
      end

      # Hot water equipment
      if set_hot_water_equipment && !space_type_properties[:derived_hot_water_equipment_parameters].nil?
        hot_water_sch = OpenstudioStandards::Schedules.resolve_load_schedule(space_type.model, parametric_schedules, space_type_properties[:derived_hot_water_equipment_parameters], 'Equipment', "#{data_dir}/default_hot_water_equipment_parameters.json", occupancy_sch, occ_params, derived_timing, overrides[:hot_water_equipment] || {})
        default_sch_set.setHotWaterEquipmentSchedule(hot_water_sch) unless hot_water_sch.nil?
      end

      return true
    end
  end
end
