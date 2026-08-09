# The AuditLog moved to openstudio-audit — one implementation for the whole family.
begin
  require 'openstudio_audit'
rescue LoadError
  require File.expand_path('../../../openstudio-audit/lib/openstudio_audit', __dir__)
end

module OpenStudioSHW
  AuditLog = OpenStudioAudit::AuditLog
end
