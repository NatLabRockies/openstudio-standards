#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates NECB_8_4_COVERAGE.html — how Section 8.4 (Performance Path) is
# covered by the gem family, article by article down to sentence/clause text,
# with links to the source.
#
#   ruby scripts/generate_necb_8_4_coverage.rb          (or: rake necb:coverage_doc)
#
# Inputs, each independent and joined here:
#
#   1. data/necb/necb_8_4_articles_2025.json — every Section 8.4 article's
#      requirement text, parsed into a sentence/clause tree with strict sanity
#      checks (scripts/fetch_necb_8_4_text.rb). This is the DENOMINATOR: all 57
#      articles render, so coverage cannot be overstated by omission.
#   2. openstudio-*/lib/**/data/necb/*_rules_*.json article_coverage manifests
#      (including the umbrella's), vintage-directionally canonicalized to 2025
#      numbering.
#   3. `article:` citations in lib/**/*.rb, classified by the audit call they
#      sit on (warn vs decision/info). A citation proves a LOG LINE mentions
#      the article — nothing more. It is never rendered as "implemented".
#   4. audit.json files from real pipeline runs (env NECB_AUDIT_JSONS,
#      colon-separated run dirs) — articles observed cited AT RUNTIME, the
#      strongest evidence tier available here.
#   5. scripts/necb_8_4_disposition.json — curated engine/modeller/covered_by/
#      gap dispositions for articles nothing declares.
#
# Every article lands in exactly ONE primary state — declared / cited (not
# declared) / dispositioned / unknown — and the states are asserted to sum to
# 57. An article that is dispositioned AND declared/cited is flagged as a
# conflict, never silently resolved.
#
# Prescriptive values (U-values, LPD, efficiencies) are NOT rendered from the
# codes MCP: the gems' own data JSONs are the authoritative source of every
# value the software applies, and the only 8.4-external content permitted here
# is a labelled reference link. A lint below fails the build if the text cache
# contains anything outside Section 8.4.

require 'json'
require 'date'

ROOT = File.expand_path('..', __dir__)
OUT = File.join(ROOT, 'NECB_8_4_COVERAGE.html')
CACHE = File.join(ROOT, 'data', 'necb', 'necb_8_4_articles_2025.json')
DISPOSITION = File.join(ROOT, 'scripts', 'necb_8_4_disposition.json')
REPO = 'https://github.com/NatLabRockies/openstudio-standards'
BRANCH = `git -C #{ROOT} rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
BLOB = "#{REPO}/blob/#{BRANCH.empty? ? 'develop' : BRANCH}"

SUBSECTIONS = {
  '8.4.1' => 'General',
  '8.4.2' => 'Compliance Calculations',
  '8.4.3' => 'Proposed Building',
  '8.4.4' => 'Energy Use Intensity (EUI path — new in 2025)',
  '8.4.5' => 'Reference Building (2020 numbering: 8.4.4.)',
  '8.4.6' => 'Part-Load Performance Curves'
}.freeze

STATUS_META = {
  'implemented' => ['Implemented (self-declared)', 'ok'],
  'partial' => ['Partial', 'warn'],
  'not_implemented' => ['Not implemented', 'bad'],
  'satisfied_by_clone' => ['Satisfied by clone', 'clone'],
  'host_scope' => ['Delegated', 'host']
}.freeze

DISPOSITION_META = {
  'engine' => ['EnergyPlus', 'clone'],
  'modeller' => ['Modeller / AHJ', 'host'],
  'covered_by' => ['Covered by (undeclared)', 'warn'],
  'gap' => ['GAP', 'bad']
}.freeze

# --- canonicalization (vintage-DIRECTIONAL, matching generate_necb_gem_coverage.rb)
#
# 2020's 8.4.4 (Reference Building) is 2025's 8.4.5; 2025's 8.4.4 is the NEW
# EUI subsection. Only 2020-vintage refs are translated. A blind bidirectional
# collapse previously rendered reference-building prose under the EUI heading.
def canonical(ref, vintage)
  r = ref.to_s.strip
  vintage.to_s == '2020' ? r.sub(/\A8\.4\.4\./, '8.4.5.') : r
end

# '8.4.5.5.(1)' -> ['8.4.5.5', 1]; '8.4.1.2.' -> ['8.4.1.2', nil]
def split_ref(ref)
  m = ref.to_s.match(/\A(8\.4\.\d+\.\d+)\.?\s*(?:\((\d+)\))?/)
  m ? [m[1], m[2]&.to_i] : [nil, nil]
end

def esc(text)
  text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

# ---------------------------------------------------------------- inputs

cache = JSON.parse(File.read(CACHE))
articles = cache['articles'] # {"8.4.1.1" => {...}}

# Change-7 lint: the cache may contain ONLY Section 8.4 text. Prescriptive
# values from Sections 3-7 must come from the gems' data JSONs, never be
# rendered from MCP-fetched text.
outside = articles.keys.reject { |k| k.start_with?('8.4.') }
abort("LINT: non-8.4 content in text cache: #{outside.join(', ')}") unless outside.empty?

# Manifest declarations, canonicalized. One record per (gem, vintage, entry).
declarations = Hash.new { |h, k| h[k] = [] }
Dir.glob(File.join(ROOT, 'openstudio-*/lib/**/data/necb/*_rules_*.json')).sort.each do |path|
  data = JSON.parse(File.read(path))
  entries = data.dig('article_coverage', 'articles') or next
  gem_name = path.sub("#{ROOT}/", '')[%r{\Aopenstudio-[a-z]+}]
  vintage = File.basename(path)[/(\d{4})\.json\z/, 1]
  entries.each do |e|
    next unless e['article'].to_s.start_with?('8.4')

    art, sentence = split_ref(canonical(e['article'], vintage))
    next unless art

    declarations[art] << e.merge('gem' => gem_name, 'vintage' => vintage,
                                 'sentence' => sentence, 'canonical' => canonical(e['article'], vintage))
  end
end

# Source citations, classified by the audit call they sit on. The umbrella's
# literal 8.4.4.x citations are the 2025 EUI path and stay; domain gems'
# literal 8.4.4.x are 2020 reference-building numbering and map to 8.4.5.x;
# "#{prefix}" expands per-vintage in the code and canonicalizes to 8.4.5.
def classify_call(lines, idx)
  idx.downto([idx - 6, 0].max) do |j|
    return :warn  if lines[j].match?(/(?:audit&?\.|\.)\s*warn\s*\(/)
    return :cited if lines[j].match?(/(?:audit&?\.|\.)\s*(?:decision|info)\s*\(/)
  end
  :cited
end

citations = Hash.new { |h, k| h[k] = [] }
Dir.glob(File.join(ROOT, 'openstudio-*/lib/**/*.rb')).sort.each do |path|
  gem_name = path.sub("#{ROOT}/", '')[%r{\Aopenstudio-[a-z]+}]
  rel = path.sub("#{ROOT}/", '')
  lines = File.readlines(path, encoding: 'UTF-8', invalid: :replace, undef: :replace)
  lines.each_with_index do |line, i|
    raw = line[/article:\s*["']([^"']+)["']/, 1] or next
    kind = classify_call(lines, i)
    raw.gsub('#{prefix}', 'PREFIX')
       .scan(/(?:PREFIX|8\.4)(?:\.\d+)*\.?(?:\(\d+\))?/)
       .each do |tok|
      ref = tok.sub('PREFIX', '8.4.5')
      ref = ref.sub(/\A8\.4\.4\./, '8.4.5.') unless gem_name == 'openstudio-necb'
      art, = split_ref(ref)
      next unless art

      citations[art] << { file: rel, line: i + 1, kind: kind }
    end
  end
end
citations.each_value { |v| v.uniq! { |c| [c[:file], c[:line], c[:kind]] } }

# Runtime evidence: articles observed in real runs' audit.json, vintage-aware.
runs = (ENV['NECB_AUDIT_JSONS'] || '').split(':').map(&:strip).reject(&:empty?)
executed = Hash.new { |h, k| h[k] = [] }
runs.each do |dir|
  audit_path = File.join(dir, 'audit.json')
  next unless File.exist?(audit_path)

  vintage = begin
    JSON.parse(File.read(File.join(dir, 'report.json')))['vintage'].to_s
  rescue StandardError
    ''
  end
  levels = Hash.new { |h, k| h[k] = Hash.new(0) }
  JSON.parse(File.read(audit_path)).each do |entry|
    ref = entry['article'].to_s
    next unless ref.start_with?('8.4')

    art, = split_ref(canonical(ref, vintage))
    levels[art][entry['level'].to_s] += 1 if art
  end
  levels.each { |art, counts| executed[art] << { run: File.basename(dir), vintage: vintage, levels: counts } }
end

dispositions = JSON.parse(File.read(DISPOSITION))['dispositions']

# ---------------------------------------------------------------- states

states = {}
conflicts = []
articles.each_key do |art|
  primary = if declarations.key?(art) then :declared
            elsif citations.key?(art) then :cited
            elsif dispositions.key?(art) then :dispositioned
            else :unknown
            end
  states[art] = primary
  conflicts << art if dispositions.key?(art) && primary != :dispositioned
end

counts = states.values.tally
total = counts.values.sum
abort("SELF-CHECK FAILED: states sum to #{total}, not #{articles.size}") unless total == articles.size

# ---------------------------------------------------------------- rendering

def link(cit)
  short = "#{cit[:file].split('/').last}:#{cit[:line]}"
  badge = cit[:kind] == :warn ? ' <span class="pill bad" title="this citation sits on an audit WARNING — often announcing the rule is NOT applied">warning</span>' : ''
  %(<a href="#{BLOB}/#{cit[:file]}#L#{cit[:line]}" title="#{esc(cit[:file])}:#{cit[:line]}">#{esc(short)}</a>#{badge})
end

def executed_badge(obs)
  return '' if obs.empty?

  substantive = obs.any? { |o| (o[:levels].keys - ['warning']).any? }
  label = substantive ? 'observed in run' : 'observed in run (warnings only)'
  css = substantive ? 'ok' : 'warn'
  detail = obs.map { |o| "#{o[:run]} (#{o[:vintage]}): #{o[:levels].map { |l, n| "#{n} #{l}" }.join(', ')}" }.join(' | ')
  %(<span class="pill #{css}" title="#{esc(detail)}">#{label}</span>)
end

def declaration_rows(decls, art_executed)
  grouped = decls.group_by { |d| [d['gem'], d['canonical'], d['status'], d['how'].to_s, d['gaps'].to_s] }
  grouped.map do |(gem_name, canon, status, how, gaps), group|
    label, css = STATUS_META.fetch(status, [status, 'none'])
    vintages = group.map { |g| g['vintage'] }.uniq.sort.join(', ')
    originals = group.map { |g| g['article'] }.uniq.sort.join(' / ')
    <<~ROW
      <tr>
        <td class="ref">#{esc(canon)}#{originals == canon ? '' : %(<div class="orig">declared as #{esc(originals)}</div>)}</td>
        <td>#{esc(gem_name)}<br><span class="dim">#{esc(vintages)}</span></td>
        <td><span class="pill #{css}">#{esc(label)}</span> #{art_executed}</td>
        <td class="how">#{esc(how)}#{gaps.empty? ? '' : %(<div class="gaps"><b>Gaps:</b> #{esc(gaps)}</div>)}</td>
      </tr>
    ROW
  end.join
end

def citation_cell(cits)
  return '' if cits.to_a.empty?

  links = cits.first(8).map { |c| link(c) }
  links << "<span class=\"dim\">+#{cits.size - 8} more</span>" if cits.size > 8
  <<~HTML
    <div class="citerow"><b>Cited at</b> <span class="dim">(a citation proves a log line mentions the
    article — it is not, by itself, evidence the rule is applied):</span> #{links.join(' · ')}</div>
  HTML
end

def disposition_block(art, dispo, conflict)
  label, css = DISPOSITION_META.fetch(dispo['category'], [dispo['category'], 'none'])
  target = Array(dispo['covered_by']).join(', ')
  <<~HTML
    <div class="dispo#{conflict ? ' conflict' : ''}">
      #{conflict ? '<span class="pill bad">⚑ CONFLICT</span> this article is dispositioned AND declared/cited — resolve, do not trust either alone.' : ''}
      <span class="pill #{css}">#{esc(label)}#{target.empty? ? '' : ": #{esc(target)}"}</span>
      #{dispo['draft'] ? '<span class="pill warn" title="not yet reviewed by a human">DRAFT</span>' : ''}
      <span class="how">#{esc(dispo['rationale'])}</span>
      <div class="dim">Reviewer: #{esc(dispo['reviewer'])}</div>
    </div>
  HTML
end

def clause_tree(art, record, decls)
  unless record['parse_ok']
    return <<~HTML
      <details><summary>Requirement text — <b>structure unverified</b> (#{esc(record['reason'])})</summary>
      <p class="dim">The parser could not verify this article's sentence structure, so the raw text is shown
      rather than a guessed tree (text under a wrong number is worse than no tree).</p>
      <pre>#{esc(record['raw'])}</pre></details>
    HTML
  end

  sentence_decls = decls.group_by { |d| d['sentence'] }
  depth_note = if sentence_decls.keys.compact.any?
                 'coverage below is declared per-sentence where marked'
               elsif decls.any?
                 'coverage is declared at ARTICLE level — per-sentence marks would be fabrication'
               else
                 'no coverage declared at any depth'
               end
  items = record['sentences'].map do |s|
    marks = (sentence_decls[s['num']] || []).map do |d|
      label, css = STATUS_META.fetch(d['status'], [d['status'], 'none'])
      %(<span class="pill #{css}" title="#{esc(d['gem'])}: #{esc(d['how'].to_s[0, 160])}">#{esc(d['gem'].sub('openstudio-', ''))}: #{esc(label)}</span>)
    end.join(' ')
    clauses = s['clauses'].map do |c|
      subs = c['subclauses'].map { |sc| %(<li class="sub"><span class="cid">(#{esc(sc['id'])})</span> #{esc(sc['text'])}</li>) }.join
      %(<li><span class="cid">(#{esc(c['id'])})</span> #{esc(c['text'])}#{subs.empty? ? '' : "<ul>#{subs}</ul>"}</li>)
    end.join
    %(<li><span class="cid">(#{s['num']})</span> #{esc(s['text'])} #{marks}#{clauses.empty? ? '' : "<ul>#{clauses}</ul>"}</li>)
  end.join
  eqs = Array(record['equations']).first(6)
  eq_html = eqs.empty? ? '' : %(<div class="eqs"><b>Formulas (reference rendering):</b><pre>#{esc(eqs.join("\n\n"))}</pre></div>)
  <<~HTML
    <details><summary>Requirement text (#{record['sentences'].size} sentences) — <span class="dim">#{depth_note}</span></summary>
    <ul class="clauses">#{items}</ul>#{eq_html}</details>
  HTML
end

state_meta = { declared: ['Declared', 'ok'], cited: ['Cited in code, not declared', 'warn'],
               dispositioned: ['Dispositioned', 'host'], unknown: ['Unknown', 'bad'] }

sections_html = SUBSECTIONS.map do |prefix, sub_title|
  rows = articles.keys.select { |a| a.start_with?("#{prefix}.") }
                 .sort_by { |a| a.scan(/\d+/).map(&:to_i) }.map do |art|
    record = articles[art]
    decls = declarations[art]
    state = states[art]
    label, css = state_meta[state]
    conflict = conflicts.include?(art)
    exec_badge = executed_badge(executed[art])

    body = +''
    if decls.any?
      body << %(<table class="inner"><thead><tr><th>Declared at</th><th>Gem</th><th>Status</th><th>How / gaps</th></tr></thead><tbody>)
      body << declaration_rows(decls, exec_badge)
      body << '</tbody></table>'
    elsif state == :cited
      body << %(<div class="dispo"><span class="pill warn">cited in code, not declared</span> <span class="how">No
        manifest entry exists, but source citations reference this article (see below). This is a manifest
        gap to close — it is NOT a claim of implementation.</span> #{exec_badge}</div>)
    elsif state == :unknown
      body << %(<div class="dispo"><span class="pill bad">unknown</span> <span class="how">No declaration, no
        citation, no disposition. Nothing is known about how this article is satisfied.</span></div>)
    end
    body << disposition_block(art, dispositions[art], conflict) if dispositions.key?(art)
    body << citation_cell(citations[art])
    body << clause_tree(art, record, decls)

    <<~ROW
      <tr class="article" id="a#{art.tr('.', '-')}">
        <td class="ref">#{esc(art)}.</td>
        <td><b>#{esc(record['title'].to_s.empty? ? '(untitled)' : record['title'])}</b>
            <span class="pill #{css}">#{label}</span>#{conflict ? ' <span class="pill bad">⚑</span>' : ''}
            <span class="dim">pp. #{record['pages']&.join('–')}</span></td>
      </tr>
      <tr class="nested"><td colspan="2">#{body}</td></tr>
    ROW
  end.join
  <<~SECTION
    <section><h2>#{esc(prefix)}. #{esc(sub_title)}</h2>
    <table class="outer"><tbody>#{rows}</tbody></table></section>
  SECTION
end.join

cards = state_meta.map do |state, (label, css)|
  %(<div class="card #{css}"><b>#{counts[state] || 0}</b><span>#{label}</span></div>)
end.join + %(<div class="card bad"><b>#{conflicts.size}</b><span>⚑ Conflicts</span></div>)

run_note = if runs.empty?
             'No run evidence supplied (set NECB_AUDIT_JSONS to one or more run directories containing audit.json + report.json) — the "observed in run" tier is absent from this build.'
           else
             "Run evidence: #{runs.map { |r| File.basename(r) }.join(', ')} — articles cited at runtime in those runs carry an \"observed in run\" badge (the strongest evidence tier here: it proves the citing code executed in at least one real scenario)."
           end

html = <<~HTML
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>NECB Section 8.4 — Performance Path coverage</title>
  <style>
    :root { color-scheme: light dark;
      --bg:#fff; --fg:#1a1a1a; --dim:#666; --line:#e3e3e3; --panel:#fafafa;
      --ok:#1a7f37; --warn:#9a6700; --bad:#b32424; --clone:#0969da; --host:#6639ba; --none:#767676; }
    @media (prefers-color-scheme: dark) { :root {
      --bg:#0d1117; --fg:#e6edf3; --dim:#9198a1; --line:#30363d; --panel:#161b22;
      --ok:#3fb950; --warn:#d29922; --bad:#f85149; --clone:#58a6ff; --host:#bc8cff; --none:#8b949e; } }
    :root[data-theme="dark"] { --bg:#0d1117; --fg:#e6edf3; --dim:#9198a1; --line:#30363d; --panel:#161b22;
      --ok:#3fb950; --warn:#d29922; --bad:#f85149; --clone:#58a6ff; --host:#bc8cff; --none:#8b949e; }
    :root[data-theme="light"] { --bg:#fff; --fg:#1a1a1a; --dim:#666; --line:#e3e3e3; --panel:#fafafa;
      --ok:#1a7f37; --warn:#9a6700; --bad:#b32424; --clone:#0969da; --host:#6639ba; --none:#767676; }
    body { background:var(--bg); color:var(--fg); margin:0 auto; padding:2rem 1.25rem; max-width:76rem;
      font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; }
    h1 { font-size:1.55rem; margin:0 0 .3rem; } h2 { font-size:1.12rem; margin:2rem 0 .5rem; }
    .lede { color:var(--dim); max-width:58rem; }
    .caveat { border-left:3px solid var(--warn); background:var(--panel); padding:.8rem 1rem; margin:1.1rem 0; border-radius:0 4px 4px 0; }
    .cards { display:flex; flex-wrap:wrap; gap:.5rem; margin:1.1rem 0; }
    .card { border:1px solid var(--line); border-radius:6px; padding:.5rem .85rem; background:var(--panel); min-width:8rem; }
    .card b { display:block; font-size:1.3rem; } .card span { color:var(--dim); font-size:.78rem; }
    .card.ok b{color:var(--ok)} .card.warn b{color:var(--warn)} .card.bad b{color:var(--bad)} .card.host b{color:var(--host)}
    .scroll { overflow-x:auto; }
    table { border-collapse:collapse; width:100%; }
    tr.article > td { border-top:1px solid var(--line); padding:.55rem .5rem; background:var(--panel); vertical-align:top; }
    tr.nested > td { padding:.15rem 0 .8rem 1.4rem; border:0; }
    table.inner { font-size:.87rem; margin:.3rem 0; }
    table.inner th { text-align:left; font-weight:500; font-size:.72rem; text-transform:uppercase; color:var(--dim);
      padding:.25rem .5rem; border-bottom:1px solid var(--line); }
    table.inner td { padding:.4rem .5rem; border-bottom:1px solid var(--line); vertical-align:top; }
    .ref { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; white-space:nowrap; }
    .orig { color:var(--dim); font-size:.72rem; }
    .dim { color:var(--dim); font-size:.82em; }
    .how { max-width:44rem; display:inline; } .gaps { margin-top:.3rem; color:var(--warn); }
    .pill { display:inline-block; padding:.05rem .5rem; border-radius:10px; font-size:.74rem; white-space:nowrap; border:1px solid currentColor; }
    .pill.ok{color:var(--ok)} .pill.warn{color:var(--warn)} .pill.bad{color:var(--bad)}
    .pill.clone{color:var(--clone)} .pill.host{color:var(--host)} .pill.none{color:var(--none)}
    .citerow { font-size:.83rem; margin:.35rem 0; }
    .citerow a { color:var(--clone); text-decoration:none; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.9em; }
    .citerow a:hover { text-decoration:underline; }
    .dispo { font-size:.87rem; margin:.35rem 0; padding:.45rem .6rem; background:var(--panel); border:1px solid var(--line); border-radius:5px; }
    .dispo.conflict { border-color:var(--bad); }
    details { margin:.4rem 0; font-size:.88rem; }
    summary { cursor:pointer; color:var(--dim); }
    ul.clauses { margin:.5rem 0 .3rem; padding-left:1.2rem; list-style:none; }
    ul.clauses ul { list-style:none; padding-left:1.4rem; }
    ul.clauses li { margin:.3rem 0; }
    .cid { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; color:var(--host); }
    .eqs pre, details pre { background:var(--panel); border:1px solid var(--line); border-radius:5px;
      padding:.6rem; overflow-x:auto; font-size:.8rem; white-space:pre-wrap; }
    footer { margin-top:2.5rem; padding-top:1rem; border-top:1px solid var(--line); color:var(--dim); font-size:.82rem; }
    code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.9em; }
  </style></head><body>

  <h1>NECB Section 8.4 — Performance Path coverage</h1>
  <p class="lede">How the <code>openstudio-*</code> gem family covers Section 8.4 of the National Energy Code of
  Canada for Buildings (2025 numbering; 2020's reference-building subsection 8.4.4. is canonicalized to 8.4.5.).
  Every article in the Section renders with its full requirement text, so coverage cannot be overstated by
  omission. #{esc(run_note)}</p>

  <div class="caveat"><b>How to read the evidence — weakest to strongest.</b>
  <ul>
    <li><b>Disposition</b> — a curated claim of <i>responsibility</i> (engine / modeller / named gem / gap), not
        of correctness. Draft dispositions are unreviewed.</li>
    <li><b>"Cited at" links</b> — the article number appears on an audit log call in that source line. A citation
        proves the log line exists, <em>nothing more</em>; citations sitting on <em>warnings</em> often announce
        the rule is <em>not</em> applied and are badged accordingly. Absence of a citation is not evidence of
        non-implementation either.</li>
    <li><b>Manifest status</b> — the gem's self-declared <code>article_coverage</code>. "Implemented" here means
        the gem <i>asserts</i> it applies the rule; two real defects have been found inside articles declared
        implemented. Independent behavioural verification is <code>rake necb:verify</code>
        (see <code>docs/necb_rule_verification.md</code>).</li>
    <li><b>"Observed in run"</b> — the article was cited at runtime in a named real pipeline run: the citing code
        demonstrably executed in at least one scenario. Still not proof of correct values.</li>
  </ul>
  <b>Prescriptive values</b> (U-values, LPDs, efficiencies) are governed by each gem's own data JSON — the number
  the software actually applies and the thing to audit: <code>openstudio-envelope .../envelope_rules_*.json</code>,
  <code>openstudio-loads .../space_types_*.json</code>, <code>openstudio-shw .../shw_rules_*.json</code>,
  <code>openstudio-hvac .../efficiencies_*.json</code>. The official code wording is available through the
  building-codes MCP (<code>get_section</code>/<code>get_table</code>) as a human reference only.</div>

  <div class="cards">#{cards}</div>

  <div class="scroll">#{sections_html}</div>

  <footer>Generated by <code>scripts/generate_necb_8_4_coverage.rb</code> — do not edit by hand
  (<code>rake necb:coverage_doc</code> to regenerate).
  Requirement text: NECB 2025 Division B via the building-codes MCP, retrieved #{esc(cache.dig('provenance', 'retrieved'))}
  (Crown copyright — reproduction authorized as Government of Canada work); parse safety checks in
  <code>scripts/fetch_necb_8_4_text.rb</code>. Source links resolve against <code>#{esc(BRANCH.empty? ? 'develop' : BRANCH)}</code>.</footer>
  </body></html>
HTML

File.write(OUT, html)
puts "wrote #{OUT.sub("#{ROOT}/", '')}"
puts format('  states: %s  (sum %d/%d)  conflicts: %s',
            counts.map { |k, v| "#{k}=#{v}" }.join(' '), total, articles.size, conflicts.join(', '))
parse_fail = articles.reject { |_, r| r['parse_ok'] }.keys
puts "  clause-tree fallbacks: #{parse_fail.empty? ? 'none' : parse_fail.join(', ')}"
