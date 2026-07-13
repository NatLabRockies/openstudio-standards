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
    assert(audit.warnings.any? { |w| w[:article].to_s.include?('8.4.4.5.(5)-(12)') },
           'daylighting gaps are loud')
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.5.(3)') && e[:action].include?('schedule modulation') })
  end

  def test_reference_2025_prefix
    model = OpenStudio::Model::Model.new
    tagged_space_type(model, 'Space Function', 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2025', audit: audit)
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.5.5.(1)') }, '2025 renumbered citations')
  end

  # The shared umbrella fixture (5ZoneNoHVAC) has ASHRAE-named, NECB-untagged
  # space types. reference_lighting must warn-and-skip loudly on it (never raise),
  # and emit exactly ONE set of article-coverage entries per call.
  def test_reference_lighting_untagged_warns_and_single_coverage
    model = load_fixture
    audit = OpenStudioLighting::AuditLog.new
    # reaching past this call at all proves it did not raise on the untagged model
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

    assert(audit.warnings.any? { |w| w[:article].to_s.include?('8.4.4.5.(5)-(12)') },
           'untagged model still warns loudly (daylighting gaps)')

    coverage = audit.entries.select { |e| e[:step] == :coverage }
    refute_empty coverage, 'lighting article coverage emitted on the untagged path'
    articles = coverage.map { |e| e[:article] }
    assert_equal articles.size, articles.uniq.size,
                 'exactly one coverage entry per article (no duplicate emission)'
  end
end
