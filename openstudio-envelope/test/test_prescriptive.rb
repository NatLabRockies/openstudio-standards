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
    # HDD 3890 -> zone 5 bin (hdd < 4000): wall 0.265, roof 0.156, window 1.9
    model.getSurfaces.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors'

      c = surface.construction.get.to_Construction.get
      case surface.surfaceType
      when 'Wall'
        assert_in_delta 0.265, c.thermalConductance.to_f, 1e-4, surface.nameString
      when 'RoofCeiling'
        assert_in_delta 0.156, c.thermalConductance.to_f, 1e-4, surface.nameString
      end
    end
    ground = model.getSurfaces.select { |s| s.isGroundSurface && s.surfaceType == 'Floor' }
    refute_empty ground
    ground.each do |surface|
      c = surface.construction.get.to_Construction.get
      assert_in_delta 0.757, c.thermalConductance.to_f, 1e-4, surface.nameString
    end
    assert audit.entries.any? { |e| e[:step] == :prescriptive && e[:article].to_s.include?('3.2.2.2') }
    assert audit.entries.any? { |e| e[:article].to_s.include?('3.2.3.1') }
  end

  def test_legacy_naming_and_reuse_conventions
    model, = applied_model
    walls = model.getSurfaces.select { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    names = walls.map { |s| s.construction.get.nameString }.uniq
    assert_equal 1, names.size, 'identical base constructions share ONE customized copy'
    assert_match(/:U-0\.265/, names.first, 'legacy BTAP naming convention (costing keys on it)')
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

  def test_include_films_lowers_construction_conductance
    legacy_model, = applied_model
    films_model, audit = applied_model(include_films: true)
    legacy_wall = legacy_model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    films_wall = films_model.getSurfaces.find { |s| s.nameString == legacy_wall.nameString }
    legacy_c = legacy_wall.construction.get.to_Construction.get.thermalConductance.to_f
    films_c = films_wall.construction.get.to_Construction.get.thermalConductance.to_f
    assert_operator films_c, :>, legacy_c,
                    'films mode: construction conductance is higher so the OVERALL (with films) U meets the table'
    # overall U with films should now equal the table value
    r_films = OpenStudioEnvelope::Constructions.film_r('wall', 'outdoors')
    overall_u = 1.0 / ((1.0 / films_c) + r_films)
    assert_in_delta 0.265, overall_u, 1e-3
    assert audit.entries.any? { |e| e[:action] == 'film convention' && e[:value].to_s.include?('code-literal') }
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
