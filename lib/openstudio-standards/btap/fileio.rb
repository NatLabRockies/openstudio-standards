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

  #Test Constructions Module
    if __FILE__ == $0
      require 'test/unit'
      class FileIOTests < Test::Unit::TestCase 
 
        def setup
        end

        def test_load_save_DOE_file()
          BTAP::FileIO::load_e_quest(BTAP::OS_RUBY_PATH + '\Resources\eQuest_3.64\4StoreyBuilding.inp')
        end


      end
    end
    # Get the name of the model.
    # @author Phylroy A. Lopez
    # @return [String] the name of the model.
    def self.get_name(model)
      unless model.building.get.name.empty?
        return model.building.get.name.get.to_s
      else
        return ""
      end
    end

    # @author Phylroy A. Lopez
    # Get the name of the model.
    # @author Phylroy A. Lopez
    # @return [String] the name of the model.
    def self.set_name(model,name)
      unless model.building.empty?
        model.building.get.setName(name)
      end
    end

    # @author Phylroy A. Lopez
    # Get the name of the model.
    # @author Phylroy A. Lopez
    # @return [String] the name of the model.
    def self.set_sql_file(model,sql_path)
      model.setSqlFile(OpenStudio::Path.new( sql_path) )
    end
    #@author Phylroy A. Lopez
    # Get the filepath of all files with extention
    # @param folder [String} the path to the folder to be scanned.
    # @param ext [String] the file extension name, ex ".epw"
    def self.get_find_files_from_folder_by_extension(folder, ext)
      Dir.glob("#{folder}/**/*#{ext}")
    end

    def self.delete_files_in_folder_by_extention(folder,ext)
      BTAP::FileIO::get_find_files_from_folder_by_extension(folder, ext).each do |file|
        FileUtils.rm(file)
        #puts "#{file} deleted."
      end
    end

    def self.find_file_in_folder_by_filename(folder,filename)
      Dir.glob("#{folder}/**/*#{filename}")
    end

    def self.fix_url_to_path(url_string)
      if  url_string =~/\/([a-zA-Z]:.*)/
        return $1
      else
        return url_string
      end
    end


    # This method loads an OpenStudio file into the model.
    # @author Phylroy A. Lopez
    # @param filepath [String] path to the OSM file.
    # @param name [String] optional model name to be set to model.
    # @return [OpenStudio::Model::Model] an OpenStudio model object.
    def self.load_idf(filepath, name = "")
      #load file
      unless File.exist?(filepath)
        raise 'File does not exist: ' + filepath.to_s
      end
      #puts "loading file #{filepath}..."
      model_path = OpenStudio::Path.new(filepath.to_s)
      #Upgrade version if required.
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      model = OpenStudio::EnergyPlus::loadAndTranslateIdf(model_path)
      version_translator.errors.each {|error| puts "Error: #{error.logMessage}\n\n"}
      version_translator.warnings.each {|warning| puts "Warning: #{warning.logMessage}\n\n"}
      #If model did not load correctly.
      if model.empty?
        raise 'something went wrong'
      end
      model = model.get
      if name != ""
        self.set_name(model,name)
      end
      #puts "File #{filepath} loaded."
      return model
    end

    def self.replace_model(model,new_model,runner = nil)
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





    # This method loads an OpenStudio file into the model.
    # @author Phylroy A. Lopez
    # @param filepath [String] path to the OSM file.
    # @param name [String] optional model name to be set to model.
    # @return [OpenStudio::Model::Model] an OpenStudio model object.
    def self.load_osm(filepath, name = "")

      #load file
      unless File.exist?(filepath)
        raise 'File does not exist: ' + filepath.to_s
      end
      #puts "loading file #{filepath}..."
      model_path = OpenStudio::Path.new(filepath.to_s)
      #Upgrade version if required.
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      model = version_translator.loadModel(model_path)
      version_translator.errors.each {|error| puts "Error: #{error.logMessage}\n\n"}
      version_translator.warnings.each {|warning| puts "Warning: #{warning.logMessage}\n\n"}
      #If model did not load correctly.
      if model.empty?
        raise "could not load #{filepath}"
      end
      model = model.get
      if name != "" and not name.nil?
        self.set_name(model,name)
      end
      #puts "File #{filepath} loaded."

      return model
    end

    # This method loads an *Quest file into the model.
    # @author Phylroy A. Lopez
    # @param filepath [String] path to the OSM file.
    # @return [OpenStudio::Model::Model] an OpenStudio model object.
    def self.load_e_quest(filepath)
      #load file
      unless File.exist?(filepath)
        raise 'File does not exist: ' + filepath.to_s
      end
      #puts "loading equest file #{filepath}. This will only convert geometry."
      #Create an instancse of a DOE model
      doe_model = BTAP::EQuest::DOEBuilding.new()
      #Load the inp data into the DOE model.
      doe_model.load_inp(filepath)

      #Convert the model to a OSM format.
      model = doe_model.create_openstudio_model_new()
      return model
    end

    #This method will inject OSM objects from a OSM file/library into the current
    # model.
    # @author Phylroy A. Lopez
    # @param filepath [String] path to the OSM library file.
    # @return [OpenStudio::Model::Model] an OpenStudio model object (self reference).
    def self.inject_osm_file(model, filepath)
      osm_data = BTAP::FileIO::load_osm(filepath)
      model.addObjects(osm_data.objects);
      return model
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

    # This method will translate to an E+ IDF format and save the model to an idf file.
    # @author Phylroy A. Lopez
    # @param model
    # @param filename The full path to save to.
    # @return [OpenStudio::Model::Model] a copy of the OpenStudio model object.
    def self.save_idf(model,filename)
      OpenStudio::EnergyPlus::ForwardTranslator.new().translateModel(model).toIdfFile().save(OpenStudio::Path.new(filename),true)
    end

    # This method will recursively translate all IDFs in a folder to OSMs, and save them to the OSM_-No_Space_Types folder
    # @author Brendan Coughlin
    # @param filepath The directory that holds the IDFs - usually DOEArchetypes\Original
    # @return nil
    def self.convert_idf_to_osm(filepath)
      Find.find(filepath) { |file|
        if file[-4..-1] == ".idf"
          model = FileIO.load_idf(file)
          # this is a bit ugly but it works properly when called on a recursive folder structure
          FileIO.save_osm(model, (File.expand_path("..\\OSM-No_Space_Types\\", filepath) << "\\" << Pathname.new(file).basename.to_s)[0..-5])
          #puts # empty line break
        end
      }
    end





    def self.get_timestep_data(osm_file,sql_file,variable_name_array, env_period = nil, hourly_time_step = nil )
      column_data = get_timeseries_arrays(sql, env_period, hourly_time_step, "Boiler Fan Coil Part Load Ratio")
    end


    def self.convert_all_eso_to_csv(in_folder,out_folder)
      list_of_csv_files = Array.new
      FileUtils.mkdir_p(out_folder)
      osmfiles = BTAP::FileIO::get_find_files_from_folder_by_extension(in_folder,".eso")

      osmfiles.each do |eso_file_path|

        #Run ESO Vars command must be run in folder.
        root_folder = Dir.getwd()
        #puts File.dirname(eso_file_path)
        Dir.chdir(File.dirname(eso_file_path))
        if File.exist?("eplustbl.htm")
          File.open("dummy.rvi", 'w') {|f| f.write("") }


          system("#{BTAP::SimManager::ProcessManager::find_read_vars_eso()} dummy.rvi unlimited")
          #get name of run from html file.
          runname = ""
          f = File.open("eplustbl.htm")
          f.each_line do |line|
            if line =~ /<p>Building: <b>(.*)<\/b><\/p>/
              #puts  "Found name: #{$1}"
              runname = $1
              break
            end
          end
          f.close
          #copy files over with distinct names
          #puts "copy hourly results to #{out_folder}/#{runname}_eplusout.csv"
          FileUtils.cp("eplusout.csv","#{out_folder}/#{runname}_eplusout.csv")
          #puts "copy html results to #{out_folder}/#{runname}_eplustbl.htm"
          FileUtils.cp("eplustbl.htm","#{out_folder}/#{runname}_eplustbl.htm")
          #puts "copy sql results to #{out_folder}/#{runname}_eplusout.sql"
          FileUtils.cp("eplusout.sql","#{out_folder}/#{runname}_eplusout.sql")


          list_of_csv_files << "#{out_folder}/#{runname}_eplusout.csv"
        end
        Dir.chdir(root_folder)
      end
      return list_of_csv_files
    end


    # This method will read a CSV file and return rows as hashes based on the selection given.
    # @author Phylroy Lopez
    # @param file The path to the csv file.
    # @param searchHash
    # @return matches A Array of rows that match the searchHash. The row is a Hash itself.
    def self.csv_look_up_rows(file, searchHash)
      options = {
          :headers =>       true,
          :converters =>     :numeric }
      table = CSV.read( file, options )
      # we'll save the matches here
      matches = nil
      # save a copy of the headers
      matches = table.find_all do |row|
        row
        match = true
        searchHash.keys.each do |key|
          match = match && ( row[key] == searchHash[key] )
        end
        match
      end
      return matches
    end

    def self.csv_look_up_unique_row(file, searchHash)
      #Load Vintage database information.
      matches = BTAP::FileIO::csv_look_up_rows(file, searchHash)
      raise( "Error:  CSV lookup found more than one row that met criteria #{searchHash} in #{@file} ") if matches.size() > 1
      raise( "Error:  CSV lookup found no rows that met criteria #{searchHash} in #{@file}") if matches.size() < 1
      return matches[0]
    end


    # This method will read a CSV file and return the unique values in a given column header.
    # @author Phylroy Lopez
    # @param file The path to the csv file.
    # @param colHeader The header name in teh csv file.
    # @return matches A Array of rows that match the searchHash. The row is a Hash itself.
    def self.csv_look_up_unique_col_data(file, colHeader)
      column_data = Array.new
      CSV.foreach( file, :headers => true ) do |row|
        column_data << row[colHeader] # For each row, give me the cell that is under the colHeader column
      end
      return column_data.sort!.uniq
    end

    def self.sum_row_headers(row,headers)
      total = 0.0
      headers.each { |header| total = total + row[header] }
      return total
    end

    def self.terminus_hourly_output(csv_file)
      #puts "Starting Terminus output processing."
      #puts "reading #{csv_file} being processed"
      #reads csv file into memory.
      original = CSV.read(csv_file,
                          {
                              :headers =>       true, #This flag tell the parser that there are headers.
                              :converters =>     :numeric  #This tell it to convert string data into numeric when possible.
                          }
      )
      #puts "done reading #{csv_file} being processed"
      # We are going to collect the header names  that fit a pattern. But first we need to
      # create array containers to save the header name. In ruby we can use the string header names
      # as the array index.

      #Create arrays to store the header names for each type.
      waterheater_gas_rate_headers = Array.new()
      waterheater_electric_rate_headers = Array.new()
      waterheater_heating_rate_headers = Array.new()
      cooling_coil_electric_power_headers = Array.new()
      cooling_coil_total_cooling_rate_headers = Array.new()
      heating_coil_air_heating_rate_headers = Array.new()
      heating_coil_gas_rate_headers = Array.new()
      plant_supply_heating_demand_rate_headers = Array.new()
      facility_total_electrical_demand_headers = Array.new()
      boiler_gas_rate_headers = Array.new()
      time_index  = Array.new()
      boiler_gas_rate_headers = Array.new()
      heating_coil_electric_power_headers = Array.new()


      #remove rows 2-169 (or 1-168 in computer array terms)
      original = self.remove_rows_from_csv_table(0,72,original)


      #Scan the CSV file to file all the headers that match the pattern. This will go through all the headers and find
      # any header that matches our regular expression if a match is made, the header name is stuffed into the string array.
      original.headers.each do |header|
        stripped_header = header.strip
        waterheater_electric_rate_headers                      << header if stripped_header =~/^.*:Water Heater Electric Power \[W\]\(Hourly\)$/
        waterheater_gas_rate_headers                           << header if stripped_header =~/^.*:Water Heater Gas Rate \[W\]\(Hourly\)$/
        waterheater_heating_rate_headers                       << header if stripped_header =~/^.*:Water Heater Heating Rate \[W\]\(Hourly\)$/
        cooling_coil_electric_power_headers                    << header if stripped_header =~/^.*:Cooling Coil Electric Power \[W\]\(Hourly\)$/
        cooling_coil_total_cooling_rate_headers                << header if stripped_header =~/^.*:Cooling Coil Total Cooling Rate \[W\]\(Hourly\)$/
        heating_coil_air_heating_rate_headers                  << header if stripped_header =~/^.*:Heating Coil Air Heating Rate \[W\]\(Hourly\)$/
        heating_coil_gas_rate_headers                          << header if stripped_header =~/^.*:Heating Coil Gas Rate \[W\]\(Hourly\)$/
        heating_coil_electric_power_headers                     << header if stripped_header =~/^.*:Heating Coil Electric Power \[W\]\(Hourly\)$/
        plant_supply_heating_demand_rate_headers               << header if stripped_header =~/^(?!SWH PLANT LOOP).*:Plant Supply Side Heating Demand Rate \[W\]\(Hourly\)$/
        facility_total_electrical_demand_headers               << header if stripped_header =~/^.*:Facility Total Electric Demand Power \[W\]\(Hourly\)$/
        boiler_gas_rate_headers                                << header if stripped_header =~/^.*:Boiler Gas Rate \[W\]\(Hourly\)/

      end
      #Debug printout stuff. Make sure the output it captures the headers you want otherwise modify the regex above
      #puts waterheater_gas_rate_headers
      #puts waterheater_electric_rate_headers
      #puts waterheater_heating_rate_headers

      #puts cooling_coil_electric_power_headers
      #puts cooling_coil_total_cooling_rate_headers

      #puts heating_coil_air_heating_rate_headers
      #puts heating_coil_gas_rate_headers

      #puts plant_supply_heating_demand_rate_headers
      #puts facility_total_electrical_demand_headers
      #puts boiler_gas_rate_headers
      #puts heating_coil_electric_power_headers


      #open up a new file to save the file to..Note: This will fail it the file is open in EXCEL.
      CSV.open("#{csv_file}.terminus_hourly.csv", 'w') do |csv|
        #Create header row for new terminus hourly file.
        csv << [
            "Date/Time",
            "water_heater_gas_rate_total",
            "water_heater_electric_rate_total",
            "water_heater_heating_rate_total",
            "cooling_coil_electric_power_total",
            "cooling_coil_total_cooling_rate_total",
            "heating_coil_air_heating_rate_total",
            "heating_coil_gas_rate_total",
            "heating_coil_electric_power_total",
            "plant_supply_heating_demand_rate_total",
            "facility_total_electrical_demand_total",
            "boiler_gas_rate_total"
        ]
        original.each do |row|

          # We are now writing data to the new csv file. This is where we can manipulate the data, row by row.
          # sum the headers collected above and store in specific *_total variables.
          # This is done via a small function self.sum_row_headers. There may only be a single
          # header collected.. That is fine. It is better to be flexible than hardcode anything.
          water_heater_gas_rate_total = self.sum_row_headers(row,waterheater_gas_rate_headers)
          water_heater_electric_rate_total = self.sum_row_headers(row,waterheater_electric_rate_headers)
          water_heater_heating_rate_total  = self.sum_row_headers(row,waterheater_heating_rate_headers)
          cooling_coil_electric_power_total = self.sum_row_headers(row, cooling_coil_electric_power_headers)
          cooling_coil_total_cooling_rate_total = self.sum_row_headers(row, cooling_coil_total_cooling_rate_headers)
          heating_coil_air_heating_rate_total = self.sum_row_headers(row, heating_coil_air_heating_rate_headers)
          heating_coil_gas_rate_total = self.sum_row_headers(row, heating_coil_gas_rate_headers)
          heating_coil_electric_power_total = self.sum_row_headers(row, heating_coil_electric_power_headers)
          plant_supply_heating_demand_rate_total = self.sum_row_headers(row, plant_supply_heating_demand_rate_headers)
          facility_total_electrical_demand_total = self.sum_row_headers(row, facility_total_electrical_demand_headers)
          boiler_gas_rate_headers_total = self.sum_row_headers(row, boiler_gas_rate_headers)



          #Write the data out. Should match header row as above.
          csv << [
              row["Date/Time"], #Time index is hardcoded because every file will have a "Date/Time" column header.
              water_heater_gas_rate_total,
              water_heater_electric_rate_total,
              water_heater_heating_rate_total,
              cooling_coil_electric_power_total,
              cooling_coil_total_cooling_rate_total,
              heating_coil_air_heating_rate_total,
              heating_coil_gas_rate_total,
              heating_coil_electric_power_total,
              plant_supply_heating_demand_rate_total,
              facility_total_electrical_demand_total,
              boiler_gas_rate_headers_total
          ]
        end
      end
      #puts "Ending Terminus output processing."
    end

    def self.remove_rows_from_csv_table(start_index,stop_index,table)
      total_rows_to_remove = stop_index - start_index
      (0..total_rows_to_remove-1).each do |counter|
        table.delete(start_index)
      end
      return table
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

    #function to wrap debug == true puts
    def debug_puts(puts_text)
      if Debug_Mode == true
        puts "#{puts_text}"
      end
    end

    def get_timeseries_arrays(openstudio_sql_file, timestep, variable_name_array, regex_name_filter = /.*/, env_period = nil)
      returnArray = Array.new()
      variable_name_array.each do |variable_name|
        possible_key_values = openstudio_sql_file.availableKeyValues(env_period,timestep,variable_name)
        possible_variable_names = openstudio_sql_file.availableVariableNames(env_period,timestep).include?(variable_name)
        if not possible_variable_names.nil?  and  possible_variable_names.include?(variable_name) and not possible_key_values.nil?
          possible_key_values.get.sort.each do |key_value|
            unless regex_name_filter.match(key_value).nil?
              returnArray << get_timeseries_array(openstudio_sql_file, timestep, variable_name, key_value)
            end
          end
        end
        return returnArray
      end
    end




    #gets a time series data vector from the sql file and puts the values into a standard array of numbers
    def get_timeseries_array(openstudio_sql_file, timestep, variable_name, key_value)
      zone_time_step = "Zone Timestep"
      hourly_time_step = "Hourly"
      hvac_time_step = "HVAC System Timestep"
      timestep = hourly_time_step
      env_period = openstudio_sql_file.availableEnvPeriods[0]
      #puts openstudio_sql_file.class
      #puts env_period.class
      #puts timestep.class
      #puts variable_name.class
      #puts key_value.class
      key_value = key_value.upcase  #upper cases the key_value b/c it is always uppercased in the sql file.
      #timestep = timestep.capitalize  #capitalize the timestep b/c it is always capitalized in the sql file
      #timestep = timestep.split(" ").each{|word| word.capitalize!}.join(" ")
      #returns an array of all keyValues matching the variable name, envPeriod, and reportingFrequency
      #we'll use this to check if the query will work before we send it.
      puts "*#{env_period}*#{timestep}*#{variable_name}"
      time_series_array = []
      puts env_period.class
      if env_period.nil?

        time_series_array = [nil]
        return time_series_array
      end
      possible_env_periods = openstudio_sql_file.availableEnvPeriods()
      if possible_env_periods.nil?
        time_series_array = [nil]
        return time_series_array
      end
      possible_timesteps = openstudio_sql_file.availableReportingFrequencies(env_period)
      if possible_timesteps.nil?
        time_series_array = [nil]
        return time_series_array
      end
      possible_variable_names = openstudio_sql_file.availableVariableNames(env_period,timestep)
      if possible_variable_names.nil?
        time_series_array = [nil]
        return time_series_array
      end
      possible_key_values = openstudio_sql_file.availableKeyValues(env_period,timestep,variable_name)
      if possible_key_values.nil?
        time_series_array = [nil]
        return time_series_array
      end

      if possible_key_values.include? key_value and
          possible_variable_names.include? variable_name and
          possible_env_periods.include? env_period and
          possible_timesteps.include? timestep
        #the query is valid
        time_series = openstudio_sql_file.timeSeries(env_period, timestep, variable_name, key_value)
        if time_series #checks to see if time_series exists
          time_series = time_series.get.values
          debug_puts "  #{key_value} time series length = #{time_series.size}"
          for i in 0..(time_series.size - 1)
            #puts "#{i.to_s} -- #{time_series[i]}"
            time_series_array << time_series[i]
          end
        end
      else
        #do this if the query is not valid.  The comments might help troubleshoot.
        time_series_array = [nil]
        debug_puts "***The pieces below do NOT make a valid query***"
        debug_puts "  *#{key_value}* - this key value might not exist for the variable you are looking for"
        debug_puts "  *#{timestep}* - this value should be Hourly, Monthly, Zone Timestep, HVAC System Timestep, etc"
        debug_puts "  *#{variable_name}* - every word should be capitalized EG:  Refrigeration System Total Compressor Electric Energy "
        debug_puts "  *#{env_period}* - you can get an array of all the valid env periods by using the sql_file.availableEnvPeriods() method "
        debug_puts "  Possible key values: #{possible_key_values}"
        debug_puts "  Possible Variable Names: #{possible_variable_names}"
        debug_puts "  Possible run periods:  #{possible_env_periods}"
        debug_puts "  Possible timesteps:  #{possible_timesteps}"
      end
      return time_series_array
    end

    #gets the average of the numbers in an array
    def non_zero_array_average(arr)
      debug_puts "average of the entire array = #{arr.inject{ |sum, el| sum + el }.to_f / arr.size}"
      arr.delete(0)
      debug_puts "average of the non-zero numbers in the array = #{arr.inject{ |sum, el| sum + el }.to_f / arr.size}"
      return arr.inject{ |sum, el| sum + el }.to_f / arr.size
    end

    #method for converting from IP to SI if you know the strings of the input and the output
    def ip_to_si(number, ip_unit_string, si_unit_string)
      ip_unit = OpenStudio::createUnit(ip_unit_string, "IP".to_UnitSystem).get
      si_unit = OpenStudio::createUnit(si_unit_string, "SI".to_UnitSystem).get
      #puts "#{ip_unit} --> #{si_unit}"
      ip_quantity = OpenStudio::Quantity.new(number, ip_unit)
      si_quantity = OpenStudio::convert(ip_quantity, si_unit).get
      #puts "#{ip_quantity} = #{si_quantity}"
      return si_quantity.value
    end

    def self.compile_qaqc_results(output_folder)
      full_json = []
      Dir.foreach("#{output_folder}") do |folder|
        next if folder == '.' or folder == '..'
        Dir.glob("#{output_folder}/#{folder}/qaqc.json") { |item|
          puts "Reading #{output_folder}/#{folder}/qaqc.json"
          json = JSON.parse(File.read(item))
          json['eplusout_err']['warnings'] = json['eplusout_err']['warnings'].size
          json['eplusout_err']['severe'] = json['eplusout_err']['warnings'].size
          json['eplusout_err']['fatal'] = json['eplusout_err']['warnings'].size
          json['run_uuid'] = SecureRandom.uuid
          bldg = json['building']['name'].split('-')
          json['building_type'] = bldg[1]
          json['template'] = bldg[0]
          full_json << json
        }
      end
      File.open("#{output_folder}/../RESULTS-#{Time.now.strftime("%m-%d-%Y")}.json", 'w') {|f| f.write(JSON.pretty_generate(full_json)) }
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

    # This method converts an idf object to a hash
    #
    # @author Padmassun Rajakareyar
    # @param obj [OpenStudio::ModelObject]
    # @return new_obj_hash [Hash] idf object converted to hash.
    # @example
    #   Converts the following IDF (openstudio::ModelObject) to
    #   ==================================================================
    #   OS:Material,
    #     {8adb3faa-8e6a-48e3-bd73-ba6a02154b02}, !- Handle
    #     1/2IN Gypsum,                           !- Name
    #     Smooth,                                 !- Roughness
    #     0.0127,                                 !- Thickness {m}
    #     0.16,                                   !- Conductivity {W/m-K}
    #     784.9,                                  !- Density {kg/m3}
    #     830.000000000001,                       !- Specific Heat {J/kg-K}
    #     0.9,                                    !- Thermal Absorptance
    #     0.4,                                    !- Solar Absorptance
    #     0.4;                                    !- Visible Absorptance
    #   ===================================================================
    #
    #   ===================================================================
    #   {
    #     "Handle": "{8adb3faa-8e6a-48e3-bd73-ba6a02154b02}",
    #     "Name": "1/2IN Gypsum",
    #     "Roughness": "Smooth",
    #     "Thickness {m}": "0.0127",
    #     "Conductivity {W/m-K}": "0.16",
    #     "Density {kg/m3}": "784.9",
    #     "Specific Heat {J/kg-K}": "830.000000000001",
    #     "Thermal Absorptance": "0.9",
    #     "Solar Absorptance": "0.4",
    #     "Visible Absorptance": "0.4"
    #   },
    #   ===================================================================
    def self.idf_to_h(obj)
      # split idf object by line
      obj_string = obj.to_s.split("\n")
      new_obj_hash = {}

      # itterate through each line and split the value and field
      # and assign it to the hash
      obj_string.each_with_index {|line,i|
        next if i == 0
        line.gsub!(/(\,|\;)/, '') # remove commas and semi-colons
        line.strip! # remove whitespace at the end and the beginning of the string
        v,k = line.split(/\s*\!\-\s+/) # split the line into at the string '!-' including the spaces before and after
        new_obj_hash[k] = v
      }
      new_obj_hash
    end

    # This method uses idf_to_h(obj) method, but deletes the fields named 'Handle' and 'Name'
    #
    # @author Padmassun Rajakareyar
    # @param obj [OpenStudio::ModelObject]
    # @return new_obj_hash [Hash] idf object converted to hash.
    # @example
    #   Converts the following IDF (openstudio::ModelObject) to
    #   ==================================================================
    #   OS:Material,
    #     {8adb3faa-8e6a-48e3-bd73-ba6a02154b02}, !- Handle
    #     1/2IN Gypsum,                           !- Name
    #     Smooth,                                 !- Roughness
    #     0.0127,                                 !- Thickness {m}
    #     0.16,                                   !- Conductivity {W/m-K}
    #     784.9,                                  !- Density {kg/m3}
    #     830.000000000001,                       !- Specific Heat {J/kg-K}
    #     0.9,                                    !- Thermal Absorptance
    #     0.4,                                    !- Solar Absorptance
    #     0.4;                                    !- Visible Absorptance
    #   ===================================================================
    #
    #   ===================================================================
    #   {
    #     "Roughness": "Smooth",
    #     "Thickness {m}": "0.0127",
    #     "Conductivity {W/m-K}": "0.16",
    #     "Density {kg/m3}": "784.9",
    #     "Specific Heat {J/kg-K}": "830.000000000001",
    #     "Thermal Absorptance": "0.9",
    #     "Solar Absorptance": "0.4",
    #     "Visible Absorptance": "0.4"
    #   },
    #   ===================================================================
    def self.idf_to_h_clean(obj)
      # converts the idf object to hash
      idf_hash = idf_to_h(obj)

      # remove the field named `Handle` and `Name` from the idf_hash
      idf_hash.delete("Handle") if idf_hash.key?("Handle")
      idf_hash.delete("Handle".to_sym) if idf_hash.key?("Handle".to_sym)

      idf_hash.delete("Name") if idf_hash.key?("Name")
      idf_hash.delete("Name".to_sym) if idf_hash.key?("Name".to_sym)

      # Loop through idf_hash and delete any field that matched the UUID regex
      # idf_hash.each {|k,v|
      #   idf_hash.delete(k) if /^\{[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\}$/.match(v)
      # }
      # idf_hash
    end

    # This method will group similar objects under a key that has all the
    # values of an IDF object which excludes Handles and Names.
    # NOTE: The objexts grouped should have the fields in the same order.
    # If not, then it would not be consired as a duplicate.
    #
    # @author Padmassun Rajakareyar
    # @param obj_array [Array] An array of idf_hash. Each idf_hash was created by idf_to_h_clean or idf_to_h method
    # @return grouped_objs [Hash] grouped idf_hash based on values within the obj_array.
    # @example Output:
    #   "[\"Smooth\", \"0.216479986995276\", \"0.9\", \"0.7\", \"0.8\"]": [
    #       {
    #         "Handle": "{a7c45cf6-166d-48a6-9750-efb5c3386d91}",
    #         "Name": "Typical Carpet Pad",
    #         "Roughness": "Smooth",
    #         "Thermal Resistance {m2-K/W}": "0.216479986995276",
    #         "Thermal Absorptance": "0.9",
    #         "Solar Absorptance": "0.7",
    #         "Visible Absorptance": "0.8"
    #       },
    #       {
    #         "Handle": "{9873fb84-bfaf-459d-8b70-2c3f5722bda9}",
    #         "Name": "Typical Carpet Pad 1",
    #         "Roughness": "Smooth",
    #         "Thermal Resistance {m2-K/W}": "0.216479986995276",
    #         "Thermal Absorptance": "0.9",
    #         "Solar Absorptance": "0.7",
    #         "Visible Absorptance": "0.8"
    #       },
    #       {
    #         "Handle": "{63a12315-1de4-453a-b154-e6e6e9871be2}",
    #         "Name": "Typical Carpet Pad 4",
    #         "Roughness": "Smooth",
    #         "Thermal Resistance {m2-K/W}": "0.216479986995276",
    #         "Thermal Absorptance": "0.9",
    #         "Solar Absorptance": "0.7",
    #         "Visible Absorptance": "0.8"
    #       }
    #     ],
    def self.group_similar_objects(obj_array)
      # group [objects] by values except Handles and Name
      grouped_objs = obj_array.group_by{ |idf_hash|
        out = []
        # skip Handle and Name keys
        #
        # ideally the `keys` of the `idf_hash` should be sorted,
        # but I'll leave it alone for now
        idf_hash.each {|key, val|
          next if key == "Handle"
          next if key == "Name"
          out << val # push all the values into an array. This becomes the key of the hash that contains the duplicate objects
        }
        out
      }

      # Sort the grouped [objects] by Name.
      # This is doen such that the first object will always have the smaller name
      grouped_objs.each {|key, dup_array|
        dup_array.sort_by{|idf_hash|
          # puts idf_hash
          idf_hash['Name'] # Sort by Name
        }
      }
      return grouped_objs
    end

    # Replace the UUID of the duplicate material, unless it contains ", !- Handle"
    # This is done so after the model has been written to the disk, It can be read and
    # the duplicate materials can be removed safely.
    #
    # @author Padmassun Rajakareyar
    # @param model [OpenStudio::Model]
    # @param grouped_objs [Hash] Output provided by group_similar_objects()
    # @return model_string [String] An OpenStudio::Model object converted to a string
    def self.replace_duplicate_obj_handles(model, grouped_objs)
      model_string = model.to_s # convert the OS:Model into a String
      grouped_objs.each {|key, dup_array|
        dup_array.each_with_index {|idf_hash, index |
          next if index == 0 # skipping index 0, because it has the shortest name and considered as the original

          # givn that the idf_hash['Handle'] => '{8c88931b-e19d-479b-ac71-138d18c97cc9}'
          # The following regex matches "{8c88931b-e19d-479b-ac71-138d18c97cc9}" in the following line
          # {8c88931b-e19d-479b-ac71-138d18c97cc9}, !- Layer 1
          #
          # but matches nothing if the line has the keyword '!- Handle' in it e.g.
          # {8c88931b-e19d-479b-ac71-138d18c97cc9}, !- Handle
          replace_regex = idf_hash['Handle'].to_s.gsub('{', '\{'). # escape brackets
          gsub('}', '\}').   # escape brackets
          gsub('-', '\-') +  # escape dashes
              '(?!.*?\!\-(\s)*Handle)' # making sure the matched handle is not part of the line that contains the substring '!- Handle'
          replace_regex = Regexp.new(replace_regex)
          # p replace_regex

          # replace duplicate handles with the handle found at index 0
          model_string.gsub!(replace_regex, dup_array[0]['Handle'])# {|match| puts match;  dup_array[0]['Handle']}
        }
      }
      return model_string
    end

    # This method gets the model string, writes it in a temporary location, reads it, and
    # converts it to an OpenStudio Model using a VersionTranslater
    #
    # @author Padmassun Rajakareyar
    # @param model_string [String] An OpenStudio::Model object converted to a string
    # @return model [OpenStudio::Model]
    def self.get_OS_Model_from_string(model_string)
      require 'securerandom'
      require 'fileutils'
      # make temerorary directory called `temp` to store the osm file
      FileUtils.mkdir_p(File.join('.', 'temp'))
      # Using SecureRandom to generate the UUID to keep the osm file unique
      temp_filename =File.join('.', 'temp',SecureRandom.uuid.to_s + '.osm')
      # write the model string as a file
      File.open(temp_filename, 'w') { |file| file.write(model_string) }
      # use a VersionTranslator to read the osm model
      translator = OpenStudio::OSVersion::VersionTranslator.new
      path = OpenStudio::Path.new(temp_filename)
      # read the model
      model = translator.loadModel(path)
      model = model.get
      # remove the temporary model
      FileUtils.rm(temp_filename)
      return model
    end

    # Eleminates duplicate ModelObjects of the given ModelObject type,
    # based on the values of each fields within the ModelObject
    #
    # @author Padmassun Rajakareyar
    # @param model [OpenStudio::Model]
    # @param model_obj_type [String] ModelObject type e.g. "OS:Material"
    # @return new_model [OpenStudio::Model] Returns new model (OS:Model) if the changes were made.
    #   or else returns the old model if no changes were made.
    def self.eleminate_duplicate_objs(model, model_obj_type) # = "OS:Material")
      model_objs_json = {}

      # convert each of the ModelObjectas a hash for easy parsing
      model.getModelObjects.sort.each {|obj|
        # hsh = idf_to_h_clean(obj) # stores the idf converted to hash, without UUIDs and Name field

        # create a hash containing all the model objects sorted by the name of the model object.
        # e.g the `OS:Construction` ModelObject  type will e placed within the `OS:Construction` key, and
        # each ModelObject has been converted to an idf_hash and pushed into the array with the appropriate key.
        (model_objs_json[obj.iddObject.name.to_s] ||= []) << idf_to_h(obj) # unless hsh.empty?
      }

      # isolate a single ModelObject type specified by the model_obj_type variable
      mat_array = model_objs_json[model_obj_type]
      if mat_array.nil? # return the old model if model_obj_type is not found
        puts "Skipping because ModelObject of type [#{model_obj_type}] was not found"
        return model
      end
      # group duplicates
      grouped_objs = group_similar_objects(mat_array)
      # replace handles of duplicate objects
      model_string = replace_duplicate_obj_handles(model, grouped_objs)
      # write the model string to a file and read it as a model
      new_model = get_OS_Model_from_string(model_string)

      # Now loop through each of the grouped objects. skip the first one, and get ModelObjects (from new osm file)
      # by name and safely remove all the duplicates
      grouped_objs.each {|key, dup_array|
        dup_array.each_with_index {|object, index |
          next if index == 0
          unless object.key?('Name') # if the idf_hash does not have a key called Name, Skip it.
            puts "Skipping ModelObject of type [#{model_obj_type}] With data [#{object.inspect}] does not have a field called 'Name'"
            next
          end
          name = object['Name']
          # puts "object: [#{object}]"
          # puts "object['Name']: [#{object['Name']}]"
          # get the object to delete by name
          obj_to_delete = new_model.getModelObjectByName(name)
          if obj_to_delete.empty? # check if the object to be deleted is initialized (or present within the new model)
            puts "ModelObject of type [#{model_obj_type}] with name [#{object['Name']}] does not exist in new model"
          else
            puts "ModelObject of type [#{model_obj_type}] with name [#{object['Name']}] was deleted"
            obj_to_delete = obj_to_delete.get # get the modelObject if it is initialized
            obj_to_delete.remove # remove object form the model
          end
        }
      }
      # File.open('./models/after.osm', 'w') { |file| file.write(new_model.to_s) }


      # File.open("./models/grp_#{model_obj_type}.json", 'w') { |file| file.write(JSON.pretty_generate(grouped_objs)) }

      return new_model
      # File.open('./models/after.osm', 'w') { |file| file.write(model_string) }
      # puts("\n\n\n" + "=="*10 + "\n\n")
      # puts JSON.pretty_generate(grouped_mats)
    end

    # Eleminates duplicate Materials and Construction Objects
    # The list of ModelObjects that are removed are:
    #   "OS:Material",
    #   "OS:Material:NoMass"
    #   "OS:WindowMaterial:SimpleGlazingSystem"
    #   "OS:WindowMaterial:Glazing"
    #   "OS:WindowMaterial:Gas"
    #   "OS:StandardsInformation:Material"
    #   "OS:Construction"
    #   "OS:DefaultSurfaceConstructions"
    #   "OS:DefaultSubSurfaceConstructions"
    #   "OS:DefaultConstructionSet"
    #   "OS:StandardsInformation:Construction"
    #
    # @author Padmassun Rajakareyar
    # @param model [OpenStudio::Model]
    # @return new_model [OpenStudio::Model] Returns new model after removing the
    #   duplicate ModelObjects atated abioe.
    def self.remove_duplicate_materials_and_constructions(model)
      old_number_of_objects = model.getModelObjects.length
      new_model = model
      # eleminate dplicate Material objects
      obj_types = [
          "OS:Material",
          "OS:Material:NoMass",
          "OS:WindowMaterial:SimpleGlazingSystem",
          "OS:WindowMaterial:Glazing",
          "OS:WindowMaterial:Gas",
          "OS:StandardsInformation:Material"
      ]

      obj_types.each {|model_obj_type|
        new_model = eleminate_duplicate_objs(new_model, model_obj_type)
      }

      # eleminate dplicate Construction objects
      obj_types = [
          "OS:Construction",
          "OS:DefaultSurfaceConstructions",
          "OS:DefaultSubSurfaceConstructions",
          "OS:DefaultConstructionSet",
          "OS:StandardsInformation:Construction",
      ]
      obj_types.each {|model_obj_type|
        new_model = eleminate_duplicate_objs(new_model, model_obj_type)
      }

      new_number_of_objects = new_model.getModelObjects.length

      puts "Number of objects removed: #{old_number_of_objects - new_number_of_objects}"
      return new_model
    end


    def self.clean_osm_file( file_path: , 
                        output_path:  )

      def self.read_osm_file(file_path)
        data = []
        current_hash = {}
      
        File.foreach(file_path) do |line|
          line.strip!
          next if line.empty?
      
          if line.start_with?('OS:')
            current_hash = { type: line.split(/[;,]/).first }
            data << current_hash
          elsif line.include?('!-')
            key, value = line.split('!-').map(&:strip)
            current_hash[value] = key.chomp(',;').strip
          else
            current_hash[:id] ||= line.chomp(',;').strip
          end
        end
      
        data
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

              
      osm_data = read_osm_file(file_path)
      osm_data.sort_by! { |hash| [hash[:type], hash['Name'] || ''] }

      handles = osm_data.map { |hash| hash['Handle'] }.compact
      duplicates = handles.select { |e| handles.count(e) > 1 }
      raise "Duplicate handles found: #{duplicates.uniq}" if duplicates.any?

      osm_data.each { |hash| remove_special_characters(hash) }
      set_all_data_time(osm_data)
      set_all_epw_paths(osm_data)
      rename_handles(osm_data)
      save_osm_file(osm_data, output_path)
    end

    def self.get_relative_path(abs_path_to_file, working_folder)
      path = Pathname.new(abs_path_to_file).relative_path_from(Pathname.new(working_folder)).to_s
      file = File.basename(abs_path_to_file)
      rel_path= File.join(path)
      # Check if file exists
      if File.file?(File.join(working_folder, rel_path))
        return rel_path
      else
        raise "File does not exist at #{File.join(working_folder, rel_path)}"
      end
    end
  end #FileIO
end #BTAP
