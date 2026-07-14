require_relative 'test_helper'

# The REUSABLE diagram API consumed by host reports (e.g. openstudio-necb's AHJ
# compliance report): OpenStudioHVAC.model_hvac_diagrams(model) draws the same
# OpenStudio-App-style loop diagrams the catalog draws, for ANY model — plus the
# self-contained icon defs + CSS a host document needs. SDK-only (no CLI).
class TestModelDiagrams < Minitest::Test
  include FixtureHelper

  # Build a hydronic boiler system on the fixture so there is a real hot-water
  # loop (pump -> boiler supply, baseboard demand) to diagram.
  def built_model
    model = load_fixture
    model.getThermalZones.each do |z|
      next if z.thermostatSetpointDualSetpoint.is_initialized

      z.setThermostatSetpointDualSetpoint(OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model))
    end
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    model
  end

  def test_model_hvac_diagrams_returns_loops_with_svg
    bundle = OpenStudioHVAC.model_hvac_diagrams(built_model)
    refute bundle[:empty], 'a boiler system has central loops'
    assert_operator bundle[:loops].size, :>=, 1, 'at least one loop diagrammed'
    loop = bundle[:loops].first
    assert loop[:kind], 'loop carries its kind'
    assert_kind_of String, loop[:label]
    assert_includes loop[:svg], '<svg', 'loop diagram is inline SVG'
    # the hot-water loop demand surfaces the served hydronic baseboards
    all_svg = bundle[:loops].map { |l| l[:svg] }.join
    assert_includes all_svg, 'Baseboard (hydronic)', 'demand branch lists served baseboards'
    # a boiler cell references the embedded boiler icon (resolves against icon_defs)
    assert_includes all_svg, '<use href="#icon-', 'cells reference embedded OS App icons'
  end

  # A single-zone (PSZ) air handler's loop label names the zone it serves, so a
  # host dropdown chooser can tell packaged single-zone units apart instead of
  # listing several ambiguous "Air loop" entries.
  def test_air_loop_label_names_its_served_zone
    model = load_fixture
    model.getThermalZones.each do |z|
      next if z.thermostatSetpointDualSetpoint.is_initialized

      z.setThermostatSetpointDualSetpoint(OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model))
    end
    zone = model.getThermalZones.sort_by(&:nameString).first
    OpenStudioHVAC.build_system(model, 'PSZ RTU Gas and DX Coils and Hot Water Baseboard', [zone])
    bundle = OpenStudioHVAC.model_hvac_diagrams(model)
    air = bundle[:loops].find { |l| l[:kind] == :air }
    refute_nil air, 'a PSZ builds an air loop'
    assert_match(/\AAir loop — /, air[:label],
                 "single-zone air loop is labelled with its served zone, got #{air[:label].inspect}")
    assert_includes air[:label], zone.nameString, 'the label carries the served zone name'
  end

  def test_model_hvac_diagrams_never_raises_on_empty_model
    bundle = OpenStudioHVAC.model_hvac_diagrams(OpenStudio::Model::Model.new)
    assert bundle[:empty], 'a bare model has no HVAC'
    assert_empty bundle[:loops]
    assert_nil bundle[:zone_equipment_svg]
  end

  def test_icon_defs_are_embedded_once_and_self_contained
    defs = OpenStudioHVAC.hvac_icon_defs
    assert_includes defs, '<symbol id="icon-', 'icon symbols defined'
    assert_includes defs, 'data:image/png;base64,', 'icons embedded as data-URIs'
    # self-contained: no url(), no <link>/@import, no remote src/href
    refute_match(/@import|<link/, defs)
    refute_match(/url\(/, defs)
    refute_match(%r{(src|href)\s*=\s*"https?://}, defs)
  end

  def test_diagram_css_is_self_contained_and_sizes_svgs
    css = OpenStudioHVAC::CatalogReport::DIAGRAM_CSS
    assert_match(/\.diagram\s*\{[^}]*overflow-x:\s*auto/, css, 'scroll container')
    assert_match(/\.diagram\s+svg\s*\{[^}]*width:\s*auto/, css, 'intrinsic-size override')
    assert_match(/break-inside:\s*avoid/, css, 'print-friendly')
    refute_match(/url\(|@import/, css, 'no external references')
  end
end
