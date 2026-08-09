require 'minitest/autorun'
require 'json'
require_relative '../lib/openstudio_audit'

# The AuditLog `ruling:` axis: every entry can cite the adjudicated project
# decision(s) (D-XX) that govern the code path, alongside the `article:` axis
# that cites the code text itself. Untagged entries must stay byte-identical to
# what they were before the axis existed.
class TestAuditLog < Minitest::Test
  def audit
    @audit ||= OpenStudioAudit::AuditLog.new
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

  def test_warnings_and_building_stamp
    audit.with_building('proposed building') do
      audit.warn(:build, 'something SKIPPED')
      audit.info(:build, 'a note')
    end
    audit.info(:build, 'outside the block')
    assert_equal 1, audit.warnings.size
    assert_equal ['proposed building', 'proposed building', nil], audit.entries.map { |e| e[:building] }
  end
end

# The shared article-coverage emitter: the loop the six gems used to each carry
# a copy of. Status drives level (implemented/satisfied_by_clone/host_scope =>
# info, partial/not_implemented => warning, gap_owner "modeller" => info scope
# note, D-09) and the citation count is a PREFIX match of the run's `article:`
# tags against the manifest article id.
class TestCoverageEmit < Minitest::Test
  def audit
    @audit ||= OpenStudioAudit::AuditLog.new
  end

  COVERAGE = {
    'articles' => [
      { 'article' => '8.4.4.7.', 'title' => 'System selection', 'status' => 'implemented',
        'how' => 'Table 8.4.4.7.-A' },
      { 'article' => '8.4.4.9.', 'title' => 'Staged heating', 'status' => 'partial',
        'how' => 'two stages', 'gaps' => 'modulating burners' },
      { 'article' => '8.4.4.11.', 'title' => 'Something unbuilt', 'status' => 'not_implemented',
        'gaps' => 'everything' },
      { 'article' => '8.4.4.3.', 'title' => 'Envelope carried over', 'status' => 'satisfied_by_clone' },
      { 'article' => '8.4.4.20.', 'title' => 'Service water heating', 'status' => 'host_scope',
        'how' => 'Delegated to openstudio-shw' },
      { 'article' => '8.4.1.1. (HVAC)', 'title' => 'Modeller inputs', 'status' => 'partial',
        'gap_owner' => 'modeller', 'how' => 'schedules read from the model',
        'gaps' => 'occupancy assumptions' }
    ]
  }.freeze

  def emit!
    audit.decision(:build, 'selected system 3', article: '8.4.4.7.(1)')
    audit.decision(:build, 'fan power', article: '8.4.4.7.(4); 8.4.4.18.(2)')
    audit.decision(:build, 'staged coil', article: '8.4.4.9.(7)')
    audit.decision(:build, 'water-side economizer', article: '5.2.2.9.(2)') # non-8.4: never counted
    OpenStudioAudit::Coverage.emit(COVERAGE, audit)
    audit.entries.select { |e| e[:step] == :coverage }
  end

  def test_emits_one_entry_per_article_at_the_right_level
    entries = emit!
    assert_equal 6, entries.size
    assert_equal %i[info warning warning info info info], entries.map { |e| e[:level] },
                 'partial/not_implemented warn; implemented/satisfied_by_clone/host_scope inform; ' \
                 'gap_owner modeller is an info scope note (D-09)'
  end

  def test_citation_counts_are_prefix_matched
    entries = emit!
    counts = entries.to_h { |e| [e[:article], e[:inputs][:decisions_citing]] }
    assert_equal 2, counts['8.4.4.7.'], 'both 8.4.4.7 citations counted'
    assert_equal 1, counts['8.4.4.9.']
    assert_equal 0, counts['8.4.4.11.']
    assert_equal 0, counts['8.4.1.1. (HVAC)'], 'the " (slice label)" suffix is stripped before matching'
  end

  def test_status_and_gap_owner_land_in_inputs
    entries = emit!
    partial = entries.find { |e| e[:article] == '8.4.4.9.' }
    assert_equal 'partial', partial[:inputs][:status]
    refute partial[:inputs].key?(:gap_owner)
    modeller = entries.find { |e| e[:article] == '8.4.1.1. (HVAC)' }
    assert_equal 'modeller', modeller[:inputs][:gap_owner]
    assert_includes modeller[:action], 'modeller scope'
    assert_includes modeller[:action], "Modeller's responsibility: occupancy assumptions"
  end

  def test_action_text_carries_status_how_and_gaps
    entries = emit!
    assert_equal 'System selection — implemented: Table 8.4.4.7.-A',
                 entries.find { |e| e[:article] == '8.4.4.7.' }[:action]
    assert_equal 'Staged heating — partial. Applied: two stages. Gaps: modulating burners',
                 entries.find { |e| e[:article] == '8.4.4.9.' }[:action]
    assert_equal 'Something unbuilt — not implemented. Gaps: everything',
                 entries.find { |e| e[:article] == '8.4.4.11.' }[:action]
    assert_equal 'Service water heating — host scope: Delegated to openstudio-shw',
                 entries.find { |e| e[:article] == '8.4.4.20.' }[:action]
  end

  def test_nil_coverage_is_a_no_op
    OpenStudioAudit::Coverage.emit(nil, audit)
    assert_empty audit.entries
  end
end
