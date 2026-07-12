require 'openstudio'

require_relative 'openstudio_hvac/version'
require_relative 'openstudio_hvac/audit_log'
require_relative 'openstudio_hvac/validation'
require_relative 'openstudio_hvac/teardown'
require_relative 'openstudio_hvac/naming'
require_relative 'openstudio_hvac/canonical'
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
require_relative 'openstudio_hvac/systems/mau_ptac'
require_relative 'openstudio_hvac/systems/baseboards_only'
require_relative 'openstudio_hvac/components/ecm_air'
require_relative 'openstudio_hvac/systems/doas_pthp'
require_relative 'openstudio_hvac/systems/ashp_baseboard'
require_relative 'openstudio_hvac/systems/doas_vrf'
require_relative 'openstudio_hvac/systems/hp_plant_fancoils'
require_relative 'openstudio_hvac/systems/zone_terminal'
require_relative 'openstudio_hvac/systems/small_systems'
require_relative 'openstudio_hvac/costing/database'
require_relative 'openstudio_hvac/costing/ledger'
require_relative 'openstudio_hvac/costing/geometry'
require_relative 'openstudio_hvac/costing/quantify_equipment'
require_relative 'openstudio_hvac/costing/ventilation'
require_relative 'openstudio_hvac/costing/report'
require_relative 'openstudio_hvac/necb/audit_log'
require_relative 'openstudio_hvac/necb/reference'
require_relative 'openstudio_hvac/necb/efficiency'
require_relative 'openstudio_hvac/necb/checker'
require_relative 'openstudio_hvac/classify'
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

  # HVAC capital costing on a SIZED model. See Costing.cost.
  def self.cost(model, **kwargs)
    Costing.cost(model, **kwargs)
  end

  # Characterize ANY model's HVAC into a neutral, serializable facts hash
  # (zone groups, energy types, heat pumps, purchased energy, plants).
  # See Classify.characterize.
  #
  # @param model [OpenStudio::Model::Model]
  # @param audit [NECB::AuditLog, nil] records evidence for every conclusion
  # @return [Hash] the facts schema
  def self.characterize(model, audit: nil)
    Classify.characterize(model, audit: audit)
  end

  # Replace whatever HVAC currently serves these zones with a catalog system
  # (zone-scoped teardown + build_system).
  def self.replace_system(model, system_name, zones, **kwargs)
    Builder.build_system(model, system_name, zones, **kwargs, remove_existing: true)
  end
end
