require_relative 'test_helper'

# The AuditLog `ruling:` axis: every entry can cite the adjudicated project
# decision(s) (D-XX) that govern the code path, alongside the `article:` axis
# that cites the code text itself. Untagged entries must stay byte-identical to
# what they were before the axis existed.
class TestAuditLog < Minitest::Test
  def audit
    @audit ||= OpenStudioHVAC::AuditLog.new
  end

  def test_ruling_is_stored_top_level
    audit.decision(:build, 'reference system operates on the proposed operating schedule',
                   article: '8.4.4.7.(1)', ruling: 'D-14')
    entry = audit.entries.first
    assert_equal 'D-14', entry[:ruling], 'ruling lands at the TOP LEVEL of the entry'
    refute entry.key?(:inputs), 'ruling never leaks into inputs'
  end

  def test_ruling_survives_every_level
    audit.decision(:build, 'a decision', ruling: 'D-01')
    audit.info(:build, 'an info', ruling: 'D-02')
    audit.warn(:build, 'a warning', ruling: 'D-03')
    assert_equal %w[D-01 D-02 D-03], audit.entries.map { |e| e[:ruling] }
  end

  def test_untagged_entries_are_unchanged
    audit.decision(:build, 'untagged', article: '8.4.4.1.(1)')
    entry = audit.entries.first
    refute entry.key?(:ruling), 'nil ruling is compacted away — no schema drift for untagged entries'
    assert_equal %i[step action article building level].sort & entry.keys.sort, entry.keys.sort
  end

  def test_multi_ruling_is_one_space_separated_string
    audit.decision(:reference, 'air-leakage default applied', ruling: 'D-19 D-21')
    entry = audit.entries.first
    assert_equal 'D-19 D-21', entry[:ruling]
    assert_equal %w[D-19 D-21], entry[:ruling].scan(/\bD-\d{2}\b/),
                 'the documented consumer parse recovers both ids'
  end

  def test_to_s_appends_ruling_after_the_article_segment
    audit.decision(:build, 'did a thing', article: '8.4.4.7.(1)', ruling: 'D-14')
    line = audit.to_s
    assert_includes line, '| per 8.4.4.7.(1)'
    assert_includes line, '| ruling D-14'
    assert_operator line.index('| per 8.4.4.7.(1)'), :<, line.index('| ruling D-14'),
                    'article segment comes first'
  end

  def test_to_s_omits_the_segment_when_untagged
    audit.decision(:build, 'did a thing', article: '8.4.4.7.(1)')
    refute_includes audit.to_s, 'ruling'
  end

  def test_to_json_carries_the_ruling
    audit.decision(:build, 'did a thing', article: '8.4.4.7.(1)', ruling: 'D-14')
    parsed = JSON.parse(audit.to_json)
    assert_equal 'D-14', parsed.first['ruling']
  end
end
