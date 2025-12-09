# These methods convert space type data to and from .csv for easy editing.
private

require 'csv'
require 'json'

# Space Type Data Schema
# Space types are composed of set of sub space types that define the internal loads, ventilation, and schedules.
# Occupancy is currently determined from the ventilation space type.
#
# space_type_name: The name of the space type
# annotation: notes on the space type and completeness of data
# lighting_space_type_name: The lighting typical to this space type
# electric_equipment_space_type_name: The electric equipment typical to this space type
# natural_gas_equipment_space_type_name: The natural gas equipment typical to this space type
# refrigeration_space_type_name: The refrigeration typical to this space type
# service_water_space_type_name: The service water typical to this space type
# ventilation_space_type_name: The ventilation typical to this space type.
# schedule_set_name: The schedule set typical to this space type.

def convert_space_type_data_to_json(input_csv = 'space_types.csv',
                                    output_json = 'space_types.json')
  # Initialize the structure
  result = []

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    space_type_hash = {
      space_type_name: row[:space_type_name],
      description: row[:description],
      annotation: row[:annotation],
      lighting_space_type_name: row[:lighting_space_type_name],
      electric_equipment_space_type_name: row[:electric_equipment_space_type_name],
      natural_gas_equipment_space_type_name: row[:natural_gas_equipment_space_type_name],
      refrigeration_space_type_name: row[:refrigeration_space_type_name],
      service_water_space_type_name: row[:service_water_space_type_name],
      ventilation_space_type_name: row[:ventilation_space_type_name],
      schedule_set_name: row[:schedule_set_name]
    }

    # Add the space_type_hash to the result array
    result << space_type_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

def convert_space_type_data_to_csv(input_json = 'space_types.json',
                                   output_csv = 'space_types.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :space_type_name,
    :description,
    :annotation,
    :lighting_space_type_name,
    :electric_equipment_space_type_name,
    :natural_gas_equipment_space_type_name,
    :refrigeration_space_type_name,
    :service_water_space_type_name,
    :ventilation_space_type_name,
    :schedule_set_name
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data.each do |space_type_entry|
      csv << [
        space_type_entry[:space_type_name],
        space_type_entry[:description],
        space_type_entry[:annotation],
        space_type_entry[:lighting_space_type_name],
        space_type_entry[:electric_equipment_space_type_name],
        space_type_entry[:natural_gas_equipment_space_type_name],
        space_type_entry[:refrigeration_space_type_name],
        space_type_entry[:service_water_space_type_name],
        space_type_entry[:ventilation_space_type_name],
        space_type_entry[:schedule_set_name]
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
