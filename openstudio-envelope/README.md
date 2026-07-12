# openstudio-envelope

NECB building-envelope prescriptive rules and reference-envelope transforms for
OpenStudio models — the second domain gem following the
[openstudio-hvac](../openstudio-hvac) pattern:

- **SDK-only.** Pure `openstudio` model manipulation; the gem never executes
  simulations (a CLI sizing recipe is shown below for when you want one).
- **Vendored, article-tagged rule data.** `lib/openstudio_envelope/data/necb/`
  holds NECB 2020 + 2025 envelope rules generated and verified offline via the
  building-codes MCP server — zero MCP dependency at runtime. Every value carries
  its article. See the data [README](lib/openstudio_envelope/data/necb/README.md)
  for provenance and regeneration.
- **AuditLog everywhere.** Every decision (U-value applied, window scaled, TBD
  derate, air-leakage arithmetic) lands in a shared audit with
  `{step, target, action, inputs, value, article, evidence, level}` — the SAME
  schema as openstudio-hvac, so one audit can span HVAC + envelope + costing.
- **Article-coverage accounting.** Every run emits the full article manifest with
  honest statuses; anything `partial`/`not_implemented` is a WARNING, never silent.

Vintages: **2020 and 2025** (2025 verbatim on envelope values; performance path
renumbered 8.4.4 → 8.4.5). 2011/2015/2017 backfill is a documented future item.

## Quick start

```ruby
require 'openstudio'
require_relative 'openstudio-envelope/lib/openstudio_envelope'

model = OpenStudio::Model::Model.load('proposed.osm').get

# --- Lookups (Section 3.2, by heating degree-days) ---
OpenStudioEnvelope::NECB.max_u(vintage: '2020', surface: 'wall',
                               boundary: 'outdoors', hdd: 3890)  # => 0.265 W/(m2.K)
OpenStudioEnvelope::NECB.max_fdwr(vintage: '2020', hdd: 3890)    # => 0.40
OpenStudioEnvelope::NECB.max_srr(vintage: '2020')                # => 0.02
OpenStudioEnvelope::Climate.hdd18(model)  # explicit > Table C-1 nearest city > .stat

# --- Prescriptive application (3.2 via 3.1.1.5/.6) ---
audit = OpenStudioEnvelope::AuditLog.new
OpenStudioEnvelope::NECB.apply_prescriptive(
  model, vintage: '2020',
  apply_fdwr: true, apply_srr: true,             # geometry mutators, opt-in
  thermal_bridging: 'efficient (BETBG)',         # NECB 3.1.1.7 via the tbd gem
  audit: audit
)

# --- Reference envelope (8.4.4.3/.4; 2025: 8.4.5.3/.4) — greenfield ---
reference = model.clone(true).to_Model
OpenStudioEnvelope::NECB.reference_envelope(reference, vintage: '2020', audit: audit)

puts audit.to_json          # every decision, article-tagged
audit.warnings.each { |w| warn w[:action] }  # gaps are never silent
```

## What the reference-envelope transform does

`reference_envelope` operates IN PLACE on the caller's clone, composing (order
matters; article prefix is 8.4.4 for 2020, 8.4.5 for 2025):

1. **Prescriptive Section 3.2** on the reference (`.1.(2)`).
2. **FDWR/SRR overage → proportional scaling** of the EXISTING fenestration per
   orientation (`.3.(3)`) — each window is scaled about its own centroid by
   `sqrt(area_ratio)`; never a window rebuild, so counts, positions, and each
   orientation's share are preserved.
3. **Roof solar absorptance 0.7** — only when you pass
   `actual_roof_absorptance_used: true` (`.3.(1)/(2)`); otherwise the proposed
   value is kept, per the code.
4. **Shading**: Space/Building shading groups and ShadingControls removed;
   Site groups (nearby structures) kept (`.3.(4)-(5)`).
5. **Fenestration optics preserved** — only U changes, SHGC/VT ride along on the
   construction (`.3.(8)`).
6. **Lightweight construction** (`.4.(1)`): every opaque assembly is rebuilt as a
   single MASSLESS layer at its unchanged (already-prescriptive) resistance —
   zero thermal mass, identical Ut. The canonical Note A-8.4.4.4.(1) layer set is
   not machine-retrievable; this interpretation is documented in the coverage
   manifest and flagged as a gap.
7. **Air-leakage default** (`.3.(6)` via 8.4.3.3.(3) + 8.4.2.9.(2)):
   `I_AGW = (5/75)^0.6 × 1.50 × S / A_AGW` applied per space as flow per exterior
   above-ground wall area, full arithmetic in the audit.
8. **Article-coverage emission** — all 14 envelope articles, statuses + citation
   counts.

## Thermal bridging (NECB 3.1.1.7)

The Table 3.2.2.x values are **effective** overall transmittance
(`Ut = Uo + Σψ·L/A + Σχ·n/A`) — clear-field U-values alone under-insulate relative
to code intent. Pass `thermal_bridging:` (a TBD built-in PSI set name such as
`'efficient (BETBG)'`, or a `{detail => psi}` Hash) and the gem drives the
[tbd](https://github.com/rd2/tbd) gem to **uprate** each assembly so its **derated**
Ut meets the prescriptive target, with per-surface derating evidence in the audit.

Honesty rules:
- `thermal_bridging:` not requested → an audit WARNING that 3.1.1.7 is unaccounted.
- tbd gem unavailable → loud warning, clear-field values applied.
- Physically infeasible uprate (edge losses alone exceed the target) → TBD's
  refusal is forwarded into the audit, never swallowed.

## Envelope + thermal-bridging costing

`OpenStudioEnvelope.cost(model, ...)` prices ANY model's envelope the legacy BTAP way:
each of the 16 costed surface types maps to a BTAP-* assembly catalog
(`data/costing/constructions.json`), every catalog candidate's `id_layers` is priced
through the materials sheets → cost table → regional factors, and each surface's
$/ft² is the linear interpolation of that (RSI, cost) curve at the surface's own RSI
(films included for opaque surfaces, `uprated_Uo` honoured after TBD runs). Glazing
adds the nearest-SHGC solar-film premium; a TBD result adds the parapet allowance and
the thermal-bridge edge piecework (`thermal_bridging.csv`, BETB details).

```ruby
report = OpenStudioEnvelope.cost(model,
  structure: { framing: :steel }, performance: :lp,
  tbd_result: tbd_result,          # from NECB::ThermalBridging.apply — TB edges + parapet
  costs_csv: 'licensed_costs.csv', # runtime injection ONLY; never commit priced values
  audit: audit)                    # ONE audit spans compliance + costing
report.total; report.envelope['surface_types']; report.thermal_bridging['by_material']
```

Honesty + licensing notes:
- The vendored costing sheets are UNPRICED (see `data/costing/README.md`); the priced
  tables resolve from `costs_csv:`/`local_factors_csv:`, `OPENSTUDIO_COSTING_DIR`, or
  the sibling openstudio-hvac gem's public vendored copies.
- Cost-curve upper-bound overruns (no catalog assembly reaches the required RSI) flag
  `unrealistic_assembly` + an audit WARNING — replacing legacy's silent $10¹² sentinel.
- **Legacy defect fixed loudly**: legacy `cost_audit_thermal_bridging`'s `find` block
  never tests the material id (its `total +=` body is truthy), so every thermal-bridge
  edge is priced as materials_opaque row 1 — *gypsum wallboard*. The port matches BY id
  and records the deviation in the audit.
- Parity gates: interpolator exact vs `BTAP::LinearRegression`; all 92 catalog
  candidates within a cent of legacy `cost_construction`; per-surface RSI ==
  `TBD.rsi`; TB material quantities exact vs `BTAP::BridgingData`.

## Composing the full NECB reference building (with openstudio-hvac)

ONE clone, ONE audit — HVAC then envelope:

```ruby
require_relative 'openstudio-hvac/lib/openstudio_hvac'
require_relative 'openstudio-envelope/lib/openstudio_envelope'

audit = OpenStudioHVAC::AuditLog.new    # schema-identical to the envelope AuditLog
result = OpenStudioHVAC::NECB.reference_hvac(proposed, vintage: '2020',
                                             building: building_facts, audit: audit)
OpenStudioEnvelope::NECB.reference_envelope(result.model, vintage: '2020', audit: audit)
# audit now spans system selection, efficiencies, ERV, envelope U-values,
# fenestration scaling, air leakage — plus BOTH article-coverage manifests.
```

To size/run the result, use the pure SDK+CLI recipe from the
[openstudio-hvac README](../openstudio-hvac/README.md) (ddy design days +
`DoZoneSizingCalculation`/`DoSystemSizingCalculation`/`DoPlantSizingCalculation` +
`WorkflowJSON` + `openstudio run -w`).

## Testing

```bash
cd openstudio-envelope
ruby test/test_data_integrity.rb      # rule data integrity + structural diff vs legacy
ruby test/test_lookups.rb             # max_u / max_fdwr / max_srr / hdd18
ruby test/test_prescriptive.rb        # per-surface application, FDWR/SRR mutators
ruby test/test_reference_envelope.rb  # reference transform + composition + E+ run
ruby test/test_e2e_run.rb             # prescriptive E2E EnergyPlus gate

# Legacy-parity + TBD suites need the repo bundle (tbd + openstudio-standards):
BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby test/test_lookup_parity.rb
BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby test/test_prescriptive_parity.rb
BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby test/test_thermal_bridging.rb
```

Parity gates (0 mismatches vs `Standard.build('NECB2020')`): U-value lookups across
12 HDDs × all surface/boundary pairs, FDWR/SRR sweeps, HDD resolution (Table C-1 and
.stat paths), and per-surface conductance after application.

## Conventions inherited from legacy (deliberate)

- **Construction-only conductance by default** (air films excluded), matching BTAP —
  legacy costing keys off construction names like `Base:U-0.265` and
  `Base:U=0.19 SHGC=0.4`, which this gem reproduces. Pass `include_films: true`
  for code-correct overall transmittance; the choice is audited either way.
- HDD via Table C-1 nearest city (haversine, 500 km tolerance) before falling back
  to the `.stat` file's 18 °C base line — same precedence as `get_necb_hdd18`.

## Documented future (not yet in scope)

2011/2015/2017 rule backfill · envelope + thermal-bridging costing (the P3b
assembly/detail vocabulary is kept compatible with `btap/bridging.rb` for this) ·
air-leakage refinements · an umbrella gem composing hvac + envelope reference
generation with compliance simulation/reporting.
