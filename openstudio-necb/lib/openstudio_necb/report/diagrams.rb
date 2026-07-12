module OpenStudioNECB
  module Report
    # System-layout schematics: supply-chain component boxes left→right with a
    # zone/demand count. Pure data in (from ModelQuery), inline SVG out.
    module Diagrams
      module_function

      BOX_W = 108
      BOX_H = 40
      GAP = 26
      KIND_COLORS = {
        oa: '#7fb3d5', hx: '#a569bd', cooling_coil: '#5dade2', heating_coil: '#e59866',
        fan: '#82e0aa', boiler: '#e57373', water_heater: '#e59866', chiller: '#5dade2',
        tower: '#76d7c4', pump: '#f7dc6f'
      }.freeze

      # loop: { name:, chain: [{kind:, name:}], zone_count:/demand_count: }
      def loop_schematic(loop, accent:)
        chain = loop[:chain] || []
        served = loop[:zone_count] || loop[:demand_count] || 0
        served_label = loop.key?(:zone_count) ? "#{served} zone#{served == 1 ? '' : 's'}" : "#{served} demand load#{served == 1 ? '' : 's'}"
        boxes = chain.empty? ? [{ kind: :other, name: '(no classified components)' }] : chain

        width = boxes.size * (BOX_W + GAP) + 140
        height = BOX_H + 46
        out = [SVG.open_svg(width, height, "System layout: #{loop[:name]}")]
        out << SVG.text(4, 14, loop[:name], font_weight: 'bold', fill: accent)
        y = 24
        boxes.each_with_index do |box, i|
          x = 4 + i * (BOX_W + GAP)
          color = KIND_COLORS.fetch(box[:kind], '#d5d8dc')
          out << SVG.rect(x, y, BOX_W, BOX_H, color, stroke: '#333', rx: 4)
          out << SVG.text(x + BOX_W / 2.0, y + 16, ModelQuery::KIND_LABELS.fetch(box[:kind], 'Component'),
                          text_anchor: 'middle', font_weight: 'bold')
          out << SVG.text(x + BOX_W / 2.0, y + 30, truncate(box[:name], 18),
                          text_anchor: 'middle', font_size: 8, fill: '#333')
          # arrow after every box; the last one points at the served-loads box
          ax = x + BOX_W
          out << SVG.line(ax + 3, y + BOX_H / 2.0, ax + GAP - 6, y + BOX_H / 2.0, '#333', stroke_width: 1.5)
          out << SVG.text(ax + GAP - 6, y + BOX_H / 2.0 + 3, '▸', fill: '#333')
        end
        served_x = 4 + boxes.size * (BOX_W + GAP)
        out << SVG.rect(served_x, y, 120, BOX_H, '#fff', stroke: '#333', stroke_dasharray: '4,3', rx: 4)
        out << SVG.text(served_x + 60, y + BOX_H / 2.0 + 4, served_label, text_anchor: 'middle')
        out << SVG.close_svg
        out.join
      end

      def truncate(string, max)
        string.to_s.length > max ? "#{string[0, max - 1]}…" : string.to_s
      end
    end
  end
end
