require_relative '../../test_helper'

# ECM HS08: Central Cooling ASHP + VRF
# DOAS with ASHP + VRF terminal units
#
# Components:
# - DOAS air loop with central cooling ASHP
# - VRF outdoor unit
# - VRF terminal units in each zone
#
# Key methods under test:
# - apply_system_ecm with 'hs08_ccashp_vrf'
# - apply_system_efficiencies_ecm
class TestECMHS08VRF < Minitest::Test
  include NecbHelper

  class FuelTypeSet
    attr_accessor :ecm_fueltype, :baseboard_type, :force_airloop_hot_water,
                  :necb_reference_hp_supp_fuel, :boiler_fueltype, :backup_boiler_fueltype

    def initialize
      @ecm_fueltype = 'Electricity'
      @baseboard_type = 'Electric'
      @force_airloop_hot_water = false
      @necb_reference_hp_supp_fuel = 'DefaultFuel'
      @boiler_fueltype = 'NaturalGas'
      @backup_boiler_fueltype = 'NaturalGas'
    end
  end

  def create_baseline_necb_model_for_ecm(template: 'NECB2011', climate: 'Toronto')
    standard = Standard.build(template)

    resource_path = File.join(__dir__, '../../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
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

    building = model.getBuilding
    building.setStandardsNumberOfStories(2)
    building.setStandardsNumberOfAboveGroundStories(2)

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

    zones = model.getThermalZones.sort
    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Electric',
      baseboard_type: 'Electric',
      hw_loop: nil
    )

    def standard.fuel_type_set
      FuelTypeSet.new
    end

    [model, standard]
  end

  ##############################################################################
  # SYSTEM CREATION TESTS
  ##############################################################################

  def test_hs08_system_creation
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have DOAS air loop"

    vrf_outdoor = model.getAirConditionerVariableRefrigerantFlows
    assert vrf_outdoor.size > 0, "Should have VRF outdoor unit"

    vrf_terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert vrf_terminals.size > 0, "Should have VRF terminal units"

    zones = model.getThermalZones
    assert vrf_terminals.size >= zones.size, "Should have at least one VRF terminal per zone"
  end

  def test_hs08_vrf_outdoor_unit_configuration
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard
    )

    vrf_outdoor = model.getAirConditionerVariableRefrigerantFlows
    assert vrf_outdoor.size > 0, "Should have VRF outdoor unit"

    vrf_outdoor.each do |vrf|
      assert vrf.terminals.size > 0, "VRF outdoor unit should have connected terminals"
    end
  end

  def test_hs08_vrf_terminals_in_zones
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard
    )

    vrf_terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert vrf_terminals.size > 0, "Should have VRF terminal units installed"
  end

  ##############################################################################
  # EFFICIENCY TESTS
  ##############################################################################

  def test_hs08_efficiency_application
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard
    )

    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs08_efficiency')

    ecm_std.apply_system_efficiencies_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard
    )

    vrf_outdoor = model.getAirConditionerVariableRefrigerantFlows
    assert vrf_outdoor.size > 0, "Should have VRF outdoor unit"

    vrf_terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert vrf_terminals.size > 0, "Should have VRF terminal units"

    vrf_outdoor.each do |vrf|
      assert vrf.terminals.size > 0, "VRF outdoor unit should have terminals"
    end
  end

  ##############################################################################
  # CLIMATE TESTS
  ##############################################################################

  def test_hs08_cold_climate
    model, standard = create_baseline_necb_model_for_ecm(climate: 'Yellowknife')

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard
    )

    vrf_outdoor = model.getAirConditionerVariableRefrigerantFlows
    assert vrf_outdoor.size > 0, "Should have VRF outdoor unit in cold climate"

    vrf_terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert vrf_terminals.size > 0, "Should have VRF terminals in cold climate"
  end
end
