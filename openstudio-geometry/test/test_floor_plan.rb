require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/openstudio_geometry'

# Per-storey floor plans: the SDK extraction (world coordinates, floor
# surfaces, storey grouping), the SDK-free SVG layer (fills, labels, tooltips,
# legend) and the self-contained standalone page.
class TestFloorPlan < Minitest::Test
  Query = OpenStudioGeometry::PlanQuery
  Svg = OpenStudioGeometry::PlanSvg
  Plan = OpenStudioGeometry::Plan

  # 15 spaces / 3 storeys (test_wizards.rb:9-32), 40 x 25 m footprint,
  # 4 m perimeter depth => a core space of exactly 32 x 17 m.
  def wizard_model(storeys: 2, below: 1)
    OpenStudioGeometry.create(shape: 'rectangle', length: 40.0, width: 25.0,
                              storeys: storeys, below_grade_storeys: below,
                              floor_to_floor_height: 3.6, perimeter_zone_depth: 4.0)
  end

  # The wizards zone SPACES, not thermal zones — give every space its own zone
  # so the zone-dependent drawing rules (fill, second label line) are exercised.
  def zone_every_space!(model)
    model.getSpaces.sort_by(&:nameString).each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{space.nameString}")
      space.setThermalZone(zone)
    end
    model
  end

  def bar_model
    OpenStudioGeometry.bar(space_type_ratios: { ['Space Function', 'Office enclosed > 25 m2'] => 0.7,
                                                ['Space Function', 'Corridor/Transition area other-sch-A'] => 0.3 },
                           length: 50.0, width: 20.0, storeys: 2, wwr: 0.4)
  end

  # Even-odd point-in-polygon (used to prove a courtyard void is really void).
  def inside?(ring, px, py)
    hits = false
    ring.each_with_index do |(x1, y1), index|
      x2, y2 = ring[(index + 1) % ring.size]
      next unless (y1 > py) != (y2 > py)

      hits = !hits if px < (((x2 - x1) * (py - y1)) / (y2 - y1)) + x1
    end
    hits
  end

  # ------------------------------------------------------------- extraction

  def test_multi_storey_wizard_numeric_polygons
    audit = OpenStudioGeometry::AuditLog.new
    data = Query.extract(wizard_model, audit: audit)

    refute data[:inferred_storeys], 'the wizard sets BuildingStorys — nothing to infer'
    assert_equal %w[Story\ 0 Story\ 1 Story\ 2], data[:storeys].map { |s| s[:name] },
                 'storeys in display order = ascending world z'
    assert_equal [-3.6, 0.0, 3.6], data[:storeys].map { |s| s[:z] }
    assert_equal [5, 5, 5], data[:storeys].map { |s| s[:spaces].size }
    assert_equal({ min_x: 0.0, min_y: 0.0, max_x: 40.0, max_y: 25.0 }, data[:bounds])

    core = data[:storeys][1][:spaces].find { |s| s[:name] == 'Story 1 Core Space' }
    refute_nil core, 'core space extracted'
    assert_equal [[[4.0, 4.0], [4.0, 21.0], [36.0, 21.0], [36.0, 4.0]]], core[:polygons],
                 'world-coordinate ring, 4 m perimeter depth inset on every side'
    assert_in_delta 32.0 * 17.0, core[:area_m2], 0.01
    assert_equal [20.0, 12.5], core[:centroid]
    assert_equal 0.0, core[:z]

    # every extracted area sums to the model's own floor area
    total = data[:storeys].sum { |s| s[:spaces].sum { |sp| sp[:area_m2] } }
    assert_in_delta 40.0 * 25.0 * 3, total, 0.5
    assert_empty audit.warnings, 'a clean wizard model produces no plan warnings'
  end

  # A space whose floors sit at two elevations (mezzanine modelled as one
  # space) is cut at the LOWEST plane — a plan is one horizontal cut.
  def test_multi_floor_space_keeps_the_lowest_set
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.new(model)
    space.setName('Mezz Space')
    [[[0, 0, 0], [0, 10, 0], [10, 10, 0], [10, 0, 0]],
     [[0, 0, 3], [0, 4, 3], [4, 4, 3], [4, 0, 3]]].each do |ring|
      vertices = OpenStudio::Point3dVector.new
      ring.each { |x, y, z| vertices << OpenStudio::Point3d.new(x, y, z) }
      OpenStudio::Model::Surface.new(vertices, model).setSpace(space)
    end

    record = Query.extract(model)[:storeys].first[:spaces].first
    assert_equal 1, record[:polygons].size, 'only the lowest floor plane is drawn'
    assert_in_delta 100.0, record[:area_m2], 0.01
  end

  def test_floorless_space_is_warned_and_skipped
    model = wizard_model(storeys: 1, below: 0)
    bare = OpenStudio::Model::Space.new(model)
    bare.setName('Shaft (no floor)')

    audit = OpenStudioGeometry::AuditLog.new
    data = Query.extract(model, audit: audit)
    names = data[:storeys].flat_map { |s| s[:spaces].map { |sp| sp[:name] } }
    refute_includes names, 'Shaft (no floor)'
    warning = audit.warnings.find { |e| e[:target] == 'Shaft (no floor)' }
    refute_nil warning, 'the skip is audited, never silent'
    assert_match(/no Floor surface/, warning[:action])
  end

  # The xOrigin trap's regression test. BTAP's rotate_model re-expresses each
  # space in a rotated LOCAL frame while leaving the building where it stands,
  # so `space.transformation * vertices` must be invariant — while the
  # rotation-blind `xOrigin + local vertex` shortcut now yields garbage.
  def test_rotation_regression_world_coordinates
    model = wizard_model(storeys: 1, below: 0)
    before = Query.extract(model)
    space = model.getSpaces.min_by(&:nameString)
    floor = space.surfaces.find { |s| s.surfaceType == 'Floor' }
    local_before = floor.vertices.map { |p| [p.x.round(3), p.y.round(3)] }

    OpenStudioGeometry::Helpers.rotate_model(model, 90)
    after = Query.extract(model)

    local_after = floor.vertices.map { |p| [p.x.round(3), p.y.round(3)] }
    refute_equal local_before, local_after, 'rotate_model DID move the local frame'
    assert_in_delta(-90.0, space.directionofRelativeNorth, 1e-6)
    assert_equal before[:storeys].first[:spaces], after[:storeys].first[:spaces],
                 'world coordinates are invariant — the building did not move'

    naive = local_after.map { |x, y| [(space.xOrigin + x).round(3), (space.yOrigin + y).round(3)] }
    world = after[:storeys].first[:spaces].find { |s| s[:name] == space.nameString }[:polygons].first
    refute_equal world, naive, 'the rotation-blind xOrigin shortcut disagrees — never use it'
  end

  # ...and a genuine rigid rotation of the building MUST move the polygons:
  # +90 deg about z maps (x, y) -> (-y, x).
  def test_rigid_rotation_moves_the_polygons
    model = wizard_model(storeys: 1, below: 0)
    before = Query.extract(model)
    rotation = OpenStudio::Transformation.rotation(OpenStudio::Vector3d.new(0, 0, 1), Math::PI / 2)
    model.getSpaces.each { |space| space.setTransformation(rotation * space.transformation) }
    after = Query.extract(model)

    before[:storeys].first[:spaces].each_with_index do |space, index|
      rotated = after[:storeys].first[:spaces][index]
      assert_equal space[:name], rotated[:name]
      expected = space[:polygons].map { |ring| ring.map { |x, y| [(-y).round(3), x.round(3)] } }
      assert_equal expected, rotated[:polygons]
      assert_in_delta space[:area_m2], rotated[:area_m2], 0.01
    end
    assert_equal({ min_x: -25.0, min_y: 0.0, max_x: 0.0, max_y: 40.0 }, after[:bounds])
  end

  def test_no_storey_fallback_infers_levels
    model = wizard_model
    model.getBuildingStorys.each(&:remove)
    assert_empty model.getBuildingStorys

    audit = OpenStudioGeometry::AuditLog.new
    data = Query.extract(model, audit: audit)
    assert data[:inferred_storeys], 'the fallback flags itself'
    assert_equal ['Level 1', 'Level 2', 'Level 3'], data[:storeys].map { |s| s[:name] }
    assert_equal [-3.6, 0.0, 3.6], data[:storeys].map { |s| s[:z] }
    assert_equal [5, 5, 5], data[:storeys].map { |s| s[:spaces].size }
    warning = audit.warnings.find { |e| e[:action].include?('storeys inferred') }
    refute_nil warning, 'inference is audited, never silent'
    assert_match(/no BuildingStory objects/, warning[:action])
  end

  # The courtyard void is space-less: no polygon covers the courtyard centre,
  # although the bounds enclose it.
  def test_courtyard_void_is_a_hole
    model = OpenStudioGeometry.create(shape: 'courtyard', length: 50.0, width: 30.0,
                                      courtyard_length: 15.0, courtyard_width: 5.0, storeys: 1)
    data = Query.extract(model)
    assert_equal({ min_x: 0.0, min_y: 0.0, max_x: 50.0, max_y: 30.0 }, data[:bounds])

    rings = data[:storeys].first[:spaces].flat_map { |space| space[:polygons] }
    assert_operator rings.size, :>=, 12, 'every courtyard space renders a ring'
    refute(rings.any? { |ring| inside?(ring, 25.0, 15.0) }, 'the courtyard centre is void')
    assert(rings.any? { |ring| inside?(ring, 1.0, 15.0) }, 'the west band is solid')
  end

  # ------------------------------------------------------------- SVG layer

  def test_bar_model_space_type_tooltips
    bundle = Plan.diagrams(bar_model)
    refute bundle[:empty]
    svg = bundle[:storeys].first[:svg]
    assert_includes svg, 'Space Function | Office enclosed &gt; 25 m2',
                    'NECB standards tags reach the tooltip (escaped)'
    assert_includes svg, 'Space Function | Corridor/Transition area other-sch-A'
    assert_match(%r{<title>[^<]+ \| [^<]+ \| [^<]+ \| [\d.]+ m²</title>}, svg,
                 'tooltip is space | zone | space type | area')
    assert_includes bundle[:legend_svg], 'Thermal zones'
  end

  # The whole drawing layer is SDK-FREE: a hand-written hash is enough.
  def test_sdk_free_layer_on_a_hand_written_hash
    storey = { name: 'Level 1', z: 0.0,
               spaces: [{ name: 'Big', zone: 'Zone A', space_type: 'Office',
                          polygons: [[[0, 0], [0, 10], [20, 10], [20, 0]]],
                          centroid: [10.0, 5.0], area_m2: 200.0 },
                        { name: 'Tiny', zone: nil, space_type: nil,
                          polygons: [[[0, 0], [0, 1], [1, 1], [1, 0]]],
                          centroid: [0.5, 0.5], area_m2: 1.0 }] }
    svg = Svg.storey_svg(storey, bounds: { min_x: 0.0, min_y: 0.0, max_x: 20.0, max_y: 10.0 })

    assert svg.start_with?('<svg viewBox="0 0 920.0 486.0"'), "unexpected header: #{svg[0, 80]}"
    refute_match(/<svg[^>]*\bwidth=/, svg, 'fit-to-width: no width/height attributes (necb convention)')
    refute_match(/<svg[^>]*\bheight=/, svg)

    # y is FLIPPED: building (0,0) is bottom-left, svg (26, 460) is bottom-left.
    assert_includes svg, '26.0,460.0'
    assert_includes svg, '894.0,26.0'

    assert_includes svg, '<title>Big | Zone A | Office | 200.0 m²</title>'
    assert_includes svg, '<title>Tiny | unassigned | no space type | 1.0 m²</title>',
                    'tooltip present even for an unlabelled shape'
    assert_includes svg, '>Big<'
    assert_includes svg, '>Zone A<', 'second label line is the zone name'
    refute_includes svg, '>Tiny<', 'a 1 m x 1 m space is too small for legible text'
    assert_includes svg, Svg.zone_color('Zone A'), 'zone fill applied'
    assert_includes svg, Svg::NO_ZONE_FILL, 'zone-less space is white'
  end

  def test_zone_palette_is_deterministic
    # NOT String#hash (seeded per process) — the same zone must get the same
    # color in every run and every document.
    assert_equal 'hsl(202, 45%, 65%)', Svg.zone_color('Zone A')
    assert_equal Svg.zone_color('Zone A'), Svg.zone_color('Zone A')
    refute_equal Svg.zone_color('Zone A'), Svg.zone_color('Zone B')
    assert_equal Svg::NO_ZONE_FILL, Svg.zone_color(nil)

    lib = File.expand_path('../lib/openstudio_geometry', __dir__)
    other = `ruby -e "require '#{lib}'; print OpenStudioGeometry::PlanSvg.zone_color('Zone A')"`
    assert_equal Svg.zone_color('Zone A'), other,
                 'stable across processes (Ruby seeds String#hash per process)'
  end

  def test_legend_lists_every_zone_once
    legend = Svg.legend_svg(['Zone B', 'Zone A', 'Zone A', nil])
    assert_equal 1, legend.scan('>Zone A<').size, 'zones are de-duplicated'
    assert_includes legend, '>Zone B<'
    assert_includes legend, '>unassigned<'
    assert legend.start_with?('<svg viewBox="0 0 920.0')
  end

  def test_empty_model_degrades_gracefully
    bundle = Plan.diagrams(OpenStudio::Model::Model.new)
    assert bundle[:empty]
    assert_empty bundle[:storeys]
    assert_nil bundle[:legend_svg]

    html = Plan.page(bundle)
    assert html.start_with?('<!DOCTYPE html>')
    assert_includes html, 'No floor plans'
  end

  # ------------------------------------------------------------- the page

  def test_standalone_page_is_self_contained
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'plans.html')
      audit = OpenStudioGeometry::AuditLog.new
      bundle = OpenStudioGeometry.floor_plans(zone_every_space!(wizard_model), path: path, audit: audit)

      assert_equal 3, bundle[:storeys].size
      html = File.read(path)
      assert html.start_with?('<!DOCTYPE html>')
      assert_equal 4, html.scan('<svg').size, 'three storey plans + the zone legend'
      assert_equal 2, html.scan('class="storey page-break"').size,
                   'a page break before every storey but the first'
      assert_includes html, 'break-inside: avoid'
      assert_includes html, '<details>', 'the only interactivity is native <details>'
      refute_match(/<script/i, html, 'no scripts')
      assert_includes html, 'Story 1 Core Space'
      assert_includes html, 'Zone Story 1 Core Space'

      # --- copied verbatim from openstudio-hvac/test/test_catalog_report.rb:75-80
      refute_match(/src\s*=\s*["']https?:/i, html, 'no remote src')
      refute_match(/<link\b/i, html, 'no <link> (external stylesheet/asset)')
      refute_match(/@import/i, html, 'no CSS @import')
      refute_match(/url\(/i, html, 'no CSS url() references')
      refute_match(%r{https?://(?!www\.w3\.org)}i, html,
                   'no external URLs except the SVG xmlns namespace')
      # --- end copied block

      entry = audit.entries.find { |e| e[:step] == :plan && e[:level] == :decision }
      refute_nil entry
      assert_equal 3, entry[:inputs][:storeys]
      assert_equal 15, entry[:inputs][:spaces]
    end
  end

  def test_facade_accepts_an_osm_path
    Dir.mktmpdir do |dir|
      osm = File.join(dir, 'm.osm')
      wizard_model(storeys: 1, below: 0).save(OpenStudio::Path.new(osm), true)
      bundle = OpenStudioGeometry.floor_plans(osm)
      assert_equal 1, bundle[:storeys].size
      refute bundle[:empty]
    end
  end

  def test_unloadable_path_never_raises
    audit = OpenStudioGeometry::AuditLog.new
    bundle = OpenStudioGeometry.floor_plans('/nonexistent/nope.osm', audit: audit)
    assert bundle[:empty]
    refute_nil bundle[:error]
    refute_empty audit.warnings
  end

  # ------------------------------------------------------------- PNG (optional)

  def test_png_rasterizes_when_a_converter_exists
    skip 'no SVG rasterizer on PATH (rsvg-convert / cairosvg / magick)' if Plan.rasterizer.nil?

    Dir.mktmpdir do |dir|
      bundle = Plan.diagrams(wizard_model(storeys: 1, below: 0))
      written = Plan.pngs(bundle, dir)
      assert_equal bundle[:storeys].size, written.size
      written.each { |file| assert_operator File.size(file), :>, 0 }
    end
  end

  # The no-rasterizer path is deterministic everywhere: hide PATH.
  def test_png_warns_loudly_when_no_rasterizer_exists
    original = ENV.fetch('PATH', '')
    ENV['PATH'] = ''
    audit = OpenStudioGeometry::AuditLog.new
    Dir.mktmpdir do |dir|
      result = Plan.png('<svg xmlns="http://www.w3.org/2000/svg"/>', File.join(dir, 'x.png'), audit: audit)
      assert_nil result, 'no PNG, and no exception'
    end
    warning = audit.warnings.first
    refute_nil warning
    assert_equal 'no SVG rasterizer found — PNG not produced', warning[:action]
  ensure
    ENV['PATH'] = original
  end
end
