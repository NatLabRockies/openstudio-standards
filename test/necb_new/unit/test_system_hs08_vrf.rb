require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# ECM HS08: Central Cooling ASHP + VRF
# DOAS with ASHP + VRF terminal units
#
# Components:
# - DOAS air loop with central cooling ASHP
# - VRF outdoor unit
# - VRF terminal units in each zone
class TestECMHS08VRF < Minitest::Test
  include(NecbHelper)

  def test_hs08_system_creation
    model, standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs08_ccashp_vrf',
      template_standard: standard)

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have DOAS air loop"

    vrf_outdoor = model.getAirConditionerVariableRefrigerantFlows
    assert vrf_outdoor.size > 0, "Should have VRF outdoor unit"

    vrf_terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert vrf_terminals.size > 0, "Should have VRF terminal units"

    zones = model.getThermalZones
    assert vrf_terminals.size >= zones.size, "Should have at least one VRF terminal per zone"
  end
end
