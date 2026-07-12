# openstudio-necb

The **umbrella** gem for the NECB Part 8 performance path. It composes the two
SDK-only domain gems —

- [openstudio-hvac](../openstudio-hvac): reference system selection (Table
  8.4.4.7.-A), topology builds, capacity-binned efficiencies, ERV, fan rules
- [openstudio-envelope](../openstudio-envelope): prescriptive Section 3.2,
  thermal bridging (3.1.1.7 via TBD), the reference-envelope transform
  (8.4.4.3/.4), envelope + thermal-bridging costing

— into the full proposed-vs-reference determination of **Article 8.4.1.2**
(Division B; wording stable across 2020/2025):

- **(2)** annual energy consumption of the proposed building ≤ the building
  energy target of the reference building
- **(3)** unmet heating hours ≤ 100 h/year for both buildings
- **(4)** unmet cooling hours: proposed within +10% of reference (2025: +10% or
  20 h, whichever is greater, on the 8.4.5 path)
- **(5)** where (3)/(4) fail: capacities *shall be incrementally increased* —
  this pipeline REPORTS the condition loudly; it does not auto-iterate.

This is the ONE place simulation execution lives (pure SDK + `openstudio` CLI,
no measures, no openstudio-standards). The domain gems never simulate. One clone
carries both reference transforms; ONE AuditLog spans system selection,
efficiencies, envelope decisions, article coverage, the 8.4.1.2 verdicts, and
(optionally) HVAC + envelope costing of both models.

## Usage

```ruby
require 'openstudio_necb'   # resolves sibling gems in the monorepo, or installed gems

result = OpenStudioNECB.performance_compliance(
  proposed_model,                      # Model or .osm path — never mutated
  vintage: '2020',                     # or '2025'
  weather: { epw: 'x.epw', ddy: 'x.ddy', stat: 'x.stat' },
  building: { storeys: 3, zone_types: { 'Zone 1' => 'Office - enclosed' },
              winter_design_temp_c: -20 },   # facts for system selection
  run_dir: 'runs/my_building',
  simulate: :annual,                   # :annual | :sizing | :none
  costing: true, costs_csv: 'licensed_costs.csv',  # runtime injection only
  thermal_bridging: 'efficient (BETBG)')

result.compliant            # true / false (nil unless simulate: :annual)
result.report               # written to run_dir/report.json
result.audit                # ONE audit — run_dir/audit.json + audit.txt
result.reference_model      # the fully-transformed reference building
```

## What the pipeline does

1. Clones the proposed model, attaches weather (EPW + DDY design days).
2. **Sizing run of the proposed** (the domain gems never simulate; selection
   kW thresholds, capacity-binned efficiencies, and costing need capacities).
3. `OpenStudioHVAC::NECB.reference_hvac` — reference systems on a fresh clone.
4. `OpenStudioEnvelope::NECB.reference_envelope` — reference envelope on the
   SAME clone, same audit.
5. Sizing run of the reference, then **efficiencies re-applied** on the sized
   capacities (the openstudio-hvac contract).
6. `simulate: :annual` — full-year runs of both models (a `run_period:`
   override exists for tests, and any shortened period is flagged in the report
   and audit as NOT a code-compliant determination).
7. 8.4.1.2 sentences (2)–(4) evaluated; every verdict lands in the audit with
   its article; a (5) failure is a loud warning.
8. `costing: true` — HVAC (openstudio-hvac) + envelope (openstudio-envelope)
   costing of BOTH models into the same audit, with the incremental
   proposed-vs-reference cost in the report.
9. `report.json`, `audit.json`, `audit.txt` written to `run_dir`.

## Modes

| `simulate:` | What runs | `compliant` |
|---|---|---|
| `:annual` | sizing + annual for both models | true/false |
| `:sizing` | sizing only (models generated, sized, costable) | nil |
| `:none` | model transforms only — proposed stays UNSIZED (loud warning: kW thresholds and capacity bins fall back) | nil |

## Testing

```bash
cd openstudio-necb
ruby test/test_compliance.rb   # 4 tests: :none transforms, :sizing + unified
                               # costing, :annual week-run full determination,
                               # caller-model immutability. E+ runs skip without
                               # the openstudio CLI.
```

Test fixtures are shared with the sibling gems (no third copy of the weather trio).

## Licensing note

Costing follows the domain gems' policy: vendored data is placeholder/unpriced;
real licensed RS-Means values are **runtime-injected** via `costs_csv:` and must
never be committed or redistributed.
