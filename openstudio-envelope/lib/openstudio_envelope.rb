require 'openstudio'

require_relative 'openstudio_envelope/version'
require_relative 'openstudio_envelope/audit_log'
require_relative 'openstudio_envelope/necb/audit_log'
require_relative 'openstudio_envelope/climate'

# OpenStudioEnvelope applies NECB building-envelope requirements to OpenStudio models
# from vendored, article-tagged rule data (data/necb/envelope_rules_<vintage>.json,
# generated/verified offline via the building-codes MCP — zero MCP dependency at
# runtime). SDK-only model manipulation; never executes simulations.
#
# What's in this gem:
#   necb/            — rules lookups, prescriptive Section 3.2 application,
#                      thermal bridging (TBD), reference-envelope transform
#   costing/         — envelope assembly costing + thermal-bridging costing
#   climate.rb       — HDD18 resolution (Table C-1 / .stat) + climate zones
#   constructions.rb / geometry.rb — construction retargeting + surface math
module OpenStudioEnvelope
  module NECB
    RULES_DIR = File.expand_path('openstudio_envelope/data/necb', __dir__)

    # Load the vendored rules for a vintage ('2020', '2025'). Raises on unknown.
    def self.rules(vintage)
      @rules ||= {}
      @rules[vintage.to_s] ||= begin
        path = File.join(RULES_DIR, "envelope_rules_#{vintage}.json")
        raise(ArgumentError, "no NECB envelope rules for vintage '#{vintage}' (expected #{path})") unless File.exist?(path)

        require 'json'
        JSON.parse(File.read(path))
      end
    end
  end
end

require_relative 'openstudio_envelope/necb/rules'
require_relative 'openstudio_envelope/constructions'
require_relative 'openstudio_envelope/geometry'
require_relative 'openstudio_envelope/necb/prescriptive'
require_relative 'openstudio_envelope/necb/thermal_bridging'
require_relative 'openstudio_envelope/necb/reference'
require_relative 'openstudio_envelope/costing/database'
require_relative 'openstudio_envelope/costing/interpolate'
require_relative 'openstudio_envelope/costing/assemblies'
require_relative 'openstudio_envelope/costing/quantify'
require_relative 'openstudio_envelope/costing/envelope_costs'
require_relative 'openstudio_envelope/costing/thermal_bridging_costs'
require_relative 'openstudio_envelope/costing/report'

module OpenStudioEnvelope
  # ---- the public API, in one place ----------------------------------------
  # (Delegators; the implementations live in the files above.)

  # Cost a model's envelope (+ thermal bridging when a TBD result / tallies are
  # given). See Costing.cost for options. Shares the AuditLog schema with
  # openstudio-hvac so one audit spans compliance + HVAC costing + envelope costing.
  def self.cost(model, **kwargs)
    Costing.cost(model, **kwargs)
  end

  # Apply the prescriptive Section 3.2 maximums (U-values, FDWR/SRR by HDD)
  # to a model in place. See NECB::Prescriptive.
  def self.apply_prescriptive(model, **kwargs)
    NECB.apply_prescriptive(model, **kwargs)
  end

  # The performance-path reference-envelope transform (8.4.4.3/.4; 2025:
  # 8.4.5.x) — runs IN PLACE on the caller's clone. See NECB::Reference.
  def self.reference_envelope(model, **kwargs)
    NECB.reference_envelope(model, **kwargs)
  end

  # Resolve heating degree-days (explicit -> Table C-1 -> .stat). See Climate.
  def self.hdd18(model, **kwargs)
    Climate.hdd18(model, **kwargs)
  end
end
