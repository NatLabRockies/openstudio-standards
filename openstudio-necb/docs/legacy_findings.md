# Legacy openstudio-standards — findings ledger

Differences and defects found in the legacy NECB implementation
(NatLabRockies/openstudio-standards, formerly NREL) during the gem-family
cross-validation. One row per finding, with status. Evidence details live in
`necb_decisions.md` (D-XX refs) and the filed issues. Statuses: FILED
(upstream issue exists) / UNFILED (verified, needs an issue) / SHARED-FIXED
(both lineages had it; fixed in the gems, still present in legacy) /
DIFFERENCE (divergent modeling choice, not established as a defect) /
UNRESOLVED (needs root-cause before filing).

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-1 | NECB2020/2025 ERV requirement inherits the NECB2017 formula: missing the non-continuous Table 5.2.10.1.-A path and the <10% OA exemption -> over-equips ERVs at HDD >= 3000 (observed: SmallOffice 5 ERVs at 3.8-12.8% OA, Warehouse 3 at <10%) | **FILED** [#2123](https://github.com/NatLabRockies/openstudio-standards/issues/2123) | D-17 |
| L-2 | BTAP costing: 14 defects found during openstudio-hvac parity validation | **FILED** [#2118](https://github.com/NatLabRockies/openstudio-standards/issues/2118) | prior session |
| L-3 | Infiltration envelope area S includes attic roofs/gables; 3.2.4.2.(1)(c) limits S to surfaces bounding CONDITIONED space (attic ceiling, not roof) -> over-installed default on attic buildings (Restaurant: 1356 m2 basis vs ~320-scale correct) | **SHARED-FIXED** (gems fixed in D-21; legacy still roof-inclusive), UNFILED | D-21 |
| L-4 | Infiltration "above-grade area" denominator in NECB2020 space_apply_infiltration_rate accumulates ALL Outdoors surfaces (walls+roofs+exposed floors); 8.4.2.9.(2) defines A_AGW as above-ground WALLS | UNFILED (nets out on towers; interacts with L-3 on low-rise) | D-19 amendment |
| L-5 | Infiltration distributed over all exterior surfaces incl. unconditioned attic volumes (vs concentrating on the conditioned enclosure) | DIFFERENCE (distribution choice; totals are the code quantity) | D-21 correction |
| L-6 | DX cooling COPs on archetypes (3.47/3.98) vs NECB Table 5.2.12.1 bin minimums (3.0) — conversion convention or bin difference not yet root-caused | UNRESOLVED | fixed-point diff |
| L-7 | Wrong-vintage inheritance PATTERN: vintage classes silently inherit older-vintage rules where no override exists (mechanism behind L-1; NECB2015 likely still runs the 2011 150 kW EHC ERV trigger — unverified against 2015 code text) | UNRESOLVED | D-17 |
| L-8 | Chiller EIR_FT: legacy vendored curves are CORRECT — they corroborated the NECB PUBLICATION erratum (misplaced decimals in print). Credit, not defect | closed (NRC errata filed 2026-07-22) | D-03 |

Maintenance rule: every new legacy finding gets a row HERE at discovery time,
plus its D-XX narrative; UNFILED rows get bundled into upstream issues when a
theme completes (L-3/L-4/L-5 are one infiltration-areas issue).
