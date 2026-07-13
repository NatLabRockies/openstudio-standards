# CLAUDE.md — openstudio-lighting

SDK-only NECB lighting gem: full Part 4 — interior LPDs (space-function and
building-type methods), daylighting controls + daylighted-area geometry,
exterior lighting, the reference-building lighting/daylighting transforms, and
lighting fixture costing.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `audit_log.rb` is a verbatim copy of
  openstudio-hvac's — regenerate from there on schema changes.
- Audit text: violations SHOUTED, passes lowercase.
- `article_coverage` manifest in `lighting_rules_*.json`; partial/
  not_implemented warn every run.
- Licensing: vendored costing sheets are UNPRICED; real prices runtime-only
  via `costs_csv:` (resolution: args → `OPENSTUDIO_COSTING_DIR` →
  openstudio-hvac's public CSVs).
- Vintages 2020 + 2025 only.

## Architecture

- `necb/apply_lights.rb` — LPD application. `lights_type:` selects the
  catalog: `'NECB_Default'` or LED. Data:
  `lpd_space_functions_2025.json` / `lpd_building_types_2025.json` /
  `led_lighting_2020.json`.
- `necb/daylighting.rb` — daylighting controls/sensors + the daylighted-area
  geometry (primary/secondary sidelighted areas, skylight wells) — VERBATIM
  geometry ports from legacy with parity gates.
- `necb/reference.rb` / `necb/reference_daylighting.rb` — reference-building
  lighting; reference daylighting is opt-in from the umbrella
  (`reference_daylighting: true`) and needs the PROPOSED model for comparison.
- `necb/exterior.rb` + `exterior_lighting_2020.json` — exterior allowances.
- `costing/*` — fixture takeoff and costing.

## Key facts / traps

- **The NECB 2020 lighting_sets catalog is LED-ONLY** — that's why legacy
  forces LED. Non-LED `lights_type` falls back by type with an audit note,
  not an error.
- Daylighted-area geometry is a verbatim legacy port — do NOT "clean it up";
  parity tests pin it to legacy output.
- `setVisibleAbsorptance` (reference daylighting interior surfaces) needs
  `OpenStudio::OptionalDouble.new(x)`.
- Comparative E+ gate exists: annual lighting energy WITH controls must be
  < WITHOUT (proves the controls actually evaluate) — keep it when touching
  daylighting.
- `quantifier.add(count: 0)` used to emit audit lines — zero-count adds are
  guarded; keep the guard.
- LPD lives HERE, not in openstudio-loads (deliberate split).

## Facade

`OpenStudioLighting.apply_lights / cost`; `OpenStudioLighting::NECB.rules /
add_daylighting_controls / reference_lighting / reference_daylighting /
led_record / table`; `OpenStudioLighting::NECB::Exterior.allowance /
apply_exterior_lights`.

## Tests

`cd openstudio-lighting && ruby test/test_XX.rb`. Fixtures shared from
`../openstudio-hvac/test/fixtures`. `*_parity.rb` needs
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
