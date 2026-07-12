# NECB envelope rule data — provenance

## envelope_rules_<vintage>.json

Machine-readable transcription of the NECB envelope requirements:

- **U-values** (`u_values`): maximum overall (**effective**, per 3.1.1.7 — thermal
  bridging included) thermal transmittance by boundary (outdoors/ground), surface type
  (wall/roofceiling/floor/window/skylight/door) and HDD climate-zone bin (ceilings
  {3000,4000,5000,6000,7000,9999} = zones 4/5/6/7A/7B/8). Lookup rule is legacy-exact:
  first value where `hdd < bin`, fallback 0.110.
- **FDWR** (`fdwr`): Article 3.2.1.4.(1) as **structured piecewise data, never eval'd**
  (constant / linear pieces). Boundary note: code text says ≤4000 → 0.40; legacy uses
  <4000 with the linear branch yielding the identical 0.40 at exactly 4000.
- **SRR** (`srr_max`): 3.2.1.4.(2), 2% of gross roof area (2017+ value; NECB 2011 was
  5% — relevant only to the future vintage backfill).
- **Reference envelope** (`reference_envelope`): the 8.4.4.3/8.4.4.4 (2025: 8.4.5.3/.4)
  parameters — populated fully in P4 (lightweight layers pinned from Note
  A-8.4.4.4.(1), air leakage from 8.4.3.3.(3)).
- **article_coverage**: the completeness manifest (same contract as openstudio-hvac) —
  every governed article with status; emitted into every run's audit; statuses flip as
  phases land.

Sources:
- **2020**: Tables 3.2.2.2 / 3.2.2.3 / 3.2.3.1 + Article 3.2.1.4, retrieved via the
  building-codes MCP server (necb:2020) and **cross-checked cell-by-cell against legacy
  openstudio-standards `NECB2020/data/surface_thermal_transmittance.json` — exact
  match** (door row per legacy refs PCF 1536/1537).
- **2025**: Tables 3.2.2.2 / 3.2.2.3 / **3.2.2.4 (doors, split out in 2025)** /
  3.2.3.1 + 3.2.1.4 via MCP (necb:2025). **All values verified identical to 2020**
  (opaque/fenestration/ground byte-match; the new door table equals the 2020 door
  row). Performance-path articles renumbered 8.4.4.x → 8.4.5.x (verbatim text).
- Runtime never contacts the MCP; regenerate/diff these files when editions change.

## table_c1.json

NECB Table C-1 climatic data (679 cities: lat/long, HDD18, design temperatures),
vendored from legacy `NECB2011/data/necb_2015_table_c1.json`, used for the
nearest-city HDD lookup (haversine, 500 km tolerance) mirroring legacy
`get_necb_hdd18`. The NECB 2025 Table C-1 (680 rows) is on the MCP as a future
cross-check/refresh source.
