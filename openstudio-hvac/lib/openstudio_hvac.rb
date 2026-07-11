require 'openstudio'

require_relative 'openstudio_hvac/version'
require_relative 'openstudio_hvac/validation'
require_relative 'openstudio_hvac/teardown'
require_relative 'openstudio_hvac/naming'
require_relative 'openstudio_hvac/catalog'
require_relative 'openstudio_hvac/components/curves'
require_relative 'openstudio_hvac/components/coils'
require_relative 'openstudio_hvac/components/schedules'
require_relative 'openstudio_hvac/systems/base_system'
require_relative 'openstudio_hvac/systems/plant_loops'
require_relative 'openstudio_hvac/systems/baseboards'
require_relative 'openstudio_hvac/systems/psz'
require_relative 'openstudio_hvac/systems/vav_reheat'
require_relative 'openstudio_hvac/systems/fan_coils'
require_relative 'openstudio_hvac/builder'

# OpenStudioHVAC builds HVAC system topologies on OpenStudio thermal zones by
# descriptive, fuel-encoding system name. Topology only — sizing runs and code
# efficiency application are the host application's job.
module OpenStudioHVAC
  # List the system catalog (MCP/tool-friendly: names are a closed, validated vocabulary).
  #
  # @param filter [String, Regexp, nil] name filter
  # @param family [String, nil] family filter
  # @return [Array<Hash>]
  def self.systems(filter: nil, family: nil)
    Catalog.list(filter: filter, family: family)
  end

  # Build a system by descriptive name. See Builder.build_system.
  def self.build_system(model, system_name, zones, **kwargs)
    Builder.build_system(model, system_name, zones, **kwargs)
  end

  # Zone-scoped teardown. See Teardown.remove_hvac_from_zones.
  def self.remove_hvac_from_zones(model, zones)
    Teardown.remove_hvac_from_zones(model, zones)
  end
end
