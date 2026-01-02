# These methods convert space type interior lighting data to and from .csv for editing.
private

require 'csv'
require 'json'

def lighting_space_types_csv_to_json(input_csv = 'lighting_space_types.csv',
                                     output_json = 'lighting_space_types.json')
  # Initialize the structure
  result = {
    lighting_space_types: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    lighting_space_type_name = row[:lighting_space_type_name]
    lighting_space_type_target_illuminance_setpoint = row[:lighting_space_type_target_illuminance_setpoint]&.to_f
    lighting_space_type_target_illuminance_units = row[:lighting_space_type_target_illuminance_units]
    general_lighting_fraction = row[:general_lighting_fraction]&.to_f
    general_lighting_coefficient_of_utilization = row[:general_lighting_coefficient_of_utilization]&.to_f
    task_lighting_fraction = row[:task_lighting_fraction]&.to_f
    task_lighting_coefficient_of_utilization = row[:task_lighting_coefficient_of_utilization]&.to_f
    supplemental_lighting_fraction = row[:supplemental_lighting_fraction]&.to_f
    supplemental_lighting_coefficient_of_utilization = row[:supplemental_lighting_coefficient_of_utilization]&.to_f
    wall_wash_lighting_fraction = row[:wall_wash_lighting_fraction]&.to_f
    wall_wash_lighting_coefficient_of_utilization = row[:wall_wash_lighting_coefficient_of_utilization]&.to_f
    source = row[:source]
    notes = row[:notes]

    lighting_space_type_hash = {
      lighting_space_type_name: lighting_space_type_name,
      lighting_space_type_target_illuminance_setpoint: lighting_space_type_target_illuminance_setpoint,
      lighting_space_type_target_illuminance_units: lighting_space_type_target_illuminance_units,
      general_lighting_fraction: general_lighting_fraction,
      general_lighting_coefficient_of_utilization: general_lighting_coefficient_of_utilization,
      task_lighting_fraction: task_lighting_fraction,
      task_lighting_coefficient_of_utilization: task_lighting_coefficient_of_utilization,
      supplemental_lighting_fraction: supplemental_lighting_fraction,
      supplemental_lighting_coefficient_of_utilization: supplemental_lighting_coefficient_of_utilization,
      wall_wash_lighting_fraction: wall_wash_lighting_fraction,
      wall_wash_lighting_coefficient_of_utilization: wall_wash_lighting_coefficient_of_utilization,
      source: source,
      notes: notes
    }

    # Add the lighting_space_type_hash to the result array
    result[:lighting_space_types] << lighting_space_type_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
lighting_space_types_csv_to_json

def lighting_space_types_json_to_csv(input_json = 'lighting_space_types.json',
                                     output_csv = 'lighting_space_types.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :lighting_space_type_name,
    :lighting_space_type_target_illuminance_setpoint,
    :lighting_space_type_target_illuminance_units,
    :general_lighting_fraction,
    :general_lighting_coefficient_of_utilization,
    :task_lighting_fraction,
    :task_lighting_coefficient_of_utilization,
    :supplemental_lighting_fraction,
    :supplemental_lighting_coefficient_of_utilization,
    :wall_wash_lighting_fraction,
    :wall_wash_lighting_coefficient_of_utilization,
    :source,
    :notes
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:lighting_space_types].each do |entry|
      lighting_space_type_name = entry[:lighting_space_type_name]
      lighting_space_type_target_illuminance_setpoint = entry[:lighting_space_type_target_illuminance_setpoint]
      lighting_space_type_target_illuminance_units = entry[:lighting_space_type_target_illuminance_units]
      general_lighting_fraction = entry[:general_lighting_fraction]
      general_lighting_coefficient_of_utilization = entry[:general_lighting_coefficient_of_utilization]
      task_lighting_fraction = entry[:task_lighting_fraction]
      task_lighting_coefficient_of_utilization = entry[:task_lighting_coefficient_of_utilization]
      supplemental_lighting_fraction = entry[:supplemental_lighting_fraction]
      supplemental_lighting_coefficient_of_utilization = entry[:supplemental_lighting_coefficient_of_utilization]
      wall_wash_lighting_fraction = entry[:wall_wash_lighting_fraction]
      wall_wash_lighting_coefficient_of_utilization = entry[:wall_wash_lighting_coefficient_of_utilization]
      source = entry[:source]
      notes = entry[:notes]

      csv << [
        lighting_space_type_name,
        buillighting_space_type_target_illuminance_setpointding_type,
        lighting_space_type_target_illuminance_units,
        general_lighting_fraction,
        general_lighting_coefficient_of_utilization,
        task_lighting_fraction,
        task_lighting_coefficient_of_utilization,
        supplemental_lighting_fraction,
        supplemental_lighting_coefficient_of_utilization,
        wall_wash_lighting_fraction,
        wall_wash_lighting_coefficient_of_utilization,
        source,
        notes
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end

def lighting_technology_csv_to_json(input_csv = 'lighting_technology.csv',
                                    output_json = 'lighting_technology.json')
  # Initialize the structure
  result = {
    lighting_technologies: []
  }

  # Read the CSV file
  CSV.foreach(input_csv, headers: true, header_converters: :symbol) do |row|
    lighting_technology = row[:lighting_technology]
    lighting_generation = row[:lighting_generation]
    lighting_system_type = row[:lighting_system_type]
    fixture_type = row[:fixture_type]
    lamp_type = row[:lamp_type]
    fixture_min_height_ft = row[:fixture_min_height_ft]&.to_f
    fixture_max_height_ft = row[:fixture_max_height_ft]&.to_f
    source_efficacy_lumens_per_watt = row[:source_efficacy_lumens_per_watt]&.to_f
    source_efficacy_reference = row[:source_efficacy_reference]
    lamp_lumen_depreciation = row[:lamp_lumen_depreciation]&.to_f
    luminaire_dirt_depreciation = row[:luminaire_dirt_depreciation]&.to_f
    lighting_loss_factor = row[:lighting_loss_factor]&.to_f
    lighting_loss_factor_reference = row[:lighting_loss_factor_reference]
    return_air_fraction = row[:return_air_fraction]&.to_f
    radiant_fraction = row[:radiant_fraction]&.to_f
    visible_fraction = row[:visible_fraction]&.to_f
    radiant_fraction_reference = row[:radiant_fraction_reference]

    lighting_technology_hash = {
      lighting_technology: lighting_technology,
      lighting_generation: lighting_generation,
      lighting_system_type: lighting_system_type,
      fixture_type: fixture_type,
      lamp_type: lamp_type,
      fixture_min_height_ft: fixture_min_height_ft,
      fixture_max_height_ft: fixture_max_height_ft,
      source_efficacy_lumens_per_watt: source_efficacy_lumens_per_watt,
      source_efficacy_reference: source_efficacy_reference,
      lamp_lumen_depreciation: lamp_lumen_depreciation,
      luminaire_dirt_depreciation: luminaire_dirt_depreciation,
      lighting_loss_factor: lighting_loss_factor,
      lighting_loss_factor_reference: lighting_loss_factor_reference,
      return_air_fraction: return_air_fraction,
      radiant_fraction: radiant_fraction,
      visible_fraction: visible_fraction,
      radiant_fraction_reference: radiant_fraction_reference
    }

    # Add the lighting_technology_hash to the result array
    result[:lighting_technologies] << lighting_technology_hash
  end

  # Write to the output JSON file
  File.write(output_json, JSON.pretty_generate(result))

  puts "Data has been converted to JSON and saved to #{output_json}"
end

# convert to json
lighting_technology_csv_to_json

def lighting_technology_json_to_csv(input_json = 'lighting_technology.json',
                                    output_csv = 'lighting_technology.csv')
  # Read the JSON file
  data = JSON.parse(File.read(input_json), symbolize_names: true)

  # Prepare the CSV headers
  headers = [
    :lighting_technology,
    :lighting_generation,
    :lighting_system_type,
    :fixture_type,
    :lamp_type,
    :fixture_min_height_ft,
    :fixture_max_height_ft,
    :source_efficacy_lumens_per_watt,
    :source_efficacy_reference,
    :lamp_lumen_depreciation,
    :luminaire_dirt_depreciation,
    :lighting_loss_factor,
    :lighting_loss_factor_reference,
    :return_air_fraction,
    :radiant_fraction,
    :visible_fraction,
    :radiant_fraction_reference
  ]

  # Write the CSV file
  CSV.open(output_csv, 'w', write_headers: true, headers: headers) do |csv|
    data[:lighting_technologies].each do |entry|
      lighting_technology = entry[:lighting_technology]
      lighting_generation = entry[:lighting_generation]
      lighting_system_type = entry[:lighting_system_type]
      fixture_type = entry[:fixture_type]
      lamp_type = entry[:lamp_type]
      fixture_min_height_ft = entry[:fixture_min_height_ft]
      fixture_max_height_ft = entry[:fixture_max_height_ft]
      source_efficacy_lumens_per_watt = entry[:source_efficacy_lumens_per_watt]
      source_efficacy_reference = entry[:source_efficacy_reference]
      lamp_lumen_depreciation = entry[:lamp_lumen_depreciation]
      luminaire_dirt_depreciation = entry[:luminaire_dirt_depreciation]
      lighting_loss_factor = entry[:lighting_loss_factor]
      lighting_loss_factor_reference = entry[:lighting_loss_factor_reference]
      return_air_fraction = entry[:return_air_fraction]
      radiant_fraction = entry[:radiant_fraction]
      visible_fraction = entry[:visible_fraction]
      radiant_fraction_reference = entry[:radiant_fraction_reference]

      csv << [
        lighting_technology,
        lighting_generation,
        lighting_system_type,
        fixture_type,
        lamp_type,
        fixture_min_height_ft,
        fixture_max_height_ft,
        source_efficacy_lumens_per_watt,
        source_efficacy_reference,
        lamp_lumen_depreciation,
        luminaire_dirt_depreciation,
        lighting_loss_factor,
        lighting_loss_factor_reference,
        return_air_fraction,
        radiant_fraction,
        visible_fraction,
        radiant_fraction_reference
      ]
    end
  end

  puts "Data has been converted to CSV and saved to #{output_csv}"
end
