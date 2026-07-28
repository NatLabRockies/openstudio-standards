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
| L-6 | DX cooling COPs on archetypes (3.47/3.98) vs Table 5.2.12.1 "3.0" expectation | **RESOLVED — NO DEFECT** (false premise #4): archetype ratings ARE the printed 5.2.12.1.-A minimums (53 kBtu/hr→SEER 15 "single-package, others"; 328/722 kBtu/hr→EER 10.0, 70-223 kW electric-heat row — 722 kBtu = 211.6 kW, still <223); COPs are the standard fan-stripped conversions (SEER quadratic; Thornton r=0.12 EER form), byte-identical in gem and legacy (hvac/conversions.rb). The "3.0" was naive EER/3.413 with no fan correction | D-31 |
| L-7 | NECB2015 runs the 2011 150 kW EHC ERV trigger (no override; 2017 introduces one) | **RESOLVED — VINTAGE-CORRECT** on convergent secondary evidence: the national NECB 2015 retained the 150 kW sensible-exhaust-heat trigger (Quebec's NECB-2015 amendment lowered it to 50 kW — an amendment to a 150 kW national base; industry change summaries place the flow-rate/OA rewrite at NECB 2017, harmonized with 90.1). Primary 2015 text not machine-accessible (codes MCP carries 2020/2025 only) — revisit if 2015 is ever ingested. The inheritance PATTERN itself remains the filed #2123 mechanism for 2020/2025 | D-31 |
| L-8 | Chiller EIR_FT: legacy vendored curves are CORRECT — they corroborated the NECB PUBLICATION erratum (misplaced decimals in print). Credit, not defect | closed (NRC errata filed 2026-07-22) | D-03 |

Maintenance rule: every new legacy finding gets a row HERE at discovery time,
plus its D-XX narrative; UNFILED rows get bundled into upstream issues when a
theme completes (L-3/L-4/L-5 are one infiltration-areas issue).

## Added 2026-07-25 (reference-systems three-way audit)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-9 | Table 8.4.4.17 fan part-load curves: 2011-era CUBICS deviate up to ~0.5xPrated from the printed 2020 quadratics, AND FanPowerMinimumFlowFraction is set to column E (power floor) instead of D (flow threshold) — reference VAV never drops below 68% flow. Inherited into NECB2020 unchanged. QUANTIFIED from the proposed side by the LargeOffice fixed-point transplant: curve/floor config alone is ~10 GJ/wk of the 28 GJ fan gap; archetype fan energy runs ~2.2x the code reference | **FILED** [#2127](https://github.com/NatLabRockies/openstudio-standards/issues/2127) | audit F-9; D-28 |
| L-10 | 8.4.4.18 fan COMBINED efficiencies (40%/55%/30%) replaced by motor-table lookups (~0.55-0.85) at the code pressures — reference fan power runs 30-50% low | **FILED** [#2127](https://github.com/NatLabRockies/openstudio-standards/issues/2127) | audit F-10/F-11 |
| L-11 | Table 8.4.4.7.-A Residential row still implements the 2011 text: no identical-to-proposed branch, no through-the-wall branch | **FILED** [#2128](https://github.com/NatLabRockies/openstudio-standards/issues/2128) | sel-audit #7 |
| L-12 | 8.4.4.6 Purchased Energy entirely unimplemented | **FILED** [#2129](https://github.com/NatLabRockies/openstudio-standards/issues/2129) | sel-audit #21 |
| L-13 | model_enable_demand_controlled_ventilation guard tests the misspelling 'NECB_Defualt' (dead code, currently harmless) | **FILED** [#2129](https://github.com/NatLabRockies/openstudio-standards/issues/2129) | air-audit F-6 |
| L-14 | Economizer trigger: flow branch fires without mechanical cooling; dwelling/hotel exemption of 5.2.2.7.(1) absent | **FILED** [#2129](https://github.com/NatLabRockies/openstudio-standards/issues/2129) | air-audit F-1 |
| L-15 | hvac_system_4: control-zone cooling design SAT difference set twice (second call passes the heating 21 K value); heating input method never set | **FILED** [#2129](https://github.com/NatLabRockies/openstudio-standards/issues/2129) | beh-audit #15 |
| L-16 | Unlisted space types hard-raise instead of the 8.4.4.7.(3) closest-type fallback (works only because JSONs pre-map all types) | **FILED** [#2128](https://github.com/NatLabRockies/openstudio-standards/issues/2128) | sel-audit #5 |
| L-17 | No 8.4.4.14 pump part-load coefficients anywhere (VS pumps keep OS default linear) | **FILED** [#2129](https://github.com/NatLabRockies/openstudio-standards/issues/2129) | plant-audit #11 |

## Added 2026-07-25 (object-level fixed-point diff, D-23/D-24)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-18 | Attic ceiling U row: OSut construction sets apply the exposed-FLOOR row (uo=eFloorU, 0.175 at HDD 3890) to the ceiling below an attic; 3.1.1.7.(6) classifies horizontal top-of-conditioned-space assemblies as ROOF assemblies (0.156 + 3.1.1.7.(4) enclosure credit). Lenient by ~9% on the attic boundary | DIFFERENCE — ours follows the inclination rule (D-24) | D-24 |
| L-19 | Two coexisting legacy construction paths disagree on the film convention by ~4%: OSut/TBD.genConstruction (NECB2020 prototypes) treats table U as OVERALL transmittance incl. films (code-literal per 1.4.1.2); BTAP apply_standard_construction_properties/customize_opaque_construction sets table U as construction-only conductance (over-stringent). Same table, two answers, path-dependent | **FILED** [#2130](https://github.com/NatLabRockies/openstudio-standards/issues/2130) | D-23 |

## Added 2026-07-25 (Warehouse residual close-out, D-32)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-20 | Ground-floor insulation vs Table 3.2.3.1 floors row ("0.757 for 1.2 m" zones 4-7B / "0.379 for full area" zone 8): the OSut archetype path models the slab BARE with no 1.2 m perimeter strip in zones 4-7B (under-insulated vs 3.2.3.3.(3)); the old BTAP apply_standard_construction_properties path applies the 0.757 strip value over the FULL slab area (over-insulated). The two legacy paths disagree with each other and neither matches the printed table; zone 8 full-area (0.379 -> 0.403 construction-only) is correct in both lineages | **FILED** as a comment on [#2130](https://github.com/NatLabRockies/openstudio-standards/issues/2130#issuecomment-5080803085) (same two-paths species); ours implements the printed zone-conditional rule (Kiva perimeter strip, D-32); legacy strip omission is MEASURED at ~6.7 GJ/wk of opaque conduction on the 4,598 m2 Warehouse slab (bare vs bare+strip; Kiva 2D — the 1.2 m strip recovers ~70% of full-slab insulation's benefit because perimeter loss dominates) | D-32; end-use isolation + object diff, all four Warehouse variants |

## Added 2026-07-28 (A-list adjudications D-37/D-39/D-40)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-21 | System 5 heating: legacy builds sys 5 with the sys 2 machinery (two-pipe changeover WITH boiler heating, always) — Table 8.4.4.7.-B's heating "None" is never honoured, and 8.4.4.1.(5) presence-identity is not consulted (a cooled-but-unheated refrigerated proposed still gets a heated reference) | DIFFERENCE — ours is conditional per D-39 (table-literal cooling-only when the proposed block is unheated; changeover kept under the 8.4.4.1.(5) override when heated); legacy parity intentionally broken for the unheated case | D-39 |
| L-22 | VAV reheat-coil sizing: legacy hard-sets reheat capacity to 1.2 x 1000 x min_flow_fraction x max_flow x 30 K (hvac_systems.rb:2446), overriding autosizing — load-blind, uses ~17%-low volumetric heat capacity (1000 vs ~1206 J/(m3.K)), and its min-flow basis is coherent only with legacy's own 68%-floor terminal config (L-9) | DIFFERENCE — ours trusts autosizing per D-40 (measured 0.11x-3.15x divergence in both directions on the sized LargeOffice reference; hard-sizing would also disable 8.4.1.2.(5) capacity iteration). Not filed: coherent within legacy's own configuration, defective only if transplanted | D-40 |
