require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_HVAC_Loop_Rules_Tests < Minitest::Test

  # Set to true to run the standards in the test.
  PERFORM_STANDARDS = true

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate hot water loop rules
  def test_hw_loop_rules
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: true,
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      heating_coil_type: 'Electric',
      fan_type: 'AF_or_BI_rdg_fancurve'
    }

    # Define test cases.
    test_cases = {}
    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3:8.4.4.10.(6h)" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1:8.4.4.9.(6h)" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2:8.4.4.9.(6h)" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1:8.4.4.9.(6h)" }

    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["NaturalGas"],
                        TestCase: ["case-1"],
                        TestPars: { :name => "tbd" } }
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
    msg = "Hot water loop rules test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_hw_loop_rules that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_hw_loop_rules(test_pars:, test_case:)
    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    baseboard_type = test_pars[:baseboard_type]
    heating_coil_type = test_pars[:heating_coil_type]
    fan_type = test_pars[:fan_type]
    chiller_type = test_pars[:chiller_type]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    hasVariablePump = true
    results = {}
    # Define the test name.
    name = "#{vintage}_#{fuel_type}"
    name_short = "#{vintage}_#{fuel_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    standard = get_standard(vintage)
    logger.info "Starting individual test: #{name}"

    # Wrap test in begin/rescue/ensure.
    begin
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC5Storeys.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models
      # Generate the osm files for all relevant cases to generate the test data for system 6
      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(model: model,
                                                                          zones: model.getThermalZones,
                                                                          heating_coil_type: heating_coil_type,
                                                                          baseboard_type: baseboard_type,
                                                                          chiller_type: chiller_type,
                                                                          fan_type: fan_type,
                                                                          hw_loop: hw_loop)
      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end
    loops = model.getPlantLoops
    loops.each do |iloop|
      iloop_name = iloop.name.to_s
      if iloop_name == 'Hot Water Loop'
        deltaT = iloop.sizingPlant.loopDesignTemperatureDifference
        supply_comps = iloop.supplyComponents
        supply_comps.each do |icomp|
          hasVariablePump = false if icomp.to_PumpConstantSpeed.is_initialized
        end
        supply_out_node = iloop.supplyOutletNode
        set_point_manager = supply_out_node.setpointManagers[0].to_SetpointManagerOutdoorAirReset.get
        spm_outdoorLowTemperature = set_point_manager.outdoorLowTemperature
        spm_outdoorHighTemperature = set_point_manager.outdoorHighTemperature
        spm_setpointatOutdoorLowTemperature = set_point_manager.setpointatOutdoorLowTemperature
        spm_setpointatOutdoorHighTemperature = set_point_manager.setpointatOutdoorHighTemperature

        # Add this test case to results and return the hash.
        results[iloop_name] = {
          name: iloop_name,
          loopDesignTemperatureDifference: deltaT,
          hasVariablePump: hasVariablePump,
          set_point_manager_outdoorLowTemperature: spm_outdoorLowTemperature,
          set_point_manager_outdoorHighTemperature: spm_outdoorHighTemperature,
          set_point_manager_setpointatOutdoorLowTemperature: spm_setpointatOutdoorLowTemperature,
          set_point_manager_setpointatOutdoorHighTemperature: spm_setpointatOutdoorHighTemperature
        }
      end
    end
    return results
    logger.info "Completed individual test: #{name}"
  end

  # Test to validate chilled water loop rules
  def test_chw_loop_rules
    logger.info "Starting suite of tests for: #{__method__}"
    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: true,
      chiller_type: 'Centrifugal',
      mau_cooling_type: 'DX',
      fan_coil_type: 'FPFC'
    }

    # Define test cases.
    test_cases = {}
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3: 8.4.4.11.(6g); 8.4.4.12.(1b,6c)" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1: 8.4.4.10.(6g); 8.4.4.11.(1b,6c)" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2: 8.4.4.10.(6g); 8.4.4.11.(1b,6c)" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1: 8.4.4.10.(6g); 8.4.4.11.(1b,6c)" }

    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["case-1"],
                        TestPars: { :name => "tbd" } }
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
    msg = "Chilled water or condenser loop rules test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test chilled and condensed water loop rules. Called by do_test_cases in necb_helper.rb.
  def do_test_chw_loop_rules(test_pars:, test_case:)
    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    chiller_type = test_pars[:chiller_type]
    mau_cooling_type = test_pars[:mau_cooling_type]
    fan_coil_type = test_pars[:fan_coil_type]
    hasVariablePump = true
    results = {}
    # Define the test name.
    name = "#{vintage}_#{fuel_type}_sys2_chw"
    name_short = "#{vintage}_#{fuel_type}_sys2_chw"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"

    # Wrap test in begin/rescue/ensure.
    begin
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, '5ZoneNoHVAC.osm'))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models
      # Generate the osm files for all relevant cases to generate the test data for system 6
      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.fuel_type_set = SystemFuels.new()
      standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: fuel_type)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys2_FPFC_sys5_TPFC(model: model,
                                       zones: model.getThermalZones,
                                       chiller_type: chiller_type,
                                       fan_coil_type: fan_coil_type,
                                       mau_cooling_type: mau_cooling_type,
                                       hw_loop: hw_loop)

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end
    loops = model.getPlantLoops
    loops.each do |iloop|
      iloop_name = iloop.name.to_s
      deltaT = iloop.sizingPlant.loopDesignTemperatureDifference
      # Check the supply loop. There should be a variable speed pump.
      supply_comps = iloop.supplyComponents
      supply_comps.each do |icomp|
        hasVariablePump = false if icomp.to_PumpConstantSpeed.is_initialized
      end
      if iloop_name == 'Chilled Water Loop'
        supply_out_node = iloop.supplyOutletNode
        set_point_manager = supply_out_node.setpointManagers[0].to_SetpointManagerScheduled.get
        setpoint_sch = set_point_manager.schedule.to_ScheduleRuleset.get
        sch_rules = setpoint_sch.scheduleRules
        sch_rules.each do |rule|
          schedule_rule_name = rule.name.get
          day_sch = rule.daySchedule
          setpoints = day_sch.values

          # Add this test case to results and return the hash.
          results[iloop_name] = {
            name: iloop_name,
            has_variable_pump: hasVariablePump,
            loop_design_temperature_difference: deltaT,
            schedule_rule_name: schedule_rule_name,
            hourly_setpoints: setpoints
          }
        end
      elsif iloop.name.to_s == 'Condenser Water Loop'
        deltaT = iloop.sizingPlant.loopDesignTemperatureDifference
        exitT = iloop.sizingPlant.designLoopExitTemperature
        supply_out_node = iloop.supplyOutletNode
        set_point_manager = supply_out_node.setpointManagers[0].to_SetpointManagerScheduled.get
        setpoint_sch = set_point_manager.schedule.to_ScheduleRuleset.get
        sch_rules = setpoint_sch.scheduleRules
        sch_rules.each do |rule|
          schedule_rule_name = rule.name.get
          day_sch = rule.daySchedule
          setpoints = day_sch.values
          results[iloop_name] = {
            name: iloop_name,
            has_variable_pump: hasVariablePump,
            loop_design_temperature_difference: deltaT,
            condenser_water_loop_exit_temperature: exitT,
            schedule_rule_name: schedule_rule_name,
            hourly_setpoints: setpoints
          }
        end
      end
    end
    return results
    logger.info "Completed individual test: #{name}"
  end
end
