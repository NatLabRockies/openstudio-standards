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
| L-3 | Infiltration envelope area S includes attic roofs/gables; 3.2.4.2.(1)(c) limits S to surfaces bounding CONDITIONED space (attic ceiling, not roof) -> over-installed default on attic buildings (Restaurant: 1356 m2 basis vs ~320-scale correct) | **FILED** [#2126](https://github.com/NatLabRockies/openstudio-standards/issues/2126) (SHARED-FIXED in gems, D-21) | D-21 |
| L-4 | Infiltration "above-grade area" denominator in NECB2020 space_apply_infiltration_rate accumulates ALL Outdoors surfaces (walls+roofs+exposed floors); 8.4.2.9.(2) defines A_AGW as above-ground WALLS | **FILED** [#2126](https://github.com/NatLabRockies/openstudio-standards/issues/2126) | D-19 amendment |
| L-5 | Infiltration distributed over all exterior surfaces incl. unconditioned attic volumes (vs concentrating on the conditioned enclosure) | DIFFERENCE — noted as observation in [#2126](https://github.com/NatLabRockies/openstudio-standards/issues/2126) | D-21 correction |
| L-6 | DX cooling COPs on archetypes (3.47/3.98) vs NECB Table 5.2.12.1 bin minimums (3.0) — conversion convention or bin difference not yet root-caused | UNRESOLVED | fixed-point diff |
| L-7 | Wrong-vintage inheritance PATTERN: vintage classes silently inherit older-vintage rules where no override exists (mechanism behind L-1; NECB2015 likely still runs the 2011 150 kW EHC ERV trigger — unverified against 2015 code text) | UNRESOLVED | D-17 |
| L-8 | Chiller EIR_FT: legacy vendored curves are CORRECT — they corroborated the NECB PUBLICATION erratum (misplaced decimals in print). Credit, not defect | closed (NRC errata filed 2026-07-22) | D-03 |

Maintenance rule: every new legacy finding gets a row HERE at discovery time,
plus its D-XX narrative; UNFILED rows get bundled into upstream issues when a
theme completes (L-3/L-4/L-5 are one infiltration-areas issue).

## Added 2026-07-25 (reference-systems three-way audit)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-9 | Table 8.4.4.17 fan part-load curves: 2011-era CUBICS deviate up to ~0.5xPrated from the printed 2020 quadratics, AND FanPowerMinimumFlowFraction is set to column E (power floor) instead of D (flow threshold) — reference VAV never drops below 68% flow. Inherited into NECB2020 unchanged | UNFILED — **high** | audit F-9 |
| L-10 | 8.4.4.18 fan COMBINED efficiencies (40%/55%/30%) replaced by motor-table lookups (~0.55-0.85) at the code pressures — reference fan power runs 30-50% low | UNFILED | audit F-10/F-11 |
| L-11 | Table 8.4.4.7.-A Residential row still implements the 2011 text: no identical-to-proposed branch, no through-the-wall branch | UNFILED | sel-audit #7 |
| L-12 | 8.4.4.6 Purchased Energy entirely unimplemented | UNFILED | sel-audit #21 |
| L-13 | model_enable_demand_controlled_ventilation guard tests the misspelling 'NECB_Defualt' (dead code, currently harmless) | UNFILED (trivial) | air-audit F-6 |
| L-14 | Economizer trigger: flow branch fires without mechanical cooling; dwelling/hotel exemption of 5.2.2.7.(1) absent | UNFILED | air-audit F-1 |
| L-15 | hvac_system_4: control-zone cooling design SAT difference set twice (second call passes the heating 21 K value); heating input method never set | UNFILED | beh-audit #15 |
| L-16 | Unlisted space types hard-raise instead of the 8.4.4.7.(3) closest-type fallback | UNFILED (works only because JSONs pre-map all types) | sel-audit #5 |
| L-17 | No 8.4.4.14 pump part-load coefficients anywhere (VS pumps keep OS default linear) | UNFILED | plant-audit #11 |

## Added 2026-07-25 (object-level fixed-point diff, D-23/D-24)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-18 | Attic ceiling U row: OSut construction sets apply the exposed-FLOOR row (uo=eFloorU, 0.175 at HDD 3890) to the ceiling below an attic; 3.1.1.7.(6) classifies horizontal top-of-conditioned-space assemblies as ROOF assemblies (0.156 + 3.1.1.7.(4) enclosure credit). Lenient by ~9% on the attic boundary | DIFFERENCE — ours follows the inclination rule (D-24) | D-24 |
| L-19 | Two coexisting legacy construction paths disagree on the film convention by ~4%: OSut/TBD.genConstruction (NECB2020 prototypes) treats table U as OVERALL transmittance incl. films (code-literal per 1.4.1.2); BTAP apply_standard_construction_properties/customize_opaque_construction sets table U as construction-only conductance (over-stringent). Same table, two answers, path-dependent | UNFILED | D-23 |
