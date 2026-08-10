# frozen_string_literal: true

module OpenStudioGeometry
  # SDK-FREE inline-SVG primitives + the per-storey floor-plan drawing built
  # from them. Pure functions over the {PlanQuery} hashes, so every drawing
  # rule is unit-testable against a hand-written hash — no OpenStudio needed.
  #
  # The primitives (open_svg/close_svg/rect/line/text) are a LOCAL COPY of
  # openstudio-necb's `report/svg.rb`, plus the polygon/group/title helpers the
  # family lacked. They are copied rather than required: openstudio-geometry
  # sits BELOW openstudio-necb in the dependency graph and must never depend
  # upward (the documented catalog_report.rb:29-32 precedent). The necb
  # convention is kept: a fit-to-width `viewBox` and NO width/height attributes,
  # so a host stylesheet's `svg { width: 100% }` scales the plan to the page.
  module PlanSvg
    module_function

    WIDTH = 920.0           # viewBox width; drawings fit to it
    PAD = 26.0              # margin around the footprint, in viewBox units
    MIN_HEIGHT = 120.0
    LABEL_MIN_W = 54.0      # below this a two-line label is illegible: skipped
    LABEL_MIN_H = 26.0
    NAME_SIZE = 11.0
    ZONE_SIZE = 9.0
    CHAR_W = 0.55           # sans-serif average advance, in font-size units
    NO_ZONE_FILL = '#ffffff'
    NO_ZONE_LABEL = 'unassigned'

    # ------------------------------------------------------------ primitives

    def esc(value)
      value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    def attrs(opts)
      opts.map { |k, v| %( #{k.to_s.tr('_', '-')}="#{esc(v)}") }.join
    end

    def open_svg(width, height, label)
      %(<svg viewBox="0 0 #{width.round(1)} #{height.round(1)}" role="img" aria-label="#{esc(label)}" ) +
        %(xmlns="http://www.w3.org/2000/svg" font-family="sans-serif" font-size="11">)
    end

    def close_svg
      '</svg>'
    end

    def rect(x, y, w, h, fill, opts = {})
      %(<rect x="#{x.round(1)}" y="#{y.round(1)}" width="#{[w, 0].max.round(1)}" ) +
        %(height="#{[h, 0].max.round(1)}" fill="#{fill}"#{attrs(opts)}/>)
    end

    def line(x1, y1, x2, y2, stroke, opts = {})
      %(<line x1="#{x1.round(1)}" y1="#{y1.round(1)}" x2="#{x2.round(1)}" y2="#{y2.round(1)}" ) +
        %(stroke="#{stroke}"#{attrs(opts)}/>)
    end

    def text(x, y, string, opts = {})
      %(<text x="#{x.round(1)}" y="#{y.round(1)}"#{attrs(opts)}>#{esc(string)}</text>)
    end

    # New in this gem: a filled polygon, optionally carrying a native <title>
    # tooltip child (self-closing when there is nothing to say).
    def polygon(points, fill, opts = {}, title: nil)
      coords = points.map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(' ')
      head = %(<polygon points="#{coords}" fill="#{fill}"#{attrs(opts)})
      title ? "#{head}>#{title(title)}</polygon>" : "#{head}/>"
    end

    # New: hover tooltip / accessible name for the element that contains it.
    def title(string)
      "<title>#{esc(string)}</title>"
    end

    # New: a <g> wrapper around pre-built fragments.
    def group(content, opts = {})
      "<g#{attrs(opts)}>#{content}</g>"
    end

    # ------------------------------------------------------------- palette

    # Deterministic zone -> HSL fill. Ruby's String#hash is SEEDED PER PROCESS,
    # so a stable djb2 is used instead: the same zone gets the same color in
    # every run, every storey and every document. Lightness stays high (65%) so
    # the black centroid labels stay readable on top.
    def zone_color(zone)
      return NO_ZONE_FILL if zone.nil? || zone.to_s.empty?

      "hsl(#{djb2(zone.to_s) % 360}, 45%, 65%)"
    end

    def djb2(string)
      string.each_byte.reduce(5381) { |hash, byte| ((hash * 33) + byte) & 0xffffffff }
    end

    # ------------------------------------------------------- storey drawing

    # One storey -> one inline <svg>. `bounds:` is the WHOLE BUILDING's extent
    # (from PlanQuery) so every storey is drawn at the same scale and position
    # and the storeys stack visually.
    #
    # @param storey [Hash] { name:, z:, spaces: [...] }
    # @param bounds [Hash, nil] { min_x:, min_y:, max_x:, max_y: }
    # @return [String] a complete <svg> element
    def storey_svg(storey, bounds: nil, width: WIDTH, north_axis: 0.0)
      bounds ||= derive_bounds(storey[:spaces])
      return empty_svg(storey[:name], width) if bounds.nil?

      scale, height = fit(bounds, width)
      body = storey[:spaces].map { |space| space_group(space, bounds, scale, height) }.join
      label = "Floor plan — #{storey[:name]}"
      [open_svg(width, height, label),
       rect(0, 0, width, height, '#ffffff'),
       body,
       scale_bar(scale, width, height),
       north_arrow(width, north_axis),
       close_svg].join
    end

    # True-north arrow, top-right. Building coordinates put "building north" up
    # the page; the Building North Axis is the building y-axis's CLOCKWISE
    # rotation from true north, so true north on screen is the up-arrow
    # rotated by -north_axis (SVG rotate is clockwise-positive on the flipped
    # y axis; sanity case: north_axis 90 = building y faces east = true north
    # points LEFT on the plan).
    def north_arrow(width, north_axis)
      cx = width - PAD - 12
      cy = PAD + 12
      arrow = [line(0, 10, 0, -8, '#111', stroke_width: 1.5),
               %(<polygon points="0,-12 -4,-4 4,-4" fill="#111"/>),
               text(0, -15, 'N', text_anchor: 'middle', fill: '#111',
                    font_size: 10, font_weight: 'bold')].join
      %(<g class="north-arrow" transform="translate(#{cx.round(1)},#{cy.round(1)}) ) +
        %(rotate(#{(-north_axis.to_f).round(1)})">#{arrow}</g>)
    end

    # Building coords (metres, y up) -> viewBox coords (y DOWN, hence flipped).
    def project(x, y, bounds, scale, height)
      [PAD + ((x - bounds[:min_x]) * scale),
       height - PAD - ((y - bounds[:min_y]) * scale)]
    end

    def fit(bounds, width)
      span_x = [bounds[:max_x] - bounds[:min_x], 1e-6].max
      span_y = [bounds[:max_y] - bounds[:min_y], 1e-6].max
      scale = (width - (2 * PAD)) / span_x
      height = [(span_y * scale) + (2 * PAD), MIN_HEIGHT].max
      [scale, height]
    end

    def derive_bounds(spaces)
      points = spaces.to_a.flat_map { |space| space[:polygons].flatten(1) }
      return nil if points.empty?

      { min_x: points.map(&:first).min, min_y: points.map(&:last).min,
        max_x: points.map(&:first).max, max_y: points.map(&:last).max }
    end

    def empty_svg(name, width)
      [open_svg(width, MIN_HEIGHT, "Floor plan — #{name} (no geometry)"),
       text(width / 2, MIN_HEIGHT / 2, 'no floor geometry on this storey',
            text_anchor: 'middle', fill: '#777'),
       close_svg].join
    end

    # One space: its filled ring(s) — each carrying the tooltip — plus the
    # two-line centroid label when the shape is big enough to hold it.
    def space_group(space, bounds, scale, height)
      fill = zone_color(space[:zone])
      tip = tooltip(space)
      rings = space[:polygons].map do |ring|
        projected = ring.map { |x, y| project(x, y, bounds, scale, height) }
        polygon(projected, fill, { stroke: '#333', stroke_width: 0.8 }, title: tip)
      end.join
      group(rings + label(space, bounds, scale, height))
    end

    # ALWAYS present, on every polygon: the full identity of the space, so a
    # shape too small to label still answers a hover.
    def tooltip(space)
      [space[:name],
       space[:zone] || NO_ZONE_LABEL,
       space[:space_type] || 'no space type',
       "#{format('%.1f', space[:area_m2].to_f)} m²"].join(' | ')
    end

    # Two lines at the centroid: space name, zone name smaller beneath.
    # Skipped entirely when the space's largest ring cannot hold legible text
    # (the tooltip still carries everything).
    def label(space, bounds, scale, height)
      ring = space[:polygons].max_by { |r| ring_span(r).inject(:*) }
      return '' if ring.nil?

      span_x, span_y = ring_span(ring)
      box_w = span_x * scale
      box_h = span_y * scale
      return '' if box_w < LABEL_MIN_W || box_h < LABEL_MIN_H

      cx, cy = project(*space[:centroid], bounds, scale, height)
      name = clip(space[:name], box_w, NAME_SIZE)
      out = text(cx, cy, name, text_anchor: 'middle', fill: '#111', font_size: NAME_SIZE)
      zone = space[:zone]
      if zone && box_h >= LABEL_MIN_H + ZONE_SIZE
        out += text(cx, cy + ZONE_SIZE + 2, clip(zone, box_w, ZONE_SIZE),
                    text_anchor: 'middle', fill: '#444', font_size: ZONE_SIZE)
      end
      out
    end

    def ring_span(ring)
      xs = ring.map(&:first)
      ys = ring.map(&:last)
      [xs.max - xs.min, ys.max - ys.min]
    end

    # Truncate to what fits the shape at this font size (never mid-render
    # overflow into the neighbouring space).
    def clip(string, box_w, font_size)
      max_chars = (box_w / (font_size * CHAR_W)).floor
      return string if string.length <= max_chars
      return string[0, max_chars] if max_chars < 4

      "#{string[0, max_chars - 1]}…"
    end

    # A 1-2-5 rounded metric scale bar, so the plan reads as a drawing.
    def scale_bar(scale, width, height)
      target = (width - (2 * PAD)) / 5.0
      metres = nice_length(target / scale)
      length = metres * scale
      x = width - PAD - length
      y = height - 8
      [line(x, y, x + length, y, '#111', stroke_width: 1.5),
       line(x, y - 4, x, y + 2, '#111', stroke_width: 1.5),
       line(x + length, y - 4, x + length, y + 2, '#111', stroke_width: 1.5),
       text(x + (length / 2), y - 6, "#{fmt_metres(metres)} m", text_anchor: 'middle',
                                                               fill: '#111', font_size: 9)].join
    end

    def nice_length(raw)
      return 1.0 if raw <= 0

      exponent = Math.log10(raw).floor
      base = 10.0**exponent
      [1, 2, 5, 10].map { |m| m * base }.min_by { |candidate| (candidate - raw).abs }
    end

    def fmt_metres(metres)
      metres == metres.to_i ? metres.to_i.to_s : format('%.1f', metres)
    end

    # ---------------------------------------------------------------- legend

    # The shared zone legend: one swatch per zone across the whole model, in
    # the same colors the plans use. `zones` may contain nil (unassigned).
    def legend_svg(zones, width: WIDTH, columns: 3)
      entries = zones.uniq.sort_by { |zone| [zone.to_s.empty? ? 1 : 0, zone.to_s] }
      return empty_legend(width) if entries.empty?

      rows = (entries.size.to_f / columns).ceil
      col_w = (width - (2 * PAD)) / columns
      height = (rows * 18.0) + 30.0
      cells = entries.each_with_index.map do |zone, index|
        x = PAD + ((index / rows) * col_w)
        y = 26.0 + ((index % rows) * 18.0)
        rect(x, y - 9, 11, 11, zone_color(zone), stroke: '#333', stroke_width: 0.6) +
          text(x + 16, y, zone || NO_ZONE_LABEL, fill: '#111', font_size: 10)
      end.join
      [open_svg(width, height, 'Thermal zone legend'),
       text(PAD, 14, 'Thermal zones', fill: '#111', font_size: 11, font_weight: 'bold'),
       cells,
       close_svg].join
    end

    def empty_legend(width)
      [open_svg(width, 30, 'Thermal zone legend (empty)'),
       text(PAD, 18, 'no thermal zones', fill: '#777', font_size: 10),
       close_svg].join
    end
  end
end
