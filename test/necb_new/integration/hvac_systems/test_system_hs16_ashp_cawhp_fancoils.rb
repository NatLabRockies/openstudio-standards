require_relative '../../test_helper'

# ECM HS16: ASHP + CAWHP + Fan Coils
# Combination system
#
# Components:
# - Air source heat pump (ASHP)
# - Condenser-assisted water heat pump (CAWHP)
# - Four-pipe fan coil units
# - Combines features of HS12 and HS15
#
# Key methods under test:
# - apply_system_ecm with 'hs16_ashp_cawhp_fancoils'
# - apply_system_efficiencies_ecm
class TestECMHS16ASHPCAWHPFanCoils < Minitest::Test
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

  def test_hs16_system_creation
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs16_ashp_cawhp_fancoils',
      template_standard: standard
    )

    plant_loops = model.getPlantLoops
    assert plant_loops.size >= 2, "Should have plant loops"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils"
  end

  def test_hs16_combination_system
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs16_ashp_cawhp_fancoils',
      template_standard: standard
    )

    plant_loops = model.getPlantLoops
    assert plant_loops.size > 0, "Should have plant loops"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have fan coils"
  end

  ##############################################################################
  # EFFICIENCY TESTS
  ##############################################################################

  def test_hs16_efficiency_application
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs16_ashp_cawhp_fancoils',
      template_standard: standard
    )

    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs16_efficiency')

    ecm_std.apply_system_efficiencies_ecm(
      model: model,
      ecm_system_name: 'hs16_ashp_cawhp_fancoils',
      template_standard: standard
    )

    plant_loops = model.getPlantLoops
    assert plant_loops.size > 0, "Should have plant loops"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils"
  end

  ##############################################################################
  # CLIMATE TESTS
  ##############################################################################

  def test_hs16_across_climates
    climates = ['Vancouver', 'Toronto', 'Yellowknife']

    climates.each do |climate|
      model, standard = create_baseline_necb_model_for_ecm(climate: climate)

      ecm_std = Standard.build('ECMS')
      ecm_std.apply_system_ecm(
        model: model,
        ecm_system_name: 'hs16_ashp_cawhp_fancoils',
        template_standard: standard
      )

      plant_loops = model.getPlantLoops
      assert plant_loops.size > 0, "Should have plant loops in #{climate}"

      fan_coils = model.getZoneHVACFourPipeFanCoils
      assert fan_coils.size > 0, "Should have fan coils in #{climate}"
    end
  end
end
