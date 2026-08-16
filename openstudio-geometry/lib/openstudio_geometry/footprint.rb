require 'json'

module OpenStudioGeometry
  # Measured-footprint massing: turn a real building outline (GeoJSON ring from
  # a building-stock source, a survey, a GIS export) plus a measured height into
  # zoned OpenStudio massing.
  #
  # Unlike `wizards.rb` and `bar.rb` this is NOT a port — there is no upstream
  # equivalent. The seven parametric wizards build their polygons analytically
  # from length/width, so winding and validity hold by construction; a measured
  # ring guarantees neither, and every method here exists because raw outlines
  # break something in the SDK:
  #
  # - `Space.fromFloorPrint` needs CLOCKWISE-from-above vertices. Counter-
  #   clockwise returns an uninitialized Optional with no message — the single
  #   most expensive trap in this path, so `normalize` always forces winding.
  # - `OpenStudio.removeSpikes` / `OpenStudio.buffer` are boost-backed and want
  #   the same clockwise rings; a counter-clockwise ring comes back EMPTY.
  # - `OpenStudio.simplify` only drops collinear points — it does NOT decimate
  #   (a 69-vertex outline stays 69 vertices at a 1 m tolerance), so `decimate`
  #   implements Douglas-Peucker to keep surface counts sane.
  #
  # SDK-only and offline, like the rest of the gem: this module takes a ring of
  # coordinates and never knows where they came from. Fetching records from a
  # building-stock service, choosing a storey height, and mapping a building
  # class to space types all belong to the caller.
  module Footprint
    module_function

    # WGS84 tangent-plane constants. Exact enough at building scale: on a
    # 5,257 m2 downtown outline this reproduces the publisher's own area to
    # within 0.2%.
    M_PER_DEG_LAT = 111_132.0
    M_PER_DEG_LON_EQUATOR = 111_320.0

    # Storey heights worth naming rather than burying as magic numbers. The
    # facade default stays the gem-wide 3.8 m; these are the two other values a
    # measured-height workflow is likely to want.
    TEN_FEET = 3.048        # the OpenStudio-standards create_space_from_polygon default
    NRCAN_IMPLIED = 3.5     # implied by NRCan's own estimated_floors = round(height / 3.5)

    # Pull the outer ring out of a GeoJSON Polygon/MultiPolygon (string keys or
    # symbol keys, parsed hash or raw JSON string). Interior rings (holes) are
    # dropped — a hole would need a courtyard-style build, not an extrusion.
    #
    # @param geojson [Hash, String, Array] GeoJSON geometry, or an [[lon, lat], ...] ring
    # @return [Array<Array(Float, Float)>] outer ring as [lon, lat] pairs
    def ring_from_geojson(geojson)
      geojson = JSON.parse(geojson) if geojson.is_a?(String)
      return geojson if geojson.is_a?(Array) && geojson.first.is_a?(Array) && geojson.first.first.is_a?(Numeric)

      unless geojson.is_a?(Hash)
        raise(ArgumentError, 'expected a GeoJSON geometry Hash or an [[lon, lat], ...] ring')
      end

      geojson = geojson.transform_keys(&:to_s)
      geojson = geojson['geometry'].transform_keys(&:to_s) if geojson['geometry']
      coordinates = geojson['coordinates']
      raise(ArgumentError, 'GeoJSON geometry has no coordinates') if coordinates.nil? || coordinates.empty?

      case geojson['type'].to_s
      when 'Polygon' then coordinates.first
      when 'MultiPolygon' then coordinates.max_by { |polygon| polygon.first.size }.first
      else raise(ArgumentError, "unsupported GeoJSON type '#{geojson['type']}' (Polygon or MultiPolygon)")
      end
    end

    # Project a WGS84 ring onto a local tangent plane in metres, centred on the
    # ring's own centroid unless an origin is given. Pure trigonometry — no
    # projection library, no network.
    #
    # @param ring [Array<Array(Float, Float)>] [lon, lat] pairs (degrees)
    # @param lat0 [Float, nil] tangent-point latitude (defaults to ring centroid)
    # @param lon0 [Float, nil] tangent-point longitude (defaults to ring centroid)
    # @return [Array<OpenStudio::Point3d>] planar points at z = 0
    def project(ring, lat0: nil, lon0: nil)
      raise(ArgumentError, 'a footprint ring needs at least 3 coordinates') if ring.size < 3

      lat0 ||= ring.sum { |_lon, lat| lat } / ring.size.to_f
      lon0 ||= ring.sum { |lon, _lat| lon } / ring.size.to_f
      m_per_deg_lon = M_PER_DEG_LON_EQUATOR * Math.cos(lat0 * Math::PI / 180.0)
      ring.map do |lon, lat|
        OpenStudio::Point3d.new((lon - lon0) * m_per_deg_lon, (lat - lat0) * M_PER_DEG_LAT, 0.0)
      end
    end

    # Shoelace signed area. Positive = counter-clockwise viewed from above,
    # negative = clockwise (which is what the SDK wants everywhere below).
    def signed_area(points)
      points.each_with_index.sum do |point, index|
        next_point = points[(index + 1) % points.size]
        (point.x * next_point.y) - (next_point.x * point.y)
      end / 2.0
    end

    def area(points)
      signed_area(points).abs
    end

    # Force clockwise-from-above winding — the orientation `Space.fromFloorPrint`,
    # `OpenStudio.removeSpikes` and `OpenStudio.buffer` all require.
    def clockwise(points)
      signed_area(points) > 0 ? points.reverse : points
    end

    def to_vector(points)
      vector = OpenStudio::Point3dVector.new
      points.each { |point| vector << point }
      vector
    end

    # Make a raw outline safe to extrude: drop the GeoJSON closing vertex and
    # any duplicates, force clockwise winding, then let the SDK strip spikes and
    # collinear points. Returns clockwise points ready for `fromFloorPrint`.
    #
    # @param points [Array<OpenStudio::Point3d>] projected ring
    # @param tolerance [Float] SDK spike/collinear tolerance in metres
    # @return [Array<OpenStudio::Point3d>]
    def normalize(points, tolerance: 0.01)
      points = points.dup
      points.pop while points.size > 1 && same_point?(points.first, points.last, tolerance)
      points = points.each_with_index.reject do |point, index|
        index.positive? && same_point?(point, points[index - 1], tolerance)
      end.map(&:first)
      raise(ArgumentError, "footprint collapsed to #{points.size} distinct vertices") if points.size < 3

      points = clockwise(points)
      despiked = OpenStudio.removeSpikes(to_vector(points), tolerance).to_a
      points = despiked if despiked.size >= 3
      simplified = OpenStudio.simplify(to_vector(points), false, tolerance).to_a
      points = simplified if simplified.size >= 3
      clockwise(points)
    end

    def same_point?(a, b, tolerance)
      (a.x - b.x).abs < tolerance && (a.y - b.y).abs < tolerance
    end

    # Douglas-Peucker decimation for a closed ring. `OpenStudio.simplify` will
    # not do this — it only removes collinear points, so a 69-vertex outline
    # survives a 1 m tolerance untouched and becomes 69 exterior walls per
    # storey. Winding and (approximate) area are preserved.
    #
    # @param points [Array<OpenStudio::Point3d>] clockwise ring
    # @param tolerance [Float] max perpendicular deviation in metres (<= 0 is a no-op)
    # @return [Array<OpenStudio::Point3d>] ring with 3+ vertices
    def decimate(points, tolerance)
      return points if tolerance.nil? || tolerance <= 0 || points.size <= 4

      # Split the closed ring into two open chains at the most distant vertex so
      # Douglas-Peucker (an open-polyline algorithm) cannot collapse the ring.
      anchor = points.first
      opposite = points.each_with_index.max_by { |point, _index| distance2(anchor, point) }.last
      first_chain = points[0..opposite]
      second_chain = points[opposite..-1] + [points.first]

      kept = douglas_peucker(first_chain, tolerance)[0..-2] +
             douglas_peucker(second_chain, tolerance)[0..-2]
      return points if kept.size < 3

      clockwise(kept)
    end

    def douglas_peucker(chain, tolerance)
      return chain if chain.size < 3

      first = chain.first
      last = chain.last
      index = nil
      furthest = 0.0
      (1..chain.size - 2).each do |i|
        deviation = perpendicular_distance(chain[i], first, last)
        if deviation > furthest
          furthest = deviation
          index = i
        end
      end
      return [first, last] if index.nil? || furthest <= tolerance

      douglas_peucker(chain[0..index], tolerance)[0..-2] + douglas_peucker(chain[index..-1], tolerance)
    end

    def distance2(a, b)
      ((a.x - b.x)**2) + ((a.y - b.y)**2)
    end

    def perpendicular_distance(point, line_start, line_end)
      dx = line_end.x - line_start.x
      dy = line_end.y - line_start.y
      length = Math.sqrt((dx * dx) + (dy * dy))
      return Math.sqrt(distance2(point, line_start)) if length < 1e-9

      (((point.x - line_start.x) * dy) - ((point.y - line_start.y) * dx)).abs / length
    end

    # Core and perimeter must tile the outline to within this fraction of its
    # area. The mitred offset below is EXACT on a convex outline (a 50x30
    # rectangle tiles to 1500.0000 m2), but adjacent perimeter quads overlap at
    # reflex corners, and a noisy outline has many: the 69-vertex downtown
    # outline this module was built against has 33 reflex corners and overlaps
    # by 1.28% raw, 0.26% decimated at 2 m, and 0.00% at 4 m. Rather than ship
    # overlapping spaces, the offset self-polices and the caller decimates
    # harder or accepts single-zone storeys.
    TILING_TOLERANCE = 0.005

    # What a caller can actually do about a rejection, in order of usefulness.
    # Lowering perimeter_zone_depth is the real lever and costs NO area
    # fidelity: over 40 consecutive NRCan records, core/perimeter succeeded on 6
    # at the 15 ft default, 12 at 9.8 ft and 20 at 6.6 ft with the outlines held
    # identical. Raising decimate_tolerance is the weak lever — 6 -> 12 at 4 m,
    # and only 16 at a destructive 10 m (45% worst-case area loss).
    ZONING_HINT = 'lower perimeter_zone_depth, raise decimate_tolerance, or use zoning: :single'.freeze

    # Cut windows into every exterior wall to hit a window-to-wall ratio.
    #
    # PURE GEOMETRY, and deliberately so. There is NO default ratio and no code
    # knowledge here: NECB's FDWR maximum is an `openstudio-envelope` concern
    # (`NECB.max_fdwr(vintage:, hdd:)`, article 3.2.1.4), and this gem carries no
    # NECB rules data by family contract. Callers pass a number they chose.
    #
    # This exists because the envelope pass CANNOT seed itself: it retargets
    # EXISTING subsurface constructions, so on measured massing — which has zero
    # windows and zero constructions — `apply_prescriptive(apply_fdwr: true)`
    # silently produces 0 subsurfaces. Cutting the openings first gives it
    # something to retarget.
    #
    # `ratio` may be a single Float, or a Hash keyed by compass bin
    # ('North'/'East'/'South'/'West') for orientation-specific glazing — the
    # natural companion to orientation-merged zoning. Bins left out of the hash
    # get no windows.
    #
    # @param model [OpenStudio::Model::Model]
    # @param ratio [Float, Hash{String=>Float}] window-to-wall ratio(s), 0..1
    # @param audit [AuditLog, nil]
    # @return [Hash] { walls:, glazed:, refused:, fdwr: achieved ratio }
    def apply_wwr(model, ratio, audit: nil)
      ratios = ratio.is_a?(Hash) ? ratio.transform_keys(&:to_s) : nil
      if ratios.nil? && !(ratio.is_a?(Numeric) && ratio >= 0.0 && ratio < 1.0)
        raise(ArgumentError, "wwr must be a Float in [0, 1) or a Hash of them, got #{ratio.inspect}")
      end
      if ratios&.any? { |_k, v| !(v.is_a?(Numeric) && v >= 0.0 && v < 1.0) }
        raise(ArgumentError, "every wwr in #{ratio.inspect} must be a Float in [0, 1)")
      end

      walls = model.getSurfaces.select do |surface|
        surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'
      end
      glazed = 0
      refused = []
      walls.sort_by(&:nameString).each do |surface|
        target = ratios ? ratios[wall_orientation(surface)] : ratio
        next if target.nil? || target <= 0.0

        # setWindowToWallRatio refuses walls it cannot cut cleanly (too small,
        # non-vertical, degenerate). It returns an empty Optional rather than
        # raising, so a silent skip is the danger here, not a crash.
        if surface.setWindowToWallRatio(target).is_initialized
          glazed += 1
        else
          refused << surface.nameString
        end
      end

      wall_area = walls.sum { |s| s.grossArea * space_multiplier(s) }
      window_area = walls.sum { |s| s.subSurfaces.sum(&:netArea) * space_multiplier(s) }
      achieved = wall_area.positive? ? window_area / wall_area : 0.0

      unless refused.empty?
        audit&.warn(:geometry, 'walls refused glazing — the achieved ratio is below target',
                    inputs: { refused: refused.size, walls: walls.size,
                              examples: refused.first(3) })
      end
      audit&.decision(:geometry, 'windows cut to a caller-specified ratio',
                      inputs: { requested: ratio, walls: walls.size, glazed: glazed,
                                refused: refused.size },
                      value: "achieved WWR #{achieved.round(4)}")
      { walls: walls.size, glazed: glazed, refused: refused.size, fdwr: achieved }
    end

    # Compass bin of a wall, from the SDK's own azimuth.
    def wall_orientation(surface)
      ORIENTATIONS[((((surface.azimuth * 180.0 / Math::PI) + 45.0) % 360.0) / 90.0).floor]
    end

    def space_multiplier(surface)
      space = surface.space
      space.is_initialized ? space.get.multiplier : 1
    end

    # Compass bins for perimeter grouping, N/E/S/W on 45 degree boundaries.
    ORIENTATIONS = %w[North East South West].freeze

    # Outward-normal azimuth of the wall standing on edge a->b, in degrees
    # clockwise from north — the same convention as `Surface#azimuth`.
    #
    # For a clockwise ring the interior lies to the RIGHT of travel (the rule
    # `offset_edge` already relies on), so the inward normal is (dy, -dx) and
    # the outward normal is (-dy, dx). Verified against the SDK on a rectangle:
    # `Surface#azimuth` reports 270/0/90/180 for the four walls and this returns
    # exactly the same four numbers.
    def edge_azimuth(a, b)
      (Math.atan2(-(b.y - a.y), b.x - a.x) * 180.0 / Math::PI) % 360.0
    end

    # Compass bin for an edge: North is [315, 45), then East, South, West.
    def edge_orientation(a, b)
      ORIENTATIONS[(((edge_azimuth(a, b) + 45.0) % 360.0) / 90.0).floor]
    end

    # Signed interior angle at vertex i, in radians. Greater than pi means a
    # reflex (concave) corner.
    def interior_angle(points, index)
      count = points.size
      previous = points[(index - 1) % count]
      current = points[index]
      following = points[(index + 1) % count]
      v1 = [previous.x - current.x, previous.y - current.y]
      v2 = [following.x - current.x, following.y - current.y]
      cross = ((current.x - previous.x) * (following.y - current.y)) -
              ((current.y - previous.y) * (following.x - current.x))
      dot = (v1[0] * v2[0]) + (v1[1] * v2[1])
      magnitude = Math.hypot(*v1) * Math.hypot(*v2)
      return Math::PI if magnitude < 1e-12

      angle = Math.acos((dot / magnitude).clamp(-1.0, 1.0))
      cross.positive? ? (2 * Math::PI) - angle : angle
    end

    # THE definition of an outline "clean enough" for core-and-perimeter
    # zoning, and the largest perimeter depth it can carry.
    #
    # Offsetting inward shortens every wall run from both ends: a corner with
    # interior angle t eats D/tan(t/2) off the edges meeting there. So edge i of
    # length L survives only while
    #
    #     L > D * (cot(t_i / 2) + cot(t_i+1 / 2))
    #
    # and the outline's ceiling is the smallest depth any edge allows. Reflex
    # corners contribute a NEGATIVE term — they lengthen the offset edge — which
    # is why concavity per se is harmless and vertex count is not the criterion.
    # For the ordinary case of two convex right angles the term is 2D, i.e. at
    # the 15 ft default NO wall run shorter than 9.14 m can carry a perimeter
    # zone. Measured across 40 consecutive NRCan records this separates
    # perfectly: every outline the full offset accepted had margin +2.03 m or
    # better, every one it rejected was negative.
    #
    # @param points [Array<OpenStudio::Point3d>] clockwise ring
    # @return [Float] largest viable perimeter_zone_depth in metres
    def max_perimeter_depth(points)
      count = points.size
      return Float::INFINITY if count < 3

      (0...count).map do |i|
        length = Math.hypot(points[(i + 1) % count].x - points[i].x,
                            points[(i + 1) % count].y - points[i].y)
        consumed = (1.0 / Math.tan(interior_angle(points, i) / 2.0)) +
                   (1.0 / Math.tan(interior_angle(points, (i + 1) % count) / 2.0))
        consumed > 1e-9 ? length / consumed : Float::INFINITY
      end.min
    end

    # The perimeter depth building codes actually mean: 15 ft, the daylit /
    # skin-influenced band. `auto_perimeter_depth` only ever reduces it.
    CONVENTIONAL_DEPTH = 4.57

    # Floor on the automatic reduction, ~10 ft: the thinnest band that still
    # reads as a daylit / skin-influenced perimeter rather than a construction
    # line offset. It is also where spurious cores stop appearing — across 46
    # NRCan records, dropping the floor to 1 m starts handing core-and-perimeter
    # zoning to 55 m2 houses, which are all perimeter in reality; at 3 m the
    # smallest outline that still zones is 104 m2 and the median depth returns
    # to the full 15 ft convention. Below this, callers get :single, which is
    # the physically honest answer for a small building.
    MIN_USEFUL_DEPTH = 3.0

    # A core smaller than this fraction of the floor is a sliver, not a core —
    # the zoning adds surfaces without adding information. NOT an invented
    # number: the ported `create_shape_rectangle` already refuses core/perimeter
    # unless BOTH plan dimensions exceed 2.5x the depth, which for a square is
    # exactly a ((2.5 - 2) / 2.5)^2 = 4% core. Same convention, generalized to
    # arbitrary outlines.
    MIN_CORE_FRACTION = 0.04

    # Perimeter depth fitted to the outline rather than to the building's size.
    #
    # Footprint SIZE is not usable here — measured over 40 consecutive NRCan
    # records, the correlation between sqrt(area) and the depth an outline can
    # carry is +0.198 (log-log +0.069), i.e. none: the ceiling is set by the
    # SHORTEST WALL RUN, a local detail feature, and buildings under 15 m across
    # had a HIGHER median ceiling (2.88 m) than 30-50 m ones (1.66 m). Scaling
    # depth with size would be guessing.
    #
    # What is usable is the outline's own measured ceiling. This keeps the
    # conventional 15 ft wherever the geometry allows it and backs off only
    # where it must — raising the zoned share of that batch from 6/40 to 14/40
    # while 6 buildings keep the full 15 ft. The 5% headroom keeps the binding
    # wall run off the exact boundary.
    #
    # @param points [Array<OpenStudio::Point3d>] clockwise ring
    # @param convention [Float] the depth to use when geometry permits
    # @return [Float, nil] usable depth, or nil when even the minimum will not fit
    def auto_perimeter_depth(points, convention: CONVENTIONAL_DEPTH)
      depth = [convention, max_perimeter_depth(points) * 0.95].min
      depth >= MIN_USEFUL_DEPTH ? depth : nil
    end

    # Core-and-perimeter zoning for an arbitrary outline, by mitred inward
    # offset: every outer edge is pushed inward by `depth` and adjacent offset
    # lines are intersected, so the inner ring has the SAME vertex count as the
    # outer one and outer edge i maps to perimeter zone i.
    #
    # Never returns a broken layout. When the offset is not viable — outline too
    # narrow for a core, mitre blow-up at a reflex corner, parallel adjacent
    # edges, or pieces that do not tile — it reports why, and the caller falls
    # back to single-zone storeys and says so in the audit.
    #
    # @param points [Array<OpenStudio::Point3d>] clockwise ring
    # @param depth [Float] perimeter zone depth in metres
    # @return [Hash] { core:, perimeters:, tiling_error: } on success,
    #   { rejected: <reason> } otherwise
    def core_and_perimeter(points, depth)
      return { rejected: 'perimeter_zone_depth must be positive' } if depth.nil? || depth <= 0
      return { rejected: "outline has only #{points.size} vertices" } if points.size < 4

      # Cheap, exact, and precise about the fix: the binding constraint is
      # almost always a wall run too short to survive the offset from both ends.
      viable = max_perimeter_depth(points)
      if viable <= depth
        return { rejected: format('wall runs too short for a %.2f m perimeter — this outline ' \
                                  'supports perimeter_zone_depth up to %.2f m; %s',
                                  depth, viable, ZONING_HINT) }
      end

      count = points.size
      inner = []
      (0...count).each do |i|
        previous_edge = offset_edge(points[(i - 1) % count], points[i], depth)
        current_edge = offset_edge(points[i], points[(i + 1) % count], depth)
        intersection = intersect_lines(*previous_edge, *current_edge)
        return { rejected: "parallel adjacent edges at vertex #{i}" } if intersection.nil?
        if Math.sqrt(distance2(points[i], intersection)) > depth * 6.0
          return { rejected: "mitre blow-up at vertex #{i} (sharp corner) — #{ZONING_HINT}" }
        end

        inner << intersection
      end

      outer_area = area(points)
      core_area = area(inner)
      if core_area < 1.0 || core_area >= outer_area
        return { rejected: "no viable core at #{depth} m depth (outline too narrow)" }
      end
      if core_area / outer_area < MIN_CORE_FRACTION
        return { rejected: format('core would be only %.1f%% of the floor (min %.0f%%) — a sliver, ' \
                                  'not a core; %s', core_area / outer_area * 100,
                                  MIN_CORE_FRACTION * 100, ZONING_HINT) }
      end
      if signed_area(inner) * signed_area(points) <= 0
        return { rejected: "inward offset self-intersected (winding flipped) — #{ZONING_HINT}" }
      end
      # The defining property of a valid core: every core vertex stands at least
      # `depth` from every wall. Weaker tests are not enough — a symmetric
      # over-offset (each edge pushed past the far side) leaves an 8x6 outline
      # with an inverted core that is still inside the outline AND still
      # correctly wound, so it passes both the area and the winding checks
      # above. Counting violations also separates the two distinct failures:
      # EVERY corner too close means the outline is too narrow for a core at
      # all; a few means the outline is locally too spiky.
      escaped = inner.count do |point|
        !inside?(point, points) || clearance(point, points) < depth * 0.99
      end
      if escaped == inner.size
        return { rejected: "no viable core at #{depth} m depth (outline too narrow)" }
      elsif escaped.positive?
        return { rejected: "inward offset escapes the outline at #{escaped} of #{inner.size} " \
                           "sharp corners — #{ZONING_HINT}" }
      end

      perimeters = []
      (0...count).each do |i|
        quad = [points[i], points[(i + 1) % count], inner[(i + 1) % count], inner[i]]
        quad = quad.uniq { |point| [point.x.round(4), point.y.round(4)] }
        return { rejected: "degenerate perimeter zone at edge #{i}" } if quad.size < 3 || area(quad) < 0.5

        perimeters << clockwise(quad)
      end

      tiled = core_area + perimeters.sum { |quad| area(quad) }
      error = (tiled - outer_area).abs / outer_area
      if error > TILING_TOLERANCE
        return { rejected: format('perimeter zones overlap by %.2f%% — %s', error * 100, ZONING_HINT) }
      end

      { core: clockwise(inner), perimeters: perimeters, tiling_error: error,
        orientations: (0...count).map { |i| edge_orientation(points[i], points[(i + 1) % count]) } }
    end

    # Push an edge inward by `depth`. For a clockwise ring the interior lies to
    # the right of the direction of travel.
    def offset_edge(from, to, depth)
      dx = to.x - from.x
      dy = to.y - from.y
      length = Math.sqrt((dx * dx) + (dy * dy))
      return [from, to] if length < 1e-9

      normal_x = (dy / length) * depth
      normal_y = (-dx / length) * depth
      [OpenStudio::Point3d.new(from.x + normal_x, from.y + normal_y, from.z),
       OpenStudio::Point3d.new(to.x + normal_x, to.y + normal_y, to.z)]
    end

    # Distance from a point to the nearest polygon edge.
    def clearance(point, polygon)
      polygon.each_with_index.map do |a, index|
        b = polygon[(index + 1) % polygon.size]
        dx = b.x - a.x
        dy = b.y - a.y
        length2 = (dx * dx) + (dy * dy)
        if length2 < 1e-18
          Math.sqrt(distance2(point, a))
        else
          t = ((((point.x - a.x) * dx) + ((point.y - a.y) * dy)) / length2).clamp(0.0, 1.0)
          Math.sqrt(((point.x - (a.x + (t * dx)))**2) + ((point.y - (a.y + (t * dy)))**2))
        end
      end.min
    end

    # Ray-casting point-in-polygon (winding-agnostic).
    def inside?(point, polygon)
      crossings = 0
      polygon.each_with_index do |a, index|
        b = polygon[(index + 1) % polygon.size]
        next unless (a.y > point.y) != (b.y > point.y)

        x_at = a.x + (((point.y - a.y) / (b.y - a.y)) * (b.x - a.x))
        crossings += 1 if x_at > point.x
      end
      crossings.odd?
    end

    def intersect_lines(a1, a2, b1, b2)
      dx1 = a2.x - a1.x
      dy1 = a2.y - a1.y
      dx2 = b2.x - b1.x
      dy2 = b2.y - b1.y
      denominator = (dx1 * dy2) - (dy1 * dx2)
      return nil if denominator.abs < 1e-9 # parallel adjacent edges

      t = (((b1.x - a1.x) * dy2) - ((b1.y - a1.y) * dx2)) / denominator
      OpenStudio::Point3d.new(a1.x + (t * dx1), a1.y + (t * dy1), a1.z)
    end

    # Decimation tolerance scaled to the building. A fixed tolerance cannot
    # serve both ends of a real building stock: 2 m is mild on a 5,000 m2 tower
    # and destroys a 100 m2 house (measured: 14.8% of its floor area). Tying it
    # to the outline's own size holds the area loss roughly constant instead —
    # a 25th of the footprint's characteristic width, floored so tiny outlines
    # keep their shape and capped so huge ones still shed noise.
    def auto_tolerance(footprint_area)
      (Math.sqrt(footprint_area) / 25.0).clamp(0.25, 3.0)
    end

    # Number of storeys implied by a measured height. Never returns less than 1.
    def storeys_for(height_m, floor_to_floor_height)
      raise(ArgumentError, 'floor_to_floor_height must be positive') unless floor_to_floor_height.to_f.positive?

      [(height_m.to_f / floor_to_floor_height.to_f).round, 1].max
    end

    # Extrude a cleaned clockwise ring into stacked, zoned, surface-matched
    # storeys. `plan` is the {core:, perimeters:} from `core_and_perimeter`, or
    # nil for one space per storey.
    #
    # @param model [OpenStudio::Model::Model]
    # @param plan [Hash, nil] core/perimeter polygons, or nil for single-zone storeys
    # @param ring [Array<OpenStudio::Point3d>] clockwise outline (used when plan is nil)
    # @param storeys [Integer] number of above-grade storeys
    # @param floor_to_floor_height [Float] metres
    # @param multiplier [Symbol] :none (build every storey) or :mid (ground/mid/top,
    #   mid carries a thermal-zone multiplier and adiabatic floors/ceilings)
    # @return [Array<OpenStudio::Model::Space>]
    def build_massing(model, plan, ring, storeys, floor_to_floor_height, multiplier: :none)
      # Spaces stay ONE PER EDGE — that keeps the geometry exact and needs no
      # polygon union — while the thermal zone each space joins is its compass
      # bin. So a 19-edge outline yields 19 perimeter spaces but the 4 zones a
      # modeller expects. Zone membership, not geometry, is what "merge by
      # orientation" means here; a genuine polygon union would have to handle
      # non-contiguous same-facing walls (an L has two north faces) and would
      # need real clipping.
      layout = if plan
                 [['Core', plan[:core], 'Core']] +
                   plan[:perimeters].each_with_index.map do |quad, i|
                     orientation = plan[:orientations][i]
                     ["#{orientation} #{i + 1}", quad, orientation]
                   end
               else
                 [['Whole Floor', ring, 'Whole Floor']]
               end

      levels = storey_levels(storeys, floor_to_floor_height, multiplier)
      spaces = []
      levels.each do |level|
        story = OpenStudio::Model::BuildingStory.new(model)
        story.setName("Story #{level[:index]}")
        story.setNominalZCoordinate(level[:z])
        story.setNominalFloortoFloorHeight(floor_to_floor_height)

        zones = {}
        layout.each do |name, polygon, group|
          optional = OpenStudio::Model::Space.fromFloorPrint(to_vector(polygon), floor_to_floor_height, model)
          if optional.empty?
            raise("Space.fromFloorPrint rejected '#{name}' on story #{level[:index]} " \
                  '(winding or self-intersection — see the OpenStudio log)')
          end

          space = optional.get
          space.setName("Story #{level[:index]} #{name}")
          space.setZOrigin(level[:z])
          space.setBuildingStory(story)
          zone = zones[group] ||= begin
            created = OpenStudio::Model::ThermalZone.new(model)
            created.setName("Story #{level[:index]} #{group} ZN")
            created.setMultiplier(level[:multiplier])
            created
          end
          space.setThermalZone(zone)
          spaces << space
        end
      end

      Helpers.match_surfaces(model)
      apply_boundary_conditions(spaces, levels, layout.size)
      spaces
    end

    # Ground/mid/top level table. With :none every storey is real; with :mid the
    # middle storeys collapse into one multiplied storey placed at their mean
    # height (the openstudio-standards story-multiplier convention).
    def storey_levels(storeys, floor_to_floor_height, multiplier)
      if multiplier == :mid && storeys > 2
        [{ index: 0, z: 0.0, multiplier: 1, position: :bottom },
         { index: 1, z: floor_to_floor_height * ((storeys - 1) / 2.0), multiplier: storeys - 2, position: :middle },
         { index: storeys - 1, z: floor_to_floor_height * (storeys - 1), multiplier: 1, position: :top }]
      else
        (0...storeys).map do |index|
          { index: index, z: floor_to_floor_height * index, multiplier: 1,
            position: index.zero? ? :bottom : (index == storeys - 1 ? :top : :middle) }
        end
      end
    end

    # Bottom floors meet the ground; surfaces that `match_surfaces` could not
    # pair because a multiplied storey stands in for many go adiabatic rather
    # than leaking heat to Outdoors.
    def apply_boundary_conditions(spaces, levels, spaces_per_storey)
      multiplied = levels.any? { |level| level[:multiplier] > 1 }
      levels.each_with_index do |level, order|
        storey_spaces = spaces[order * spaces_per_storey, spaces_per_storey] || []
        storey_spaces.each do |space|
          space.surfaces.each do |surface|
            next if surface.outsideBoundaryCondition == 'Surface'

            if surface.surfaceType == 'Floor' && level[:position] == :bottom
              Helpers.set_boundary_condition([surface], 'Ground')
            elsif multiplied && %w[Floor RoofCeiling].include?(surface.surfaceType) &&
                  !(surface.surfaceType == 'RoofCeiling' && level[:position] == :top) &&
                  !(surface.surfaceType == 'Floor' && level[:position] == :bottom)
              Helpers.set_boundary_condition([surface], 'Adiabatic')
            end
          end
        end
      end
    end
  end
end
