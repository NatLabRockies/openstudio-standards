module BTAP
  module LinearRegression

    # Interpolate a 2D array for the dependent variable `x2` and get the
    # y-intercept.
    # @param x_y_array [Array[Array]] 2D array of floats.
    # @param x2        [Float]        Dependent variable to be interpolated.
    # @param extrapolate_percent_range [Float]
    # @return [[Float, String]] The interpolated y-intercept and the warning
    #                           message, "OK" if none.
    def self.interpolate(x_y_array:, x2:, extrapolate_percentage_range: 50.0)
      notes = "OK"
      array = x_y_array.uniq.sort { |a, b| a[0] <=> b[0] }

      if array.empty? 
        return 0.0, "[BTAP::LinearRegression] Empty array given for interpolation, returning zero."
      elsif array.size == 1
        return array.first[1].to_f, notes
      end

      ratio_range = extrapolate_percentage_range / 100.0
      lower_bound = (1.0 - ratio_range) * array[0][0] 
      upper_bound = (1.0 + ratio_range) * array[-1][0]

      if x2 < lower_bound
        return lower_bound, "[BTAP::LinearRegression] Dependent variable #{x2} precedes the lower bound " \
                            "(#{lower_bound}) for the #{extrapolate_percentage_range}% range. Returning the lower " \
                            "bound."
      elsif x2 > upper_bound
        return upper_bound, "[BTAP::LinearRegression] Dependent variable #{x2} exceeds the upper bound " \
                            "(#{upper_bound}) for the #{extrapolate_percentage_range}% range. Returning the upper " \
                            "bound."
      elsif x2 < array.first[0].to_f

        # Extrapolate down using first and second cost value to this
        # out-of-range input.
        x_array      = [array[0][0].to_f, array[1][0].to_f]
        y_array      = [array[0][1].to_f, array[1][1].to_f]
        linear_model = LinearModel.new(x_array, y_array)
        y2           = linear_model.y_intercept + linear_model.slope * x2
        return y2, notes
      elsif x2 > array.last[0].to_f

        # Extrapolate up using second to last and last cost value to this
        # out-of-range input.
        x_array      = [array[-2][0].to_f, array[-1][0].to_f]
        y_array      = [array[-2][1].to_f, array[-1][1].to_f]
        linear_model = LinearModel.new(x_array, y_array)
        y2           = linear_model.y_intercept + linear_model.slope * x2
        return y2, notes
      else
        array.each_index do |counter|

          # skip last value.
          next if array[counter] == array.last

          x0 = array[counter][0]
          y0 = array[counter][1]
          x1 = array[counter + 1][0]
          y1 = array[counter + 1][1]

          # Skip if x2 is not between x0 and x1.
          next if x2 < x0 || x2 > x1

          y2 = y0 # Just in-case x0, x1 and x2 are identical.
          if (x1 - x0) > 0.0
            y2 = y0.to_f + ((y1 - y0).to_f * (x2 - x0).to_f / (x1 - x0).to_f)
          end
          return y2, notes
        end
      end
    end

    class LinearModel
      def initialize(xs, ys)
        @xs, @ys = xs, ys
        if @xs.length != @ys.length
          raise "Unbalanced data. xs need to be same length as ys"
        end
      end

      def y_intercept
        return mean(@ys) - (slope * mean(@xs))
      end

      def slope
        x_mean = mean(@xs)
        y_mean = mean(@ys)

        numerator = (0...@xs.length).reduce(0) do |sum, i|
          sum + ((@xs[i] - x_mean) * (@ys[i] - y_mean))
        end

        denominator = @xs.reduce(0) do |sum, x|
          sum + ((x - x_mean) ** 2)
        end

        return (numerator / denominator)
      end

      def mean(values)
        total = values.reduce(0) { |sum, x| x + sum }
        return Float(total) / Float(values.length)
      end
    end
  end
end


