# CLAUDE.md — openstudio-loads

SDK-only NECB space-use gem: NECB space-type assignment, occupancy/receptacle
load densities, and operating schedules (8.4.3.2 / Section 4 space-use data).
**LPD is deliberately EXCLUDED** (openstudio-lighting owns it) and **SHW is
deliberately EXCLUDED** (openstudio-shw owns it) — do not add them back here.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `audit_log.rb` is a verbatim copy of
  openstudio-hvac's — regenerate from there on schema changes.
- Audit text: violations SHOUTED, passes lowercase.
- `article_coverage` manifest in `loads_rules_*.json`; partial/not_implemented
  warn every run.
- Vintages 2020 + 2025 only (2011–2017 user-deferred).

## Architecture

- `necb/space_types.rb` + `data/necb/space_types_2020.json` — the NECB
  space-type catalog (names, densities, schedule letters).
- `necb/apply.rb` — `assign_space_types(model, map)` where map is
  `{space name => [building_type, space_type]}`, then `apply_loads` sets
  people/equipment densities + schedules.
- `schedules.rb` + `data/necb/schedules_2020.json` — NECB schedule
  construction (A–K letters → day/week/year rulesets).

## Key facts / traps

- **NECB 2020 space-type NAMES differ from 2011** — e.g.
  `'Office enclosed > 25 m2'`, `'Corridor/Transition area other-sch-A'`,
  `'Dining area - family dining'`, `'Dwelling units general'` (no `-sch`
  suffix). There are NO gas-equipment space types in the 2020 data. Always
  grep `space_types_2020.json` for exact names.
- **Legacy schedules are MIDNIGHT-FIRST:** `values[0]` corresponds to the code
  table's TRAILING 12 a.m. column. Parity comparisons must rotate.
- 'Table 8.4.3.5' is assumed chiller COP/IPLV (Scroll/Screw 2.802), NOT
  simulation parameters — the coverage manifest was corrected once already;
  don't re-mislabel it.
- SpaceType density getters (`lightingPowerPerFloorArea` etc.) can return
  OptionalDouble depending on SDK version — unwrap before `.round`.
- **The umbrella's EUI normalization consumes `Apply.apply_people` /
  `apply_equipment` / `apply_schedule_set` / `apply_thermostat` directly with
  SYNTHETIC Table 8.4.4.2 records** (openstudio-necb `eui_archetypes.rb`) — the
  record field names/units (occupancy_per_area per 1000 ft², W/ft², schedule
  name shapes `NECB-<letter>-…`) are a cross-gem contract; changing them
  breaks the umbrella's round-trip test.
- The coverage-emission count is PINNED at 7 in test_apply_loads (5 × 8.4.3.x
  + 8.4.2.7 slice + 8.4.3.6) — bump consciously.
- The umbrella's bare-geometry on-ramp (`necb_loads:` option) calls this gem
  first, then lighting → shw → hvac. Space-type TAGS (standardsBuildingType /
  standardsSpaceType) drive every downstream gem — assignment correctness here
  propagates everywhere.

## Facade

`OpenStudioLoads.assign_space_types`; `OpenStudioLoads::NECB.rules /
apply_loads / table / data_vintage`.

## Tests

`cd openstudio-loads && ruby test/test_XX.rb`. Fixtures shared from
`../openstudio-hvac/test/fixtures`. `*_parity.rb` needs
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
