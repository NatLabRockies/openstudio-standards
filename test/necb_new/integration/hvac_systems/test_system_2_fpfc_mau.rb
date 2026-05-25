require_relative '../../test_helper'

# NECB System 2: FPFC (Four-Pipe Fan Coil) + MAU
#
# Components:
# - Make-up Air Unit (MAU/DOAS) for ventilation
# - Four-pipe fan coil units in each zone
# - Chilled water plant with chillers
# - Hot water plant with boilers
# - Condenser water loop with cooling towers
#
# Applications:
# - Multi-story buildings, offices, schools
# - Buildings requiring simultaneous heating/cooling in different zones
# - Zone-level temperature control with centralized plants
#
# Variants:
# - Scroll vs Centrifugal chiller
# - DX vs Hydronic MAU cooling
# - Various heating fuel types
#
# Key methods under test:
# - add_sys2_FPFC_sys5_TPFC (with fan_coil_type: 'FPFC')
class TestNECBSystem2 < Minitest::Test
  include NecbHelper

  ##############################################################################
  # BASIC SYSTEM CREATION TESTS
  ##############################################################################

  def test_system_2_basic_creation
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size >= 1, "Should have at least one air loop (MAU)"

    mau_loop = air_loops.find { |loop|
      loop.name.to_s.downcase.include?('sys_2') ||
      loop.name.to_s.downcase.include?('sys 2') ||
      loop.name.to_s.downcase.include?('make-up') ||
      loop.name.to_s.downcase.include?('doas')
    }
    refute_nil mau_loop, "Should have System 2 make-up air unit"

    chw_loops = model.getPlantLoops.select { |loop|
      loop.name.to_s.downcase.include?('chw') ||
      loop.name.to_s.downcase.include?('chilled')
    }
    assert chw_loops.size > 0, "Should have chilled water loop"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coil units"
  end

  def test_system_2_zone_equipment_assignment
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    zones = model.getThermalZones
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    zones.each do |zone|
      equipment_list = zone.equipment
      assert equipment_list.size > 0, "Zone #{zone.name} should have zone equipment"

      has_fan_coil = equipment_list.any? { |eq|
        eq.to_ZoneHVACFourPipeFanCoil.is_initialized
      }
      assert has_fan_coil, "Zone #{zone.name} should have four-pipe fan coil"
    end
  end

  ##############################################################################
  # CHILLER TYPE TESTS
  ##############################################################################

  def test_system_2_with_scroll_chiller
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    chillers = model.getChillerElectricEIRs
    assert chillers.size > 0, "Should have at least one chiller"
  end

  def test_system_2_with_centrifugal_chiller
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Centrifugal',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    chillers = model.getChillerElectricEIRs
    assert chillers.size > 0, "Should have centrifugal chiller"
  end

  ##############################################################################
  # MAU COOLING TYPE TESTS
  ##############################################################################

  def test_system_2_with_dx_mau_cooling
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'DX',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    mau_loop = air_loops.find { |loop|
      loop.name.to_s.downcase.include?('sys_2') ||
      loop.name.to_s.downcase.include?('sys 2')
    }
    refute_nil mau_loop, "Should have MAU air loop"

    dx_coils = []
    mau_loop.supplyComponents.each do |component|
      if component.to_CoilCoolingDXSingleSpeed.is_initialized ||
         component.to_CoilCoolingDXTwoSpeed.is_initialized
        dx_coils << component
      end
    end

    assert dx_coils.size > 0, "MAU should have DX cooling coil when mau_cooling_type is DX"
  end

  def test_system_2_with_hydronic_mau_cooling
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    mau_loop = air_loops.first

    chw_coils = []
    mau_loop.supplyComponents.each do |component|
      if component.to_CoilCoolingWater.is_initialized
        chw_coils << component.to_CoilCoolingWater.get
      end
    end

    assert chw_coils.size > 0, "MAU with hydronic cooling should have chilled water coil"
  end

  ##############################################################################
  # PLANT LOOP TESTS
  ##############################################################################

  def test_system_2_condenser_loop
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    cw_loops = model.getPlantLoops.select { |loop|
      loop.name.to_s.downcase.include?('cw') ||
      loop.name.to_s.downcase.include?('condenser')
    }
    assert cw_loops.size > 0, "Should have condenser water loop"

    cooling_towers = model.getCoolingTowerSingleSpeeds
    assert cooling_towers.size > 0, "Should have cooling tower"
  end

  def test_system_2_with_electric_boiler
    model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto', heating_fuel: 'Electricity')
    hw_loop = create_hot_water_loop(model, standard, boiler_fuel: 'Electricity')

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    boilers = model.getBoilerHotWaters
    assert boilers.size > 0, "Should have boilers on hot water loop"
  end

  ##############################################################################
  # NECB VINTAGE TESTS
  ##############################################################################

  def test_system_2_necb2015
    model, standard = create_baseline_necb_model(template: 'NECB2015', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size >= 1, "NECB2015 System 2 should create air loops"
  end

  def test_system_2_necb2017
    model, standard = create_baseline_necb_model(template: 'NECB2017', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size >= 1, "NECB2017 System 2 should create air loops"
  end

  def test_system_2_necb2020
    model, standard = create_baseline_necb_model(template: 'NECB2020', climate: 'Toronto')
    hw_loop = create_hot_water_loop(model, standard)

    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: model.getThermalZones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FPFC',
      mau_cooling_type: 'Hydronic',
      hw_loop: hw_loop
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size >= 1, "NECB2020 System 2 should create air loops"
  end

  ##############################################################################
  # CLIMATE VARIATION TESTS
  ##############################################################################

  def test_system_2_climate_variation
    climates = ['Vancouver', 'Toronto', 'Yellowknife']

    climates.each do |climate|
      model, standard = create_baseline_necb_model(template: 'NECB2011', climate: climate)
      hw_loop = create_hot_water_loop(model, standard)

      standard.add_sys2_FPFC_sys5_TPFC(
        model: model,
        zones: model.getThermalZones,
        chiller_type: 'Scroll',
        fan_coil_type: 'FPFC',
        mau_cooling_type: 'DX',
        hw_loop: hw_loop
      )

      air_loops = model.getAirLoopHVACs
      assert air_loops.size > 0, "#{climate}: Should create air loop"

      fan_coils = model.getZoneHVACFourPipeFanCoils
      assert fan_coils.size > 0, "#{climate}: Should create fan coils"
    end
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  def create_baseline_necb_model(template:, climate:, heating_fuel: 'NaturalGas')
    standard = Standard.build(template)

    resource_path = File.join(File.dirname(__FILE__), '..', '..', '..', 'necb', 'unit_tests', 'resources', '5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    climate_files = {
      'Toronto' => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
      'Vancouver' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
      'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
    }
    epw_file = climate_files[climate] || climate_files['Toronto']
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

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

    standard.fuel_type_set = SystemFuels.new
    standard.fuel_type_set.set_defaults(
      standards_data: standard.instance_variable_get(:@standards_data),
      primary_heating_fuel: heating_fuel
    )

    [model, standard]
  end

  def create_hot_water_loop(model, standard, boiler_fuel: 'NaturalGas')
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName('Hot Water Loop')
    hw_loop.setMaximumLoopTemperature(82.0)
    hw_loop.setMinimumLoopTemperature(60.0)

    sizing = hw_loop.sizingPlant
    sizing.setLoopType('Heating')
    sizing.setDesignLoopExitTemperature(82.0)
    sizing.setLoopDesignTemperatureDifference(11.0)

    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.addToNode(hw_loop.supplyInletNode)

    boiler = OpenStudio::Model::BoilerHotWater.new(model)
    boiler.setFuelType(boiler_fuel)
    hw_loop.addSupplyBranchForComponent(boiler)

    htg_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 82.0)
    setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch)
    setpoint_mgr.addToNode(hw_loop.supplyOutletNode)

    hw_loop
  end
end
