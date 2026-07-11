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

    # Map of canonical (generated) name -> row. Canonical names are an equal-class resolver
    # key alongside the legacy names; a collision with a legacy name would be a bug.
    def self.canonical_map
      @canonical_map ||= begin
        map = {}
        rows.each do |row|
          canonical = Canonical.name(row)
          raise("canonical name collision: '#{canonical}'") if map.key?(canonical) || rows.any? { |r| r['name'] == canonical }

          map[canonical] = row
        end
        map
      end
    end

    # List catalog entries, optionally filtered by a substring/regexp on the name or a family.
    # Each row includes its generated 'canonical_name' (the consolidated grammar).
    #
    # @param filter [String, Regexp, nil] name filter (matches legacy OR canonical name)
    # @param family [String, nil] family filter (e.g. 'psz')
    # @return [Array<Hash>] matching rows (name, canonical_name, family, ...)
    def self.list(filter: nil, family: nil)
      result = rows.map { |r| r.merge('canonical_name' => Canonical.name(r)) }
      result = result.select { |r| r['family'] == family } if family
      case filter
      when String
        f = filter.downcase
        result = result.select { |r| r['name'].downcase.include?(f) || r['canonical_name'].downcase.include?(f) }
      when Regexp
        result = result.select { |r| r['name'] =~ filter || r['canonical_name'] =~ filter }
      end
      result
    end

    # Resolve a descriptive name to its full config (row merged with its sizing block).
    # Accepts the legacy catalog name, the generated canonical name, or a row alias.
    # Raises with close-match suggestions on an unknown name.
    #
    # @param name [String] legacy name, canonical name, or alias
    # @return [Hash] config with string keys; ['sizing'] is the resolved sizing block Hash
    def self.resolve(name)
      row = rows.find { |r| r['name'] == name || (r['aliases'] || []).include?(name) }
      row ||= canonical_map[name]
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
