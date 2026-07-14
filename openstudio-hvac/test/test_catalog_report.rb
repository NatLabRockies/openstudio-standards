require_relative 'test_helper'

# Full-coverage render: builds all 97 catalog systems on the fixture, extracts
# their real topology, and asserts the self-contained HTML catalog contains every
# system, draws most of them, and makes NO external requests. Building 97 models
# takes ~30-60s (no CLI needed — topology builds are SDK-only). The whole suite
# renders ONCE (memoized, written to a temp path so the write path is exercised too).
class TestCatalogReport < Minitest::Test
  include FixtureHelper

  OUT_PATH = File.join(Dir.tmpdir, "catalog_report_#{Process.pid}.html")

  # Single render for the whole suite: also exercises the write-to-path branch.
  def self.html
    @html ||= OpenStudioHVAC.catalog_html(OUT_PATH)
  end

  Minitest.after_run { File.delete(OUT_PATH) if File.exist?(OUT_PATH) }

  def html
    self.class.html
  end

  def rows
    OpenStudioHVAC::Catalog.rows
  end

  def esc(str)
    OpenStudioHVAC::CatalogReport.esc(str)
  end

  def test_returns_a_string
    assert_kind_of String, html
    assert_match(/<html/i, html)
    assert_match(%r{</html>}i, html)
  end

  def test_contains_every_argument_name
    missing = rows.map { |r| r['name'] }.reject { |name| html.include?(esc(name)) }
    assert_empty missing, "argument names missing from catalog HTML: #{missing.inspect}"
  end

  def test_contains_every_canonical_name
    missing = rows.map { |r| OpenStudioHVAC::Canonical.name(r) }.reject { |name| html.include?(esc(name)) }
    assert_empty missing, "canonical names missing from catalog HTML: #{missing.inspect}"
  end

  def test_draws_most_systems
    svg_count = html.scan('<svg').size
    assert_operator svg_count, :>=, 60, "expected >= 60 inline <svg blocks, got #{svg_count}"
  end

  def test_loops_render_at_fixed_natural_size
    # Every loop <svg> now carries explicit width/height attributes equal to its
    # viewBox so it renders 1:1 (consistent box size across systems, no zoom).
    svg_with_width = html.scan(/<svg[^>]*\bwidth="/).size
    assert_operator svg_with_width, :>=, 60,
                    "expected most <svg> blocks to carry a width attribute, got #{svg_with_width}"
    # Wide loops scroll in their container instead of shrinking to fit...
    assert_match(/\.diagram\s*\{[^}]*overflow-x:\s*auto/, html, 'diagram container scrolls horizontally')
    # ...and the svg rule must NOT stretch the diagram to full container width.
    refute_match(/svg\s*\{[^}]*width:\s*100%/, html, 'svg must not be stretched to 100% width')
  end

  def test_family_groups_start_collapsed
    # Each family group is a collapsible toggle and starts COLLAPSED on load.
    collapsed = html.scan('class="nav-family collapsed"').size
    titles = html.scan('class="nav-family-title"').size
    assert_operator collapsed, :>=, 11, "family groups should render collapsed on load, got #{collapsed}"
    assert_equal titles, collapsed, 'every family group carries the collapsed class on load'
    assert_match(/class="nav-family-title"/, html, 'family header is a clickable toggle')
  end

  def test_no_external_references
    refute_match(/src\s*=\s*["']https?:/i, html, 'no remote src')
    refute_match(/<link\b/i, html, 'no <link> (external stylesheet/asset)')
    refute_match(/@import/i, html, 'no CSS @import')
    refute_match(/url\(/i, html, 'no CSS url() references')
    refute_match(%r{https?://(?!www\.w3\.org)}i, html,
                 'no external URLs except the SVG xmlns namespace')
  end

  def test_embedded_os_app_icons
    # The real OpenStudio Application component icons are embedded as base64
    # PNG data-URIs — ONCE each, in the hidden master <defs> — and referenced by
    # component cells via <use>. Each data-URI must appear exactly once (embed
    # once, reference many), so the count of data-URIs equals the count of
    # <symbol>/<image> definitions and is far below the number of <use> refs.
    data_uris = html.scan('data:image/png;base64,').size
    assert_operator data_uris, :>=, 20,
                    "expected >= 20 embedded PNG icons, got #{data_uris}"
    symbols = html.scan(/<symbol id="icon-/).size
    images = html.scan('<image ').size
    assert_equal data_uris, symbols, 'each icon data-URI is defined once as a <symbol>'
    assert_equal data_uris, images, 'each icon data-URI is embedded once in an <image>'

    # ...and the icons are actually USED, many more times than they are embedded.
    uses = html.scan('<use ').size
    assert_operator uses, :>=, 1, 'embedded icons are referenced via <use>'
    assert_operator uses, :>, data_uris, 'icons are referenced far more often than embedded (embed once, reference many)'

    # Spot-check the mapping: a boiler cell references the boiler icon, a
    # variable-volume fan the fan_variable icon, a water-source heat pump the
    # water-to-water HP icon (NOT a pump icon), district heating its own icon.
    %w[icon-boiler icon-fan_variable icon-heatpump_watertowater_equationfit_heating
       icon-districtheating icon-chiller_air].each do |id|
      assert_includes html, %(<symbol id="#{id}"), "#{id} is embedded"
      assert_includes html, %(<use href="##{id}"), "#{id} is referenced by a cell"
    end
  end

  def test_icon_attribution_present
    # BSD-3-Clause requires attribution: a visible footer credit to the source.
    assert_match(/Component icons .* OpenStudio Application/i, html,
                 'footer credits the OpenStudio Application icons')
    assert_includes html, 'BSD-3-Clause', 'footer names the icon license'
  end

  def test_script_is_inline_only
    # Inline <script> is now required (master-detail/search/tabs are JS-driven),
    # but it must never reference an external file — no src= on any script tag.
    assert_match(/<script\b/i, html, 'inline <script> is required for the interactive UX')
    refute_match(/<script[^>]*\bsrc=/i, html, 'the script must be inline (no src= attribute)')
  end

  def test_master_detail_search_and_tabs
    # Master-detail scaffolding: the searchable left nav and the right detail pane.
    assert_match(/id="system-search"/, html, 'search input present')
    assert_match(/class="[^"]*\bsystem-detail\b/, html, 'system-detail containers present')
    assert_match(/class="[^"]*\bsidebar\b/, html, 'left sidebar present')
    assert_match(/class="[^"]*\bnav-family\b/, html, 'family-grouped nav present')

    # Per-system tab controls exist (systems with multiple loops render >1 tab).
    assert_match(/class="[^"]*\btab-bar\b/, html, 'tab bar present')
    assert_operator html.scan(/class="tab(?: active)?"/).size, :>=, 2, 'multiple tab controls present'

    # Native SVG <title> hover tooltips on components/demand boxes (many of them).
    assert_operator html.scan('<title>').size, :>=, 60, 'SVG <title> tooltips present'
  end

  def test_plant_demand_enumerates_served_loads
    # A plant loop's demand side now enumerates the served loads, INCLUDING the
    # zone-level hydronic equipment. A hot-water system that feeds baseboards
    # (e.g. 'Baseboard gas boiler', or any '... Hot Water Baseboard' system) must
    # surface a "Baseboard (hydronic)" demand branch in its loop diagram.
    assert_includes html, 'Baseboard (hydronic)',
                    'hot-water loop demand lists served hydronic baseboards'
    # Four-pipe fan-coil systems surface their zone-level fan-coil coils, and
    # air-handler water coils still surface as heating/cooling coils.
    assert_includes html, 'Fan-coil coil', 'plant demand lists zone-level fan-coil coils'
  end

  def test_condenser_loop_demand_shows_served_chillers
    # A water-cooled chiller's condenser IS the load its condenser-water loop
    # serves. That loop's demand must surface the chillers it cools, labelled by
    # compressor type + "(condenser)", instead of collapsing to "No loads".
    assert_includes html, 'Rotary-screw chiller (condenser)',
                    'condenser loop demand surfaces the rotary-screw chillers it cools'
    assert_match(/chiller \(condenser\)/, html,
                 'a chiller-condenser demand label is present')
    # No plant loop that genuinely has demand equipment should render "No loads".
    # (The chiller condensers were the equipment previously being dropped.)
    refute_match(/Rotary-screw chiller \(condenser\)[\s\S]{0,400}No loads/, html,
                 'the condenser loop no longer shows "No loads"')
  end

  def test_plant_demand_coils_labelled_with_their_zone
    # Zone-served plant coils are drawn as their OWN demand branch labelled with
    # the zone (not collapsed into one "×2" group), so the diagram shows WHERE
    # each coil is — consistent with the per-zone air-loop demand.
    assert_includes html, 'Fan-coil coil — Thermal Zone 1',
                    'hot/chilled water loop demand shows a zone-labelled fan-coil coil'
    assert_includes html, 'Fan-coil coil — Thermal Zone 2',
                    'the second served zone is its own demand branch'
  end

  def test_air_loop_demand_shows_zone_level_components
    # The air-loop demand is drawn as one branch PER served zone; each zone cell
    # is headed by the served zone's name and shows its air terminal (its own
    # upstream cell) plus its zone-level HVAC equipment.
    assert_includes html, 'Zone:', 'air-loop demand draws a per-zone cell headed by the zone name'
    assert_match(/terminal|Diffuser/i, html,
                 'the demand branch shows the served zone air terminal')
    # Zone-level equipment (baseboards on a PSZ) appears inside the zone cell.
    assert_match(/baseboard/i, html, 'zone cell shows zone-level equipment')
  end

  def test_supply_components_carry_specific_type_labels
    # Every supply cell reflects the component's SPECIFIC type, never the coarse
    # kind — so equipment sharing a kind is told apart and nothing is merged.

    # hs09 (ASHP + backup): the DX heat-pump heating coil and the electric backup
    # coil are DISTINCT series cells, not one merged "heating coil ×2".
    assert_includes html, 'DX heating coil', 'DX heat-pump heating coil labelled specifically'
    assert_includes html, 'Electric heating coil', 'electric backup coil labelled specifically'
    assert_includes html, 'DX cooling coil', 'DX cooling coil labelled specifically'

    # Fans carry their control type (constant- vs variable-volume matters).
    assert_includes html, 'Constant-volume fan', 'constant-volume fan labelled specifically'
    assert_includes html, 'Variable-volume fan', 'variable-volume fan labelled specifically'

    # Pumps carry their control type.
    assert_includes html, 'Variable-speed pump', 'variable-speed pump labelled specifically'
  end

  def test_water_source_heat_pump_not_mislabeled_pump
    # A plant water-source heat pump must classify as a heat pump, NEVER be
    # swallowed by the pump regex. Its cell reads "Heat pump (heating)".
    assert_includes html, 'Heat pump (heating)',
                    'plant water-source heat pump surfaces as a heat pump, not a pump'
  end

  def test_district_energy_surfaces_on_condenser_loop
    # District heating/cooling on a plant supply must appear, not vanish.
    assert_includes html, 'District heating', 'district heating source surfaces'
    assert_includes html, 'District cooling', 'district cooling source surfaces'
  end

  def test_chiller_variants_distinguished_by_compressor_type
    # The fan-coil / VAV systems differ ONLY by chiller compressor type, so the
    # chiller cells must be labelled by that type parsed from the object name.
    assert_includes html, 'Centrifugal chiller', 'centrifugal chiller labelled by compressor type'
    assert_includes html, 'Scroll chiller', 'scroll chiller labelled by compressor type'
  end

  def test_parallel_boilers_render_as_two_cells
    # Two boilers are genuine parallel equipment: they render as two distinct
    # cells (Primary + Secondary), never a collapsed "Boiler ×2".
    assert_includes html, 'Primary boiler', 'lead boiler is its own cell'
    assert_includes html, 'Secondary boiler', 'lag boiler is its own cell'
    refute_match(/Boiler\s*×2/, html, 'boilers are not collapsed into a counted cell')
  end

  def test_cascade_has_center_band_labels
    # The vertical cascade mirrors the OpenStudio App's GridItem.cpp layout: a
    # center connector band between the supply row and the demand block carries
    # the "Supply Equipment" and "Demand Equipment" labels.
    assert_includes html, 'Supply Equipment', 'center band carries the Supply Equipment label'
    assert_includes html, 'Demand Equipment', 'center band carries the Demand Equipment label'
  end

  def test_demand_splitter_mixer_and_stacked_branches
    # The demand block is a splitter -> parallel branches (stacked vertically) ->
    # mixer, matching the OS App. The splitter/mixer nodes and each stacked branch
    # carry a marker class so the structure is assertable without pixel coords.
    assert_match(/class="demand-splitter"/, html, 'demand splitter node present')
    assert_match(/class="demand-mixer"/, html, 'demand mixer node present')
    branches = html.scan('class="demand-branch"').size
    assert_operator branches, :>=, 2,
                    "vertically-stacked demand branches present, got #{branches}"
  end

  def test_writes_file_matching_return_value
    rendered = html # reference first: the memoized render is what writes OUT_PATH (order-independent)
    assert File.exist?(OUT_PATH), 'catalog_html writes a file when a path is given'
    written = File.read(OUT_PATH)
    assert_equal rendered, written, 'written file equals the returned string'
    rows.each do |r|
      assert_includes written, esc(r['name']), "written file contains argument name #{r['name']}"
    end
  end
end
