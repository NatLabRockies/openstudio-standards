# CLAUDE.md — openstudio-geometry

SDK-only geometry-authoring gem: the seven parametric shape wizards
(rectangle, L, T, U, H, E, courtyard) and the Goldwasser bar engine, plus tiny
BTAP helpers. This is the on-ramp for authoring models from nothing (and for
the future MCP server) — its output feeds loads → lighting → shw → hvac →
envelope.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `audit_log.rb` is a verbatim copy of
  openstudio-hvac's — regenerate from there on schema changes.
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
- Facade: `OpenStudioGeometry.create(shape:, **params)` and
  `OpenStudioGeometry.bar(space_type_ratios: {[building_type, space_type] => fraction}, ...)`.

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
- `rotate_model` sign convention: +45° produces +π/4 in atan2 terms.
- Bar honors WWR, party walls become adiabatic, below-grade surfaces get
  Ground boundary conditions.
- Full-family composition is pinned by test: bar geometry → loads → lighting
  → shw → hvac → envelope with ONE audit — keep that test green when changing
  output structure.

## Tests

`cd openstudio-geometry && ruby test/test_wizards.rb test/test_bar.rb`.
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
