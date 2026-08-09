require 'openstudio'

require_relative 'openstudio_loads/version'
require_relative 'openstudio_loads/audit_log'

# OpenStudioLoads applies NECB space-use data to OpenStudio models — internal
# loads (people, plug/gas equipment), ventilation outdoor air, modelling
# infiltration, the NECB-<letter> schedule sets and thermostat set-points — from
# vendored, article-tagged data (NECB 8.4.3.2; generated/verified offline via the
# building-codes MCP, zero MCP dependency at runtime). SDK-only; never simulates.
#
# Deliberate boundaries (sibling gems): Part 4 LPD allowances + daylighting ->
# openstudio-lighting; Part 6 SHW demand + efficiencies -> openstudio-shw;
# HVAC systems -> openstudio-hvac; envelope -> openstudio-envelope.
module OpenStudioLoads
  module NECB
    DATA_DIR = File.expand_path('openstudio_loads/data/necb', __dir__)

    # Vintage rules (provenance + coverage manifest). '2025' aliases the 2020
    # data tables (values verified identical; citations renumbered).
    def self.rules(vintage)
      @rules ||= {}
      @rules[vintage.to_s] ||= begin
        path = File.join(DATA_DIR, "loads_rules_#{vintage}.json")
        raise(ArgumentError, "no NECB loads rules for vintage '#{vintage}' (expected #{path})") unless File.exist?(path)

        require 'json'
        JSON.parse(File.read(path))
      end
    end

    # The vintage whose data tables back this vintage (2025 -> 2020).
    def self.data_vintage(vintage)
      rules(vintage)['data_vintage_alias'] || vintage.to_s
    end

    def self.table(vintage, name)
      @tables ||= {}
      key = [data_vintage(vintage), name]
      @tables[key] ||= begin
        require 'json'
        JSON.parse(File.read(File.join(DATA_DIR, "#{name}_#{key[0]}.json")))['table']
      end
    end
  end

  # Assign NECB space types to a bare-geometry model. See NECB::Apply.
  def self.assign_space_types(model, map, vintage: '2020', audit: nil)
    NECB::Apply.assign_space_types(model, map, vintage: vintage, audit: audit)
  end

  # THE gem's verb: apply the NECB space-use loads (people, equipment,
  # ventilation OA, infiltration, schedules, thermostats) to every tagged
  # space type. Deliberately excludes lighting (openstudio-lighting) and SHW
  # (openstudio-shw). See NECB::Apply.apply_loads.
  def self.apply_loads(model, vintage: '2020', audit: nil)
    NECB.apply_loads(model, vintage: vintage, audit: audit)
  end
end

require_relative 'openstudio_loads/necb/space_types'
require_relative 'openstudio_loads/schedules'
require_relative 'openstudio_loads/necb/apply'
