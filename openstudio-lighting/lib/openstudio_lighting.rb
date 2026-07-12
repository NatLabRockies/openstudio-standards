require 'openstudio'

# The loads gem is the canonical NECB space-type data owner and schedule builder.
begin
  require 'openstudio_loads'
rescue LoadError
  require File.expand_path('../../openstudio-loads/lib/openstudio_loads', __dir__)
end

require_relative 'openstudio_lighting/version'
require_relative 'openstudio_lighting/audit_log'

# OpenStudioLighting applies NECB Part 4 interior lighting to OpenStudio models:
# LPD allowances (4.2.1.5/4.2.1.6 via the space-type records), the LED
# alternative, atrium height rules, and the NECB2015-lineage occupancy-sensor
# lighting-schedule synthesis (Table 4.3.2.10 factors). Reference-building
# lighting per 8.4.4.5. SDK-only; vendored article-tagged data (verified via the
# building-codes MCP offline); shared AuditLog schema with the sibling gems.
module OpenStudioLighting
  module NECB
    DATA_DIR = File.expand_path('openstudio_lighting/data/necb', __dir__)

    def self.rules(vintage)
      @rules ||= {}
      @rules[vintage.to_s] ||= begin
        path = File.join(DATA_DIR, "lighting_rules_#{vintage}.json")
        raise(ArgumentError, "no NECB lighting rules for vintage '#{vintage}' (expected #{path})") unless File.exist?(path)

        require 'json'
        JSON.parse(File.read(path))
      end
    end

    def self.data_vintage(vintage)
      rules(vintage)['data_vintage_alias'] || vintage.to_s
    end

    def self.table(name)
      @tables ||= {}
      @tables[name] ||= begin
        require 'json'
        JSON.parse(File.read(File.join(DATA_DIR, "#{name}.json")))['table']
      end
    end

    # The merged LED alternative table (lighting_per_area W/ft2 + heat fractions).
    def self.led_record(building_type:, space_type:)
      table('led_lighting_2020').find do |r|
        r['building_type'] == building_type && r['space_type'] == space_type
      end
    end
  end

  # Apply NECB interior lighting to every tagged space type. See NECB::ApplyLights.
  def self.apply_lights(model, **kwargs)
    NECB.apply_lights(model, **kwargs)
  end
end

require_relative 'openstudio_lighting/necb/apply_lights'
require_relative 'openstudio_lighting/necb/exterior'
require_relative 'openstudio_lighting/necb/reference'
