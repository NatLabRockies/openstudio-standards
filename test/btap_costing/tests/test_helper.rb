require_relative '../../../lib/openstudio-standards.rb'
require 'optparse'
require 'logger'
require 'minitest/autorun'
require_relative '../../../lib/openstudio-standards/btap/costing/btap_workflow.rb'
require 'fileutils'
require 'optparse'

class Btap_results_helper

  def btap_results_regression_test()
    args = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: example.rb [options]"
      opts.on("-b", "--building_type=NAME", "Building Type") do |n|
        args['building_type'] = n
      end

      opts.on("-t", "--template=NAME", "NECB Template(BTAPPRE1980, BTAP1980TO2010, NECB2011, NECB2015, NECB2017, or NECB2020)") do |n|
        args['template'] = n
      end

      opts.on("-f", "--primary_heating_fuel=NAME", "Primary Heating Fuel (NaturalGas,Electricity,FuelOilNo2,HeatPump or DefaultFuel)") do |n|
        args['primary_heating_fuel'] = n
      end

      opts.on("-w", "--epw_file=NAME", "NECB2017-CAN_YT_Whitehorse.Intl.AP.719640_CWEC2016.epw ") do |n|
        args['epw_file'] = n
      end

      opts.on("-k", "--keep_all_results", "Don't delete anything after runs") do |n|
        args['keep_all_results'] = n
      end

      opts.on("-p", "--postprocess_only", "only if you do not wish to do complete run. This has options to the the os/e+ measures only...or only the reports measures (measures_only|postprocess_only)") do |n|
        args['post_process_only'] = n
      end

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end.parse!

    # set default tolerance
    tolerance = 0.10

    # Arguments passed from command line.
    # BTAPCreatePrototypeBuilding Measure Args.
    building_type = args['building_type']
    template = args['template']
    epw_file = args['epw_file']
    dir_name_fuel = args['primary_heating_fuel']
    primary_heating_fuel = args['primary_heating_fuel']

    if ((template == 'BTAPPRE1980') ||(template == 'BTAP1980TO2010')) && (primary_heating_fuel == 'NaturalGasHPGasBackup')
      raise("NECB reference heat pump option is not valid with templates BTAPPRE1980 and BTAP1980TO2010")
    end

    # CLI args
    postprocess_only = args['post_process_only']
    keep_all_results = args['keep_all_results']
    puts "tester Helper args pass are:"
    puts args

    #Location of measures folder.
    measures_folder = File.join(__dir__, '../../../measures')
    # Seed files.. in this case dummy files.
    dummy_osm = File.join(__dir__, '..', 'resources', 'dummy.osm')
    dummy_epw = File.join(__dir__, '..', 'resources', 'dummy.epw')
    # Test output folder.
    out_dir = File.join(__dir__, '..', '..', '..', 'costing_output')
    # Model name derived from NECB building, location and template.
    model_name = "#{building_type}-#{template}-#{dir_name_fuel}-#{File.basename(epw_file, '.epw')}"
    # RUn folder for current workflow.
    run_dir = File.join(out_dir, model_name)
    # Workflow file path.
    osw_path = OpenStudio::Path.new(File.join(run_dir, 'out.osw'))
    # Create workflow object.. This is ths simulation workflow.
    btap_rs = BTAPWorkflow.new(measures_folder: measures_folder)

    #Dont create the OSW file if we are doing a post-process only.
    if not postprocess_only
      # Create OSM file.

      # Create the main output folder if it doesn not exist.
      unless Dir.exist?(out_dir)
        FileUtils.mkdir_p(out_dir)
      end

      # Delete / Create folder for run workflow.
      unless Dir.exist?(run_dir)
        FileUtils.mkdir_p(run_dir)
      end

      # Add basics required parameters.. since we are using create prototype.both the osm and epw are dummy files that are not used.
      btap_rs.set_run_dir(run_dir: run_dir)
      btap_rs.workflow.setSeedFile(dummy_osm)
      btap_rs.workflow.setWeatherFile(dummy_epw)

      #add OS Measures create prototype building with argruments.
      btap_rs.add_btap_create_necb_prototype_building_measure(building_type: building_type,
                                                              epw_file: epw_file,
                                                              template: template,
                                                              primary_heating_fuel: primary_heating_fuel)

      #Add Reports Measure btap_reports
      btap_rs.add_btap_results_measure()

      # Add the measures to the workflow. This is required.
      btap_rs.add_measures_to_workflow()

      # Save OSW file.
      osw_path = OpenStudio::Path.new(File.join(run_dir, 'out.osw'))
      puts "Saving OSW file here #{osw_path}"
      btap_rs.workflow.saveAs(File.absolute_path(osw_path.to_s))
    end

    # This runs the workflow.
    btap_rs.run_workflow(postprocess_only: postprocess_only, osw_path: osw_path)

    # Check Cost file exists
    cost_result_json_path = File.join(run_dir, '/run/001_btap_results/cost_results.json')
    raise("Could not find costing json at this path:#{cost_result_json_path}") unless File.exist?(cost_result_json_path)

    # Check Cost results are the same.
    regression_files_folder = "#{File.dirname(__FILE__)}/regression_files"
    expected_result_filename = "#{regression_files_folder}/#{model_name}_expected_result.cost.json"
    test_result_filename = "#{regression_files_folder}/#{model_name}_test_result.cost.json"
    FileUtils.rm(test_result_filename) if File.exist?(test_result_filename)
    puts("Writing test results to #{test_result_filename}")
    FileUtils.cp(cost_result_json_path, test_result_filename)
    if File.exist?(expected_result_filename)
      unless FileUtils.compare_file(cost_result_json_path, expected_result_filename)
        #raise("Regression test for #{model_name} produces differences. Examine expected and test result differences in the #{File.dirname(__FILE__)}/regression_files folder ")
        expected_hash = JSON.parse(File.read(expected_result_filename))
        test_hash = JSON.parse(File.read(test_result_filename))
        error_message = ''
        ["envelope",
         "lighting",
         "heating_and_cooling",
         "shw",
         "ventilation",
         "grand_total"].each do |end_use|
          expected = expected_hash["totals"][end_use]
          test = test_hash["totals"][end_use]
          perc_change = (test - expected)/ expected * 100.0
          if perc_change.abs() > tolerance
            error_message << "#{end_use} percent change by #{perc_change}\n"
          end
        end
        if error_message != ''
          raise("Regression test for #{model_name} produces differences. #{error_message}")
        end
      end
  else
    raise("No expected test file...Generating expected file #{expected_result_filename}. Please verify.")
  end

  # Let user know it passed.
  puts "Regression test for #{model_name} passed."

  # Delete all unneeded files unless requested.
  unless keep_all_results
    #These files/folders are required to run the reports measure.
    dont_delete = []
    dont_delete << File.join(run_dir, 'in.osm')
    dont_delete << File.join(run_dir, 'in.osw')
    dont_delete << File.join(run_dir, 'out.osw')
    dont_delete << File.join(run_dir, 'in.idf')
    dont_delete << File.join(run_dir, 'out.idf')
    dont_delete << File.join(run_dir, 'run')
    dont_delete << File.join(run_dir, 'run', 'in.idf')
    dont_delete << File.join(run_dir, 'run', 'eplusout.sql')
    Dir.glob("#{run_dir}/**/*").select { |file| not (dont_delete.include?(file)) }.each { |file| FileUtils.rm_rf(file) }
  end

  #This has to be set to new osm files as a seedfile to work.
  osw_file = OpenStudio::WorkflowJSON.load(OpenStudio::Path.new(File.join(run_dir, 'out.osw'))).get
  osw_file.setSeedFile(File.join(run_dir, 'in.osm'))
  osw_file.saveAs(File.join(run_dir, 'out.osw'))
  return run_dir
end
end
Btap_results_helper.new().btap_results_regression_test()
