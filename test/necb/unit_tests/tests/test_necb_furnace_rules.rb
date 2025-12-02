require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_HVAC_Furnace_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the furnace efficiency generated against expected values.
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_furnace_efficiency
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: false,
                        stage_types: 'single' }

    # Define test cases.
    test_cases = {}
    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3 Table 5.2.12.1" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1 Table 5.2.12.1" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2 Table 5.2.12.1" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1 Table 5.2.12.1.-O" }

    # Test cases. Two cases for NG and one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: @AllTemplates,
                        :heating_coil_types => ['Electric'],
                        TestCase: ["case-1"],
                        TestPars: { :tested_capacity_kW => 10.0,
                                       :baseboard_type => "Electric",
                                       :efficiency_metric => "thermal efficiency" } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # AFUE : Testing the capacity of 58.65 kW lies within the range of 0-117.23 kW for NECB2011, 0-66 kW for NECB2015 and NECB2017, also 0-66 kW for NECB2020
    # Thermal efficiency : Testing the capacity of 127.3 kW lies within the range of 117.3-2930 kW for NECB2011, 66.1-2930 kW for NECB2015 and NECB2017, also 66.1-2930 kW for NECB2020
    test_cases_hash = { vintage: @AllTemplates,
                        :heating_coil_types => ["NaturalGas"],
                        TestCase: ["case-1"],
                        TestPars: { :tested_capacity_kW => 58.65,
                                       :baseboard_type => "Hot Water",
                                       :efficiency_metric => "annual fuel utilization efficiency" } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        :heating_coil_types => ["NaturalGas"],
                        TestCase: ["case-2"],
                        TestPars: { :tested_capacity_kW => 127.3,
                                       :baseboard_type => "Hot Water",
                                       :efficiency_metric => "thermal efficiency" } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # Create empty results hash and call the template method that runs the individual test cases.
    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    file_root = "#{self.class.name}-#{__method__}".downcase
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Read expected results.
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), { symbolize_names: true })
    # Check if test results match expected.
    msg = "furnace efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_furnace_efficiency that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_furnace_efficiency(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    heating_coil_type = test_pars[:heating_coil_types]
    baseboard_type = test_case[:baseboard_type]
    vintage = test_pars[:vintage]

    # Test specific inputs.
    furnace_cap = test_case[:tested_capacity_kW]
    efficiency_metric = test_case[:efficiency_metric]

    name = "#{vintage}_sys3_Furnace-#{heating_coil_type}_cap-#{furnace_cap}kW_Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_#{furnace_cap}_sys3_Furnace"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Array.new

    # Wrap test in begin/rescue/ensure.
    begin
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models
      standard = get_standard(vintage)
      always_on = model.alwaysOnDiscreteSchedule
      hw_loop = nil
      if baseboard_type == 'Hot Water'
        hw_loop = OpenStudio::Model::PlantLoop.new(model)
        standard.setup_hw_loop_with_components(model, hw_loop, heating_coil_type, heating_coil_type, always_on)
      end
      sys3_heating_coil_type = 'Electric'
      sys3_heating_coil_type = 'Gas' if heating_coil_type == 'NaturalGas'

      # Single stage furnace.
      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model: model,
                                                                                                  zones: model.getThermalZones,
                                                                                                  heating_coil_type: sys3_heating_coil_type,
                                                                                                  baseboard_type: baseboard_type,
                                                                                                  hw_loop: hw_loop,
                                                                                                  new_auto_zoner: false)
      model.getCoilHeatingGass.each { |coil| coil.setNominalCapacity(furnace_cap * 1000.0) }

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract the results for checking.
    test_efficiency_value = 0
    if heating_coil_type == 'NaturalGas'
      test_efficiency_value = model.getCoilHeatingGass[0].gasBurnerEfficiency
    elsif heating_coil_type == 'Electric'
      test_efficiency_value = model.getCoilHeatingElectrics[0].efficiency
    end
    # Convert efficiency depending on the metric being used.
    if efficiency_metric == 'annual fuel utilization efficiency'
      test_efficiency_value = OpenstudioStandards::HVAC.thermal_eff_to_afue(test_efficiency_value)
    elsif efficiency_metric == 'thermal efficiency'
      test_efficiency_value = test_efficiency_value
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(furnace_cap, 'kW', 'Btu/hr').get
    # Add this test case to results and return the hash.
    results = {
      name: name,
      baseboard_type: baseboard_type,
      heating_coil_type: heating_coil_type,
      tested_capacity_kW: furnace_cap.signif,
      tested_capacity_Btu_per_hr: capacity_btu_per_hr.signif,
      efficiency_metric: efficiency_metric,
      efficiency_value: test_efficiency_value.signif(3)
    }

    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate the furnace part load performance curve.
  def test_furnace_plf_vs_plr_curve
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: false,
                        heating_coil_type: 'Gas',
                        baseboard_type: 'Hot Water' }

    # Define test cases.
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3 Table 8.4.4.22.A" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1 Table 8.4.4.21.-A" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2 Table 8.4.4.21.-A" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1 Table 8.4.5.3" }

    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["NaturalGas"],
                        TestCase: ["SingleStage"],
                        TestPars: { :stage => "Single" } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # Create empty results hash and call the template method that runs the individual test cases.
    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    file_root = "#{self.class.name}-#{__method__}".downcase
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Read expected results.
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), {symbolize_names: true})

    # Check if test results match expected.
    msg = "Furnace plf vs plr curve coeffs test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_furnace_plf_vs_plr_curve that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_furnace_plf_vs_plr_curve(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    heating_coil_type = test_pars[:heating_coil_type]
    baseboard_type = test_pars[:baseboard_type]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    stage_type = test_case[:stage]

    name = "#{vintage}_sys3_Furnace-#{fuel_type}_#{heating_coil_type}_Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_sys3_Furnace"
    output_folder = method_output_folder("#{test_name}/#{name_short}")

    logger.info "Starting individual test: #{name}"
    results = Array.new

    # Wrap test in begin/rescue/ensure.
    begin
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models
      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      # Single stage furnace.
      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model: model,
                                                                                                  zones: model.getThermalZones,
                                                                                                  heating_coil_type: heating_coil_type,
                                                                                                  baseboard_type: baseboard_type,
                                                                                                  hw_loop: hw_loop,
                                                                                                  new_auto_zoner: false)

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS

    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract the results for checking.
    model.getCoilHeatingGass.sort.each do |mod_furnace|
      heatingCoil_name = mod_furnace.name.get
      furnace_curve = mod_furnace.partLoadFractionCorrelationCurve.get.to_CurveCubic.get
      furnace_curve_name = furnace_curve.name.get
      results << {
        name: heatingCoil_name.to_sym,
        curve_name: furnace_curve_name,
        type: "cubic",
        coeff1: furnace_curve.coefficient1Constant,
        coeff2: furnace_curve.coefficient2x,
        coeff3: furnace_curve.coefficient3xPOW2,
        coeff4: furnace_curve.coefficient4xPOW3,
        min_x: furnace_curve.minimumValueofx,
        max_x: furnace_curve.maximumValueofx
      }
    end
    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate number of stages for multi furnaces
  # *** Method re-named so that test not run as multi stage fails ***
  # Test fail with error : NoMethodError: undefined method
  # `autosizedSpeed2GrossRatedTotalCoolingCapacity|' for #<OpenStudio::Model::CoilCoolingDXMultiSpeed:0x0000000009476978>|n
  # lib/openstudio-standards/standards/Standards.CoilCoolingDXMultiSpeed.rb:232:in
  # `coil_cooling_dx_multi_speed_find_capacity|'
  # *** Not active as multi_stage coils do not work ***
  def donot_test_furnace_num_stages
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = { TestMethod: __method__,
                        SaveIntermediateModels: false,
                        fuel_type: 'NaturalGas',
                        heating_coil_type: 'Gas',
                        baseboard_type: 'Hot Water' }

    # Define test cases.
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3 " }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1 " }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2 " }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1 " }

    # Test cases.
    test_cases_hash = { vintage: @AllTemplates,
                        TestCase: ["Test-small"],
                        TestPars: { :capacity_kW => 33.0 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = { vintage: @AllTemplates,
                        TestCase: ["Test-medium"],
                        TestPars: { :capacity_kW => 67.0  } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = { vintage: @AllTemplates,
                        TestCase: ["Test-large"],
                        TestPars: { :capacity_kW => 133.0 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = { vintage: @AllTemplates,
                        TestCase: ["Test-xlarge"],
                        TestPars: { :capacity_kW => 199.0 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # Create empty results hash and call the template method that runs the individual test cases.
    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    file_root = "#{self.class.name}-#{__method__}".downcase
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Read expected results.
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), {symbolize_names: true})

    # Check if test results match expected.
    msg = "Furnace number of stages test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_furnace_num_stages that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_furnace_num_stages(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    heating_coil_type = test_pars[:heating_coil_type]
    baseboard_type = test_pars[:baseboard_type]
    vintage = test_pars[:vintage]

    # Test specific values.
    cap = test_case[:capacity_kW]

    # Set up remaining parameters for test.

    name = "#{vintage}_sys3_Furnace-#{heating_coil_type}_cap-#{cap}kW_Baseboard-#{baseboard_type}"
    name_short = "Furnace-#{cap}kW"
    output_folder = method_output_folder("#{test_name}/#{name_short}")

    logger.info "Starting individual test: #{name}"
    results = Array.new
    begin

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(model: model,
                                                                                                 zones: model.getThermalZones,
                                                                                                 heating_coil_type: heating_coil_type,
                                                                                                 baseboard_type: baseboard_type,
                                                                                                 hw_loop: hw_loop,
                                                                                                 new_auto_zoner: true)
      model.getCoilHeatingGasMultiStages.each { |coil| coil.stages.last.setNominalCapacity(cap*1000.0) }

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS

    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Generate the osm files for all relevant cases to generate the test data for system 3. 2011 results:
    #caps = [33000.0, 66001.0, 132001.0, 198001.0]
    #num_stages_needed = {}
    #num_stages_needed[33000.0] = 2
    #num_stages_needed[66001.0] = 2
    #num_stages_needed[132001.0] = 3
    #num_stages_needed[198001.0] = 4
    # Extract the results for checking.  *** This needs to be checked for completion once multi stage furnace working ***
    coils = model.getCoilHeatingGasMultiStages
    stages = []
    coils.each do |coil|
      stages << coil.stages.size
    end
    results = {
      furnace_capacity_kW: cap,
      number_of_stages: stages
    }
    logger.info "Completed individual test: #{name}"
    return results
  end
end
