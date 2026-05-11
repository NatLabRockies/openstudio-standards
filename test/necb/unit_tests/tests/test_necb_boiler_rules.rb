require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)


class NECB_HVAC_Boiler_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the boiler thermal efficiency generated against expected values.
  #  Makes use of the template design pattern with the work done by the do_* method below (i.e. 'do_' prepended to the current method name)
  def test_boiler_efficiency
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       mau_type: true,
                       mau_heating_coil_type: 'Hot Water',
                       baseboard_type: 'Hot Water'}

    # Define test cases.
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 Table 5.2.12.1"}

    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["Electricity"],
                       TestCase: ["case-1"],
                       TestPars: {:tested_capacity_kW => 10.0,
                                     :efficiency_metric => "thermal efficiency"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["NaturalGas", "FuelOilNo2"],
                       TestCase: ["case-1"],
                       TestPars: {:name => "tbd",
                                     :tested_capacity_kW => 43.96,
                                     :efficiency_metric => "annual fuel utilization efficiency",
                                     :efficiency_value => "tbd"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["NaturalGas", "FuelOilNo2"],
                       TestCase: ["case-2"],
                       TestPars: {:name => "tbd",
                                     :tested_capacity_kW => 410.3,
                                     :efficiency_metric => "thermal efficiency",
                                     :efficiency_value => "tbd"}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["NaturalGas", "FuelOilNo2"],
                       TestCase: ["case-3"],
                       TestPars: {:name => "tbd",
                                     :tested_capacity_kW => 2510,
                                     :efficiency_metric => "combustion efficiency",
                                     :efficiency_value => "tbd"}}
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
    msg = "Boiler efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_boiler_efficiency that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_boiler_efficiency(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    mau_type = test_pars[:mau_type]
    mau_heating_coil_type = test_pars[:mau_heating_coil_type]
    baseboard_type = test_pars[:baseboard_type]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]

    # Test specific inputs.
    boiler_cap = test_case[:tested_capacity_kW]
    efficiency_metric = test_case[:efficiency_metric]

    # Define the test name.
    name = "#{vintage}_sys1_Boiler-#{fuel_type}_cap-#{boiler_cap.to_int}kW_MAU-#{mau_type}_MauCoil-#{mau_heating_coil_type}_Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_sys1_Boiler-#{fuel_type}_cap-#{boiler_cap.to_int}kW"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

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
      standard.add_sys1_unitary_ac_baseboard_heating(model: model,
                                                    zones: model.getThermalZones,
                                                    mau_type: mau_type,
                                                    mau_heating_coil_type: mau_heating_coil_type,
                                                    baseboard_type: baseboard_type,
                                                    hw_loop: hw_loop)

      # Set the boiler capacity. Convert from kw to W first.
      model.getBoilerHotWaters.each {|iboiler| iboiler.setNominalCapacity(boiler_cap*1000.0)}

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Recover the thermal efficiency set in the measure for checking below.
    test_efficiency_value = 0
    model.getBoilerHotWaters.each do |iboiler|
      if iboiler.nominalCapacity.to_f > 1
        test_efficiency_value = iboiler.nominalThermalEfficiency
        break
      end
    end

    # Convert efficiency depending on the metric being used.
    if efficiency_metric == 'annual fuel utilization efficiency'
      test_efficiency_value = OpenstudioStandards::HVAC.thermal_eff_to_afue(test_efficiency_value)
    elsif efficiency_metric == 'combustion efficiency'
      test_efficiency_value = OpenstudioStandards::HVAC.thermal_eff_to_comb_eff(test_efficiency_value)
    elsif efficiency_metric == 'thermal efficiency'
      test_efficiency_value = test_efficiency_value
    end

    # Add this test case to results and return the hash.
    results = {
      name: name,
      tested_capacity_kW: boiler_cap.signif,
      efficiency_metric: efficiency_metric,
      efficiency_value: test_efficiency_value.signif(3)
    }
    logger.info "Completed individual test: #{name}"
    return results
  end


  # Test to validate the number of boilers used and their capacities depending on total heating capacity.
  # NECB2011 rule for number of boilers is:
  # if capacity <= 176 kW ---> one single stage boiler
  # if capacity > 176 kW and <= 352 kW ---> 2 boilers of equal capacity
  # if capacity > 352 kW ---> one modulating boiler down to 25% of capacity"
  def test_number_of_boilers
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'NaturalGas',
                       mau_type: true,
                       heating_coil_type: 'Electric',
                       baseboard_type: 'Hot Water'}

    # Define test cases.
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 8.4.4.10.(6) clauses b,c,d"}

    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["NaturalGas"],
                       TestCase: ["Single_Small_Boiler"],
                       TestPars: {:tested_capacity_kW => 100}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["NaturalGas"],
                       TestCase: ["Two_Equal_Sized_Boilers"],
                       TestPars: {:tested_capacity_kW => 200}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    test_cases_hash = {vintage: @AllTemplates,
                       fuel_type: ["NaturalGas"],
                       TestCase: ["Single_Large_Boiler"],
                       TestPars: {:tested_capacity_kW => 400}}
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    # Read expected results. This is used to set the tested cases as the parameters change depending on the
    # fuel type and boiler size.
    file_root = "#{self.class.name}-#{__method__}".downcase
    file_name = File.join(@expected_results_folder, "#{file_root}-expected_results.json")
    expected_results = JSON.parse(File.read(file_name), {symbolize_names: true})

    # Create empty results hash and call the template method that runs the individual test cases.
    test_results = do_test_cases(test_cases: test_cases, test_pars: test_parameters)

    # Write test results.
    test_result_file = File.join(@test_results_folder, "#{file_root}-test_results.json")
    File.write(test_result_file, JSON.pretty_generate(test_results))

    # Check if test results match expected.
    msg = "Boiler efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')

    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_number_of_boilers that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_number_of_boilers(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    mau_type = test_pars[:mau_type]
    heating_coil_type = test_pars[:heating_coil_type]
    baseboard_type = test_pars[:baseboard_type]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]

    # Test specific inputs.
    total_boiler_cap = test_case[:tested_capacity_kW]

    # Define the test name.
    name = "#{vintage}_Sys1_#{total_boiler_cap.round(0)}kW_#{fuel_type}_boiler_HeatingCoilType-#{heating_coil_type}_Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_sys1_#{total_boiler_cap.round(0)}kW_#{fuel_type}_boiler"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

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
      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model: model,
                                                                                                  zones: model.getThermalZones,
                                                                                                  heating_coil_type: heating_coil_type,
                                                                                                  baseboard_type: baseboard_type,
                                                                                                  hw_loop: hw_loop,
                                                                                                  new_auto_zoner: false)
      model.getBoilerHotWaters.each {|iboiler| iboiler.setNominalCapacity(total_boiler_cap*1000.0)}

      # Run sizing. Is this required?
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Check that there are two boilers in the model. BTAP sets the second boiler to 0.001 W if the rules say only one boiler required.
    boilers = model.getBoilerHotWaters
    boiler_count = 0
    total_capacity = 0.0
    boilers.each do |boiler|

      # Skip boilers that are sized zero.
      next if boiler.nominalCapacity.to_f < 0.1

      # Add this test case to results.
      boiler_count += 1
      boiler_capacity = (boiler.nominalCapacity.to_f)/1000.0
      total_capacity += boiler_capacity
      boilerID = "Boiler-#{boiler_count}"
      results[boilerID.to_sym] = {
        name: boiler.name.to_s,
        boiler_capacity_kW: (boiler_capacity).signif,
        minimum_part_load_ratio: boiler.minimumPartLoadRatio
      }
    end
    results[:All]= {
      tested_capacity_kW: (total_boiler_cap.to_f).signif,
      total_capacity_kW: (total_capacity).signif,
      number_of_boilers: boiler_count
    }
    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate the boiler part load performance curve.
  def test_boiler_plf_vs_plr_curve
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       mau_type: true,
                       mau_heating_coil_type: 'Hot Water',
                       baseboard_type: 'Hot Water'}

    # Define test cases.
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: "NECB 2011 p3 8.4.4.22 (maybe)"}

    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['NECB2011'], # @AllTemplates,
                       fuel_type: ["NaturalGas"],
                       TestCase: ["case-1"],
                       TestPars: {:name => "tbd"}}
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
    msg = "Boiler plf vs plr curve coeffs test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_boiler_plf_vs_plr_curve that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_boiler_plf_vs_plr_curve(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    mau_type = test_pars[:mau_type]
    mau_heating_coil_type = test_pars[:mau_heating_coil_type]
    baseboard_type = test_pars[:baseboard_type]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]

    name = "#{vintage}_sys1_Boiler-#{fuel_type}_Mau-#{mau_type}_MauCoil-#{mau_heating_coil_type}_Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_sys1"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

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
      standard.add_sys1_unitary_ac_baseboard_heating(model: model,
                                                    zones: model.getThermalZones,
                                                    mau_type: mau_type,
                                                    mau_heating_coil_type: mau_heating_coil_type,
                                                    baseboard_type: baseboard_type,
                                                    hw_loop: hw_loop)

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract the results for checking. There are always two boilers.
    boilers = model.getBoilerHotWaters
    boilers.each do |boiler|
      logger.info "Boiler: #{boiler}"
      eff_curve_name, eff_curve_type, corr_coeff = get_boiler_eff_curve_data(boiler)
      boiler_eff = boiler.nominalThermalEfficiency
      boiler_name = boiler.name.get
      results[boiler_name.to_sym]= {
          boiler_name: boiler_name,
          boiler_eff: boiler_eff,
          eff_curve_name: eff_curve_name,
          eff_curve_type: eff_curve_type,
          curve_coefficients: corr_coeff
      }
    end
    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate the custom boiler thermal efficiencies applied against expected values stored in the file:
  # 'compliance_boiler_custom_efficiencies_expected_results.json
  def test_custom_efficiency
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all cases.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: false,
                       mau_type: true,
                       mau_heating_coil_type: 'Hot Water',
                       baseboard_type: 'Hot Water'}

    # Define test cases.
    standard_ecms = get_standard("ECMS")
    boilers = standard_ecms.standards_data["tables"]["boiler_eff_ecm"]["table"] # Used to get the case names and data.
    test_cases = Hash.new
    boilers.each do |boiler|
      test_cases_hash = {vintage: @AllTemplates,
                         TestCase: [boiler["name"]],
                         TestPars: {:Reference=>boiler["notes"],
                                       :boiler_name=>boiler["name"],
                                       :boiler_eff=>boiler["efficiency"],
                                       :eff_curve_name=>boiler["part_load_curve"]}}
      new_test_cases = make_test_cases_json(test_cases_hash)
      merge_test_cases!(test_cases, new_test_cases)
    end

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
    msg = "Boiler efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_custom_efficiency that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_custom_efficiency(test_pars:, test_case:)

    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    mau_type = test_pars[:mau_type]
    mau_heating_coil_type = test_pars[:mau_heating_coil_type]
    baseboard_type = test_pars[:baseboard_type]
    vintage = test_pars[:vintage]
    reference = test_case[:Reference]

    # Test specific inputs.
    boiler_name = test_case[:boiler_name]
    fuel_type = 'NaturalGas'
    boiler_cap = 1500000

    # Define the test name.
    name = "#{vintage}_sys1_Boiler-#{fuel_type}_cap-#{boiler_cap.to_int}W_MAU-#{mau_type}_MauCoil-#{mau_heating_coil_type}_Baseboard-#{baseboard_type}_efficiency-#{boiler_name}"
    name_short = "#{vintage}_sys1-#{boiler_name}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Started individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin
      standard = get_standard(vintage)
      standard_ecms = get_standard("ECMS")

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder,"5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models

      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys1_unitary_ac_baseboard_heating(model: model,
                                                      zones: model.getThermalZones,
                                                      mau_type: mau_type,
                                                      mau_heating_coil_type: mau_heating_coil_type,
                                                      baseboard_type: baseboard_type,
                                                      hw_loop: hw_loop)
      model.getBoilerHotWaters.each {|iboiler| iboiler.setNominalCapacity(boiler_cap)}

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS

      # Customize the efficiency. Specify the name and the method will look up the correct boiler.
      standard_ecms.modify_boiler_efficiency(model: model, boiler_eff: boiler_name)
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract the results for checking. There are always two boilers.
    results[:Reference] = reference
    boilers = model.getBoilerHotWaters
    boilers.each do |boiler|
      eff_curve_name, eff_curve_type, corr_coeff = get_boiler_eff_curve_data(boiler)
      boiler_eff = boiler.nominalThermalEfficiency
      boiler_name = boiler.name.get
      results[boiler_name.to_sym]= {
          boiler_name: boiler_name,
          boiler_eff: boiler_eff,
          eff_curve_name: eff_curve_name,
          eff_curve_type: eff_curve_type,
          curve_coefficients: corr_coeff
      }
    end
    logger.info "Completed individual test: #{name}"
    return results
  end

  # @note Helper method to return the part load curve data.
  # @param boiler [OS::Boiler] an openstudio boiler.
  # @return the efficiency curve name [String], curve type [String] and the curve coefficients [Array] (curve type dependent).
  def get_boiler_eff_curve_data(boiler)
    corr_coeff = []
    eff_curve = nil
    eff_curve_type = boiler.normalizedBoilerEfficiencyCurve.get.iddObjectType.valueName.to_s
    case eff_curve_type
    when "OS_Curve_Bicubic"
      eff_curve = boiler.normalizedBoilerEfficiencyCurve.get.to_CurveBicubic.get
      corr_coeff << eff_curve.coefficient1Constant
      corr_coeff << eff_curve.coefficient2x
      corr_coeff << eff_curve.coefficient3xPOW2
      corr_coeff << eff_curve.coefficient4y
      corr_coeff << eff_curve.coefficient5yPOW2
      corr_coeff << eff_curve.coefficient6xTIMESY
      corr_coeff << eff_curve.coefficient7xPOW3
      corr_coeff << eff_curve.coefficient8yPOW3
      corr_coeff << eff_curve.coefficient9xPOW2TIMESY
      corr_coeff << eff_curve.coefficient10xTIMESYPOW2
      corr_coeff << eff_curve.minimumValueofx
      corr_coeff << eff_curve.maximumValueofx
      corr_coeff << eff_curve.minimumValueofy
      corr_coeff << eff_curve.maximumValueofy
    when "OS_Curve_Biquadratic"
      eff_curve = boiler.normalizedBoilerEfficiencyCurve.get.to_CurveBiquadratic.get
      corr_coeff << eff_curve.coefficient1Constant
      corr_coeff << eff_curve.coefficient2x
      corr_coeff << eff_curve.coefficient3xPOW2
      corr_coeff << eff_curve.coefficient4y
      corr_coeff << eff_curve.coefficient5yPOW2
      corr_coeff << eff_curve.coefficient6xTIMESY
      corr_coeff << eff_curve.minimumValueofx
      corr_coeff << eff_curve.maximumValueofx
      corr_coeff << eff_curve.minimumValueofy
      corr_coeff << eff_curve.maximumValueofy
    when "OS_Curve_Cubic"
      eff_curve = boiler.normalizedBoilerEfficiencyCurve.get.to_CurveCubic.get
      corr_coeff << eff_curve.coefficient1Constant
      corr_coeff << eff_curve.coefficient2x
      corr_coeff << eff_curve.coefficient3xPOW2
      corr_coeff << eff_curve.coefficient4xPOW3
      corr_coeff << eff_curve.minimumValueofx
      corr_coeff << eff_curve.maximumValueofx
    when "OS_Curve_Linear"
      eff_curve = boiler.normalizedBoilerEfficiencyCurve.get.to_CurveLinear.get
      corr_coeff << eff_curve.coefficient1Constant
      corr_coeff << eff_curve.coefficient2x
      corr_coeff << eff_curve.minimumValueofx
      corr_coeff << eff_curve.maximumValueofx
    when "OS_Curve_Quadratic"
      eff_curve = boiler.normalizedBoilerEfficiencyCurve.get.to_CurveQuadratic.get
      corr_coeff << eff_curve.coefficient1Constant
      corr_coeff << eff_curve.coefficient2x
      corr_coeff << eff_curve.coefficient3xPOW2
      corr_coeff << eff_curve.minimumValueofx
      corr_coeff << eff_curve.maximumValueofx
    when "OS_Curve_QuadraticLinear"
      eff_curve = boiler.normalizedBoilerEfficiencyCurve.get.to_CurveQuadraticLinear.get
      corr_coeff << eff_curve.coefficient1Constant
      corr_coeff << eff_curve.coefficient2x
      corr_coeff << eff_curve.coefficient3xPOW2
      corr_coeff << eff_curve.coefficient4y
      corr_coeff << eff_curve.coefficient5xTIMESY
      corr_coeff << eff_curve.coefficient6xPOW2TIMESY
      corr_coeff << eff_curve.minimumValueofx
      corr_coeff << eff_curve.maximumValueofx
      corr_coeff << eff_curve.minimumValueofy
      corr_coeff << eff_curve.maximumValueofy
    end
    eff_curve_name = eff_curve.name.get
    return eff_curve_name, eff_curve_type, corr_coeff
  end
end
