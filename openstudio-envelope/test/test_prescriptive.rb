require_relative 'test_helper'

# P3 gate (standalone half): prescriptive application sets every envelope surface to
# its NECB maximum U; FDWR/SRR mutators hit their limits; audit narrates everything.
class TestPrescriptive < Minitest::Test
  include FixtureHelper

  HDD = 3890 # Toronto (Table C-1)

  def applied_model(**kwargs)
    model = load_fixture
    audit = OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: HDD, **kwargs)
    [model, audit]
  end

  def test_walls_and_roofs_hit_table_values
    model, audit = applied_model
    # HDD 3890 -> zone 5 bin (hdd < 4000): table wall 0.265, roof 0.156 as
    # OVERALL U incl. films (1.4.1.2 definition; default include_films: true)
    # -> construction-only conductance 1/(1/U - R_films): wall 0.2759, roof
    # 0.1594 — the same values the legacy OSut path (TBD.genConstruction)
    # produces on NECB2020 archetypes.
    model.getSurfaces.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors'

      c = surface.construction.get.to_Construction.get
      case surface.surfaceType
      when 'Wall'
        assert_in_delta 0.27595, c.thermalConductance.to_f, 1e-4, surface.nameString
      when 'RoofCeiling'
        assert_in_delta 0.15942, c.thermalConductance.to_f, 1e-4, surface.nameString
      end
    end
    ground = model.getSurfaces.select { |s| s.isGroundSurface && s.surfaceType == 'Floor' }
    refute_empty ground
    ground.each do |surface|
      c = surface.construction.get.to_Construction.get
      assert_in_delta 0.86283, c.thermalConductance.to_f, 1e-4, surface.nameString
    end
    assert audit.entries.any? { |e| e[:step] == :prescriptive && e[:article].to_s.include?('3.2.2.2') }
    assert audit.entries.any? { |e| e[:article].to_s.include?('3.2.3.1') }
  end

  def test_legacy_naming_and_reuse_conventions
    model, = applied_model
    walls = model.getSurfaces.select { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    names = walls.map { |s| s.construction.get.nameString }.uniq
    assert_equal 1, names.size, 'identical base constructions share ONE customized copy'
    assert_match(/:U-0\.27/, names.first, 'legacy BTAP naming convention (costing keys on it)')
  end

  def test_fdwr_and_srr_mutators
    model, audit = applied_model(apply_fdwr: true, apply_srr: true)
    census = OpenStudioEnvelope::Geometry.exposed_walls(model)
    limit = OpenStudioEnvelope::NECB.max_fdwr(vintage: '2020', hdd: HDD) # (2000-778)/3000 = 0.4074
    assert_in_delta limit, census[:fdwr], 0.03, 'windows rebuilt to the FDWR limit'
    census[:walls].each do |wall|
      wall.subSurfaces.each { |ss| assert_equal 'FixedWindow', ss.subSurfaceType }
    end

    roofs = OpenStudioEnvelope::Geometry.exposed_roofs(model)
    assert_in_delta 0.02, roofs[:srr], 0.002, 'skylights at 2% of gross roof area'
    assert audit.entries.any? { |e| e[:step] == :geometry && e[:article].to_s.include?('3.2.1.4') }
  end

  def test_film_convention_default_and_optout
    films_model, audit = applied_model # default include_films: true
    btap_model, btap_audit = applied_model(include_films: false)
    films_wall = films_model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    btap_wall = btap_model.getSurfaces.find { |s| s.nameString == films_wall.nameString }
    films_c = films_wall.construction.get.to_Construction.get.thermalConductance.to_f
    btap_c = btap_wall.construction.get.to_Construction.get.thermalConductance.to_f
    assert_operator films_c, :>, btap_c,
                    'default (films) mode: construction conductance is higher so the OVERALL (with films) U meets the table'
    # default: overall U with films equals the table value (1.4.1.2 definition)
    r_films = OpenStudioEnvelope::Constructions.film_r('wall', 'outdoors')
    overall_u = 1.0 / ((1.0 / films_c) + r_films)
    assert_in_delta 0.265, overall_u, 1e-3
    # opt-out: construction-only conductance equals the table value (old BTAP)
    assert_in_delta 0.265, btap_c, 1e-4
    assert audit.entries.any? { |e| e[:action] == 'film convention' && e[:value].to_s.include?('code-literal') }
    assert btap_audit.entries.any? { |e| e[:action] == 'film convention' && e[:value].to_s.include?('BTAP') }
  end

  # 1.4.1.2 "building envelope" scope: an unconditioned attic's deck/gables are
  # NOT envelope (constructions untouched); the ceiling below IS — set to the
  # ROOF row (3.1.1.7.(6) inclination rule) with the enclosure credited at
  # U 6.25 (3.1.1.7.(4)) and interior films on both faces.
  def test_attic_scope_deck_untouched_ceiling_retargeted
    model = OpenStudio::Model::Model.new
    print_at = lambda do |z|
      pts = OpenStudio::Point3dVector.new
      [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| pts << OpenStudio::Point3d.new(x, y, z) }
      pts
    end
    cond = OpenStudio::Model::Space.fromFloorPrint(print_at.call(0.0), 3.0, model).get
    attic = OpenStudio::Model::Space.fromFloorPrint(print_at.call(3.0), 2.0, model).get
    spaces = OpenStudio::Model::SpaceVector.new
    [cond, attic].each { |s| spaces << s }
    OpenStudio::Model.matchSurfaces(spaces)
    attic.setPartofTotalFloorArea(false)

    # seed every surface with a real layered construction
    mat = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumSmooth', 0.02, 0.5, 800, 1000)
    ins = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumSmooth', 0.2, 0.03, 45, 1000)
    seed = OpenStudio::Model::Construction.new(model)
    seed.setLayers([mat, ins, mat])
    model.getSurfaces.each { |s| s.setConstruction(seed) }
    deck = attic.surfaces.find { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
    deck_before = deck.construction.get.nameString

    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: HDD)

    assert_equal deck_before, deck.construction.get.nameString, 'attic deck is not envelope — construction untouched'
    ceiling = cond.surfaces.find { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Surface' }
    target = 1.0 / ((1.0 / 0.156) - (1.0 / 6.25) - OpenStudioEnvelope::Constructions.film_r_interzone('roofceiling'))
    assert_in_delta target, ceiling.construction.get.to_Construction.get.thermalConductance.to_f, 1e-4,
                    'ceiling to attic set to roof row with enclosure credit + interzone films'
    attic_floor = attic.surfaces.find { |s| s.surfaceType == 'Floor' }
    assert_equal ceiling.construction.get.nameString, attic_floor.construction.get.nameString,
                 'paired surface carries the same construction'
  end

  def test_windows_preserve_shgc
    model = load_fixture
    # give one wall a window with a known SHGC before applying
    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    wall.setWindowToWallRatio(0.3)
    glazing = OpenStudio::Model::SimpleGlazing.new(model)
    glazing.setUFactor(3.5)
    glazing.setSolarHeatGainCoefficient(0.42)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([glazing])
    wall.subSurfaces.each { |ss| ss.setSubSurfaceType('FixedWindow'); ss.setConstruction(construction) }

    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: HDD)
    ss = wall.subSurfaces.first
    new_glazing = ss.construction.get.to_Construction.get.layers.first.to_SimpleGlazing.get
    assert_in_delta 1.9, new_glazing.uFactor, 1e-6, 'window U at Table 3.2.2.3 value'
    assert_in_delta 0.42, new_glazing.solarHeatGainCoefficient, 1e-6, 'SHGC preserved'
  end

  def test_unresolvable_hdd_raises
    assert_raises(ArgumentError) { OpenStudioEnvelope::NECB.apply_prescriptive(load_fixture, vintage: '2020') }
  end
end
