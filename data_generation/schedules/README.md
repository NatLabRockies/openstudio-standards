# Schedule data-generation scripts

These are **developer / data-generation utilities**, not part of the
`openstudio-standards` library. They were relocated here from
`lib/openstudio-standards/schedules/` so they are not loaded with the gem.

Each script guards its top-level execution with `if __FILE__ == $PROGRAM_NAME`,
so requiring it has no side effects; run them directly to regenerate data.

| Script | Purpose |
|---|---|
| `occ_schedule_converter.rb` | Convert standard time–value occupancy schedules into parametric control-point form (`default_parametric_schedules.json`). |
| `analyze_schedule_data.rb` | Earlier analysis pass deriving parametric parameters (st/et, base/peak, control points) from standard schedule data. |
| `parametric_refactor_poc.rb` | Standalone proof-of-concept for the smootherstep interpolation; draws ASCII charts (requires the `ascii_charts` gem). |

Run from the repository root, e.g.:

```sh
ruby data_generation/schedules/occ_schedule_converter.rb
```
