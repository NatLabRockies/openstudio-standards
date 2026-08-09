# CLAUDE.md — openstudio-shw

SDK-only NECB service water heating gem: Part 6 — SHW demand from NECB
space-use data, tank/system construction, heater efficiencies (including heat
pump and instantaneous water heaters), the reference transform, and costing.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `audit_log.rb` aliases the shared class in
  **openstudio-audit** — schema changes happen there, never as a local copy.
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
- **The water-heater part-load curve looks wrong and is not (D-53).** The code
  (2020 **8.4.5.9.(2)**, 2025 **8.4.6.9.(2)**) writes a QUADRATIC *fuel-ratio*
  curve `FHeatPLC = 0.021826 + 0.977630x + 0.000543x²`
  (`Fuel_pl = Fuel_des × FHeatPLC`); the gem vendors a CUBIC in the E+
  `WaterHeater:Mixed` part-load-factor field, which is a *degradation divisor*
  (`fuel = Q/(η·PLF)`). They relate as `PLF(x) = x / FHeatPLC(x)` — RATIONAL,
  so no exact polynomial exists — and the cubic is that image, probe-verified
  ≤0.98% over PLR 0.25-1.0 (`rake necb:curves`). **Do not "fix" this by putting
  the code quadratic in the PLF field**: it inverts the relation (+92% fuel at
  half load, +253% at quarter load) and double-counts the standby `a` term that
  E+ already carries as off-cycle parasitic fuel + tank UA.
- The curve's scope is the ARTICLE's: gas/oil, storage AND instantaneous;
  electric is out of scope and is AUDITED as such, never silently skipped.
  `part_load_curve` honours the ruleset `form` (Cubic/Quadratic) and raises on
  a mis-shaped spec.

## Facade

`OpenStudioSHW.apply_shw`; `OpenStudioSHW::NECB.rules / reference_shw /
apply_water_heater_efficiency`.

## Tests

`cd openstudio-shw && ruby test/test_XX.rb`. Fixtures shared from
`../openstudio-hvac/test/fixtures`. `test_shw_parity.rb` needs
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
