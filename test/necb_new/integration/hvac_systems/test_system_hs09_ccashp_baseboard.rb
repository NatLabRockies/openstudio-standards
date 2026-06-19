require_relative '../../test_helper'

# ECM HS09: Cold-Climate ASHP + Baseboards
# Critical for NECB Zones 6-8
#
# Components:
# - Cold-climate air source heat pump (variable or single speed)
# - Electric or hot water baseboards for backup
# - Air loops for heating/cooling
class TestECMHS09CCASHP < Minitest::Test
  include NecbHelper

  def setup
    @model, @standard = create_baseline_necb_model(add_baseboard_heating: true)
    @ecm_std = Standard.build('ECMS')
    @ecm_std.apply_system_ecm(
      model: @model,
      ecm_system_name: 'hs09_ccashp_baseboard',
      template_standard: @standard
    )
  end

  def test_hs09_system_creation
    air_loops = @model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have air loops"

    heating_coils_vs = @model.getCoilHeatingDXVariableSpeeds
    cooling_coils_vs = @model.getCoilCoolingDXVariableSpeeds
    heating_coils_ss = @model.getCoilHeatingDXSingleSpeeds
    cooling_coils_ss = @model.getCoilCoolingDXSingleSpeeds

    total_heating_coils = heating_coils_vs.size + heating_coils_ss.size
    total_cooling_coils = cooling_coils_vs.size + cooling_coils_ss.size

    assert total_heating_coils > 0, "Should have DX heating coils for cold-climate ASHP"
    assert total_cooling_coils > 0, "Should have DX cooling coils for cold-climate ASHP"

    baseboards_electric = @model.getZoneHVACBaseboardConvectiveElectrics
    baseboards_hw = @model.getZoneHVACBaseboardConvectiveWaters
    total_baseboards = baseboards_electric.size + baseboards_hw.size
    assert total_baseboards > 0, "Should have baseboards in zones"
  end

  def test_hs09_efficiency_application
    run_dir = File.join(Dir.pwd, 'output', "ecm_tests_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    @standard.try_sizing_run(model: @model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs09_efficiency')

    @ecm_std.apply_system_efficiencies_ecm(
      model: @model,
      ecm_system_name: 'hs09_ccashp_baseboard',
      template_standard: @standard
    )

    heating_coils_vs = @model.getCoilHeatingDXVariableSpeeds
    if heating_coils_vs.size > 0
      heating_coils_vs.each do |coil|
        speeds = coil.speeds
        assert speeds.size > 0, "Variable speed coil should have at least one speed"
      end
    end

    heating_coils_ss = @model.getCoilHeatingDXSingleSpeeds
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
end
