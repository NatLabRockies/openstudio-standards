require_relative 'test_helper'

# P4 gate: the MURB / DWELLING reference path — HAS NEVER EXECUTED with a real
# NECB catalog dwelling space-type name in this repo. Existing tests use
# 'Multi-unit residential' (test_necb_reference.rb, test_necb_selector.rb),
# which is only a `building_type` string in the space-types catalog and
# happens to match the "residential" keyword — it is NOT a dwelling-unit
# `space_type` row. The real catalog dwelling row is:
#   { "building_type": "Space Function", "space_type": "Dwelling units general" }
# (openstudio-loads/lib/openstudio_loads/data/necb/space_types_2020.json).
#
# This file tags a model with that exact name and exercises BOTH gems' dwelling
# detection through the SAME model, on MODEL VALUES only:
#  1. openstudio-lighting's reference_lighting: dwelling units are overridden
#     to 5 W/m2 (8.4.4.5.(2)) via `standardsSpaceType =~ /dwelling/i`
#     (necb/reference.rb apply_dwelling_rule) — regardless of the Part-4
#     catalog LPD row, and regardless of a deliberately hostile 99 W/m2 input.
#  2. openstudio-hvac's category_for keyword vote: 'dwelling' is a keyword of
#     the "Residential/Accommodation Area" category (selection.categories in
#     reference_rules_2020.json) — a real model tagged with the dwelling
#     catalog name must vote that category and take the `special: residential`
#     branch, exercised end-to-end via reference_hvac (not just the synthetic
#     facts test_necb_selector.rb already covers).
class TestNecbMurbDwellingReference < Minitest::Test
  include FixtureHelper

  LIGHTING_LIB = File.expand_path('../../openstudio-lighting/lib/openstudio_lighting', __dir__)
  DWELLING_BUILDING_TYPE = 'Space Function'
  DWELLING_SPACE_TYPE = 'Dwelling units general'
  HOSTILE_W_PER_M2 = 99.0

  def tag_fixture_as_dwelling(model)
    model.getSpaceTypes.select { |st| st.spaces.any? }.each do |st|
      st.setStandardsBuildingType(DWELLING_BUILDING_TYPE)
      st.setStandardsSpaceType(DWELLING_SPACE_TYPE)
    end
    model
  end

  def dwelling_tagged_space_type(model)
    st = OpenStudio::Model::SpaceType.new(model)
    st.setName("#{DWELLING_BUILDING_TYPE} #{DWELLING_SPACE_TYPE}")
    st.setStandardsBuildingType(DWELLING_BUILDING_TYPE)
    st.setStandardsSpaceType(DWELLING_SPACE_TYPE)
    st
  end

  # ---- (1) HVAC selector dwelling detection, exercised through a real model ----

  def test_hvac_selector_votes_residential_accommodation_for_a_real_dwelling_tagged_model
    model = tag_fixture_as_dwelling(load_fixture)
    zones = model.getThermalZones.sort_by(&:nameString)
    # Heated-only proposed system: the special residential rule's
    # "heated only -> System 1" sentence, hit via the auto-derived zone_types
    # (no building: {zone_types:} override — the tag alone must drive selection).
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)

    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020', audit: audit)

    assert_equal ['Residential/Accommodation Area'], result.assignments.map(&:category).uniq,
                 "the 'dwelling' keyword must route a real dwelling-tagged model into the residential " \
                 'category (selection.categories in reference_rules_2020.json), not just in the synthetic ' \
                 'facts of test_necb_selector.rb'
    assert_equal [1], result.assignments.map(&:reference_system).uniq
    assert_equal [:build], result.assignments.map(&:action).uniq
    refute_empty result.model.getZoneHVACPackagedTerminalAirConditioners,
                 'System 1 = MAU + PTAC per zone'
  end

  # ---- (2) reference lighting dwelling override, at MODEL level ----

  def test_reference_lighting_applies_5_w_per_m2_dwelling_override_over_a_hostile_lpd
    skip 'openstudio-lighting not present' unless File.exist?("#{LIGHTING_LIB}.rb")
    require LIGHTING_LIB

    model = OpenStudio::Model::Model.new
    space_type = dwelling_tagged_space_type(model)
    definition = OpenStudio::Model::LightsDefinition.new(model)
    definition.setName('Hostile Dwelling Lights Definition')
    definition.setWattsperSpaceFloorArea(HOSTILE_W_PER_M2)
    lights = OpenStudio::Model::Lights.new(definition)
    lights.setSpaceType(space_type)
    space = OpenStudio::Model::Space.new(model) # a floor-area space so the type is consequential
    space.setSpaceType(space_type)

    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

    dwelling_lpd = OpenStudioLighting::NECB.rules('2020')['dwelling_unit_lpd_w_per_m2'].to_f
    assert_in_delta 5.0, dwelling_lpd, 1e-9, 'sanity: the data file still declares 5.0 W/m2 (8.4.4.5.(2))'

    actual = space_type.lights.first.lightsDefinition.wattsperSpaceFloorArea.get
    assert_in_delta dwelling_lpd, actual, 1e-6,
                     '8.4.4.5.(2): dwelling units must be modeled at 5 W/m2, overriding BOTH the hostile ' \
                     'proposed value and the ordinary Part-4 catalog LPD for this space type'
    refute_in_delta HOSTILE_W_PER_M2, actual, 1e-6, 'reference retained the hostile proposed dwelling LPD'
  end
end
