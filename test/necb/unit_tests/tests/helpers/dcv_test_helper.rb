require_relative '../../../../helpers/minitest_helper'
require_relative '../../../../helpers/create_doe_prototype_helper'
require 'json'
require_relative '../../../../helpers/necb_helper'

include(NecbHelper)

module DCVTestHelper
  # Test configuration constants
  EPW_FILE = 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw'.freeze
  PRIMARY_HEATING_FUEL = 'NaturalGas'.freeze
  DCV_TYPE = 'Occupancy_based_DCV'.freeze
  CO2_SCHEDULE_STRING_INDEX = 6

  def setup_dcv_test
    @epw_file = EPW_FILE
    @primary_heating_fuel = PRIMARY_HEATING_FUEL
    @dcv_type = DCV_TYPE
  end

  def run_dcv_test(template, building_type, dcv_type)
    @template = template
    @building_type = building_type
    @dcv_type = dcv_type
    @test_results_array = []
    
    setup_file_paths
    @test_results_array << build_test_result
    File.write(@test_results_file, JSON.pretty_generate(@test_results_array))
    compare_results
  end

  private

  def setup_file_paths
    @output_folder = File.join(__dir__, '../output/test_dcv', @dcv_type, @template, @building_type)
    @expected_results_file = File.join(__dir__, '../../expected_results/', "dcv_#{@dcv_type}_#{@template}_#{@building_type}_expected_results.json")
    @test_results_file = File.join(__dir__, '../../expected_results/', "dcv_#{@dcv_type}_#{@template}_#{@building_type}_test_results.json")
    @sizing_run_dir = File.join(@output_folder, 'sizing_folder')
    
    FileUtils.mkdir_p(@output_folder)
  end

  def build_test_result
    result = {
      'template' => @template,
      'epw_file' => @epw_file,
      'building_type' => @building_type,
      'primary_heating_fuel' => @primary_heating_fuel,
      'dcv_type' => @dcv_type
    }

    # Create and configure model
    standard = Standard.build(@template)
    model = standard.load_building_type_from_library(building_type: @building_type)
    standard.model_apply_standard(
      model: model,
      epw_file: @epw_file,
      sizing_run_dir: @sizing_run_dir,
      primary_heating_fuel: @primary_heating_fuel,
      dcv_type: @dcv_type
    )

    gather_model_data(model, result)
    result
  end

  # Gather data from the model
  def gather_model_data(model, result)
    gather_zone_air_contaminant_data(model, result)
    gather_space_data(model, result)
    gather_air_loop_data(model, result)
  end

  # Gather zone air contaminant data
  def gather_zone_air_contaminant_data(model, result)
    zone_air_contaminant_balance = model.getZoneAirContaminantBalance
    co2_schedule = zone_air_contaminant_balance.outdoorCarbonDioxideSchedule.get
    
    result['outdoor_co2_schedule_name'] = co2_schedule.name.to_s
    result['outdoor_co2_schedule_for_alldays_ppm'] = co2_schedule.getString(CO2_SCHEDULE_STRING_INDEX).to_s
  end

  # Gather space data
  def gather_space_data(model, result)
    model.getSpaces.each do |space|
      zone = space.thermalZone&.get
      next unless zone
      
      co2_controller = zone.zoneControlContaminantController.get
      space_name = space.name.to_s
      
      availability_schedule = co2_controller.carbonDioxideControlAvailabilitySchedule.get
      setpoint_schedule = co2_controller.carbonDioxideSetpointSchedule.get
      
      result["#{space_name} - co2_availability_schedule"] = availability_schedule.name.to_s
      result["#{space_name} - co2_setpoint_schedule"] = setpoint_schedule.name.to_s
      result["#{space_name} - co2_setpoint_schedule_ppm"] = setpoint_schedule.getString(CO2_SCHEDULE_STRING_INDEX).to_s
    end
  end

  # Gather air loop data
  def gather_air_loop_data(model, result)
    model.getAirLoopHVACs.each do |air_loop|
      air_loop.supplyComponents.each do |component|
        hvac_component = component.to_AirLoopHVACOutdoorAirSystem
        next if hvac_component.empty?

        outdoor_air_system = hvac_component.get
        controller_outdoorair = outdoor_air_system.getControllerOutdoorAir
        controller_mechanical_ventilation = controller_outdoorair.controllerMechanicalVentilation
        
        system_name = outdoor_air_system.name.to_s
        outdoor_controller_name = controller_outdoorair.name.to_s
        mech_vent_controller_name = controller_mechanical_ventilation.name.to_s
        
        result["#{system_name} - outdoor_air_controller"] = outdoor_controller_name
        result["#{outdoor_controller_name} - mechanical_ventilation_controller"] = mech_vent_controller_name
        result["#{mech_vent_controller_name} - dcv_status"] = controller_mechanical_ventilation.demandControlledVentilation.to_s
        result["#{mech_vent_controller_name} - outdoor_air_method"] = controller_mechanical_ventilation.systemOutdoorAirMethod.to_s
      end
    end
  end

  # Compare test results with expected results
  def compare_results
    assert(File.exist?(@expected_results_file), "Expected results file not found: #{@expected_results_file}")
    
    expected_results = JSON.parse(File.read(@expected_results_file))
    assert_equal(expected_results.size, @test_results_array.size, "Mismatch in number of results")
    
    expected_results.each_with_index do |expected, index|
      actual = @test_results_array[index]
      next if expected == actual
      
      assert(false, "Mismatch at row #{index}:\nExpected: #{expected}\nActual: #{actual}")
    end
  end
end