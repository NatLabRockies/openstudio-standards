3. **✅ Renames — DONE** (D-67): `heat_source: 'ashp'` in systems.json
   (aliased); geometry facade `storeys:` unification (aliased); lighting
   `option:`/`placement:` collapse (deprecated alias); `H` → `Html`
   (aliased); sprint-named test files renamed.# Code clarity & organization review — the seven-gem family

**Date:** 2026-08-09. **Scope:** all seven domain gems + the openstudio-necb
umbrella (~25,000 lines, 110 files). **Reviewed by:** three independent
fresh-eyes sweeps (openstudio-hvac; umbrella + simulation; the five smaller
domain gems), findings verified against the code at head of `phylroy_dnd`.

**The audience test applied throughout:** could a mechanical engineer — who
knows HVAC, NECB article numbering, and EnergyPlus, with moderate Ruby —
pick each gem up in 30 minutes with no author to ask?

**Status column:** ✅ fixed in this pass · 🔶 recommendation (your call —
API rename, file split, or legal/process decision) · ⏳ proposed, awaiting
your go-ahead (test-covered but higher-churn).

---

## Verdict

**The inline engineering prose is unusually good — the navigation layer is
what fails the engineer test.** Nearly every non-obvious branch carries a
WHY comment citing the NECB article, often with the measurement that decided
it (`psz.rb:88-96` on supplemental-coil placement; `efficiency.rb:400-405` on
the 724%-pump-efficiency FATAL; `runner.rb:22-30` on design-day replacement).
The failures are at the front door and the map:

1. **READMEs have drifted factually behind the code** — ~15 hard breaks,
   several of which actively mislead: examples that raise, an energy-recovery
   API that no longer exists, NECB article numbers that don't exist in
   2020/2025, a catalog half its real size.
2. **The house dialect has no glossary.** `ruling: 'D-56'` appears 196 times
   in openstudio-hvac alone and is defined only in a sibling gem's docs;
   "on-ramp", "gate", "bump", "secant", "fixed-point", "TTW", "fleet" are
   never defined anywhere.
3. **Nothing separates API from internals.** Zero `private` markers across
   the family publish ~370 module methods where ~25 are intended API; YARD
   `@param`/`@return` coverage is ~15%.
4. **A handful of monoliths.** `performance_compliance` is 238 lines with 24
   keyword arguments (7 undocumented); `bar.rb` has a 517-line method, broken
   indentation, and a YARD block attached to the wrong method;
   `reference.rb`'s last 672 lines have no section banners.

None of these are craft problems — the code underneath is disciplined. They
are discoverability problems, and most were cheap to fix.

---

## openstudio-necb (umbrella)

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🔴 | README's `eui_supplement` example uses the **removed** `archetype_areas:` kwarg — following it raises `ArgumentError` | `README.md` vs `compliance.rb` (requires `archetypes:`) | ✅ |
| 🔴 | README's pipeline order is pre-D-52: it puts the annual runs after the reference build; the code runs the proposed annual FIRST. Three conflicting numbered pipelines exist (README, CLAUDE.md, code comments) | `README.md` step 7 vs `compliance.rb` step 1b | ✅ one canonical numbering |
| 🔴 | README says the umbrella composes "two domain gems"; it composes six. The gemspec declares only three — an installed-gem (non-monorepo) build fails to load | `README.md:3-11`, `openstudio-necb.gemspec` | ✅ README + gemspec |
| 🟠 | The second compliance path (`path: :eui`, NECB 2025 8.4.4) appears nowhere in the README | grep `path:` → 0 hits | ✅ |
| 🟠 | `performance_compliance`: 238 lines, 24 kwargs, **7 undocumented** — including `province_state` (gates the whole Part 11 GHG determination) and `eui_supplement` (gates the second path); `@return` sits mid-parameter-list | `compliance.rb:78-315` | ✅ options table + YARD; ⏳ decomposition into named phase methods (see below) |
| 🟠 | The `begin`/`rescue` wrapper is invisible: `begin` at `:102`, body deliberately un-indented for 208 lines, `rescue` at `:311` | `compliance.rb` | ⏳ fixed by the decomposition |
| 🟠 | Zero `private` markers: `Compliance` publishes 30 methods, 1 is the entry point | whole gem | ✅ private_class_method |
| 🟠 | `report/diagrams.rb` (54 lines) is dead code — zero callers; still `require`d | `report.rb:6` | ✅ deleted |
| 🟠 | Contradictory claims about which report files touch the SDK (`model_query.rb:3` "the ONLY" vs `report.rb:39` "the only") | both headers | ✅ stated once, correctly |
| 🟡 | `necb_decisions.md` (3,444 lines) is chronological with IDs out of numeric order (…D-52, D-60, D-59, D-58, D-53…) and has no TOC | headings | ✅ generated TOC |
| 🟡 | `report/` split (svg→charts→html→checklist→model_query→sections→report) is good layered design, invisible — seven bare requires | `report.rb:1-7` | ✅ stack map comment |
| 🟡 | `sections.rb` hand-numbered `# -- N` markers drifted vs `ORDER`; helpers interleaved | `sections.rb:28-532` | ✅ |
| 🟡 | `archetypes.rb` bang methods: `resolve!`/`applicability!` don't mutate; `normalize!` does | `archetypes.rb:59,125,225` | ✅ renamed `resolve`/`verify_applicability!` (aliased); file → `eui_archetypes.rb` disambiguating the two senses of "archetype" |
| 🟡 | `H` single-letter module used ~150× in the renderer | `report/html.rb:5` | ✅ renamed `Html` (`H` aliased) |
| 🟡 | `eui_compliance` duplicates ~40 lines of load/validate/weather/report scaffolding | `compliance.rb:405-499` | ⏳ shared scaffold in decomposition |

**Also good:** the Modes table and the 8.4.1.2 sentence-by-sentence intro in
the README are the best explanation of the determination anywhere in the
repo; `checklist.rb` documents its case-sensitivity contract precisely; the
runtime data JSONs all carry provenance blocks (exemplary).

## openstudio-hvac

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🔴 | README: "44 catalog names"; the catalog has **97 rows, 18 families**. The headline family table lists 4 of 17 builder families — an engineer looking for DOAS/WSHP/VRF concludes they don't exist | `README.md:74-81` vs `data/systems.json`, `builder.rb:4-22` | ✅ table generated from systems.json |
| 🔴 | README documents the **removed** 150 kW exhaust-heat ERV trigger as part of `reference_hvac` ("no sizing run needed"); the real API is a separate post-sizing `apply_energy_recovery(model, vintage:, hdd:)`. A user following the README gets a reference model with **no energy recovery and no error** | `README.md:286-293` vs `necb/reference.rb:1270` | ✅ |
| 🔴 | README contradicts itself on reference heat pumps: "now covered" (§ at :123) vs "out of scope for now" (:158); the stale claim is also in `systems.json`'s comment | `README.md`, `data/systems.json` | ✅ |
| 🟠 | 7 of ~13 public entry points absent from the README — including `catalog_html`, which renders the build-verified diagram catalog of all 97 systems (exactly what an engineer needs first) | `lib/openstudio_hvac.rb:94-115` | ✅ + "Start here" block |
| 🟠 | `ruling: 'D-nn'` — 196 occurrences, 36 distinct IDs, **defined nowhere in this gem**; three more undefined citation namespaces (`T7`, `L-23`, `A1`) layered on top | throughout | ✅ citation-conventions section |
| 🟠 | Zero `private` in the four big modules: `NECB` publishes 51 methods (~5 intended), `Efficiency` 56, `Classify` 31, `CatalogReport` 87 | grep | ✅ private_class_method |
| 🟠 | `necb/reference.rb`: section banners stop at line 940; the last 672 lines cover six unrelated topics unmarked | `reference.rb:1146-1611` | ✅ banners |
| 🟠 | `systems/small_systems.rb` holds six unrelated system families (Furnace, EvapCooler, Wshp, Vrf, ZoneErvs, Doas) — named for a code-size property, not a domain one; `UnitHeaters` hides in `zone_terminal.rb` | `small_systems.rb` | ✅ split per family + `unit_heaters.rb` (follow-up pass) |
| 🟠 | Oversizing-cap sentinels 1.3/1.1/1.0 hardcoded in Ruby duplicate `data/sizing.json` — the 8.4.4.8 cap silently stops working if the JSON changes | `reference.rb:1437-1444` | ✅ named constants citing the JSON |
| 🟠 | 20-line block of uncited VRF constants (`COP 4.0`, `26.2 °C`, `-0.00019231`); similar bare numbers in `small_systems.rb`, `hp_plant_fancoils.rb`, `zone_terminal.rb`; `vav_reheat.rb:151`'s only justification is the undefined token "T11" | `components/ecm_air.rb:223-242` etc. | ✅ source note per line |
| 🟠 | `systems.json` config vocabulary: three ways to say heating, two for cooling, three for ventilation, case-inconsistent values, and `heating_coil_type: 'DX'` semantically meaning "this is an ASHP" | 30 distinct keys, no schema doc | ✅ schema README + frozen schema lint; ✅ `heat_source: 'ashp'` rename (aliased, D-67) |
| 🟠 | YARD coverage ~15%; near-zero in exactly the two files that implement the code (`reference.rb` 2/51, `efficiency.rb` 9/56); the flagship `to_html` docstring is attached to a constant, not the method | measured per file | ✅ tag public surface + fix orphan |
| 🟡 | ~~Sprint-named test files: `test_thin_tail.rb` (contains the VRF/ERV/GSHP tests), `test_cbecs_backlog.rb`~~ — renamed to `test_vrf_erv_gshp_composites.rb` / `test_cbecs_families.rb` | `test/` | ✅ renamed |
| 🟡 | `family_guess` holds either a real mapping (String) or an actual guess (Symbol) — "the name lies half the time"; `loop_` trailing-underscore workaround ×47; `row` = string label in one method, table hash in another | `classify.rb`, `efficiency.rb:451` | 🔶 |
| 🟡 | 2.6 MB generated `SYSTEM_CATALOG.html` (+ .csv/.txt) at gem root, unexplained (correction: they are GITIGNORED build output, not committed); gemspec ships a nonexistent `LICENSE*` | gem root | ✅ regeneration script + README line; LICENSE handled in the gemspec pass |

**Also good:** the facade file is a genuinely good API index; `Catalog.resolve`
raises with closest-match suggestions; `teardown.rb`'s numbered-steps style is
the house standard; `data/necb/README.md` + `data/costing/README.md` are model
provenance docs; domain naming (`pressure_rise_pa`, `w_per_kw`,
`mau_heating_coil_type`) reads like a mechanical spec.

## openstudio-lighting

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🔴 | README cites **NECB articles that do not exist** (4.2.2.7/4.2.2.9/4.2.2.10 — 2011 numbers; the code's own CITATION HYGIENE block says 4.2.2 ends at 4.2.2.6). An engineer opens NECB 2020, fails to find them, and distrusts the gem | `README.md:91-93` vs `necb/daylighting.rb:32-38` | ✅ |
| 🔴 | README documents the legacy-2011 path as the default; the code default is `placement: :necb2020` (new union-polygon geometry, none of the preserved defects) | `README.md:83-100` vs `daylighting.rb:260` | ✅ |
| 🟠 | README contradicts itself ×3 on whether reference daylighting shipped ("loud gap" / "documented future" / a full section documenting it as shipped) | `README.md:45,77,102` | ✅ |
| 🟠 | Stale hardware description: "stepped ×2", "zone primary at 1.0"; code: 3 steps, computed daylighted-area fraction (physically significant) | `daylighting.rb:43,301` | ✅ |
| 🟡 | Two overlapping knobs (`option:` and `placement:`) where one enum would do; `option: 'all'` silently ignores `placement:` | `daylighting.rb:260-275` | ✅ collapsed to `placement:` (`option:` deprecated alias, audit-warned) |
| 🟡 | `daylighting.rb` still contains the legacy area math that `daylighted_areas.rb` replaces — "how is daylighted area computed?" has two answers in two files (correctly labelled, but…) | `daylighting.rb:45-190` | ✅ quarantined into `daylighted_areas_legacy_2011.rb` (constant paths unchanged) |
| 🟡 | `data/costing/` has no provenance README (siblings have one) | — | ✅ |

**Also good — hold this up as the family standard:** the three daylighting
files are *clearly* delineated, each opening by stating its job and why it is
not one of the others; `daylight_control_requirement.rb` derives the power
test from the code text instead of asserting it and defines five honest
states including `unknown`.

## openstudio-envelope

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🟠 | Facade exposes only `.cost`; the three headline entry points the README teaches live as delegators at the bottom of leaf files | `openstudio_envelope.rb` vs `prescriptive.rb:338`, `reference.rb:384` | ✅ facade delegators added |
| 🟠 | Quick-start's first line doesn't run (String path where the SDK needs `OpenStudio::Path`) | `README.md:30` | ✅ |
| 🟡 | Facade header advertises an unfinished "P1 (this commit) → P4" build-out that is finished | `openstudio_envelope.rb:13-15` | ✅ |
| 🟡 | `ENCLOSURE_R = 1.0 / 6.25` directly under a comment about "overall U of 6.25"; `U_FALLBACK = 0.110` cited to a legacy source line, not an article | `prescriptive.rb:38-40`, `rules.rb:10` | ✅ comment; 🔶 rename |

Strongest gem of the five smaller ones — `prescriptive.rb`'s header
(quoting sentence, deriving interpretation, sizing the ~4% film effect) is
model documentation.

## openstudio-loads

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🟠 | The boundary table — the gem's best feature — declares openstudio-lighting and openstudio-shw "**future**"; both shipped | `README.md:26-27,105`, facade `:12-14` | ✅ |
| 🟡 | Facade guards requires with `if File.exist?` for files that always exist; "phased build-out" comments | `openstudio_loads.rb:54-56` | ✅ |
| 🟡 | `apply_loads` — the gem's whole purpose — has no top-level facade method while minor `assign_space_types` does | `necb/apply.rb:377` | ✅ delegator added |
| 🟡 | `emit_article_coverage` variant doesn't strip sentence numbers — counts `8.4.3.2.(1)` differently from every sibling gem (reporting-correctness drift) | `apply.rb:302` vs lighting/shw | ✅ aligned |

`necb/apply.rb` is the best-organized file in the family — 15 methods in
narrative order, each stating what it does and what it deliberately doesn't.

## openstudio-shw

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🟠 | **Undeclared runtime dependency**: `costing.rb` requires `OpenStudioHVAC::Costing::*` at load; gemspec declares only openstudio-loads | `costing.rb:2-4` vs gemspec | ✅ |
| 🟠 | Only gem with `data/necb/` and no provenance README — for the most formula-dense data of the five | `data/necb/` | ✅ |
| 🟠 | The JSON carries Table 6.2.2.1 formulas as **inert documentation strings** while live coefficients are hardcoded in Ruby — editing the JSON changes nothing, and nothing says so; bin edges (76/208/380/454 L, 22/30.5 kW) are bare numerals in a 60-line case | `efficiency.rb:44-77` vs `shw_rules_*.json` | ✅ named constants + provenance-only note |
| 🟡 | Weakest YARD of the family (28 defs, 9 `@param`); public costing facade has no doc block; missing `local_factors_csv:` that sibling costing facades accept | `costing.rb:26` | ✅ YARD; 🔶 param parity |

## openstudio-geometry

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| 🔴 | A 30-line YARD block for the deliberately-unported ASHRAE-90.1 wrapper is attached to the wrong method — documenting `:template ('90.1-2013')` on a NECB method taking `(length, width, origin, depth)` | `bar.rb:783-814` → `:815` | ✅ deleted |
| 🟠 | Broken indentation: the last 5 method defs sit at column 0 inside the module — folding, grep, and scanning all break at line 815 | `bar.rb:815-1536` | ✅ re-indented |
| 🟠 | The 3D renderer (215 lines + facade method + 5 tests) is invisible from the README — "Two engines" | `render.rb`, `README.md:5` | ✅ README section |
| 🟠 | `create_bar` is 517 lines with zero internal markers; `create_sliced_bar_simple_polygons` 307 | `bar.rb:10-526` | ✅ step banners |
| 🟠 | Four spellings of one concept in one facade (`storys`/`stories`/`storey`/`storeys`) and two parameter vocabularies for the same idea across `create` vs `bar` | `openstudio_geometry.rb:37` vs `:102` | ✅ facade standardized on `storeys:`/`below_grade_storeys:` (aliased; ambiguity raises) |
| 🟡 | README overclaims below-grade support for all seven wizards (only rectangle/aspect_ratio have it); CLAUDE.md lists an "E" shape that doesn't exist and omits aspect_ratio | `wizards.rb:186`, `CLAUDE.md:3-4` | ✅ |
| 🟡 | `helpers.rb` loads only as a side effect of `wizards.rb`; pseudo-keyword `length = length` anti-pattern in the aspect_ratio wrapper | `openstudio_geometry.rb:3-7`, `wizards.rb:218-225` | ✅ require; 🔶 arg cleanup |

The wizards' 6× repeated skeleton is justified (declared verbatim port) but
now says so; provenance (Goldwasser lineage) was already well stated in code.

## openstudio-simulation

In good shape — the facade states the gem's position and the Backend contract
in 12 lines, and `Remote` is a rare stub that teaches. Only gap: three public
methods missing from the README (`zone_unmet_occupied_hours`,
`request_run_period_variables!`, `run_period_sums`) ✅, and a duplicated
`openstudio_cli?` probe 🔶.

---

## Cross-gem consistency (the five smaller gems especially)

| Sev | Finding | Status |
|---|---|---|
| 🟠 | **Root README mentions none of the seven gems** — an engineer cloning the repo cannot discover them | ✅ family table added |
| 🟠 | `emit_article_coverage` copy-pasted 4×, in 4 different files, **already drifted** (loads variant counts articles differently) | ✅ aligned; 🔶 extract shared |
| 🟠 | `audit_log.rb` copy-pasted 6× by design (sync-tested) — works, but the generated-file banner naming the canonical copy was only in CLAUDE.md | ✅ banner; 🔶 extract `openstudio-audit` gem |
| 🟠 | Facades aren't facades: 8 public delegators live in leaf files; only geometry's facade is complete (and it's the one with no NECB namespace) | ✅ delegators added |
| 🟠 | Gemspec metadata contradicts: **two licenses** (envelope BSD-3-Clause vs LGPL-3.0 elsewhere), two homepages, two author strings; none ships LICENSE except envelope | 🔶 legal/ownership call — flagged, not changed |
| 🟡 | `RULES_DIR` vs `DATA_DIR`; two sibling gems define `NECB.table` with different arity | 🔶 unify |
| 🟡 | Data-JSON naming mostly `<subject>_<vintage>.json` with stragglers (`daylighting_controls_4_2_1_6.json` keyed on an article number) | 🔶 |
| 🟡 | Test-suite naming not parallel (shw/geometry missing `test_data_integrity`/`test_e2e_run`; inverted pairs like `test_apply_lights` ↔ `test_lights_parity`) | 🔶 |
| 🟡 | No family Rakefile — tests run file-by-file only | 🔶 |
| ✅ | `vintage` vocabulary is clean family-wide (`template` appears only in vendored 90.1 rows and one CSV column — now noted) | — |

## Glossary + citation system (new)

`docs/README.md` now carries the family glossary (on-ramp, gate, bump,
stamp, secant, fixed-point, TTW, fleet, zonal/global/mixed, thermal block);
every gem README carries a short "Citation conventions" section (`article:` =
the code clause; `ruling: 'D-nn'` = the adjudicated reading, registry in
`necb_decisions.md` + `decisions.json`; `L-nn` legacy findings; `T-n`/`A-n`
archived registers); `necb_decisions.md` opens with a generated numeric TOC.

## What the verification pass itself caught

Executing the repaired README examples verbatim (the review's rule: a
quick-start is a test) surfaced **two real path bugs in the runner**, both
fixed:

1. `Runner.run_energyplus!` stored the OSW seed as a caller-relative path,
   which the CLI resolves against the OSW's own directory — any RELATIVE
   `run_dir:` (`'runs/my_building'`, the obvious first thing a user types)
   failed with "Seed model … cannot be found". Fixed with an absolute seed
   path (`runner.rb`).
2. `Runner.attach_weather!` stored the EPW path as given, resolved later from
   the run directory — a relative `weather[:epw]` failed the same way. Fixed
   with `File.expand_path`.

Also caught while cross-checking the two sweeps against each other: the
lighting fixture-coster's own header claimed daylighting-sensor costing "is
NOT ported" while the port sits 160 lines below in the same file
(`costing/fixtures.rb` — the header predated the port). Header corrected; a
reminder that headers drift exactly like READMEs.

Two engineering values were flagged UNVERIFIED during the magic-number
citation pass (they differ from legacy and no source was traced):
`small_systems.rb` evap-cooler design effectiveness **0.85** (legacy uses
0.90) and the evap-cooler SPM values (zero approach offset, 15.5/30.0 °C
clamps vs legacy's +3 °R approach clamped 70/78 °F). RESOLVED in the
follow-up pass: both aligned to legacy bit-identically (D-66); E+ gate
green. CBECS-only family, no fleet exposure.

The full-suite gate then caught two more:

- **A missed D-62 pin** (fixed): `test_necb_water_economizer.rb` still
  asserted 8.4.4.12 "remains partial" with the 5.2.2.8.(4)-(5) gaps string —
  D-62 closed those clauses and moved the twin pin in
  `test_necb_energy_recovery.rb`, but not this one. The test now pins the
  implemented status.
- **A pre-existing data/test drift** — root-caused and FIXED in the
  follow-up pass: the D-23 `include_films` default flip (2026-07-25) left
  `test_legacy_archetype_e2e.rb` and openstudio-loads `test_e2e_run.rb`
  comparing construction-only conductance against the 0.265 OVERALL table
  value (0.2759 = 1/(1/0.265 − film R); printed Table 3.2.2.2 zone-5 wall =
  0.265 overall — the code was right). Both tests migrated to the D-23
  convention; D-23 amendment logged.

## The public/private line (drawn in this pass)

**321 methods privatized across 19 files** (`private_class_method` under an
`# ---- internals (not API) ----` divider), every survivor justified by a
repo-wide caller grep, zero test regressions. The apparent API drops from
~370 module methods to ~50 with real callers — e.g. openstudio-hvac's
`NECB` module went 51 → 10 public, `Efficiency` 56 → 7, `CatalogReport`
87 → 4, the umbrella's `Compliance` 23 → 3. ~30 surviving public methods
that lacked YARD `@param`/`@return` tags got them, including the whole
facade-priority list and `Archetypes.resolve!`'s return shape.
openstudio-geometry was deliberately left unmarked (its helpers are all
genuinely called cross-file or named in its docs).

## Awaiting your call (⏳ / 🔶 highlights)

1. **⏳ Decompose `performance_compliance`** (238 lines → ~15-line sequence of
   named phase methods, fixes the invisible begin/rescue, lets
   `eui_compliance` share scaffolding). Test-covered (umbrella suite + report
   goldens + fleet baselines for A/B) but the highest-churn edit — say go and
   it happens with a one-building before/after report.json diff as the gate.
2. **🔶 File splits**: `small_systems.rb` → one file per family;
   `energy_recovery.rb` out of reference.rb; lighting's legacy area math →
   `daylighted_areas_legacy_2011.rb`. Pure moves, but they touch requires.
3. **🔶 Renames**: `heating_coil_type: 'DX'` → `heat_source: 'ashp'` in
   systems.json; geometry facade `storeys` unification; lighting
   `option:`/`placement:` collapse; `H` → `Html`; sprint-named test files.
4. **🔶 License/homepage reconciliation** (envelope BSD + NatLabRockies vs
   LGPL + NREL elsewhere) — a legal/ownership decision.
5. **✅ DONE — `openstudio-audit` (gem #8)** now holds the one AuditLog and
   the one coverage-emitter loop; six copies became three-line aliases; the
   copy-sync machinery is retired (D-67).
