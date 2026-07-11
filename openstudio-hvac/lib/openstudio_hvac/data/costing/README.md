# Costing data — provenance and licensing

Vendored from openstudio-standards `btap/common_resources/` + `btap/costing/` (public repo).

- **Schema is RS-Means-derived** (line-item ids, city cost-index localization structure —
  RS-Means is a proprietary Gordian dataset).
- **Shipped values are overwhelmingly `source: placeholder`** (1791 of 1968 rows in
  `costs.csv`) — US national-average stand-ins, NOT licensed RS-Means prices.
- Real licensed values must be **injected at runtime** via the `costs_csv:` option on
  `OpenStudioHVAC.cost` and must **never be committed** to this repository or redistributed.

Files:
- `costs.csv` — unit costs by line-item id (material / labour / equipment operation costs)
- `materials_hvac.csv` — HVAC component → line-item id mapping (+ per-item multipliers)
- `hvac_vent_ahu.csv` — AHU assemblies (component id layers × quantity multipliers)
- `costs_local_factors.csv` — city cost-index factors (material/installation, base 100)
- `locations.csv` — city latitude/longitude for nearest-location matching
- `mech_sizing.json` — engineering sizing tables (flow → pipe/duct diameters)
