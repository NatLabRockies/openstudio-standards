require_relative '../../test_helper'

# ECM HS09: Cold-Climate ASHP + Baseboards
# Critical for NECB Zones 6-8
#
# Components:
# - Cold-climate air source heat pump (variable or single speed)
# - Electric or hot water baseboards for backup
# - Air loops for heating/cooling
#
# Key methods under test:
# - apply_system_ecm with 'hs09_ccashp_baseboard'
# - apply_system_efficiencies_ecm
class TestECMHS09CCASHP < Minitest::Test
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

  def test_hs09_system_creation
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs09_ccashp_baseboard',
      template_standard: standard
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have air loops"

    heating_coils_vs = model.getCoilHeatingDXVariableSpeeds
    cooling_coils_vs = model.getCoilCoolingDXVariableSpeeds
    heating_coils_ss = model.getCoilHeatingDXSingleSpeeds
    cooling_coils_ss = model.getCoilCoolingDXSingleSpeeds

    total_heating_coils = heating_coils_vs.size + heating_coils_ss.size
    total_cooling_coils = cooling_coils_vs.size + cooling_coils_ss.size

    assert total_heating_coils > 0, "Should have DX heating coils for cold-climate ASHP"
    assert total_cooling_coils > 0, "Should have DX cooling coils for cold-climate ASHP"

    baseboards_electric = model.getZoneHVACBaseboardConvectiveElectrics
    baseboards_hw = model.getZoneHVACBaseboardConvectiveWaters
    total_baseboards = baseboards_electric.size + baseboards_hw.size
    assert total_baseboards > 0, "Should have baseboards in zones"
  end

  ##############################################################################
  # EFFICIENCY TESTS
  ##############################################################################

  def test_hs09_efficiency_application
    model, standard = create_baseline_necb_model_for_ecm

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs09_ccashp_baseboard',
      template_standard: standard
    )

    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs09_efficiency')

    ecm_std.apply_system_efficiencies_ecm(
      model: model,
      ecm_system_name: 'hs09_ccashp_baseboard',
      template_standard: standard
    )

    heating_coils_vs = model.getCoilHeatingDXVariableSpeeds
    if heating_coils_vs.size > 0
      heating_coils_vs.each do |coil|
        speeds = coil.speeds
        assert speeds.size > 0, "Variable speed coil should have at least one speed"
      end
    end

    heating_coils_ss = model.getCoilHeatingDXSingleSpeeds
    if heating_coils_ss.size > 0
      heating_coils_ss.each do |coil|
        rated_cop = coil.ratedCOP
        if rated_cop.respond_to?(:is_initialized)
          next unless rated_cop.is_initialized
          cop = rated_cop.get
        else
          cop = rated_cop
        end
        assert cop >= 1.5 && cop <= 5.0, "ASHP heating COP should be 1.5-5.0, got #{cop}"
      end
    end

    assert (heating_coils_vs.size + heating_coils_ss.size) > 0, "Should have heating coils"
  end

  ##############################################################################
  # CLIMATE TESTS
  ##############################################################################

  def test_hs09_in_zone_7
    model, standard = create_baseline_necb_model_for_ecm(climate: 'Yellowknife')

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs09_ccashp_baseboard',
      template_standard: standard
    )

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have air systems in Zone 7"

    baseboards_electric = model.getZoneHVACBaseboardConvectiveElectrics
    baseboards_hw = model.getZoneHVACBaseboardConvectiveWaters
    total_baseboards = baseboards_electric.size + baseboards_hw.size
    assert total_baseboards > 0, "Should have backup heating baseboards in cold climate"
  end
end
