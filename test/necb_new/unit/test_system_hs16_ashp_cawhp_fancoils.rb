require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# ECM HS16: ASHP + CAWHP + Fan Coils
# Combination system
#
# Components:
# - Air source heat pump (ASHP)
# - Condenser-assisted water heat pump (CAWHP)
# - Four-pipe fan coil units
# - Combines features of HS12 and HS15
class TestECMHS16ASHPCAWHPFanCoils < Minitest::Test
  include(NecbHelper)

  def test_hs16_system_creation
    model, standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs16_ashp_cawhp_fancoils',
      template_standard: standard)

    plant_loops = model.getPlantLoops
    assert plant_loops.size >= 2, "Should have plant loops"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils"
  end
end
