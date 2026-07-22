require_relative 'test_helper'

# Hostile-outcome gate for the reference ENVELOPE air-leakage transform
# (NECB 8.4.4.3.(6) via 8.4.3.3.(3) + 8.4.2.9.(2)).
#
# Method: give the PROPOSED deliberately non-compliant infiltration, build the
# reference, then assert the reference carries the NECB default and ONLY the
# NECB default.
#
# The subtlety this guards: OpenStudio models infiltration with three unrelated
# object types — SpaceInfiltrationDesignFlowRate, ...EffectiveLeakageArea, and
# ...FlowCoefficient. A transform that clears one and adds its own leaves the
# others in place, so the space ends up with the NECB default PLUS whatever the
# proposed had. Object counts, not just the flow value, are the assertion that
# catches it.
class TestNECBHostileReferenceEnvelope < Minitest::Test
  include FixtureHelper

  HDD = 3890 # Toronto Pearson
  HOSTILE_FLOW_PER_AREA = 0.05 # m3/s.m2 — ~50x the NECB default
  HOSTILE_ELA_CM2 = 5000.0

  def build_reference(model)
    OpenStudioEnvelope::NECB.reference_envelope(model, vintage: '2020', hdd: HDD,
                                                audit: OpenStudioEnvelope::AuditLog.new)
    model
  end

  def hostile_design_flow_rate!(space)
    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space.model)
    infiltration.setName("#{space.nameString} HOSTILE DesignFlowRate")
    infiltration.setFlowperExteriorWallArea(HOSTILE_FLOW_PER_AREA)
    infiltration.setSpace(space)
    infiltration
  end

  def hostile_effective_leakage_area!(space)
    ela = OpenStudio::Model::SpaceInfiltrationEffectiveLeakageArea.new(space.model)
    ela.setName("#{space.nameString} HOSTILE EffectiveLeakageArea")
    ela.setEffectiveAirLeakageArea(HOSTILE_ELA_CM2)
    ela.setSpace(space)
    ela
  end

  # Positive control: the transform demonstrably fires and replaces a hostile
  # DesignFlowRate. If this fails the harness is broken and the negative case
  # below proves nothing.
  def test_reference_replaces_hostile_design_flow_rate
    model = load_fixture
    model.getSpaces.each { |space| hostile_design_flow_rate!(space) }
    build_reference(model)

    rates = model.getSpaceInfiltrationDesignFlowRates
    refute_empty rates, 'reference must define infiltration'
    assert(rates.none? { |r| r.nameString.include?('HOSTILE') },
           'the proposed infiltration objects must be replaced, not kept')

    rates.each do |rate|
      flow = rate.flowperExteriorWallArea
      next unless flow.is_initialized

      refute_in_delta HOSTILE_FLOW_PER_AREA, flow.get, 1e-9,
                      'reference retained the hostile proposed infiltration rate'
    end
  end

  # DEFECT #3 — reproduction.
  #
  # apply_air_leakage_default (reference.rb:187) removes only
  # getSpaceInfiltrationDesignFlowRates. A proposed model expressing
  # infiltration as EffectiveLeakageArea keeps that object AND gains the NECB
  # default, so the reference building leaks roughly twice — inflating
  # reference energy and making the proposed easier to pass.
  #
  # EXPECTED TO FAIL until the transform clears every infiltration
  # representation.
  def test_reference_does_not_double_count_effective_leakage_area
    model = load_fixture
    model.getSpaces.each { |space| hostile_effective_leakage_area!(space) }
    survivors_before = model.getSpaceInfiltrationEffectiveLeakageAreas.size
    assert_operator survivors_before, :>, 0, 'precondition: the proposed has ELA infiltration'

    build_reference(model)

    assert_empty model.getSpaceInfiltrationEffectiveLeakageAreas,
                 'DOUBLE-COUNTED INFILTRATION: the reference kept the proposed ' \
                 "SpaceInfiltrationEffectiveLeakageArea object(s) (#{survivors_before} of them) AND added " \
                 'the NECB default DesignFlowRate on top. The reference building therefore leaks about ' \
                 'twice, which inflates reference energy and makes the proposed easier to pass. ' \
                 'See reference.rb:187 — it removes only getSpaceInfiltrationDesignFlowRates.'
  end

  # Same defect, other representation. Kept separate so a partial fix that
  # handles only ELA still reports the remaining hole.
  def test_reference_does_not_double_count_flow_coefficient
    model = load_fixture
    model.getSpaces.each do |space|
      coefficient = OpenStudio::Model::SpaceInfiltrationFlowCoefficient.new(space.model)
      coefficient.setName("#{space.nameString} HOSTILE FlowCoefficient")
      coefficient.setFlowCoefficient(0.1)
      coefficient.setSpace(space)
    end

    build_reference(model)

    assert_empty model.getSpaceInfiltrationFlowCoefficients,
                 'DOUBLE-COUNTED INFILTRATION: the reference kept the proposed ' \
                 'SpaceInfiltrationFlowCoefficient object(s) and added the NECB default on top.'
  end

  # Pin the formula itself so a fix to the object-clearing above cannot quietly
  # change the resulting rate. I_AGW = (5/75)^0.6 x I75 x S / A_AGW.
  def test_reference_infiltration_matches_the_i_agw_formula
    model = load_fixture
    build_reference(model)

    envelope_area = 0.0
    wall_area = 0.0
    model.getSurfaces.each do |surface|
      boundary = OpenStudioEnvelope::NECB::Prescriptive.boundary_of(surface)
      next if boundary.nil?

      envelope_area += surface.grossArea
      wall_area += surface.grossArea if surface.surfaceType == 'Wall' && boundary == 'outdoors'
    end
    expected = ((5.0 / 75.0)**0.60) * 1.50 * envelope_area / wall_area / 1000.0

    rates = model.getSpaceInfiltrationDesignFlowRates
    refute_empty rates
    rates.each do |rate|
      assert rate.flowperExteriorWallArea.is_initialized,
             'reference infiltration must be set as flow per exterior wall area'
      assert_in_delta expected, rate.flowperExteriorWallArea.get, 1e-9,
                      '8.4.2.9.(2): I_AGW = (5/75)^0.6 x 1.50 x S / A_AGW'
    end
  end
end
