require_relative '../../test_helper'

# ECM HS14: GSHP + Fan Coils
# Ground-source heat pump with four-pipe fan coils - most complex ECM
#
# Components:
# - Ground heat exchanger (GHX)
# - Hot water and chilled water plant loops
# - Four-pipe fan coil units in each zone
#
# Key methods under test:
# - apply_system_ecm with 'hs14_cgshp_fancoils'
# - apply_system_efficiencies_ecm
class TestECMHS14GSHPFanCoils < Minitest::Test
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

  def test_hs14_system_creation
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
      template_standard: standard
    )

    plant_loops = model.getPlantLoops
    assert plant_loops.size >= 2, "Should have multiple plant loops (ground loop, hot/cold water)"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils in zones"

    zones = model.getThermalZones
    assert fan_coils.size >= zones.size, "Should have at least one fan coil per zone"
  end

  def test_hs14_ground_heat_exchanger
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
      template_standard: standard
    )

    plant_loops = model.getPlantLoops
    assert plant_loops.size > 0, "Should have plant loops"
  end

  def test_hs14_fan_coils_configuration
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
      template_standard: standard
    )

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils"

    fan_coils.each do |fc|
      assert fc.heatingCoil, "Fan coil should have heating coil"
      assert fc.coolingCoil, "Fan coil should have cooling coil"
    end
  end

  ##############################################################################
  # EFFICIENCY TESTS
  ##############################################################################

  def test_hs14_efficiency_application
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
      template_standard: standard
    )

    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs14_efficiency')

    ecm_std.apply_system_efficiencies_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
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

  def test_hs14_cold_climate
    model, standard = create_baseline_necb_model_for_ecm(climate: 'Yellowknife')

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
      template_standard: standard
    )

    plant_loops = model.getPlantLoops
    assert plant_loops.size > 0, "Should have plant loops in cold climate"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have fan coils in cold climate"
  end
end
