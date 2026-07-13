# CLAUDE.md — openstudio-necb (the umbrella)

Composes the six SDK-only domain gems (hvac, envelope, loads, lighting, shw,
geometry) into the full NECB Part 8 determination. **This is the ONLY gem
allowed to run EnergyPlus** (pure SDK + `openstudio` CLI — no measures, no
openstudio-standards). One clone carries both reference transforms; ONE
AuditLog spans everything.

## Pipeline (`Compliance.performance_compliance`)

clone → weather attach → HDD (explicit → Table C-1 → .stat) → proposed sizing
→ reference_hvac + reference_envelope (+ optional reference_daylighting) on
ONE clone/audit → reference sizing → efficiencies RE-applied on sized
capacities → annual runs → 8.4.1.2.(2)–(4) verdicts → sentence-(5) capacity
auto-iteration (sizing-factor bumps, stall detection) → Section 10 tier →
2025 Part 11 GHG → optional costing of both models → report.json / audit.json
/ audit.txt → optional compliance_report.html.

- Modes `simulate: :annual | :sizing | :none` (only `:annual` determines).
- `path: :eui` (2025 only) — the 8.4.4 archetype-EUI path: BET =
  Σ(Aᵢ×EUIᵢ)+PL from Table 8.4.4.1; NO reference building. Guards: ≥90%
  archetype floor coverage, HDD < 9000.
- `eui_supplement: {archetype_areas:}` on a 2025 REFERENCE-path run also
  computes the 8.4.4 verdict against the same annual kWh →
  `report['eui_path']` (one run, both paths).
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
- `runner.rb` — weather attach, `run_energyplus!`, `energy_results` (End Uses
  via TabularData GJ rows — SqlFile has NO fuel-agnostic end-use methods),
  unmet hours, `clean_run?`. District accessors renamed across SDK versions —
  `respond_to?` probe.
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
- SpaceType density getters may return OptionalDouble — unwrap (see
  `ModelQuery.unwrap`).
- Licensing: `costs_csv:` runtime injection only; the report embeds cost
  TOTALS only, never line-item licensed prices. NEVER stage `.mcp.json`.

## Tests

```bash
cd openstudio-necb
ruby test/test_compliance.rb          # pipeline modes + capacity iteration
ruby test/test_tiers_eui.rb           # tiers, 8.4.4 EUI path, GHG
ruby test/test_report_units.rb        # SDK-free renderer units + goldens
ruby test/test_report_model_query.rb  # SDK extraction
ruby test/test_report_html.rb         # whole-document renders + 2025 E2E
```

E+ tests skip without the CLI; annual tests use week runs (~1 min each).
Fixtures shared from `../openstudio-hvac/test/fixtures`.
