# CLAUDE.md — openstudio-envelope

SDK-only NECB envelope gem: prescriptive Section 3.2 requirements, thermal
bridging (3.1.1.7), the reference-envelope transform (8.4.4.3/.4 in 2020
numbering), climate/HDD resolution, and envelope + thermal-bridging costing.

## Family contract (shared by all seven gems)

- Pure OpenStudio SDK; no openstudio-standards, no measures; never simulates.
- One AuditLog schema `{step, target, action, inputs, value, article,
  evidence, building, level}`; warnings never silent; `building:` stamp via
  `audit.with_building`. `necb/audit_log.rb` aliases the local class; the
  class itself (`audit_log.rb`) is a verbatim copy of openstudio-hvac's —
  regenerate from there, never hand-edit divergently.
- Audit text: violations SHOUTED, passes lowercase (report checklist parses
  case-sensitively).
- `article_coverage` manifest in each vintage rules JSON; partial/
  not_implemented warn every run.
- Licensing: real RS-Means prices only via runtime `costs_csv:`; the vendored
  `data/costing/constructions.json` is UNPRICED (price-reference columns
  blanked). Runtime price resolution: explicit args → `OPENSTUDIO_COSTING_DIR`
  → openstudio-hvac's public vendored CSVs.
- Vintages 2020 + 2025 only (2011–2017 user-deferred).

## Architecture

- `climate.rb` — HDD18 resolution: explicit arg → Table C-1 (`table_c1.json`)
  matched from the EPW site name → `.stat` file fallback. NECB climate zones
  4–8 from HDD.
- `necb/rules.rb` + `data/necb/envelope_rules_*.json` — U-value/FDWR/SRR
  tables keyed by HDD.
- `necb/prescriptive.rb` — applies Section 3.2 maximums to a model.
- `necb/reference.rb` — the reference-building envelope transform (runs on the
  SAME clone reference_hvac produced, same audit). Emits article coverage.
- `necb/thermal_bridging.rb` — 3.1.1.7 via TBD; `thermal_bridging:` accepts
  the BETBG detail-set names (e.g. `'efficient (BETBG)'`).
- `constructions.rb` / `geometry.rb` — construction retargeting + surface math.
- `costing/*` — envelope quantity takeoff (assemblies keyed to the BTAP-*
  costing vocabulary), U-value interpolation between catalog constructions,
  TB costing.

## Key facts / traps

- **FDWR limit at HDD ≤ 4000 is the flat 0.40 piece**, NOT the linear formula
  (Toronto HDD 3890 → 0.40). Don't "fix" tests to the formula.
- SimpleGlazing constructions return an EMPTY `thermalConductance` — use the
  `uFactor` fallback or you silently skip windows.
- `setSolarAbsorptance` / `setVisibleAbsorptance` need
  `OpenStudio::OptionalDouble.new(x)`, not a bare Float.
- The reference air-leakage default clears **ALL THREE infiltration
  representations** (DesignFlowRate + EffectiveLeakageArea + FlowCoefficient)
  before applying I_AGW — clearing only DesignFlowRate double-counted
  infiltration for ELA/FlowCoefficient proposeds (fixed defect; hostile test
  pins it). Cleared counts land in the audit decision.
- The 0.7 reference roof absorptance is read from
  `reference_envelope.roof_absorptance_if_actual_used` in the rules JSON —
  not hardcoded.
- The manifest count-pin lints (test_data_integrity / test_reference_envelope)
  assert **16** articles per vintage — bump them CONSCIOUSLY when adding
  entries; the vintage-numbering lint checks only the renumbered 8.4.4/8.4.5
  subsection (8.4.1-8.4.3 are vintage-invariant).
- Reference transform retargets EXISTING constructions — bare-geometry models
  (from openstudio-geometry wizards/bar) have none; seed a construction set
  first.
- Test windows need SimpleGlazing constructions or legacy parity comparisons
  raise 'Optional not initialized' (visibleTransmittance).
- Legacy `BTAPCosting` parity requires `BTAPCosting.allocate` plus
  monkeypatched `getThermalZonesSorted`/`getSpacesSorted`.

## Facade

`OpenStudioEnvelope.cost`; `OpenStudioEnvelope::NECB.rules /
apply_prescriptive / reference_envelope`;
`OpenStudioEnvelope::NECB::ThermalBridging.apply(psi_set: 'regular (BETBG)')`
(the umbrella's `thermal_bridging:` kwarg feeds this);
`OpenStudioEnvelope::Climate.hdd18`.

## Tests

`cd openstudio-envelope && ruby test/test_XX.rb`. Fixtures shared from
`../openstudio-hvac/test/fixtures`. `*_parity.rb` suites compare against
legacy openstudio-standards and need
`BUNDLE_GEMFILE=/workspaces/openstudio-standards/Gemfile bundle exec ruby ...`.
