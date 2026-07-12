require 'openstudio'

module OpenStudioEnvelope
  module Costing
    # Thermal-bridging costing — port of BTAP::BridgingData
    # .get_material_quantities_for_edges + cost_audit_thermal_bridging, keyed on
    # the vendored thermal_bridging.csv ($/ft piecework recipes per TBD edge type x
    # wall reference "<assembly> <quality>", BETB detail provenance).
    #
    # LEGACY DEFECT (fixed here, loudly): legacy cost_audit_thermal_bridging
    # iterates the id=>quantity map but its `materials_opaque.find` block never
    # tests the id — the block body (`total += ...`) is truthy, so `find` stops at
    # the FIRST row and EVERY thermal-bridge material is priced as materials_opaque
    # row 1 ("gypsum wallboard 0.5 in thick"). This port matches materials BY ID
    # (the obvious intent) and audits the deviation.
    #
    # Per legacy comment, NO regional factors apply: edge piecework is costed
    # nationwide.
    module ThermalBridgingCosts
      module_function

      SKIPPED_EDGE_TYPES = %w[transition ceiling].freeze
      FENESTRATION_EDGE = /\A(skylight)?(jamb|sill|head)\z/.freeze

      # Normalize a tallies hash out of a TBD.process result: io edges grouped by
      # (normalized edge type) with lengths in metres, all referenced to one wall
      # assembly+quality (the census can't attribute edges per wall type — same as
      # legacy, which tallies against the building's costed wall assembly).
      def tallies_from_tbd(tbd_result, wall_reference)
        edges = tbd_result.is_a?(Hash) ? tbd_result.dig(:io, :edges) : nil
        return nil if edges.nil?

        tallies = Hash.new { |h, k| h[k] = Hash.new(0.0) }
        edges.each do |edge|
          type = edge[:type].to_s.sub(/concave\z/, '').sub(/convex\z/, '')
          tallies[type][wall_reference] += edge[:length].to_f
        end
        tallies
      end

      # @param tallies [Hash] { edge_type => { "<assembly> <quality>" => length_m } }
      # @return [Hash] the thermal_bridging section of the report
      def cost(tallies, database:, audit: nil)
        quantities, tally_rows = material_quantities(tallies, database, audit)

        total = 0.0
        by_material = []
        quantities.sort.each do |id, quantity_m|
          if id.to_s == '0' || id.to_s.strip.empty?
            audit&.warn(:costing_thermal_bridging,
                        "thermal_bridging.csv references material id '#{id}' which has no materials_opaque row — skipped " \
                        "(quantity #{quantity_m.round(2)} m)")
            next
          end

          material = database.materials_opaque.find { |row| row['materials_opaque_id'] == id.to_s }
          if material.nil?
            audit&.warn(:costing_thermal_bridging, "material id #{id} not found in materials_opaque — skipped")
            next
          end

          costs = database.cost_record(material['id'])
          material_cost = costs['materialOpCost'] * material['material_mult'].to_f
          labour_cost = costs['laborOpCost'] * material['labour_mult'].to_f
          quantity_ft = OpenStudio.convert(quantity_m, 'm', 'ft').get
          # materials_opaque quantities are ft2; piecework recipes price per ft of
          # edge, hence the legacy sqrt (ft2 -> ft)
          per_ft_divisor = Math.sqrt(material['quantity'].to_f)
          line = ((material_cost + labour_cost + costs['equipmentOpCost']) *
                  (quantity_ft / per_ft_divisor)).round(2)
          total += line
          by_material << { 'materials_opaque_id' => id, 'description' => material['description'],
                           'quantity_m' => quantity_m.round(2), 'cost' => line }
        end

        audit&.decision(:costing_thermal_bridging,
                        'thermal-bridge edges costed via thermal_bridging.csv piecework recipes, materials matched BY ID',
                        inputs: { edge_rows: tally_rows, materials: by_material.size },
                        value: "$#{total.round(2)}",
                        evidence: 'legacy defect corrected: cost_audit_thermal_bridging\'s find block ignores the id ' \
                                  'and prices every edge as materials_opaque row 1 (gypsum wallboard)')

        { 'total_thermal_bridging_cost' => total.round(2), 'by_material' => by_material }
      end

      # Port of get_material_quantities_for_edges: edge tallies -> materials_opaque
      # id => accumulated quantity (m), via the CSV's id_layers x multipliers.
      def material_quantities(tallies, database, audit)
        quantities = Hash.new(0.0)
        rows_used = 0

        tallies.each do |edge_type, references|
          next if SKIPPED_EDGE_TYPES.include?(edge_type.to_s)

          normalized = edge_type.to_s
          normalized = 'fenestration' if normalized.match?(FENESTRATION_EDGE)

          references.each do |wall_reference, quantity_m|
            row = database.thermal_bridging.find do |r|
              r['edge_type'] == normalized && r['wall_reference'] == wall_reference
            end
            if row.nil?
              audit&.warn(:costing_thermal_bridging,
                          "no thermal_bridging.csv entry for edge '#{normalized}' with wall reference '#{wall_reference}' — skipped " \
                          "(#{quantity_m.round(2)} m uncosted)")
              next
            end

            rows_used += 1
            ids = row['material_opaque_id_layers'].to_s.split(',')
            multipliers = row['id_layers_quantity_multipliers'].to_s.split(',')
            ids.zip(multipliers).each do |id, scale|
              quantities[id.strip] += scale.to_f * quantity_m
            end
          end
        end
        [quantities, rows_used]
      end
    end
  end
end
