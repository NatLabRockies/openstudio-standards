# rubocop:disable all

# constrain an input value between lower and upper limit
def clamp(x, lower_limit = 0, upper_limit = 1.0)
  if x < lower_limit
    lower_limit
  elsif x > upper_limit
    upper_limit
  else
    x
  end
end

# apply smootherstep function
# see: https://en.wikipedia.org/wiki/Smoothstep#Variations
def smootherstep(edge0, edge1, x)
  x = clamp((x - edge0) / (edge1 - edge0))

  return x * x * x * (x * (6.0 * x - 15.0) + 10.0)
end

# applies smootherstep to the input set of <24 time_value_pairs to interpolate missing points
# returns an expanded array of 24 time value pairs 
def smooth_schedule_from_time_values(time_value_pairs)
  return_arry = []
  if time_value_pairs[0][0] != 0
    time_value_pairs.unshift([0, time_value_pairs[0][1]])
  end
  if time_value_pairs[-1][0] != 24
    time_value_pairs << [24, time_value_pairs[-1][1]]
  end

  time_value_pairs.each_cons(2) do |this_pair, next_pair|
    this_time = this_pair[0].to_f
    this_val = this_pair[1]
    next_time = next_pair[0].to_f
    next_val = next_pair[1]

    Range.new(this_time,next_time,true).step(1).each do |hr|
      hr_frac = (hr - this_time)/(next_time - this_time)
      val_frac = smootherstep(0,1,hr_frac)
      if next_val < this_val
        val_actual = this_val - (val_frac * (next_val - this_val).abs)
      else
        val_actual = this_val + (val_frac * (next_val - this_val).abs)
      end
      return_arry << [hr, val_actual]
    end
  end
  return_arry
end


# time_value_pairs = [
#   [2, 0.4],
#   [3, 0.6],
#   [10,0.8],
#   [17,0.8],
#   [22,0.3]
# ]

# time_value_pairs = [
#   [2, 0.1],
#   [7,0.8],
#   [18,0.8],
#   [23,0.1]
# ]

# time_value_pairs = [
#   [2, 0.1],
#   [7,0.7],
#   [12,0.4],
#   [15,0.7],
#   [18,1],
#   [23,0.1]
# ]

time_value_pairs = [
  [0, 0.05],
  [1, 0],
  [4, 0],
  [8.0, 0.4],
  [10, 0.2],
  [12, 0.8],
  [15, 0.2],
  [19, 0.8],
  [23, 0.2]
]

# compare to schedule produced from full set of 24 time-value pairs 
orig_tvps = [
  [0.0, 0.05],
	[1.0, 0.0],
	[2.0, 0.0],
	[3.0, 0.0],
	[4.0, 0.0],
	[5.0, 0.05],
	[6.0, 0.1],
	[7.0, 0.4],
	[8.0, 0.4],
	[9.0, 0.4],
	[10.0, 0.2],
	[11.0, 0.5],
	[12.0, 0.8],
	[13.0, 0.7],
	[14.0, 0.4],
	[15.0, 0.2],
	[16.0, 0.25],
	[17.0, 0.5],
	[18.0, 0.8],
	[19.0, 0.8],
	[20.0, 0.8],
	[21.0, 0.5],
	[22.0, 0.35],
	[23.0, 0.2]
]
tvs = smooth_schedule_from_time_values(time_value_pairs)

require 'ascii_charts'
puts AsciiCharts::Cartesian.new(tvs).draw
# tvs.each{|tv| puts "#{tv[0]} - #{tv[1]}"}
puts AsciiCharts::Cartesian.new(orig_tvps).draw