require 'openstudio'

module OpenStudioEnvelope
  module Costing
    # Envelope costing — port of legacy cost_audit_envelope + cost_construction.
    # For each censused surface: the costed-assembly catalog supplies (RSI, cost)
    # pairs (each candidate construction's id_layers priced through the materials
    # sheet -> costs table -> regional factors), the surface's cost per ft2 is the
    # linear interpolation of that curve at the surface's own RSI, glazing adds the
    # nearest-SHGC solar-film premium, and the line total is cost/ft2 x net area x
    # zone multiplier.
    module EnvelopeCosts
      module_function

      # @return [Hash] the envelope section of the report
      def cost(model, database:, province_state:, city:, structure: nil,
               performance: :lp, tb_tallies: nil, audit: nil)
        census = Quantify.census(model, audit: audit)
        curve_cache = {}
        section = { 'construction_costs' => [], 'surface_types' => {}, 'total_envelope_cost' => 0.0 }
        upper_exceeded = []

        Quantify::SURFACE_TYPES.each do |surface_type|
          items = census[surface_type]
          type_cost = 0.0
          type_area = 0.0

          items.each do |item|
            assembly = Assemblies.for_surface_type(surface_type, structure, performance)
            sheet = Assemblies::SHEETS.fetch(surface_type)
            curve = curve_cache[[sheet, assembly]] ||=
              cost_curve(database, sheet, assembly, province_state, city)

            result = Interpolate.interpolate(x_y_array: curve[:points], x2: item.rsi)
            upper_exceeded << "#{item.surface.nameString} (#{surface_type}, RSI #{item.rsi.round(3)})" if result.upper_bound_exceeded

            film_cost = 0.0
            if Assemblies::GLAZING_SHEETS.include?(sheet)
              film_cost = solar_film_cost(database, item.surface, province_state, city)
            end

            area_m2 = item.area_m2 * item.multiplier
            area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
            line_cost = (result.value + film_cost) * area_ft2
            type_cost += line_cost
            type_area += area_m2

            accumulate_row(section['construction_costs'], assembly, surface_type, item,
                           line_cost, area_m2, result.note)
          end

          snake = surface_type.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
          section['surface_types'][snake] = {
            'cost' => type_cost.round(2), 'area_m2' => type_area.round(2),
            'cost_per_m2' => type_area.positive? ? (type_cost / type_area).round(2) : 0.0
          }
          section['total_envelope_cost'] += type_cost
        end

        add_parapet(section, tb_tallies, audit) if tb_tallies

        unless upper_exceeded.empty?
          message = 'assembly cost curve upper bound exceeded — no costed assembly reaches the ' \
                    "required thermal resistance for: #{upper_exceeded.join('; ')}. The clamped " \
                    'upper-bound cost was used; the real assembly may be unbuildable at catalog pricing ' \
                    '(legacy adds a $10^12 sentinel here — this port flags instead).'
          audit&.warn(:costing_envelope, message)
          section['unrealistic_assembly'] = true
          section['unrealistic_assembly_note'] = message
        end

        section['total_envelope_cost'] = section['total_envelope_cost'].round(2)
        audit&.decision(:costing_envelope, 'envelope costed by assembly cost-curve interpolation at each surface RSI',
                        inputs: { surfaces: census.values.sum(&:size), city: city, province_state: province_state,
                                  performance: performance, structure: structure || 'default (steel-framed)' },
                        value: "$#{section['total_envelope_cost'].round(2)}")
        section
      end

      # (RSI, $/ft2) points for an assembly catalog — each candidate construction's
      # id_layers priced once (legacy cost_construction).
      def cost_curve(database, sheet, assembly, province_state, city)
        candidates = database.construction_candidates(sheet, assembly)
        points = candidates.map do |rsi, construction|
          [rsi, construction_cost(database, construction, province_state, city)]
        end
        { points: points, candidates: candidates }
      end

      # Legacy cost_construction: sum over id_layers of
      # ((material x reg_mat/100) + (labour x reg_inst/100) + equipment) x quantity,
      # each layer rounded to cents.
      def construction_cost(database, construction, province_state, city)
        id_key = "materials_#{construction['type']}_id"
        sheet_rows = database.materials_sheet(construction['type'])

        construction['id_layers'].sum do |layer_id|
          material = sheet_rows.find { |row| row[id_key] == layer_id.to_s }
          raise(ArgumentError, "material id #{layer_id} not found in materials_#{construction['type']}") if material.nil?

          costs = database.cost_record(material['id'])
          reg_mat, reg_inst, = database.regional_factors(province_state, city, material['id'])
          material_cost = costs['materialOpCost'] * material['material_mult'].to_f
          labour_cost = costs['laborOpCost'] * material['labour_mult'].to_f
          (((material_cost * reg_mat / 100.0) + (labour_cost * reg_inst / 100.0) +
            costs['equipmentOpCost']) * material['quantity'].to_f).round(2)
        end
      end

      # Legacy SHGC film premium: nearest materials_glazing 'Solarfilms' row by
      # |SHGC delta|, material+labour x regional factors.
      def solar_film_cost(database, subsurface, province_state, city)
        shgc = shgc_of(subsurface)
        return 0.0 if shgc.nil?

        row = database.materials_glazing
                      .select { |r| r['material_type'] == 'Solarfilms' }
                      .min_by { |r| (shgc - r['solar_heat_gain_coefficient'].to_f).abs }
        return 0.0 if row.nil?

        costs = database.cost_record(row['id'])
        material_cost = costs['materialOpCost'] * mult(row['material_mult'])
        labour_cost = costs['laborOpCost'] * mult(row['labour_mult'])
        reg_mat, reg_inst, = database.regional_factors(province_state, city, row['id'])
        (material_cost * reg_mat / 100.0) + (labour_cost * reg_inst / 100.0)
      end

      def shgc_of(subsurface)
        return nil if subsurface.construction.empty?

        construction = subsurface.construction.get.to_LayeredConstruction
        return nil if construction.empty?

        layer = construction.get.layers.first
        simple = layer.to_SimpleGlazing
        return simple.get.solarHeatGainCoefficient if simple.is_initialized

        glazing = layer.to_StandardGlazing
        return glazing.get.solarTransmittanceatNormalIncidence.to_f if glazing.is_initialized && !glazing.get.solarTransmittanceatNormalIncidence.nil?

        nil
      end

      # Parapets are not modelled surfaces: legacy adds parapet length x 1 m of the
      # averaged exterior-wall $/m2 when TBD edge tallies are available.
      def add_parapet(section, tb_tallies, audit)
        parapet = tb_tallies['parapet']
        return if parapet.nil? || parapet.empty?

        length_m = parapet.values.sum
        wall_rate = section['surface_types'].dig('exterior_wall', 'cost_per_m2').to_f
        cost = (length_m * wall_rate).round(2)
        section['parapet_cost'] = cost
        section['total_envelope_cost'] += cost
        audit&.info(:costing_envelope, 'parapet allowance added (parapet length x 1 m at the exterior-wall rate)',
                    inputs: { parapet_length_m: length_m.round(2), wall_cost_per_m2: wall_rate },
                    value: "$#{cost}")
      end

      def accumulate_row(rows, assembly, surface_type, item, line_cost, area_m2, note)
        conductance = (1.0 / item.rsi).round(3)
        row = rows.find { |r| r['assembly_name'] == assembly && r['conductance'] == conductance && r['surface_type'] == surface_type }
        if row.nil?
          rows << { 'assembly_name' => assembly, 'surface_type' => surface_type,
                    'conductance' => conductance, 'area' => area_m2.round(2),
                    'cost' => line_cost.round(2),
                    'cost_per_area' => area_m2.positive? ? (line_cost / area_m2).round(2) : 0.0,
                    'note' => note }
        else
          row['area'] = (row['area'] + area_m2).round(2)
          row['cost'] = (row['cost'] + line_cost).round(2)
          row['cost_per_area'] = row['area'].positive? ? (row['cost'] / row['area']).round(2) : 0.0
        end
      end

      def mult(value)
        value.nil? || value.to_s.strip.empty? ? 1.0 : value.to_f
      end
    end
  end
end
