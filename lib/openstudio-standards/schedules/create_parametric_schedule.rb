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
    # @param cyclic [Boolean] treat the pairs as one day of a repeating profile, so the run
    #   after the last anchor interpolates into the first anchor of the next day instead of
    #   being held flat to hour 24. Off by default: the slope expander passes bare ramp
    #   segments that are assembled elsewhere and must keep the flat padding.
    # @return [<Array>] Returns an expanded array of 24 time value pairs
    def self.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour, easing: nil, cyclic: false)
      easing ||= method(:smootherstep_easing)
      return_arry = []

      # A repeating profile closes on itself: the run after the last anchor leads into the
      # first anchor of the NEXT day, so hour 24 sits partway along a real segment. Padding
      # with a copy of the last value (and hour 0 with a copy of the first) held both sides
      # of midnight flat and left a step between them at the day boundary. Closing the
      # cycle instead puts the interpolated value on hour 24 and carries the rest of the
      # segment into the early hours.
      wrap_span = (time_value_pairs[0][0] + 24.0) - time_value_pairs[-1][0]
      close_cycle = cyclic && wrap_span.positive? && wrap_span < 24.0

      if close_cycle
        time_value_pairs = time_value_pairs + [[time_value_pairs[0][0] + 24.0, time_value_pairs[0][1]]]
      else
        if time_value_pairs[0][0] != 0
          time_value_pairs.unshift([0, time_value_pairs[0][1]])
        end
        if time_value_pairs[-1][0] < 24
          time_value_pairs << [24, time_value_pairs[-1][1]]
        end
      end

      last_time = time_value_pairs[-1][0]

      time_value_pairs.each_cons(2) do |this_pair, next_pair|
        this_time = this_pair[0].to_f
        this_val = this_pair[1]
        next_time = next_pair[0].to_f
        next_val = next_pair[1]

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

      return return_arry unless close_cycle

      # Bring the part of the closing segment that ran past midnight back onto the day.
      # Its final sample lands on the first anchor, which the interior loop already
      # emitted, so collapse the duplicate.
      folded = return_arry.map { |time, val| [time > 24.0 ? (time - 24.0).round(9) : time, val] }
      OpenstudioStandards::Schedules.collapse_coincident_times(folded.sort_by { |pair| pair[0] })
    end

    # Wrap time value pairs to 24 hours
    #
    # Times outside 0..24 are folded back onto the day in either direction. Folding the
    # low side matters once a profile is anchored on its occupied window: a short occupied
    # day leaves a long overnight pad, and the pad points ahead of the window land before
    # hour 0. Left unfolded they reach {add_time_value_pairs_to_schedule}, which builds an
    # OpenStudio::Time from a negative hour.
    #
    # @param time_value_pairs [Array] array of time value pairs
    # @return [Array] array of wrapped time value pairs
    def self.wrap_schedule_pairs(time_value_pairs)
      # divide the time value pairs at 0 and 24 hours
      wrap_group = []
      normal_group = []

      time_value_pairs.each do |time, value|
        if time >= 24
          wrap_group << [time - 24.0, value]
        end
        if time.negative?
          wrap_group << [time + 24.0, value]
        end
        if time >= 0 && time <= 24.0
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

    # Parser for a control-point token: an anchor name (st/et/base/peak) with an optional
    # arithmetic modifier, e.g. 'st-1', 'et+6', 'peak*0.5'.
    CONTROL_POINT_PARSER = /([a-z]+)(?:([+\-*])(\d+(?:\.\d+)?))?/.freeze

    # Default width, in hours, of the rigid region held immediately outside the occupied
    # window. One hour is what the authored data overwhelmingly uses for the arrival and
    # departure ramps ('st-1' and 'et+1'). Overridable per profile via a `shoulder` field.
    CONTROL_POINT_SHOULDER_HOURS = 1.0

    # Absolute standard time of a control-point time token, i.e. where the point sits when
    # the profile is expanded at its own st_std/et_std. Offsets are read in real hours and
    # are NOT scaled here - scaling is the time warp's job.
    #
    # @param token [String] control-point time token, e.g. 'st-1' or 'et+6'
    # @param st_std [Float] standard start time
    # @param et_std [Float] standard end time
    # @return [Float] absolute time in standard coordinates
    def self.control_point_standard_time(token, st_std, et_std)
      time_point = token.scan(CONTROL_POINT_PARSER)[0]
      time = time_point[0] == 'et' ? et_std.to_f : st_std.to_f
      time = time.send(time_point[1], time_point[2].to_f) unless time_point[1].nil? && time_point[2].nil?
      time
    end

    # Build the map from standard-time coordinates to the requested [start_time, end_time]
    # timing, as a monotone piecewise-linear function on the 24 h circle.
    #
    # Scaling each control point's offset off its own anchor - the previous approach -
    # stretches the padding as hard as the occupied hours, so the mapped profile covers
    # more than a day and then interferes with itself: expanding office occupancy
    # (st_std 8, et_std 17) to st 8.25 / et 21 pushed 'et+7' to hour 31, which
    # {wrap_schedule_pairs} folded onto 07:00 as a notch in a ramp climbing to peak, and
    # pushed 'st-8' to -3.0, below the start of the day. The arrival and departure ramps
    # widened with the duration for the same reason.
    #
    # Warping every point through ONE monotone map removes all of that by construction:
    # order is preserved, the ramps keep their authored width, and the mapped profile
    # spans exactly 24 h rather than the 34 h that a 1.4x multiplier produced.
    #
    # Four arcs, all pinned so W(st_std) == start_time and W(et_std) == end_time:
    #   [st_std - h, st_std] -> [st - h, st]   rigid, keeps the arrival ramp's real width
    #   [st_std, et_std]     -> [st, et]       elastic, the occupied shape stretches here
    #   [et_std, et_std + h] -> [et, et + h]   rigid, keeps the departure ramp's real width
    #   the remaining pad    -> the rest       elastic, absorbs all the leftover slack
    #
    # @param st_std [Float] standard start time
    # @param et_std [Float] standard end time
    # @param start_time [Float] requested start time
    # @param end_time [Float] requested end time
    # @param shoulder [Float] width in hours of the rigid region outside each window edge
    # @return [Proc] lambda(standard_time) -> actual time
    def self.control_point_time_warp(st_std, et_std, start_time, end_time, shoulder: CONTROL_POINT_SHOULDER_HOURS)
      st_std = st_std.to_f
      et_std = et_std.to_f
      st = start_time.to_f
      et = end_time.to_f
      et_std += 24.0 if et_std <= st_std
      et += 24.0 if et <= st

      duration_std = et_std - st_std
      duration = et - st

      # A profile that already fills the day (design days run 0..24) has no unoccupied
      # hours to hold fixed, so a plain affine scale is the only map available.
      if duration_std >= 24.0 || duration >= 24.0
        ratio = duration / duration_std
        return ->(time) { st + ((time - st_std) * ratio) }
      end

      # Shoulders are rigid, so they can never claim more room than the unoccupied hours
      # leave - in the standard timing or in the requested one.
      rigid = [shoulder.to_f, (24.0 - duration_std) / 2.0, (24.0 - duration) / 2.0].min
      rigid = 0.0 if rigid.negative?

      # Knots on the standard circle -> knots on the actual circle. Both lists are
      # non-decreasing and span exactly 24 h, which is what makes the map monotone and
      # 24-periodic: control points cannot cross, invert, or wrap past one another.
      src = [st_std - rigid, st_std, et_std, et_std + rigid, st_std - rigid + 24.0]
      dst = [st - rigid,     st,     et,     et + rigid,     st - rigid + 24.0]

      lambda do |time|
        # Fold onto one turn of the standard circle, keeping the turn count so a point
        # authored past midnight keeps its own next-day (or previous-day) representative.
        turns = ((time - src.first) / 24.0).floor
        folded = time - (24.0 * turns)
        i = src.each_cons(2).find_index { |lower, upper| folded <= upper } || (src.length - 2)
        span = src[i + 1] - src[i]
        fraction = span.abs < 1e-9 ? 0.0 : (folded - src[i]) / span
        dst[i] + (fraction * (dst[i + 1] - dst[i])) + (24.0 * turns)
      end
    end

    # Compress the unoccupied padding of an over-specified profile so its control points
    # span no more than 24 hours in standard coordinates.
    #
    # A handful of authored profiles pad generously on both sides - the airport concourse
    # profile runs st_std 5 / et_std 23 yet places points at 'st-8' and 'et+6', 32 hours of
    # coverage for a 24 hour day. Those pads wrap through the occupied window and no
    # ordering of them is meaningful. The excess is taken out of the two pads in proportion
    # to their size, which keeps the shape of each pad and leaves everything between
    # st_std and et_std untouched.
    #
    # @param standard_times [Array<Float>] control-point times in standard coordinates
    # @param st_std [Float] standard start time
    # @param et_std [Float] standard end time
    # @return [Array<Float>] times spanning at most 24 hours
    def self.compress_standard_span(standard_times, st_std, et_std)
      low, high = standard_times.minmax
      excess = (high - low) - 24.0
      return standard_times if excess <= 0.0

      pre = [st_std - low, 0.0].max
      post = [high - et_std, 0.0].max
      total = pre + post
      # the occupied window alone covers the day; there is no padding to give back
      return standard_times if total <= 0.0

      pre_scale = pre.zero? ? 1.0 : [pre - (excess * pre / total), 0.0].max / pre
      post_scale = post.zero? ? 1.0 : [post - (excess * post / total), 0.0].max / post

      standard_times.map do |time|
        if time < st_std
          st_std - ((st_std - time) * pre_scale)
        elsif time > et_std
          et_std + ((time - et_std) * post_scale)
        else
          time
        end
      end
    end

    # Collapse anchors that round onto the same timestep, keeping the last value authored
    # there. Two distinct anchors can land on one timestep once the unoccupied pad
    # compresses; leaving both would hand {smooth_schedule_from_time_values} a zero-width
    # segment to interpolate across.
    #
    # @param time_value_pairs [Array] sorted [time, value] pairs
    # @return [Array] pairs with coincident times collapsed
    def self.collapse_coincident_times(time_value_pairs)
      time_value_pairs.each_with_object([]) do |(time, val), collapsed|
        if !collapsed.empty? && (collapsed[-1][0] - time).abs < 1e-9
          collapsed[-1][1] = val
        else
          collapsed << [time, val]
        end
      end
    end

    # Resolve the base and peak a profile expands against, given caller overrides.
    #
    # Three ways to state them, in increasing precedence:
    #   nothing            the profile's own authored base and peak
    #   :base / :peak      absolute values
    #   :base_peak_ratio   the base as a fraction of the peak, which is the quantity that
    #                      is usually sampled -- a stock's lighting base-to-peak ratio is a
    #                      ratio precisely because peak varies by space type, so an absolute
    #                      base cannot express it across a whole building
    #
    # Each has a weekend counterpart (:wknd_base, :wknd_peak, :wknd_base_peak_ratio) used
    # for the Sat/Sun/Wknd profiles, matching how :wknd_st and :wknd_et already work.
    # Weekends fall back to the weekday value when no weekend override is given, so a
    # caller that speaks only of the building as a whole still gets a consistent schedule.
    #
    # Two further behaviours, both off unless asked for:
    #   :cap_wknd_base_at_wkdy  hold the weekend base at or below the weekday base. A caller
    #                           sampling the two ratios independently can draw a weekend
    #                           ratio above its weekday one; whether that should mean a
    #                           higher unoccupied weekend load is a modelling question, and
    #                           this is how a caller says no. The comparison is on the
    #                           resolved values, not the ratios, since weekday and weekend
    #                           profiles can carry different peaks.
    #
    # A ratio is ignored on a profile that holds one value all day. There is no base-to-peak
    # span to restate, and moving the base would turn a deliberately flat profile into a
    # shaped one. An explicit :base still applies -- that is a direct instruction, not a
    # proportion of something that is not there.
    #
    # @param params [Hash] expansion params
    # @param base_std [Float] the profile's authored base
    # @param peak_std [Float] the profile's authored peak
    # @param weekend [Boolean] true when resolving a Sat/Sun/Wknd profile
    # @return [Array<Float>] the base and peak to expand against
    def self.resolve_base_and_peak(params, base_std, peak_std, weekend: false)
      resolve = lambda do |for_weekend|
        pick = lambda do |weekday_key, weekend_key|
          value = for_weekend ? params[weekend_key] : nil
          value.nil? ? params[weekday_key] : value
        end

        peak = pick.call(:peak, :wknd_peak) || peak_std
        base = pick.call(:base, :wknd_base)
        ratio = pick.call(:base_peak_ratio, :wknd_base_peak_ratio)
        # an explicit base wins over the ratio; stating both is a caller confusion, not a blend
        flat = !base_std.nil? && !peak_std.nil? && (peak_std - base_std).abs < 1e-9
        base = ratio * peak if base.nil? && !ratio.nil? && !flat
        base = base_std if base.nil?

        [base, peak]
      end

      base, peak = resolve.call(weekend)
      if weekend && params[:cap_wknd_base_at_wkdy]
        weekday_base, = resolve.call(false)
        base = [base, weekday_base].min unless base.nil? || weekday_base.nil?
      end

      [base, peak]
    end

    # Evaluate one control point's value token against a base and peak.
    #
    # Three anchors are understood:
    #   'base', 'peak'  the endpoints themselves, optionally scaled ('peak*0.35')
    #   'range*f'       a fraction f of the way from base to peak
    #
    # 'range' is what interior points should use. An endpoint anchor pins a point to one
    # end of the profile and leaves it there when the other end moves, so a shoulder
    # authored as 'peak*0.35' does not budge when the base is raised -- the profile
    # flattens against its own shoulders rather than lifting. 'range*f' carries the point
    # with both ends, which is what raising a base-to-peak ratio means. The two agree
    # exactly at the authored base and peak, which is why the shipped data could be
    # converted point for point.
    #
    # @param token [String] value token, e.g. 'base', 'peak*0.35', 'range*0.2'
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @return [Float] the value, clamped to 0..1
    def self.evaluate_control_point_value(token, base, peak)
      anchor, operator, operand = token.scan(CONTROL_POINT_PARSER)[0]
      factor = operand.nil? ? nil : operand.to_f

      value = case anchor
              when 'range'
                base + (factor.nil? ? 1.0 : factor) * (peak - base)
              when 'peak'
                peak
              else
                base
              end
      # 'range' spends its factor on the interpolation; the endpoint anchors take an operator
      value = value.send(operator, factor) if anchor != 'range' && !operator.nil?

      # limit value between 0 and 1 (clamp is non-mutating, so reassign)
      value.clamp(0, 1)
    end

    # Evaluate a control-point schedule definition into sorted [time, value] anchor
    # pairs, BEFORE any wrap or smoothing. Times may legitimately exceed 24 (next-day
    # spillover) or fall below 0 (previous-day spillover).
    #
    # Each point is resolved to its absolute standard time and then passed through the
    # monotone warp from {control_point_time_warp}, so the anchors come out in authored
    # order and span at most 24 h whatever start_time and end_time are asked for.
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

      st_std = schedule_data[:st_std]
      et_std = schedule_data[:et_std]
      warp = OpenstudioStandards::Schedules.control_point_time_warp(
        st_std, et_std, start_time, end_time,
        shoulder: schedule_data[:shoulder] || CONTROL_POINT_SHOULDER_HOURS
      )

      # evaluate control points with inputs
      time_value_pairs = schedule_data[:control_points].map do |point|
        # control points are an array of two strings describing the time and value modifiers relative to start and end time (st/et) and base and peak values
        # e.g. ['st-1', 'range*0.5']
        time = OpenstudioStandards::Schedules.control_point_standard_time(point[0], st_std, et_std)
        [time, OpenstudioStandards::Schedules.evaluate_control_point_value(point[1], base, peak)]
      end

      # Sort in STANDARD coordinates. A few authored profiles interleave st- and
      # et-anchored points (the dining profiles put 'st+6' at 22 h ahead of 'et-7' at
      # 19 h); ordering before the warp - which is monotone - makes the resulting order
      # independent of the requested duration rather than a function of the multiplier.
      time_value_pairs.sort_by! { |pair| pair[0] }

      standard_times = OpenstudioStandards::Schedules.compress_standard_span(
        time_value_pairs.map(&:first), st_std.to_f, et_std.to_f
      )
      time_value_pairs = time_value_pairs.each_with_index.map do |(_, val), i|
        [round_to_timestep.call(warp.call(standard_times[i])), val]
      end
      OpenstudioStandards::Schedules.collapse_coincident_times(time_value_pairs)
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
        # Stretch (default): anchor to st/et and warp standard times onto the window.
        time_value_pairs = OpenstudioStandards::Schedules.evaluate_schedule_control_points(schedule_data, base, peak, start_time, end_time, timesteps_per_hour)
      end

      if time_value_pairs[-1][0] > 24 || time_value_pairs[0][0].negative?
        time_value_pairs = OpenstudioStandards::Schedules.wrap_schedule_pairs(time_value_pairs)
      end

      # apply smoothing to intermediate values between. The anchors are one day of a
      # repeating profile, so the gap across midnight is interpolated rather than held flat.
      OpenstudioStandards::Schedules.smooth_schedule_from_time_values(time_value_pairs, timesteps_per_hour, cyclic: true)
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
    # An overnight span is expressed by an end_time past 24 (a guest room runs st 17 -> et 33).
    # The post-midnight portion is folded back onto the same day, so the return is always a
    # single 24 h profile - no next-day spillover rule is involved.
    #
    # @param schedule_data [Hash] hash of schedule data containing :start_slope and :end_slope
    # @param base [Float] input schedule base value
    # @param peak [Float] input schedule peak value
    # @param start_time [Float] input start time, clamped to 0..24
    # @param end_time [Float] input end time, clamped to start_time..start_time + 24; values
    #   past 24 wrap the occupied span across midnight
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
      # An overnight span carries the end time past midnight - guest rooms run st 17 -> et 33.
      # Clamping et to 24 truncated the profile at midnight and dropped the whole post-midnight
      # portion. The wrap helpers below already fold times beyond 24 back onto the day, so the
      # only real bound is one full day; clamping the low side to st also keeps a malformed
      # et < st from inverting the ramp control points into an empty profile.
      et = end_time.clamp(st, st + 24.0)
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

      # The startup and endup curves above supply only the rising and falling edges; the plateau
      # between them is filled here. The plateau is the unwrapped interval start_upper ->
      # end_lower, which for an overnight span runs past 24 (21:00 -> 29:00). Each sample at
      # clock time t stands for both t and t+24 in that unwrapped timeline, so testing both
      # positions fills the post-midnight portion without needing a wrapped-interval special
      # case - and leaves an empty plateau (ramps so wide they overlap, end_lower <= start_upper)
      # unfilled, which comparing the wrapped bounds directly would not.
      combined.each do |pair|
        in_plateau = (pair[0] >= start_upper && pair[0] <= end_lower) ||
                     ((pair[0] + 24.0) >= start_upper && (pair[0] + 24.0) <= end_lower)
        pair[1] = 1 if in_plateau
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
    # Collapse each run of equal consecutive values to its last pair, which is the one
    # entry an until-time day schedule needs for the run. The final pair always survives.
    #
    # @param time_value_pairs [Array] array of [time, value] pairs
    # @return [Array] the reduced pairs
    def self.reduce_time_value_pairs(time_value_pairs)
      time_value_pairs.reject.with_index do |pair, i|
        pair[1] == time_value_pairs[i + 1][1] unless i == (time_value_pairs.size - 1)
      end
    end

    def self.add_time_value_pairs_to_schedule(day_sch, time_value_pairs)
      time_value_pairs.each_with_index do |pair, i|
        if i != (time_value_pairs.size - 1) && pair[1] == time_value_pairs[i + 1][1]
          next
        end

        hr = pair[0].to_i
        min = (pair[0].modulo(1) * 60).to_i

        day_sch.addValue(OpenStudio::Time.new(0, hr, min, 0), pair[1])
      end
    end

    # Schedule data is organized one file per category. Each load file holds both forms a
    # schedule can take: control-point profiles (direct) and derivation parameters (derived
    # from occupancy). The schedule set's `{category}_schedule` key names a record in the
    # file its slot maps to here.
    SCHEDULE_DATA_DIR = File.join(__dir__, 'data').freeze
    SCHEDULE_DATA_FILES = {
      occupancy: 'default_occupancy_schedules.json',
      interior_lighting: 'default_lighting_schedules.json',
      electric_equipment: 'default_electric_equipment_schedules.json',
      gas_equipment: 'default_gas_equipment_schedules.json',
      hot_water_equipment: 'default_hot_water_equipment_schedules.json',
      diurnal: 'default_diurnal_schedules.json'
    }.freeze

    # Load slot -> [schedule-set key, data file slot, category]. Hot water and gas records
    # both carry category 'Equipment', so the file - not the category - is what tells them
    # apart.
    LOAD_SLOTS = {
      lighting: [:interior_lighting_schedule, :interior_lighting, 'Lighting'],
      electric_equipment: [:electric_equipment_schedule, :electric_equipment, 'Equipment'],
      gas_equipment: [:gas_equipment_schedule, :gas_equipment, 'Equipment'],
      hot_water_equipment: [:hot_water_equipment_schedule, :hot_water_equipment, 'Equipment']
    }.freeze

    # Remove load instances that would otherwise reach EnergyPlus with no schedule, along
    # with any definition the removal leaves unreferenced.
    #
    # A definition can be shared by instances in other space types, so it is removed only
    # once its last instance is gone. Definitions are deduplicated by handle rather than by
    # object identity, since these are SWIG wrappers and two wrappers around the same model
    # object are not necessarily eql?.
    #
    # @param instances [Array<OpenStudio::Model::ModelObject>] load instances to remove
    # @param definition_method [Symbol] reader on an instance returning its definition
    # @return [Integer] number of instances removed
    def self.remove_unscheduled_load_instances(instances, definition_method)
      instances = instances.sort
      definitions = instances.map { |instance| instance.public_send(definition_method) }
                             .uniq { |definition| definition.handle.to_s }
      count = instances.size
      instances.each(&:remove)
      definitions.each { |definition| definition.remove if definition.instances.empty? }
      count
    end

    # @param slot [Symbol] key of {SCHEDULE_DATA_FILES}
    # @return [String] absolute path to that category's schedule data file
    def self.schedule_data_path(slot)
      File.join(SCHEDULE_DATA_DIR, SCHEDULE_DATA_FILES.fetch(slot))
    end

    # @param slot [Symbol] key of {SCHEDULE_DATA_FILES}
    # @return [Array<Hash>] parsed records for that category
    def self.schedule_data(slot)
      JSON.parse(File.read(schedule_data_path(slot)), symbolize_names: true)
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
    # @param schedule_array [Array] array of default schedule data objects to load from
    # @param schedule_name [String] name of schedule to create
    # @param params [Hash] optional schedule input overrides used during expansion.
    #   Supported keys:
    #   - :st [Float] weekday start time in hours. Drives Default/Wkdy profiles. Defaults to schedule object :st_std.
    #   - :et [Float] weekday end time in hours. Drives Default/Wkdy profiles. Defaults to schedule object :et_std.
    #   - :wknd_st [Float] weekend start time in hours. Drives Wknd/Sat/Sun profiles. Defaults to :st_std.
    #   - :wknd_et [Float] weekend end time in hours. Drives Wknd/Sat/Sun profiles. Defaults to :et_std.
    #   - :base [Float] base schedule value (typically 0.0..1.0). Defaults to :base_std.
    #   - :peak [Float] peak schedule value (typically 0.0..1.0). Defaults to :peak_std.
    #   - :base_peak_ratio [Float] the base as a fraction of the peak, an alternative to :base
    #     for callers holding a ratio rather than an absolute. Ignored when :base is given.
    #   - :wknd_base, :wknd_peak, :wknd_base_peak_ratio [Float] the same three for Wknd/Sat/Sun
    #     profiles. Each falls back to its weekday counterpart when omitted.
    #   - :cap_wknd_base_at_wkdy [Boolean] hold the weekend base at or below the weekday base.
    #   - :start_slope [Float] optional start transition slope factor for slope-based profile expansion.
    #     If provided together with :end_slope, uses expand_schedule_start_end_slope.
    #   - :end_slope [Float] optional end transition slope factor for slope-based profile expansion.
    #     If omitted (or :start_slope omitted), falls back to expand_schedule_control_points.
    #
    #   Notes:
    #   - All keys are optional. Apart from the weekend variants, which apply only to
    #     Wknd/Sat/Sun profiles, each applies to every matching schedule object in schedule_array.
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
        start_slope = params[:start_slope].nil? ? obj[:start_slope] : params[:start_slope]
        end_slope = params[:end_slope].nil? ? obj[:end_slope] : params[:end_slope]

        day_types = obj[:day_types].split('|')

        # Weekday vs weekend timing: weekend day types use the weekend building
        # hours when supplied; everything else uses the weekday building hours. The
        # standard timings (st_std/et_std) are the fallback when building hours are not
        # supplied, so standalone expansion (empty params) is unchanged.
        is_weekend = (day_types & %w[Wknd Sat Sun]).any? && (day_types & %w[Default Wkdy]).empty?

        base, peak = OpenstudioStandards::Schedules.resolve_base_and_peak(params, obj[:base_std], obj[:peak_std], weekend: is_weekend)
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

        # Design days are unaffected by building hours, and by a base-to-peak ratio: expand
        # them at the standard timing and the authored base and peak. A design day is a
        # peak-condition sizing assumption rather than a statement about how the space runs,
        # so a ratio describing unoccupied hours has nothing to say about it -- and a winter
        # design day authored flat at zero would otherwise be lifted, changing heating
        # sizing. An explicit base or peak is a direct instruction and still applies.
        # Derived profiles carry their own winter_ and summer_design_day_base, so this is
        # only the control-point path.
        design_base, design_peak = base, peak
        if (day_types & %w[SmrDsn WntrDsn]).any?
          ratio_free = params.reject { |key, _| %i[base_peak_ratio wknd_base_peak_ratio].include?(key) }
          design_base, design_peak = OpenstudioStandards::Schedules.resolve_base_and_peak(ratio_free, obj[:base_std], obj[:peak_std], weekend: is_weekend)
        end

        design_pairs =
          if st == obj[:st_std] && et == obj[:et_std] && design_base == base && design_peak == peak
            regular_pairs
          else
            OpenstudioStandards::Schedules.expand_parametric_profile(obj, design_base, design_peak, obj[:st_std], obj[:et_std], timesteps_per_hour, start_slope: start_slope, end_slope: end_slope)
          end

        regular_reduced = OpenstudioStandards::Schedules.reduce_time_value_pairs(regular_pairs)
        design_reduced = design_pairs.nil? ? regular_reduced : OpenstudioStandards::Schedules.reduce_time_value_pairs(design_pairs)

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
    # With no explicit threshold, "active" means above the profile's own floor rather than
    # above zero. Nearly every occupancy profile carries a non-zero overnight base (0.05 is
    # typical), and an absolute `> 0` test calls those hours active too - inferring 0..24 and
    # producing a flat schedule for anything that keys off the returned span. Measuring from
    # the profile's own minimum makes the result invariant to that base offset.
    #
    # NOTE: the span is taken from the first and last active pair in clock order, so an
    # overnight profile (occupied 17:00 through 08:00) infers a span covering the inactive
    # middle of the day. Callers that know the real timing should pass it explicitly.
    #
    # @param time_value_pairs [Array] array of [time, value] pairs
    # @param threshold [Float, nil] absolute minimum value considered active; when nil, the
    #   cutoff is set just above the profile's own minimum value
    # @return [Array<Float>] [start_time, end_time]
    def self.infer_start_end_times_from_profile(time_value_pairs, threshold = nil)
      return [0.0, 24.0] if time_value_pairs.empty?

      cutoff = if threshold.nil?
                 values = time_value_pairs.map { |pair| pair[1].to_f }
                 values.min + (0.01 * (values.max - values.min))
               else
                 threshold.to_f
               end
      active_pairs = time_value_pairs.select { |pair| pair[1].to_f > cutoff }
      # A flat profile has no active span to recover; fall back to the full day.
      return [0.0, 24.0] if active_pairs.empty?

      [active_pairs.first[0].to_f, active_pairs.last[0].to_f]
    end

    # Method to derive time-value pairs from a set of time-value pairs. The derived values are determined by applying the given parameters and derivation type.
    #
    # Shift the presence source in time, so a load can lead or lag the occupancy it derives
    # from. Values are resampled onto the original time grid at (t - lag_hours), wrapping
    # across midnight, so the returned pairs keep the schedule's own timestep structure.
    #
    # @param time_value_pairs [Array] array of [time, value] pairs
    # @param lag_hours [Float, nil] signed hours; positive delays the load behind occupancy
    # @return [Array] array of time value pairs
    def self.lag_presence_pairs(time_value_pairs, lag_hours)
      return time_value_pairs if lag_hours.nil? || lag_hours.to_f.abs < 1e-9
      return time_value_pairs if time_value_pairs.size < 2

      lag = lag_hours.to_f
      sorted = time_value_pairs.sort_by { |time, _| time }
      # OpenStudio ScheduleDay values apply UP TO their time, so the value in force at t is
      # carried by the first pair whose time is at or after t.
      value_at = lambda do |time|
        wrapped = time % 24.0
        pair = sorted.find { |pair_time, _| pair_time >= wrapped - 1e-9 } || sorted.last
        pair[1]
      end
      time_value_pairs.map { |time, _| [time, value_at.call(time - lag)] }
    end

    # Numerically safe logistic. Without the clamp a steepness above ~40 overflows Math.exp
    # and the curve returns NaN rather than the step it is asymptotically approaching.
    #
    # @param value [Float] exponent input
    # @return [Float] logistic of the input
    def self.logistic_sigma(value)
      1.0 / (1.0 + Math.exp(-value.clamp(-60.0, 60.0)))
    end

    # @param derivation_type [String] type of derivation to perform. Options are 'linear',
    #   'exponential', 'exponential-inverse', 'logistic', 'saturating', 'first_order' and 'up_down'
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
    # @param lag_hours [Float, nil] shift the presence source in time before deriving; signed
    #   hours, positive delays the load behind occupancy. Composes with every derivation type.
    # @param midpoint [Float, nil] 'logistic' only; presence at which the load is halfway to peak
    # @param steepness [Float, nil] 'logistic' only; how sharply the load switches at the midpoint
    # @param threshold [Float, nil] 'saturating' only; presence at which the load reaches peak
    # @param alpha_rise [Float, nil] 'first_order' only; 0-1 rate at which the load follows presence upward
    # @param alpha_fall [Float, nil] 'first_order' only; 0-1 rate at which the load follows presence downward
    # @return [Array] array of derived time value pairs
    def self.derive_values(derivation_type, base, peak, response, initial_values, start_slope: nil, end_slope: nil, start_time: nil, end_time: nil, timesteps_per_hour: 1, schedule_name: nil, base_peak_mode: 'absolute', occupancy_base: nil, occupancy_peak: nil, lag_hours: nil, midpoint: nil, steepness: nil, threshold: nil, alpha_rise: nil, alpha_fall: nil)
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

      # A load can lead or lag the occupancy it derives from - lights that come up before the
      # first arrivals, equipment that runs on after the last departure. Applied to the presence
      # source before any derivation type, so it composes with all of them.
      initial_values = OpenstudioStandards::Schedules.lag_presence_pairs(initial_values, lag_hours)

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
      when 'logistic'
        # S-curve response: the load stays near base until presence passes `midpoint`, then
        # rises steeply to peak. Expresses a load that switches rather than tracks - which no
        # power law can bend to, however the response is tuned. Renormalized so presence 0 maps
        # to base and presence 1 to peak regardless of where the midpoint sits.
        mid = midpoint.nil? ? 0.5 : midpoint.to_f
        steep = steepness.nil? ? 12.0 : steepness.to_f
        low = OpenstudioStandards::Schedules.logistic_sigma(steep * (0.0 - mid))
        high = OpenstudioStandards::Schedules.logistic_sigma(steep * (1.0 - mid))
        span = high - low
        initial_values.each do |initial_pair|
          presence_value = presence.call(initial_pair[1])
          shape = if span.abs < 1e-9
                    presence_value
                  else
                    (OpenstudioStandards::Schedules.logistic_sigma(steep * (presence_value - mid)) - low) / span
                  end
          derived_pairs << [initial_pair[0], base + ((peak - base) * shape.clamp(0.0, 1.0))]
        end
      when 'saturating'
        # The load reaches full output once presence passes `threshold`, and stays there while
        # presence keeps climbing - lighting in a space that is fully lit for one occupant.
        limit = threshold.nil? ? 0.5 : threshold.to_f
        limit = 1e-6 if limit <= 0.0
        initial_values.each do |initial_pair|
          shape = [presence.call(initial_pair[1]) / limit, 1.0].min
          derived_pairs << [initial_pair[0], base + ((peak - base) * shape)]
        end
      when 'first_order'
        # Rate-asymmetric first-order response: the load chases presence quickly on the way up
        # and slowly on the way down (or the reverse), which is how equipment that switches on
        # with the first occupant but powers down long after the last one behaves.
        #
        # NOTE: `response` is unused by this type - the two alpha rates are its parameters.
        rise = (alpha_rise.nil? ? 0.5 : alpha_rise.to_f).clamp(0.0, 1.0)
        fall = (alpha_fall.nil? ? 0.2 : alpha_fall.to_f).clamp(0.0, 1.0)
        targets = initial_values.map { |initial_pair| presence.call(initial_pair[1]) }
        state = targets.first.to_f
        # Warm-up passes so the result is the periodic steady state rather than an artifact of
        # whatever value the day happens to start on.
        2.times do
          targets.each { |target| state += (target > state ? rise : fall) * (target - state) }
        end
        initial_values.each_with_index do |initial_pair, index|
          target = targets[index]
          state += (target > state ? rise : fall) * (target - state)
          derived_pairs << [initial_pair[0], base + ((peak - base) * state.clamp(0.0, 1.0))]
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

      # Every derivation runs between base and peak; a 'linear' response above 1 is a load
      # that reaches its peak before full presence, not one that exceeds it. Unclamped, the
      # value base + (peak - base) x presence x response passes the peak - 1.0275 for a
      # response of 1.15 on a 0.05-0.9 span - and a Fractional schedule carrying 1.00125
      # stops EnergyPlus before the simulation starts.
      lo, hi = [base, peak].minmax
      derived_pairs = derived_pairs.map { |time, value| [time, value.clamp(lo, hi)] }
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

      diurnal_schedules = OpenstudioStandards::Schedules.schedule_data(:diurnal)
      diurnal_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(model, diurnal_schedules, diurnal_profile, {}, category: 'Diurnal')
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
    # The ruleset itself is assembled by {create_complex_schedule}, the same constructor the
    # direct parametric path uses; this method derives the day profiles and builds its
    # options. A source rule that carries no dates becomes a rule dated 1/1-12/31, which is
    # what a dateless rule means.
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
      # Weekend rules run between their own base and peak, so a weekend base-to-peak ratio
      # can differ from the weekday one. Resolved by the caller, which still had the
      # authored values and the overrides apart; absent that, weekends follow weekdays.
      weekend_base = params[:wknd_base].nil? ? base : params[:wknd_base]
      weekend_peak = params[:wknd_peak].nil? ? peak : params[:wknd_peak]
      response = params[:response]
      start_slope = params[:start_slope]
      end_slope = params[:end_slope]
      # Optional shaping parameters. `lag_hours` composes with every derivation type;
      # the rest are read by the type that uses them and ignored otherwise. None have
      # design-day overrides - a design day is a peak-condition assumption, not a
      # statement about how the load follows presence.
      lag_hours = params[:lag_hours]
      midpoint = params[:midpoint]
      steepness = params[:steepness]
      threshold = params[:threshold]
      alpha_rise = params[:alpha_rise]
      alpha_fall = params[:alpha_fall]
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

      # Derive one day profile: gate the occupancy day's pairs where the diurnal modifier
      # applies, run the derivation, and collapse equal-value runs the way the direct
      # parametric path does before it hands profiles to create_complex_schedule.
      derive_day = lambda do |day_base, day_peak, day_response, occ_day_sch, gated|
        occ_time_values = occ_day_sch.times.map(&:totalHours).zip(occ_day_sch.values)
        occ_time_values = diurnal_gate.call(occ_time_values) if gated && !diurnal_gate.nil?
        derived_pairs = OpenstudioStandards::Schedules.derive_values(
          derivation_type, day_base, day_peak, day_response, occ_time_values,
          start_slope: start_slope, end_slope: end_slope,
          start_time: derivation_start_time, end_time: derivation_end_time,
          timesteps_per_hour: timesteps_per_hour, schedule_name: params[:name],
          base_peak_mode: base_peak_mode, occupancy_base: occupancy_base, occupancy_peak: occupancy_peak,
          lag_hours: lag_hours, midpoint: midpoint, steepness: steepness,
          threshold: threshold, alpha_rise: alpha_rise, alpha_fall: alpha_fall
        )
        OpenstudioStandards::Schedules.reduce_time_value_pairs(derived_pairs)
      end

      # Assemble the create_complex_schedule options. Design days derive without the
      # diurnal gate; rules carry the source rule's dates and days, with a rule that has no
      # dates of its own running all year, which is what dateless rules mean.
      options = {
        'name' => params[:name],
        'default_day' => ['Default Day'] + derive_day.call(base, peak, response, occupancy_schedule.defaultDaySchedule, true),
        'summer_design_day' => derive_day.call(summer_design_day_base, summer_design_day_peak, summer_design_day_response,
                                               occupancy_schedule.summerDesignDaySchedule, false),
        'winter_design_day' => derive_day.call(winter_design_day_base, winter_design_day_peak, winter_design_day_response,
                                               occupancy_schedule.winterDesignDaySchedule, false),
        'rules' => []
      }

      rule_sources = occupancy_schedule.scheduleRules
      rule_bases = []
      rule_sources.each_with_index do |rule, index|
        # A rule that runs only on Saturday and Sunday is a weekend profile and takes the
        # weekend base and peak. One that also applies on a weekday is a weekday rule that
        # happens to extend across the weekend, so it keeps the weekday values.
        rule_weekend = (rule.applySaturday || rule.applySunday) &&
                       !(rule.applyMonday || rule.applyTuesday || rule.applyWednesday || rule.applyThursday || rule.applyFriday)
        rule_base = rule_weekend ? weekend_base : base
        rule_peak = rule_weekend ? weekend_peak : peak
        rule_bases << [rule_base, rule_peak]

        date_range = if rule.startDate.is_initialized && rule.endDate.is_initialized
                       start_date = rule.startDate.get
                       end_date = rule.endDate.get
                       "#{start_date.monthOfYear.value}/#{start_date.dayOfMonth}-#{end_date.monthOfYear.value}/#{end_date.dayOfMonth}"
                     else
                       '1/1-12/31'
                     end
        days = []
        days << 'Sun' if rule.applySunday
        days << 'Mon' if rule.applyMonday
        days << 'Tue' if rule.applyTuesday
        days << 'Wed' if rule.applyWednesday
        days << 'Thu' if rule.applyThursday
        days << 'Fri' if rule.applyFriday
        days << 'Sat' if rule.applySaturday

        options['rules'] << ["rule #{index}", date_range, days.join('/')] +
                            derive_day.call(rule_base, rule_peak, response, rule.daySchedule, true)
      end

      derived_schedule = OpenstudioStandards::Schedules.create_complex_schedule(model, options)

      # create_complex_schedule names rules after the ruleset and the placeholder label;
      # restore the source-rule naming and stamp the derivation provenance.
      rule_sources.each_with_index do |rule, index|
        sch_rule = derived_schedule.scheduleRules.find { |r| r.name.get == "#{params[:name]} rule #{index} Rule" }
        if sch_rule.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules',
                             "Derived schedule '#{params[:name]}' is missing the rule derived from '#{rule.name}'.")
          next
        end

        sch_rule.setName("#{rule.name} Derived #{params[:category]} Rule")
        day_sch = sch_rule.daySchedule
        day_sch.setName("#{rule.name} Derived #{params[:category]} Day Sch")

        props = day_sch.additionalProperties
        props.setFeature('base', rule_bases[index][0])
        props.setFeature('peak', rule_bases[index][1])
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
    # @param name [String, nil] the load schedule reference
    # @param category [String] schedule category ('Lighting' or 'Equipment')
    # @param data_slot [Symbol] key of {SCHEDULE_DATA_FILES} naming this load's data file
    # @param occupancy_sch [OpenStudio::Model::ScheduleRuleset, nil] occupancy schedule for derivation
    # @param params [Hash] expansion params (st/et/offsets) applied to direct schedules
    # @param derived_timing [Hash] timing carried into derived loads
    # @param load_override [Hash] runtime override fields merged last (highest precedence)
    # @return [OpenStudio::Model::ScheduleRuleset, nil] the resulting schedule, or nil
    def self.resolve_load_schedule(model, name, category, data_slot, occupancy_sch, params, derived_timing, load_override = {})
      return nil if name.nil?

      load_override ||= {}
      data = OpenstudioStandards::Schedules.schedule_data(data_slot)

      # Direct path: the reference resolves to a control-point profile. Which form a record
      # takes is what distinguishes the two paths - a profile carries day_types, a derivation
      # carries derivation_type - so a category file can hold both without ambiguity.
      profiles = data.select { |o| o[:name].to_s == name.to_s && !o[:day_types].nil? }
      unless profiles.empty?
        return OpenstudioStandards::Schedules.create_parametric_schedule_full(model, profiles, name, params.merge(load_override), category: category)
      end

      load_params = data.find { |s| s[:name].to_s == name.to_s && !s[:derivation_type].nil? }
      if load_params.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Could not find load schedule '#{name}' in #{SCHEDULE_DATA_FILES.fetch(data_slot)}.")
        return nil
      end

      # Derived path: transform the occupancy schedule using its derivation parameters.
      if occupancy_sch.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules', "Load schedule '#{name}' is derived from occupancy but there is no occupancy schedule to derive it from; skipping.")
        return nil
      end

      # precedence: runtime override (load_override) > standard JSON params
      derived_params = load_params.merge(derived_timing).merge(load_override)

      # Resolve the base and peak here rather than inside the derivation, because this is
      # the last point at which the authored values and the caller's overrides are still
      # separable. One merge later they are the same two keys, and a base_peak_ratio could
      # never take effect: it would always find an authored base already in place.
      derived_params[:base], derived_params[:peak] =
        OpenstudioStandards::Schedules.resolve_base_and_peak(load_override, load_params[:base], load_params[:peak])
      derived_params[:wknd_base], derived_params[:wknd_peak] =
        OpenstudioStandards::Schedules.resolve_base_and_peak(load_override, load_params[:base], load_params[:peak], weekend: true)

      OpenstudioStandards::Schedules.create_derived_schedule_from_occupancy_schedule(occupancy_sch, derived_params)
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
    #   An 'occupancy_peak_override' additional property on the space type (set by a
    #   keep_standard_design_level people load override) wins over all other occupancy peak inputs.
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
      if space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized
        schedule_set_name = space_type.additionalProperties.getFeatureAsString('schedule_set').get
        # Each set now belongs to exactly one space type, so the name alone resolves it. The
        # building-type axis that used to be disambiguated here lives in the space type
        # taxonomy instead - a school corridor is its own space type, resolved upstream in
        # OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties.
        space_type_properties = default_parametric_sch_set.find { |s| s[:schedule_set_name] == schedule_set_name }

        if space_type_properties.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules', "Unable to find schedule set '#{schedule_set_name}' for #{space_type.name}.")
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

      # Resolve runtime overrides for this space use, matched against the names the space type
      # answers to: its schedule set, its all-level space type, its ventilation space type.
      overrides = OpenstudioStandards::CreateTypical.resolve_overrides(
        schedule_overrides, space_type,
        section_keys: %i[occupancy lighting electric_equipment gas_equipment hot_water_equipment]
      )

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
      # :schedule names which schedule to draw from, handled by schedule_name_for below; the
      # rest of the section are expansion parameters
      occ_params = occ_params.merge(overrides[:occupancy].reject { |field, _| field == :schedule }) if overrides[:occupancy].is_a?(Hash)

      # A keep_standard_design_level people load override adjusts the occupancy schedule peak
      # instead of the design occupancy level (see CreateTypical.space_type_apply_load_overrides).
      # It is computed to hit a specific peak occupancy, so it wins over other peak inputs.
      if space_type.additionalProperties.getFeatureAsDouble('occupancy_peak_override').is_initialized
        occupancy_peak_override = space_type.additionalProperties.getFeatureAsDouble('occupancy_peak_override').get
        occ_params[:peak] = occupancy_peak_override
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules', "#{space_type.name} occupancy schedule peak set to #{occupancy_peak_override.round(3)} from the occupancy_peak_override additional property.")

        # derived load schedules with base_peak_mode 'relative' follow the raw occupancy
        # presence values, so the adjusted occupancy peak also shifts those schedules.
        # 'absolute' mode (the default) normalizes presence over the occupancy base/peak
        # and is unaffected.
        LOAD_SLOTS.each do |section_key, (set_key, data_slot, _category)|
          load_name = space_type_properties[set_key]
          next if load_name.nil?

          load_params = OpenstudioStandards::Schedules.schedule_data(data_slot).find { |s| s[:name] == load_name }
          next if load_params.nil?

          base_peak_mode = (overrides[section_key].is_a?(Hash) && overrides[section_key][:base_peak_mode]) || load_params[:base_peak_mode]
          if base_peak_mode.to_s == 'relative'
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules', "#{space_type.name} derived load schedule '#{load_name}' uses base_peak_mode 'relative', so the schedule derived from occupancy will be adjusted along with the occupancy schedule peak.")
          end
        end
      end

      # Timing carried into derived loads (used by the 'up_down' derivation; other
      # derivation types inherit timing from the occupancy schedule they transform).
      derived_timing = {}
      derived_timing[:st] = occ_params[:st] unless occ_params[:st].nil?
      derived_timing[:et] = occ_params[:et] unless occ_params[:et].nil?

      # The schedule a load draws from: the one its schedule set names, unless an override names
      # another. A schedule set that names none leaves the load unscheduled and its objects are
      # removed below, so naming one here is how a space type the data leaves unscheduled - a
      # restroom given occupancy by an occupancy_overrides entry, say - gets a schedule to go
      # with it.
      schedule_name_for = lambda do |section_key, property_key|
        named = (overrides[section_key] || {})[:schedule]
        named.nil? || named.to_s.strip.empty? ? space_type_properties[property_key] : named.to_s
      end

      # Find occupancy schedule. A null occupancy schedule (not-regularly-occupied sets) is
      # expected; those loads use the direct path below.
      occupancy_schedules = OpenstudioStandards::Schedules.schedule_data(:occupancy)
      occupancy_schedule_name = schedule_name_for.call(:occupancy, :occupancy_schedule)
      occupancy_sch = nil
      unless occupancy_schedule_name.nil?
        occupancy_sch = OpenstudioStandards::Schedules.create_parametric_schedule_full(space_type.model, occupancy_schedules, occupancy_schedule_name, occ_params, category: 'Occupancy')
        if occupancy_sch.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules',
                             "Could not build occupancy schedule '#{occupancy_schedule_name}' for #{space_type.name}; the space type will be left unoccupied.")
        end
      end

      # Add occupancy schedule to the default schedule set. Not-regularly-occupied sets
      # have a null occupancy schedule (their loads use the direct path below), so skip
      # people and the activity schedule when there is no occupancy.
      if set_people
        if occupancy_sch.nil?
          # The loads path is independent of this one: with space_type_load_method
          # 'standards', Standards.People.rb creates a People object for any space type
          # whose standards data gives a nonzero occupancy_per_area, regardless of whether
          # a schedule will exist. Leaving that object behind produces
          #   ** Severe ** <root>[People][<name>] - Missing required property
          #                'number_of_people_schedule_name'
          # which is fatal at EnergyPlus input processing, so the model never runs. The 21
          # not-regularly-occupied schedule sets (corridors, restrooms, stairwells, attics,
          # plenums, shafts, interior parking, storage, datacenters) declare no occupancy
          # schedule by design, so the People object is removed rather than invented.
          people = space_type.people + space_type.spaces.flat_map(&:people)
          removed = OpenstudioStandards::Schedules.remove_unscheduled_load_instances(people, :peopleDefinition)
          if removed > 0
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules',
                               "Schedule set '#{space_type_properties[:schedule_set_name]}' for #{space_type.name} defines no occupancy schedule; removed #{removed} People object(s) that would have had no schedule.")
          end
        else
          default_sch_set.setNumberofPeopleSchedule(occupancy_sch)

          # Set the activity schedule. Use a default 120 W/person. The name is shared, not per
          # space type, so create_constant_schedule_ruleset's dedupe-by-name returns one
          # schedule object for the whole model instead of an identical copy per space type.
          occupancy_activity_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(space_type.model, 120.0, name: 'Occupant Activity Schedule 120 W/person')
          default_sch_set.setPeopleActivityLevelSchedule(occupancy_activity_sch)
        end
      end

      # Each load: a direct control-point schedule or one derived from occupancy, decided by
      # the form of the record its name resolves to inside the category's data file.
      setters = { lighting: :setLightingSchedule,
                  electric_equipment: :setElectricEquipmentSchedule,
                  gas_equipment: :setGasEquipmentSchedule,
                  hot_water_equipment: :setHotWaterEquipmentSchedule }
      enabled = { lighting: set_lights, electric_equipment: set_electric_equipment,
                  gas_equipment: set_gas_equipment, hot_water_equipment: set_hot_water_equipment }

      # Same contract as people above: a load object whose schedule slot is null would
      # reach EnergyPlus missing its required schedule_name and terminate the run, so the
      # objects are removed instead of being left unscheduled.
      load_instances = { lighting: [:lights, :lightsDefinition],
                         electric_equipment: [:electricEquipment, :electricEquipmentDefinition],
                         gas_equipment: [:gasEquipment, :gasEquipmentDefinition],
                         hot_water_equipment: [:hotWaterEquipment, :hotWaterEquipmentDefinition] }

      LOAD_SLOTS.each do |section_key, (set_key, data_slot, category)|
        next unless enabled[section_key]

        load_schedule_name = schedule_name_for.call(section_key, set_key)
        if load_schedule_name.nil?
          getter, definition_method = load_instances[section_key]
          objects = space_type.public_send(getter) + space_type.spaces.flat_map { |space| space.public_send(getter) }
          removed = OpenstudioStandards::Schedules.remove_unscheduled_load_instances(objects, definition_method)
          if removed > 0
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Schedules',
                               "Schedule set '#{space_type_properties[:schedule_set_name]}' for #{space_type.name} defines no #{section_key} schedule; removed #{removed} #{section_key} object(s) that would have had no schedule.")
          end
          next
        end

        # :schedule names which schedule to draw from; it is not one of the expansion or
        # derivation parameters the rest of the section carries
        load_override = (overrides[section_key] || {}).reject { |field, _| field == :schedule }
        load_sch = OpenstudioStandards::Schedules.resolve_load_schedule(
          space_type.model, load_schedule_name, category, data_slot,
          occupancy_sch, occ_params, derived_timing, load_override
        )
        default_sch_set.public_send(setters[section_key], load_sch) unless load_sch.nil?
      end

      return true
    end
  end
end
