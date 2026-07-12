require 'csv'
require 'json'

module OpenStudioEnvelope
  module Costing
    # The envelope cost database. Vendored UNPRICED sheets (constructions.json,
    # materials_opaque/glazing, thermal_bridging, locations — see data/costing/
    # README.md); the two PRICED tables (costs.csv, costs_local_factors.csv) are
    # deliberately NOT vendored here — they resolve at runtime from explicit
    # arguments or the sibling openstudio-hvac gem's public vendored copies, so
    # priced data never gains another in-repo copy. Real licensed RS-Means values
    # must only ever be injected via costs_csv: and never committed.
    class Database
      DATA_DIR = File.expand_path('../data/costing', __dir__)

      # Candidate directories for the priced tables, in order.
      PRICED_FALLBACK_DIRS = [
        ENV['OPENSTUDIO_COSTING_DIR'],
        File.expand_path('../../../../openstudio-hvac/lib/openstudio_hvac/data/costing', __dir__)
      ].compact.freeze

      attr_reader :warnings, :materials_opaque, :materials_glazing, :constructions,
                  :thermal_bridging, :locations

      # @param costs_csv [String, nil] priced unit-cost table (same columns as the
      #   openstudio-hvac vendored costs.csv); overrides/extends the resolved base
      # @param local_factors_csv [String, nil] city cost-index factors table
      def initialize(costs_csv: nil, local_factors_csv: nil)
        @warnings = []
        @constructions = JSON.parse(File.read(File.join(DATA_DIR, 'constructions.json')))
        @materials_opaque = load_csv(File.join(DATA_DIR, 'materials_opaque.csv'))
        @materials_glazing = load_csv(File.join(DATA_DIR, 'materials_glazing.csv'))
        @thermal_bridging = load_csv(File.join(DATA_DIR, 'thermal_bridging.csv'))
        @locations = load_csv(File.join(DATA_DIR, 'locations.csv'))

        @costs = index_by_id(load_csv(resolve_priced('costs.csv', costs_csv)))
        if costs_csv && File.exist?(base_priced_path('costs.csv').to_s)
          # explicit costs_csv was loaded as base above only when no fallback exists;
          # when both exist the explicit file OVERRIDES row-by-row (hvac-gem contract)
          index_by_id(load_csv(costs_csv)).each { |id, row| @costs[id] = row }
        end
        @local_factors = load_csv(resolve_priced('costs_local_factors.csv', local_factors_csv))
      end

      # Unit-cost record for a line-item id (nil material AND labour raises, matching legacy).
      def cost_record(id)
        row = @costs[id.to_s.upcase]
        raise(ArgumentError, "no costing information available for material id #{id}") if row.nil?

        mat = row['materialOpCost']
        lab = row['laborOpCost']
        if blank?(mat) && blank?(lab)
          raise(ArgumentError, "costing information for material id #{id} is nil — check costing data")
        end

        { 'materialOpCost' => mat.to_f, 'laborOpCost' => lab.to_f,
          'equipmentOpCost' => row['equipmentOpCost'].to_f }
      end

      # Regional cost factors (legacy get_regional_cost_factors): matched on
      # province/city + the item id's 2-char code prefix; 100/100/100 fallback with
      # a recorded warning.
      # @return [Array(Float, Float, Float)] material %, installation %, total %
      def regional_factors(province_state, city, item_id)
        prefix = item_id.to_s[0..1]
        @local_factors.each do |row|
          next unless row['province_state'] == province_state && row['city'] == city
          return [row['material'].to_f, row['installation'].to_f, row['total'].to_f] if row['code_prefix'] == prefix
        end
        warning = "no regional adjustment factor for item #{item_id} (prefix #{prefix}) in #{city}, #{province_state}; using 100/100/100"
        @warnings << warning unless @warnings.include?(warning)
        [100.0, 100.0, 100.0]
      end

      # Nearest cost location to a lat/long (haversine).
      def closest_location(lat, long)
        @locations.min_by { |loc| haversine_m([lat, long], [loc['latitude'].to_f, loc['longitude'].to_f]) }
      end

      # Candidate constructions for a sheet + assembly: { rsi => construction hash
      # (with 'usi', 'name', 'type', 'id_layers') }, RSI ascending.
      def construction_candidates(sheet, assembly_name)
        by_usi = @constructions.dig(sheet, assembly_name, 'usi')
        raise(ArgumentError, "no costed assembly '#{assembly_name}' in constructions sheet '#{sheet}'") if by_usi.nil?

        by_usi.map do |usi, construction|
          [1.0 / usi.to_f, construction.merge('name' => assembly_name, 'usi' => usi.to_f)]
        end.sort_by(&:first).to_h
      end

      def materials_sheet(type)
        type.to_s == 'glazing' ? @materials_glazing : @materials_opaque
      end

      private

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def base_priced_path(filename)
        PRICED_FALLBACK_DIRS.map { |d| File.join(d, filename) }.find { |p| File.exist?(p) }
      end

      def resolve_priced(filename, explicit)
        base = base_priced_path(filename)
        return base if base # explicit costs_csv then overrides row-by-row in initialize
        return explicit if explicit && File.exist?(explicit)

        raise(ArgumentError,
              "#{filename} not found. Priced cost tables are not vendored in openstudio-envelope " \
              '(see data/costing/README.md) — pass costs_csv:/local_factors_csv:, set ' \
              'OPENSTUDIO_COSTING_DIR, or install alongside the openstudio-hvac gem.')
      end

      def load_csv(path)
        CSV.read(path, headers: true).map(&:to_h)
      end

      def index_by_id(rows)
        rows.each_with_object({}) { |row, map| map[row['id'].to_s.upcase] = row }
      end

      def haversine_m(loc1, loc2)
        rad = Math::PI / 180
        dlat = (loc2[0] - loc1[0]) * rad
        dlon = (loc2[1] - loc1[1]) * rad
        a = Math.sin(dlat / 2)**2 +
            Math.cos(loc1[0] * rad) * Math.cos(loc2[0] * rad) * Math.sin(dlon / 2)**2
        6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      end
    end
  end
end
