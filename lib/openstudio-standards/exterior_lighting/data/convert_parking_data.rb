# These methods convert parking data to and from .csv for editing.
private

require 'csv'
require 'json'

def parking_csv_to_json(input_csv = 'parking.csv',
                        output_json = 'parking.json')
  # Initialize the structure
  result = {
    parking: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    building_type = row[:building_type]
    building_area_per_spot = row[:building_area_per_spot]&.to_f
    units_per_spot = row[:units_per_spot]&.to_f
    students_per_spot = row[:students_per_spot]&.to_f
    beds_per_spot = row[:beds_per_spot]&.to_f
    parking_area_per_spot = row[:parking_area_per_spot]&.to_f

    parking_hash = {
      building_type: building_type,
      building_area_per_spot: building_area_per_spot,
      units_per_spot: units_per_spot,
      students_per_spot: students_per_spot,
      beds_per_spot: beds_per_spot,
      parking_area_per_spot: parking_area_per_spot
    }

    # Add the space_type_hash to the result array
    result[:parking] << parking_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
parking_csv_to_json

def parking_json_to_csv(input_json = 'parking.json',
                        output_csv = 'parking.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :building_type,
    :building_area_per_spot,
    :units_per_spot,
    :students_per_spot,
    :beds_per_spot,
    :parking_area_per_spot
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:parking].each do |parking_entry|
      building_type = parking_entry[:building_type]
      building_area_per_spot = parking_entry[:building_area_per_spot]
      units_per_spot = parking_entry[:units_per_spot]
      students_per_spot = parking_entry[:students_per_spot]
      beds_per_spot = parking_entry[:beds_per_spot]
      parking_area_per_spot = parking_entry[:parking_area_per_spot]

      csv << [
        building_type,
        building_area_per_spot,
        units_per_spot,
        students_per_spot,
        beds_per_spot,
        parking_area_per_spot
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
