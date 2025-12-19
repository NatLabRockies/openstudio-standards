require_relative '../../../lib/openstudio-standards.rb'
require 'minitest/autorun'
require 'optparse'
require_relative '../../NZEHVAC/measure.rb'
require 'fileutils'
require 'minitest/unit'
require 'optparse'


class BtapResults_Test < Minitest::Test


  def test_qaqc()

    # NZEB HVAC arguments
    @hvac_system_type = ["VAV Reheat",
                        "PVAV Reheat",
                        "VRF with DOAS",
                        "VRF with DOAS with DCV",
                        "Ground Source Heat Pumps with DOAS",
                        "Ground Source Heat Pumps with DOAS with DCV",
                        "Fan Coils with DOAS",
                        "Fan Coils with DOAS with DCV",
                        "Fan Coils with ERVs"]
    @hvac_system_partition = [
        "Automatic Partition",
        "Whole Building",
        "One System Per Building Story",
        "One System Per Building Type"
    ]
    @remove_existing_hvac = [true,false]

    # check if there are any command line arguments, if there are run those
    input_args = ARGV

    #building_type = 'Outpatient'
    building_type = 'LargeHotel'
    #building_type = 'FullServiceRestaurant'
    #building_type = 'Warehouse'
    #building_type = 'LargeOffice'
    #building_type = 'MediumOffice'
    #building_type = 'MidriseApartment'

    #epw_file = "CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw"
    #epw_file = "CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw"
    #epw_file = "CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw"
    #epw_file = "CAN_AB_Fort.Mcmurray.AP.716890_CWEC2020.epw"
    #epw_file = "CAN_NS_Halifax.Dockyard.713280_CWEC2020.epw"
    #epw_file = "CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw"
    #epw_file = "CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw"
    epw_file = "CAN_NT_Yellowknife.AP.719360_CWEC2020.epw"

    #template = 'BTAPPRE1980'
    #template = 'BTAP1980TO2010'
    #template = 'NECB2011'
    #template = 'NECB2015'
    template = 'NECB2017'

    # If you want openstudio-standards to make an osm for you set use_existing_osm to 'true'
    use_existing_osm = false
    # If you to use an osm other than those used for regression tests set 'custom_file' to the file name
    #custom_file = 'LargeHotel-NECB2017-CAN_AB_Edmonton.Intl.AP.711230_CWEC2016_expected_result.osm'
    #custom_file = 'FullServiceRestaurant-NECB2015-CAN_AB_Calgary.Intl.AP.718770_CWEC2016_expected_result_test.osm'
    #custom_file = 'LargeHotel-NECB2017-CAN_AB_Calgary.Intl.AP.718770_CWEC2016_expected_result_HP_mod.osm'
    #custom_file = 'LargeHotel-NECB2017-CAN_QC_Kuujjuaq.AP.719060_CWEC2016_expected_result_HP_mod.osm'
    custom_file = nil
    # Change this folder to where the custom file is (starting from btap_costing/)
    @test_fold = "/os_standards_reg_tests/"

    # If you already ran the simulation and have the results set the location of the results folder here
    # (starting from btap_costing/).  Do not add starting and ending '/'.  Set to nil if you have not already run a
    # simulation.
    #@test_output = "testdir_QC"
    @test_output = nil

    if use_existing_osm == true && custom_file.nil? && input_args.empty?
      if epw_file == "CAN_AB_Calgary.Intl.AP.718770_CWEC2016.epw" || epw_file == "CAN_QC_Kuujjuaq.AP.719060_CWEC2016.epw"
        @test_file = building_type + '-' + template + '-' + epw_file[0..-5] + '_expected_result.osm'
        puts ' '
        puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        puts "Testing with existing test file: #{@test_file}"
        puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        puts ' '
      else
        puts ' '
        puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        puts 'You have selected to use an OpenStudio-standards NECB regression test file but have selected an incorrect weather file.  Will now generate osm via OpenStudio-standards.'
        puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        puts ' '
      end
    elsif use_existing_osm == true && input_args.empty? && @test_output.nil? && !custom_file.nil?
      @test_file = custom_file
      puts ' '
      puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
      puts "Testing with existing custom test file: #{@test_file}"
      puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
      puts ' '
    elsif use_existing_osm == true && input_args.empty? && !@test_output.nil? && !custom_file.nil?
      @test_file = custom_file
      puts ' '
      puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
      puts "Testing with existing results in folder: #{@test_output}"
      puts "Testing with existing file: #{@test_file}"
      puts "In folder: #{@test_fold}"
      puts '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
      puts ' '
    end
    # Set 'autozone' to false if you do not want openstudio to run with the auto thermal zoning feature enabled.
    autozone = true

    unless input_args.empty?
      if ((input_args.length / 3).to_i) * 3 < input_args.length
        puts " "
        puts "Incorrect number of arguments, running default buildings:"
        puts building_type
        puts " "
        puts "With default weather files:"
        puts epw_file
        puts " "
        puts "With default templates"
        puts template
        puts " "
      else
        (0..(input_args.length - 1)).step(3) do |index|
          building_type = input_args[index]
          epw_file = input_args[index + 1]
          template = input_args[index + 2]
        end
      end
    end

    create_model_simulate_and_qaqc_regression_test(epw_file: epw_file,
                                                   template: template,
                                                   building_type: building_type,
                                                   auto_zone: autozone
    )


  end


  def create_model_simulate_and_qaqc_regression_test(epw_file:,
                                                     template:,
                                                     building_type:,
                                                     auto_zone: true
  )

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio. Ensure files exist.
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    test_dir = "#{File.dirname(__FILE__)}/output"
    if !Dir.exist?(test_dir)
      Dir.mkdir(test_dir)
    end

    standard = Standard.build("#{template}")

    if @test_file.nil?
      model_name = "#{building_type}-#{template}-#{File.basename(epw_file, '.epw')}"
      run_dir = "#{test_dir}/#{model_name}"
      if !Dir.exist?(run_dir)
        Dir.mkdir(run_dir)
      end
      #create standard model
      model = standard.model_create_prototype_model(epw_file: epw_file,
                                                    sizing_run_dir: run_dir,
                                                    template: template,
                                                    building_type: building_type,
                                                    new_auto_zoner: auto_zone)
    elsif !@test_output.nil?
      model_name = @test_file
      top_dir_element = /btap_costing/ =~ File.expand_path(File.dirname(__FILE__))
      top_dir_name = File.expand_path(File.dirname(__FILE__))[0..(top_dir_element - 1)]
      run_dir = top_dir_name + 'btap_costing/' + @test_output
      in_file = top_dir_name + 'btap_costing' + @test_fold + @test_file
      model = BTAP::FileIO.load_osm(in_file)
      BTAP::Environment::WeatherFile.new(epw_file).set_weather_file(model)
    else
      model_name = @test_file
      run_dir = "#{test_dir}/#{model_name[0..-5]}"
      if !Dir.exist?(run_dir)
        Dir.mkdir(run_dir)
      end
      top_dir_element = /btap_costing/ =~ File.expand_path(File.dirname(__FILE__))
      top_dir_name = File.expand_path(File.dirname(__FILE__))[0..(top_dir_element - 1)]
      in_file = top_dir_name + 'btap_costing' + @test_fold + @test_file
      model = BTAP::FileIO.load_osm(in_file)
      BTAP::Environment::WeatherFile.new(epw_file).set_weather_file(model)
    end

    #Run NZEB HVAC measure
    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      # create an instance of the measure and runner
      measure = NzeHvac.new
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
      assert_equal(3, arguments.size)

      remove_existing_hvac = arguments[0].clone
      assert(remove_existing_hvac.setValue(true))
      argument_map['remove_existing_hvac'] = remove_existing_hvac

      hvac_system_type = arguments[1].clone
      assert(hvac_system_type.setValue("Fan Coils with DOAS"))
      argument_map['hvac_system_type'] = hvac_system_type

      hvac_system_partition = arguments[2].clone
      assert(hvac_system_partition.setValue("Automatic Partition"))
      argument_map['hvac_system_partition'] = hvac_system_partition

      Dir.chdir(run_dir)
      # run the measure
      measure.run(model,runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end




    if @test_output.nil?
      #run models
      standard.model_run_simulation_and_log_errors(model, run_dir)
    end

    # mimic the process of running this measure in OS App or PAT
    model_out_path = "#{run_dir}/final.osm"
    workspace_path = "#{run_dir}/run/in.idf"
    sql_path = "#{run_dir}/run/eplusout.sql"
    cost_result_json_path = "#{run_dir}/cost_results.json"
    cost_list_json_path = "#{run_dir}/btap_items.json"

    #create osm file to use mimic PAT/OS server called final
    model.save(model_out_path, true)


    assert(File.exist?(model_out_path), "Could not find osm at this path:#{model_out_path}")
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path))
    assert(File.exist?(workspace_path), "Could not find idf at this path:#{workspace_path}")
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path))
    assert(File.exist?(sql_path), "Could not find sql at this path:#{sql_path}")
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path))


    model.save(model_out_path, true)

    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      # create an instance of the measure and runner
      measure = BtapResults.new
      arguments = measure.arguments()
      argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
      assert_equal(10, arguments.size)

      hourly_data = arguments[0].clone
      assert(hourly_data.setValue("false"))
      argument_map['generate_hourly_report'] = hourly_data

      output_diet = arguments[1].clone
      assert(output_diet.setValue(false))
      argument_map['output_diet'] = output_diet

      envelope_costing = arguments[2].clone
      assert(envelope_costing.setValue(true))
      argument_map['envelope_costing'] = envelope_costing

      lighting_costing = arguments[3].clone
      assert(lighting_costing.setValue(true))
      argument_map['lighting_costing'] = lighting_costing

      boilers_costing = arguments[4].clone
      assert(boilers_costing.setValue(true))
      argument_map['boilers_costing'] = boilers_costing

      chillers_costing = arguments[5].clone
      assert(chillers_costing.setValue(true))
      argument_map['chillers_costing'] = chillers_costing

      cooling_towers_costing = arguments[6].clone
      assert(cooling_towers_costing.setValue(true))
      argument_map['cooling_towers_costing'] = cooling_towers_costing

      shw_costing = arguments[7].clone
      assert(shw_costing.setValue(true))
      argument_map['shw_costing'] = shw_costing

      ventilation_costing = arguments[8].clone
      assert(ventilation_costing.setValue(true))
      argument_map['ventilation_costing'] = ventilation_costing

      zone_system_costing = arguments[9].clone
      assert(zone_system_costing.setValue(true))
      argument_map['zone_system_costing'] = zone_system_costing

      Dir.chdir(run_dir)
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end
    assert(File.exist?(cost_result_json_path), "Could not find costing json at this path:#{cost_result_json_path}")
    regression_files_folder = "#{File.dirname(__FILE__)}/regression_files"
    expected_result_filename = "#{regression_files_folder}/#{model_name}_expected_result.cost.json"
    test_result_filename = "#{regression_files_folder}/#{model_name}_test_result.cost.json"
    FileUtils.rm(test_result_filename) if File.exist?(test_result_filename)
    FileUtils.cp(cost_result_json_path, test_result_filename)
    puts "Saved cost results here #{test_result_filename}"

    # Do comparison of direct btap_costing results and those derived from the itemized cost list
    # Check if an itemized cost list file exists.  If it exists, do the comparison.  If not, Ignore the comparison.
    if File.exist?(cost_list_json_path)
      # Get the itemized cost list file.
      costList = JSON.parse(File.read(cost_list_json_path))
      # Cost the building based on the itemized cost list.
      btapCosting = BTAPCosting.new()
      cost_list_output = btapCosting.cost_list_items(btap_items: costList)
      # Get the detailed btap_costing result file:
      cost_result = JSON.parse(File.read(cost_result_json_path))
      cost_sum = cost_result['totals']
      # Compare the results and let the user know if there are differences.  Do not fail test if there are.
      puts("")
      puts("Comparing BTAP_Costing results and itemized costing list cost results:")
      puts("Envelope Cost Difference: #{cost_sum['envelope'].to_f - cost_list_output['envelope'].to_f}") if cost_list_output['enevelope'] != cost_sum['envelope']
      puts("Lighting Cost Difference: #{cost_sum['lighting'].to_f - cost_list_output['lighting'].to_f}") if cost_list_output['lighting'] != cost_sum['lighting']
      puts("Heating and Cooling Cost Difference: #{cost_sum['heating_and_cooling'].to_f - cost_list_output['heating_and_cooling'].to_f}") if cost_list_output['heating_and_cooling'] != cost_sum['heating_and_cooling']
      puts("SHW Cost Difference: #{cost_sum['shw'].to_f - cost_list_output['shw'].to_f}") if cost_list_output['shw'] != cost_sum['shw']
      puts("Ventilation Cost Difference: #{cost_sum['ventilation'].to_f - cost_list_output['ventilation'].to_f}") if cost_list_output['ventilation'] != cost_sum['ventilation']
      if cost_sum['grand_total'] == cost_list_output['grand_total']
        puts("No difference in costing between BTAP_Costing results and itemized cost list results.")
      else
        puts("Total Cost Difference: #{cost_sum['grand_total'].to_f - cost_list_output['grand_total'].to_f}")
      end
    end
  end
end
