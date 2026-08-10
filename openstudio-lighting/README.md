# openstudio-lighting

NECB Part 4 lighting for OpenStudio models — a domain gem in the seven-gem
family (see the root README for the family map). Depends on
**openstudio-loads** (the canonical NECB space-type data owner and schedule
builder). SDK-only; vendored article-tagged data verified offline via the
codes MCP; shared AuditLog schema + article-coverage manifests.

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
  NameError and a `select(&false)` TypeError in the height helper. (Legacy has
  since fixed the `select` one too — `necb_2011.rb`
  `get_max_space_height_for_space_type` now uses a real block, in tree since
  the origin/nrcan merge.)
- **Reference lighting** (8.4.4.5): allowance LPD, dwelling units 5 W/m²,
  Focc/Fpers via schedule modulation (interpretation audited), fraction
  identity. Daylighting sentences (5)–(12) are covered by the separate
  `reference_daylighting` transform (see below); when the caller opts out of
  it, the gap is shouted.
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

## Daylighting

`OpenStudioLighting.add_daylighting_controls(model, vintage:, placement:)`
places DaylightingControls (stepped ×3, space-type
`target_illuminance_setpoint`, sensor at the lowest-floor bounding-box centre
+0.8 m). ONE knob selects the rule — `placement:`:

- `placement: :all` — **the default for this entry point**: sensors in every
  space with exterior fenestration, no threshold (the legacy blanket option),
  zone fraction 1.0 and the 2-step control. The reference-building transform
  (`reference_daylighting`) defaults to `:necb2020` instead, because the
  reference must be built to the code rule.
- **`placement: :necb2020` (D-57)** — sensors where NECB
  2020/2025 **4.2.2.1.(10)–(15)** requires them: the Table 4.2.1.6 space-function
  control matrix gates each space, the input-power tests use
  `LPD_general × daylighted area` (exact — one LPD per space, no luminaire
  layout needed), and the daylighted areas come from the **4.2.2.3
  (primary + secondary sidelighted) and 4.2.2.5 (under skylights)** geometry:
  one polygon per aperture, flattened, unioned then subtracted (the articles'
  "without double-counting"), precedence primary > toplit > secondary. The
  zone's daylight fraction is the **daylighted share of the zone floor area**
  (not 1.0 — the controls govern the daylighted areas, not the whole room).
- `placement: :necb2011` (alias `:necb_default`) — the legacy-exact 2011 port,
  kept ONLY so the parity gate can prove the port faithful. It **mirrors legacy
  as fixed by [#2119](https://github.com/NREL/openstudio-standards/pull/2119)**
  (merged 2026-07-15, in tree since the origin/nrcan merge): the window
  criteria apply only to spaces WITH exterior windows and the skylight criteria
  only to spaces WITH skylights, the skylight area accumulates once per
  skylight (outside the exterior-window loop), and the ≥25 m² office exemption
  matches `/office\s*-?\s*enclosed/i` so it fires on NECB2020 space-type names.
  **The pre-#2119 defects are gone from both sides** — `office_match: :legacy`
  and `:any_enclosed_office` now behave identically, and both stay accepted.
  What remains between this path and `:necb2020` is a **RULE** difference
  between the code editions, not a defect: 2011 ANDs area/aperture thresholds,
  2020/2025 tests sidelighting and toplighting input power independently
  (L-26). Do not build on this path.

`option:` is **deprecated** — it used to be a second, overlapping selector that
silently won over `placement:`. It still works and still lands on the rule it
always did (`'all'` → `:all`; `'NECB_Default'` → `:necb2011` when `placement:`
names it, else `:necb2020`), and passing it now writes an audit info entry
saying so. Pass `placement:` alone.

**Citation hygiene:** Subsection 4.2.2 of NECB 2020/2025 **ends at article
4.2.2.6**. Citations to 4.2.2.7–4.2.2.12 are NECB 2011 numbers and are wrong
in a 2020/2025 context (the code enforces this — see the CITATION HYGIENE
block in `necb/daylighting.rb`).

Sensor costing uses the legacy daylighted-area rule: per controlled zone,
fixtures = Σ ceil(ft²/1000 × Fix_1000ft), sensors =
ceil(ceil(fixtures × area-ratio)/4) per aperture type, each priced with the
per-sensor BOM (sensor row 407 + 30 ft wiring + 30 ft PVC conduit + box).

### Which file does what

| File | Job |
|---|---|
| `necb/daylight_control_requirement.rb` | WHERE controls are required — the 4.2.2.1.(10)–(15) rule over Table 4.2.1.6 |
| `necb/daylighted_areas.rb` | HOW MUCH area — the 4.2.2.3/.5 union-polygon geometry |
| `necb/daylighting.rb` | the actuator: places the DaylightingControl objects |
| `necb/daylighted_areas_legacy_2011.rb` | QUARANTINE: the legacy NECB 2011 area math (`Daylighting.sidelighting_parameters` / `.skylight_parameters`), parity-pinned to legacy **as fixed by #2119** — do not build on it |
| `necb/reference_daylighting.rb` | the 8.4.4.5.(5)–(12) reference-building transform |

## Reference daylighting (8.4.4.5.(5)–(12))

`OpenStudioLighting::NECB.reference_daylighting(reference, vintage:, proposed:)`
evaluates photocontrols in the reference building by **detailed EnergyPlus
daylighting**: interior reflectances set per (10)(b) (floor 0.15 / walls 0.50 /
ceiling 0.80), fenestration VT identical to proposed by construction ((10)(d),
the envelope transform preserves optics), set-points from the proposed
building's photocontrols else the space-type illuminance ((11)), and the
sentence-(12) FDL-factor fallback declared unnecessary since detailed
daylighting is available. Audited interpretation: the analytic
single-centered-window/skylight AREA convention of sentences (5)–(8) is
replaced by the ported 4.2.2 threshold geometry on the reference's actual
FDWR/SRR-scaled fenestration. The comparative E+ gate proves the evaluation is
live (lighting energy drops when controls are present). The umbrella pipeline
runs this BY DEFAULT (D-51); `reference_daylighting: false` opts out, loudly.

## Citation conventions

`article:` in audit entries = the NECB clause that mandates a value;
`ruling: 'D-nn'` = the adjudicated reading of it (e.g. `D-57` = the 4.2.2.1
placement rule, `D-51` = reference photocontrols on by default). The registry
is [openstudio-necb/docs/necb_decisions.md](../openstudio-necb/docs/necb_decisions.md)
(id-ordered index at the top) + its drift-tested `decisions.json` mirror;
`L-nn` cites [legacy_findings.md](../openstudio-necb/docs/legacy_findings.md)
(e.g. `L-26`, the ANDed sidelighting/toplighting rule — FIXED UPSTREAM as to
its implementation defects by #2119, still a deliberate 2011-vs-2020 rule
divergence per D-57). Family glossary:
[openstudio-necb/docs/README.md](../openstudio-necb/docs/README.md).

## Documented future

Exterior-lighting schedules beyond the astronomical clock · 2011–2017 vintage
backfill.
