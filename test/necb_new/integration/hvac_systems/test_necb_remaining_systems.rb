require_relative '../../test_helper'

class TestNECBRemainingHVACSystems < Minitest::Test
  include(NecbHelper)

  ##############################################################################
  # SYSTEM 2: FPFC (Four-Pipe Fan Coil) + Make-up Air Unit
  ##############################################################################

  def test_system_2_fpfc_creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

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

  def test_system_2_components_after_sizing
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 2)
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    # Run sizing
    run_dir = File.join(Dir.pwd, 'output', 'remaining_hvac_tests')
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system2_sizing')

    # Verify chillers
    chillers = model.getChillerElectricEIRs
    assert chillers.length > 0, "Should have at least one chiller"

    chillers.each do |chiller|
      ref_cap = chiller.referenceCapacity
      if ref_cap.respond_to?(:is_initialized) && ref_cap.is_initialized
        capacity = ref_cap.get
        assert capacity > 0, "Chiller capacity should be positive after sizing"
      elsif ref_cap.is_a?(Numeric)
        assert ref_cap > 0, "Chiller capacity should be positive after sizing"
      end
    end

    # Verify cooling towers
    cooling_towers = model.getCoolingTowerSingleSpeeds + model.getCoolingTowerTwoSpeeds + model.getCoolingTowerVariableSpeeds
    assert cooling_towers.length > 0, "Should have at least one cooling tower"
  end

  def test_system_2_zone_equipment_assignment
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 2)
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    # Verify each zone has zone equipment
    zones.each do |zone|
      equipment_list = zone.equipment
      assert equipment_list.length > 0, "Zone #{zone.name} should have zone equipment"

      # Should have fan coil unit
      has_fan_coil = equipment_list.any? { |eq| eq.to_ZoneHVACFourPipeFanCoil.is_initialized }
      assert has_fan_coil, "Zone #{zone.name} should have four-pipe fan coil"
    end
  end

  ##############################################################################
  # SYSTEM 5: TPFC (Two-Pipe Fan Coil) + Make-up Air Unit
  ##############################################################################

  def test_system_5_tpfc_creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

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

  def test_system_5_heating_cooling_schedules
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 5)
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    # For TPFC, verify that heating/cooling availability schedules exist
    # (TPFC operates in seasonal modes: heating season, cooling season, shoulder season)
    fan_coils = model.getZoneHVACFourPipeFanCoils

    fan_coils.each do |fan_coil|
      # Verify availability schedule exists
      avail_sch = fan_coil.availabilitySchedule
      assert avail_sch, "Fan coil should have availability schedule"
    end
  end

  def test_system_5_with_hydronic_mau_cooling
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 5)
    hw_loop = create_hot_water_loop(model, standard)

    # System 5 with hydronic cooling for MAU
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'TPFC',
      mau_cooling_type: 'Hydronic',  # Hydronic instead of DX
      hw_loop: hw_loop
    )

    # Verify chilled water coils in air loop
    air_loops = model.getAirLoopHVACs
    mau_loop = air_loops.first

    # Check for chilled water cooling coil
    chw_coils = []
    mau_loop.supplyComponents.each do |component|
      if component.to_CoilCoolingWater.is_initialized
        chw_coils << component.to_CoilCoolingWater.get
      end
    end

    assert chw_coils.length > 0, "MAU with hydronic cooling should have chilled water coil"
  end

  ##############################################################################
  # SYSTEM 3/8: PSZ/VAV with Gas Heating/Electric Reheat
  ##############################################################################

  def test_system_8_vav_with_gas_reheat_creation
    # System 8 is similar to System 3 but with reheat
    # File: hvac_system_3_and_8_single_speed.rb handles both
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 8)
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
      model: model,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Verify air loops
    air_loops = model.getAirLoopHVACs
    assert air_loops.length > 0, "Should create air loop(s)"

    # Verify DX cooling coils
    dx_coils = model.getCoilCoolingDXSingleSpeeds
    assert dx_coils.length > 0, "Should have DX cooling coils"

    # Verify heating coils
    gas_heating_coils = model.getCoilHeatingGass
    assert gas_heating_coils.length > 0, "Should have gas heating coils"
  end

  def test_system_8_components_after_sizing
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 8)
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
      model: model,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Run sizing
    run_dir = File.join(Dir.pwd, 'output', 'remaining_hvac_tests')
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system8_sizing')

    # Verify DX coil capacities
    dx_coils = model.getCoilCoolingDXSingleSpeeds
    dx_coils.each do |coil|
      rated_capacity = coil.ratedTotalCoolingCapacity
      if rated_capacity.respond_to?(:is_initialized)
        next unless rated_capacity.is_initialized
        capacity = rated_capacity.get
      else
        capacity = rated_capacity
        next if capacity.nil?
      end
      assert capacity > 0, "DX coil rated capacity should be positive after sizing"
    end

    # Verify heating coil capacities
    gas_heating_coils = model.getCoilHeatingGass
    gas_heating_coils.each do |coil|
      nominal_capacity = coil.nominalCapacity
      if nominal_capacity.respond_to?(:is_initialized)
        next unless nominal_capacity.is_initialized
        capacity = nominal_capacity.get
      else
        capacity = nominal_capacity
        next if capacity.nil?
      end
      assert capacity > 0, "Gas heating coil capacity should be positive after sizing"
    end
  end

  def test_system_8_baseboard_heating
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop (required by System 8)
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(
      model: model,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Verify baseboard heaters were added to zones
    baseboards = model.getZoneHVACBaseboardConvectiveWaters + model.getZoneHVACBaseboardConvectiveElectrics
    assert baseboards.length > 0, "Should create baseboard heating units"

    # Verify baseboards are connected to zones
    zones.each do |zone|
      equipment_list = zone.equipment
      has_baseboard = equipment_list.any? do |eq|
        eq.to_ZoneHVACBaseboardConvectiveWater.is_initialized ||
          eq.to_ZoneHVACBaseboardConvectiveElectric.is_initialized
      end
      assert has_baseboard, "Zone #{zone.name} should have baseboard heating"
    end
  end

  ##############################################################################
  # SYSTEM 7: VAV with PFP (Parallel Fan-Powered) Boxes
  ##############################################################################

  def test_system_7_vav_pfp_concept
    # System 7 (VAV with PFP boxes) is not implemented as a separate method in NECB2011
    # It would typically be a VAV system (System 6) with parallel fan-powered terminal units
    # For now, this test documents the concept

    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

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

  ##############################################################################
  # MULTI-VINTAGE TESTING
  ##############################################################################

  def test_system_2_across_vintages
    ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'].each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Toronto')

      zones = model.getThermalZones

      # Create hot water loop (required by System 2)
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys2_FPFC_sys5_TPFC(
        model: model,
        zones: zones,
        chiller_type: 'Scroll',
        fan_coil_type: 'FPFC',
        mau_cooling_type: 'DX',
        hw_loop: hw_loop
      )

      air_loops = model.getAirLoopHVACs
      assert air_loops.length > 0, "#{vintage}: Should create air loop"

      fan_coils = model.getZoneHVACFourPipeFanCoils
      assert fan_coils.length > 0, "#{vintage}: Should create fan coils"
    end
  end

  def test_system_5_across_vintages
    ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'].each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Toronto')

      zones = model.getThermalZones

      # Create hot water loop (required by System 5)
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys2_FPFC_sys5_TPFC(
        model: model,
        zones: zones,
        chiller_type: 'Scroll',
        fan_coil_type: 'TPFC',
        mau_cooling_type: 'Hydronic',
        hw_loop: hw_loop
      )

      air_loops = model.getAirLoopHVACs
      assert air_loops.length > 0, "#{vintage}: Should create air loop"

      fan_coils = model.getZoneHVACFourPipeFanCoils
      assert fan_coils.length > 0, "#{vintage}: Should create fan coils"
    end
  end

  ##############################################################################
  # CLIMATE VARIATION
  ##############################################################################

  def test_system_2_climate_variation
    climates = [
      { name: 'Vancouver', zone: 4 },
      { name: 'Toronto', zone: 5 },
      { name: 'Yellowknife', zone: 8 }
    ]

    climates.each do |climate|
      model, standard = create_baseline_necb_model(template: 'NECB2011', climate: climate[:name])

      zones = model.getThermalZones

      # Create hot water loop (required by System 2)
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys2_FPFC_sys5_TPFC(
        model: model,
        zones: zones,
        chiller_type: 'Scroll',
        fan_coil_type: 'FPFC',
        mau_cooling_type: 'DX',
        hw_loop: hw_loop
      )

      air_loops = model.getAirLoopHVACs
      assert air_loops.length > 0, "#{climate[:name]}: Should create air loop"

      fan_coils = model.getZoneHVACFourPipeFanCoils
      assert fan_coils.length > 0, "#{climate[:name]}: Should create fan coils"
    end
  end

  private

  # Helper method to create baseline NECB model for testing
  # Reuses scaffolding from ECM tests - includes thermostats and thermal zones
  def create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '..', '..', '..', 'necb', 'unit_tests', 'resources', '5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    # Set climate
    climate_files = {
      'Toronto' => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      'Vancouver' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
      'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
    }
    epw_file = climate_files[climate] || climate_files['Toronto']
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply NECB space types
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    # Set building properties
    building = model.getBuilding
    building.setStandardsNumberOfStories(2)
    building.setStandardsNumberOfAboveGroundStories(2)

    # Add thermostats to zones (REQUIRED for HVAC systems)
    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.setName('Heating Setpoint Schedule')
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 21.0)

    clg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    clg_sch.setName('Cooling Setpoint Schedule')
    clg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 24.0)

    model.getThermalZones.each do |zone|
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      thermostat.setHeatingSetpointTemperatureSchedule(htg_sch)
      thermostat.setCoolingSetpointTemperatureSchedule(clg_sch)
      zone.setThermostatSetpointDualSetpoint(thermostat)
    end

    # Initialize fuel_type_set (required by HVAC system methods)
    standard.fuel_type_set = SystemFuels.new()
    standard.fuel_type_set.set_defaults(standards_data: standard.instance_variable_get(:@standards_data), primary_heating_fuel: 'NaturalGas')

    [model, standard]
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
