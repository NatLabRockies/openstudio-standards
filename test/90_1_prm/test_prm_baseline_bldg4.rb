require_relative '../helpers/minitest_helper'
require_relative 'create_performance_rating_method_helper'
require_relative 'baseline_901_2013_helper'

class Baseline9012013TestBldg4 < Minitest::Test

  include Baseline9012013

  # Test LPDs for bldg_4
  # @author Matt Leach, NORESCO
  # Known failure due to currently not having parking space type
  def test_lpd_bldg4
    model = create_baseline_model('bldg_4', '90.1-2013', 'ASHRAE 169-2006-5B', 'MediumOffice', 'Xcel Energy CO EDA', false, true)
    failure_array = []

    lpd_test_hash = {}
    lpd_test_hash["Parking Level 1B ParkingLot"] = {"LPD" => 0.04,"Space_Type" => "Parking"} #Interior parking lot is currently not an available space type.
    lpd_test_hash["Parking Level 1B IDF 1B05"] = {"LPD" => 1.11,"Space_Type" => "IT_Room"}
    lpd_test_hash["IndoorPracticeField"] = {"LPD" => 0.72,"Space_Type" => "Gym"}

    lpd_test_hash.keys.each do |space_name|
      space = model.getSpaceByName(space_name).get
      lpd_w_per_m2 = space.lightingPowerPerFloorArea
      lpd_w_per_ft2 = OpenStudio.convert(lpd_w_per_m2,'W/m^2','W/ft^2').get

      unless (lpd_test_hash[space_name]["LPD"] - lpd_w_per_ft2).abs < 0.01
        failure_array << "Expected LPD of #{lpd_test_hash[space_name]["LPD"]} W/ft2 for Space #{space_name} of Type #{lpd_test_hash[space_name]["Space_Type"]}; got #{lpd_w_per_ft2.round(2)} W/ft2 instead"
      end
    end
    assert_equal(0, failure_array.length, "There were #{failure_array.length} failures:  #{failure_array.join('.  ')}")
  end

  # Test System Type for bldg_4
  # @author Matt Leach, NORESCO
  def test_system_type_bldg4
    model = create_baseline_model('bldg_4', '90.1-2013', 'ASHRAE 169-2006-5B', 'MediumOffice', 'Xcel Energy CO EDA', false, true)
    failure_array = []

    # test main system type
    expected_system_string = "PVAV_Reheat (Sys5)"
    # do not expect any PSZ systems for this model (all fully conditioned zones should be on main baseline system)
    model.getAirLoopHVACs.each do |airloop|
      airloop_name = airloop.name.get.to_s
      unless airloop_name.include? expected_system_string
        system_type_confirmed = false
      else
        system_type_confirmed = true
      end
      unless system_type_confirmed
        failure_array << "System Type for Airloop #{airloop_name} is Unexpected.  Expected Type #{expected_system_string}"
      end
      # check terminal types
      thermal_zones_attached = 0
      airloop.thermalZones.each do |zone|
        thermal_zones_attached += 1
        # look for air terminal for zone
        if zone.airLoopHVACTerminal.is_initialized
          terminal = zone.airLoopHVACTerminal.get
          # get terminal and make sure it is the correct type
          unless terminal.to_AirTerminalSingleDuctVAVReheat.is_initialized
            failure_array << "Expected terminals to be of type AirTerminalSingleDuctVAVReheat for System #{airloop_name}; this is not true for Terminal #{terminal.name}"
          end
        else
          failure_array << "No terminal attaching Zone #{zone} to System #{airloop_name}"
        end
      end
      unless thermal_zones_attached > 0
        failure_array << "No thermal zones attached to System #{airloop_name}"
      end
      # check fan type
      unless airloop.supplyFan.is_initialized
        failure_array << "No supply fan attached to System #{airloop_name}"
      else
        # get fan type
        supply_fan = airloop.supplyFan.get
        unless supply_fan.to_FanVariableVolume.is_initialized
          failure_array << "Expected fan of type VariableVolume for System #{airloop_name}"
        end
      end
      # check heating and cooling coil types
      # heating coil
      unless airloop.supplyComponents('OS_Coil_Heating_Water'.to_IddObjectType).length == 1
        failure_array << "Expected heating coil of type CoilHeatingWater for System #{airloop_name} (System Type 5 with District Heating)"
      else
        airloop.supplyComponents('OS_Coil_Heating_Water'.to_IddObjectType).each do |heating_water_coil|
          unless heating_water_coil.to_CoilHeatingWater.get.plantLoop.is_initialized
            failure_array << "Heating coil serving System #{airloop_name} is not attached to a plant loop"
          else
            plant_loop = heating_water_coil.to_CoilHeatingWater.get.plantLoop.get
            districting_supply_components = []
            plant_loop.supplyComponents.each do |sc|
              case sc.iddObjectType.valueName.to_s
              when 'OS_DistrictHeating', 'OS_DistrictHeating_Water', 'OS_DistrictHeating_Steam'
                districting_supply_components << sc
              end
            end
            unless districting_supply_components.size == 1
              failure_array << "Expected Heating Coil for System #{airloop_name} to be served by a DistrictHeating object"
            end
          end
        end
      end
      # cooling coil
      unless airloop.supplyComponents('OS_Coil_Cooling_DX_TwoSpeed'.to_IddObjectType).length == 1
        failure_array << "Expected cooling coil of type CoilCoolingDXTwoSpeed for System #{airloop_name}"
      end
    end

    # check for exhaust fans (should match exhaust fans)
    number_of_exhaust_fans = 0
    model.getFanZoneExhausts.each do |exhaust_fan|
      number_of_exhaust_fans +=1
      if exhaust_fan.name.get.to_s == "Parking Level 1B ParkingLot Exhaust Fan"
        expected_efficiency = 0.71047619047619
        expected_pressure_rise = 716.49
        expected_flow_rate = 35.396
        # check values
        unless (exhaust_fan.fanEfficiency - expected_efficiency).abs < 0.01
          failure_array << "Baseline Fan Efficiency for #{exhaust_fan.name} (#{exhaust_fan.fanEfficiency.round(1)}) expected to matched Proposed Value of #{expected_efficiency}"
        end
        unless (exhaust_fan.pressureRise - expected_pressure_rise).abs < 0.01
          failure_array << "Baseline Fan Pressure Rise for #{exhaust_fan.name} (#{exhaust_fan.pressureRise.round(2)} Pa) expected to matched Proposed Value of #{expected_pressure_rise} Pa"
        end
        if exhaust_fan.maximumFlowRate.is_initialized
          unless (exhaust_fan.maximumFlowRate.get - expected_flow_rate).abs < 0.01
            failure_array << "Baseline Fan Flow Rate for #{exhaust_fan.name} (#{exhaust_fan.maximumFlowRate.round(3)} m3/s) expected to matched Proposed Value of #{expected_flow_rate} m3/s"
          end
        else
          failure_array << "Baseline Fan Flow Rate for #{exhaust_fan.name} expected to matched Proposed Value of #{expected_flow_rate} m3/s but no value was specified"
        end
      elsif exhaust_fan.name.get.to_s == "Parking Level 2B ParkingLot Exhaust Fan"
        expected_efficiency = 0.71047619047619
        expected_pressure_rise = 908.41
        expected_flow_rate = 40.116
        # check values
        unless (exhaust_fan.fanEfficiency - expected_efficiency).abs < 0.01
          failure_array << "Baseline Fan Efficiency for #{exhaust_fan.name} (#{exhaust_fan.fanEfficiency.round(1)}) expected to matched Proposed Value of #{expected_efficiency}"
        end
        unless (exhaust_fan.pressureRise - expected_pressure_rise).abs < 0.01
          failure_array << "Baseline Fan Pressure Rise for #{exhaust_fan.name} (#{exhaust_fan.pressureRise.round(2)} Pa) expected to matched Proposed Value of #{expected_pressure_rise} Pa"
        end
        if exhaust_fan.maximumFlowRate.is_initialized
          unless (exhaust_fan.maximumFlowRate.get - expected_flow_rate).abs < 0.01
            failure_array << "Baseline Fan Flow Rate for #{exhaust_fan.name} (#{exhaust_fan.maximumFlowRate.round(3)} m3/s) expected to matched Proposed Value of #{expected_flow_rate} m3/s"
          end
        else
          failure_array << "Baseline Fan Flow Rate for #{exhaust_fan.name} expected to matched Proposed Value of #{expected_flow_rate} m3/s but no value was specified"
        end
      else
        failure_array << "Unexpected Exhaust Fan = #{exhaust_fan.name.get.to_s}"
      end
    end
    unless number_of_exhaust_fans == 2
      failure_array << "Expected 2 Exhaust Fans; found #{number_of_exhaust_fans} instead"
    end
    assert_equal(0, failure_array.length, "There were #{failure_array.length} failures:  #{failure_array.join('.  ')}")
  end

  # Test Equipment Efficiencies for bldg_4
  # @author Matt Leach, NORESCO
  def test_hvac_eff_bldg4
    model = create_baseline_model('bldg_4', '90.1-2013', 'ASHRAE 169-2006-5B', 'MediumOffice', 'Xcel Energy CO EDA', false, true)
    failure_array = []

    # check coil efficiencies
    dx_coil_hash = {}
    dx_coil_hash["IPF Above Ground PVAV_Reheat (Sys5) Clg Coil"] = {"CoilType" => "TwoSpeedCooling","Capacity" => 3651.0,"EfficiencyType" => "EER","Efficiency" => 9.5}
    failure_array = check_dx_cooling_two_speed_efficiency(model, dx_coil_hash, failure_array)

    # check fan powers
    supply_fan_hash = {}
    # expect test to fail because pressure differential for MERV 13 filter is being added to expected calculation
    # if pressure differential is set to zero, test passes
    supply_fan_hash["IPF Above Ground PVAV_Reheat (Sys5) Fan"] = {"CFM" => 136667.0,"PressureDifferential" => 0.0}
    failure_array = check_variable_speed_fan_power(model, supply_fan_hash, failure_array)
    failure_array = check_constant_speed_fan_power(model, supply_fan_hash, failure_array)

    # check plant loop components
    # hw pumps
    failure_array = check_district_hw_pumps(model, failure_array)
    assert_equal(0, failure_array.length, "There were #{failure_array.length} failures:  #{failure_array.join('.  ')}")
  end
end
