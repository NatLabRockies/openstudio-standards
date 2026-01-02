Standard.class_eval do
  # A set of methods to run the OpenStudio model

  # Runs an annual simulation
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param run_dir [String] file path location for the annual run, defaults to 'Run' in the current directory
  # @return [Boolean] returns true if successful, false if not
  def model_run_simulation_and_log_errors(model, run_dir = "#{Dir.pwd}/Run")
    # Make the directory if it doesn't exist
    FileUtils.mkdir_p(run_dir)

    # Save the model to energyplus idf
    idf_name = 'in.idf'
    osm_name = 'in.osm'
    osw_name = 'in.osw'
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
    forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
    idf = forward_translator.translateModel(model)
    idf_path = OpenStudio::Path.new("#{run_dir}/#{idf_name}")
    osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
    osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
    idf.save(idf_path, true)
    model.save(osm_path, true)

    # Set up the simulation
    # Find the weather file
    epw_path = OpenstudioStandards::Weather.model_get_full_weather_file_path(model)
    if epw_path.empty?
      return false
    end

    epw_path = epw_path.get

    # close current sql file
    model.resetSqlFile

    # If running on a regular desktop, use RunManager.
    # If running on OpenStudio Server, use WorkFlowMananger
    # to avoid slowdown from the run.
    use_runmanager = true

    begin
      workflow = OpenStudio::WorkflowJSON.new
      use_runmanager = false
    rescue NameError
      use_runmanager = true
    end

    sql_path = nil
    if use_runmanager
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Running with RunManager.')

      # Find EnergyPlus
      ep_dir = OpenStudio.getEnergyPlusDirectory
      ep_path = OpenStudio.getEnergyPlusExecutable
      ep_tool = OpenStudio::Runmanager::ToolInfo.new(ep_path)
      idd_path = OpenStudio::Path.new("#{ep_dir}/Energy+.idd")
      output_path = OpenStudio::Path.new("#{run_dir}/")

      # Make a run manager and queue up the run
      run_manager_db_path = OpenStudio::Path.new("#{run_dir}/run.db")
      # HACK: workaround for Mac with Qt 5.4, need to address in the future.
      OpenStudio::Application.instance.application(false)
      run_manager = OpenStudio::Runmanager::RunManager.new(run_manager_db_path, true, false, false, false)
      job = OpenStudio::Runmanager::JobFactory.createEnergyPlusJob(ep_tool,
                                                                   idd_path,
                                                                   idf_path,
                                                                   epw_path,
                                                                   output_path)

      run_manager.enqueue(job, true)

      # Start the run and wait for it to finish.
      while run_manager.workPending
        sleep 1
        OpenStudio::Application.instance.processEvents
      end

      sql_path = OpenStudio::Path.new("#{run_dir}/EnergyPlus/eplusout.sql")

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")

    else # method to running simulation within measure using OpenStudio 2.x WorkflowJSON

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Running with OS 2.x WorkflowJSON.')

      # Copy the weather file to this directory
      epw_name = 'in.epw'
      begin
        FileUtils.copy(epw_path.to_s, "#{run_dir}/#{epw_name}")
      rescue StandardError
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Due to limitations on Windows file path lengths, this measure won't work unless your project is located in a directory whose filepath is less than 90 characters long, including slashes.")
        return false
      end

      workflow.setSeedFile(osm_name)
      workflow.setWeatherFile(epw_name)
      workflow.saveAs(File.absolute_path(osw_path.to_s))

      # 'touch' the weather file - for some odd reason this fixes the simulation not running issue we had on openstudio-server.
      # Removed for until further investigation completed.
      # FileUtils.touch("#{run_dir}/#{epw_name}")

      cli_path = OpenStudio.getOpenStudioCLI
      cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
      # cmd = "\"#{cli_path}\" --verbose run -w \"#{osw_path}\""
      puts cmd

      # Run the sizing run
      OpenstudioStandards.run_command(cmd)

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")

      sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")

    end

    # @todo Delete the eplustbl.htm and other files created by the run for cleanliness.

    if OpenStudio.exists(sql_path)
      sql = OpenStudio::SqlFile.new(sql_path)
      # Check to make sure the sql file is readable,
      # which won't be true if EnergyPlus crashed during simulation.
      unless sql.connectionOpen
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The run failed, cannot create model.  Look at the eplusout.err file in #{File.dirname(sql_path.to_s)} to see the cause.")
        return false
      end
      # Attach the sql file from the run to the model
      model.setSqlFile(sql)
    else
      # If the sql file does not exist, it is likely that EnergyPlus crashed,
      # in which case the useful errors are inside the eplusout.err file.
      err_file_path_string = "#{run_dir}/run/eplusout.err"
      err_file_path = OpenStudio::Path.new(err_file_path_string)
      if OpenStudio.exists(err_file_path)
        if __dir__[0] == ':' # Running from OpenStudio CLI
          errs = EmbeddedScripting.getFileAsString(err_file_path_string)
        else
          errs = File.read(err_file_path_string)
        end
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The run did not finish because of the following errors: #{errs}")
        return false
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Results for the run couldn't be found here: #{sql_path}.")
        return false
      end
    end

    # Report severe or fatal errors in the run
    error_query = "SELECT ErrorMessage
        FROM Errors
        WHERE ErrorType in(1,2)"
    errs = model.sqlFile.get.execAndReturnVectorOfString(error_query)
    if errs.is_initialized
      errs = errs.get
    end

    # Check that the run completed successfully
    end_file_stringpath = "#{run_dir}/run/eplusout.end"
    end_file_path = OpenStudio::Path.new(end_file_stringpath)
    if OpenStudio.exists(end_file_path)
      endstring = File.read(end_file_stringpath)
    end

    if !endstring.include?('EnergyPlus Completed Successfully')
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The run did not finish and had following errors: #{errs.join('\n')}")
      return false
    end

    # Log any severe errors that did not cause simulation to fail
    unless errs.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "The run completed but had the following severe errors: #{errs.join('\n')}")
    end

    return true
  end

  # A helper method to run a sizing run and pull any values calculated during autosizing back into the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param sizing_run_dir [String] file path location for the sizing run, defaults to 'SR' in the current directory
  # @param sizing_run_simulation [Boolean] whether to run the simulation for the sizing periods, defaults to true
  # @return [Boolean] returns true if successful, false if not
  def model_run_sizing_run(model, sizing_run_dir = "#{Dir.pwd}/SR", sizing_run_simulation = true)
    # Change the simulation to only run the sizing days
    sim_control = model.getSimulationControl
    sim_control.setRunSimulationforSizingPeriods(sizing_run_simulation)
    sim_control.setRunSimulationforWeatherFileRunPeriods(false)
    if model.version >= OpenStudio::VersionString.new('3.0.0')
      sim_control.setDoHVACSizingSimulationforSizingPeriods(true)
      sim_control.setMaximumNumberofHVACSizingSimulationPasses(1)
    end
    if model.version >= OpenStudio::VersionString.new('3.8.0')
      sim_control.setDoZoneSizingCalculation(true)
      sim_control.setDoSystemSizingCalculation(true)
      sim_control.setDoPlantSizingCalculation(true)
    end

    # check that all zones have surfaces.
    raise 'Error: Sizing Run Failed. Thermal Zones with no surfaces exist.' unless model_do_all_zones_have_surfaces?(model)

    # Run the sizing run
    success = model_run_simulation_and_log_errors(model, sizing_run_dir)

    # Change the model back to running the weather file
    sim_control.setRunSimulationforSizingPeriods(false)
    sim_control.setRunSimulationforWeatherFileRunPeriods(true)
    if model.version >= OpenStudio::VersionString.new('3.0.0')
      sim_control.setDoHVACSizingSimulationforSizingPeriods(false)
    end

    return success
  end

  # Method to check if all zones have surfaces. This is required to run a simulation.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_do_all_zones_have_surfaces?(model)
    # Check to see if all zones have surfaces.
    model.getThermalZones.each do |zone|
      surfaces = zone.spaces.sort.flat_map(&:surfaces)
      if surfaces.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.simulation', "Thermal zone #{zone.name} does not contain surfaces.\n")
        return false
      end
    end
    return true
  end

  # A helper method to run a space sizing run and pull any values calculated during autosizing back into the model.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param sizing_run_dir [String] file path location for the sizing run, defaults to 'SpaceSR' in the current directory
  # @return [OpenStudio::Model::Model] returns the model if successful
  def model_run_space_sizing_run(sizing_run_dir = "#{Dir.pwd}/SpaceSR")
    puts '*************Runing sizing space Run ***************************'
    # Make copy of model
    model = BTAP::FileIO.deep_copy(model, true)
    space_load_array = []

    # Make sure the model is good to run.
    # 1. Ensure External surfaces are set to a construction
    ext_surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(model.getSurfaces, ['Outdoors',
                                                                                             'Ground',
                                                                                             'GroundFCfactorMethod',
                                                                                             'GroundSlabPreprocessorAverage',
                                                                                             'GroundSlabPreprocessorCore',
                                                                                             'GroundSlabPreprocessorPerimeter',
                                                                                             'GroundBasementPreprocessorAverageWall',
                                                                                             'GroundBasementPreprocessorAverageFloor',
                                                                                             'GroundBasementPreprocessorUpperWall',
                                                                                             'GroundBasementPreprocessorLowerWall'])
    fail = false
    ext_surfaces.each do |surface|
      if surface.construction.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Ext Surface #{surface.name} does not have a construction.Cannot perform sizing.")
        fail = true
      end
    end
    puts "#{ext_surfaces.size} External Surfaces counted."
    raise "Can't run sizing since envelope is not set." if fail == true

    # remove any thermal zones.
    model.getThermalZones.each(&:remove)

    # assign a zone to each space.
    # Create a thermal zone for each space in the model
    model.getSpaces.each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("#{space.name} ZN")
      space.setThermalZone(zone)
    end
    # Add a thermostat
    BTAP::Compliance::NECB2011.set_zones_thermostat_schedule_based_on_space_type_schedules(model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished creating thermal zones')
    # Add ideal loads to every zone/space and run
    # a sizing run to determine heating/cooling loads,
    # which will impact HVAC systems.
    model.getThermalZones.each do |zone|
      ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
      ideal_loads.addToThermalZone(zone)
    end
    model_run_sizing_run(model, sizing_run_dir)
    model.getSpaces.each do |space|
      unless space.thermalZone.empty?
        # error if zone design load methods are not available
        if space.model.version < OpenStudio::VersionString.new('3.6.0')
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.simulation', 'Required ThermalZone methods .autosizedHeatingDesignLoad and .autosizedCoolingDesignLoad are not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
        end

        space_cooling_load = 0.0
        if space.thermalZone.get.autosizedCoolingDesignLoad.is_initialized
          space_cooling_load = space.thermalZone.get.autosizedCoolingDesignLoad.get
        end

        space_heating_load = 0.0
        if space.thermalZone.get.autosizedHeatingDesignLoad.is_initialized
          space_heating_load = space.thermalZone.get.autosizedHeatingDesignLoad.get
        end

        space_load_array << { 'space_name' => space.name, 'CoolingDesignLoad' => space_cooling_load, 'HeatingDesignLoad' => space_heating_load }
      end
    end
    puts space_load_array
    puts '*************Done Runing sizing space Run ***************************'
    return model
  end
end
