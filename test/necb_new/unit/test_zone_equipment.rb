require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# Test NECB zone equipment configuration and characteristics
# Tests PTAC, baseboard heaters, and fan coil units without requiring sizing runs
#
# Methods tested:
# - NECB2011#add_ptac_dx_cooling
# - NECB2011#add_zone_baseboards
# - NECB2011#add_sys1_unitary_ac_baseboard_heating
# - Standard zone equipment configuration methods
#
# References:
# - NECB 2011 Table 5.2.2.3   (Equipment Performance)
# - NECB 2011 Clause 8.4.4.13 (System 1 - PTAC with Baseboard)
# - NECB 2011 Clause 5.2.10.3 (Direct Expansion Equipment Efficiency)
class TestZoneEquipment < Minitest::Test
  include(NecbHelper)

  def test_ptac
    model, standard = create_baseline_necb_model
    zone = model.getThermalZones.first

    # Create PTAC using NECB method
    standard.add_ptac_dx_cooling(model, zone, true)

    # Verify PTAC was added
    ptacs = zone.equipment.select { |e| e.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized }
    assert_equal 1, ptacs.size, "Should have 1 PTAC in zone"

    # Get PTAC and verify basic configuration
    ptac = ptacs.first.to_ZoneHVACPackagedTerminalAirConditioner.get

    # Verify PTAC has cooling coil
    cooling_coil = ptac.coolingCoil
    assert cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized,
      "PTAC should have DX cooling coil"

    # Verify PTAC has heating coil
    heating_coil = ptac.heatingCoil.to_CoilHeatingElectric
    assert heating_coil.is_initialized,
      "PTAC should have electric heating coil"

    # Verify heating coil has always-off schedule
    sched = heating_coil.get.availabilitySchedule
    assert sched.name.to_s.downcase.include?('off'),
      "PTAC heating coil schedule should be always off, got #{sched.name}"

    # Verify PTAC has fan
    fan = ptac.supplyAirFan.to_FanOnOff
    assert fan.is_initialized,
      "PTAC should have on-off fan"

    dx_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get

    # Verify performance curves exist
    refute_nil dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve,
               "DX coil should have capacity-f(T) curve"
    refute_nil dx_coil.totalCoolingCapacityFunctionOfFlowFractionCurve,
               "DX coil should have capacity-f(flow) curve"
    refute_nil dx_coil.energyInputRatioFunctionOfTemperatureCurve, "DX coil should have EIR-f(T) curve"
    refute_nil dx_coil.energyInputRatioFunctionOfFlowFractionCurve, "DX coil should have EIR-f(flow) curve"
    refute_nil dx_coil.partLoadFractionCorrelationCurve, "DX coil should have PLF curve"

    # Verify fan pressure rise (NECB sets 640 Pa)
    assert_in_delta 640.0, fan.get.pressureRise, 10.0,
      "PTAC fan pressure rise should be 640 Pa per NECB"
  end

  def test_electric_baseboard
    model, standard = create_baseline_necb_model
    zone = model.getThermalZones.first

    # Add electric baseboard
    standard.add_zone_baseboards(
      baseboard_type: 'Electric',
      hw_loop: nil,
      model: model,
      zone: zone
    )

    # Verify baseboard was added
    baseboards = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveElectric.is_initialized }

    assert_equal 1, baseboards.size, "Should have 1 electric baseboard in zone"
  end

  def test_hot_water_baseboard
    model, standard = create_baseline_necb_model
    zone = model.getThermalZones.first

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')

    # Add hot water baseboard
    standard.add_zone_baseboards(
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      model: model,
      zone: zone
    )

    # Verify baseboard was added
    baseboards = zone.equipment.select { |e| e.to_ZoneHVACBaseboardConvectiveWater.is_initialized }
    assert_equal 1, baseboards.size, "Should have 1 hot water baseboard in zone"

    # Verify baseboard has heating coil
    baseboard = baseboards.first.to_ZoneHVACBaseboardConvectiveWater.get
    htg_coil = baseboard.heatingCoil
    assert htg_coil.to_CoilHeatingWaterBaseboard.is_initialized,
      "Hot water baseboard should have water heating coil"

    # Verify coil is connected to hot water loop
    coil = htg_coil.to_CoilHeatingWaterBaseboard.get
    assert coil.plantLoop.is_initialized,
      "Baseboard heating coil should be connected to plant loop"
    assert_equal hw_loop.handle.to_s, coil.plantLoop.get.handle.to_s,
      "Baseboard should be connected to hot water loop"
  end
end
