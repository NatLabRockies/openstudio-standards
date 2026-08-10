# data/costing — lighting fixture costing sheets

Three CSVs ported from the legacy BTAP costing database
(`lib/openstudio-standards/btap/common/`, renamed from `btap/common_resources/`
by #2120), consumed by `costing/fixtures.rb`:

- `lighting_sets.csv` — template × building_type × space_type × CFL/LED →
  fixture-type selection by average-ceiling-height bin. The `template`
  column is the CSV's own vocabulary: it equals `"NECB" + vintage`
  (`NECB2020`), synthesized in `fixtures.rb`.
- `lighting.csv` — fixture rows: id_layers × quantity multipliers.
- `materials_lighting.csv` — the material rows those layers price through.

**Licensing (family rule):** these vendored sheets are UNPRICED/placeholder.
Real licensed RS-Means prices are runtime-injected — resolution order:
explicit `costs_csv:`/`local_factors_csv:` args → `OPENSTUDIO_COSTING_DIR` →
openstudio-hvac's public vendored CSVs. Licensed values must never be
committed, and reports embed cost TOTALS only.

Daylighting-sensor costing note: sensor counts derive from the legacy
daylighted-area rule in `costing/fixtures.rb` (`SENSOR_BOM` +
`daylighting_note` — sensor + 30 ft wiring + 30 ft conduit + box per sensor);
models without daylighting controls cost $0 exactly like legacy.
