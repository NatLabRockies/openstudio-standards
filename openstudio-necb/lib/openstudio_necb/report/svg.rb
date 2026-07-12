module OpenStudioNECB
  module Report
    # Inline-SVG primitives. Every chart/diagram is built from these so the
    # report needs no external assets or scripts.
    module SVG
      module_function

      def open_svg(width, height, label)
        %(<svg viewBox="0 0 #{width} #{height}" role="img" aria-label="#{H.esc(label)}" ) +
          %(xmlns="http://www.w3.org/2000/svg" font-family="sans-serif" font-size="11">)
      end

      def close_svg
        '</svg>'
      end

      def rect(x, y, w, h, fill, opts = {})
        extra = opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{H.esc(v)}") }.join
        %(<rect x="#{x.round(1)}" y="#{y.round(1)}" width="#{[w, 0].max.round(1)}" height="#{h.round(1)}" fill="#{fill}"#{extra}/>)
      end

      def line(x1, y1, x2, y2, stroke, opts = {})
        extra = opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{H.esc(v)}") }.join
        %(<line x1="#{x1.round(1)}" y1="#{y1.round(1)}" x2="#{x2.round(1)}" y2="#{y2.round(1)}" stroke="#{stroke}"#{extra}/>)
      end

      def text(x, y, string, opts = {})
        extra = opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{H.esc(v)}") }.join
        %(<text x="#{x.round(1)}" y="#{y.round(1)}"#{extra}>#{H.esc(string)}</text>)
      end

      # The shared horizontal-bar primitive: a labelled bar with its value
      # printed at the end. Returns SVG fragments (no <svg> wrapper).
      def bar_row(y, label, value, max_value, color, label_w:, plot_w:, bar_h: 14, value_text: nil)
        frac = max_value.to_f.positive? ? [value.to_f / max_value, 0.0].max : 0.0
        bar_w = frac * plot_w
        out = []
        out << text(label_w - 6, y + bar_h - 3, label, text_anchor: 'end', fill: '#111')
        out << rect(label_w, y, bar_w, bar_h, color)
        vtext = value_text || value.to_s
        if bar_w > plot_w * 0.55
          out << text(label_w + bar_w - 5, y + bar_h - 3, vtext, text_anchor: 'end', fill: '#fff')
        else
          out << text(label_w + bar_w + 5, y + bar_h - 3, vtext, fill: '#111')
        end
        out.join
      end
    end
  end
end
