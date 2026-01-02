# This script translates the occupancy schedules from schedules data in 'standard' time-value pair form
# to parametric form by analyzing the trends in the hourly data and extracting control points.
# The resulting parametric data is saved to a JSON file and equivalent schedules are created in an OpenStudio model

require 'openstudio'
require 'json'
require 'csv'
require_relative 'create'
require_relative 'add_schedule_parametric'

def evaluate_trends(values)
  # step through each time value pair and determine if the trend from one point to the next is increasing, decreasing, or constant and by how much
  trends = []
  (1...values.size).each do |i|
    this_value = values[i - 1]
    next_value = values[i]
    if next_value > this_value
      trends << { type: :increasing, from_hour: i, from: this_value, to_hour: i + 1, to: next_value, change: next_value - this_value }
    elsif next_value < this_value
      trends << { type: :decreasing, from_hour: i, from: this_value, to_hour: i + 1, to: next_value, change: next_value - this_value }
    else
      trends << { type: :constant, from_hour: i, from: this_value, to_hour: i + 1, to: next_value }
    end
  end

  return trends
end

def find_changes(values)
  # extract the points where the trend changes
  trends = evaluate_trends(values)

  changes = []

  # move starting decreasing trends to the end of the array
  first_zero = trends.index { |t| t[:type] != :decreasing }
  trends = trends[first_zero..] + trends[0...first_zero] if first_zero

  trends.each_with_index do |trend, i|
    if i == 0 || trend[:type] != trends[i - 1][:type]
      changes << trend
    else
      changes[-1][:to] = trend[:to]
      changes[-1][:to_hour] = trend[:to_hour]
      changes[-1][:change] += trend[:change] if trend[:change]
    end
  end
  return changes
end

def control_points_from_changes(values)
  parametric_data = {}

  changes = find_changes(values)

  changes.each { |chg| puts chg.inspect }

  base = values.min
  peak = values.max

  # find start time as the midpoint of the first increasing trend
  first_increase = changes.index { |t| t[:type] == :increasing }
  if first_increase.nil?
    start_time = 0
  else
    start_time = (changes[first_increase][:from_hour] + ((changes[first_increase][:to_hour] - changes[first_increase][:from_hour]) / 2))
  end

  # find end time as the midpoint of the last decreasing trend
  last_decrease = changes.rindex { |t| t[:type] == :decreasing }
  if last_decrease.nil?
    end_time = 24
  else
    if changes[last_decrease][:to_hour] < changes[first_increase][:from_hour]
      changes[last_decrease][:to_hour] += 24
      changes[last_decrease][:from_hour] += 24
    end
    end_time = (changes[last_decrease][:from_hour] + ((changes[last_decrease][:to_hour] - changes[last_decrease][:from_hour]) / 2))
  end

  puts "start_time: #{start_time} end_time: #{end_time}"

  if end_time < start_time
    end_time += 24
  end

  puts "start_time: #{start_time} end_time: #{end_time}"

  duration = end_time - start_time
  mid_time = start_time + (duration.to_f / 2).round
  mid_dur = mid_time - start_time
  puts "mid_time: #{mid_time} mid_dur: #{mid_dur}"
  ctrl_pts = []
  changes.each do |trend|
    next if trend[:type] == :constant

    # construct control point as array of strings, where first string is the time modifier in terms of start time (st) or endtime (et), e.g. 'st-1'
    # and the second string is the value modifier in terms of the base or peak value, e.g. 'base' or 'peak'
    ctrlpt1 = []
    ctrlpt2 = []
    from_dif = trend[:from_hour] - start_time
    to_dif = trend[:to_hour] - start_time
    if from_dif < mid_dur
      ctrlpt1[0] = 'st'
    else
      from_dif = trend[:from_hour] - end_time
      ctrlpt1[0] = 'et'
    end
    ctrlpt1[0] += from_dif.zero? ? '' : '++-'[from_dif <=> 0] + from_dif.abs.to_s

    ctrlpt1[1] = trend[:from] == base ? 'base' : 'peak'
    ctrlpt1[1] += trend[:from] == base || trend[:from] == peak ? '' : "*#{trend[:from] / peak}"

    if to_dif < mid_dur
      ctrlpt2[0] = 'st'
    else
      to_dif = trend[:to_hour] - end_time
      ctrlpt2[0] = 'et'
    end
    ctrlpt2[0] += to_dif.zero? ? '' : '++-'[to_dif <=> 0] + to_dif.abs.to_s

    ctrlpt2[1] = trend[:to] == base ? 'base' : 'peak'
    ctrlpt2[1] += trend[:to] == base || trend[:to] == peak ? '' : "*#{trend[:to] / peak}"
    ctrl_pts << ctrlpt1
    ctrl_pts << ctrlpt2
  end
  if ctrl_pts.empty? && base == peak
    ctrl_pts << ['st', 'base']
    ctrl_pts << ['et', 'base']
  end

  puts "control points: #{ctrl_pts.each { |c| puts c.inspect }}"

  parametric_data[:st_std] = start_time
  parametric_data[:et_std] = end_time
  parametric_data[:control_pts] = ctrl_pts

  return parametric_data
end

# new moethod to convert standard occ schedule data to parametric form
def derive_schedule_parameters_from_data(data)
  all_parametric_data = []
  data.each do |obj|
    param_data = {}
    param_data[:name] = obj[:name]
    param_data[:day_types] = obj[:day_types]
    param_data[:start_date] = obj[:start_date]
    param_data[:end_date] = obj[:end_date]
    param_data[:category] = obj[:category]
    param_data[:units] = obj[:units]
    param_data[:type] = 'parametric'

    # extract control points from schedule values
    hr_vals = obj[:values]
    if hr_vals.size == 1
      hr_vals = Array.new(24, hr_vals[0])
    end
    base = hr_vals.min
    peak = hr_vals.max
    param_data[:base_std] = base
    param_data[:peak_std] = peak

    # determine control points and standard start/end times
    param_data.merge!(control_points_from_changes(hr_vals))
    puts param_data.inspect
    all_parametric_data << param_data
  end
  return all_parametric_data
end

def load_schedule_data(path)
  file_content = File.read(path)
  return JSON.parse(file_content, symbolize_names: true)
end

def select_schedules_by_category(schedules, selection_key)
  return schedules.select { |obj| obj[:category] == selection_key }
end

# translate standard schedule data to a form usable by OpenstudioStandards::Schedules.create_complex_schedule
def schedule_data_to_input_hash(schedule_array)
  # schedule_array is an array of hashes with profiles of the same name
  options = {}
  options['name'] = schedule_array[0][:name]
  options['rules'] = []
  schedule_array.each do |obj|
    # hr_data = obj.select { |k, v| k.to_s.include?('hr_') }
    hr_data = obj[:values]
    if hr_data.size == 1
      hr_data = Array.new(24, hr_data[0])
    elsif hr_data.size < 24
      puts "Error: #{options[:name]} schedule data is not 24 hours long!"
    end
    # tv_pairs = hr_data.keys.map { |k| k.to_s.gsub('hr_', '').to_f }.zip(hr_data.values)
    tv_pairs = hr_data.each_with_index.map { |v, i| [i + 1, v] } # convert to 1-based index
    # only keep last time-value pair with unique value
    tv_pairs_reduced = tv_pairs.reject.with_index { |e, i| e[1] == tv_pairs[i + 1][1] unless i == 23 }
    day_types = obj[:day_types].split('|')
    day_types.each do |day_type|
      case day_type
      when 'Default'
        options['default_day'] = ['default'] + tv_pairs_reduced
      when 'WntrDsn'
        options['winter_design_day'] = tv_pairs_reduced
      when 'SmrDsn'
        options['summer_design_day'] = tv_pairs_reduced
      when 'Hol'
        # do nothing
      else
        start_date = DateTime.strptime(obj[:start_date]).strftime('%m/%d')
        end_date = DateTime.strptime(obj[:end_date]).strftime('%m/%d')
        rule_a = [day_type]
        rule_a << "#{start_date}-#{end_date}"
        rule_a << day_type
        rule_a += tv_pairs_reduced
        options['rules'] << rule_a
      end
    end
  end
  return options
end

def convert_all_schedules(create_osm: false)
  base_dir = File.dirname(__FILE__), '../standards/ashrae_90_1/data'
  data_path = File.join(base_dir, 'ashrae_90_1.schedules.cleaned.json')

  data = load_schedule_data(data_path)

  puts data[:schedules].select { |obj| obj[:category] == 'Occupancy' }.size

  occ_sch_data = select_schedules_by_category(data[:schedules], 'Occupancy')

  puts occ_sch_data.first

  names = occ_sch_data.map { |obj| obj[:name] }.uniq

  # names = ['Large Office Bldg Occ']

  all_parametric_data = []
  names.each do |name|
    sch_data = occ_sch_data.select { |obj| obj[:name] == name }
    parametric_form = derive_schedule_parameters_from_data(sch_data)
    all_parametric_data += parametric_form
  end

  File.write(File.join(base_dir, 'occ_sch_parametric.json'), JSON.pretty_generate(all_parametric_data))

  return unless create_osm

  puts 'Creating OpenStudio model with converted schedules...'
  model = OpenStudio::Model::Model.new
  model.getTimestep.setNumberOfTimestepsPerHour(1)

  # create schedules from parametric form
  names.each do |name|
    param_data = all_parametric_data.select { |obj| obj[:name] == name }
    OpenstudioStandards::Schedules.model_add_parametric_schedule_full(model, param_data, name, {})

    # create equivalent schedules from standard data
    sch_data = occ_sch_data.select { |obj| obj[:name] == name }
    standard_sch_inputs = schedule_data_to_input_hash(sch_data)

    OpenstudioStandards::Schedules.create_complex_schedule(model, standard_sch_inputs)
  end

  model.save('occ_sch_parametric.osm', true)
end

convert_all_schedules(create_osm: true)
