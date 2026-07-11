require 'json'

module OpenStudioHVAC
  # The descriptive-name system registry, loaded from data/systems.json.
  # The name is the API: it encodes topology family AND fuel/coil/baseboard choices.
  module Catalog
    SYSTEMS_PATH = File.expand_path('data/systems.json', __dir__)
    SIZING_PATH  = File.expand_path('data/sizing.json', __dir__)

    def self.rows
      @rows ||= JSON.parse(File.read(SYSTEMS_PATH))['systems']
    end

    def self.sizing_blocks
      @sizing_blocks ||= JSON.parse(File.read(SIZING_PATH))['sizing']
    end

    # List catalog entries, optionally filtered by a substring/regexp on the name or a family.
    #
    # @param filter [String, Regexp, nil] name filter
    # @param family [String, nil] family filter (e.g. 'psz')
    # @return [Array<Hash>] matching rows (name, family, ...)
    def self.list(filter: nil, family: nil)
      result = rows
      result = result.select { |r| r['family'] == family } if family
      case filter
      when String then result = result.select { |r| r['name'].downcase.include?(filter.downcase) }
      when Regexp then result = result.select { |r| r['name'] =~ filter }
      end
      result
    end

    # Resolve a descriptive name to its full config (row merged with its sizing block).
    # Raises with close-match suggestions on an unknown name.
    #
    # @param name [String] exact catalog name
    # @return [Hash] config with string keys; ['sizing'] is the resolved sizing block Hash
    def self.resolve(name)
      row = rows.find { |r| r['name'] == name }
      if row.nil?
        words = name.downcase.split(/\s+/)
        suggestions = rows.map { |r| r['name'] }
                          .max_by(3) { |n| words.count { |w| n.downcase.include?(w) } }
        raise(ArgumentError,
              "unknown system name '#{name}'. Closest catalog entries:\n  - #{suggestions.join("\n  - ")}")
      end

      config = row.dup
      if row['sizing'].is_a?(String)
        block = sizing_blocks[row['sizing']]
        raise(ArgumentError, "systems.json row '#{name}' references unknown sizing block '#{row['sizing']}'") if block.nil?

        config['sizing'] = block
      end
      config
    end
  end
end
