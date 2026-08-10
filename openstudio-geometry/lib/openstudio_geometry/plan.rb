# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require_relative 'plan_query'
require_relative 'plan_svg'

module OpenStudioGeometry
  # Per-storey floor plans: {PlanQuery} (SDK) + {PlanSvg} (SDK-free drawing)
  # composed into the two consumable products —
  #
  #  * {diagrams}    — a plain-hash bundle of inline SVG strings a HOST report
  #                    embeds (shaped like OpenStudioHVAC::CatalogReport
  #                    .model_diagrams, the bundle openstudio-necb's AHJ report
  #                    already knows how to consume). NEVER raises.
  #  * {html_report} — one self-contained standalone page (inline CSS, inline
  #                    SVG, native <details>, NO scripts and NO external
  #                    references of any kind — unlike the 3D `render` viewer,
  #                    which needs the model-viewer CDN script).
  #
  # {png} is an OPTIONAL convenience: it rasterizes a plan through whichever
  # system SVG converter is installed and warns loudly (returning nil) when
  # none is — a PNG is never a required output.
  module Plan
    module_function

    # ------------------------------------------------------------- bundle

    # @param model [OpenStudio::Model::Model]
    # @param audit [AuditLog, nil]
    # @return [Hash] { storeys: [{ name:, svg: }], legend_svg:, empty:,
    #   inferred_storeys:, error: (only on failure) }
    def diagrams(model, audit: nil)
      bundle_from(PlanQuery.extract(model, audit: audit))
    rescue StandardError => e
      audit&.warn(:plan, "floor-plan diagrams failed — none produced (#{e.message})")
      { storeys: [], legend_svg: nil, empty: true, inferred_storeys: false, error: e.message }
    end

    # The SDK-free half of {diagrams}: a {PlanQuery} hash -> the SVG bundle.
    # Split out so a caller that also wants the raw hash (for the space tables)
    # extracts ONCE.
    def bundle_from(data)
      if data[:error]
        return { storeys: [], legend_svg: nil, empty: true,
                 inferred_storeys: data[:inferred_storeys] || false, error: data[:error] }
      end

      storeys = data[:storeys].map do |storey|
        { name: storey[:name],
          svg: PlanSvg.storey_svg(storey, bounds: data[:bounds],
                                  north_axis: data[:north_axis_deg].to_f) }
      end
      zones = data[:storeys].flat_map { |storey| storey[:spaces].map { |space| space[:zone] } }.uniq
      { storeys: storeys,
        legend_svg: storeys.empty? ? nil : PlanSvg.legend_svg(zones),
        empty: storeys.empty?,
        inferred_storeys: data[:inferred_storeys] }
    end

    # ------------------------------------------------------------- page

    CSS = <<~CSS.freeze
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
             color: #111; background: #fff; line-height: 1.45; font-size: 14px;
             max-width: 62rem; margin: 0 auto; padding: 1.5rem; }
      h1 { font-size: 1.5rem; margin-bottom: .25rem; }
      h2 { font-size: 1.15rem; margin: 1.6rem 0 .6rem; border-bottom: 2px solid #111; padding-bottom: .2rem; }
      p.meta { color: #444; font-size: .85rem; }
      section { margin-bottom: 1rem; break-inside: avoid; }
      svg { width: 100%; height: auto; }
      table { border-collapse: collapse; width: 100%; margin: .5rem 0; font-size: .85rem; }
      th, td { border: 1px solid #bbb; padding: .3rem .5rem; text-align: left; vertical-align: top; }
      thead th { background: #eee; }
      nav.toc { font-size: .85rem; margin: .6rem 0 1rem; }
      nav.toc a { margin-right: .9rem; color: #1a5276; }
      details { margin: .5rem 0; } summary { cursor: pointer; font-weight: 600; }
      .warnstrip { background: #fff3cd; border: 2px solid #9a6700; padding: .6rem .8rem;
                   font-weight: 600; margin: .6rem 0; }
      footer { margin-top: 2rem; font-size: .75rem; color: #555; border-top: 1px solid #bbb; padding-top: .5rem; }
      @media print {
        body { max-width: none; padding: 0; font-size: 12px; }
        nav.toc { display: none; }
        .page-break { break-before: page; }
        h2 { break-after: avoid; }
        thead { display: table-header-group; }
        * { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
      }
    CSS

    def esc(value)
      PlanSvg.esc(value)
    end

    def anchor(name)
      "storey-#{name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')}"
    end

    # Model or .osm path -> the complete standalone page (also written to
    # `path` when given). Never raises: an unreadable/plan-less model renders
    # as a one-line note.
    #
    # @return [String] the full HTML document
    def html_report(model_or_path, path = nil, audit: nil, title: 'Floor plans')
      detail = extract_for(model_or_path, audit: audit)
      html = page(bundle_from(detail), title: title, source: source_label(model_or_path), detail: detail)
      File.write(path, html) if path
      html
    end

    # Model or .osm path -> the raw {PlanQuery} hash (an `error:` hash when the
    # path will not load). Never raises.
    def extract_for(model_or_path, audit: nil)
      model = load_model(model_or_path, audit: audit)
      return PlanQuery.extract(model, audit: audit) if model

      { storeys: [], bounds: nil, inferred_storeys: false,
        error: "could not load #{model_or_path}" }
    end

    # Assemble the document from an already-built bundle (`detail:` is the
    # raw {PlanQuery} hash, used for the per-storey space tables; optional).
    def page(bundle, title: 'Floor plans', source: nil, detail: nil)
      body = +''
      body << %(<h1>#{esc(title)}</h1>)
      body << %(<p class="meta">#{esc(source)}</p>) if source
      body << %(<p class="meta">#{esc(summary_line(bundle))}</p>)
      if bundle[:inferred_storeys]
        body << %(<p class="warnstrip">Storeys were inferred from floor elevations — ) \
                'the model carries no usable BuildingStory assignments.</p>'
      end
      if bundle[:error]
        body << %(<p class="warnstrip">No floor plans: #{esc(bundle[:error])}</p>)
      elsif bundle[:empty]
        body << '<p class="warnstrip">No floor plans: the model has no space with a Floor surface.</p>'
      else
        body << toc(bundle)
        # No zone legend on the page (phylroy, 2026-08-10): too small to read
        # and redundant with the per-storey space inventory below; the bundle
        # still carries legend_svg for hosts that want it.
        bundle[:storeys].each_with_index do |storey, index|
          body << storey_section(storey, index, detail)
        end
      end
      body << %(<footer>Generated by openstudio-geometry #{esc(OpenStudioGeometry::VERSION)} — ) \
              'plan view of each storey in world coordinates; fills are per thermal zone.</footer>'
      document(title, body)
    end

    def document(title, body)
      %(<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">) +
        %(<meta name="viewport" content="width=device-width, initial-scale=1">) +
        %(<title>#{esc(title)}</title><style>#{CSS}</style></head><body>#{body}</body></html>)
    end

    def summary_line(bundle)
      return 'no storeys rendered' if bundle[:storeys].empty?

      "#{bundle[:storeys].size} storey(s): #{bundle[:storeys].map { |s| s[:name] }.join(', ')}"
    end

    def toc(bundle)
      links = bundle[:storeys].map { |s| %(<a href="##{anchor(s[:name])}">#{esc(s[:name])}</a>) }.join
      %(<nav class="toc">#{links}</nav>)
    end

    # One section per storey — `page-break` so printing gives a plan per page,
    # `break-inside: avoid` (in CSS, on every section) so a plan is never split.
    def storey_section(storey, index, detail)
      klass = index.zero? ? 'storey' : 'storey page-break'
      table = space_table(detail, storey[:name])
      %(<section class="#{klass}" id="#{anchor(storey[:name])}"><h2>#{esc(storey[:name])}</h2>) +
        storey[:svg].to_s + table + '</section>'
    end

    # The optional collapsible space inventory (native <details>, no scripts).
    def space_table(detail, storey_name)
      storey = detail && detail[:storeys].find { |s| s[:name] == storey_name }
      return '' if storey.nil? || storey[:spaces].empty?

      rows = storey[:spaces].map do |space|
        "<tr><td>#{esc(space[:name])}</td><td>#{esc(space[:zone] || '—')}</td>" \
          "<td>#{esc(space[:space_type] || '—')}</td>" \
          "<td>#{format('%.1f', space[:area_m2].to_f)}</td></tr>"
      end.join
      "<details><summary>#{storey[:spaces].size} space(s)</summary>" \
        '<table><thead><tr><th>Space</th><th>Thermal zone</th><th>Space type</th>' \
        "<th>Floor area (m²)</th></tr></thead><tbody>#{rows}</tbody></table></details>"
    end

    # ------------------------------------------------------------- helpers

    # Model in -> model out; .osm path in -> loaded model (nil + audited warn
    # when it will not load).
    def load_model(model_or_path, audit: nil)
      return model_or_path unless model_or_path.is_a?(String)

      loaded = OpenStudio::Model::Model.load(OpenStudio::Path.new(model_or_path))
      return loaded.get if loaded.is_initialized

      audit&.warn(:plan, 'model could not be loaded — no floor plans produced', target: model_or_path)
      nil
    rescue StandardError => e
      audit&.warn(:plan, "model could not be loaded — no floor plans produced (#{e.message})",
                  target: model_or_path.to_s)
      nil
    end

    def source_label(model_or_path)
      return File.basename(model_or_path) if model_or_path.is_a?(String)

      name = model_or_path.respond_to?(:building) ? model_or_path.building : nil
      name&.is_initialized ? name.get.nameString : nil
    end

    # ------------------------------------------------------------- PNG

    # Rasterizer probes, in preference order: [executable, argv builder].
    RASTERIZERS = [
      ['rsvg-convert', ->(svg, png) { ['rsvg-convert', '-o', png, svg] }],
      ['cairosvg', ->(svg, png) { ['cairosvg', svg, '-o', png] }],
      ['magick', ->(svg, png) { ['magick', svg, png] }]
    ].freeze

    # First rasterizer on PATH, or nil.
    def rasterizer
      RASTERIZERS.find { |exe, _| which(exe) }
    end

    def which(exe)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
        candidate = File.join(dir, exe)
        return candidate if File.file?(candidate) && File.executable?(candidate)
      end
      nil
    end

    # OPTIONAL rasterization of one plan SVG. Returns the written path, or nil
    # (with a loud audit warning) when no system rasterizer is installed or the
    # conversion fails. Never raises, never a hard dependency.
    def png(svg, path, audit: nil)
      found = rasterizer
      if found.nil?
        audit&.warn(:plan, 'no SVG rasterizer found — PNG not produced',
                    target: File.basename(path.to_s),
                    inputs: { probed: RASTERIZERS.map(&:first) })
        return nil
      end

      FileUtils.mkdir_p(File.dirname(path))
      svg_path = File.join(Dir.tmpdir, "plan_#{Process.pid}_#{rand(1 << 32)}.svg")
      File.write(svg_path, svg)
      ok = system(*found.last.call(svg_path, path.to_s), out: File::NULL, err: File::NULL)
      unless ok && File.exist?(path.to_s)
        audit&.warn(:plan, "#{found.first} failed to rasterize the plan — PNG not produced",
                    target: File.basename(path.to_s))
        return nil
      end
      path.to_s
    rescue StandardError => e
      audit&.warn(:plan, "PNG rasterization failed (#{e.message})", target: File.basename(path.to_s))
      nil
    ensure
      File.delete(svg_path) if svg_path && File.exist?(svg_path)
    end

    # Rasterize a whole bundle into `dir`, one PNG per storey. Returns the
    # written paths (empty when no rasterizer is available).
    def pngs(bundle, dir, audit: nil)
      FileUtils.mkdir_p(dir)
      bundle[:storeys].filter_map do |storey|
        slug = storey[:name].to_s.gsub(/[^A-Za-z0-9._-]+/, '_')
        png(storey[:svg], File.join(dir, "#{slug}.png"), audit: audit)
      end
    end
  end
end
