require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_PumpPower_Test < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # NECB2015 rules for cooling tower
  # power = 0.013 x capacity in kW
  # Note that most of the code was copied from 2015 part of test_necb_coolingtower_rules.rb because it creates a building
  # with a heating, cooling, and heat rejection loop.  This was necessary to test the NECB2015 pump power rules.  The test
  # creates the building with HVAC, applies another sizing run, and runs the apply_maximum_loop_pump_power(model) method.
  # The test then calculates what the pump power adjustment should be and compares that to what was applied to the model.
  # If the answer is close then the test passes.  I did not take the time to write the code to create a model with headered
  # pumps or with a water source heat pump.  So, those aspects of test_necb_coolingtower_rules.rb will not be exercised.
  # Until further testing is done test_necb_coolingtower_rules.rb should not be used with models containing headered pumps
  # or water source heat pumps.
  def test_pumppower
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: true,
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      heating_coil_type: 'Hot Water',
      fan_type: 'AF_or_BI_rdg_fancurve',
      chiller_cap: 1000000.0
    }
    tol = 1.0e-3
    # Define test cases.
    test_cases = {}

    # Define references (per vintage in this case).
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1:Table 5.2.6.3." }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2:Table 5.2.6.3." }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1:Table 5.2.6.3." }

    # Test cases. Three cases for NG and FuelOil, one for Electric.
    # Results and name are tbd here as they will be calculated in the test.
    test_cases_hash = { vintage: @SomeTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["case-1"],
                        TestPars: { :tested_capacity_kW => 10.0,
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
    msg = "Pump power test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  def do_test_pumppower(test_pars:, test_case:)
    # Debug.
    logger.debug "test_pars: #{JSON.pretty_generate(test_pars)}"
    logger.debug "test_case: #{JSON.pretty_generate(test_case)}"

    # Define local variables. These are extracted from the supplied hashes.
    # General inputs.
    test_name = test_pars[:TestMethod]
    save_intermediate_models = test_pars[:SaveIntermediateModels]
    chiller_type = test_pars[:chiller_type]
    fan_type = test_pars[:fan_type]
    chiller_cap = test_pars[:chiller_cap]
    baseboard_type = test_pars[:baseboard_type]
    heating_coil_type = test_pars[:heating_coil_type]
    fuel_type = test_pars[:fuel_type]
    vintage = test_pars[:vintage]
    standard = get_standard(vintage)

    # Define the test name.
    name = "#{vintage}_sys6_#{fuel_type}_ChillerType_#{chiller_type}_#{chiller_cap}watts_baseboard_type-#{baseboard_type}_heating_coil_type-#{heating_coil_type}_Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_sys6_#{fuel_type}_ChillerType-#{chiller_type}-#{chiller_cap}watts"
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
      standard.setup_hw_loop_with_components(model, hw_loop, fuel_type, fuel_type, always_on)
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: model.getThermalZones,
        heating_coil_type: heating_coil_type,
        baseboard_type: baseboard_type,
        chiller_type: chiller_type,
        fan_type: fan_type,
        hw_loop: hw_loop)
      model.getChillerElectricEIRs.each { |ichiller| ichiller.setReferenceCapacity(chiller_cap) }
      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    # Apply the NECB 2015 pump power rules to the model.
    standard.apply_maximum_loop_pump_power(model)

    # From here to the end of the method the expected pump power is calculated and is compared to what was applied to the model.
    results = {}
    plant_loops = model.getPlantLoops
    plant_loops.each do |plantloop|
      pumps = []
      max_powertoload = 0
      total_pump_power = 0
      # This cycles through the plant loop supply side components to determine if there is a heat pump present or a pump
      # If a heat pump is present the pump power to total demand ratio is set to what NECB 2015 table 5.2.6.3. say it should be.
      # If a pump is present, this is a handy time to grab it for modification later.  Also, it adds the pump power consumption
      # to a total which will be used to determine how much to modify the pump power consumption later.
      plantloop.supplyComponents.each do |supplycomp|
        case supplycomp.iddObjectType.valueName.to_s
        when 'OS_CentralHeatPumpSystem'
          max_powertoload = 22
        when 'OS_Coil_Heating_WaterToAirHeatPump_EquationFit'
          max_powertoload = 22
        when 'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeedEquationFit'
          max_powertoload = 22
        when 'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeedEquationFit_SpeedData'
          max_powertoload = 22
        when 'OS_HeatPump_WaterToWater_EquationFit_Cooling'
          max_powertoload = 22
        when 'OS_HeatPump_WaterToWater_EquationFit_Heating'
          max_powertoload = 22
        when 'OS_Pump_VariableSpeed'
          pump = supplycomp.to_PumpVariableSpeed.get
          pumps << pump
          total_pump_power += pump.autosizedRatedPowerConsumption.get
        when 'OS_Pump_ConstantSpeed'
          pump = supplycomp.to_PumpConstantSpeed.get
          pumps << pump
          total_pump_power += pump.autosizedRatedPowerConsumption.get
        when 'OS_HeaderedPumps_ConstantSpeed'
          pump = supplycomp.to_HeaderedPumpsConstantSpeed.get
          pumps << pump
          total_pump_power += pump.autosizedRatedPowerConsumption.get
        when 'OS_HeaderedPumps_VariableSpeed'
          pump = supplycomp.to_HeaderedPumpsVariableSpeed.get
          pumps << pump
          total_pump_power += pump.autosizedRatedPowerConsumption.get
        end
      end
      # If no pumps were found then there is nothing to set so go to the next plant loop
      next if pumps.length == 0
      # If a heat pump was found then the pump power to total demand ratio should have been set to what NECB 2015 table 5.2.6.3 says.
      # If the pump power to total demand ratio was not set then no heat pump was present so set according to if the plant loop is
      # used for heating, cooling, or heat rejection (condeser as OpenStudio calls it).

      unless max_powertoload > 0
        case plantloop.sizingPlant.loopType
        when 'Heating'
          max_powertoload = 4.5
        when 'Cooling'
          max_powertoload = 14
        when 'Condenser'
          max_powertoload = 12
        end
      end

      # If nothing was found then do nothing (though by this point if nothing was found then an error should have been thrown).
      next if max_powertoload == 0
      # Get the capacity of the loop (using the more general method of calculating via maxflow*temp diff*density*heat capacity)
      # This is more general than the other method in Standards.PlantLoop.rb which only looks at heat and cooling.  Also,
      # that method looks for specific equipment and would be thrown if other equipment was present.  However my method
      # only works for water for now.
      plantloop_capacity = standard.plant_loop_capacity_w_by_maxflow_and_delta_t_forwater(plantloop)
      # Sizing factor is pump power (W)/ zone demand (in kW, as approximated using plant loop capacity).
      necb_pump_power_cap = plantloop_capacity * max_powertoload / 1000
      pump_power_adjustment = necb_pump_power_cap / total_pump_power
      plant_loop_capacity_kW = plantloop_capacity / 1000
      pumps.each do |pump|
        results[pump.name.get] = {
          plant_loop_type: plantloop.sizingPlant.loopType,
          max_power_to_load: max_powertoload.signif(2),
          plant_loop_capacity_kW: plant_loop_capacity_kW.signif(2),
          pump_design_power_sizing_method: pump.designPowerSizingMethod,
          pump_power_adjustment: pump_power_adjustment.signif(2)
        }

        case pump.designPowerSizingMethod
        when 'PowerPerFlowPerPressure'
          results[pump.name.get][:pump_rated_pump_head_Pa] = pump.ratedPumpHead.signif(2)
        when 'PowerPerFlow'
          results[pump.name.get][:pump_designElectricPowerPerUnitFlowRate] = pump.designElectricPowerPerUnitFlowRate.signif(2)
        end
      end
    end
    logger.info "Completed individual test: #{name}"
    return results
  end
end
