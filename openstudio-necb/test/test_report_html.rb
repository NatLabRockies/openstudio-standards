require_relative 'test_helper'
require 'tmpdir'

# Whole-document render from a REAL pipeline result (sizing mode — fast), plus
# the report_html: hook. The canned-data render lives in test_report_units.rb.
class TestReportHTML < Minitest::Test
  include FixtureHelper

  def weather
    { epw: EPW, ddy: DDY, stat: STAT }
  end

  def building_for(model)
    { storeys: 1, zone_types: zone_types_for(model), winter_design_temp_c: -20 }
  end

  def test_sizing_mode_render_with_real_models
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-rpt-')
    proposed = proposed_with_hvac
    result = OpenStudioNECB.performance_compliance(
      proposed, vintage: '2020', simulate: :sizing, weather: weather,
      building: building_for(proposed), run_dir: dir)

    html = OpenStudioNECB::Report.render(result, project_name: 'Sizing Fixture',
                                                 address: '123 Test St, Toronto ON')
    assert_includes html, 'UNDETERMINED', 'sizing mode makes no compliance determination'
    assert_includes html, 'NECB 2020 Energy Code Compliance Report'
    assert_includes html, 'Sizing Fixture'
    # real models flow through ModelQuery: envelope + system schematics render
    assert_includes html, 'Area-weighted average U-value', 'envelope chart from the real model'
    assert_includes html, 'System layout', 'loop schematics from the real model'
    assert_operator html.scan('<svg').size, :>=, 3, 'charts + proposed/reference schematics'
    assert_includes html, 'Full audit trail'
    # anchors resolve; no external references
    hrefs = html.scan(/href="#([^"]+)"/).flatten.uniq
    ids = html.scan(/id="([^"]+)"/).flatten
    assert_empty hrefs - ids, 'every checklist/audit anchor resolves'
    refute_match(%r{(src|href)\s*=\s*"https?://}, html)
    refute_match(/<script|<link/, html)
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  # The full AHJ document: 2025 week run, BOTH compliance paths (8.4.1.2
  # performance + 8.4.4 archetype-EUI supplement), Part 11 GHG, tiers.
  def test_annual_2025_both_paths_report
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-rpt2025-')
    proposed = proposed_with_hvac
    result = OpenStudioNECB.performance_compliance(
      proposed, vintage: '2025', simulate: :annual, weather: weather,
      building: building_for(proposed), run_dir: dir,
      run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 },
      province_state: 'ONTARIO',
      eui_supplement: { archetype_areas: { 'Office' => nil } },
      report_html: true,
      report_options: { project_name: 'E2E Fixture Building', address: 'Toronto, ON',
                        prepared_by: 'openstudio-necb test suite' })

    path = File.join(dir, 'compliance_report.html')
    assert File.exist?(path)
    html = File.read(path)
    assert_match(/PERFORMANCE PATH: (PASS|FAIL)/, html, '8.4.1.2 verdict rendered')
    assert_match(/EUI PATH \(8\.4\.4\): (PASS|FAIL)/, html, '8.4.4 supplement verdict rendered')
    assert_includes html, 'Operational GHG emissions (NECB 2025 Part 11)'
    assert_includes html, 'Table 8.4.4.1', 'BET line table present'
    assert_includes html, 'SHORTENED RUN PERIOD', 'week run flagged loudly'
    assert result.report.key?('eui_path'), 'supplement stored in the report hash'
    hrefs = html.scan(/href="#([^"]+)"/).flatten.uniq
    ids = html.scan(/id="([^"]+)"/).flatten
    assert_empty hrefs - ids
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_report_html_hook_writes_file
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osnecb-rpthook-')
    proposed = proposed_with_hvac
    result = OpenStudioNECB.performance_compliance(
      proposed, vintage: '2020', simulate: :sizing, weather: weather,
      building: building_for(proposed), run_dir: dir,
      report_html: true, report_options: { project_name: 'Hook Test' })

    path = File.join(result.run_dir, 'compliance_report.html')
    assert File.exist?(path), 'report_html: true writes compliance_report.html into run_dir'
    assert_includes File.read(path), 'Hook Test'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end
end
