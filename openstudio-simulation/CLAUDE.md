# CLAUDE.md — openstudio-simulation

The lowest-level gem of the family: EnergyPlus execution with a pluggable
backend. **Only this gem and the umbrella (via its `Runner` alias) ever
simulate** — the domain gems are SDK-only by contract.

## Architecture

- `runner.rb` — `attach_weather!(model, epw:, ddy:)` (EPW + DDY design days),
  `run_energyplus!` (writes in.osm/in.osw, drives the `openstudio` CLI),
  `energy_results` (End Uses via TabularData GJ rows — SqlFile has NO
  fuel-agnostic end-use methods), unmet hours, `clean_run?`. District-energy
  accessors were renamed across SDK versions — probe with `respond_to?`.
- `backends.rb` — `Backend` seam. `Local` runs `openstudio run -w in.osw`.
  `Remote` is a documented stub whose docstring mirrors the real hbix
  AWS-Batch service (upload_model → presigned S3 PUT → submit_simulation →
  poll → get_simulation_results).

## Key facts / traps

- **`engine_version:` must match the model's version on the remote service** —
  version translation is FORWARD-ONLY; a server defaulting to an older
  OpenStudio cannot open a newer OSM (hard-won).
- Remote submits can transiently 503/timeout during service deploys or after
  idle — retry with backoff before concluding the service is down; submit is
  deployed separately from the read/upload endpoints.
- The remote OSM path (2-phase openstudio workflow) and the IDF path are both
  verified working against the live service; results matched local to the
  decimal.

## Tests

`cd openstudio-simulation && ruby test/test_XX.rb` (skip without the CLI).
