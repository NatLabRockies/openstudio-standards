# These methods convert exhuast fan data to and from .csv for editing.
private

require 'csv'
require 'json'

def typical_exhaust_csv_to_json(input_csv = 'typical_exhaust.csv',
                                output_json = 'typical_exhaust.json')
  # Initialize the structure
  result = {
    space_types: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    space_type = row[:space_type]
    building_type = row[:building_type]
    exhaust_per_area = row[:exhaust_per_area]

    space_type_hash = {
      space_type: space_type,
      building_type: building_type,
      exhaust_per_area: exhaust_per_area
    }

    # Add the space_type_hash to the result array
    result[:space_types] << space_type_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
typical_exhaust_csv_to_json

def typical_exhaust_json_to_csv(input_json = 'typical_exhaust.json',
                                output_csv = 'typical_exhaust.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :space_type,
    :building_type,
    :exhaust_per_area
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:space_types].each do |space_type_entry|
      space_type = space_type_entry[:space_type]
      building_type = space_type_entry[:building_type]
      exhaust_per_area = space_type_entry[:exhaust_per_area]

      csv << [
        space_type,
        building_type,
        exhaust_per_area
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
