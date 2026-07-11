module OpenStudioHVAC
  module Costing
    # The re-costable item ledger (port of the legacy btap_items / cost_list_items model):
    # quantification produces line items {id, quantity, mults, tags}; pricing applies the
    # cost database + regional factors. The same ledger can be re-priced for any city or
    # custom cost database.
    class Ledger
      CATEGORIES = %w[HEATING_COOLING ZONAL VENTILATION DISTRIBUTION].freeze

      attr_reader :items

      def initialize
        @items = []
      end

      # @param id [String, Integer] cost line-item id
      # @param quantity [Numeric]
      # @param tags [Array<String>] category tags (see CATEGORIES) + free-form context tags
      def add(id:, quantity:, tags:, material_mult: 1.0, labour_mult: 1.0, equipment_mult: 1.0, note: nil)
        return if quantity.to_f.zero?

        @items << { 'id' => id.to_s, 'quantity' => quantity.to_f,
                    'material_mult' => material_mult.to_f, 'labour_mult' => labour_mult.to_f,
                    'equipment_mult' => equipment_mult.to_f,
                    'tags' => Array(tags).map(&:to_s), 'note' => note }.compact
      end

      # Add every layer of an assembly row (hvac_vent_ahu-style id_layers x multipliers),
      # scaled by a base quantity.
      def add_assembly(id_layers:, layer_multipliers:, base_quantity:, tags:, note: nil)
        ids = id_layers.to_s.split(',').map(&:strip)
        mults = layer_multipliers.to_s.split(',').map { |m| m.strip.to_f }
        ids.zip(mults).each do |id, mult|
          add(id: id, quantity: base_quantity.to_f * (mult || 1.0), tags: tags, note: note)
        end
      end

      # Price the ledger for a location (port of cost_list_items):
      # item_cost = (mat*matf/100*mat_mult + lab*instf/100*lab_mult + eq*eqf/100*eq_mult) * qty
      #
      # @return [Hash] { 'total' =>, 'by_category' => {cat => cost}, 'items' => priced items }
      def price(database, province_state:, city:)
        by_category = Hash.new(0.0)
        priced = @items.map do |item|
          record = database.cost_record(item['id'])
          mat_f, inst_f, eq_f = database.regional_factors(province_state, city, item['id'])
          cost = (record['materialOpCost'] * (mat_f / 100.0) * item['material_mult'] +
                  record['laborOpCost'] * (inst_f / 100.0) * item['labour_mult'] +
                  record['equipmentOpCost'] * (eq_f / 100.0) * item['equipment_mult']) *
                 item['quantity']
          item['tags'].each { |tag| by_category[tag] += cost if CATEGORIES.include?(tag) }
          item.merge('cost' => cost.round(2))
        end
        { 'province_state' => province_state, 'city' => city,
          'total' => priced.sum { |i| i['cost'] }.round(2),
          'by_category' => by_category.transform_values { |v| v.round(2) },
          'items' => priced }
      end
    end
  end
end
