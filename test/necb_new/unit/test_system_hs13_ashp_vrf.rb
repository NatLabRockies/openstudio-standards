# ECM HS13: ASHP + VRF
# Similar to HS08 with different DOAS configuration
#
# Components:
# - DOAS air loop with ASHP
# - VRF outdoor unit
# - VRF terminal units
# - Electric baseboards for backup heating
class TestECMHS13ASHPVRF < Minitest::Test
  include(NecbHelper)

  def test_hs13_system_creation
    model, standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    ecm_std = Standard.build('ECMS')
    ecm_std.apply_system_ecm(
      model: model,
      ecm_system_name: 'hs13_ashp_vrf',
      template_standard: standard)

    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have DOAS air loop"

    vrf_outdoor = model.getAirConditionerVariableRefrigerantFlows
    assert vrf_outdoor.size > 0, "Should have VRF outdoor unit"

    vrf_terminals = model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert vrf_terminals.size > 0, "Should have VRF terminal units"

    baseboards = model.getZoneHVACBaseboardConvectiveElectrics
    assert baseboards.size > 0, "Should have electric baseboards for backup"
  end
end
