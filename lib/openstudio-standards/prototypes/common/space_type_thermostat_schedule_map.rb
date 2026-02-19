# Create a .json for new space type thermostat setpoint schedules
require 'openstudio-standards'

# print gem version
puts "Using openstudio-standards version #{Gem.loaded_specs['openstudio-standards'].version}"

templates = [
  'ComStock DOE Ref Pre-1980',
  'ComStock DOE Ref 1980-2004',
  'ComStock 90.1-2004',
  'ComStock 90.1-2007',
  'ComStock 90.1-2010',
  'ComStock 90.1-2013',
  'ComStock 90.1-2016',
  'ComStock 90.1-2019',
  'ComStock DEER 1985',
  'ComStock DEER 1996',
  'ComStock DEER 2003',
  'ComStock DEER 2007',
  'ComStock DEER 2011',
  'ComStock DEER 2014',
  'ComStock DEER 2015',
  'ComStock DEER 2017',
  'ComStock DEER 2020'
]

prototype_map = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/prototype_space_type_map.json"), symbolize_names: true)

# loop through space types and store thermostat data
all_data_json = []
templates.each do |template|
  std = Standard.build(template)
  space_type_data = std.standards_data['space_types']
  space_type_data.each do |e|
    standards_building_type = e['building_type']
    standards_space_type = e['space_type']
    map = prototype_map.find { |s| s[:standards_building_type] == standards_building_type && s[:standards_space_type] == standards_space_type }
    new_space_type = map.nil? ? nil : map[:new_standards_space_type]

    all_data_json << {
      template: e['template'],
      standards_building_type: standards_building_type,
      standards_space_type: standards_space_type,
      heating_setpoint_schedule: e['heating_setpoint_schedule'],
      cooling_setpoint_schedule: e['cooling_setpoint_schedule'],
      new_space_type: new_space_type
    }
  end
end
all_data_json = all_data_json.sort_by { |h| h[:standards_space_type] }
all_data_json = all_data_json.sort_by { |h| h[:standards_building_type] }

# # Write to csv file
# CSV.open('data/prototype_thermostat_map_intermediate.csv', 'w') do |csv|
#   csv << all_data_json.first.keys
#   all_data_json.each do |row|
#     csv << row.values
#   end
# end

# # Write to json file
# File.write('data/prototype_thermostat_map_intermediate.json', JSON.pretty_generate(all_data_json))

# get space type names from new_space_type field in the hashes of the all_data_json file, an array of hashes
all_new_space_types = all_data_json.map { |h| h[:new_space_type] }.compact.uniq

# for each space type, check if there is a unique heating thermostat schedule and a unique thermostat schedule. if so, return it. if not, report for each building type. Then, if each building type has non-unique ones, report for 90.1-2013 version
thermostat_schedule_lookup = []
all_new_space_types.each do |new_space_type|
  new_space_type_data = all_data_json.select { |h| h[:new_space_type] == new_space_type }
  heating_thermostat_schs = new_space_type_data.map { |h| h[:heating_setpoint_schedule] }.compact.uniq
  cooling_thermostat_schs = new_space_type_data.map { |h| h[:cooling_setpoint_schedule] }.compact.uniq

  # check if there is a unique heating and cooling thermostat for this space type
  # if so, report it out
  if (heating_thermostat_schs.size < 2) && (cooling_thermostat_schs.size < 2)
    thermostat_schedule_lookup << {
      space_type: new_space_type,
      standards_building_type: nil,
      heating_setpoint_schedule: heating_thermostat_schs[0],
      cooling_setpoint_schedule: cooling_thermostat_schs[0]
    }
    next
  end

  # if not, check if there is a unique heating and cooling thermostat by standards building type
  # if so, log, otherwise use 90.1-2013
  space_type_bldg_types = new_space_type_data.map { |h| h[:standards_building_type] }.compact.uniq
  space_type_bldg_types.each do |bldg_type|
    data_subset = new_space_type_data.select { |h| h[:standards_building_type] == bldg_type }
    heating_thermostat_schs = data_subset.map { |h| h[:heating_setpoint_schedule] }.compact.uniq
    cooling_thermostat_schs = data_subset.map { |h| h[:cooling_setpoint_schedule] }.compact.uniq
    if (heating_thermostat_schs.size < 2) && (cooling_thermostat_schs.size < 2)
      thermostat_schedule_lookup << {
        space_type: new_space_type,
        standards_building_type: bldg_type,
        heating_setpoint_schedule: heating_thermostat_schs[0],
        cooling_setpoint_schedule: cooling_thermostat_schs[0]
      }
    else
      puts "Space type '#{new_space_type}' and standards building type '#{bldg_type}' has #{heating_thermostat_schs.size} heating setpoint schedules and #{cooling_thermostat_schs.size} cooling setpoint schedules, depending on the template. Using 'ComStock 90.1-2013'."
      data_subset = data_subset.select { |h| h[:template] == 'ComStock 90.1-2013' }[0]
      heating_thermostat_sch = data_subset.nil? ? nil : data_subset[:heating_setpoint_schedule]
      cooling_thermostat_sch = data_subset.nil? ? nil : data_subset[:cooling_setpoint_schedule]
      thermostat_schedule_lookup << {
        space_type: new_space_type,
        standards_building_type: bldg_type,
        heating_setpoint_schedule: heating_thermostat_sch,
        cooling_setpoint_schedule: cooling_thermostat_sch
      }
    end
  end
end

# Write to json file
File.write('data/thermostat_schedule_lookup.json', JSON.pretty_generate(thermostat_schedule_lookup))
