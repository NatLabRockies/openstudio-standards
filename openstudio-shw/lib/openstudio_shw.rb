require 'openstudio'

begin
  require 'openstudio_loads'
rescue LoadError
  require File.expand_path('../../openstudio-loads/lib/openstudio_loads', __dir__)
end

require_relative 'openstudio_shw/version'
require_relative 'openstudio_shw/audit_log'

# OpenStudioSHW applies NECB service water heating to OpenStudio models: per-space
# demand (WaterUseEquipment from the NECB space-type peak flows/temperatures/
# schedules — openstudio-loads data), the legacy-parity auto-sized SHW plant loop
# (WaterHeaterMixed + pump), Part 6 water-heater performance (Table 6.2.2.1,
# NECB2020 UEF procedure), and the 8.4.4.20 reference treatment. SDK-only;
# vendored article-tagged data (MCP-verified offline); shared AuditLog schema.
module OpenStudioSHW
  module NECB
    DATA_DIR = File.expand_path('openstudio_shw/data/necb', __dir__)

    def self.rules(vintage)
      @rules ||= {}
      @rules[vintage.to_s] ||= begin
        path = File.join(DATA_DIR, "shw_rules_#{vintage}.json")
        raise(ArgumentError, "no NECB shw rules for vintage '#{vintage}' (expected #{path})") unless File.exist?(path)

        require 'json'
        JSON.parse(File.read(path))
      end
    end
  end

  # Demand + plant: see NECB::Demand.apply_shw.
  def self.apply_shw(model, **kwargs)
    NECB::Demand.apply_shw(model, **kwargs)
  end
end

require_relative 'openstudio_shw/necb/demand'
require_relative 'openstudio_shw/necb/efficiency'
require_relative 'openstudio_shw/necb/reference'
