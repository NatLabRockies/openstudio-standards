require 'minitest/autorun'
require 'json'
require_relative '../lib/openstudio_geometry'

# Measured-footprint gate: a real GeoJSON outline plus a measured height builds
# valid zoned massing; the SDK traps that make raw outlines fail (winding,
# non-decimating simplify, mitre overlap at reflex corners) stay pinned.
class TestFootprint < Minitest::Test
  F = OpenStudioGeometry::Footprint

  # A real NRCan building-stock record (feature 870226c8, Ottawa K1P): 69
  # vertices, 33 of them reflex, 5,266 m2 published area, 82.65 m measured.
  # Kept verbatim so the traps it exposes cannot quietly stop being tested.
  OTTAWA_TOWER = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'footprint_ottawa_tower.json'))).freeze
  PUBLISHED_AREA = 5266.0
  MEASURED_HEIGHT = 82.65

  def rect_ring(length = 50.0, width = 30.0)
    F.clockwise([[0, 0], [0, width], [length, width], [length, 0]].map { |x, y| OpenStudio::Point3d.new(x, y, 0) })
  end

  # The tangent-plane projection has to reproduce the publisher's own area, or
  # every area downstream is wrong.
  def test_projection_reproduces_published_area
    ring = F.ring_from_geojson(OTTAWA_TOWER)
    outline = F.normalize(F.project(ring))
    assert_in_delta PUBLISHED_AREA, F.area(outline), PUBLISHED_AREA * 0.005, 'projected area within 0.5% of published'
    assert_equal 69, outline.size, 'no vertices lost to normalization'
  end

  # THE trap: Space.fromFloorPrint wants clockwise-from-above and returns an
  # uninitialized Optional (no message) otherwise. normalize must always
  # deliver clockwise regardless of the source ring's winding.
  def test_normalize_forces_clockwise_either_way
    ring = F.ring_from_geojson(OTTAWA_TOWER)
    forward = F.normalize(F.project(ring))
    reversed = F.normalize(F.project(ring.reverse))

    assert_operator F.signed_area(forward), :<, 0, 'clockwise viewed from above'
    assert_operator F.signed_area(reversed), :<, 0, 'reversed input still comes back clockwise'
    assert_in_delta F.area(forward), F.area(reversed), 0.5

    model = OpenStudio::Model::Model.new
    assert OpenStudio::Model::Space.fromFloorPrint(F.to_vector(forward), 3.048, model).is_initialized,
           'clockwise ring is accepted by the SDK'
    refute OpenStudio::Model::Space.fromFloorPrint(F.to_vector(forward.reverse), 3.048, model).is_initialized,
           'counter-clockwise is silently rejected — this is why normalize exists'
  end

  # OpenStudio.simplify only drops collinear points; it does NOT decimate.
  # Douglas-Peucker has to, or every storey carries 69 exterior walls.
  def test_decimate_where_sdk_simplify_will_not
    outline = F.normalize(F.project(F.ring_from_geojson(OTTAWA_TOWER)))
    assert_equal outline.size, OpenStudio.simplify(F.to_vector(outline), false, 1.0).size + 1,
                 'SDK simplify removes at most a collinear point at 1 m — it does not decimate'

    coarse = F.decimate(outline, 4.0)
    assert_operator coarse.size, :<, 25, 'Douglas-Peucker actually reduces the vertex count'
    assert_operator F.signed_area(coarse), :<, 0, 'winding preserved'
    assert_in_delta F.area(outline), F.area(coarse), F.area(outline) * 0.01, 'area preserved within 1%'
    assert_equal outline.size, F.decimate(outline, 0).size, 'tolerance 0 is a no-op'
  end

  # The mitred offset is exact on a convex outline. If this drifts, every
  # core/perimeter area downstream is wrong.
  def test_core_and_perimeter_tiles_a_rectangle_exactly
    plan = F.core_and_perimeter(rect_ring, 4.57)
    refute plan[:rejected], 'a plain rectangle must accept core and perimeter zoning'
    assert_equal 4, plan[:perimeters].size, 'one perimeter zone per outer edge'

    tiled = F.area(plan[:core]) + plan[:perimeters].sum { |quad| F.area(quad) }
    assert_in_delta 1500.0, tiled, 0.001, 'core + perimeters tile the outline exactly'
    assert_in_delta (50.0 - (2 * 4.57)) * (30.0 - (2 * 4.57)), F.area(plan[:core]), 0.001
    assert plan[:perimeters].all? { |quad| F.signed_area(quad) < 0 }, 'every zone clockwise'
  end

  # What actually decides whether an outline can carry core-and-perimeter
  # zoning is wall-run length against the offset depth, NOT vertex count or
  # concavity. The offset must report the outline's own ceiling, and honouring
  # it must be what recovers the zoning.
  def test_zoning_is_bounded_by_wall_runs_not_by_vertex_count
    outline = F.normalize(F.project(F.ring_from_geojson(OTTAWA_TOWER)))
    reflex = (0...outline.size).count do |i|
      a = outline[(i - 1) % outline.size]
      b = outline[i]
      c = outline[(i + 1) % outline.size]
      (((b.x - a.x) * (c.y - b.y)) - ((b.y - a.y) * (c.x - b.x))).positive?
    end
    assert_operator reflex, :>, 20, 'fixture really is a reflex-heavy outline'

    raw = F.core_and_perimeter(outline, 4.57)
    assert raw[:rejected], 'raw outline cannot carry a 15 ft perimeter and must be refused'
    assert_match(/lower perimeter_zone_depth/, raw[:rejected], 'rejection names the real lever')

    # Decimating to 20 vertices does NOT rescue it: one wall run is still 0.29 m
    # short of surviving a 4.57 m offset, and that zone would self-intersect.
    coarse = F.decimate(outline, 4.0)
    ceiling = F.max_perimeter_depth(coarse)
    assert_in_delta 4.46, ceiling, 0.05, "the outline's own ceiling, reported not guessed"
    assert F.core_and_perimeter(coarse, 4.57)[:rejected], 'above the ceiling stays refused'

    # Honouring the reported ceiling is what makes it viable.
    plan = F.core_and_perimeter(coarse, 3.0)
    refute plan[:rejected], 'below the ceiling the same outline zones cleanly'
    assert_operator plan[:tiling_error], :<=, F::TILING_TOLERANCE
    assert_equal coarse.size, plan[:perimeters].size, 'one perimeter zone per wall run'
  end

  # The ceiling is exact and derivable by hand: every edge of a rectangle sits
  # between two right angles, each eating D off it, so the limit is half the
  # short side.
  def test_max_perimeter_depth_is_exact_on_a_rectangle
    assert_in_delta 15.0, F.max_perimeter_depth(rect_ring(50.0, 30.0)), 1e-9
    assert_in_delta 3.0, F.max_perimeter_depth(rect_ring(8.0, 6.0)), 1e-9
    refute F.core_and_perimeter(rect_ring(50.0, 30.0), 10.0)[:rejected], 'well under the ceiling holds'
    assert F.core_and_perimeter(rect_ring(50.0, 30.0), 15.1)[:rejected], 'over the ceiling does not'

    # Geometrically viable is not the same as useful: at 14.9 m the offset still
    # closes, but the core is 0.27% of the floor. The sliver guard is what stops
    # that, and it fires before the geometry does.
    sliver = F.core_and_perimeter(rect_ring(50.0, 30.0), 14.9)
    assert sliver[:rejected]
    assert_match(/sliver/, sliver[:rejected])
  end

  # :auto keeps the 15 ft convention where it fits and backs off only where it
  # must — and says so, because a reduced band is no longer the code daylit zone.
  def test_auto_perimeter_depth_prefers_the_convention
    assert_in_delta F::CONVENTIONAL_DEPTH, F.auto_perimeter_depth(rect_ring(50.0, 30.0)), 1e-9,
                    'a roomy outline keeps the full 15 ft'
    narrow = F.auto_perimeter_depth(rect_ring(12.0, 9.0))
    assert_operator narrow, :<, F::CONVENTIONAL_DEPTH, 'a tight outline is reduced'
    assert_in_delta 4.5 * 0.95, narrow, 1e-9, '5% headroom off the outline ceiling'
    assert_nil F.auto_perimeter_depth(rect_ring(3.0, 2.0)), 'below the useful minimum, no depth at all'

    audit = OpenStudioGeometry::AuditLog.new
    OpenStudioGeometry.create_from_footprint(geojson: OTTAWA_TOWER, height_m: 20.0,
                                             decimate_tolerance: 4.0, audit: audit)
    reduced = audit.warnings.find { |w| w[:action].include?('reduced below the 15 ft convention') }
    refute_nil reduced, 'a non-conventional perimeter band must never be silent'
    assert_operator reduced[:inputs][:perimeter_zone_depth], :<, F::CONVENTIONAL_DEPTH
    assert_equal F::CONVENTIONAL_DEPTH, reduced[:inputs][:conventional_depth]
  end

  def test_core_and_perimeter_rejects_outline_too_narrow_for_a_core
    plan = F.core_and_perimeter(rect_ring(8.0, 6.0), 4.57)
    assert plan[:rejected]
    assert_match(/supports perimeter_zone_depth up to 3\.00 m/, plan[:rejected],
                 'the rejection carries the number the caller needs')
  end

  # Perimeter zones merge by compass bin: spaces stay one-per-edge (exact
  # geometry, no polygon union) while the ZONE each joins is its orientation.
  # The SDK's own Surface#azimuth is the ground truth for the convention.
  def test_perimeter_zones_merge_by_orientation
    model = OpenStudioGeometry.create_from_footprint(
      points: rect_ring(50.0, 30.0), storeys: 1, zoning: :core_perimeter, perimeter_zone_depth: 4.57
    )
    assert_equal 5, model.getSpaces.size, 'one space per edge plus the core'
    assert_equal 5, model.getThermalZones.size, 'N/E/S/W + core'
    assert_equal ['Story 0 Core ZN', 'Story 0 East ZN', 'Story 0 North ZN',
                  'Story 0 South ZN', 'Story 0 West ZN'],
                 model.getThermalZones.map(&:nameString).sort

    # Every zone's exterior walls must actually face the way its name claims.
    expected = { 'North' => 0, 'East' => 90, 'South' => 180, 'West' => 270 }
    model.getThermalZones.each do |zone|
      bin = zone.nameString.split[2]
      next if bin == 'Core'

      azimuths = zone.spaces.flat_map(&:surfaces)
                     .select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
                     .map { |s| (s.azimuth * 180 / Math::PI).round }.uniq
      assert_equal [expected[bin]], azimuths, "#{bin} zone walls face #{bin}"
    end
    core = model.getThermalZones.find { |z| z.nameString.include?('Core') }
    assert_empty core.spaces.flat_map(&:surfaces)
                     .select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' },
                 'the core has no exterior wall — that is what makes it a core'
  end

  # The point of merging: a many-edged real outline collapses to the 4+1 zones a
  # modeller expects, without a single wall landing in the wrong bin.
  def test_orientation_merge_collapses_a_real_outline
    model = OpenStudioGeometry.create_from_footprint(
      geojson: OTTAWA_TOWER, height_m: MEASURED_HEIGHT, floor_to_floor_height: F::NRCAN_IMPLIED,
      decimate_tolerance: 4.0, multiplier: :mid
    )
    assert_operator model.getSpaces.size, :>, 20, 'still one space per edge per storey'
    assert_equal 15, model.getThermalZones.size, '5 zones x 3 storeys, not one per space'
    assert_equal 5, model.getThermalZones.count { |z| z.nameString.start_with?('Story 0 ') },
                 'exactly N/E/S/W + core on the ground storey'

    misfiled = model.getThermalZones.sum do |zone|
      bin = zone.nameString.split[2]
      next 0 if bin == 'Core'

      zone.spaces.flat_map(&:surfaces)
          .select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
          .count { |s| F::ORIENTATIONS[((((s.azimuth * 180 / Math::PI) + 45) % 360) / 90).floor] != bin }
    end
    assert_equal 0, misfiled, 'every exterior wall sits in its own compass bin'

    # zones must not span storeys — a multiplied storey needs its own zones
    assert_equal [1, 22], model.getThermalZones.map(&:multiplier).uniq.sort
  end

  # The azimuth convention is the SDK's, not one of our own invention.
  def test_edge_orientation_matches_sdk_azimuth
    ring = rect_ring(50.0, 30.0)
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.fromFloorPrint(F.to_vector(ring), 3.0, model).get
    sdk = space.surfaces.select { |s| s.surfaceType == 'Wall' }
                .map { |s| ((s.azimuth * 180 / Math::PI) % 360).round }.sort
    mine = (0...ring.size).map { |i| F.edge_azimuth(ring[i], ring[(i + 1) % ring.size]).round % 360 }.sort
    assert_equal sdk, mine, 'edge_azimuth reproduces Surface#azimuth exactly'

    # bin boundaries sit at 45 degrees, and North wraps through 0
    assert_equal 'North', F.edge_orientation(*[[0, 0], [1, 0]].map { |x, y| OpenStudio::Point3d.new(x, y, 0) })
    assert_equal 'South', F.edge_orientation(*[[1, 0], [0, 0]].map { |x, y| OpenStudio::Point3d.new(x, y, 0) })
    assert_equal 'West', F.edge_orientation(*[[0, 0], [0, 1]].map { |x, y| OpenStudio::Point3d.new(x, y, 0) })
    assert_equal 'East', F.edge_orientation(*[[0, 1], [0, 0]].map { |x, y| OpenStudio::Point3d.new(x, y, 0) })
  end

  # Windows are PURE GEOMETRY here: a caller-chosen ratio, no default, no code
  # knowledge. The NECB maximum belongs to openstudio-envelope.
  def test_apply_wwr_scalar
    model = OpenStudioGeometry.create_from_footprint(points: rect_ring(50.0, 30.0), storeys: 2,
                                                     zoning: :single)
    assert_equal 0, model.getSubSurfaces.size, 'measured massing starts with no windows at all'

    audit = OpenStudioGeometry::AuditLog.new
    result = OpenStudioGeometry.apply_wwr(model, 0.35, audit: audit)
    assert_equal 8, result[:walls], '4 walls x 2 storeys'
    assert_equal 8, result[:glazed]
    assert_equal 0, result[:refused]
    assert_in_delta 0.35, result[:fdwr], 1e-6, 'achieved ratio hits the request'
    assert_equal 8, model.getSubSurfaces.size

    entry = audit.entries.reverse.find { |e| e[:action].include?('windows cut') }
    assert_equal 0.35, entry[:inputs][:requested]
  end

  # Orientation-specific glazing — the companion to orientation-merged zoning.
  # A bin left out of the hash gets NO windows, it does not fall back.
  def test_apply_wwr_per_orientation
    model = OpenStudioGeometry.create_from_footprint(points: rect_ring(50.0, 30.0), storeys: 1,
                                                     zoning: :single)
    # both spellings must work: brace-less (parsed as keywords) and explicit Hash
    OpenStudioGeometry.apply_wwr(model, 'South' => 0.5, 'North' => 0.15)

    by_bin = model.getSurfaces
                  .select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
                  .group_by { |s| F.wall_orientation(s) }
    assert_in_delta 0.5, by_bin['South'].sum { |s| s.subSurfaces.sum(&:netArea) } / by_bin['South'].sum(&:grossArea), 1e-6
    assert_in_delta 0.15, by_bin['North'].sum { |s| s.subSurfaces.sum(&:netArea) } / by_bin['North'].sum(&:grossArea), 1e-6
    assert_empty by_bin['East'].flat_map(&:subSurfaces), 'omitted bins get no windows'
    assert_empty by_bin['West'].flat_map(&:subSurfaces)
  end

  # The seam with openstudio-envelope: the NECB maximum is ITS rule (3.2.1.4),
  # this gem only cuts the opening. Pinned as a number so a change in either
  # gem is visible — HDD 4500 gives (2000 - 0.2*4500)/3000 by hand.
  def test_apply_wwr_accepts_an_externally_computed_necb_limit
    model = OpenStudioGeometry.create_from_footprint(points: rect_ring(50.0, 30.0), storeys: 1,
                                                     zoning: :single)
    necb_limit_hdd4500 = (2000 - (0.2 * 4500)) / 3000.0
    assert_in_delta 0.3667, necb_limit_hdd4500, 0.0001
    result = OpenStudioGeometry.apply_wwr(model, necb_limit_hdd4500)
    assert_in_delta necb_limit_hdd4500, result[:fdwr], 1e-6
  end

  def test_apply_wwr_rejects_bad_ratios
    model = OpenStudioGeometry.create_from_footprint(points: rect_ring(50.0, 30.0), storeys: 1,
                                                     zoning: :single)
    assert_raises(ArgumentError) { OpenStudioGeometry.apply_wwr(model, 1.0) }
    assert_raises(ArgumentError) { OpenStudioGeometry.apply_wwr(model, -0.1) }
    assert_raises(ArgumentError) { OpenStudioGeometry.apply_wwr(model, 'lots') }
    assert_raises(ArgumentError) { OpenStudioGeometry.apply_wwr(model, 'South' => 1.5) }
    assert_raises(ArgumentError) { OpenStudioGeometry.apply_wwr(model) }
  end

  # Symbol bins and an explicit Hash must land in the same place as the
  # brace-less form — the signature accepts all three spellings on purpose.
  def test_apply_wwr_hash_spellings_agree
    ratios = [{ 'South' => 0.4 }, nil, nil]
    achieved = ratios.each_with_index.map do |explicit, index|
      model = OpenStudioGeometry.create_from_footprint(points: rect_ring(50.0, 30.0), storeys: 1,
                                                       zoning: :single)
      case index
      when 0 then OpenStudioGeometry.apply_wwr(model, explicit)
      when 1 then OpenStudioGeometry.apply_wwr(model, 'South' => 0.4)
      else OpenStudioGeometry.apply_wwr(model, South: 0.4)
      end[:fdwr]
    end
    assert_equal 1, achieved.uniq.size, 'Hash, brace-less and Symbol bins agree'
    assert_operator achieved.first, :>, 0.0
  end

  # Storey count comes from the measured height. The three plausible storey
  # heights give three different answers, which is exactly why it is an input.
  def test_storeys_derived_from_measured_height
    assert_equal 27, F.storeys_for(MEASURED_HEIGHT, F::TEN_FEET)
    assert_equal 24, F.storeys_for(MEASURED_HEIGHT, F::NRCAN_IMPLIED), 'matches the publisher\'s own estimated_floors'
    assert_equal 22, F.storeys_for(MEASURED_HEIGHT, 3.8), 'gem-wide default storey height'
    assert_equal 1, F.storeys_for(1.2, 3.8), 'never less than one storey'
    assert_raises(ArgumentError) { F.storeys_for(30.0, 0) }
  end

  def test_end_to_end_single_zone_massing
    audit = OpenStudioGeometry::AuditLog.new
    model = OpenStudioGeometry.create_from_footprint(
      geojson: OTTAWA_TOWER, height_m: MEASURED_HEIGHT, floor_to_floor_height: F::TEN_FEET,
      zoning: :single, decimate_tolerance: 4.0, audit: audit,
      source: { feature_id: '870226c8', dataset: 'nrcan-buildings' }
    )

    assert_equal 27, model.getSpaces.size, 'one space per storey at 10 ft floors'
    assert_equal 27, model.getBuildingStorys.size
    assert(model.getSpaces.all? { |s| s.floorArea > 0 })
    assert_in_delta PUBLISHED_AREA * 27, model.getBuilding.floorArea, PUBLISHED_AREA * 27 * 0.01

    ground = model.getSpaces.select { |s| s.nameString.start_with?('Story 0 ') }
    ground_floors = ground.flat_map(&:surfaces).select { |s| s.surfaceType == 'Floor' }
    assert(ground_floors.all? { |s| s.outsideBoundaryCondition == 'Ground' }, 'bottom storey meets the ground')
    assert_operator model.getSurfaces.count { |s| s.outsideBoundaryCondition == 'Surface' }, :>, 40,
                    'storeys matched to each other'

    # site is georeferenced from the ring itself
    assert_in_delta 45.4214, model.getSite.latitude, 0.01
    assert_in_delta(-75.6977, model.getSite.longitude, 0.01)
  end

  def test_end_to_end_core_perimeter_and_story_multiplier
    audit = OpenStudioGeometry::AuditLog.new
    model = OpenStudioGeometry.create_from_footprint(
      geojson: OTTAWA_TOWER, height_m: MEASURED_HEIGHT, floor_to_floor_height: F::NRCAN_IMPLIED,
      zoning: :core_perimeter, perimeter_zone_depth: 3.0, decimate_tolerance: 4.0,
      multiplier: :mid, audit: audit
    )

    assert_equal 3, model.getBuildingStorys.size, 'ground / multiplied middle / top'
    per_storey = model.getSpaces.size / 3
    assert_operator per_storey, :>, 4, 'core plus one perimeter zone per outer edge'
    assert_equal 22, model.getThermalZones.map(&:multiplier).max, '24 storeys - 2 real ones'

    entry = audit.entries.reverse.find { |e| e[:step] == :geometry && e[:action].include?('measured-footprint') }
    assert_equal :core_perimeter, entry[:inputs][:zoning]
    assert_equal 24, entry[:inputs][:storeys_above]
    assert_in_delta MEASURED_HEIGHT, entry[:inputs][:modelled_height_m], 2.0

    adiabatic = model.getSurfaces.count { |s| s.outsideBoundaryCondition == 'Adiabatic' }
    assert_operator adiabatic, :>, 0, 'multiplied storey does not leak through unmatched floors/ceilings'
  end

  # Provenance is the whole reason this lives in the gem: a measured massing is
  # only reproducible if the audit records what it was measured from.
  def test_audit_records_full_provenance
    audit = OpenStudioGeometry::AuditLog.new
    OpenStudioGeometry.create_from_footprint(
      geojson: OTTAWA_TOWER, height_m: MEASURED_HEIGHT, decimate_tolerance: 4.0,
      source: { feature_id: '870226c8', dataset: 'nrcan-buildings', height_field: 'height_max_m' },
      audit: audit
    )
    inputs = audit.entries.reverse.find { |e| e[:step] == :geometry && e[:action].include?('measured-footprint') }[:inputs]

    assert_equal '870226c8', inputs[:feature_id]
    assert_equal 'nrcan-buildings', inputs[:dataset]
    assert_equal 'height_max_m', inputs[:height_field]
    assert_equal MEASURED_HEIGHT, inputs[:height_m]
    assert_equal 3.8, inputs[:floor_to_floor_height], 'the assumption is recorded, not buried'
    assert_equal 70, inputs[:vertices_raw], 'as supplied, closing vertex included'
    assert_operator inputs[:vertices_used], :<, 70
    assert_equal 4.0, inputs[:decimate_tolerance]
  end

  # Degradation must be loud: a noisy outline gets single-zone storeys AND a
  # warning naming the reason, never a silent overlap.
  def test_zoning_degrades_loudly
    audit = OpenStudioGeometry::AuditLog.new
    model = OpenStudioGeometry.create_from_footprint(
      geojson: OTTAWA_TOWER, height_m: 20.0, zoning: :core_perimeter,
      perimeter_zone_depth: 4.57, decimate_tolerance: 0, audit: audit
    )
    warning = audit.warnings.find { |w| w[:inputs][:reason] }
    refute_nil warning, 'silent degradation is a family contract violation'
    assert_match(/raise decimate_tolerance/, warning[:inputs][:reason], 'warning names the fix')

    entry = audit.entries.reverse.find { |e| e[:step] == :geometry && e[:action].include?('measured-footprint') }
    assert_equal :single, entry[:inputs][:zoning]
    assert_equal :core_perimeter, entry[:inputs][:requested_zoning]
    assert_equal 5, model.getSpaces.size, 'one space per storey after the fallback'
  end

  def test_geojson_shapes_accepted
    ring = F.ring_from_geojson(OTTAWA_TOWER)
    assert_equal ring, F.ring_from_geojson(JSON.generate(OTTAWA_TOWER)), 'raw JSON string'
    assert_equal ring, F.ring_from_geojson({ 'geometry' => OTTAWA_TOWER }), 'wrapped in a Feature'
    assert_equal ring, F.ring_from_geojson(ring), 'a bare [[lon, lat], ...] ring passes through'

    multi = { 'type' => 'MultiPolygon', 'coordinates' => [[[[0, 0], [0, 1], [1, 1]]], OTTAWA_TOWER['coordinates']] }
    assert_equal ring, F.ring_from_geojson(multi), 'MultiPolygon takes the largest ring'
    assert_raises(ArgumentError) { F.ring_from_geojson({ 'type' => 'LineString', 'coordinates' => [[0, 0]] }) }
  end

  def test_invalid_parameters
    assert_raises(ArgumentError) { OpenStudioGeometry.create_from_footprint(height_m: 20.0) }
    assert_raises(ArgumentError) { OpenStudioGeometry.create_from_footprint(geojson: OTTAWA_TOWER) }
    assert_raises(ArgumentError) do
      OpenStudioGeometry.create_from_footprint(geojson: OTTAWA_TOWER, points: [], height_m: 20.0)
    end
    assert_raises(ArgumentError) do
      OpenStudioGeometry.create_from_footprint(geojson: OTTAWA_TOWER, height_m: 20.0, zoning: :perimeter_only)
    end
    assert_raises(ArgumentError) do
      OpenStudioGeometry.create_from_footprint(geojson: OTTAWA_TOWER, height_m: 20.0, multiplier: :all)
    end
    assert_raises(ArgumentError) { F.project([[0, 0], [1, 1]]) }
  end
end
