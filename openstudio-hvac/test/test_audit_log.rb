require_relative 'test_helper'

# The AuditLog implementation moved to the openstudio-audit gem; this gem keeps
# the historic constant as an ALIAS (lib/openstudio_hvac/audit_log.rb), which is
# the whole compatibility mechanism for every `OpenStudioHVAC::AuditLog` call
# site in the gem. The behaviour suite lives in openstudio-audit/test/test_audit.rb —
# what this file guards is that the alias resolves and still carries the
# `ruling:` axis (D-44).
class TestAuditLog < Minitest::Test
  def test_the_gem_constant_is_the_shared_class
    assert_same OpenStudioAudit::AuditLog, OpenStudioHVAC::AuditLog,
                'OpenStudioHVAC::AuditLog is an alias of the openstudio-audit class, not a copy'
    assert_same OpenStudioAudit::AuditLog, OpenStudioHVAC::NECB::AuditLog,
                'the NECB-scoped back-compat alias resolves to the same class'
  end

  def test_the_ruling_kwarg_still_works_through_the_alias
    audit = OpenStudioHVAC::AuditLog.new
    audit.decision(:build, 'reference system operates on the proposed operating schedule',
                   article: '8.4.4.7.(1)', ruling: 'D-14')
    entry = audit.entries.first
    assert_equal 'D-14', entry[:ruling], 'ruling lands at the TOP LEVEL of the entry'
    refute entry.key?(:inputs), 'ruling never leaks into inputs'
    assert_includes audit.to_s, '| ruling D-14'
  end
end
