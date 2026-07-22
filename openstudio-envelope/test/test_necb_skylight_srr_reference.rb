require_relative 'test_helper'

# P4 gate: the reference-envelope SKYLIGHT/SRR path (8.4.4.3.(3) via 3.2.1.4.(2))
# — HAS NEVER EXECUTED anywhere in this suite before this file. The shared
# 5-zone fixture has no skylights, and test_reference_envelope.rb's
# `proposed_model` helper (despite a now-fixed stale comment claiming
# otherwise) never created one either, so `scale_fenestration_to_limits`'s
# roof-scaling branch in necb/reference.rb had zero test coverage.
#
# Method mirrors test_fdwr_scaled_proportionally_not_rebuilt: build a hostile
# proposed SRR, run the reference transform, assert MODEL VALUES (skylight
# area/SRR), never audit text.
class TestNECBSkylightSRRReference < Minitest::Test
  include FixtureHelper

  HDD = 3890
  SRR_LIMIT = 0.02 # 3.2.1.4.(2): total skylight area < 2% of gross roof area

  # Add one skylight per exposed conditioned roof at the given SRR, via the
  # SAME centroid-scaled-subsurface geometry the PRESCRIPTIVE path uses
  # (Geometry.apply_srr). This is a FIXTURE BUILDER call, not the code under
  # test: the reference transform under test (scale_fenestration_to_limits)
  # shrinks EXISTING subsurfaces via Geometry.scale_subsurfaces — it never
  # calls apply_srr, which only the prescriptive path uses to ADD skylights.
  def model_with_skylights(srr:)
    model = load_fixture
    glazing = OpenStudio::Model::SimpleGlazing.new(model)
    glazing.setUFactor(3.0)
    glazing.setSolarHeatGainCoefficient(0.5)
    glazing.setVisibleTransmittance(0.6)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setName('Proposed Skylight Construction')
    construction.setLayers([glazing])
    ok = OpenStudioEnvelope::Geometry.apply_srr(model, srr, construction)
    raise('fixture builder failed to add skylights') unless ok

    model
  end

  def reference(model)
    audit = OpenStudioEnvelope::AuditLog.new
    OpenStudioEnvelope::NECB.reference_envelope(model, vintage: '2020', hdd: HDD, audit: audit)
    audit
  end

  # Positive control + the reproduction in one call: the proposed model
  # actually HAS a skylight (unlike every other fixture in this repo), its SRR
  # is 5x the 2% cap, and the reference transform's roof-scaling branch fires
  # for the first time in any test.
  def test_reference_shrinks_hostile_skylight_to_the_srr_limit
    model = model_with_skylights(srr: 0.10)
    before_roofs = OpenStudioEnvelope::Geometry.exposed_roofs(model)
    before_sub_area = before_roofs[:subsurface_area_m2]
    before_walls = OpenStudioEnvelope::Geometry.exposed_walls(model)
    before_window_area = before_walls[:subsurface_area_m2]
    before_window_count = model.getSubSurfaces.count { |s| s.subSurfaceType != 'Skylight' }
    assert_operator before_roofs[:srr], :>, SRR_LIMIT, 'fixture precondition: proposed SRR exceeds the limit'

    reference(model)

    after_roofs = OpenStudioEnvelope::Geometry.exposed_roofs(model)
    ratio = SRR_LIMIT / before_roofs[:srr]
    assert_in_delta before_sub_area * ratio, after_roofs[:subsurface_area_m2], 1e-3,
                    'skylight area must shrink by exactly limit/proposed_srr (8.4.4.3.(3))'
    assert_in_delta SRR_LIMIT, after_roofs[:srr], 1e-4, 'resulting SRR must land at the 2% cap'
    assert_operator after_roofs[:srr], :<=, SRR_LIMIT + 1e-6

    after_walls = OpenStudioEnvelope::Geometry.exposed_walls(model)
    assert_in_delta before_window_area, after_walls[:subsurface_area_m2], 1e-6,
                    'wall windows must be untouched by the roof-only SRR scaling'
    assert_equal before_window_count, model.getSubSurfaces.count { |s| s.subSurfaceType != 'Skylight' },
                 'wall window count untouched'
  end

  # Negative case: SRR already within the limit -> the roof-scaling branch must
  # not fire at all (reference.rb: `return unless roofs[:srr] && roofs[:srr] >
  # srr_limit`) — skylight geometry byte-identical, not merely "close".
  def test_reference_leaves_compliant_skylight_byte_identical
    model = model_with_skylights(srr: 0.01) # half the cap
    before = model.getSurfaces.select { |s| s.surfaceType == 'RoofCeiling' }
                  .to_h { |r| [r.nameString, r.subSurfaces.map(&:grossArea)] }
    assert(before.values.flatten.any? { |a| a > 0 }, 'fixture precondition: skylights actually present')

    reference(model)

    after = model.getSurfaces.select { |s| s.surfaceType == 'RoofCeiling' }
                 .to_h { |r| [r.nameString, r.subSurfaces.map(&:grossArea)] }
    assert_equal before, after, 'SRR under the limit: skylight areas must be byte-identical, not scaled'
  end
end
