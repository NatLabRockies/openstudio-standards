# *********************************************************************
# *  Copyright (c) 2008-2015, Natural Resources Canada
# *  All rights reserved.
# *
# *  This library is free software; you can redistribute it and/or
# *  modify it under the terms of the GNU Lesser General Public
# *  License as published by the Free Software Foundation; either
# *  version 2.1 of the License, or (at your option) any later version.
# *
# *  This library is distributed in the hope that it will be useful,
# *  but WITHOUT ANY WARRANTY; without even the implied warranty of
# *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# *  Lesser General Public License for more details.
# *
# *  You should have received a copy of the GNU Lesser General Public
# *  License along with this library; if not, write to the Free Software
# *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# **********************************************************************/

require 'fileutils'
require 'csv'
require 'securerandom'
require 'digest'


module BTAP
  module FileIO

    # This method loads an OpenStudio file into the model.
    # @author Phylroy A. Lopez
    # @param filepath [String] path to the OSM file.
    # @param name [String] optional model name to be set to model.
    # @return [OpenStudio::Model::Model] an OpenStudio model object.
    def self.load_osm(filepath, name = "")
      unless File.exist?(filepath)
        raise 'File does not exist: ' + filepath.to_s
      end
      model_path = OpenStudio::Path.new(filepath.to_s)

      # Upgrade version if required.
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      model = version_translator.loadModel(model_path)
      version_translator.errors.each { |error| puts "Error: #{error.logMessage}\n" }
      version_translator.warnings.each { |warning| puts "Warning: #{warning.logMessage}\n" }
      if model.empty?
        raise "Could not load #{filepath}"
      end
      model = model.get
      if name != "" and not name.nil?
        self.set_name(model,name)
      end

      return model
    end

    #load a model into OS & version translates, exiting and erroring if a problem is found
    def self.safe_load_model(model_path_string)
      model_path = OpenStudio::Path.new(model_path_string)
      if OpenStudio::exists(model_path)
        versionTranslator = OpenStudio::OSVersion::VersionTranslator.new
        model = versionTranslator.loadModel(model_path)
        if model.empty?
          raise "Version translation failed for #{model_path_string}"
        else
          model = model.get
        end
      else
        raise "#{model_path_string} couldn't be found"
      end
      return model
    end

    # This method will save the model to an osm file.
    # @author Phylroy A. Lopez
    # @param model
    # @param filename The full path to save to.
    # @return [OpenStudio::Model::Model] a copy of the OpenStudio model object.
    def self.save_osm(model,filename)
      FileUtils.mkdir_p(File.dirname(filename))
      File.delete(filename) if File.exist?(filename)
      model.save(OpenStudio::Path.new(filename))
      #puts "File #{filename} saved."
    end

    # This method will return a deep copy of the model.
    # Simply because I don't trust the clone method yet.
    # @author Phylroy A. Lopez
    # @return [OpenStudio::Model::Model] a copy of the OpenStudio model object.
    def self.deep_copy(model,bool = true)
      return model.clone(bool).to_Model

      # pull original weather file object over
      weather_file = new_model.getOptionalWeatherFile
      if not weather_file.empty?
        weather_file.get.remove
        BTAP::runner_register("Info", "Removed alternate model's weather file object.",runner)
      end
      original_weather_file = model.getOptionalWeatherFile
      if not original_weather_file.empty?
        original_weather_file.get.clone(new_model)
      end

      # pull original design days over
      new_model.getDesignDays.sort.each { |designDay|
        designDay.remove
      }
      model.getDesignDays.sort.each { |designDay|
        designDay.clone(new_model)
      }

      # swap underlying data in model with underlying data in new_model
      # remove existing objects from model
      handles = OpenStudio::UUIDVector.new
      model.objects.each do |obj|
        handles << obj.handle
      end
      model.removeObjects(handles)
      # add new file to empty model
      model.addObjects( new_model.toIdfFile.objects )
      BTAP::runner_register("Info",  "Model name is now #{model.building.get.name}.", runner)
    end

    def debug_puts(puts_text)
      if Debug_Mode == true
        puts "#{puts_text}"
      end
    end

    def self.compare_osm_files(model_true, model_compare)
      only_model_true = [] # objects only found in the true model
      only_model_compare = [] # objects only found in the compare model
      both_models = [] # objects found in both models
      diffs = [] # differences between the two models
      num_ignored = 0 # objects not compared because they don't have names

      # Define types of objects to skip entirely during the comparison
      object_types_to_skip = [
          'OS:EnergyManagementSystem:Sensor', # Names are UIDs
          'OS:EnergyManagementSystem:Program', # Names are UIDs
          'OS:EnergyManagementSystem:Actuator', # Names are UIDs
          'OS:Connection', # Names are UIDs
          'OS:PortList', # Names are UIDs
          'OS:Building', # Name includes timestamp of creation
          'OS:ModelObjectList' # Names are UIDs
      ]

      # Find objects in the true model only or in both models
      model_true.getModelObjects.sort.each do |true_object|

        # Skip comparison of certain object types
        next if object_types_to_skip.include?(true_object.iddObject.name)

        # Skip comparison for objects with no name
        unless true_object.iddObject.hasNameField
          num_ignored += 1
          next
        end

        # Find the object with the same name in the other model
        compare_object = model_compare.getObjectByTypeAndName(true_object.iddObject.type, true_object.name.to_s)
        if compare_object.empty?
          only_model_true << true_object
        else
          both_models << [true_object, compare_object.get]
        end
      end

      # Report a diff for each object found in only the true model
      only_model_true.each do |true_object|
        diffs << "A #{true_object.iddObject.name} called '#{true_object.name}' was found only in the before model"
      end

      # Find objects in compare model only
      model_compare.getModelObjects.sort.each do |compare_object|

        # Skip comparison of certain object types
        next if object_types_to_skip.include?(compare_object.iddObject.name)

        # Skip comparison for objects with no name
        unless compare_object.iddObject.hasNameField
          num_ignored += 1
          next
        end

        # Find the object with the same name in the other model
        true_object = model_true.getObjectByTypeAndName(compare_object.iddObject.type, compare_object.name.to_s)
        if true_object.empty?
          only_model_compare << compare_object
        end
      end

      # Report a diff for each object found in only the compare model
      only_model_compare.each do |compare_object|
        #diffs << "An object called #{compare_object.name} of type #{compare_object.iddObject.name} was found only in the compare model"
        diffs << "A #{compare_object.iddObject.name} called '#{compare_object.name}' was found only in the after model"
      end

      # Compare objects found in both models field by field
      both_models.each do |b|
        true_object = b[0]
        compare_object = b[1]
        idd_object = true_object.iddObject

        true_object_num_fields = true_object.numFields
        compare_object_num_fields = compare_object.numFields

        # loop over fields skipping handle
        (1...[true_object_num_fields, compare_object_num_fields].max).each do |i|

          field_name = idd_object.getField(i).get.name

          # Don't compare node, branch, or port names because they are populated with IDs
          next if field_name.include?('Node Name')
          next if field_name.include?('Branch Name')
          next if field_name.include?('Inlet Port')
          next if field_name.include?('Outlet Port')
          next if field_name.include?('Inlet Node')
          next if field_name.include?('Outlet Node')
          next if field_name.include?('Port List')
          next if field_name.include?('Cooling Control Zone or Zone List Name')
          next if field_name.include?('Heating Control Zone or Zone List Name')
          next if field_name.include?('Heating Zone Fans Only Zone or Zone List Name')
          next if field_name.include?('Zone Terminal Unit List')

          # Don't compare the names of schedule type limits
          # because they appear to be created non-deteministically
          next if field_name.include?('Schedule Type Limits Name')

          # Get the value from the true object
          true_value = ""
          if i < true_object_num_fields
            true_value = true_object.getString(i).to_s
          end
          true_value = "-" if true_value.empty?

          # Get the same value from the compare object
          compare_value = ""
          if i < compare_object_num_fields
            compare_value = compare_object.getString(i).to_s
          end
          compare_value = "-" if compare_value.empty?

          # Round long numeric fields
          true_value = true_value.to_f.round(5) unless true_value.to_f.zero?
          compare_value = compare_value.to_f.round(5) unless compare_value.to_f.zero?

          # Move to the next field if no difference was found
          next if true_value == compare_value
          next if true_value.to_f.zero? && compare_value.to_f.zero?

          # Check numeric values if numeric
          if (compare_value.is_a? Numeric) && (true_value.is_a? Numeric)
            diff = true_value.to_f - compare_value.to_f
            unless true_value.zero?
              # next if absolute value is less than a tenth of a percent difference
              next if (diff / true_value.to_f).abs < 0.001
            end
          end

          # Report the difference
          diffs << "For #{true_object.iddObject.name} called '#{true_object.name}' field '#{field_name}': before model = #{true_value}, after model = #{compare_value}"

        end
      end

      return diffs
    end

    def self.set_all_epw_paths(osm_data)
      osm_data.each do |hash|
        hash.each do |key, value|
          #Check if value is in a epw file path format like this "USA_CA_San.Francisco.Intl.AP.724940_TMY3.epw"
          if value.match?(/.*\.epw/)
            # Get name of file without path from value
            hash[key] = File.basename(value)
          end
        end
      end
    end

    def self.set_all_data_time(osm_data)
      osm_data.each do |hash|
        hash.each do |key, value|
          #Check if value is in a date-time format like this "2024-10-17 01:19:35 UTC"
          if value.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/)
            hash[key] = "2024-01-01 01:00:00 UTC"
          end
        end
      end
    end

    def self.save_osm_file(osm_data, output_path)
      File.open(output_path, 'w') do |file|
        osm_data.each do |hash|
          file.puts "#{hash["type"]},"
          hash.each do |key, value|
            next if key == "type"
            is_last_key = (hash.keys - [:type]).last == key
            if key == :id
              file.puts "  #{value},"
            else
              file.puts "  #{value}#{is_last_key ? ';' : ','}".ljust(42) + " !- #{key}"
            end
          end
          file.puts
        end
      end
    end

    def self.rename_handles(osm_data)

      hash = Digest::SHA1.hexdigest("fixed_seed")
      handle_map = {}
      new_handle_index = 0
      object_type_index = 0
      last_object_type = nil

      osm_data.each do |hash|
        if hash['Handle']
          #puts hash
          #puts "#{hash['type']} == #{last_object_type}"
          if hash['type'] != last_object_type
            last_object_type = hash['type']
            object_type_index += 1
            new_handle_index = 1
          else
            new_handle_index += 1
          end

          # create a formatted string that is 12 charecters created with new_handle_index, but padded with 0s on the left.
          formatted_index = new_handle_index.to_s.rjust(12, '0')
          formatted_index_object_type = object_type_index.to_s.rjust(4, '0')
          new_handle = "{00000000-0000-0000-#{formatted_index_object_type}-#{formatted_index}}"
          handle_map[hash['Handle']] = new_handle
          hash['Handle'] = new_handle
        end
      end

      osm_data.each do |hash|
        hash.each do |key, value|
          if handle_map.key?(value)
            hash[key] = handle_map[value]
          end
        end
      end

      # Go through all hashes in osm_data and if the "Name" field value fits this pattern {9386c18d-e70a-447e-8b69-9a0a39fd8f06} replace it with an incremented value.
      name_map = {}
      new_name_index = 0
      osm_data.each do |hash|
        if hash['Name'] && hash['Name'].match?(/\{[a-fA-F0-9\-]{36}\}/)
          new_name_index += 1
          formatted_new_name_index = new_name_index.to_s.rjust(4, '0')
          new_name = "{00000000-0000-#{formatted_new_name_index}-0000-000000000000}"
          name_map[hash['Name']] = new_name
          hash['Name'] = new_name
        end
      end

      osm_data.each do |hash|
        hash.each do |key, value|
          if name_map.key?(value)
            hash[key] = name_map[value]
          end
        end
      end
    end

    def self.remove_special_characters(hash)
      hash.keys.each do |key|
        new_key = key.to_s.sub(/[;,]$/, '')
        hash[new_key] = hash.delete(key)
      end

      hash.each do |key, value|
        next unless value.is_a?(String)
        hash[key] = value.gsub(/[;,]$/, '')
      end
    end

    def self.clean_osm_file(file_path:, output_path:)
      osm_data = []
      current_hash = {}
      File.foreach(file_path) do |line|
        line.strip!
        next if line.empty?
         if line.start_with?('OS:')
          current_hash = { type: line.split(/[;,]/).first }
          osm_data << current_hash
        elsif line.include?('!-')
          key, value = line.split('!-').map(&:strip)
          current_hash[value] = key.chomp(',;').strip
        elsif line.include?('! ') # for lines that have '! ' but not '!-'
          key, value = line.split('! ').map(&:strip)
          current_hash[value] = key.chomp(',;').strip
        else
          current_hash[:id] ||= line.chomp(',;').strip
        end
      end
      osm_data.sort_by! { |hash| [hash[:type], hash['Name'] || ''] }
      handles = osm_data.map { |hash| hash['Handle'] }.compact
      duplicates = handles.select { |e| handles.count(e) > 1 }
      raise "Duplicate handles found: #{duplicates.uniq}" if duplicates.any?

      osm_data.each { |hash| remove_special_characters(hash) }
      set_all_data_time(osm_data)
      set_all_epw_paths(osm_data)
      rename_handles(osm_data)

      File.open(output_path, 'w') do |file|
        osm_data.each do |hash|
          file.puts "#{hash["type"]},"
          hash.each do |key, value|
            next if key == "type"
            is_last_key = (hash.keys - [:type]).last == key
            if key == :id
              file.puts "  #{value},"
            else
              file.puts "  #{value}#{is_last_key ? ';' : ','}".ljust(42) + " !- #{key}"
            end
          end
          file.puts
        end
      end
    end
  end
end
