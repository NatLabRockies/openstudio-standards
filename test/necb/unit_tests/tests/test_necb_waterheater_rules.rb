require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)


class NECB_WaterHeater_Rules < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate part-load performance curve of gas fired service water heater.
  def no_test_swh_curves
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'Electricity',
                       heating_coil_type: 'DX',
                       baseboard_type: 'Hot Water'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: 'NECB 2011 xxx'}
    
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['NECB2011'], #@AllTemplates, 
                       TestCase: ['Case 1'], 
                       TestPars: {swh_volume_L: 100.0,
                                  swh_temperature_degC: 60.0,
                                  swh_pump_head: 1.0,
                                  swh_pump_motor_efficiency: 0.7,
                                  swh_capacity_kW: 100.0,
                                  swh_fuel: 'NaturalGas',
                                  swh_parasitic_fuel_consumption_rate: 1.0}
                      }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    
    # Set the expected results filename.
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
  # @note Companion method to test_swh_curves that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_swh_curves(test_pars:, test_case:)
    
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

    # Test specific inputs.
    swh_volume_L = test_case[:swh_volume_L].to_f
    swh_temperature_degC = test_case[:swh_temperature_degC].to_f
    swh_pump_head = test_case[:swh_pump_head].to_f
    swh_pump_motor_efficiency = test_case[:swh_pump_motor_efficiency].to_f
    swh_capacity_kW = test_case[:swh_capacity_kW].to_f
    swh_fuel = test_case[:swh_fuel]
    swh_parasitic_fuel_consumption_rate = test_case[:swh_parasitic_fuel_consumption_rate].to_f

    # Define the test name. 
    name = "#{vintage}-swh_#{swh_capacity_kW.round(0)}kW-swh_fuel_#{swh_fuel}"
    name_short = "#{vintage}-swh_#{swh_capacity_kW.round(0)}kW-#{swh_fuel}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin

      # Load model and set climate file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder, "5ZoneNoHVAC.osm"))
      weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: weather_file_path)
      BTAP::FileIO.save_osm(model, "#{output_folder}/#{name}-baseline.osm") if save_intermediate_models

      # Add SWH loop.
      standard = get_standard(vintage)
      OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                system_name: 'Main Service Water Loop',
                                                                                service_water_temperature: swh_temperature_degC,
                                                                                service_water_pump_head: swh_pump_head,
                                                                                service_water_pump_motor_efficiency: swh_pump_motor_efficiency,
                                                                                water_heater_capacity: (swh_capacity_kW*1000.0),
                                                                                water_heater_volume: (swh_volume_L/1000.0),
                                                                                water_heater_fuel: swh_fuel)
                                                                      

      # Add hvac system.
      hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
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

    # Extract standards generated part-load performance curve.
    shw_units = model.getWaterHeaterMixeds
    shw_plfvsplr_curve = shw_units[0].partLoadFactorCurve.get
    results = get_curve_info(shw_plfvsplr_curve)
    
    logger.info "Completed individual test: #{name}"
    return results
  end

  # Test to validate efficiency and standby losses of service water heater.
  def test_swh_eff_standby_losses
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters.
    test_parameters = {TestMethod: __method__,
                       SaveIntermediateModels: true,
                       fuel_type: 'Electricity',
                       heating_coil_type: 'DX',
                       baseboard_type: 'Hot Water'}

    # Define test cases. 
    test_cases = Hash.new

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = {Reference: 'NECB 2011 xxx'}
    
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = {vintage: ['NECB2011', 'NECB2020'], #@AllTemplates, 
                       swh_capacity_kW: [10.0, 20.0, 30.0, 40.0],
                       swh_volume_L: [200.0, 300.0, 500.0],
                       swh_fuel: ['Electricity', 'NaturalGas'],
                       TestCase: ['Case 1'], 
                       TestPars: {swh_temperature_degC: 60.0,
                                  swh_pump_head: 1.0,
                                  swh_pump_motor_efficiency: 0.7,
                                  swh_parasitic_fuel_consumption_rate: 1.0}
                      }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)
    
    # Set the expected results filename.
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
  # @note Companion method to test_swh_eff_standby_losses that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_swh_eff_standby_losses(test_pars:, test_case:)
    
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

    # Varying inputs.
    vintage = test_pars[:vintage]
    swh_capacity_kW = test_pars[:swh_capacity_kW].to_f
    swh_volume_L = test_pars[:swh_volume_L].to_f
    swh_fuel = test_pars[:swh_fuel]

    # Test specific constant inputs.
    swh_temperature_degC = test_case[:swh_temperature_degC].to_f
    swh_pump_head = test_case[:swh_pump_head].to_f
    swh_pump_motor_efficiency = test_case[:swh_pump_motor_efficiency].to_f
    swh_parasitic_fuel_consumption_rate = test_case[:swh_parasitic_fuel_consumption_rate].to_f

    # Define the test name. 
    name = "#{vintage}-swh_#{swh_capacity_kW.round(0)}kW-volume_#{swh_volume_L}L-fuel_#{swh_fuel}"
    name_short = "#{vintage}-#{swh_capacity_kW.round(0)}kW-#{swh_volume_L}L-#{swh_fuel}"
    output_folder = method_output_folder("#{test_name}/#{name_short}")
    logger.info "Starting individual test: #{name}"
    results = Hash.new

    # Wrap test in begin/rescue/ensure.
    begin
    
      # Load basic model, no need to set weather file.
      model = BTAP::FileIO.load_osm(File.join(@resources_folder,"SmallOffice.osm"))
      BTAP::FileIO.save_osm(model, "#{output_folder}/baseline.osm") if save_intermediate_models
      
      # Remove HVAC and add in new loop with test sizing parameters.
      model.getPlantLoops.each(&:remove)
      model.purgeUnusedResourceObjects
      standard = get_standard(vintage)
      OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                system_name: 'Test Service Water Loop',
                                                                                service_water_temperature: 60.0,
                                                                                service_water_pump_head: 1.0,
                                                                                service_water_pump_motor_efficiency: 0.7,
                                                                                water_heater_capacity: (swh_capacity_kW*1000.0),
                                                                                water_heater_volume: (swh_volume_L/1000.0),
                                                                                water_heater_fuel: swh_fuel)

      # Apply the water heater sizing rules.
      model.getWaterHeaterMixeds.each { |unit| standard.water_heater_mixed_apply_efficiency(unit) }
      BTAP::FileIO.save_osm(model, "#{output_folder}/post_swh_sizing.osm") if save_intermediate_models
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Extract the results.
    unit_count = 0
    swh_units = model.getWaterHeaterMixeds
    swh_units.each do |unit|
      unit_count += 1
      swh_tank_eff = unit.heaterThermalEfficiency.to_f
      swh_tank_vol = unit.tankVolume.to_f
      swh_tank_cap = unit.heaterMaximumCapacity.to_f
      offcycle_ua = unit.offCycleLossCoefficienttoAmbientTemperature.to_f
      oncycle_ua = unit.onCycleLossCoefficienttoAmbientTemperature.to_f
      unitID = "SWH_unit-#{unit_count}"
      results[unitID.to_sym] = {
        name: unit.name.to_s,
        volume_L: (swh_tank_vol*1000.0).signif(3),
        capacity_kW: (swh_tank_cap/1000.0).signif(3),
        efficiency: swh_tank_eff.signif(3),
        off_cycle_UA_WperK: offcycle_ua.signif(4),
        on_cycle_UA_WperK: oncycle_ua.signif(4)
      }
    end
    
    logger.info "Completed individual test: #{name}"
    return results
  end
end
