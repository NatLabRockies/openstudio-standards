# This script reads OpenStudio_standards.xlsx
# and creates a JSON file containing all the information

require 'json'
require 'rubyXL'
require 'csv'

class String

  def snake_case
    downcase.gsub(' ', '_').gsub('-', '_')
  end

end

# Convert OpenStudio_Standards.xlsx to a series
# of JSON files for easier consumption.
class Hash

  def sort_by_key_updated(recursive = false, &block)
    self.keys.sort(&block).reduce({}) do |seed, key|
      seed[key] = self[key]
      if recursive && seed[key].is_a?(Hash)
        seed[key] = seed[key].sort_by_key(true, &block)
      elsif recursive && seed[key].is_a?(Array) && seed[key][0].is_a?(Hash)
        # Sort by the set of unique properties
        uniq_props = unique_properties(key)
        if uniq_props.size > 0
          # Temporarily replace real values with placeholders for sorting
          nil_placeholder = 'zzzz'
          true_placeholder = 'TRUETRUETRUE'
          false_placeholder = 'FALSEFALSEFALSE'
          seed[key].each do |item|
            item.keys.each do |key2|
              if item[key2].nil?
                item[key2] = nil_placeholder
              elsif [true].include?(item[key2])
                item[key2] = true_placeholder
              elsif [false].include?(item[key2])
                item[key2] = false_placeholder
              elsif item[key2].is_a?(String) && /(\d|\.)+E\d/.match(item[key2])
                # Replace scientific notation strings with floats
                item[key2] = item[key2].to_f
              end
            end
          end

          # Sort
          seed[key] = seed[key].sort_by do |hsh|
            sort_order = []
            uniq_props.each do |prop|
              if hsh.has_key?(prop)
                sort_order << hsh[prop]
              end
            end
            sort_order
          end

          # Replace placeholders with real values
          seed[key].each do |item|
            item.keys.each do |key2|
              if item[key2] == nil_placeholder
                item[key2] = nil
              elsif item[key2] == true_placeholder
                item[key2] = true
              elsif item[key2] == false_placeholder
                item[key2] = false
              end
            end
          end
        else
          seed[key] = seed[key]
        end
      end
      seed
    end
  end

end

# Defines the set of properties that should be unique across all objects of the same type.
# This set is used for checking for duplicate objects and for sorting objects in the JSON files.
def unique_properties(sheet_name)
  return case sheet_name
         when 'templates', 'standards', 'climate_zone_sets', 'constructions', 'curves', 'fans'
           ['name']
         when 'prm_constructions'
           ['template', 'name']
         when 'prm_exterior_lighting'
           ['template']
         when 'materials'
           ['name', 'code_category']
         when 'space_types', 'space_types_lighting', 'space_types_rendering_color', 'space_types_ventilation', 'space_types_occupancy', 'space_types_infiltration', 'space_types_equipment', 'space_types_thermostats', 'space_types_swh'
           ['template', 'building_type', 'space_type']
         when 'exterior_lighting'
           ['lighting_zone', 'template']
         when 'schedules'
           ['name', 'day_types', 'start_date', 'end_date']
         when 'construction_properties'
           ['template', 'climate_zone_set', 'operation_type', 'intended_surface_type', 'standards_construction_type', 'building_category', 'orientation', 'minimum_percent_of_surface', 'maximum_percent_of_surface']
         when 'boilers'
           ['template', 'fluid_type', 'fuel_type', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'chillers'
           ['template', 'cooling_type', 'condenser_type', 'compressor_type', 'absorption_type', 'compliance_path', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'furnaces'
           ['template', 'equipment_type', 'fuel_type', 'electric_power_phase', 'minimum_capacity', 'maximum_capacity', 'minimum_combo_unit_cooling_capacity', 'maximum_combo_unit_cooling_capacity', 'subtype', 'start_date', 'end_date']
         when 'heat_rejection'
           ['template', 'equipment_type', 'fan_type', 'start_date', 'end_date']
         when 'water_source_heat_pumps'
           ['template', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'water_source_heat_pumps_heating'
           ['template', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'heat_pumps'
           ['template', 'cooling_type', 'heating_type', 'subcategory', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'heat_pumps_heating'
           ['template', 'cooling_type', 'subcategory', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'unitary_acs'
           ['template', 'cooling_type', 'heating_type', 'subcategory', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
          when 'computer_room_acs'
            ['template', 'cooling_type', 'heating_type', 'subcategory', 'minimum_capacity', 'maximum_capacity', 'start_date', 'end_date']
         when 'water_heaters'
           ['template', 'equipment_type', 'fuel_type', 'minimum_capacity', 'maximum_capacity', 'minimum_storage', 'maximum_storage', 'minimum_capacity_per_storage', 'maximum_capacity_per_storage', 'draw_profile', 'start_date', 'end_date']
         when 'elevators'
           ['template', 'building_type']
         when 'refrigeration_system_lineup', 'refrigeration_system'
           ['template', 'building_type', 'size_category', 'system_type']
         when 'refrigerated_cases'
           ['template', 'size_category', 'case_type', 'case_category']
         when 'refrigeration_condenser'
           ['template', 'building_type', 'system_type', 'size_category']
         when 'refrigeration_walkins'
           ['template', 'size_category', 'walkin_type']
         when 'refrigeration_compressors'
           ['template', 'compressor_name', 'compressor_type']
         when 'economizers'
           ['climate_zone', 'data_center', 'minimum_capacity', 'fan_cooling_application', 'minimum_water_cooled_chilled_water_capacity_no_fan_cooling', 'minimum_air_cooled_chilled_water_or_district_chilled_water_capacity_no_fan_cooling', 'fixed_dry_bulb_is_allowed', 'differential_dry_bulb_is_allowed', 'electronic_enthalpy_is_allowed', 'differential_enthalpy_is_allowed', 'dew_point_dry_bulb_is_allowed', 'fixed_enthalpy_is_allowed', 'fixed_enthalpy_fixed_dry_bulb_is_allowed', 'differential_enthalpy_fixed_dry_bulb_is_allowed', 'fixed_dry_bulb_high_limit_shutoff_temp', 'fixed_enthalpy_high_limit_shutoff_enthalpy', 'dew_point_dry_bulb_high_limit_shutoff_dew_point_temp', 'dew_point_dry_bulb_high_limit_shutoff_dry_bulb_temp', 'fixed_enthalpy_fixed_dry_bulb_high_limit_shutoff_enthalpy', 'fixed_enthalpy_fixed_dry_bulb_high_limit_shutoff_dry_bulb_temp', 'differential_enthalpy_fixed_dry_bulb_high_limit_shutoff_dry_bulb_temp', 'percent_increase_cooling_efficiency_eliminate_requirement', 'heat_recovery_exempted']
         when 'motors'
           ['template', 'number_of_poles', 'type', 'synchronous_speed', 'minimum_capacity', 'maximum_capacity']
         when 'ground_temperatures'
          ['template', 'building_type', 'climate_zone']
         when 'hvac_inference'
           ['template', 'size_category', 'heating_source', 'cooling_source', 'delivery_type']
         when 'size_category'
           ['template', 'building_category', 'minimum_floors', 'maximum_floors', 'minimum_area', 'maximum_area']
         when 'construction_sets'
           ['template', 'building_type', 'space_type', 'is_residential']
         when 'parking', 'entryways'
           ['building_type']
         when 'prototype_inputs'
           ['template', 'building_type', 'hvac_system']
         when 'climate_zones'
           ['name', 'standard']
         when 'energy_recovery'
           ['climate_zone', 'under_8000_hours', 'nontransient_dwelling', 'percent_oa_0_to_10', 'percent_oa_10_to_20 ', 'percent_oa_20_to_30', 'percent_oa_30_to_40', 'percent_oa_40_to_50', 'percent_oa_50_to_60', 'percent_oa_60_to_70', 'percent_oa_70_to_80', 'percent_oa_greater_than_80', 'design_conditions', 'energy_recovery_effectiveness', 'enthalpy_recovery_ratio', 'sensible_energy_recovery_ratio']
         when 'space_types_lighting_control'
           ['template', 'building_type', 'space_type']
         when 'prm_hvac_bldg_type'
           ['template', 'hvac_building_type']
         when 'prm_swh_bldg_type'
           ['template', 'swh_building_type']
         when 'prm_wwr_bldg_type'
           ['template', 'wwr_building_type']
         when 'prm_baseline_hvac'
           ['template', 'hvac_building_type', 'bldg_area_min', 'bldg_area_max', 'bldg_flrs_min', 'bldg_flrs_max']
         when 'prm_heat_type'
           ['template', 'hvac_building_type', 'climate_zone']
         when 'prm_interior_lighting'
           ['template', 'lpd_space_type']
         when 'lpd_space_type'
           ['template', 'lpd_space_type']
         else
           []
        end
end

# Shortens JSON file path names to avoid Windows build errors when
# compiling the OpenStudio CLI
def shorten_sheet_name(sheet_name)
  short_sheet_name = sheet_name
  short_sheet_name = short_sheet_name.gsub('refrigeration_system_lineup', 'ref_lnup') # 19 saved
  short_sheet_name = short_sheet_name.gsub('refrigerated_cases', 'ref_cases') # 9 saved
  short_sheet_name = short_sheet_name.gsub('exterior_lighting', 'ext_ltg') # 10 saved
  short_sheet_name = short_sheet_name.gsub('space_types', 'spc_typ') # 10 saved

  return short_sheet_name
end

# Determine the directory of the data based on the spreadsheet name
def standard_parent_directory_from_spreadsheet_title(spreadsheet_title)
  data_directory = spreadsheet_title.downcase.gsub('openstudio_standards-', '').gsub(/\(\w*\)/, '').split('-').first
  # puts "Extracting standard parent directory from spreadsheet title #{spreadsheet_title} = #{data_directory}"

  return data_directory
end

# Determine the directory name from the template
def standard_directory_name_from_template(template)
  directory_name = template.downcase.gsub(/\W/, '_').gsub('90_1', 'ashrae_90_1')
  # puts "Extracting standard directory from template #{template} = #{directory_name}"

  return directory_name
end

def exclusion_list
  file_path = "#{__dir__}/exclude_list.csv"
  csv_file = CSV.read(file_path, headers:true)
  csv_data = csv_file.map {|row| row.to_hash}
  exclusion_array = { "os_stds" => { "worksheets" => [], "columns" => [] },
                      "data_lib" => { "worksheets" => [], "columns" => [] } }
  csv_file.each do |row|
    if row['columns'] == 'all'
      exclusion_array['os_stds']['worksheets'] << row['worksheet'] if row['exclude_from_os_stds'] == 'TRUE'
      exclusion_array['data_lib']['worksheets'] << row['worksheet'] if row['exclude_from_data_lib'] == 'TRUE'
    else
      exclusion_array['os_stds']['columns'] << row['columns'] if row['exclude_from_os_stds'] == 'TRUE'
      exclusion_array['data_lib']['columns'] << row['columns'] if row['exclude_from_data_lib'] == 'TRUE'
    end
  end
  return exclusion_array
end

def parse_units(unit)
  # useless_units = [nil, 'fraction', '%', 'COP_68F', 'COP_47F', '%/gal', 'Btu/hr/Btu/hr', 'Btu/hr/gal', 'BTU/hr/ft', 'W/BTU/h']
  units_to_skip = [nil, 'fraction', '%', 'EER', '>23m^2', '>84m^2', '<23m^2', '<84m^2']
  unit_parsed = nil
  if not units_to_skip.include?(unit)
    if unit == '%/gal'
      unit = '1/gal'
    end
    unit_parsed = OpenStudio.createUnit(unit)
    if unit_parsed.empty?
      unit_parsed = "Not recognized by OpenStudio"
    else
      unit_parsed = unit_parsed.get()
    end
  end
  return unit_parsed
end

# Exports spreadsheet data to data jsons, nested by the standards templates
#
# @param spreadsheet_titles
# @param dataset_type [String] valid choices are 'os_stds' or 'data_lib'
#   'os_stds' updates json files in openstudio standards, while 'data_lib' exports 90.1 jsons for the data library
def export_spreadsheet_to_json(spreadsheet_titles, dataset_type: 'os_stds')
  if dataset_type == 'data_lib'
    standards_dir = File.expand_path("#{__dir__}/../../data/standards/export")
    skip_list = exclusion_list['data_lib']
    skip_list['templates'] = ['DOE Ref Pre-1980',
                              'DOE Ref 1980-2004',
                              'NREL ZNE Ready 2017',
                              'ZE AEDG Multifamily',
                              'OEESC 2014',
                              'ICC IECC 2015',
                              'ECBC 2017',
                              '189.1-2009']
  else
    standards_dir = File.expand_path("#{__dir__}/../../lib/openstudio-standards/standards")
    skip_list = exclusion_list['os_stds']
    skip_list['templates'] = []
  end
  worksheets_to_skip = skip_list['worksheets']
  cols_to_skip = skip_list['columns']
  templates_to_skip = skip_list['templates']

  # List of columns that are boolean
  # (rubyXL returns 0 or 1, will translate to true/false)
  bool_cols = []
  bool_cols << 'hx'
  bool_cols << 'data_center'
  bool_cols << 'under_8000_hours'
  bool_cols << 'nontransient_dwelling'
  bool_cols << 'u_value_includes_interior_film_coefficient'
  bool_cols << 'u_value_includes_exterior_film_coefficient'

  warnings = []
  duplicate_data = []
  spreadsheet_titles.each do |spreadsheet_title|

    # Path to the xlsx file
    xlsx_path = "#{__dir__}/#{spreadsheet_title}.xlsx"

    unless File.exist?(xlsx_path)
      warnings << "could not find spreadsheet called #{spreadsheet_title}"
      next
    end

    puts "Parsing #{xlsx_path}"

    # Open workbook
    workbook = RubyXL::Parser.parse(xlsx_path)
    puts "After parse workbook"

    # Find all the template directories that match the search criteria embedded in the spreadsheet title
    dirs = spreadsheet_title.gsub('OpenStudio_Standards-', '').gsub(/\(\w*\)/, '').split('-')
    new_dirs = []
    dirs.each { |d| d == 'ALL' ? new_dirs << '*' : new_dirs << "*#{d}*" }
    glob_string = "#{standards_dir}/#{new_dirs.join('/')}"
    puts "--spreadsheet title embedded search criteria: #{glob_string} yields:"
    template_dirs = Dir.glob(glob_string).select { |f| File.directory?(f) && !f.include?('data') && !f.include?('ashrae_90_1_prm') }
    # template_dirs = Dir.glob(glob_string).select { |f| File.directory?(f) && !f.include?('data') }
    template_dirs.each do |template_dir|
      puts "----#{template_dir}"
    end

    # Export each tab to a hash, where the key is the sheet name
    # and the value is an array of objects
    standards_data = {}
    list_of_sheets = []
    list_of_names = []
    list_of_units = []
    list_of_OS_okay_units = []
    workbook.worksheets.each do |worksheet|
      sheet_name = worksheet.sheet_name.snake_case

      # Skip the specified worksheets
      if worksheets_to_skip.include?(sheet_name)
        puts "Skipping #{sheet_name}"
        next
      else
        puts "Processing #{sheet_name}"
      end

      # All spreadsheets must have headers in row 3
      # and data from roworksheet 4 onward.
      header_row = 2 # Base 0

      # Get all data
      # extract_data was deprecated in rubyXL
      # inputting the method here https://github.com/weshatheleopard/rubyXL/issues/201
      all_data = worksheet.sheet_data.rows.map { |row|
        row.cells.map { |c| c && c.value() } unless row.nil?
      }

      # Get the header row data
      header_data = all_data[header_row]

      # Format the headers and parse out units (in parentheses)
      headers = []
      header_data.each do |header_string|
        break if header_string.nil?
        header = {}
        header["name"] = header_string.gsub(/\(.*\)/, '').strip.snake_case
        header_unit_parens = header_string.scan(/\(.*\)/)[0]
        list_of_sheets << sheet_name
        list_of_names << header_string.gsub(/\(.*\)/, '').strip.snake_case
        if header_unit_parens.nil?
          header["units"] = nil
          list_of_units << nil
          list_of_OS_okay_units << nil
        else
          header["units"] = header_unit_parens.gsub(/\(|\)/, '').strip
          list_of_units << header_unit_parens.gsub(/\(|\)/, '').strip
          list_of_OS_okay_units << parse_units(header_unit_parens.gsub(/\(|\)/, '').strip)
        end
        headers << header
      end
      puts "--found #{headers.size} columns"

      # Loop through all rows and export
      # data for the row to a hash.
      objs = []
      for i in (header_row + 1)..(all_data.size - 1)
        row = all_data[i]
        # Stop when reach a blank row
        break if row.nil?
        # puts "------row #{i} = #{row}"
        obj = {}

        # Check if all cells in the row are null
        all_null = true
        for j in 0..headers.size - 1
          # Flip the switch if a value is found
          unless row[j].nil?
            all_null = false
          end
        end

        # Skip recording empty rows
        next if all_null == true

        # Store values from appropriate columns
        for j in 0..headers.size - 1
          val = row[j]
          # Don't record nil values
          # next if val.nil?
          # Flip the switch if a value is found
          unless val.nil?
            all_null = false
          end
          # Skip specified columns
          next if cols_to_skip.include?(headers[j]['name'])
          # Convert specified columns to boolean
          if bool_cols.include?(headers[j]['name'])
            if val == 1
              val = true
            elsif val == 0
              val = false
            else
              val = nil
            end
          end
          # Convert date columns to standard format
          if headers[j]['name'].include?('_date')
            if val.is_a?(DateTime)
              val = val.to_s
            else
              begin
                val = DateTime.parse(val).to_s
              rescue ArgumentError, TypeError
                puts "ERROR - value '#{val}', class #{val.class} in #{sheet_name}, row #{i}, col #{j} is not a valid date"
                return false
              end
            end
          end

          # Record the value
          obj[headers[j]['name']] = val
          # Skip recording units for unitless values
          next if headers[j]['units'].nil?
          # Record the units
          # obj["#{headers[j]['name']}_units"] = headers[j]['units']
        end

        # Store the array of objects
        # special cases for some types
        if sheet_name == 'climate_zone_sets'
          new_obj = {}
          new_obj['name'] = obj['name']
          items = []
          obj.each do |key, val2|
            # Skip the key
            next if key == 'name'
            # Skip blank climate zone values
            next if val2.nil?
            items << val2
          end
          new_obj['climate_zones'] = items
          objs << new_obj
        elsif sheet_name == 'constructions' or sheet_name == 'prm_constructions'
          new_obj = {}
          new_obj['name'] = obj['name']
          items = []
          obj.each do |key, val2|
            # Skip the key
            next if key == 'name'
            # Put materials into an array,
            # record other fields normally
            if key.include?('material')
              # Skip blank material values
              next if val2.nil?
              items << val2
            else
              new_obj[key] = val2
            end
          end
          new_obj['materials'] = items
          objs << new_obj
        elsif sheet_name == 'schedules'
          new_obj = {}
          new_obj['name'] = obj['name']
          items = []
          obj.each do |key, val2|
            # Skip the key
            next if key == 'name'
            # Put materials into an array,
            # record other fields normally
            if key.include?('hr')
              # Skip blank hourly values
              next if val2.nil?
              items << val2
            else
              new_obj[key] = val2
            end
          end
          new_obj['values'] = items
          objs << new_obj
        else
          objs << obj
        end

      end

      # Report how many objects were found
      puts "--found #{objs.size} rows"

      # Skip to the next sheet if no objects were found
      if objs.empty?
        warnings << "did not export #{sheet_name} in #{spreadsheet_title} because no rows were found"
        next
      end

      # Save the objects to the hash
      standards_data[sheet_name] = objs
    end


    filename_out = spreadsheet_title.gsub(/[()]/, '')
    # CSV.open("metadata.csv", "wb") {|csv| headers.to_a.each {|elem| csv << elem} }
    # list_metadata = [list_of_sheets, list_of_names, list_of_units, list_of_OS_okay_units].transpose
    list_metadata = [list_of_sheets, list_of_names, list_of_units].transpose
    list_metadata.insert(0, ['Sheet', 'Name', 'Unit']) # [1, 2, 2.5, 3, 4]
    File.write("data/standards/metadata_units_#{filename_out}.csv", list_metadata.map(&:to_csv).join)
    # Check for duplicate data in space_types_* sheets
    standards_data.each_pair do |sheet_name, objs|
      skip_duplicate_check = []
      next if skip_duplicate_check.include?(sheet_name)

      # Defines the set of properties that should be unique across all objects of the same type
      unique_props = unique_properties(sheet_name)
      # Ensure that a set of properties was defined
      if unique_props.empty?
        puts "--ERROR no unique set of properties was defined for #{sheet_name}, cannot check for duplicates"
        return false
      end

      # Check for duplicates using unique property set
      puts "Checking #{sheet_name} for duplicates based on columns: #{unique_props.join(', ')}"
      found_objs = {}
      objs.each_with_index do |obj, i|
        unique_aspects = []
        unique_props.each { |prop| unique_aspects << obj[prop] }
        unique_aspect = unique_aspects.join('|')
        if found_objs.include?(unique_aspect)
          status = 'different'
          status = 'same' if obj.to_s == found_objs[unique_aspect]
          duplicate_data << [spreadsheet_title, sheet_name, i, status, unique_aspect]
        end
        found_objs[unique_aspect] = obj.to_s
      end
    end

    # Merge all space_types_* sheets into a single space_types sheet
    space_types = {}
    standards_data.each_pair do |sheet_name, objs|
      next unless sheet_name.include?('space_types_')
      puts "Merging #{sheet_name} into space_types"
      objs.each do |obj|
        name = "#{obj['template']}|#{obj['building_type']}|#{obj['space_type']}"
        if space_types[name].nil?
          space_types[name] = obj
        else
          space_types[name].merge!(obj)
        end
      end

      # Remove space_types_* from the standards_data
      standards_data.delete(sheet_name)
    end
    standards_data['space_types'] = space_types.values unless space_types.empty?

    # Export each set of objects to a JSON file
    standards_data.each_pair do |sheet_name, objs|
      puts "Writing #{sheet_name} which has #{objs.size} objects"

      # Record the number of files that were exported for error checking
      jsons_written = 0

      # Split template-specific datasets into separate files.
      # Store common/shared datasets under a higher-level folder
      parent_dir = standard_parent_directory_from_spreadsheet_title(spreadsheet_title)
      if objs.first.has_key?('template')
        puts '--template-specific, writing a file for each template with just that templates objects'

        # Split objects by template
        templates_to_objects = {}
        objs.each do |obj|
          temp = obj['template']
          if templates_to_objects[temp]
            templates_to_objects[temp] << obj
          else
            templates_to_objects[temp] = [obj]
          end
        end

        # Write out a file for each template with the objects for that template.
        templates_to_objects.each_pair do |template, objs|
          next if template == 'Any'
          next if templates_to_skip.include?(template)
          template_dir_name = standard_directory_name_from_template(template)
          # Sort the objects
          sorted_objs = {sheet_name => objs}.sort_by_key_updated(true) {|x, y| x.to_s <=> y.to_s}

          # Also check directly underneath the parent directory
          if /prm/.match(template_dir_name) && !/prm/.match(parent_dir)
            child_dir = "#{standards_dir}/#{parent_dir}_prm/#{template_dir_name}"
          else
            child_dir = "#{standards_dir}/#{parent_dir}/#{template_dir_name}"
          end
          additional_dirs = []
          additional_dirs << child_dir if Dir.exist?(child_dir)
          possible_template_dirs = template_dirs + additional_dirs
          puts "Additional dir = #{child_dir}"

          wrote_json = false
          possible_template_dirs.each do |template_dir|
            last_dir = template_dir.split('/').last
            next unless last_dir == template_dir_name
            data_dir = "#{template_dir}/data"
            Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
            json_path = "#{data_dir}/#{template_dir_name}.#{shorten_sheet_name(sheet_name)}.json"
            if json_path.size > 256
              puts "--ERROR the JSON path is #{json_path.size - 256} characters longer than the Window 256 character limit, cannot write to #{json_path}"
              return false
            end
            File.open(json_path, 'w:UTF-8') do |file|
              file << JSON.pretty_generate(sorted_objs)
            end
            puts "--successfully generated #{json_path}"
            jsons_written += 1
            wrote_json = true
          end

          unless wrote_json
            warnings << "did not export data for template #{template} from #{sheet_name} in #{spreadsheet_title} because there was no valid directory matching '#{template_dir_name}' based on the spreadsheet title embedded search criteria"
          end
        end

        # Stop if no objects on this sheet list the template called 'Any'
        next if templates_to_objects['Any'].nil?

        # Sort the objects
        sorted_objs = {sheet_name => templates_to_objects['Any']}.sort_by_key_updated(true) {|x, y| x.to_s <=> y.to_s}

        # Write all objects that use the 'Any' template to the parent directories
        wrote_any_template_json = false
        template_dirs.uniq.each do |template_dir|
          data_dir = "#{template_dir}/data"
          Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
          json_path = "#{data_dir}/Any.#{shorten_sheet_name(sheet_name)}.json"
          if json_path.size > 256
            puts "--ERROR the JSON path is #{json_path.size - 256} characters longer than the Window 256 character limit, cannot write to #{json_path}"
            return false
          end
          File.open(json_path, 'w:UTF-8') do |file|
            file << JSON.pretty_generate(sorted_objs)
          end
          puts "--successfully generated #{json_path}"
          jsons_written += 1
          wrote_any_template_json = true
        end

        unless wrote_any_template_json
          warnings << "did not export data for template 'Any' from #{sheet_name} in #{spreadsheet_title} because there was no valid directory to store 'Any' template data."
        end
      else
        puts '--not template-specific, writing a file with all objects for each template specified by search criteria'

        # Sort the objects
        sorted_objs = {sheet_name => objs}.sort_by_key_updated(true) {|x, y| x.to_s <=> y.to_s}

        # Write out a file for each template with all objects on the sheet
        template_dirs.each do |template_dir|
          data_dir = "#{template_dir}/data"
          Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
          json_path = "#{data_dir}/#{parent_dir}.#{shorten_sheet_name(sheet_name)}.json"
          if json_path.size > 256
            puts "--ERROR the JSON path is #{json_path.size - 256} characters longer than the Window 256 character limit, cannot write to #{json_path}"
            return false
          end
          File.open(json_path, 'w:UTF-8') do |file|
            file << JSON.pretty_generate(sorted_objs)
          end
          puts "--successfully generated #{json_path}"
          jsons_written += 1
        end
      end

      # Confirm that at least 1 JSON file was written per sheet
      if jsons_written.zero?
        puts "--ERROR no JSON files were written for #{sheet_name} even though objects were found.  Check sheet contents or delete rows."
        # return false
      end
    end
  end

  # Print out all the warnings in one place
  puts "\n**** WARNINGS ****"
  warnings.each { |w| puts "WARNING #{w}" }

  # Write duplicates out to file
  if duplicate_data.size > 0
    duplicate_log_path = "#{__dir__}/openstudio_standards_duplicates_log.csv"
    puts "\n**** DUPLICATES ****"
    puts "There were #{duplicate_data.size} duplicate objects found.  See detail in: #{duplicate_log_path}"
    CSV.open(duplicate_log_path, 'wb') do |csv|
      csv << ['Spreadsheet Name', 'Worksheet Name', 'Object Index in Worksheet', 'Similarity of Duplicate', 'Duplicate Object']
      duplicate_data.each do |duplicate|
        csv << duplicate
      end
    end
    # Open the duplicates csv file
    if Gem.win_platform?
      system("start #{File.expand_path(duplicate_log_path)}")
    else
      system("open #{File.expand_path(duplicate_log_path)}")
    end
  end

  return true
end
