require_relative 'test_helper'

# P4 gate: the FIXTURE MONOCULTURE gap for multi-storey selection. Every other
# reference_hvac test in this repo (including test_necb_reference.rb's own
# test_three_storey_office_to_sys6) runs on the single-storey 5-zone office
# fixture and FAKES 3 storeys by overriding `building: { storeys: 3, ... }` —
# the storeys count never comes from real geometry, so `building_info`'s
# `Costing::Geometry.above_ground_storeys(model)` auto-derivation path has
# never been exercised for a System 6 selection, and no test has ever built a
# REAL multi-storey zone stack through this path.
#
# This file builds an actual >=3-storey model with openstudio-geometry's bar
# engine (which tags space types with real NECB catalog names in the same
# step), runs reference_hvac with NO storeys override, and asserts:
#  1. the auto-derived storey count really is >= 3 and General Area zones
#     select System 6 (not System 3);
#  2. the built System 6 supply fan's total efficiency is 0.55 — asserted
#     NOWHERE in the existing suite (test_necb_reference.rb's sys6 test only
#     checks supply pressureRise, never supply efficiency, even though it
#     checks BOTH for the return fan).
class TestNecbMultistoreySys6Reference < Minitest::Test
  include FixtureHelper

  GEOMETRY_LIB = File.expand_path('../../openstudio-geometry/lib/openstudio_geometry', __dir__)
  LOADS_LIB = File.expand_path('../../openstudio-loads/lib/openstudio_loads', __dir__)

  def setup
    skip 'openstudio-geometry not present' unless File.exist?("#{GEOMETRY_LIB}.rb")
    skip 'openstudio-loads not present (needed for thermostats before build_system)' unless File.exist?("#{LOADS_LIB}.rb")
    require GEOMETRY_LIB
    require LOADS_LIB
  end

  # A real 3-storey office bar, tagged with the exact catalog office name in
  # the SAME step (OpenStudioGeometry.bar's ratio-tagging), loads applied
  # (thermostats — build_system refuses zones without one), then a proposed
  # HVAC system built on every zone.
  def multistorey_proposed_model
    model = OpenStudioGeometry.bar(
      space_type_ratios: { ['Space Function', 'Office enclosed > 25 m2'] => 1.0 },
      length: 40.0, width: 20.0, num_stories_above_grade: 3, wwr: 0.3
    )
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020')
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    model
  end

  def test_three_storey_bar_geometry_selects_system_6_not_system_3
    model = multistorey_proposed_model
    derived_storeys = OpenStudioHVAC::Costing::Geometry.above_ground_storeys(model)
    assert_operator derived_storeys, :>=, 3, 'fixture precondition: real geometry, not a storeys: override'

    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020', audit: audit)

    assert_equal ['General Area'], result.assignments.map(&:category).uniq,
                 'bar-tagged Office enclosed > 25 m2 zones must vote General Area'
    assert_equal [6], result.assignments.map(&:reference_system).uniq,
                 '>=3 storeys -> System 6 (Table 8.4.4.7.-A), not System 3'
    refute_empty result.model.getFanVariableVolumes, 'System 6 is VAV — variable-volume fans expected'
  end

  # The gap this closes: supply-fan efficiency was asserted NOWHERE for System
  # 6 anywhere in the repo (test_necb_reference.rb's sys6 test asserts supply
  # pressureRise and BOTH return pressureRise/efficiency, but never supply
  # efficiency). fans['system_6']['supply_efficiency'] in
  # data/necb/reference_rules_2020.json declares 0.55 (8.4.4.18.(4)); assert
  # the BUILT model actually carries that value.
  def test_system_6_supply_fan_total_efficiency_matches_the_declared_0_55
    model = multistorey_proposed_model
    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020')

    declared = OpenStudioHVAC::NECB.rules('2020').fetch('fans').fetch('system_6').fetch('supply_efficiency')
    assert_in_delta 0.55, declared, 1e-9, 'sanity: the data file still declares 0.55'

    supply_fans = result.model.getFanVariableVolumes.reject { |f| f.nameString =~ /return/i }
    refute_empty supply_fans, 'System 6 must have built supply fans'
    supply_fans.each do |fan|
      assert_in_delta 1000.0, fan.pressureRise, 0.1, "#{fan.nameString}: supply pressure"
      assert_in_delta declared, fan.fanTotalEfficiency, 1e-6,
                       "#{fan.nameString}: built supply fan total efficiency must match the declared " \
                       '8.4.4.18.(4) value (fans.system_6.supply_efficiency) — if this ever mismatches, ' \
                       'that is a FINDING against apply_fan_rules (necb/reference.rb), not this test.'
    end
  end
end
