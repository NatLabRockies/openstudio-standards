# Remote (AWS) backend — implementation plan, ready to execute

Status: **PLANNED, not wired** (phylroy, 2026-08-10: "plan the aws wiring so
its ready"). The `Remote` class in `lib/openstudio_simulation/backends.rb`
is a documented stub whose docstring already carries the validated service
shape; this plan is the execution recipe for the day one of the trigger
conditions fires.

## Trigger conditions (when wiring becomes worth it)

1. **Variant matrices**: fleet × {2020, 2025} × {Electricity, NaturalGas} ×
   {Toronto, Edmonton, Yellowknife} ≈ 500–900 E+ runs — beyond the 48 local
   cores.
2. **CI-hosted sweeps/parity** on runners without local horsepower.
3. **Freeing the workstation** during long baseline refreshes.

NOT a trigger: shortening one building's sequential chain — a remote node
simulates 8760 h no faster than a local core, and Batch adds per-run
overhead (upload, queue, cold start, download).

## The service contract (validated live; region ca-central-1)

```
upload_model(filename)                  -> { model_id, upload_url, s3_key }
PUT model bytes to upload_url           (presigned S3)
submit_simulation(model_id, weather_station_id, weather_format,
                  workflow_type, engine_version, queue)
                                        -> { job_id, status, phases }
get_simulation_status/progress(job_id)  (pending|running|failed|completed)
get_simulation_results(job_id)          -> presigned URLs (~15 min TTL)
```

Hard-won constraints (each cost real time once — do not relearn them):
- **Engine version must match the model; translation is forward-only.** A
  3.11-saved OSM dies instantly on the platform-default 3.9 runner. Pass
  `engine_version:` explicitly; never rely on "latest".
- The `openstudio` workflow is 2-phase (measures 3.x → energyplus); the
  `energyplus` workflow is 1-phase and takes a translated IDF directly.
  Both paths were verified working; **results matched local to the
  decimal** (the fidelity precedent this plan's gate re-proves).
- Submits can transiently 503 after service deploys or idle — retry with
  backoff before concluding the service is down.
- Async on AWS Batch: expect a cold start before `submitted` moves; poll
  on a backoff (15 s default), never tight-loop.

## Design

### 1. `Remote#execute(dir)` — fill the stub, keep the contract

The Backend contract is unchanged: given `dir/in.osm` (+`in.osw`), land
`dir/run/eplusout.sql` and `dir/run/eplusout.err` locally; raise on
failure. Implementation per the stub's 5-step skeleton with:

- **Default path = the 1-phase `energyplus` workflow.** Translate
  `in.osm → in.idf` IN-PROCESS (`OpenStudio::EnergyPlus::ForwardTranslator`
  — no CLI dependency), upload the IDF, submit with
  `engine_version: opts[:engine_version]` (the E+ version, e.g. '25.2' —
  verified available). This sidesteps the OSM-version wall entirely as
  long as the remote E+ matches the local SDK's E+.
- The 2-phase `openstudio` OSM path stays available via
  `workflow_type: 'openstudio'` for models the remote OS engine can open.
- **Version guard:** read the model/IDF version before upload; if it
  exceeds the requested engine, raise with the forward-only explanation —
  never submit a run that will die on the runner.
- Weather: the service resolves `weather_station_id` from its own library;
  the mapping from our EPW basenames to station ids is a small config hash
  passed in `opts` (Toronto/Edmonton/Yellowknife CWEC2020 to start).
  Document that arbitrary local EPWs are NOT uploadable on this path.
- Download both artifacts IMMEDIATELY on completion (15-minute presigned
  TTL); verify non-empty; raise with the phase errors otherwise.
- Retry ladder: submit 503/timeout → exponential backoff ×5; poll
  tolerates transient read errors; a `failed` terminal status raises with
  `phases[].errors`.

### 2. Configuration and credentials

- Constructor args win; env fallbacks:
  `OS_SIM_REMOTE_ENDPOINT`, `OS_SIM_REMOTE_API_KEY`,
  `OS_SIM_REMOTE_ENGINE` (E+ version), `OS_SIM_REMOTE_QUEUE`.
- **Credentials are never committed, never logged, never echoed into
  audit entries or raised messages** (the same hard rule as `costs_csv:`
  and the .mcp.json lesson). Error messages name the endpoint host only.

### 3. Threading the backend through the pipeline

`Runner.run_energyplus!` already takes `backend:`. The umbrella calls it
without one at ~8 sites, so add a **module-level default**:
`OpenStudioSimulation::Runner.default_backend = Remote.new(...)` (falls
back to `Local.new`; per-call `backend:` still wins). No signature churn in
`performance_compliance`; the sweep script opts in with
`REMOTE=1` → sets the default backend from env config at startup. Fork
safety: each forked sweep child constructs its own backend instance (no
shared HTTP state across forks).

### 4. Tests

- **Unit (no network):** inject a fake transport lambda (the DI pattern
  proven in openstudio-geometry's `render.rb` exporter) — happy path,
  submit-503-retry, failed-status raise, TTL-expired re-fetch raise,
  version-guard raise. All fast, all offline.
- **Live smoke (skipped without creds):** `skip 'remote creds not set'`
  unless the env vars exist — the loud-skip convention. One 5ZoneNoHVAC
  sizing run end-to-end.
- **Fidelity gate (the one that matters):** one full building (SmallOffice
  week determination) run twice — Local vs Remote backend — and
  `report.json` compared field-by-field. The precedent says to-the-decimal;
  the gate enforces it before any sweep ever runs remotely.

### 5. Sweep integration (after the backend lands)

`necb_archetype_sweep.rb`: `REMOTE=1` selects the remote default backend
for the E+ runs; generation (legacy `model_create_prototype_model`) STAYS
LOCAL — it is SDK+sizing-run work inside the legacy gem, not a plain E+
execution, and it is already cached. Note the queue-width consequence: 15
buildings × up-to-13-run chains submit sequentially per building — remote
helps exactly when the MATRIX is wide, as stated in the triggers.

### 6. Out of scope (documented, deliberate)

- The service's bulk-submission API (an optimization once single-run
  wiring is proven).
- Cost controls/budget caps — operator concern, noted in the README when
  wired.
- Uploading arbitrary weather files.

## Effort when triggered

~1 day: transport + retries (half day), version guard + weather map,
unit tests with the fake transport, the live smoke, the fidelity gate.
Prerequisite from the operator: the service endpoint + API key as env
vars, and confirmation of the available engine versions that week.
