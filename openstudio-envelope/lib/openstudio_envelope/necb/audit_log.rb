require_relative '../audit_log'

module OpenStudioEnvelope
  module NECB
    # Alias: one gem-wide audit log (same entry schema as OpenStudioHVAC::AuditLog, so
    # a single log can thread through envelope + HVAC reference generation together).
    AuditLog = OpenStudioEnvelope::AuditLog
  end
end
