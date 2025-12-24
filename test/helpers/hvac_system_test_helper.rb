# A set of methods for testing hvac system methods

# write errors to a log file
def log_hvac_test_errors(errs)
  File.open("#{__dir__}/../os_stds_methods/output/test_add_hvac_systems.log", 'a') do |file|
    errs.each { |err| file.puts(err) }
  end
end

# default hash for hvac tests
def default_hvac_test_hash
  # example hash for an HVAC system type test
  # default optional arguments should match those in model_add_hvac_system
  default_hash = {template: '90.1-2013',
                  model_test_name: nil,
                  model_name: 'basic_2_story_office_no_hvac_60WWR',
                  climate_zone: 'ASHRAE 169-2013-7A',
                  system_type: nil,
                  main_heat_fuel: nil,
                  zone_heat_fuel: nil,
                  cool_fuel: nil,
                  zone_selection: 'all',
                  hot_water_loop_type: nil,
                  chilled_water_loop_cooling_type: nil,
                  heat_pump_loop_cooling_type: nil,
                  air_loop_heating_type: nil,
                  air_loop_cooling_type: nil,
                  zone_equipment_ventilation: nil,
                  unmet_hrs_htg: 300.0,
                  unmet_hrs_clg: 300.0}
  return default_hash
end

# Runs an hvac test given an input model name and HVAC argument values
# Uses the default hash above
#
# @param hvac_arguments [Hash] a hash
def model_hvac_test(hvac_arguments)
  # Make the output directory if it doesn't exist
  output_dir = "#{__dir__}/../os_stds_methods/output"
  FileUtils.mkdir output_dir unless Dir.exist? output_dir

  reset_log
  errs = []

  hash = default_hvac_test_hash.merge(hvac_arguments)
  template = hash[:template]
  model_test_name = hash[:model_test_name]
  model_name = hash[:model_name]
  climate_zone = hash[:climate_zone]
  system_type = hash[:system_type]
  main_heat_fuel = hash[:main_heat_fuel]
  zone_heat_fuel = hash[:zone_heat_fuel]
  cool_fuel = hash[:cool_fuel]
  zone_selection = hash[:zone_selection]
  hot_water_loop_type = hash[:hot_water_loop_type]
  chilled_water_loop_cooling_type = hash[:chilled_water_loop_cooling_type]
  heat_pump_loop_cooling_type = hash[:heat_pump_loop_cooling_type]
  air_loop_heating_type = hash[:air_loop_heating_type]
  air_loop_cooling_type = hash[:air_loop_cooling_type]
  zone_equipment_ventilation = hash[:zone_equipment_ventilation]
  unmet_hrs_htg = hash[:unmet_hrs_htg]
  unmet_hrs_clg = hash[:unmet_hrs_clg]

  standard = Standard.build(template)
  if model_test_name.nil?
    model_test_name = system_type.gsub(' ', '_')
  end
  model_dir = "#{output_dir}/hvac_#{model_test_name}"

  # Load the model if already created
  annual_run_success = false
  if File.exist?("#{model_dir}/AR/run/eplusout.sql")
    puts "test: '#{model_test_name}' results already available. Not re-rerunning energy simulation."
    model = OpenStudio::Model::Model.new
    sql = OpenstudioStandards::SqlFile.sql_file_safe_load("#{model_dir}/AR/run/eplusout.sql")
    model.setSqlFile(sql)
    annual_run_success = true
  end

  # If not created, make and run annual simulation
  unless annual_run_success
    puts "test: '#{model_test_name}' results not available. Running energy simulation."
    # Load the test model
    model_path = "#{__dir__}/../os_stds_methods/models/#{model_name}.osm"
    model = standard.safe_load_model(model_path)
    unless model
      raise "ERROR: unable to load model: #{model_path}. Check that it is a valid path."
    end

    # Assign a weather file
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    zones = model.getThermalZones
    heated_and_cooled_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
    heated_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) }
    cooled_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
    cooled_only_zones = zones.select { |zone| !OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
    heated_only_zones = zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && !OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone) }
    system_zones = heated_and_cooled_zones + cooled_only_zones
    case zone_selection
    when 'heated_zones'
        zones = heated_zones
    when 'cooled_zones'
        zones = cooled_zones
    when 'heated_only_zones'
        zones = heated_only_zones
    when 'cooled_only_zones'
        zones = cooled_only_zones
    else # 'all'
        zones = system_zones
    end

    # Add the HVAC
    added_hvac = OpenstudioStandards::HVAC.model_add_hvac_system(model, system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                hot_water_loop_type: hot_water_loop_type,
                                                chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                air_loop_heating_type: air_loop_heating_type,
                                                air_loop_cooling_type: air_loop_cooling_type,
                                                zone_equipment_ventilation: zone_equipment_ventilation)

    unless added_hvac
      errs << "Unable to apply hvac constructor for system type '#{system_type}' to model #{model_test_name}."
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end

    # Save the model
    model.save("#{model_dir}/final.osm", true)

    # Perform a sizing run
    sizing_run_success = standard.model_run_sizing_run(model, "#{model_dir}/SR")
    unless sizing_run_success
      errs << "#{model_test_name} sizing run failed"
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end

    # Check the conditioned floor area
    if model.building.get.conditionedFloorArea.get.zero?
      errs << "Test model #{model_test_name} has no conditioned area."
      log_hvac_test_errors(errs)
      return errs
    end

    # If there are any multizone systems, reset damper positions
    # to achieve a 60% ventilation effectiveness minimum for the system
    # following the ventilation rate procedure from 62.1
    standard.model_apply_multizone_vav_outdoor_air_sizing(model)

    # Apply the prototype HVAC assumptions
    standard.model_apply_prototype_hvac_assumptions(model, '', climate_zone)

    # Apply the HVAC efficiency standard
    apply_efficiency_success = standard.model_apply_hvac_efficiency_standard(model, climate_zone)
    unless apply_efficiency_success
      errs << "Failed to apply standard efficiencies after sizing run for model #{model_test_name}"
      errs << "#{apply_efficiency_success}"
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end

    # Run the annual run
    annual_run_success = standard.model_run_simulation_and_log_errors(model, "#{model_dir}/AR")
    unless annual_run_success
      errs << "For #{model_test_name} annual run failed" unless annual_run_success
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end
  end

  # Check unmet hours
  unmet_heating_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours(model)
  unmet_cooling_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours(model)
  unmet_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(model)
  if unmet_hrs
    if unmet_heating_hrs > unmet_hrs_htg
      errs << "Model #{model_test_name} has #{unmet_heating_hrs.round(1)} unmet occupied heating hours, more than the expected limit of #{unmet_hrs_htg}."
    end
    if unmet_cooling_hrs > unmet_hrs_clg
      errs << "Model #{model_test_name} has #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours, more than the expected limit of #{unmet_hrs_clg}."
    end
  else
    errs << "Could not determine unmet hours for model #{model_test_name}.  Simulation may have failed."
  end
  log_hvac_test_errors(errs)
  log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)

  # @todo add checks for hvac enduse euis, ventilation unmet hours
  return errs
end

# Runs individual model hvac tests for an array of hvac test hashes
#
# @param test_set [Array] an array of test hashes
def group_hvac_test(test_set)
  group_errs = []
  test_set.each do |test_hash|
    errs = model_hvac_test(test_hash)
    group_errs << errs unless errs.empty?
  end
  assert(group_errs.size == 0, group_errs.join("\n"))
end

# default hash for radiant system tests
def default_radiant_test_hash
  # example hash for an HVAC system type test
  # default optional arguments should match those in model_add_low_temp_radiant
  default_hash = {two_pipe_system: false,
                  two_pipe_control_strategy: 'outdoor_air_lockout',
                  two_pipe_lockout_temperature: 65.0,
                  plant_supply_water_temperature_control: false,
                  plant_supply_water_temperature_control_strategy: 'outdoor_air',
                  hwsp_at_oat_low: 120,
                  hw_oat_low: 55,
                  hwsp_at_oat_high: 80,
                  hw_oat_high: 70,
                  chwsp_at_oat_low: 70,
                  chw_oat_low: 65,
                  chwsp_at_oat_high: 55,
                  chw_oat_high: 75,
                  radiant_type: 'floor',
                  radiant_temperature_control_type: 'SurfaceFaceTemperature',
                  radiant_setpoint_control_type: 'ZeroFlowPower',
                  include_carpet: true,
                  carpet_thickness_in: 0.25,
                  control_strategy: 'proportional_control',
                  use_zone_occupancy_for_control: true,
                  occupied_percentage_threshold: 0.10,
                  model_occ_hr_start: 6.0,
                  model_occ_hr_end: 18.0,
                  proportional_gain: 0.3,
                  switch_over_time: 24.0,
                  radiant_availability_type: 'precool',
                  radiant_lockout: false,
                  radiant_lockout_start_time: 12.0,
                  radiant_lockout_end_time: 20.0}
  return default_hash
end

def model_radiant_system_test(arguments)
  output_dir = "#{__dir__}/../os_stds_methods/output"
  FileUtils.mkdir output_dir unless Dir.exist? output_dir

  reset_log
  errs = []

  # merge arugments with default hashes
  hash = default_hvac_test_hash.merge(default_radiant_test_hash)
  hash = hash.merge(arguments)

  # hash arguments defaulted in default_hvac_test_hash
  template = hash[:template]
  model_test_name = hash[:model_test_name]
  model_name = hash[:model_name]
  climate_zone = hash[:climate_zone]
  unmet_hrs_htg = hash[:unmet_hrs_htg]
  unmet_hrs_clg = hash[:unmet_hrs_clg]

  # hash arguments defined in default_radiant_test_hash
  two_pipe_system = hash[:two_pipe_system]
  two_pipe_control_strategy = hash[:two_pipe_control_strategy]
  two_pipe_lockout_temperature = hash[:two_pipe_lockout_temperature]
  plant_supply_water_temperature_control = hash[:plant_supply_water_temperature_control]
  plant_supply_water_temperature_control_strategy = hash[:plant_supply_water_temperature_control_strategy]
  hwsp_at_oat_low = hash[:hwsp_at_oat_low]
  hw_oat_low = hash[:hw_oat_low]
  hwsp_at_oat_high = hash[:hwsp_at_oat_high]
  hw_oat_high = hash[:hw_oat_high]
  chwsp_at_oat_low = hash[:chwsp_at_oat_low]
  chw_oat_low = hash[:chw_oat_low]
  chwsp_at_oat_high = hash[:chwsp_at_oat_high]
  chw_oat_high = hash[:chw_oat_high]
  radiant_type = hash[:radiant_type]
  radiant_temperature_control_type = hash[:radiant_temperature_control_type]
  radiant_setpoint_control_type = hash[:radiant_setpoint_control_type]
  include_carpet = hash[:include_carpet]
  carpet_thickness_in = hash[:carpet_thickness_in]
  use_zone_occupancy_for_control = hash[:use_zone_occupancy_for_control]
  occupied_percentage_threshold = hash[:occupied_percentage_threshold]
  model_occ_hr_start = hash[:model_occ_hr_start]
  model_occ_hr_end = hash[:model_occ_hr_end]
  control_strategy = hash[:control_strategy]
  proportional_gain = hash[:proportional_gain]
  switch_over_time = hash[:switch_over_time]
  radiant_availability_type= hash[:radiant_availability_type]
  radiant_lockout=  hash[:radiant_lockout]
  radiant_lockout_start_time = hash[:radiant_lockout_start_time]
  radiant_lockout_end_time = hash[:radiant_lockout_end_time]

  standard = Standard.build(template)
  if model_test_name.nil?
    model_test_name = 'default_radiant_controls_test_name'
  else
    model_test_name = model_test_name.gsub(' ', '_')
  end
  model_dir = "#{output_dir}/hvac_#{model_test_name}"

  # Load the model if already created
  annual_run_success = false
  if File.exist?("#{model_dir}/AR/run/eplusout.sql")
    puts "test: '#{model_test_name}' results already available. Not re-rerunning energy simulation."
    model = OpenStudio::Model::Model.new
    sql = OpenstudioStandards::SqlFile.sql_file_safe_load("#{model_dir}/AR/run/eplusout.sql")
    model.setSqlFile(sql)
    annual_run_success = true
  end

  # If not created, make and run annual simulation
  unless annual_run_success
    puts "test: '#{model_test_name}' results not available. Running energy simulation."
    # Load the test model
    model_path = "#{__dir__}/../os_stds_methods/models/#{model_name}.osm"
    model = standard.safe_load_model(model_path)
    unless model
      raise "ERROR: unable to load model: #{model_path}. Check that it is a valid path."
    end

    # Assign a weather file
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # create plant loops
    zones = model.getThermalZones
    hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, 'DistrictHeating', hot_water_loop_type: 'LowTemperature')
    chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, 'DistrictCooling', chilled_water_loop_cooling_type: 'WaterCooled')

    # add doas system for ventilation
    air_loop = OpenstudioStandards::HVAC.model_add_doas(model,
                                       zones,
                                       hot_water_loop: hot_water_loop,
                                       chilled_water_loop: chilled_water_loop)

    unless air_loop
      errs << "Failed to apply model_add_doas to model #{model_test_name}."
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end

    # add radiant system
    radiant_loops = OpenstudioStandards::HVAC.model_add_low_temp_radiant(model,
                                                        zones,
                                                        hot_water_loop,
                                                        chilled_water_loop,
                                                        two_pipe_system: two_pipe_system,
                                                        two_pipe_control_strategy: two_pipe_control_strategy,
                                                        two_pipe_lockout_temperature: two_pipe_lockout_temperature,
                                                        plant_supply_water_temperature_control: plant_supply_water_temperature_control,
                                                        plant_supply_water_temperature_control_strategy: plant_supply_water_temperature_control_strategy,
                                                        hwsp_at_oat_low: hwsp_at_oat_low,
                                                        hw_oat_low: hw_oat_low,
                                                        hwsp_at_oat_high: hwsp_at_oat_high,
                                                        hw_oat_high: hw_oat_high,
                                                        chwsp_at_oat_low: chwsp_at_oat_low,
                                                        chw_oat_low: chw_oat_low,
                                                        chwsp_at_oat_high: chwsp_at_oat_high,
                                                        chw_oat_high: chw_oat_high,
                                                        radiant_type: radiant_type,
                                                        radiant_temperature_control_type: radiant_temperature_control_type,
                                                        radiant_setpoint_control_type: radiant_setpoint_control_type,
                                                        include_carpet: include_carpet,
                                                        carpet_thickness_in: carpet_thickness_in,
                                                        use_zone_occupancy_for_control: use_zone_occupancy_for_control,
                                                        occupied_percentage_threshold: occupied_percentage_threshold,
                                                        model_occ_hr_start: model_occ_hr_start,
                                                        model_occ_hr_end: model_occ_hr_end,
                                                        control_strategy: control_strategy,
                                                        proportional_gain: proportional_gain,
                                                        switch_over_time: switch_over_time,
                                                        radiant_availability_type: radiant_availability_type,
                                                        radiant_lockout: radiant_lockout,
                                                        radiant_lockout_start_time: radiant_lockout_start_time,
                                                        radiant_lockout_end_time: radiant_lockout_end_time)

    unless radiant_loops
      errs << "Failed to apply model_add_low_temp_radiant to model #{model_test_name}."
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end

    # Save the model
    model.save("#{model_dir}/final.osm", true)

    # Perform a sizing run
    sizing_run_success = standard.model_run_sizing_run(model, "#{model_dir}/SR")
    unless sizing_run_success
      errs << "#{model_test_name} sizing run failed"
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end

    # Run the annual run
    annual_run_success = standard.model_run_simulation_and_log_errors(model, "#{model_dir}/AR")
    unless annual_run_success
      errs << "For #{model_test_name} annual run failed" unless annual_run_success
      log_hvac_test_errors(errs)
      log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)
      return errs
    end
  end

  # Check unmet hours
  unmet_heating_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours(model)
  unmet_cooling_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours(model)
  unmet_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(model)
  if unmet_hrs
    if unmet_heating_hrs > unmet_hrs_htg
      errs << "Model #{model_test_name} has #{unmet_heating_hrs.round(1)} unmet occupied heating hours, more than the expected limit of #{unmet_hrs_htg}."
    end
    if unmet_cooling_hrs > unmet_hrs_clg
      errs << "Model #{model_test_name} has #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours, more than the expected limit of #{unmet_hrs_clg}."
    end
  else
    errs << "Could not determine unmet hours for model #{model_test_name}.  Simulation may have failed."
  end
  log_hvac_test_errors(errs)
  log_messages_to_file("#{model_dir}/openstudio-standards.log", debug=false)

  # @todo add checks for hvac enduse euis, ventilation unmet hours
  return errs
end