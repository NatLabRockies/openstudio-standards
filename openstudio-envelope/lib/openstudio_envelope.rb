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
# Phased build-out (see plan): P1 data (this commit) -> P2 lookups + HDD ->
# P3 prescriptive application + FDWR/SRR -> P3b thermal bridging (TBD) ->
# P4 reference envelope (8.4.4.3/.4).
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
