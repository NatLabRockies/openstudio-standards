require_relative 'test_helper'
require 'tmpdir'

# Table 8.4.4.7.-B note (1) / Table 8.4.5.7.-B note (1) (D-55): "where present,
# humidification systems in the reference building shall use the same energy source
# as the corresponding humidification system in the proposed building".
#
# Before D-55 this was a bare COUNT taken before the teardown plus a warning — and
# nothing pinned it. Two defects came with it: the count also warned about
# humidifiers that go on to survive untouched on :copy_proposed loops, and the ones
# on replaced loops were destroyed as a side effect of `air_loop.remove` rather than
# deliberately.
class TestNecbHumidification < Minitest::Test
  include FixtureHelper

  MZ = 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard'.freeze
  FPFC = 'FPFC MAU Chilled Water Coils with Scroll Chiller'.freeze

  def humidistat!(model, zones, rh = 30.0)
    schedule = OpenStudio::Model::ScheduleRuleset.new(model)
    schedule.setName("Min RH #{rh.round}")
    schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), rh)
    zones.each do |zone|
      stat = OpenStudio::Model::ZoneControlHumidistat.new(model)
      stat.setHumidifyingRelativeHumiditySetpointSchedule(schedule)
      zone.setZoneControlHumidistat(stat)
    end
    schedule
  end

  # Put a humidifier on an air loop, optionally with the control a real humidified
  # proposed carries.
  def humidify!(air_loop, kind: :gas, control: :humidistat, schedule: nil)
    model = air_loop.model
    humidifier = if kind == :gas
                   OpenStudio::Model::HumidifierSteamGas.new(model)
                 else
                   OpenStudio::Model::HumidifierSteamElectric.new(model)
                 end
    humidifier.setName("proposed #{kind} humidifier on #{air_loop.nameString}")
    humidifier.autosizeRatedCapacity
    humidifier.autosizeRatedPower if humidifier.respond_to?(:autosizeRatedPower)
    assert humidifier.addToNode(air_loop.supplyOutletNode), 'proposed humidifier accepted by the SDK'
    node = humidifier.outletModelObject.get.to_Node.get

    case control
    when :humidistat
      manager = OpenStudio::Model::SetpointManagerSingleZoneHumidityMinimum.new(model)
      manager.setControlZone(air_loop.thermalZones.first)
      manager.addToNode(node)
    when :scheduled
      manager = OpenStudio::Model::SetpointManagerScheduled.new(model, schedule)
      manager.setControlVariable('MinimumHumidityRatio')
      manager.addToNode(node)
    end
    humidifier
  end

  def reference(model, types, storeys: 3, vintage: '2020')
    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, vintage: vintage,
      building: { storeys: storeys, zone_types: model.getThermalZones.to_h { |z| [z.nameString, types] } },
      audit: audit
    )
    [result, audit]
  end

  # A 3-storey office proposed (System 6 reference) whose single air loop humidifies.
  def humidified_office(kind: :gas, control: :humidistat)
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, MZ, zones)
    schedule = control == :scheduled ? humidity_schedule(model) : nil
    humidistat!(model, zones) if control == :humidistat
    model.getAirLoopHVACs.each { |l| humidify!(l, kind: kind, control: control, schedule: schedule) }
    model
  end

  def humidity_schedule(model)
    schedule = OpenStudio::Model::ScheduleRuleset.new(model)
    schedule.setName('Proposed Min Humidity Ratio')
    schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.004)
    schedule
  end

  def humidifiers(model)
    model.getHumidifierSteamGass.map { |h| [:gas, h] } + model.getHumidifierSteamElectrics.map { |h| [:electric, h] }
  end

  def d55(audit)
    audit.entries.select { |e| e[:ruling].to_s.include?('D-55') }
  end

  # ---- the rebuild ----

  def test_gas_humidification_is_rebuilt_on_natural_gas
    result, audit = reference(humidified_office(kind: :gas), 'Office - open plan')
    rebuilt = humidifiers(result.model)
    assert_equal 1, rebuilt.size, 'one reference humidifier for the one reference air loop'
    assert_equal :gas, rebuilt.first.first, 'note (1): the reference uses the PROPOSED energy source'
    assert rebuilt.first.last.isRatedCapacityAutosized, 'never hard-sized (L-23)'

    entry = d55(audit).find { |e| e[:action].include?('reference humidification rebuilt') }
    refute_nil entry
    assert_equal :decision, entry[:level], 'the T8 warning became a decision'
    assert_equal 'Table 8.4.4.7.-B Note (1)', entry[:article]
    assert_equal 'NaturalGas', entry[:inputs][:energy_source]
  end

  def test_electric_humidification_is_rebuilt_on_electricity
    result, audit = reference(humidified_office(kind: :electric), 'Office - open plan')
    rebuilt = humidifiers(result.model)
    assert_equal 1, rebuilt.size
    assert_equal :electric, rebuilt.first.first
    entry = d55(audit).find { |e| e[:action].include?('reference humidification rebuilt') }
    assert_equal 'Electricity', entry[:inputs][:energy_source]
  end

  # An uncontrolled humidifier is silently inert — the rebuild is worthless without
  # a setpoint that actually reaches it.
  def test_rebuilt_humidifier_carries_a_working_control
    result, audit = reference(humidified_office(kind: :gas), 'Office - open plan')
    managers = result.model.getSetpointManagerSingleZoneHumidityMinimums
    assert_equal 1, managers.size
    manager = managers.first
    assert manager.controlZone.is_initialized, 'the setpoint manager has a control zone'
    assert manager.controlZone.get.zoneControlHumidistat.is_initialized,
           'the control zone carries the humidistat that survived the teardown'
    assert manager.setpointNode.is_initialized, 'the setpoint manager is on a node'

    humidifier = result.model.getHumidifierSteamGass.first
    assert_equal humidifier.outletModelObject.get.handle.to_s, manager.setpointNode.get.handle.to_s,
                 "the setpoint sits on the humidifier's own outlet node"
    entry = d55(audit).find { |e| e[:action].include?('reference humidification rebuilt') }
    assert_includes entry[:inputs][:control], 'SetpointManagerSingleZoneHumidityMinimum'
  end

  # The proposed's own scheduled minimum-humidity setpoint is the fallback when no
  # zone humidistat exists — control still comes from the proposed, never invented.
  def test_scheduled_setpoint_is_the_fallback_control
    result, audit = reference(humidified_office(kind: :electric, control: :scheduled), 'Office - open plan')
    assert_equal 1, humidifiers(result.model).size
    scheduled = result.model.getSetpointManagerScheduleds.select { |s| s.controlVariable == 'MinimumHumidityRatio' }
    assert_equal 1, scheduled.size, 'the proposed loop control is gone with the loop; the reference has its own'
    assert_equal 'Proposed Min Humidity Ratio', scheduled.first.schedule.nameString,
                 "the rebuilt control uses the PROPOSED's setpoint schedule"
    entry = d55(audit).find { |e| e[:action].include?('reference humidification rebuilt') }
    assert_includes entry[:inputs][:control], 'SetpointManagerScheduled'
  end

  # No humidistat, no scheduled setpoint: the source is known but the CONTROL is not.
  # Building an inert humidifier would misrepresent the reference as humidified.
  def test_undeterminable_control_warns_and_builds_nothing
    result, audit = reference(humidified_office(kind: :gas, control: :none), 'Office - open plan')
    assert_empty humidifiers(result.model), 'no inert humidifier is left behind'
    warning = d55(audit).find { |e| e[:level] == :warning }
    refute_nil warning
    assert_includes warning[:action], 'INERT'
  end

  # ---- the pre-teardown over-count defect ----

  # A residential fan-coil block takes the :copy_proposed rule, so its MAU loop —
  # and the humidifier on it — is never replaced. The old code counted humidifiers
  # BEFORE the teardown and warned "NOT rebuilt" about this one too.
  def test_humidifier_surviving_on_a_copy_proposed_loop_does_not_warn
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, FPFC, zones)
    humidistat!(model, zones)
    model.getAirLoopHVACs.each { |l| humidify!(l, kind: :gas) }

    result, audit = reference(model, 'Multi-unit residential', storeys: 3)
    assert_equal [:copy_proposed], result.assignments.map(&:action).uniq, 'precondition: nothing is replaced'
    assert_equal 1, humidifiers(result.model).size, 'the proposed humidifier survives untouched'
    assert_empty d55(audit).select { |e| e[:level] == :warning },
                 'a surviving humidifier is NOT a "not rebuilt" warning'
    retained = d55(audit).find { |e| e[:action].include?('retained on this reference loop') }
    refute_nil retained
    assert_equal :info, retained[:level]
  end

  # ---- merged systems and vintages ----

  # D-28 merges multizone selection groups onto one reference system. Where the
  # merged blocks disagree on energy source, note (1) can only be satisfied for one.
  def test_mixed_energy_sources_elect_the_majority_and_shout
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, MZ, zones[0..1])
    OpenStudioHVAC.build_system(model, MZ, zones[2..4])
    humidistat!(model, zones)
    loops = model.getAirLoopHVACs.sort_by { |l| l.thermalZones.size }
    humidify!(loops.first, kind: :gas)        # 2 zones
    humidify!(loops.last, kind: :electric)    # 3 zones

    result, audit = reference(model, 'Office - open plan')
    rebuilt = humidifiers(result.model)
    assert_equal 1, rebuilt.size, 'the merged reference system carries one humidifier'
    assert_equal :electric, rebuilt.first.first, 'majority of the merged thermal blocks'
    warning = d55(audit).find { |e| e[:action].include?('DIFFERENT') }
    refute_nil warning, 'the divergence is shouted, not silent'
    assert_equal :warning, warning[:level]
  end

  def test_2025_cites_the_renumbered_table
    _, audit = reference(humidified_office(kind: :gas), 'Office - open plan', vintage: '2025')
    entry = d55(audit).find { |e| e[:action].include?('reference humidification rebuilt') }
    refute_nil entry
    assert_equal 'Table 8.4.5.7.-B Note (1)', entry[:article]
  end

  # ---- the gate that matters: EnergyPlus must actually OPERATE it ----

  def test_rebuilt_humidifier_consumes_its_energy_source_in_energyplus
    skip 'openstudio CLI not available' unless openstudio_cli?

    model = attach_weather!(humidified_office(kind: :gas))
    result, = reference(model, 'Office - open plan')
    Dir.mktmpdir('oshvac-humid-') do |dir|
      run_dir = run_energyplus!(result.model, dir, sizing_only: false)
      assert_clean_energyplus_run(run_dir, 'reference with rebuilt gas humidification')
      gas = humidification_end_use(result.model.sqlFile.get, 'Natural Gas')
      electricity = humidification_end_use(result.model.sqlFile.get, 'Electricity')
      assert_operator gas, :>, 0.0, 'EnergyPlus actually RAN the rebuilt gas humidifier'
      assert_in_delta 0.0, electricity, 1e-9, 'and it burned gas, not electricity'
    end
  end

  def humidification_end_use(sql, column)
    value = sql.execAndReturnFirstDouble(
      "SELECT Value FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' " \
      "AND TableName='End Uses' AND RowName='Humidification' AND ColumnName='#{column}'"
    )
    value.is_initialized ? value.get : nil
  end
end
