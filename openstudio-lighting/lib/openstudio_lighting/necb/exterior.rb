require 'json'

module OpenStudioLighting
  module NECB
    # Exterior lighting power allowances — NECB 4.2.3.1 (Tables -A..-E), a
    # greenfield implementation (legacy only carries prototype-specific exterior
    # wattages; it never computes the code allowance).
    #
    # The allowance = basic site allowance (Table -B) + tradable allowances
    # (Table -D, x quantities, tradable among themselves) + non-tradable
    # allowances (Table -C, per-application caps). Zone 0 has no allowances.
    module Exterior
      module_function

      def data
        @data ||= JSON.parse(File.read(File.join(NECB::DATA_DIR, 'exterior_lighting_2020.json')))
      end

      # Compute the exterior lighting power allowance.
      # @param zone [Integer, String] exterior lighting zone 0..4 (Table -A)
      # @param quantities [Hash] table keys => quantity (m2, m, or count per the
      #   row's unit), e.g. { 'parking_and_drives_m2' => 500, 'entrances_exits_m' => 12 }
      # @return [Hash] { 'basic_site_w', 'tradable_w', 'non_tradable_w', 'total_w', 'lines' }
      def allowance(zone:, quantities:, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        zone_key = zone.to_s
        raise(ArgumentError, "unknown exterior lighting zone '#{zone}' (0..4)") unless data['basic_site_allowance_w'].key?(zone_key)

        basic = data['basic_site_allowance_w'][zone_key].to_f
        lines = []
        unknown = quantities.keys.map(&:to_s) -
                  (data['tradable'] + data['non_tradable']).map { |r| r['key'] }
        unknown.each do |key|
          audit.warn(:lighting_exterior, "unknown exterior application '#{key}' — not in Tables 4.2.3.1.-C/-D; skipped")
        end

        tradable_w = sum_rows(data['tradable'], quantities, zone_key, lines, audit)
        non_tradable_w = sum_rows(data['non_tradable'], quantities, zone_key, lines, audit)
        total = basic + tradable_w + non_tradable_w

        audit.decision(:lighting_exterior, 'exterior lighting power allowance computed',
                       inputs: { zone: zone_key, basic_site_w: basic, tradable_w: tradable_w.round(1),
                                 non_tradable_w: non_tradable_w.round(1) },
                       value: "#{total.round(1)} W (tradable allowances may be traded among tradable applications; non-tradable are per-application caps)",
                       article: '4.2.3.1.')
        { 'basic_site_w' => basic, 'tradable_w' => tradable_w.round(1),
          'non_tradable_w' => non_tradable_w.round(1), 'total_w' => total.round(1), 'lines' => lines }
      end

      def sum_rows(rows, quantities, zone_key, lines, audit)
        total = 0.0
        rows.each do |row|
          quantity = quantities[row['key']] || quantities[row['key'].to_sym]
          next if quantity.nil? || quantity.to_f.zero?

          rate = row['by_zone'][zone_key]
          if rate.nil?
            audit.warn(:lighting_exterior,
                       "no allowance for '#{row['application']}' in lighting zone #{zone_key} — 0 W",
                       article: '4.2.3.1.')
            next
          end
          watts = rate.to_f * quantity.to_f
          lines << { 'application' => row['application'], 'unit' => row['unit'],
                     'rate' => rate.to_f, 'quantity' => quantity.to_f, 'watts' => watts.round(1) }
          total += watts
        end
        total
      end

      # Create an ExteriorLights object at the given design wattage with
      # astronomical-clock control (lights off in daylight).
      def apply_exterior_lights(model, watts, name: 'NECB Exterior Lighting', audit: nil)
        definition = OpenStudio::Model::ExteriorLightsDefinition.new(model)
        definition.setName("#{name} Definition")
        definition.setDesignLevel(watts.to_f)
        lights = OpenStudio::Model::ExteriorLights.new(definition)
        lights.setName(name)
        lights.setControlOption('AstronomicalClock')
        audit&.decision(:lighting_exterior, 'exterior lights created (astronomical clock control)',
                        inputs: { design_w: watts.to_f.round(1) }, article: '4.2.3.1.')
        lights
      end
    end
  end
end
