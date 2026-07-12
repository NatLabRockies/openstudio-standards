require_relative '../audit_log'

module OpenStudioHVAC
  module NECB
    # Back-compat alias: the audit log started NECB-scoped but serves the whole gem
    # (reference generation AND costing).
    AuditLog = OpenStudioHVAC::AuditLog
  end
end
