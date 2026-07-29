require_relative 'test_helper'

# P3 gate: the 4.2.3.1 exterior allowance calculator (greenfield) and the
# 8.4.4.5 reference-lighting transform.
class TestExteriorAndReference < Minitest::Test
  include FixtureHelper

  def test_exterior_allowance_zone3
    audit = OpenStudioLighting::AuditLog.new
    result = OpenStudioLighting::NECB::Exterior.allowance(
      zone: 3,
      quantities: { 'parking_and_drives_m2' => 1000, 'walkways_narrow_m' => 50,
                    'entrances_exits_m' => 10, 'drive_up_windows' => 2 },
      audit: audit)

    assert_equal 500.0, result['basic_site_w'], 'Table -B zone 3'
    # tradable: 1000x0.65 + 50x2.0 + 10x69 = 650 + 100 + 690 = 1440
    assert_in_delta 1440.0, result['tradable_w'], 0.1
    # non-tradable: 2 x 200 W drive-throughs
    assert_in_delta 400.0, result['non_tradable_w'], 0.1
    assert_in_delta 2340.0, result['total_w'], 0.1
    assert_equal 4, result['lines'].size
    decision = audit.entries.find { |e| e[:article] == '4.2.3.1.' && e[:level] == :decision }
    refute_nil decision
  end

  def test_exterior_zone0_and_unknown_keys_warn
    audit = OpenStudioLighting::AuditLog.new
    result = OpenStudioLighting::NECB::Exterior.allowance(
      zone: 0, quantities: { 'parking_and_drives_m2' => 1000, 'bogus_key' => 5 }, audit: audit)
    assert_equal 0.0, result['total_w'], 'zone 0: no allowances anywhere'
    assert(audit.warnings.any? { |w| w[:action].include?("'bogus_key'") })
    assert(audit.warnings.any? { |w| w[:action].include?('no allowance') && w[:action].include?('zone 0') })
    assert_raises(ArgumentError) { OpenStudioLighting::NECB::Exterior.allowance(zone: 9, quantities: {}) }
  end

  def test_apply_exterior_lights
    model = OpenStudio::Model::Model.new
    audit = OpenStudioLighting::AuditLog.new
    lights = OpenStudioLighting::NECB::Exterior.apply_exterior_lights(model, 2340.0, audit: audit)
    assert_in_delta 2340.0, lights.exteriorLightsDefinition.designLevel, 1e-6
    assert_equal 'AstronomicalClock', lights.controlOption
  end

  def test_reference_lighting_dwelling_rule_and_coverage
    model = OpenStudio::Model::Model.new
    tagged_space_type(model, 'Space Function', 'Office enclosed > 25 m2')
    dwelling = tagged_space_type(model, 'Space Function', 'Dwelling units general')

    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

    lights = dwelling.lights.first
    refute_nil lights, 'dwelling space type has lights'
    assert_in_delta 5.0, lights.lightsDefinition.wattsperSpaceFloorArea.get, 1e-6,
                    '8.4.4.5.(2): dwelling units at 5 W/m2'

    %w[8.4.4.5.(1) 8.4.4.5.(2)].each do |article|
      assert(audit.entries.any? { |e| e[:article].to_s.include?(article) }, article)
    end
    assert(audit.warnings.any? { |w| w[:step] == :lighting_reference && w[:article].to_s.include?('8.4.4.5.(5)-(12)') },
           'daylighting gaps are loud when reference_daylighting did NOT run (the default)')
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.5.(3)') && e[:action].include?('schedule modulation') })
  end

  # The (5)-(12) warning is CONDITIONAL: reference_daylighting.rb models and
  # audits those sentences itself, so when the caller runs it (the umbrella's
  # default since D-51) this transform must not claim they are unmodeled.
  def test_reference_lighting_daylighting_kwarg_silences_the_gap_warning
    model = OpenStudio::Model::Model.new
    tagged_space_type(model, 'Space Function', 'Office enclosed > 25 m2')

    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', daylighting: true, audit: audit)

    refute(audit.warnings.any? { |w| w[:step] == :lighting_reference && w[:article].to_s.include?('8.4.4.5.(5)-(12)') },
           'daylighting: true — (5)-(12) is modeled elsewhere, so no "NOT modeled" warning here')
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.5.(1)') },
           'the rest of the reference lighting transform is unchanged')
  end

  def test_reference_2025_prefix
    model = OpenStudio::Model::Model.new
    tagged_space_type(model, 'Space Function', 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2025', audit: audit)
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.5.5.(1)') }, '2025 renumbered citations')
  end

  # The shared umbrella fixture (5ZoneNoHVAC) has ASHRAE-named, NECB-untagged
  # space types used by real floor-area spaces. reference_lighting must REFUSE
  # it: an unresolvable space type would silently keep the proposed's LPD in
  # the reference (the clone), waiving the 8.4.4.5.(1) allowance. This test
  # previously asserted warn-and-skip ("never raise") — that WAS the defect.
  def test_reference_lighting_refuses_untagged_fixture
    model = load_fixture
    audit = OpenStudioLighting::AuditLog.new
    error = assert_raises(ArgumentError) do
      OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)
    end
    assert_includes error.message, 'SmallOffice', 'refusal names the unresolvable space type'
    assert(audit.warnings.any? { |w| w[:action].to_s.include?('UNRESOLVABLE') },
           'refusal also lands in the audit trail')
  end

  # Tagged with real catalog names, the same fixture passes the gate, warns on
  # the modelled-gap articles, and emits exactly ONE set of article-coverage
  # entries per call.
  def test_reference_lighting_tagged_fixture_single_coverage
    model = load_fixture
    model.getSpaceTypes.select { |st| st.spaces.any? }.each do |st|
      st.setStandardsBuildingType('Space Function')
      st.setStandardsSpaceType('Office enclosed > 25 m2')
    end
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

    assert(audit.warnings.any? { |w| w[:step] == :lighting_reference && w[:article].to_s.include?('8.4.4.5.(5)-(12)') },
           'daylighting gaps still warn loudly on a run without reference_daylighting')

    coverage = audit.entries.select { |e| e[:step] == :coverage }
    refute_empty coverage, 'lighting article coverage emitted'
    articles = coverage.map { |e| e[:article] }
    assert_equal articles.size, articles.uniq.size,
                 'exactly one coverage entry per article (no duplicate emission)'
  end
end
