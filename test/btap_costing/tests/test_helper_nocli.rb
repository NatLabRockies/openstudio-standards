require_relative '../../../lib/openstudio-standards.rb'
require 'optparse'
require 'logger'
require 'minitest/autorun'
require_relative '../../../lib/openstudio-standards/btap/costing/btap_workflow.rb'
require 'fileutils'
#require 'optparse'

class Btap_results_helper

  def btap_results_regression_test()
    cp = CommonPaths.instance
    args = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: example.rb [options]"
      opts.on("-b", "--building_type=NAME", "Building Type") do |n|
        args['building_type'] = n
      end

      opts.on("-t", "--template=NAME", "NECB Template(BTAPPRE1980,BTAP1980TO2010,NECB2011, NECB2015, NECB2017, or NECB2020)") do |n|
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

      # opts.on("-p", "--postprocess_only", "only if you do not wish to do complete run. This has options to the the os/e+ measures only...or only the reports measures (measures_only|postprocess_only)") do |n|
      #   args['post_process_only'] = n
      # end

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
      raise("HeatPump as fuel type is not valid with templates BTAPPRE1980 and BTAP1980TO2010")
    end
    # CLI args
    # postprocess_only = args['post_process_only']
    keep_all_results = args['keep_all_results']
    puts "tester Helper args pass are:"
    puts args

    # Test output folder.
    out_dir = File.join(__dir__, '..', '..', 'costing_output')
    model_name = "#{building_type}-#{template}-#{dir_name_fuel}-#{File.basename(epw_file, '.epw')}"
    run_dir = File.join(out_dir, model_name)

    standard = Standard.build("#{template}")
    #model = standard.load_building_type_from_library(building_type: building_type)
    model = standard.model_create_prototype_model(
      template: template,
      building_type: building_type,
      epw_file: epw_file,
      primary_heating_fuel: primary_heating_fuel,
      sizing_run_dir: run_dir
    )
    standard.model_run_simulation_and_log_errors(model, run_dir)

    # mimic the process of running this measure in OS App or PAT
    model_out_path = "#{run_dir}/final.osm"

    #create osm file to use mimic PAT/OS server called final
    model.save(model_out_path, true)

    # Do costing.
    post_analysis = BTAPDatapointAnalysis.new(
      model: model,
      output_folder: run_dir,
      template: template,
      standard: standard,
      qaqc: nil)

    post_analysis.run_costing

    # Check Cost file exists
    cost_result_json_path = File.join(run_dir, '/cost_results.json')
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
          perc_change = ((test - expected)/ expected) * 100.0
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
