require 'csv'
require 'json-schema'

# This abstract class holds methods that many versions of ASHRAE 90.1 share.
# If a method in this class is redefined by a subclass,
# the implementation in the subclass is used.
# @abstract
class ASHRAE901PRM < Standard
  def initialize
    super()
    load_standards_database
    @sizing_run_dir = Dir.pwd
  end

  def load_standards_database(data_directories = [])
    super([__dir__] + data_directories)
  end

  # Method to generate user data from a user model and save the csvs to the user_data_path
  # This method can generate one user data csv based on the matching name or a full set of user data if
  # leave it as nil
  # @param user_model [OpenStudio::Model::Model] OpenStudio model object
  # @param user_data_path [String] data path
  # @param user_data_file [String] the name of the user data file.
  def generate_userdata_to_csv(user_model, user_data_path, user_data_file = nil)
    user_data_list = [UserDataCSVAirLoopHVAC.new(user_model, user_data_path),
                      UserDataCSVBuilding.new(user_model, user_data_path),
                      UserDataCSVSpace.new(user_model, user_data_path),
                      UserDataCSVSpaceTypes.new(user_model, user_data_path),
                      UserDataCSVAirLoopHVACDOAS.new(user_model, user_data_path),
                      UserDataCSVExteriorLights.new(user_model, user_data_path),
                      UserDataCSVLights.new(user_model, user_data_path),
                      UserDataCSVThermalZone.new(user_model, user_data_path),
                      UserDataCSVElectricEquipment.new(user_model, user_data_path),
                      UserDataCSVGasEquipment.new(user_model, user_data_path),
                      UserDataCSVOutdoorAir.new(user_model, user_data_path),
                      UserDataWaterUseConnection.new(user_model, user_data_path),
                      UserDataWaterUseEquipment.new(user_model, user_data_path),
                      UserDataWaterUseEquipmentDefinition.new(user_model, user_data_path)]

    if user_data_file.nil?
      user_data_list.each(&:write_csv)
    else
      user_data_list.each do |user_data|
        if user_data.file_name == user_data_file
          user_data.write_csv
        end
      end
    end
  end

  # Convert user data csv files to json format and save to project folder
  # Method will create the json_folder in the project_path
  # @author Doug Maddox, PNNL
  # @param user_data_path [String path to folder containing csv files
  # @param project_path [String path to project folder
  # @return [String] path to json files
  def convert_userdata_csv_to_json(user_data_path, project_path)
    # Get list of possible files from lib\openstudio-standards\standards\ashrae_90_1_prm\userdata_csv
    stds_dir = __dir__
    src_csv_dir = "#{stds_dir}/userdata_csv/*.csv"
    json_objs = {}

    Dir.glob(src_csv_dir).each do |csv_full_name|
      json_rows = []
      csv_file_name = File.basename(csv_full_name, File.extname(csv_full_name))
      unless UserDataFiles.matched_any?(csv_file_name)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "user data file: #{csv_file_name} is not a valid file name. See the full list of acceptable file names in https://pnnl.github.io/BEM-for-PRM/user_guide/add_compliance_data/")
      end
      json_objs[csv_file_name] = json_rows
    end

    # Read all valid files in user_data_folder and load into json array
    unless user_data_path == ''
      user_data_validation_outcome = true
      Dir.glob("#{user_data_path.gsub('\\', '/')}/*.csv").each do |csv_full_name|
        csv_file_name = File.basename(csv_full_name, File.extname(csv_full_name))
        if json_objs.key?(csv_file_name)
          # Load csv file into array of hashes
          json_rows = CSV.foreach(csv_full_name, headers: true).map { |row| user_data_preprocessor(row) }
          next if json_rows.empty?

          # validate the user_data in json_rows
          unless user_data_validation(csv_file_name, json_rows)
            user_data_validation_outcome = false
          end

          # remove file extension
          file_name = File.basename(csv_full_name, File.extname(csv_full_name))
          json_objs[file_name] = json_rows
        end
      end
      unless user_data_validation_outcome
        terminate_prm_write_log('Error found in the user data. Check output log to see detail error messages', project_path, false)
      end
    end

    # Make folder for json files; remove pre-existing first, if needed
    json_path = "#{project_path}/user_data_json"
    FileUtils.rm_rf(json_path)
    FileUtils.mkdir_p(json_path)

    # Write all json files
    json_objs.each do |file_name, json_rows|
      json_obj = {}
      json_obj[file_name] = json_rows
      json_path_file = "#{json_path}/#{file_name}.json"
      File.open(json_path_file, 'w:UTF-8') do |file|
        file << JSON.pretty_generate(json_obj)
      end
    end

    return json_path
  end

  def load_schemas
    schemas = {}
    schema_folder_path = File.expand_path('./userdata_json', __dir__)
    Dir.glob(File.join(schema_folder_path, '*.json')).each do |file_path|
      filename = File.basename(file_path)
      schema = JSON.parse(File.read(file_path))
      schemas[filename] = schema
    end
    schemas
  end

  # Load user data from project folder into standards database data structure
  # Each user data object type is a new item in the @standards_data hash
  # @author Doug Maddox, PNNL
  # @param json_path [String path to folder containing json files
  def load_userdata_to_standards_database(json_path)
    files = Dir.glob("#{json_path}/*.json").select { |e| File.file? e }
    # load json schema
    schemas = load_schemas
    files.each do |file|
      file_name = File.basename(file)
      data = JSON.parse(File.read(file))
      # schema validation
      begin
        schema = schemas[file_name]
        JSON::Validator.validate!(schema, data)
      rescue JSON::Schema::ValidationError => e
        puts "Validation error #{file_name} failed due to: #{e.message}"
      rescue StandardError => e
        puts "Error, cannot read the file. #{e.message}"
      end

      data.each_pair do |key, objs|
        # Override the template in inherited files to match the instantiated template
        if @standards_data[key].nil?
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Adding #{key} from #{File.basename(file)}")
        else
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.standard', "Overriding #{key} with #{File.basename(file)}")
        end
        @standards_data[key] = objs

        next if objs.empty?
      end
    end
  end

  # Convert user csv data raw value to appropriate type
  def convert_value(hash_value)
    hash_value.transform_values do |value|
      next nil if value.nil? || value.strip.empty?

      # Trim white space and convert to lower case
      value = value.strip
      lower_case_value = value.downcase

      # Convert types
      case lower_case_value
      when /^\d+$/
        lower_case_value.to_i
      when /^\d+\.\d+$/
        lower_case_value.to_f
      when 'true'
        true
      when 'false'
        false
      else
        # preserve the case
        value
      end
    end
  end

  # Perform user data preprocessing
  # @param [CSV::ROW] row 2D array for each row. The row is limited to 2 indexes, representing key and value.
  def user_data_preprocessor(row)
    new_array = []

    # Strip the strings in the value
    row.each do |sub_array|
      new_array << sub_array.collect { |e| e ? e.strip : e }
    end
    # @todo Future expansion can added to here.
    # Convert the 2d array to hash and return
    convert_value(new_array.to_h)
  end

  # Perform user data validation

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def user_data_validation(object_name, user_data)
    # 1. Check user_spacetype and user_space LPD total % = 1.0
    case object_name
    when UserDataFiles::BUILDING
      return check_userdata_building(object_name, user_data)
    when UserDataFiles::SPACE, UserDataFiles::SPACETYPE
      return check_userdata_space_and_spacetype(object_name, user_data)
    when UserDataFiles::ELECTRIC_EQUIPMENT
      return check_userdata_electric_equipment(object_name, user_data)
    when UserDataFiles::GAS_EQUIPMENT
      return check_userdata_gas_equipment(object_name, user_data)
    when UserDataFiles::LIGHTS
      return check_userdata_lights(object_name, user_data)
    when UserDataFiles::EXTERIOR_LIGHTS
      return check_userdata_exterior_lighting(object_name, user_data)
    when UserDataFiles::AIRLOOP_HVAC
      return check_userdata_airloop_hvac(object_name, user_data)
    when UserDataFiles::DESIGN_SPECIFICATION_OUTDOOR_AIR
      return check_userdata_outdoor_air(object_name, user_data)
    when UserDataFiles::AIRLOOP_HVAC_DOAS
      return check_userdata_airloop_hvac_doas(object_name, user_data)
    when UserDataFiles::ZONE_HVAC
      return check_userdata_zone_hvac(object_name, user_data)
    when UserDataFiles::THERMAL_ZONE
      return check_userdata_thermal_zone(object_name, user_data)
    when UserDataFiles::WATERUSE_CONNECTIONS
      return check_userdata_wateruse_connections(object_name, user_data)
    when UserDataFiles::WATERUSE_EQUIPMENT
      return check_userdata_wateruse_equipment(object_name, user_data)
    when UserDataFiles::WATERUSE_EQUIPMENT_DEFINITION
      return check_userdata_wateruse_equipment_definition(object_name, user_data)
    else
      return true
    end
  end

  # Check for incorrect data in [UserDataFiles::LIGHTS]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_lights(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_light|
      name = prm_read_user_data(user_light, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: lights name is missing or empty. Lights user data has not validated.")
        return false
      end

      has_retail_display_exception = prm_read_user_data(user_light, 'has_retail_display_exception')
      unless has_retail_display_exception.nil? || UserDataBoolean.matched_any?(has_retail_display_exception)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Lights name #{name}, has_retail_display_exception shall be either True or False. Got #{has_retail_display_exception}")
        userdata_valid = false
      end

      has_unregulated_exception = prm_read_user_data(user_light, 'has_unregulated_exception')
      unless has_unregulated_exception.nil? || UserDataBoolean.matched_any?(has_unregulated_exception)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Lights name #{name}, has_unregulated_exception shall be either True or False. Got #{has_unregulated_exception}")
        userdata_valid = false
      end
    end
    # do we need to regulate the unregulated_category?
    return userdata_valid
  end

  # Check for incorrect data in [UserDataFiles::BUILDING]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_building(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_building|
      name = prm_read_user_data(user_building, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: building name is missing or empty. Building user data has not validated.")
        return false
      end

      building_type_for_hvac = prm_read_user_data(user_building, 'building_type_for_hvac')
      unless building_type_for_hvac.nil? || UserDataHVACBldgType.matched_any?(building_type_for_hvac)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "Unknown building type #{building_type_for_hvac} for prescribed HVAC system type. For full list of the building type, see: https://pnnl.github.io/BEM-for-PRM/user_guide/prm_api_ref/baseline_generation_api/#--default_hvac_bldg_type")
        userdata_valid = false
      end

      building_type_for_wwr = prm_read_user_data(user_building, 'building_type_for_wwr')
      unless building_type_for_wwr.nil? || UserDataWWRBldgType.matched_any?(building_type_for_wwr)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "Unknown building type #{building_type_for_hvac} for prescribed window-to-wall ratio. For full list of the building type, see: https://pnnl.github.io/BEM-for-PRM/user_guide/prm_api_ref/baseline_generation_api/#--default_wwr_bldg_type")
        userdata_valid = false
      end

      building_type_for_swh = prm_read_user_data(user_building, 'building_type_for_swh')
      unless building_type_for_swh.nil? || UserDataSHWBldgType.matched_any?(building_type_for_swh)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "Unknown building type #{building_type_for_hvac} for prescribed service hot water system. For full list of the building type, see: https://pnnl.github.io/BEM-for-PRM/user_guide/prm_api_ref/baseline_generation_api/#--default_swh_bldg_type")
        userdata_valid = false
      end

      is_exempt_from_rotations = prm_read_user_data(user_building, 'is_exempt_from_rotations')
      unless is_exempt_from_rotations.nil? || UserDataBoolean.matched_any?(is_exempt_from_rotations)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Building name #{name}, is_exempt_from_rotations shall be either True or False. Got #{is_exempt_from_rotations}.")
        userdata_valid = false
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in [UserDataFiles::THERMAL_ZONE]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_thermal_zone(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_thermal_zone|
      name = prm_read_user_data(user_thermal_zone, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: thermal zone name is missing or empty. Thermal zone user data has not validated.")
        return false
      end
      has_health_safety_night_cycle_exception = prm_read_user_data(user_thermal_zone, 'has_health_safety_night_cycle_exception')
      unless has_health_safety_night_cycle_exception.nil? || UserDataBoolean.matched_any?(has_health_safety_night_cycle_exception)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Thermal zone name #{name}, has_health_safety_night_cycle_exception shall be either True or False. Got #{has_health_safety_night_cycle_exception}")
        userdata_valid = false
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in [UserDataFiles::ZONE_HVAC]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_zone_hvac(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_zone_hvac|
      name = prm_read_user_data(user_zone_hvac, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: zone HVAC name is missing or empty. Zone HVAC user data has not validated.")
        return false
      end
      # Fan power credits, exhaust air energy recovery
      user_zone_hvac.each_key do |info_key|
        # Fan power credits
        if info_key.include?('has_fan_power_credit')
          has_fan_power_credit = prm_read_user_data(user_zone_hvac, info_key)
          unless has_fan_power_credit.nil? || UserDataBoolean.matched_any?(has_fan_power_credit)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, zone HVAC name #{name}, #{info_key} shall be either True or False. Got #{has_fan_power_credit}.")
            userdata_valid = false
          end
        elsif info_key.include?('fan_power_credit')
          fan_power_credit = prm_read_user_data(user_zone_hvac, info_key)
          unless fan_power_credit.nil? || Float(fan_power_credit, exception: false)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, zone HVAC name #{name}, #{info_key} shall be a numeric value. Got #{fan_power_credit}.")
            userdata_valid = false
          end
        end
        # Exhaust air energy recovery
        if info_key.include?('exhaust_energy_recovery_exception')
          exhaust_energy_recovery_exception = prm_read_user_data(user_zone_hvac, info_key)
          unless exhaust_energy_recovery_exception.nil? || UserDataBoolean.matched_any?(exhaust_energy_recovery_exception)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, zone HVAC name #{name}, #{info_key} shall be either True or False. Got #{exhaust_energy_recovery_exception}.")
            userdata_valid = false
          end
        end
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in [UserDataFiles::AIRLOOP_HVAC_DOAS]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_airloop_hvac_doas(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_airloop|
      name = prm_read_user_data(user_airloop, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: air loop name is missing or empty. Air loop user data has not validated.")
        return false
      end
      # Fan power credits, exhaust air energy recovery
      user_airloop.each_key do |info_key|
        # Fan power credits
        if info_key.include?('has_fan_power_credit')
          has_fan_power_credit = prm_read_user_data(user_airloop, info_key)
          unless has_fan_power_credit.nil? || UserDataBoolean.matched_any?(has_fan_power_credit)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, #{info_key} shall be either True or False. Got #{has_fan_power_credit}.")
            userdata_valid = false
          end
        elsif info_key.include?('fan_power_credit')
          fan_power_credit = prm_read_user_data(user_airloop, info_key)
          unless fan_power_credit.nil? || Float(fan_power_credit, exception: false)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, #{info_key} shall be a numeric value. Got #{fan_power_credit}.")
            userdata_valid = false
          end
        end
        # Exhaust air energy recovery
        if info_key.include?('exhaust_energy_recovery_exception')
          exhaust_energy_recovery_exception = prm_read_user_data(user_airloop, info_key)
          unless exhaust_energy_recovery_exception.nil? || UserDataBoolean.matched_any?(exhaust_energy_recovery_exception)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, #{info_key} shall be either True or False. Got #{exhaust_energy_recovery_exception}.")
            userdata_valid = false
          end
        end
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in [UserDataFiles::DESIGN_SPECIFICATION_OUTDOOR_AIR]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_outdoor_air(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_oa|
      name = prm_read_user_data(user_oa, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: air loop name is missing or empty. Air loop user data has not validated.")
        return false
      end

      outdoor_airflow_per_person = prm_read_user_data(user_oa, 'outdoor_airflow_per_person')
      unless outdoor_airflow_per_person.nil? || Float(outdoor_airflow_per_person, exception: false)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Design outdoor air name #{name}, outdoor_airflow_per_person shall be a numeric value. Got #{outdoor_airflow_per_person}.")
        userdata_valid = false
      end

      outdoor_airflow_per_floor_area = prm_read_user_data(user_oa, 'outdoor_airflow_per_floor_area')
      unless outdoor_airflow_per_floor_area.nil? || Float(outdoor_airflow_per_floor_area, exception: false)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Design outdoor air name #{name}, outdoor_airflow_per_floor_area shall be a numeric value. Got #{outdoor_airflow_per_floor_area}.")
        userdata_valid = false
      end

      outdoor_air_flowrate = prm_read_user_data(user_oa, 'outdoor_air_flowrate')
      unless outdoor_air_flowrate.nil? || Float(outdoor_air_flowrate, exception: false)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Design outdoor air name #{name}, outdoor_air_flowrate shall be a numeric value. Got #{outdoor_air_flowrate}.")
        userdata_valid = false
      end

      outdoor_air_flow_air_changes_per_hour = prm_read_user_data(user_oa, 'outdoor_air_flow_air_changes_per_hour')
      unless outdoor_air_flow_air_changes_per_hour.nil? || Float(outdoor_air_flow_air_changes_per_hour, exception: false)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Design outdoor air name #{name}, outdoor_air_flow_air_changes_per_hour shall be a numeric value. Got #{outdoor_air_flow_air_changes_per_hour}.")
        userdata_valid = false
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in [UserDataFiles::AIRLOOP_HVAC]
  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file
  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_airloop_hvac(object_name, user_data)
    userdata_valid = true
    user_data.each do |user_airloop|
      name = prm_read_user_data(user_airloop, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: air loop name is missing or empty. Air loop user data has not validated.")
        return false
      end
      # gas phase air cleaning is system base - add proposed hvac system name to zones
      economizer_exception_for_gas_phase_air_cleaning = prm_read_user_data(user_airloop, 'economizer_exception_for_gas_phase_air_cleaning', UserDataBoolean::FALSE)
      unless economizer_exception_for_gas_phase_air_cleaning.nil? || UserDataBoolean.matched_any?(economizer_exception_for_gas_phase_air_cleaning)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, economizer_exception_for_gas_phase_air_cleaning shall be either True or False. Got #{economizer_exception_for_gas_phase_air_cleaning}")
        userdata_valid = false
      end

      economizer_exception_for_open_refrigerated_cases = prm_read_user_data(user_airloop, 'economizer_exception_for_open_refrigerated_cases', UserDataBoolean::FALSE)
      unless economizer_exception_for_open_refrigerated_cases.nil? || UserDataBoolean.matched_any?(economizer_exception_for_open_refrigerated_cases)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, economizer_exception_for_open_refrigerated_cases shall be either True or False. Got #{economizer_exception_for_open_refrigerated_cases}")
        userdata_valid = false
      end

      # Fan power credits, exhaust air energy recovery
      user_airloop.each_key do |info_key|
        # Fan power credits
        if info_key.include?('has_fan_power_credit')
          has_fan_power_credit = prm_read_user_data(user_airloop, info_key)
          unless has_fan_power_credit.nil? || UserDataBoolean.matched_any?(has_fan_power_credit)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, #{info_key} shall be either True or False. Got #{has_fan_power_credit}.")
            userdata_valid = false
          end
        elsif info_key.include?('fan_power_credit')
          fan_power_credit = prm_read_user_data(user_airloop, info_key)
          unless fan_power_credit.nil? || Float(fan_power_credit, exception: false)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, #{info_key} shall be a numeric value. Got #{fan_power_credit}.")
            userdata_valid = false
          end
        end
        # Exhaust air energy recovery
        if info_key.include?('exhaust_energy_recovery_exception')
          exhaust_energy_recovery_exception = prm_read_user_data(user_airloop, info_key)
          unless exhaust_energy_recovery_exception.nil? || UserDataBoolean.matched_any?(exhaust_energy_recovery_exception)
            OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Air Loop name #{name}, #{info_key} shall be either True or False. Got #{has_fan_power_credit}.")
            userdata_valid = false
          end
        end
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in exterior lights user data

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_exterior_lighting(object_name, user_data)
    userdata_valid = true
    user_data.each do |exterior_light|
      name = prm_read_user_data(exterior_light, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: exterior light name is missing or empty. Exterior light user data has not validated.")
        return false
      end

      num_cats = prm_read_user_data(exterior_light, 'num_ext_lights_subcats', '0').to_i
      (1..num_cats).each do |icat|
        cat_key = format('end_use_subcategory_%02d', icat)
        subcat = prm_read_user_data(exterior_light, cat_key, nil)
        unless subcat
          OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, Exterior light: #{name}, #{cat_key} is either missing or empty.")
          userdata_valid = false
        end
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in gas equipment user data

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_gas_equipment(object_name, user_data)
    userdata_valid = true
    user_data.each do |gas_row|
      name = prm_read_user_data(gas_row, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: gas equipoment name is missing or empty. Gas equipment user data has not validated.")
        return false
      end
      # check for fractions
      fraction_of_controlled_receptacles = prm_read_user_data(gas_row, 'fraction_of_controlled_receptacles')
      unless fraction_of_controlled_receptacles.nil? || Float(fraction_of_controlled_receptacles, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: gas equipment definition #{name}'s fraction of controlled receptacles shall be a float, Got #{fraction_of_controlled_receptacles}.")
      end
      receptacle_power_savings = prm_read_user_data(gas_row, 'receptacle_power_savings')
      unless receptacle_power_savings.nil? || Float(receptacle_power_savings, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: gas equipment definition #{name}'s receptacle power savings shall be a float, Got #{receptacle_power_savings}.")
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in electric equipment user data

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_electric_equipment(object_name, user_data)
    userdata_valid = true
    user_data.each do |electric_row|
      name = prm_read_user_data(electric_row, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: electric equipoment name is missing or empty. Electric equipment user data has not validated.")
        return false
      end
      # check for fractions
      fraction_of_controlled_receptacles = prm_read_user_data(electric_row, 'fraction_of_controlled_receptacles')
      unless fraction_of_controlled_receptacles.nil? || Float(fraction_of_controlled_receptacles, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: electric equipment definition #{name}'s fraction of controlled receptacles shall be a float, Got #{fraction_of_controlled_receptacles}.")
      end
      receptacle_power_savings = prm_read_user_data(electric_row, 'receptacle_power_savings')
      unless receptacle_power_savings.nil? || Float(receptacle_power_savings, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: electric equipment definition #{name}'s receptacle power savings shall be a float, Got #{receptacle_power_savings}.")
      end
      # check for data type
      # unless fan_power_credit.nil? || Float(fan_power_credit, exception: false)
      motor_horsepower = prm_read_user_data(electric_row, 'motor_horsepower')
      unless motor_horsepower.nil? || Float(motor_horsepower, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Motor #{electric_row['name']}'s horsepower data is either 0.0 or unavailable. Check the inputs.")
      end
      motor_efficiency = prm_read_user_data(electric_row, 'motor_efficiency')
      unless motor_efficiency.nil? || Float(motor_efficiency, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Motor #{electric_row['name']}'s efficiency data is either 0.0 or unavailable. Check the inputs.")
      end
      motor_is_exempt = prm_read_user_data(electric_row, 'motor_is_exempt')
      unless motor_is_exempt.nil? || UserDataBoolean.matched_any?(motor_is_exempt)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Motor #{electric_row['name']} is exempt data should be either True or False. But get data #{electric_row['motor_is_exempt']}")
      end
      # We may need to do the same for refrigeration and elevator?
      # Check elevator
      elevator_weight_of_car = prm_read_user_data(electric_row, 'elevator_weight_of_car')
      unless elevator_weight_of_car.nil? || Float(elevator_weight_of_car, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Elevator #{electric_row['name']}'s weight of car data is either 0.0 or unavailable. Check the inputs.")
      end
      elevator_rated_load = prm_read_user_data(electric_row, 'elevator_rated_load')
      unless elevator_rated_load.nil? || Float(elevator_rated_load, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Elevator #{electric_row['name']}'s rated load data is either 0.0 or unavailable. Check the inputs.")
      end
      elevator_counter_weight_of_car = prm_read_user_data(electric_row, 'elevator_counter_weight_of_car')
      unless elevator_counter_weight_of_car.nil? || Float(elevator_counter_weight_of_car, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Elevator #{electric_row['name']}'s counter weight of car data is either 0.0 or unavailable. Check the inputs.")
      end
      elevator_speed_of_car = prm_read_user_data(electric_row, 'elevator_speed_of_car')
      unless elevator_speed_of_car.nil? || Float(elevator_speed_of_car, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Elevator #{electric_row['name']}'s speed of car data is either 0.0 or unavailable. Check the inputs.")
      end
      elevator_number_of_stories = prm_read_user_data(electric_row, 'elevator_number_of_stories')
      unless elevator_number_of_stories.nil? || Integer(elevator_number_of_stories, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Elevator #{electric_row['name']}'s serves number of stories data is either smaller or equal to 1 or unavailable. Check the inputs.")
      end
      # Check refrigeration
      # Check data type
      # The equipment class shall be verified at the implementation level
      refrigeration_equipment_volume = prm_read_user_data(electric_row, 'refrigeration_equipment_volume')
      unless refrigeration_equipment_volume.nil? || Float(refrigeration_equipment_volume, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Refrigeration #{electric_row['name']}'s equipment volume data is either 0.0 or unavailable. Check the inputs.")
      end
      refrigeration_equipment_total_display_area = prm_read_user_data(electric_row, 'refrigeration_equipment_total_display_area')
      unless refrigeration_equipment_total_display_area.nil? || Float(refrigeration_equipment_total_display_area, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: Refrigeration #{electric_row['name']}'s total display area data is either 0.0 or unavailable. Check the inputs.")
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in space and spacetype user data

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_space_and_spacetype(object_name, user_data)
    userdata_valid = true
    user_data.each do |row|
      building_type_for_wwr = prm_read_user_data(row, 'building_type_for_wwr')
      unless building_type_for_wwr.nil? || UserDataWWRBldgType.matched_any?(building_type_for_wwr)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "Unknown building type #{building_type_for_wwr} for prescribed window to wall ratio. For full list of the building type, see: https://pnnl.github.io/BEM-for-PRM/user_guide/prm_api_ref/baseline_generation_api/#--default_wwr_bldg_type")
        userdata_valid = false
      end
      unless prm_read_user_data(row, 'num_std_ltg_types', '0').to_i == 0
        num_ltg_type = row['num_std_ltg_types'].to_i
        total_ltg_percent = 0.0
        std_ltg_index = 0
        while std_ltg_index < num_ltg_type
          frac_key = format('std_ltg_type_frac%02d', (std_ltg_index + 1))
          total_ltg_percent += prm_read_user_data(row, frac_key, '0.0').to_f
          std_ltg_index += 1
        end
        if (total_ltg_percent - 1.0).abs > 0.01
          OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data #{object_name}: The fraction of user defined lighting types in Space/SpaceType: #{row['name']} does not add up to 1.0. The calculated fraction is #{total_ltg_percent}.")
          userdata_valid = false
        end
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in water use connections

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_wateruse_connections(object_name, user_data)
    userdata_valid = true
    user_data.each do |row|
      name = prm_read_user_data(row, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: water use connection name is missing or empty. user data is not validated.")
        return false
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in water use equipment

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_wateruse_equipment(object_name, user_data)
    userdata_valid = true
    user_data.each do |row|
      name = prm_read_user_data(row, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: water use equipment name is missing or empty. user data is not validated.")
        return false
      end

      building_swh_type = prm_read_user_data(row, 'building_type_swh', nil)
      # gas phase air cleaning is system base - add proposed hvac system name to zones
      unless building_swh_type.nil? || UserDataSHWBldgType.matched_any?(building_swh_type)
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}, water equipment name #{name}, building_type_swh shall be one of the string listed in https://pnnl.github.io/BEM-for-PRM/user_guide/prm_api_ref/baseline_generation_api/#--default_swh_bldg_type. Got #{building_swh_type}")
        userdata_valid = false
      end
    end
    return userdata_valid
  end

  # Check for incorrect data in water use equipment definition

  # @param object_name [String] name of user data csv file to check
  # @param user_data [Hash] hash of data from user data csv file

  # @return [Boolean] true if data is valid, false if error found
  def check_userdata_wateruse_equipment_definition(object_name, user_data)
    userdata_valid = true
    user_data.each do |row|
      name = prm_read_user_data(row, 'name')
      unless name
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: water use equipment name is missing or empty. user data is not validated.")
        return false
      end
      # check for data type
      peak_flow_rate = prm_read_user_data(row, 'peak_flow_rate', nil)
      unless peak_flow_rate.nil? || Float(peak_flow_rate, exception: false)
        userdata_valid = false
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "User data: #{object_name}: water use equipment definition #{name}'s peak flow rate shall be a float, Got #{peak_flow_rate}.")
      end
    end
    return userdata_valid
  end
end
