module OpenStudioNECB
  module Report
    # Proposed-vs-reference comparison charts built on SVG.bar_row.
    module Charts
      module_function

      LABEL_W = 150
      PLOT_W = 560
      WIDTH = LABEL_W + PLOT_W + 90
      BAR_H = 14
      PAIR_GAP = 4
      GROUP_GAP = 14

      # rows: [[label, proposed_value, reference_value], ...] — reference may be
      # nil (EUI-only runs render proposed bars alone).
      def paired_bars(rows, unit:, label:, prec: 0)
        rows = rows.reject { |_, p, r| (p.nil? || p.zero?) && (r.nil? || r.zero?) }
        return '' if rows.empty?

        max = rows.flat_map { |_, p, r| [p, r] }.compact.max.to_f
        return '' if max.zero?

        has_ref = rows.any? { |_, _, r| !r.nil? }
        group_h = has_ref ? (2 * BAR_H + PAIR_GAP) : BAR_H
        height = rows.size * (group_h + GROUP_GAP) + 10
        out = [SVG.open_svg(WIDTH, height, label)]
        y = 5
        rows.each do |row_label, proposed, reference|
          out << SVG.bar_row(y, row_label, proposed || 0, max, H::PROPOSED_COLOR,
                             label_w: LABEL_W, plot_w: PLOT_W, bar_h: BAR_H,
                             value_text: "#{H.fmt(proposed, prec: prec)} #{unit}")
          if has_ref
            out << SVG.bar_row(y + BAR_H + PAIR_GAP, '', reference || 0, max, H::REFERENCE_COLOR,
                               label_w: LABEL_W, plot_w: PLOT_W, bar_h: BAR_H,
                               value_text: "#{H.fmt(reference, prec: prec)} #{unit}")
          end
          y += group_h + GROUP_GAP
        end
        out << SVG.close_svg
        out.join
      end

      # Totals bar chart with dashed vertical target line(s):
      # targets: [[label, value], ...] drawn as dashed lines across the plot.
      def total_bars(rows, targets: [], unit: 'kWh', label: 'Annual energy totals')
        rows = rows.reject { |_, v| v.nil? }
        return '' if rows.empty?

        max = (rows.map { |_, v| v } + targets.map { |_, v| v }).compact.max.to_f
        return '' if max.zero?

        height = rows.size * (BAR_H + GROUP_GAP) + (targets.empty? ? 10 : 30)
        out = [SVG.open_svg(WIDTH, height, label)]
        y = 5
        rows.each_with_index do |(row_label, value), i|
          color = i.zero? ? H::PROPOSED_COLOR : H::REFERENCE_COLOR
          out << SVG.bar_row(y, row_label, value, max, color,
                             label_w: LABEL_W, plot_w: PLOT_W, bar_h: BAR_H,
                             value_text: "#{H.fmt(value, prec: 0)} #{unit}")
          y += BAR_H + GROUP_GAP
        end
        targets.each_with_index do |(t_label, t_value), i|
          x = LABEL_W + (t_value / max) * PLOT_W
          out << SVG.line(x, 0, x, y, '#b02a37', stroke_dasharray: '5,4', stroke_width: 2)
          out << SVG.text(x + 4, y + 12 + (i * 12), "#{t_label}: #{H.fmt(t_value, prec: 0)} #{unit}", fill: '#b02a37')
        end
        out << SVG.close_svg
        out.join
      end
    end
  end
end
