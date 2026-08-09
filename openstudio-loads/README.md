# openstudio-loads

NECB space-use loads and schedules for OpenStudio models — a domain gem in the
seven-gem family (see the root README for the family map):

- **SDK-only.** Pure `openstudio` model manipulation; never simulates.
- **Vendored, article-tagged data.** The 308 NECB2020 space-type records and 240
  `NECB-<letter>-<category>` schedule records, vendored from the legacy MERGED
  runtime tables and verified against the codes MCP (Tables A-8.4.3.2.(1)-A…-K
  and A-8.4.3.2.(2)-A/-B). Zero MCP dependency at runtime. See
  `lib/openstudio_loads/data/necb/README.md`.
- **AuditLog + article coverage.** Same schema as the sibling gems; every run
  emits the Subsection 8.4.3 manifest — 8.4.3.2 is honestly **partial** in
  THIS gem (lighting and SHW are the sibling gems' scope — apply
  openstudio-lighting / openstudio-shw after `apply_loads`) and the manifest
  says so on every run.

Vintages: **2020 and 2025** (2025 verified value-identical via the MCP —
Article 8.4.3.2 was restructured into clauses and the schedule tables renumbered
`(1)` → `(1)(b)`; the 2025 rules file aliases the 2020 data with renumbered
citations). 2011/2015/2017 backfill is a documented future item.

## What lives in which gem (the boundary table)

| Concern | Gem |
|---|---|
| People, plug/gas equipment, ventilation OA, modelling infiltration, NECB schedule sets, thermostat set-points | **openstudio-loads (this gem)** |
| Lighting power — Part 4 LPD allowances + daylighting | openstudio-lighting |
| Service water heating — Part 6 SHW demand + efficiencies | openstudio-shw |
| HVAC systems, reference systems, efficiencies, HVAC costing | openstudio-hvac |
| Envelope U-values, FDWR/SRR, thermal bridging, reference envelope, envelope costing | openstudio-envelope |
| Performance-path composition, simulation, 8.4.1.2 compliance | openstudio-necb |

## Quick start — bare geometry to a running model

```ruby
require 'openstudio'
require_relative 'openstudio-loads/lib/openstudio_loads'

model = OpenStudio::Model::Model.load(OpenStudio::Path.new('geometry_only.osm')).get
audit = OpenStudioLoads::AuditLog.new

# 1. the on-ramp: tag spaces with NECB space types
OpenStudioLoads.assign_space_types(model,
  { 'Space 101' => ['Space Function', 'Office enclosed > 25 m2'],
    'Space 102' => ['Space Function', 'Corridor/Transition area other-sch-A'] },
  vintage: '2020', audit: audit)

# 2. the loads pass: people, equipment, OA, infiltration, schedules, thermostats
OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)

# data access + individual schedules
OpenStudioLoads::NECB::SpaceTypes.record(building_type: 'Space Function',
                                         space_type: 'Office enclosed > 25 m2')
OpenStudioLoads::Schedules.add(model, 'NECB-A-Occupancy', audit: audit)
```

With openstudio-hvac and openstudio-envelope alongside, bare geometry becomes a
complete NECB proposed building without openstudio-standards:
loads → `OpenStudioHVAC.build_system` → `OpenStudioEnvelope::NECB.apply_prescriptive`
(one audit spans all of it — pinned by `test_e2e_run.rb`).

## What apply_loads does (legacy-parity, per tagged space type)

- **People**: `occupancy_per_area` (people/1000 ft² → people/m²), FractionRadiant
  0.3, Clothing/Air-Velocity/Work-Efficiency comfort schedules.
- **Electric/Gas equipment**: W/ft² and Btu/hr·ft² densities with
  latent/radiant/lost fractions.
- **Ventilation OA** (`DesignSpecificationOutdoorAir`, method Sum) with the legacy
  **per-person rescale**: the ventilation standard's occupant density differs from
  NECB's, so cfm/person × (standard occupancy / NECB occupancy) — the summed OA
  matches the standard's intent at NECB density. Source values are stashed on
  `additionalProperties`. Space types without data get a zero DSOA (required for
  OA controls).
- **Modelling infiltration** from the space-type data (distinct from the envelope
  gem's 8.4.3.3 air-leakage rule, which may override it in the reference).
- **Schedule set** wiring: occupancy, activity, equipment (NOT lighting).
- **Thermostats**: a dual-setpoint thermostat per space type from the NECB
  set-point schedules; zones lacking a thermostat get their space type's
  (never overwrites an existing one).
- Plenum and `'- undefined -'` space types are skipped, audited.

The schedule builder ports `model_add_schedule` exactly (day-type tokens, design
days, Hourly change-point insertion — values are MIDNIGHT-FIRST as transcribed by
legacy; Constant rows). Deviation: an unknown schedule name WARNS in the audit
before the always-on fallback (legacy is silent).

## Citation conventions

`article:` in audit entries = the NECB clause that mandates a value;
`ruling: 'D-nn'` = the adjudicated reading of it. The registry is
[openstudio-necb/docs/necb_decisions.md](../openstudio-necb/docs/necb_decisions.md)
(id-ordered index at the top) + its drift-tested `decisions.json` mirror;
`L-nn` cites the legacy findings register. The family glossary lives in
[openstudio-necb/docs/README.md](../openstudio-necb/docs/README.md).

## Testing

```bash
cd openstudio-loads
ruby test/test_data_integrity.rb   # vendored data vs legacy merged tables + MCP goldens
ruby test/test_schedules.rb        # builder semantics + loud fallback
ruby test/test_apply_loads.rb      # golden application assertions
ruby test/test_e2e_run.rb          # bare geometry -> clean E+ week run + 3-gem composition

# Parity gates need the repo bundle:
BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby test/test_schedules_parity.rb
BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby test/test_apply_parity.rb
```

Parity: all 86 schedule names build identically to legacy `model_add_schedule`
(day values, design days, rule flags/dates); 7 representative space types match
legacy `space_type_apply_internal_loads(set_lights: false)` on 17-field
per-object signatures — 0 mismatches.

## Documented future (not in scope)

2011–2017 vintage
backfill · ECM load scalers · dwelling/wildcard schedule merging (autozone/HVAC
territory) · semi-heated set-point-from-specifications (8.4.3.2.(3)).
