require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/necb_helper'
include(NecbHelper)

class NECB_HVAC_Heatpump_Tests < Minitest::Test

  def setup()
    define_folders(__dir__)
    define_std_ranges
  end

  # Test to validate the heating efficiency generated against expected values stored in the file:
  # 'compliance_heatpump_efficiencies_expected_results.csv

  def test_heatpumps
    logger.info "Starting suite of tests for: #{__method__}"

    # Define test parameters that apply to all tests.
    test_parameters = {
      TestMethod: __method__,
      SaveIntermediateModels: false,
      heating_coil_type: 'DX',
      baseboard_type: 'Hot Water'
    }

    # Define test cases.
    test_cases = {}

    # Define references (per vintage in this case).
    test_cases[:NECB2011] = { Reference: "NECB 2011 p3: Table 5.2.12.1. (page 5-13); Table 8.4.4.21.-E" }
    test_cases[:NECB2015] = { Reference: "NECB 2015 p1: Table 5.2.12.1. (page 5-14); Table 8.4.4.21.-E" }
    test_cases[:NECB2017] = { Reference: "NECB 2017 p2: Table 5.2.12.1. (page 5-16); Table 8.4.4.21.-E" }
    test_cases[:NECB2020] = { Reference: "NECB 2020 p1: Table 5.2.12.1.-A; 8.4.5.7." }

    # Test cases.
    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["Small single package (CSA-C656)"],
                        TestPars: { :test_capacity_kW => 9.5 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["Medium single package (CSA-C746)"],
                        TestPars: { :test_capacity_kW => 29.5 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["Medium large single package (CSA-C746)"],
                        TestPars: { :test_capacity_kW => 47.5 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["Large single package (CSA-C746)"],
                        TestPars: { :test_capacity_kW => 146.5 } }
    new_test_cases = make_test_cases_json(test_cases_hash)
    merge_test_cases!(test_cases, new_test_cases)

    test_cases_hash = { vintage: @AllTemplates,
                        fuel_type: ["Electricity"],
                        TestCase: ["Extra large single package (AHRI 340/360)"],
                        TestPars: { :test_capacity_kW => 300.0 } }
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
    msg = "Heat pump efficiencies test results do not match what is expected in test"
    compare_results(expected_results: expected_results, test_results: test_results, msg: msg, type: 'json_data')
    logger.info "Finished suite of tests for: #{__method__}"
  end

  # @param test_pars [Hash] has the static parameters.
  # @param test_case [Hash] has the specific test parameters.
  # @return results of this case.
  # @note Companion method to test_heatpump_efficiency that runs a specific test. Called by do_test_cases in necb_helper.rb.
  def do_test_heatpumps(test_pars:, test_case:)

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
    standard = get_standard(vintage)
    # Test specific inputs.
    cap = test_case[:test_capacity_kW]
    # Define the test name.
    name = "#{vintage}_sys3_HtgDXCoilCap_#{fuel_type}_cap-#{cap.to_int}kW__Baseboard-#{baseboard_type}"
    name_short = "#{vintage}_sys3_HtgDXCoilCap_cap-#{cap.to_int}kW"

    output_folder = method_output_folder("#{test_name}/#{name_short}")
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
      standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model: model,
                                                                                                  zones: model.getThermalZones,
                                                                                                  heating_coil_type: heating_coil_type,
                                                                                                  baseboard_type: baseboard_type,
                                                                                                  hw_loop: hw_loop,
                                                                                                  new_auto_zoner: false)
      # According to NECB 2011, Section 8.4.4.14, the heat pump must be sized based on its cooling capacity.
      dx_clg_coils = model.getCoilCoolingDXSingleSpeeds
      dx_clg_coils.each do |coil|
        coil.setRatedTotalCoolingCapacity(cap * 1000.0)
        flow_rate = cap * 1000.0 * 5.0e-5
        coil.setRatedAirFlowRate(flow_rate)
      end

      # Run sizing.
      run_sizing(model: model, template: vintage, save_model_versions: save_intermediate_models, output_dir: output_folder) if PERFORM_STANDARDS
    rescue => error
      msg = "#{__FILE__}::#{__method__}\n#{error.full_message}"
      logger.error(msg)
      return {ERROR: msg}
    end

    capacity_btu_per_hr = OpenStudio.convert(cap.to_f, 'kW', 'Btu/hr').get
    heating_coil = model.getCoilHeatingDXSingleSpeeds[0]
    rated_cop = heating_coil.ratedCOP.to_f

    # Figure out the performance metric used in NECB and report that value
    if cap < 19 then
      if vintage == 'NECB2020' then
        metric = 'HSPF'
        hspf = 1.0593*rated_cop*rated_cop - 4.0795*rated_cop + 8.1583 # Curve fit of NREL equation in hspf_to_cop_no_fan. For range 5.5 to 8.4 (HSPF)
        value = hspf.signif(2)
      else
        metric = 'SEER'
        value = OpenstudioStandards::HVAC.cop_no_fan_to_seer(rated_cop).signif(3)
      end
    else
      if vintage == 'NECB2020' then
        metric = 'COP_h (with fan)'
      elsif vintage == 'NECB2015' || vintage == 'NECB2017' then
        metric = 'heating COP (with fan)'
      else
        metric = 'COP (with fan)'
      end
      cop_with_fan = rated_cop / ((1.48E-7 * capacity_btu_per_hr) + 1.062)
      value = cop_with_fan.signif(3)
    end
    results = {
      test_capacity_kW: cap.signif(3),
      test_capacity_btu_per_hr: capacity_btu_per_hr.signif(3),
      metric.to_sym => value
    }

    # Recover curves.
    # Define the curves and their types inline, using curve names as keys
    curves = [
      { curve: heating_coil.totalHeatingCapacityFunctionofTemperatureCurve.to_CurveCubic.get, type: 'cubic' },
      { curve: heating_coil.energyInputRatioFunctionofTemperatureCurve.to_CurveCubic.get, type: 'cubic' },
      { curve: heating_coil.totalHeatingCapacityFunctionofFlowFractionCurve.to_CurveCubic.get, type: 'cubic' },
      { curve: heating_coil.energyInputRatioFunctionofFlowFractionCurve.to_CurveQuadratic.get, type: 'quadratic' },
      { curve: heating_coil.partLoadFractionCorrelationCurve.to_CurveCubic.get, type: 'cubic' }
    ]

    # Populate the result hash using curve names as keys
    curve_results = Hash.new
    curves.each do |curve_detail|
      curve = curve_detail[:curve]
      curve_name = curve.name.get
      curve_results[curve_name.to_sym] = {
        curve_type: curve_detail[:type],
        minimumValueofx: sprintf('%.5E', curve.minimumValueofx),
        maximumValueofx: sprintf('%.5E', curve.maximumValueofx),
        coefficient1Constant: sprintf('%.5E', curve.coefficient1Constant),
        coefficient2x: sprintf('%.5E', curve.coefficient2x),
        coefficient3xPOW2: sprintf('%.5E', curve.coefficient3xPOW2)
      }
      # Conditionally add `coefficient4xPOW3` if it exists (only for cubic curves)
      curve_results[curve_name.to_sym][:coefficient4xPOW3] = sprintf('%.5E', curve.coefficient4xPOW3) if curve.respond_to?(:coefficient4xPOW3)
    end
    results[:curves] = curve_results


    # Add this test case to results and return the hash.

    logger.info "Completed individual test: #{name}"
    return results
  end
end