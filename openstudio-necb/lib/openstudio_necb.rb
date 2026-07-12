require 'openstudio'

# The domain gems: installed as gems, or monorepo siblings during incubation.
begin
  require 'openstudio_hvac'
rescue LoadError
  require File.expand_path('../../openstudio-hvac/lib/openstudio_hvac', __dir__)
end
begin
  require 'openstudio_envelope'
rescue LoadError
  require File.expand_path('../../openstudio-envelope/lib/openstudio_envelope', __dir__)
end

require_relative 'openstudio_necb/version'
require_relative 'openstudio_necb/runner'
require_relative 'openstudio_necb/compliance'

# OpenStudioNECB is the UMBRELLA: it composes the SDK-only domain gems
# (openstudio-hvac reference systems + efficiencies, openstudio-envelope
# prescriptive/reference envelope + thermal bridging) into the NECB Part 8
# performance path — proposed vs reference building energy target (8.4.1.2) —
# with simulation execution (the one place simulation is allowed; the domain
# gems never simulate), unified costing, and ONE AuditLog across everything.
module OpenStudioNECB
  # The shared audit class (openstudio-hvac's and openstudio-envelope's are
  # schema-identical; one instance flows through both).
  AuditLog = OpenStudioHVAC::AuditLog

  # Run the full performance-path pipeline. See Compliance.performance_compliance.
  def self.performance_compliance(model, **kwargs)
    Compliance.performance_compliance(model, **kwargs)
  end
end
