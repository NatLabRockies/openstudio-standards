require 'minitest/autorun'
require 'json'
require 'base64'
require_relative '../lib/openstudio_geometry'

# The campus-repo 3D renderer port: crash-isolated glTF export + fallback
# ladder + palette boost + <model-viewer> HTML with the geometry embedded as
# a base64 data URI.
class TestRender < Minitest::Test
  def wizard_model
    OpenStudioGeometry.create(shape: 'rectangle', length: 30.0, width: 20.0,
                              above_ground_storys: 2, floor_to_floor_height: 3.5,
                              perimeter_zone_depth: 3.0)
  end

  def extract_gltf(html)
    m = html.match(%r{data:model/gltf\+json;base64,([A-Za-z0-9+/=]+)})
    refute_nil m, 'embedded glTF data URI present'
    JSON.parse(Base64.decode64(m[1]))
  end

  def test_render_happy_path_embeds_boosted_gltf
    audit = OpenStudioGeometry::AuditLog.new
    html = OpenStudioGeometry.render(wizard_model, audit: audit)

    assert_includes html, '<model-viewer'
    assert_includes html, 'model-viewer.min.js', 'viewer component script tag present'
    refute_includes html, 'Approximate massing', 'clean model needs no fallback'

    gltf = extract_gltf(html)
    materials = gltf['materials'].to_h { |m| [m['name'], m['pbrMetallicRoughness']] }
    wall = materials['Wall']
    refute_nil wall, 'SDK glTF material names survive'
    assert_in_delta 0.84, wall['baseColorFactor'][0], 1e-6, 'campus palette applied (warm-sand wall)'
    assert_in_delta 0.65, wall['roughnessFactor'], 1e-6
    assert_equal 0.0, wall['metallicFactor']
    assert(audit.entries.any? { |e| e[:action] == '3D geometry viewer produced (glTF embedded as data URI)' })
  end

  def test_render_writes_standalone_page
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'view.html')
      fragment = OpenStudioGeometry.render(wizard_model, path: path)
      refute_empty fragment
      page = File.read(path)
      assert page.start_with?('<!DOCTYPE html>')
      assert_includes page, fragment[0, 200]
    end
  end

  # The campus fallback ladder, exercised deterministically with an injected
  # exporter: full export "crashes", massing-shell export succeeds.
  def test_ladder_falls_back_to_massing_shell
    calls = []
    exporter = lambda do |ctrl, out|
      calls << ctrl
      next false unless ctrl['remove_subsurfaces'] && !ctrl.key?('keep_surfaces')

      File.write(out, '{"materials":[]}')
      true
    end
    ok, note = OpenStudioGeometry::Render.export_repaired('unused.osm', File.join(Dir.tmpdir, 'l1.gltf'),
                                                          exporter: exporter)
    assert ok
    assert_match(/windows\/doors omitted/, note)
    assert_equal false, calls.first['remove_subsurfaces'], 'full export attempted first'
  end

  # Bisection stage: one poisoned surface handle crashes any export containing
  # it; the ladder must isolate exactly that handle and drop it.
  def test_ladder_bisects_out_the_crashing_surface
    model = wizard_model
    Dir.mktmpdir do |dir|
      osm = File.join(dir, 'm.osm')
      model.save(OpenStudio::Path.new(osm), true)
      handles = OpenStudioGeometry::Render.surface_handles(osm)
      assert_operator handles.length, :>, 4
      bad = handles[3]

      exporter = lambda do |ctrl, out|
        keep = ctrl['keep_surfaces'] || (handles - (ctrl['drop_surfaces'] || []))
        next false unless ctrl['remove_subsurfaces'] # full export always "crashes"
        next false if keep.include?(bad)

        File.write(out, '{"materials":[]}')
        true
      end
      ok, note = OpenStudioGeometry::Render.export_repaired(osm, File.join(dir, 'out.gltf'),
                                                            exporter: exporter)
      assert ok
      assert_match(/1 bad surface\(s\) omitted/, note)
    end
  end

  def test_worker_control_removes_subsurfaces
    model = wizard_model
    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    wall.setWindowToWallRatio(0.4)
    refute_empty model.getSubSurfaces
    Dir.mktmpdir do |dir|
      osm = File.join(dir, 'm.osm')
      model.save(OpenStudio::Path.new(osm), true)
      out = File.join(dir, 'shell.gltf')
      ok = OpenStudioGeometry::Render.run_export(osm, out, { 'remove_subsurfaces' => true })
      assert ok, 'worker exports the massing shell'
      names = JSON.parse(File.read(out))['materials'].map { |m| m['name'] }
      refute_includes names, 'Window', 'sub-surfaces removed before export'
    end
  end
end
