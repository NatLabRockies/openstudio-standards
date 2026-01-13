require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)


class NECB_HVAC_Chiller_Test < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # For NECB 2020 testing, for all chiller types except the centrifugal chillers, I don't think we can test the last row of NECB2020 code of capacities more than 2110 kw, as it will be divided into 2 chillers,
  # each chiller will have 1055 kW and that would move it to the upper row of NECB2020 code and COP will be always 5.633 not 6.018 (Mariana)
  # Consequently i've updated the expected results for all chiller types except the centrifugal chillers that are more then 2110 kW (7,200,000 btu/hr) to be 5.633 not 6.018
  def test_NECB_chiller_cop
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false,
                       fuel_type: 'Electricity',
                       mau_cooling_type: 'Hydronic'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 Table 5.2.12.1. Points to CSA-C743-09"}
    test_cases[:NECB2015] = {Reference: "NECB 2015 p1 Table 5.2.12.1. Points to CSA-C743-09"}
    test_cases[:NECB2017] = {Reference: "NECB 2017 p2 Table 5.2.12.1. Points to CSA-C743-09"}
    test_cases[:NECB2020] = {Reference: "NECB 2020 p1 Table 5.2.12.1.-K (Path B)"}
    
    # Test cases. Define each case seperately as they have unique kW values to test accross the vintages/chiller types.
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["small"], 
                       TestPars: {:tested_capacity_kW => 132}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["medium"], 
                       TestPars: {:tested_capacity_kW => 396}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["large"], 
                       TestPars: {:tested_capacity_kW => 791}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["x-large"], 
                       TestPars: {:tested_capacity_kW => 1200}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2020'], 
                       chiller_type: ["Scroll", "Rotary Screw", "Reciprocating"],
                       TestCase: ["xx-large"], 
                       TestPars: {:tested_capacity_kW => 2200}}
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
    msg = "Chiller COP test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_NECB_chiller_cop that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_NECB_chiller_cop(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    mau_cooling_type = test_pars[:mau_cooling_type]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    chiller_type = test_pars[:chiller_type]

    # Test specific inputs.
    chiller_cap = test_case[:tested_capacity_kW]

    # Define the test name. 
    name = "#{vintage}_sys2_ChillerType-#{chiller_type}_Chiller_cap-#{chiller_cap}kW"
    name_short = "#{vintage}_sys2_Chiller-#{chiller_type}_cap-#{chiller_cap}kW"
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
      standard.fuel_type_set = SystemFuels.new()
      standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: fuel_type)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys2_FPFC_sys5_TPFC(model: model,
                                      zones: model.getThermalZones,
                                      chiller_type: chiller_type,
                                      fan_coil_type: 'FPFC',
                                      mau_cooling_type: mau_cooling_type,
                                      hw_loop: hw_loop)
      model.getChillerElectricEIRs.each {|chiller| chiller.setReferenceCapacity(chiller_cap*1000.0)}

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Recover the COP for checking. 
    results = Hash.new
    chiller_count = 0
    total_capacity = 0.0
    model.getChillerElectricEIRs.each do |chiller|
      next if chiller.referenceCapacity.to_f < 0.1

      # Add this test case to results.
      chiller_count += 1
      chiller_capacity = (chiller.referenceCapacity.to_f)/1000.0
      total_capacity += chiller_capacity
      chillerID = "Chiller-#{chiller_count}"
      results[chillerID.to_sym] = {
        name: chiller.name.to_s,
        capacity_kW: chiller_capacity.signif(3),
        capacity_ton: OpenStudio.convert(chiller_capacity, 'kW', 'ton').get.signif,
        capacity_BTUh: OpenStudio.convert(chiller_capacity, 'kW', 'kBtu/hr').get.signif,
        COP_kW_kW: chiller.referenceCOP.to_f.signif(3),
        COP_kW_ton: OpenStudio.convert((1.0/chiller.referenceCOP.to_f), '1/kW', '1/ton').get.signif
      }
    end
    results[:All] = {
      tested_capacity_kW: (chiller_cap.to_f).signif(3), 
      total_capacity_kW: (total_capacity).signif(3), 
      number_of_chillers: chiller_count,
    }

    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate the number of chillers used and their capacities depending on total cooling capacity.
  # NECB2011 rule for number of chillers is:
  # "if capacity <= 2100 kW ---> one chiller
  # if capacity > 2100 kW ---> 2 chillers with half the capacity each"
  def test_number_of_chillers
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false,
                       fuel_type: 'Electricity',
                       baseboard_type: 'Hot Water',
                       heating_coil_type: 'Hot Water',
                       fan_type: 'AF_or_BI_rdg_fancurve'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 8.4.4.11.(6)"}
    test_cases[:NECB2015] = {Reference: "xx"}
    test_cases[:NECB2017] = {Reference: "xx"}
    test_cases[:NECB2020] = {Reference: "NECB 2011 p3 8.4.4.10.(6)"}
    
    # Test cases. Define each case seperately as they have unique kW values to test accross the vintages/chiller types.
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["single"], 
                       TestPars: {:tested_capacity_kW => 800}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["twin"], 
                       TestPars: {:tested_capacity_kW => 3200}}
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
    msg = "Number of chillers and capacity test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_number_of_chillers that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_number_of_chillers (test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    baseboard_type = test_pars[:baseboard_type]
    heating_coil_type = test_pars[:heating_coil_type]
    fan_type = test_pars[:fan_type]
    vintage = test_pars[:vintage]
    chiller_type = test_pars[:chiller_type]

    # Test specific inputs.
    chiller_cap = test_case[:tested_capacity_kW]
      
    # Wrap test in begin/rescue/ensure.
    begin

      # Define the test name. 
      name = "#{vintage}_sys6_ChillerType_#{chiller_type}-Chiller_cap-#{chiller_cap}kW"
      name_short = "#{vintage}_sys6_Chiller-#{chiller_type}_cap-#{chiller_cap}kW"
      output_folder = method_output_folder("#{test_name}/#{name_short}")
      logger.info "Starting individual test: #{name}"

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.fuel_type_set = SystemFuels.new()
      standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: fuel_type)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(model: model,
                                                                          zones: model.getThermalZones,
                                                                          heating_coil_type: heating_coil_type,
                                                                          baseboard_type: baseboard_type,
                                                                          chiller_type: chiller_type,
                                                                          fan_type: fan_type,
                                                                          hw_loop: hw_loop)
      model.getChillerElectricEIRs.each {|ichiller| ichiller.setReferenceCapacity(chiller_cap*1000.0)}

      # Run the standards.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Recover the chillers for checking. 
    results = Hash.new
    chiller_count = 0
    total_capacity = 0.0
    model.getChillerElectricEIRs.each do |chiller|
      next if chiller.referenceCapacity.to_f < 0.1

      # Add this test case to results.
      chiller_count += 1
      chiller_capacity = (chiller.referenceCapacity.to_f)/1000.0
      total_capacity += chiller_capacity
      chillerID = "Chiller-#{chiller_count}"
      results[chillerID.to_sym] = {
        name: chiller.name.to_s,
        capacity_kW: chiller_capacity.signif(3),
        capacity_ton: OpenStudio.convert(chiller_capacity, 'kW', 'ton').get.signif(3),
        capacity_BTUh: OpenStudio.convert(chiller_capacity, 'kW', 'kBtu/hr').get.signif(3),
        minimum_part_load_ratio: chiller.minimumPartLoadRatio.signif(3)
      }
    end
    results[:All] = {
      tested_capacity_kW: (chiller_cap.to_f).signif(3), 
      total_capacity_kW: (total_capacity).signif(3), 
      number_of_chillers: chiller_count,
    }

    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate the chiller performance curves.
  def test_chiller_curves
    logger.info "Starting suite of tests for: #{__method__}"
    
    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false,
                       fuel_type: 'NaturalGas',
                       mau_cooling_type: 'Hydronic',
                       
                       baseboard_type: 'Hot Water',
                       heating_coil_type: 'Hot Water',
                       fan_type: 'AF_or_BI_rdg_fancurve'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 Table 8.4.4.22.C"}
    test_cases[:NECB2015] = {Reference: "xx"}
    test_cases[:NECB2017] = {Reference: "xx"}
    test_cases[:NECB2020] = {Reference: "xx"}
    
    # Test cases. Define each case seperately as they have unique kW values to test accross the vintages/chiller types.
    test_cases_hash = {vintage: ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'], 
    #test_cases_hash = {vintage: ['NECB2011'], 
                       chiller_type: ["Scroll", "Centrifugal", "Rotary Screw", "Reciprocating"],
                       TestCase: ["small"], 
                       TestPars: {:tested_capacity_kW => 800}}
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
    msg = "Chiller performance curve coeffs test results do not match expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_chiller_curves that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_chiller_curves (test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    fuel_type = test_pars[:fuel_type]
    mau_cooling_type = test_pars[:mau_cooling_type]

    baseboard_type = test_pars[:baseboard_type]
    heating_coil_type = test_pars[:heating_coil_type]
    fan_type = test_pars[:fan_type]
    vintage = test_pars[:vintage]
    chiller_type = test_pars[:chiller_type]

    # Test specific inputs.
    chiller_cap = test_case[:tested_capacity_kW]
      
    # Wrap test in begin/rescue/ensure.
    begin

      # Define the test name. 
      name = "#{vintage}_sys5_ChillerType_#{chiller_type}"
      name_short = "#{vintage}_sys5_ChillerType_#{chiller_type}"
      output_folder = method_output_folder("#{test_name}/#{name_short}")
      logger.info "Starting individual test: #{name}"

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard = get_standard(vintage)
      standard.fuel_type_set = SystemFuels.new()
      standard.fuel_type_set.set_defaults(standards_data: standard.standards_data, primary_heating_fuel: fuel_type)
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys2_FPFC_sys5_TPFC(model: model,
                                       zones: model.getThermalZones,
                                       chiller_type: chiller_type,
                                       fan_coil_type: 'FPFC',
                                       mau_cooling_type: mau_cooling_type,
                                       hw_loop: hw_loop)

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract the results for checking. There are sometimes two chillers.
    results = Hash.new
    chillers = model.getChillerElectricEIRs
    chillers.each do |chiller|

      # Skip chillers that are sized zero.
      next if chiller.referenceCapacity.to_f < 0.1

      eff_curve_name, eff_curve_type, corr_coeff = get_curve_info(chiller.coolingCapacityFunctionOfTemperature)
      chiller_capacity = (chiller.referenceCapacity.to_f)/1000.0
      capacity_kW = chiller_capacity
      chiller_name = chiller.name.get
      results[chiller_name.to_sym] = {
          chiller_name: chiller_name,
          capacity_kW: capacity_kW.signif(3),
          eff_curve_name: eff_curve_name,
          eff_curve_type: eff_curve_type,
          curve_coefficients: corr_coeff
      }
    end

    logger.info "Completed individual test: #{name}"
    return results
  end
end
