require_relative '../helpers/minitest_helper'

# Part of the ASHRAE 90.1 Appendix G Performance Rating Method (PRM) baseline automation implementation test suite
# Check that the supplemental (electric) heat of air-source heat pump baseline systems
# is locked out above 40F outdoor dry-bulb temperature.
class AppendixGPRMTests < Minitest::Test
  LOCKOUT_TEMPERATURE_C = OpenStudio.convert(40.0, 'F', 'C').get

  def setup_supplemental_heat_lockout_model
    model = OpenStudio::Model::Model.new
    zones = Array.new(2) do |i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i + 1}")
      zone
    end
    return model, zones
  end

  # System 2, PTHP
  def test_pthp_supplemental_heat_lockout
    model, zones = setup_supplemental_heat_lockout_model
    standard = Standard.build('90.1-PRM-2019')
    standard.model_add_prm_baseline_system(model, 'PTHP', 'Electricity', 'Electricity', 'Electricity', zones, nil)

    pthps = model.getZoneHVACPackagedTerminalHeatPumps
    assert_equal(zones.size, pthps.size, 'Expected one PTHP per zone in the System 2 baseline.')
    pthps.each do |pthp|
      assert_in_delta(LOCKOUT_TEMPERATURE_C, pthp.maximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation, 0.01,
                      "The supplemental heater of #{pthp.name} should be locked out above 40F.")
    end
  end

  # System 4, PSZ-HP
  def test_psz_hp_supplemental_heat_lockout
    model, zones = setup_supplemental_heat_lockout_model
    standard = Standard.build('90.1-PRM-2019')
    standard.model_add_prm_baseline_system(model, 'PSZ_HP', 'Electricity', 'Electricity', 'Electricity', zones, nil)

    unitary_systems = model.getAirLoopHVACUnitarySystems
    assert_equal(zones.size, unitary_systems.size, 'Expected one unitary system per zone in the System 4 baseline.')
    unitary_systems.each do |unitary_system|
      assert_in_delta(LOCKOUT_TEMPERATURE_C, unitary_system.maximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation, 0.01,
                      "The supplemental heater of #{unitary_system.name} should be locked out above 40F.")
    end
  end
end
