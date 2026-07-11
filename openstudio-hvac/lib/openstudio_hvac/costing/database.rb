require 'csv'
require 'json'

module OpenStudioHVAC
  module Costing
    # The cost database: vendored placeholder CSVs (RS-Means-derived schema; see
    # data/costing/README.md) with runtime injection of licensed values via costs_csv.
    # Ports the openstudio-standards BTAPCosting data/localization semantics.
    class Database
      DATA_DIR = File.expand_path('../data/costing', __dir__)

      attr_reader :warnings

      # @param costs_csv [String, nil] path to a custom costs CSV (same columns as the
      #   vendored costs.csv) whose rows override/extend the placeholder values
      def initialize(costs_csv: nil)
        @warnings = []
        @costs = index_by_id(load_csv(File.join(DATA_DIR, 'costs.csv')))
        if costs_csv
          index_by_id(load_csv(costs_csv)).each { |id, row| @costs[id] = row }
        end
        @materials_hvac = load_csv(File.join(DATA_DIR, 'materials_hvac.csv'))
        @ahu_assemblies = load_csv(File.join(DATA_DIR, 'hvac_vent_ahu.csv'))
        @local_factors = load_csv(File.join(DATA_DIR, 'costs_local_factors.csv'))
        @locations = load_csv(File.join(DATA_DIR, 'locations.csv'))
        @mech_sizing = JSON.parse(File.read(File.join(DATA_DIR, 'mech_sizing.json')))
      end

      attr_reader :materials_hvac, :ahu_assemblies, :mech_sizing, :locations

      # Unit-cost record for a line-item id (nil material AND labour raises, matching legacy).
      # @return [Hash] { 'materialOpCost' =>, 'laborOpCost' =>, 'equipmentOpCost' => Float }
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

      # Regional cost factors for a line item in a city (legacy get_regional_cost_factors):
      # matched on province/city + the item id's 2-char code prefix; 100/100/100 fallback
      # with a recorded warning.
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

      # Nearest cost location to a lat/long (haversine; legacy get_closest_cost_location).
      # @return [Hash] { 'province_state' =>, 'city' =>, ... }
      def closest_location(lat, long)
        @locations.min_by { |loc| haversine_m([lat, long], [loc['latitude'].to_f, loc['longitude'].to_f]) }
      end

      # HVAC material rows matching a Material name (and optional Size/Fuel selectors).
      def materials(material, size: nil, fuel: nil)
        rows = @materials_hvac.select { |r| r['Material'] == material }
        rows = rows.select { |r| r['Size'].to_s == size.to_s } if size
        rows = rows.select { |r| r['Fuel'].to_s == fuel.to_s } if fuel
        rows
      end

      private

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
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
