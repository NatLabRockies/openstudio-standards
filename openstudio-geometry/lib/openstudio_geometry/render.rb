# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'fileutils'
require 'json'
require 'rbconfig'
require 'tempfile'
require 'timeout'

module OpenStudioGeometry
  # 3D geometry viewer — Ruby port of the campus repo's renderer
  # (canmet-energy/campus, src/buildings/reports/geometry_view.py): export the
  # model to glTF with the SDK's GltfForwardTranslator and render it with
  # Google's <model-viewer> web component, glTF embedded as a base64 data URI
  # so the HTML needs no side files.
  #
  # Robustness measures carried over verbatim from campus:
  #  1. The C++ translator can SEGFAULT on un-triangulatable surfaces, so
  #     every export runs in an isolated child process (render_worker.rb).
  #  2. A fallback ladder repairs crashing models on in-memory copies (the
  #     source .osm is never modified): (a) full export -> (b) sub-surfaces
  #     removed (massing shell) -> (c) binary-search the offending base
  #     surfaces in child processes and drop just those.
  #  3. Material colors boosted for contrast (palette keyed on the SDK's
  #     glTF material names).
  #
  # NOTE: the <model-viewer> SCRIPT loads from the Google CDN at view time
  # (needs internet, same trade-off campus ships with; the caption says so).
  # The geometry itself is fully embedded.
  module Render
    module_function

    WORKER = File.expand_path('render_worker.rb', __dir__)
    MV_VERSION = '4.3.1'
    MV_CDN = "https://ajax.googleapis.com/ajax/libs/model-viewer/#{MV_VERSION}/model-viewer.min.js"
    MAX_REMOVE = 12
    MAX_PROBES = 80

    # name -> [[r, g, b, a], roughness] (campus palette, verbatim)
    PALETTE = {
      'Wall' => [[0.84, 0.57, 0.26, 1.00], 0.65],       # warm sand
      'RoofCeiling' => [[0.70, 0.19, 0.16, 1.00], 0.65], # terracotta
      'Floor' => [[0.29, 0.33, 0.39, 1.00], 0.70],      # cool slate
      'Door' => [[0.50, 0.29, 0.10, 1.00], 0.60],       # rich wood
      'Window' => [[0.18, 0.60, 0.93, 0.42], 0.08]      # vivid glass
    }.freeze

    # ---------------------------- material contrast ----------------------------

    def saturate(rgb, factor = 1.5)
      lum = (0.2126 * rgb[0]) + (0.7152 * rgb[1]) + (0.0722 * rgb[2])
      rgb.map { |c| (lum + ((c - lum) * factor)).clamp(0.0, 1.0) }
    end

    def boost_materials!(gltf)
      (gltf['materials'] || []).each do |mat|
        pbr = (mat['pbrMetallicRoughness'] ||= {})
        if (entry = PALETTE[mat['name']])
          pbr['baseColorFactor'] = entry[0].dup
          pbr['roughnessFactor'] = entry[1]
        else
          base = pbr['baseColorFactor'] || [0.7, 0.7, 0.7, 1.0]
          alpha = base.length > 3 ? base[3] : 1.0
          pbr['baseColorFactor'] = saturate(base[0, 3]) + [alpha]
          pbr['roughnessFactor'] = 0.62
        end
        pbr['metallicFactor'] = 0.0
      end
      gltf
    end

    # ---------------------------- subprocess export ----------------------------

    # One worker run with a control hash. True iff clean exit + non-empty file.
    def run_export(osm_path, out_path, control, timeout: 240)
      File.delete(out_path) if File.exist?(out_path)
      ctrl = Tempfile.new(['gltf_ctrl', '.json'])
      ctrl.write(JSON.generate(control))
      ctrl.close
      pid = Process.spawn(RbConfig.ruby, WORKER, osm_path.to_s, out_path.to_s, ctrl.path,
                          %i[out err] => File::NULL)
      begin
        Timeout.timeout(timeout) { Process.wait(pid) }
        $?.exitstatus == 0 && File.exist?(out_path) && File.size(out_path).positive? # rubocop:disable Style/SpecialGlobalVars
      rescue Timeout::Error
        Process.kill('KILL', pid)
        Process.wait(pid)
        false
      end
    ensure
      ctrl&.unlink
    end

    # Loading a model never crashes (only export does) — in-process is fine.
    def surface_handles(osm_path)
      loaded = OpenStudio::Model::Model.load(OpenStudio::Path.new(osm_path.to_s))
      return [] if loaded.empty?

      loaded.get.getSurfaces.map { |s| s.handle.to_s }
    end

    # The campus fallback ladder. Returns [ok, note]; leaves the good glTF at
    # out_path. `exporter` is injectable for deterministic ladder tests.
    def export_repaired(osm_path, out_path, audit: nil, exporter: nil)
      exporter ||= ->(ctrl, out) { run_export(osm_path, out, ctrl) }

      return [true, ''] if exporter.call({ 'remove_subsurfaces' => false }, out_path)

      if exporter.call({ 'remove_subsurfaces' => true }, out_path)
        note = 'Approximate massing — windows/doors omitted to render.'
        audit&.warn(:render, 'glTF export crashed on sub-surfaces — windows/doors omitted (massing shell)')
        return [true, note]
      end

      handles = surface_handles(osm_path)
      return [false, ''] if handles.empty?

      probe_out = "#{out_path}.probe.gltf"
      keep_ok = ->(keep) { exporter.call({ 'remove_subsurfaces' => true, 'keep_surfaces' => keep }, probe_out) }

      removed = []
      probes = 0
      while probes < MAX_PROBES
        keep = handles - removed
        probes += 1
        break if keep_ok.call(keep)

        # binary-search one offending surface within `keep` (which crashes)
        cur = keep
        while cur.length > 1 && probes < MAX_PROBES
          left = cur[0, cur.length / 2]
          probes += 1
          cur = keep_ok.call(left) ? cur[(cur.length / 2)..] : left
        end
        removed << cur[0]
        audit&.info(:render, "bisection: crashing surface isolated (#{removed.length}), #{probes} probes")
        break if removed.length >= MAX_REMOVE
      end
      File.delete(probe_out) if File.exist?(probe_out)

      if removed.any? && exporter.call({ 'remove_subsurfaces' => true, 'drop_surfaces' => removed }, out_path)
        note = "Approximate massing — windows/doors + #{removed.length} bad surface(s) omitted."
        audit&.warn(:render, "glTF export required dropping #{removed.length} crashing surface(s) — approximate massing",
                    inputs: { dropped_handles: removed })
        return [true, note]
      end
      [false, '']
    end

    # ------------------------------- viewer -----------------------------------

    def viewer_html(src, height: 480, note: '')
      banner = if note.empty?
                 ''
               else
                 '<div style="font-size:12px;color:#b06a00;background:#fff6e5;' \
                   'border-left:4px solid #e8a33d;padding:5px 9px;border-radius:4px;margin:0 0 6px">' \
                   "&#9888; #{CGI.escapeHTML(note)}</div>"
               end
      "<h2>3D geometry</h2>#{banner}" \
        "<script type=\"module\" src=\"#{MV_CDN}\"></script>" \
        "<model-viewer src=\"#{src}\" alt=\"Building geometry\" " \
        'camera-controls ' \
        'tone-mapping="neutral" shadow-intensity="0.9" shadow-softness="0.8" exposure="1.0" ' \
        'environment-image="neutral" camera-orbit="-35deg 68deg 70%" bounds="tight" ' \
        'min-camera-orbit="auto auto auto" max-camera-orbit="auto 95deg auto" ' \
        'interaction-prompt="none" touch-action="pan-y" ' \
        "style=\"width:100%;height:#{height.to_i}px;background:" \
        'linear-gradient(#f7fafc,#e6edf2);border:1px solid #e3eaef;border-radius:8px">' \
        '<div slot="poster" style="display:flex;align-items:center;justify-content:center;' \
        'height:100%;color:#62707c">Loading 3D model&#8230;</div>' \
        '</model-viewer>' \
        '<div style="font-size:12px;color:#8794a1;margin:4px 0 8px">' \
        'Drag to orbit &#183; scroll to zoom. ' \
        '(3D viewer script loads from Google CDN; needs internet.)</div>'
    end

    # Model or .osm path -> self-contained viewer fragment ('' if unrenderable).
    def geometry_viewer(model_or_path, height: 480, work_dir: nil, audit: nil)
      work = work_dir ? File.expand_path(work_dir) : Dir.tmpdir
      FileUtils.mkdir_p(work)

      osm_path = model_or_path
      temp_osm = nil
      unless model_or_path.is_a?(String)
        temp_osm = File.join(work, "render_#{Process.pid}_#{object_id}.osm")
        model_or_path.save(OpenStudio::Path.new(temp_osm), true)
        osm_path = temp_osm
      end

      gltf_path = File.join(work, "#{File.basename(osm_path, '.osm')}.__geom.gltf")
      ok, note = export_repaired(osm_path, gltf_path, audit: audit)
      unless ok
        audit&.warn(:render, 'glTF export failed after the full fallback ladder — no 3D view produced',
                    target: File.basename(osm_path))
        return ''
      end

      gltf = boost_materials!(JSON.parse(File.read(gltf_path)))
      payload = JSON.generate(gltf)
      audit&.decision(:render, '3D geometry viewer produced (glTF embedded as data URI)',
                      target: File.basename(osm_path),
                      inputs: { gltf_bytes: payload.bytesize, materials: gltf['materials']&.length,
                                approximate: !note.empty? },
                      value: note.empty? ? 'full geometry (windows/doors included)' : note)
      viewer_html("data:model/gltf+json;base64,#{Base64.strict_encode64(payload)}",
                  height: height, note: note)
    ensure
      [temp_osm, defined?(gltf_path) ? gltf_path : nil].compact.each do |f|
        File.delete(f) if File.exist?(f)
      end
    end
  end
end
