require_relative 'test_helper'

# 8.4.4.14 (2025: 8.4.5.14) hydronic pump rules, applied by the efficiency
# pass: Table 8.4.4.14. riding-curve coefficients + the below-D minimum-flow
# clamp on every variable-speed pump (sentences (4)-(5)), and the (1)-(3)
# combined W/(L/s) power transfer from a sized proposed model. All hostile
# outcomes assert MODEL VALUES; unknowns must warn, never stay silent.
class TestNecbPumpRules < Minitest::Test
  RIDING = { a: 0.227143, b: 1.178929, c: -0.41071, d: 0.47, e: 0.68 }.freeze

  def loop_with_vsd_pump(model, type:, flow: nil, power: nil)
    loop_ = OpenStudio::Model::PlantLoop.new(model)
    loop_.sizingPlant.setLoopType(type)
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setRatedFlowRate(flow) if flow
    pump.setRatedPowerConsumption(power) if power
    pump.addToNode(loop_.supplyInletNode)
    [loop_, pump]
  end

  def test_riding_curve_coefficients_and_floor_applied
    # the below-D floor approximation the code comment claims must actually hold
    poly_at_d = RIDING[:a] + RIDING[:b] * RIDING[:d] + RIDING[:c] * RIDING[:d]**2
    assert_in_delta RIDING[:e], poly_at_d, 0.02, 'polynomial at D equals E within table rounding'

    model = OpenStudio::Model::Model.new
    _, pump = loop_with_vsd_pump(model, type: 'Cooling', flow: 0.02)
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020', audit: audit)

    assert_in_delta RIDING[:a], pump.coefficient1ofthePartLoadPerformanceCurve, 1e-6
    assert_in_delta RIDING[:b], pump.coefficient2ofthePartLoadPerformanceCurve, 1e-6
    assert_in_delta RIDING[:c], pump.coefficient3ofthePartLoadPerformanceCurve, 1e-6
    assert_in_delta 0.0, pump.coefficient4ofthePartLoadPerformanceCurve, 1e-9
    assert_in_delta RIDING[:d] * 0.02, pump.minimumFlowRate, 1e-9, 'below-D floor via min-flow clamp'
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.14.(4)-(5)') })
    assert(audit.entries.any? { |e| e[:level] == :info && e[:action].include?('no proposed model supplied') },
           'transfer skip is noted, never silent')
  end

  def test_power_transfer_uses_combined_w_per_l_s_by_loop_type
    proposed = OpenStudio::Model::Model.new
    loop_with_vsd_pump(proposed, type: 'Heating', flow: 0.010, power: 800.0)
    loop_with_vsd_pump(proposed, type: 'Heating', flow: 0.005, power: 700.0) # combined: 1500 W / 15 L/s

    reference = OpenStudio::Model::Model.new
    _, ref_pump = loop_with_vsd_pump(reference, type: 'Heating', flow: 0.020) # 20 L/s
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: '2020', audit: audit, proposed: proposed)

    assert_in_delta 2000.0, ref_pump.ratedPowerConsumption.get, 0.1,
                    'combined proposed intensity (100 W per L/s) x reference flow (20 L/s)'
    decision = audit.entries.find { |e| e[:article] == '8.4.4.14.(1)-(3)' }
    refute_nil decision, 'transfer decision audited'
    assert_equal 2, decision[:inputs][:proposed_pumps], 'sentence (2): both pumps combined'
    assert_in_delta 100.0, decision[:inputs][:proposed_w_per_l_s], 0.01
  end

  def test_constant_speed_reference_pump_gets_transfer_but_no_curve
    proposed = OpenStudio::Model::Model.new
    loop_with_vsd_pump(proposed, type: 'Condenser', flow: 0.010, power: 1200.0) # 120 W/(L/s)

    reference = OpenStudio::Model::Model.new
    loop_ = OpenStudio::Model::PlantLoop.new(reference)
    loop_.sizingPlant.setLoopType('Condenser')
    pump = OpenStudio::Model::PumpConstantSpeed.new(reference)
    pump.setRatedFlowRate(0.005)
    pump.addToNode(loop_.supplyInletNode)
    OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: '2020', audit: OpenStudioHVAC::AuditLog.new,
                                            proposed: proposed)
    assert_in_delta 600.0, pump.ratedPowerConsumption.get, 0.1, '120 W/(L/s) x 5 L/s'
  end

  def test_undeterminable_proposed_pumps_warn_never_silent
    proposed = OpenStudio::Model::Model.new
    loop_with_vsd_pump(proposed, type: 'Heating') # autosized, no sql -> nothing readable

    reference = OpenStudio::Model::Model.new
    _, ref_pump = loop_with_vsd_pump(reference, type: 'Heating', flow: 0.02)
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: '2020', audit: audit, proposed: proposed)

    assert(audit.warnings.any? { |w| w[:action].include?('NOT transferred') },
           'undeterminable proposed pumps warn loudly')
    assert ref_pump.ratedPowerConsumption.empty?, 'no transfer happened — autosizing retained'
    assert_in_delta RIDING[:a], ref_pump.coefficient1ofthePartLoadPerformanceCurve, 1e-6,
                    'Table curves still applied'
  end

  def test_missing_loop_type_correspondence_warns
    proposed = OpenStudio::Model::Model.new
    loop_with_vsd_pump(proposed, type: 'Heating', flow: 0.010, power: 800.0)

    reference = OpenStudio::Model::Model.new
    loop_with_vsd_pump(reference, type: 'Cooling', flow: 0.02) # no Cooling pumps in proposed
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: '2020', audit: audit, proposed: proposed)

    assert(audit.warnings.any? { |w| w[:action].include?('NO Cooling-type loop pumps') },
           'missing loop-type correspondence warns')
  end

  def test_2025_citations_renumbered
    model = OpenStudio::Model::Model.new
    loop_with_vsd_pump(model, type: 'Heating', flow: 0.01)
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2025', audit: audit)
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.5.14.(4)-(5)') },
           '2025 cites the renumbered article')
  end
end

# D-14 (8.4.3.2.(1)): reference air systems inherit the PROPOSED operating
# schedule; zones with no proposed air system keep the builder default.
class TestNecbOperatingSchedules < Minitest::Test
  include FixtureHelper

  def test_reference_inherits_proposed_availability_schedule
    proposed = load_fixture
    zones = proposed.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(proposed, 'PSZ RTU with exhaust Gas and DX Coils and Hot Water Baseboard', zones)
    sched = OpenStudio::Model::ScheduleRuleset.new(proposed)
    sched.setName('Office Operation 6-18')
    sched.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 6), 0.0)
    sched.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 18), 1.0)
    sched.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24), 0.0)
    proposed.getAirLoopHVACs.each { |l| l.setAvailabilitySchedule(sched) }

    result = OpenStudioHVAC::NECB.reference_hvac(
      proposed, vintage: '2020',
      building: { storeys: 1, zone_types: proposed.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] } })
    ref_loops = result.model.getAirLoopHVACs
    refute_empty ref_loops
    ref_loops.each { |l| assert_equal 'Office Operation 6-18', l.availabilitySchedule.nameString }
    assert(result.audit.entries.any? { |e| e[:article] == '8.4.3.2.(1)' && e[:level] == :decision })
    # the 5.2.10.1 classification now sees the inherited schedule
    hours = OpenStudioHVAC::NECB.annual_availability_hours(ref_loops.first)
    assert_operator hours, :<, 8000, 'inherited 12h schedule classifies non-continuous'
  end

  def test_no_proposed_air_system_keeps_default_with_note
    proposed = load_fixture
    zones = proposed.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(proposed, 'Baseboard gas boiler', zones) # no air loops
    result = OpenStudioHVAC::NECB.reference_hvac(
      proposed, vintage: '2020',
      building: { storeys: 1, zone_types: proposed.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] } })
    assert(result.audit.entries.any? { |e| e[:article] == '8.4.3.2.(1)' && e[:action].include?('default retained') })
  end
end
