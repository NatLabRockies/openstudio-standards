# CLAUDE.md — openstudio-hvac

Standalone, SDK-only HVAC gem: system topology builds, NECB reference-system
generation, capacity-binned efficiencies, and HVAC costing. The founding gem of
the seven-gem family (hvac, envelope, loads, lighting, shw, geometry, necb) —
its `AuditLog` is the canonical copy the umbrella aliases.

## Family contract (applies to every gem in the family)

- **Pure OpenStudio SDK.** No openstudio-standards, no measures, no BTAP.
- **Never simulates.** Only the umbrella (openstudio-necb) runs EnergyPlus.
  Anything capacity-binned must work on already-sized models or skip loudly.
- **One AuditLog schema** across all gems:
  `{step, target, action, inputs, value, article, evidence, building, level}`,
  levels `:decision | :info | :warning`. **Warnings are never silent** —
  anything skipped/unknown lands in the log. `audit.building=` /
  `audit.with_building(name) {}` stamps entries with WHICH model they concern
  (`'input model'` / `'proposed building'` / `'reference building'`; nil =
  cross-building verdict). The six sibling `audit_log.rb` files are **verbatim
  copies** — change hvac's, then regenerate the others with a sed module-name
  swap (see git history of the `building:` stamp commit).
- **Audit text convention:** violations are SHOUTED (`EXCEEDS`, `does NOT
  meet`, `BELOW the`), passes are lowercase (`does not exceed`, `within`).
  The report checklist classifier is deliberately case-SENSITIVE about this —
  breaking the convention misclassifies verdicts in the HTML report.
- **Article-coverage manifests:** each vintage ruleset JSON carries an
  `article_coverage` block (implemented / partial / not_implemented /
  satisfied_by_clone / host_scope); partial + not_implemented warn on every
  run. `host_scope` = the article is real NECB but owned by the umbrella or a
  sibling gem — the `how` string names the delegate (e.g. "Delegated to
  openstudio-shw"). `openstudio-necb/docs/NECB_GEM_COVERAGE.md` is the rollup —
  regenerate with `rake necb:coverage_doc` (it also emits a
  Cross-gem delegations table reconciling each host_scope article against the
  sibling entry that covers it). The report reconciles the same way at render
  time: a host_scope article with no covering entry in the run becomes a ▲
  checklist warning.
- **Licensing (hard rule):** licensed RS-Means values are runtime-injected via
  `costs_csv:` and NEVER committed. This gem's `data/costing/costs.csv` +
  `costs_local_factors.csv` are the pre-existing public vendored copies that
  other gems' costing resolves to as a fallback (explicit args →
  `OPENSTUDIO_COSTING_DIR` → these). Other gems vendor only UNPRICED sheets.
- **Vintages:** 2020 + 2025 only. 2011–2017 backfills are user-deferred.

## Architecture

- `catalog.rb` / `systems.json` — 65 canonical system names, 11 families
  (NECB sys1–6, ECM hs08–16, CBECS). Names are exact strings, e.g.
  `'PSZ RTU with exhaust Gas and DX Coils and Hot Water Baseboard'` — grep
  `systems.json` before assuming a name.
- `builder.rb` + `systems/*.rb` — topology builders (one file per family;
  `base_system.rb` is the shared scaffold). Output is topology-only; the NECB
  efficiency pass sets performance values.
- `necb/reference.rb` — Table 8.4.4.7.-A system selection + reference build +
  8.4.4.12 economizers (DifferentialEnthalpy on sys1/3/4/6+HP; sys2/5 water
  economizer = warning only). The 5.2.10.1 ERV trigger is the NECB 2020
  Table 5.2.10.1.-A/-B airflow thresholds (HDD row x %OA band x
  continuous/non-continuous, >=8000 h/yr from the loop availability
  schedule) — `NECB.apply_energy_recovery(model, vintage:, hdd:)`, a
  POST-SIZING pass the umbrella calls after the reference sizing run
  (it needs sized supply/OA flows; unsized -> loud warn). NOT the 2011
  150 kW exhaust-heat formula (wrong vintage, permissive for small
  high-%OA systems).
- `necb/efficiency.rb` — capacity-binned minimums (`efficiencies_*.json`) +
  plant staging thresholds (176/352 kW boilers, 2100 kW chillers, 0.25
  modulating minimum) read from `reference_rules_*.json`
  `heating_plant`/`cooling_plant` (NOT hardcoded — wired by the orphan-key
  lint; behaviour fingerprinted bit-identical) +
  Table 8.4.4.17 fan power curves applied POST-SIZING (rows by rated kW;
  c1–c3 = columns A/B/C, min-flow-fraction = D; the VSD row exists but the
  selection sentences never pick it) +
  Table 8.4.4.14 hydronic pump rules (D-11): every PumpVariableSpeed gets
  the riding-curve row (sentence (5)) + below-D min-flow clamp, and — when
  the SIZED proposed is passed via `apply_efficiencies(..., proposed:)` —
  reference pump rated power is set from the proposed loop-type's combined
  peak W/(L/s) intensity × reference flow ((1)-(3); (2) combines by summing
  power AND flow; sentence (6) is an acknowledged gap). Undeterminable
  proposed pumps or unsized flows warn loudly.
- `necb/checker.rb` — `check_part5`: warnings-only QAQC (economizers 5.2.2.8,
  5.2.10.1 table trigger (needs `hdd:` + sized flows), 5.2.12 minimums via
  clone-and-diff against the efficiency pass).
  Capacity-binned checks need SIZED equipment — hard-size in tests.
- `costing/*` — quantity takeoff → ledger → report. Costing values come from
  the CSV database at runtime.
- `characterize` / `classify.rb` / `canonical.rb` — reverse-mapping an existing
  model's HVAC to catalog vocabulary.

## Facade

`OpenStudioHVAC.systems / build_system / remove_hvac_from_zones / cost /
characterize / replace_system`; `OpenStudioHVAC::NECB.reference_hvac /
apply_efficiencies / check_part5 / rules`.

## Traps

- **8.4.6 part-load curves are PROBE-VERIFIED** (`rake necb:curves`,
  `openstudio-necb/scripts/necb_8_4_6_curve_probe.rb`): as-applied model curves vs code
  coefficients under documented transforms (FHeatPLC = PLR/eff, °F→°C
  surfaces), compared FUNCTIONALLY over sampled envelopes — never
  coefficient-wise (vendored JSON rounding reads as fake deviation). Every
  code polynomial self-checks ≈1.0 at its rating point first.
- DX cooling EIR_FT was regenerated EXACTLY from the code (the 2011-lineage
  surface deviated 1.95%); the PLF cycling curve is a refit of PLR/EIR_FPLR
  clamped to [0.7, 1.0] (~2% = structural floor of cubic-on-rational). NECB
  2020 8.4.5.4 == 2025 8.4.6.4 coefficients, verified identical.
- **Chiller EIR_FT: the PRINTED code is defective** — NECB 2020 Table
  8.4.5.5-C == 2025 8.4.6.5-C carry misplaced-decimal coefficients
  (water-cooled Scroll d, Reciprocating b, air-cooled Screw a); errata filed
  with NRC 2026-07-22. The probe compares vs `CHILLER_EIR_FT_EC_F_ERRATUM`
  (labelled "vs proposed erratum"); the vendored legacy curves match the
  corrected rows on all six coefficients to <4e-6 — do NOT "fix" them toward
  the printed values.
- `furnace_staging`/`dx_staging` in the rules JSONs are
  `non_rule_keys`-exempted FUTURE-implementation data backing declared-partial
  articles — not dead weight, not yet consumed (`hydronic_pumps` graduated to a consumed rule block in D-11).
- Base efficiency setters already apply NECB values to CBECS-built DX/fan/pump
  equipment — there is NO "90.1 fallback gap" (a previously-suspected defect
  that turned out to be a false premise).
- `reference_hvac` clones the proposed; selection needs
  `building: { storeys:, zone_types: {zone name => NECB space type} }`.
- Data-centre kW selection thresholds and capacity bins need a sizing run
  first; unsized equipment falls back with warnings, never silently.
- District heating objects: SDK renamed classes at 3.7 (DistrictHeating →
  DistrictHeatingWater) — probe with `respond_to?`.

## Tests

`cd openstudio-hvac && ruby test/test_XX.rb`. Fixtures in `test/fixtures/`
(5ZoneNoHVAC.osm + Toronto CWEC2020 epw/ddy/stat) are shared by the whole
family — do not duplicate them. E+-dependent tests skip without the
`openstudio` CLI. Parity tests against legacy openstudio-standards need
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
