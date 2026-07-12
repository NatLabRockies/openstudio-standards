module OpenStudioEnvelope
  module Costing
    # Exact port of BTAP::LinearRegression.interpolate — the cost-vs-RSI
    # interpolator legacy envelope costing keys on. Semantics preserved verbatim:
    # ±2% clamp bands beyond the data return the CLAMPED bound (±2% of the
    # boundary y), in-band out-of-range extrapolates linearly from the two nearest
    # points, in-range interpolates piecewise-linearly.
    #
    # DELIBERATE DEVIATION from legacy: exceeding the upper clamp does NOT add the
    # legacy $10^12 "revolutionary engineering technology fudge factor" to the
    # total — the condition surfaces as `upper_bound_exceeded` on the result and
    # the caller writes a LOUD audit warning + report flag instead.
    module Interpolate
      Result = Struct.new(:value, :note, :upper_bound_exceeded, keyword_init: true)

      module_function

      # @param x_y_array [Array<Array(Float, Float)>]
      # @param x2 [Float] where to evaluate
      # @param extrapolation_range [Float] clamp band, fraction (legacy 0.02)
      # @return [Result]
      def interpolate(x_y_array:, x2:, extrapolation_range: 0.02)
        note = 'OK'
        array = x_y_array.uniq.sort { |a, b| a[0] <=> b[0] }
        pct = extrapolation_range * 100

        return Result.new(value: 0.0, note: 'empty array given for interpolation, returning zero', upper_bound_exceeded: false) if array.empty?
        return Result.new(value: array.first[1].to_f, note: note, upper_bound_exceeded: false) if array.size == 1

        x_lo = (1.0 - extrapolation_range) * array[0][0]
        x_hi = (1.0 + extrapolation_range) * array[-1][0]
        y_lo = (1.0 - extrapolation_range) * array[0][1]
        y_hi = (1.0 + extrapolation_range) * array[-1][1]

        if x2 < x_lo
          return Result.new(value: y_lo, upper_bound_exceeded: false,
                            note: "x #{x2.round(4)} precedes the lower bound (#{x_lo.round(4)}) for the #{pct}% range; returning the lower bound")
        elsif x2 > x_hi
          return Result.new(value: y_hi, upper_bound_exceeded: true,
                            note: "x #{x2.round(4)} exceeds the upper bound (#{x_hi.round(4)}) for the #{pct}% range; returning the upper bound")
        elsif x2 < array.first[0].to_f
          return Result.new(value: linear(array[0], array[1], x2), note: note, upper_bound_exceeded: false)
        elsif x2 > array.last[0].to_f
          return Result.new(value: linear(array[-2], array[-1], x2), note: note, upper_bound_exceeded: false)
        end

        array.each_cons(2) do |(x0, y0), (x1, y1)|
          next if x2 < x0 || x2 > x1

          value = y0.to_f
          value = y0.to_f + ((y1 - y0).to_f * (x2 - x0).to_f / (x1 - x0).to_f) if (x1 - x0) > 0.0
          return Result.new(value: value, note: note, upper_bound_exceeded: false)
        end
        Result.new(value: array.last[1].to_f, note: 'fell through interpolation; returning last point', upper_bound_exceeded: false)
      end

      def linear(p0, p1, x2)
        x0, y0 = p0.map(&:to_f)
        x1, y1 = p1.map(&:to_f)
        slope = (y1 - y0) / (x1 - x0)
        y0 + slope * (x2 - x0)
      end
    end
  end
end
