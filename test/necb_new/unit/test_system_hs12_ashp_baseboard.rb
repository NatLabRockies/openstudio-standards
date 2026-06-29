require_relative '../coverage_helper'

# ECM HS12: Standard ASHP + Baseboards
# Standard zones (4-5)
#
# Components:
# - Standard air source heat pump
# - Electric or hot water baseboards
# - Air loops for heating/cooling
class TestECMHS12ASHPBaseboard < Minitest::Test
  include(NecbHelper)

  def setup
    @model, @standard = create_baseline_necb_model(
      primary_heating_fuel: 'Electricity',
      add_thermostat: true,
      add_baseboard_heating: true)

    @ecm_std = Standard.build('ECMS')
    @ecm_std.apply_system_ecm(
      model: @model,
      ecm_system_name: 'hs12_ashp_baseboard',
      template_standard: @standard)
  end

  def test_hs12_system_creation
    air_loops = @model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have air loops"

    heating_coils_dx = @model.getCoilHeatingDXSingleSpeeds
    cooling_coils_dx = @model.getCoilCoolingDXSingleSpeeds
    assert heating_coils_dx.size > 0, "Should have DX heating coils for @standard ASHP"
    assert cooling_coils_dx.size > 0, "Should have DX cooling coils for @standard ASHP"

    baseboards_electric = @model.getZoneHVACBaseboardConvectiveElectrics
    baseboards_hw = @model.getZoneHVACBaseboardConvectiveWaters
    total_baseboards = baseboards_electric.size + baseboards_hw.size
    assert total_baseboards > 0, "Should have baseboards in zones"
  end

  def test_hs12_efficiency_application
    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    @standard.try_sizing_run(model: @model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs12_efficiency')

    @ecm_std.apply_system_efficiencies_ecm(
      model: @model,
      ecm_system_name: 'hs12_ashp_baseboard',
      template_standard: @standard
    )

    heating_coils = @model.getCoilHeatingDXSingleSpeeds
    heating_coils.each do |coil|
      rated_cop = coil.ratedCOP
      if rated_cop.respond_to?(:is_initialized)
        next unless rated_cop.is_initialized
        cop = rated_cop.get
      else
        cop = rated_cop
      end
      assert cop >= 2.0 && cop <= 5.0, "Standard ASHP heating COP should be 2.0-5.0, got #{cop}"
    end

    cooling_coils = @model.getCoilCoolingDXSingleSpeeds
    cooling_coils.each do |coil|
      rated_cop = coil.ratedCOP
      if rated_cop.respond_to?(:is_initialized)
        next unless rated_cop.is_initialized
        cop = rated_cop.get
      else
        cop = rated_cop
      end
      assert cop >= 2.5 && cop <= 6.0, "Standard ASHP cooling COP should be 2.5-6.0, got #{cop}"
    end
  end
end
