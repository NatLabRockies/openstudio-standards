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

- `necb/apply_lights.rb` — LPD application. Unmatched CONSEQUENTIAL space
  types (used by a floor-area space; orphans/plenums exempt) WARN
  individually, and the summary decision logs `applied` AND `eligible` (a
  bare numerator once hid a total no-op). `lights_type:` selects the
  catalog: `'NECB_Default'` or LED. Data:
  `lpd_space_functions_2025.json` / `lpd_building_types_2025.json` /
  `led_lighting_2020.json`.
- `necb/daylighting.rb` — daylighting controls/sensors. `placement:` is the
  ONLY selector: `:all` (**the default of `add_controls`**) = sensors
  everywhere there is exterior fenestration; `:necb2020` = NECB 2020/2025
  4.2.2.1.(10)-(15) (D-57) and the default of `reference_daylighting`;
  `:necb2011` (alias `:necb_default`) = the legacy-exact 2011 port, defects
  preserved, kept reachable so `test_daylighting_parity.rb` still proves the
  port faithful. An unknown placement raises. `option:` is a DEPRECATED alias
  (`'all'`→`:all`, `'NECB_Default'`→`:necb2011` if placement says so else
  `:necb2020`) that audits an info entry when used — `Daylighting.resolve_placement`
  owns the mapping, `Daylighting.normalize_placement` (public) owns the
  vocabulary, and nothing else may keep a second copy of either.
- `necb/daylighted_areas_legacy_2011.rb` — QUARANTINE. Reopens `Daylighting` to
  hold the VERBATIM legacy `sidelighting_parameters` / `skylight_parameters`
  (constant paths unchanged) — they exist ONLY to be diffed against legacy by
  `test_daylighting_parity.rb`; do not build on them.
- `necb/daylighted_areas.rb` — the 2020/2025 daylighted-area geometry per
  4.2.2.3. (primary + **secondary** sidelighted) and 4.2.2.5. (under skylights),
  adapted from openstudio-standards' `space_daylighted_areas`: one polygon per
  aperture, all flattened to z = 0, **joined** into a union then **subtracted**,
  which is the "without double-counting overlapping areas" the articles require.
  NECB precedence is **primary > toplit > secondary** — the OPPOSITE of the
  90.1 original (4.2.2.5.(2)(b) clips the toplit area at the primary band;
  4.2.2.3.(9) kills secondary beyond either).
- `necb/daylight_control_requirement.rb` — the 4.2.2.1.(10)-(15) rule itself:
  the Table 4.2.1.6. column gate + the input-POWER tests + the (12)/(15)
  exceptions. Data: `daylighting_controls_4_2_1_6.json`.
- `necb/reference.rb` / `necb/reference_daylighting.rb` — reference-building
  lighting. **`reference_lighting` HARD-RAISES when any floor-area space type
  is unresolvable** — the allowance for an unlisted space function is a human
  judgement (4.2.1.6.(1)(b)), so no fallback is invented; before this gate an
  unmatched type silently kept the proposed's LPD in the reference clone
  (allowance waived). The umbrella pre-flights even earlier with suggestions;
  this guards direct gem callers. reference daylighting runs BY DEFAULT from the
  umbrella (D-51; `reference_daylighting: false` opts out) and needs the PROPOSED
  model for comparison. `reference_lighting(daylighting:)` tells the lighting
  transform whether the daylighting one will run: the "(5)-(12) NOT modeled"
  warning fires only when it will not.
- `necb/exterior.rb` + `exterior_lighting_2020.json` — exterior allowances.
- `costing/*` — fixture takeoff and costing.

## Key facts / traps

- **The NECB 2020 lighting_sets catalog is LED-ONLY** — that's why legacy
  forces LED. Non-LED `lights_type` falls back by type with an audit note,
  not an error.
- **The power test is tractable because the LPD is uniform.** 4.2.2.1.(10)/(13)
  test input power *inside* a daylighted area, which normally needs a luminaire
  layout. It does not here: one LPD per space means
  `power = LPD_general x daylighted_area` exactly. "General" excludes the
  separately named `Additional Lights` (the 4.2.1.6. specialty allowance).
- **Sidelighting and toplighting are INDEPENDENT** — never AND them. ANDing them
  (with the 2011 area/aperture criteria) is L-26: a window-only space could never
  qualify, so 10 of 17 archetypes got no reference photocontrols at all.
- **Subsection 4.2.2 of NECB 2020/2025 ENDS AT ARTICLE 4.2.2.6.** Any citation to
  4.2.2.7.-4.2.2.12. is a NECB 2011 leftover and is wrong; 4.2.2.2. is "Lighting
  Controls in Storage Garages", not occupancy controls.
- Zone daylight fraction on the `:necb2020` path is the **daylighted share of
  the zone floor area**, not 1.0 — (10)/(13) control the lighting in the
  daylighted areas, not the whole room. The legacy paths still use 1.0.
- `sidelighting_parameters` / `skylight_parameters` in
  `daylighted_areas_legacy_2011.rb` are a
  verbatim legacy port — do NOT "clean them up"; parity tests pin them to legacy
  output, including its defects (no union, no secondary area, skylight-only
  spaces compute zero).
- **Do not regenerate `daylighting_controls_4_2_1_6.json` from one MCP call.**
  Both the 2020 and 2025 Table 4.2.1.6 extractions are corrupted, differently,
  and disagree on 38 of 91 rows. See the data README.
- `setVisibleAbsorptance` (reference daylighting interior surfaces) needs
  `OpenStudio::OptionalDouble.new(x)`.
- Comparative E+ gate exists: annual lighting energy WITH controls must be
  < WITHOUT (proves the controls actually evaluate) — keep it when touching
  daylighting.
- `quantifier.add(count: 0)` used to emit audit lines — zero-count adds are
  guarded; keep the guard.
- LPD lives HERE, not in openstudio-loads (deliberate split).
- In tests, a space type is only CONSEQUENTIAL (gate/warn eligible) if a
  floor-area Space uses it — attach a Space, or the gate ignores it.

## Facade

`OpenStudioLighting.apply_lights / cost`; `OpenStudioLighting::NECB.rules /
add_daylighting_controls / reference_lighting / reference_daylighting /
led_record / table`; `OpenStudioLighting::NECB::Exterior.allowance /
apply_exterior_lights`.

## Tests

`cd openstudio-lighting && ruby test/test_XX.rb`. Fixtures shared from
`../openstudio-hvac/test/fixtures`. `*_parity.rb` needs
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
