require_relative '../coverage_helper'

class TestNECBRemainingHVACSystems < Minitest::Test
  include(NecbHelper)

  def test_system_2_fpfc
    model, standard = create_baseline_necb_model(add_thermostat: true, primary_heating_fuel: 'NaturalGas')

    zones = model.getThermalZones

    # Create hot water loop (required by System 2)
    hw_loop = create_hot_water_loop(model, standard)

    # Add System 2 (FPFC + MAU)
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    # Verify air loop was created (MAU/DOAS)
    air_loops = model.getAirLoopHVACs
    assert air_loops.length > 0, "Should create at least one air loop (MAU)"

    # Check for MAU or DOAS (Dedicated Outdoor Air System) - both terms for make-up air
    mau_loop = air_loops.find { |loop| loop.name.to_s.include?('Make-up') || loop.name.to_s.include?('MAU') || loop.name.to_s.include?('doas') }
    assert mau_loop, "Should create make-up air unit or DOAS"

    # Verify fan coils were created
    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.length > 0, "Should create four-pipe fan coils"

    # Verify chilled water loop
    chw_loops = model.getPlantLoops.select { |loop| loop.name.to_s.downcase.include?('chilled') || loop.name.to_s.downcase.include?('chw') }
    assert chw_loops.length > 0, "Should create chilled water loop"

    # Verify condenser water loop
    cw_loops = model.getPlantLoops.select { |loop| loop.name.to_s.downcase.include?('condenser') || loop.name.to_s.downcase.include?('cw') }
    assert cw_loops.length > 0, "Should create condenser water loop"
  end

  def test_system_5_tpfc_creation
    model, standard = create_baseline_necb_model(add_thermostat: true, primary_heating_fuel: 'NaturalGas')

    zones = model.getThermalZones

    # Create hot water loop (required by System 5)
    hw_loop = create_hot_water_loop(model, standard)

    # Add System 5 (TPFC + MAU)
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',  # Two-pipe instead of four-pipe
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    # Verify air loop was created (MAU)
    air_loops = model.getAirLoopHVACs
    assert air_loops.length > 0, "Should create at least one air loop (MAU)"

    # Verify fan coils were created (two-pipe in this case)
    # Note: TPFC typically uses ZoneHVACFourPipeFanCoil with special scheduling
    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.length > 0, "Should create fan coils for System 5"

    # Verify plant loops
    plant_loops = model.getPlantLoops
    assert plant_loops.length >= 2, "Should create multiple plant loops"
  end

  def test_system_7_vav_pfp_concept
    skip "System 7 (VAV with PFP boxes) is not implemented as a separate method in NECB2011
    It would typically be a VAV system (System 6) with parallel fan-powered terminal units
    For now, this test documents the concept"

    model, standard = create_baseline_necb_model(add_thermostat: true, primary_heating_fuel: 'NaturalGas')

    zones = model.getThermalZones

    # Create hot water loop (required by System 6)
    hw_loop = create_hot_water_loop(model, standard)

    # System 6 (VAV) is the closest to System 7
    # System 7 would use parallel fan-powered boxes instead of standard VAV terminals
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: hw_loop
    )

    # Verify VAV system was created
    air_loops = model.getAirLoopHVACs
    assert air_loops.length > 0, "Should create VAV air loop"

    # Standard System 6 creates VAV terminal units, not PFP boxes
    # To implement true System 7, would need to replace VAV terminals with parallel fan-powered boxes
    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.length > 0, "Should create VAV terminal units"

    # Document that System 7 (PFP boxes) would require modification to use
    # AirTerminalSingleDuctParallelPIUReheat instead
  end

  # Helper to create hot water loop (required by some HVAC systems)
  def create_hot_water_loop(model, standard)
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')

    # Set plant loop temperatures
    hw_loop.setMaximumLoopTemperature(82.0)
    hw_loop.setMinimumLoopTemperature(60.0)

    # Add sizing
    sizing = hw_loop.sizingPlant
    sizing.setLoopType('Heating')
    sizing.setDesignLoopExitTemperature(82.0)
    sizing.setLoopDesignTemperatureDifference(11.0)

    # Add supply components
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.addToNode(hw_loop.supplyInletNode)

    # Add boiler
    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType('NaturalGas')
    hw_loop.addSupplyBranchForComponent(boiler)

    # Add setpoint manager
    setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch = OpenStudio::Model::ScheduleRuleset.new(model))
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 82.0)
    setpoint_mgr.addToNode(hw_loop.supplyOutletNode)

    hw_loop
  end
end
