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

**Maintenance (D-44):** every new `## D-XX` heading here must also land in
`openstudio-necb/lib/openstudio_necb/data/decisions.json` — the runtime registry
the audit log and the AHJ report read. `test/test_decisions_registry.rb` fails
the build in both directions (heading without registry entry, registry entry
without heading), and a `kind: "runtime"` entry must be cited by at least one
`ruling:` tag in gem code. Registry summaries are PARAPHRASE — never NECB text
verbatim (D-01 scopes verbatim reproduction to the generated coverage docs).

**Live registers:** D (decisions, here) and L (legacy findings,
`legacy_findings.md`). The A/T registers of the 2026-07-25 reference-systems
audit are drained and archived — see `docs/README.md`.

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

## D-19 — Infiltration lineage reconciliation (OPEN: arithmetic differs, both claim the same code default)

- **Facts pinned (2026-07-24):** 8.4.4.3.(6) sets reference air leakage equal to
  the DEFAULT of 8.4.3.3.(3); 8.4.3.3.(3) = 1.50 L/(s.m2) at 75 Pa, adjusted per
  8.4.2.9.(2) (I_AGW = (5/75)^0.6 x 1.50 x S/A_AGW, applied to above-ground
  wall area). For an UNTESTED building, proposed and reference must therefore
  carry IDENTICAL infiltration — the observed MURB difference (proposed 0.142
  vs reference 0.247 mean ACH; the entire 2.5x heating gap) is NOT
  code-intended. My earlier "code-intended asymmetry" call was WRONG and is
  retracted. Our transform implements the code arithmetic textually
  (AIR_LEAKAGE_I75 = 1.50, exponent 0.60, S/A_AGW, per-wall-area). Legacy
  NECB2020 vendors the CORRECT constant (0.0015 @75 Pa, ref PCF 1414, note
  claims code conversion) but no NECB2020 override of the 2011
  space_apply_infiltration_rate (total = constant x wall+roof+subsurface,
  spread over all exterior area, no visible (5/75)^0.6 or S/A_AGW step) was
  found in building_envelope.rb.
- **Open items:** (1) locate where (if anywhere) legacy applies the pressure
  conversion for 2020; (2) reconcile DELIVERED ACH — the E+ tabular values are
  confounded by infiltration coefficient models (constant/wind terms may
  differ between lineages); compare design flow totals and coefficients
  directly from both OSMs; (3) our pipeline should WARN when an untested
  proposed's infiltration deviates from the 8.4.3.3.(3) default (today it is
  cloned untouched — deviation below default is PERMISSIVE); (4) if legacy
  skips the pressure conversion, that is a third wrong-vintage/AS-IS defect
  for the upstream issue set.
- **Who/when:** Claude under D-10 delegation, 2026-07-24. Findings [READ] from
  code text (codes MCP) and both lineages' source; not yet numerically closed.

### D-19 amendment (same day): legacy override FOUND — divergence narrowed to area accounting

Correction: legacy NECB2020 DOES override space_apply_infiltration_rate
(necb_2020.rb:67, missed on first look — it lives in necb_2020.rb, not
building_envelope.rb) and applies the SAME formula as our transform:
1.5e-3 x (5/75)^0.6 x S/A_AGW. Both lineages implement 8.4.3.3.(3) /
8.4.2.9.(2). The remaining divergence is in the AREAS and application basis:
legacy's "A_AGW" accumulates ALL Outdoors surfaces (walls + roofs + exposed
floors; code says above-ground WALLS only — minor for a highrise, large for
a 1-storey warehouse), legacy uses space multipliers, and the two lineages
apply the per-m2 rate over different E+ fields (flow-per-exterior-surface vs
flow-per-exterior-wall). The observed 0.142-vs-0.247 delivered-ACH gap is
the product of these area/application choices plus possibly differing E+
coefficient terms — still to be numerically reconciled surface-by-surface
on the MURB before declaring which lineage (or both) deviates and by how
much. The proposed-side default-conformance warning (open item 3) remains
to implement.

### D-19 resolution (2026-07-24): infiltration FIXED and verified; residual MURB heating gap reopened as D-20

Step-0 arithmetic exonerated BOTH lineages on design flow: legacy proposed and
our reference each install EXACTLY the code total (1601.8 L/s = 0.1969 x 1.5 x
S on the MURB, 100.0% both sides; legacy 2020's area quirks net out here). The
real defect was OURS and temporal: the reference wrote the constant convention
(A=1) while the cloned proposed carried DOE-2 wind-driven (A=0, C=0.224) —
identical design totals, ~1.7x different delivered ACH. FIX: the reference now
inherits the proposed's modifier coefficients + schedule (constant fallback
when the proposed has none), and an untested proposed whose installed total
deviates >10% from the 8.4.3.3.(3) default draws a loud warning (below-default
is the permissive direction). VERIFIED: reference delivered infiltration
0.247 -> 0.135 ACH (proposed 0.142); reference energy 24128 -> 23069 kWh wk
(78% -> 81% of target); envelope suite green incl. new inheritance +
deviation-warning tests.

## D-20 — MURB residual heating gap (OPEN)

With ventilation, infiltration, lighting, equipment, SHW, pumps and ERV count/
effectiveness (both lineages 0.5) now symmetric or ruled out, reference
heating remains 30.0 GJ vs proposed 13.3 GJ for the January week. Next
suspects, untested: reference VAV terminal minimum-flow reheat on the corridor
system; MAU supply-air tempering setpoint vs legacy's; PTAC sizing/control on
reference dwelling zones. To be investigated next session.

### D-20 progress (2026-07-24): SAT hypothesis TESTED AND REFUTED

The corridor sys-6 SAT control asymmetry (our constant 13 C deck vs legacy
SingleZoneReheat 13-43 C) was implemented as a Warmest 13-43 C reset and
measured: reference WORSENED 23069 -> 23528 kWh wk (heating 30.0 -> 31.9 GJ).
Cause of the refutation: the sys-6 terminals carry REHEAT COILS, so the 13 C
deck was never cold-dumping — it is standard VAV-with-reheat practice; the
Warmest variant merely over-delivers at minimum flow. Change REVERTED. SAT
control moves the picture by ~+-2 GJ; the dominant ~17 GJ residual is
elsewhere. Next suspect (dwelling side, where the gain-summary excess sits):
the MAU / PTAC / baseboard interaction on reference dwelling zones — PTAC fan
and cycling behaviour, MAU operating schedule, and zone-equipment control
order — via a zone-level differential audit of one representative suite.

### D-20 CLOSED (2026-07-24): economizer on the 100%-OA MAU was locking out heat recovery all winter

Root cause, convicted by direct model comparison ("compare the systems" —
phylroy's suggestion): the 8.4.4.12 economizer pass put DifferentialEnthalpy
on EVERY reference air system including the System 1 makeup-air unit (100%
outdoor air, 80 of 90 zones). An air economizer cannot increase OA on an
all-outdoor-air system, but its winter signal (outdoor enthalpy < return —
true every heating hour) engages the HX economizer LOCKOUT and bypasses the
5.2.10.1 energy-recovery wheel for the entire heating season. The legacy
archetype correctly models the MAU with NoEconomizer. Confirming evidence:
reference Heat Recovery end-use was 0.00 GJ vs proposed 1.37; the corridor
loops were symmetric (both lineages lock out there, both DifferentialEnthalpy).

FIX: apply_economizers exempts System 1 with an audited info note. VERIFIED
on the MURB January week: reference heating 31.9 -> 12.9 GJ (proposed 13.3 —
heating rows now MATCH); reference total 23528 -> 18358 kWh wk; fixed point
converged to 102% of target. The compliance flip (was 78%, now marginal
non-compliant at 102%) is the CORRECT outcome of a fixed-point test — an
essentially-reference building should land AT the boundary, not enjoy a 22%
cushion granted by disabled mandated heat recovery. Cumulative D-19+D-20
effect on the MURB reference: 24131 -> 18358 kWh wk (-24%): the reference
generator was PERMISSIVE by nearly a quarter on this building class before
the fixed-point audit.

Residual ledger for the MURB (~2%): infiltration normalization remainder
(0.135 vs 0.142 ACH), DX COP bins (summer-side), pump/fan rule differences —
all individually documented above.

### D-19+D-20 fleet effect (first full annual sweep since both fixes)

| Building | ref before | ref after | % of target before -> after |
|---|---|---|---|
| Warehouse | 15339 | 12186 | 83% -> 104% (marginal fail) |
| FullServiceRestaurant | 5114 | 4122 | 56% -> 69% |
| HighriseApartment | 24131 | 18358 | 78% -> 102% (marginal fail) |
| PrimarySchool | 36275 | 26433 | 60% -> 83% |
| RetailStandalone | 10864 | 7694 | 64% -> 90% |

The reference generator was 20-29% permissive fleet-wide, dominated by the
D-19 infiltration-convention asymmetry (every building) plus D-20's MAU
heat-recovery lockout (System-1 buildings). Post-fix the archetypes cluster
near 100% of target — the fixed-point expectation for code-minimum
buildings. The two marginal fails (102%/104%) and the Restaurant's 69% are
within the documented residual ledger (legacy over-equipped ERVs per
upstream #2123, DX COP bins, infiltration normalization remainder). All
gates green: full hvac suite, necb:verify, 5/5 sweep PASS.

## D-21 — Residual infiltration asymmetry on low-rise buildings (OPEN, two new findings)

The 19-29% reference drops on Restaurant/PrimarySchool/Retail are fully
attributed: D-20 fired ZERO times outside the MURB (audit-verified), so they
are pure D-19 coefficient inheritance. But the post-fix symmetry check
exposed two new items:

1. **Legacy over-installs proposed infiltration on roof-dominated low-rise
   buildings**: proposed installed totals are 160% (Restaurant, 401 vs 250
   L/s) and 166% (Retail, 1703 vs 1025) of the 8.4.3.3.(3) code default —
   the legacy wall+ROOF area basis inflates exactly where roofs dominate.
   The MURB tower (negligible roof) masked this: its total was 100.0% exact.
   ABOVE-default proposed infiltration is the CONSERVATIVE direction
   (proposed pays extra heating), but it is still non-conformant modeling —
   upstream-issue material alongside #2123.
2. **Our 8.4.3.3.(3) deviation warning failed to fire** on 60-66% deviations
   — a warning-coverage defect. Prime suspect: the proposed-total computation
   is skipped when ELA/FlowCoefficient objects exist, or an ordering issue;
   to be fixed with a hostile test that PINS the warning on a deviating model.
3. Delivered-ACH asymmetry (Restaurant 0.095 vs 0.292 mean zone ACH) also
   reflects per-space DISTRIBUTION (legacy spreads flow over exterior
   surfaces incl. the huge attic volume; our wall-area basis concentrates it
   in perimeter zones) — totals AND distribution both matter for zone-level
   comparisons; building totals are the code-meaningful quantity.

Who/when: Claude under D-10 delegation, 2026-07-24; [RAN] evidence from
sweep audits + model totals probes.

### D-21 correction (same day): the warning is NOT defective; finding 1 retracted as stated

Direct repro on the Restaurant model: ELA/FC guard not involved (0/0), and
the warning correctly did NOT fire — the transform computes code_total from
its envelope_area = 1356 m2 (Outdoors+Ground surfaces INCLUDING the attic
roof) giving 400.6 L/s, which matches the legacy proposed's 401 L/s within
0.1%. The "160% over-install" figure in finding 1 came from this
investigator's scratchpad probe using a NARROWER S (846 m2, effectively
excluding the attic roof) — the two lineages actually AGREE with each other
on roof-inclusive S. Finding 1 is therefore retracted as stated; what
remains open is the real question underneath: does 3.2.4.2.(1)'s "total
area of building envelope" mean the attic ROOF or the CEILING below an
unconditioned attic? That decides the correct default total for every
attic building and affects BOTH lineages identically — a code-text
verification for next session, not a lineage divergence. Finding 3
(distribution: legacy floods the huge attic volume with infiltration, our
wall-basis concentrates it in perimeter zones) stands, and is now the whole
explanation for the Restaurant delivered-ACH asymmetry.

### D-21 verdict (2026-07-24): 3.2.4.2.(1)(c) settles the envelope-area question

Code text, verbatim: the air leakage area "shall include all the surfaces
separating conditioned space from unconditioned space" (3.2.4.2.(1)(c),
referenced by 8.4.2.9.(2)'s S). For an unconditioned attic: the attic ROOF
does NOT bound conditioned space and is NOT in S; the CEILING below the
attic IS. BOTH lineages currently compute roof-inclusive S, so both
over-install the default on attic buildings — a SHARED conservative bias
(symmetric between proposed and reference, so comparisons stay fair; the
absolute default totals are high). My scratchpad probe's narrower S was
closer to the code's intent; the mutual 401-vs-400.6 agreement was two
implementations sharing the same S mistake.

QUEUED FIX (ours): envelope_area/S per (c) — exclude Outdoors surfaces of
unconditioned spaces (attics/plenums; partofTotalFloorArea/zone-conditioning
heuristic), include interzone surfaces between conditioned and unconditioned
spaces; pin with an attic-fixture test. Legacy side: same S issue, one more
item for the upstream set. Impact: attic-building default totals drop
(Restaurant ~1356 -> ~850-900 m2 basis); tower/MURB unaffected.

### D-21 CLOSED (2026-07-24): S computed per 3.2.4.2.(1)(c), attic-pinned

apply_air_leakage_default now builds S as the enclosure of the CONDITIONED
volume: Outdoors + ground-contact surfaces of conditioned spaces plus
interzone surfaces to unconditioned spaces (attic ceilings/plenums);
unconditioned spaces' own surfaces are excluded and receive NO infiltration
object (their exterior walls sit outside A_AGW). Ground contact stays in S
as normalization area — no slab leakage is modeled; the S/A_AGW term puts
the whole total on above-ground walls (phylroy's ground-leakage challenge,
answered from the (1)(c) text). Multiplier-aware. Pinned by an attic
fixture test: 10x10x3 conditioned + 10x10x2 attic -> S=320 (not 500),
A_AGW=120, installed total = 0.2954 x S, attic object-free. Attic-building
reference defaults will drop at the next sweep (Restaurant basis 1356 ->
~320-scale per its geometry); the legacy side's roof-inclusive S remains
upstream-issue material.

## D-22 — Audit T-list implemented (T1-T13); fleet converges to 90-105%

All thirteen ours-side findings from the 2026-07-25 reference-systems audit
fixed in one batch (see audit_2026-07-25_reference_systems.md for the list):
oversizing caps now BIND (generic zone factors cleared, HP 1.0 preserved);
tower fan at Table 5.2.12.2 0.013; post-sizing 5.2.2.7 economizer trigger
(strip below 1500 L/s & 20 kW); HP heating capacity pinned to cooling
(8.4.4.13.(2)(c)); night-cycle + min-OA-follows-schedule; ERV wheel
parasitic power + OA-flow bypass; 8.4.4.15 -> partial + hard-set-OA warning;
humidification + mixed-group warnings; zone-equipment fans to the
8.4.4.18.(3) spec; VAV reheat flow cap 0.5; strict staging boundaries +
ceil cells; stale notes fixed. Four new pin tests (test_audit_fixes.rb) +
widened citation pin. Gates: full hvac scan clean, necb:verify green,
umbrella battery 8/118, sweep 5/5.

Fleet effect (January week, % of target): Warehouse 104->105, Restaurant
69->98, HighriseApartment 102->99, PrimarySchool 83->96, Retail 90->90.
The dominant movers were T5 (unoccupied OA shutoff + night cycle — the
Restaurant and School references stopped heating 24/7 ventilation) and the
counter-direction T6/T10 (wheel power, zone-fan spec) — the fleet now sits
90-105% of target, the tightest fixed-point clustering yet. A-list items
(A1-A5) remain with phylroy.

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-23 — Film convention: table U is OVERALL transmittance (default flipped)

The object-level fixed-point diff (phylroy's "compare the OSM objects"
approach) showed every legacy archetype wall at construction conductance
0.276 vs our reference 0.265. Decoded exactly: legacy NECB2020 prototypes
build constructions via OSut TBD.genConstruction, whose uo is documented
"desired Uo factor (WITH air film resistance)" (wall film 0.150, roof
0.140) -> construction-only 1/(1/0.265-0.150)=0.276, 1/(1/0.156-0.140)=
0.159. The NECB 1.4.1.2 definition settles who is right: overall thermal
transmittance "reflects ... air films on both faces of above-ground
components" [READ, MCP]. Our include_films: false default (comment claimed
it "matches legacy BTAP" — true of the OLD BTAP path, not of what NECB2020
prototypes actually run) was ~4% OVER-stringent on walls.

Decision: include_films now defaults TRUE (module + facade). Exemptions:
SimpleGlazing fenestration takes the table value directly (its uFactor IS
the with-films value; legacy agrees — archetype windows carry 1.9/2.69
verbatim). Mechanism-parity test passes include_films: false explicitly
(it gates the BTAP mechanism, not the convention). film_r values match
OSut within rounding (wall 0.1497/0.150, roof 0.1374/0.140, floor
0.192/0.190). Pins updated: wall 0.27595, roof 0.15942, ground floor
0.86283.

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-24 — Envelope scope: unconditioned spaces out, interzone assemblies in

Second object-diff finding: the Restaurant reference carried an attic DECK
at U 0.156 while legacy leaves it uninsulated (4.461) and insulates the
ceiling. Both our prescriptive AND reference transforms iterated ALL
Outdoors/Ground surfaces and skipped ALL interzone surfaces — backwards on
both counts per the 1.4.1.2 "building envelope" definition (separates
CONDITIONED space from unconditioned/exterior/ground).

Decision (implemented in Prescriptive.apply, shared by the reference
transform):
- surfaces of unconditioned spaces (inside_envelope? = partofTotalFloorArea,
  with the legacy space_conditioning_category tag honoured so tagged plenums
  count as inside) are LEFT UNTOUCHED (audited info, 1.4.1.2.);
- assemblies separating conditioned from enclosed unconditioned space are
  envelope: Table 3.2.2.2 row by INCLINATION (3.1.1.7.(6) — surfaceType
  encodes it), the enclosure credited at U 6.25 per 3.1.1.7.(4), interior
  films both faces. Attic ceiling target: 1/(1/0.156-0.16-0.215)=0.16569.
  Paired surface gets the same construction.
- the same inside_envelope? predicate now drives the 8.4.3.3 air-leakage S
  and the lightweight rebuild (attic decks keep real constructions).

DIVERGENCE from legacy, logged not adopted: legacy OSut applies the
exposed-FLOOR row (0.175) to attic ceilings ("iAtticFloor" with
uo=eFloorU). 3.1.1.7.(6) classifies horizontal top-of-conditioned-space
assemblies as ROOF assemblies; the floor-row reading is more lenient with
no inclination-rule basis. Ours: roof row + enclosure credit -> overall
0.1602 effective vs legacy's 0.175-equivalent. Candidate legacy ledger row
(attic ceiling row choice) — filed as L-18.

Pinned by test_attic_scope_deck_untouched_ceiling_retargeted (deck
construction unchanged; ceiling at 0.16569; pair shares the construction).
Fleet impact: reference walls ~4% less insulated (reference energy UP
slightly, % of target DOWN) — full-fleet re-sweep queued behind the
17-archetype run.

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-25 — Runner design-day attach: replace + filter to annual extremes

LargeOffice (the only archetype whose PROPOSED carries a cooling tower)
crashed E+ sizing: "Bad starting values for UA". Root cause chain: (1)
Runner.attach_weather! APPENDED the full DDY onto models that already carry
design days -> 81 SizingPeriod:DesignDay objects with duplicates; (2) a
first-cut filter regex (/.4%/) still matched the MONTHLY .4% design days —
a January cooling day's ~2C wet-bulb makes the tower UA regula-falsi
bracket infeasible. Legacy sizing runs use 3 design days (verified in the
generation's SR2 in.idf).

Fix: attach_weather! now REMOVES existing design days and imports only the
legacy model_set_design_days default list (Htg 99.6% DB, Clg .4% DB=>MWB /
0.4% DB=>MCWB, Clg .4% WB=>MDB), falling back to the full set only when a
DDY matches nothing. NOTE: every earlier sweep sized on the duplicated
81-DD set; the magnitude of that effect on prior fleet numbers is
UNVERIFIED until the post-D-23/D-24 re-sweep (which uses the corrected
attach throughout) lands.

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-26 — Tower fan sums the condenser loop; sized tower hydraulics hardened

Two-part follow-up to T2, exposed by LargeOffice (the first two-chiller +
tower fleet member):

1. apply_tower_rules computed rejection from the PRIMARY chiller argument
   alone. A two-chiller plant (8.4.4.10.(6) split) halves per-chiller
   capacity, so the tower fan came out at half the code value. Now a
   dedicated pass AFTER all chiller capacities are final: rejection = SUM of
   sized capacities x (1+1/COP) over the loop's chillers (parked 0.001 W
   secondaries contribute ~0 — correct). Pinned by
   test_tower_fan_power_sums_chillers_on_loop.

2. Even with the correct fan, re-running sizing with a HARD code fan crashes
   E+ ("Bad starting values for UA"): E+ derives autosized tower air flow
   FROM fan power, then solves UA by regula falsi — empirically the solve
   fails for THIS plant at hard fans of 17-30 kW while the 15.9 kW autosize
   and 39.3 kW both pass [RAN, standalone E+ bisect]. Legacy sets the same
   0.013 kW/kW pre-sizing and merely happens to sit outside the band
   (proposed air/load 0.0348 passes; ours 0.0341 failed). Fix: when the
   post-sizing pass sets the Table 5.2.12.2 fan, it FIRST hardens the sizing
   run's solved water flow / air flow / UA / free-convection values on the
   tower — later runs have nothing to re-solve; the code fan is a parasitic
   override on E+'s self-consistent heat-transfer sizing. The code governs
   fan POWER, not UA, so this is faithful.

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-27 — SWH circulators are outside 8.4.4.14; transfer head reconciled

First finding from the reference-system VARIANT matrix (gas fuel column —
run at phylroy's direction after the coverage analysis showed the electric
archetype fleet exercises only 4 of 14 catalog variants): all four gas
buildings crashed E+ in reference_annual with "Errors found in Pump input"
— the D-11 pump transfer had put the space-heating W/(L/s) intensity onto
the SERVICE WATER LOOP circulator (8 W) while it kept the proposed's 1.9 MPa
head, implying a 724% pump efficiency (E+ fatal). The electric fleet ran
the same code path and passed only by arithmetic luck (76 W -> 66%).

Decision:
- Loops with a water heater on supply or water-use connections on demand
  are OUTSIDE the 8.4.4.14 hydronic-pump scope: no riding curve, no
  transfer, audited info. They are also EXCLUDED from the proposed
  intensity stats (an SWH circulator must not pollute the Heating-loop
  W/(L/s)).
- Physicality guard on every transfer: if flow x inherited_head /
  transferred_power exceeds motor efficiency, the head is reconciled to a
  65% total efficiency (power is the article's number and stays
  authoritative); loud warning.

Pinned by test_swh_loop_excluded_from_pump_rules_and_stats and
test_transfer_reconciles_unphysical_inherited_head.

- Who/when: Claude under D-10 delegation, 2026-07-25.

### D-27 amendment (2026-07-29): a reconciled pump is only physical for the sizes it was reconciled AGAINST

Found reviewing the D-46 staging change, but NOT caused by it — a latent
defect the topology change happened to trip. The transfer (and the D-38 clamp)
hard-set pump POWER and reconcile the head, while pump FLOW stays autosized.
The triple is physical for the flow sized SO FAR; the next sizing run
re-derives the flow, and a grown flow makes the frozen power/head imply a pump
efficiency above the motor efficiency — an EnergyPlus INPUT fatal ("Calculated
Pump Efficiency > 100%"), thrown during input checking, before the efficiency
pass gets its chance to re-reconcile. Measured: reference HW pump reconciled
at 2.0e-4 m3/s, re-sized to 3.24e-4 (1.62x) in an 8.4.1.2.(5) round, 117%.

Fix (root, not margin): `NECB.prepare_for_resizing(model)` releases hard-set
pump power back to AUTOSIZE, and the umbrella calls it before every
capacity-iteration re-size. EnergyPlus then derives power from the flow and
head it just sized — inconsistency impossible by construction — and the
efficiency pass immediately re-transfers against the NEW flow, so no article
value is lost. A pure margin (reconciling at 65% instead of the ~90% motor
ceiling) was tried first and rejected: it only buys a ratio of headroom and
still failed this case.

Pinned by test_capacity_iteration_converges_undersized_building (which fataled
before the fix). Any future pass that hard-sets a sized quantity on a model
that may be re-sized belongs in `prepare_for_resizing` too — reference boiler
and chiller capacities are the standing candidates.

## D-28 — Multizone selection groups merge into whole-building systems

LargeOffice end-use isolation (the +7-12% fleet outlier): the proposed
archetype partitions zones per STOREY (5 air loops), and building one
reference system per selection group leaked that partition into the
reference — the 12-effective-storey LargeOffice (mid floor x10 multiplier;
above_ground_storeys=12 is CORRECT) got 3 storey-groups x (4 facades +
internal) = 17 systems instead of the ~6 Note (3) to Table 8.4.4.7.-B
prescribes. Fragmentation consequences, all confirmed by end uses: 6 of 17
loops fell below the 1500 L/s economizer trigger (NoEconomizer -> January
mechanical cooling 2.1 GJ + 10.4 GJ of condenser/CHW pumping while legacy
free-cools at 0.1 GJ), small per-loop flows dodged Table 5.2.10.1 (1 ERV
vs a consolidated 2), and 17 fan pairs.

Decision: same-catalog multizone (sys 2/5/6) :build assignments merge
before building — one system spans the thermal blocks of all storeys; the
facade/internal/underground split happens INSIDE the builder (D-18
zone_groups). Single-zone families (1/3/4/hp) keep their selection
grouping (sys-3 school/retail loop counts stay at legacy parity). Audited
as 'multizone selection groups merged into whole-building systems'.

Effect: LargeOffice 17 -> 6 loops, cooling 2.1 -> 0.2 GJ, pumps 10.4 ->
6.6 GJ; MediumOffice 3 -> 1 loop. Both references DROPPED (better), moving
% of target 107 -> 110 / 103 -> 110 — the residual is the FAN gap (legacy
51.4 vs ours 23.1 GJ at similar design flows/pressures/schedules), under
investigation via the legacy-curve transplant experiment.

- Who/when: Claude under D-10 delegation, 2026-07-25.

### D-28 verdict (2026-07-25): the residual office gap is legacy fan energy

Transplant experiments on the LargeOffice reference (post-merge, January
week) [RAN, standalone E+; note: energyplus -D silently gives an all-zero
ABUPS — drop it for weather runs]:

| configuration | Fans GJ | Heating GJ |
|---|---|---|
| our reference (code Table 8.4.4.17 curves, D=0.35) | 23.1 | 57.9 |
| + LEGACY fan curves/floor (0.68 cubic, L-9 config) | 33.1 | 57.9 |
| + night OA open (undo T5 damper schedule) | 33.1 | 60.8 |
| legacy archetype (target) | 51.4 | 65.2 |

Accounting: L-9 curve/floor ~10 GJ; design flow (-14%, 274 vs 234 m3/s)
~5 GJ; night-OA ~3 GJ of heating; the remaining ~18 GJ of fan energy is
the archetype's own prototype fan operation at legacy's higher flows —
a PROPOSED-side characteristic. Everything reference-side is
probe-verified against the printed code (curves, floors, pressures,
efficiencies identical-or-code). Verdict: the office +10% is dominated
by the legacy archetype NOT being code-minimum on fan energy — the
fixed-point premise partially breaks for VAV offices, from the legacy
side. Strengthens the L-9/L-10 upstream case with a measured whole-
building effect (~2.2x reference fan energy on LargeOffice).

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-29 — Upstream issues carry explicit Claude authorship (phylroy's direction)

"file the L-9/L-10 fan issue upstream as you not me" + "state in
#2123/#2126 and future issue that you wrote it": L-9+L-10 filed together
as #2127 with an authorship note naming Claude as the author (submitted
from phylroy's account for access; AI authorship stated in the body), and
the same note was prepended retroactively to #2123 and #2126. STANDING
RULE for future upstream filings: always include the authorship note.
Supersedes the earlier no-Claude-attribution convention from the #2123
filing.

- Who/when: phylroy directed, Claude executed, 2026-07-25.

## D-30 — Ledger cleared: L-11..L-17 and L-19 filed upstream as #2128/#2129/#2130

Per the D-29 authorship rule (all Claude-authored, stated in each body):
- #2128 — Table 8.4.4.7.-A selection: L-11 (residential row still 2011
  text) + L-16 (unlisted space types hard-raise vs the 8.4.4.7.(3)
  closest-correspondence fallback).
- #2129 — reference modeling rules: L-15 (hvac_system_4.rb:76 control-zone
  cooling ΔT overwritten with the heating 21 K value — verified at the
  line), L-14 (5.2.2.7 flow branch without mechanical cooling + missing
  dwelling/hotel exemption), L-17 (no Table 8.4.4.14 pump coefficients),
  L-12 (8.4.4.6 purchased energy unimplemented), L-13 ('NECB_Defualt'
  dead guard).
- #2130 — L-19 film-convention disagreement between the OSut and BTAP
  construction paths (~4% on the same Table 3.2.2.2 values).

Ledger now has NO unfiled rows; open remainder is UNRESOLVED-only (L-6 DX
COP convention, L-7 NECB2015 ERV vintage question). Coverage docs
regenerated post-D-23..D-28 (57/57, no conflicts, no fallbacks).

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-31 — L-6 and L-7 root-caused: both close with NO legacy defect

L-6 (DX COP "mismatch") was a FALSE PREMISE — the fourth of this effort:
archetype coil names carry their ratings (53kBtu/hr 15.0SEER, 328/722
kBtu/hr 10.0EER) and those ARE the printed Table 5.2.12.1.-A minimums
[READ, MCP]: <19 kW single-package "others" -> SEER 15; 70-223 kW
electric-resistance-heat row -> EER 10.0 (722 kBtu/hr = 211.6 kW sits
below the 223 kW boundary, so 10.0 not 9.7). The observed COPs are those
ratings through the standard fan-stripping conversions — SEER: -0.0076s^2
+0.3796s; EER: ((EER/3.412)+0.12)/(1-0.12), Thornton r=0.12 — and the
formulas are byte-identical in the gem (efficiency.rb) and legacy
(hvac/conversions.rb). The "3.0 bins" expectation was naive EER/3.413.
Convention now PINNED: rated SEER/EER are fan-inclusive; E+ coil COP is
coil-only; both lineages strip the fan the same way.

L-7 (NECB2015 ERV vintage): legacy NECB2015 has NO override of
air_loop_hvac_energy_recovery_ventilator_required? (runs the 2011 150 kW
trigger; the override chain starts at NECB2017) [READ]. Secondary sources
converge that this is VINTAGE-CORRECT: the national NECB 2015 kept the
150 kW sensible-exhaust-heat trigger (Quebec's NECB-2015-Qc amendment cut
it to 50 kW — an amendment presupposing the 150 kW national base; change
summaries put the flow-rate/OA-based rewrite at NECB 2017). Primary 2015
text is not machine-accessible (codes MCP: 2020/2025 only) — flagged for
re-verification if 2015 is ever ingested. UNVERIFIED-against-primary is
stated in the ledger row.

Ledger status after D-31: no UNFILED and no UNRESOLVED rows remain.

- Who/when: Claude under D-10 delegation, 2026-07-25.

## D-32 — Warehouse residual root-caused: ground-floor Table 3.2.3.1 extent was misread (our defect, fixed)

End-use isolation on all four Warehouse variants showed the +2..+6% residual
was ENTIRELY heating (fans at parity, unlike the offices); the heat-balance
decomposition put 9.6 GJ/wk of it in opaque conduction; the object diff (its
envelope check only compared Outdoors surfaces — ground was a blind spot,
now understood) pinned it to the 4,598 m2 slab: legacy models it BARE
(U 7.39) in zones 4-7B while our reference insulated it FULL-AREA to the
Table 3.2.3.1 value (0.757 -> 0.863 construction-only).

The printed table [READ, MCP, 2020 and 2025 identical] is zone-conditional:
floors row reads "0.757 for 1.2 m" in zones 4-7B — a PERIMETER STRIP per
3.2.3.3.(3), the slab field carries NO prescriptive maximum — vs "0.379 for
full area" in zone 8. Confirmation from the fleet: at Yellowknife (zone 8)
legacy insulates full-area at U 0.403 = 0.379 with the interior film
stripped, agreeing with our 0.404 to three digits. Our full-area application
below zone 8 was the defect (8.4.4.1.(2): the reference must MEET 3.2, and
3.2 prescribes only the strip).

Decision: openstudio-envelope Prescriptive now implements the printed rule —
zone 8 keeps the full-area retarget; zones 4-7B keep the modeled slab field
and get the strip via the Kiva foundation's interior horizontal insulation
(R sized so the strip assembly meets the table U, width from the rules JSON;
plain-Ground floors without Kiva get an audited warning that the strip is
not representable). The extent metadata lives OUTSIDE u_values (which is
structurally pinned to the legacy JSON by test_data_integrity). Mechanism-
parity test excludes ground floors (legacy old-BTAP applies full-area — one
of the two mutually inconsistent legacy paths, see L-20).

Measured effect (January week, % of target): Toronto electric 106 -> 104
(heating delta +2.72 -> +1.28 GJ), Toronto gas 102 -> 106 (the reference's
gas-coil AFUE bin flipped across the 66 kW boundary as loads resized — the
new run is internally consistent at blended eff ~0.84), Edmonton 99 -> 101
(the load change legitimately tipped one ERV determination), Yellowknife
unchanged by construction (zone-8 path untouched). Remaining residual is
attributed to LEGACY-side divergences: the missing 1.2 m strip in the
archetypes (~6.7 GJ/wk of opaque loss on this slab, L-20 — Kiva 2D: the
strip recovers ~70% of full-slab insulation's benefit), ERV wheels running
in all climates from the wrong-vintage trigger (#2123 family, +0.19 GJ
parasitic), and CV fan character (+0.31 GJ, #2127 family). The fixed-point
premise again breaks from the legacy side, as with the D-28 offices.

- Who/when: Claude under D-10 delegation, 2026-07-25.
- Evidence: [RAN] ABUPS end-use + SensibleHeatGainSummary decomposition on
  cached sweep SQL (4 variants); [RAN] object survey incl. Foundation
  surfaces; [READ, MCP] NECB 2020/2025 3.2.3.1/3.2.3.3/8.4.4.1; [RAN]
  envelope test battery + parity gate green; [RAN] 4-variant re-runs.

## D-33 — Variant mockup set: the never-fleet-exercised reference routes now run the full pipeline

Coverage audit of the reference-system routes (sweep audits x 22 runs +
gem test greps): the archetype fleet only ever selects/builds Systems
1/3/4/6 (electric + gas). Gem-level topology tests already covered sys 2,
hp, copy_proposed, through_the_wall and sys 1 — but System 5 had NEVER
been built anywhere (selector-level only), the kitchen-hood ROUTE never
fired, the 8.4.4.6 purchased-energy representations had no build test,
and none of the non-fleet routes had ever been through the umbrella
pipeline (proposed+reference sizing runs, post-sizing efficiencies, ERV
determination).

Decision: seven synthetic mockups (5ZoneNoHVAC geometry + NECB catalog
space types + catalog loads baked in via openstudio-loads; conditions the
OSM cannot express carried as building: overrides in manifest.json — the
same mechanism a real modeller uses):
sys2_museum (Historical Collections -> FPFC+chiller), sys5_refrigerated
(FIRST-EVER TPFC build; A4 heating adjudication pending), hp_office
(Table 8.4.4.13 ASHP override), res_copy (compatible cooling -> identical
reference), res_ttw (incompatible central CHW -> through-the-wall),
kitchen_hood (hood route -> System 4 + article), purchased_energy
(district heating/cooling -> gas-boiler + air-cooled-chiller
representations on a storeys-3 sys 6). Generator:
scripts/generate_variant_mockups.rb -> test/fixtures/variant_mockups/;
gate: test/test_variant_mockups.rb (8 runs, sizing mode with the CLI,
:none fallback without). All green including E+ sizing on every mockup.

Finding logged en passant: 'Museum general exhibition area' selects
Assembly Area via the 'exhibit' keyword, not Historical Collections via
'museum' (category order + keyword collision). Ambiguous against the
printed Table 8.4.4.7.-A wording — the mockup uses 'Museum restoration
room' to avoid the collision; flagged for the A-list review if museum
exhibition galleries should be Historical Collections (A6 candidate).

Still unreachable by any fixture: nothing at the route level. Remaining
depth gaps are the A-list adjudications themselves (A1/A2 residential+HP
precedence and water-loop boundary, A4 System 5 heating source) — the
mockups exercise CURRENT behavior and will pin whatever phylroy decides.

- Who/when: Claude under D-10 delegation, 2026-07-27.
- Evidence: [RAN] sweep-audit scan (22 runs -> sys 1/3/4/6 only); [RAN]
  gem-test grep; [RAN] generator + 8/8 test battery with sizing runs.

## D-34 — A1 adjudicated (phylroy): residential heat-pump blocks follow legacy — ASHP redirect

phylroy's ruling (2026-07-27): "A1 follow legacy." A residential/
accommodation block whose proposed system includes a heat pump takes the
8.4.4.7.(4) ASHP redirect (Table 8.4.4.13 reference), NOT the Table
8.4.4.7.-A "(or heat pumps)" identical-to-proposed parenthetical.

Legacy context [READ]: legacy has no per-block HP detection at all — its
necb_reference_hp is a GLOBAL boolean on the fuel-type set (a generation
input); when true every family, residential included, builds its
reference-hp ASHP variant, and there is no copy branch (that absence is
L-11/#2128). "Follow legacy" therefore means: HP presence always
redirects.

Implementation: residential_assignment checks group[:heat_pump] FIRST
(before heated-only/compatible/otherwise) and returns a System-1 :build
assignment that finalize's hp override flips to 'hp'; the "(or heat
pumps)" line is removed from residential_compatible_cooling? (heat-pump
groups never reach it). Pins: selector test
(test_residential_heat_pump_redirects_not_copies), reference build test
(PTHP residential -> ASHP RTU, PTHPs replaced), new res_hp mockup through
the full pipeline with sizing; res_copy mockup switched to PTAC so the
copy rule keeps its own end-to-end pin. All green (selector 18, reference
7, ttw, murb, mockups 9/9).

- Who/when: ruling phylroy 2026-07-27; implementation Claude under D-10.
- Evidence: [READ] legacy autozone.rb necb_reference_hp branches (e.g.
  :1082), fuel_type_set plumbing necb_2011.rb:409/708; [RAN] test batteries.

## D-35 — Appendix A ingested (hbix#67 fixed): four notes fetched; lightweight rebuild corrected to light-frame mass

The hbix maintainer ingested Appendix A within a day of #67. The four
load-bearing notes were retrieved [READ, MCP 2026-07-28] and dispositioned:

1. **A-8.4.4.4.(1) (Thermal Mass) — our interpretation CORRECTED.**
   "Lightweight" is not zero-mass: the note prescribes following the
   proposed's layer structure with insulation varied to the Part 3 U-value,
   and its example assemblies are light FRAME constructions — wood-frame
   40.8 kg/m2 / 45.5 kJ/(m2.K), steel-frame 33.9 / 35.3. The reference
   rebuild now uses one StandardOpaqueMaterial calibrated to the wood-frame
   example (0.15 m; density and cp derived; conductivity from the target
   resistance) instead of a MasslessOpaqueMaterial. Bonus: one material now
   serves every boundary — the Kiva special case collapses (regular
   materials are Kiva-legal). Test pin updated to assert the note's mass
   and heat capacity. The single-calibrated-layer stands in for the note's
   layer-structure guidance (approximation stated in the manifest).
2. **A-3.2.3.3 (Floors in contact with the ground) — D-32 VERIFIED.**
   Whole-floor-or-perimeter is a binary per-floor determination measured
   once from grade; crawl-space floors count even unconstructed. Nothing
   contradicts the Kiva-strip implementation.
3. **A-Table 3.2.2.2 — no film content.** The note is about climate-zone
   derivation (90.1 minus moist/dry/marine, 7 split into 7A/7B). D-23's
   film convention continues to rest on the normative 1.4.1.2 definition.
4. **A-8.4.4.13 (Heat Pump Definitions) — A2 evidence complete.** See the
   A-list: water-loop = internal loop (aux boiler/tower allowed);
   water-source = external water (surface/ground water or external waste
   heat, directly or via HX); ground-source = ground HX. Presented to
   phylroy for the A2 ruling; not implemented pending that ruling.

- Who/when: Claude under D-10 delegation, 2026-07-28.
- Evidence: [READ, MCP] all four notes; [RAN] envelope battery green
  (reference/hostile/skylight/data-integrity/prescriptive); [RAN] Warehouse
  annual e2e with the light-frame reference (Kiva-legality + energy effect).

## D-36 — Campus 3D renderer ported into openstudio-geometry

phylroy's request (2026-07-27): bring the campus repo's OSM 3D renderer
into the gem family. Port of canmet-energy/campus geometry_view.py,
design carried verbatim: crash-isolated subprocess glTF export (the C++
GltfForwardTranslator can segfault), the three-step repair ladder
(full -> massing shell -> bisect out crashing surfaces), campus material
palette, base64-embedded glTF in Google's <model-viewer>. Facade:
OpenStudioGeometry.render(model_or_path, path:). Kept the campus CDN
trade-off for the viewer script (captioned; geometry itself embedded).
5 tests incl. deterministic ladder/bisection via injectable exporter and
a real subprocess worker round-trip. Also fixed a stale D-23-era pin in
test_bar.rb (0.265 overall -> 0.2759 construction-only naming).

- Who/when: requested phylroy 2026-07-27; implementation Claude under
  D-10, 2026-07-28.
- Evidence: [RAN] test_render.rb 5/5, wizards/bar green; [RAN] Warehouse
  reference archetype rendered end-to-end (146 KB self-contained page).

## D-37 — A2 adjudicated (phylroy): the printed 8.4.4.13 split, boundary per Note A-8.4.4.13

phylroy's ruling (2026-07-28): "implement the printed split per your
recommendation." Water-LOOP heat pumps (Note A-8.4.4.13: HP on an INTERNAL
water loop — aux boiler and/or heat-rejection device explicitly allowed)
KEEP their Table 8.4.4.7.-A selection per 8.4.4.13.(1); air-, water- and
ground-SOURCE heat pumps redirect to the Table 8.4.4.13 ASHP reference per
sentence (2).

Implementation: Classify now records per-group heat_pump_sources
(:air | :water_loop | :external) — DX/PTHP/VRF are :air; water-to-air
coils/units are classified by their SOURCE loop (ground HX, district, or
temperature-source component => :external; otherwise :water_loop).
Reference gains heat_pump_redirects?(group): redirect unless every source
is :water_loop; a detected HP with NO source evidence keeps the redirect
(conservative pre-D-37 behavior). finalize audits the WLHP retention
('8.4.4.13.(1); Note A-8.4.4.13'); the D-34 residential branch narrows to
REDIRECTING heat pumps, so a residential WLHP falls to the Table -A
residential rules ('wshp' is compatible cooling -> copy).

Consequence faced squarely: the catalog 'Water source heat pumps' system
(internal boiler + evaporative fluid cooler loop) is by the note's
definitions a water-LOOP system — the two tests that used it to prove the
ASHP redirect now use PTHP (genuinely air-source), and a new build test
pins both directions (WLHP stays -> System 3 with the note cited;
ground-HX swap -> 'hp'). Selector: five new pins incl. mixed-sources
redirect, no-evidence redirect, and residential-WLHP copy.

- Who/when: ruling phylroy 2026-07-28; implementation Claude under D-10.
- Evidence: [READ, MCP] Note A-8.4.4.13; [RAN] hvac battery green
  (selector 23, reference 8, classify, e2e 3 incl. the cold-week ASHP
  conditioning run, efficiency/ERV/2025/pump/CBECS suites), umbrella
  mockups 9/9.

## D-38 — A3 adjudicated (phylroy): 5.2.6.3 pump-power caps applied min-wins over the 8.4.4.14 transfer

phylroy's ruling (2026-07-28): "do it and record the decision" on the
min-wins recommendation. The reference building's hydronic pump power is
set by the 8.4.4.14.(1)-(3) proposed-intensity transfer AND then clamped
at the Table 5.2.6.3 maximum — 8.4.4.1.(2) makes Part 5 prescriptive a
CEILING the reference may never pierce. min-wins is the only reading
satisfying both articles simultaneously, and it closes the perverse
incentive where wasteful proposed pumping inflates its own target.

Values verified against the printed 2020 AND 2025 tables [READ, MCP,
identical]: Heating 4.5 / Cooling 14 / Heat rejection 12 / Water-source
heat pump 22 W_motorpower per kW_thermalpeak (combined pump motors per
hydronic system, vs the loop's peak thermal demand at design).

Implementation (openstudio-hvac efficiency pass): after the per-pump
transfer, apply_pump_power_cap clamps each loop's COMBINED pump power;
thermal peak by loop role — Heating from boiler capacities, Cooling from
chiller reference capacities, Heat rejection from the served chillers'
cap x (1+1/COP) (same arithmetic as the D-26 tower rule), WSHP row when
the loop hosts water-to-air HP coils (from their rated cooling
capacities). Clamps keep the flow/head/power triple physical (the D-27
guard) so E+ never sees >100% pump efficiency. Unsized thermal peak or
pump power -> audited 'not evaluable' info, never a silent skip; within-
cap loops audit their compliance. Caps vendored in reference_rules_
{2020,2025}.json under hydronic_pumps.power_caps_w_per_kw. Applies with
or without a proposed model — the ceiling binds the reference regardless.
Note: legacy applies ONLY the 5.2.6.3 caps and lacks 8.4.4.14 (L-17,
#2129); we now implement both, reconciled.

- Who/when: ruling phylroy 2026-07-28; implementation Claude under D-10.
- Evidence: [READ, MCP] 5.2.6.3 + Table (2020/2025); [RAN] pump-rules
  12/12 (clamp + min-wins pins), efficiency suite, necb:verify orphan-key
  lint OK, gas Warehouse annual sweep with the cap live.

## D-39 — A4 adjudicated (phylroy): System 5 heating "None" honoured conditionally per 8.4.4.1.(5)

phylroy's ruling (2026-07-28): "do 3 and document it" — the conditional
reconciliation. Table 8.4.4.7.-B lists System 5 (two-pipe fan-coil,
water-cooled chiller) with heating "None" [READ, MCP — row re-verified];
8.4.4.1.(5) requires heating PRESENCE per thermal block to be identical
to the proposed. Reconciliation (same shape as D-38's min-wins): the
table's "None" governs the default composition — a COOLED-BUT-UNHEATED
proposed block (the refrigerated-space case System 5 exists for) gets a
cooling-only TPFC reference; when the proposed block IS heated, sentence
(5) overrides presence and the existing two-pipe changeover heating is
kept (no baseboard variant invented — the table describes none). Both
branches audited with both articles. A block with NO conditioning at all
gets no reference system (existing 8.4.4.1.(5) behavior — that case is
absence, not "None").

Implementation: FanCoils builder gains config 'heating' => 'none'
(no hot-water loop, no MAU heating coil, zone fan coils carry a
zero-capacity always-off placeholder electric coil — the FourPipeFanCoil
object requires one); finalize merges that config for System 5
assignments whose group is unheated. The prior always-heat behavior was
deliberate legacy parity (legacy builds sys 5 with the sys 2 machinery,
heating included) — that parity is now intentionally broken for the
unheated case, in the code-literal direction.

Pins: selector (unheated -> 'heating'='none' config; heated -> override
audited), reference build (cooling-only: no boiler, no hydronic heating
coils, placeholder at 0 W; heated: boiler present), and two pipeline
mockups — sys5_refrigerated (heated fixture, presence-override decision)
+ NEW sys5_unheated (hand-built DX-only proposed; cooling-only TPFC
through E+ sizing). 10/10 mockups, fan-coils suite, selector 25,
reference 10 all green.

- Who/when: ruling phylroy 2026-07-28; implementation Claude under D-10.
- Evidence: [READ, MCP] Table 8.4.4.7.-B System 5 row; [RAN] batteries.

## D-40 — A5 adjudicated (phylroy): reheat-coil autosizing trusted; legacy hard-size workaround rejected

phylroy's ruling (2026-07-28, after reviewing the measurement): no-change
— reference VAV reheat coils stay AUTOSIZED. The legacy workaround
(hvac_systems.rb:2446: cap = 1.2 x 1000 x min_flow_fraction x
max_air_flow x (43-13), hard-set on electric and hot-water reheat coils)
is NOT adopted.

Evidence [RAN — sized LargeOffice reference, 20 terminals]: autosized
capacities range 0.11x to 3.15x the legacy formula — it misses in BOTH
directions because it is geometry-based and load-blind. The premise
mismatch is structural: legacy's cap assumes reheat at MINIMUM airflow
(coherent with legacy's own L-9 68%-floor config); our terminals carry
the D-22 maximumFlowFractionDuringReheat=0.5, so coils the formula calls
2-3x oversized are correctly sized for the 50%-flow reheat they actually
deliver (term 12: 17.4 kW vs a 31.7 kW deliverable ceiling). Adopting
would undersize those (unmet-hours risk), inflate the load-sized ones
3-9x (feeding boiler plant sizing and loosening the D-38 pump cap
basis), disable 8.4.1.2.(5) capacity auto-iteration on reheat
(hard-sized equipment ignores sizing factors), and rests on no code
text. The legacy 1000 J/(m3.K) constant is also ~17% under the physical
rho.cp (~1206), making the nominal 1.2 margin ~1.0 net.

Regression net: the sys-6 E+ e2e conditioning asserts (January-week
zones-conditioned checks) stand as the guard; if a sys-6 fixed-point
residual ever traces to reheat sizing, reopen with data via the ledger.

- Who/when: ruling phylroy 2026-07-28; analysis Claude under D-10.
- Evidence: [READ] legacy hvac_systems.rb:2442-2456; [RAN] ComponentSizes
  join on the sized LargeOffice reference (table in the conversation
  record); no code change.

## D-41 — 8.4.4.20.(3)-(4) machine-verified (appendix-era ingestion); SWH reference gap refined

The SHW manifest's oldest caveat — "sentence text falls in a PDF-extraction
chunk gap; not machine-verified" — is closed: the full 8.4.4.20 article
(sentences (1)-(9)) and Note A-8.4.4.20.(4)(a) now retrieve cleanly via
the MCP [READ, 2026-07-28]. Verification outcome: the umbrella's
clone-based treatment SATISFIES (3) (boiler-fed immersion coil keeps the
boiler's energy type), (4) (identical capacities/schedules trivially
match the ratio + operational requirements; the note only describes how
to determine the ratio), and (6)/(7)/(8). The manifest gap is REFINED to
the two genuinely unimplemented sentences: (5) 8.4.5 part-load curves on
reference SWH equipment, and (9) consolidation of multiple proposed
circulation pumps into one constant-speed pump (clone keeps identical
W/(L/s) — energy-equivalent, topology differs). No code change; both
refinements queued behind the staged-heating work in the completion list.

- Who/when: Claude under D-10 delegation, 2026-07-28.
- Evidence: [READ, MCP] 8.4.4.20 + A-8.4.4.20.(4)(a); [READ] shw
  reference.rb (no pump/part-load handling — confirming the refined gaps).

## D-42 — First FULL-ANNUAL fleet sweep (8760 h): reference generation validated; verdicts expose a proposed-side archetype character

First code-compliant-duration sweep (SWEEP_MODE=full, 15 archetypes,
Toronto/electric, D-32..D-41 all in effect). Energy fixed point
(% of target = proposed/reference):

| building | week% | annual% | shift | compliant |
|---|---|---|---|---|
| QuickServiceRestaurant | 92 | 89 | -3 | no |
| SmallOffice | 88 | 89 | +1 | no |
| FullServiceRestaurant | 95 | 91 | -4 | no |
| SmallHotel | 92 | 91 | -1 | no |
| LargeHotel | 90 | 92 | +2 | YES |
| PrimarySchool | 95 | 94 | -1 | YES |
| RetailStripmall | 89 | 97 | +8 | YES |
| Warehouse | 103 | 97 | -6 | no |
| HighriseApartment | 99 | 98 | -1 | no |
| LowriseApartment | 96 | 98 | +2 | no |
| RetailStandalone | 101 | 98 | -3 | no |
| SecondarySchool | 97 | 98 | +1 | YES |
| MidriseApartment | 97 | 99 | +2 | no |
| MediumOffice | 110 | 111 | +1 | no |
| LargeOffice | 110 | 113 | +3 | no |

Findings:
1. **Energy: 13/15 within 89-99%; median ~97-98.** The heating-dominated
   week-run residuals compressed as predicted (Warehouse 103->97,
   Stripmall 89->97); the office fan gap persisted year-round (111/113 —
   consistent with the #2127 legacy-fan attribution, fans run all year).
   SmallOffice did NOT compress (88->89): its ~11% gap is structural, not
   seasonal — the remaining unexplained tail item. Restaurant/hotel gaps
   deepened slightly with summer in scope (89-91).
2. **Reference conditioning is sound through a full year: unmet HEATING
   ~0 h fleet-wide** (max 85.75 h reference SmallHotel, under the 100 h
   limit everywhere else ~0).
3. **The compliant=false wave is 8.4.1.2.(4) unmet COOLING, proposed
   side.** The reference consistently right-sizes cooling (fewer unmet
   hours); the legacy proposed's HARD-SIZED cooling runs 1.2-5x the
   reference's unmet hours (e.g. SmallOffice 261 vs 217, LowriseApt 528
   vs 95, SmallHotel 2756 vs 691), violating the within-+10% criterion.
   Sentence (5) iteration fired, bumped the proposed cooling sizing
   factor, and STALLED — hard-sized legacy equipment ignores sizing
   factors (the documented trap, detected loudly). 4/15 archetypes pass
   outright. Verdict: the reference pipeline behaved correctly end to
   end; the non-compliances are a measured CHARACTERISTIC of the legacy
   archetypes under full-annual scrutiny — ledgered as L-23.
4. Offices additionally fail sentence (2) on energy (111/113% > 100%),
   as the fan attribution predicts.

- Who/when: Claude under D-10 delegation, 2026-07-28 (sweep requested by
  phylroy: "do a full annual sweep").
- Evidence: [RAN] 15 full-annual pipeline runs (30 annual E+ simulations
  + sizing runs, all PASS); report.json capacity_iterations/unmet blocks;
  week-run baselines from the cached fleet.

## D-43 — 8.4.1.2.(5) capacity iteration made per-thermal-block, secant-targeted from run history

- Decision: the sentence-(5) capacity auto-iteration no longer bumps only the
  failing building's GLOBAL SizingParameters factors. Each round now reads the
  previous annual run's PER-ZONE 'Time Setpoint Not Met During Occupied' hours
  (SystemSummary — new `Runner.zone_unmet_occupied_hours`, openstudio-simulation)
  and raises Sizing:Zone heating/cooling factors on the failing thermal blocks
  only: heating on zones > 100 h in a building whose sentence-(3) gate failed;
  cooling (proposed only) on zones exceeding the SAME zone of the reference
  clone plus the vintage allowance (+10%; 2025: max(+10%, 20 h)). The first
  bump per zone/metric is geometric (`capacity_step`); later bumps are SECANT
  extrapolations from that zone's own (factor, unmet-hours) history, aimed at
  0.9x the applicable limit and clamped to max(step, 2)x growth per round so
  the increase stays "incremental" as the sentence is worded.
- Why: (a) sentences (3)/(4) are written "for each thermal block" — per-zone
  targeting is the code-literal resolution, and the global bump over-grew every
  system in the building to fix one zone; (b) the previous run already contains
  the attribution and the slope, so informed steps converge in fewer full-annual
  E+ runs (the expensive unit); requested by phylroy 2026-07-28 after the D-42
  discussion ("could the previous run inform the next run on the sizing scaling
  required per thermoblock?").
- Fallbacks (both audited with `mode` in the decision inputs): 'global' when
  per-zone data is absent entirely; 'mixed' when a failing gate has NO single
  failing zone — facility unmet hours are a UNION over zones, not a sum, so a
  building can fail sentence (3) with every zone under 100 h; that gate gets
  the global bump alongside the zonal ones. Zone factors OVERRIDE the global
  factor (E+ semantics), so the modes compose without double-scaling.
- Unchanged: reference cooling is still never bumped (enlarging reference
  cooling shrinks the sentence-(4) allowance — cannot be what (5) intends,
  per D-42); stall detection still stops the loop when a bump yields < 1 h
  improvement (hard-sized equipment responds to neither zonal nor global
  factors — the L-23 characteristic is unaffected).
- Evidence: [RAN] SizingZone per-zone factor API probe; [RAN] unit tests
  (secant/clamp/fallback arithmetic; zonal/global/mixed targeting on in-memory
  models); [RAN] test_capacity_iteration_converges_undersized_building — the
  undersized 4-week fixture now converges through 'zonal' mode with Sizing:Zone
  factors set on the failing zones and the global factor untouched.
- Files: openstudio-simulation runner.rb (+ test_local_run.rb per-zone
  assertions), openstudio-necb compliance.rb (iterate_capacities,
  bump_capacities, failing_zone_targets, next_sizing_factor; run_annual stores
  zone_unmet_occupied_hours), test_compliance.rb, necb_rules_{2020,2025}.json
  8.4.1.2 how-text, umbrella CLAUDE.md.
- Who/when: Claude under D-10 delegation, 2026-07-28 (implementation requested
  by phylroy: "implement it — per-zone targeting plus the secant step").

## D-44 — Decisions surfaced at RUNTIME: `ruling:` audit tags, a registry, and a report appendix

- **What:** the 43 decisions in this file governed pipeline behaviour but were
  invisible to anyone running it — the *why* lived only in docs a user of the
  gems has no reason to know exists. Audit entries now carry an optional
  `ruling:` tag citing decision ids alongside the existing `article:` citation,
  and the AHJ report grows an appendix naming every decision that actually
  fired in the run, with a self-contained explanation of each.
- **Why:** phylroy, 2026-07-28: *"bake some of this into the code… reported in
  the logs"*. `article:` answers "what does the code require"; `ruling:` answers
  "why did we read it that way" — the second axis a reviewer needs and could
  previously only get by reading this file.
- **Design:**
  - `ruling:` is an optional TOP-LEVEL kwarg on `AuditLog#decision/#info/#warn`
    (never inside `inputs:`), threaded through the private `add`. `.compact`
    drops it when nil, so untagged entries are byte-identical to before.
    `to_s` appends `" | ruling D-XX"` AFTER the `" | per <article>"` segment;
    `to_json` needed no change. Applied identically to all six copies.
  - Multi-ruling sites use ONE space-separated string (`ruling: 'D-19 D-21'`),
    mirroring the joined-articles convention; every consumer parses with
    `Decisions.ids_in` (`/\bD-\d{2}\b/`). Literals always sit on one line —
    the drift grep depends on it.
  - `data/decisions.json` + `OpenStudioNECB::Decisions` (the `Tiers` loader
    pattern): all entries as `{id, title, kind, summary, articles}`.
    `kind` is `runtime` (a `ruling:`-tagged call site exists) /
    `runtime_unwired` (runtime behaviour, nothing tagged yet — D-09, D-18,
    D-25, D-36, D-45) / `data` (manifest or vendored-data only — D-03, D-12,
    D-41) / `process` (how the project works). Summaries are 2-3 self-contained
    sentences, paraphrased, no external links: the report is one file and cites
    nothing outside itself, so the summary IS the documentation.
  - Report: `rulings_appendix` between the coverage and audit appendices, with
    an unconditional TOC link — ALWAYS rendered (placeholder when nothing
    fired) because the html test asserts every href resolves. One row per fired
    decision: id, title, summary, fire count, anchor to the first firing audit
    entry. An unregistered id renders "not in registry" rather than crashing.
  - Coverage-emitter entries (`step: :coverage`) are deliberately NOT tagged —
    they are manifest boilerplate and would swamp the appendix fire counts.
    This is why D-09 is `runtime_unwired` rather than `runtime`.
- **Scope:** 61 `ruling:` tags across 24 decisions, in
  `openstudio-hvac/.../necb/{reference,efficiency}.rb`,
  `openstudio-envelope/.../necb/{prescriptive,reference}.rb`,
  `openstudio-necb/{compliance,archetypes}.rb`. No message text, article,
  input or determination behaviour changed anywhere — this is reporting only.
- **Drift guards** (`test/test_decisions_registry.rb`): headings == registry
  ids; every cited id resolves; every `kind: runtime` entry is cited; nothing
  non-runtime is cited; literals are one-line and well-formed; `ruling:` never
  nested in `inputs:`; and the six `audit_log.rb` copies are byte-identical
  modulo their module line.
- **Also flattened** (phylroy's "this is confusing" feedback): the A and T
  registers of the 2026-07-25 audit are drained — A6 moves here as D-45, that
  file is banner-marked archived evidence, and `docs/README.md` now states
  which registers are live.
- **Files:** 6x `audit_log.rb`; the six tagged source files;
  `lib/openstudio_necb/decisions.rb` + `data/decisions.json`;
  `report/sections.rb`; `docs/{necb_decisions,README,audit_2026-07-25_reference_systems}.md`;
  CLAUDE.md (necb + hvac); tests `test_decisions_registry.rb` (new),
  `openstudio-hvac/test/test_audit_log.rb` (new), `test_report_units.rb`,
  `test_compliance.rb`.
- **Who/when:** Claude under D-10 delegation, 2026-07-28.

## D-45 — Museum exhibition galleries: which Table 8.4.4.7.-A row? (OPEN — pending phylroy ruling)

- **The question (was A6 on the 2026-07-25 audit list, moved here by D-44):**
  a space named for a museum's general exhibition area selects the Assembly
  Area category via the 'exhibit' keyword rather than Historical Collections
  via 'museum' — a keyword-ORDER collision in the category matcher, found by
  the D-33 variant mockups. Which Table 8.4.4.7.-A row should museum
  exhibition galleries take?
- **Why it is genuinely ambiguous:** the printed row wording supports either
  reading — a gallery is both an assembly space and a collections space, and
  the two rows can select different reference systems. This is an
  interpretation call, not a defect.
- **Current behaviour (unchanged, untagged):** first keyword wins, so
  'exhibit' -> Assembly Area. The D-33 mockup sidesteps it by using a
  'Museum restoration room' space type, so no test depends on the collision
  either way.
- **Status:** OPEN, awaiting phylroy. Registered `runtime_unwired` — when it
  is ruled, tag the selection call site with `ruling: 'D-45'` and flip the
  registry entry to `runtime`.
- **Who/when:** raised Claude under D-10 (2026-07-27, D-33); re-filed here
  2026-07-28 under D-44's register flattening.

## D-46 — Staged heating and cooling built as unitary multispeed coils; stage COUNT set post-sizing, capacities left autosized

**What.** NECB 8.4.4.9.(7) and 8.4.4.10.(8) (2025: 8.4.5.9.(7)/8.4.5.10.(8))
require the reference building's furnaces and DX systems to be modelled as
equal stages — two of them at or below the 66 kW threshold, `ceil(kW/66)`
above it. The vendored `furnace_staging`/`dx_staging` blocks carried those
numbers since 2026-07-12 but nothing read them. They are now consumed:

- **Topology.** Reference systems 3 and 4 (and the Table 8.4.4.13 ASHP) build
  as an `AirLoopHVACUnitarySystem` holding the supply fan, a
  `CoilCoolingDXMultiSpeed`, and a `CoilHeatingGasMultiStage` (gas) /
  `CoilHeatingDXMultiSpeed` (ASHP) / plain `CoilHeatingElectric` (electric,
  see D-49). A multispeed coil cannot sit bare on an air loop — `addToNode`
  returns false — so the container is mandatory, not a style choice.
  Controls mirror the legacy multi-speed sys-3 build: `Load` control on the
  elected control zone, always-on fan schedule, and the
  `SetpointManagerSingleZoneReheat` left on the loop outlet.
- **Flag-gated.** The builder branches on a `staged_coils` config key set ONLY
  by the reference ruleset's `system_definitions`. Catalog defaults, proposed
  models and CBECS builds keep today's bare single-speed topology and their
  pins stay green.
- **Stage COUNT post-sizing, capacities AUTOSIZED.** The efficiency pass's new
  `apply_staging` reads the sized TOP-stage capacity (which IS the unit total —
  EnergyPlus stages are cumulative, not additive), computes N, adds/removes
  stages, re-autosizes every stage, and rewrites the
  `UnitarySystemPerformanceMultispeed` flow ratios to k/N. **Capacities are
  never hard-set.** That is what keeps 8.4.1.2.(5) capacity auto-iteration
  (D-43) responsive — the L-23 lesson. Heating and cooling stage counts are
  independent; the SDK writes each mode's speed count from its own coil.
- **Efficiencies bin by TOP stage.** `apply_dx_cooling_multi` /
  `apply_dx_heating_multi` / `apply_gas_multi` look the row up against the same
  `unitary_acs` / `heat_pumps` / `furnaces` tables using the total capacity and
  write that row's COP/burner efficiency and curves to EVERY stage — what the
  legacy multispeed applier does, and correct because those are unit-capacity
  tables, not per-stage tables.

**Why this shape.** Alternatives were rejected: hard-sizing stage capacities to
kW/N defeats capacity iteration and the D-40 autosizing ruling; leaving the
coils bare is impossible in the SDK; per-stage table lookups would invent a
binning the tables do not define.

**Evidence [RAN — four Phase-0 mockup gates, OpenStudio 3.11 / EnergyPlus 25.2,
5ZoneNoHVAC + Toronto CWEC2020]:**

1. A 2-stage autosized unitary PSZ sizes stage 1 at exactly 0.5000 of stage 2,
   cooling and heating alike (29 542 / 59 085 W and 50 821 / 101 641 W).
2. Bare-vs-unitary: DX cooling matches within 0.03% (59 066 vs 59 085 W) and
   supply flow is identical, but the **heating coil sizes 2.22x larger**
   (45 781 W bare vs 101 641 W in the unitary). This is a structural EnergyPlus
   sizing-path difference, not a modelling error: the unitary sizes its heating
   coil on the FULL design supply air flow from the design heating mixed-air
   temperature to the central heating supply temperature, while a bare air-loop
   coil sizes on the heating-day ideal-loads peak flow (0.92 of 3.06 m3/s).
   Probed and confirmed invariant under MaximumSupplyAirTemperature (set,
   autosized, and default), fan placement, and Load-vs-SetPoint control. The
   reference furnace therefore gets LARGER and can land in a different
   Table 5.2.12.1 capacity bin — a real fleet-wide change that the week-run
   sweep must attribute.
3. Post-sizing 2 -> 3 stages -> re-size gives exact 1/3, 2/3, 1 ratios on both
   coils; going back to 2 stages reproduces the original capacities bit for bit.
4. EnergyPlus accepts the gas multistage + performance object: 2-stage gas and
   electric January week runs complete with zero severe errors. (A synthetic
   4-stage run on the same small fixture raised warmup-convergence severes; the
   staging rule would never produce four stages at that capacity.)

**Design deviation, logged:** the reference ASHP's supplemental coil is placed
on the air LOOP downstream of the unitary rather than in the unitary's
supplemental slot. EnergyPlus sizes a unitary's supplemental heater equal to
the heat-pump capacity, which measured 26% short on a catalog build (71.8 kW vs
97.2 kW) and about 70% short on a reference build (15.2 kW vs the loop-sized
coil) — below the -10 degC compressor cutoff that failed the cold-week
conditioning gate at 84 unmet occupied heating hours against a 24 h limit. On
the loop the coil sizes on the loop's heating design and is driven by the outlet
setpoint manager (the legacy arrangement); the same week run then reports 1.75
unmet hours. No capacity was hard-set to achieve this.

**Re-validation owed:** the sys 3/4 topology change alters every archetype
fingerprint, so the D-42 full-annual fleet claim does NOT carry over. The
15-archetype week-run sweep is the gate before any fresh energy claim.

- **Files:** `openstudio-hvac/lib/openstudio_hvac/{components/coils.rb,
  systems/psz.rb, necb/efficiency.rb, necb/reference.rb, necb/checker.rb,
  classify.rb, catalog_icons.rb, catalog_report.rb, costing/ventilation.rb,
  data/necb/reference_rules_{2020,2025}.json}`;
  `openstudio-necb/{lib/openstudio_necb/report/model_query.rb,
  scripts/necb_fixed_point_diff.rb}`; tests `test_necb_staging.rb` (new),
  `test_necb_reference.rb`, `test_necb_e2e_run.rb`.
- **Who/when:** Claude under D-10 delegation, 2026-07-29.

### D-46 amendment (2026-07-29, review): the staged unitary was bypassing D-14 and running its fan 8760 h

Caught by the week-run sweep gate, not by any unit test. A fan inside an
`AirLoopHVACUnitarySystem` is NOT governed by the air loop's availability
schedule — the unitary carries its OWN. The first staged build left that at
its always-on default, so every staged reference fan ran continuously all
year, silently overriding the operating schedule D-14 inherits from the
proposed building.

MEASURED on the Warehouse (January week): reference fan energy 4 642 kWh
against the proposed's 1 733 (2.68x). The same building before staging:
0.98x. Fleet effect: every PSZ archetype fell 7-9 percentage points of
percent-of-target (Warehouse 103 -> 94, SecondarySchool 97 -> 88,
SmallOffice 88 -> 81, PrimarySchool 95 -> 88, RetailStandalone 101 -> 94) —
i.e. the reference got MORE permissive, the dangerous direction for a
compliance target, and for a reason with no basis in the code.

Fix: the unitary's AVAILABILITY schedule follows the loop's — at build time,
and again in `apply_operating_schedules` (the D-14 owner, which now propagates
into unitaries via `apply_unitary_operating_schedule`). The fan OPERATING MODE
stays continuous, as a constant-volume system's is; an intermediate attempt to
put the inherited schedule in that field instead was rejected by EnergyPlus
outright ("schedule contains values that are <= 0"), which fataled every PSZ
reference sizing run until corrected. Post-fix Warehouse fan ratio: 0.88, with
zero unmet hours on both sides — the night-cycle pickup concern did not
materialize.

Lesson for future topology work: wrapping equipment in a container silently
re-homes every schedule, setpoint and sizing path that used to reach it. The
unit tests all passed both before and after this fix — only the fleet sweep
saw it, which is why the sweep is a merge gate and not a formality.

### D-46 amendment (2026-07-29): staged airflow investigated — my "constant-volume" defect claim RETRACTED; a ventilation floor added instead

The full-annual sweep attributed almost all of staging's fleet gain to
reference FAN energy, not coil efficiency: PSZ references fell 21-36% on fans
(SmallOffice -36%, Warehouse -27%, SecondarySchool -23%) against 1-5% on
heating. LargeOffice (system 6, no PSZ) is bit-identical end-use for end-use —
a clean control confirming the change touches exactly what staging touches.
Cause: `set_stage_flow_ratios` writes ratio k/N per stage, so stage 1 runs the
fan at 1/N of design flow (verified in the built IDF).

I first called this a DEFECT, reasoning that Table 8.4.4.7.-B gives systems
1-5 "Constant-volume" fan control and the staging sentences stage capacity,
not airflow. **That claim is RETRACTED — it was a false premise** (the fifth
of this project; the standing rule is to run the refuting check BEFORE calling
anything a defect, and here the refutation was one IDD lookup away):

- [READ] The EnergyPlus IDD requires each speed's Rated Air Flow Rate to be
  0.00004027-0.00006041 m3/s **per watt of THAT speed's capacity**. Holding
  flow constant while staging capacity puts stage 1 of a two-stage coil at
  ~2x the legal ratio. Constant airflow with staged capacity is not
  modelable in `Coil:Cooling:DX:MultiSpeed` at all — the airflow MUST track
  the staged capacity.
- [READ] Legacy does the same: its multi-speed builder sets per-speed supply
  air flow rates rather than holding them constant.
- So "Constant-volume" in the table describes the DISTRIBUTION system (no VAV
  terminals, no zone-level flow modulation), not a fan locked to one speed. A
  staged DX unit is inherently a multi-speed-fan machine, and the fan savings
  are a real consequence of the staging the code requires.

What the investigation DID find is narrower and real: legacy floors low-speed
flow at the minimum outdoor-air rate, and we did not. Stage 1 at 1/N of design
flow can fall below the ventilation air the system exists to deliver. Fixed:
`set_stage_flow_ratios(unitary, min_ratio:)` floors every ratio, and
`apply_stage_flow_ratios` passes the sized minimum-OA fraction, auditing the
floor whenever it binds. Pinned by
test_stage_flow_ratios_are_floored_at_the_outdoor_air_fraction.

Net effect on the fleet: the floor binds only on high-OA units, so most PSZ
numbers stand; the 2026-07-29 full-annual results are re-run below.

## D-47 — Stage count CLAMPED at the EnergyPlus four-stage ceiling, with a shouted warning on every clamp

**What.** `Coil:Cooling:DX:MultiSpeed`, `Coil:Heating:DX:MultiSpeed` and
`Coil:Heating:Gas:MultiStage` structurally cap at four stages — the SDK's fifth
`addStage` silently returns false (probe-verified). Above 264 kW the staging
rule asks for five or more equal stages, which EnergyPlus cannot represent. The
count is clamped at four and the audit entry is a SHOUTED warning naming the
required count, the sized capacity and the ceiling, so a fleet sweep enumerates
the real cases rather than hiding them.

**Why not something else.** Splitting the load across two parallel unitary
systems would change the reference TOPOLOGY (and its fan count, economizer
trigger and costing) to work around a tool limit; refusing to build would break
determination for large systems. A clamped count with larger-than-code stage
increments is the honest approximation, and the warning makes it visible in
the report checklist.

- **Files:** `openstudio-hvac/lib/openstudio_hvac/necb/efficiency.rb`
  (`MAX_STAGES`, `stage_multispeed_coil`).
- **Evidence:** [RAN] SDK probe — the fifth `addStage` returns false on both the
  cooling and the gas coil while the object keeps four stages.
- **Who/when:** Claude under D-10 delegation, 2026-07-29.

## D-48 — Staging scope is AIR-LOOP unitary equipment; zone terminals and make-up-air tempering coils stay single-speed

**What.** 8.4.4.9.(7)/8.4.4.10.(8) staging is applied to air-loop unitary
equipment only. Packaged terminal units (PTAC/PTHP) keep single-speed coils:
the OpenStudio SDK will accept a multispeed coil there, but the EnergyPlus IDD
restricts the terminal's coil choices and the model would die at forward
translation. Make-up-air tempering DX (reference systems 1, 2 and 5) also stays
single-speed — those coils temper a ventilation stream rather than being the
staged unitary equipment the sentences describe.

**How it is audited.** The skips are reported as info entries grouped BY REASON
(one entry per reason with the coil count and the first few names) rather than
one entry per coil. A deliberate deviation from per-skip auditing: a MURB or
hotel reference carries hundreds of identical packaged terminals, and per-coil
entries would swamp the report's audit appendix without adding information.

- **Files:** `openstudio-hvac/lib/openstudio_hvac/necb/efficiency.rb`
  (`audit_staging_skips`).
- **Who/when:** Claude under D-10 delegation, 2026-07-29.

## D-49 — Electric resistance heating is not a furnace: 8.4.4.9.(7) staging is not applied to it

**What.** The staging sentence governs furnaces. An electric-resistance heating
coil is not a furnace — it has no burner, no combustion staging, and its
part-load behaviour is linear, so splitting it into equal stages would change
nothing physical while adding objects and a false claim of compliance
machinery. Electric-heated reference systems 3 and 4 therefore build the staged
multispeed DX COOLING coil (8.4.4.10.(8) does bind) paired with a plain
single-stage `CoilHeatingElectric` inside the same unitary.

**Consequence.** The heating side of an electric sys 3/4 reference is
unchanged by this work apart from its move inside the unitary container (which
does change how EnergyPlus sizes it — see the D-46 measurement).

- **Files:** `openstudio-hvac/lib/openstudio_hvac/systems/psz.rb`.
- **Who/when:** Claude under D-10 delegation, 2026-07-29.

## D-50 — Terminal/secondary capacity split realized as Sizing:Zone dedicated-outdoor-air accounting

**What.** 8.4.4.9.(3) and 8.4.4.10.(7) (2025: 8.4.5.9.(3)/8.4.5.10.(7)) say
that where the selection table puts heating (or cooling) in BOTH a zone
terminal and a secondary system, the terminal covers the space loads and the
combined pair covers the peak. Reference systems 1, 2 and 5 are exactly that
shape (PTAC / four-pipe / two-pipe fan coil plus a make-up-air unit), and
EnergyPlus expresses the accounting directly: `Sizing:Zone` dedicated-outdoor-
air accounting with a NEUTRAL supply-air strategy makes the ventilation stream
neither add nor remove zone load, so the terminal's design load is the
envelope-and-internal load alone while the make-up-air unit carries ventilation
at system level. The combined pair still meets the peak because both are sized
on the same design day.

**Approximations declared, not assumed.** (a) The setpoint pair is 20.0/20.1
degC — EnergyPlus rejects a low setpoint that is not strictly below the high
one, and 20 degC is the make-up-air unit's own neutral supply temperature for
system 1. For systems 2 and 5 the unit actually supplies about 13 degC, so
using a neutral setpoint for SIZING is a deliberate reading of the split rather
than a description of operation; it is also the only one EnergyPlus solves
cleanly (a 13 degC setpoint made the fan-coil chilled-water coil's design UA
solve fail). (b) Reference systems 3, 4, 6 and the ASHP mix outdoor air into
the supply stream instead of feeding the zone separately, so they have no
equivalent accounting: their split is approximated by ordinary mixed-air zone
sizing with baseboards taking the residual, and every such group gets an audit
entry saying so.

**Evidence [RAN — sized 5ZoneNoHVAC mockups, Toronto CWEC2020]:** turning the
accounting on moves the summed zone design loads by +1.3% heating and -8.6%
cooling on systems 1, 2 and 5 alike, with no new EnergyPlus severe errors. The
13 degC variant produced a severe ("Calculation of cooling coil design UA
failed") on the four-pipe fan coil and was rejected on that basis.

- **Files:** `openstudio-hvac/lib/openstudio_hvac/{data/sizing.json,
  systems/base_system.rb, necb/reference.rb}`.
- **Who/when:** Claude under D-10 delegation, 2026-07-29.

### D-46 sweep gate (2026-07-29): fleet re-validated; staging TIGHTENS the reference

Week-run sweep, 15/15 PASS, after both review fixes. Percent-of-target moved
UP everywhere versus the D-42 week baseline — the reference building now
consumes LESS, because staged equipment runs at better part-load efficiency
than the single-speed coils it replaced. That is the direction the code
intends: the reference is REQUIRED to be staged, so the target it sets is
genuinely harder to beat.

| Building | D-42 | now | Building | D-42 | now |
|---|---|---|---|---|---|
| RetailStripmall | 89 | **104** | LargeHotel | 90 | 92 |
| SecondarySchool | 97 | **103** | PrimarySchool | 95 | 97 |
| Warehouse | 103 | **107** | LowriseApartment | 96 | 98 |
| RetailStandalone | 101 | **105** | MidriseApartment | 97 | 99 |
| SmallOffice | 88 | 91 | MediumOffice | 110 | 112 |
| LargeOffice | 110 | 113 | HighriseApartment | 99 | 99 |
| SmallHotel | 92 | 92 | FullServiceRestaurant | 95 | 95 |
| QuickServiceRestaurant | 92 | 92 | | | |

Consequence to note: four legacy archetypes cross 100% and now fail sentence
(2) that previously passed (Warehouse, RetailStandalone, RetailStripmall,
SecondarySchool). Nothing about the PROPOSED side changed — they fail because
the reference got more efficient. The gain scales with how part-loaded the
systems are, which is why RetailStripmall (ten small PSZ units) moves most
(+15) and the hydronic/MURB archetypes barely move.

The D-42 FULL-ANNUAL numbers are superseded and have NOT been re-run — the
full-annual claim is owed a fresh sweep before it is quoted again.

### D-46 FINAL full-annual sweep (2026-07-29, post-staging + ventilation floor)

True 8760 h, all 15 archetypes, 15/15 PASS. This supersedes D-42's
full-annual table, which predates staging.

| Building | D-42 | final | | Building | D-42 | final |
|---|---|---|---|---|---|---|
| SmallOffice | 89 | **98.0** | | FullServiceRestaurant | 91 | 95.3 |
| Warehouse | 97 | **104.6** | | LargeHotel | 92 | 93.2 |
| RetailStandalone | 98 | **104.9** | | QuickServiceRestaurant | 89 | 93.9 |
| RetailStripmall | 97 | **103.8** | | MidriseApartment | 99 | 100.1 |
| SecondarySchool | 98 | **102.9** | | HighriseApartment | 98 | 99.4 |
| PrimarySchool | 93 | 98.5 | | LowriseApartment | 98 | 99.0 |
| SmallHotel | 91 | 95.6 | | MediumOffice | 111 | 113.9 |
| | | | | LargeOffice | 113 | 113.3 |

5/15 compliant (was 4/15). Every building moved UP: the reference is more
efficient once its DX/furnace equipment is staged, so the target is stricter.

**D-42's last open residual is CLOSED.** SmallOffice's ~11% gap, which D-42
proved was structural rather than seasonal and left unexplained, was the
missing staging: 89 -> 98.0. SmallOffice is almost entirely PSZ, the most
staging-sensitive archetype in the fleet.

Ventilation floor: bound on 43 units across 7 buildings (SecondarySchool 28,
PrimarySchool 7, SmallHotel 3, RetailStandalone 2, and one each in the
restaurants and LargeHotel), several at an outdoor-air fraction of 1.00 —
100%-OA make-up air units that would otherwise have staged down to half flow
while owing full ventilation. Energy effect is small (+0.00% to +0.41% on the
reference total, largest on FullServiceRestaurant); the correctness is the
point.

Unchanged and still owed: the offices sit at 113-114% on the legacy fan
attribution (#2127, L-9/L-10), untouched by staging because system 6 is
hydronic — LargeOffice is bit-identical end-use for end-use across the whole
staging change, which is the cleanest available control that staging touches
only what it should.
