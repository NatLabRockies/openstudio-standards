require 'minitest/unit'
require 'json'
require 'csv'
require 'digest'


class NECBRegressionHelper < Minitest::Test



  def setup()
    @building_type = 'FullServiceRestaurant'
    @epw_file = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'
    @template = 'NECB2011'
    @test_dir = "#{File.dirname(__FILE__)}/output"
    @expected_results_folder = "#{File.dirname(__FILE__)}/../expected/"
    @model = nil
    @model_name = nil
    @run_simulation = false
    @primary_heating_fuel = "Electricity"
  end


  def create_model_and_regression_test(building_type: @building_type,
                                       epw_file: @epw_file,
                                       template: @template,
                                       test_dir: @test_dir,
                                       expected_results_folder: @expected_results_folder,
                                       run_simulation: @run_simulation,
                                       primary_heating_fuel: @primary_heating_fuel
  )
    @epw_file = epw_file
    @template = template
    @building_type = building_type
    @test_dir = test_dir
    @expected_results_folder = expected_results_folder
    @primary_heating_fuel = primary_heating_fuel
    self.create_model(building_type: @building_type,
                      epw_file: @epw_file,
                      template: @template,
                      test_dir: @test_dir,
                      primary_heating_fuel: @primary_heating_fuel)

    result, diff = self.osm_regression(expected_results_folder: @expected_results_folder)
    if run_simulation
      self.run_simulation()
      #self.qaqc_regression()
    end
    return result, diff
  end


  def create_model(epw_file: @epw_file,
                   template: @template,
                   building_type: @building_type,
                   test_dir: @test_dir,
                   primary_heating_fuel: @primary_heating_fuel)
    #set paths

    @model_name = "#{building_type}-#{template}-#{primary_heating_fuel}-#{File.basename(epw_file, '.epw').split('.')[0]}"

    @run_dir = "#{test_dir}/#{@model_name}"
    #create folders
    if !Dir.exist?(test_dir)
      Dir.mkdir(test_dir)
    end
    if !Dir.exist?(@run_dir)
      Dir.mkdir(@run_dir)
    end
    puts "========================model_name =================== #{@model_name}"
    @model = Standard.build("#{template}").model_create_prototype_model(epw_file: epw_file,
                                                                        sizing_run_dir: @run_dir,
                                                                        template: template,
                                                                        building_type: building_type,
                                                                        primary_heating_fuel: primary_heating_fuel
)
    unless @model.instance_of?(OpenStudio::Model::Model)
      puts "Creation of Model for #{@model_name} failed. Please check output for errors."
    end
    return self
  end


  def osm_regression(expected_results_folder: @expected_results_folder)
    begin
      diffs = []
      osm_results_folder = File.join(File.expand_path('..', expected_results_folder), 'output_osm')
      idf_results_folder = File.join(File.expand_path('..', expected_results_folder), 'output_idf')
      diff_results_folder = File.join(File.expand_path('..', expected_results_folder), 'output_diff')
      [osm_results_folder, idf_results_folder, diff_results_folder].each do |folder|
        FileUtils.mkdir_p(folder) unless Dir.exist?(folder)
      end

      expected_osm_file = File.join(expected_results_folder, @model_name + '.osm')
      test_osm_file = File.join(osm_results_folder, @model_name + '.osm')
      test_idf_file = File.join(idf_results_folder, @model_name + '.idf')

      #save test results by default
      BTAP::FileIO.save_osm(@model, test_osm_file)
      BTAP::FileIO::clean_osm_file(file_path: test_osm_file, output_path: test_osm_file)
      @model = BTAP::FileIO::load_osm(test_osm_file)
      puts "saved test result osm file to #{test_osm_file}"
      BTAP::FileIO.save_idf(@model, test_idf_file)
      puts "saved test result idf file to #{test_idf_file}"
      
      # Load the expected osm
      unless File.exist?(expected_osm_file)
        raise("The initial osm path: #{expected_osm_file} does not exist.")
      end
      expected_osm_model_path = OpenStudio::Path.new(expected_osm_file.to_s)
      # Upgrade version if required.
      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      expected_model = version_translator.loadModel(expected_osm_model_path).get

      # Compare the two models.
      diffs = BTAP::FileIO::compare_osm_files(expected_model, @model)
    rescue => exception
      # Log error/exception and then keep going.
      error = "#{exception.backtrace.first}: #{exception.message} (#{exception.class})"
      exception.backtrace.drop(1).map {|s| "\n#{s}"}.each {|bt| error << bt.to_s}
      diffs << "#{@model_name}: Error \n#{error}"
    end
    #Write out diff or error message
    diff_file = File.join(diff_results_folder,@model_name+'_diffs.json')
    FileUtils.rm(diff_file) if File.exist?(diff_file)
    if diffs.size > 0
      File.write(diff_file, JSON.pretty_generate(diffs))
      puts "There were #{diffs.size} differences/errors in #{expected_osm_file} #{@template} #{@epw_file}"
      return false, {"diffs-errors" => diffs}
    else
      return true, []
    end
  end

  def run_simulation(expected_results_folder: @expected_results_folder)
    model_out_path = "#{@run_dir}/ExampleModel.osm"
    workspace_path = "#{@run_dir}/ModelToIdf/in.idf"
    sql_path = "#{@run_dir}/ModelToIdf/EnergyPlusPreProcess-0/EnergyPlus-0/eplusout.sql"
    report_path = "#{@run_dir}/report.html"
    test_qaqc_file = "#{expected_results_folder}#{@model_name}_test_result_qaqc.json"
    [model_out_path, workspace_path, sql_path, report_path, test_qaqc_file].each do |file|
      if File.exist?(file)
        FileUtils.rm(file)
      end
    end

    weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(@epw_file)
    OpenstudioStandards::Weather.model_set_building_location(@model, weather_file_path: weather_file_path)

    Standard.build("#{@template}").model_run_simulation_and_log_errors(@model, @run_dir)
  end


end