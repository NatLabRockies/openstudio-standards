# Reference-systems three-way audit — consolidated triage (2026-07-25)

> **ARCHIVED EVIDENCE — not a live queue (D-44, 2026-07-28).** Every row below
> is resolved: T1-T13 → D-22, A1-A5 → D-34/D-37/D-38/D-39/D-40, A6 → **D-45**
> (ruled 2026-07-29), LEDGERED rows → `legacy_findings.md`. The A
> and T registers are retired; the live registers are **D** (decisions,
> `necb_decisions.md`, mirrored in `decisions.json` and surfaced at runtime via
> `ruling:` tags) and **L** (legacy findings). Kept for the reasoning and
> three-way comparison evidence behind those decisions. See `docs/README.md`.

Four parallel auditors compared every NECB 2020 reference-HVAC article
(8.4.4.6-.19) and all builder behaviours three ways: code text (codes MCP) vs
openstudio-hvac vs legacy openstudio-standards. Already-adjudicated items
(D-06..D-21) excluded. Full raw findings in the session transcripts; this file
is the action ledger. Statuses: TO-FIX (ours, clear code basis, D-10
delegation) / ADJUDICATE (needs phylroy) / LEDGERED (legacy → legacy_findings.md)
/ DOC (manifest/citation text) / OK.

## TO-FIX (ours), severity order
| # | Finding | Basis |
|---|---|---|
| T1 | **8.4.4.8 caps never bind**: builders stamp zone sizing factors 1.3/1.1 which OVERRIDE the capped global Sizing:Parameters (E+ IDD: zone factor wins). Audit log claims a cap the model does not carry. Fix: apply_oversizing_caps resets zone factors that equal the generic 1.3/1.1 (preserving the HP 1.0 cooling factor required by 8.4.4.13.(2)(b)). | HIGH — falsifies an audit claim |
| T2 | **Tower fan power 0.015** is the NECB2011 value; NECB2015+ (and Table 5.2.12.2) say 0.013 — legacy-2020 uses 0.013. Also split the citation: cells → 8.4.4.11.(2)-(3), fan → 5.2.12.2. | HIGH |
| T3 | **Economizers over-applied**: no 5.2.2.7 trigger (mech cooling AND >1500 L/s or >20 kW; dwelling/hotel exempt), applied pre-sizing where thresholds cannot be known. Fix: post-sizing threshold pass (NoEconomizer + audit below trigger); checker gains the same thresholds. | HIGH (penalizes proposed) |
| T4 | **HP heating capacity rule 8.4.4.13.(2)(c)**: rated heating capacity never pinned to cooling capacity (curve shape right, rating wrong). Fix post-sizing in the efficiency pass. | MED |
| T5 | **Night-cycle + motorized OA damper missing** (legacy: CycleOnAny + min-OA schedule = occupancy). Fix: AvailabilityManagerNightCycle on reference loops + min-OA schedule = inherited operating schedule (extends D-14). | MED |
| T6 | **ERV wheel parasitic power = 0 W + HX bypass control default**: add the PNNL surrogate wheel power and BypassWhenOAFlowGreaterThanMinimum (non-DOAS) in add_energy_recovery. | MED |
| T7 | **8.4.4.15 over-claimed**: status → partial; warn when a proposed ControllerOutdoorAir carries hard-set min OA (identity-by-clone then unsound); DCV gap becomes warning-visible. | MED |
| T8 | **Humidification (Table -B note 1) undeclared**: declare in manifest + runtime warn when the proposed had humidifiers on replaced loops. | MED |
| T9 | **Mixed-group majority vote silent** (8.4.4.7.(1) is per-block): warn on non-unanimous groups. Keyword-order fragility (hotel-dining → Residential) documented in manifest. | MED |
| T10 | **Zone-equipment fans skip 8.4.4.18**: fan-coil/PTAC/OnOff zone fans keep SDK defaults; extend apply_fan_rules to zone fans of systems 1-5 (640 Pa / 40%). | MED |
| T11 | **VAV terminal MaximumFlowFractionDuringReheat 0.5** (legacy parity, heating-airflow behaviour). | LOW-MED |
| T12 | Boundary strictness: split at >176/>352/>2100 (code: "not greater than"), tower cells = ceil. | LOW |
| T13 | Stale 8.4.4.11 manifest gaps note (temps ARE set). | DOC |

## ADJUDICATE (phylroy)
| A1 | ~~Residential blocks WITH heat pumps~~ **RESOLVED (D-34, phylroy 2026-07-27): follow legacy — 8.4.4.7.(4) ASHP redirect wins over the Table -A parenthetical. Implemented + pinned (selector/reference/res_hp mockup).** |
| A2 | ~~Water-LOOP vs water-SOURCE HP boundary~~ **RESOLVED (D-37, phylroy 2026-07-28): printed split implemented with the Note A-8.4.4.13 boundary — internal-loop (boiler/tower) WLHP keeps Table -A (8.4.4.13.(1)); ground-HX/district/external-water and air-source redirect ((2)); source classified from the HP's source plant loop; no-evidence detections keep the conservative redirect. WSHP e2e premise updated (catalog 'Water source heat pumps' is a water-LOOP system by the note).** |
| A3 | ~~5.2.6.3.(1) pump caps vs 8.4.4.14 transfer~~ **RESOLVED (D-38, phylroy 2026-07-28): min-wins — transfer the proposed intensity per 8.4.4.14, then clamp the loop's combined pump power at the Table 5.2.6.3 W/kW of peak thermal demand (4.5 htg / 14 clg / 12 rej / 22 WSHP, values MCP-verified both vintages); clamp keeps the head physical and audits both articles.** |
| A4 | ~~Table -B System 5 heating "None"~~ **RESOLVED (D-39, phylroy 2026-07-28): conditional — cooled-but-unheated proposed blocks get the table-literal cooling-only TPFC; heated blocks keep the changeover heating per the 8.4.4.1.(5) presence override; both branches audited. Legacy always-heat parity intentionally broken for the unheated case.** |
| A5 | ~~Reheat-coil hard-size workaround~~ **RESOLVED (D-40, phylroy 2026-07-28): NO-CHANGE — autosizing trusted. Measured on the sized LargeOffice reference: the legacy formula misses 0.11x-3.15x in both directions (min-flow basis incompatible with our 0.5 reheat-flow cap; load-blind), would disable capacity auto-iteration, and has no code basis. E+ e2e conditioning asserts are the regression net.** |
| A6 | ~~'Museum general exhibition area' selects Assembly Area via the 'exhibit' keyword, not Historical Collections via 'museum'~~ **RESOLVED (D-45, 2026-07-29): the collections row names museum and gallery ARCHIVES, so an exhibition gallery is the assembly row's "exhibit space" — existing behaviour ratified; the over-broad 'museum' keyword was narrowed so the answer no longer depends on category order.** |

## LEDGERED (legacy — see legacy_findings.md L-9..L-15)
Fan-curve cubics functionally wrong + D/E column conflation (HIGH); 8.4.4.18
combined efficiencies replaced by motor tables; residential row still
2011-text; 8.4.4.6 purchased energy absent; 'NECB_Defualt' dead guard;
economizer flow-branch-without-cooling nit; sys4 control-zone sizing defect
(ours is the correct side); no 8.4.4.14 coefficients (linear pumps); hard
raise on unlisted space types.

## Notable OK (three-way exact)
All plant temperatures/resets; Table 8.4.4.14 + 8.4.4.17 coefficients and row
selection; -10C HP cutoff; exhaust-fan identity; ERV heat routing; Table -A
row thresholds; -B fan-control/cooling-type columns; sizing blocks verbatim
vs legacy incl. the deliberate sys2/5 inverted SPM pair.

## Attic answer (D-21 follow-up)
Legacy attics DO carry partofTotalFloorArea=false → our S fix fires on them.
The Restaurant's small post-D-21 delta is therefore genuine (its attic zone is
"conditioned-shaped" — zoned with an empty thermostat — but the flag is what
our rule keys on and it is set). No extra heuristic needed.
