# CLAUDE.md — openstudio-necb (the umbrella)

Composes the six SDK-only domain gems (hvac, envelope, loads, lighting, shw,
geometry) into the full NECB Part 8 determination. **This is the ONLY gem
allowed to run EnergyPlus** (pure SDK + `openstudio` CLI — no measures, no
openstudio-standards). One clone carries both reference transforms; ONE
AuditLog spans everything.

## Pipeline (`Compliance.performance_compliance`)

clone → on-ramp → **space-type pre-flight** (`validate_space_types!`: every
floor-area space type must resolve against the NECB catalog; hard
`ArgumentError` with did-you-mean suggestions — BREAKING for untagged models
BY DESIGN, since unmatched types silently keep the proposed's lighting/loads
in the reference clone; the raise lands inside the diagnostics begin so the
audit still flushes) → weather attach → HDD (explicit → Table C-1 → .stat) →
proposed sizing
→ reference_hvac + reference_envelope + reference_lighting (Part 4 allowance
LPDs, always) + reference_shw (Part 6 minimum efficiencies, always) +
optional reference_daylighting on ONE clone/audit → reference sizing →
efficiencies RE-applied on sized capacities → annual runs → 8.4.1.2.(2)–(4)
verdicts → sentence-(5) capacity auto-iteration (sizing-factor bumps, stall
detection) → Section 10 tier → 2025 Part 11 GHG → optional costing of both
models → report.json / audit.json / audit.txt → optional compliance_report.html.

All reference transforms run inside `audit.with_building('reference building')`
so their entries and coverage are stamped and reconcilable. Only schedules and
occupancy/receptacle loads stay identical-by-clone (8.4.3.2); lighting power
and SHW efficiencies ARE regenerated to code on the reference.

- Modes `simulate: :annual | :sizing | :none` (only `:annual` determines).
- `path: :eui` (2025 only) — the 8.4.4 archetype-EUI path via
  `archetypes.rb`: `archetypes: {'Office' => :all | [space names]}` (a SPACE
  mapping — `archetype_areas` is gone); areas COMPUTED from the model per
  8.4.4.1.(3), unmapped area pro-rata per (4); <90% coverage or HDD ≥ 9000
  HARD-REFUSE. The proposed is CHECKED against Table 8.4.4.2 (values +
  hourly schedule profiles) and, when non-conformant, NORMALIZED to it before
  the annual run (8.4.4.2.(1)) — normalization REPLACES the run, no extra
  cost. NO reference building.
- `eui_supplement: {archetypes:, run_normalized:}` on a 2025 REFERENCE-path
  run: the two paths simulate DIFFERENT proposeds (as-specified vs
  Table-8.4.4.2-normalized), so the shared-run shortcut is only lawful when
  the conformance check passes; otherwise `report['eui_path']` is
  `computed: false` with the mismatch list (default — never silently double
  E+ cost) unless `run_normalized: true` runs the normalized clone into
  `proposed_eui_annual/`. The report renders NOT COMPUTED as its own state.
- `necb_loads:` — bare-geometry on-ramp (loads → lighting → optional shw →
  optional hvac) before the pipeline.
- Returns `ComplianceResult` Struct
  `(proposed_model, reference_model, report, audit, compliant, run_dir)`.

## Audit building-stamp (load-bearing)

The pipeline sets `audit.building=` / `audit.with_building` at EVERY phase
boundary: `'input model'` (load + on-ramp), `'proposed building'`,
`'reference building'`, nil for cross-building verdicts. Keep new phases
stamped — the HTML report's "Applies to" chips and issue-traceability depend
on it. Audit text convention: violations SHOUTED, passes lowercase — the
checklist classifier in `report/checklist.rb` parses this CASE-SENSITIVELY.

## Modules

- `compliance.rb` — the pipeline + eui path + capacity iteration + costing.
- `Runner` is an ALIAS of `OpenStudioSimulation::Runner` (the runner was
  extracted to the openstudio-simulation gem): weather attach,
  `run_energyplus!`, `energy_results` (End Uses via TabularData GJ rows —
  SqlFile has NO fuel-agnostic end-use methods), unmet hours, `clean_run?`.
  District accessors renamed across SDK versions — `respond_to?` probe.
- `archetypes.rb` — the 8.4.4 machinery: mapping/areas/applicability +
  Table 8.4.4.2 conformance check + normalization (built THROUGH
  openstudio-loads' record machinery with synthetic archetype records).
- `data/necb/necb_rules_{2020,2025}.json` — the umbrella's own
  `article_coverage` manifests (8.4.1.2 determination, 8.4.2.x methods,
  8.4.4.x EUI). Declaration-only: the umbrella has NO runtime
  emit_article_coverage yet, so its partial/not_implemented do NOT warn on
  runs (unlike domain gems).
- `tiers.rb` + `data/eui_targets_2025.json` / `ghg_factors_2025.json` —
  Section 10 tiers (≤100/75/50/<40% → 1–4, identical 2020/2025), 8.4.4 BET
  arithmetic, Part 11 GHG levels A–F (provincial factors: ON elec 57.9 g/kWh,
  gas 185).
- `report.rb` + `report/` — the AHJ HTML report.
  **`report/model_query.rb` is the ONLY SDK-touching renderer file** (plain
  hashes out, never raises); html/svg/charts/checklist/diagrams/sections are
  SDK-free. Single self-contained file: inline SVG/CSS, no scripts (native
  `<details>` only), no external references — tests enforce this. Goldens in
  `test/goldens/` (`UPDATE_GOLDEN=1` to regenerate).

## Key facts / traps

- Sentence (4) unmet cooling is VACUOUS when the proposed has no mechanical
  cooling (passive overheating ≠ capacity shortfall) — audited determination.
- Capacity iteration bumps global SizingParameters; hard-sized equipment does
  not respond → stall detection stops the loop with a loud warning.
- A shortened `run_period:` computes the same arithmetic but flags NOT
  code-compliant (`report['annual'] = false` + warning + report strip).
- `AuditLog` here is an alias of `OpenStudioHVAC::AuditLog`.
- **Cloning a SpaceType for load overrides? Clone its DefaultScheduleSet
  too** — a fresh set severs Lights schedule inheritance and EnergyPlus
  FATALS on schedule-less Lights (found by the E+ battery, invisible to
  SDK-only tests).
- Schedule-PROFILE comparison across models must clone the candidate into the
  target's model first: differing assumed years shift day-of-week rules
  (weekday profiles get compared against weekends).
- SpaceType density getters may return OptionalDouble — unwrap (see
  `ModelQuery.unwrap`).
- Licensing: `costs_csv:` runtime injection only; the report embeds cost
  TOTALS only, never line-item licensed prices. NEVER stage `.mcp.json`.

## Tests

```bash
cd openstudio-necb
ruby test/test_compliance.rb          # pipeline modes + capacity iteration + pre-flight
ruby test/test_archetypes.rb          # 8.4.4 mapping/check/normalize (round-trip pinned)
ruby test/test_tiers_eui.rb           # tiers, 8.4.4 EUI path, GHG
ruby test/test_report_units.rb        # SDK-free renderer units + goldens
ruby test/test_report_model_query.rb  # SDK extraction
ruby test/test_report_html.rb         # whole-document renders + 2025 E2E
```

E+ tests skip without the CLI; annual tests use week runs (~1 min each).
Fixtures shared from `../openstudio-hvac/test/fixtures`.
