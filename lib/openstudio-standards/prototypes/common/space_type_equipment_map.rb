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
new_space_types_additional_properties = JSON.parse(File.read("#{File.dirname(__FILE__)}/../../../openstudio-standards/space_type/data/level_1_space_types.json"), symbolize_names: true)

# loop through space types and store equipment data
all_data_json = []
templates.each do |template|
  std = Standard.build(template)
  space_type_data = std.standards_data['space_types']
  space_type_data.each do |e|
    standards_building_type = e['building_type']
    standards_space_type = e['space_type']
    map = prototype_map.find { |s| s[:standards_building_type] == standards_building_type && s[:standards_space_type] == standards_space_type }
    new_space_type = map.nil? ? nil : map[:new_standards_space_type]
    space_data = new_space_types_additional_properties.find { |s| s[:space_type_name] == new_space_type }
    electric_equipment_space_type_name = space_data.nil? ? nil : space_data[:electric_equipment_space_type_name]
    natural_gas_equipment_space_type_name = space_data.nil? ? nil : space_data[:natural_gas_equipment_space_type_name]

    all_data_json << {
      template: e['template'],
      standards_building_type: standards_building_type,
      standards_space_type: standards_space_type,
      electric_equipment_per_area: e['electric_equipment_per_area'],
      electric_equipment_fraction_latent: e['electric_equipment_fraction_latent'],
      electric_equipment_fraction_radiant: e['electric_equipment_fraction_radiant'],
      electric_equipment_fraction_lost: e['electric_equipment_fraction_lost'],
      gas_equipment_per_area: e['gas_equipment_per_area'],
      gas_equipment_fraction_latent: e['gas_equipment_fraction_latent'],
      gas_equipment_fraction_radiant: e['gas_equipment_fraction_radiant'],
      gas_equipment_fraction_lost: e['gas_equipment_fraction_lost'],
      new_space_type: new_space_type,
      electric_equipment_space_type_name: electric_equipment_space_type_name,
      natural_gas_equipment_space_type_name: natural_gas_equipment_space_type_name
    }
  end
end
all_data_json = all_data_json.sort_by { |h| h[:standards_space_type] }
all_data_json = all_data_json.sort_by { |h| h[:standards_building_type] }

# # Write to csv file
# CSV.open('data/prototype_equipment_map_intermediate.csv', 'w') do |csv|
#   csv << all_data_json.first.keys
#   all_data_json.each do |row|
#     csv << row.values
#   end
# end

# # Write to json file
# File.write('data/prototype_equipment_map_intermediate.json', JSON.pretty_generate(all_data_json))

# get equipment space type names from new_space_type field in the hashes of the all_data_json file, an array of hashes
all_electric_space_types = all_data_json.map { |h| h[:electric_equipment_space_type_name] }.compact.uniq
all_gas_space_types = all_data_json.map { |h| h[:natural_gas_equipment_space_type_name] }.compact.uniq

puts "Found #{all_electric_space_types.size} electric equipment space types and #{all_gas_space_types.size} gas equipment space types."

# for each electric equipment space type, check if there is a unique epd if so, return it. if not, report for each building type for the ComStock 90.1-2010 version
electric_equipment_lookup = []
all_electric_space_types.each do |electric_equipment_space_type|
  elec_space_type_data = all_data_json.select { |h| (h[:electric_equipment_space_type_name] == electric_equipment_space_type) }
  epds = elec_space_type_data.map { |h| h[:electric_equipment_per_area] }.compact.uniq

  # check if there is a unique equipment setup for this space type
  # if so, report it out
  if epds.size < 2
    lookup = {
      electric_equipment_space_type_name: electric_equipment_space_type,
      standards_building_type: nil,
      electric_equipment_per_area: epds[0],
      electric_equipment_per_area_units: 'W/ft^2',
      electric_equipment_fraction_latent: elec_space_type_data[0][:electric_equipment_fraction_latent],
      electric_equipment_fraction_radiant: elec_space_type_data[0][:electric_equipment_fraction_radiant],
      electric_equipment_fraction_lost: elec_space_type_data[0][:electric_equipment_fraction_lost]
    }

    electric_equipment_lookup << lookup
    next
  end

  # if not, filter by standards building type
  space_type_bldg_types = elec_space_type_data.map { |h| h[:standards_building_type] }.compact.uniq
  space_type_bldg_types.each do |bldg_type|
    bldg_type_elec_space_type_data = elec_space_type_data.select { |h| h[:standards_building_type] == bldg_type }
    epds = bldg_type_elec_space_type_data.map { |h| h[:electric_equipment_per_area] }.compact.uniq
    if epds.size > 1
      puts "Multiple electric equipment options found for space type #{electric_equipment_space_type} in building type #{bldg_type}. Logging ComStock 90.1-2010 data."
      bldg_type_elec_space_type_data = bldg_type_elec_space_type_data.select { |h| (h[:template] == 'ComStock 90.1-2010') }
    end
    if bldg_type_elec_space_type_data[0].nil?
      puts "No electric equipment data found for space type #{electric_equipment_space_type} in building type #{bldg_type}."
    else
      lookup = {
        electric_equipment_space_type_name: electric_equipment_space_type,
        standards_building_type: bldg_type,
        electric_equipment_per_area: bldg_type_elec_space_type_data[0][:electric_equipment_per_area],
        electric_equipment_per_area_units: 'W/ft^2',
        electric_equipment_fraction_latent: bldg_type_elec_space_type_data[0][:electric_equipment_fraction_latent],
        electric_equipment_fraction_radiant: bldg_type_elec_space_type_data[0][:electric_equipment_fraction_radiant],
        electric_equipment_fraction_lost: bldg_type_elec_space_type_data[0][:electric_equipment_fraction_lost]
      }
      electric_equipment_lookup << lookup
    end
  end
end

# Write to json file
File.write('data/electric_equipment_space_types.json', JSON.pretty_generate(electric_equipment_lookup))

# for each gas equipment space type, check if there is a unique epd if so, return it. if not, report for each building type for the ComStock 90.1-2010 version
gas_equipment_lookup = []
all_gas_space_types.each do |gas_equipment_space_type|
  gas_space_type_data = all_data_json.select { |h| (h[:natural_gas_equipment_space_type_name] == gas_equipment_space_type) }
  gpds = gas_space_type_data.map { |h| h[:gas_equipment_per_area] }.compact.uniq

  # check if there is a unique equipment setup for this space type
  # if so, report it out
  if gpds.size < 2
    lookup = {
      natural_gas_equipment_space_type_name: gas_equipment_space_type,
      standards_building_type: nil,
      gas_equipment_per_area: gpds[0],
      gas_equipment_per_area_units: 'Btu/hr*ft^2',
      gas_equipment_fraction_latent: gas_space_type_data[0][:gas_equipment_fraction_latent],
      gas_equipment_fraction_radiant: gas_space_type_data[0][:gas_equipment_fraction_radiant],
      gas_equipment_fraction_lost: gas_space_type_data[0][:gas_equipment_fraction_lost]
    }

    gas_equipment_lookup << lookup
    next
  end

  # if not, filter by standards building type
  space_type_bldg_types = gas_space_type_data.map { |h| h[:standards_building_type] }.compact.uniq
  space_type_bldg_types.each do |bldg_type|
    bldg_type_gas_space_type_data = gas_space_type_data.select { |h| h[:standards_building_type] == bldg_type }
    gpds = bldg_type_gas_space_type_data.map { |h| h[:gas_equipment_per_area] }.compact.uniq
    if gpds.size > 1
      puts "Multiple gas equipment options found for space type #{gas_equipment_space_type} in building type #{bldg_type}. Logging ComStock 90.1-2010 data."
      bldg_type_gas_space_type_data = bldg_type_gas_space_type_data.select { |h| (h[:template] == 'ComStock 90.1-2010') }
    end
    if bldg_type_gas_space_type_data[0].nil?
      puts "No gas equipment data found for space type #{gas_equipment_space_type} in building type #{bldg_type}."
    else
      lookup = {
        natural_gas_equipment_space_type_name: gas_equipment_space_type,
        standards_building_type: bldg_type,
        gas_equipment_per_area: bldg_type_gas_space_type_data[0][:gas_equipment_per_area],
        gas_equipment_per_area_units: 'Btu/hr*ft^2',
        gas_equipment_fraction_latent: bldg_type_gas_space_type_data[0][:gas_equipment_fraction_latent],
        gas_equipment_fraction_radiant: bldg_type_gas_space_type_data[0][:gas_equipment_fraction_radiant],
        gas_equipment_fraction_lost: bldg_type_gas_space_type_data[0][:gas_equipment_fraction_lost]
      }
      gas_equipment_lookup << lookup
    end
  end
end

# Write to json file
File.write('data/gas_equipment_space_types.json', JSON.pretty_generate(gas_equipment_lookup))
