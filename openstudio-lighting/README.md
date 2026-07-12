# openstudio-lighting

NECB Part 4 lighting for OpenStudio models — the fifth domain gem in the family
(openstudio-hvac, openstudio-envelope, openstudio-loads, openstudio-necb).
Depends on **openstudio-loads** (the canonical NECB space-type data owner and
schedule builder). SDK-only; vendored article-tagged data verified offline via
the codes MCP; shared AuditLog schema + article-coverage manifests.

Vintages: **2020 and 2025.** The 2025 4.2.1.6 edition diff looked significant
but is structural — 2025 added a per-space-function **lighting-control
requirement matrix** (4.2.2.1) and renamed rows; a 162-row normalized join found
**zero LPD differences** vs 2020 (atrium bins identical). 2025 aliases the 2020
LPDs while shipping both 2025 tables and the control matrix as native data.

## What it does

```ruby
require_relative 'openstudio-lighting/lib/openstudio_lighting'  # pulls openstudio-loads

# interior lighting on a space-type-tagged model (after OpenStudioLoads apply_loads)
OpenStudioLighting.apply_lights(model, vintage: '2020',
                                lights_type: 'NECB_Default',  # or 'LED'
                                lights_scale: 1.0, audit: audit)

# reference-building lighting (8.4.4.5; 2025: 8.4.5.5)
OpenStudioLighting::NECB.reference_lighting(model, vintage: '2020', audit: audit)

# exterior allowance (4.2.3.1, greenfield — legacy never computed it)
result = OpenStudioLighting::NECB::Exterior.allowance(zone: 3,
  quantities: { 'parking_and_drives_m2' => 1000, 'entrances_exits_m' => 10 }, audit: audit)
OpenStudioLighting::NECB::Exterior.apply_exterior_lights(model, result['total_w'], audit: audit)

# fixture costing (legacy BTAP port; priced tables runtime-injected as in the sibling gems)
report = OpenStudioLighting.cost(model, vintage: '2020', city: 'TORONTO',
                                 province_state: 'ONTARIO', audit: audit)
```

- **Interior LPD** from the space-type records (4.2.1.5/4.2.1.6), heat
  fractions, watts-per-person, specialty additional lights.
- **Occupancy-sensor lighting schedules** (NECB2015-lineage): above 8.6 W/m²
  the lighting schedule is synthesized hour-by-hour — value ×
  `(1 − rel_absence_occ × occ_sense − personal_control)` when occupancy <
  `rel_absence_occ` (the Table 4.3.2.10 factors carried in the space-type data).
- **LED alternative** with the atrium height equations — two legacy defects in
  that (never-exercised) path fixed and audited: an undefined `space_height`
  NameError and a `select(&false)` TypeError in the height helper.
- **Reference lighting** (8.4.4.5): allowance LPD, dwelling units 5 W/m²,
  Focc/Fpers via schedule modulation (interpretation audited), fraction
  identity; daylighting sentences (5)–(12) are a loud gap.
- **Exterior allowances**: basic site + tradable + non-tradable by lighting
  zone (Tables 4.2.3.1.-A…-E), per-line evidence, `ExteriorLights` with
  astronomical-clock control.
- **Fixture costing**: per-space fixture sets by ceiling-height bin; the
  NECB2020 catalog is LED-only (why legacy hard-forces LED — the gem detects
  the modeled type and falls back with an audit note). Dollar parity vs legacy
  `cost_audit_lighting` on the LED/NECB2020 path. Daylighting sensors are
  costed when controls exist (see Daylighting below).

## Testing

```bash
cd openstudio-lighting
ruby test/test_data_integrity.rb        # data + 2025 verification lint
ruby test/test_apply_lights.rb          # LPD, synthesis hour-math, LED+atrium fix
ruby test/test_exterior_and_reference.rb
ruby test/test_costing.rb               # incl. legacy $ parity under the repo bundle
ruby test/test_e2e_run.rb               # E+ lighting-energy gate + 4-gem composition
BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby test/test_lights_parity.rb
```

Parity: 5 space types × {NECB_Default, LED} match legacy `set_lights: true`
per-object (W/m², fractions, full schedule signatures incl. synthesized sensor
rulesets); fixture costing matches legacy `cost_audit_lighting` to the dollar.

## Documented future

Photocontrol energy evaluation, the 4.2.2 threshold-based sensor placement
(primary-sidelighted-area / effective-aperture geometry) and the
8.4.4.5.(5)–(12) reference daylighting geometry · exterior-lighting schedules
beyond astronomical clock · 2011–2017 backfill.

## Daylighting

`OpenStudioLighting.add_daylighting_controls(model, vintage:)` places a
DaylightingControl in every space with exterior fenestration (the legacy
"all daylighted spaces" option): stepped ×2 control, space-type
`target_illuminance_setpoint`, sensor at the lowest-floor bounding-box centre
+0.8 m, zone primary control at fraction 1.0. Costing then prices sensors per
controlled zone — ceil(fixtures/4) with the legacy per-sensor BOM (sensor row
407 + 30 ft wiring + 30 ft PVC conduit + box). Audited deviation: the fixture
count uses the whole zone area (an upper bound) until the daylighted-area
geometry (primary sidelighted / under-skylight) is ported; the 4.2.2
threshold-based placement and the 8.4.4.5.(5)–(12) reference daylighting
geometry remain documented futures.
