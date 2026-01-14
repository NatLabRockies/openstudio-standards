# This class holds methods that apply NECB2011 rules.
# @ref [References::NECB2011]
class NECB2011 < Standard
  require 'zip'
  require 'open-uri'

  @template = new.class.name
  register_standard(@template)
  attr_reader :template
  attr_reader :tbd
  attr_reader :osut
  attr_reader :activity
  attr_reader :structure
  attr_accessor :standards_data
  attr_accessor :space_type_map
  attr_accessor :space_multiplier_map
  attr_accessor :fuel_type_set

  # This is a helper method to convert arguments to float.
  #   If variable undefined set to the default
  #   If already a numeric then return it
  #   If variable is a string then convert to a float, using the default if 'NECB_Default'
  #   If that all fails then return the default.
  def convert_arg_to_f(variable:, default:)
    return default if variable.nil?
    return variable if variable.kind_of?(Numeric)
    if variable.is_a? String
      return default if variable.to_s.downcase == 'necb_default'
      variable = variable.strip
      return variable.to_f
    end
    return default
  end

  # This method converts arguments to bool.
  #   If variable undefined set to the default
  #   If already a bool then return it
  #   If variable is a string then convert to a bool, using the default if 'NECB_Default'
  #   If that all fails then return the default.
  def convert_arg_to_bool(variable:, default:)
    return default if variable.nil?
    return variable if variable.is_a?(TrueClass) || variable.is_a?(FalseClass)
    if variable.is_a? String
      return default if variable.to_s.downcase == 'necb_default'
      return false if variable.to_s.downcase == 'false'
      return true if variable.to_s.downcase == 'true'
    end
    return default
  end

  # This method checks if a variable is a string.
  #   If variable undefined set to the default
  #   If variable is a string then return it, using the default if 'NECB_Default'
  #   If that all fails then return the default.
  def convert_arg_to_string(variable:, default:)
    return default if variable.nil?
    if variable.is_a? String
      return default if variable.to_s.downcase == 'necb_default'
      return variable
    end
    return default
  end

  def get_standards_table(table_name:)
    if @standards_data['tables'][table_name].nil?
      message = "Could not find table #{table_name} in database."
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.NECB', message)
    end
    @standards_data['tables'][table_name]
  end

  def get_standard_constant_value(constant_name:)
    puts 'do nothing'
  end

  # Combine the data from the JSON files into a single hash
  # Load JSON files differently depending on whether loading from
  # the OpenStudio CLI embedded filesystem or from typical gem installation
  def load_standards_database_new
    @standards_data = {}
    @standards_data['tables'] = {}

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('../common', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    else
      path = "#{File.dirname(__FILE__)}/../common/"
      raise 'Could not find common folder' unless Dir.exist?(path)

      files = Dir.glob("#{path}/*.json").select { |e| File.file? e }
      files.each do |file|
        data = JSON.parse(File.read(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    end

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('data/', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    else
      files = Dir.glob("#{File.dirname(__FILE__)}/data/*.json").select { |e| File.file? e }
      files.each do |file|
        data = JSON.parse(File.read(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    end
    # Write database to file.
    # File.open(File.join(File.dirname(__FILE__), '..', 'NECB2011.json'), 'w') {|f| f.write(JSON.pretty_generate(@standards_data))}

    return @standards_data
  end

  # Create a schedule from the openstudio standards dataset and
  # add it to the model.
  #
  # @param schedule_name [String} name of the schedule
  # @return [ScheduleRuleset] the resulting schedule ruleset
  # @todo make return an OptionalScheduleRuleset
  def model_add_schedule(model, schedule_name)
    super(model, schedule_name)
  end

  def get_standards_constant(name)
    object = @standards_data['constants'][name]

    if object.nil? || object['value'].nil?
      raise("could not find #{name} in standards constants database. ")
    end

    return object['value']
  end

  def get_standards_formula(name)
    object = @standards_data['formulas'][name]
    raise("could not find #{name} in standards formual database. ") if object.nil? || object['value'].nil?

    return object['value']
  end

  def initialize
    super()
    @template = self.class.name
    @standards_data = load_standards_database_new
    corrupt_standards_database
    @tbd = nil
    @activity = nil
    @structure = nil
    @osut = {gra0: 0, graX: 0, status: 0, logs: []} # "gra": "gross roof area"

    # puts "loaded these tables..."
    # puts @standards_data.keys.size
    # raise("tables not all loaded in parent #{}") if @standards_data.keys.size < 24
  end

  def get_all_spacetype_names
    return @standards_data['space_types'].map { |space_types| [space_types['building_type'], space_types['space_type']] }
  end

  # Enter in [latitude, longitude] for each loc and this method will return the distance.
  def distance(loc1, loc2)
    rad_per_deg = Math::PI / 180 # PI / 180
    rkm = 6371 # Earth radius in kilometers
    rm = rkm * 1000 # Radius in meters

    dlat_rad = (loc2[0] - loc1[0]) * rad_per_deg # Delta, converted to rad
    dlon_rad = (loc2[1] - loc1[1]) * rad_per_deg

    lat1_rad, lon1_rad = loc1.map { |i| i * rad_per_deg }
    lat2_rad, lon2_rad = loc2.map { |i| i * rad_per_deg }

    a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    rm * c # Delta in meters
  end

  def get_necb_hdd18(model:, necb_hdd: true)
    max_distance_tolerance = 500000
    min_distance = 100000000000000.0
    necb_closest = nil
    weather_file_path = model.weatherFile.get.path.get.to_s

    # Check if weather file exists at the specified path
    unless File.exist?(weather_file_path)
      # Try to find the file in the data/weather folder
      weather_file_name = File.basename(weather_file_path)
      data_weather_path = File.absolute_path(File.join(__FILE__, '..', '..', '..', '..', '..', '..', 'data', 'weather', weather_file_name))

      if File.exist?(data_weather_path)
        weather_file_path = data_weather_path
        # Update the model's weather file path to point to the found file
        OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      else
        raise "Weather file not found at #{weather_file_path} or #{data_weather_path}"
      end
    end

    epw_file = model.weatherFile.get.file.get
    stat_file_path = weather_file_path.gsub('.epw', '.stat')
    stat_file = OpenstudioStandards::Weather::StatFile.new(stat_file_path)
    # If necb_hdd is false use the information in the .stat file associated with the.epw file.
    unless necb_hdd
      return stat_file.hdd18
    end
    # this extracts the table from the json database.
    necb_2015_table_c1 = @standards_data['tables']['necb_2015_table_c1']['table']
    necb_2015_table_c1.each do |necb|
      next if necb['lat_long'].nil? # Need this until Tyson cleans up table.

      dist = distance([epw_file.latitude, epw_file.longitude], necb['lat_long'])
      if min_distance > dist
        min_distance = dist
        necb_closest = necb
      end
    end
    if ((min_distance / 1000.0) > max_distance_tolerance) && !stat_file.hdd18.nil?
      puts "Could not find close NECB HDD from Table C1 < #{max_distance_tolerance}km. Closest city is #{min_distance / 1000.0}km away. Using epw hdd18 instead."
      return stat_file.hdd18
    else
      dist_clause = "%.2f % #{(min_distance / 1000.0)}"
      puts "INFO:NECB HDD18 of #{necb_closest['degree_days_below_18_c'].to_f}  at nearest city #{necb_closest['city']},#{necb_closest['province']}, at a distance of " + dist_clause + 'km from epw location. Ref: nbc_2015_table_c1'
      return necb_closest['degree_days_below_18_c'].to_f
    end
  end

  # This method is a wrapper to create the 16 archetypes easily. # 55 args
  def model_create_prototype_model(template:,
                                   building_type:,
                                   construction_opt: '',
                                   epw_file:,
                                   custom_weather_folder: nil,
                                   debug: false,
                                   sizing_run_dir: Dir.pwd,
                                   hvac_system_primary: nil,
                                   hvac_system_dwelling_units: nil,
                                   hvac_system_washrooms: nil,
                                   hvac_system_corridor: nil,
                                   hvac_system_storage: nil,
                                   primary_heating_fuel: 'Electricity',
                                   swh_fuel: nil,
                                   dcv_type: 'NECB_Default',
                                   lights_type: 'NECB_Default',
                                   lights_scale: 1.0,
                                   daylighting_type: 'NECB_Default',
                                   ecm_system_name: 'NECB_Default',
                                   ecm_system_zones_map_option: 'NECB_Default',
                                   erv_package: 'NECB_Default',
                                   boiler_eff: nil,
                                   unitary_cop: nil,
                                   furnace_eff: nil,
                                   shw_eff: nil,
                                   ext_wall_cond: nil,
                                   ext_floor_cond: nil,
                                   ext_roof_cond: nil,
                                   ground_wall_cond: nil,
                                   ground_floor_cond: nil,
                                   ground_roof_cond: nil,
                                   door_construction_cond: nil,
                                   fixed_window_cond: nil,
                                   glass_door_cond: nil,
                                   overhead_door_cond: nil,
                                   skylight_cond: nil,
                                   glass_door_solar_trans: nil,
                                   fixed_wind_solar_trans: nil,
                                   skylight_solar_trans: nil,
                                   rotation_degrees: nil,
                                   fdwr_set: -1.0,
                                   srr_set: -1.0,
                                   srr_opt: '',
                                   nv_type: nil,
                                   nv_opening_fraction: nil,
                                   nv_temp_out_min: nil,
                                   nv_delta_temp_in_out: nil,
                                   scale_x: nil,
                                   scale_y: nil,
                                   scale_z: nil,
                                   pv_ground_type: nil,
                                   pv_ground_total_area_pv_panels_m2: nil,
                                   pv_ground_tilt_angle: nil,
                                   pv_ground_azimuth_angle: nil,
                                   pv_ground_module_description: nil,
                                   chiller_type: nil,
                                   occupancy_loads_scale: nil,
                                   electrical_loads_scale: nil,
                                   oa_scale: nil,
                                   infiltration_scale: nil,
                                   output_variables: nil,
                                   shw_scale: nil,
                                   output_meters: nil,
                                   airloop_economizer_type: nil,
                                   baseline_system_zones_map_option: nil,
                                   tbd_option: 'none',
                                   tbd_interpolate: true,
                                   necb_hdd: true,
                                   boiler_fuel: nil,
                                   boiler_cap_ratio: nil,
                                   airloop_fancoils_heating: nil,
                                   oerd_utility_pricing: nil)
    model = load_building_type_from_library(building_type: building_type)
    return model_apply_standard(model: model,
                                construction_opt: construction_opt,
                                tbd_option: tbd_option,
                                tbd_interpolate: tbd_interpolate,
                                epw_file: epw_file,
                                custom_weather_folder: custom_weather_folder,
                                sizing_run_dir: sizing_run_dir,
                                hvac_system_primary: nil,
                                hvac_system_dwelling_units: nil,
                                hvac_system_washrooms: nil,
                                hvac_system_corridor: nil,
                                hvac_system_storage: nil,
                                primary_heating_fuel: primary_heating_fuel,
                                swh_fuel: swh_fuel,
                                dcv_type: dcv_type, # Four options: (1) 'NECB_Default', (2) 'No_DCV', (3) 'Occupancy_based_DCV' , (4) 'CO2_based_DCV'
                                lights_type: lights_type, # Two options: (1) 'NECB_Default', (2) 'LED'
                                lights_scale: lights_scale,
                                daylighting_type: daylighting_type, # Two options: (1) nil/none/false/'NECB_Default' (Option #1 puts daylighting sensors in the spaces as per NECB requirements; so some spaces may not have sensors), (2) 'add_daylighting_controls' (Option #2 puts daylighting sensors in all spaces regardless of NECB requirements)
                                ecm_system_name: ecm_system_name,
                                ecm_system_zones_map_option: ecm_system_zones_map_option, # (1) 'NECB_Default' (2) 'one_sys_per_floor' (3) 'one_sys_per_bldg'
                                erv_package: erv_package,
                                boiler_eff: boiler_eff,
                                unitary_cop: unitary_cop,
                                furnace_eff: furnace_eff,
                                shw_eff: shw_eff,
                                ext_wall_cond: ext_wall_cond,
                                ext_floor_cond: ext_floor_cond,
                                ext_roof_cond: ext_roof_cond,
                                ground_wall_cond: ground_wall_cond,
                                ground_floor_cond: ground_floor_cond,
                                ground_roof_cond: ground_roof_cond,
                                door_construction_cond: door_construction_cond,
                                fixed_window_cond: fixed_window_cond,
                                glass_door_cond: glass_door_cond,
                                overhead_door_cond: overhead_door_cond,
                                skylight_cond: skylight_cond,
                                glass_door_solar_trans: glass_door_solar_trans,
                                fixed_wind_solar_trans: fixed_wind_solar_trans,
                                skylight_solar_trans: skylight_solar_trans,
                                rotation_degrees: rotation_degrees,
                                fdwr_set: fdwr_set,
                                srr_set: srr_set,
                                srr_opt: srr_opt,
                                nv_type: nv_type, # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_nv'
                                nv_opening_fraction: nv_opening_fraction, # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 0.1), (3) opening fraction of windows, which can be a float number between 0.0 and 1.0
                                nv_temp_out_min: nv_temp_out_min, # options: (1) nil/none/false(2) 'NECB_Default' (i.e. 13.0 based on inputs from Michel Tardif re a real school in QC), (3) minimum outdoor air temperature (in Celsius) below which natural ventilation is shut down
                                nv_delta_temp_in_out: nv_delta_temp_in_out, # options: (1) nil/none/false (2) 'NECB_Default' (i.e. 1.0 based on inputs from Michel Tardif re a real school in QC), (3) temperature difference (in Celsius) between the indoor and outdoor air temperatures below which ventilation is shut down
                                scale_x: scale_x,
                                scale_y: scale_y,
                                scale_z: scale_z,
                                pv_ground_type: pv_ground_type, # Two options: (1) nil/none/false/'NECB_Default', (2) 'add_pv_ground'
                                pv_ground_total_area_pv_panels_m2: pv_ground_total_area_pv_panels_m2, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. building footprint), (3) area value (e.g. 50)
                                pv_ground_tilt_angle: pv_ground_tilt_angle, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. latitude), (3) tilt angle value (e.g. 20)
                                pv_ground_azimuth_angle: pv_ground_azimuth_angle, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. south), (3) azimuth angle value (e.g. 90)
                                pv_ground_module_description: pv_ground_module_description, # Options: (1) nil/none/false, (2) 'NECB_Default' (i.e. Standard), (3) other options ('Standard', 'Premium', ThinFilm')
                                occupancy_loads_scale: occupancy_loads_scale,
                                electrical_loads_scale: electrical_loads_scale,
                                oa_scale: oa_scale,
                                infiltration_scale: infiltration_scale,
                                chiller_type: chiller_type, # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) e.g. 'VSD'
                                output_variables: output_variables,
                                shw_scale: shw_scale,  # Options: (1) 'NECB_Default'/nil/'none'/false (i.e. do nothing), (2) a float number larger than 0.0
                                output_meters: output_meters,
                                airloop_economizer_type: airloop_economizer_type, # (1) 'NECB_Default'/nil/' (2) 'DifferentialEnthalpy' (3) 'DifferentialTemperature'
                                baseline_system_zones_map_option: baseline_system_zones_map_option,  # Three options: (1) 'NECB_Default'/'none'/nil (i.e. 'one_sys_per_bldg'), (2) 'one_sys_per_dwelling_unit', (3) 'one_sys_per_bldg'
                                necb_hdd: necb_hdd,
                                boiler_fuel: boiler_fuel,
                                boiler_cap_ratio: boiler_cap_ratio,
                                airloop_fancoils_heating: airloop_fancoils_heating,
                                oerd_utility_pricing: oerd_utility_pricing
                                )
  end

  def load_building_type_from_library(building_type:)
    osm_model_path = File.absolute_path(File.join(__FILE__, '..', '..', '..', "necb/NECB2011/data/geometry/#{building_type}.osm"))
    model = false
    if File.file?(osm_model_path)
      model = BTAP::FileIO.load_osm(osm_model_path)
      model.getBuilding.setName(building_type)
    end
    return model
  end

  # Created this method so that additional methods can be addded for bulding the prototype model in later
  # code versions without modifying the build_protoype_model method or copying it wholesale for a few changes.
  def model_apply_standard(model:,
                           construction_opt: '',
                           tbd_option: 'none',
                           tbd_interpolate: true,
                           epw_file:,
                           custom_weather_folder: nil,
                           btap_weather: true,
                           sizing_run_dir: Dir.pwd,
                           necb_reference_hp: false,
                           necb_reference_hp_supp_fuel: 'DefaultFuel',
                           hvac_system_primary: 'NECB_Default',
                           hvac_system_dwelling_units: 'NECB_Default',
                           hvac_system_washrooms: 'NECB_Default',
                           hvac_system_corridor: 'NECB_Default',
                           hvac_system_storage: 'NECB_Default',
                           primary_heating_fuel: 'Electricity',
                           swh_fuel: nil,
                           dcv_type: 'NECB_Default',
                           lights_type: 'NECB_Default',
                           lights_scale: 'NECB_Default',
                           daylighting_type: 'NECB_Default',
                           ecm_system_name: 'NECB_Default',
                           ecm_system_zones_map_option: 'NECB_Default',
                           erv_package: 'NECB_Default',
                           boiler_eff: nil,
                           furnace_eff: nil,
                           unitary_cop: nil,
                           shw_eff: nil,
                           ext_wall_cond: nil,
                           ext_floor_cond: nil,
                           ext_roof_cond: nil,
                           ground_wall_cond: nil,
                           ground_floor_cond: nil,
                           ground_roof_cond: nil,
                           door_construction_cond: nil,
                           fixed_window_cond: nil,
                           glass_door_cond: nil,
                           overhead_door_cond: nil,
                           skylight_cond: nil,
                           glass_door_solar_trans: nil,
                           fixed_wind_solar_trans: nil,
                           skylight_solar_trans: nil,
                           fdwr_set: nil,
                           srr_set: nil,
                           srr_opt: '',
                           rotation_degrees: nil,
                           scale_x: nil,
                           scale_y: nil,
                           scale_z: nil,
                           nv_type: nil,
                           nv_opening_fraction: nil,
                           nv_temp_out_min: nil,
                           nv_delta_temp_in_out: nil,
                           pv_ground_type: nil,
                           pv_ground_total_area_pv_panels_m2: nil,
                           pv_ground_tilt_angle: nil,
                           pv_ground_azimuth_angle: nil,
                           pv_ground_module_description: nil,
                           chiller_type: nil,
                           occupancy_loads_scale: nil,
                           electrical_loads_scale: nil,
                           oa_scale: nil,
                           infiltration_scale: nil,
                           output_variables: nil,
                           shw_scale: nil,
                           output_meters: nil,
                           airloop_economizer_type: nil,
                           baseline_system_zones_map_option: nil,
                           necb_hdd: true,
                           boiler_fuel: nil,
                           boiler_cap_ratio: nil,
                           airloop_fancoils_heating: nil,
                           oerd_utility_pricing: nil)

    apply_weather_data(model: model,
                       epw_file: epw_file,
                       custom_weather_folder: custom_weather_folder,
                       btap_weather: btap_weather)
    primary_heating_fuel = validate_primary_heating_fuel(primary_heating_fuel: primary_heating_fuel, model: model)
    self.fuel_type_set = SystemFuels.new()
    self.fuel_type_set.set_defaults(standards_data: @standards_data, primary_heating_fuel: primary_heating_fuel)
    clean_and_scale_model(model: model, rotation_degrees: rotation_degrees, scale_x: scale_x, scale_y: scale_y, scale_z: scale_z)

    ext_floor_cond           = convert_arg_to_f(variable: ext_floor_cond, default: nil)
    ext_roof_cond            = convert_arg_to_f(variable: ext_roof_cond, default: nil)
    ext_wall_cond            = convert_arg_to_f(variable: ext_wall_cond, default: nil)
    ground_floor_cond        = convert_arg_to_f(variable: ground_floor_cond, default: nil)
    ground_roof_cond         = convert_arg_to_f(variable: ground_roof_cond, default: nil)
    ground_wall_cond         = convert_arg_to_f(variable: ground_wall_cond, default: nil)
    door_construction_cond   = convert_arg_to_f(variable: door_construction_cond, default: nil)
    fixed_window_cond        = convert_arg_to_f(variable: fixed_window_cond, default: nil)
    fixed_wind_solar_trans   = convert_arg_to_f(variable: fixed_wind_solar_trans, default: nil)
    skylight_solar_trans     = convert_arg_to_f(variable: skylight_solar_trans, default: nil)
    glass_door_solar_trans   = convert_arg_to_f(variable: glass_door_solar_trans, default: nil)
    fdwr_set                 = convert_arg_to_f(variable: fdwr_set, default: -1)
    srr_set                  = convert_arg_to_f(variable: srr_set, default: -1)
    srr_opt                  = convert_arg_to_string(variable: srr_opt, default: '')
    construction_opt         = convert_arg_to_string(variable: construction_opt, default: '')
    tbd_option               = convert_arg_to_string(variable: tbd_option, default: 'none')
    tbd_interpolate          = convert_arg_to_bool(variable: tbd_interpolate, default: true)
    necb_hdd                 = convert_arg_to_bool(variable: necb_hdd, default: true)
    boiler_fuel              = convert_arg_to_string(variable: boiler_fuel, default: nil)
    boiler_cap_ratio         = convert_arg_to_string(variable: boiler_cap_ratio, default: nil)
    swh_fuel                 = convert_arg_to_string(variable: swh_fuel, default: nil)
    airloop_fancoils_heating = convert_arg_to_bool(variable: airloop_fancoils_heating, default: false)

    massive = construction_opt == 'structure'

    # Check if custom systems are assigned to dwelling units, washrooms, corridors, and storage rooms.  If they are, set
    # them to be the same as the primary system type.  If no primary system type is defined then set them to be nil.
    hvac_system_dwelling_units, hvac_system_corridor, hvac_system_storage, hvac_system_washrooms = reset_hvac_system_if_required(hvac_system_primary: hvac_system_primary,
                                                                                                                                 hvac_system_dwelling_units: hvac_system_dwelling_units,
                                                                                                                                 hvac_system_corridor: hvac_system_corridor,
                                                                                                                                 hvac_system_storage: hvac_system_storage,
                                                                                                                                 hvac_system_washrooms: hvac_system_washrooms)
    oerd_utility_pricing = convert_arg_to_bool(variable: oerd_utility_pricing, default: false)

    boiler_cap_ratios = set_boiler_cap_ratios(boiler_cap_ratio: boiler_cap_ratio, boiler_fuel: boiler_fuel) unless boiler_cap_ratio.nil? && boiler_fuel.nil?
    self.fuel_type_set.set_boiler_fuel(standards_data: @standards_data, boiler_fuel: boiler_fuel, boiler_cap_ratios: boiler_cap_ratios) unless boiler_fuel.nil?
    self.fuel_type_set.set_swh_fuel(swh_fuel: swh_fuel) unless swh_fuel.nil? || swh_fuel.to_s.downcase == 'defaultfuel'
    self.fuel_type_set.set_airloop_fancoils_heating() if airloop_fancoils_heating

    # Ensure the volume calculation in all spaces is done automatically
    model.getSpaces.sort.each do |space|
      space.autocalculateVolume
    end

    output_meters = check_output_meters(output_meters: output_meters) if oerd_utility_pricing

    assign_building_activity(model: model)
    assign_building_structure(model: model, activity: @activity, massive: massive)
    apply_loads(model: model,
                lights_type: lights_type,
                lights_scale: lights_scale,
                occupancy_loads_scale: occupancy_loads_scale,
                electrical_loads_scale: electrical_loads_scale,
                oa_scale: oa_scale)
    apply_envelope(model: model,
                   construction_opt: construction_opt,
                   bldg_category: @activity.category,
                   bldg_structure: @structure.structure,
                   ext_wall_cond: ext_wall_cond,
                   ext_floor_cond: ext_floor_cond,
                   ext_roof_cond: ext_roof_cond,
                   ground_wall_cond: ground_wall_cond,
                   ground_floor_cond: ground_floor_cond,
                   ground_roof_cond: ground_roof_cond,
                   door_construction_cond: door_construction_cond,
                   fixed_window_cond: fixed_window_cond,
                   glass_door_cond: glass_door_cond,
                   overhead_door_cond: overhead_door_cond,
                   skylight_cond: skylight_cond,
                   glass_door_solar_trans: glass_door_solar_trans,
                   fixed_wind_solar_trans: fixed_wind_solar_trans,
                   skylight_solar_trans: skylight_solar_trans,
                   infiltration_scale: infiltration_scale,
                   necb_hdd: necb_hdd)
    apply_fdwr_srr_daylighting(model: model,
                               fdwr_set: fdwr_set,
                               srr_set: srr_set,
                               srr_opt: srr_opt,
                               necb_hdd: necb_hdd)
    apply_thermal_bridging(model: model,
                           necb_hdd: necb_hdd,
                           structure: @structure,
                           option: tbd_option,
                           interpolate: tbd_interpolate,
                           wallU: ext_wall_cond,
                           floorU: ext_floor_cond,
                           roofU: ext_roof_cond)
    apply_auto_zoning(model: model,
                      sizing_run_dir: sizing_run_dir,
                      lights_type: lights_type,
                      lights_scale: lights_scale)
    apply_kiva_foundation(model, massive)
    apply_systems_and_efficiencies(model: model,
                                   sizing_run_dir: sizing_run_dir,
                                   hvac_system_primary: hvac_system_primary,
                                   hvac_system_dwelling_units: hvac_system_dwelling_units,
                                   hvac_system_washrooms: hvac_system_washrooms,
                                   hvac_system_corridor: hvac_system_corridor,
                                   hvac_system_storage: hvac_system_storage,
                                   primary_heating_fuel: primary_heating_fuel,
                                   dcv_type: dcv_type,
                                   ecm_system_name: ecm_system_name,
                                   ecm_system_zones_map_option: ecm_system_zones_map_option,
                                   erv_package: erv_package,
                                   boiler_eff: boiler_eff,
                                   unitary_cop: unitary_cop,
                                   furnace_eff: furnace_eff,
                                   shw_eff: shw_eff,
                                   daylighting_type: daylighting_type,
                                   nv_type: nv_type,
                                   nv_opening_fraction: nv_opening_fraction,
                                   nv_temp_out_min: nv_temp_out_min,
                                   nv_delta_temp_in_out: nv_delta_temp_in_out,
                                   pv_ground_type: pv_ground_type,
                                   pv_ground_total_area_pv_panels_m2: pv_ground_total_area_pv_panels_m2,
                                   pv_ground_tilt_angle: pv_ground_tilt_angle,
                                   pv_ground_azimuth_angle: pv_ground_azimuth_angle,
                                   pv_ground_module_description: pv_ground_module_description,
                                   chiller_type: chiller_type,
                                   shw_scale: shw_scale,
                                   airloop_economizer_type: airloop_economizer_type,
                                   baseline_system_zones_map_option: baseline_system_zones_map_option)
    self.set_output_variables(model: model, output_variables: output_variables)
    self.set_output_meters(model: model, output_meters: output_meters)

    return model
  end

  # This method cleans the model of any existing HVAC systems and applies any desired ratation or scaling to the model.
  def clean_and_scale_model(model:, rotation_degrees: nil, scale_x: nil, scale_y: nil, scale_z: nil)
    # clean model..
    BTAP::Resources::Envelope::remove_all_envelope_information(model)
    model = OpenstudioStandards::HVAC.remove_all_hvac(model)
    model.getThermalZones.sort.each { |zone| zone.setUseIdealAirLoads(true) }
    model.getZoneHVACPackagedTerminalAirConditioners.each(&:remove)
    model.getCoilCoolingDXSingleSpeeds.each(&:remove)
    model.getZoneHVACBaseboardConvectiveWaters.each(&:remove)
    model.getAirLoopHVACZoneMixers.each(&:remove)
    model.getAirLoopHVACZoneSplitters.each(&:remove)
    model.getAirTerminalSingleDuctConstantVolumeNoReheats.each(&:remove)
    model.getWaterUseEquipmentDefinitions.each(&:remove)
    model.getWaterUseEquipments.each(&:remove)
    model.getWaterUseConnectionss.each(&:remove)
    model.getPumpConstantSpeeds.each(&:remove)
    model.getPumpVariableSpeeds.each(&:remove)
    model.getBoilerHotWaters.each(&:remove)
    model.getBoilerSteams.each(&:remove)
    model.getPlantLoops.each(&:remove)
    model.getSchedules.each(&:remove)
    model.getThermalZones.sort.each { |zone| zone.thermostat(&:remove) }
    model.getSpaces.sort.each { |space| space.designSpecificationOutdoorAir(&:remove) }
    model.getThermostatSetpointDualSetpoints.each(&:remove)

    scale_x = 1.0
    scale_y = 1.0
    scale_z = 1.0
    # Rotate to model if requested
    rotation_degrees = convert_arg_to_f(variable: rotation_degrees, default: 0.0)
    BTAP::Geometry.rotate_building(model: model, degrees: rotation_degrees) unless rotation_degrees == 0.0

    # Scale model if requested
    scale_x = convert_arg_to_f(variable: scale_x, default: 1.0)
    scale_y = convert_arg_to_f(variable: scale_y, default: 1.0)
    scale_z = convert_arg_to_f(variable: scale_z, default: 1.0)
    return unless scale_x != 1.0 || scale_y != 1.0 || scale_z != 1.0

    BTAP::Geometry.scale_model(model, scale_x, scale_y, scale_z)
  end

  def apply_systems_and_efficiencies(model:,
                                     sizing_run_dir:,
                                     hvac_system_primary: 'NECB_Default',
                                     hvac_system_dwelling_units: 'NECB_Default',
                                     hvac_system_washrooms: 'NECB_Default',
                                     hvac_system_corridor: 'NECB_Default',
                                     hvac_system_storage: 'NECB_Default',
                                     primary_heating_fuel:,
                                     dcv_type: 'NECB_Default',
                                     ecm_system_name: 'NECB_Default',
                                     ecm_system_zones_map_option: 'NECB_Default',
                                     erv_package: 'NECB_Default',
                                     boiler_eff: nil,
                                     furnace_eff: nil,
                                     unitary_cop: nil,
                                     shw_eff: nil,
                                     daylighting_type: 'NECB_Default',
                                     nv_type: nil,
                                     nv_opening_fraction: nil,
                                     nv_temp_out_min: nil,
                                     nv_delta_temp_in_out: nil,
                                     pv_ground_type:,
                                     pv_ground_total_area_pv_panels_m2:,
                                     pv_ground_tilt_angle:,
                                     pv_ground_azimuth_angle:,
                                     pv_ground_module_description:,
                                     chiller_type: 'NECB_Default',
                                     shw_scale:,
                                     airloop_economizer_type: nil,
                                     baseline_system_zones_map_option:)

    # Create ECM object.
    ecm = ECMS.new

    # -------- Systems Layout-----------

    # Create Default Systems.
    apply_systems(model: model,
                  hvac_system_primary: hvac_system_primary,
                  hvac_system_dwelling_units: hvac_system_dwelling_units,
                  hvac_system_washrooms: hvac_system_washrooms,
                  hvac_system_corridor: hvac_system_corridor,
                  hvac_system_storage: hvac_system_storage,
                  sizing_run_dir: sizing_run_dir,
                  shw_scale: shw_scale,
                  baseline_system_zones_map_option: baseline_system_zones_map_option)

    # Apply new ECM system. Overwrite standard as required.
    ecm.apply_system_ecm(model: model,
                         ecm_system_name: ecm_system_name,
                         template_standard: self,
                         ecm_system_zones_map_option: ecm_system_zones_map_option)

    # -------- Performace, Efficiencies, Controls and Sensors ------------
    #
    # Set code standard equipment characteristics.
    sql_db_vars_map = apply_standard_efficiencies(model: model,
                                                  sizing_run_dir: sizing_run_dir,
                                                  necb_reference_hp: self.fuel_type_set.necb_reference_hp)
    # Apply System
    ecm.apply_system_efficiencies_ecm(model: model, ecm_system_name: ecm_system_name, template_standard: self)
    # Apply ECM ERV charecteristics as required. Part 2 of above ECM.
    ecm.apply_erv_ecm_efficiency(model: model, erv_package: erv_package)
    # Apply DCV as required
    model_enable_demand_controlled_ventilation(model, dcv_type)
    # Apply Boiler Efficiency
    ecm.modify_boiler_efficiency(model: model, boiler_eff: boiler_eff)
    # Apply Furnace Efficiency
    ecm.modify_furnace_efficiency(model: model, furnace_eff: furnace_eff)
    # Apply Unitary curves
    ecm.modify_unitary_cop(model: model, unitary_cop: unitary_cop, sizing_done: false, sql_db_vars_map: sql_db_vars_map)
    # Apply SHW Efficiency
    ecm.modify_shw_efficiency(model: model, shw_eff: shw_eff)
    # Apply daylight controls.
    model_add_daylighting_controls(model: model, daylighting_type: daylighting_type)
    # Apply Chiller efficiency
    ecm.modify_chiller_efficiency(model: model, chiller_type: chiller_type)
    # Apply airloop economizer
    ecm.add_airloop_economizer(model: model, airloop_economizer_type: airloop_economizer_type)
    # Perform a second sizing run if needed
    if (!unitary_cop.nil? && unitary_cop != 'NECB_Default') || !model.getPlantLoops.empty?
      # Do a sizing run
      try_sizing_run(model: model, sizing_run_dir: sizing_run_dir, sizing_run_subdir: 'SR2')
      #end
    end
    # apply unitary cop
    ecm.modify_unitary_cop(model: model, unitary_cop: unitary_cop, sizing_done: true, sql_db_vars_map: sql_db_vars_map)
    # set capacities of district heating and cooling equipment for ground-source heat pump ecm
    district_heat = false
    if model.version < OpenStudio::VersionString.new('3.7.0')
      district_heat = !model.getDistrictHeatings.empty?
    else
      district_heat = !model.getDistrictHeatingWaters.empty?
    end
    ecm.set_ghx_loop_district_cap(model) if (district_heat && !model.getDistrictCoolings.empty?)

    # -------Pump sizing required by some vintages----------------
    # Apply Pump power as required.
    apply_loop_pump_power(model: model, sizing_run_dir: sizing_run_dir)

    # -------Natural ventilation----------------
    # Apply natural ventilation using simplified method.
    if nv_type == 'add_nv'
      ecm.apply_nv(model: model,
                   nv_type: nv_type,
                   nv_opening_fraction: nv_opening_fraction,
                   nv_temp_out_min: nv_temp_out_min,
                   nv_delta_temp_in_out: nv_delta_temp_in_out)
    end

    # -------Ground-mounted PV panels----------------
    # Apply ground-mounted PV panels as required.
    if pv_ground_type == 'add_pv_ground'
      ecm.apply_pv_ground(model: model,
                          pv_ground_type: pv_ground_type,
                          pv_ground_total_area_pv_panels_m2: pv_ground_total_area_pv_panels_m2,
                          pv_ground_tilt_angle: pv_ground_tilt_angle,
                          pv_ground_azimuth_angle: pv_ground_azimuth_angle,
                          pv_ground_module_description: pv_ground_module_description)
    end

    # Rename air loop and plant loop nodes to accommodate coming OpenStudio version
    OpenstudioStandards::HVAC.rename_air_loop_nodes(model)
    OpenstudioStandards::HVAC.rename_plant_loop_nodes(model)
  end

  def apply_loads(model:,
                  lights_type: 'NECB_Default',
                  lights_scale: 1.0,
                  validate: true,
                  occupancy_loads_scale: nil,
                  electrical_loads_scale: nil,
                  oa_scale: nil)
    # Create ECM object.
    ecm = ECMS.new
    lights_scale = convert_arg_to_f(variable: lights_scale, default: 1.0)
    if validate
      raise('validation of model failed.') unless validate_initial_model(model)
      raise('validation of spacetypes failed.') unless validate_and_upate_space_types(model)
    end
    # this sets/stores the template version loads that the model uses.
    model.getBuilding.setStandardsTemplate(self.class.name)
    set_occ_sensor_spacetypes(model, @space_type_map)
    model_add_loads(model, lights_type, lights_scale)
    ecm.scale_occupancy_loads(model: model, scale: occupancy_loads_scale)
    ecm.scale_electrical_loads(model: model, scale: electrical_loads_scale)
    ecm.scale_oa_loads(model: model, scale: oa_scale)
  end

  def apply_weather_data(model:, epw_file:, custom_weather_folder: nil, btap_weather: true)
    # Create full path to weather file
    weather_files = File.absolute_path(File.join(__FILE__, '..', '..', '..', '..', '..' , '..', "data/weather"))
    weather_file = File.join(weather_files, epw_file)
    # Check if the weather file exists.  If it does continue as normal, otherwise try to dowload it from the
    # canmet-energy/btap_weather repository
    unless File.exist?(weather_file)
      # Check if btap_batch transferred the weather file
      weather_transfer = check_datapoint_weather_folder(epw_file: epw_file, weather_folder: weather_files, custom_weather_folder: custom_weather_folder)
      # If btap_batch didn't transfer the weather file, download it.
      get_weather_file_from_repo(epw_file: epw_file, btap_weather: btap_weather) unless weather_transfer
    end

    # Fix EMS references. Temporary workaround for OS issue #2598
    model_temp_fix_ems_references(model)
    model.getThermostatSetpointDualSetpoints(&:remove)
    model.getYearDescription.setDayofWeekforStartDay('Sunday')
    weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
  end

  def apply_envelope(model:,
                     construction_opt: '',
                     bldg_category: '',
                     bldg_structure: '',
                     ext_wall_cond: nil,
                     ext_floor_cond: nil,
                     ext_roof_cond: nil,
                     ground_wall_cond: nil,
                     ground_floor_cond: nil,
                     ground_roof_cond: nil,
                     door_construction_cond: nil,
                     fixed_window_cond: nil,
                     glass_door_cond: nil,
                     overhead_door_cond: nil,
                     skylight_cond: nil,
                     glass_door_solar_trans: nil,
                     fixed_wind_solar_trans: nil,
                     skylight_solar_trans: nil,
                     infiltration_scale: nil,
                     necb_hdd: true)
    raise('validation of model failed.') unless validate_initial_model(model)

    model_apply_infiltration_standard(model)
    ecm = ECMS.new
    ecm.scale_infiltration_loads(model: model, scale: infiltration_scale)
    model.getInsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')
    model.getOutsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')

    construction_opt = '' unless construction_opt.respond_to?(:to_sym)
    bldg_structure   = '' unless bldg_structure.respond_to?(:to_sym)
    construction_opt = construction_opt.to_s.downcase
    bldg_structure   = bldg_structure.to_s.downcase.to_sym
    bldg_structures  = @structure.data[:structure].keys

    if construction_opt == 'structure' && bldg_structures.include?(bldg_structure)
      argh            = {}
      argh[:eWallU  ] = ext_wall_cond          if ext_wall_cond
      argh[:eFloorU ] = ext_floor_cond         if ext_floor_cond
      argh[:eRoofU  ] = ext_roof_cond          if ext_roof_cond
      argh[:gWallU  ] = ground_wall_cond       if ground_wall_cond
      argh[:gFloorU ] = ground_floor_cond      if ground_floor_cond
      argh[:gRoofU  ] = ground_roof_cond       if ground_roof_cond
      argh[:doorU   ] = door_construction_cond if door_construction_cond
      argh[:fenU    ] = fixed_window_cond      if fixed_window_cond
      argh[:skyU    ] = skylight_solar_trans   if skylight_solar_trans
      argh[:doorSHGC] = glass_door_solar_trans if glass_door_solar_trans
      argh[:fenSHGC ] = fixed_wind_solar_trans if fixed_wind_solar_trans
      argh[:skySHGC ] = skylight_solar_trans   if skylight_solar_trans

      assign_contruction_to_adiabatic_surfaces(model)
      ok = add_construction_sets(model, necb_hdd, argh)

      raise('NECB2011: Failed to assign default construction sets') unless ok
    else
      model_add_constructions(model)
      apply_standard_construction_properties(model: model,
                                             ext_wall_cond: ext_wall_cond,
                                             ext_floor_cond: ext_floor_cond,
                                             ext_roof_cond: ext_roof_cond,
                                             ground_wall_cond: ground_wall_cond,
                                             ground_floor_cond: ground_floor_cond,
                                             ground_roof_cond: ground_roof_cond,
                                             door_construction_cond: door_construction_cond,
                                             fixed_window_cond: fixed_window_cond,
                                             glass_door_cond: glass_door_cond,
                                             overhead_door_cond: overhead_door_cond,
                                             skylight_cond: skylight_cond,
                                             glass_door_solar_trans: glass_door_solar_trans,
                                             fixed_wind_solar_trans: fixed_wind_solar_trans,
                                             skylight_solar_trans: skylight_solar_trans,
                                             necb_hdd: necb_hdd)
    end

    model_create_thermal_zones(model, @space_multiplier_map)
  end

  # Apply Kiva foundation model to floors/walls with ground boundary condition.
  # created by: Kamel Haddad (kamel.haddad@nrcan-rncan.gc.ca)
  # 'massive' edit: denis@rd2.ca
  #
  # @param massive [Boolean] whether opaque materials are standard (not massless)
  def apply_kiva_foundation(model, massive = false)
    # define a Kiva model for the whole bldg that's used for the first floor in contact with ground in each zone
    bldg_kiva_model = OpenStudio::Model::FoundationKiva.new(model)
    bldg_kiva_model.setName("Bldg Kiva Foundation")
    bldg_kiva_model.setWallHeightAboveGrade(0.0)
    bldg_kiva_model.setWallDepthBelowSlab(0.0)
    model.getThermalZones.sort.each do |zone|
      zone_kiva_models = [bldg_kiva_model]
      zone_grd_flr_counter = 0
      zone.spaces.sort.each do |space|
        # store space floors and walls in contact with ground and exterior walls
        space_ground_floors = []
        space_ground_walls = []
        space_ext_walls = []
        space_ground_floors += space.surfaces.select {|surf| surf.surfaceType.downcase == 'floor' && surf.isGroundSurface }
        space_ground_walls += space.surfaces.select {|surf| surf.surfaceType.downcase == 'wall' && surf.isGroundSurface }
        space_ext_walls += space.surfaces.select {|surf| surf.surfaceType.downcase == 'wall' && surf.outsideBoundaryCondition.downcase == 'outdoors'}
        # loop through space floors in contact with ground and assing a Kiva model for each
        space_ground_floors.each do |gfloor|
          zone_grd_flr_counter += 1
          if zone_grd_flr_counter > 1
            # a new Kiva model is needed for each additional floor in contact with the ground in the zone
            kiva_model = OpenStudio::Model::FoundationKiva.new(model)
            kiva_model.setName("#{gfloor.name.to_s} Kiva Foundation")
            kiva_model.setWallHeightAboveGrade(0.0)
            kiva_model.setWallDepthBelowSlab(0.0)
            zone_kiva_models << kiva_model
          end
          # Kiva model only works with standard materials. Replace constructions
          # massless materials with standard ones.
          # Kiva model only works with standard materials. Replace constructions
          # massless materials with standard ones. Skip check if 'massive'.
          if massive
            c = gfloor.construction.get.to_LayeredConstruction.get
            gfloor.setOutsideBoundaryCondition('Foundation')
            gfloor.setAdjacentFoundation(zone_kiva_models.last)
            gfloor.setConstruction(c)
          else
            replace_massless_material_with_std_material(model,gfloor)
            gfloor.setOutsideBoundaryCondition('Foundation')
            gfloor.setAdjacentFoundation(zone_kiva_models.last)
          end

          # Set the exposed perimeter for space floors in contact with the ground.
          floor_exp_per = 0.0
          if !space_ground_walls.empty?
            floor_exp_per += get_surface_exp_per(gfloor,space_ground_walls)
          elsif !space_ext_walls.empty?
            floor_exp_per += get_surface_exp_per(gfloor,space_ext_walls)
          end
          gfloor.createSurfacePropertyExposedFoundationPerimeter('TotalExposedPerimeter',floor_exp_per)
          # specify a foundation boundary condition for space walls in contact with the ground and in
          # contact with the space floor in contact with ground 'gfloor'
          space_ground_walls.each do |gwall|
            if surfaces_are_in_contact?(gfloor,gwall)
              if massive
                c = gwall.construction.get.to_LayeredConstruction.get
                gwall.setOutsideBoundaryCondition('Foundation')
                gwall.setAdjacentFoundation(zone_kiva_models.last)
                gwall.setConstruction(c)
              else
                replace_massless_material_with_std_material(model,gwall)
                gwall.setOutsideBoundaryCondition('Foundation')
                gwall.setAdjacentFoundation(zone_kiva_models.last)
              end
            end
          end
        end
      end
    end
    kiva_settings = model.getFoundationKivaSettings if !model.getFoundationKivas.empty?
  end

  # check if two surfaces are in contact. For every two consecutive vertices on surface 1,
  # loop through two consecutive vertices of surface two. Then check whether the vertices
  # of surfaces 2 are on the same line as the vertices from surface 1. If the two vectors
  # defined by the two vertices on surface 1 and those on surface 2 overlap, then the two
  # surfaces are in contact. If a side from surface 2 is in contact with a side from surface 1,
  # the length of the side from surface 2 is limited to the length of the side from surface 1.
  # created by: Kamel Haddad (kamel.haddad@nrcan-rncan.gc.ca)
  def surfaces_are_in_contact?(surf1,surf2)
    surfaces_in_contact = false
    vert1 = surf1.vertices[0]
    for index1 in 1..surf1.vertices.size
      if index1 < surf1.vertices.size
        vert2 = surf1.vertices[index1]
      else
        vert2 = surf1.vertices[0]
      end
      seg12_length = ((vert2.x-vert1.x)**2+(vert2.y-vert1.y)**2+(vert2.z-vert1.z)**2)**0.5
      surf2_seg_length = 0.0
      vert3 = surf2.vertices[0]
      for index2 in 1..surf2.vertices.size
        if index2 < surf2.vertices.size
          vert4 = surf2.vertices[index2]
        else
          vert4 = surf2.vertices[0]
        end
        vert1_2_3_same_line_and_dir = three_vertices_same_line_and_dir?(vert1,vert2,vert3)
        if vert1_2_3_same_line_and_dir
          vert1_2_4_same_line_and_dir = three_vertices_same_line_and_dir?(vert1,vert2,vert4)
          if vert1_2_4_same_line_and_dir
            surfaces_in_contact = true
            seg34_length = ((vert4.x-vert3.x)**2+(vert4.y-vert3.y)**2+(vert4.z-vert3.z)**2)**0.5
            surf2_seg_length += seg34_length
            raise("Surface #{surf2.name.to_s} has sides in contact with surface #{surf1.name.to_s} but with a length greater than the max.") if surf2_seg_length > seg12_length
          end
        end
        vert3 = vert4
      end
      vert1 = vert2
    end

    return surfaces_in_contact
  end

  # Loop through the layers of the construction of the surface and replace any massless material with
  # a standard one. The material used instead is from the EnergyPlus dataset file 'ASHRAE_2005_HOF_Materials.idf'
  # with the name: 'Insulation: Expanded polystyrene - extruded (smooth skin surface) (HCFC-142b exp.)'.
  # The thickness of the new material is based on the thermal resistance of the massless material it replaces.
  # created by: Kamel Haddad (kamel.haddad@nrcan-rncan.gc.ca)
  def replace_massless_material_with_std_material(model,surf)
    std_const_name = "#{surf.construction.get.name.to_s}_std"
    std_const = model.getLayeredConstructions.select {|const| const.name.to_s == std_const_name}
    new_const = nil
    if !std_const.empty?
      new_const = std_const[0]
    else
      new_layers = {}
      has_massless_mat = false
      layer_index = 0
      surf.construction.get.to_LayeredConstruction.get.layers.each do |layer|
        if layer.to_MasslessOpaqueMaterial.is_initialized then
          has_massless_mat = true
          new_mat = OpenStudio::Model::StandardOpaqueMaterial.new(model)
          new_mat.setName("Expanded Polystyrene")
          new_mat.setThermalConductivity(0.029)
          new_mat.setDensity(29.0)
          new_mat.setSpecificHeat(1210.0)
          new_mat.setRoughness('MediumSmooth')
          new_mat.setThickness(layer.to_MasslessOpaqueMaterial.get.thermalResistance.to_f * new_mat.thermalConductivity.to_f)
        else
          new_mat = layer
        end
        new_layers[layer_index] = new_mat
        layer_index += 1
      end
      if has_massless_mat
        new_const = OpenStudio::Model::Construction.new(model)
        new_layers.keys.sort.each {|layer_index| new_const.to_LayeredConstruction.get.insertLayer(layer_index,new_layers[layer_index])}
        new_const.setName("#{surf.construction.get.name.to_s}_std")
      end
    end
    surf.setConstruction(new_const) if !new_const.nil?

  end

  # Find the exposed perimeter of a floor surface. For each side of the floor loop through
  # the walls and find the walls that share sides with the floor. Then sum the lengths of
  # the sides of the walls that come in contact with sides of the floor.
  # created by: Kamel Haddad (kamel.haddad@nrcan-rncan.gc.ca)
  def get_surface_exp_per(floor,walls)
    floor_exp_per = 0.0
    vert1 = floor.vertices[0]
    # loop through the indices of the floor surface
    for index in 1..floor.vertices.size
      if index < floor.vertices.size
        vert2 = floor.vertices[index]
      else
        vert2 = floor.vertices[0]
      end
      side_length = ((vert2.x-vert1.x)**2+(vert2.y-vert1.y)**2+(vert2.z-vert1.z)**2)**0.5
      walls_exp_per = 0.0
      walls.each do |wall|
        vert3 = wall.vertices[0]
        # loop through the indices of the wall surface
        for index2 in 1..wall.vertices.size-1
          if index2 < wall.vertices.size
            vert4 = wall.vertices[index2]
          else
            vert4 = wall.vertices[0]
          end
          vert1_2_3_on_same_line = three_vertices_same_line_and_dir?(vert1,vert2,vert3)
          if vert1_2_3_on_same_line
            vert1_2_4_on_same_line = three_vertices_same_line_and_dir?(vert1,vert2,vert4)
            if vert1_2_4_on_same_line
              wall_width = ((vert4.x-vert3.x)**2+(vert4.y-vert3.y)**2+(vert4.z-vert3.z)**2)**0.5
              walls_exp_per += wall_width
            end
          end
          vert3 = vert4
        end
      end
      # increment the exposed perimeter of the floor. Limit the length of the walls in contact with the
      # side of the floor to the length of the side of the floor.
      floor_exp_per += [walls_exp_per,side_length].min
      vert1 = vert2
    end

    return floor_exp_per
  end

  # check that three vertices are on the same line. Also check that the vectors
  # from vert1 and vert2 and from vert1 and vert3 are in the same direction.
  # created by: Kamel Haddad (kamel.haddad@nrcan-rncan.gc.ca)
  def three_vertices_same_line_and_dir?(vert1,vert2,vert3)
    tol = 1.0e-5
    vec12x,vec12y,vec12z = -vert1.x+vert2.x,-vert1.y+vert2.y,-vert1.z+vert2.z # x,y,z of vector 12
    vec12x = 0.0 if vec12x.abs < tol
    vec12y = 0.0 if vec12y.abs < tol
    vec12z = 0.0 if vec12z.abs < tol
    vec13x,vec13y,vec13z = -vert1.x+vert3.x,-vert1.y+vert3.y,-vert1.z+vert3.z # x,y,z of vector 13
    vec13x = 0.0 if vec13x.abs < tol
    vec13y = 0.0 if vec13y.abs < tol
    vec13z = 0.0 if vec13z.abs < tol
    # x,y,z of the cross product of the vectors 12 and 13
    cross_12_13_x = vec12y*vec13z-vec12z*vec13y
    cross_12_13_y = vec12z*vec13x-vec12x*vec13z
    cross_12_13_z = vec12x*vec13y-vec12y*vec13x
    # vectors are in parallel when x,y,z of cross product are 0.0
    vertices_on_same_line = false
    vertices_on_same_line = true if (cross_12_13_x == 0.0) && (cross_12_13_y == 0.0) && (cross_12_13_z == 0.0)
    vectors_same_direction = false
    if vertices_on_same_line
      vec12_13_x_factor = vec13x*vec12x
      vec12_13_y_factor = vec13y*vec12y
      vec12_13_z_factor = vec13z*vec12z
      vectors_same_direction = true if (vec12_13_x_factor >= 0.0) && (vec12_13_y_factor >= 0.0) && (vec12_13_z_factor >= 0.0)
    end
    same_line_same_dir = vertices_on_same_line && vectors_same_direction

    return same_line_same_dir
  end

  # Thermal zones need to be set to determine conditioned spaces when applying fdwr and srr limits.
  #
  # fdwr_set/srr_set settings:
  #   0-1:  Remove all windows/skylights and add windows/skylights to match this fdwr/srr
  #    -1:  Remove all windows/skylights and add windows/skylights to match max fdwr/srr from NECB
  #    -2:  Do not apply any fdwr/srr changes, leave windows/skylights alone (also works for fdwr/srr > 1)
  #    -3:  Use old method which reduces existing window/skylight size (if necessary) to meet maximum NECB fdwr/srr limit
  # <-3.1:  Remove all the windows/skylights
  #   > 1:  Do nothing
  #
  # By default, :srr_opt is an empty string (" "). If set to "osut", SRR is
  # instead met using OSut's 'addSkylights' (:srr_set numeric values may apply).
  def apply_fdwr_srr_daylighting(model:, fdwr_set: -1.0, srr_set: -1.0, necb_hdd: true, srr_opt: '')
    fdwr_set = -1.0 if (fdwr_set == 'NECB_default') || fdwr_set.nil?
    srr_set = -1.0 if (srr_set == 'NECB_default') || srr_set.nil?
    fdwr_set = fdwr_set.to_f
    srr_set = srr_set.to_f
    apply_standard_window_to_wall_ratio(model: model, fdwr_set: fdwr_set, necb_hdd: necb_hdd)
    apply_standard_skylight_to_roof_ratio(model: model, srr_set: srr_set, srr_opt: srr_opt)
    # model_add_daylighting_controls(model) # to be removed after refactor.
  end

  # Initiates a BTAP building ACTIVITY.
  #
  # @param model [OpenStudio::Model::Model] a model
  #
  # @return [BTAP::Activity] a BTAP building ACTIVITY (see logs if failed)
  def assign_building_activity(model: nil)
    @activity = BTAP::Activity.new(model)
  end

  # Initiates a BTAP building STRUCTURE.
  #
  # @param model [OpenStudio::Model::Model] a model
  # @param activity [BTAP::Activity] a BTAP building ACTIVITY object
  # @param massive [Boolean] whether requesting internal mass generation
  #
  # @return [BTAP::Structure] a BTAP building STRUCTURE (see logs if failed)
  def assign_building_structure(model: nil, activity: nil, massive: true)
    @structure = BTAP::Structure.new(model, activity, massive)
  end

  ##
  # (Optionally) uprates - then derates - envelope surface constructions due to
  # MAJOR thermal bridges (e.g. roof parapets, corners, fenestration
  # perimeters). See lib/openstudio-standards/btap/bridging.rb, which relies on
  # the Thermal Bridging & Derating (TBD) gem.
  #
  # @param model [OpenStudio::Model::Model] an OpenStudio model
  # @param necb_hdd [Boolean] whether to rely on BTAP to set HDD (vs stat file)
  # @param structure [BTAP::Structure] BTAP Structure object
  # @param option [#to_sym] BTAP/TBD option e.g. "uprate"
  # @param interpolate [Boolean] true if TBD interpolates among Uo (uprating)
  # @param wallU [Numeric] optional wall Ut in W/m2.K if uprating
  # @param floorU [Numeric] optional floor Ut in W/m2.K if uprating
  # @param roofU [Numeric] optional roof Ut in W/m2.K if uprating
  #
  # @return [Boolean] true if successful, e.g. no errors, compliant if uprated
  def apply_thermal_bridging(model: nil,
                             necb_hdd: true,
                             structure: nil,
                             option: 'none',
                             interpolate: false,
                             wallU: nil,
                             floorU: nil,
                             roofU: nil)
    necb_hdd = true unless [true, false].include?(necb_hdd)
    return true unless option.respond_to?(:to_sym)
    return true if option.to_s.downcase == 'none'

    hdd    = get_necb_hdd18(model: model, necb_hdd: necb_hdd)
    wallU  = wallU  ? wallU  : max_u_necb("wall", "outdoors", hdd)
    floorU = floorU ? floorU : max_u_necb("floor", "outdoors", hdd)
    roofU  = roofU  ? roofU  : max_u_necb("roofceiling", "outdoors", hdd)

    argh             = {}
    argh[:structure] = structure
    argh[:walls    ] = { uo: wallU  }
    argh[:floors   ] = { uo: floorU }
    argh[:roofs    ] = { uo: roofU  }

    case option.downcase
    when 'uprate'
      argh[:walls  ][:ut] = wallU
      argh[:floors ][:ut] = floorU
      argh[:roofs  ][:ut] = roofU
    when 'good'
      argh[:quality] = :good
    else
      argh[:quality] = :bad
    end

    argh[:interpolate] = interpolate
    argh[:interpolate] = false unless [true, false].include?(interpolate)

    @tbd = BTAP::Bridging.new(model, argh)

    true
  end

  # Apply the air leakage requirements to the model, as described in PNNL section 5.2.1.6.
  # This method creates customized infiltration objects for each space
  # and removes the SpaceType-level infiltration objects.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  # @todo This infiltration method is not used by the Reference buildings, fix this inconsistency.
  def model_apply_infiltration_standard(model)
    # Set the infiltration rate at each space
    model.getSpaces.sort.each do |space|
      space_apply_infiltration_rate(space)
    end

    # Remove infiltration rates set at the space type
    model.getSpaceTypes.sort.each do |space_type|
      space_type.spaceInfiltrationDesignFlowRates.each(&:remove)
    end

    return true
  end

  # @param necb_reference_hp [Boolean] if true, NECB reference model rules for heat pumps will be used.
  def apply_standard_efficiencies(model:, sizing_run_dir:, dcv_type: 'NECB_Default', necb_reference_hp: false)
    # Do a sizing run
    try_sizing_run(model: model, sizing_run_dir: sizing_run_dir, sizing_run_subdir: 'plant_loops')

    climate_zone = 'NECB HDD Method'

    # This is needed for NECB2011 as a workaround for sizing the reheat boxes.
    model.getAirTerminalSingleDuctVAVReheats.each { |iobj| air_terminal_single_duct_vav_reheat_set_heating_cap(iobj) }
    # Apply the prototype HVAC assumptions
    model_apply_prototype_hvac_assumptions(model, nil, climate_zone)
    # Apply the HVAC efficiency standard
    sql_db_vars_map = {}
    model_apply_hvac_efficiency_standard(model, climate_zone, sql_db_vars_map: sql_db_vars_map, necb_ref_hp: necb_reference_hp)

    model_enable_demand_controlled_ventilation(model, dcv_type)
    return sql_db_vars_map
  end

  # Shut off the system during unoccupied periods.
  # During these times, systems will cycle on briefly
  # if temperature drifts below setpoint.  For systems
  # with fan-powered terminals, the whole system
  # (not just the terminal fans) will cycle on.
  # Terminal-only night cycling is not used because the terminals cannot
  # provide cooling, so terminal-only night cycling leads to excessive
  # unmet cooling hours during unoccupied periods.
  # If the system already has a schedule other than
  # Always-On, no change will be made.  If the system has
  # an Always-On schedule assigned, a new schedule will be created.
  # In this case, occupied is defined as the total percent
  # occupancy for the loop for all zones served.
  #
  # @param min_occ_pct [Double] the fractional value below which
  # the system will be considered unoccupied.
  # @return [Boolean] true if successful, false if not
  def air_loop_hvac_enable_unoccupied_fan_shutoff(air_loop_hvac, min_occ_pct = 0.05)
    # Set the system to night cycle
    air_loop_hvac.setNightCycleControlType('CycleOnAny')

    # Check if already using a schedule other than always on
    avail_sch = air_loop_hvac.availabilitySchedule
    unless avail_sch == air_loop_hvac.model.alwaysOnDiscreteSchedule
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Availability schedule is already set to #{avail_sch.name}.  Will assume this includes unoccupied shut down; no changes will be made.")
      return true
    end

    # Get the airloop occupancy schedule
    loop_occ_sch = air_loop_hvac_get_occupancy_schedule(air_loop_hvac, occupied_percentage_threshold: min_occ_pct)
    flh = OpenstudioStandards::Schedules.schedule_get_equivalent_full_load_hours(loop_occ_sch)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Annual occupied hours = #{flh.round} hr/yr, assuming a #{min_occ_pct} occupancy threshold.  This schedule will be used as the HVAC operation schedule.")

    # Set HVAC availability schedule to follow occupancy
    air_loop_hvac.setAvailabilitySchedule(loop_occ_sch)
    air_loop_hvac.supplyComponents.each do |comp|
      if comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
        comp.to_AirLoopHVACUnitaryHeatPumpAirToAir.get.setSupplyAirFanOperatingModeSchedule(loop_occ_sch)
      elsif comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized
        comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get.setAvailabilitySchedule(loop_occ_sch)
      end
    end

    return true
  end

  # do not apply zone hvac ventilation control
  def zone_hvac_component_occupancy_ventilation_control(zone_hvac_component)
    return false
  end

  def apply_loop_pump_power(model:, sizing_run_dir:)
    # Remove duplicate materials and constructions
    # Note For NECB2015 This is the 2nd time this method is bieng run.
    # First time it ran in the super() within model_apply_standard() method
    # model = return BTAP::FileIO::remove_duplicate_materials_and_constructions(model)
    return model
  end

  # this method will determine the vintage of NECB spacetypes the model contains. It will return nil if it can't
  # determine it.
  def determine_spacetype_vintage(model)
    #this code is the list of available vintages
    space_type_vintage_list = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020', 'BTAPPRE1980', 'BTAP1980TO2010']
    #this reorders the list to do the current class first.
    space_type_vintage_list.insert(0, space_type_vintage_list.delete(self.class.name))
    # Set the space_type
    space_type_vintage = nil
    # get list of space types used in model and a mapped string.
    model_space_type_names = model.getSpaceTypes.map do |spacetype|
      [spacetype.standardsBuildingType.get.to_s + '-' + spacetype.standardsSpaceType.get.to_s]
    end
    # Now iterate though each vintage
    space_type_vintage_list.each do |template|
      # Create the standard object and get a list of all the spacetypes available for that vintage.
      standard_space_type_list = Standard.build(template).get_all_spacetype_names.map { |spacetype| [spacetype[0].to_s + '-' + spacetype[1].to_s] }
      # set array to contain unknown spacetypes.
      unknown_spacetypes = []
      # iterate though all space types that the model is using
      model_space_type_names.each do |space_type_name|
        # push unknown spacetypes into the array.
        unknown_spacetypes << space_type_name unless standard_space_type_list.include?(space_type_name)
      end
      if unknown_spacetypes.empty?
        # No unknowns, so return the template and don't bother looking for others.
        return template
      end
    end
    return space_type_vintage
  end

  # This method will validate that the space types in the model are indeed the correct NECB spacetypes names.
  def validate_and_upate_space_types(model)
    space_type_vintage = determine_spacetype_vintage(model)
    if space_type_vintage.nil?
      message = "These some of the spacetypes in the model are not part of any necb standard.\n  Please ensure all spacetype in model are correct."
      puts "Error: #{message}"
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.NECB', message)
      return false
    elsif space_type_vintage == self.class.name
      # the spacetype in the model match the version we are trying to create.
      # no translation neccesary.
      return true
    else
      # Need to translate to current vintage.
      no_errors = true
      st_model_vintage_string = "#{space_type_vintage}_space_type"
      bt_model_vintage_string = "#{space_type_vintage}_building_type"
      st_target_vintage_string = "#{self.class.name}_space_type"
      bt_target_vintage_string = "#{self.class.name}_building_type"
      space_type_upgrade_map = @standards_data['space_type_upgrade_map']
      model.getSpaceTypes.sort.each do |st|
        space_type_map = space_type_upgrade_map.detect { |row| (row[st_model_vintage_string] == st.standardsSpaceType.get.to_s) && (row[bt_model_vintage_string] == st.standardsBuildingType.get.to_s) }
        st.setStandardsBuildingType(space_type_map[bt_target_vintage_string].to_s.strip)
        raise('could not set buildingtype') unless st.setStandardsBuildingType(space_type_map[bt_target_vintage_string].to_s.strip)
        raise('could not set this') unless st.setStandardsSpaceType(space_type_map[st_target_vintage_string].to_s.strip)

        # Set name of spacetype to new name.
        st.setName("#{st.standardsBuildingType.get} #{st.standardsSpaceType.get}")
      end
      return no_errors
    end
  end

  # Set the infiltration rate for this space to include
  # the impact of air leakage requirements in the standard.
  #
  # @return [Double] true if successful, false if not
  # @todo handle doors and vestibules
  def space_apply_infiltration_rate(space)
    # Remove infiltration rates set at the space type.
    infiltration_data = @standards_data['infiltration']
    unless space.spaceType.empty?
      space.spaceType.get.spaceInfiltrationDesignFlowRates.each(&:remove)
    end
    # Remove infiltration rates set at the space object.
    space.spaceInfiltrationDesignFlowRates.each(&:remove)

    exterior_wall_and_roof_and_subsurface_area = OpenstudioStandards::Geometry.space_get_exterior_wall_and_subsurface_and_roof_area(space) # To do
    # Don't create an object if there is no exterior wall area
    if exterior_wall_and_roof_and_subsurface_area <= 0.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.Model', "For #{template}, no exterior wall area was found, no infiltration will be added.")
      return true
    end
    # Calculate the total infiltration, assuming
    # that it only occurs through exterior walls and roofs (not floors as
    # explicit stated in the NECB2011 so overhang/cantilevered floors will
    # have no effective infiltration)
    tot_infil_m3_per_s = get_standards_constant('infiltration_rate_m3_per_s_per_m2') * exterior_wall_and_roof_and_subsurface_area
    # Now spread the total infiltration rate over all
    # exterior surface area (for the E+ input field) this will include the exterior floor if present.
    all_ext_infil_m3_per_s_per_m2 = tot_infil_m3_per_s / space.exteriorArea

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.Space', "For #{space.name}, adj infil = #{all_ext_infil_m3_per_s_per_m2.round(8)} m^3/s*m^2.")

    # Get any infiltration schedule already assigned to this space or its space type
    # If not, the always on schedule will be applied.
    infil_sch = nil
    unless space.spaceInfiltrationDesignFlowRates.empty?
      old_infil = space.spaceInfiltrationDesignFlowRates[0]
      if old_infil.schedule.is_initialized
        infil_sch = old_infil.schedule.get
      end
    end

    if infil_sch.nil? && space.spaceType.is_initialized
      space_type = space.spaceType.get
      unless space_type.spaceInfiltrationDesignFlowRates.empty?
        old_infil = space_type.spaceInfiltrationDesignFlowRates[0]
        if old_infil.schedule.is_initialized
          infil_sch = old_infil.schedule.get
        end
      end
    end

    if infil_sch.nil?
      infil_sch = space.model.alwaysOnDiscreteSchedule
    end

    # Create an infiltration rate object for this space
    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space.model)
    infiltration.setName("#{space.name} Infiltration")
    infiltration.setFlowperExteriorSurfaceArea(all_ext_infil_m3_per_s_per_m2)
    infiltration.setSchedule(infil_sch)
    infiltration.setConstantTermCoefficient(get_standards_constant('infiltration_constant_term_coefficient'))
    infiltration.setTemperatureTermCoefficient(get_standards_constant('infiltration_constant_term_coefficient'))
    infiltration.setVelocityTermCoefficient(get_standards_constant('infiltration_velocity_term_coefficient'))
    infiltration.setVelocitySquaredTermCoefficient(get_standards_constant('infiltration_velocity_squared_term_coefficient'))
    infiltration.setSpace(space)

    return true
  end

  # @return [Boolean] returns true if successful, false if not
  def set_occ_sensor_spacetypes(model, space_type_map)
    building_type = 'Space Function'
    space_type_map.each do |space_type_name, space_names|
      space_names.sort.each do |space_name|
        space = model.getSpaceByName(space_name)
        next if space.empty?

        space = space.get

        # Check if space type for this space matches NECB2011 specific space type
        # for occupancy sensor that is area dependent. Note: space.floorArea in m2.

        # Evaluate the formula in the database.
        standard_space_type_name = space_type_name
        floor_area = space.floorArea
        if eval(@standards_data['formulas']['occupancy_sensors_space_types_formula']['value'])
          # If there is only one space assigned to this space type, then reassign this stub
          # to the @@template duplicate with appendage " - occsens", otherwise create a new stub
          # for this space. Required to use reduced LPD by NECB2011 0.9 factor.
          space_type_name_occsens = space_type_name + ' - occsens'
          stub_space_type_occsens = model.getSpaceTypeByName("#{building_type} #{space_type_name_occsens}")

          if stub_space_type_occsens.empty?
            # create a new space type just once for space_type_name appended with " - occsens"
            stub_space_type_occsens = OpenStudio::Model::SpaceType.new(model)
            stub_space_type_occsens.setStandardsBuildingType(building_type)
            stub_space_type_occsens.setStandardsSpaceType(space_type_name_occsens)
            stub_space_type_occsens.setName("#{building_type} #{space_type_name_occsens}")
            space_type_apply_rendering_color(stub_space_type_occsens)
            space.setSpaceType(stub_space_type_occsens)
          else
            # reassign occsens space type stub already created...
            stub_space_type_occsens = stub_space_type_occsens.get
            space.setSpaceType(stub_space_type_occsens)
          end
        end
      end
    end
    return true
  end

  # 2019-05-23 ckirney  This is an ugly, disgusting, hack (hence the name) that I dreamed out so that we could quickly
  # and easily finish the merge from the nrcan branch (using OS 2.6.0) to master (using OS 2.8.0).  This must be revised
  # and a more elegant solution found.
  #
  # This method takes everything in the @standards_data['tables'] hash and adds it to the main @standards_data hash.
  # This was done because other contributors insist on using the 'model_find_object' method which is passed a hash and
  # some search criteria.  The 'model_find_objects' then looks through the hash to information matching the search
  # criteria.  NECB standards assumes that the 'standards_lookup_table_first' method is used.  This does basically the
  # some thing as 'model_find_objects' only it assumes that you are looking in the standards hash and you tell it which
  # table in the standards hash to look for.
  def corrupt_standards_database
    @standards_data['tables'].each do |table|
      @standards_data[table[0]] = table[1]['table']
    end
  end

  # This model gets the climate zone column index from tables 3.2.2.x
  # @author phylroy.lopez@nrcan.gc.ca
  # @param hdd [Float]
  # @return [Fixnum] climate zone 4-8
  def get_climate_zone_index(hdd)
    # check for climate zone index from NECB 3.2.2.X
    case hdd
    when 0..2999 then
      return 0 # climate zone 4
    when 3000..3999 then
      return 1 # climate zone 5
    when 4000..4999 then
      return 2 # climate zone 6
    when 5000..5999 then
      return 3 # climate zone 7a
    when 6000..6999 then
      return 4 # climate zone 7b
    when 7000..1000000 then
      return 5 # climate zone 8
    end
  end

  # This model gets the climate zone name and returns the climate zone string.
  # @author phylroy.lopez@nrcan.gc.ca
  # @param hdd [Float]
  # @return [Fixnum] climate zone 4-8
  def get_climate_zone_name(hdd)
    case get_climate_zone_index(hdd)
    when 0 then
      return '4'
    when 1 then
      return '5' # climate zone 5
    when 2 then
      return '6' # climate zone 6
    when 3 then
      return '7a' # climate zone 7a
    when 4 then
      return '7b' # climate zone 7b
    when 5 then
      return '8' # climate zone 8
    end
  end

  def model_add_daylighting_controls(model:, daylighting_type:)

    return if daylighting_type == 'none'
    ##### Find spaces with exterior fenestration including fixed window, operable window, and skylight.
    daylight_spaces = []
    daylight_spaces_target_illuminance_setpoint_hash = {}
    model.getSpaces.sort.each do |space|
      space.surfaces.sort.each do |surface|
        surface.subSurfaces.sort.each do |subsurface|
          if subsurface.outsideBoundaryCondition == 'Outdoors' &&
            (subsurface.subSurfaceType == 'FixedWindow' ||
              subsurface.subSurfaceType == 'OperableWindow' ||
              subsurface.subSurfaceType == 'Skylight')
            daylight_spaces << space
            space_type = space.spaceType.get
            space_type_name = space.spaceType.get.name.to_s
            space_type_name = space_type_name.gsub('Space Function', '')
            # puts "space_type_name is #{space_type_name}"

            # Gather minimum illuminance level as per NECB
            lux_spacetype_data = @standards_data['tables']['space_types']['table']
            standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
            standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
            lux_space_type_properties = lux_spacetype_data.detect { |s| (s['building_type'] == standards_building_type) && (s['space_type'] == standards_space_type) }
            if lux_space_type_properties.nil?
              raise("#{standards_building_type} for #{standards_space_type} was not found please verify the target_illuminance_setpoint database names match the space type names.")
            end

            target_illuminance_setpoint = lux_space_type_properties['target_illuminance_setpoint'].to_f
            daylight_spaces_target_illuminance_setpoint_hash[space.name.to_s] = target_illuminance_setpoint

            # subsurface.outsideBoundaryCondition == "Outdoors" && (subsurface.subSurfaceType == "FixedWindow" || "OperableWindow")
          end
          # surface.subSurfaces.each do |subsurface|
        end
        # space.surfaces.each do |surface|
      end
      # model.getSpaces.sort.each do |space|
    end

    ##### Remove duplicate spaces from the "daylight_spaces" array, as a daylighted space may have various fenestration types.
    daylight_spaces = daylight_spaces.uniq
    # puts "daylight_spaces are #{daylight_spaces}"

    if daylighting_type.nil? || daylighting_type == false || daylighting_type == 'none' || daylighting_type == 'NECB_Default' # puts daylighting sensors in the spaces as per NECB requirements; so some spaces may not have sensors

      ##### Create hashes for "Primary Sidelighted Areas", "Sidelighting Effective Aperture", "Daylighted Area Under Skylights",
      ##### and "Skylight Effective Aperture" for the whole model.
      ##### Each of these hashes will be used later in this function (i.e. model_add_daylighting_controls)
      ##### to provide a dictionary of daylighted space names and the associated value (i.e. daylighted area or effective aperture).
      primary_sidelighted_area_hash = {}
      sidelighting_effective_aperture_hash = {}
      daylighted_area_under_skylights_hash = {}
      skylight_effective_aperture_hash = {}

      ##### Calculate "Primary Sidelighted Areas" AND "Sidelighting Effective Aperture" as per NECB2011. # @todo consider removing overlapped sidelighted area
      daylight_spaces.sort.each do |daylight_space|
        primary_sidelighted_area = 0.0
        area_weighted_vt_handle = 0.0
        area_weighted_vt = 0.0
        window_area_sum = 0.0

        ##### Calculate floor area of the daylight_space and get floor vertices of the daylight_space (to be used for the calculation of daylight_space depth)
        floor_surface = nil
        floor_area = 0.0
        floor_vertices = []
        daylight_space.surfaces.sort.each do |surface|
          if surface.surfaceType == 'Floor'
            floor_surface = surface
            floor_area += surface.netArea
            floor_vertices << surface.vertices
          end
        end

        ##### Loop through the surfaces of each daylight_space to calculate primary_sidelighted_area and
        ##### area-weighted visible transmittance and window_area_sum which are used to calculate sidelighting_effective_aperture
        primary_sidelighted_area, area_weighted_vt_handle, window_area_sum =
          get_parameters_sidelighting(daylight_space: daylight_space,
                                      floor_surface: floor_surface,
                                      floor_vertices: floor_vertices,
                                      floor_area: floor_area,
                                      primary_sidelighted_area: primary_sidelighted_area,
                                      area_weighted_vt_handle: area_weighted_vt_handle,
                                      window_area_sum: window_area_sum)

        primary_sidelighted_area_hash[daylight_space.name.to_s] = primary_sidelighted_area

        ##### Calculate area-weighted VT of glazing (this is used to calculate sidelighting effective aperture; see NECB2011: 4.2.2.10.).
        area_weighted_vt = area_weighted_vt_handle / window_area_sum
        sidelighting_effective_aperture_hash[daylight_space.name.to_s] = window_area_sum * area_weighted_vt / primary_sidelighted_area
        # daylight_spaces.each do |daylight_space|
      end

      ##### Calculate "Daylighted Area Under Skylights" AND "Skylight Effective Aperture"
      daylight_spaces.sort.each do |daylight_space|
        # puts daylight_space.name.to_s
        skylight_area = 0.0
        skylight_area_weighted_vt_handle = 0.0
        skylight_area_weighted_vt = 0.0
        skylight_area_sum = 0.0
        daylighted_under_skylight_area = 0.0

        ##### Loop through the surfaces of each daylight_space to calculate daylighted_area_under_skylights and skylight_effective_aperture for each daylight_space
        daylighted_under_skylight_area, skylight_area_weighted_vt_handle, skylight_area_sum =
          get_parameters_skylight(daylight_space: daylight_space,
                                  skylight_area_weighted_vt_handle: skylight_area_weighted_vt_handle,
                                  skylight_area_sum: skylight_area_sum,
                                  daylighted_under_skylight_area: daylighted_under_skylight_area)

        daylighted_area_under_skylights_hash[daylight_space.name.to_s] = daylighted_under_skylight_area

        ##### Calculate skylight_effective_aperture as per NECB2011: 4.2.2.7.
        ##### Note that it was assumed that the skylight is flush with the ceiling. Therefore, area-weighted average well factor (WF) was set to 0.9 in the below Equation.
        skylight_area_weighted_vt = skylight_area_weighted_vt_handle / skylight_area_sum
        skylight_effective_aperture_hash[daylight_space.name.to_s] = 0.85 * skylight_area_sum * skylight_area_weighted_vt * 0.9 / daylighted_under_skylight_area
        # daylight_spaces.each do |daylight_space|
      end
      # puts "primary_sidelighted_area_hash is #{primary_sidelighted_area_hash}"
      # puts sidelighting_effective_aperture_hash
      # puts daylighted_area_under_skylights_hash
      # puts skylight_effective_aperture_hash

      ##### Find office spaces >= 25m2 among daylight_spaces
      offices_larger_25m2 = []
      daylight_spaces.sort.each do |daylight_space|
        ## The following steps are for in case an office has multiple floors at various heights
        ## 1. Calculate number of floors of each daylight_space
        ## 2. Find the lowest z among all floors of each daylight_space
        ## 3. Find lowest floors of each daylight_space (these floors are at the same level)
        ## 4. Calculate 'daylight_space_area' as sum of area of all the lowest floors of each daylight_space, and gather the vertices of all the lowest floors of each daylight_space

        ## 1. Calculate number of floors of daylight_space
        floor_vertices = []
        number_floor = 0
        daylight_space.surfaces.sort.each do |surface|
          if surface.surfaceType == 'Floor'
            floor_vertices << surface.vertices
            number_floor += 1
          end
        end

        ## 2. Loop through all floors of daylight_space, and find the lowest z among all floors of daylight_space
        lowest_floor_z = []
        highest_floor_z = []
        for i in 0..number_floor - 1
          if i == 0
            lowest_floor_z = floor_vertices[i][0].z
            highest_floor_z = floor_vertices[i][0].z
          else
            if lowest_floor_z > floor_vertices[i][0].z
              lowest_floor_z = floor_vertices[i][0].z
            else
              lowest_floor_z = lowest_floor_z
            end
            if highest_floor_z < floor_vertices[i][0].z
              highest_floor_z = floor_vertices[i][0].z
            else
              highest_floor_z = highest_floor_z
            end
          end
        end

        ## 3 and 4. Loop through all floors of daylight_space, and calculate the sum of area of all the lowest floors of daylight_space,
        ## and gather the vertices of all the lowest floors of daylight_space
        daylight_space_area = 0
        lowest_floors_vertices = []
        floor_vertices = []
        daylight_space.surfaces.sort.each do |surface|
          if surface.surfaceType == 'Floor'
            floor_vertices = surface.vertices
            if floor_vertices[0].z == lowest_floor_z
              lowest_floors_vertices << floor_vertices
              daylight_space_area += surface.netArea
            end
          end
        end

        if daylight_space.spaceType.get.standardsSpaceType.get.to_s == 'Office - enclosed' && daylight_space_area >= 25.0
          offices_larger_25m2 << daylight_space.name.to_s
        end
      end

      ##### find daylight_spaces which do not need daylight sensor controls based on the primary_sidelighted_area as per NECB2011: 4.2.2.8.
      ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their primary_sidelighted_area <= 100m2), as per NECB2011: 4.2.2.2.
      daylight_spaces_exception = []
      primary_sidelighted_area_hash.sort.each do |key_daylight_space_name, value_primary_sidelighted_area|
        if value_primary_sidelighted_area <= 100.0 && [key_daylight_space_name].any? { |word| offices_larger_25m2.include?(word) } == false
          daylight_spaces_exception << key_daylight_space_name
        end
      end

      ##### find daylight_spaces which do not need daylight sensor controls based on the sidelighting_effective_aperture as per NECB2011: 4.2.2.8.
      ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their sidelighting_effective_aperture <= 10%), as per NECB2011: 4.2.2.2.
      sidelighting_effective_aperture_hash.sort.each do |key_daylight_space_name, value_sidelighting_effective_aperture|
        if value_sidelighting_effective_aperture <= 0.1 && [key_daylight_space_name].any? { |word| offices_larger_25m2.include?(word) } == false
          daylight_spaces_exception << key_daylight_space_name
        end
      end

      ##### find daylight_spaces which do not need daylight sensor controls based on the daylighted_area_under_skylights as per NECB2011: 4.2.2.4.
      ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their daylighted_area_under_skylights <= 400m2), as per NECB2011: 4.2.2.2.
      daylighted_area_under_skylights_hash.sort.each do |key_daylight_space_name, value_daylighted_area_under_skylights|
        if value_daylighted_area_under_skylights <= 400.0 && [key_daylight_space_name].any? { |word| offices_larger_25m2.include?(word) } == false
          daylight_spaces_exception << key_daylight_space_name
        end
      end

      ##### find daylight_spaces which do not need daylight sensor controls based on the skylight_effective_aperture criterion as per NECB2011: 4.2.2.4.
      ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their skylight_effective_aperture <= 0.6%), as per NECB2011: 4.2.2.2.
      skylight_effective_aperture_hash.sort.each do |key_daylight_space_name, value_skylight_effective_aperture|
        if value_skylight_effective_aperture <= 0.006 && [key_daylight_space_name].any? { |word| offices_larger_25m2.include?(word) } == false
          daylight_spaces_exception << key_daylight_space_name
        end
      end
      # puts daylight_spaces_exception

      ##### Loop through the daylight_spaces and exclude the daylight_spaces that do not meet the criteria (see above) as per NECB2011: 4.2.2.4. and 4.2.2.8.
      daylight_spaces_exception.sort.each do |daylight_space_exception|
        daylight_spaces.sort.each do |daylight_space|
          if daylight_space.name.to_s == daylight_space_exception
            daylight_spaces.delete(daylight_space)
          end
        end
      end
      # puts daylight_spaces

      # elsif daylighting_type == 'add_daylighting_controls' # puts daylighting sensors in all spaces regardless of NECB requirements

    end  #if daylighting_type.nil? || daylighting_type == false || daylighting_type == 'none' || daylighting_type == 'NECB_Default'

    ##### Create one daylighting sensor and put it at the center of each daylight_space if the space area < 250m2;
    ##### otherwise, create two daylight sensors, divide the space into two parts and put each of the daylight sensors at the center of each part of the space.
    daylight_spaces.sort.each do |daylight_space|
      # puts daylight_space.name.to_s
      ##### 1. Calculate number of floors of each daylight_space
      ##### 2. Find the lowest z among all floors of each daylight_space
      ##### 3. Find lowest floors of each daylight_space (these floors are at the same level)
      ##### 4. Calculate 'daylight_space_area' as sum of area of all the lowest floors of each daylight_space, and gather the vertices of all the lowest floors of each daylight_space
      ##### 5. Find min and max of x and y among vertices of all the lowest floors of each daylight_space

      ##### Calculate number of floors of daylight_space
      floor_vertices = []
      number_floor = 0
      daylight_space.surfaces.sort.each do |surface|
        if surface.surfaceType == 'Floor'
          floor_vertices << surface.vertices
          number_floor += 1
        end
      end

      ##### Loop through all floors of daylight_space, and find the lowest z among all floors of daylight_space
      lowest_floor_z = []
      highest_floor_z = []
      for i in 0..number_floor - 1
        if i == 0
          lowest_floor_z = floor_vertices[i][0].z
          highest_floor_z = floor_vertices[i][0].z
        else
          if lowest_floor_z > floor_vertices[i][0].z
            lowest_floor_z = floor_vertices[i][0].z
          else
            lowest_floor_z = lowest_floor_z
          end
          if highest_floor_z < floor_vertices[i][0].z
            highest_floor_z = floor_vertices[i][0].z
          else
            highest_floor_z = highest_floor_z
          end
        end
      end
      # puts lowest_floor_z

      ##### Loop through all floors of daylight_space, and calculate the sum of area of all the lowest floors of daylight_space,
      ##### and gather the vertices of all the lowest floors of daylight_space
      daylight_space_area = 0
      lowest_floors_vertices = []
      floor_vertices = []
      daylight_space.surfaces.sort.each do |surface|
        if surface.surfaceType == 'Floor'
          floor_vertices = surface.vertices
          if floor_vertices[0].z == lowest_floor_z
            lowest_floors_vertices << floor_vertices
            daylight_space_area += surface.netArea
          end
        end
      end
      # puts daylight_space.name.to_s
      # puts number_floor
      # puts lowest_floors_vertices
      # puts daylight_space_area

      ##### Loop through all lowest floors of daylight_space and find the min and max of x and y among their vertices
      xmin = lowest_floors_vertices[0][0].x
      ymin = lowest_floors_vertices[0][0].y
      xmax = lowest_floors_vertices[0][0].x
      ymax = lowest_floors_vertices[0][0].y
      zmin = lowest_floor_z
      for i in 0..lowest_floors_vertices.count - 1 # this loops through each of the lowers floors of daylight_space
        for j in 0..lowest_floors_vertices[i].count - 1 # this loops through each of vertices of each of the lowers floors of daylight_space

          if xmin > lowest_floors_vertices[i][j].x
            xmin = lowest_floors_vertices[i][j].x
          end
          if ymin > lowest_floors_vertices[i][j].y
            ymin = lowest_floors_vertices[i][j].y
          end
          if xmax < lowest_floors_vertices[i][j].x
            xmax = lowest_floors_vertices[i][j].x
          end
          if ymax < lowest_floors_vertices[i][j].y
            ymax = lowest_floors_vertices[i][j].y
          end
        end
      end
      # puts daylight_space.name.to_s
      # puts xmin
      # puts xmax
      # puts ymin
      # puts ymax

      ##### Get the thermal zone of daylight_space (this is used later to assign daylighting sensor)
      zone = daylight_space.thermalZone
      # puts "zone name is #{zone}"
      if !zone.empty?
        zone = daylight_space.thermalZone.get
        ##### Get the floor of the daylight_space
        floors = []
        daylight_space.surfaces.sort.each do |surface|
          if surface.surfaceType == 'Floor'
            floors << surface
          end
        end

        ##### Set daylighting controls illuminance setpoint and number of stepped control steps
        number_of_stepped_control_steps = 2   ##### Note that the minimum number of stepped control steps is two steps as per NECB2011.
        illuminance_setpoint =  daylight_spaces_target_illuminance_setpoint_hash.select {|key| key == daylight_space.name.to_s }
        illuminance_setpoint = illuminance_setpoint[daylight_space.name.to_s]

        ##### Create daylighting sensor control
        ##### NOTE: NECB2011 has some requirements on the number of sensors in spaces based on the area of the spaces.
        ##### However, EnergyPlus/OpenStudio allows to put maximum two built-in sensors in each thermal zone rather than in each space.
        ##### Since a thermal zone may include several spaces which are not next to each other on the same floor, or
        ##### a thermal zone may include spaces on different floors, a simplified method has been used to create a daylighting sensor.
        ##### So, in each thermal zone, only one daylighting sensor has been created even if the area of that thermal zone requires more than one daylighting sensor.
        ##### Also, it has been assumed that a thermal zone includes spaces which are next to each other and are on the same floor.
        ##### Furthermore, the one daylighting sensor in each thermal zone (where the thermal zone needs daylighting sensor),
        ##### the sensor has been put at the intersection of the minimum and maximum x and y of the lowest floor of that thermal zones.
        sensor = OpenStudio::Model::DaylightingControl.new(daylight_space.model)
        sensor.setName("#{daylight_space.name} daylighting control")
        sensor.setSpace(daylight_space)
        sensor.setIlluminanceSetpoint(illuminance_setpoint)
        sensor.setLightingControlType('Stepped')
        sensor.setNumberofSteppedControlSteps(number_of_stepped_control_steps)
        x_pos = (xmin + xmax) / 2.0
        y_pos = (ymin + ymax) / 2.0
        z_pos = zmin + 0.8 # put it 0.8 meter above the floor
        sensor_vertex = OpenStudio::Point3d.new(x_pos, y_pos, z_pos)
        sensor.setPosition(sensor_vertex)
        zone.setPrimaryDaylightingControl(sensor)
        zone.setFractionofZoneControlledbyPrimaryDaylightingControl(1.0)
        # if !zone.empty?
      end
      # daylight_spaces.each do |daylight_space|
    end # END if daylighting_controls_type.nil? || daylighting_controls_type == false || daylighting_controls_type == 'none' || daylighting_controls_type == 'NECB_Default'

  end # END model_add_daylighting_controls(model:, daylighting_type:)

  ##### Define ScheduleTypeLimits for Any_Number_ppm
  ##### @todo (upon other BTAP tasks) This function can be added to btap/schedules.rb > module StandardScheduleTypeLimits
  def get_any_number_ppm(model)
    name = 'Any_Number_ppm'
    any_number_ppm_schedule_type_limits = model.getScheduleTypeLimitsByName(name)
    return any_number_ppm_schedule_type_limits.get unless any_number_ppm_schedule_type_limits.empty?

    any_number_ppm_schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
    any_number_ppm_schedule_type_limits.setName(name)
    any_number_ppm_schedule_type_limits.setNumericType('CONTINUOUS')
    any_number_ppm_schedule_type_limits.setUnitType('Dimensionless')
    any_number_ppm_schedule_type_limits.setLowerLimitValue(400.0)
    any_number_ppm_schedule_type_limits.setUpperLimitValue(1000.0)
    return any_number_ppm_schedule_type_limits
  end

  # Note: Values for dcv_type are: 'Occupancy_based_DCV', 'CO2_based_DCV', 'No_DCV', 'NECB_Default'
  def model_enable_demand_controlled_ventilation(model, dcv_type = 'No_DCV')
    return if dcv_type == 'NECB_Defualt'

    if dcv_type == 'Occupancy_based_DCV' || dcv_type == 'CO2_based_DCV'
      # @todo IMPORTANT: (upon other BTAP tasks) Set a value for the "Outdoor Air Flow per Person" field of the "OS:DesignSpecification:OutdoorAir" object
      # Note: The "Outdoor Air Flow per Person" field is required for occupancy-based DCV.
      # Note: The "Outdoor Air Flow per Person" values should be based on ASHRAE 62.1: Article 6.2.2.1.
      # Note: The "Outdoor Air Flow per Person" should be entered for "ventilation_per_person" in "lib/openstudio-standards/standards/necb/NECB2011/data/space_types.json"

      ##### Define indoor CO2 availability schedule (required for CO2-based DCV)
      ##### Reference: see page B.13 of PNNL (2017), "Impacts of Commercial Building Controls on Energy Savings and Peak Load Reduction", available a: https://www.energy.gov/eere/buildings/downloads/impacts-commercial-building-controls-energy-savings-and-peak-load-reduction
      ##### Note: the defined schedule here is redundant as the schedule says it is always on AND
      ##### the "ZoneControl:ContaminantController" object says that "If this field is left blank, the schedule has a value of 1 for all time periods".
      indoor_co2_availability_schedule = OpenStudio::Model::ScheduleCompact.new(model)
      indoor_co2_availability_schedule.setName('indoor_co2_availability_schedule')
      indoor_co2_availability_schedule.setScheduleTypeLimits(BTAP::Resources::Schedules::StandardScheduleTypeLimits.get_fraction(model))
      indoor_co2_availability_schedule.to_ScheduleCompact.get
      # indoor_co2_availability_schedule.setString(1,"indoor_co2_availability_schedule")
      indoor_co2_availability_schedule.setString(3, 'Through: 12/31')
      indoor_co2_availability_schedule.setString(4, 'For: Weekdays SummerDesignDay')
      indoor_co2_availability_schedule.setString(5, 'Until: 07:00')
      indoor_co2_availability_schedule.setString(6, '0.0')
      indoor_co2_availability_schedule.setString(7, 'Until: 22:00')
      indoor_co2_availability_schedule.setString(8, '1.0')
      indoor_co2_availability_schedule.setString(9, 'Until: 24:00')
      indoor_co2_availability_schedule.setString(10, '0.0')
      indoor_co2_availability_schedule.setString(11, 'For: Saturday WinterDesignDay')
      indoor_co2_availability_schedule.setString(12, 'Until: 07:00')
      indoor_co2_availability_schedule.setString(13, '0.0')
      indoor_co2_availability_schedule.setString(14, 'Until: 18:00')
      indoor_co2_availability_schedule.setString(15, '1.0')
      indoor_co2_availability_schedule.setString(16, 'Until: 24:00')
      indoor_co2_availability_schedule.setString(17, '0.0')
      indoor_co2_availability_schedule.setString(18, 'For: AllOtherDays')
      indoor_co2_availability_schedule.setString(19, 'Until: 24:00')
      indoor_co2_availability_schedule.setString(20, '0.0')

      ##### Define indoor CO2 setpoint schedule (required for CO2-based DCV)
      ##### Reference: see page B.13 of PNNL (2017), "Impacts of Commercial Building Controls on Energy Savings and Peak Load Reduction", available a: https://www.energy.gov/eere/buildings/downloads/impacts-commercial-building-controls-energy-savings-and-peak-load-reduction
      indoor_co2_setpoint_schedule = OpenStudio::Model::ScheduleCompact.new(model)
      indoor_co2_setpoint_schedule.setName('indoor_co2_setpoint_schedule')
      indoor_co2_setpoint_schedule.setScheduleTypeLimits(get_any_number_ppm(model))
      indoor_co2_setpoint_schedule.to_ScheduleCompact.get
      indoor_co2_setpoint_schedule.setString(3, 'Through: 12/31')
      indoor_co2_setpoint_schedule.setString(4, 'For: AllDays')
      indoor_co2_setpoint_schedule.setString(5, 'Until: 24:00')
      indoor_co2_setpoint_schedule.setString(6, '1000.0')
      # indoor_co2_setpoint_schedule.setToConstantValue(1000.0) #1000 ppm

      ##### Define outdoor CO2 schedule (required for CO2-based DCV
      ##### Reference: see page B.13 of PNNL (2017), "Impacts of Commercial Building Controls on Energy Savings and Peak Load Reduction", available a: https://www.energy.gov/eere/buildings/downloads/impacts-commercial-building-controls-energy-savings-and-peak-load-reduction
      outdoor_co2_schedule = OpenStudio::Model::ScheduleCompact.new(model)
      outdoor_co2_schedule.setName('outdoor_co2_schedule')
      outdoor_co2_schedule.setScheduleTypeLimits(get_any_number_ppm(model))
      outdoor_co2_schedule.to_ScheduleCompact.get
      outdoor_co2_schedule.setString(3, 'Through: 12/31')
      outdoor_co2_schedule.setString(4, 'For: AllDays')
      outdoor_co2_schedule.setString(5, 'Until: 24:00')
      outdoor_co2_schedule.setString(6, '400.0')
      # outdoor_co2_schedule.setToConstantValue(400.0) #400 ppm

      ##### Define ZoneAirContaminantBalance (required for CO2-based DCV)
      zone_air_contaminant_balance = model.getZoneAirContaminantBalance
      zone_air_contaminant_balance.setCarbonDioxideConcentration(true)
      zone_air_contaminant_balance.setOutdoorCarbonDioxideSchedule(outdoor_co2_schedule)

      ##### Set CO2 controller in each space (required for CO2-based DCV)
      model.getSpaces.sort.each do |space|
        # puts space.name.to_s
        zone = space.thermalZone
        if !zone.empty?
          zone = space.thermalZone.get
        end
        zone_control_co2 = OpenStudio::Model::ZoneControlContaminantController.new(zone.model)
        zone_control_co2.setName("#{space.name} Zone Control Contaminant Controller")
        zone_control_co2.setCarbonDioxideControlAvailabilitySchedule(indoor_co2_availability_schedule)
        zone_control_co2.setCarbonDioxideSetpointSchedule(indoor_co2_setpoint_schedule)
        zone.setZoneControlContaminantController(zone_control_co2)
      end
      # if dcv_type == "Occupancy_based_DCV" || dcv_type == "CO2_based_DCV"
    end

    ##### Loop through AirLoopHVACs
    model.getAirLoopHVACs.sort.each do |air_loop|
      ##### Loop through AirLoopHVAC's supply nodes to:
      ##### (1) Find its AirLoopHVAC:OutdoorAirSystem using the supply node;
      ##### (2) Find Controller:OutdoorAir using AirLoopHVAC:OutdoorAirSystem;
      ##### (3) Get "Controller Mechanical Ventilation" from Controller:OutdoorAir.
      air_loop.supplyComponents.sort.each do |supply_component|
        ##### Find AirLoopHVAC:OutdoorAirSystem of AirLoopHVAC using the supply node.
        hvac_component = supply_component.to_AirLoopHVACOutdoorAirSystem

        if !hvac_component.empty?
          ##### Find Controller:OutdoorAir using AirLoopHVAC:OutdoorAirSystem.
          hvac_component = hvac_component.get
          controller_oa = hvac_component.getControllerOutdoorAir

          ##### Get "Controller Mechanical Ventilation" from Controller:OutdoorAir.
          controller_mv = controller_oa.controllerMechanicalVentilation

          ##### Set "Demand Controlled Ventilation" to "Yes" or "No" in Controller:MechanicalVentilation depending on dcv_type.
          if (dcv_type == 'CO2_based_DCV') || (dcv_type == 'Occupancy_based_DCV') # Occupancy
            controller_mv.setDemandControlledVentilation(true)
            ##### Set the "System Outdoor Air Method" field based on dcv_type in the Controller:MechanicalVentilation object
            if dcv_type == 'CO2_based_DCV'
              controller_mv.setSystemOutdoorAirMethod('IndoorAirQualityProcedure')
            else # dcv_type == 'Occupancy_based_DCV'
              controller_mv.setSystemOutdoorAirMethod('ZoneSum')
            end
          elsif dcv_type == 'No_DCV'
            controller_mv.setDemandControlledVentilation(false)
          end
          # puts controller_mv
          # if !hvac_component.empty?
        end
        # air_loop.supplyComponents.each do |supply_component|
      end
      # model.getAirLoopHVACs.each do |air_loop|
    end
  end

  def set_lighting_per_area_led_lighting(space_type:, definition:, lighting_per_area_led_lighting:, lights_scale:)
    # puts "#{space_type.name.to_s} - 'space_height' - #{space_height.to_s}"
    occ_sens_lpd_frac = 1.0
    # NECB2011 space types that require a reduction in the LPD to account for
    # the requirement of an occupancy sensor (8.4.4.6(3) and 4.2.2.2(2))
    reduce_lpd_spaces = ['Classroom/lecture/training', 'Conf./meet./multi-purpose', 'Lounge/recreation',
                         'Conf./meet./multi-purpose', 'Washroom-sch-A', 'Washroom-sch-B', 'Washroom-sch-C', 'Washroom-sch-D',
                         'Washroom-sch-E', 'Washroom-sch-F', 'Washroom-sch-G', 'Washroom-sch-H', 'Washroom-sch-I',
                         'Dress./fitt. - performance arts', 'Locker room', 'Locker room-sch-A', 'Locker room-sch-B',
                         'Locker room-sch-C', 'Locker room-sch-D', 'Locker room-sch-E', 'Locker room-sch-F', 'Locker room-sch-G',
                         'Locker room-sch-H', 'Locker room-sch-I', 'Retail - dressing/fitting']
    if reduce_lpd_spaces.include?(space_type.standardsSpaceType.get)
      # Note that "Storage area", "Storage area - refrigerated", "Hospital - medical supply" and "Office - enclosed"
      # LPD should only be reduced if their space areas are less than specific area values.
      # This is checked in a space loop after this function in the calling routine.
      occ_sens_lpd_frac = 0.9
    end

    # ##### Since Atrium's LPD for LED lighting depends on atrium's height, the height of the atrium (if applicable) should be found.
    standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
    if standards_space_type.include? 'Atrium' # @todo Note that since none of the archetypes has Atrium, this was tested for 'Dining'. #Atrium
      puts "#{standards_space_type} - has atrium" # space_type.name.to_s
      # Get the max height for the spacetype.
      max_space_height_for_spacetype = get_max_space_height_for_space_type(space_type: space_type)
      if max_space_height_for_spacetype < 12.0 # @todo Note that since none of the archetypes has Atrium, this was tested for 'Dining' with the threshold of 5.0 m for space_height.
        # @todo Regarding the below equations, identify which version of ASHRAE 90.1 was used in NECB2015.
        atrium_lpd_eq_smaller_12_intercept = 0
        atrium_lpd_eq_smaller_12_slope = 1.06
        atrium_lpd_eq_larger_12_intercept = 4.3
        atrium_lpd_eq_larger_12_slope = 1.06
        lighting_per_area_led_lighting_atrium = (atrium_lpd_eq_smaller_12_intercept + atrium_lpd_eq_smaller_12_slope * 12.0) * 0.092903 # W/ft2 @todo Note that for NECB2011, a constant LPD is used for atrium based on NECB2015's equations. NECB2011's threshold for height is 13.0 m.
      elsif max_space_height_for_spacetype >= 12.0 && max_space_height_for_spacetype < 13.0
        lighting_per_area_led_lighting_atrium = (atrium_lpd_eq_larger_12_intercept + atrium_lpd_eq_larger_12_slope * 12.5) * 0.092903 # W/ft2
      else # i.e. space_height >= 13.0
        lighting_per_area_led_lighting_atrium = (atrium_lpd_eq_larger_12_intercept + atrium_lpd_eq_larger_12_slope * 13.0) * 0.092903 # W/ft2
      end
      puts "#{standards_space_type} - has lighting_per_area_led_lighting_atrium - #{lighting_per_area_led_lighting_atrium}"
      lighting_per_area_led_lighting = lighting_per_area_led_lighting_atrium
    end
    lighting_per_area_led_lighting *= lights_scale
    definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area_led_lighting.to_f * occ_sens_lpd_frac, 'W/ft^2', 'W/m^2').get)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area_led_lighting} W/ft^2.")
  end

  # Adds the loads and associated schedules for each space type
  # as defined in the OpenStudio_Standards_space_types.json file.
  # This includes lights, plug loads, occupants, ventilation rate requirements,
  # infiltration, gas equipment (for kitchens, etc.) and typical schedules for each.
  # Some loads are governed by the standard, others are typical values
  # pulled from sources such as the DOE Reference and DOE Prototype Buildings.
  #
  # @return [Boolean] returns true if successful, false if not
  def model_add_loads(model, lights_type, lights_scale)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying space types (loads)')

    # Loop through all the space types currently in the model,
    # which are placeholders, and give them appropriate loads and schedules
    model.getSpaceTypes.sort.each do |space_type|
      # Rendering color
      space_type_apply_rendering_color(space_type)

      # Loads
      space_type_apply_internal_loads(space_type: space_type, lights_type: lights_type, lights_scale: lights_scale)

      # Schedules
      space_type_apply_internal_load_schedules(space_type)
      space_type_apply_thermostat_schedules(space_type)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying space types (loads)')

    return true
  end

  ##### This method is needed to the space_type_apply_internal_loads space needed for the calculation of atriums' LPD when LED lighting is used in atriums. ***END***
  def get_max_space_height_for_space_type(space_type:)
    # initialize return value to zero.
    max_space_height_for_space_type = 0.0
    # Interate through all spaces in model.. not just ones that have space type defined.. Is this right sara?
    space_type.spaces.sort.each do |space|
      # Get only the wall type surfaces and iterate throught them.
      space.surfaces.sort.select(&:surfaceType == 'Wall').each do |wall_surface|
        # Find the vertex with the max z value.
        vertex_with_max_height = wall_surface.vertices.max_by(&:z)
        # replace max if this surface has something bigger.
        max_space_height_for_space_type = vertex_with_max_height.z if vertex_with_max_height.z > max_space_height_for_space_type
      end
    end
    return max_space_height_for_space_type
  end

  ##### The below method is for the 'model_add_daylighting_controls' method
  def get_parameters_sidelighting(daylight_space:, floor_surface:, floor_vertices:, floor_area:, primary_sidelighted_area:, area_weighted_vt_handle:, window_area_sum:)
    daylight_space.surfaces.sort.each do |surface|
      ##### Get the vertices of each exterior wall of the daylight_space on the floor
      ##### (these vertices will be used to calculate daylight_space depth in relation to the exterior wall, and
      ##### the distance of the window to vertical walls on each side of the window)
      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'
        wall_vertices_x_on_floor = []
        wall_vertices_y_on_floor = []
        surface_z_min = [surface.vertices[0].z, surface.vertices[1].z, surface.vertices[2].z, surface.vertices[3].z].min
        surface.vertices.each do |vertex|
          # puts vertex.z
          if vertex.z == surface_z_min && surface_z_min == floor_vertices[0][0].z
            wall_vertices_x_on_floor << vertex.x
            wall_vertices_y_on_floor << vertex.y
          end
        end
      end

      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall' && surface_z_min == floor_vertices[0][0].z

        ##### Calculate the daylight_space depth in relation to the considered exterior wall.
        ##### To calculate daylight_space depth, first get the floor vertices which are on the opposite side of the considered exterior wall.
        floor_vertices_x_wall_opposite = []
        floor_vertices_y_wall_opposite = []
        floor_vertices[0].each do |floor_vertex|
          if (floor_vertex.x != wall_vertices_x_on_floor[0] && floor_vertex.y != wall_vertices_y_on_floor[0]) || (floor_vertex.x != wall_vertices_x_on_floor[1] && floor_vertex.y != wall_vertices_y_on_floor[1])
            floor_vertices_x_wall_opposite << floor_vertex.x
            floor_vertices_y_wall_opposite << floor_vertex.y
          end
        end

        ##### To calculate daylight_space depth, second calculate floor length on both sides: (1) exterior wall side, (2) on the opposite side of the exterior wall
        floor_width_wall_side = Math.sqrt((wall_vertices_x_on_floor[0] - wall_vertices_x_on_floor[1])**2 + (wall_vertices_y_on_floor[0] - wall_vertices_y_on_floor[1])**2)
        floor_width_wall_opposite = Math.sqrt((floor_vertices_x_wall_opposite[0] - floor_vertices_x_wall_opposite[1])**2 + (floor_vertices_y_wall_opposite[0] - floor_vertices_y_wall_opposite[1])**2)

        ##### Now, daylight_space depth can be calculated using the floor area and two lengths of the floor (note that these two lengths are in parallel to each other).
        daylight_space_depth = 2 * floor_area / (floor_width_wall_side + floor_width_wall_opposite)

        ##### Loop through the windows (including fixed and operable ones) to get window specification (width, height, area, visible transmittance (VT)), and area-weighted VT
        surface.subSurfaces.sort.each do |subsurface|
          # puts subsurface.name.to_s
          if subsurface.subSurfaceType == 'FixedWindow' || subsurface.subSurfaceType == 'OperableWindow'
            window_vt = subsurface.visibleTransmittance
            window_vt = window_vt.get
            window_area = subsurface.netArea
            window_area_sum += window_area
            area_weighted_vt_handle += window_area * window_vt
            window_vertices = subsurface.vertices
            if window_vertices[0].z.round(2) == window_vertices[1].z.round(2)
              window_width = Math.sqrt((window_vertices[0].x - window_vertices[1].x)**2.0 + (window_vertices[0].y - window_vertices[1].y)**2.0)
            else
              window_width = Math.sqrt((window_vertices[1].x - window_vertices[2].x)**2.0 + (window_vertices[1].y - window_vertices[2].y)**2.0)
            end
            window_head_height = [window_vertices[0].z, window_vertices[1].z, window_vertices[2].z, window_vertices[3].z].max.round(2)
            primary_sidelighted_area_depth = [window_head_height, daylight_space_depth].min # as per NECB2011: 4.2.2.9.

            ##### Calculate the  distance of the window to vertical walls on each side of the window (this is used to determine the sidelighted area's width).
            window_vertices_on_floor = []
            window_vertices.each do |vertex|
              window_vertices_on_floor << floor_surface.plane.project(vertex)
            end
            window_wall_distance_side1 = [Math.sqrt((wall_vertices_x_on_floor[0] - window_vertices_on_floor[0].x)**2.0 + (wall_vertices_y_on_floor[0] - window_vertices_on_floor[0].y)**2.0),
                                          Math.sqrt((wall_vertices_x_on_floor[0] - window_vertices_on_floor[2].x)**2.0 + (wall_vertices_y_on_floor[0] - window_vertices_on_floor[2].y)**2.0),
                                          0.6].min # 0.6 m as per NECB2011: 4.2.2.9.
            window_wall_distance_side2 = [Math.sqrt((wall_vertices_x_on_floor[1] - window_vertices_on_floor[0].x)**2.0 + (wall_vertices_y_on_floor[1] - window_vertices_on_floor[0].y)**2.0),
                                          Math.sqrt((wall_vertices_x_on_floor[1] - window_vertices_on_floor[2].x)**2.0 + (wall_vertices_y_on_floor[1] - window_vertices_on_floor[2].y)**2.0),
                                          0.6].min # 0.6 m as per NECB2011: 4.2.2.9.
            primary_sidelighted_area_width = window_wall_distance_side1 + window_width + window_wall_distance_side2
            primary_sidelighted_area += primary_sidelighted_area_depth * primary_sidelighted_area_width
            # if subsurface.subSurfaceType == "FixedWindow" || subsurface.subSurfaceType == "OperableWindow"
          end
          # surface.subSurfaces.each do |subsurface|
        end
        # if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall" && surface_z_min == floor_vertices[0][0].z
      end
      # daylight_space.surfaces.each do |surface|
    end

    return primary_sidelighted_area, area_weighted_vt_handle, window_area_sum
  end

  ##### The below method is for the 'model_add_daylighting_controls' method
  def get_parameters_skylight(daylight_space:, skylight_area_weighted_vt_handle:, skylight_area_sum:, daylighted_under_skylight_area:)
    daylight_space.surfaces.sort.each do |surface|
      ##### Get roof vertices
      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'
        roof_vertices = surface.vertices
      end

      ##### Loop through each subsurface to calculate daylighted_area_under_skylights and skylight_effective_aperture for each daylight_space
      surface.subSurfaces.sort.each do |subsurface|
        if subsurface.subSurfaceType == 'Skylight'
          skylight_vt = subsurface.visibleTransmittance
          skylight_vt = skylight_vt.get
          skylight_area = subsurface.netArea
          skylight_area_sum += skylight_area
          skylight_area_weighted_vt_handle += skylight_area * skylight_vt

          ##### Get skylight vertices
          skylight_vertices = subsurface.vertices

          ##### Calculate skylight width and height
          skylight_width = Math.sqrt((skylight_vertices[0].x - skylight_vertices[1].x)**2.0 + (skylight_vertices[0].y - skylight_vertices[1].y)**2.0)
          skylight_length = Math.sqrt((skylight_vertices[0].x - skylight_vertices[3].x)**2.0 + (skylight_vertices[0].y - skylight_vertices[3].y)**2.0)

          ##### Get ceiling height assuming the skylight is flush with the ceiling
          ceiling_height = skylight_vertices[0].z

          ##### Calculate roof lengths
          ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
          roof_length_0 = Math.sqrt((roof_vertices[0].x - roof_vertices[1].x)**2.0 + (roof_vertices[0].y - roof_vertices[1].y)**2.0)
          roof_length_1 = Math.sqrt((roof_vertices[1].x - roof_vertices[2].x)**2.0 + (roof_vertices[1].y - roof_vertices[2].y)**2.0)
          roof_length_2 = Math.sqrt((roof_vertices[2].x - roof_vertices[3].x)**2.0 + (roof_vertices[2].y - roof_vertices[3].y)**2.0)
          roof_length_3 = Math.sqrt((roof_vertices[3].x - roof_vertices[0].x)**2.0 + (roof_vertices[3].y - roof_vertices[0].y)**2.0)

          ##### Find the skylight point that is the closest one to roof_vertex_0
          ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
          roof_vertex_0_skylight_vertex_0 = Math.sqrt((roof_vertices[0].x - skylight_vertices[0].x)**2.0 + (roof_vertices[0].y - skylight_vertices[0].y)**2.0)
          roof_vertex_0_skylight_vertex_1 = Math.sqrt((roof_vertices[0].x - skylight_vertices[1].x)**2.0 + (roof_vertices[0].y - skylight_vertices[1].y)**2.0)
          roof_vertex_0_skylight_vertex_2 = Math.sqrt((roof_vertices[0].x - skylight_vertices[2].x)**2.0 + (roof_vertices[0].y - skylight_vertices[2].y)**2.0)
          roof_vertex_0_skylight_vertex_3 = Math.sqrt((roof_vertices[0].x - skylight_vertices[3].x)**2.0 + (roof_vertices[0].y - skylight_vertices[3].y)**2.0)
          roof_vertex_0_closest_distance = [roof_vertex_0_skylight_vertex_0, roof_vertex_0_skylight_vertex_1, roof_vertex_0_skylight_vertex_2, roof_vertex_0_skylight_vertex_3].min
          if roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_0
            roof_vertex_0_closest_point = skylight_vertices[0]
          elsif roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_1
            roof_vertex_0_closest_point = skylight_vertices[1]
          elsif roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_2
            roof_vertex_0_closest_point = skylight_vertices[2]
          elsif roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_3
            roof_vertex_0_closest_point = skylight_vertices[3]
          end

          ##### Find the skylight point that is the closest one to roof_vertex_2
          ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
          roof_vertex_2_skylight_vertex_0 = Math.sqrt((roof_vertices[2].x - skylight_vertices[0].x)**2.0 + (roof_vertices[2].y - skylight_vertices[0].y)**2.0)
          roof_vertex_2_skylight_vertex_1 = Math.sqrt((roof_vertices[2].x - skylight_vertices[1].x)**2.0 + (roof_vertices[2].y - skylight_vertices[1].y)**2.0)
          roof_vertex_2_skylight_vertex_2 = Math.sqrt((roof_vertices[2].x - skylight_vertices[2].x)**2.0 + (roof_vertices[2].y - skylight_vertices[2].y)**2.0)
          roof_vertex_2_skylight_vertex_3 = Math.sqrt((roof_vertices[2].x - skylight_vertices[3].x)**2.0 + (roof_vertices[2].y - skylight_vertices[3].y)**2.0)
          roof_vertex_2_closest_distance = [roof_vertex_2_skylight_vertex_0, roof_vertex_2_skylight_vertex_1, roof_vertex_2_skylight_vertex_2, roof_vertex_2_skylight_vertex_3].min
          if roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_0
            roof_vertex_2_closest_point = skylight_vertices[0]
          elsif roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_1
            roof_vertex_2_closest_point = skylight_vertices[1]
          elsif roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_2
            roof_vertex_2_closest_point = skylight_vertices[2]
          elsif roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_3
            roof_vertex_2_closest_point = skylight_vertices[3]
          end

          ##### Calculate the vertical distance from the closest skylight points (projection onto the roof) to the wall (projection onto the roof) for roof_vertex_0 and roof_vertex_2
          ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
          ##### For the calculation of each vertical distance: (1) first the area of the triangle is calculated knowing the cooridantes of its three corners;
          ##### (2) the vertical distance (i.e. triangle height) is calculated knowing the triangle area and the associated roof length.
          rv_0_triangle_0_area = 0.5 * (((roof_vertex_0_closest_point.x - roof_vertices[1].x) * (roof_vertex_0_closest_point.y - roof_vertices[0].y)) -
              ((roof_vertex_0_closest_point.x - roof_vertices[0].x) * (roof_vertex_0_closest_point.y - roof_vertices[1].y))).abs
          rv_0_distance_0 = (2.0 * rv_0_triangle_0_area) / roof_length_0
          rv_0_triangle_3_area = 0.5 * (((roof_vertex_0_closest_point.x - roof_vertices[3].x) * (roof_vertex_0_closest_point.y - roof_vertices[0].y)) -
              ((roof_vertex_0_closest_point.x - roof_vertices[0].x) * (roof_vertex_0_closest_point.y - roof_vertices[3].y))).abs
          rv_0_distance_3 = (2.0 * rv_0_triangle_3_area) / roof_length_3

          rv_2_triangle_1_area = 0.5 * (((roof_vertex_2_closest_point.x - roof_vertices[1].x) * (roof_vertex_2_closest_point.y - roof_vertices[2].y)) -
              ((roof_vertex_2_closest_point.x - roof_vertices[2].x) * (roof_vertex_2_closest_point.y - roof_vertices[1].y))).abs
          rv_2_distance_1 = (2.0 * rv_2_triangle_1_area) / roof_length_1
          rv_2_triangle_2_area = 0.5 * (((roof_vertex_2_closest_point.x - roof_vertices[3].x) * (roof_vertex_2_closest_point.y - roof_vertices[2].y)) -
              ((roof_vertex_2_closest_point.x - roof_vertices[2].x) * (roof_vertex_2_closest_point.y - roof_vertices[3].y))).abs
          rv_2_distance_2 = (2.0 * rv_2_triangle_2_area) / roof_length_2

          ##### Set the vertical distances from the closest skylight points (projection onto the roof) to the wall (projection onto the roof) for roof_vertex_0 and roof_vertex_2
          distance_1 = rv_0_distance_0
          distance_2 = rv_0_distance_3
          distance_3 = rv_2_distance_1
          distance_4 = rv_2_distance_2

          ##### Calculate the width and length of the daylighted area under the skylight as per NECB2011: 4.2.2.5.
          ##### Note: In the below loops, if any exterior walls has window(s), the width and length of the daylighted area under the skylight are re-calculated as per NECB2011: 4.2.2.5.
          daylighted_under_skylight_width = skylight_width + [0.7 * ceiling_height, distance_1].min + [0.7 * ceiling_height, distance_4].min
          daylighted_under_skylight_length = skylight_length + [0.7 * ceiling_height, distance_2].min + [0.7 * ceiling_height, distance_3].min

          ##### As noted above, the width and length of the daylighted area under the skylight are re-calculated (as per NECB2011: 4.2.2.5.), if any exterior walls has window(s).
          ##### To this end, the window_head_height should be calculated, as below:
          daylight_space.surfaces.sort.each do |curr_surface|
            if curr_surface.outsideBoundaryCondition == 'Outdoors' && curr_surface.surfaceType == 'Wall'
              wall_vertices_on_floor_x = []
              wall_vertices_on_floor_y = []
              wall_vertices = curr_surface.vertices
              if wall_vertices[0].z == wall_vertices[1].z
                wall_vertices_on_floor_x << wall_vertices[0].x
                wall_vertices_on_floor_x << wall_vertices[1].x
                wall_vertices_on_floor_y << wall_vertices[0].y
                wall_vertices_on_floor_y << wall_vertices[1].y
              elsif wall_vertices[0].z == wall_vertices[3].z
                wall_vertices_on_floor_x << wall_vertices[0].x
                wall_vertices_on_floor_x << wall_vertices[3].x
                wall_vertices_on_floor_y << wall_vertices[0].y
                wall_vertices_on_floor_y << wall_vertices[3].y
              end
              window_vertices = subsurface.vertices
              window_head_height = [window_vertices[0].z, window_vertices[1].z, window_vertices[2].z, window_vertices[3].z].max.round(2)

              ##### Calculate the exterior wall length (on the floor)
              exterior_wall_length = Math.sqrt((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1])**2.0 + (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1])**2.0)

              ##### Calculate the vertical distance of skylight_vertices[0] projection onto the roof/floor to the exterior wall
              skylight_vertex_0_triangle_area = 0.5 * (((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) * (wall_vertices_on_floor_y[0] - skylight_vertices[0].y)) -
                  ((wall_vertices_on_floor_x[0] - skylight_vertices[0].x) * (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]))).abs
              skylight_vertex_0_distance = (2.0 * skylight_vertex_0_triangle_area) / exterior_wall_length

              ##### Calculate the vertical distance of skylight_vertices[1] projection onto the roof/floor to the exterior wall
              skylight_vertex_1_triangle_area = 0.5 * (((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) * (wall_vertices_on_floor_y[0] - skylight_vertices[1].y)) -
                  ((wall_vertices_on_floor_x[0] - skylight_vertices[1].x) * (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]))).abs
              skylight_vertex_1_distance = (2.0 * skylight_vertex_1_triangle_area) / exterior_wall_length

              ##### Calculate the vertical distance of skylight_vertices[3] projection onto the roof/floor to the exterior wall
              skylight_vertex_3_triangle_area = 0.5 * (((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) * (wall_vertices_on_floor_y[0] - skylight_vertices[3].y)) -
                  ((wall_vertices_on_floor_x[0] - skylight_vertices[3].x) * (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]))).abs
              skylight_vertex_3_distance = (2.0 * skylight_vertex_3_triangle_area) / exterior_wall_length

              ##### Loop through the subsurfaces that has exterior windows to re-calculate the width and length of the daylighted area under the skylight
              curr_surface.subSurfaces.sort.each do |curr_subsurface|
                if curr_subsurface.subSurfaceType == 'FixedWindow' || curr_subsurface.subSurfaceType == 'OperableWindow'

                  if skylight_vertex_0_distance == skylight_vertex_1_distance # skylight_01 is in parellel to the exterior wall
                    if skylight_vertex_0_distance.round(2) == distance_2.round(2)
                      daylighted_under_skylight_length = skylight_length + [0.7 * ceiling_height, distance_2, distance_2 - window_head_height].min + [0.7 * ceiling_height, distance_3].min
                    elsif skylight_vertex_0_distance.round(2) == distance_3.round(2)
                      daylighted_under_skylight_length = skylight_length + [0.7 * ceiling_height, distance_2].min + [0.7 * ceiling_height, distance_3, distance_3 - window_head_height].min
                    end
                  elsif skylight_vertex_0_distance == skylight_vertex_3_distance # skylight_03 is in parellel to the exterior wall
                    if skylight_vertex_0_distance.round(2) == distance_1.round(2)
                      daylighted_under_skylight_width = skylight_width + [0.7 * ceiling_height, distance_1, distance_1 - window_head_height].min + [0.7 * ceiling_height, distance_4].min
                    elsif skylight_vertex_0_distance.round(2) == distance_4.round(2)
                      daylighted_under_skylight_width = skylight_width + [0.7 * ceiling_height, distance_1].min + [0.7 * ceiling_height, distance_4, distance_4 - window_head_height].min
                    end
                    # if skylight_vertex_0_distance == skylight_vertex_1_distance
                  end

                  daylighted_under_skylight_area += daylighted_under_skylight_length * daylighted_under_skylight_width
                  # if subsurface.subSurfaceType == "FixedWindow" || subsurface.subSurfaceType == "OperableWindow"
                end
                # surface.subSurfaces.each do |subsurface|
              end
              # if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall"
            end
            # daylight_space.surfaces.each do |surface|
          end
          # if subsurface.subSurfaceType == "Skylight"
        end
        # surface.subSurfaces.each do |subsurface|
      end
      # daylight_space.surfaces.each do |surface|
    end

    return daylighted_under_skylight_area, skylight_area_weighted_vt_handle, skylight_area_sum
  end

  def set_output_variables(model:,output_variables:)
    unless output_variables.nil? or output_variables.empty?
      output_variables.each do |output_variable|
        puts output_variable
        puts output_variable['frequency']
        raise("Frequency is not valid. Must by \"hourly\" or \"timestep\" but got #{output_variable}.") unless ["timestep","hourly",'daily','monthly','annual'].include?(output_variable['frequency'])
        output = OpenStudio::Model::OutputVariable.new(output_variable['variable'],model)
        output.setKeyValue(output_variable['key'])
        output.setReportingFrequency(output_variable['frequency'])
      end
    end
    return model
  end

  def set_output_meters(model:,output_meters:)
    unless output_meters.nil? or output_meters.empty?
      # remove existing output meters
      existing_meters = model.getOutputMeters

      # OpenStudio doesn't seemt to like two meters of the same name, even if they have different reporting frequencies.
      output_meters.each do |new_meter|
        #check if meter already exists
        result = existing_meters.select { |e_m| e_m.name == new_meter['name'] }
        puts("More and one output meter named #{new_meter['name']}") if result.size > 1
        if result.size >= 1
          existing_meter = result[0]
          puts("A meter named #{new_meter['name']} already exists. One will not be added to the model.")
          if existing_meter.reportingFrequency != new_meter['frequency']
            existing_meter.setReportingFrequency(new_meter['frequency'])
            puts("Changing reporting frequency of existing meter to #{new_meter['frequency']}.")
          end
        end
        if result.size == 0
          meter = OpenStudio::Model::OutputMeter.new(model)
          meter.setName(new_meter['name'])
          meter.setReportingFrequency(new_meter['frequency'])
          puts("Adding meter for #{meter.name} reporting #{new_meter['frequency']}")
        end
      end
    end
    return model
  end

  # This method handles looking for the epw_file in btap_weather or Climate.OneBuilding.Org. It
  # checks for the epw_file in the historical data first.  If it is not there then it looks in the future weather data.
  # If it is not there either, it throws an error.
  # epw_file (String): The name of the epw file.  The different weather files all share the same name as the epw file,
  #                    only the extension changes.
  # btap_weather (Boolean): Determines whether to download from the btap_weather repository or Climate.OneBuilding.Org.
  def get_weather_file_from_repo(epw_file:, btap_weather:)
    # Get just the weather file name without the extension
    weather_loc = epw_file[0..-5]
    # Get the url of the file containing the historical weather data file names in the repository and the repository
    # folder containing the files
    if btap_weather
      historic_weather_files_loc = @standards_data['constants']['historic_weather_file_list_btap']['value'].to_s
      historic_folder = @standards_data['constants']['historic_weather_folder_url_btap']['value'].to_s
      future_weather_files_loc = @standards_data['constants']['future_weather_file_list_btap']['value'].to_s
      future_folder = @standards_data['constants']['future_weather_folder_url_btap']['value'].to_s
    else
      historic_weather_files_loc = @standards_data['constants']['historic_weather_file_list']['value'].to_s
      historic_folder = @standards_data['constants']['historic_weather_folder_url']['value'].to_s
      future_weather_files_loc = @standards_data['constants']['future_weather_file_list']['value'].to_s
      future_folder = @standards_data['constants']['future_weather_folder_url']['value'].to_s
    end
    # Get the files from the repository
    success_flag = download_and_save_file(weather_list_url: historic_weather_files_loc,
                                          weather_loc: weather_loc,
                                          download_folder: historic_folder,
                                          btap_weather: btap_weather)
    return if success_flag
    # If the file could not be found in the historical data look for it with the future weather data.
    puts "Could not find #{epw_file} in historical weather data files, looking in future weather data files."
    success_flag = download_and_save_file(weather_list_url: future_weather_files_loc,
                                          weather_loc: weather_loc,
                                          download_folder: future_folder,
                                          btap_weather: btap_weather)
    return if success_flag
    raise("Could not locate the following file in #{btap_weather ? "btap_weather" : "Climate.OneBuilding.Org"} or could not extract the data: #{epw_file} Please check the spelling of the file or visit #{btap_weather ? "https://github.com/canmet-energy/btap_weather" : "https://climate.onebuilding.org/WMO_Region_4_North_and_Central_America/"} to see if the file exists.")
  end

  # This method actually looks for and downloads the zip file from the https://github.com/canmet-energy/btap_weather
  # repository.  The repository contains json files containing the names of all of the weather data zip files of a given
  # type (either historic weather files or future weather files).  This json is checked first to make sure that the file
  # is in the repository.  If it is, the method downloads the zip file and extracts the data all to the
  # openstudio-standards weather file folder.

  # Arguments:
  # weather_list_url (string): the web address of the json file containing the list of weather files on the repository
  # weather_loc (string): the name of the epw file we are looking for without the .epw extension
  # git_folder (string): the url of the folder containing the weather files.  As of 2023-07-07 this this is either the
  #                      url of the historical weather data folder or the future weather data folder.
  # btap_weather (Boolean): Determines whether to download from the btap_weather repository or Climate.OneBuilding.Org.
  def download_and_save_file(weather_list_url:, weather_loc:, download_folder:, btap_weather:)
    status = false
    attempt = 1
    # Try to download the list of weather files 5 times, waiting 5 seconds between each attempt.
    until attempt > 5
      begin
        puts "Beginning attempt #{attempt} to download #{weather_list_url}"
        # Download the list of weather files on the repository
        URI.open(weather_list_url) do |web_data|
          # Convert the weather file list to an array
          if web_data.size <= 100
            raise("Could not read #{weather_list_url}!")
          end
          weather_files = (JSON.parse(web_data.read)).to_a
          # Check to see if the requested weather file is on the list
          zip_name = weather_files.find{ |weather_file| weather_file.match(weather_loc) }
          # If the weather file is on the list proceed, otherwise report that it could not be found
          unless zip_name.nil?
            # Found the weather file on the list
            # Define the full url of the weather zip file we want to download
            if btap_weather
              save_file_url = download_folder + zip_name
            else
              # Used to resolve the Climate.OneBuilding.Org download link from using just the filename.
              abbreviation_map = {
                'AB' => 'AB_Alberta/',
                'BC' => 'BC_British_Columbia/',
                'MB' => 'MB_Manitoba/',
                'NB' => 'NB_New_Brunswick/',
                'NL' => 'NL_Newfoundland_and_Labrador/',
                'NS' => 'NS_Nova_Scotia/',
                'NT' => 'NT_Northwest_Territories/',
                'NU' => 'NU_Nunavut/',
                'ON' => 'ON_Ontario/',
                'PE' => 'PE_Prince_Edward_Island/',
                'QC' => 'QC_Quebec/',
                'SK' => 'SK_Saskatchewan/',
                'YT' => 'YT_Yukon/'
              }
              save_file_url = download_folder + abbreviation_map[zip_name[4..5]] + zip_name
            end
            # Define the local location of where the weather zip file will be saved
            weather_dir = File.absolute_path(File.join(__FILE__, '..', '..', '..', '..', '..' , '..', "data/weather"))
            save_file = File.join(weather_dir, zip_name)
            attemptb = 1
            # Try to download the weather file up to 5 times, waiting 5 seconds between each attempt.
            until attemptb > 5
              begin
                puts "Beginning attempt #{attemptb} to download #{save_file_url}"
                # Download the weather zip file from the repository
                URI.open(save_file_url) do |file_url|
                  if file_url.size <= 100
                    raise("Could not read #{save_file_url}!")
                  end
                  # Save the zip file in the /data/weather folder
                  File.open(save_file, 'wb') { |f| f.write(file_url.read) }
                  puts "Downloaded #{save_file_url} to #{save_file}"
                  # Extract the individual weother files from the zip file
                  status = extract_weather_data(zipped_file: save_file, weather_dir: weather_dir)
                end
                attemptb = 10
              rescue
                sleep(30)
                attemptb += 1
              end
            end
          end
        end
        attempt = 10
      rescue
        sleep(30)
        attempt += 1
      end
    end
    return status
  end

  # This method checks if a zip file containing weather data is stored in an external directory.  If it is, then it
  # checks if the name of the zip file (without extension) matches the name of the desired epw file (without extension).
  # If it does then it copies the zip file to the openstudio-standards weather directory and expands the file.
  # Presumably the zip file contains the .ddy, .epw, and .stat files needed by the rest of BTAP.  If no appropriate
  # weather zip files are present in the external directory then the method returns false.
  # Arguments:
  # epw_file (string): The name of the .epw file that BTAP will use.
  # weather_folder (string): The path to the openstudio-standards weather folder.
  # custom_weather_folder (string): The path to the external folder presumably containing the weather data zip file.
  def check_datapoint_weather_folder(epw_file:, weather_folder:, custom_weather_folder: nil)
    # Check if the external weather directory exists and return false if there isn't one
    return false if custom_weather_folder.nil?
    # Check if there are any zip files in the external weather directory and return false if there isn't any.
    zip_search_term = File.join(custom_weather_folder.to_s, '*.zip')
    zip_files = Dir[zip_search_term]
    return false if zip_files.empty?
    # Look for a zip file in the external directory named after the .epw file.  If there isn't one return false.
    weather_loc = epw_file[0..-5]
    weather_zip = weather_loc + '.zip'
    zip_find = zip_files.select{ |check_file | File.basename(check_file).to_s.downcase == weather_zip.to_s.downcase }
    return false if zip_find.empty?
    # Copy the zip file we want from the external weather directory to the openstudio-standards weather directory and
    # extract the weather data in the file.
    puts "Copying: #{zip_find[0]} from the btap_cli weather folder to the openstudio-standards weather folder: #{weather_folder}"
    FileUtils.cp(zip_find[0], weather_folder)
    dest_zip = File.join(weather_folder, weather_zip)
    # Return true if everything goes well.
    return extract_weather_data(zipped_file: dest_zip, weather_dir: weather_folder)
  end

  # This method extracts data from a zip file.  The name implies it is to be used for zip files containing weather
  # data but really it can be used to extract any zip file.
  # Arguments:
  # zipped_file (string): As the name implies, this is the name and path to the zip file we want to expand.
  # weather_dir (string): This is the folder where the zipped files will be extracted to.  Don't let the name fool you.
  #                       it can be any folder not just a weather directory.
  def extract_weather_data(zipped_file:, weather_dir:)
    # Set a flag to check if the weather data is for future weather.
    future_file = false

    # Data structure to determine if the weather file contains all necessary elements.
    checklist = {'.epw' => false, '.stat' => false, '.ddy' => false}
    # Start expanding the data.
    Zip::File.open(zipped_file) do |zip_file|
      puts "Expanding #{zipped_file}"
      # Cycle through each file in the zip file
      zip_file.each do |entry|
        # Define the location of where the file will be saved locally
        curr_save_file = File.join(weather_dir, entry.name.to_s)
        puts "Extracting #{entry.name} to #{curr_save_file}"
        # Check if the file includes a '_ASHRAE.ddy' term.  If there is, later on we will rename the '_ASHRAE.ddy' file
        # to just '.ddy'. This is so the rest of BTAP uses the _ASHRAE.ddy file.
        entry_name = entry.name.to_s
        if entry_name.length > 11
          future_file = true if entry_name.end_with?('_ASHRAE.ddy')
        end
        # entry.extract # This was required before but now it isn't.  I'm confused so am saving this comment to
        # remind me if there are problems later.
        # Read the data from the file
        content = entry.get_input_stream.read
        # Save the data locally
        File.open(curr_save_file, 'wb') { |save_f| save_f.write(content) }

        # Add the file extension of the current entry to the checklist.
        file_extension = entry_name[entry_name.rindex('.')..]
        if checklist.key?(file_extension)
          checklist[file_extension] = true
        end
      end
    end
    if future_file
      # Rename the non ASHRAE.ddy as '_non_ASHRAE.ddy' and save the '_ASHRAE.ddy' as the regular '.ddy' file.  This is
      # because the ASHRAE .ddy file includes sizing information not included in the regular .ddy file for future
      # weather data files.  Unfortunately, openstudio-standards just looks for the regular .ddy file for sizing
      # information which is why the switch is done.
      weather_loc = (File.basename(zipped_file).to_s)[0..-5]
      puts "Renaming #{weather_loc}.ddy as #{weather_loc}_orig.ddy and #{weather_loc}_ASHRAE.ddy as #{weather_loc}.ddy."
      puts "This is so that the design weather information in the #{weather_loc}_ASHRAE.ddy file is used."
      orig_ddy_name = File.join(weather_dir, (weather_loc + ".ddy"))
      ashrae_ddy_name = File.join(weather_dir, (weather_loc + "_ASHRAE.ddy"))
      rev_ddy_name = File.join(weather_dir, (weather_loc + "_orig.ddy"))
      FileUtils.cp(orig_ddy_name, rev_ddy_name)
      FileUtils.cp(ashrae_ddy_name, orig_ddy_name)
    end

    # Return false if not all files are present:
    if !checklist.values.all?()
      puts "Error: Not all files present in #{zipped_file}. Missing #{checklist.select { |k, v| v == false}.keys.join(", ") } file(s). Exiting..."
      exit(1)
    end

    # Return true if everything worked out
    return true
  end

  # This method is defined and used by the vintage classes to address he issue with the heat pump fuel types.  This
  # method does nothing when creating NECB reference buildings.
  def validate_primary_heating_fuel(primary_heating_fuel:, model:)
    if primary_heating_fuel.to_s.downcase == 'defaultfuel' || primary_heating_fuel.to_s.downcase == 'necb_default'
      epw = OpenStudio::EpwFile.new(model.weatherFile.get.path.get)
      default_fuel = @standards_data['regional_fuel_use'].detect { |fuel_sources| fuel_sources['state_province_regions'].include?(epw.stateProvinceRegion) }['fueltype_set']
      if default_fuel.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.swh', "Could not find a default fuel for #{epw.stateProvinceRegion}.  Using Electricity as the fuel type instead.")
        return 'Electricity'
      end
      return default_fuel
    end
    return primary_heating_fuel
  end

  # This method expects a string with the following pattern:  number-number
  # The first number is the percent of the total capacity that the primary boiler's capacity will be set to.
  # The second number is the percent of the total capacity that the secondary boiler's capacity will be set to.
  # If no boiler_cap_ratio is provided the the primary boiler will have its capacity set to 75% of the total and the
  # secondary boiler will have its capacity set to 25% of the total.  If a boiler_cap_ratio is set to '0_0' then the
  # NECB default capacities are assigned.
  def set_boiler_cap_ratios(boiler_cap_ratio:, boiler_fuel:)
    # Rules if boiler_fuel is defined
    unless boiler_fuel.nil?
      # Set the NECB default boiler capacities if the boiler_cap_ratio is set to '0-0'
      if boiler_cap_ratio == '0-0'
        boiler_cap_ratios = {
          primary_ratio: nil,
          secondary_ratio: nil
        }
        return boiler_cap_ratios
      elsif !boiler_fuel.to_s.downcase.include?('backup') && boiler_cap_ratio.nil?
        # Set the NECB default boiler capacities if the boiler_cap_ratio in not defined and the boiler fuel type is set
        # and the primary and secondary fuel types are the same.
        boiler_cap_ratios = {
          primary_ratio: nil,
          secondary_ratio: nil
        }
        return boiler_cap_ratios
      end
    end
    # Assuming the above rules do not apply, set the default boiler capacity ratio to 75% for the primary boiler and 25%
    # for the secondary boiler
    if boiler_cap_ratio.nil?
      boiler_cap_ratios = {
        primary_ratio: 0.75,
        secondary_ratio: 0.25
      }
      return boiler_cap_ratios
    end
    # If you defined the boiler capacity ratios set them accordingly.
    # Split the capacity ratio using the '-' symbol
    string_ratios = boiler_cap_ratio.to_s.split('-')
    # Turn the percentages into fractions
    primary_ratio = string_ratios[0].to_f/100.0
    secondary_ratio = string_ratios[1].to_f/100.0
    # Set the hash containg the ratios and return
    boiler_cap_ratios = {
      primary_ratio: primary_ratio,
      secondary_ratio: secondary_ratio
    }
    return boiler_cap_ratios
  end

  # Until someone has time to allow dwelling units, washrooms, cooridors, and storage rooms can get their own custom
  # system types (beyond the default necb_system), this metod will set the system type for those rooms to either be
  # their default or to the primary system type (if one is defined and the other sytems are not set to default)
  def reset_hvac_system_if_required(hvac_system_primary: nil, hvac_system_dwelling_units: nil, hvac_system_corridor: nil, hvac_system_storage: nil, hvac_system_washrooms: nil)
    if hvac_system_primary.nil? || hvac_system_primary.to_s.downcase == "necb_default"
      hvac_system_dwelling_units = "NECB_Default"
      hvac_system_corridor = "NECB_Default"
      hvac_system_storage = "NECB_Default"
      hvac_system_washrooms = "NECB_Default"
    else
      hvac_system_dwelling_units = hvac_system_primary unless hvac_system_dwelling_units.nil? || hvac_system_dwelling_units.to_s.downcase == "necb_default"
      hvac_system_corridor = hvac_system_primary unless hvac_system_corridor.nil? || hvac_system_corridor.to_s.downcase == "necb_default"
      hvac_system_storage = hvac_system_primary unless hvac_system_storage.nil? || hvac_system_storage.to_s.downcase == "necb_default"
      hvac_system_washrooms = hvac_system_primary unless hvac_system_washrooms.nil? || hvac_system_washrooms.to_s.downcase == "necb_default"
    end
    return hvac_system_dwelling_units, hvac_system_corridor, hvac_system_storage, hvac_system_washrooms
  end

  # This method checks if the output_meters argument contains a net electricity meter with 'timestep' frequency.  If one
  # is then the method does nothing.  If one is not then it is added.  This is used in conjunction with the
  # 'oerd_utility_pricing' argument.  If that argument is present then a net electricity meter with 'timestep' frequency
  # is required to determine the peak net electricity usage.
  def check_output_meters(output_meters: nil)
    if output_meters.nil?
      output_meters = [
        {
          "name" => "ElectricityNet:Facility",
          "frequency" => "Hourly"
        },
        {
          "name" => "Heating:Electricity",
          "frequency" => "Hourly"
        },
        {
          "name" => "WaterSystems:Electricity",
          "frequency" => "Hourly"
        }
      ]
    else
      electnet_facility = output_meters.select { |output_meter| (output_meter["name"].to_s.downcase == "electricitynet:facility") && (output_meter["frequency"].to_s.downcase == "hourly") }
      if electnet_facility.empty?
        output_meters << {
          "name" => "ElectricityNet:Facility",
          "frequency" => "Hourly"
        }
      end
      heating_elec = output_meters.select { |output_meter| (output_meter["name"].to_s.downcase == "heating:electricity") && (output_meter["frequency"].to_s.downcase == "hourly") }
      if electnet_facility.empty?
        output_meters << {
          "name" => "Heating:Electricity",
          "frequency" => "Hourly"
        }
      end
      watersys_elec = output_meters.select { |output_meter| (output_meter["name"].to_s.downcase == "watersystems:electricity") && (output_meter["frequency"].to_s.downcase == "hourly") }
      if electnet_facility.empty?
        output_meters << {
          "name" => "WaterSystems:Electricity",
          "frequency" => "Hourly"
        }
      end
    end
    return output_meters
  end

  # This method is used to do a sizing run on the model.  It will return true if the sizing run was successful and
  # will generate an error if it was not.  The method will also resize any DX heating coils that have a capacity less than 1.0 kW to
  # 1.0 kW and rerun the sizing run until it succeeds or the sizing run continues to fail.
  #
  # Arguments:
  # model (OpenStudio::Model::Model): The model to run the sizing run on.
  # sizing_run_dir (String): The directory where the sizing run files will be saved.
  def try_sizing_run(model:, sizing_run_dir:, sizing_run_subdir:)
    raise('validation of model failed.') unless validate_initial_model(model)

    # Do a sizing run to determine the system capacities.  If a sizing run fails, hard size any failing DX heating coils
    # to 1.0 kW and rerun the sizing run until it succeeds.  If no DX heating coils are found, or none had a small
    # capacity then raise an error.
    loop do
      sizing_run_success = model_run_sizing_run(model, "#{sizing_run_dir}/#{sizing_run_subdir}", true)
      break if sizing_run_success

      # Sizing run failed, check all DX heating coils and set their size to 1 if less than 1
      dx_coil_changed = false

      model.getCoilHeatingDXSingleSpeeds.each do |coil|
        autosized_capacity = coil.autosizedRatedTotalHeatingCapacity
        if autosized_capacity.is_initialized && autosized_capacity.get < 1.0
          coil.setRatedTotalHeatingCapacity(1.0)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC',  "DX Heating Coil #{coil.name.to_s} has a rated capacity less than 1.0 kW and has been resized to 1.0 kW to avoid sizing run failure.")
          puts "DX Heating Coil #{coil.name.to_s} has a rated capacity less than 1.0 kW and has been resized to 1.0 kW to avoid sizing run failure."
          dx_coil_changed = true
        end
      end
      model.getCoilHeatingDXMultiSpeeds.each do |coil|
        coil.stages.each do |stage|
          autosized_capacity = stage.autosizedGrossRatedHeatingCapacity
          if autosized_capacity.is_initialized && autosized_capacity.get < 1.0
            stage.setGrossRatedHeatingCapacity(1.0)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC',  "A DX Heating Coil #{coil.name.to_s} stage has a rated capacity less than 1.0 kW and has been resized to 1.0 kW to avoid sizing run failure.")
            puts "A DX Heating Coil #{coil.name.to_s} stage has a rated capacity less than 1.0 kW and has been resized to 1.0 kW to avoid sizing run failure."
            dx_coil_changed = true
          end
        end
      end

      # If no DX coil was changed, break loop and raise error
      if !dx_coil_changed
        raise("sizing run failed! check #{sizing_run_dir}/#{sizing_run_subdir} (DX coil sizes adjusted, but no further changes possible)")
      end
      puts "Rerunning sizing run after adjusting DX heating coil capacity to 1.0 kW."
      # Otherwise, loop will rerun sizing
    end
  end
end
