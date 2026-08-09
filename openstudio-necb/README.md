# openstudio-necb

The **umbrella** gem for the NECB Part 8 performance path. It composes the
five SDK-only domain gems —

- [openstudio-hvac](../openstudio-hvac): reference system selection (Table
  8.4.4.7.-A), topology builds, capacity-binned efficiencies, ERV, fan rules
- [openstudio-envelope](../openstudio-envelope): prescriptive Section 3.2,
  thermal bridging (3.1.1.7 via TBD), the reference-envelope transform
  (8.4.4.3/.4), envelope + thermal-bridging costing
- [openstudio-loads](../openstudio-loads): NECB space-type assignment and
  space-use loads (occupancy, receptacles, ventilation, schedules)
- [openstudio-lighting](../openstudio-lighting): Part 4 LPD allowances,
  daylighting controls, the reference-lighting transform (8.4.4.5)
- [openstudio-shw](../openstudio-shw): Part 6 service-water-heating demand
  and minimum efficiencies, the reference-SHW transform (8.4.4.20)

— plus [openstudio-simulation](../openstudio-simulation) (the EnergyPlus
runner) into the full proposed-vs-reference determination of **Article
8.4.1.2** (Division B; wording stable across 2020/2025). The seventh family
gem, [openstudio-geometry](../openstudio-geometry), sits upstream: it creates
the model you feed in here.

The 8.4.1.2 determination:

- **(2)** annual energy consumption of the proposed building ≤ the building
  energy target of the reference building
- **(3)** unmet heating hours ≤ 100 h/year for both buildings
- **(4)** unmet cooling hours: proposed within +10% of reference (2025: +10% or
  20 h, whichever is greater, on the 8.4.5 path). The clause applies to thermal
  blocks *"for which mechanical cooling is provided"* — a proposed building with
  no mechanical cooling passes (4) vacuously (passive-overheating hours are not
  a cooling-capacity shortfall), with the determination audited.
- **(5)** where (3)/(4) fail: capacities are **incrementally increased until the
  loads are met** — the failing building's heating/cooling sizing factors are
  bumped by `capacity_step:` (default 1.25, per failing thermal block where the
  data supports it), the building re-sized and re-run (the reference
  additionally gets its capacity-binned efficiencies re-applied on the new
  sizes before its energy run), up to `max_capacity_iterations:` (default 3).
  Every bump is an audited decision; the history lands in
  `report['capacity_iterations']` with per-run evidence directories. A bump
  that yields no unmet-hours improvement (hard-sized equipment does not respond
  to sizing factors) stalls the loop with a loud warning instead of burning
  iterations; still-failing after the cap = non-compliant + warning.

This is the ONE place simulation execution lives (pure SDK + `openstudio` CLI,
no measures, no openstudio-standards). The domain gems never simulate. One clone
carries all the reference transforms; ONE AuditLog spans system selection,
efficiencies, envelope decisions, article coverage, the 8.4.1.2 verdicts, and
(optionally) HVAC + envelope costing of both models.

## Quick start (runnable)

This block runs as-is from the repo root — it uses the family's shared test
fixture and the bare-geometry on-ramp:

```ruby
require_relative 'openstudio-necb/lib/openstudio_necb'

fixtures = 'openstudio-hvac/test/fixtures'
weather  = "#{fixtures}/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020"
model    = OpenStudio::Model::Model.load(
             OpenStudio::Path.new("#{fixtures}/5ZoneNoHVAC.osm")).get
space_map = model.getSpaces.to_h do |s|
  [s.nameString, ['Space Function', 'Office enclosed > 25 m2']]
end

result = OpenStudioNECB.performance_compliance(
  model, vintage: '2020',
  weather: { epw: "#{weather}.epw", ddy: "#{weather}.ddy" },
  building: { storeys: 1 },
  necb_loads: { space_type_map: space_map, shw_fuel: 'NaturalGas',
                hvac_system: 'Baseboard gas boiler' },
  simulate: :annual, report_html: true,
  run_dir: 'runs/quick_start')

puts result.compliant       # true / false (nil unless simulate: :annual)
result.report               # written to run_dir/report.json
result.audit                # ONE audit — run_dir/audit.json + audit.txt
result.reference_model      # the fully-transformed reference building
```

**Before your first run on your own model**, know the two hard gates:

1. **Space types must carry NECB tags.** Every space type with floor area must
   resolve against the NECB catalog (`'BuildingType'`+`'SpaceType'` standards
   tags, or names the catalog recognizes). Unmatched types would silently keep
   the proposed's lighting/loads in the reference — comparing the building
   against itself — so the pipeline refuses instead, with did-you-mean
   suggestions. Untagged bare geometry: use the `necb_loads:` on-ramp as above.
2. **The storey count must be knowable.** Reference-system selection (Table
   8.4.4.7.-A) depends on storeys; pass `building: { storeys: N }` or model
   `BuildingStory` objects. An unknowable storey count raises rather than
   silently assuming 1.

Older `.osm` files are version-translated in memory on load (the file on disk
is never modified; the translation is recorded in the audit).

## What the pipeline does

The step numbers below match the `# N.` markers in
`lib/openstudio_necb/compliance.rb` — this list is the canonical one.

1. Load + validate the input model — on-ramp for bare geometry
   (`necb_loads:`), simulate-ability gates, the NECB space-type pre-flight.
2. Attach weather (EPW + DDY design days); resolve heating degree-days
   (explicit `hdd:` → Table C-1 from the EPW site → `.stat`).
3. **Sizing run of the proposed** (selection kW thresholds, capacity-binned
   efficiencies, and costing need capacities; the domain gems never simulate).
4. **Annual run of the proposed — before the reference is built.** The
   proposed annual depends on nothing downstream, and when the proposed
   carries a heat pump its annual heating-energy split feeds the
   8.4.4.13.(2)(g) auxiliary-fuel election in the reference build (D-52).
5. **Reference build** on ONE clone, same audit:
   `OpenStudioHVAC::NECB.reference_hvac` →
   `OpenStudioEnvelope::NECB.reference_envelope` →
   `OpenStudioLighting::NECB.reference_lighting` (Part 4 allowance LPDs,
   dwelling units to 5 W/m²) + `reference_daylighting` (photocontrols, ON by
   default per D-51) → `OpenStudioSHW::NECB.reference_shw` (Part 6 minimum
   efficiencies). Schedules and occupancy/receptacle loads stay
   identical-by-clone per 8.4.3.2; lighting power and SHW efficiency do NOT.
6. Sizing run of the reference, then **efficiencies re-applied** on the sized
   capacities, plus the post-sizing determinations (5.2.10.1 energy recovery
   on sized flows, 5.2.2.7 economizer thresholds).
7. **Annual run of the reference**, the 8.4.1.2 sentences (2)–(4) verdicts,
   and the sentence-(5) capacity iteration loop (bumps → re-size → re-run
   until loads are met, the cap, or a stall).
8. NECB 2025 + `province_state:` — the Part 11 operational-GHG level.
9. `costing: true` — HVAC + envelope costing of BOTH models into the same
   audit, with the incremental proposed-vs-reference cost in the report.
10. `eui_supplement:` (2025) — the 8.4.4 archetype-EUI verdict computed
    alongside the reference-path verdict (see below).
11. Article coverage emitted; `report.json`, `audit.json`, `audit.txt` (and
    `compliance_report.html` with `report_html: true`) written to `run_dir`.

A shortened `run_period:` computes the same arithmetic but is flagged in the
report and audit as NOT a code-compliant determination.

Every audit entry is stamped with **which model it is about** (`building:`
`'input model'` | `'proposed building'` | `'reference building'`; absent =
cross-building comparison/verdict) — so a warning is always traceable to the
model it belongs to in `audit.txt`, `audit.json`, and the HTML report's
"Applies to" chips.

## Modes

| `simulate:` | What runs | `compliant` |
|---|---|---|
| `:annual` | sizing + annual for both models | true/false |
| `:sizing` | sizing only (models generated, sized, costable) | nil |
| `:none` | model transforms only — proposed stays UNSIZED (loud warning: kW thresholds and capacity bins fall back) | nil |

## The two compliance paths

**`path: :reference`** (default, 2020 + 2025) — everything described above:
build a reference building, compare annual energy.

**`path: :eui`** (NECB 2025 only) — the 8.4.4 archetype-EUI path. No
reference building is generated or simulated; the building energy target is
`BET = Σ(Aᵢ × EUIᵢ) + PL` from Table 8.4.4.1.:

```ruby
result = OpenStudioNECB.performance_compliance(
  model, vintage: '2025', path: :eui,
  archetypes: { 'Office' => :all },       # archetype => :all | [space names]
  process_loads_kwh: 0,
  weather: { epw: ..., ddy: ... }, run_dir: 'runs/eui')
```

Floor areas are COMPUTED from the model per 8.4.4.1.(3) (unmapped area
distributes pro-rata per (4)); <90% archetype coverage or HDD ≥ 9000
hard-refuses. The proposed is checked against Table 8.4.4.2 (values + hourly
schedule profiles) and, when non-conformant, NORMALIZED to the table before
its annual run per 8.4.4.2.(1).

**`eui_supplement:`** on a 2025 *reference-path* run computes BOTH verdicts:
`eui_supplement: { archetypes: { 'Office' => :all }, run_normalized: true }`.
The two paths simulate different proposed buildings (as-specified vs
Table-8.4.4.2-normalized), so the shared-run shortcut is only lawful when the
conformance check passes; otherwise `report['eui_path']` reports
`computed: false` with the mismatch list — unless `run_normalized: true`
authorizes the extra normalized run.

## Options reference

All `performance_compliance` keywords (YARD in `compliance.rb` is the
authoritative copy):

| Keyword | Default | What it does |
|---|---|---|
| `vintage:` | `'2020'` | NECB edition: `'2020'` or `'2025'` |
| `weather:` | `{}` | `{ epw:, ddy:, stat: }` — epw+ddy required unless `simulate: :none` |
| `building:` | nil | selection facts: `storeys:`, `zone_types:`, `winter_design_temp_c:` … |
| `hdd:` | nil | heating degree-days override (else Table C-1 → .stat) |
| `run_dir:` | required | working directory for runs, report, audit |
| `simulate:` | `:annual` | `:annual` / `:sizing` / `:none` (see Modes) |
| `run_period:` | nil | shortened run for TESTS — flags the result non-compliant-determination |
| `costing:` | false | cost BOTH models (HVAC + envelope) into the same audit |
| `city:`, `province_state:` | nil | costing location; `province_state:` ALSO gates the 2025 Part 11 GHG determination |
| `costs_csv:` | nil | licensed RS-Means CSV — runtime injection only, never committed |
| `thermal_bridging:` | nil | TBD PSI set for the envelope transforms |
| `actual_roof_absorptance_used:` | false | proposed models real roof absorptance → reference roof set to 0.7 (8.4.4.3.(1)/(2)) |
| `max_capacity_iterations:` | 3 | 8.4.1.2.(5) iteration cap (0 disables) |
| `capacity_step:` | 1.25 | first sizing-factor bump per failing thermal block |
| `necb_loads:` | nil | bare-geometry on-ramp: `space_type_map:` (required), `lights_type:`, `shw_fuel:`, `hvac_system:` |
| `reference_daylighting:` | true | build + evaluate reference photocontrols (D-51); false = loud opt-out |
| `path:` | `:reference` | `:reference` or `:eui` (2025) |
| `archetypes:` | nil | `:eui` path mapping (required there) |
| `process_loads_kwh:` | 0.0 | `:eui` path PL term (8.4.4.1.(2)) |
| `eui_supplement:` | nil | 2025 reference-path runs: also compute the EUI verdict |
| `report_html:` | false | write `run_dir/compliance_report.html` |
| `report_options:` | `{}` | report header: `project_name:`, `address:`, `permit_number:`, `prepared_by:`, `date:`, `professional_of_record:` |
| `audit:` | nil | supply your own AuditLog (one audit across several calls) |

## AHJ compliance report (HTML)

`report_html: true` (or `OpenStudioNECB::Report.write_html(result, path, options)`
on any `ComplianceResult`) renders **one self-contained HTML file** for
building-permit submission — no external resources, no scripts (native
`<details>` only), print-ready. Its structure mirrors the City of Vancouver
*Building Energy Design Statement* (the canonical Canadian AHJ intake form).
Sections, in order: project header + verdict banner (PASS/FAIL per path,
Tier, GHG-level badges) · compliance-path declaration · the article-sorted
**checklist derived from the audit log** (every row links to its full audit
entry; warnings can never be hidden) · Energy (paired end-use bars, totals
with dashed target lines, unmet hours, capacity-iteration history) ·
GHG (2025 Part 11) · EUI path (when computed) · Envelope (area-weighted
U-values, FDWR/SRR) · HVAC (proposed-vs-reference system-layout schematics) ·
Lighting · Loads · SHW · costing totals (when run) · article-coverage
appendix · **decisions-and-assumptions appendix** (every `D-nn` ruling that
fired in the run, with its plain-language summary) · the full collapsed audit
trail · signature blocks.

The report details **every change the pipeline made and why** — each audit
entry becomes a row with the model it applies to, the action taken, the NECB
article that mandates it, and the ruling that governs the reading.

Out of scope (by design): jurisdiction-specific signed PDF forms (this report
is the evidence package attached to them), French localization, and line-item
cost ledgers (totals only — licensed unit costs are never embedded).

## Citation conventions (`article:` and `ruling:`)

Audit entries and code comments carry two citation axes:

- **`article:`** — the NECB clause that mandates a value or step
  (e.g. `8.4.4.7.(4)`).
- **`ruling: 'D-nn'`** — the adjudicated *reading* of that clause where
  interpretation was required. The registry is
  [docs/necb_decisions.md](docs/necb_decisions.md) (human prose) +
  `lib/openstudio_necb/data/decisions.json` (machine-readable; drift-tested).
- `L-nn` = legacy-implementation findings ([docs/legacy_findings.md](docs/legacy_findings.md));
  `T-n` / `A-n` = the archived 2026-07-25 audit registers (see
  [docs/README.md](docs/README.md) for the register guide and the family
  glossary).

## Testing

```bash
cd openstudio-necb
ruby test/test_compliance.rb   # pipeline modes, capacity iteration, pre-flight,
                               # input validation gates. E+ runs skip without the CLI.
ruby test/test_archetypes.rb   # 8.4.4 mapping / conformance check / normalization
ruby test/test_tiers_eui.rb    # Section 10 tiers, 2025 8.4.4 EUI path, Part 11 GHG
ruby test/test_report_units.rb       # SDK-free renderer units + golden SVG
ruby test/test_report_model_query.rb # SDK extraction (chains, envelope, glazing)
ruby test/test_report_html.rb        # whole-document renders from real pipelines
ruby test/test_decisions_registry.rb # D-nn registry drift + audit-log copy sync
```

Test fixtures are shared with the sibling gems (no third copy of the weather trio).

## Licensing note

Costing follows the domain gems' policy: vendored data is placeholder/unpriced;
real licensed RS-Means values are **runtime-injected** via `costs_csv:` and must
never be committed or redistributed.
