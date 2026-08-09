require 'openstudio'

# The shared audit machinery (AuditLog + article-coverage emitter) the whole
# family writes to. Installed as a gem, or a monorepo sibling during incubation.
begin
  require 'openstudio_audit'
rescue LoadError
  require File.expand_path('../../openstudio-audit/lib/openstudio_audit', __dir__)
end

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
begin
  require 'openstudio_loads'
rescue LoadError
  require File.expand_path('../../openstudio-loads/lib/openstudio_loads', __dir__)
end
begin
  require 'openstudio_lighting'
rescue LoadError
  require File.expand_path('../../openstudio-lighting/lib/openstudio_lighting', __dir__)
end
begin
  require 'openstudio_shw'
rescue LoadError
  require File.expand_path('../../openstudio-shw/lib/openstudio_shw', __dir__)
end
begin
  require 'openstudio_simulation'
rescue LoadError
  require File.expand_path('../../openstudio-simulation/lib/openstudio_simulation', __dir__)
end

require_relative 'openstudio_necb/version'
require_relative 'openstudio_necb/tiers'
require_relative 'openstudio_necb/decisions'
require_relative 'openstudio_necb/eui_archetypes'
require_relative 'openstudio_necb/compliance'
require_relative 'openstudio_necb/report'

# OpenStudioNECB is the UMBRELLA: it composes the five SDK-only domain gems
# (openstudio-hvac reference systems + efficiencies, openstudio-envelope
# prescriptive/reference envelope + thermal bridging, openstudio-loads NECB
# space-use loads, openstudio-lighting LPD allowances + daylighting,
# openstudio-shw service-water-heating minimums) into the NECB Part 8
# performance path — proposed vs reference building energy target (8.4.1.2) —
# with simulation execution via openstudio-simulation (the one place
# simulation is allowed; the domain gems never simulate), unified costing,
# and ONE AuditLog across everything. The seventh family gem,
# openstudio-geometry, sits UPSTREAM: it creates the model you feed in here.
module OpenStudioNECB
  # The shared audit class, now owned by openstudio-audit: every family gem
  # aliases the SAME class, so one instance flows through all of them.
  AuditLog = OpenStudioAudit::AuditLog

  # Simulation execution now lives in the lowest-level family gem,
  # openstudio-simulation (SDK+CLI, no compliance layer). Alias it so
  # compliance.rb's Runner.attach_weather! / run_energyplus! / clean_run? /
  # energy_results / unmet_occupied_hours keep working unchanged.
  Runner = OpenStudioSimulation::Runner

  # Run the full performance-path pipeline. See Compliance.performance_compliance.
  def self.performance_compliance(model, **kwargs)
    Compliance.performance_compliance(model, **kwargs)
  end
end
