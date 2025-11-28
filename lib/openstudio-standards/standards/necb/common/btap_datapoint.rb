require 'openstudio'
require 'securerandom'
require 'optparse'
require 'yaml'
require 'git-revision'
# resource_folder = File.join(__dir__, '..', '..', 'measures/btap_results/resources')
# OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

class BTAPDatapoint
  def initialize(input_folder: nil,
                 output_folder: nil,
                 weather_folder: nil,
                 input_folder_cache: File.join(__dir__, 'input_cache'))
    @failed = false

    # set default input folder.
    if input_folder.nil?
      input_folder = File.join(__dir__, 'input')
    end
    if output_folder.nil?
      output_folder = File.join(__dir__, 'output')
    end
    # Create an empty weather folder if one doesn't exist.  This is to avoid issues later.
    if weather_folder.nil?
      weather_folder = File.join(__dir__, 'weather')
    end
    puts("INPUT FOLDER:#{input_folder}")
    puts("OUTPUT FOLDER:#{output_folder}")

    # Set local temp cache folders. These are created new for each datapoint.
    # Location of the datapoint input folder. Could be local, cloud, or VM host.
    @dp_input_folder = File.join(input_folder)
    # Location of temp folder, it is always local.
    @dp_temp_folder = File.join(__dir__, 'temp_folder')

    # Make sure temp folder is always clean.
    FileUtils.rm_rf(@dp_temp_folder)
    FileUtils.mkdir_p(@dp_temp_folder)

    # Create local cache for datapoint folder. Makes everything faster an easier to have a local copy. Mirroring logic
    # even if running locally to be consistent.
    FileUtils.rm_rf(input_folder_cache)
    FileUtils.mkdir_p(input_folder_cache)

    # Check if input where input is from.
    if @dp_input_folder.start_with?('s3:')
      # Lets dissect the information from the s3 path.
      m = @dp_input_folder.match(%r{s3://(.*?)/(.*)})
      puts(m)
      puts(m[1])
      puts(m[2])
      @s3_bucket = m[1]
      @s3_input_folder_object = m[2]
      m = output_folder.match(%r{s3://(.*?)/(.*)})
      puts(m)
      puts(m[1])
      puts(m[2])
      @s3_output_folder_object = m[2]
      puts("s3_bucket:#{@s3_bucket}")
      puts("s3_input_folder_object:#{@s3_input_folder_object}")
      puts("s3_output_folder_object:#{@s3_output_folder_object}")

      s3_copy(source_folder: @dp_input_folder, target_folder: input_folder_cache)
    else
      raise("input folder dne:#{@dp_input_folder}") unless Dir.exist?(@dp_input_folder)

      puts @dp_input_folder
      puts input_folder_cache
      FileUtils.cp_r(File.join(@dp_input_folder, '.'), input_folder_cache)
    end
    run_options_path = File.join(input_folder_cache, 'run_options.yml')
    raise("Could not read input from #{run_options_path}") unless File.file?(run_options_path)

    @options = YAML.load_file(run_options_path)

    # Location of datapoint output folder. Could be local, cloud, or VM host.
    @dp_output_folder = File.join(output_folder, @options[:datapoint_id])

    # Show versions in yml file.
    @options[:os_git_revision] = OpenstudioStandards.git_revision

    # Get users' inputs for the parameters needed for the calculation af net present value
    @npv_start_year = @options[:npv_start_year]
    @npv_end_year = @options[:npv_end_year]
    @npv_discount_rate = @options[:npv_discount_rate]
    @npv_discount_rate_carbon = @options[:npv_discount_rate_carbon]

    # Save configuration to temp folder.
    File.open(File.join(@dp_temp_folder, 'run_options.yml'), 'w') { |file| file.write(@options.to_yaml) }
    begin
      # set up basic model.
      # This dynamically creates a class by string using the factory method design pattern.
      @options[:template] = 'NECB2011' if @options[:algorithm_type] == 'osm_batch'
      @standard = Standard.build(@options[:template])

      # Set use the convert_arg_to_bool method from the standard class to set the @oerd_utility_pricing_flag
      @oerd_utility_pricing = @standard.convert_arg_to_bool(variable: @options[:oerd_utility_pricing], default: false)
      @utility_pricing_year = @standard.convert_arg_to_f(variable: @options[:utility_pricing_year], default: 2020)

      # This allows you to select the skeleton model from our built in starting points. You can add a custom file as
      # it will search the libary first,.
      # model = load_osm(@options[:building_type]) # loads skeleton file from path.
      model = @standard.load_building_type_from_library(building_type: @options[:building_type])
      if false == model
        osm_model_path = File.absolute_path(File.join(input_folder_cache, @options[:building_type] + '.osm'))
        raise("File #{osm_model_path} not found") unless File.exist?(osm_model_path)

        model = BTAP::FileIO.load_osm(osm_model_path)
      end
      #If analysis type is osm_batch..do nothing to the osm files other than add temporal outputs and weather data.
      if @options[:algorithm_type] == 'osm_batch'
        @standard.set_output_variables(model: model, output_variables: @options[:output_variables])
        @standard.set_output_meters(model: model, output_meters: @options[:output_meters])
        climate_zone = 'NECB HDD Method'
        model.getYearDescription.setDayofWeekforStartDay('Sunday')
        epw_file = @options[:epw_file]
        epw_dir = nil
        local_epw_file_path = File.join(input_folder_cache,@options[:epw_file])
        epw_dir = input_folder_cache if File.exist? local_epw_file_path
        weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
        OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      else
        # Otherwise modify osm input with options.
        @standard.model_apply_standard(model: model,
                                       epw_file: @options[:epw_file],
                                       custom_weather_folder: weather_folder,
                                       btap_weather: @options[:btap_weather],
                                       sizing_run_dir: File.join(@dp_temp_folder, 'sizing_folder'),
                                       hvac_system_primary: @options[:hvac_system_primary],
                                       hvac_system_dwelling_units: @options[:hvac_system_dwelling_units],
                                       hvac_system_washrooms: @options[:hvac_system_washrooms],
                                       hvac_system_corridor: @options[:hvac_system_corridor],
                                       hvac_system_storage: @options[:hvac_system_storage],
                                       primary_heating_fuel: @options[:primary_heating_fuel],
                                       necb_reference_hp: @options[:necb_reference_hp],
                                       necb_reference_hp_supp_fuel: @options[:necb_reference_hp_supp_fuel],
                                       dcv_type: @options[:dcv_type], # Four options: @options[: (1) 'NECB_Default', (2) 'No DCV', (3) 'Occupancy-based DCV' , (4) 'CO2-based DCV'
                                       lights_type: @options[:lights_type], # Two options: @options[: (1) 'NECB_Default', (2) 'LED'
                                       lights_scale: @options[:lights_scale],
                                       daylighting_type: @options[:daylighting_type], # Two options: @options[: (1) 'NECB_Default', (2) 'add_daylighting_controls'
                                       ecm_system_name: @options[:ecm_system_name],
                                       ecm_system_zones_map_option: @options[:ecm_system_zones_map_option], # (1) 'NECB_Default' (2) 'one_sys_per_floor' (3) 'one_sys_per_bldg'
                                       erv_package: @options[:erv_package],
                                       boiler_eff: @options[:boiler_eff],
                                       # Inconsistent naming Todo Chris K.
                                       unitary_cop: @options[:adv_dx_units],
                                       furnace_eff: @options[:furnace_eff],
                                       shw_eff: @options[:shw_eff],
                                       ext_wall_cond: @options[:ext_wall_cond],
                                       ext_floor_cond: @options[:ext_floor_cond],
                                       ext_roof_cond: @options[:ext_roof_cond],
                                       ground_wall_cond: @options[:ground_wall_cond],
                                       ground_floor_cond: @options[:ground_floor_cond],
                                       ground_roof_cond: @options[:ground_roof_cond],
                                       door_construction_cond: @options[:door_construction_cond],
                                       fixed_window_cond: @options[:fixed_window_cond],
                                       glass_door_cond: @options[:glass_door_cond],
                                       overhead_door_cond: @options[:overhead_door_cond],
                                       skylight_cond: @options[:skylight_cond],
                                       glass_door_solar_trans: @options[:glass_door_solar_trans],
                                       fixed_wind_solar_trans: @options[:fixed_wind_solar_trans],
                                       skylight_solar_trans: @options[:skylight_solar_trans],
                                       fdwr_set: @options[:fdwr_set],
                                       srr_set: @options[:srr_set],
                                       rotation_degrees: @options[:rotation_degrees],
                                       scale_x: @options[:scale_x],
                                       scale_y: @options[:scale_y],
                                       scale_z: @options[:scale_z],
                                       pv_ground_type: @options[:pv_ground_type],
                                       pv_ground_total_area_pv_panels_m2: @options[:pv_ground_total_area_pv_panels_m2],
                                       pv_ground_tilt_angle: @options[:pv_ground_tilt_angle],
                                       pv_ground_azimuth_angle: @options[:pv_ground_azimuth_angle],
                                       pv_ground_module_description: @options[:pv_ground_module_description],
                                       nv_type: @options[:nv_type],
                                       nv_opening_fraction: @options[:nv_opening_fraction],
                                       nv_temp_out_min: @options[:nv_temp_out_min],
                                       nv_delta_temp_in_out: @options[:nv_delta_temp_in_out],
                                       occupancy_loads_scale: @options[:occupancy_loads_scale],
                                       electrical_loads_scale: @options[:electrical_loads_scale],
                                       oa_scale: @options[:oa_scale],
                                       infiltration_scale: @options[:infiltration_scale],
                                       chiller_type: @options[:chiller_type],
                                       output_variables: @options[:output_variables],
                                       output_meters: @options[:output_meters],
                                       airloop_economizer_type: @options[:airloop_economizer_type],
                                       shw_scale: @options[:shw_scale],
                                       baseline_system_zones_map_option: @options[:baseline_system_zones_map_option],
                                       tbd_option: @options[:tbd_option],
                                       necb_hdd: @options[:necb_hdd],
                                       boiler_fuel: @options[:boiler_fuel],
                                       boiler_cap_ratio: @options[:boiler_cap_ratio],
                                       swh_fuel: @options[:swh_fuel],
                                       airloop_fancoils_heating: @options[:airloop_fancoils_heating],
                                       oerd_utility_pricing: @oerd_utility_pricing
                                       )
      end

      # Save model to disk.
      puts "saving model to #{File.join(@dp_temp_folder, 'output.osm')}"
      BTAP::FileIO.save_osm(model, File.join(@dp_temp_folder, 'output.osm'))

      # Run annual simulation of model.
      if @options[:run_annual_simulation]
        @run_dir = File.join(@dp_temp_folder, 'run_dir')
        puts "running simulation in #{@run_dir}"
        @standard.model_run_simulation_and_log_errors(model, @run_dir)
        #Check if sql file was create.. if not we can't get much output.
        raise('no sql file found,simulation probably could not start due to error...see error logs.') if model.sqlFile.empty?
        # Create qaqc file and save it.
        @qaqc = BTAPDatapoint.build_qaqc(model, @standard, @options[:datapoint_id], @options[:analysis_id])

        # Load the sql file into model
        sql_path = OpenStudio::Path.new(File.join(@run_dir, 'run/eplusout.sql'))
        raise(OpenStudio::Error, 'openstudio.model.Model', "Results for the sizing run couldn't be found here: #{sql_path}.") unless OpenStudio.exists(sql_path)

        sql = OpenStudio::SqlFile.new(sql_path)
        # Check to make sure the sql file is readable,
        # which won't be true if EnergyPlus crashed during simulation.
        unless sql.connectionOpen
          raise(OpenStudio::Error, 'openstudio.model.Model', "The run failed.  Look at the eplusout.err file in #{File.dirname(sql_path.to_s)} to see the cause.")
          return false
        end
        # Attach the sql file from the run to the sizing model
        model.setSqlFile(sql)

        if @options[:enable_costing] or @options[:enable_carbon]
          @cp = CommonPaths.instance
          post_analysis = BTAPDatapointAnalysis.new(
            model: model,
            output_folder: @dp_temp_folder,
            template: @options[:template],
            standard: @standard,
            qaqc: @qaqc)
        end

        @cost_result = nil
        if @options[:enable_costing]
          @cost_result = post_analysis.run_costing(
            costs_csv: @cp.costs_path,
            factors_csv: @cp.costs_local_factors_path)
        end

        @carbon_result = nil
        if @options[:enable_carbon]
          @carbon_result = post_analysis.run_carbon
        end

        @qaqc[:options] = @options # This is options sent on the command line
        # BTAPData
        @btap_data = BTAPData.new(model: model,
                                  runner: nil,
                                  cost_result: @cost_result,
                                  carbon_result: @carbon_result,
                                  qaqc: @qaqc,
                                  npv_start_year: @npv_start_year,
                                  npv_end_year: @npv_end_year,
                                  npv_discount_rate: @npv_discount_rate,
                                  npv_discount_rate_carbon: @npv_discount_rate_carbon,
                                  oerd_utility_pricing: @oerd_utility_pricing,
                                  utility_pricing_year: @utility_pricing_year).btap_data

        # Write Files
        File.open(File.join(@dp_temp_folder, 'btap_data.json'), 'w') { |f| f.write(JSON.pretty_generate(@btap_data.sort.to_h, allow_nan: true)) }
        puts "Wrote File btap_data.json in #{Dir.pwd} "

        File.open(File.join(@dp_temp_folder, 'qaqc.json'), 'w') { |f| f.write(JSON.pretty_generate(@qaqc, allow_nan: true)) }
        puts "Wrote File qaqc.json in #{Dir.pwd} "

        #output hourly data
        self.output_hourly_data(model,@dp_temp_folder, @options[:datapoint_id])

        # Output timestep data
        self.output_timestep_data(model,@dp_temp_folder, @options[:datapoint_id])
      end
    rescue StandardError => bang
      puts "Error occured: #{bang}"
      @bang = bang
      File.open(File.join(@dp_temp_folder, 'error.txt'), 'w') { |f| f.write(@bang.message + "\n" + @bang.backtrace.join("\n")) }
      @failed = true
    ensure # will always get executed
      if @dp_output_folder.start_with?('s3://')
        @dp_output_folder = File.join(@s3_output_folder_object, @options[:datapoint_id])
        s3_copy_folder_to_s3(bucket_name: @s3_bucket,
                             source_folder: @dp_temp_folder,
                             target_folder: @dp_output_folder)
      else
        # Copy results to datapoint output folder.
        @dp_output_folder = File.join(output_folder, @options[:datapoint_id])
        FileUtils.rm_rf(@dp_output_folder)
        FileUtils.mkdir_p(@dp_output_folder)
        FileUtils.cp_r(File.join(@dp_temp_folder, '.'), @dp_output_folder) # Needs dot otherwise will copy temp folder and not just contents.
        puts "Copied output to your designated output folder in the #{@options[:datapoint_id]} subfolder."
      end

      # clean temp/cache folder up.
      FileUtils.rm_rf(input_folder_cache)
      FileUtils.rm_rf(@dp_temp_folder)
      # Do not fail container if running on AWS, handle error on AWS instead to avoid isuses with large analyses.
      unless @failed == false || (@dp_output_folder.start_with?('s3://'))
      #if @failed == true
        raise(@bang)
      end
    end
  end

  class << self

    # Initializes the qaqc data structure.
    # Scoped inside of the class so that it can be used in the intialization of
    # this class as well as in BTAPAnalysis.
    def build_qaqc(model, standard, datapoint_id, analysis_id)
      qaqc = standard.init_qaqc(model)
      command = "SELECT Value
                FROM TabularDataWithStrings
                WHERE ReportName='LEEDsummary'
                AND ReportForString='Entire Facility'
                AND TableName='Sec1.1A-General Information'
                AND RowName = 'Principal Heating Source'
                AND ColumnName='Data'"
      value = model.sqlFile.get.execAndReturnFirstString(command)
      # make sure all the data are available
      qaqc[:building][:principal_heating_source] = 'unknown'
      unless value.empty?
        qaqc[:building][:principal_heating_source] = value.get
      end

      if qaqc[:building][:principal_heating_source] == 'Additional Fuel'
        model.getPlantLoops.sort.each do |iplantloop|
          boilers = iplantloop.components.select { |icomponent| icomponent.to_BoilerHotWater.is_initialized }
          qaqc[:building][:principal_heating_source] = 'FuelOilNo2' unless boilers.select { |boiler| boiler.to_BoilerHotWater.get.fuelType.to_s == 'FuelOilNo2' }.empty?
        end
      end

      qaqc[:aws_datapoint_id] = datapoint_id
      qaqc[:aws_analysis_id]  = analysis_id

      return qaqc
    end
  end

  def s3_copy_file_to_s3(bucket_name:, source_file:, target_file:, n: 0)
    require 'aws-sdk-core'
    require 'aws-sdk-s3'
    Aws.use_bundled_cert!
    s3_client = Aws::S3::Client.new(region: 'ca-central-1')
    # Using transfer manager class instead of depricated method
    transfer_manager = Aws::S3::TransferManager.new(client: s3_client)

    puts("Copying File to S3. source_file:#{source_file} bucket:#{bucket_name} target_folder:#{target_file}")
    response = nil
    begin
      # Using upload_file from transfer manager class instead of depricated method from older class structure
      result = transfer_manager.upload_file(source_file, bucket: bucket_name, key: target_file)

      if result == true
        puts "Object '#{source_file}' uploaded to bucket '#{bucket_name}'."
      else
        puts response
        raise("Error:Object '#{source_file}' not uploaded to bucket '#{bucket_name}'.")
      end
    rescue StandardError => bang
      # Implementing exponential backoff
      # Tried 7 times.. give up.
      if n == 8
        raise("Giving Up. Failed to submit send file #{source_file} #{target_file} in 8 tries while using exponential backoff. Error was:#{bang}.")
      end

      # Exponential wait time
      wait_time = 2**n + rand
      puts "Implementing exponential backoff for sending #{target_file} for #{wait_time}s. #{n}th try"
      sleep(wait_time)
      # Do recursive function.
      return s3_copy_file_to_s3(bucket_name: bucket_name, source_file: source_file, target_file: target_file, n: n + 1)
    end
    return response
  end

  def s3_copy_folder_to_s3(bucket_name:,
                           source_folder:,
                           target_folder:)
    puts("Copying Folder to S3. source_folder:#{source_folder} bucket:#{bucket_name} target_folder:#{target_folder}")

    # Iterate over files in folder.
    Dir[File.join(source_folder, '**/*')].reject { |fn| File.directory?(fn) }.each do |source_file|
      # Convert to s3 path. Removing source parent folders and replacing with s3 output folder.
      target_file = File.join(target_folder, source_file.gsub(source_folder, ''))
      s3_copy_file_to_s3(bucket_name: bucket_name,
                         source_file: source_file,
                         target_file: target_file)
    end
  end

  def s3_copy(source_folder:,
              target_folder:)
    require 'open3'
    exit_code = nil
    error = nil
    Open3.popen2e('aws', 's3', 'cp', source_folder, target_folder, '--recursive') do |stdin, stdout_stderr, wait_thread|
      error = stdout_stderr.read
      exit_code = wait_thread.value
    end
    if exit_code != 0
      raise(error)
    end

    return exit_code
  end

  def output_hourly_data(model, output_folder, datapoint_id)
    osm_path = File.join(output_folder, "run_dir/in.osm")
    sql_path = File.join(output_folder, "run_dir/run/eplusout.sql")
    csv_output = File.join(output_folder, "hourly.csv")

    hours_of_year = []
    d = Time.new(2006, 1, 1, 1)
    (0...8760).each do |increment|
      hours_of_year << (d + (60 * 60) * increment).strftime('%Y-%m-%d %H:%M')
    end

    array_of_hashes = []

    # Find hourly outputs available for this datapoint.
    query = "
        SELECT ReportDataDictionaryIndex
        FROM ReportDataDictionary
        WHERE ReportingFrequency == 'Hourly'
                                                       "
    # Get hourly data for each output.
    model.sqlFile.get.execAndReturnVectorOfInt(query).get.each do |rdd_index|

      # Get Name
      query = "
        SELECT Name
        FROM ReportDataDictionary
        WHERE ReportDataDictionaryIndex == #{rdd_index}
      "
      name = model.sqlFile.get.execAndReturnFirstString(query).get

      # Get KeyValue
      query = "
        SELECT KeyValue
        FROM ReportDataDictionary
        WHERE ReportDataDictionaryIndex == #{rdd_index}
      "

      # In some cases KeyValue has a value and sometimes it does not.  In some cases KeyValue is null.  If the command
      # below is run and KeyValue is null then the command fails and returns an error.  The fix below assumes that if
      # the command below fails it is because KeyValue is null.  In that case the "key_value" variable is set to a
      # blank.
      begin
        key_value = model.sqlFile.get.execAndReturnFirstString(query).get
      rescue StandardError => bang
        key_value = ""
      end

      # Get Units
      query = "
        SELECT Units
        FROM ReportDataDictionary
        WHERE ReportDataDictionaryIndex == #{rdd_index}
      "
      units = model.sqlFile.get.execAndReturnFirstString(query).get

      # Get hourly data
      query = "
                    Select Value
                    FROM ReportData
                    WHERE
                        ReportDataDictionaryIndex = #{rdd_index}
      "
      hourly_values = model.sqlFile.get.execAndReturnVectorOfDouble(query).get

      hourly_hash = Hash[hours_of_year.zip(hourly_values)]

      data_hash = { "datapoint_id": datapoint_id, "Name": name, "KeyValue": key_value, "Units": units }.merge(hourly_hash)
      array_of_hashes << data_hash
    end

    CSV.open(csv_output, "wb") do |csv|
      unless array_of_hashes.empty?
        csv << array_of_hashes.first.keys # adds the attributes name on the first line
        array_of_hashes.each do |hash|
          csv << hash.values
        end
      end
    end
  end
  #=====================================================================================================================
  def output_timestep_data(model, output_folder,datapoint_id)
    osm_path = File.join(output_folder, "run_dir/in.osm")
    sql_path = File.join(output_folder, "run_dir/run/eplusout.sql")
    csv_output = File.join(output_folder, "timestep.csv")
    #===================================================================================================================
    # Get number of timesteps from the model
    number_of_timesteps_per_hour = model.getTimestep.numberOfTimestepsPerHour
    #===================================================================================================================
    # Calculate number of timesteps of the whole year
    number_of_timesteps_of_year = 365 * 24 * number_of_timesteps_per_hour

    timesteps_of_year = []
    d = Time.new(2006, 1, 1, 0)
    (0...number_of_timesteps_of_year).each do |increment|
      timesteps_of_year << (d + (60 * 60 / number_of_timesteps_per_hour) * increment).strftime('%Y-%m-%d %H:%M')
    end
    timesteps_index = Array(0..number_of_timesteps_of_year-1)
    #===================================================================================================================
    # Create a hash with indices ('timesteps_index') as keys and timesteps as values ('timesteps_of_year')
    # Note from Sara Gilani: 'I had to do this, as when I used 'timesteps_of_year' as keys to create all hashes below
    # (e.g. timestep_hash_datapoint_id, timestep_hash_name, timestep_hash_key_value, ...),
    # it did not create the right number of timesteps for the whole year'
    timesteps_of_year_with_index = Hash[timesteps_index.zip(timesteps_of_year)]
    #===================================================================================================================
    array_of_hashes = []
    array_of_hashes_transposed = []
    #===================================================================================================================
    # Find timestep outputs available for this datapoint.
    query = "
        SELECT ReportDataDictionaryIndex
        FROM ReportDataDictionary
        WHERE ReportingFrequency == 'Zone Timestep'
        "
    #===================================================================================================================
    # Get timestep data for each output.
    model.sqlFile.get.execAndReturnVectorOfInt(query).get.each do |rdd_index|
      #=================================================================================================================
      # Get Name
      query = "
        SELECT Name
        FROM ReportDataDictionary
        WHERE ReportDataDictionaryIndex == #{rdd_index}
      "
      name = model.sqlFile.get.execAndReturnFirstString(query).get
      #=================================================================================================================
      # Get KeyValue
      query = "
        SELECT KeyValue
        FROM ReportDataDictionary
        WHERE ReportDataDictionaryIndex == #{rdd_index}
      "
      #=================================================================================================================
      # In some cases KeyValue has a value and sometimes it does not.  In some cases KeyValue is null.  If the command
      # below is run and KeyValue is null then the command fails and returns an error.  The fix below assumes that if
      # the command below fails it is because KeyValue is null.  In that case the "key_value" variable is set to a
      # blank.
      begin
        key_value = model.sqlFile.get.execAndReturnFirstString(query).get
      rescue StandardError => bang
        key_value = ""
      end
      #=================================================================================================================
      # Get Units
      query = "
        SELECT Units
        FROM ReportDataDictionary
        WHERE ReportDataDictionaryIndex == #{rdd_index}
      "
      units = model.sqlFile.get.execAndReturnFirstString(query).get
      #=================================================================================================================
      # Get timestep data
      query = "
        Select VariableValue
        FROM ReportVariableData
        WHERE
        ReportVariableDataDictionaryIndex = #{rdd_index}
      "
      timestep_values = model.sqlFile.get.execAndReturnVectorOfDouble(query).get

      timestep_hash = Hash[timesteps_index.zip(timestep_values)]

      data_hash = { "datapoint_id": datapoint_id, "Name": name, "KeyValue": key_value, "Units": units }.merge(timestep_hash)

      array_of_hashes << data_hash

      #=================================================================================================================
      # Create a hash of data for having timesteps as rows instead of columns that is used for hourly outputs START
      number_of_timesteps = timesteps_of_year.length()

      array = [datapoint_id]
      array_datapoint_id = array.zip(*[array]*number_of_timesteps).flatten
      timestep_hash_datapoint_id = Hash[timesteps_index.zip(array_datapoint_id)]

      array = [name]
      array_name = array.zip(*[array]*number_of_timesteps).flatten
      timestep_hash_name = Hash[timesteps_index.zip(array_name)]

      array = [key_value]
      array_key_value = array.zip(*[array]*number_of_timesteps).flatten
      timestep_hash_key_value = Hash[timesteps_index.zip(array_key_value)]

      array = [units]
      array_units = array.zip(*[array]*number_of_timesteps).flatten
      timestep_hash_units = Hash[timesteps_index.zip(array_units)]

      timestep_hash_values = Hash[timesteps_index.zip(timestep_values)]

      data_hash_transposed = Hash.new
      timestep_hash_values.keys.each do |key|
        data_hash_transposed[key] = [
          timesteps_of_year_with_index[key],
          timestep_hash_datapoint_id[key],
          timestep_hash_name[key],
          timestep_hash_key_value[key],
          timestep_hash_units[key],
          timestep_hash_values[key]
        ]
      end

      array_of_hashes_transposed << data_hash_transposed
      # Create a hash of data for having timesteps as rows instead of columns that is used for hourly outputs END
      #=================================================================================================================

    end #model.sqlFile.get.execAndReturnVectorOfInt(query).get.each do |rdd_index|
    #===================================================================================================================
    # # This csv file has timesteps as the first row
    # CSV.open(csv_output, "wb") do |csv|
    #   unless array_of_hashes.empty?
    #     csv << array_of_hashes.first.keys # adds the attributes name on the first line
    #     array_of_hashes.each do |hash|
    #       csv << hash.values
    #     end
    #   end
    # end
    #===================================================================================================================
    # This csv file has timesteps as the first column
    header = ['Index', 'Timestep', 'datapoint_id', 'Name', 'KeyValue', 'Units', 'Value']
    CSV.open(csv_output, "wb") do |csv|
      csv << header
      array_of_hashes_transposed.each do |hash|
        hash.keys().each do |index|
          row_index = index
          row_timestep = hash[index][0]
          row_datapoint_id = hash[index][1]
          row_name = hash[index][2]
          row_key_value = hash[index][3]
          row_units = hash[index][4]
          row_value = hash[index][5]

          row = CSV::Row.new(header,[])
          row['Index'] = row_index
          row['Timestep'] = row_timestep
          row['datapoint_id'] = row_datapoint_id
          row['Name'] = row_name
          row['KeyValue'] = row_key_value
          row['Units'] = row_units
          row['Value'] = row_value
          csv << row
        end
      end
    end
    #===================================================================================================================
  end #output_timestep_data
  #=====================================================================================================================
end
