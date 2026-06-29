require 'openstudio'
require 'json'
require 'csv'
require_relative 'create'
require_relative 'add_schedule_parametric'

def load_schedule_data(path)
  file_content = File.read(path)
  return JSON.parse(file_content, symbolize_names: true)
end

def select_schedules_by_category(schedules, selection_key)
  return schedules.select { |obj| obj[:category] == selection_key }
end

# translates standards occupancy schedule data to parametric form
def schedule_data_to_parametric(data)
  all_parametric_data = []

  data.each do |obj|
    param_data = {}
    param_data[:name] = obj[:name]
    param_data[:category] = obj[:category]
    param_data[:units] = obj[:units]
    param_data[:day_types] = obj[:day_types]
    param_data[:start_date] = obj[:start_date]
    param_data[:end_date] = obj[:end_date]
    param_data[:type] = 'parametric'

    hr_data = obj.select { |k, v| k.to_s.include?('hr_') }
    hr_vals = hr_data.values
    base = hr_vals.min
    peak = hr_vals.max

    max_pos_chg = 0
    max_neg_chg = 0
    st = 0
    et = 0
    hr_vals.each_with_index do |val, i|
      next if i == 0

      change = val - hr_vals[i - 1]
      if change > max_pos_chg
        max_pos_chg = change
        st = i + 1
      end

      if change < max_neg_chg
        max_neg_chg = change
        et = i + 1
      end
    end

    # diff between st and last time of base val before st
    base_st_adj = 0
    base_et_adj = 0
    peak_st_adj = 0
    peak_et_adj = 0

    last_base_idx = hr_vals[0...st].rindex(base)
    base_st_adj = last_base_idx - (st - 1) unless last_base_idx.nil?
    peak_st_adj = [0, hr_vals.index(peak) - (st - 1)].max

    last_peak_idx = hr_vals[st...et].rindex(peak)
    peak_et_adj = (st + last_peak_idx + 1) - et unless last_peak_idx.nil?

    base_et_adj = [0, hr_vals[et..].index(base)].max unless hr_vals[et..].index(base).nil?

    param_data[:base_std] = base
    param_data[:peak_std] = peak
    param_data[:st_std] = st
    param_data[:et_std] = et
    param_data[:control_points] = [
      ['st', { '+': base_st_adj }, 'base', {}],
      ['st', { '+': peak_st_adj }, 'peak', {}],
      ['et', { '+': peak_et_adj }, 'peak', {}],
      ['et', { '+': base_et_adj }, 'base', {}]
    ]
    all_parametric_data << param_data
  end
  return all_parametric_data
end

def write_data_to_csv(data)
  names = data.first.keys
  c = CSV.generate do |csv|
    csv << names
    data.each do |o|
      csv << o.values
    end
  end
  puts 'writing csv'
  File.write('data_summary.csv', c)
end

# translate standard schedule data to a form usable by OpenstudioStandards::Schedules.create_complex_schedule
def schedule_data_to_input_hash(schedule_array)
  # schedule_array is an array of hashes with profiles of the same name
  options = {}
  options['name'] = schedule_array[0][:name]
  options['rules'] = []
  schedule_array.each do |obj|
    hr_data = obj.select { |k, v| k.to_s.include?('hr_') }
    tv_pairs = hr_data.keys.map { |k| k.to_s.gsub('hr_', '').to_f }.zip(hr_data.values)
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
        start_date = DateTime.strptime(obj[:start_date], '%m/%d/%Y').strftime('%m/%d')
        end_date = DateTime.strptime(obj[:end_date], '%m/%d/%Y').strftime('%m/%d')
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

def convert_all_schedules
  data_path = 'C:/Repos/PNNL/building-energy-standards-data/building_energy_standards_data/database_files/support_schedules.json'
  data = load_schedule_data(data_path)

  occ_sch_data = select_schedules_by_category(data, 'Occupancy')
  # occ_sch_data = find_values(occ_sch_data)
  # write_data_to_csv(occ_sch_data)

  names = occ_sch_data.map { |obj| obj[:name] }.uniq

  # puts names

  model = OpenStudio::Model::Model.new
  model.getTimestep.setNumberOfTimestepsPerHour(4)
  names.each do |name|
    print "Processing #{name}"
    sch_data = occ_sch_data.select { |e| e[:name] == name }

    parametric_form = schedule_data_to_parametric(sch_data)

    OpenstudioStandards::Schedules.create_parametric_schedule_full(model, parametric_form, name, {})

    # create equivalent schedule from standard data
    standard_sch_inputs = schedule_data_to_input_hash(sch_data)
    OpenstudioStandards::Schedules.create_complex_schedule(model, standard_sch_inputs)
  end

  model.save('test_compare_all.osm', true)
end

convert_all_schedules
