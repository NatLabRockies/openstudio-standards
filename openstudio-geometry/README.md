# openstudio-geometry

Parametric building geometry — the **authoring on-ramp** for the openstudio-*
NECB gem family (and the intended MCP tool surface). SDK-only; shared AuditLog
schema. Three engines: the footprint wizards and the bar engine (verbatim ports
from openstudio-standards) plus a 3D viewer (ported from canmet-energy/campus):

## Footprint wizards

`OpenstudioStandards::Geometry.create_shape_*` ported whole (rectangle,
aspect-ratio with rotation, courtyard, H, L, T, U): perimeter/core zoning per
storey, matched surfaces. Rectangle (and the aspect-ratio wrapper that
delegates to it) supports below-grade storeys with Ground boundary conditions;
the other shapes do not.

```ruby
model = OpenStudioGeometry.create(shape: 'rectangle', length: 40.0, width: 25.0,
                                  above_ground_storys: 3, under_ground_storys: 1,
                                  perimeter_zone_depth: 4.0, audit: audit)
OpenStudioGeometry.create(shape: 'l', length: 40.0, width: 40.0, num_floors: 2)
```

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
  length: 50.0, width: 20.0, num_stories_above_grade: 3, wwr: 0.4,
  party_wall_stories_north: 2, num_stories_below_grade: 1)
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
```

## Documented future

A seed-construction-set helper (candidate for the envelope gem) · FloorspaceJS
import · the DOE/DEER building-type-ratio wrappers (host-scope).
