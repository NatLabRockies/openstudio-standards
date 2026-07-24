# NECB gem family — decision record

Adjudicated interpretations and product decisions for the `openstudio-*` NECB
gem family. Machine-checkable coverage lives elsewhere — article dispositions in
`openstudio-necb/scripts/necb_8_4_disposition.json`, per-gem `article_coverage` manifests, the
generated `NECB_8_4_COVERAGE.html`, and the evidence rules in
`openstudio-necb/docs/necb_rule_verification.md`. **This file records the judgement calls**: the
code-interpretation and design decisions a reviewer cannot re-derive from the
code alone, who made them, and why. Newest last. Add an entry whenever an
interpretation of code text is adopted, a deviation is accepted, or a
product-shaping call is made.

Format per entry: **what was decided / who / when / why / evidence & commit**.

---

## D-01 — NECB text reproduction (Crown copyright)

- **Decision:** NECB article text may be reproduced in full in generated
  coverage documents committed to the public repository.
- **Who/when:** phylroy, 2026-07-22.
- **Why:** NRCan is the Crown; NECB copyright is the Government of Canada's.
- **Evidence:** `NECB_8_4_COVERAGE.html` renders full clause text; cache in
  `data/necb/necb_8_4_articles_2025.json`. Commit `09c011740`.

## D-02 — Unresolvable space types are a hard error (BREAKING)

- **Decision:** `performance_compliance` pre-flights every floor-area space
  type against the NECB catalog and **raises** (with did-you-mean suggestions)
  instead of silently waiving the affected allowance. Breaking for untagged
  models, deliberately.
- **Who/when:** phylroy (accepted the breaking behaviour), 2026-07-22.
- **Why:** the previous behaviour silently waived the lighting allowance — a
  compliance result that looked complete but wasn't (defect #1 of the
  verification plan).
- **Evidence:** hostile tests in `openstudio-*/test/test_necb_hostile_reference.rb`;
  commit `b03f77e33`.

## D-03 — Chiller EIR_FT: verify against the proposed erratum, not the printed code

- **Decision:** Table 8.4.5.5.-C (2020) / 8.4.6.5.-C (2025) water-cooled Scroll
  and Reciprocating EIR_FT rows are defective **in print** (single misplaced
  decimals; the printed Reciprocating row yields a physically impossible
  negative power ratio at the AHRI rating point). The probe compares against
  erratum-corrected coefficients, labelled "vs proposed erratum" until NRC
  confirms.
- **Who/when:** phylroy (confirmed with the full errata report; "no longer a
  blocker"), 2026-07-22. Errata filed with NRC Codes Canada 2026-07-22.
- **Why:** corrections corroborated exactly (<4e-6, all six coefficients, both
  rows) by the independent legacy NECB-2011-lineage vendored curves.
- **Evidence:** `openstudio-necb/scripts/necb_8_4_6_curve_probe.rb`
  (`CHILLER_EIR_FT_EC_F_ERRATUM`); commit `00da55675`.

## D-04 — EUI path (2025 8.4.4): two-run design with check-then-normalize

- **Decision:** the EUI path and performance path simulate **different**
  proposed models, so Table 8.4.4.2 normalization uses a two-run design: check
  whether the model already carries the Table values; if yes, skip the second
  annual run; the EUI supplement defaults to NOT COMPUTED with mismatches
  listed, and `run_normalized: true` opts into the second run.
- **Who/when:** phylroy (the two-run + schedule-equality shortcut is their
  design), 2026-07-22.
- **Evidence:** `OpenStudioNECB::Archetypes`, round-trip test pinning
  check↔transform; commit `7f7a87047`.

## D-05 — Two 8.4.4.2 interpretations adopted

- **Decision:** (a) *lighting-operation schedules* are normalized (not just
  LPD): the Table 8.4.4.2 operating schedule replaces the model's lighting
  schedules for the EUI run. (b) *outdoor air* is read as ASHRAE 62.1-2016
  rates evaluated at the Table 8.4.4.2 occupant density.
- **Who/when:** phylroy ("do what you think is correct for both … it makes
  sense"), 2026-07-22.
- **Why:** 8.4.4.2 normalizes operating conditions so archetype comparison is
  apples-to-apples; leaving proposed lighting schedules or proposed OA rates in
  place would leak proposed-design behaviour into the normalized run.
- **Evidence:** commit `f42f19533`.

## D-06 — ERV trigger: NECB 2020 Tables 5.2.10.1.-A/-B, post-sizing

- **Decision:** replace the inherited NECB 2011 exhaust-heat-content trigger
  (150 kW formula — wrong vintage, permissive for small high-%OA systems) with
  the 2020/2025 airflow-threshold tables (HDD row × %OA band ×
  continuous ≥8000 h/yr from the loop availability schedule), evaluated
  **post-sizing** via `OpenStudioHVAC::NECB.apply_energy_recovery`. `simulate:
  :none` skips the determination loudly. Manifest honesty first, then the
  implementation ("do both").
- **Who/when:** phylroy, 2026-07-22.
- **Open item:** builders default fan availability to Always On, so most
  systems classify continuous (Table -B is all-"R" at HDD ≥ 3000); wiring
  reference fan schedules to archetype operating-schedule letters would flip
  many to non-continuous. Flagged in the hvac manifest gaps, undecided.
- **Evidence:** hostile tests incl. the 85%-OA divergence case; commit
  `f045739f1`.

## D-07 — 8.4.6.6 cooling tower: engine disposition with numeric cross-check

- **Decision:** the reference tower's part-load capacity behaviour is satisfied
  by EnergyPlus's Merkel effectiveness-NTU model (`CoolingTowerSingleSpeed`,
  which has no curve fields the code's FWB polynomial could be installed into).
  Dispositioned `engine`, backed by a gated numeric cross-check rather than
  argument alone.
- **Who/when:** phylroy ("do the disposition with the numeric cross-check"),
  2026-07-23.
- **Why:** the FWB/FRA polynomial (identical in 2020 8.4.5.6 / 2025 8.4.6.6) is
  the DOE-2.1E curve-fit of the same physics. Cross-check anchored at the CTI
  rating point (78°F wb / 10°F range / 7°F approach): exact agreement at the
  anchor, ≤12.7% across the CTI-wet-bulb slice (gated at 15% as a regression
  tripwire); at cold wet-bulbs the code fit under-predicts capacity relative to
  physics (conservative, up to ~2× at 50°F wb) — where capacity never binds
  because the single-speed fan cycles. Applies to the **performance path only**
  (8.4.6.1 scopes curves to the reference building; the EUI path has none).
- **Evidence:** `openstudio-necb/scripts/necb_8_4_6_curve_probe.rb` (tower section, in
  `rake necb:verify`); `openstudio-necb/scripts/necb_8_4_disposition.json` 8.4.6.6.

## D-08 — Batch sign-off of the remaining 19 article dispositions

- **Decision:** all 19 remaining draft dispositions in
  `openstudio-necb/scripts/necb_8_4_disposition.json` signed off in four groups:
  - **A. Probe-evidenced `covered_by` (7):** 8.4.6.1, 8.4.6.2, 8.4.6.3,
    8.4.6.4, 8.4.6.5, 8.4.6.7, 8.4.6.9 — each rationale carries its numeric
    result from `rake necb:curves`, which re-verifies on every run.
  - **B. Engine physics (4):** 8.4.2.4, 8.4.2.5, 8.4.2.8, 8.4.2.11.
  - **C. Modeller responsibility (4):** 8.4.1.3, 8.4.1.4, 8.4.2.12, 8.4.3.8.
  - **D. Acknowledged gaps (4):** 8.4.2.6 (0.35 W/(m²·K) inter-block
    coefficient), 8.4.3.7 (±1°C default throttling range), 8.4.3.9 (ice
    plants), 8.4.6.8 (absorption chillers N/A; the latent silent-fallback to
    Scroll must be fixed before absorption support is ever claimed).
- **Who/when:** phylroy, 2026-07-23 (group-by-group review).
- **Why:** a disposition is a claim of *responsibility*, not correctness — the
  deliberate weaker claim. Group D remains publicly documented as uncovered;
  implementing any of those articles later is separate, evidence-backed work.
- **Evidence:** `openstudio-necb/scripts/necb_8_4_disposition.json` (no `draft` entries
  remain); rendered without DRAFT pills in `NECB_8_4_COVERAGE.html`.

## D-09 — Umbrella manifest emits at runtime; warnings split from modeller scope notes

- **Decision:** the umbrella (`openstudio-necb`) now emits its own
  `article_coverage` manifest into the audit at the end of every successful
  pipeline run, same contract as the five domain gems — with one new uniform
  semantic across ALL six emitters: a `partial`/`not_implemented` entry flagged
  `"gap_owner": "modeller"` emits as an **info scope note** ("modeller scope")
  instead of a warning, and the AHJ report renders it with the ⓘ glyph, off the
  checklist.
- **Who/when:** phylroy, 2026-07-23 (chose the split over uniform-warn and
  declaration-only).
- **Why:** a warning that no model change can ever clear (e.g. "choice among
  urban climatic datasets is the modeller's") is a check-engine-light-always-on:
  it trains readers to ignore ▲. Real pipeline limitations still warn — the
  umbrella's 8.4.2.2 (elevators/escalators never added to end-use accounting)
  warns on every run; 8.4.2.3 Climatic Data is flagged modeller-scope. The flag
  is inert on implemented-family statuses and only `"modeller"` softens.
- **Evidence:** `Compliance.emit_article_coverage`, the `gap_owner` branches in
  all six emitters, `coverage_status` in `report/sections.rb`; tests in
  `test_compliance.rb` (none-mode assertions) and `test_report_units.rb`
  (`test_coverage_status_modeller_scope_note`).

## D-10 — Remaining adjudications delegated to Claude, with mandatory logging

- **Decision:** phylroy delegated the remaining queue decisions: "make the rest
  of the decisions on your own.. whatever you recommend.. But always report/log
  your decisions so I can review and eventually make course corrections later
  after you have implemented everything." Every subsequent judgement call is
  made per the best evidence-backed recommendation and logged here as a D-XX
  entry, self-contained enough to reverse on review.
- **Who/when:** phylroy, 2026-07-23.

## D-11 — 8.4.4.14 Hydronic Pumps implemented (intensity transfer + Table curves)

- **Decision:** implement, with these interpretive choices:
  - Sentences (1)-(3) through **one mechanism**: the proposed loop-type's
    pumps' combined peak power intensity in W/(L/s) — sentence (3)'s own
    metric, which equals head/efficiency (P = V·head/eff, sentence (1)) and
    absorbs sentence (2)'s multi-pump combination by summing power AND flow.
    Loop-TYPE correspondence (Heating/Cooling/Condenser) — a pump-to-pump
    bijection cannot exist between different topologies.
  - Sentence (2) transfers as **intensity × reference flow, not absolute
    watts** — reference flows legitimately differ from proposed; the intensity
    is what prevents a consolidation free ride. Documented in the manifest gaps.
  - Sentences (4)-(5): every reference `PumpVariableSpeed` gets the Table
    8.4.4.14. **riding-curve** row (sentence (5) directs variable-flow pumps to
    ride the curve; the VSD row is vendored unused). Below-D floor via the
    minimum-flow clamp at D — the same documented approximation as the
    8.4.4.17 fan curves (polynomial at D = 0.691 vs E = 0.68).
  - Sentence (6) (5.2.12.1 pump-energy-inclusive secondary adjustment) is an
    acknowledged gap.
  - The `hydronic_pumps` rules-JSON key graduated from orphan-lint-exempt
    future data to a consumed rule block carrying the Table coefficients.
- **Who/when:** phylroy chose "Implement" (2026-07-23); the interpretive
  sub-choices are Claude's under D-10 delegation.
- **Evidence:** `Efficiency.apply_pump_rules` / `transfer_pump_power` /
  `proposed_pump_stats` in `openstudio-hvac/.../necb/efficiency.rb`; umbrella
  passes `proposed:` post-sizing; `test_necb_pump_rules.rb` (6 runs, incl.
  combined-intensity arithmetic, warn-never-silent, 2025 renumbering).

## D-12 — 8.4.4.16 Space Temperature Control re-manifested modeller-scope

- **Decision:** status `not_implemented` was factually wrong. Re-manifested
  `partial` + `gap_owner: "modeller"`: sentence (2) (throttling identical to
  proposed) is satisfied **by construction** — both buildings use ideal
  thermostat control on cloned schedules, there is no throttling knob to
  differ; sentence (1)'s ±2°C radiant workaround applies only "if the energy
  model calculations do not allow for modeling of radiant effects", which
  EnergyPlus does — it binds only when the modeller approximates a radiant
  design convectively, and applying it is then the modeller's responsibility
  (rendered as an ⓘ scope note per D-09, no longer a permanent warning).
- **Who/when:** phylroy chose "Re-manifest" (2026-07-23).
- **Evidence:** manifest entries in both vintage rules JSONs; pin updated in
  `test_necb_energy_recovery.rb` (asserts info + gap_owner, not warning).

## D-13 — Screw/Centrifugal chiller curves probed; imperfect printed normalization accepted

- **Decision:** the curve probe now compares water-cooled Rotary Screw and
  Centrifugal (all six curves EXACT, 0.00%, vs the printed Table 8.4.6.5.-A/-B/-C
  rows — these EIR_FT rows are NOT erratum-affected). The printed Screw CAP_FT
  (0.962), Centrifugal CAP_FT (0.950) and Screw EIR_FPLR (1.026) do NOT
  normalize to 1.0 at the AHRI 550/590 rating point; accepted as genuine
  properties of the printed fits, not transcription errors, because the
  independent legacy NECB-2011-lineage vendored curves agree with the printed
  rows digit-for-digit. Self-checks use these documented expected values.
  The condensing-boiler 6-term row remains honestly uncompared (bivariate in
  PLR + water temperature; no reference build ever selects the condensing curve).
- **Who/when:** Claude under D-10 delegation, 2026-07-23.
- **Evidence:** `openstudio-necb/scripts/necb_8_4_6_curve_probe.rb` (`CHILLER_CAP_FT_RATING_EXPECTED`,
  `CHILLER_EIR_FT_EC_F_PRINTED`); `rake necb:curves` green with 24 comparisons.

---

*Pending under D-10 delegation: the D-06 fan-availability open item (reference
fan schedules vs Always On — substantial, affects ERV continuous classification
and reference energy; deferred to its own work session).*

## D-14 — Reference air systems inherit the proposed operating schedule (resolves D-06)

- **Decision:** `reference_hvac` captures each zone's proposed air-system
  availability schedule before the strip and applies it to the reference loop
  serving those zones, per 8.4.3.2.(1) (operating schedules identical in both
  buildings). No proposed air system → builder default (Always On) retained
  with an info note; conflicting schedules on one loop → most-zones schedule
  wins with a loud warning. This feeds the 5.2.10.1 continuous/non-continuous
  ERV classification: a proposed on a 12 h schedule now classifies
  non-continuous (Table -A) instead of defaulting continuous. Proposed models
  whose loops are Always On (the common default) are unchanged.
- **Who/when:** Claude under D-10 delegation, 2026-07-23.
- **Evidence:** `Reference.apply_operating_schedules`; `TestNecbOperatingSchedules`
  (inheritance + non-continuous classification + no-air-system note); ERV suite
  and rake necb:verify green.

## D-15 — ERV effectiveness and frost provenance verified against 5.2.10.1 text

- **Decision:** Sentence (4) requires >= 50% ENTHALPY effectiveness (the code
  equation is enthalpy-ratio based, both editions identical). The builder sets
  sensible AND latent effectiveness to 0.50 at every rating point, which gives
  enthalpy effectiveness exactly 0.50 by identity (both components of delta-h
  transfer at 50%) — minimum-compliant for a reference build; VERIFIED on all
  eight HX fields by test. Sentence (6) overshoot control is satisfied by
  supply-air outlet temperature control + the OutdoorAirPretreat setpoint
  manager. The frost values (-23.3 C ExhaustOnly, defrost fractions) are
  EnergyPlus modeling assumptions, NOT code values — 5.2.10.1 is silent on
  frost — now labelled as such in the rules JSONs (modeling_note) so they can
  no longer be mistaken for code transcriptions. Sentences (5) (test-method
  certification) and (3) (specialized-exhaust exemption) are modeller/equipment
  scope.
- **Who/when:** Claude under D-10 delegation, 2026-07-23.
- **Evidence:** NECB 2020/2025 5.2.10.1 text via codes MCP; effectiveness_article/
  overshoot_article/modeling_note in reference_rules_{2020,2025}.json; the
  extended high-OA test (all 8 fields + (4)/(6) citations); audit decision now
  cites 5.2.10.1.(4)/(6).

## D-16 — Archetype breadth sweep; orphaned proposed EMS purged from the reference

- **Decision:** `openstudio-necb/scripts/necb_archetype_sweep.rb` cross-validates the pipeline
  on real whole buildings (legacy NECB2020 archetypes -> full pipeline, sizing
  mode). First run: FullServiceRestaurant and HighriseApartment (90 zones,
  11 ERVs) PASSED; Warehouse/PrimarySchool/RetailStandalone FATALED in the
  reference sizing run — legacy sys_4 optimum-start EMS programs survive the
  HVAC strip with dangling handle references that reach EnergyPlus as raw
  {UUID} tokens. Fix: `Reference.purge_orphaned_ems` removes EMS programs with
  dangling references (plus emptied calling managers and orphaned actuators)
  with a loud audit warning — the reference's controls come from the reference
  ruleset, never proposed EMS overrides. All five archetypes now PASS
  (six real buildings including SmallOffice).
- **Who/when:** Claude under D-10 delegation, 2026-07-23.
- **Evidence:** sweep verdict tables (before/after); ERV+pump suites and
  rake necb:verify green post-fix.

## D-17 — Legacy ERV diagnosis filed upstream (issue #2123)

- **Decision:** the legacy NECB2020/2025 ERV determination defect was diagnosed
  to file/line and reported upstream: NECB2020 has no override, so it inherits
  NECB2017's data-driven formula (`NECB2017/data/formulas.json`
  `heat_recovery_requirement_formula`) — a faithful transcription of the
  CONTINUOUS Table 5.2.10.1.-B only. Missing vs the 2020/2025 text: (1) the
  non-continuous Table -A path (operating hours never consulted), (2) the
  <10% OA exemption (`hdd >= 3000 -> true` has no OA floor). Legacy therefore
  OVER-equips ERVs at HDD >= 3000 — observed on SmallOffice (5 ERVs, loops at
  3.8-12.8% OA) and Warehouse (3 ERVs, all <10% OA). NOT the 150 kW EHC
  method (that is NECB2011/2015 only) — corrects this record's earlier
  shorthand. Issue includes a full solution draft (both tables + availability-
  schedule hours classifier) and five regression tests; PR offered.
- **Who/when:** filed by phylroy (drafted under D-10 delegation), 2026-07-24.
- **Evidence:** https://github.com/NatLabRockies/openstudio-standards/issues/2123
  (the former NREL repo — renamed/transferred; GitHub redirects the NREL URL).

## D-18 — Sys-6 zone grouping rewritten to Note (3) of Table 8.4.4.7.-B

- **Decision:** the builder's one-air-handler-per-storey convention (comment
  claimed "the NECB sys6 convention") has NO code basis and was caught by the
  archetype fixed-point comparison (our MURB reference built 10 corridor
  systems where legacy built 1; the code text vindicates legacy). zone_groups
  now implements Note (3) verbatim: <= 4 above-ground storeys -> ONE system
  for all storeys; > 4 storeys -> external thermal blocks grouped by facade
  orientation (N/E/S/W, 45-degree-centred bins), internal blocks one group;
  underground blocks always one independent group. **Corner blocks** (exterior
  walls on several facades) bin by LARGEST exterior-wall area among
  orientations, ties resolving N > E > S > W — deterministic and
  area-faithful. External/internal/underground classification from surface
  boundary conditions (Outdoors walls; Ground/Foundation walls with no
  Outdoors walls = underground).
- **Who/when:** phylroy directed the fix incl. corner-block handling,
  2026-07-24; grouping details Claude under D-10.
- **Evidence:** vav_reheat.rb zone_groups; NECB 2020 8.4.4.7 text (Note (3))
  retrieved via codes MCP; MURB re-sweep topology (corridors collapse 10 -> 1
  system, reference converges toward the legacy 2-loop layout).
