# NECB gem family — decision record

Adjudicated interpretations and product decisions for the `openstudio-*` NECB
gem family. Machine-checkable coverage lives elsewhere — article dispositions in
`scripts/necb_8_4_disposition.json`, per-gem `article_coverage` manifests, the
generated `NECB_8_4_COVERAGE.html`, and the evidence rules in
`docs/necb_rule_verification.md`. **This file records the judgement calls**: the
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
- **Evidence:** `scripts/necb_8_4_6_curve_probe.rb`
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
- **Evidence:** `scripts/necb_8_4_6_curve_probe.rb` (tower section, in
  `rake necb:verify`); `scripts/necb_8_4_disposition.json` 8.4.6.6.

## D-08 — Batch sign-off of the remaining 19 article dispositions

- **Decision:** all 19 remaining draft dispositions in
  `scripts/necb_8_4_disposition.json` signed off in four groups:
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
- **Evidence:** `scripts/necb_8_4_disposition.json` (no `draft` entries
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

---

*Pending adjudication (not yet decisions): pump power 8.4.4.14 and per-object
oversizing limits; the D-06 fan-availability open item.*
