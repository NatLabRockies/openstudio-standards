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

  # A space type only matters if a floor-area space uses it — attach one so the
  # gate treats the type as consequential.
  def with_space(space_type)
    space = OpenStudio::Model::Space.new(space_type.model)
    space.setSpaceType(space_type)
    space_type
  end

  # DEFECT #1 — fixed: the reference transform now REFUSES, loudly.
  #
  # apply_lights silently skips space types with no catalog record, and the
  # reference is a clone — so before the fix, an unmatched type kept the
  # proposed's LPD verbatim: the 8.4.4.5.(1) allowance was waived and an
  # over-lit space incurred zero penalty. The allowance for an unlisted space
  # function is a human judgement (4.2.1.6.(1)(b)), so no fallback value is
  # invented: reference_lighting raises before a wrong reference can exist,
  # naming the type. (The umbrella pre-flight fails even earlier, with
  # suggestions — this guards direct gem callers.)
  def test_reference_lighting_refuses_unknown_space_type_instead_of_keeping_hostile_lpd
    model = OpenStudio::Model::Model.new
    space_type = with_space(hostile_lights!(tagged_space_type(model, 'Space Function', UNKNOWN_SPACE_TYPE)))

    audit = OpenStudioLighting::AuditLog.new
    error = assert_raises(ArgumentError) do
      OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)
    end

    assert_includes error.message, UNKNOWN_SPACE_TYPE, 'the refusal must name the unresolvable space type'
    assert_includes error.message, '8.4.4.5.(1)', 'the refusal must cite the waived allowance article'
    assert_in_delta HOSTILE_W_PER_M2, lpd_of(space_type), 1e-6,
                    'the model must be left untouched on refusal — no partial transform'
    assert(audit.warnings.any? { |w| w[:action].to_s.include?(UNKNOWN_SPACE_TYPE) && w[:action].to_s.include?('UNRESOLVABLE') },
           'the refusal must also land in the audit trail (warnings are never silent)')
  end

  # An unmatched space type NO floor-area space uses is inconsequential — the
  # gate must not refuse over the fixture's orphan space types.
  def test_unused_unknown_space_type_does_not_block_reference_lighting
    model = OpenStudio::Model::Model.new
    with_space(tagged_space_type(model, 'Space Function', KNOWN_SPACE_TYPE))
    tagged_space_type(model, 'Space Function', UNKNOWN_SPACE_TYPE) # orphan: no spaces

    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit) # must not raise

    assert(audit.warnings.none? { |w| w[:action].to_s.include?('UNRESOLVABLE') },
           'orphan space types must not generate unresolvable warnings')
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
