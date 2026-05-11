require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# Comprehensive Test Suite for NECB HVAC Systems 1 and 4
#
# SYSTEM 1: PTAC/PTHP (Packaged Terminal Air Conditioner/Heat Pump)
# - Components: PTAC with DX cooling, electric heating coil (always off), zone baseboards
# - Applications: Hotels, apartments, residential spaces, small data centers
# - File: hvac_system_1_single_speed.rb
#
# SYSTEM 4: PSZ (Packaged Single Zone)
# - Components: Single-zone rooftop unit with DX cooling, gas/electric heating, zone baseboards
# - Applications: Automotive areas, warehouses, food service with vented appliances
# - File: hvac_system_4.rb
#
# Test Coverage:
# - System creation and component verification
# - Multi-zone assignment and configuration
# - Vintage variations (NECB2011/2015/2017/2020)
# - Climate zone variations
# - Heating/cooling component verification after sizing
# - Integration with hot water loops
class TestNECBSystems1And4 < Minitest::Test
  include(NecbHelper)

  ##############################################################################
  # SYSTEM 1: PTAC with Baseboard Heating
  ##############################################################################

  def test_system_1_ptac_basic_creation
    # Test basic System 1 creation with PTAC units for each zone
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    # Create hot water loop for baseboards
    hw_loop = create_hot_water_loop(model, standard)

    # Add System 1 with PTAC + hot water baseboards
    result = standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      necb_reference_hp_supp_fuel: 'DefaultFuel',
      zones: zones,
      mau_type: false,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      multispeed: false
    )

    # Should return true on success
    assert result, "System 1 creation should return true"

    # Verify PTAC units were created for each zone
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    assert ptacs.length > 0, "Should create PTAC units"
    assert_equal zones.length, ptacs.length, "Should create one PTAC per zone"

    # Verify each PTAC is assigned to a zone
    ptacs.each do |ptac|
      assert ptac.thermalZone.is_initialized, "PTAC should be assigned to thermal zone"
    end
  end

  def test_system_1_ptac_dx_cooling_components
    # Test that PTAC units have proper DX cooling coils
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      mau_type: false,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      multispeed: false
    )

    ptacs = model.getZoneHVACPackagedTerminalAirConditioners

    ptacs.each do |ptac|
      # Verify cooling coil is single-speed DX
      cooling_coil = ptac.coolingCoil
      assert cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized,
             "PTAC should have single-speed DX cooling coil"

      dx_coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get

      # Verify DX coil has NECB performance curves
      assert dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve,
             "DX coil should have capacity-temperature curve"
      assert dx_coil.energyInputRatioFunctionOfTemperatureCurve,
             "DX coil should have EIR-temperature curve"
      assert dx_coil.partLoadFractionCorrelationCurve,
             "DX coil should have part load fraction curve"
    end
  end

  def test_system_1_ptac_heating_coil_always_off
    # Test that PTAC heating coils are electric but always off (baseboards provide heating)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      mau_type: false,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      multispeed: false
    )

    ptacs = model.getZoneHVACPackagedTerminalAirConditioners

    ptacs.each do |ptac|
      heating_coil = ptac.heatingCoil

      # Verify heating coil is electric
      assert heating_coil.to_CoilHeatingElectric.is_initialized,
             "PTAC should have electric heating coil"

      # Verify schedule is always off
      htg_coil = heating_coil.to_CoilHeatingElectric.get
      schedule = htg_coil.availabilitySchedule

      if schedule.to_ScheduleConstant.is_initialized
        const_sched = schedule.to_ScheduleConstant.get
        assert_equal 0.0, const_sched.value, "PTAC heating coil should be always off"
      end
    end
  end

  def test_system_1_with_mau
    # Test System 1 with Make-up Air Unit (MAU/DOAS)
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    # Add System 1 WITH MAU
    air_loop = standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      multispeed: false
    )

    # Should return air loop when MAU is created
    assert air_loop, "Should return air loop when MAU is present"
    assert air_loop.is_a?(OpenStudio::Model::AirLoopHVAC), "Should return AirLoopHVAC object"

    # Verify MAU air loop exists
    air_loops = model.getAirLoopHVACs
    assert air_loops.length > 0, "Should create MAU air loop"

    # Verify MAU has DX cooling coil
    dx_coils = model.getCoilCoolingDXSingleSpeeds
    assert dx_coils.length > 0, "MAU should have DX cooling coil"
  end

  def test_system_1_electric_baseboards
    # Test System 1 with electric baseboards
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      mau_type: false,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil,
      multispeed: false
    )

    # Verify electric baseboards were created
    electric_baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert electric_baseboards.length > 0, "Should create electric baseboards"
    assert_equal zones.length, electric_baseboards.length, "Should create one baseboard per zone"

    # Verify each baseboard is assigned to a zone
    electric_baseboards.each do |baseboard|
      assert baseboard.thermalZone.is_initialized, "Baseboard should be assigned to zone"
    end
  end

  def test_system_1_hot_water_baseboards
    # Test System 1 with hot water baseboards
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      mau_type: false,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      multispeed: false
    )

    # Verify hot water baseboards were created
    hw_baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert hw_baseboards.length > 0, "Should create hot water baseboards"
    assert_equal zones.length, hw_baseboards.length, "Should create one baseboard per zone"

    # Verify baseboards are connected to hot water loop
    hw_baseboards.each do |baseboard|
      coil = baseboard.heatingCoil
      assert coil.plantLoop.is_initialized, "Baseboard coil should be connected to plant loop"
      assert_equal hw_loop, coil.plantLoop.get, "Baseboard should be connected to hw_loop"
    end
  end

  ##############################################################################
  # SYSTEM 4: PSZ (Packaged Single Zone) with Baseboard Heating
  ##############################################################################

  def test_system_4_psz_basic_creation
    # Test basic System 4 creation with PSZ unit
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    # Add System 4 (PSZ with gas heating and hot water baseboards)
    air_loop = standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      necb_reference_hp_supp_fuel: 'DefaultFuel',
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Should return air loop
    assert air_loop, "System 4 creation should return air loop"
    assert air_loop.is_a?(OpenStudio::Model::AirLoopHVAC), "Should return AirLoopHVAC object"

    # Verify air loop was created
    air_loops = model.getAirLoopHVACs
    assert air_loops.length > 0, "Should create PSZ air loop"

    # Verify air loop name includes system identifier
    assert_match(/sys.*4/i, air_loop.name.to_s, "Air loop name should identify System 4")
  end

  def test_system_4_gas_heating_components
    # Test System 4 with gas heating coil
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Verify gas heating coil was created
    gas_heating_coils = model.getCoilHeatingGass
    assert gas_heating_coils.length > 0, "Should create gas heating coil"

    # Verify gas coil is on the air loop
    air_loop = model.getAirLoopHVACs.first
    supply_components = air_loop.supplyComponents

    has_gas_coil = supply_components.any? do |component|
      component.to_CoilHeatingGas.is_initialized
    end
    assert has_gas_coil, "Air loop should have gas heating coil"
  end

  def test_system_4_electric_heating_components
    # Test System 4 with electric heating coil
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Electric',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Verify electric heating coil was created
    electric_heating_coils = model.getCoilHeatingElectrics
    assert electric_heating_coils.length > 0, "Should create electric heating coil"
  end

  def test_system_4_dx_cooling_components
    # Test System 4 DX cooling coil configuration
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Verify DX cooling coil was created
    dx_coils = model.getCoilCoolingDXSingleSpeeds
    assert dx_coils.length > 0, "Should create DX cooling coil"

    dx_coils.each do |dx_coil|
      # Verify NECB performance curves
      assert dx_coil.totalCoolingCapacityFunctionOfTemperatureCurve,
             "DX coil should have capacity-temperature curve"
      assert dx_coil.energyInputRatioFunctionOfTemperatureCurve,
             "DX coil should have EIR-temperature curve"
      assert dx_coil.partLoadFractionCorrelationCurve,
             "DX coil should have part load fraction curve"
    end
  end

  def test_system_4_constant_volume_fan
    # Test System 4 uses constant volume fan
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Verify constant volume fan was created
    cv_fans = model.getFanConstantVolumes
    assert cv_fans.length > 0, "Should create constant volume fan"

    # Verify fan is on the air loop
    air_loop = model.getAirLoopHVACs.first
    supply_components = air_loop.supplyComponents

    has_cv_fan = supply_components.any? do |component|
      component.to_FanConstantVolume.is_initialized
    end
    assert has_cv_fan, "Air loop should have constant volume fan"
  end

  def test_system_4_outdoor_air_system
    # Test System 4 outdoor air system configuration
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    air_loop = model.getAirLoopHVACs.first

    # Verify outdoor air system exists
    oa_system = air_loop.airLoopHVACOutdoorAirSystem
    assert oa_system.is_initialized, "Air loop should have outdoor air system"

    oa_sys = oa_system.get
    oa_controller = oa_sys.getControllerOutdoorAir

    # Verify outdoor air controller mechanical ventilation method is ZoneSum
    mech_vent_controller = oa_controller.controllerMechanicalVentilation
    assert_equal 'ZoneSum', mech_vent_controller.systemOutdoorAirMethod,
                 "OA controller should use ZoneSum method per NECB"
  end

  def test_system_4_setpoint_manager_single_zone_reheat
    # Test System 4 uses SetpointManagerSingleZoneReheat
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    air_loop = model.getAirLoopHVACs.first

    # Verify setpoint manager is single zone reheat
    supply_outlet_node = air_loop.supplyOutletNode
    setpoint_managers = supply_outlet_node.setpointManagers

    assert setpoint_managers.length > 0, "Air loop should have setpoint manager"

    has_sz_reheat_spm = setpoint_managers.any? do |spm|
      spm.to_SetpointManagerSingleZoneReheat.is_initialized
    end
    assert has_sz_reheat_spm, "Should use SetpointManagerSingleZoneReheat for PSZ"
  end

  ##############################################################################
  # COMPONENT VERIFICATION AFTER SIZING
  ##############################################################################

  def test_system_1_components_after_sizing
    # Test System 1 component sizing
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      mau_type: false,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop,
      multispeed: false
    )

    # Run sizing
    run_dir = File.join(Dir.pwd, 'output', 'hvac_systems_1_4_tests')
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system1_sizing')

    # Verify PTAC DX coils have positive capacities
    ptacs = model.getZoneHVACPackagedTerminalAirConditioners
    ptacs.each do |ptac|
      cooling_coil = ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.get
      rated_capacity = cooling_coil.ratedTotalCoolingCapacity

      if rated_capacity.respond_to?(:is_initialized) && rated_capacity.is_initialized
        capacity = rated_capacity.get
        assert capacity > 0, "PTAC DX coil capacity should be positive after sizing"
      end
    end
  end

  def test_system_4_components_after_sizing
    # Test System 4 component sizing
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')

    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      necb_reference_hp: false,
      zones: zones,
      heating_coil_type: 'Gas',
      baseboard_type: 'Hot Water',
      hw_loop: hw_loop
    )

    # Run sizing
    run_dir = File.join(Dir.pwd, 'output', 'hvac_systems_1_4_tests')
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'system4_sizing')

    # Verify DX coil capacities
    dx_coils = model.getCoilCoolingDXSingleSpeeds
    dx_coils.each do |coil|
      rated_capacity = coil.ratedTotalCoolingCapacity
      if rated_capacity.respond_to?(:is_initialized) && rated_capacity.is_initialized
        capacity = rated_capacity.get
        assert capacity > 0, "DX coil capacity should be positive after sizing"
      end
    end

    # Verify heating coil capacities
    gas_heating_coils = model.getCoilHeatingGass
    gas_heating_coils.each do |coil|
      nominal_capacity = coil.nominalCapacity
      if nominal_capacity.respond_to?(:is_initialized) && nominal_capacity.is_initialized
        capacity = nominal_capacity.get
        assert capacity > 0, "Gas heating coil capacity should be positive after sizing"
      end
    end
  end

  ##############################################################################
  # MULTI-VINTAGE TESTING
  ##############################################################################

  def test_system_1_across_vintages
    # Test System 1 across NECB vintages
    ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'].each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Toronto')

      zones = model.getThermalZones
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys1_unitary_ac_baseboard_heating(
        model: model,
        necb_reference_hp: false,
        zones: zones,
        mau_type: false,
        mau_heating_coil_type: 'Electric',
        baseboard_type: 'Hot Water',
        hw_loop: hw_loop,
        multispeed: false
      )

      ptacs = model.getZoneHVACPackagedTerminalAirConditioners
      assert ptacs.length > 0, "#{vintage}: Should create PTAC units"
    end
  end

  def test_system_4_across_vintages
    # Test System 4 across NECB vintages
    ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'].each do |vintage|
      model, standard = create_baseline_necb_model(template: vintage, climate: 'Toronto')

      zones = model.getThermalZones
      hw_loop = create_hot_water_loop(model, standard)

      air_loop = standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
        model: model,
        necb_reference_hp: false,
        zones: zones,
        heating_coil_type: 'Gas',
        baseboard_type: 'Hot Water',
        hw_loop: hw_loop
      )

      assert air_loop, "#{vintage}: Should create PSZ air loop"

      dx_coils = model.getCoilCoolingDXSingleSpeeds
      assert dx_coils.length > 0, "#{vintage}: Should create DX cooling coil"
    end
  end

  ##############################################################################
  # CLIMATE VARIATION
  ##############################################################################

  def test_system_1_climate_variation
    # Test System 1 across different Canadian climate zones
    climates = [
      { name: 'Vancouver', zone: 4 },
      { name: 'Toronto', zone: 5 },
      { name: 'Yellowknife', zone: 8 }
    ]

    climates.each do |climate|
      model, standard = create_baseline_necb_model(template: 'NECB2011', climate: climate[:name])

      zones = model.getThermalZones
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys1_unitary_ac_baseboard_heating(
        model: model,
        necb_reference_hp: false,
        zones: zones,
        mau_type: false,
        mau_heating_coil_type: 'Electric',
        baseboard_type: 'Hot Water',
        hw_loop: hw_loop,
        multispeed: false
      )

      ptacs = model.getZoneHVACPackagedTerminalAirConditioners
      assert ptacs.length > 0, "#{climate[:name]} (Zone #{climate[:zone]}): Should create PTACs"
    end
  end

  def test_system_4_climate_variation
    # Test System 4 across different Canadian climate zones
    climates = [
      { name: 'Vancouver', zone: 4 },
      { name: 'Toronto', zone: 5 },
      { name: 'Yellowknife', zone: 8 }
    ]

    climates.each do |climate|
      model, standard = create_baseline_necb_model(template: 'NECB2011', climate: climate[:name])

      zones = model.getThermalZones
      hw_loop = create_hot_water_loop(model, standard)

      air_loop = standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
        model: model,
        necb_reference_hp: false,
        zones: zones,
        heating_coil_type: 'Gas',
        baseboard_type: 'Hot Water',
        hw_loop: hw_loop
      )

      assert air_loop, "#{climate[:name]} (Zone #{climate[:zone]}): Should create PSZ"
    end
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  # Helper method to create baseline NECB model for testing
  # Reuses scaffolding from remaining_hvac_tests - includes thermostats and thermal zones
  def create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
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
    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 82.0)
    setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch)
    setpoint_mgr.addToNode(hw_loop.supplyOutletNode)

    hw_loop
  end
end
