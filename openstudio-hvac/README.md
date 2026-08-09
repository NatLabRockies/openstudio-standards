# openstudio-hvac

Build HVAC system **topologies** on OpenStudio thermal zones by **descriptive, fuel-encoding
system name** — no standards metadata, no pre-existing systems, no sizing runs required.

Incubating inside the openstudio-standards repository as an independent, SDK-only gem
(`require 'openstudio'` is the only runtime dependency). Topology only by design: sizing runs
and code-efficiency application are the host application's job (e.g. openstudio-standards,
whose data-driven efficiency pass applies to any topology, including systems built here).

## Start here: the visual catalog

```ruby
require 'openstudio_hvac'
OpenStudioHVAC.catalog_html('catalog.html')
```

renders a searchable, build-verified HTML catalog of **every system in the
gem** — one schematic diagram per catalog row (air loops, plants, zone
equipment), with names, families, and config. If you are a mechanical
engineer deciding whether the system you need exists, open that file first.

`ruby scripts/regenerate_catalog.rb` rebuilds the gem-root artifacts
(`SYSTEM_CATALOG.html` / `.csv` / `.txt`) — run it after any `systems.json` edit.

The public entry points, one line each:

| Call | What it does |
|---|---|
| `OpenStudioHVAC.systems` | list the catalog (names, families, config) |
| `OpenStudioHVAC.build_system(model, name, zones, ...)` | build a catalog system's topology on zones |
| `OpenStudioHVAC.remove_hvac_from_zones(model, zones)` | zone-scoped teardown (incl. orphaned plants) |
| `OpenStudioHVAC.cost(model, ...)` | capital costing of a SIZED model |
| `OpenStudioHVAC.characterize(model)` | ANY model's HVAC → neutral facts hash |
| `OpenStudioHVAC.replace_system(...)` | teardown + build, preserving exhaust fans |
| `OpenStudioHVAC.catalog_html(path)` / `.model_hvac_diagrams(model)` / `.hvac_icon_defs` | diagrams |
| `OpenStudioHVAC::NECB.reference_hvac(model, vintage:, ...)` | the 8.4.4 proposed→reference transform |
| `OpenStudioHVAC::NECB.apply_efficiencies(model, vintage:, ...)` | Table 5.2.12.1 minimums on a sized model |
| `OpenStudioHVAC::NECB.apply_energy_recovery(model, vintage:, hdd:)` | the 5.2.10.1 ERV determination (post-sizing) |
| `OpenStudioHVAC::NECB.prepare_for_resizing(model)` | release hard-set pump power before re-sizing |
| `OpenStudioHVAC::NECB.apply_economizer_thresholds(model)` | 5.2.2.7 economizer triggers (post-sizing) |
| `OpenStudioHVAC::NECB.check_part5(model, ...)` | warnings-only Part 5 QAQC |

## Usage

```ruby
require 'openstudio_hvac'

# Discover the catalog (a closed, validated vocabulary — MCP/tool friendly)
OpenStudioHVAC.systems(filter: 'Gas')
# => [{ 'name' => 'PSZ RTU Gas and DX Coils and Hot Water Baseboard', 'family' => 'psz', ... }, ...]

# Build a system on a set of zones. The name IS the fuel specification.
result = OpenStudioHVAC.build_system(
  model,
  'PSZ RTU Gas and DX Coils and Hot Water Baseboard',
  zones,
  control_zone: zones.first,       # explicit control zone: no sizing run needed to elect one
  remove_existing: false,          # true = zone-scoped teardown first (replace, don't stack)
  namer: :default                  # :necb_pipe_name reproduces the NECB naming convention
)
result.air_loops    # => [OpenStudio::Model::AirLoopHVAC]
result.control_zone
```

Preconditions (validated with clear errors): zones must carry dual-setpoint thermostats;
the control zone must be one of the served zones.

### Sizing and efficiencies

```ruby
# 1. topology (this gem)
OpenStudioHVAC.build_system(model, 'PSZ RTU Electric and DX Coils and Electric Baseboard', zones)

# 2. sizing: any runner. The gem is SDK-only and never executes simulations — it only
#    READS hard/autosized values afterwards. Pure SDK + openstudio CLI, no other gems
#    (smoke-tested recipe; needs a weather file + its .ddy design days):
ddy = OpenStudio::EnergyPlus.loadAndTranslateIdf(ddy_path).get
ddy.getDesignDays.each { |dd| model.addObject(dd.clone) }
sim = model.getSimulationControl
sim.setDoZoneSizingCalculation(true)
sim.setDoSystemSizingCalculation(true)
sim.setDoPlantSizingCalculation(true)
sim.setRunSimulationforSizingPeriods(true)
sim.setRunSimulationforWeatherFileRunPeriods(false)
model.save("#{sizing_dir}/in.osm", true)
osw = OpenStudio::WorkflowJSON.new
osw.setSeedFile("#{sizing_dir}/in.osm")
osw.saveAs("#{sizing_dir}/in.osw")
system("openstudio run -w #{sizing_dir}/in.osw")
model.setSqlFile(OpenStudio::SqlFile.new(OpenStudio::Path.new("#{sizing_dir}/run/eplusout.sql")))
# -> autosized accessors (capacities/flows) now resolve on the model
#    (openstudio-standards users can equivalently call model_run_sizing_run)

# 3. code efficiencies: NATIVE for NECB 2020/2025 (capacity-binned COP/EER/thermal
#    efficiencies + NECB performance curves, parity-gated 0-mismatch vs the legacy pass):
OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020')
```

For vintages the gem has not vendored yet (NECB 2011–2017) or non-NECB standards, the
host efficiency pass remains the alternative and lands cleanly on gem-built coils
(coil naming is aligned to its dispatch):
`standard.model_apply_hvac_efficiency_standard(model, 'NECB HDD Method')`.

## Catalog

**97 catalog names across 18 families** — all NECB reference systems sys1–sys6
including the reference heat-pump variants, the complete NECB ECM set
(hs08–hs16), and the CBECS descriptive types. The table below is generated
from `lib/openstudio_hvac/data/systems.json` (regenerate with the one-liner
under it — never hand-edit the counts):

| Family | Rows | Example |
|---|---|---|
| `baseboards` | 3 | `Baseboard electric` |
| `composite` | 12 | `DOAS with VRF` |
| `doas` | 1 | `DOAS ventilation only` |
| `doas_pthp` | 1 | `hs11_ashp_pthp` |
| `ecm_ashp_baseboard` | 2 | `hs12_ashp_baseboard` |
| `ecm_doas_vrf` | 2 | `hs13_ashp_vrf` |
| `ecm_hp_fancoils` | 3 | `hs14_cgshp_fancoils` |
| `evap_cooler` | 1 | `Direct evap coolers with no heat` |
| `fan_coils` | 16 | `FPFC MAU DX Coils with Scroll Chiller` |
| `furnace` | 1 | `Forced air furnace` |
| `mau_ptac` | 8 | `PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC` |
| `psz` | 20 | `PSZ-AC with gas coil` |
| `unit_heaters` | 2 | `Gas unit heaters` |
| `vav_reheat` | 18 | `PVAV with gas boiler reheat` |
| `vrf` | 1 | `VRF` |
| `wshp` | 1 | `Water source heat pumps` |
| `zone_ervs` | 1 | `Zone ERVs` |
| `zone_terminal` | 4 | `PTHP` |

```bash
ruby -rjson -e 'rows = JSON.parse(File.read("lib/openstudio_hvac/data/systems.json"))["systems"]
puts "#{rows.size} rows"; rows.group_by { |r| r["family"] }.sort.each { |f, rs|
puts "| `#{f}` | #{rs.size} | `#{rs.map { |r| r["name"] }.min_by(&:length)}` |" }'
```

The NECB core families: `mau_ptac` = sys1 (100% OA make-up air unit +
per-zone PTAC + baseboards); `fan_coils` = sys2/sys5 (per-zone two/four-pipe
fan coils + CV make-up air unit); `psz` = sys3/sys4 (packaged single-zone
rooftop units); `vav_reheat` = sys6 (per-storey built-up VAV, supply+return
fans, CHW/CW plant). Every NECB family is parity-verified against the legacy
openstudio-standards builders (object inventory, sizing fields, quirks and
all — pipe-names byte-identical), and the topology + host-efficiency contract
is integration-verified (capacity-binned values + reference curves land on
gem-built coils after the host's sizing/efficiency pass).

### CBECS names (first increment)

CBECS descriptive types build through the same families (`origin: "cbecs"` rows; no NECB
sizing block — the host's sizing conventions apply):

| CBECS name | Family | Notes |
|---|---|---|
| `Baseboard electric` / `Baseboard gas boiler` | `baseboards` | zone baseboards only, no air system |
| `PSZ-AC with electric coil` / `... gas coil` / `... electric baseboard heat` / `... gas boiler` | `psz` (`per_zone: true`) | **one packaged unit per zone** (the CBECS/90.1 convention); gas-boiler variant puts hot-water coils on each unit |
| `PTAC with baseboard electric` / `... gas boiler` | `zone_terminal` | **self-ventilating** no-heat PTACs (cooling + OA) with baseboards doing the heating |
| `PTHP` | `zone_terminal` | per-zone packaged terminal heat pumps (DX heat/cool + electric supplemental) |
| `Window AC with baseboard electric` | `zone_terminal` | cooling-only window units (EER 8.5) + electric baseboards |
| `Gas unit heaters` / `Electric unit heaters` | `unit_heaters` | per-zone unit heaters, CV fan |
| `VAV chiller with gas boiler reheat` | `vav_reheat` | central VAV + CHW cooling + gas-boiler HW heat/reheat |
| `Forced air furnace` / `Residential AC with baseboard electric` | `furnace` (+composite) | per-zone CV furnace / cooling-only central AC loops |
| `Baseboard district hot water` | `baseboards` (`hw_source: 'district'`) | hot-water baseboards on a district-heating loop, no boilers |
| `PVAV with gas boiler reheat` | `vav_reheat` (`cooling_type: 'dx'`) | packaged VAV: two-speed DX cooling, gas-boiler HW heat/reheat |
| `Direct evap coolers with baseboard electric` / `... no heat` | `evap_cooler` (+composite) | per-zone direct evap coolers, supply follows outdoor wet-bulb (legacy EMS availability program not replicated — documented) |
| `VRF` / `DOAS with VRF` | `vrf` (+composite) | outdoor VRF unit + zone terminals; standalone terminals self-ventilate, the DOAS composite zeroes terminal OA |
| `DOAS with water source heat pumps {fluid cooler, cooling tower} with boiler` / `... with ground source heat pump` | `composite` (`doas` + `wshp`) | HP condenser loop + per-zone water-to-air HPs; DOAS ventilates. `heat_rejection`: fluid cooler / cooling tower / vertical ground HX (GSHP — no boiler) |
| `DOAS with fan coil {chiller, air-cooled chiller, district chilled water} with {boiler, district hot water}` | `composite` (`doas` + `fan_coils` `mau: false`) | DOAS ventilates; no-MAU four-pipe fan coils condition — the full 3×2 matrix via `chw_source` / `hw_source` part configs |
| `Zone ERVs` | `zone_ervs` | per-zone energy recovery ventilators — the `with ERVs` suffix part for composites |

**Composites**: a `composite` catalog row lists `parts` (other catalog names + config overrides)
built on the same zones — the mechanism for the whole CBECS `DOAS with <zone system>` matrix;
additional combinations are catalog data, not code.

Zone partitioning (heated-only zones get unit heaters/baseboards, cooled-only get the system)
remains the caller's job, exactly as in openstudio-standards `add_cbecs_hvac_system`. Any
additional CBECS combination is now composable as a catalog row (a `composite` with `parts`
and per-part `config` overrides) — no new code required.

### NECB reference heat pump names (sys1/3/4 ASHP)

The `necb_reference_hp` variants are now covered — the legacy regional-fuel lookup proved
unnecessary because the supplemental/reheat fuel is **encoded in the name** (e.g. "ASHP with
**Gas** Supp. Heat Coils", "with **Electric** Reheat"):

| Name pattern | Family | Notes |
|---|---|---|
| `PSZ RTU [with exhaust] ASHP with {Gas,Electric} and ASHP with {Gas,Electric} Supp. Heat Coils and {Hot Water,Electric} Baseboard` | `psz` (`heat_source: 'ashp'`) | sys3/sys4 ASHP: DX heat/cool (`_ashp` names, −10 °C compressor cutoff) + supplemental coil, DX sizing factors 1.0/1.3 |
| `PSZ RTU ASHP with {Gas,Electric} and ASHP Coils and {Hot Water,Electric} Baseboard with {Gas,Electric} Reheat` | `mau_ptac` (`reference_hp: true`) | sys1 ASHP: 100% OA MAU with ASHP DX coils, warmest SPM 13–20 °C, Total-load sizing, CAV reheat terminals + baseboards |

sys6's reference-HP variant remains out (the legacy catalog has no descriptions for it;
add rows + a `vav_reheat` DX option if ever needed).

### NECB ECM names — complete (hs08–hs16)

All ECMs are **topology only**: capacity-binned ECM curves/COPs are applied by the host's
`apply_efficiency_ecm_*` pass after sizing, exactly as in the legacy flow (where build-time
curve application is provisional and re-done post-sizing). Structural equipment curves that
the efficiency pass does *not* re-set (hs14's W2W HCAPF/HPOWERF, hs15's CAWHP biquadratics)
ship in `curves.json`.

| ECM name | Family | Notes |
|---|---|---|
| `hs08_ccashp_vrf` / `hs13_ashp_vrf` | `ecm_doas_vrf` | Outdoor VRF unit (heat recovery, −25 °C) + zone VRF terminals + DOAS (CCASHP variable-speed / ASHP single-speed DX) |
| `hs09_ccashp_baseboard` / `hs12_ashp_baseboard` | `ecm_ashp_baseboard` | DOAS (default) + PTAC cooling + baseboards; `vent_type: 'mixed'` gives the multizone-VAV variant (warmest SPM, VV fans, electric-reheat terminals) |
| `hs11_ashp_pthp` | `doas_pthp` | DOAS + ASHP + zone PTHPs |
| `hs14_cgshp_fancoils` | `ecm_hp_fancoils` | Ground-source W2W HP + boiler backup, water/air-cooled chillers, district-modeled GLHX loop, DOAS + 4-pipe fan coils |
| `hs15_cawhp_fancoils` / `hs16_ashp_cawhp_fancoils` | `ecm_hp_fancoils` | Central air-to-water plant-loop-EIR HP companion pair + boiler backup; hs16 adds an ASHP DX DOAS |

Documented deviations from legacy: the `'AirSoure'` typo (a silently failing condenser-type
set on the hs15 heating HP) is corrected to `'AirSource'`; hs14's destructive
`model.getOutputVariables.each(&:remove)` is not replicated (the district-rate output
variables are still added).

## Canonical names — one consolidated grammar

The catalog's legacy names carry three inherited dialects (CBECS fuel-first
`'Baseboard gas boiler'`, NECB medium-first `'... Hot Water Baseboard'`, ECM ids
`'hs11_ashp_pthp'`). They remain the stable keys — byte-matched to their upstream
vocabularies. On top of them, every row gets a **canonical name generated from its
structured config** (so it is consistent by construction and cannot drift):

```
<primary system>[ + <zone equipment>][ (<plant>)]
```

| Legacy | Canonical (generated) |
|---|---|
| `Baseboard gas boiler` | `hot water baseboards (gas boiler)` |
| `PSZ RTU Gas and DX Coils and Hot Water Baseboard` | `packaged single-zone DX with gas heat + hot water baseboards (gas boiler)` |
| `hs08_ccashp_vrf` | `DOAS cold-climate ASHP + VRF` |
| `hs14_cgshp_fancoils` | `four-pipe fan coils on a ground-source heat pump plant` |

`OpenStudioHVAC.systems` lists both (`name` + `canonical_name`); `build_system` and
`Catalog.resolve` accept either (plus optional per-row `aliases`). Canonical names are
verified unique and disjoint from the legacy set, and are the recommended surface for new
code and tool/MCP integrations.

## Costing — all systems, all families

Unlike openstudio-standards (which can only cost NECB/ECM systems, by parsing `SYS_n` from
air-loop names), the gem costs **every family**: because it built the system, the AHU/
distribution assembly class comes from the catalog family — no name parsing.

```ruby
result = OpenStudioHVAC.build_system(model, name, zones)
# ... size the model (host sizing run, or hard-set capacities) ...
report = OpenStudioHVAC.cost(model,
                             systems: [result],        # OPTIONAL: highest-fidelity loop->family map
                             city: 'TORONTO', province_state: 'ONTARIO',  # or inferred from site
                             costs_csv: nil)           # inject licensed values; else placeholders
report.total          # $
report.by_category    # HEATING_COOLING / ZONAL / VENTILATION / DISTRIBUTION
report.items          # re-costable ledger: [{id, quantity, mults, tags, cost}]
report.warnings       # anything uncosted is EXPLICIT (never silent zeros)
report.audit          # AuditLog: classification, selection math, per-item decisions

# GENERAL OSMs: systems: is optional. Unmapped air loops are classified automatically —
# exactly when recognizable (gem catalog names, legacy sys_N pipe names), structurally
# otherwise (multizone VAV -> sys6 class, packaged single-zone -> sys3 class, ...), with
# structural guesses reported as warnings. cost(model) on a foreign OSM costs the whole
# mechanical scope, not just plant/zonal.
# mech_room_name: 'Space 5' pins the mechanical room for geometry-derived items;
# default election matches legacy (Electrical/Mechanical space type, else the
# lowest-storey conditioned space closest to the building centre)
```

- **Requires a sized model** (capacities/flows read from hard or autosized values; some
  fallbacks — hot-water coil capacities, zone heating loads — additionally use the attached
  SQL file when present).
- **What's costed:** plant (boilers by fuel/efficiency bucket, chillers by compressor/condenser
  type, towers, pumps + VFDs, AWHP/GSHP), zonal (PTAC/PTHP/fan coils/VRF terminals + outdoor
  units/baseboards/unit heaters/WSHP/zone ERVs — WSHP/ERV extend legacy coverage), AHU
  assemblies (component layers × quantities), air-loop coil equipment (hydronic/DX/gas/electric
  coils, DX condensing units + refrigerant piping, CCASHP extras), and the **full geometry
  layer** (SDK-only ports of the legacy mech-room/roof-centroid/storey-edge helpers):
  boiler/chiller flues, fuel lines and electrical utility runs, piping-to-pumps, hot/chilled
  water header piping distribution, tower risers, mech-room-to-roof gas/HW/CHW/electrical
  lines, central + floor trunk ducts, per-terminal hydronic piping and electrical runs,
  HW-baseboard copper convectors with perimeter distribution piping/wiring, HRV cores with
  return fans, and per-zone duct distribution (diffusers, ductwork lbs, insulation, flex duct)
  — with RS-Means-style city localization and per-item material/labour multipliers. The
  ledger can be re-priced for any city or custom database.
- **Data & licensing:** vendored CSVs are ~91% `placeholder` values in an RS-Means-derived
  schema (`lib/openstudio_hvac/data/costing/README.md`); real licensed values are injected via
  `costs_csv:` and must never be committed.
- **Parity vs legacy `BTAPCosting` (NECB sys6 on the 5-zone fixture, same sized model):**
  ledger diff is **28/28 ids matched, zero quantity differences, zero one-sided ids**; the
  legacy zonal domain total is reproduced **exactly to the dollar**. The only deviations are
  documented *corrections of a legacy defect*: E+ reports no sized `Rated Capacity` for
  hot-water coils, so legacy misclassifies hydronic AHUs as heat pumps — selecting the wrong
  `hvac_vent_ahu` assembly row (dropping the heating-coil valve-piping set), omitting the
  mech-room-to-roof HW line, and never costing the air-loop HW heating coil. The gem costs
  the correct HW assembly and roof line (the HW coil itself is uncostable from E+ output in
  both implementations — the gem warns, legacy is silent).
- **Documented deferrals (explicit warnings):** district energy connection costs;
  evaporative-cooler media (no unit-cost data exists — legacy never costed it either);
  fan-coil MAU ventilation (matches legacy sys-2 handling).

## NECB performance path: proposed + reference HVAC

Self-contained NECB 2020 reference-HVAC generation (Division B, Subsection 8.4.4) — the
proposed→reference transform the legacy performance-compliance scaffold never implemented:

```ruby
facts  = OpenStudioHVAC.characterize(model)        # ANY OSM -> neutral facts hash
result = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020',
                                             building: { storeys: 3 })  # optional overrides
result.model        # the reference model (clone; the proposed model is untouched)
result.assignments  # per zone group: System 1-6/'hp', catalog name, energy type, articles
result.audit        # AuditLog: every decision with inputs, evidence and article citation
puts result.audit   # human narrative; result.audit.to_json for QAQC pipelines

OpenStudioHVAC::NECB.apply_efficiencies(model, vintage: '2020')  # Table 5.2.12.1, sized model

# ONE audit for compliance + costing: thread a single AuditLog through the pipeline
# and get one chronological, article-tagged narrative (JSON for QAQC, text for humans):
audit  = OpenStudioHVAC::AuditLog.new
ref    = OpenStudioHVAC::NECB.reference_hvac(model, vintage: '2020', audit: audit)
# ... size ref.model ...
report = OpenStudioHVAC.cost(ref.model, audit: audit)
audit.entries.map { |e| e[:step] }.uniq
# => characterize, selection, build, rules, efficiency, coverage,
#    costing_equipment, costing_geometry, costing_classification, ..., costing
```

- **Classifier** (`characterize`): reads arbitrary proposed models via a structural
  loop-composition walk (gem-built and legacy pipe-named systems are recognized exactly);
  yields heated/cooled, heating/cooling energy types (resolved through plant loops), heat
  pumps, purchased energy, terminal types, design cooling kW.
- **Selection** (Table 8.4.4.7.-A): space-type categories + storey bands + the 20 kW
  data-centre threshold; residential heated-only/copy-proposed/through-the-wall rules; the
  8.4.4.13 heat-pump override (reference = packaged rooftop ASHP, System 2 exempt);
  energy type follows the proposed system (8.4.4.9/10), purchased heating represented by
  gas (8.4.4.6). Rules live in `data/necb/reference_rules_2020.json` — generated offline
  from the building-codes MCP server with an article citation on every block; **zero MCP
  dependency at runtime**.
- **Reference modeling rules**: oversizing capped at min(proposed, 30%/10%) (8.4.4.8),
  fan specs (8.4.4.18: sys 1/3/4/5 → 640 Pa @ 40%, no return fan; sys 6 → 1000 Pa @ 55%
  supply + 250 Pa @ 30% return), heat-pump −10 °C heating cutoff (8.4.4.13), purchased
  cooling → air-cooled electric chiller (8.4.4.6.(2)), and **energy recovery
  (8.4.4.19)**: a separate **post-sizing** pass —
  `NECB.apply_energy_recovery(model, vintage:, hdd:)` — evaluates the NECB 2020/2025
  Table 5.2.10.1.-A/-B airflow thresholds (HDD row × %-outdoor-air band ×
  continuous/non-continuous operation) per reference air loop and adds the rotary
  HX @ 50% effectiveness with OA-pretreat control where required. It needs SIZED
  supply/OA flows, so call it AFTER the reference sizing run (unsized loops warn
  loudly; the umbrella pipeline sequences this automatically). Proposed zone
  exhaust fans are preserved through `replace_system` (8.4.4.17.(1)).
- **Article-coverage accounting**: every audit ends with a `:coverage` section listing
  **all 20 articles** of the reference subsection with a handling status
  (implemented / partial / not-implemented / satisfied-by-clone / host-scope), the
  number of decisions that cited each article in that run, and the declared gaps —
  partial and unimplemented articles surface as **warnings in every log** (e.g.
  ice-plant heat recovery 8.4.4.18, radiant workaround 8.4.4.16), so a missed requirement is
  visible per run rather than discovered in review. The manifest lives in the rules
  JSON and is lint-tested for completeness on both vintages.
- **Efficiencies** (`apply_efficiencies`): SDK-only port of the NECB pass — boilers
  (incl. 176/352 kW primary/secondary staging), chillers (2100 kW split, 25% modulating
  floor, tower cell/fan rules), single-speed DX cooling/heating, gas coils, with the
  vendored Table 5.2.12.1 tables + 31 NECB performance curves
  (`data/necb/efficiencies_2020.json`). **Parity-gated:** 0 mismatches vs legacy
  `model_apply_hvac_efficiency_standard` (NECB2020) across efficiencies, COPs, staging,
  curves and tower sizing on sys3/sys6/reference-HP.
- **Audit-first**: every decision (classification evidence, rule row + inputs, build
  action, `min(proposed 1.5, cap 1.3)` arithmetic, table row per efficiency value)
  carries its NECB article — QAQC reads the log instead of diffing models. Warnings are
  never silent (unsized capacities, unlisted space types per 8.4.4.7.(3)).
- **Vintages**: NECB **2020** and **2025**, both fully native. 2025 renumbered the
  performance path (8.4.4 → 8.4.5; rule values verified identical via the MCP edition
  diff), so `vintage: '2025'` produces the same selections with 2025 article citations.
  2025 efficiencies are transcribed from the 2025 Table 5.2.12.1 series (chillers/
  boilers/furnaces/EER ladder verified identical; real changes: small HP cooling
  EER 11 → SEER 15, split HP heating HSPF 7.4 → 7.8; SEER2/HSPF2 classes carried as
  distinct rows). 2011–2017 are data drops away.
- **Scope/limits (v1)**: HVAC only (envelope/lighting/SHW reference rules and compliance
  simulation stay host-side); the gem never runs simulations — size the proposed model
  first for capacity-threshold rules, and re-run `apply_efficiencies` after sizing the
  reference model.

## Design notes

- **The name is the API.** Each catalog row fully specifies topology + fuels/coils/baseboard,
  like CBECS's `'Baseboard gas boiler'` and NECB's systems.json descriptions.
- **`control_zone:` is a first-class parameter.** Single-zone systems (one air handler tracking
  one thermostat over several zones) traditionally elected the control zone by largest heating
  load, requiring a sizing run and standards-tagged geometry. Naming it explicitly removes that
  dependency entirely.
- **NECB behavior is data** (`lib/openstudio_hvac/data/`): sizing blocks (`sizing.json`),
  reference performance curves (`curves.json`), and the catalog (`systems.json`).
- **Naming is pluggable.** `:necb_pipe_name` byte-matches the legacy
  `sys_3|mixed|shr>none|...` convention (verified against openstudio-standards output) for
  hosts whose downstream code parses those names.
- **Zone-scoped teardown** (`remove_existing:`) replaces systems on the given zones only,
  including orphaned plant loops (water-cooled chiller → condenser chains handled via a
  fixpoint), preserving service-hot-water loops and other zones' systems.

## Citation conventions (`article:`, `ruling:`, and the letter registers)

Audit entries and code comments in this gem carry two citation axes:

- **`article:`** — the NECB clause that mandates a value or step
  (e.g. `8.4.4.7.(4)`).
- **`ruling: 'D-nn'`** — the adjudicated *reading* of that clause where
  interpretation was required (e.g. `D-56` = the sys2/sys5 water-side
  economizer). The registry is
  [openstudio-necb/docs/necb_decisions.md](../openstudio-necb/docs/necb_decisions.md)
  (human prose, with an id-ordered index at the top) mirrored in
  `openstudio-necb/lib/openstudio_necb/data/decisions.json`
  (machine-readable, drift-tested both ways).

Comments may also cite `L-nn` (legacy-implementation findings,
`openstudio-necb/docs/legacy_findings.md`) and `T-n` / `A-n` (the archived
2026-07-25 reference-systems audit registers — drained into D-22/D-34…D-45;
kept as evidence). The family glossary — on-ramp, gate, bump, fleet, TTW and
friends — lives in
[openstudio-necb/docs/README.md](../openstudio-necb/docs/README.md).

## Tests

```bash
cd openstudio-hvac
ruby test/test_catalog.rb
ruby test/test_naming.rb
ruby test/test_psz.rb
# full proposed -> reference -> EnergyPlus gate (4 E+ executions, ~1-2 min;
# skips automatically when the openstudio CLI is unavailable):
ruby test/test_necb_e2e_run.rb
```

`test_necb_e2e_run.rb` is the simulation gate: gem-built proposed systems and their NECB
references must translate, size, and run in EnergyPlus with **no Fatal and no Severe
errors**, and the week-long runs must **actually condition the zones** — facility
"Time Setpoint Not Met During Occupied" hours are asserted (≤ 24 h heating / ≤ 6 h
cooling for the simulated January week; a miswired system fails every occupied hour).
Scenarios: a design-day sizing run for the sys3 reference (with efficiencies landing on
the sized results); a one-week Toronto January run of the **ASHP reference** — cold
enough to force operation below the −10 °C compressor cutoff, so the unmet-hours gate
proves the supplemental heat + baseboards carry the load through heat-pump lockout; and
a one-week run of a sys6 reference with its 8.4.4.19 ERV active (VAV + plants + rotary
HX + OA-pretreat controls at runtime, verified to produce HVAC energy). Weather
fixtures (Toronto EPW/DDY/STAT) ship in `test/fixtures/weather/` so the suite is
self-contained.

Plain ruby + the OpenStudio SDK bindings — no bundler required.

## Sibling and umbrella gems

- [openstudio-envelope](../openstudio-envelope) — the envelope domain gem
  (prescriptive 3.2, thermal bridging via TBD, the reference-envelope transform,
  envelope + thermal-bridging costing), same AuditLog schema.
- [openstudio-necb](../openstudio-necb) — the umbrella: composes the five domain
  gems (this one + envelope, loads, lighting, shw) into the full NECB 8.4.1.2
  performance-path determination (proposed vs reference, sizing/annual
  simulation via openstudio-simulation, unified costing, one audit).
- [openstudio-loads](../openstudio-loads) — NECB space-use loads and schedules
  (people, plug loads, ventilation OA, NECB schedule sets, set-points): the
  bare-geometry on-ramp that makes gem-only proposed buildings possible.
- [openstudio-lighting](../openstudio-lighting) — NECB Part 4 lighting (LPD
  allowances, occupancy-sensor schedules, LED, exterior allowances, reference
  lighting, fixture costing), built on openstudio-loads.
- [openstudio-shw](../openstudio-shw) — NECB Part 6 service water heating
  (demand from space-type data, auto-sized plant, Table 6.2.2.1 UEF
  efficiencies, reference treatment, costing on this gem's engine), built on
  openstudio-loads.
- [openstudio-geometry](../openstudio-geometry) — parametric massing (footprint
  wizards + the Goldwasser bar engine with NECB space types assigned by ratio):
  the authoring on-ramp that makes the whole chain gem-only from nothing.
