# Reference-systems three-way audit — consolidated triage (2026-07-25)

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
| A1 | Residential blocks WITH heat pumps: Table -A row says identical-to-proposed; 8.4.4.7.(4) redirects to ASHP. Ours=copy, legacy=redirect. Genuinely ambiguous. |
| A2 | Water-LOOP vs water-SOURCE HP boundary (8.4.4.13.(1) keeps WLHP on Table -A; sentence (2) redirects W-SOURCE). Our single hp flag redirects both; Note A-8.4.4.13 unavailable via MCP. Touches the WSHP e2e test premise. |
| A3 | 5.2.6.3.(1) loop pump power caps (NECB2015+, W/kW: 4.5 htg /14 clg /12 rej /22 WSHP): legacy applies to the reference; interaction with our 8.4.4.14 proposed-intensity transfer needs a ruling (which basis wins when they conflict?). |
| A4 | Table -B System 5 heating "None": both lineages build seasonal hydronic heating anyway (deliberate legacy parity). Keep or honour the table? |
| A5 | Reheat-coil hard-size workaround (legacy caps at 1.2x min-flow ΔT30): adopt, or trust autosizing (our e2e conditioning asserts pass today)? |
| A6 | 'Museum general exhibition area' selects Assembly Area via the 'exhibit' keyword, not Historical Collections via 'museum' (keyword-order collision, found by the D-33 mockups). Which Table 8.4.4.7.-A row should museum exhibition galleries use? |

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
