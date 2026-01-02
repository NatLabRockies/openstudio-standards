
def load_test_model(model_name)

  # Load the test model
  translator = OpenStudio::OSVersion::VersionTranslator.new
  path = OpenStudio::Path.new("#{File.dirname(__FILE__)}/models/#{model_name}.osm")
  model = translator.loadModel(path)
  assert(model.is_initialized, "Could not load test model '#{model_name}.osm' from /models.  Check name for typos.")
  model = model.get

  return model

end

def create_baseline_model(model_name, standard, climate_zone, building_type, custom = nil, debug = false, load_existing_model = true)

  # Get the name of the test that is calling this method and append it to the
  # model name.  This prevents race conditions when running tests in parallel.
  caller_test_name = caller_locations.first.label
  test_specific_model_name = "#{model_name}_#{caller_test_name}"

  # If requested, first attempt to load baseline model
  # from file instead of recreating it.
  model = nil
  if load_existing_model
    model = load_baseline_model(test_specific_model_name, standard, climate_zone, building_type, custom, debug)
  end

  # If the existing model was loaded, return that
  if model
    return model
  end

  # Make a directory to save the resulting models
  test_dir = "#{File.dirname(__FILE__)}/output"
  if !Dir.exist?(test_dir)
    Dir.mkdir(test_dir)
  end

  model = load_test_model(model_name)

  # @todo see weather module for weather file locations for each climate zone
  base_rel_path = '../../../data/weather/'
  if model.weatherFile.empty?
    epw_name = nil
    case climate_zone
      when 'ASHRAE 169-2006-1A', 'ASHRAE 169-2013-1A'
        epw_name = 'USA_FL_Miami.Intl.AP.722020_TMY3.epw'
      when 'ASHRAE 169-2006-1B', 'ASHRAE 169-2013-1B'
        epw_name = 'USA_AZ_Phoenix-Sky.Harbor.Intl.AP.722780_TMY3.epw'
      when 'ASHRAE 169-2006-2A', 'ASHRAE 169-2013-2A'
        epw_name = 'USA_TX_Houston-Bush.Intercontinental.AP.722430_TMY3.epw'
      when 'ASHRAE 169-2006-2B', 'ASHRAE 169-2013-2B'
        epw_name = 'USA_AZ_Phoenix-Sky.Harbor.Intl.AP.722780_TMY3.epw'
      when 'ASHRAE 169-2006-3A', 'ASHRAE 169-2013-3A'
        epw_name = 'USA_TN_Memphis.Intl.AP.723340_TMY3.epw'
      when 'ASHRAE 169-2006-3B', 'ASHRAE 169-2013-3B'
        epw_name = 'USA_TX_El.Paso.Intl.AP.722700_TMY3.epw'
      when 'ASHRAE 169-2006-3C', 'ASHRAE 169-2013-3C'
        epw_name = 'USA_CA_San.Francisco.Intl.AP.724940_TMY3.epw'
      when 'ASHRAE 169-2006-4A', 'ASHRAE 169-2013-4A'
        epw_name = 'USA_MD_Baltimore-Washington.Intl.AP.724060_TMY3.epw'
      when 'ASHRAE 169-2006-4B', 'ASHRAE 169-2013-4B'
        epw_name = 'USA_NM_Albuquerque.Intl.AP.723650_TMY3.epw'
      when 'ASHRAE 169-2006-4C', 'ASHRAE 169-2013-4C'
        epw_name = nil # WA-Seattle
      when 'ASHRAE 169-2006-5A', 'ASHRAE 169-2013-5A'
        epw_name = 'USA_IL_Chicago-OHare.Intl.AP.725300_TMY3.epw'
      when 'ASHRAE 169-2006-5B', 'ASHRAE 169-2013-5B'
        epw_name = nil # CO Boulder
      when 'ASHRAE 169-2006-5C', 'ASHRAE 169-2013-5C'
        epw_name = nil
      when 'ASHRAE 169-2006-6A', 'ASHRAE 169-2013-6A'
        epw_name = nil # MN-Minneapolis
      when 'ASHRAE 169-2006-6B', 'ASHRAE 169-2013-6B'
        epw_name = 'USA_MT_Helena.Rgnl.AP.727720_TMY3.epw'
      when 'ASHRAE 169-2006-7A', 'ASHRAE 169-2013-7A'
        epw_name = 'USA_MN_Duluth.Intl.AP.727450_TMY3.epw'
      when 'ASHRAE 169-2006-7B', 'ASHRAE 169-2013-7B'
        epw_name = nil
      when 'ASHRAE 169-2006-8A' 'ASHRAE 169-2013-8A'
        epw_name = 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw'
      when 'ASHRAE 169-2006-8B', 'ASHRAE 169-2013-8B'
        epw_name = nil
      else
        puts "No Weather file set, and CANNOT locate #{climate_zone}"
        return [false, ["No Weather file set, and CANNOT locate #{climate_zone}"]]
    end
    if epw_name.nil?
      puts "No Weather file set, and CANNOT locate #{climate_zone}"
    else
      rel_path = base_rel_path + epw_name
      weather_file_path =  File.expand_path(rel_path, __FILE__)
      # set the weather file to the model
      success = OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      if success
        puts "Set Weather file to '#{weather_file_path}'"
      else
        puts "Failed to set the weather file"
        return [false, ["Failed to set the weather file"]]
      end
    end
  else # Weather file is set
    # Make sure the weather file is where it says
    epw_path = model.weatherFile.get.path
    if epw_path.is_initialized
      epw_path_string = epw_path.get.to_s
      puts "path string = #{epw_path_string}"
      unless File.exist?(epw_path_string)
        epw_name = File.basename(epw_path_string)
        rel_path = base_rel_path + epw_name
        weather_file_path = File.expand_path(rel_path, __FILE__)
        # set the weather file to the model
        success = OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
        if success
          puts "Set Weather file to '#{weather_file_path}'"
        else
          puts "Failed to set the weather file"
          return [false, ["Failed to set the weather file"]]
        end
      end
    end
  end

  # Create a directory for the test result
  osm_directory = "#{test_dir}/#{test_specific_model_name}-#{standard}-#{climate_zone}-#{custom}"
  if !Dir.exist?(osm_directory)
    Dir.mkdir(osm_directory)
  end

  # Open a channel to log info/warning/error messages
  msg_log = OpenStudio::StringStreamLogSink.new
  if debug
    msg_log.setLogLevel(OpenStudio::Debug)
  else
    msg_log.setLogLevel(OpenStudio::Info)
  end

  # Create the baseline model from the
  # supplied proposed test model
  standard = Standard.build(standard)

  # run sizing - due to the model uses layer by layer approach to define a window, the lack or incorrect
  # uFactor calculation without running Eplus causes error in the space conditioning category function
  # therefore, we force to run a sizing run.
  sizing_run_test_files = ['bldg_11', 'bldg_17']
  if sizing_run_test_files.include?(model_name)
    unless standard.model_run_sizing_run(model, "#{osm_directory}/PROPOSED")
      return false
    end
  end
  standard.model_create_prm_baseline_building(model, building_type, climate_zone, custom, osm_directory, debug)

  # Show the output messages
  errs = []

  # Log the messages to file for easier review
  log_name = "create_baseline.log"
  log_file_path = "#{osm_directory}/#{log_name}"
  messages = log_messages_to_file(log_file_path, debug)

  msg_log.logMessages.each do |msg|
    # DLM: you can filter on log channel here for now
    if /openstudio.*/.match(msg.logChannel) #/openstudio\.model\..*/
      # Skip certain messages that are irrelevant/misleading
      next if msg.logMessage.include?("Skipping layer") || # Annoying/bogus "Skipping layer" warnings
          msg.logChannel.include?("runmanager") || # RunManager messages
          msg.logChannel.include?("setFileExtension") || # .ddy extension unexpected
          msg.logChannel.include?("Translator") || # Forward translator and geometry translator
          msg.logMessage.include?("UseWeatherFile") || # 'UseWeatherFile' is not yet a supported option for YearDescription
          msg.logMessage.include?("has multiple parents") || # Bogus errors about curves having multiple parents
          msg.logMessage.include?('Prior to OpenStudio 2.6.2, this field was returning a double, it now returns an Optional double') # Warning about OS API change

      # Report the message in the correct way
      if msg.logLevel == OpenStudio::Info
        puts(msg.logMessage)
      elsif msg.logLevel == OpenStudio::Warn
        puts("WARNING - [#{msg.logChannel}] #{msg.logMessage}")
      elsif msg.logLevel == OpenStudio::Error
        puts("ERROR - [#{msg.logChannel}] #{msg.logMessage}")
        errs << "ERROR - [#{msg.logChannel}] #{msg.logMessage}"
      elsif msg.logLevel == OpenStudio::Debug && debug
        puts("DEBUG - #{msg.logMessage}")
      end
    end
  end

  # Save the test model
  baseline_model_name = "baseline"
  model.save(OpenStudio::Path.new("#{osm_directory}/#{baseline_model_name}.osm"), true)

  # Assert no errors
  assert(errs.size == 0, "Model created, but had Errors: #{errs.join(',')}")

  # Run a sizing run for the baseline model
  # so that the sql matches the actual equipment names
  if standard.model_run_sizing_run(model, "#{osm_directory}/SRB") == false
    return false
  end

  return model

end

def load_baseline_model(model_name, standard, climate_zone, building_type, custom = nil, debug = false)

  # Get the test directory
  test_dir = "#{File.dirname(__FILE__)}/output"
  osm_directory = "#{test_dir}/#{model_name}-#{standard}-#{climate_zone}-#{custom}"
  if !Dir.exist?(osm_directory)
    return false
  end

  # Load the test model
  base_model_name = "baseline"
  translator = OpenStudio::OSVersion::VersionTranslator.new
  path = OpenStudio::Path.new("#{osm_directory}/#{base_model_name}.osm")
  model = translator.loadModel(path)
  if model.empty?
    return false
  else
    model = model.get
  end

  # Attach the sql file from the last sizing run
  sql_path_1x = OpenStudio::Path.new("#{osm_directory}/SRB/EnergyPlus/eplusout.sql")
  sql_path_2x = OpenStudio::Path.new("#{osm_directory}/SRB/run/eplusout.sql")
  if OpenStudio::exists(sql_path_1x)
    sql = OpenStudio::SqlFile.new(sql_path_1x)
    # Check to make sure the sql file is readable,
    # which won't be true if EnergyPlus crashed during simulation.
    if !sql.connectionOpen
      puts "The sizing run failed, cannot create model.  Look at the eplusout.err file in #{File.dirname(sql_path_1x.to_s)} to see the cause."
      return false
    end
    # Attach the sql file from the run to the model
    model.setSqlFile(sql)
  elsif OpenStudio::exists(sql_path_2x)
    sql = OpenStudio::SqlFile.new(sql_path_2x)
    # Check to make sure the sql file is readable,
    # which won't be true if EnergyPlus crashed during simulation.
    if !sql.connectionOpen
      puts "The sizing run failed, cannot create model.  Look at the eplusout.err file in #{File.dirname(sql_path_2x.to_s)} to see the cause."
      return false
    end
    # Attach the sql file from the run to the model
    model.setSqlFile(sql)
  else
    puts "Results for the sizing run couldn't be found here: #{sql_path_1x} or here: #{sql_path_2x}."
    return false
  end

  return model

end

