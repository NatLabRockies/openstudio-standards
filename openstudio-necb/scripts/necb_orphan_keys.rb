#!/usr/bin/env ruby
# frozen_string_literal: true

# Orphan rule-key lint.
#
# Every top-level key in a gem's `*_rules_*.json` is either a RULE (something
# lib/ reads to make a NECB decision) or DOCUMENTATION (units, notes, change
# logs). A rule key that no .rb file reads is dead config: the behaviour is
# either missing, or — more often here — implemented with the value hardcoded
# somewhere else, so the JSON and the code can silently disagree.
#
# Documentation keys must be declared explicitly in the JSON as
# `"non_rule_keys": [...]`. Exemptions are reviewable in a diff rather than
# inferred from a naming convention.
#
# Pure Ruby: no OpenStudio SDK, no gems. Safe to run anywhere.
#
#   ruby openstudio-necb/scripts/necb_orphan_keys.rb          # report + exit 1 on findings
#   ruby openstudio-necb/scripts/necb_orphan_keys.rb --quiet  # exit code only

require 'json'

ROOT = File.expand_path('../..', __dir__)
META_KEYS = %w[provenance article_coverage non_rule_keys].freeze

# Read the article_coverage manifest so the remedy can reflect what the gem
# has ALREADY declared about the article a key belongs to. A key backing an
# article that is honestly declared `partial`/`not_implemented` is dead config,
# not concealed non-coverage — a different fix, and a much lower severity.
def coverage_statuses(data)
  entries = data['article_coverage']
  entries = entries['articles'] if entries.is_a?(Hash) && entries.key?('articles')
  return {} unless entries

  list = entries.is_a?(Hash) ? entries.map { |a, v| (v.is_a?(Hash) ? v : {}).merge('article' => a) } : entries
  list.to_h { |e| [e['article'].to_s, e['status'].to_s] }
end

# A key is "consumed" if its literal appears as a string or symbol in any .rb
# outside data/. Every rule access in these gems is a literal fetch, so a plain
# scan is sufficient — no need to instrument Hash reads.
def consumed?(key, source)
  source.include?("'#{key}'") || source.include?("\"#{key}\"") || source.match?(/:#{Regexp.escape(key)}\b/)
end

def gem_sources(gem_dir)
  Dir.glob(File.join(gem_dir, 'lib/**/*.rb'))
     .reject { |p| p.include?('/data/') }
     .map { |p| File.read(p, encoding: 'UTF-8', invalid: :replace, undef: :replace) }
     .join("\n")
end

quiet = ARGV.include?('--quiet')
findings = []

Dir.glob(File.join(ROOT, 'openstudio-*')).sort.select { |d| File.directory?(d) }.each do |gem_dir|
  rulesets = Dir.glob(File.join(gem_dir, 'lib/**/data/**/*_rules_*.json'))
  next if rulesets.empty?

  source = gem_sources(gem_dir)
  gem_name = File.basename(gem_dir)

  # Union keys across vintages: a key consumed in one vintage's code path is
  # consumed, but each file declares its own documentation exemptions.
  keys = {}
  statuses = {}
  rulesets.sort.each do |path|
    data = JSON.parse(File.read(path))
    exempt = Array(data['non_rule_keys'])
    statuses.merge!(coverage_statuses(data))
    (data.keys - META_KEYS - exempt).each { |k| (keys[k] ||= []) << File.basename(path) }
  end

  keys.sort.each do |key, files|
    next if consumed?(key, source)

    # Which articles cite this key? Used only to soften the remedy text.
    related = statuses.select { |_, s| %w[partial not_implemented].include?(s) }
    findings << { gem: gem_name, key: key, files: files.uniq, declared_partial: related.any? }
  end
end

unless quiet
  if findings.empty?
    puts 'necb_orphan_keys: OK — every rule key is read by lib/'
  else
    puts "necb_orphan_keys: #{findings.size} unconsumed rule key(s)\n\n"
    findings.group_by { |f| f[:gem] }.each do |gem_name, group|
      puts gem_name
      group.each { |f| puts format('  %-28s declared in %s', f[:key], f[:files].join(', ')) }
      puts
    end
    puts <<~REMEDY
      Each key above is declared as rule data but never read. Pick one:

        1. WIRE IT UP   — the behaviour exists but reads a hardcoded constant
                          instead of this data. Point the code at the JSON so
                          the two cannot drift. (Most common cause here.)
        2. IMPLEMENT    — the behaviour is genuinely missing. Build it.
        3. DECLARE IT   — the behaviour is deliberately absent. Ensure the
                          article's status is `partial`/`not_implemented` with
                          `gaps`, and delete the dead block.
        4. EXEMPT IT    — the key is documentation, not a rule. Add it to
                          `non_rule_keys` in that JSON.

      A key whose article is ALREADY declared partial/not_implemented is dead
      config, not hidden non-coverage — prefer remedy 3 or 4 there.
    REMEDY
  end
end

exit(findings.empty? ? 0 : 1)
