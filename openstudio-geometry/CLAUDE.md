# CLAUDE.md — openstudio-geometry

SDK-only geometry-authoring gem: the seven parametric shape wizards
(rectangle, aspect-ratio, courtyard, H, L, T, U) and the Goldwasser bar
engine, plus tiny BTAP helpers. This is the on-ramp for authoring models from nothing (and for
the future MCP server) — its output feeds loads → lighting → shw → hvac →
envelope.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `audit_log.rb` aliases the shared class in
  **openstudio-audit** — schema changes happen there, never as a local copy.
- No NECB rules data here — this gem is code-agnostic authoring, so there is
  no article-coverage manifest.

## Architecture

- `wizards.rb` — the 7 `create_shape_*` wizards, SCRIPTED verbatim ports from
  legacy `geometry/create_shape.rb` (not hand transcriptions).
- `bar.rb` — the Goldwasser bar engine: `create_bar` + `bar_hash_setup_run`
  (ported from legacy `create_bar.rb` lines 452–1256 — everything ≥1257 was
  the CreateTypical/Standard-coupled arg pipeline and is deliberately
  excluded) + a 5-helper closure from `create.rb`.
- `helpers.rb` — `match_surfaces` / `rotate_model` / `set_boundary_condition`.
- **Floor plans** (`plan_query.rb` → `plan_svg.rb` → `plan.rb`, facade
  `OpenStudioGeometry.floor_plans(model_or_path, path:, png_dir:)`): per-storey
  2D plans. `plan_query.rb` is the ONLY SDK-touching file (plain hashes out,
  never raises — the necb `report/model_query.rb` boundary); `plan_svg.rb`
  holds a LOCAL COPY of necb's `report/svg.rb` primitives (fit-to-width
  viewBox, no width/height attrs) plus polygon/group/`<title>` — copied, never
  required upward (catalog_report.rb:29-32 precedent). `Plan.diagrams` returns
  the `model_diagrams`-shaped bundle `{storeys:[{name:,svg:}], legend_svg:,
  empty:, inferred_storeys:, error:}` a host report embeds; `Plan.html_report`
  writes a page that PASSES the family self-containment assertions (no
  scripts, no external references) — which the 3D `render` deliberately
  cannot. `Plan.png`/`Plan.pngs` are optional (rsvg-convert → cairosvg →
  magick; loud warn + nil when absent).
- Facade: `OpenStudioGeometry.create(shape:, **params)` and
  `OpenStudioGeometry.bar(space_type_ratios: {[building_type, space_type] => fraction}, ...)`.
- **Facade storeys vocabulary is `storeys:` / `below_grade_storeys:`** on BOTH
  entry points; audit inputs are `storeys_above:`/`storeys_below:`. The engines
  keep their upstream spellings, so the aliases are normalized per entry point
  before dispatch (`CREATE_ALIASES` → rectangle's
  `above_ground_storys`/`under_ground_storys`, everything else `num_floors`;
  `resolve_alias` → bar's `num_stories_*_grade`) — never inside `ordered`,
  whose unknown-key raise must keep firing for real typos. Old names still
  work; alias + engine name together raises (ambiguous);
  `below_grade_storeys:` on a non-rectangle shape raises.

## Key facts / traps

- **Wizard/bar output has NO constructions** — envelope passes retarget
  EXISTING constructions, so authored models need a seed construction set
  before any envelope work (future: seed helper in openstudio-envelope).
- **Bar output IS standards-TAGGED** (creates SpaceTypes with
  standardsBuildingType/standardsSpaceType and slices ratio-true, verified to
  1%); wizard output is NOT tagged — run openstudio-loads assignment on it.
- `bar_hash[:space_types]` entries need ABSOLUTE `:floor_area` values, not
  ratios — the facade converts.
- The verbatim ports must stay verbatim: when re-extracting legacy chunks, the
  LAST chunk swallows the module-closing `end`s — strip trailing low-indent
  `end` lines.
- `rotate_model` sign convention: +45° produces +π/4 in atan2 terms. It uses
  `changeTransformation`, which re-expresses each space in a rotated LOCAL
  frame and leaves the building where it stands — world coordinates are
  INVARIANT under it (pinned by `test_floor_plan.rb`). Anything reading
  geometry must go through `space.transformation * surface.vertices`; the
  `space.xOrigin + local vertex` shortcut (legacy costing/geometry.rb:233) is
  rotation-blind and produces garbage after a `rotate_model` call.
- Floor-plan zone colors hash zone names with a local djb2, NOT `String#hash`
  (Ruby seeds that per process — colors would change every run).
- Bar honors WWR, party walls become adiabatic, below-grade surfaces get
  Ground boundary conditions.
- Full-family composition is pinned by test: bar geometry → loads → lighting
  → shw → hvac → envelope with ONE audit — keep that test green when changing
  output structure.

## Tests

`cd openstudio-geometry && ruby test/test_wizards.rb test/test_bar.rb`
(`test/test_render.rb`, `test/test_floor_plan.rb` for the two renderers).
Fixtures shared from `../openstudio-hvac/test/fixtures`.

## 3D renderer (campus port)

- `render.rb` + `render_worker.rb` — port of canmet-energy/campus
  `src/buildings/reports/geometry_view.py`: SDK `GltfForwardTranslator` →
  glTF → Google `<model-viewer>` HTML, geometry embedded as a base64 data
  URI. Facade: `OpenStudioGeometry.render(model_or_path, path:, height:)`.
- **Every export runs in a child process** (`render_worker.rb` via
  `Process.spawn`) because the C++ translator can SEGFAULT on
  un-triangulatable surfaces — never call `modelToGLTF` in-process on
  untrusted geometry.
- Fallback ladder (campus-verbatim): full → sub-surfaces removed (massing
  shell) → binary-search crashing base surfaces (MAX_REMOVE 12 / MAX_PROBES
  80). `export_repaired` takes an injectable `exporter:` for deterministic
  ladder tests.
- Trade-off carried from campus: the <model-viewer> SCRIPT loads from the
  Google CDN at view time (caption says so); the geometry itself is fully
  embedded. A CSP that blocks external hosts (e.g. Artifacts) will not run
  this viewer.
