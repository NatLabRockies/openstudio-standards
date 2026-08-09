require_relative 'openstudio_audit/log'
require_relative 'openstudio_audit/coverage'

# OpenStudioAudit is the shared audit machinery of the NECB gem family: the ONE
# `AuditLog` class (entry schema, `building:` stamping, `article:`/`ruling:`
# citation axes, JSON + narrative rendering) and the ONE article-coverage
# emitter every gem runs at the end of its happy path.
#
# It carries no domain knowledge and no OpenStudio dependency — it is the
# lowest-level gem in the family, required by all of hvac, envelope, loads,
# lighting, shw, geometry and the openstudio-necb umbrella. Each of those
# aliases the class into its own namespace (`OpenStudioHVAC::AuditLog =
# OpenStudioAudit::AuditLog`), so every existing call site keeps working; the
# aliases are the compatibility mechanism, not a second implementation.
module OpenStudioAudit
  VERSION = '0.1.0'.freeze
end
