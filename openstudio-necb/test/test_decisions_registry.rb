require_relative 'test_helper'

# Drift guards for the decision registry (D-44).
#
# The registry is the runtime-visible mirror of docs/necb_decisions.md: code
# cites decisions with the AuditLog `ruling:` kwarg, and the AHJ report renders
# the ones that fired. Three ways that can rot, all caught here:
#   (a) a decision is added to the doc and never mirrored into the registry;
#   (b) code cites an id that does not exist;
#   (c) an entry claims kind "runtime" but nothing actually cites it.
#
# SDK-free and fast. The code scan degrades to a skip when the sibling gems are
# not on disk (packaged-gem runs).
class TestDecisionsRegistry < Minitest::Test
  Decisions = OpenStudioNECB::Decisions

  MONOREPO = File.expand_path('../..', __dir__)
  GEMS = %w[openstudio-necb openstudio-hvac openstudio-envelope openstudio-loads
            openstudio-lighting openstudio-shw openstudio-geometry].freeze
  DOC = File.expand_path('../docs/necb_decisions.md', __dir__)
  KINDS = %w[runtime runtime_unwired data process].freeze

  # `ruling:` literals are single-quoted and live on ONE line by convention —
  # this scan is why that convention exists.
  RULING_LITERAL = /ruling:\s*'([^']*)'/.freeze

  def gem_sources
    @gem_sources ||= GEMS.filter_map do |gem|
      dir = File.join(MONOREPO, gem, 'lib')
      Dir.glob(File.join(dir, '**', '*.rb')) if File.directory?(dir)
    end.flatten
  end

  # Comment lines are excluded everywhere: the convention is documented with
  # examples ("ruling: 'D-14'") in several files, and prose must not count as a
  # citation or be held to the literal's grammar.
  def code_lines(path)
    File.readlines(path).each_with_index.reject { |line, _| line.lstrip.start_with?('#') }
  end

  def cited_ids
    @cited_ids ||= gem_sources.flat_map do |path|
      code_lines(path).flat_map do |line, _|
        line.scan(RULING_LITERAL).flatten.flat_map { |lit| Decisions.ids_in(lit) }
      end
    end.uniq
  end

  # -- shape ---------------------------------------------------------------

  def test_every_entry_is_well_formed
    Decisions.all.each do |d|
      assert_match(/\AD-\d{2}\z/, d['id'], "malformed id #{d['id'].inspect}")
      refute_empty d['title'].to_s, "#{d['id']} has no title"
      assert_includes KINDS, d['kind'], "#{d['id']} has an unknown kind #{d['kind'].inspect}"
      assert_kind_of Array, d['articles'], "#{d['id']} articles must be an array"
      # 2-3 self-contained sentences: the report shows this text and nothing else
      assert_operator d['summary'].to_s.length, :>, 120, "#{d['id']} summary too short to stand alone"
      assert_operator d['summary'].to_s.scan(/\.\s|\.\z/).size, :>=, 2, "#{d['id']} summary needs >= 2 sentences"
    end
  end

  def test_ids_are_unique
    assert_equal Decisions.ids.uniq, Decisions.ids, 'duplicate id in the registry'
  end

  # -- (a) doc <-> registry ------------------------------------------------

  def test_registry_mirrors_every_decision_heading
    # exactly '## D-XX' — '### D-19 amendment' style sub-headings are updates to
    # an existing decision, not decisions of their own
    doc_ids = File.read(DOC).scan(/^## (D-\d{2})\b/).flatten
    refute_empty doc_ids, 'no decision headings found — is the doc path right?'
    assert_empty doc_ids - Decisions.ids, 'decision(s) in the doc are missing from decisions.json'
    # D-44 documents this feature itself and must also be in the doc
    assert_empty Decisions.ids - doc_ids, 'registry entr(ies) have no ## heading in the doc'
  end

  # -- (b)/(c) code <-> registry -------------------------------------------

  # The id-ordered TOC at the top of the (chronological) decisions doc is
  # generated from the registry — regenerate on drift, never hand-edit.
  def test_decisions_toc_is_current
    script = File.expand_path('../scripts/generate_decisions_toc.rb', __dir__)
    assert system(RbConfig.ruby, script, '--check', out: File::NULL, err: File::NULL),
           'docs/necb_decisions.md TOC is stale — run: ruby scripts/generate_decisions_toc.rb'
  end

  def test_every_cited_id_resolves
    skip 'sibling gems not on disk' if gem_sources.empty?
    unknown = cited_ids - Decisions.ids
    assert_empty unknown, "code cites unregistered decision id(s): #{unknown.join(', ')}"
  end

  def test_every_runtime_entry_is_actually_cited
    skip 'sibling gems not on disk' if gem_sources.empty?
    uncited = Decisions.of_kind('runtime').map { |d| d['id'] } - cited_ids
    assert_empty uncited,
                 "kind:runtime but no `ruling:` literal cites them: #{uncited.join(', ')} " \
                 '(tag the call site, or re-classify the entry)'
  end

  def test_non_runtime_entries_are_not_cited
    skip 'sibling gems not on disk' if gem_sources.empty?
    non_runtime = Decisions.all.reject { |d| d['kind'] == 'runtime' }.map { |d| d['id'] }
    stray = non_runtime & cited_ids
    assert_empty stray, "cited at runtime but not kind:runtime: #{stray.join(', ')}"
  end

  def test_ruling_literals_are_on_one_line_and_well_formed
    skip 'sibling gems not on disk' if gem_sources.empty?
    gem_sources.each do |path|
      code_lines(path).each do |line, i|
        next unless line.include?('ruling:')
        # AuditLog itself: the kwarg default and the passthrough into #add
        next if line =~ /ruling:\s*(nil|ruling)\b/

        assert_match RULING_LITERAL, line,
                     "#{path}:#{i + 1} — ruling: literal must be a single-quoted string on ONE line"
        literal = line[RULING_LITERAL, 1]
        assert_match(/\AD-\d{2}( D-\d{2})*\z/, literal,
                     "#{path}:#{i + 1} — ruling must be space-separated ids, got #{literal.inspect}")
      end
    end
  end

  def test_ruling_is_never_nested_inside_inputs
    skip 'sibling gems not on disk' if gem_sources.empty?
    gem_sources.each do |path|
      code_lines(path).each do |line, i|
        next unless line =~ /inputs:\s*\{[^}]*ruling:/

        flunk "#{path}:#{i + 1} — ruling: must be a TOP-LEVEL kwarg, never inside inputs:"
      end
    end
  end

  # -- loader --------------------------------------------------------------

  def test_ids_in_parses_multi_ruling_strings
    assert_equal %w[D-19 D-21], Decisions.ids_in('D-19 D-21')
    assert_equal ['D-14'], Decisions.ids_in('D-14')
    assert_empty Decisions.ids_in(nil)
    assert_empty Decisions.ids_in('')
    assert_equal ['D-19'], Decisions.ids_in('D-19 D-19'), 'de-duplicated'
  end

  def test_lookup
    assert_equal 'D-14', Decisions.lookup('D-14')['id']
    assert_nil Decisions.lookup('D-99')
  end

  # -- one AuditLog, aliased everywhere ------------------------------------

  # The class itself now lives in openstudio-audit; each family gem's
  # `audit_log.rb` is a three-line ALIAS of it. That alias is the compatibility
  # mechanism for every existing call site, so what has to stay true is not
  # "the copies are byte-identical" (there are no copies any more) but "every
  # gem's constant IS the shared class".
  AUDIT_LOG_ALIASES = {
    'openstudio-hvac' => %w[openstudio_hvac OpenStudioHVAC],
    'openstudio-envelope' => %w[openstudio_envelope OpenStudioEnvelope],
    'openstudio-geometry' => %w[openstudio_geometry OpenStudioGeometry],
    'openstudio-lighting' => %w[openstudio_lighting OpenStudioLighting],
    'openstudio-loads' => %w[openstudio_loads OpenStudioLoads],
    'openstudio-shw' => %w[openstudio_shw OpenStudioSHW]
  }.freeze

  # The umbrella pulls in every domain gem except geometry (it sits upstream of
  # the pipeline), so load whatever is not already resolved from disk.
  def load_family_gem(gem, dir, mod)
    return true if Object.const_defined?(mod)

    facade = File.join(MONOREPO, gem, 'lib', "#{dir}.rb")
    return false unless File.exist?(facade)

    require facade
    Object.const_defined?(mod)
  end

  def test_every_gem_aliases_the_one_shared_audit_log
    resolved = AUDIT_LOG_ALIASES.filter_map do |gem, (dir, mod)|
      next unless load_family_gem(gem, dir, mod)

      assert_same OpenStudioAudit::AuditLog, Object.const_get(mod)::AuditLog,
                  "#{mod}::AuditLog is not the shared OpenStudioAudit::AuditLog — " \
                  'the alias is the compatibility mechanism; a second copy would drift'
      gem
    end
    skip 'sibling gems not on disk' if resolved.size < 2

    assert_equal AUDIT_LOG_ALIASES.size, resolved.size, 'a family gem did not resolve its AuditLog alias'
    assert_same OpenStudioAudit::AuditLog, OpenStudioNECB::AuditLog, 'the umbrella aliases it too'
  end

  def test_the_shared_audit_log_supports_the_ruling_kwarg
    audit = OpenStudioAudit::AuditLog.new
    audit.decision(:build, 'reference system operates on the proposed operating schedule',
                   article: '8.4.4.7.(1)', ruling: 'D-19 D-21')
    entry = audit.entries.first
    assert_equal 'D-19 D-21', entry[:ruling], 'ruling is read back from the TOP LEVEL of the entry'
    refute entry.key?(:inputs), 'ruling never leaks into inputs'
    assert_equal %w[D-19 D-21], Decisions.ids_in(entry[:ruling]), 'and the registry parse recovers both ids'
    assert_includes audit.to_s, '| ruling D-19 D-21'
  end
end
