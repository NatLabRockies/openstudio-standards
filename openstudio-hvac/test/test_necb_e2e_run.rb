require_relative 'test_helper'
require 'tmpdir'

# Full proposed -> reference -> EnergyPlus gate: the generated systems must actually
# RUN (translate, size, and — for the controls case — simulate a week) with no Fatal
# and no Severe errors. Pure gem + openstudio CLI; skips if the CLI is unavailable.
#
# ~4 EnergyPlus executions; expect a few minutes.
class TestNecbE2ERun < Minitest::Test
  include FixtureHelper

  def setup
    skip 'openstudio CLI not available' unless openstudio_cli?
    @dir = Dir.mktmpdir('oshvac-e2e-')
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def office_types(model)
    model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }
  end

  # Proposed CBECS baseboards runs in E+; its sys3-gas reference sizes cleanly and the
  # efficiency pass lands real capacity-binned values on the sized reference.
  def test_proposed_and_sys3_reference_size_cleanly
    proposed = attach_weather!(load_fixture)
    zones = proposed.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(proposed, 'Baseboard gas boiler', zones)

    run_dir = run_energyplus!(proposed, "#{@dir}/proposed")
    assert_clean_energyplus_run(run_dir, 'proposed (Baseboard gas boiler)')

    result = OpenStudioHVAC::NECB.reference_hvac(proposed,
                                                 building: { storeys: 1, zone_types: office_types(proposed) })
    assert_equal [3], result.assignments.map(&:reference_system).uniq

    ref_run = run_energyplus!(result.model, "#{@dir}/reference")
    assert_clean_energyplus_run(ref_run, 'reference (sys3 gas)')

    # efficiencies on the now-sized reference: no 'not sized' warnings, values applied
    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(result.model, vintage: '2020', audit: audit)
    assert_empty audit.warnings.select { |w| w[:action].include?('not sized') },
                 'all components sized after the reference E+ run'
    # D-46: the sys3 reference furnace is a STAGED Coil:Heating:Gas:MultiStage
    # inside the unitary; the burner efficiency lands on every stage.
    gas_coil = result.model.getCoilHeatingGasMultiStages.min_by(&:nameString)
    refute_nil gas_coil, 'staged sys3 reference builds a multi-stage gas coil'
    assert_operator gas_coil.stages.size, :>=, 2, '8.4.4.9.(7): at least two equal stages'
    gas_coil.stages.each { |stage| assert_operator stage.gasBurnerEfficiency, :>=, 0.80 }
    boiler = result.model.getBoilerHotWaters.find { |b| b.nameString.include?('Primary') }
    assert_in_delta 0.90, boiler.nominalThermalEfficiency, 1e-6
  end

  # Air-source HP proposed -> Table 8.4.4.13 ASHP reference: a January week in
  # Toronto forces operation BELOW the -10 C compressor cutoff, so unmet hours
  # prove the supplemental heat + baseboards actually carry the load when the
  # heat pump locks out. (D-37: the proposed is a PTHP — air-source, which
  # REDIRECTS; the old 'Water source heat pumps' proposed here is by Note
  # A-8.4.4.13 a water-LOOP system whose internal boiler+fluid-cooler loop now
  # correctly KEEPS its Table -A selection — see test_necb_reference.rb.)
  def test_ashp_reference_conditions_through_a_cold_week
    proposed = attach_weather!(load_fixture)
    zones = proposed.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(proposed, 'PTHP', zones)

    result = OpenStudioHVAC::NECB.reference_hvac(proposed,
                                                 building: { storeys: 1, zone_types: office_types(proposed) })
    assert_equal ['hp'], result.assignments.map(&:reference_system).uniq

    ref_run = run_energyplus!(result.model, "#{@dir}/ashp_week", sizing_only: false)
    assert_clean_energyplus_run(ref_run, 'reference (ASHP per Table 8.4.4.13, one-week run)')
    assert_zones_conditioned(result.model.sqlFile.get, 'ASHP reference week',
                             max_heating_hours: 24, max_cooling_hours: 6)

    OpenStudioHVAC::NECB.apply_efficiencies(result.model, vintage: '2020')
    hp = result.model.getCoilHeatingDXMultiSpeeds.min_by(&:nameString)
    refute_nil hp, 'staged reference ASHP builds a multispeed heating coil'
    hp.stages.each { |stage| assert_operator stage.grossRatedHeatingCOP, :>, 2.0 }
    assert_in_delta(-10.0, hp.minimumOutdoorDryBulbTemperatureforCompressorOperation, 1e-6)
  end

  # The controls gate: a sys6 reference WITH the 8.4.4.19 ERV simulates a January week
  # (VAV + boiler/chiller plants + rotary HX + OA-pretreat SPM all active at runtime).
  # Mirrors the umbrella flow: sizing run -> apply_energy_recovery on the SIZED
  # flows (Table 5.2.10.1 trigger) -> week run.
  def test_sys6_reference_with_erv_simulates_a_week
    proposed = attach_weather!(load_fixture)
    zones = proposed.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(proposed, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    proposed.getSpaces.each do |space|
      spec = OpenStudio::Model::DesignSpecificationOutdoorAir.new(proposed)
      spec.setOutdoorAirFlowperFloorArea(0.001) # ~10%+ OA once sized; Always On -> continuous -> Table -B "R"
      space.setDesignSpecificationOutdoorAir(spec)
    end

    result = OpenStudioHVAC::NECB.reference_hvac(proposed,
                                                 building: { storeys: 3, zone_types: office_types(proposed) })
    assert_equal [6], result.assignments.map(&:reference_system).uniq

    run_energyplus!(result.model, "#{@dir}/sys6_sizing", sizing_only: true)
    erv_audit = OpenStudioHVAC::NECB.apply_energy_recovery(result.model, hdd: 3890)
    refute_empty result.model.getHeatExchangerAirToAirSensibleAndLatents, 'ERV present'
    decision = erv_audit.entries.find { |e| e[:action].include?('energy recovery added') }
    assert_equal 'continuous', decision[:inputs][:operation]

    ref_run = run_energyplus!(result.model, "#{@dir}/sys6_week", sizing_only: false)
    assert_clean_energyplus_run(ref_run, 'reference (sys6 + ERV, one-week run)')
    assert_zones_conditioned(result.model.sqlFile.get, 'sys6 reference week',
                             max_heating_hours: 24, max_cooling_hours: 6)

    # the simulation produced actual HVAC energy use (end-uses summary, GJ)
    sql = result.model.sqlFile.get
    hvac_gj = %i[electricityFans electricityCooling electricityHeating electricityPumps
                 naturalGasHeating].sum do |meter|
      value = sql.send(meter)
      value.is_initialized ? value.get : 0.0
    end
    assert_operator hvac_gj, :>, 0.0, 'week run produced HVAC energy use (fans/pumps/heating/cooling)'
  end
end
