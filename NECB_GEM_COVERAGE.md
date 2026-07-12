# NECB coverage across the openstudio-* gem family

Auto-generated rollup of every gem's 2020 article-coverage manifest (the 2025
manifests mirror these with renumbered citations). Statuses: implemented /
partial (warns every run) / not_implemented (warns every run) /
satisfied_by_clone / host_scope.

## Implemented (25)

| Gem | Article | Title | Notes |
|---|---|---|---|
| openstudio-envelope | 3.1.1.6. | Determination of Areas (FDWR/SRR area basis) | gross wall/roof area census + FDWR/SRR computed from exposed conditioned surfaces (Geometry module) |
| openstudio-envelope | 3.1.1.7. | Thermal Characteristics of Building Assemblies (EFFECTIVE tr | TBD-based uprate/derate: assemblies uprated so the DERATED effective Ut meets the table targets (thermal_bridging: option, BETBG PSI sets) |
| openstudio-envelope | 3.2.1.4. | Allowable Fenestration and Door Area (FDWR + 2% skylights) | max_fdwr piecewise formula + 2% SRR; FDWR window rebuild and centroid-scaled skylights (apply_fdwr:/apply_srr:) |
| openstudio-envelope | 3.2.2.1. | General (above-ground assemblies) | prescriptive application classifies and hard-assigns all above-ground assemblies |
| openstudio-envelope | 3.2.2.2. | Opaque above-ground U-values by HDD zone | opaque U-values applied per HDD bin (legacy-compatible construction conductance; include_films: for overall) |
| openstudio-envelope | 3.2.2.3. | Fenestration/skylight U-values by HDD zone | window/skylight U via SimpleGlazing replacement preserving SHGC/VT; opaque doors via insulation solve |
| openstudio-envelope | 3.2.2.4. | Door U-values (2025 split-out table; 2020: within 3.2.2.x) | door values applied (2025 split-out table == 2020 door row) |
| openstudio-envelope | 3.2.3.1. | Building assemblies in contact with the ground | ground-contact wall/roof/floor U-values applied (no ground fenestration) |
| openstudio-lighting | 4.2.1.4. | Methods of Determining Interior Lighting Power Allowance | space-function method via NECB space-type records (openstudio-loads data); building-type method via the vendored 4.2.1.5 table |
| openstudio-lighting | 4.2.1.5. | Building Type Method LPD | 2020 values embedded in WholeBuilding space-type records (verified vs code) |
| openstudio-lighting | 4.2.1.6. | Space Function Method LPD | 2020 values embedded in space-function records; additional_lighting_per_area specialty allowance applied |
| openstudio-lighting | 4.2.3.1. | Exterior Lighting Power Allowances | allowance calculator over the vendored Tables 4.2.3.1.-A..-E (basic site + tradable + non-tradable by lighting zone) + ExteriorLights creation with astronomical |
| openstudio-lighting | 4.3.2.10. | Occupancy/personal control factors (trade-off path) | the Focc/Fpers factors ship as space-type keys and drive the sensor-schedule synthesis |
| openstudio-shw | 8.4.3.2. (SWH loads) | Service water heating loads representative of the building | per-space WaterUseEquipment from the NECB space-type peak flows, target temperatures and NECB-<letter> SWH schedules (openstudio-loads data) |
| openstudio-envelope | 8.4.4.1. | Reference building basis (envelope meets Section 3.2) | reference envelope meets prescriptive Section 3.2 (U-values at the building HDD; FDWR/SRR enforced via 8.4.4.3.(3) scaling) |
| openstudio-hvac | 8.4.4.17. | Fans (exhaust fans, fan power vs flow curves) | VAV fan power-vs-flow curves from Table -17 applied in the (post-sizing) efficiency pass, row selected by rated power per sentences (3)-(5); the below-D floor i |
| openstudio-hvac | 8.4.4.19. | Energy Recovery Systems | 5.2.10.1 exhaust-heat-content trigger (>150 kW, specification-based) evaluated per reference air loop; rotary HX @ 50% effectiveness with OA-pretreat control ad |
| openstudio-shw | 8.4.4.20.(2) | HP-source SWH -> air-source HP in the reference | apply_shw(fuel: 'HeatPump') builds an air-source HPWH; a reference generated from it keeps the air-source energy type by construction |
| openstudio-envelope | 8.4.4.3. | Reference envelope: absorptance, FDWR scaling, shading, fene | roof absorptance 0.7 iff proposed used actual values; proportional per-orientation FDWR/SRR scaling of EXISTING fenestration; Space/Building shading + controls  |
| openstudio-envelope | 8.4.4.4. | Lightweight construction + space thermal characteristics | opaque assemblies rebuilt as massless (zero thermal mass) layers at unchanged Ut; space thermal characteristics satisfied by clone |
| openstudio-lighting | 8.4.4.5.(1) | Reference building interior lighting power = Part 4 allowanc | apply_lights sets the allowance LPD from the space-type records |
| openstudio-lighting | 8.4.4.5.(2) | Dwelling units 5 W/m2 | reference_lighting overrides dwelling space types to 5 W/m2 |
| openstudio-lighting | 8.4.4.5.(4) | Radiant/convective/return-air fractions identical to propose | fractions come from the same space-type records for both models |
| openstudio-hvac | 8.4.4.7. | HVAC System Selection (Tables -A/-B) | Category election per Table -A (space type + storeys + cooling-kW threshold), closest-type fallback per sentence (3), residential special rules, HP redirect per |
| openstudio-hvac | 8.4.4.8. | Equipment Oversizing | Heating/cooling sizing factors set to min(proposed, 1.30/1.10) with the arithmetic recorded. |

## Satisfied by construction (clone) (3)

| Gem | Article | Title | Notes |
|---|---|---|---|
| openstudio-hvac | 8.4.4.15. | Outdoor Air | Spaces (and their DesignSpecificationOutdoorAir) are retained by the clone; rebuilt systems draw the same peak OA specifications (1). |
| openstudio-hvac | 8.4.4.2. | Operating Schedules, Internal Loads and Service Water Heatin | The reference model is a clone of the proposed model: schedules and internal/SHW loads remain identical, as required. |
| openstudio-shw | 8.4.4.20.(1) | Reference SWH identical to proposed (storage, power, energy  | the umbrella clones the proposed; neither reference transform touches SWH plant sizing or fuel |

## Host / other-gem scope (11)

| Gem | Article | Title | Notes |
|---|---|---|---|
| openstudio-envelope | 3.1.1.5. | Determination of Thermal Characteristics |  |
| openstudio-loads | 8.4.3.1. | Thermal Blocks | thermal-block/zoning decisions belong to the modeller or the HVAC autozoning layer, not the loads pass |
| openstudio-loads | 8.4.3.3. | Air Leakage | implemented in the openstudio-envelope gem (8.4.3.3.(3) default air-leakage rule in its reference transform); the loads pass applies only the space-type modelli |
| openstudio-loads | 8.4.3.4. | HVAC System Operation | fan/system operating schedules ship in the schedule sets (NECB-<letter>-Fan); wiring them to systems is the openstudio-hvac / umbrella layer |
| openstudio-loads | 8.4.3.5. | Assumed chiller performance for Part 8 calculations (Table 8 | Table 8.4.3.5 = assumed chiller COP/IPLV (Scroll < 528 kW: COP 2.802/IPLV 3.664; Screw >= 528 kW: COP 2.802/IPLV 3.737) — an HVAC calculation assumption, not a  |
| openstudio-hvac | 8.4.4.1. | General — reference building basis (prescriptive components, | Whole-building modeling basis; the HVAC slice is governed by the articles below. Envelope/lighting/SHW prescriptive conformance is host-side. |
| openstudio-envelope | 8.4.4.2. | Operating schedules/loads identical | HVAC-side handled by openstudio-hvac reference_hvac (satisfied by clone there) |
| openstudio-hvac | 8.4.4.20. | Service Water Heating Systems | SHW reference rules are out of the HVAC scope (host-side future work). |
| openstudio-hvac | 8.4.4.3. | Building Envelope Components (solar absorptance) | Envelope rules are out of the HVAC scope (host-side future work). |
| openstudio-hvac | 8.4.4.4. | Envelope Thermal Characteristics (lightweight construction) | Envelope rules are out of the HVAC scope (host-side future work). |
| openstudio-hvac | 8.4.4.5. | Lighting | Lighting rules are out of the HVAC scope (host-side future work). |

## Partial (warns every run) (15)

| Gem | Article | Title | Notes |
|---|---|---|---|
| openstudio-lighting | 4.2.2.2. | Occupancy Controls (interior) | control HARDWARE (sensors) is not modeled as objects; area-threshold occupancy-sensor space-type cloning is 2011-only machinery (no-op in 2015+, out of scope) |
| openstudio-lighting | 4.2.2.3.-4.2.2.12. | Other interior lighting controls (daylighting, exterior cont | photocontrol ENERGY evaluation not modeled; 8.4.4.5.(5)-(12) reference daylighting geometry not modeled |
| openstudio-shw | 6.2.2.1. | Service water heater performance (Table 6.2.2.1) | solar-thermal and pool-heater classes not modeled (legacy scope); HPWH uses the bounded pumped-condenser construction (upstream stratified-tank/EMS recipe not p |
| openstudio-loads | 8.4.3.2. | Operating Schedules, Internal Loads, Service Water Heating L | lighting power + lighting schedules provided by the openstudio-lighting gem (apply it after apply_loads); service-water-heating loads + SWH schedules provided b |
| openstudio-hvac | 8.4.4.10. | Cooling Systems | Terminal/secondary capacity split (7) and DX multi-stage modeling (8) are sizing-time refinements not yet modeled. |
| openstudio-hvac | 8.4.4.11. | Cooling Tower Systems | 35/29 C inlet/outlet, 24 C wb rating and condenser pump specifics are not explicitly set (host/sizing refinements). |
| openstudio-hvac | 8.4.4.12. | Cooling with Outside Air (economizers) | systems 2/5 route to the 5.2.2.9 WATER economizer (hydronic, not modeled — loud warning); DX staging clauses 5.2.2.8.(4)-(5) not enforced |
| openstudio-hvac | 8.4.4.13. | Heat Pumps | Capacity rules (2)(b)-(c) (cooling-peak sizing without oversizing, 8.3/-8.3 C capacity profile) and the 33% auxiliary-fuel election (2)(g) are sizing/annual-ene |
| openstudio-hvac | 8.4.4.14. | Hydronic Pumps | Pump head/efficiency identical-to-proposed (1), combined-pump consolidation (2) and pump power-vs-flow curves (4) are not yet transferred from the proposed mode |
| openstudio-hvac | 8.4.4.18. | Supply Air Systems (airflow rates, fan specs) | Supply-airflow determination at 21/11 C deltas ((1)-(2)) is sizing-time; sentences (5)-(6) (identical fan power / 5.2.12.1-included fan energy) are not modeled. |
| openstudio-shw | 8.4.4.20.(3)-(4) | Remaining reference SWH sentences | sentence text falls in a PDF-extraction chunk gap; not machine-verified |
| openstudio-lighting | 8.4.4.5.(3) | Occupancy/personal control factors in the reference | strict reading multiplies installed power by Focc x Fpers |
| openstudio-lighting | 8.4.4.5.(5)-(12) | Reference daylighting geometry + photocontrols | sentences (5)-(8) analytic single-centered-window/skylight AREA convention replaced by the ported 4.2.2 threshold geometry on the actual scaled fenestration (au |
| openstudio-hvac | 8.4.4.6. | Purchased Energy | Capacity-ratio clauses (1)(b)/(2)(b) are sizing-time and not enforced; purchased SHW (3) is host-scope. |
| openstudio-hvac | 8.4.4.9. | Heating System | Terminal/secondary capacity split (3), multi-energy capacity ratios (5), and furnace multi-stage modeling (7: staged objects) are sizing-time refinements not ye |

## Not implemented (warns every run) (3)

| Gem | Article | Title | Notes |
|---|---|---|---|
| openstudio-envelope | 3.2.4.1. | Air Leakage | air-barrier requirements are not modeled (documented future) |
| openstudio-shw | 6.2.3.-6.2.7. | SWH controls, piping insulation, pools, booster heaters | piping insulation, temperature maintenance controls, pool covers etc. not modeled (legacy scope) |
| openstudio-hvac | 8.4.4.16. | Space Temperature Control (radiant workaround, throttling ra | Radiant-system +-2 C schedule adjustment (1) and throttling-range matching (2) are not applied (only relevant when the proposed design has radiant systems). |

## Beyond the manifests: scope decisions

Implemented in the umbrella (openstudio-necb) without per-gem manifests:
- **Section 10 energy performance tiers** (Table 10.1.2.1, verified identical 2020/2025): reported on every annual determination.
- **NECB 2025 8.4.4 archetype-EUI path** (`path: :eui`): BET = sum(A_i x EUI_i) + PL from Table 8.4.4.1 — no reference building; applicability guards (>= 90% archetype floor area, HDD < 9000) warn.
- **NECB 2025 Part 11 operational GHG levels** (A-F) from the provincial emission factors (Tables 11.4.1.1/11.4.2.1).
- **Part 5 prescriptive QAQC checker** (openstudio-hvac `check_part5`, first slice): economizer capability 5.2.2.8, heat-recovery trigger 5.2.10.1, equipment minimums 5.2.12 (clone-and-diff; sized equipment required for capacity bins).

Deliberately out of scope (by design, not oversight):
- **Trade-off paths 3.3 / 4.3 / 6.3** — superseded by the performance path for this family's purpose (the 4.3.2.10 factors ARE used by the lighting gem).
- **Part 7 (electrical power & monitoring)** — not energy-model-expressible; nothing in legacy either.
- **Part 5 remainder** (duct/pipe insulation, fan power limits 5.2.3, controls 5.2.8, VAV 5.2.11) — future checker slices.
- **8.4.3.6-8.4.3.9** (semi-heated set-points, ice rinks, pools) — niche; unmodeled in legacy.
- **Air barriers (3.2.4)** and **SHW secondary requirements (6.2.3-6.2.7)** — construction-spec items with no energy-model expression.
- **2011/2015/2017 vintage backfills** — user-deferred.
