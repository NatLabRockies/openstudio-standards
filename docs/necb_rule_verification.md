# NECB rule verification

`rake necb:verify` checks that the NECB rules the gem family *declares* are
rules it actually *applies*.

## Why this exists

Each domain gem's ruleset JSON carries an `article_coverage` manifest
declaring every NECB article as `implemented` / `partial` /
`not_implemented` / `satisfied_by_clone` / `host_scope`, and
`scripts/generate_necb_gem_coverage.rb` rolls those up into
`NECB_GEM_COVERAGE.md`.

That manifest is **self-declared prose**. `status: "implemented"` is justified
only by a `how` string, and until these checks existed nothing verified that an
article declared implemented changed anything in a model. Two real defects
survived review, tests, and CI inside articles declared `implemented`:

- **(fixed)** the reference lighting reset silently no-oped for any space type
  absent from the NECB catalog, so the reference kept the **proposed's**
  lighting power — the Part 4 allowance was waived and the proposed compared
  against itself. Fixed at three layers: `apply_lights` warns per consequential
  unmatched type and logs `applied` **and** `eligible` counts;
  `reference_lighting` hard-refuses (raises) when any floor-area space type is
  unresolvable — the allowance for an unlisted space function is a human
  judgement (4.2.1.6.(1)(b)), so no fallback value is invented; and the
  umbrella's `performance_compliance` pre-flights **every** floor-area space
  type against the catalog before any transform or simulation, failing with
  the full unmatched list and nearest-catalog-name suggestions (deterministic
  token overlap — never auto-applied, because 12 catalog pairs differ only by
  a size threshold no string metric can choose between). This is a breaking
  change for untagged models, by design: you cannot certify a building whose
  reference silently failed to build;
- **(fixed)** the reference air-leakage default cleared only
  `SpaceInfiltrationDesignFlowRate`, so a proposed expressing infiltration as
  `EffectiveLeakageArea` or `FlowCoefficient` kept it **and** gained the NECB
  default on top — roughly double infiltration. All three representations are
  now cleared, and the audit records how many of each were removed
  (`proposed_infiltration_objects_cleared`).

Both are *permissive*: they make a proposed building easier to pass. Both were
invisible because the tests that covered these articles asserted on **audit
strings** rather than model values, and the audit reports success in both
cases.

Both fixes followed the same pattern: the hostile test was written first and
failed, the fix made it pass, and the test now stands as the regression guard.
For lighting, the interpretation question ("what should the reference do for a
space type not in the catalog?") was answered *refuse loudly, suggest, never
guess* — the pre-flight gate makes a silently-wrong determination impossible
rather than trying to invent an allowance no one authorized.

## The checks

### `rake necb:orphan_keys` — static, no SDK

Every top-level key in a `*_rules_*.json` must be read by that gem's `lib/`.
A key nothing reads is dead config: either the behaviour is missing, or — more
often here — it exists but reads a **hardcoded constant**, so the JSON and the
code can drift apart silently.

Documentation keys are exempted explicitly via `"non_rule_keys": [...]` in the
JSON, so exemptions are reviewable in a diff rather than inferred from naming.

The remedy text deliberately offers *wire it up* alongside *implement* and
*downgrade*: several currently-flagged keys back behaviour that **is**
implemented with the constants duplicated in Ruby, and telling someone to
"implement" it would be the wrong work.

### `rake necb:hostile` — SDK only, no `openstudio` CLI

Per gem, `test/test_necb_hostile_reference.rb`:

1. builds a proposed model and drives the governed quantities deliberately
   out of compliance (lighting power 99 W/m², infiltration ~50x the default);
2. generates the reference;
3. asserts the reference carries the **code** value, not the hostile one.

Every assertion is on a **model value**. Audit assertions are not accepted as
evidence here — the defects above prove the audit can report success while the
model is unchanged.

Each file pairs a *positive control* (a case where the transform must fire)
with the reproduction. If the control fails, the harness is broken and the
reproduction proves nothing.

Reference generation runs no EnergyPlus, so these tests need only
`require 'openstudio'` — they do **not** skip on a node without the CLI, unlike
the e2e suites.

## Deliberate exemptions

Some rules legitimately leave the reference equal to the proposed, and the
hostile tests must not flag them:

- **Plenums** are skipped by design in the lighting transform.
- **Follows-proposed rules** — e.g. reference heating energy type follows the
  proposed (8.4.4.9.(4)).
- **Lesser-of rules** — e.g. equipment oversizing (8.4.4.8) legitimately
  retains a proposed value already below the cap.
- **`satisfied_by_clone` articles** — schedules and occupancy/receptacle loads
  (8.4.3.2) *must* be identical between the two models.

Where an exemption exists, pin it with an assertion, so a later fix cannot
silently convert a deliberate exemption into a behaviour change.

## A note on evidence standards

An earlier draft of this work asserted a third defect — that equipment
oversizing (8.4.4.8) was a de-facto no-op because `SizingParameters` default to
1.0. **That was false.** They default to 1.25 / 1.15, so the cooling cap fires
and mutates the model on every default-built model. The claim had been written
up as "verified" without ever running the one-line check that refutes it.

Two consequences are baked into these checks:

- assertions are on model values, executed, never on prose or narration;
- `rake necb:hostile` must **not** flag oversizing. If it ever does, the
  harness is miscalibrated — not the code.

The same discipline applies to reading this document: a claim here is only as
good as the test next to it.

## Scope limits

- **Capacity-binned rules** (boiler staging, chiller split, DX bins, fan power
  curves) key on rated capacity, which needs sized equipment. One hostile
  fixture exercises one bin branch, so these articles remain **unproven** by
  this harness. They are not covered — do not read a green `necb:verify` as
  covering them.
- The checks prove a transform *fires* and produces the *code value*. They do
  not prove the code value is the right reading of the article; that still
  needs a human against the NECB text.
