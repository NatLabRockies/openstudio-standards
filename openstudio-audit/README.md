# openstudio-audit

The shared audit machinery of the NECB gem family (see the root README for the
family map): **one** `AuditLog` class and **one** article-coverage emitter,
used by openstudio-hvac, -envelope, -loads, -lighting, -shw, -geometry and the
openstudio-necb umbrella.

No domain knowledge, no OpenStudio dependency — this is the lowest-level gem in
the family. It was extracted from the six verbatim `audit_log.rb` copies the
gems used to each carry; each of those files is now a three-line alias
(`OpenStudioHVAC::AuditLog = OpenStudioAudit::AuditLog`), so every existing call
site keeps working unchanged. The aliases ARE the compatibility mechanism —
there is no second implementation.

```ruby
require_relative 'openstudio-audit/lib/openstudio_audit'

audit = OpenStudioAudit::AuditLog.new
audit.with_building('reference building') do
  audit.decision(:build, 'reference system operates on the proposed operating schedule',
                 target: 'SYS-3 air loop', inputs: { schedule: 'NECB-A' },
                 value: 'NECB-A', article: '8.4.4.7.(1)', ruling: 'D-14')
end
audit.warnings  # never silent: anything skipped/unknown lands here
puts audit.to_s # narrative, one line per entry;  audit.to_json for machines
```

## Entry schema

`{step, target, action, inputs, value, article, ruling, evidence, building, level}`
— all optional except `step` / `action` / `level`; nil fields are compacted
away. `level` is `:decision | :info | :warning`.

- **`article:`** cites the CODE that mandates a value (e.g. `'8.4.4.8.(1)'`).
  Several citations join into one string with `; `.
- **`ruling:`** cites the adjudicated project DECISION that says how we read
  that code (`openstudio-necb/docs/necb_decisions.md`, mirrored machine-readably
  in `decisions.json`). Two axes: what was done, and why we did it that way.
- **`building:`** which model the entry is about (`'input model'`,
  `'proposed building'`, `'reference building'`; nil = cross-building verdict),
  stamped automatically from the `#building` context — set it at phase
  boundaries with `audit.building=` or the nestable `with_building(name) {}`.
- **Contract: warnings are never silent** — anything skipped or unknown lands
  in the log.
- **Audit text convention:** violations are SHOUTED (`EXCEEDS`, `does NOT
  meet`, `BELOW the`), passes lowercase (`does not exceed`, `within`). The
  umbrella report's checklist classifier is deliberately case-SENSITIVE.

### The `ruling:` convention (D-44)

A static drift test in the umbrella (`test_decisions_registry.rb`) greps for
exactly this shape, so:

- TOP-LEVEL kwarg, **never** inside `inputs:`;
- a single-quoted literal on **ONE** line;
- several ids = one space-separated string (`ruling: 'D-19 D-21'`), parsed with
  `OpenStudioNECB::Decisions.ids_in`;
- every id cited must exist in the registry, and every `kind: "runtime"` entry
  there must be cited by at least one tag — the test is hard in both directions;
- `step: :coverage` entries are NOT tagged (manifest boilerplate would swamp the
  report appendix's fire counts).

## The emit contract

Each gem owns an `article_coverage` manifest inside its vintage ruleset JSON
(`implemented` / `partial` / `not_implemented` / `satisfied_by_clone` /
`host_scope`) and resolves it its own way — from a pre-resolved ruleset (hvac),
from `NECB.rules(vintage)` (envelope, lighting, loads, shw), or from a data-file
path (the umbrella). What happens next is identical everywhere and lives here:

```ruby
OpenStudioAudit::Coverage.emit(coverage, audit)  # coverage = the resolved article_coverage hash
```

Every declared article lands in the audit as a `step: :coverage` entry carrying
`inputs: { status:, decisions_citing: }` (plus `gap_owner:` when present) and
the manifest's `article:`, so a missed requirement is visible in every log
rather than discovered by review. Levels:

| status | level |
| --- | --- |
| `implemented`, `satisfied_by_clone`, `host_scope` | `info` |
| `partial`, `not_implemented` | `warning` — on every run |
| any status with `gap_owner: "modeller"` | `info` scope note (D-09) |

`gap_owner: "modeller"` gaps are wholly the modeller's responsibility, so the
AHJ report is not permanently stamped with warnings no model change can clear.

`decisions_citing` counts the run's `article:` tags that PREFIX-match the
manifest id, after stripping a `' (slice label)'` / `'(N)'` suffix and the
trailing dot. Citations are harvested with `/\d+\.\d+(?:\.\d+)*\./`, so a Part 3
or Part 5 citation is scanned but simply never prefix-matches a Part 8 manifest
entry. `emit(nil, audit)` is a no-op — a gem whose ruleset carries no manifest
emits nothing.

## Tests

`cd openstudio-audit && ruby test/test_audit.rb` (SDK-free and fast).
