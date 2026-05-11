require 'singleton'
require 'json'
require 'csv'

# Singleton class to centralize all database operations
class CostingDatabase
  include Singleton

  def initialize
    @cp = CommonPaths.instance # Stores paths
    @db = Hash.new             # Stores the costing database

    # Load the database from the individual CSV files
    # Load costing data
    @db['costs'] = []                # Costing data
    @db['localization_factors'] = [] # Local costing factors
    @db['raw'] = {}                  # Raw data
    @db['db_errors'] = []

    data_costs = CSV.read(@cp.costs_path)

    1.upto data_costs.length - 1 do |i|
      row = data_costs[i]
      index = row.each
      item = Hash.new
      item["baseCosts"] = Hash.new
      costs = item["baseCosts"]

      item["id"]               = index.next
      item["sheet"]            = index.next
      item["source"]           = index.next
      item["description"]      = index.next
      item["city"]             = index.next
      item["province_state"]   = index.next
      costs["materialOpCost"]  = index.next.to_f
      costs["laborOpCost"]     = index.next.to_f
      costs["equipmentOpCost"] = index.next.to_f

      @db["costs"] << item
    end

    # Load the localization factors
    data_factors = CSV.read(@cp.costs_local_factors_path)

    1.upto data_factors.length - 1 do |i|
      row = data_factors[i]
      index = row.each
      item = Hash.new

      item["province_state"] = index.next
      item["city"]           = index.next
      item["division"]       = index.next
      item["code_prefix"]    = index.next
      item["material"]       = index.next.to_f
      item["installation"]   = index.next.to_f
      item["total"]          = index.next.to_f

      @db["localization_factors"] << item
    end

    # Load the raw data
    raw_data_names = [
      'locations',
      'construction_sets',
      'constructions_opaque',
      'materials_opaque',
      'constructions_glazing',
      'materials_glazing',
      'Constructions',
      'ConstructionProperties',
      'lighting_sets',
      'lighting',
      'materials_lighting',
      'hvac_vent_ahu',
      'materials_hvac'
    ]

    0.upto(raw_data_names.length - 1) do |i|
      data_path = @cp.raw_paths[i]
      unless File.exist?(data_path)
        raise("Error: Could not find #{data_path}")
      end
      @db['raw'][raw_data_names[i]] = CSV.read(data_path, headers: true).map { |row| row.to_hash}
    end
  end

  # Validate the construction sets and the AHU items.
  def validate_database()
    validate_constructions_sets()
    validate_ahu_items_and_quantities()
  end

  def validate_constructions_sets()
    construction_sets = @db['raw']['construction_sets']
    failed = false
    templates = ["NECB2011", "NECB2015", "NECB2017", "NECB2020", "BTAPPRE1980", "BTAP1980TO2010"]
    bad_records = {}
    bad_records[:invalid_space_type_names] = []
    bad_records[:min_max_floor_range_errors] = []
    #  CHECK if spacetype names are valid in costing database
    valid_space_types = []
    templates.each do |template|
      valid_space_types += Standard.build(template.gsub(/\s+/, "")).get_all_spacetype_names.map { |spacetype| (template + '-' + spacetype[0].to_s + '-' + spacetype[1].to_s).strip }
    end
    # construction_sets

    construction_sets.each do |row|
      target_space_type = "#{row['template'].gsub(/\s+/, "") + '-' + row['building_type']}-#{row['space_type']}".strip
      unless valid_space_types.include?(target_space_type.to_s)
        bad_records[:invalid_space_type_names] << {template: row['template'].gsub(/\s+/, ""), space_type: target_space_type}
      end
    end


    # Check if # of floors contains 1 to 999
    #Get Unique spacetypes.
    bad_evelope_story_ranges = []
    space_types = construction_sets.map { |row| {template: row["template"], building_type: row["building_type"], space_type: row["space_type"]} }.uniq
    space_types.each do |space_type|
      range = Array.new
      instances = construction_sets.select { |row| row['template'] == space_type[:template] && row['building_type'] == space_type[:building_type] && row['space_type'] == space_type[:space_type] }
      instances.each do |instance|
        min_val = instance['min_stories'].to_i
        min_val = 0 if min_val == 1
        max_val = instance['max_stories'].to_i
        range << min_val
        range << max_val
        failed = true
      end
      range.sort!
      incomplete_range = (range.first != 0 or range.last < 999)
      possible_duplicate = (range.uniq.size != range.size)
      if incomplete_range or possible_duplicate
        space_type[:range] = range
        space_type[:error] = {incomplete_range: incomplete_range, possible_duplicate: possible_duplicate}
        bad_records[:min_max_floor_range_errors] << space_type
      end
    end
    if bad_records[:min_max_floor_range_errors].size > 0 or bad_records[:invalid_space_type_names].size > 0
      puts "Errors in ConstructionSets Costing Table."
      puts JSON.pretty_generate(bad_records)
      raise("costing spreadsheet validation failed")
    end
  end


  # This method verifies that, for a given row the number of items listed in the 'id_layers' column is the same as the
  # number of quantities listed in the 'Id_layers_quantity_multipliers' column in the 'hvac_vent_ahu' sheet in the
  # costing spreadsheet.  If there is a difference in the number of items and number of quantities in a row then that
  # row needs to be investigated and fixed.
  def validate_ahu_items_and_quantities()
    # Find out if there are a different number of items and number oof quantities in any row of the 'hvac_vent_ahu'
    # sheet.
    diff_id_quantities = @db['raw']['hvac_vent_ahu'].select{|data| data['id_layers'].to_s.split(',').size != data['Id_layers_quantity_multipliers'].to_s.split(',').size}
    # If there is a difference (that is the diff_id_quantities has something in it) then raise an error.
    unless diff_id_quantities.empty?
      puts "Errors in the hvac_vent_ahu Costing Table.  The number of id_layers does not match the number of"
      puts "Id_layers_quantity_multipliers for the following item(s):"
      puts JSON.pretty_generate(diff_id_quantities)
      raise("costing spreadsheet validation failed")
    end
  end

  # Overload the element of operator for database accesses
  def [](element)
    @db[element]
  end

  # Overload the element assignment operator for inputting additional data
  def []=(element, value)
    @db[element] = value
  end
end
