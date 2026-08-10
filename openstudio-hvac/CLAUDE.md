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
  `{step, target, action, inputs, value, article, ruling, evidence, building, level}`,
  levels `:decision | :info | :warning`. **Warnings are never silent** —
  anything skipped/unknown lands in the log. `audit.building=` /
  `audit.with_building(name) {}` stamps entries with WHICH model they concern
  (`'input model'` / `'proposed building'` / `'reference building'`; nil =
  cross-building verdict). The class itself lives in **openstudio-audit**
  (`OpenStudioAudit::AuditLog`); every gem's `audit_log.rb` is a three-line
  ALIAS of it (`AuditLog = OpenStudioAudit::AuditLog`) — change the schema
  THERE, never re-copy it here. `test_decisions_registry.rb` in the umbrella
  fails if a gem stops resolving to the shared class. Do NOT touch the 9-line
  `necb/audit_log.rb` alias files.
- **`ruling:` — the second citation axis (D-44).** `article:` cites the CODE
  that mandates a value; `ruling:` cites the adjudicated DECISION that says how
  we read it (`openstudio-necb/docs/necb_decisions.md`). Rules:
  - TOP-LEVEL kwarg, **never** inside `inputs:` (the report's input renderers
    would swallow it).
  - Single-quoted literal on **ONE line** — a static test greps for exactly
    that shape. Several ids = one space-separated string: `ruling: 'D-19 D-21'`
    (mirrors the joined-`article:` convention); parse with
    `OpenStudioNECB::Decisions.ids_in`.
  - Every id cited must exist in
    `openstudio-necb/lib/openstudio_necb/data/decisions.json`, and every entry
    there with `kind: "runtime"` must be cited by ≥1 tag — the drift test is
    hard in both directions. Adding a decision means adding it to BOTH the doc
    and the registry.
  - Do **not** tag `step: :coverage` entries — manifest boilerplate would swamp
    the report appendix's fire counts.
  - Purely additive: tagging never changes an action string, article, input or
    any determination behaviour.
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
- **The legacy-parity ORACLE is pinned:** `legacy_pin/REF` names the exact
  openstudio-standards fork revision the parity gates compare against; bump
  it deliberately (see `legacy_pin/README.md`).

## Architecture

- `catalog.rb` / `systems.json` — 65 canonical system names, 11 families
  (NECB sys1–6, ECM hs08–16, CBECS). Names are exact strings, e.g.
  `'PSZ RTU with exhaust Gas and DX Coils and Hot Water Baseboard'` — grep
  `systems.json` before assuming a name.
- `builder.rb` + `systems/*.rb` — topology builders (one file per family;
  `base_system.rb` is the shared scaffold). Output is topology-only; the NECB
  efficiency pass sets performance values.
- `necb/reference.rb` — Table 8.4.4.7.-A system selection + reference build +
  8.4.4.12 economizers (DifferentialEnthalpy on sys1/3/4/6+HP; sys2/5 get the
  5.2.2.9 WATER-side economizer since D-56 — `HeatExchangerFluidToFluid`
  condenser->CHW, `CoolingSetpointModulated`, UA + both flows autosized at
  sizing factor 1.0. **The tower setpoint reset is not optional**:
  `plant_loops.rb` pins the condenser loop at a constant 29 degC, so any
  exchanger added there is INERT until the setpoint follows the outdoor wet-bulb
  plus the tower's own `designApproachTemperature`). The 5.2.10.1 ERV trigger is the NECB 2020
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
- **Staged coils (8.4.4.9.(7)/8.4.4.10.(8), D-46..D-50)** — reference systems
  3/4 and the Table -13 ASHP build their fan + coils inside an
  `AirLoopHVACUnitarySystem` (multispeed coils CANNOT sit bare on an air loop;
  `addToNode` returns false). Load-bearing names: `CoilCoolingDXMultiSpeed_dx`
  / `_ashp`, `CoilHeatingGasMultiStage_gas`, `CoilHeatingDXMultiSpeed_ashp`.
  - **Flag:** `config['staged_coils']`, set ONLY by the reference ruleset's
    `system_definitions` — catalog/proposed/CBECS builds stay bare.
  - **NEVER hard-set a stage capacity.** `Efficiency.apply_staging` adjusts the
    stage COUNT post-sizing (`kW <= 66 ? 2 : ceil(kW/66)`) and re-autosizes;
    the equal increments come from `Coils.set_stage_flow_ratios` writing k/N
    into the `UnitarySystemPerformanceMultispeed`. Hard-sizing kills D-43
    capacity iteration (the L-23 lesson).
  - **4-stage clamp (D-47):** the SDK refuses a fifth stage; clamps emit a
    SHOUTED warning.
  - **`Coils.supply_components(air_loop)`** is the contract: it expands unitary
    containers into their fan/coils. Every consumer that scans a supply path
    for coils or fans MUST go through it (reference fan rules, economizers,
    classify, costing, checker, diagrams; the umbrella's `model_query.rb` and
    `necb_fixed_point_diff.rb` inline their own copies).
  - The reference ASHP's supplemental coil sits on the LOOP downstream of the
    unitary, not in the unitary's supplemental slot — E+ sizes a unitary's
    supplemental heater to the heat-pump capacity, which starved back-up heat
    below the -10 degC cutoff (84 unmet hours -> 1.75 after the move).
  - Efficiencies bin by TOP-stage (= total) capacity, one row applied to every
    stage. The unitary sizes its heating coil ~2.2x the bare air-loop coil
    (full-flow mixed-air-to-43 degC vs the heating-day ideal-loads peak) —
    measured in D-46.
  - **Staged airflow is NOT optional, and is not a "constant-volume"
    violation.** The E+ IDD requires each speed's rated air flow to be
    0.00004027-0.00006041 m3/s per watt OF THAT SPEED's capacity, so flow must
    track staged capacity; constant flow at staged capacity is unmodelable.
    Legacy does the same. Table 8.4.4.7.-B's "Constant-volume" describes the
    DISTRIBUTION (no VAV terminals). This was called a defect once and
    retracted — check the IDD before re-litigating. What IS required: floor the
    ratios at the minimum-OA fraction (`set_stage_flow_ratios(min_ratio:)`), or
    a low stage delivers less air than the ventilation requirement.
  - **A container re-homes every schedule that used to reach the equipment.**
    The loop's availability does NOT govern a fan INSIDE a unitary: the unitary
    has its own availability, and its fan-operating-mode schedule picks
    continuous (1) vs cycling (0). The AVAILABILITY must follow the loop
    schedule — set at build time AND re-pointed by the D-14 pass
    (`apply_unitary_operating_schedule`); the fan MODE stays continuous, since
    E+ rejects a mode schedule containing zeros. The first cut left it at the
    always-on default and every staged reference fan ran 8760 h: Warehouse fan
    energy 2.68x the proposed's (0.98x before staging; 0.88x after the fix),
    which moved every PSZ archetype 7-9 points MORE LENIENT. Every unit test
    passed; only the fleet sweep caught it (D-46 amendment) — which is why the
    sweep is a merge gate.
- **Reference fan energy is DISCONTINUOUS at 25 kW** (8.4.4.17.(3)-(5),
  `apply_fan_power_curve`). Selection is by `pressureRise x flow / efficiency`:
  `>= 25 kW` -> 'forward curved with inlet vanes' (min flow 0.25, coefficients
  0.3396/-0.8481/1.4957); `> 7.5 && < 25 kW` -> 'airfoil with inlet vanes'
  (min flow 0.35, 0.5843/-0.5792/0.9702). At a 0.285 flow fraction those are
  0.219 vs 0.498 of rated power — **2.27x across the boundary**. MEASURED: a
  4.6% cut in design airflow (daylighting reducing gains) moved a MediumOffice
  supply fan 25.6 -> 24.4 kW and raised fan energy 49%, with run hours,
  airflow and fan spec all unchanged. Any change that nudges a reference fan
  across 25 kW produces a step that LOOKS like a regression and is not — check
  the band before investigating anything else.
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
- `furnace_staging`/`dx_staging` graduated to CONSUMED rule blocks in D-46 (as
  `hydronic_pumps` did in D-11) — `non_rule_keys` is now empty in both vintages
  and the orphan lint enforces their consumption.
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
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/legacy_pin/Gemfile bundle exec ruby ...`,
the PINNED legacy oracle (see legacy_pin/README.md); `LEGACY_PIN_REQUIRED=1`
turns a missing oracle into a failure.

## A-list rulings (D-34..D-40, 2026-07-28) — behavior pins

- **Residential + heat pump** (D-34): the 8.4.4.7.(4) ASHP redirect wins over
  the Table -A "(or heat pumps)" copy parenthetical — redirect BEFORE the
  compatible-cooling check.
- **WLHP vs WSHP** (D-37, Note A-8.4.4.13): `Classify` records per-group
  `heat_pump_sources` (:air | :water_loop | :external) by inspecting
  water-to-air HPs' SOURCE plant loop (ground HX/district/temp-source =>
  external). `heat_pump_redirects?` gates the redirect: all-water-loop stays
  on Table -A; empty sources = conservative redirect. The catalog 'Water
  source heat pumps' system is a water-LOOP system by the note (internal
  boiler + fluid cooler) — do NOT use it to test the ASHP redirect; use PTHP.
- **Facts over family names** (D-58): `residential_compatible_cooling?` reads
  `zonal_units` (ptac/pthp/fan_coil/vrf_terminal/wshp) and `loop_dx_cooling` —
  NEVER go back to family-string matching; legacy pipe names put family
  STRINGS into `:family_guess` and the old symbol test silently sent the
  fleet hotels' MAU+PTAC guest blocks to through-the-wall instead of the
  Table -A identical-copy. Plant HPs (HeatPumpPlantLoopEIR / WaterToWater on
  a loop serving hydronic coils) mark their groups via
  `record_plant_heat_pump` — 8.4.4.13.(2) reaches "conditioned water to a
  hydronic loop", not just coil-level units — and their SOURCE loops are
  excluded from purchased-energy detection (the legacy GLHX district-object
  ground proxy is not purchased heating). The whole proposed→reference matrix
  is pinned by `test_reference_selection_matrix.rb` against the adjudicated
  golden (FULL_MATRIX=1 for all 97; regen requires re-adjudication, D-58).
- **HP aux-fuel election** (D-52, 8.4.4.13.(2)(g)): when the umbrella hands
  `reference_hvac` a `proposed_annual:` hash (per-loop/per-zone delivered
  heating energy joined from `Classify.heating_election_inventory` + the
  proposed annual SQL), `heat_pump_aux_energy_type` elects the hp variant's
  fuel — largest terminal/aux energy type over the (g)(i)/(g)(ii) scope,
  gated by the 33% proviso; every fallback path (no data / no aux / gate
  fails) drops to the structural 8.4.4.9.(4) proxy AUDITED. (2)(b) is a
  measured no-op: the builders' per-zone cooling factor 1.0 OVERRIDES the
  capped global (A/B 1.0000). `Coils.supply_components` now also unwraps the
  legacy `AirLoopHVACUnitaryHeatPumpAirToAir(MultiSpeed)` wrappers — before
  D-52 those loops read coil-less and their HPs were invisible.
- **5.2.6.3 pump caps** (D-38): after the 8.4.4.14 transfer, each loop's
  COMBINED pump power is clamped min-wins at Table 5.2.6.3 W/kW of peak
  thermal demand (`apply_pump_power_cap`; caps vendored under
  `hydronic_pumps.power_caps_w_per_kw`). Clamp reuses the head-reconciliation
  guard — never hard-set pump power without keeping flow/head/power physical.
- **System 5 heating** (D-39): FanCoils config `'heating' => 'none'` builds
  cooling-only TPFC (no HW loop; zero-capacity always-off placeholder coil —
  FourPipeFanCoil requires one). finalize merges it when the sys-5 group is
  unheated; heated groups keep the changeover per 8.4.4.1.(5).
- **Reheat sizing** (D-40): reference VAV reheat coils stay AUTOSIZED — the
  legacy 1.2x1000xmin-flow hard-size is rejected (load-blind, incompatible
  with our 0.5 reheat-flow cap, and hard-sized coils break capacity
  auto-iteration). Don't "fix" sys-6 parity by importing it.
