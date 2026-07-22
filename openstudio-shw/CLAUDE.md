# CLAUDE.md — openstudio-shw

SDK-only NECB service water heating gem: Part 6 — SHW demand from NECB
space-use data, tank/system construction, heater efficiencies (including heat
pump and instantaneous water heaters), the reference transform, and costing.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `audit_log.rb` is a verbatim copy of
  openstudio-hvac's — regenerate from there on schema changes.
- Audit text: violations SHOUTED, passes lowercase.
- `article_coverage` manifest in `shw_rules_*.json`; partial/not_implemented
  warn every run.
- Vintages 2020 + 2025 only.

## Architecture

- `necb/demand.rb` — per-space SHW flow demand from NECB space-type data,
  aggregated to a building system.
- `necb/reference.rb` — system construction (tank, pump/loop, use
  connections) + the reference transform. `fuel:` selects gas/electric/HP/
  instantaneous variants.
- `necb/efficiency.rb` — heater performance by fuel + capacity/volume bins,
  including heat-pump and instantaneous water heaters.
- `costing.rb` — tank/heater costing.

## Key facts / traps

- **Legacy tank-sizing sorted-array defect is DELIBERATELY PRESERVED for
  parity** (0.0757 vs 0.1239 m³ — reads the wrong element of a sorted array)
  — it warns in the audit here and is FIXED on the PR branch
  (`fix/btap-costing-defects`, PR #2119 on NatLabRockies/openstudio-standards).
  Do not "fix" it here without breaking the parity gate knowingly.
- SHW lives HERE, not in openstudio-loads (deliberate split); the umbrella
  on-ramp only builds SHW when `shw_fuel:` is passed.
- Demand needs space-type TAGS (standardsSpaceType) — bare models must go
  through openstudio-loads assignment first.
- Vintage aliasing is OWNED by openstudio-loads
  (`OpenStudioLoads::NECB.data_vintage`, called from `necb/demand.rb`) — the
  2025 rules file deliberately has no `data_vintage_alias` key (deleted as
  dead config by the orphan-key lint).
- The water-heater part-load factor curve is probe-verified equivalent to the
  8.4.6.9 FHeatPLC (≤0.98%; `rake necb:curves`).

## Facade

`OpenStudioSHW.apply_shw`; `OpenStudioSHW::NECB.rules / reference_shw /
apply_water_heater_efficiency`.

## Tests

`cd openstudio-shw && ruby test/test_XX.rb`. Fixtures shared from
`../openstudio-hvac/test/fixtures`. `test_shw_parity.rb` needs
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
