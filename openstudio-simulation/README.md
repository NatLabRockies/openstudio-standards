# openstudio-simulation

Run EnergyPlus on an OpenStudio model and get results back — **without** any
compliance layer. This is the lowest-level gem in the family: it depends on
nothing else in the family, only the OpenStudio SDK (and, for local execution,
the `openstudio` CLI on PATH).

Use it when you just want to simulate a model and read the numbers — locally
now, or against a remote/AWS EnergyPlus service later via the same API.

## Quick start — the facade

```ruby
require 'openstudio_simulation'

result = OpenStudioSimulation.run(
  model,
  run_dir: '/tmp/myrun',
  weather: { epw: 'weather.epw', ddy: 'weather.ddy' }, # optional; attaches design days
  run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 } # optional
)

result.clean?      # => true  (E+ completed, no Fatal/Severe)
result.run_dir     # => "/tmp/myrun/run"
result.energy      # => { 'total_site_kwh' => ..., 'end_uses_kwh' => {...}, ... }
result.unmet_hours # => { 'heating' => ..., 'cooling' => ... }
```

`sizing_only: true` runs a design-day sizing pass only; `energy` and
`unmet_hours` are then `nil`.

## Granular API — `OpenStudioSimulation::Runner`

The backend-agnostic steps, if you want them individually:

- `Runner.attach_weather!(model, epw:, ddy:)`
- `Runner.run_energyplus!(model, dir, sizing_only: false, run_period: nil, backend: Local.new)`
- `Runner.clean_run?(run_dir)`
- `Runner.energy_results(model)` — site energy + end-use breakdown (kWh)
- `Runner.unmet_occupied_hours(model)` — Facility setpoint-not-met hours
- `Runner.zone_unmet_occupied_hours(model)` — per-zone unmet occupied hours
  from the SQL (feeds the umbrella's capacity iteration)
- `Runner.request_run_period_variables!(model, names)` — idempotent '*'-keyed
  `OutputVariable` requests at RunPeriod frequency
- `Runner.run_period_sums(model, variable_name)` — per-KeyValue run-period sums
  restricted to `EnvironmentType = 3`, so design days are excluded
- `Runner.openstudio_cli?`

`run_energyplus!` prepares the run directory (sizing flags, run period,
`in.osm` + `in.osw`), delegates the actual EnergyPlus invocation to the
backend, then attaches `run/eplusout.sql` to the model.

## The local-vs-cloud seam — Backends

The one place execution happens is a `Backend`. Its contract: given a `dir`
that already contains `in.osm` + `in.osw`, run EnergyPlus so that
`dir/run/eplusout.sql` **and** `dir/run/eplusout.err` exist, and raise on
failure.

- **`Local`** (default) — runs `openstudio run -w dir/in.osw` on this machine.
- **`Remote`** — a documented stub for a remote/AWS EnergyPlus service. Its
  `execute` raises `NotImplementedError` with the exact contract to implement
  (upload `in.osm`/`in.osw` → trigger → poll → download `eplusout.sql` +
  `eplusout.err` into `dir/run/`). A commented skeleton shows the shape; no
  real AWS client or endpoints are fabricated — wire it to your own service.

```ruby
OpenStudioSimulation.run(model, run_dir: dir,
                         backend: OpenStudioSimulation::Remote.new(endpoint: '…', api_key: '…'))
```

Because every backend lands the same two artifacts on local disk, the result
parsers (`clean_run?`, `energy_results`, `unmet_occupied_hours`) are
transport-agnostic and work unchanged for local or cloud runs.

## Citation conventions

`article:` in audit entries = the NECB clause that mandates a value;
`ruling: 'D-nn'` = the adjudicated reading of it. The registry is
[openstudio-necb/docs/necb_decisions.md](../openstudio-necb/docs/necb_decisions.md)
(id-ordered index at the top) + its drift-tested `decisions.json` mirror;
`L-nn` cites the legacy findings register. The family glossary lives in
[openstudio-necb/docs/README.md](../openstudio-necb/docs/README.md).

## Tests

```bash
cd openstudio-simulation
ruby test/test_backends.rb    # no CLI needed — proves the backend seam
ruby test/test_local_run.rb   # skips without the openstudio CLI — real E+ run
```
