require 'openstudio'

require_relative 'openstudio_geometry/version'
require_relative 'openstudio_geometry/audit_log'
require_relative 'openstudio_geometry/helpers'
require_relative 'openstudio_geometry/footprint'
require_relative 'openstudio_geometry/wizards'
require_relative 'openstudio_geometry/bar'
require_relative 'openstudio_geometry/render'
require_relative 'openstudio_geometry/plan_query'
require_relative 'openstudio_geometry/plan_svg'
require_relative 'openstudio_geometry/plan'

# OpenStudioGeometry creates parametric building geometry — the authoring
# on-ramp for the gem family (and the future MCP surface): footprint wizards
# (rectangle, aspect-ratio, courtyard, H, L, T, U) with perimeter/core zoning,
# below-grade storeys, and matched surfaces. SDK-only; shared AuditLog schema.
#
# Downstream: OpenStudioLoads.assign_space_types + apply_loads,
# OpenStudioLighting.apply_lights, OpenStudioSHW.apply_shw,
# OpenStudioHVAC.build_system, OpenStudioEnvelope prescriptive/reference,
# OpenStudioNECB.performance_compliance.
module OpenStudioGeometry
  SHAPES = %w[rectangle aspect_ratio courtyard h l t u].freeze

  # Canonical facade vocabulary (`storeys:` / `below_grade_storeys:`) mapped to
  # the spellings the verbatim-ported engines actually take. The engines keep
  # their upstream names, so the mapping differs per entry point: `create`'s
  # rectangle path takes above/under_ground_storys, every other shape takes a
  # single num_floors, and the bar engine takes num_stories_*_grade. Aliases are
  # resolved BEFORE `ordered`'s unknown-parameter check; the old names keep
  # working unchanged, and passing an alias together with its target raises.
  CREATE_ALIASES = { 'rectangle' => { storeys: :above_ground_storys,
                                      below_grade_storeys: :under_ground_storys } }.freeze
  CREATE_ALIASES_DEFAULT = { storeys: :num_floors }.freeze

  # Keyword-friendly facade over the wizards. Returns the model (a fresh one is
  # created when none is given); every call is audited with the full parameter
  # set so downstream QAQC can reproduce the massing.
  #
  #   OpenStudioGeometry.create(shape: 'rectangle', length: 40, width: 25,
  #                             storeys: 3, below_grade_storeys: 1, audit: audit)
  #
  # `storeys:`/`below_grade_storeys:` are the canonical spellings; the engines'
  # own names (above_ground_storys, under_ground_storys, num_floors) are still
  # accepted. Only the rectangle shape has below-grade storeys.
  def self.create(shape:, model: nil, audit: nil, **params)
    audit ||= AuditLog.new
    model ||= OpenStudio::Model::Model.new
    shape = shape.to_s.downcase
    raise(ArgumentError, "unknown shape '#{shape}' (#{SHAPES.join(', ')})") unless SHAPES.include?(shape)

    params = normalize_storey_aliases(params, shape)

    result = case shape
             when 'rectangle'
               Wizards.create_shape_rectangle(model,
                                              *ordered(params, %i[length width above_ground_storys under_ground_storys
                                                                  floor_to_floor_height plenum_height perimeter_zone_depth
                                                                  initial_height],
                                               [100.0, 100.0, 3, 1, 3.8, 1.0, 4.57, 0.0]))
             when 'aspect_ratio'
               Wizards.create_shape_aspect_ratio(model,
                                                 *ordered(params, %i[aspect_ratio floor_area rotation num_floors
                                                                     floor_to_floor_height plenum_height perimeter_zone_depth],
                                                  [0.5, 1000.0, 0.0, 3, 3.8, 1.0, 4.57]))
             when 'courtyard'
               Wizards.create_shape_courtyard(model,
                                              *ordered(params, %i[length width courtyard_length courtyard_width
                                                                  num_floors floor_to_floor_height plenum_height
                                                                  perimeter_zone_depth],
                                               [50.0, 30.0, 15.0, 5.0, 3, 3.8, 1.0, 4.57]))
             when 'h'
               Wizards.create_shape_h(model,
                                      *ordered(params, %i[length left_width center_width right_width left_end_length
                                                          right_end_length left_upper_end_offset right_upper_end_offset
                                                          num_floors floor_to_floor_height plenum_height
                                                          perimeter_zone_depth],
                                       [40.0, 40.0, 10.0, 40.0, 15.0, 15.0, 15.0, 15.0, 3, 3.8, 1.0, 4.57]))
             when 'l'
               Wizards.create_shape_l(model,
                                      *ordered(params, %i[length width lower_end_width upper_end_length
                                                          num_floors floor_to_floor_height plenum_height
                                                          perimeter_zone_depth],
                                       [40.0, 40.0, 20.0, 20.0, 3, 3.8, 1.0, 4.57]))
             when 't'
               Wizards.create_shape_t(model,
                                      *ordered(params, %i[length width upper_end_width lower_end_length
                                                          left_end_offset num_floors floor_to_floor_height
                                                          plenum_height perimeter_zone_depth],
                                       [40.0, 40.0, 20.0, 20.0, 10.0, 3, 3.8, 1.0, 4.57]))
             when 'u'
               Wizards.create_shape_u(model,
                                      *ordered(params, %i[length left_width right_width left_end_length
                                                          right_end_length left_end_offset num_floors
                                                          floor_to_floor_height plenum_height perimeter_zone_depth],
                                       [40.0, 40.0, 40.0, 15.0, 15.0, 25.0, 3, 3.8, 1.0, 4.57]))
             end
    raise(ArgumentError, "#{shape} wizard rejected the parameters (see the OpenStudio log)") if result.nil?

    # defaults mirror the per-shape defaults arrays above
    storeys_above = params.fetch(:above_ground_storys) { params.fetch(:num_floors, 3) }
    storeys_below = params.fetch(:under_ground_storys) { shape == 'rectangle' ? 1 : 0 }
    audit.decision(:geometry, "#{shape} massing created",
                   inputs: params.merge(shape: shape,
                                        spaces: model.getSpaces.size,
                                        storeys_above: storeys_above,
                                        storeys_below: storeys_below))
    model
  end

  # Measured-footprint entry: a real building outline plus a measured height in,
  # zoned massing out. A peer of `create`, deliberately NOT a member of SHAPES —
  # `create` dispatches positional scalars (length, width, ...) through
  # `ordered`, and a coordinate ring is not that shape.
  #
  #   OpenStudioGeometry.create_from_footprint(
  #     geojson: record['geometry_geojson'], height_m: record['height_max_m'],
  #     floor_to_floor_height: OpenStudioGeometry::Footprint::TEN_FEET,
  #     source: { feature_id: record['feature_id'], dataset: 'nrcan-buildings' })
  #
  # Storey count is derived from the measured height unless `storeys:` is given.
  # Because a measured massing is only reproducible if you record what it was
  # measured from, the audit entry carries the full provenance: `source:`, which
  # height went in, the storey height assumed, the decimation tolerance, and the
  # zoning that was actually achieved (`core_perimeter` degrades to `single`
  # with a warning when the outline cannot carry a core).
  #
  # @param geojson [Hash, String, Array, nil] GeoJSON Polygon/MultiPolygon or [[lon, lat], ...] ring
  # @param points [Array<OpenStudio::Point3d>, nil] already-projected metres (skips projection)
  # @param height_m [Float, nil] measured height; required unless `storeys:` is given
  # @param storeys [Integer, nil] explicit storey count, overriding the measured height
  # @param floor_to_floor_height [Float] metres (3.8 gem-wide default; see
  #   Footprint::TEN_FEET 3.048 and Footprint::NRCAN_IMPLIED 3.5)
  # @param zoning [Symbol] :core_perimeter (default) or :single
  # @param perimeter_zone_depth [Float, :auto] metres. :auto (default) keeps the
  #   15 ft convention wherever the outline can carry it and reduces it only
  #   where it cannot, warning whenever it does. Footprint SIZE is deliberately
  #   NOT an input — measured, it does not predict what an outline can carry
  # @param decimate_tolerance [Float, :auto] Douglas-Peucker tolerance in metres;
  #   0 disables. :auto (default) scales it to the outline's own size — a fixed
  #   tolerance either leaves towers noisy or destroys small buildings
  # @param multiplier [Symbol] :none (every storey real) or :mid (ground/mid/top)
  # @param origin [Array(Float, Float), nil] [lat, lon] tangent point; defaults to the ring centroid
  # @param source [Hash] free-form provenance recorded verbatim in the audit
  # @return [OpenStudio::Model::Model]
  def self.create_from_footprint(geojson: nil, points: nil, height_m: nil, storeys: nil,
                                 floor_to_floor_height: 3.8, zoning: :core_perimeter,
                                 perimeter_zone_depth: :auto, decimate_tolerance: :auto,
                                 multiplier: :none, origin: nil, source: {},
                                 model: nil, audit: nil)
    audit ||= AuditLog.new
    model ||= OpenStudio::Model::Model.new
    raise(ArgumentError, 'pass either geojson: or points:, not both') if geojson && points
    raise(ArgumentError, 'a footprint needs geojson: or points:') if geojson.nil? && points.nil?
    raise(ArgumentError, 'pass height_m: or storeys:') if height_m.nil? && storeys.nil?
    unless %i[core_perimeter single].include?(zoning)
      raise(ArgumentError, "unknown zoning '#{zoning}' (core_perimeter, single)")
    end
    unless %i[none mid].include?(multiplier)
      raise(ArgumentError, "unknown multiplier '#{multiplier}' (none, mid)")
    end

    if geojson
      ring = Footprint.ring_from_geojson(geojson)
      centroid_lat = origin ? origin[0] : ring.sum { |_lon, lat| lat } / ring.size.to_f
      centroid_lon = origin ? origin[1] : ring.sum { |lon, _lat| lon } / ring.size.to_f
      points = Footprint.project(ring, lat0: centroid_lat, lon0: centroid_lon)
      model.getSite.setLatitude(centroid_lat)
      model.getSite.setLongitude(centroid_lon)
    end

    raw_vertices = points.size
    outline = Footprint.normalize(points)
    if decimate_tolerance == :auto
      decimate_tolerance = Footprint.auto_tolerance(Footprint.area(outline)).round(2)
    end
    outline = Footprint.decimate(outline, decimate_tolerance)
    footprint_area = Footprint.area(outline)

    storeys ||= Footprint.storeys_for(height_m, floor_to_floor_height)
    raise(ArgumentError, 'storeys must be at least 1') if storeys < 1

    if perimeter_zone_depth == :auto
      perimeter_zone_depth = (Footprint.auto_perimeter_depth(outline) || Footprint::MIN_USEFUL_DEPTH).round(2)
      if zoning == :core_perimeter && perimeter_zone_depth < Footprint::CONVENTIONAL_DEPTH
        # Never silently: a reduced band is no longer the code's daylit zone.
        audit.warn(:geometry, 'perimeter zone depth reduced below the 15 ft convention to fit the outline',
                   inputs: { perimeter_zone_depth: perimeter_zone_depth,
                             conventional_depth: Footprint::CONVENTIONAL_DEPTH,
                             outline_ceiling_m: Footprint.max_perimeter_depth(outline).round(2) }.merge(source))
      end
    end

    plan = zoning == :core_perimeter ? Footprint.core_and_perimeter(outline, perimeter_zone_depth) : nil
    if plan && plan[:rejected]
      audit.warn(:geometry, 'core-and-perimeter zoning not viable for this outline — single zone per storey',
                 inputs: { reason: plan[:rejected], perimeter_zone_depth: perimeter_zone_depth,
                           vertices: outline.size, decimate_tolerance: decimate_tolerance,
                           footprint_area_m2: footprint_area.round(1) }.merge(source))
      plan = nil
    end
    achieved_zoning = plan ? :core_perimeter : :single

    spaces = Footprint.build_massing(model, plan, outline, storeys, floor_to_floor_height, multiplier: multiplier)

    audit.decision(:geometry, 'measured-footprint massing created',
                   inputs: { vertices_raw: raw_vertices, vertices_used: outline.size,
                             decimate_tolerance: decimate_tolerance,
                             footprint_area_m2: footprint_area.round(1),
                             height_m: height_m, floor_to_floor_height: floor_to_floor_height,
                             storeys_above: storeys, storeys_below: 0,
                             modelled_height_m: (storeys * floor_to_floor_height).round(2),
                             zoning: achieved_zoning, requested_zoning: zoning,
                             # nil when no perimeter zoning happened — reporting the
                             # depth that was tried and rejected reads as if it applied
                             perimeter_zone_depth: achieved_zoning == :core_perimeter ? perimeter_zone_depth : nil,
                             multiplier: multiplier, spaces: spaces.size }.merge(source),
                   value: "#{footprint_area.round(1)} m2 x #{storeys} storeys")
    model
  end

  # Cut windows into every exterior wall to a caller-chosen window-to-wall
  # ratio. There is NO default and no code knowledge — see Footprint.apply_wwr.
  #
  #   OpenStudioGeometry.apply_wwr(model, 0.35)
  #   OpenStudioGeometry.apply_wwr(model, 'South' => 0.4, 'North' => 0.2)
  #
  # For the NECB maximum use openstudio-envelope, which owns the rule:
  #
  #   limit = OpenStudioEnvelope::NECB.max_fdwr(vintage: '2020', hdd: hdd)
  #   OpenStudioGeometry.apply_wwr(model, limit)
  #
  # @param model [OpenStudio::Model::Model]
  # @param wwr [Float, Hash{String=>Float}] ratio(s) in [0, 1), optionally per
  #   compass bin ('North'/'East'/'South'/'West')
  # @return [Hash] { walls:, glazed:, refused:, fdwr: }
  # `bins` catches the brace-less hash form: with an `audit:` keyword in the
  # signature Ruby 3 parses `apply_wwr(model, 'South' => 0.4)` as keywords, not
  # as a positional Hash, so accepting both spellings avoids a silent ArgumentError.
  def self.apply_wwr(model, wwr = nil, audit: nil, **bins)
    ratio = wwr.nil? && !bins.empty? ? bins : wwr
    raise(ArgumentError, 'pass a window-to-wall ratio: a Float, or per-orientation bins') if ratio.nil?

    Footprint.apply_wwr(model, ratio, audit: audit || AuditLog.new)
  end

  # The family-native bar entry: sliced bar massing with NECB space types
  # assigned by ratio in ONE step — geometry AND standards tagging, ready for
  # OpenStudioLoads.apply_loads without a separate assign_space_types call.
  # (The upstream DOE/DEER ratio wrappers are not ported; this replaces them
  # for the NECB family.)
  #
  #   OpenStudioGeometry.bar(
  #     space_type_ratios: { ['Space Function', 'Office enclosed > 25 m2'] => 0.7,
  #                          ['Space Function', 'Corridor/Transition area other-sch-A'] => 0.3 },
  #     length: 50.0, width: 20.0, storeys: 3, wwr: 0.4)
  #
  # @param space_type_ratios [Hash{Array(String,String)=>Numeric}] (building_type,
  #   space_type) pairs => floor-area ratios (normalized internally)
  # @param storeys [Integer] canonical spelling of num_stories_above_grade (3)
  # @param below_grade_storeys [Integer] canonical spelling of num_stories_below_grade (0)
  # @param division_method ['Multiple Space Types - Simple Sliced',
  #   'Multiple Space Types - Individual Stories Sliced', 'Single Space Type - Core and Perimeter']
  def self.bar(space_type_ratios:, model: nil, length: 50.0, width: 20.0,
               storeys: nil, below_grade_storeys: nil,
               num_stories_above_grade: nil, num_stories_below_grade: nil,
               floor_height: 3.8, wwr: 0.4,
               division_method: 'Multiple Space Types - Simple Sliced',
               story_multiplier_method: 'None',
               make_mid_story_surfaces_adiabatic: false,
               party_wall_fraction: 0.0,
               party_wall_stories_north: 0, party_wall_stories_south: 0,
               party_wall_stories_east: 0, party_wall_stories_west: 0,
               bottom_story_ground_exposed_floor: true,
               top_story_exterior_exposed_roof: true,
               audit: nil)
    audit ||= AuditLog.new
    model ||= OpenStudio::Model::Model.new
    raise(ArgumentError, 'space_type_ratios must not be empty') if space_type_ratios.empty?

    num_stories_above_grade = resolve_alias(:storeys, storeys, :num_stories_above_grade, num_stories_above_grade, 3)
    num_stories_below_grade = resolve_alias(:below_grade_storeys, below_grade_storeys,
                                            :num_stories_below_grade, num_stories_below_grade, 0)

    num_stories = num_stories_below_grade + num_stories_above_grade
    total_area = length * width * num_stories
    ratio_sum = space_type_ratios.values.sum.to_f
    space_types_hash = {}
    space_type_ratios.each do |(building_type, space_type_name), ratio|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName("#{building_type} #{space_type_name}")
      space_type.setStandardsBuildingType(building_type)
      space_type.setStandardsSpaceType(space_type_name)
      space_types_hash[space_type] = { floor_area: total_area * ratio / ratio_sum }
    end

    args = { num_stories_below_grade: num_stories_below_grade,
             num_stories_above_grade: num_stories_above_grade,
             bar_division_method: division_method,
             story_multiplier_method: story_multiplier_method,
             make_mid_story_surfaces_adiabatic: make_mid_story_surfaces_adiabatic,
             wwr: wwr,
             party_wall_fraction: party_wall_fraction,
             party_wall_stories_north: party_wall_stories_north,
             party_wall_stories_south: party_wall_stories_south,
             party_wall_stories_east: party_wall_stories_east,
             party_wall_stories_west: party_wall_stories_west,
             bottom_story_ground_exposed_floor: bottom_story_ground_exposed_floor,
             top_story_exterior_exposed_roof: top_story_exterior_exposed_roof }

    result = Bar.bar_hash_setup_run(model, args, length, width, floor_height,
                                    OpenStudio::Point3d.new(0, 0, 0), space_types_hash, num_stories)
    raise('bar creation failed (see the OpenStudio log)') if result == false

    audit.decision(:geometry, 'sliced bar massing created with NECB space types assigned by ratio',
                   inputs: { length: length, width: width, wwr: wwr,
                             storeys_above: num_stories_above_grade, storeys_below: num_stories_below_grade,
                             division_method: division_method,
                             space_types: space_type_ratios.keys.map { |bt, st| "#{bt}|#{st}" },
                             spaces: model.getSpaces.size })
    model
  end

  # 3D viewer facade (campus-repo renderer port): Model or .osm path in,
  # self-contained HTML fragment out (glTF embedded as a base64 data URI,
  # crash-isolated export with the campus fallback ladder). Writes a complete
  # standalone page to `path:` when given; returns the fragment either way
  # ('' when the model is unrenderable — audited, never raises).
  #
  #   OpenStudioGeometry.render(model, path: 'building_3d.html')
  def self.render(model_or_path, path: nil, height: 480, work_dir: nil, audit: nil)
    audit ||= AuditLog.new
    fragment = Render.geometry_viewer(model_or_path, height: height, work_dir: work_dir, audit: audit)
    if path && !fragment.empty?
      File.write(path, "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" \
                       '<title>Building geometry</title></head><body ' \
                       "style=\"font-family:system-ui,sans-serif;margin:24px\">#{fragment}</body></html>")
    end
    fragment
  end

  # Per-storey floor plans (the 2D counterpart to `render`): Model or .osm path
  # in, a plain-hash bundle of inline SVG strings out — one plan per storey plus
  # a shared thermal-zone legend. Spaces are drawn in world coordinates, tinted
  # by thermal zone, labelled with space + zone name, and every polygon carries
  # a `space | zone | space type | area` hover tooltip. Never raises: an
  # unreadable or floor-less model comes back as an empty bundle carrying
  # `error:`, so a host report can degrade gracefully.
  #
  #   bundle = OpenStudioGeometry.floor_plans(model, path: 'plans.html')
  #   bundle[:storeys].map { |s| s[:name] }   # => ["Story 0", "Story 1", ...]
  #
  # Unlike `render`, the standalone page written to `path:` is FULLY
  # self-contained — inline CSS and SVG, native <details>, no scripts and no
  # external references at all.
  #
  # @param model_or_path [OpenStudio::Model::Model, String] model or .osm path
  # @param path [String, nil] write the standalone HTML page here
  # @param png_dir [String, nil] rasterize one PNG per storey into this
  #   directory (optional — needs rsvg-convert, cairosvg or magick on PATH;
  #   audited warning and no files when none is installed)
  # @param audit [AuditLog, nil] audit sink; step `:plan`
  # @return [Hash] { storeys: [{ name:, svg: }], legend_svg:, empty:,
  #   inferred_storeys:, error: (only on failure) }
  def self.floor_plans(model_or_path, path: nil, png_dir: nil, audit: nil)
    audit ||= AuditLog.new
    detail = Plan.extract_for(model_or_path, audit: audit)
    bundle = Plan.bundle_from(detail)
    if path
      File.write(path, Plan.page(bundle, source: Plan.source_label(model_or_path), detail: detail))
    end
    pngs = png_dir ? Plan.pngs(bundle, png_dir, audit: audit) : []

    if bundle[:error]
      audit.warn(:plan, 'no floor plans produced', inputs: { error: bundle[:error] })
    else
      audit.decision(:plan, 'per-storey floor plans rendered',
                     target: Plan.source_label(model_or_path),
                     inputs: { storeys: bundle[:storeys].size,
                               spaces: detail[:storeys].sum { |s| s[:spaces].size },
                               inferred_storeys: bundle[:inferred_storeys],
                               html: path, pngs: pngs.size },
                     value: bundle[:storeys].map { |s| s[:name] }.join(', '))
    end
    bundle
  end

  # Rewrites the canonical storey names to the spellings the shape's wizard
  # takes, so `ordered`'s unknown-parameter check below still sees only real
  # wizard keys (and still raises for genuine typos).
  def self.normalize_storey_aliases(params, shape)
    params = params.transform_keys(&:to_sym)
    aliases = CREATE_ALIASES.fetch(shape, CREATE_ALIASES_DEFAULT)
    if params.key?(:below_grade_storeys) && !aliases.key?(:below_grade_storeys)
      raise(ArgumentError, "below_grade_storeys: is only supported by the 'rectangle' shape — " \
                           "the #{shape} wizard has no below-grade storeys " \
                           '(aspect_ratio delegates to rectangle but fixes them at 0)')
    end

    aliases.each do |alias_key, target|
      next unless params.key?(alias_key)
      raise(ArgumentError, "pass either #{alias_key}: or #{target}:, not both — they set the same value") if params.key?(target)

      params[target] = params.delete(alias_key)
    end
    params
  end

  # Alias resolution for keyword entry points (bar): nil means "not given", so
  # an alias and its target supplied together are ambiguous and raise.
  def self.resolve_alias(alias_key, alias_value, target_key, target_value, default)
    if !alias_value.nil? && !target_value.nil?
      raise(ArgumentError, "pass either #{alias_key}: or #{target_key}:, not both — they set the same value")
    end

    alias_value || target_value || default
  end

  # Positional-argument adapter: the wizards keep their upstream positional
  # signatures; unknown keys raise so typos never silently fall to defaults.
  def self.ordered(params, keys, defaults)
    unknown = params.keys.map(&:to_sym) - keys
    raise(ArgumentError, "unknown parameter(s) #{unknown.join(', ')} — expected #{keys.join(', ')}") unless unknown.empty?

    keys.each_with_index.map { |key, index| params.key?(key) ? params[key] : defaults[index] }
  end
end
