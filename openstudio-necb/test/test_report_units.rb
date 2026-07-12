require_relative 'test_helper'

# SDK-free renderer units: HTML helpers, checklist derivation, charts, and the
# full-document render from CANNED report/audit data (no models, no simulation).
class TestReportUnits < Minitest::Test
  H = OpenStudioNECB::Report::H
  Checklist = OpenStudioNECB::Report::Checklist
  Charts = OpenStudioNECB::Report::Charts

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
    audit.decision(:coverage, '8.4.2.3 climatic data taken from model inputs', article: '8.4.2.3.')
    audit.warn(:efficiency, 'unsized DX coil skipped by capacity-binned lookup',
               target: 'Coil 1', article: 'Table 5.2.12.1.')
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
    assert_equal :info, by_article['8.4.2.3.'].glyph, 'coverage entries are scope notes'
    assert_equal :warning, by_article['Table 5.2.12.1.'].glyph, 'warnings elevate'
    assert_equal rows.sort_by { |r| Checklist.article_sort_key(r.article) }.map(&:article), rows.map(&:article),
                 'rows are article-sorted'
    assert rows.all? { |r| r.audit_index.is_a?(Integer) }, 'every row anchors an audit entry'
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
    # single-file guarantee: no external fetches of any kind
    refute_match(%r{(src|href)\s*=\s*"https?://}, html)
    refute_match(/<link|<script|@import|url\(/, html)
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
