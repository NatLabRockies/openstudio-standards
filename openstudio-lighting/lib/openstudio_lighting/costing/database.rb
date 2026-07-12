require 'csv'

module OpenStudioLighting
  module Costing
    # Lighting cost database: vendored UNPRICED sheets (lighting_sets / lighting /
    # materials_lighting — none carry dollar values); the PRICED tables (costs.csv,
    # costs_local_factors.csv) resolve at runtime exactly like the
    # openstudio-envelope gem: explicit args, OPENSTUDIO_COSTING_DIR, or the
    # sibling openstudio-hvac gem's public vendored copies. Licensed values are
    # runtime-injected only and never committed.
    class Database
      DATA_DIR = File.expand_path('../data/costing', __dir__)
      PRICED_FALLBACK_DIRS = [
        ENV['OPENSTUDIO_COSTING_DIR'],
        File.expand_path('../../../../openstudio-hvac/lib/openstudio_hvac/data/costing', __dir__)
      ].compact.freeze

      attr_reader :lighting_sets, :lighting, :materials_lighting, :warnings

      def initialize(costs_csv: nil, local_factors_csv: nil)
        @warnings = []
        @lighting_sets = load_csv(File.join(DATA_DIR, 'lighting_sets.csv'))
        @lighting = load_csv(File.join(DATA_DIR, 'lighting.csv'))
        @materials_lighting = load_csv(File.join(DATA_DIR, 'materials_lighting.csv'))
        @costs = index_by_id(load_csv(resolve_priced('costs.csv', costs_csv)))
        index_by_id(load_csv(costs_csv)).each { |id, row| @costs[id] = row } if costs_csv && File.exist?(costs_csv)
        @local_factors = load_csv(resolve_priced('costs_local_factors.csv', local_factors_csv))
        @locations = load_csv(File.join(PRICED_FALLBACK_DIRS.last, 'locations.csv')) rescue []
      end

      def cost_record(id)
        row = @costs[id.to_s.upcase]
        raise(ArgumentError, "no costing information for material id #{id}") if row.nil?

        { 'materialOpCost' => row['materialOpCost'].to_f, 'laborOpCost' => row['laborOpCost'].to_f,
          'equipmentOpCost' => row['equipmentOpCost'].to_f }
      end

      def regional_factors(province_state, city, item_id)
        prefix = item_id.to_s[0..1]
        @local_factors.each do |row|
          next unless row['province_state'] == province_state && row['city'] == city
          return [row['material'].to_f, row['installation'].to_f] if row['code_prefix'] == prefix
        end
        warning = "no regional adjustment factor for item #{item_id} (prefix #{prefix}) in #{city}, #{province_state}; using 100/100"
        @warnings << warning unless @warnings.include?(warning)
        [100.0, 100.0]
      end

      def closest_location(lat, long)
        return nil if @locations.empty?

        rad = Math::PI / 180
        @locations.min_by do |loc|
          dlat = (loc['latitude'].to_f - lat) * rad
          dlon = (loc['longitude'].to_f - long) * rad
          Math.sin(dlat / 2)**2 + Math.cos(lat * rad) * Math.cos(loc['latitude'].to_f * rad) * Math.sin(dlon / 2)**2
        end
      end

      private

      def resolve_priced(filename, explicit)
        base = PRICED_FALLBACK_DIRS.map { |d| File.join(d, filename) }.find { |p| File.exist?(p) }
        return base if base
        return explicit if explicit && File.exist?(explicit)

        raise(ArgumentError, "#{filename} not found — pass costs_csv:/local_factors_csv:, set " \
                             'OPENSTUDIO_COSTING_DIR, or install alongside the openstudio-hvac gem')
      end

      def load_csv(path)
        CSV.read(path, headers: true).map(&:to_h)
      end

      def index_by_id(rows)
        rows.each_with_object({}) { |row, map| map[row['id'].to_s.upcase] = row }
      end
    end
  end
end
