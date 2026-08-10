# frozen_string_literal: true

module OpenStudioGeometry
  # The floor-plan renderer's ONLY SDK-touching file: an OpenStudio model in,
  # plain hashes out (never raises). Everything downstream — `plan_svg.rb`,
  # `plan.rb` — is SDK-free and unit-testable against hand-written hashes.
  #
  # Schema returned by {extract}:
  #
  #   { storeys: [{ name: String, z: Float,
  #                 spaces: [{ name: String, zone: String|nil,
  #                            space_type: String|nil,
  #                            polygons: [[[x, y], ...], ...],
  #                            centroid: [x, y], area_m2: Float, z: Float }] }],
  #     bounds: { min_x:, min_y:, max_x:, max_y: } | nil,
  #     inferred_storeys: Boolean,
  #     error: String (only on failure — then storeys is empty) }
  #
  # Coordinates are WORLD coordinates in metres: every floor surface is
  # transformed with `space.transformation * surface.vertices` (the bar.rb:347
  # idiom). The `space.xOrigin/yOrigin` offset shortcut is deliberately NOT
  # used — it is rotation-blind and silently draws rotated buildings unrotated.
  module PlanQuery
    module_function

    # Floor planes within this many metres are the same storey (also the
    # tolerance for "which floor surface set is the lowest one").
    Z_TOL = 0.01

    # @param model [OpenStudio::Model::Model]
    # @param audit [OpenStudioGeometry::AuditLog, nil] warnings sink (step :plan)
    # @return [Hash] the schema above; never raises
    def extract(model, audit: nil)
      pairs = model.getSpaces.sort_by(&:nameString).filter_map do |space|
        record = space_record(space, audit: audit)
        record ? [space, record] : nil
      end

      storeys, inferred = group_storeys(model, pairs, audit: audit)
      { storeys: storeys,
        bounds: bounds(model, pairs.map(&:first)),
        inferred_storeys: inferred }
    rescue StandardError => e
      audit&.warn(:plan, "floor-plan extraction failed — no plans produced (#{e.message})")
      { storeys: [], bounds: nil, inferred_storeys: false, error: e.message }
    end

    # ------------------------------------------------------------- per space

    # One space -> its plan record, or nil when the space has no floor surface
    # (audited, never silent).
    def space_record(space, audit: nil)
      polygons = floor_polygons(space)
      if polygons.empty?
        audit&.warn(:plan, 'space has no Floor surface — omitted from the floor plan',
                    target: space.nameString)
        return nil
      end

      area = polygons.sum { |ring| polygon_area(ring) }
      { name: space.nameString,
        zone: zone_name(space),
        space_type: space_type_name(space),
        polygons: polygons.map { |ring| ring.map { |x, y| [x.round(3), y.round(3)] } },
        centroid: centroid(polygons).map { |v| v.round(3) },
        area_m2: area.round(2),
        z: floor_z(space).round(3) }
    end

    # World-coordinate rings of the space's LOWEST floor plane. A space with
    # floors at several elevations (a mezzanine modelled as one space) keeps
    # only the lowest set — a plan shows one horizontal cut, not both.
    def floor_polygons(space)
      floors = space.surfaces.select { |surface| surface.surfaceType == 'Floor' }
      return [] if floors.empty?

      transformation = space.transformation
      rings = floors.map do |surface|
        points = (transformation * surface.vertices).map { |p| [p.x, p.y, p.z] }
        [points.map { |p| p[2] }.min, points.map { |p| [p[0], p[1]] }]
      end
      lowest = rings.map(&:first).min
      rings.select { |z, _| (z - lowest).abs <= Z_TOL }.map(&:last).reject { |ring| ring.size < 3 }
    end

    # World z of the space's lowest floor plane (the storey-binning key).
    def floor_z(space)
      transformation = space.transformation
      space.surfaces.select { |s| s.surfaceType == 'Floor' }
           .flat_map { |s| (transformation * s.vertices).map(&:z) }.min.to_f
    end

    def zone_name(space)
      zone = space.thermalZone
      zone.is_initialized ? zone.get.nameString : nil
    end

    # Standards tags first ("Space Function | Office enclosed > 25 m2"), plain
    # SpaceType name as the fallback, nil when the space is untyped.
    def space_type_name(space)
      space_type = space.spaceType
      return nil unless space_type.is_initialized

      space_type = space_type.get
      standards = space_type.standardsSpaceType
      return space_type.nameString unless standards.is_initialized

      building = space_type.standardsBuildingType
      building.is_initialized ? "#{building.get} | #{standards.get}" : standards.get
    end

    # ----------------------------------------------------------- storeys

    # @return [Array(Array<Hash>, Boolean)] storey groups (display order = min
    #   world z) and whether they had to be inferred from floor elevations.
    def group_storeys(model, pairs, audit: nil)
      stories = model.getBuildingStorys
      orphans = pairs.count { |space, _| !space.buildingStory.is_initialized }

      if stories.empty? || orphans.positive?
        reason = stories.empty? ? 'the model has no BuildingStory objects' : "#{orphans} space(s) have no building storey"
        audit&.warn(:plan, "storeys inferred from floor elevations — #{reason}",
                    inputs: { spaces: pairs.size, building_storeys: stories.size })
        return [infer_storeys(pairs), true]
      end

      groups = stories.sort_by(&:nameString).filter_map do |story|
        handle = story.handle.to_s
        records = pairs.select { |space, _| space.buildingStory.get.handle.to_s == handle }.map(&:last)
        next if records.empty?

        { name: story.nameString, z: records.map { |r| r[:z] }.min, spaces: records }
      end
      [groups.sort_by { |group| group[:z] }, false]
    end

    # Fallback grouping: bin the space records by floor-plane world z (±Z_TOL)
    # and synthesize `Level N` names bottom-up.
    def infer_storeys(pairs)
      bins = []
      pairs.map(&:last).sort_by { |record| record[:z] }.each do |record|
        bin = bins.find { |b| (b[:z] - record[:z]).abs <= Z_TOL }
        bin ? bin[:spaces] << record : bins << { z: record[:z], spaces: [record] }
      end
      bins.sort_by { |bin| bin[:z] }.each_with_index.map do |bin, index|
        { name: "Level #{index + 1}", z: bin[:z],
          spaces: bin[:spaces].sort_by { |record| record[:name] } }
      end
    end

    # ----------------------------------------------------------- geometry

    # Plan extents over every transformed floor point (the bar.rb:344-352
    # BoundingBox idiom). nil when nothing was extracted.
    def bounds(_model, spaces)
      box = OpenStudio::BoundingBox.new
      spaces.each do |space|
        transformation = space.transformation
        space.surfaces.select { |s| s.surfaceType == 'Floor' }.each do |surface|
          box.addPoints(transformation * surface.vertices)
        end
      end
      return nil unless box.minX.is_initialized

      { min_x: box.minX.get.round(3), min_y: box.minY.get.round(3),
        max_x: box.maxX.get.round(3), max_y: box.maxY.get.round(3) }
    end

    # Shoelace area of a closed ring (absolute — winding order is irrelevant
    # for a plan).
    def polygon_area(ring)
      sum = 0.0
      ring.each_with_index do |(x1, y1), index|
        x2, y2 = ring[(index + 1) % ring.size]
        sum += (x1 * y2) - (x2 * y1)
      end
      (sum / 2.0).abs
    end

    # Area-weighted centroid over the space's rings; degenerate rings fall back
    # to the vertex average so a label always has somewhere to go.
    def centroid(rings)
      total = 0.0
      cx = 0.0
      cy = 0.0
      rings.each do |ring|
        area = polygon_area(ring)
        next if area.zero?

        rx, ry = ring_centroid(ring)
        total += area
        cx += rx * area
        cy += ry * area
      end
      return [cx / total, cy / total] if total.positive?

      points = rings.flatten(1)
      return [0.0, 0.0] if points.empty?

      [points.sum { |p| p[0] } / points.size, points.sum { |p| p[1] } / points.size]
    end

    def ring_centroid(ring)
      cross_sum = 0.0
      cx = 0.0
      cy = 0.0
      ring.each_with_index do |(x1, y1), index|
        x2, y2 = ring[(index + 1) % ring.size]
        cross = (x1 * y2) - (x2 * y1)
        cross_sum += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
      end
      return [ring.sum { |p| p[0] } / ring.size, ring.sum { |p| p[1] } / ring.size] if cross_sum.zero?

      [cx / (3.0 * cross_sum), cy / (3.0 * cross_sum)]
    end
  end
end
