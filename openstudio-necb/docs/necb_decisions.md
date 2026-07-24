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
