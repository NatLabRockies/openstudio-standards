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
- `footprint.rb` — MEASURED-footprint massing (facade
  `OpenStudioGeometry.create_from_footprint(geojson:, height_m:, ...)`): a real
  outline (GeoJSON ring from a building-stock service, survey or GIS export)
  plus a measured height in, zoned storeys out. **The one file here that is NOT
  a port** — there is no upstream equivalent; the wizards build their polygons
  analytically so winding and validity hold by construction, which a measured
  ring guarantees neither. Deliberately a PEER of `create`, not a member of
  `SHAPES`: `create` dispatches positional scalars through `ordered`, and a
  coordinate ring is not that shape. Stays SDK-only and offline — fetching
  records, choosing a storey height, and class→space-type mapping are the
  caller's, never the gem's.
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

- **`Space.fromFloorPrint` needs CLOCKWISE-from-above vertices** and returns an
  uninitialized Optional with NO message otherwise (the caller dies later on a
  bare `Optional not initialized`). `OpenStudio.removeSpikes` / `buffer` are
  boost-backed and want the same winding — a counter-clockwise ring comes back
  EMPTY, not reversed. `Footprint.normalize` always forces winding; never hand
  a raw ring straight to the SDK.
- **`OpenStudio.simplify` does NOT decimate** — it only drops collinear points,
  so a 69-vertex outline survives a 1 m tolerance untouched and becomes 69
  exterior walls per storey. `Footprint.decimate` is Douglas-Peucker, split at
  the far vertex so a closed ring cannot collapse.
- **Mitred core/perimeter offset is EXACT on convex outlines** (50×30 rectangle
  tiles to 1500.0000 m²) but adjacent perimeter quads OVERLAP at reflex
  corners, and real outlines are full of them (the Ottawa test fixture: 33
  reflex of 69). So `Footprint.core_and_perimeter` self-polices — validity is
  "every core vertex stands ≥ depth from every wall" (`clearance`), because the
  weaker area/winding/containment tests all pass on an inverted core from a
  symmetric over-offset. It returns `{rejected: <reason>}` rather than a broken
  layout; the facade then degrades to single-zone storeys with a `warn`.
- **What decides whether an outline can carry core/perimeter is WALL-RUN
  LENGTH against the offset depth — not vertex count, not concavity.** An
  inward offset eats `D/tan(t/2)` off both ends of every wall run, so edge i
  survives only while `L > D*(cot(t_i/2) + cot(t_i+1/2))`; reflex corners
  contribute a NEGATIVE term, which is why concavity is harmless on its own (a
  19-vertex outline with 37% reflex corners zones fine). For two convex right
  angles the term is `2D`, so **at the 15 ft default no wall run under 9.14 m
  can carry a perimeter zone**. `Footprint.max_perimeter_depth` returns the
  outline's own ceiling, and the rejection message quotes it. Measured over 40
  consecutive NRCan records this separates perfectly — every accepted outline
  had margin ≥ +2.03 m, every rejected one was negative — and the median
  outline's ceiling is only **2.59 m**, which is why the single-zone fallback
  is the common case on auto-extracted stock.
- **The lever is `perimeter_zone_depth`, not `decimate_tolerance`**, hence the
  `:auto` default = `min(15 ft, 0.95 x ceiling)`. Lowering depth costs NO area
  (outlines held identical): 6/40 at a fixed 15 ft, 15/40 at 9.8 ft, 24/40 at
  6.6 ft. Decimating harder reaches 15/40 only at 4 m and 25/40 at a
  destructive 10 m (45% worst-case area loss). On the full defaults the batch
  gets 14/40 core/perimeter (from 6/40), 6 of them keeping the full 15 ft,
  median depth 3.22 m. Any reduction below the convention emits a `warn` — a
  narrowed band is no longer the code's daylit zone, so it must never be silent.
- **Footprint SIZE must NOT drive the depth.** Measured, `corr(sqrt(area),
  ceiling) = +0.198` (log-log +0.069) — none. The ceiling is set by the
  shortest wall run, a local feature: outlines under 15 m across had a HIGHER
  median ceiling (2.88 m) than 30-50 m ones (1.66 m). Only `decimate_tolerance`
  scales with size, and only because area LOSS scales with size.
- **Perimeter zones merge by ORIENTATION, and it is zone membership that
  merges — not polygons.** Spaces stay one-per-edge (geometry exact, no polygon
  union needed, surface matching untouched) while each joins the thermal zone
  of its compass bin, so a storey presents `North/East/South/West/Core ZN`
  however many edges the outline has. Across 46 NRCan records this capped zones
  per storey at 5 (was up to 20) with ZERO exterior walls in the wrong bin.
  `Footprint.edge_azimuth` uses the SDK's own convention — outward normal,
  degrees clockwise from north — and is pinned against `Surface#azimuth`, which
  reports 270/0/90/180 for a rectangle's four walls. Bins are 45-degree
  boundaries with North wrapping through 0. A zone may hold NON-CONTIGUOUS
  spaces (an L has two north faces); that is legal in OpenStudio and is exactly
  why a real polygon union was not attempted.
- **Geometrically viable != useful.** A 50x30 rectangle still offsets at 14.9 m
  but leaves a 0.27% core, so `MIN_CORE_FRACTION` (4%) rejects slivers. That 4%
  is NOT invented: `create_shape_rectangle` already refuses core/perimeter
  unless both plan dims exceed 2.5x depth, which for a square is exactly a 4%
  core — same convention, generalized.
- **`MIN_USEFUL_DEPTH` is 3.0 m (~10 ft), not a token minimum.** `:auto` will
  shrink the depth to fit any outline, which defeats the wizards' 2.5x-plan-dim
  convention (that presumes a FIXED depth). Measured over 46 records, a 1 m
  floor starts handing core/perimeter to 55 m2 houses — all perimeter in
  reality; at 3 m the smallest zoned outline is 104 m2 and the median depth
  returns to the full 15 ft. Below the floor, callers get `:single`.
- **`decimate_tolerance:` defaults to `:auto`, and must.** A fixed tolerance
  cannot serve a whole building stock: at a flat 2 m the same batch lost 14.8%
  of a small house's floor area (mean 1.60%), against 2.87% worst / 0.67% mean
  once the tolerance scales as `sqrt(area)/25` clamped to [0.25, 3.0].
- **`apply_wwr(model, ratio)` is PURE GEOMETRY — no default, no code
  knowledge.** NECB's FDWR maximum is `openstudio-envelope`'s rule
  (`NECB.max_fdwr(vintage:, hdd:)`, article 3.2.1.4, vintages '2020'/'2025' —
  NOT 'NECB2020'); this gem carries no NECB rules data by family contract, so
  the caller passes a number it chose. Accepts a Float or per-orientation bins
  ('South' => 0.4); bins left out get NO windows. Three spellings work (Hash,
  brace-less, Symbol) because with an `audit:` kwarg Ruby 3 parses a brace-less
  hash as keywords — hence the `**bins` catch.
- **THERMOSTATS gate the whole envelope pass** (corrected, D-75 — an earlier
  note here blamed construction seeding). `OpenStudioEnvelope::Geometry.conditioned?`
  requires `partofTotalFloorArea` AND a zone `thermostatSetpointDualSetpoint`;
  `exposed_walls`/`exposed_roofs` filter on it, so on measured massing — zones
  but NO thermostats — the census returns 0 walls and
  `apply_prescriptive(apply_fdwr: true)` bails silently at 0 subsurfaces. Add a
  dual-setpoint thermostat per zone and the SAME call yields 60 windows at
  FDWR 0.3667 with 60/60 constructions, on a model that started windowless.
- **openstudio-envelope CAN seed fenestration constructions, but NOT opaque
  ones.** `subsurface_target_construction` (private; invoked automatically by
  `apply_fdwr:`/`apply_srr:`) builds a SimpleGlazing construction at the
  prescriptive U from nothing. Opaque has no equivalent: `assign_surface` warns
  "no layered construction — skipped", `Constructions.opaque_at_conductance`
  deep-copies a base you must supply, and `Reference` does
  `next if surface.construction.empty?` and reads conductance off the original.
  So an opaque SEED is still the real missing piece — openstudio-envelope's own
  future-work note.
- `apply_wwr` therefore is NOT the only way to get windows on measured massing
  (thermostats + `apply_fdwr:` also works). It stays useful because it is pure
  geometry — a ratio YOU choose, per-orientation, no thermostats, no NECB.
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

## Building-stock adapter (`scripts/building_stock.rb`)

NRCan footprint records -> massing. Lives in `scripts/`, NOT `lib/`, because
`spec.files` is `lib/**/*` — so the networked fetch sits beside its consumer
without shipping in an SDK-only gem (D-71/D-72). `Footprint` still never learns
where a ring came from.

- Transport: stateless JSON-RPC `tools/call` to the HTTP MCP server; the reply
  is an SSE `data:` frame whose `result.content[0].text` is itself JSON. Same
  shape as `openstudio-necb/scripts/fetch_necb_8_4_text.rb`.
- Auth: `BUILDING_STOCK_MCP_URL` / `BUILDING_STOCK_API_KEY`, else `.mcp.json`
  (gitignored). NOTHING hardcoded; the key is never printed, never written to
  the cache, never stamped on a model.
- `--cache` / `--from-cache` split so a build is reproducible and needs no
  network — the NECB text fetcher's rule.
- `Adapter.stamp` writes the record onto `building.additionalProperties` as
  `nrcan_*` so the next stage (WWR by class/vintage, weather by FSA) reads it
  off the model. Deliberately NOT `setStandardsBuildingType` — `building_class`
  is NRCan's heuristic, not a standards building type.
- **`multiplier:` defaults to `:mid` here, unlike the gem facade.** Stock work
  is bulk: a 28-storey record is 336 real spaces at `:none` and 36 at `:mid`
  for the same loads and envelope.

## Tests

`cd openstudio-geometry && ruby test/test_wizards.rb test/test_bar.rb`
(`test/test_render.rb`, `test/test_floor_plan.rb` for the two renderers,
`test/test_footprint.rb` for measured footprints — ~35 s, it builds 27-storey
massing several times over). `test/fixtures/footprint_ottawa_tower.json` is a
REAL NRCan building-stock record (feature `870226c8`, Ottawa K1P, 69 vertices /
33 reflex / 5,266 m² published / 82.65 m) kept verbatim so the traps above
cannot quietly stop being tested — do not tidy it.
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
