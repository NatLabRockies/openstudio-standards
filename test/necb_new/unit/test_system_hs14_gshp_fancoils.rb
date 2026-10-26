require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# ECM HS14: GSHP + Fan Coils
# Ground-source heat pump with four-pipe fan coils - most complex ECM
#
# Components:
# - Ground heat exchanger (GHX)
# - Hot water and chilled water plant loops
# - Four-pipe fan coil units in each zone
class TestECMHS14GSHPFanCoils < Minitest::Test
  include(NecbHelper)

  def test_hs14_system_creation
    model, standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs14_cgshp_fancoils',
      template_standard: standard)

    plant_loops = model.getPlantLoops
    assert plant_loops.size >= 2, "Should have multiple plant loops (ground loop, hot/cold water)"

    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "Should have four-pipe fan coils in zones"

    zones = model.getThermalZones
    assert fan_coils.size >= zones.size, "Should have at least one fan coil per zone"
  end
end
