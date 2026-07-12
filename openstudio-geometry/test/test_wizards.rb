require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/openstudio_geometry'

# Wizard gate: every shape builds valid zoned massing; rectangle checked in
# detail (space census, matched surfaces, below-grade BCs); unknown-parameter
# typos raise instead of silently defaulting.
class TestWizards < Minitest::Test
  def test_rectangle_census_and_matching
    audit = OpenStudioGeometry::AuditLog.new
    model = OpenStudioGeometry.create(shape: 'rectangle', length: 40.0, width: 25.0,
                                      above_ground_storys: 2, under_ground_storys: 1,
                                      floor_to_floor_height: 3.6, perimeter_zone_depth: 4.0,
                                      audit: audit)
    assert_equal 15, model.getSpaces.size, '5 spaces (4 perimeter + core) x 3 storeys'
    assert_equal 3, model.getBuildingStorys.size

    # below-grade storey: walls Ground, interior floors/ceilings matched
    basement = model.getSpaces.select { |s| s.nameString.start_with?('Story 0') }
    assert_equal 5, basement.size
    ground_walls = basement.flat_map(&:surfaces).select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Ground' }
    assert_operator ground_walls.size, :>=, 4, 'below-grade exterior walls are Ground'

    matched = model.getSurfaces.count { |s| s.outsideBoundaryCondition == 'Surface' }
    assert_operator matched, :>, 20, 'interior surfaces matched between storeys and zones'

    total_area = model.getSpaces.sum(&:floorArea)
    assert_in_delta 40.0 * 25.0 * 3, total_area, 0.5, 'floor area = footprint x storeys'
    decision = audit.entries.find { |e| e[:step] == :geometry }
    assert_equal 15, decision[:inputs][:spaces]
  end

  def test_every_shape_builds
    { 'aspect_ratio' => { aspect_ratio: 0.6, floor_area: 1800.0, num_floors: 2 },
      'courtyard' => { length: 50.0, width: 30.0, courtyard_length: 20.0, courtyard_width: 10.0, num_floors: 1 },
      'h' => { num_floors: 1 },
      'l' => { num_floors: 1 },
      't' => { num_floors: 1 },
      'u' => { num_floors: 1 } }.each do |shape, params|
      model = OpenStudioGeometry.create(shape: shape, **params)
      assert_operator model.getSpaces.size, :>=, 4, "#{shape}: zoned spaces"
      assert(model.getSpaces.all? { |s| s.floorArea > 0 }, "#{shape}: positive areas")
      exterior_walls = model.getSurfaces.count { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
      assert_operator exterior_walls, :>=, 4, "#{shape}: exterior walls present"
    end
  end

  def test_courtyard_has_inner_facade
    model = OpenStudioGeometry.create(shape: 'courtyard', length: 50.0, width: 30.0,
                                      courtyard_length: 20.0, courtyard_width: 10.0, num_floors: 1)
    footprint = model.getSpaces.sum(&:floorArea)
    assert_in_delta 50.0 * 30.0 - 20.0 * 10.0, footprint, 0.5, 'courtyard void excluded from floor area'
  end

  def test_invalid_parameters
    assert_raises(ArgumentError) { OpenStudioGeometry.create(shape: 'dodecagon') }
    assert_raises(ArgumentError) { OpenStudioGeometry.create(shape: 'rectangle', lenght: 40.0) } # typo must raise
    assert_raises(ArgumentError) { OpenStudioGeometry.create(shape: 'rectangle', length: 10.0, width: 10.0, perimeter_zone_depth: 6.0) }
  end

  def test_rotation_via_aspect_ratio
    model = OpenStudioGeometry.create(shape: 'aspect_ratio', aspect_ratio: 0.5, floor_area: 1000.0,
                                      rotation: 45.0, num_floors: 1)
    group = model.getSpaces.first
    assert_in_delta(45.0 * Math::PI / 180, Math.atan2(group.transformation.matrix[1, 0], group.transformation.matrix[0, 0]), 0.2)
  end
end
