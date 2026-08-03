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

## Added 2026-07-28 (first full-annual sweep, D-42)

| # | Finding | Status | Evidence |
|---|---|---|---|
| L-23 | Legacy NECB2020 archetypes under full-annual scrutiny: proposed-side unmet COOLING hours run 1.2-5x the reference building's (e.g. SmallOffice 261 vs 217 h, LowriseApartment 528 vs 95 h, SmallHotel 2,756 vs 691 h), failing the 8.4.1.2.(4) within-+10% criterion in 11/15 buildings; the sentence-(5) capacity-increase remedy is defeated because archetype equipment is HARD-SIZED (ignores global sizing factors — iteration stalls, detected loudly). Unmet heating is ~0 fleet-wide | DIFFERENCE/characteristic — measured by our pipeline's verdicts; not filed (whether archetypes should pass a determination they were never run through is a scoping question, and the +10% criterion binds only in full-annual runs legacy never performs) | D-42 |

## Added 2026-07-29 (staged heating/cooling, D-46..D-50)

| # | Finding | Status | Evidence |
|---|---------|--------|----------|
| L-24 | Legacy implements 8.4.4.9.(7)/8.4.4.10.(8) staging but **never reaches it**: `multispeed:` defaults to false in `add_sys3and8_...`/`add_sys1_...` and ALL six `autozone.rb` call sites pass `multispeed: false` explicitly; no caller in `lib/` passes true. Every NECB archetype legacy generates therefore carries SINGLE-SPEED coils — the staging sentences are unimplemented in practice for the models we cross-validate against | DIFFERENCE (ours implements them; the divergence is intended) | [RAN] grep of all call sites; the sweep's proposed models carry `CoilCoolingDXSingleSpeed` |
| L-25 | In that dormant path, `hvac_systems.rb:930/1195` sets stage count `(cap/66 + 0.5).round` (not the printed `ceil`) and pins stage capacities at fixed 66 kW multiples with the TOP stage at `66 kW x N` — which **exceeds the equipment's design capacity** in most cases (100 kW design -> 132 kW top stage; 400 kW -> 462 kW; and at exactly 66 kW it produces 66/132 where sentence (b) requires two EQUAL stages, 33/66). Sentence (a) of both articles fixes the system capacity at the served loads x oversize factor, so a top stage above it contradicts (a); efficiency is then binned on that inflated `stage_cap.last` rather than the design capacity | DIFFERENCE — LATENT (unreachable via the archetype path, so not filed upstream). Ours divides the design capacity into N equal cumulative steps, keeping the top stage == design capacity per (a), and leaves them AUTOSIZED per D-46 | [RAN] arithmetic replay of the legacy formula over 30-400 kW; [READ] hvac_systems.rb:925-990, 1190-1230 |

## Added 2026-07-29 (daylighting control selection, D-51 follow-up)

| # | Finding | Status | Evidence |
|---|---------|--------|----------|
| L-26 | **Daylighting-control selection applied NECB 2011 criteria to the 2020/2025 path** — the same vintage-inheritance species as L-1 (ERV). Legacy `necb_2011.rb:1730-1757` excepts a space unless primary sidelighted area > 100 m2 AND daylighted area under skylights > 400 m2 AND skylight effective aperture > 0.006 (its own comment cites "NECB2011: 4.2.2.2"), with an offices->=25 m2 carve-out. NECB **2020** 4.2.2.1 rewrote this completely: sentence **(10)** requires SIDELIGHTING photocontrols on input POWER (>=150 W in primary sidelighted areas, or >=300 W primary+secondary), sentence **(13)** requires TOPLIGHTING photocontrols at >=150 W under skylights/roof monitors, each gated by the space type's Table 4.2.1.6 control column, with explicit exceptions in (12)/(15). The 2011 criteria are AREA/effective-aperture based and are applied CONJUNCTIVELY, so a window-only space always fails the skylight test and gets no controls at all. The legacy geometry also SUMS per-window areas with no union (contrary to 4.2.2.3.(1)/(5), 4.2.2.4.(1), 4.2.2.5.(1)) and computes NO secondary sidelighted area, so (10)(b) could not even be expressed | **DELIBERATE DIVERGENCE as of D-57 (2026-07-29)** — the reference path now implements the 2020/2025 rule (`openstudio-lighting/.../necb/daylight_control_requirement.rb` + `daylighted_areas.rb`, `placement: :necb2020`, the default). Placement across the 17 cached NECB2020 archetypes goes from 21 to 174 spaces, and seven of the ten archetypes D-51 found inert now move. The legacy-exact 2011 port stays reachable as `placement: :necb2011` and remains pinned by `test_daylighting_parity.rb`, so the port is still provably faithful; selecting it WARNS that the target is looser than the code requires. **Still not filed upstream** | [READ] necb_2011.rb:1730,1733,1749,1757; [RAN] codes MCP `get_section('necb','4.2.2.1')` sentences (10)-(15), `4.2.2.3.`, `4.2.2.4.`, `4.2.2.5.`, and 4.2.2.6 "Special Applications" ends Subsection 4.2.2 (so 4.2.2.7-4.2.2.10 do NOT exist in NECB 2020/2025 — every such citation in openstudio-lighting is fixed); [RAN] `openstudio-lighting/test/test_daylighting_necb2020.rb` 24 runs / 518 assertions / 0 failures; [RAN] `test_daylighting_parity.rb` 3 runs / 0 failures |

## Added 2026-08-03 (never-swept archetypes, close-out plan Phase 1b)

| # | Finding | Status | Evidence |
|---|---------|--------|----------|
| L-27 | **NorthernEducation and NorthernHealthCare cannot be generated by legacy at all**: `model_create_prototype_model` dies in `apply_loads` ("validation of model failed", `necb_2011.rb:787`) because their geometry OSMs lack `Building.standardsNumberOfStories` / `standardsNumberOfAboveStories` — the legacy pipeline's own validation rejects the legacy library's own geometry. The two zone-8 archetypes are therefore unreachable for any cross-validation (Yellowknife pass moot) | UNFILED — upstream candidate (bundle with the Phase 5b filings) | [RAN] `gen_NorthernEducation.err` / `gen_NorthernHealthCare.err`, both identical traces; [READ] necb_2011.rb:787 |
| L-28 | **Three LEEP models (Midrise/MultiTower/PointTower) carry a `Space Function - undefined -` space type on floor-area spaces** — unresolvable against the NECB catalog by construction (it IS the catalog's undefined sentinel), so the reference lighting/loads allowance cannot be determined for those spaces. Our pre-flight refuses them loudly (by design); legacy generates them silently with whatever loads the sentinel row carries. LEEPTownHouse (fully tagged) PASSES at 103% | UNFILED — same bundle; the models need real space-function tags | [RAN] sweep PREFLIGHT-REFUSAL x3 naming the type; LEEPTownHouse PASS 103% |
