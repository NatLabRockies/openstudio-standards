module OpenStudioLoads
  module NECB
    # Access to the vendored NECB space-type records (data/necb/space_types_<v>.json).
    # Records are keyed the legacy way: (building_type, space_type) — the pair the
    # OpenStudio SpaceType carries as standardsBuildingType/standardsSpaceType.
    module SpaceTypes
      module_function

      # @return [Hash] the full 80-key record (raises on unknown pair)
      def record(building_type:, space_type:, vintage: '2020')
        row = find(building_type: building_type, space_type: space_type, vintage: vintage)
        if row.nil?
          raise(ArgumentError,
                "no NECB #{vintage} space type ['#{building_type}', '#{space_type}'] — " \
                "see OpenStudioLoads::NECB::SpaceTypes.list(vintage: '#{vintage}')")
        end
        row
      end

      # @return [Hash, nil]
      def find(building_type:, space_type:, vintage: '2020')
        NECB.table(vintage, 'space_types').find do |r|
          r['building_type'] == building_type && r['space_type'] == space_type
        end
      end

      # @return [Array<Array(String, String)>] all (building_type, space_type) pairs
      def list(vintage: '2020')
        NECB.table(vintage, 'space_types').map { |r| [r['building_type'], r['space_type']] }
      end

      def undefined?(record)
        record['necb_hvac_system_selection_type'] == '- undefined -'
      end
    end
  end
end
