require_relative 'test_helper'

# P4 gate: the `:through_the_wall` selection result — HAS NEVER been exercised
# through the BUILD step. test_necb_selector.rb's
# test_residential_otherwise_through_the_wall proves `select_reference_systems`
# RETURNS an Assignment with action: :through_the_wall using synthetic facts,
# but reference_hvac's build loop (necb/reference.rb, around line 230) has no
# dispatch on `assignment.action` at all except `:copy_proposed` (which
# `next`s past the build). Every other action — :build AND :through_the_wall —
# falls into the exact same
#   zones = assignment.zones.map { |n| zones_by_name.fetch(n) }
#   result = OpenStudioHVAC.replace_system(reference, assignment.catalog_name, zones, ...)
# path. residential_assignment (reference.rb ~130) sets reference_system: 1 for
# BOTH the "heated only" (:build) and "otherwise" (:through_the_wall)
# sentences, so the fall-through this test proves is: :through_the_wall
# results in the IDENTICAL System 1 catalog build ("PSZ MAU ... with PTAC") as
# the heated-only branch — the action label carries no distinct topology.
#
# This test asserts the resulting loop/equipment SHAPE (model values), and is
# NOT a fix: System 1 already models per-zone PTAC (a through-the-wall
# packaged terminal unit) plus a central MAU for ventilation air, which is a
# defensible reading of "through-the-wall systems" — see the report for the
# full evaluation of whether this is a FINDING.
class TestNecbThroughTheWallBuild < Minitest::Test
  include FixtureHelper

  # A central multi-zone VAV-with-reheat proposed system (family 'vav_reheat')
  # is NOT in residential_compatible_cooling?'s allowlist (psz, mau_ptac,
  # zone_terminal, fan_coils, wshp, vrf) and is not a heat pump, so a
  # heated+cooled 'Multi-unit residential' group must fall to the "otherwise"
  # sentence: action :through_the_wall.
  def build_incompatible_cooling_residential_model
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard', zones)
    types = model.getThermalZones.to_h { |z| [z.nameString, 'Multi-unit residential'] }
    [model, types]
  end

  def test_through_the_wall_action_falls_through_to_system_1_ptac_plus_mau
    model, types = build_incompatible_cooling_residential_model

    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020',
                                                 building: { storeys: 1, zone_types: types }, audit: audit)

    assert_equal [:through_the_wall], result.assignments.map(&:action).uniq,
                 'fixture precondition: heated+cooled residential with an incompatible cooling family ' \
                 'must select the "otherwise" sentence'
    assert_equal [1], result.assignments.map(&:reference_system).uniq
    assert_equal ['PSZ MAU Hot Water and DX Coils and Hot Water Baseboard with PTAC'],
                 result.assignments.map(&:catalog_name).uniq,
                 ':through_the_wall and heated-only :build share the identical System 1 catalog definition ' \
                 '(reference.rb residential_assignment sets reference_system: 1 for both sentences)'

    # Resulting model SHAPE: one central MAU air loop (ventilation only) + one
    # PTAC per zone (the through-the-wall unit) + hydronic baseboards, and NO
    # central chiller (the proposed's central VAV/chiller plant is gone — the
    # reference is entirely rebuilt, not merged with the proposed).
    zone_count = result.model.getThermalZones.size
    assert_equal 1, result.model.getAirLoopHVACs.size, 'System 1 = one central MAU for ventilation air'
    assert_equal 'PSZ MAU Hot Water and DX Coils and Hot Water Baseboard with PTAC',
                 result.model.getAirLoopHVACs.first.nameString
    assert_equal zone_count, result.model.getZoneHVACPackagedTerminalAirConditioners.size,
                 'one through-the-wall PTAC per zone'
    assert_equal zone_count, result.model.getZoneHVACBaseboardConvectiveWaters.size,
                 'one hydronic baseboard per zone (gas -> hot water, energy type follows proposed)'
    assert_empty result.model.getChillerElectricEIRs,
                 'System 1 has no central chiller — cooling is per-zone DX in the PTAC'
    assert_empty result.model.getZoneHVACBaseboardConvectiveElectrics
  end
end
