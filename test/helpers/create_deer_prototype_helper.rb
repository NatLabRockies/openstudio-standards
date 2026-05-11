# Create a base class for testing DEER prototype buildings
class CreateDEERPrototypeBuildingTest < Minitest::Test

  def setup
    # Make a directory to save the resulting models
    @test_dir = "#{__dir__}/output"
    if !Dir.exist?(@test_dir)
      Dir.mkdir(@test_dir)
    end
    # Make a file to store the model comparisons
    @results_csv_file = "#{@test_dir}/prototype_buildings_results.csv"
    # Add a header row on file creation
    if !File.exist?(@results_csv_file)
      File.open(@results_csv_file, 'a') do |file|
        file.puts "building_type,template,climate_zone,fuel_type,end_use,legacy_val,osm_val,percent_error,difference,absolute_percent_error"
      end
    end
    # Make a file that combines all the run logs
    @combined_results_log = "#{@test_dir}/prototype_buildings_run.log"
    if !File.exist?(@combined_results_log)
      File.open(@combined_results_log, 'a') do |file|
        file.puts "Started @ #{Time.new}"
      end
    end

  end

  # Dynamically create a test for each building type/template/climate zone
  # so that if one combo fails the others still run
  def CreateDEERPrototypeBuildingTest.create_run_model_tests(building_types,
      templates,
      hvac_systems,
      climate_zones,
      create_models = true,
      run_models = true,
      compare_results = true,
      debug = false)

    building_types.each do |building_type|
      templates.each do |template|
        hvac_systems.each do |hvac_system|
          climate_zones.each do |climate_zone|
            create_building(building_type, template, hvac_system, climate_zone, create_models, run_models, compare_results, debug )
          end
        end
      end
    end

  end

  def CreateDEERPrototypeBuildingTest.create_building(building_type,
      template,
      hvac_system,
      climate_zone,
      create_models,
      run_models,
      compare_results,
      debug )

      method_name = "test_#{building_type}-#{template}-#{hvac_system}-#{climate_zone}".gsub(' ','_')

    define_method(method_name) do

      # Start time
      start_time = Time.new

      # Reset the log for this test
      reset_log

      # Paths for this test run

      model_name = "#{building_type}-#{template}-#{hvac_system}-#{climate_zone}"

      run_dir = "#{@test_dir}/#{model_name}"
      if !Dir.exist?(run_dir)
        Dir.mkdir(run_dir)
      end
      full_sim_dir = "#{run_dir}/AnnualRun"
      idf_path_string = "#{run_dir}/#{model_name}.idf"
      idf_path = OpenStudio::Path.new(idf_path_string)
      osm_path_string = "#{run_dir}/final.osm"
      output_path = OpenStudio::Path.new(run_dir)

      model = nil
      # Create the model, if requested
      if create_models
        prototype_creator = Standard.build("#{template}_#{building_type}_#{hvac_system}")
        model = prototype_creator.model_create_prototype_model(climate_zone, nil, run_dir, debug)

        # If the model was not created successfully,
        # create and save an empty model. Tests will fail
        # because there will be errors in the log.
        if !model
          model = OpenStudio::Model::Model.new
        end

        # Save the final osm
        model.save(osm_path_string, true)

        # Convert the model to energyplus idf
        forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
        idf = forward_translator.translateModel(model)
        idf.save(idf_path,true)

      end

      # Run the simulation, if requested
      if run_models

        # Delete previous run directories if they exist
        FileUtils.rm_rf(full_sim_dir)

        # Load the model from disk if not already in memory
        if model.nil?
          model = prototype_creator.safe_load_model(osm_path_string)
          forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
          idf = forward_translator.translateModel(model)
          idf.save(idf_path,true)
        end

        # Run the annual simulation
        standard = Standard.build("#{template}")
        standard.model_run_simulation_and_log_errors(model, full_sim_dir)

      end

      # Compare the results against the legacy idf files if requested
      if compare_results
        puts "compare_results not yet available for DEER Prototype models"
      end

      # Calculate run time
      run_time = Time.new - start_time

      # Report out errors
      log_file_path = "#{run_dir}/openstudio-standards.log"
      messages = log_messages_to_file(log_file_path, debug)
      errors = get_logs(OpenStudio::Error)

      # Copy errors to combined log file
      File.open(@combined_results_log, 'a') do |file|
        file.puts "*** #{model_name}, Time: #{run_time.round} sec ***"
        messages.each do |message|
          file.puts message
        end
      end

      # Assert if there were any errors
      assert(errors.size == 0, errors)

    end
  end

end
