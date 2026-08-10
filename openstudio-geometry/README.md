# openstudio-geometry

Parametric building geometry — the **authoring on-ramp** for the openstudio-*
NECB gem family (and the intended MCP tool surface). SDK-only; shared AuditLog
schema. Four engines: the footprint wizards and the bar engine (verbatim ports
from openstudio-standards), a 3D viewer (ported from canmet-energy/campus) and
a per-storey 2D floor-plan renderer:

## Footprint wizards

`OpenstudioStandards::Geometry.create_shape_*` ported whole (rectangle,
aspect-ratio with rotation, courtyard, H, L, T, U): perimeter/core zoning per
storey, matched surfaces. Rectangle supports below-grade storeys with Ground
boundary conditions; the other shapes do not (the aspect-ratio wrapper
delegates to rectangle but fixes below-grade storeys at 0).

```ruby
model = OpenStudioGeometry.create(shape: 'rectangle', length: 40.0, width: 25.0,
                                  storeys: 3, below_grade_storeys: 1,
                                  perimeter_zone_depth: 4.0, audit: audit)
OpenStudioGeometry.create(shape: 'l', length: 40.0, width: 40.0, storeys: 2)
```

`storeys:`/`below_grade_storeys:` are the canonical spellings across the
facade; the engines' own names (`above_ground_storys`, `under_ground_storys`,
`num_floors`, `num_stories_above_grade`, `num_stories_below_grade`) remain
accepted, but passing a canonical name and its engine name together raises.
Unknown parameters raise (typos never silently fall to defaults).

## The bar engine (Goldwasser lineage)

`create_bar` + `bar_hash_setup_run` and their five polygon/space helpers,
ported verbatim. The DOE/DEER building-type-ratio wrappers are deliberately
NOT ported (they depend on CreateTypical metadata and `Standard.build`);
instead the family-native entry assigns **NECB space types by ratio in one
step** — geometry arrives already standards-tagged for
`OpenStudioLoads.apply_loads`:

```ruby
model = OpenStudioGeometry.bar(
  space_type_ratios: { ['Space Function', 'Office enclosed > 25 m2'] => 0.7,
                       ['Space Function', 'Corridor/Transition area other-sch-A'] => 0.3 },
  length: 50.0, width: 20.0, storeys: 3, wwr: 0.4,
  party_wall_stories_north: 2, below_grade_storeys: 1)
```

Slicing is ratio-true (verified to 1%), WWR is honored per facade, party-wall
storeys go adiabatic, below-grade surfaces go Ground.

## The 3D viewer (campus port)

`OpenStudioGeometry.render(model_or_path, path:, height:)` — a port of
canmet-energy/campus `geometry_view.py`: the SDK `GltfForwardTranslator`
produces glTF, embedded as a base64 data URI in a Google `<model-viewer>` HTML
fragment (a complete standalone page is also written when `path:` is given).
Every export runs in a child process (`render_worker.rb`) because the C++
translator can SEGFAULT on un-triangulatable surfaces; the campus fallback
ladder then retries — full model → sub-surfaces removed (massing shell) →
binary-search removal of crashing base surfaces. Unrenderable models return
`''` (audited, never raises).

```ruby
OpenStudioGeometry.render(model, path: 'building_3d.html')
```

Trade-off carried from campus: the `<model-viewer>` SCRIPT loads from the
Google CDN at view time (the caption says so); the geometry itself is fully
embedded. A CSP that blocks external hosts (e.g. Artifacts) will not run this
viewer.

## Floor plans (per-storey 2D)

`OpenStudioGeometry.floor_plans(model_or_path, path:, png_dir:, audit:)` — the
2D counterpart to the 3D viewer, for the everyday question *"what are the
spaces and zones in this model called?"*. One inline-SVG plan per storey: space
footprints in **world coordinates** (`space.transformation * surface.vertices`,
so rotated buildings draw rotated), filled by thermal zone from a deterministic
palette, labelled with space name + zone name at the centroid, and every
polygon carries a `space | zone | space type | area` hover tooltip — plus a
shared zone legend and a metric scale bar.

```ruby
bundle = OpenStudioGeometry.floor_plans(model, path: 'floor_plans.html')
bundle[:storeys].map { |s| s[:name] }        # => ["Story 0", "Story 1", "Story 2"]
bundle[:storeys].first[:svg]                 # inline <svg> string, embeddable anywhere
bundle[:legend_svg]                          # the shared thermal-zone legend
```

The returned bundle — `{ storeys: [{name:, svg:}], legend_svg:, empty:,
inferred_storeys:, error: }` — is the same never-raises shape
`OpenStudioHVAC::CatalogReport.model_diagrams` returns, so a host report (the
NECB AHJ compliance report) can embed the plans and degrade to a one-line note
on an empty or unreadable model. Layering: `plan_query.rb` is the only
SDK-touching file (plain hashes out), `plan_svg.rb` and `plan.rb` are SDK-free.

The standalone page written to `path:` is **fully self-contained** — inline CSS
and SVG, native `<details>`, no scripts and no external references at all (one
`break-inside: avoid` section per storey, page-broken so printing gives a plan
per page). Unlike the 3D viewer, it renders under a strict CSP.

`png_dir:` additionally rasterizes one PNG per storey, if a system converter is
installed (`rsvg-convert` → `cairosvg` → `magick`); when none is, the audit gets
a loud warning and no PNG is written — PNGs are never a required output.

Storeys come from `BuildingStory` objects, ordered by minimum world z. A model
without them (or with unassigned spaces) falls back to binning floor elevations
at ±0.01 m into synthesized `Level N` storeys, flagged `inferred_storeys: true`
plus an audit warning. Spaces with no `Floor` surface are warned and skipped;
a space with floors at several elevations is cut at the lowest one.

## Composing with the family

Bar/wizard output carries **no constructions** — downstream envelope work
retargets existing ones, so seed a basic construction set (or start from an
OSM that has one) before `OpenStudioEnvelope` passes. With that, the full
authoring chain is gem-only:

geometry → `OpenStudioLoads.apply_loads` → `OpenStudioLighting.apply_lights` →
`OpenStudioSHW.apply_shw` → `OpenStudioHVAC.build_system` →
`OpenStudioEnvelope` prescriptive → `OpenStudioNECB.performance_compliance`
(proposed + reference + costing, one audit) — pinned by
`test/test_bar.rb#test_full_family_composition_from_bar`.

## Citation conventions

`article:` in audit entries = the NECB clause that mandates a value;
`ruling: 'D-nn'` = the adjudicated reading of it. The registry is
[openstudio-necb/docs/necb_decisions.md](../openstudio-necb/docs/necb_decisions.md)
(id-ordered index at the top) + its drift-tested `decisions.json` mirror;
`L-nn` cites the legacy findings register. The family glossary lives in
[openstudio-necb/docs/README.md](../openstudio-necb/docs/README.md).

## Testing

```bash
cd openstudio-geometry
ruby test/test_wizards.rb   # shape census, matching, ground BCs, rotation, typo guards
ruby test/test_bar.rb       # ratio-true slicing + tagging, WWR, party/below-grade, family composition
ruby test/test_render.rb    # crash-isolated glTF export, fallback ladder, embedded-viewer HTML
ruby test/test_floor_plan.rb # world-coordinate extraction, storey grouping, SVG layer, self-contained page
```

## Documented future

A seed-construction-set helper (candidate for the envelope gem) · FloorspaceJS
import · the DOE/DEER building-type-ratio wrappers (host-scope).
