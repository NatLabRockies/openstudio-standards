require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)


class NECB_HVAC_Fan_Rules_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate variable volume fan performance curves and pressure rise.
  def test_vav_fan_rules
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'NaturalGas',
                       baseboard_type: 'Hot Water',
                       chiller_type: 'Scroll',
                       heating_coil_type: 'Electric',
                       vavfan_type: 'AF_or_BI_rdg_fancurve'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3: 8.4.4.19.(4); 8.4.4.18."}
    
    # Test cases. Define each case seperately as they have unique kW values to test.
    test_cases_hash = {vintage: ['NECB2011'], 
                       TestCase: ["small"], 
                       TestPars: {:tested_max_flow_L_s => 1000}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2011'], 
                       TestCase: ["medium"], 
                       TestPars: {:tested_max_flow_L_s => 10000}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2011'], 
                       TestCase: ["large"], 
                       TestPars: {:tested_max_flow_L_s => 40000}}
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
    msg = "VAV fan test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_vav_fan_rules that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_vav_fan_rules(test_pars:, test_case:)

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
    baseboard_type = test_pars[:baseboard_type]
    heating_coil_type = test_pars[:heating_coil_type]
    vavfan_type = test_pars[:vavfan_type]

    # Test specific inputs.
    fan_flow = test_case[:tested_max_flow_L_s]

    # Define the test name. 
    name = "#{vintage}_sys6_vavfancap-#{fan_flow}L/s"
    name_short = "#{vintage}_VAV-#{fan_flow}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"

    # Wrap test in begin/rescue/ensure.
    begin
      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder,"5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(model: model,
                                                                          zones: model.getThermalZones,
                                                                          heating_coil_type: heating_coil_type,
                                                                          baseboard_type: baseboard_type,
                                                                          chiller_type: chiller_type,
                                                                          fan_type: vavfan_type,
                                                                          hw_loop: hw_loop)
      
      vavfans = model.getFanVariableVolumes
      vavfans.each do |ifan|
        ifan.setMaximumFlowRate(fan_flow/1000.0) 
      end

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # The code seems to be assigning the worng curve. See: 
    #  https://github.com/NREL/openstudio-standards/blob/f7d95c1a420d277b836251fd00e55c6a72310a92/lib/openstudio-standards/standards/necb/NECB2011/hvac_systems.rb#L1367
    # Not sure why this is not using the equation in 5.2.3.2

    # Recover the fans for checking. 
    results = Hash.new
    total_power = 0.0
    specific_eff = 0.0
    max_flow = 0.0
    vavfans = model.getFanVariableVolumes
    vavfans.each do |ifan|
      fan_name = ifan.name.to_s
      max_flow = ifan.maximumFlowRate.get
      static_p = ifan.pressureRise
      total_eff = ifan.fanTotalEfficiency
      fan_power = max_flow * static_p / (total_eff * 1000.0)
      total_power += fan_power
      results[fan_name.to_sym] = {
        fan_power_kW: fan_power.signif,
        pressure_rise_Pa: static_p.signif,
        max_flow_L_s: (max_flow * 1000.0).signif,
        min_flow_fraction: ifan.fanPowerMinimumFlowFraction.signif,
        power_min_flow_rate: ifan.fanPowerMinimumAirFlowRate.get.signif,
        motor_efficiency: ifan.motorEfficiency.signif(2),
        total_efficiency: total_eff.signif(2),
        power_coefficients: [
          ifan.fanPowerCoefficient1.get.signif(4),
          ifan.fanPowerCoefficient2.get.signif(4),
          ifan.fanPowerCoefficient3.get.signif(4),
          ifan.fanPowerCoefficient4.get.signif(4)
        ]
      }
    end
    specific_eff = total_power / max_flow
    results[:system] = {
      power_demand_per_flow: specific_eff.signif(3)
    }

    # Check economizer control.
    airloops = model.getAirLoopHVACs
    airloops.each do |iloop|
      loop_name = iloop.name.to_s
      oa_sys = iloop.airLoopHVACOutdoorAirSystem.get
      oa_ctl = oa_sys.getControllerOutdoorAir
      results[loop_name.to_sym] = {
        OA_system: oa_sys.name.to_s,
        OC_control: oa_ctl.name.to_s,
        economizer: oa_ctl.getEconomizerControlType.to_s
      }
    end
    return results
  end

  # Test to validate constant volume fan pressure rise and total efficiency.
  def test_cav_fan_rules
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'NaturalGas',
                       mau_type: true,
                       mau_heating_coil_type: 'Hot Water',
                       baseboard_type: 'Hot Water'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3: 8.4.4.19.(3)"}
    
    # Test cases. Define each case seperately as they have unique kW values to test.
    test_cases_hash = {vintage: ['NECB2011'], 
                       TestCase: ["cav_fan"], 
                       TestPars: {:tested_max_flow_L_s => 10000}}
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
    msg = "CAV fan test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_cav_fan_rules that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_cav_fan_rules(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    baseboard_type = test_pars[:baseboard_type]
    mau_type = test_pars[:mau_type]
    mau_heating_coil_type = test_pars[:mau_heating_coil_type]
    vintage = test_pars[:vintage]

    # Test specific inputs.
    fan_flow = test_case[:tested_max_flow_L_s]

    # Define the test name. 
    name = "#{vintage}_sys1"
    name_short = "#{vintage}_sys1"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"

    # Wrap test in begin/rescue/ensure.
    begin

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder,"5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys1_unitary_ac_baseboard_heating(model: model,
                                                              zones: model.getThermalZones,
                                                              mau_type: mau_type,
                                                              mau_heating_coil_type: mau_heating_coil_type,
                                                              baseboard_type: baseboard_type,
                                                              hw_loop: hw_loop)
      
      # Fan is normally autosized but set a flow rate here so we can check the specific power.
      cavfans = model.getFanConstantVolumes
      cavfans.each do |ifan|
        ifan.setMaximumFlowRate(fan_flow/1000.0) 
      end

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end
    
    # Recover the fans for checking. 
    results = Hash.new
    total_power = 0.0
    specific_eff = 0.0
    max_flow = 0.0
    cavfans = model.getFanConstantVolumes
    cavfans.each do |ifan|
      fan_name = ifan.name.to_s
      max_flow = ifan.maximumFlowRate.get
      static_p = ifan.pressureRise
      total_eff = ifan.fanTotalEfficiency
      fan_power = max_flow * static_p / (total_eff * 1000.0)
      total_power += fan_power
      results[fan_name.to_sym] = {
        fan_power_kW: fan_power.signif,
        pressure_rise_Pa: static_p.signif,
        max_flow_L_s: (max_flow * 1000.0).signif,
        motor_efficiency: ifan.motorEfficiency.signif(2),
        total_efficiency: total_eff.signif(2)
      }
    end
    specific_eff = total_power / max_flow
    results[:system] = {
      power_demand_per_flow: specific_eff.signif(3)
    }

    # Check economizer control.
    airloops = model.getAirLoopHVACs
    airloops.each do |iloop|
      loop_name = iloop.name.to_s
      oa_sys = iloop.airLoopHVACOutdoorAirSystem.get
      oa_ctl = oa_sys.getControllerOutdoorAir
      results[loop_name.to_sym] = {
        OA_system: oa_sys.name.to_s,
        OC_control: oa_ctl.name.to_s,
        economizer: oa_ctl.getEconomizerControlType.to_s
      }
    end
    return results
  end
end
