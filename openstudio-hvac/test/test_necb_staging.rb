require_relative 'test_helper'
require 'tmpdir'

# 8.4.4.9.(7) / 8.4.4.10.(8) staged heating and cooling (D-46..D-50).
#
# The SDK-only assertions run everywhere; the staging arithmetic itself needs a
# SIZED model, so the capacity-driven cases go through the openstudio CLI and
# skip without it.
class TestNecbStaging < Minitest::Test
  include FixtureHelper

  STAGED = { 'staged_coils' => true }.freeze
  GAS_PSZ = 'PSZ RTU Gas and DX Coils and Electric Baseboard'.freeze
  ELEC_PSZ = 'PSZ RTU Electric and DX Coils and Electric Baseboard'.freeze
  ASHP_PSZ = 'PSZ RTU ASHP with Electric and ASHP with Electric Supp. Heat Coils and Electric Baseboard'.freeze

  def setup
    @dir = nil
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def build(name, config: STAGED, weather: false)
    model = load_fixture
    attach_weather!(model) if weather
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, name, zones, control_zone: zones.first, config: config)
    [model, zones]
  end

  def size!(model, tag)
    @dir ||= Dir.mktmpdir('oshvac-staging-')
    run_energyplus!(model, "#{@dir}/#{tag}")
  end

  def rules
    OpenStudioHVAC::NECB.rules('2020')
  end

  def stage_caps(coil)
    coil.stages.map do |s|
      if s.respond_to?(:grossRatedTotalCoolingCapacity)
        OpenStudioHVAC::NECB::Efficiency.optional_f(s.grossRatedTotalCoolingCapacity) ||
          OpenStudioHVAC::NECB::Efficiency.optional_f(s.autosizedGrossRatedTotalCoolingCapacity)
      elsif s.respond_to?(:grossRatedHeatingCapacity)
        OpenStudioHVAC::NECB::Efficiency.optional_f(s.grossRatedHeatingCapacity) ||
          OpenStudioHVAC::NECB::Efficiency.optional_f(s.autosizedGrossRatedHeatingCapacity)
      else
        OpenStudioHVAC::NECB::Efficiency.optional_f(s.nominalCapacity) ||
          OpenStudioHVAC::NECB::Efficiency.optional_f(s.autosizedNominalCapacity)
      end
    end
  end

  # ---- topology: the flag gates it, and nothing else changes ----

  def test_flag_off_keeps_the_bare_single_speed_topology
    model, = build(GAS_PSZ, config: {})

    assert_empty model.getAirLoopHVACUnitarySystems, 'unflagged builds stay bare'
    assert_equal 1, model.getCoilCoolingDXSingleSpeeds.size
    assert_equal 1, model.getCoilHeatingGass.size
    assert_empty model.getCoilCoolingDXMultiSpeeds
  end

  def test_staged_gas_psz_builds_a_unitary_with_two_autosized_stages
    model, = build(GAS_PSZ)

    assert_equal 1, model.getAirLoopHVACUnitarySystems.size
    unitary = model.getAirLoopHVACUnitarySystems.first
    assert_equal 'Load', unitary.controlType
    refute unitary.controllingZoneorThermostatLocation.empty?, 'Load control needs a control zone'

    cooling = OpenStudioHVAC::Coils.multispeed(unitary.coolingCoil)
    heating = OpenStudioHVAC::Coils.multispeed(unitary.heatingCoil)
    assert_equal 'CoilCoolingDXMultiSpeed_dx', cooling.nameString
    assert_equal 'CoilHeatingGasMultiStage_gas', heating.nameString
    assert_equal 2, cooling.stages.size
    assert_equal 2, heating.stages.size
    cooling.stages.each { |s| assert s.isGrossRatedTotalCoolingCapacityAutosized, 'stage capacities stay autosized' }
    heating.stages.each { |s| assert s.isNominalCapacityAutosized, 'stage capacities stay autosized' }

    ratios = unitary.designSpecificationMultispeedObject.get.supplyAirflowRatioFields
    assert_equal [[0.5, 0.5], [1.0, 1.0]],
                 ratios.map { |f| [f.heatingRatio.get, f.coolingRatio.get] }
    # the SetpointManagerSingleZoneReheat stays on the loop outlet
    assert_equal 1, model.getSetpointManagerSingleZoneReheats.size
  end

  # D-49: electric resistance is not a furnace.
  def test_staged_electric_psz_keeps_a_single_stage_electric_coil
    model, = build(ELEC_PSZ)
    unitary = model.getAirLoopHVACUnitarySystems.first

    assert_equal 1, model.getCoilCoolingDXMultiSpeeds.size, '8.4.4.10.(8) still stages the DX cooling'
    assert_empty model.getCoilHeatingGasMultiStages
    refute unitary.heatingCoil.get.to_CoilHeatingElectric.empty?, 'electric heat stays a plain coil'
  end

  # The supplemental coil is a LOOP coil downstream of the unitary, not the
  # unitary's supplemental slot (D-46 deviation: the unitary sizes its
  # supplemental heater to the heat-pump capacity, starving the back-up heat).
  def test_staged_ashp_keeps_the_supplemental_coil_on_the_loop
    model, = build(ASHP_PSZ)
    unitary = model.getAirLoopHVACUnitarySystems.first

    assert unitary.supplementalHeatingCoil.empty?, 'no supplemental coil inside the unitary'
    air_loop = model.getAirLoopHVACs.first
    supp = air_loop.supplyComponents.select { |c| c.to_CoilHeatingElectric.is_initialized }
    assert_equal 1, supp.size, 'supplemental electric coil sits on the air loop'
    assert_equal 1, model.getCoilHeatingDXMultiSpeeds.size
    assert_equal 1, model.getCoilCoolingDXMultiSpeeds.size
    assert_in_delta(-10.0, model.getCoilHeatingDXMultiSpeeds.first.minimumOutdoorDryBulbTemperatureforCompressorOperation, 1e-6)
  end

  # Coils.supply_components is the contract every consumer relies on.
  def test_supply_components_descends_into_the_unitary
    model, = build(GAS_PSZ)
    air_loop = model.getAirLoopHVACs.first

    raw = air_loop.supplyComponents.map { |c| c.iddObjectType.valueName }
    assert_includes raw, 'OS_AirLoopHVAC_UnitarySystem'
    refute_includes raw, 'OS_Coil_Cooling_DX_MultiSpeed', 'the container hides the coils from a plain scan'

    deep = OpenStudioHVAC::Coils.supply_components(air_loop).map { |c| c.iddObjectType.valueName }
    assert_includes deep, 'OS_Fan_ConstantVolume'
    assert_includes deep, 'OS_Coil_Cooling_DX_MultiSpeed'
    assert_includes deep, 'OS_Coil_Heating_Gas_MultiStage'
  end

  # ---- staging arithmetic (needs sized capacities) ----

  def test_stage_count_follows_the_vendored_thresholds
    rule = rules['furnace_staging']
    assert_equal 66, rule['two_stage_max_kw']
    assert_equal 66, rule['stage_size_kw']
    assert_equal rules['dx_staging']['two_stage_max_kw'], rule['two_stage_max_kw']

    # the rule as implemented: N = kW <= two_stage_max ? 2 : min(ceil(kW/size), 4)
    counts = [10.0, 66.0, 66.1, 132.0, 132.1, 198.0, 264.0, 500.0].map do |kw|
      wanted = kw <= rule['two_stage_max_kw'] ? 2 : (kw / rule['stage_size_kw']).ceil
      [wanted, OpenStudioHVAC::NECB::Efficiency::MAX_STAGES].min
    end
    assert_equal [2, 2, 2, 2, 3, 3, 4, 4], counts
  end

  # D-62 — 5.2.2.8.(4)-(5): an ECONOMIZER system's staged cooling gets a
  # stage-count floor (lowest stage <= 25% at >= 70 kW, <= 50% at > 25 kW).
  # Capacities hard-set so top_stage_capacity is readable without a sizing run.
  def test_economizer_staging_floor_5_2_2_8
    spec = rules['economizer_dx_staging']
    assert_equal 0.25, spec['ge_70_kw_lowest_fraction']
    assert_equal 0.5, spec['over_25_kw_lowest_fraction']

    { 100.0 => 4, 40.0 => 2, 20.0 => 2 }.each do |kw, expected|
      model, = build(GAS_PSZ)
      unitary = model.getAirLoopHVACUnitarySystems.first
      coil = OpenStudioHVAC::Coils.multispeed(unitary.coolingCoil)
      coil.stages.each_with_index { |s, i| s.setGrossRatedTotalCoolingCapacity(kw * 1000.0 * (i + 1) / coil.stages.size) }
      model.getControllerOutdoorAirs.each { |c| c.setEconomizerControlType('DifferentialEnthalpy') }

      audit = OpenStudioHVAC::AuditLog.new
      OpenStudioHVAC::NECB::Efficiency.send(:apply_staging, model, rules, '2020', audit)
      assert_equal expected, coil.stages.size,
                   "#{kw} kW economizer system: lowest stage must be <= #{kw >= 70 ? 25 : 50}%"
      if kw >= 70
        entry = audit.entries.find { |e| e[:action].include?('5.2.2.8 economizer staging floor') }
        refute_nil entry, 'the floor decision is audited'
        assert_equal '5.2.2.8.(4)-(5)', entry[:article]
        assert_includes entry[:ruling].to_s, 'D-62'
      end
    end

    # No economizer -> the 8.4.4.10.(8) incremental rule alone (100 kW -> 2).
    model, = build(GAS_PSZ)
    unitary = model.getAirLoopHVACUnitarySystems.first
    coil = OpenStudioHVAC::Coils.multispeed(unitary.coolingCoil)
    coil.stages.each_with_index { |s, i| s.setGrossRatedTotalCoolingCapacity(100_000.0 * (i + 1) / coil.stages.size) }
    model.getControllerOutdoorAirs.each { |c| c.setEconomizerControlType('NoEconomizer') }
    OpenStudioHVAC::NECB::Efficiency.send(:apply_staging, model, rules, '2020', OpenStudioHVAC::AuditLog.new)
    assert_equal 2, coil.stages.size, 'no economizer: ceil(100/66) = 2, no floor'
  end

  def test_staged_capacities_size_to_equal_increments_and_efficiencies_bin_on_the_total
    skip 'openstudio CLI not available' unless openstudio_cli?

    model, = build(GAS_PSZ, weather: true)
    size!(model, 'gas')

    cooling = model.getCoilCoolingDXMultiSpeeds.first
    heating = model.getCoilHeatingGasMultiStages.first
    [cooling, heating].each do |coil|
      caps = stage_caps(coil)
      refute_includes caps, nil, "#{coil.nameString}: sized stage capacities"
      assert_in_delta 0.5, caps.first / caps.last, 1e-3, "#{coil.nameString}: stage 1 = half the total"
    end

    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)

    # one table row, applied to EVERY stage
    assert_equal 1, model.getCoilCoolingDXMultiSpeeds.first.stages.map(&:grossRatedCoolingCOP).uniq.size
    assert_operator model.getCoilCoolingDXMultiSpeeds.first.stages.first.grossRatedCoolingCOP, :>, 2.0
    burner = model.getCoilHeatingGasMultiStages.first.stages.map(&:gasBurnerEfficiency).uniq
    assert_equal 1, burner.size
    assert_operator burner.first, :>=, 0.75

    staged = audit.entries.select { |e| e[:action].to_s.include?('equal stages') }
    refute_empty staged, 'the staging decision is audited'
    assert(staged.all? { |e| e[:ruling].to_s.include?('D-46') }, 'staging entries cite D-46')
    assert(staged.all? { |e| e[:article].to_s =~ /8\.4\.4\.(9|10)\./ })
  end

  # D-43 compatibility: the count can move after sizing and the capacities
  # follow on the next sizing run — nothing is hard-set.
  def test_stage_count_can_be_raised_after_sizing_and_recapacitates
    skip 'openstudio CLI not available' unless openstudio_cli?

    model, = build(GAS_PSZ, weather: true)
    size!(model, 'restage_a')
    cooling = model.getCoilCoolingDXMultiSpeeds.first
    total_before = stage_caps(cooling).last

    unitary = model.getAirLoopHVACUnitarySystems.first
    OpenStudioHVAC::NECB::Efficiency.resize_stages(cooling, 3)
    OpenStudioHVAC::Coils.set_stage_flow_ratios(unitary)
    model.resetSqlFile if model.respond_to?(:resetSqlFile)
    size!(model, 'restage_b')

    caps = stage_caps(model.getCoilCoolingDXMultiSpeeds.first)
    assert_equal 3, caps.size
    assert_in_delta 1.0 / 3, caps[0] / caps[2], 1e-3
    assert_in_delta 2.0 / 3, caps[1] / caps[2], 1e-3
    assert_in_delta total_before, caps.last, total_before * 0.02, 'the total is unchanged by re-staging'
  end

  # D-47: above the four-stage ceiling the count is clamped and SHOUTED.
  def test_clamp_at_the_four_stage_ceiling_warns_loudly
    model, = build(GAS_PSZ)
    coil = model.getCoilHeatingGasMultiStages.first
    coil.stages.each { |s| s.setNominalCapacity(400_000.0) } # 400 kW -> 7 stages wanted

    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB::Efficiency.apply_staging(model, rules, '2020', audit)

    assert_equal 4, model.getCoilHeatingGasMultiStages.first.stages.size
    clamp = audit.entries.find { |e| e[:action].to_s.include?('CLAMPED') }
    refute_nil clamp, 'the clamp is audited'
    assert_equal :warning, clamp[:level], 'the clamp is a warning, not an info'
    assert_includes clamp[:action], 'EXCEEDS', 'violations are SHOUTED (report checklist parses case-sensitively)'
    assert_equal 'D-47', clamp[:ruling]
  end

  # Growing the stage count appends a stage EnergyPlus has never sized, so the
  # new top stage reads back nil — the efficiency binning must use the total
  # measured BEFORE re-staging, not a re-read.
  def test_efficiencies_still_bin_when_staging_grows_the_stage_count
    model, = build(GAS_PSZ)
    coil = model.getCoilHeatingGasMultiStages.first
    coil.stages.each { |s| s.setNominalCapacity(150_000.0) } # -> ceil(150/66) = 3 stages

    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)

    grown = model.getCoilHeatingGasMultiStages.first
    assert_equal 3, grown.stages.size
    grown.stages.each do |stage|
      assert stage.isNominalCapacityAutosized, 'the added stage is autosized, never hard-set'
      assert_operator stage.gasBurnerEfficiency, :>=, 0.75, 'every stage got the table value'
    end
    # the unsized DX cooling coil still warns loudly (nothing gave it a capacity);
    # the GAS coil, whose total was measured before re-staging, must not.
    gas_warnings = audit.warnings.select do |w|
      "#{w[:target]} #{w[:action]}".include?('CoilHeatingGasMultiStage')
    end
    assert_empty gas_warnings, 'no capacity-unavailable warning after a stage-count growth'
  end

  # D-48: PTAC/PTHP terminals and make-up-air DX stay single-speed, audited.
  def test_zone_terminal_dx_is_skipped_and_audited
    model, = build('PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC', config: {})
    audit = OpenStudioHVAC::NECB::AuditLog.new
    OpenStudioHVAC::NECB::Efficiency.apply_staging(model, rules, '2020', audit)

    skips = audit.entries.select { |e| e[:ruling] == 'D-48' }
    refute_empty skips, 'the single-speed skips are audited'
    assert(skips.all? { |e| e[:level] == :info })
    assert(skips.any? { |e| e[:action].include?('zone-terminal DX') })
    refute_empty model.getCoilCoolingDXSingleSpeeds, 'terminals keep single-speed coils'
  end

  # ---- D-50: the terminal/secondary split ----

  def test_make_up_air_systems_carry_dedicated_outdoor_air_zone_sizing
    model, zones = build('PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC', config: {})

    zones.each do |zone|
      sizing = zone.sizingZone
      assert sizing.accountforDedicatedOutdoorAirSystem, "#{zone.nameString}: DOAS accounting on"
      assert_equal 'NeutralSupplyAir', sizing.dedicatedOutdoorAirSystemControlStrategy
      low = sizing.dedicatedOutdoorAirLowSetpointTemperatureforDesign.get
      high = sizing.dedicatedOutdoorAirHighSetpointTemperatureforDesign.get
      assert_operator low, :<, high, 'EnergyPlus rejects low >= high with a Severe'
      assert_in_delta 20.0, low, 1e-6
    end
  end

  def test_mixed_air_systems_do_not_get_dedicated_outdoor_air_accounting
    _model, zones = build(GAS_PSZ)

    zones.each do |zone|
      refute zone.sizingZone.accountforDedicatedOutdoorAirSystem,
             'sys 3/4 mix outdoor air into the supply stream — no DOAS accounting'
    end
  end

  def test_reference_transform_audits_the_split_for_both_shapes
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    types = zones.to_h { |z| [z.nameString, 'Office - enclosed'] }
    result = OpenStudioHVAC::NECB.reference_hvac(model, building: { storeys: 1, zone_types: types })

    split = result.audit.entries.select { |e| e[:ruling] == 'D-50' }
    refute_empty split, 'the terminal/secondary split is audited'
    assert(split.all? { |e| e[:article] =~ /8\.4\.4\.9\.\(3\)/ })
  end
  # A staged unit reduces supply flow with capacity (the E+ multispeed coil
  # requires flow to track per-stage capacity), but must not stage below the
  # ventilation air it exists to deliver.
  def test_stage_flow_ratios_are_floored_at_the_outdoor_air_fraction
    model = OpenStudio::Model::Model.new
    unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
    coil = OpenStudioHVAC::Coils.dx_cooling_multi_speed(model, model.alwaysOnDiscreteSchedule)
    unitary.setCoolingCoil(coil)
    performance = OpenStudio::Model::UnitarySystemPerformanceMultispeed.new(model)
    unitary.setDesignSpecificationMultispeedObject(performance)

    # Two stages, no floor: stage 1 rides at half flow.
    OpenStudioHVAC::Coils.set_stage_flow_ratios(unitary)
    ratios = performance.supplyAirflowRatioFields.map { |f| f.coolingRatio.get }
    assert_in_delta 0.5, ratios.first, 1e-6
    assert_in_delta 1.0, ratios.last, 1e-6

    # A 70% outdoor-air unit cannot drop to 50% flow — the floor binds.
    OpenStudioHVAC::Coils.set_stage_flow_ratios(unitary, min_ratio: 0.7)
    floored = performance.supplyAirflowRatioFields.map { |f| f.coolingRatio.get }
    assert_in_delta 0.7, floored.first, 1e-6, 'low stage floored at the ventilation fraction'
    assert_in_delta 1.0, floored.last, 1e-6, 'top stage still full flow'

    # A floor below the natural ratio changes nothing, and no ratio exceeds 1.
    OpenStudioHVAC::Coils.set_stage_flow_ratios(unitary, min_ratio: 0.2)
    assert_in_delta 0.5, performance.supplyAirflowRatioFields.first.coolingRatio.get, 1e-6
    OpenStudioHVAC::Coils.set_stage_flow_ratios(unitary, min_ratio: 1.5)
    assert(performance.supplyAirflowRatioFields.all? { |f| f.coolingRatio.get <= 1.0 + 1e-9 })
  end
end
