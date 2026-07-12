# Envelope costing data — provenance and licensing

Vendored from openstudio-standards `btap/common_resources/` (public repo), same policy
as the openstudio-hvac gem's `data/costing/README.md`.

Files vendored here (all UNPRICED):
- `constructions.json` — costed assembly catalogs per surface sheet (wall/roof/floor/
  window/skylight/door/door_glass/bg_wall/bg_roof/slab): BTAP-* assembly name → per-USI
  construction variants with `id_layers` (materials sheet row ids). No dollar values.
- `materials_opaque.csv` / `materials_glazing.csv` — layer id → RS-Means line-item id
  mapping + per-layer quantity/multipliers (+ glazing optical/frame attributes used for
  SHGC solar-film matching). The vestigial `material_cost`/`labour_cost`/
  `equipment_cost`/`*_op_factor` reference columns were BLANKED at vendoring time —
  the costing engine never reads them; all pricing flows through the costs table.
- `thermal_bridging.csv` — TBD edge type × wall-reference (assembly + quality) →
  `material_opaque_id_layers` × `id_layers_quantity_multipliers` ($/ft piecework
  recipes, BETB detail references). No dollar values.
- `locations.csv` — city latitude/longitude for nearest-cost-location matching.

Files deliberately NOT vendored here:
- `costs.csv` (line-item unit costs) and `costs_local_factors.csv` (city cost-index
  factors). These are RS-Means-schema priced tables; to avoid a third in-repo copy the
  envelope `Database` resolves them at runtime, in order:
  1. explicit `costs_csv:` / `local_factors_csv:` arguments,
  2. the sibling openstudio-hvac gem's vendored copies
     (`../openstudio-hvac/lib/openstudio_hvac/data/costing/`),
  and raises with instructions when neither is available.
- Real licensed RS-Means values must only ever be **injected at runtime** via
  `costs_csv:` and must **never be committed** to this repository or redistributed.
