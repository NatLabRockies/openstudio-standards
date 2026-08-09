require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/openstudio_geometry'

# Bar engine gate: ratio-true slicing with standards tagging, WWR, party walls,
# below-grade handling — and the full-family composition (bar geometry through
# compliance with ONE audit).
class TestBar < Minitest::Test
  RATIOS = { ['Space Function', 'Office enclosed > 25 m2'] => 0.7,
             ['Space Function', 'Corridor/Transition area other-sch-A'] => 0.3 }.freeze

  # Wizard/bar output has no constructions; downstream envelope work retargets
  # EXISTING ones, so authored models need a seed set first.
  def seed_constructions(model)
    opaque = OpenStudio::Model::MasslessOpaqueMaterial.new(model, 'MediumSmooth', 2.0)
    opaque.setName('Seed R-2')
    construction = OpenStudio::Model::Construction.new(model)
    construction.setName('Seed Opaque')
    construction.setLayers([opaque])
    glazing = OpenStudio::Model::SimpleGlazing.new(model)
    glazing.setUFactor(2.5)
    glazing.setSolarHeatGainCoefficient(0.4)
    glazing.setVisibleTransmittance(0.5)
    window = OpenStudio::Model::Construction.new(model)
    window.setName('Seed Window')
    window.setLayers([glazing])
    model.getSurfaces.each { |s| s.setConstruction(construction) }
    model.getSubSurfaces.each { |s| s.setConstruction(window) }
  end

  def test_ratio_true_slicing_and_tagging
    audit = OpenStudioGeometry::AuditLog.new
    model = OpenStudioGeometry.bar(space_type_ratios: RATIOS, length: 50.0, width: 20.0,
                                   num_stories_above_grade: 2, wwr: 0.4, audit: audit)

    assert(model.getSpaces.all? { |s| s.spaceType.is_initialized }, 'every space typed')
    areas = Hash.new(0.0)
    model.getSpaces.each { |s| areas[s.spaceType.get.standardsSpaceType.get] += s.floorArea }
    total = areas.values.sum
    assert_in_delta 50.0 * 20.0 * 2, total, 1.0
    assert_in_delta 0.7, areas['Office enclosed > 25 m2'] / total, 0.01, 'ratio-true slicing'
    assert_in_delta 0.3, areas['Corridor/Transition area other-sch-A'] / total, 0.01

    wall_area = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
                     .sum(&:grossArea)
    window_area = model.getSubSurfaces.sum(&:grossArea)
    assert_in_delta 0.4, window_area / wall_area, 0.03, 'WWR honored'
    assert(audit.entries.any? { |e| e[:action].include?('sliced bar massing') })
  end

  def test_below_grade_and_party_walls
    model = OpenStudioGeometry.bar(space_type_ratios: RATIOS, length: 40.0, width: 15.0,
                                   num_stories_above_grade: 2, num_stories_below_grade: 1,
                                   party_wall_stories_north: 2, wwr: 0.3)
    ground = model.getSurfaces.count { |s| s.outsideBoundaryCondition == 'Ground' }
    assert_operator ground, :>=, 1, 'below-grade surfaces grounded'
    adiabatic = model.getSurfaces.count { |s| s.outsideBoundaryCondition == 'Adiabatic' }
    assert_operator adiabatic, :>=, 1, 'party walls adiabatic'
  end

  # storeys:/below_grade_storeys: are the canonical names; num_stories_*_grade
  # (the engine's own spelling, used by the tests above) still works, and the
  # two together are ambiguous.
  def test_storey_aliases
    audit = OpenStudioGeometry::AuditLog.new
    canonical = OpenStudioGeometry.bar(space_type_ratios: RATIOS, length: 30.0, width: 15.0,
                                       storeys: 2, below_grade_storeys: 1, wwr: 0.3, audit: audit)
    legacy = OpenStudioGeometry.bar(space_type_ratios: RATIOS, length: 30.0, width: 15.0,
                                    num_stories_above_grade: 2, num_stories_below_grade: 1, wwr: 0.3)
    assert_equal legacy.getSpaces.size, canonical.getSpaces.size, 'old names produce the same geometry'
    assert_in_delta legacy.getSpaces.sum(&:floorArea), canonical.getSpaces.sum(&:floorArea), 0.01
    inputs = audit.entries.find { |e| e[:step] == :geometry }[:inputs]
    assert_equal 2, inputs[:storeys_above]
    assert_equal 1, inputs[:storeys_below]

    assert_raises(ArgumentError) do
      OpenStudioGeometry.bar(space_type_ratios: RATIOS, storeys: 2, num_stories_above_grade: 3)
    end
    assert_raises(ArgumentError) { OpenStudioGeometry.bar(space_type_ratios: RATIOS, storeyz: 2) }
  end

  def test_full_family_composition_from_bar
    %w[loads lighting shw hvac envelope].each do |gem_name|
      path = File.expand_path("../../openstudio-#{gem_name}/lib/openstudio_#{gem_name}", __dir__)
      skip "openstudio-#{gem_name} not present" unless File.exist?("#{path}.rb")
      require path
    end

    model = OpenStudioGeometry.bar(space_type_ratios: RATIOS, length: 50.0, width: 20.0,
                                   num_stories_above_grade: 2, wwr: 0.4)
    seed_constructions(model) # wizard output carries no constructions; the envelope pass retargets existing ones
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)
    OpenStudioLighting.apply_lights(model, vintage: '2020', audit: audit)
    OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: 'NaturalGas', audit: audit)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', model.getThermalZones.sort_by(&:nameString))
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890, audit: audit)

    refute_empty model.getPeoples.to_a, 'loads live on bar geometry'
    refute_empty model.getSpaceTypes.flat_map { |st| st.lights.to_a }, 'lighting live'
    refute_empty model.getWaterUseEquipments.to_a, 'SHW live'
    assert_operator model.getPlantLoops.size, :>=, 2, 'heating + SHW plants'
    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    # D-23: table 0.265 is OVERALL U (incl. films) — constructions are named by
    # the construction-only conductance 1/(1/0.265 - R_films) = 0.2759.
    assert_match(/:U-0\.2759/, wall.construction.get.nameString, 'prescriptive envelope applied')
    steps = audit.entries.map { |e| e[:step] }.uniq
    %i[loads lighting shw prescriptive].each { |s| assert_includes steps, s }
    assert_operator JSON.parse(audit.to_json).size, :>, 40,
                    'ONE audit spans geometry-authored building through every domain'
  end
end
