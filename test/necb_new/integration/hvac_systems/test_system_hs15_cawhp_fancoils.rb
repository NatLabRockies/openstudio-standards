require_relative '../../test_helper'

# ECM HS15: CAWHP + Fan Coils
# Condenser-assisted water heating with air-to-water heat pump
#
# Components:
# - Air-to-water heat pump (CAWHP)
# - Hot water and chilled water plant loops
# - Four-pipe fan coil units
# - Condenser heat recovery for domestic hot water
class TestECMHS15CAWHPFanCoils < Minitest::Test
  include(NecbHelper)

  def test_hs15_system_creation
    model, standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs15_cawhp_fancoils',
      template_standard: standard)

    plant_loops = model.getPlantLoops
    assert plant_loops.size >= 2, "Should have hot water and chilled water loops"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils"
  end
end
