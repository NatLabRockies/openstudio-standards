# These methods convert entryway data to and from .csv for editing.
private

require 'csv'
require 'json'

def entryways_csv_to_json(input_csv = 'entryways.csv',
                          output_json = 'entryways.json')
  # Initialize the structure
  result = {
    entryways: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    building_type = row[:building_type]
    rollup_doors_per_10000_ft2 = row[:rollup_doors_per_10000_ft2]&.to_f
    entrance_doors_per_10000_ft2 = row[:entrance_doors_per_10000_ft2]&.to_f
    other_doors_per_10000_ft2 = row[:other_doors_per_10000_ft2]&.to_f
    entrance_canopies = row[:entrance_canopies]&.to_f
    emergency_canopies = row[:emergency_canopies]&.to_f
    canopy_size = row[:canopy_size]&.to_f
    floor_area_per_drive_through_window = row[:floor_area_per_drive_through_window]&.to_f
    notes = row[:notes]

    entryways_hash = {
      building_type: building_type,
      rollup_doors_per_10000_ft2: rollup_doors_per_10000_ft2,
      entrance_doors_per_10000_ft2: entrance_doors_per_10000_ft2,
      other_doors_per_10000_ft2: other_doors_per_10000_ft2,
      entrance_canopies: entrance_canopies,
      emergency_canopies: emergency_canopies,
      canopy_size: canopy_size,
      floor_area_per_drive_through_window: floor_area_per_drive_through_window,
      notes: notes
    }

    # Add the space_type_hash to the result array
    result[:entryways] << entryways_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
entryways_csv_to_json

def entryways_json_to_csv(input_json = 'entryways.json',
                          output_csv = 'entryways.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :building_type,
    :rollup_doors_per_10000_ft2,
    :entrance_doors_per_10000_ft2,
    :other_doors_per_10000_ft2,
    :entrance_canopies,
    :parking_area_pemergency_canopieser_spot
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:entryways].each do |entryways|
      building_type = entryways[:building_type]
      rollup_doors_per_10000_ft2 = entryways[:rollup_doors_per_10000_ft2]
      entrance_doors_per_10000_ft2 = entryways[:entrance_doors_per_10000_ft2]
      other_doors_per_10000_ft2 = entryways[:other_doors_per_10000_ft2]
      entrance_canopies = entryways[:entrance_canopies]
      emergency_canopies = entryways[:emergency_canopies]
      canopy_size = entryways[:canopy_size]
      floor_area_per_drive_through_window = entryways[:floor_area_per_drive_through_window]
      notes = entryways[:notes]

      csv << [
        building_type,
        rollup_doors_per_10000_ft2,
        entrance_doors_per_10000_ft2,
        other_doors_per_10000_ft2,
        entrance_canopies,
        emergency_canopies,
        canopy_size,
        floor_area_per_drive_through_window,
        notes
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
