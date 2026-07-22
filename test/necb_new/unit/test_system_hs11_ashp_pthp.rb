# ECM HS11: ASHP + PTHP (Packaged Terminal Heat Pumps)
# Most common ECM - hotels, apartments, offices
#
# Components:
# - DOAS with ASHP for ventilation
# - PTHP units in each zone
# - DX heating and cooling coils
class TestECMHS11ASHPPTHP < Minitest::Test
  include(NecbHelper)

  def setup
    @model, @standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    @ecm_std = Standard.build('ECMS')
    @ecm_std.apply_system_ecm(
      model: @model,
      ecm_system_name: 'hs11_ashp_pthp',
      template_standard: @standard)
  end

  def test_hs11_system_creation
    air_loops = @model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have DOAS air loop"

    heating_coils_dx = @model.getCoilHeatingDXSingleSpeeds
    cooling_coils_dx = @model.getCoilCoolingDXSingleSpeeds
    assert heating_coils_dx.size > 0, "Should have DX heating coils for ASHP"
    assert cooling_coils_dx.size > 0, "Should have DX cooling coils for ASHP"

    pthps = @model.getZoneHVACPackagedTerminalHeatPumps
    assert pthps.size > 0, "Should have PTHPs in zones"

    pthps.each do |pthp|
      assert pthp.heatingCoil.to_CoilHeatingDXSingleSpeed.is_initialized, "PTHP should have DX heating coil"
      assert pthp.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized, "PTHP should have DX cooling coil"
    end
  end

  def test_hs11_efficiency_application
    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    @standard.try_sizing_run(model: @model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs11_efficiency')

    @ecm_std.apply_system_efficiencies_ecm(
      model: @model,
      ecm_system_name: 'hs11_ashp_pthp',
      template_standard: @standard
    )

    heating_coils = @model.getCoilHeatingDXSingleSpeeds
    assert heating_coils.size > 0, "Should have heating coils"

    heating_coils.each do |coil|
      rated_cop = coil.ratedCOP
      if rated_cop.respond_to?(:is_initialized)
        next unless rated_cop.is_initialized
        cop = rated_cop.get
      else
        cop = rated_cop
      end
      assert cop >= 2.0 && cop <= 5.0, "Heat pump heating COP should be 2.0-5.0, got #{cop} for #{coil.name}"
    end

    cooling_coils = @model.getCoilCoolingDXSingleSpeeds
    assert cooling_coils.size > 0, "Should have cooling coils"

    cooling_coils.each do |coil|
      rated_cop = coil.ratedCOP
      if rated_cop.respond_to?(:is_initialized)
        next unless rated_cop.is_initialized
        cop = rated_cop.get
      else
        cop = rated_cop
      end
      assert cop >= 2.5 && cop <= 6.0, "Heat pump cooling COP should be 2.5-6.0, got #{cop} for #{coil.name}"
    end
  end
end
