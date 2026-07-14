module OpenStudioNECB
  module Report
    # HTML string helpers + the report stylesheet. Everything is escaped unless
    # wrapped in Raw (pre-built fragments from these helpers).
    module H
      Raw = Struct.new(:html)

      module_function

      PROPOSED_COLOR = '#1a5276'.freeze
      REFERENCE_COLOR = '#7f8c8d'.freeze

      def esc(value)
        value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
      end

      def raw(html)
        Raw.new(html)
      end

      def cell(value)
        value.is_a?(Raw) ? value.html : esc(value)
      end

      def tag(name, content = nil, **attrs)
        attr_string = attrs.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{esc(v)}") }.join
        content.nil? ? "<#{name}#{attr_string}>" : "<#{name}#{attr_string}>#{cell(content)}</#{name}>"
      end

      def section(id, title, body, page_break: false)
        klass = page_break ? 'page-break' : nil
        %(<section id="#{id}"#{klass ? %( class="#{klass}") : ''}><h2>#{esc(title)}</h2>#{body}</section>)
      end

      def table(headers, rows, css: nil)
        head = headers.map { |h| "<th>#{cell(h)}</th>" }.join
        body = rows.map { |r| "<tr>#{r.map { |c| "<td>#{cell(c)}</td>" }.join}</tr>" }.join
        %(<table#{css ? %( class="#{css}") : ''}><thead><tr>#{head}</tr></thead><tbody>#{body}</tbody></table>)
      end

      def kv_table(pairs)
        rows = pairs.map { |k, v| "<tr><th>#{esc(k)}</th><td>#{cell(v)}</td></tr>" }.join
        %(<table class="kv">#{rows}</table>)
      end

      def badge(text, kind)
        %(<span class="badge badge-#{kind}">#{esc(text)}</span>)
      end

      GLYPHS = { pass: %w[✓ pass], fail: %w[✗ fail], warning: %w[▲ warn],
                 info: %w[● info], na: %w[○ na] }.freeze

      def glyph(kind)
        symbol, klass = GLYPHS.fetch(kind, GLYPHS[:na])
        %(<span class="glyph glyph-#{klass}">#{symbol}</span>)
      end

      def fmt(value, unit: nil, prec: 1)
        return '—' if value.nil?

        text = if value.is_a?(Numeric)
                 rounded = value.round(prec)
                 rounded = rounded.to_i if prec.zero? || rounded == rounded.to_i
                 rounded.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
               else
                 value.to_s
               end
        unit ? "#{text} #{unit}" : text
      end

      # Which-model tag for audit-derived rows: proposed (blue), reference
      # (gray), input model (amber); nil = a cross-building comparison/verdict.
      def building_chip(name)
        return %(<span class="bldg bldg-na">comparison</span>) if name.nil? || name.to_s.empty?

        klass = case name.to_s
                when /reference/i then 'bldg-reference'
                when /input/i then 'bldg-input'
                else 'bldg-proposed'
                end
        %(<span class="bldg #{klass}">#{esc(name.to_s.sub(/ building\z/, ''))}</span>)
      end

      def details(summary, body, open: false)
        %(<details#{open ? ' open' : ''}><summary>#{esc(summary)}</summary>#{body}</details>)
      end

      def legend
        %(<span class="chip" style="background:#{PROPOSED_COLOR}"></span> Proposed
          <span class="chip" style="background:#{REFERENCE_COLOR}"></span> Reference)
      end

      CSS = <<~CSS.freeze
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
               color: #111; background: #fff; line-height: 1.45; font-size: 14px;
               max-width: 62rem; margin: 0 auto; padding: 1.5rem; }
        h1 { font-size: 1.5rem; margin-bottom: .25rem; }
        h2 { font-size: 1.15rem; margin: 1.6rem 0 .6rem; border-bottom: 2px solid #111; padding-bottom: .2rem; }
        h3 { font-size: 1rem; margin: .9rem 0 .4rem; }
        p.meta { color: #444; font-size: .85rem; }
        section { margin-bottom: 1rem; }
        table { border-collapse: collapse; width: 100%; margin: .5rem 0; font-size: .85rem; }
        th, td { border: 1px solid #bbb; padding: .3rem .5rem; text-align: left; vertical-align: top; }
        thead th { background: #eee; }
        table.kv { width: auto; min-width: 50%; }
        table.kv th { background: #f4f4f4; width: 14rem; font-weight: 600; }
        .banner { border: 3px solid #111; padding: 1rem; margin: 1rem 0; display: flex;
                  flex-wrap: wrap; gap: 1.2rem; align-items: center; }
        .banner .big { font-size: 1.6rem; font-weight: 700; }
        .badge { display: inline-block; padding: .18rem .6rem; border-radius: .3rem;
                 font-weight: 700; font-size: .85rem; color: #fff; }
        .badge-pass { background: #1e7e34; } .badge-fail { background: #b02a37; }
        .badge-tier { background: #1a5276; } .badge-ghg { background: #5b2c6f; }
        .badge-warn { background: #9a6700; }
        .glyph { font-weight: 700; }
        .glyph-pass { color: #1e7e34; } .glyph-fail { color: #b02a37; }
        .glyph-warn { color: #9a6700; } .glyph-info { color: #1a5276; } .glyph-na { color: #777; }
        .chip { display: inline-block; width: .8rem; height: .8rem; border-radius: .15rem;
                vertical-align: middle; margin: 0 .25rem 0 .8rem; }
        .warnstrip { background: #fff3cd; border: 2px solid #9a6700; padding: .6rem .8rem;
                     font-weight: 600; margin: .6rem 0; }
        .bldg { display: inline-block; padding: .05rem .45rem; border-radius: .7rem;
                font-size: .75rem; font-weight: 700; color: #fff; white-space: nowrap; }
        .bldg-proposed { background: #1a5276; } .bldg-reference { background: #7f8c8d; }
        .bldg-input { background: #9a6700; } .bldg-na { background: #fff; color: #555; border: 1px solid #999; }
        .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
        svg { width: 100%; height: auto; }
        nav.toc { font-size: .85rem; margin: .6rem 0 1rem; }
        nav.toc a { margin-right: .9rem; color: #1a5276; }
        details { margin: .5rem 0; } summary { cursor: pointer; font-weight: 600; }
        .sig { display: inline-block; width: 45%; margin: 1.6rem 2% 0 0; border-top: 1px solid #111;
               padding-top: .3rem; font-size: .85rem; }
        footer { margin-top: 2rem; font-size: .75rem; color: #555; border-top: 1px solid #bbb; padding-top: .5rem; }
        /* OpenStudio-App-style per-building loop dropdown chooser (inline JS) */
        .hvac-select { margin: .5rem 0 1rem; }
        .loop-select-label { font-weight: 600; font-size: .9rem; }
        .loop-select { font-size: .9rem; padding: .2rem .4rem; margin-left: .3rem; }
        .loop-panel[hidden] { display: none; }
        .loop-panel-title { display: none; }
        @media print {
          /* reveal every loop on paper (the chooser hides non-active panels on screen) */
          .loop-panel[hidden] { display: block !important; }
          .loop-panel-title { display: block; font-weight: 600; }
          .loop-select-label { display: none; }
          body { max-width: none; padding: 0; font-size: 12px; }
          nav.toc { display: none; }
          section { break-inside: avoid; }
          .page-break { break-before: page; }
          h2 { break-after: avoid; }
          thead { display: table-header-group; }
          * { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
        }
      CSS
    end
  end
end
