require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_Airloop_Sizing_Parameters_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate sizing rules for air loop
  def test_airloop_sizing_rules_vav
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: true,
      baseboard_type: 'Hot Water',
      chiller_type: 'Reciprocating',
      heating_coil_type: 'Electric',
      fan_type: 'AF_or_BI_rdg_fancurve'
    }

    # Define test cases.
    test_cases = {}
    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3:8.4.4.9.(1b,2b), 8.4.4.19.(2a, 2b)" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1:8.4.4.8.(1b,2b), 8.4.4.18.(2a, 2b)" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2:8.4.4.8.(1b,2b), 8.4.4.18.(2a, 2b)" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1:8.4.4.8.(1b,2b), 8.4.4.18.(2a, 2b)" }

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
    msg = "Sizing parameters test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  def do_test_airloop_sizing_rules_vav(test_pars:, test_case:)

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

    # Define the test name.
    name = "#{vintage}_#{fuel_type}_sys6"
    name_short = "#{vintage}_#{fuel_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    standard = get_standard(vintage)
    logger.info "Starting individual test: #{name}"

    # Wrap test in begin/rescue/ensure.
    begin
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: model.getThermalZones,
        heating_coil_type: heating_coil_type,
        baseboard_type: baseboard_type,
        chiller_type: chiller_type,
        fan_type: fan_type,
        hw_loop: hw_loop)

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS if PERFORM_STANDARDS

    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    airloops = model.getAirLoopHVACs
    results = Hash.new
    airloops.each do |iloop|
      iloop_name = iloop.name.get

      # Initialize an array to store thermal zone results for this air loop
      thermal_zone_results = []
      thermal_zones = iloop.thermalZones
      tot_floor_area = 0.0
      thermal_zones.each do |izone|
        izone_name = izone.name.get
        sizing_zone = izone.sizingZone

        # check sizing factors
        heating_sizing_factor = sizing_zone.zoneHeatingSizingFactor
        cooling_sizing_factor = sizing_zone.zoneCoolingSizingFactor

        # check supply temperature diffs and method
        design_clg_supply_temp_input_method = sizing_zone.zoneCoolingDesignSupplyAirTemperatureInputMethod.to_s
        design_htg_supply_temp_input_method = sizing_zone.zoneHeatingDesignSupplyAirTemperatureInputMethod.to_s
        heating_sizing_temp_diff = sizing_zone.zoneHeatingDesignSupplyAirTemperatureDifference
        cooling_sizing_temp_diff = sizing_zone.zoneCoolingDesignSupplyAirTemperatureDifference
        tot_floor_area += izone.floorArea

        # Add this test case to results and return the hash.
        thermal_zone_results << {
          thermal_zone_name: izone_name,
          heating_sizing_factor: heating_sizing_factor.to_f.signif(2),
          cooling_sizing_factor: cooling_sizing_factor.to_f.signif(2),
          design_clg_supply_temp_input_method: design_clg_supply_temp_input_method,
          design_htg_supply_temp_input_method: design_htg_supply_temp_input_method,
          heating_sizing_temp_diff: heating_sizing_temp_diff.signif(3),
          cooling_sizing_temp_diff: cooling_sizing_temp_diff.signif(3)
        }
      end
      results[iloop_name] = thermal_zone_results
    end
    # necb_min_flow_rate = 0.002 * tot_floor_area
    # demand_comps = iloop.demandComponents
    # tot_min_flow_rate = 0.0
    # demand_comps.each do |icomp|
    # if icomp.to_AirTerminalSingleDuctVAVReheat.is_initialized
    # vav_box = icomp.to_AirTerminalSingleDuctVAVReheat.get
    # tot_min_flow_rate += vav_box.fixedMinimumAirFlowRate
    # end
    # end
    # diff = (tot_min_flow_rate - necb_min_flow_rate).abs / necb_min_flow_rate
    # min_flow_rate_set_correctly = true
    # if diff > tol then min_flow_rate_set_correctly = false end
    # assert(min_flow_rate_set_correctly, "test_airloop_sizing_rules_vav: Minimum vav box flow rate does not match necb requirement #{name}")
    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate sizing rules for air loop
  def test_airloop_sizing_rules_heatpump
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: true,
      baseboard_type: 'Hot Water',
      heating_coil_type: 'DX'
    }

    # Define test cases.
    test_cases = {}

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3:8.4.4.9.(1b), 8.4.4.14.(2b), 8.4.4.19.(2a, 2b)" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1:8.4.4.8.(1b), 8.4.4.13.(2b), 8.4.4.18.(2a, 2b)" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2:8.4.4.8.(1b), 8.4.4.13.(2b), 8.4.4.18.(2a, 2b)" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1:8.4.4.8.(1b), 8.4.4.13.(2b), 8.4.4.18.(2a, 2b)" }

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
    msg = "Sizing parameters test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  def do_test_airloop_sizing_rules_heatpump(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    baseboard_type = test_pars[:baseboard_type]
    heating_coil_type = test_pars[:heating_coil_type]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]

    # Define the test name.
    name = "#{vintage}_#{fuel_type}_sys3"
    name_short = "#{vintage}_#{fuel_type}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    standard = get_standard(vintage)
    logger.info "Starting individual test: #{name}"

    # Wrap test in begin/rescue/ensure.
    begin

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
        model: model,
        zones: model.getThermalZones,
        heating_coil_type: heating_coil_type,
        baseboard_type: baseboard_type,
        hw_loop: hw_loop,
        new_auto_zoner: false)

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS if PERFORM_STANDARDS

    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    airloops = model.getAirLoopHVACs
    results = Hash.new
    airloops.each do |iloop|
      iloop_name = iloop.name.get

      # Initialize an array to store thermal zone results for this air loop
      thermal_zone_results = []
      thermal_zones = iloop.thermalZones
      tot_floor_area = 0.0
      thermal_zones.each do |izone|
        izone_name = izone.name.get
        sizing_zone = izone.sizingZone

        # check sizing factors
        heating_sizing_factor = sizing_zone.zoneHeatingSizingFactor
        cooling_sizing_factor = sizing_zone.zoneCoolingSizingFactor
        heating_sizing_temp_diff = sizing_zone.zoneHeatingDesignSupplyAirTemperatureDifference
        cooling_sizing_temp_diff = sizing_zone.zoneCoolingDesignSupplyAirTemperatureDifference
        tot_floor_area += izone.floorArea

        # Add this test case to results and return the hash.
        thermal_zone_results << {
          thermal_zone_name: izone_name,
          heating_sizing_factor: heating_sizing_factor.to_f.signif(2),
          cooling_sizing_factor: cooling_sizing_factor.to_f.signif(2),
          heating_sizing_temp_diff: heating_sizing_temp_diff.signif(3),
          cooling_sizing_temp_diff: cooling_sizing_temp_diff.signif(3)
        }
      end
      results[iloop_name] = thermal_zone_results
    end
    logger.info "Completed individual test: #{name}"
    return results
  end
end
