require_relative 'test_helper'

# SDK-free renderer units: HTML helpers, checklist derivation, charts, and the
# full-document render from CANNED report/audit data (no models, no simulation).
class TestReportUnits < Minitest::Test
  H = OpenStudioNECB::Report::H
  Checklist = OpenStudioNECB::Report::Checklist
  Charts = OpenStudioNECB::Report::Charts
  Sections = OpenStudioNECB::Report::Sections

  GOLDEN_DIR = File.expand_path('goldens', __dir__)

  def golden(name, actual)
    path = File.join(GOLDEN_DIR, name)
    normalized = actual.gsub(/\s+/, ' ').strip
    if ENV['UPDATE_GOLDEN']
      FileUtils.mkdir_p(GOLDEN_DIR)
      File.write(path, normalized)
      skip "golden #{name} regenerated"
    end
    assert File.exist?(path), "golden #{name} missing — run with UPDATE_GOLDEN=1 to create"
    assert_equal File.read(path), normalized, "golden #{name} drifted (UPDATE_GOLDEN=1 to accept)"
  end

  def canned_audit
    audit = OpenStudioNECB::AuditLog.new
    audit.decision(:compliance, 'proposed does not exceed the building energy target',
                   inputs: { proposed_kwh: 90_000.0, reference_building_energy_target_kwh: 100_000.0 },
                   value: 'margin 10000.0 kWh (10.0%)', article: '8.4.1.2.(2)')
    audit.decision(:compliance, 'unmet heating hours EXCEED 100 h',
                   inputs: { proposed_h: 140.0, reference_h: 20.0, limit_h: 100 }, article: '8.4.1.2.(3)')
    audit.decision(:compliance, 'proposed ALSO meets the archetype-EUI building energy target (8.4.4 path)',
                   inputs: { proposed_kwh: 90_000.0, bet_kwh: 120_000.0 }, article: '8.4.4.1.(2)')
    # implemented — no checklist row (appendix-only)
    audit.info(:coverage, 'climatic data taken from model inputs',
               inputs: { status: 'implemented', decisions_citing: 3 }, article: '8.4.2.3.')
    # implementing entry that covers the host_scope delegation below
    audit.info(:coverage, 'reference lighting applied (Part 4 allowance LPDs)',
               inputs: { status: 'implemented', decisions_citing: 2 }, article: '8.4.4.5.')
    # host_scope COVERED by 8.4.4.5. above (prefix match) — no checklist row
    audit.info(:coverage, 'delegated to openstudio-lighting',
               inputs: { status: 'host_scope', decisions_citing: 0 }, article: '8.4.4.5.(1)')
    # host_scope ORPHAN — nothing implements 8.4.4.20. → warning checklist row
    audit.info(:coverage, 'delegated to openstudio-shw',
               inputs: { status: 'host_scope', decisions_citing: 0 }, article: '8.4.4.20.')
    audit.with_building('reference building') do
      audit.warn(:efficiency, 'unsized DX coil skipped by capacity-binned lookup',
                 target: 'Coil 1', article: 'Table 5.2.12.1.')
    end
    audit.with_building('input model') do
      audit.warn(:loads, 'space with no space type assigned', target: 'Space 9')
    end
    audit
  end

  def canned_report
    {
      'vintage' => '2025', 'hdd' => 3890, 'simulate' => 'annual', 'annual' => true,
      'compliant' => true, 'percent_of_target' => 90.0, 'tier' => 1,
      'ghg' => { 'percent_of_ghg_target' => 24.0, 'level' => 'B' },
      'eui_path' => { 'bet_kwh' => 120_000.0, 'compliant' => true, 'percent_of_target' => 75.0, 'tier' => 2,
                      'lines' => [{ 'archetype' => 'Office', 'area_m2' => 600.0,
                                    'eui_kwh_per_m2' => 175, 'kwh' => 105_000.0 }] },
      'proposed' => { 'total_site_kwh' => 90_000.0, 'electricity_kwh' => 40_000.0, 'natural_gas_kwh' => 50_000.0,
                      'eui_kwh_per_m2' => 150.0, 'floor_area_m2' => 600.0, 'ghg_kg_co2e' => 11_566.0,
                      'end_uses_kwh' => { 'heating' => 50_000.0, 'cooling' => 5_000.0, 'fans' => 8_000.0,
                                          'pumps' => 2_000.0, 'interior_lighting' => 15_000.0,
                                          'interior_equipment' => 10_000.0, 'water_systems' => 0.0 },
                      'unmet_occupied_hours' => { 'heating' => 12.0, 'cooling' => 40.0 },
                      'cost' => { 'hvac' => 100_000.0, 'envelope' => 250_000.0, 'total' => 350_000.0 } },
      'reference' => { 'total_site_kwh' => 100_000.0, 'electricity_kwh' => 45_000.0, 'natural_gas_kwh' => 55_000.0,
                       'eui_kwh_per_m2' => 166.7, 'ghg_kg_co2e' => 48_190.0,
                       'end_uses_kwh' => { 'heating' => 55_000.0, 'cooling' => 6_000.0, 'fans' => 9_000.0,
                                           'pumps' => 2_500.0, 'interior_lighting' => 16_000.0,
                                           'interior_equipment' => 10_000.0, 'water_systems' => 0.0 },
                       'unmet_occupied_hours' => { 'heating' => 20.0, 'cooling' => 35.0 },
                       'cost' => { 'hvac' => 90_000.0, 'envelope' => 240_000.0, 'total' => 330_000.0 } },
      'incremental_cost_proposed_vs_reference' => 20_000.0,
      'warnings' => ['unsized DX coil skipped by capacity-binned lookup']
    }
  end

  def canned_result
    OpenStudioNECB::Compliance::ComplianceResult.new(
      proposed_model: nil, reference_model: nil, report: canned_report,
      audit: canned_audit, compliant: true, run_dir: nil)
  end

  def test_escaping
    assert_equal '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;', H.esc('<a href="x">&</a>')
    html = H.table(['A'], [['<script>alert(1)</script>']])
    refute_includes html, '<script>'
  end

  def test_fmt
    assert_equal '12,345 kWh', H.fmt(12_345.2, unit: 'kWh', prec: 0)
    assert_equal '—', H.fmt(nil)
    assert_equal '0.347', H.fmt(0.3468, prec: 3)
  end

  def test_checklist_verdicts_respect_shouting_convention
    rows = Checklist.rows(canned_audit.entries)
    by_article = rows.to_h { |r| [r.article, r] }
    assert_equal :pass, by_article['8.4.1.2.(2)'].glyph, 'lowercase "does not exceed" is a PASS'
    assert_equal :fail, by_article['8.4.1.2.(3)'].glyph, 'uppercase EXCEED is a FAIL'
    assert_equal :pass, by_article['8.4.4.1.(2)'].glyph
    assert_equal :warning, by_article['Table 5.2.12.1.'].glyph, 'warnings elevate'
    assert_equal rows.sort_by { |r| Checklist.article_sort_key(r.article) }.map(&:article), rows.map(&:article),
                 'rows are article-sorted'
    assert rows.all? { |r| r.audit_index.is_a?(Integer) }, 'every row anchors an audit entry'
  end

  def test_coverage_reconciliation
    rows = Checklist.rows(canned_audit.entries)
    orphan = rows.find { |r| r.article == '8.4.4.20.' }
    refute_nil orphan, 'orphan host_scope delegation surfaces on the checklist'
    assert_equal :warning, orphan.glyph
    assert_includes orphan.statement, 'NOT covered'
    assert_nil rows.find { |r| r.article == '8.4.4.5.(1)' }, 'covered host_scope stays off the checklist'
    assert_nil rows.find { |r| r.article == '8.4.2.3.' }, 'implemented coverage emits no checklist row'
    assert_nil rows.find { |r| r.article == '8.4.4.5.' }, 'implemented coverage emits no checklist row'

    html = OpenStudioNECB::Report.render(canned_result)
    assert_includes html, 'delegated — covered by another gem'
    assert_includes html, 'NOT covered in this run'
  end

  # D-09: a partial/not_implemented coverage entry flagged gap_owner "modeller"
  # renders as an info scope note, never a warning — and never reaches the
  # checklist. The flag must not soften anything else.
  def test_coverage_status_modeller_scope_note
    entry = { step: :coverage, level: :info, article: '8.4.2.3.',
              action: 'Climatic Data — partial, modeller scope',
              inputs: { status: 'partial', gap_owner: 'modeller', decisions_citing: 2 } }
    glyph, text = Sections.coverage_status(entry, Set.new)
    assert_equal :info, glyph
    assert_equal 'modeller scope', text
    assert_empty Checklist.rows([entry]), 'scope note stays off the checklist'

    glyph, = Sections.coverage_status({ inputs: { status: 'partial' } }, Set.new)
    assert_equal :warning, glyph, 'unflagged partial still warns'
    glyph, = Sections.coverage_status({ inputs: { status: 'not_implemented', gap_owner: 'engine' } }, Set.new)
    assert_equal :fail, glyph, 'only gap_owner "modeller" softens'
    glyph, = Sections.coverage_status({ inputs: { status: 'implemented', gap_owner: 'modeller' } }, Set.new)
    assert_equal :pass, glyph, 'flag is inert on implemented statuses'
  end

  def test_building_stamp_traces_issues_to_their_model
    audit = canned_audit
    ref_warn = audit.entries.find { |e| e[:step] == :efficiency }
    input_warn = audit.entries.find { |e| e[:step] == :loads }
    verdict = audit.entries.find { |e| e[:article] == '8.4.1.2.(2)' }
    assert_equal 'reference building', ref_warn[:building], 'warning stamped with its model'
    assert_equal 'input model', input_warn[:building]
    assert_nil verdict[:building], 'cross-building verdicts carry no stamp'
    assert_nil audit.building, 'with_building restores the outer context'

    rows = Checklist.rows(audit.entries)
    assert_equal 'reference building', rows.find { |r| r.article == 'Table 5.2.12.1.' }.building

    html = OpenStudioNECB::Report.render(canned_result)
    assert_includes html, 'bldg-reference', 'reference chip rendered'
    assert_includes html, 'bldg-input', 'input-model chip rendered'
    assert_includes html, '>Applies to<', 'checklist/audit tables carry the Applies-to column'
    assert_includes audit.to_s, 'building: reference building', 'audit.txt narrative carries the stamp'
  end

  def test_checklist_measured_values
    row = Checklist.rows(canned_audit.entries).find { |r| r.article == '8.4.1.2.(2)' }
    assert_includes row.measured, 'proposed_kwh: 90000.0'
  end

  def test_paired_bars_golden
    svg = Charts.paired_bars([['Heating', 50_000.0, 55_000.0], ['Cooling', 5_000.0, 6_000.0]],
                             unit: 'kWh', label: 'test chart')
    assert_includes svg, OpenStudioNECB::Report::H::PROPOSED_COLOR
    assert_includes svg, OpenStudioNECB::Report::H::REFERENCE_COLOR
    golden('paired_bars.svg', svg)
  end

  def test_paired_bars_edge_cases
    assert_equal '', Charts.paired_bars([], unit: 'kWh', label: 'x')
    assert_equal '', Charts.paired_bars([['a', 0, 0]], unit: 'kWh', label: 'x')
    solo = Charts.paired_bars([['a', 10.0, nil]], unit: 'kWh', label: 'x')
    refute_includes solo, OpenStudioNECB::Report::H::REFERENCE_COLOR, 'nil reference renders proposed-only'
  end

  def test_total_bars_target_line
    svg = Charts.total_bars([['Proposed', 90_000.0], ['Reference', 100_000.0]],
                            targets: [['BET (8.4.4)', 120_000.0]])
    assert_includes svg, 'stroke-dasharray'
    assert_includes svg, 'BET (8.4.4)'
  end

  def test_full_render_from_canned_data
    html = OpenStudioNECB::Report.render(canned_result, project_name: 'Unit Test Tower',
                                                        prepared_by: 'A. Modeller')
    assert_includes html, 'PERFORMANCE PATH: PASS'
    assert_includes html, 'EUI PATH (8.4.4): PASS'
    assert_includes html, 'TIER 1'
    assert_includes html, 'GHG LEVEL B'
    assert_includes html, 'Operational GHG emissions (NECB 2025 Part 11)'
    assert_includes html, 'LEVEL B'
    assert_includes html, 'Table 8.4.4.1'
    assert_includes html, 'Incremental cost'
    assert_includes html, 'Unit Test Tower'
    # every internal link resolves
    hrefs = html.scan(/href="#([^"]+)"/).flatten.uniq
    ids = html.scan(/id="([^"]+)"/).flatten
    missing = hrefs - ids
    assert_empty missing, "dangling anchors: #{missing.inspect}"
    # single-file guarantee: no external fetches of any kind. The loop chooser
    # adds ONE inline <script>, so allow an inline script but forbid an external
    # one (src=), and keep external stylesheets / @import / url() forbidden.
    refute_match(%r{(src|href)\s*=\s*"https?://}, html)
    refute_match(/<link\b/i, html)
    refute_match(/<script[^>]*\bsrc=/i, html)
    refute_match(/@import|url\(/, html)
  end

  # The HVAC section consumes the openstudio-hvac diagram bundles (plain hashes)
  # that report.rb computes off the SDK models. With nil/absent models it must
  # render explanatory notes, never crash.
  def test_hvac_section_handles_nil_and_stub_bundles
    stub = { loops: [{ kind: :hot_water, label: 'Hot water loop',
                       svg: '<svg width="10" height="10"><title>stub loop</title></svg>' }],
             zone_equipment_svg: '<svg width="10" height="10"><title>stub zeq</title></svg>', empty: false }
    # proposed present (stub), reference nil (e.g. EUI path with no reference building)
    html = Sections.hvac(proposed_hvac: stub, reference_hvac: nil, audit_entries: [])
    assert_includes html, 'Proposed building systems'
    assert_includes html, 'Hot water loop'
    assert_includes html, 'stub loop'
    assert_includes html, 'Zone equipment'
    assert_includes html, 'Reference building systems'
    assert_includes html, 'No reference building on this path'

    # empty proposed bundle (no loops, no zone equipment) states so
    empty_html = Sections.hvac(proposed_hvac: { loops: [], zone_equipment_svg: nil, empty: true },
                               reference_hvac: nil, audit_entries: [])
    assert_includes empty_html, 'No central HVAC loops'

    # keys entirely absent (report-only render) → notes, no crash
    absent_html = Sections.hvac(audit_entries: [])
    assert_includes absent_html, 'HVAC systems'
    assert_includes absent_html, 'report-only mode'
  end

  # The canned full render carries the reused diagram plumbing: the icon <defs>
  # are embedded once, DIAGRAM_CSS is in the stylesheet, and it stays
  # self-contained (icons are data-URIs, not url()/remote refs).
  def test_full_render_embeds_hvac_icon_defs_and_diagram_css
    html = OpenStudioNECB::Report.render(canned_result)
    assert_includes html, '<symbol id="icon-', 'HVAC icon defs embedded once'
    assert_includes html, 'data:image/png;base64,', 'icons are self-contained data-URIs'
    assert_match(/\.diagram\s*\{[^}]*overflow-x:\s*auto/, html, 'diagram scroll CSS present')
    assert_match(/\.diagram\s+svg\s*\{[^}]*width:\s*auto/, html, 'intrinsic-size svg override present')
    # still self-contained: allow the one inline chooser <script>, forbid external
    refute_match(/<link\b/i, html, 'no external stylesheet')
    refute_match(/<script[^>]*\bsrc=/i, html, 'no external script')
    refute_match(/@import|url\(/, html, 'no @import/url() references')
    refute_match(%r{(src|href)\s*=\s*"https?://}, html, 'no remote src/href')
  end

  def test_shortened_run_warns_loudly
    report = canned_report.merge('annual' => false)
    result = OpenStudioNECB::Compliance::ComplianceResult.new(
      proposed_model: nil, reference_model: nil, report: report,
      audit: canned_audit, compliant: true, run_dir: nil)
    html = OpenStudioNECB::Report.render(result)
    assert_includes html, 'SHORTENED RUN PERIOD'
  end

  def test_undetermined_run
    report = canned_report.merge('compliant' => nil, 'annual' => nil)
    report.delete('tier')
    result = OpenStudioNECB::Compliance::ComplianceResult.new(
      proposed_model: nil, reference_model: nil, report: report,
      audit: OpenStudioNECB::AuditLog.new, compliant: nil, run_dir: nil)
    html = OpenStudioNECB::Report.render(result)
    assert_includes html, 'UNDETERMINED'
    refute_includes html, 'PERFORMANCE PATH: PASS'
  end
end
