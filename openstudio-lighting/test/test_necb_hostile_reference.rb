require_relative 'test_helper'

# Hostile-outcome gate for the reference LIGHTING transform (NECB 8.4.4.5.(1)).
#
# Method: give the PROPOSED a deliberately non-compliant lighting power, build
# the reference, then assert the reference carries the Part 4 ALLOWANCE rather
# than the hostile proposed value.
#
# Why outcomes and not audit strings: the reference is a CLONE of the proposed,
# so a transform that silently no-ops leaves reference LPD == proposed LPD —
# i.e. the allowance is waived and the proposed is compared against itself. The
# audit meanwhile records a confident "interior lighting applied" decision. Any
# test that asserts on the audit passes while the model is wrong, which is
# exactly how this class of defect survived. Assert model values only.
#
# Expected values are recomputed from the catalog in-test rather than
# hardcoded, so the assertions follow the data if it is revised.
class TestNECBHostileReferenceLighting < Minitest::Test
  include FixtureHelper

  HOSTILE_W_PER_M2 = 99.0
  KNOWN_SPACE_TYPE = 'Office enclosed > 25 m2'.freeze
  # Deliberately absent from the 308-row catalog. Note the real rows are
  # 'Office enclosed <= 25 m2' and 'Office enclosed > 25 m2' — this hyphenated
  # form is the shape of name a foreign or older model actually carries.
  UNKNOWN_SPACE_TYPE = 'Office - enclosed'.freeze

  def catalog_lpd_w_per_m2(space_type)
    record = OpenStudioLoads::NECB::SpaceTypes.find(building_type: 'Space Function',
                                                    space_type: space_type, vintage: '2020')
    refute_nil record, "fixture precondition: '#{space_type}' must exist in the catalog"
    OpenStudio.convert(record['lighting_per_area'].to_f, 'W/ft^2', 'W/m^2').get
  end

  # Stand in for an over-lit proposed design.
  def hostile_lights!(space_type)
    definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
    definition.setName("#{space_type.nameString} HOSTILE Lights Definition")
    definition.setWattsperSpaceFloorArea(HOSTILE_W_PER_M2)
    lights = OpenStudio::Model::Lights.new(definition)
    lights.setName("#{space_type.nameString} HOSTILE Lights")
    lights.setSpaceType(space_type)
    space_type
  end

  def lpd_of(space_type)
    instance = space_type.lights.first
    return nil if instance.nil?

    watts = instance.lightsDefinition.wattsperSpaceFloorArea
    watts.is_initialized ? watts.get : nil
  end

  # Positive control: for a catalog-resolvable space type the transform must
  # overwrite the hostile value with the allowance. If this fails, the harness
  # itself is broken and the negative case below proves nothing.
  def test_reference_lighting_overwrites_hostile_lpd_for_known_space_type
    model = OpenStudio::Model::Model.new
    space_type = hostile_lights!(tagged_space_type(model, 'Space Function', KNOWN_SPACE_TYPE))

    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020',
                                                audit: OpenStudioLighting::AuditLog.new)

    assert_in_delta catalog_lpd_w_per_m2(KNOWN_SPACE_TYPE), lpd_of(space_type), 1e-6,
                    '8.4.4.5.(1): reference LPD must be the Part 4 allowance, not the proposed value'
    refute_in_delta HOSTILE_W_PER_M2, lpd_of(space_type), 1e-6,
                    'reference retained the hostile proposed LPD'
  end

  # DEFECT #1 — reproduction.
  #
  # apply_lights.rb:47 returns false when the space type has no catalog record,
  # without touching the model and without an audit warning. Because the
  # reference is a clone, it keeps the proposed's LPD verbatim: an arbitrarily
  # over-lit space incurs ZERO lighting penalty and the building is more likely
  # to be judged compliant.
  #
  # EXPECTED TO FAIL until the miss is handled (raise, or reset to a defensible
  # allowance). Passing quietly means the allowance is being waived.
  def test_reference_lighting_does_not_silently_keep_hostile_lpd_for_unknown_space_type
    model = OpenStudio::Model::Model.new
    space_type = hostile_lights!(tagged_space_type(model, 'Space Function', UNKNOWN_SPACE_TYPE))

    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

    refute_in_delta HOSTILE_W_PER_M2, lpd_of(space_type), 1e-6,
                    "8.4.4.5.(1) WAIVED: space type '#{UNKNOWN_SPACE_TYPE}' has no catalog record, so the " \
                    'reference kept the proposed LPD (99 W/m2) verbatim. Reference == proposed means the ' \
                    'lighting allowance is not enforced for this space and the proposed is compared ' \
                    'against itself. See apply_lights.rb:47.'
  end

  # Independent of how the miss is ultimately resolved, it must not be SILENT —
  # the family contract is that warnings are never silent. Separate from the
  # assertion above so the log gap is visible even while the model gap stands.
  def test_unmatched_space_type_is_reported
    model = OpenStudio::Model::Model.new
    hostile_lights!(tagged_space_type(model, 'Space Function', UNKNOWN_SPACE_TYPE))

    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

    assert(audit.warnings.any? { |w| w[:action].to_s.include?(UNKNOWN_SPACE_TYPE) },
           "no audit warning names the unmatched space type '#{UNKNOWN_SPACE_TYPE}'; the reference " \
           'lighting reset was skipped with no record that anything was missed')
  end

  # Plenums are skipped BY DESIGN (apply_lights.rb:39-40). Pinned so that
  # whatever fix lands for the miss above does not turn a deliberate exemption
  # into a false failure.
  def test_plenum_exemption_is_preserved
    model = OpenStudio::Model::Model.new
    plenum = hostile_lights!(tagged_space_type(model, 'Space Function', 'Office enclosed <= 25 m2'))
    plenum.setName('Zone 1 Plenum')

    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020',
                                                audit: OpenStudioLighting::AuditLog.new)

    assert_in_delta HOSTILE_W_PER_M2, lpd_of(plenum), 1e-6,
                    'plenums are exempt by design and must be left untouched'
  end
end
