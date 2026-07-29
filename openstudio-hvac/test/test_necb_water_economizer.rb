require_relative 'test_helper'
require 'tmpdir'

# 8.4.4.12 / 8.4.5.12 Table -12 -> 5.2.2.9 (D-56): reference systems 2 and 5 get a
# WATER-side economizer, not the air economizer of 5.2.2.8.
#
# 5.2.2.9.(1) — chilling the distribution fluid by direct/indirect EVAPORATION —
# requires capability for 100% of the cooling load at outdoor WET-BULB <= 7 C.
# (2) — by SENSIBLE heat transfer — uses outdoor DRY-BULB <= 10 C. The reference
# rejects heat through an evaporative tower, so (1) binds.
#
# Before D-56 `apply_economizers` warned and returned for systems 2/5, the OA
# controller stayed NoEconomizer, and check_part5 then flagged the very same loop for
# having no economizer.
class TestNecbWaterEconomizer < Minitest::Test
  include FixtureHelper

  # a data centre above the 20 kW cooling threshold selects reference System 2
  def sys2_proposed
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PSZ RTU Electric and DX Coils and Electric Baseboard', zones)
    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(30_000.0) }
    model
  end

  def reference(model, types, vintage: '2020', storeys: 1)
    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, vintage: vintage,
      building: { storeys: storeys, zone_types: model.getThermalZones.to_h { |z| [z.nameString, types] } },
      audit: audit
    )
    [result, audit]
  end

  def sys2_reference(vintage: '2020')
    reference(sys2_proposed, 'Data centre', vintage: vintage)
  end

  def d56(audit)
    audit.entries.select { |e| e[:ruling].to_s.include?('D-56') }
  end

  # ---- topology ----

  def test_system_2_reference_gets_a_water_side_economizer
    result, audit = sys2_reference
    assert_equal [2], result.assignments.map(&:reference_system).uniq, 'precondition: System 2'
    hxs = result.model.getHeatExchangerFluidToFluids
    assert_equal 1, hxs.size, 'one economizer heat exchanger on the chilled-water plant'
    hx = hxs.first

    chw = result.model.getPlantLoops.find { |l| l.nameString == 'Chilled Water Loop' }
    cw  = result.model.getPlantLoops.find { |l| l.nameString == 'Condenser Water Loop' }
    refute_nil chw
    refute_nil cw
    assert(chw.supplyComponents(OpenStudio::Model::HeatExchangerFluidToFluid.iddObjectType).any?,
           'the exchanger is SUPPLY equipment on the chilled-water loop (the load)')
    assert(cw.demandComponents(OpenStudio::Model::HeatExchangerFluidToFluid.iddObjectType).any?,
           'and DEMAND equipment on the condenser loop (the evaporatively-cooled source)')

    entry = d56(audit).find { |e| e[:action].include?('water-side economizer built') }
    refute_nil entry
    assert_equal :decision, entry[:level]
    assert_equal '8.4.4.12. (Table -12 -> 5.2.2.9)', entry[:article]
    assert_equal 7.0, entry[:inputs][:capability_wet_bulb_c]
    refute_nil hx
  end

  # "Capable of ... 100% of the cooling load" is sizing, and the reference never
  # hard-sizes (L-23): sizing factor 1.0 on autosized UA and both design flows.
  def test_economizer_is_sized_for_the_full_design_load_and_never_hard_sized
    result, = sys2_reference
    hx = result.model.getHeatExchangerFluidToFluids.first
    assert hx.isHeatExchangerUFactorTimesAreaValueAutosized
    assert hx.isLoopSupplySideDesignFlowRateAutosized
    assert hx.isLoopDemandSideDesignFlowRateAutosized
    assert_in_delta 1.0, hx.sizingFactor, 1e-9
    assert_equal 'CoolingSetpointModulated', hx.controlType
    assert_equal 'FreeCooling', hx.heatTransferMeteringEndUseType
  end

  # The control needs a setpoint to modulate onto, and it is the loop's OWN
  # 8.4.4.10.(6) design exit temperature, not an invented number.
  def test_economizer_control_setpoint_is_the_loop_design_exit_temperature
    result, = sys2_reference
    hx = result.model.getHeatExchangerFluidToFluids.first
    chw = result.model.getPlantLoops.find { |l| l.nameString == 'Chilled Water Loop' }
    node = hx.supplyOutletModelObject.get.to_Node.get
    managers = node.setpointManagers.filter_map { |m| m.to_SetpointManagerScheduled.is_initialized ? m.to_SetpointManagerScheduled.get : nil }
    assert_equal 1, managers.size, 'the modulated control has a setpoint on the exchanger outlet'
    day = managers.first.schedule.to_ScheduleRuleset.get.defaultDaySchedule
    assert_in_delta chw.sizingPlant.designLoopExitTemperature, day.values.first, 1e-9
  end

  # Without this the economizer is inert: the builder pins the condenser loop at 29 C,
  # so the source is never colder than the chilled-water return.
  def test_condenser_setpoint_is_reset_to_the_outdoor_wet_bulb
    result, audit = sys2_reference
    cw = result.model.getPlantLoops.find { |l| l.nameString == 'Condenser Water Loop' }
    managers = cw.supplyOutletNode.setpointManagers
    assert_equal 1, managers.size, 'the constant 29 C setpoint is REPLACED, not stacked'
    reset = managers.first.to_SetpointManagerFollowOutdoorAirTemperature
    assert reset.is_initialized
    reset = reset.get
    assert_equal 'OutdoorAirWetBulb', reset.referenceTemperatureType,
                 'an evaporative tower tracks the wet bulb, not the dry bulb'
    tower = result.model.getCoolingTowerSingleSpeeds.first
    assert_in_delta tower.designApproachTemperature.get, reset.offsetTemperatureDifference, 1e-9,
                    "the offset is the tower's OWN design approach"
    chw = result.model.getPlantLoops.find { |l| l.nameString == 'Chilled Water Loop' }
    assert_in_delta chw.sizingPlant.designLoopExitTemperature, reset.minimumSetpointTemperature, 1e-9
    assert_in_delta cw.sizingPlant.designLoopExitTemperature, reset.maximumSetpointTemperature, 1e-9

    entry = d56(audit).find { |e| e[:action].include?('condenser loop setpoint reset') }
    refute_nil entry
    assert_equal '5.2.2.9.', entry[:article]
  end

  # Sentence (2) is declared inapplicable, not silently ignored.
  def test_sentence_2_sensible_criterion_is_declared_inapplicable
    _, audit = sys2_reference
    entry = d56(audit).find { |e| e[:action].include?('sensible-transfer criterion') }
    refute_nil entry
    assert_equal :info, entry[:level]
    assert_equal 10.0, entry[:inputs][:capability_dry_bulb_c]
  end

  def test_2025_cites_the_renumbered_article
    _, audit = sys2_reference(vintage: '2025')
    entry = d56(audit).find { |e| e[:action].include?('water-side economizer built') }
    refute_nil entry
    assert_equal '8.4.5.12. (Table -12 -> 5.2.2.9)', entry[:article]
  end

  # ---- articles that must NOT change ----

  # Systems 1/3/4/6 + HP keep the 5.2.2.8 AIR economizer and gain no heat exchanger.
  def test_air_economizer_systems_are_untouched
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    result, = reference(model, 'Office - enclosed')
    assert_equal [3], result.assignments.map(&:reference_system).uniq
    assert_empty result.model.getHeatExchangerFluidToFluids, 'no water economizer on an air-economizer system'
    kinds = result.model.getAirLoopHVACs.filter_map do |l|
      oa = l.airLoopHVACOutdoorAirSystem
      oa.is_initialized ? oa.get.getControllerOutdoorAir.getEconomizerControlType : nil
    end
    assert_equal ['DifferentialEnthalpy'], kinds.uniq
  end

  # 8.4.4.12 stays PARTIAL — the DX staging clauses 5.2.2.8.(4)-(5) are still open, and
  # test_necb_energy_recovery.rb:174 asserts the coverage entry remains a warning.
  def test_8_4_4_12_remains_partial_and_still_warns
    %w[2020 2025].each do |vintage|
      prefix = vintage == '2020' ? '8.4.4' : '8.4.5'
      entry = OpenStudioHVAC::NECB.rules(vintage)['article_coverage']['articles']
                                  .find { |a| a['article'] == "#{prefix}.12." }
      assert_equal 'partial', entry['status']
      assert_match(/5\.2\.2\.8\.\(4\)-\(5\)/, entry['gaps'], 'the open DX staging clauses are still declared')
    end
    _, audit = sys2_reference
    coverage = audit.entries.find { |e| e[:step] == :coverage && e[:article] == '8.4.4.12.' }
    refute_nil coverage
    assert_equal :warning, coverage[:level]
  end

  # ---- the QAQC checker must stop contradicting the builder ----

  def test_checker_no_longer_flags_a_loop_that_has_a_water_economizer
    result, = sys2_reference
    audit = OpenStudioHVAC::NECB.check_part5(result.model, vintage: '2020')
    flagged = audit.warnings.select { |w| w[:action].include?('NO economizer') }
    assert_empty flagged, 'the checker no longer contradicts the reference builder'
    note = audit.entries.find { |e| e[:action].include?('water-side economizer') && e[:step] == :check_part5 }
    refute_nil note
    assert_equal :info, note[:level]
    assert_equal '5.2.2.9.', note[:article]
    assert_equal 'D-56', note[:ruling]
  end

  # ...but a genuinely un-economized water-cooled loop is STILL a finding.
  def test_checker_still_flags_a_loop_with_no_economizer_at_all
    result, = sys2_reference
    result.model.getHeatExchangerFluidToFluids.each(&:remove)
    audit = OpenStudioHVAC::NECB.check_part5(result.model, vintage: '2020')
    assert(audit.warnings.any? { |w| w[:action].include?('NO economizer') },
           'removing the exchanger restores the 5.2.2.8 finding — the suppression is scoped, not blanket')
  end

  # ---- the capability gate: EnergyPlus must actually free-cool ----

  # 5.2.2.9.(1) verified as CAPABILITY, not as "an exchanger exists": in every hour of
  # an April run with a chilled-water load and outdoor wet-bulb <= 7 C, the economizer
  # must carry 100% of that load (chiller off).
  def test_energyplus_economizer_carries_the_whole_load_below_7c_wet_bulb
    skip 'openstudio CLI not available' unless openstudio_cli?

    result, = sys2_reference
    model = attach_weather!(result.model)
    %w[Site\ Outdoor\ Air\ Wetbulb\ Temperature Fluid\ Heat\ Exchanger\ Heat\ Transfer\ Rate
       Chiller\ Evaporator\ Cooling\ Rate].each do |name|
      OpenStudio::Model::OutputVariable.new(name, model).setReportingFrequency('Hourly')
    end
    Dir.mktmpdir('oshvac-wse-') do |dir|
      run_dir = run_energyplus!(model, dir, sizing_only: false, run_period: [4, 1, 4, 30])
      assert_clean_energyplus_run(run_dir, 'System 2 reference with the 5.2.2.9 water economizer')
      sql = model.sqlFile.get
      wb = run_period_series(sql, 'Site Outdoor Air Wetbulb Temperature')
      hx = run_period_series(sql, 'Fluid Heat Exchanger Heat Transfer Rate')
      chiller = chiller_load(sql)
      n = [wb.size, hx.size, chiller.size].min
      assert_operator n, :>, 100, 'a full month of hourly data'

      band = (0...n).map { |i| { wb: wb[i], hx: hx[i], load: hx[i] + chiller[i] } }
                    .select { |r| r[:load] > 100.0 && r[:wb] <= 7.0 }
      refute_empty band, 'the run period must contain loaded hours at or below 7 C wet-bulb'
      shortfall = band.reject { |r| r[:hx] / r[:load] > 0.999 }
      assert_empty shortfall,
                   "5.2.2.9.(1): #{shortfall.size} of #{band.size} in-band hours were NOT carried 100% by the " \
                   'economizer'
    end
  end

  RUN_PERIOD = "t.EnvironmentPeriodIndex IN (SELECT EnvironmentPeriodIndex FROM EnvironmentPeriods " \
               'WHERE EnvironmentType = 3) AND t.WarmupFlag = 0'

  # The shared DDY carries ~85 design days; an unfiltered hourly series is mostly
  # design-day hours, which are not the weather the criterion is about.
  def run_period_series(sql, name, key = nil)
    query = 'SELECT d.Value FROM ReportData d ' \
            'JOIN ReportDataDictionary dd ON d.ReportDataDictionaryIndex = dd.ReportDataDictionaryIndex ' \
            'JOIN Time t ON t.TimeIndex = d.TimeIndex ' \
            "WHERE dd.Name = '#{name}' AND dd.ReportingFrequency = 'Hourly' AND #{RUN_PERIOD}"
    query += " AND dd.KeyValue = '#{key}'" if key
    query += ' ORDER BY d.TimeIndex'
    value = sql.execAndReturnVectorOfDouble(query)
    value.is_initialized ? value.get.to_a : []
  end

  def chiller_load(sql)
    keys = sql.execAndReturnVectorOfString(
      "SELECT DISTINCT dd.KeyValue FROM ReportDataDictionary dd " \
      "WHERE dd.Name = 'Chiller Evaporator Cooling Rate' AND dd.ReportingFrequency = 'Hourly'"
    )
    series = (keys.is_initialized ? keys.get.to_a : []).map { |k| run_period_series(sql, 'Chiller Evaporator Cooling Rate', k) }
    return [] if series.empty?

    (0...series.map(&:size).min).map { |i| series.sum { |s| s[i] } }
  end
end
