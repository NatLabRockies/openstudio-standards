# These methods convert space type service water heating equipment data to and from .csv for editing.
private

require 'csv'
require 'json'

# Typical Water Use Equipment Data Schema
# equipment_name: The name of the specific piece of equipment. The space name will be prepended, and flow rate and temperature appended to the name.
# peak_flow_rate: The peak flow rate in gallons per hour
# peak_flow_rate_per_area: The peak flow rate in gallons per hour per ft^2 of floor area. Only used if 'peak_flow_rate' is unspecified.
# loop_type: Several options are available.
#  - 'One Per Space': This water use equipment uses a dedicated loop in each space.
#  - 'One Per Unit': This water use equipment uses a dedicated loop in each space. Water use equipment flow rates are multiplied by the 'num_units' additional property on the Space object.
#  - 'Shared': Equipment will use the shared building service hot water loop.
#  - 'One Per Space Type Adjacent': Not yet supported. Will create a dedicated loop to serve all adjacent equipment of the same space type.
#  - 'One Per Building Type Adjacent': Not yet supported. Will create a dedicated loop to serve all adjacent equipment of the same building type.
# temperature: Target mixed water temperature at the water use, in degrees Fahrenheit
# flow_rate_schedule: The name of the flow rate schedule from the schedules .json
# sensible_fraction: The fraction of heat content converted to space sensible load
# latent_fraction: The fraction of heat content converted to space latent load

# Future Schema inclusions?
# minimum_space_size: Not yet supported. Only add this water use if the space is above this size of floor area.
# minimum_tank_volume: Not yet supported. The minimum tank volume to use for dedicated loops. The default is 40 gallons.

def csv_to_json(input_csv = 'typical_water_use_equipment.csv',
                output_json = 'typical_water_use_equipment.json')
  # Initialize the structure
  result = {
    space_types: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    space_type = row[:space_type]
    building_type = row[:building_type]

    # Add water_use_equipment entry
    water_use_entry = {
      equipment_name: row[:equipment_name],
      peak_flow_rate_gph: row[:peak_flow_rate_gph]&.to_f, # gallons / hour
      peak_flow_rate_gph_per_floor_area_ft2: row[:peak_flow_rate_gph_per_floor_area_ft2]&.to_f, # gallons / hour-ft^2
      loop_type: row[:loop_type],
      mixed_water_temperature_f: row[:mixed_water_temperature_f]&.to_f, # deg F
      flow_rate_schedule: row[:flow_rate_schedule],
      sensible_fraction: row[:sensible_fraction]&.to_f,
      latent_fraction: row[:latent_fraction]&.to_f
    }

    # Initialize a new space_type entry if it doesn't exist
    space_type_hash = result[:space_types].select { |hash| (hash[:space_type] == space_type) && (hash[:building_type] == building_type) }
    space_type_hash = space_type_hash[0]

    if space_type_hash.nil?
      space_type_hash = {
        space_type: space_type,
        building_type: building_type,
        water_use_equipment: [water_use_entry]
      }
      # Add the space_type_hash to the result array
      result[:space_types] << space_type_hash
    else
      space_type_hash[:water_use_equipment] << water_use_entry
    end
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
csv_to_json

def json_to_csv(input_json = 'typical_water_use_equipment.json',
                output_csv = 'typical_water_use_equipment_converted.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :space_type,
    :building_type,
    :equipment_name,
    :peak_flow_rate_gph,
    :peak_flow_rate_gph_per_floor_area_ft2,
    :loop_type,
    :mixed_water_temperature_f,
    :flow_rate_schedule,
    :sensible_fraction,
    :latent_fraction
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:space_types].each do |space_type_entry|
      space_type = space_type_entry[:space_type]
      building_type = space_type_entry[:building_type]

      space_type_entry[:water_use_equipment].each do |equipment|
        csv << [
          space_type,
          building_type,
          equipment[:equipment_name],
          equipment[:peak_flow_rate_gph],
          equipment[:peak_flow_rate_gph_per_floor_area_ft2],
          equipment[:loop_type],
          equipment[:mixed_water_temperature_f],
          equipment[:flow_rate_schedule],
          equipment[:sensible_fraction],
          equipment[:latent_fraction]
        ]
      end
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
