# These methods convert infiltration data to and from .csv for editing.
private

require 'csv'
require 'json'

def infiltration_csv_to_json(input_csv = 'NISTInfiltrationCorrelations.csv',
                             output_json = 'NISTInfiltrationCorrelations.json')
  # Initialize the structure
  result = {
    infiltration: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    building_type = row[:building_type]
    climate_zone = row[:climate_zone]
    air_barrier = row[:air_barrier]
    hvac_status = row[:hvac_status]
    a = row[:a]&.to_f
    b = row[:b]&.to_f
    d = row[:d]&.to_f

    infiltration_hash = {
      building_type: building_type,
      climate_zone: climate_zone,
      air_barrier: air_barrier,
      hvac_status: hvac_status,
      a: a,
      b: b,
      d: d
    }

    # Add the space_type_hash to the result array
    result[:infiltration] << infiltration_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
infiltration_csv_to_json

def infiltration_json_to_csv(input_json = 'NISTInfiltrationCorrelations.json',
                             output_csv = 'NISTInfiltrationCorrelations.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :building_type,
    :climate_zone,
    :air_barrier,
    :hvac_status,
    :a,
    :b,
    :d
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:infiltration].each do |infiltration_entry|
      building_type = infiltration_entry[:building_type]
      climate_zone = infiltration_entry[:climate_zone]
      air_barrier = infiltration_entry[:air_barrier]
      hvac_status = infiltration_entry[:hvac_status]
      a = infiltration_entry[:a]
      b = infiltration_entry[:b]
      d = infiltration_entry[:d]

      csv << [
        building_type,
        climate_zone,
        air_barrier,
        hvac_status,
        a,
        b,
        d
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
