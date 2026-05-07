# Schedule Editor

A browser-based tool for comparing and tuning parametric schedules against ASHRAE 90.1 reference (explicit) schedules. It provides a three-pane interface backed by a local Ruby/Sinatra server.

## Overview

```
┌─────────────────┬────────────────────────────┬──────────────────────┐
│   Left pane     │       Middle pane          │     Right pane       │
│                 │                            │                      │
│ Space type tree │ Calendar map (day types)   │ Global controls      │
│   + schedule    │                            │ ASHRAE reference     │
│   management   │ Profile charts:            │   selector           │
│                 │   – Grey = ASHRAE std      │ Profile metadata     │
│                 │   – Colored = parametric   │ Parameter sliders    │
└─────────────────┴────────────────────────────┴──────────────────────┘
```

**Left pane** — browse space types and their linked schedules (occupancy, lighting, electric equipment, gas equipment). Create new schedules or duplicate/unassign existing ones.

**Middle pane** — a D3-style calendar map that colours each day of the year by its assigned day-type profile (Default, Wkdy, Wknd, Mon–Sun, etc.). Clicking a day activates the corresponding profile tab. Profile charts show the ASHRAE standard (grey, step-after) and the expanded parametric curve (coloured) overlaid.

**Right pane** — edit parameters for the active schedule and day-type profile:
- **Timesteps per hour** — controls expansion resolution (shared across all profiles)
- **ASHRAE reference selector** — choose which standard schedule to compare against
- **Profile metadata** — rename the day-type token or adjust start/end date ranges for non-Default profiles
- **Occupancy sliders** — start time, end time, base fraction, peak fraction (each shows its default value as a reference mark)
- **Derived controls** — base, peak, response, and derivation type for lighting/equipment schedules; derivation types: `linear`, `exponential`, `exponential-inverse`, `up_down`

Changes are held in memory as a working copy. Click **Save changes** to write modified data back to the source JSON files on disk.

## Prerequisites

- Ruby (compatible with the project's Gemfile; tested with the version in `.ruby-version`)
- Bundler gem (`gem install bundler`)
- Node.js ≥ 18 and npm

## Running the tool

### 1. Install Ruby dependencies

```powershell
cd utilities/schedule_editor
$env:BUNDLE_GEMFILE = "server_gemfile"
bundle install
```

### 2. Start the API server

```powershell
# From the repo root:
cd utilities/schedule_editor
$env:BUNDLE_GEMFILE = "server_gemfile"
bundle exec ruby server.rb
```

The server listens on **http://localhost:4567**. Leave this terminal running.

### 3. Install frontend dependencies (first run only)

```powershell
cd utilities/schedule_editor/app
npm install
```

### 4. Start the frontend dev server

```powershell
cd utilities/schedule_editor/app
npm run dev
```

Open **http://localhost:5173** in a browser. API requests are proxied automatically to port 4567.

### 5. Build for production (optional)

```powershell
cd utilities/schedule_editor/app
npm run build
# Output is written to utilities/schedule_editor/app/dist/
```

## Architecture

| File/directory | Purpose |
|---|---|
| `server_gemfile` | Isolated Gemfile for the Sinatra server (sinatra, rack-cors, puma) |
| `server.rb` | Sinatra API server — loads schedule data files and exposes five endpoints |
| `app/` | Vite + React frontend |
| `app/src/context.jsx` | Global state (`useReducer`) and all action type constants |
| `app/src/api.js` | Fetch wrappers for each server endpoint |
| `app/src/components/` | React components (one file per UI panel/widget) |
| `app/src/utils/` | Pure utility functions (`dayAssignment.js`, `expandDebounced.js`) |

### Server endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/data` | Returns all schedule JSON data files as one payload |
| `POST` | `/api/expand_parametric` | Expands occupancy schedule control points via `expand_schedule_control_points` |
| `POST` | `/api/expand_slope` | Expands slope-based schedules via `expand_schedule_start_end_slope` |
| `POST` | `/api/derive` | Derives lighting/equipment profiles from occupancy via `derive_values` |
| `POST` | `/api/save` | Atomically writes modified data back to allowed JSON targets on disk |

### Data files (read from `lib/openstudio-standards/schedules/data/`)

| Key | File |
|---|---|
| `occupancy_schedules` | `default_parametric_occupancy_schedules.json` |
| `schedule_sets` | `default_parametric_schedule_set.json` |
| `lighting_params` | `default_lighting_parameters.json` |
| `elec_equip_params` | `default_electric_equipment_parameters.json` |
| `gas_equip_params` | `default_gas_equipment_parameters.json` |
| `hot_water_params` | `default_hot_water_equipment_parameters.json` |
| `ashrae_schedules` | `ashrae_90_1.schedules.json` |
