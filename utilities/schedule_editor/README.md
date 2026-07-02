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

**Left pane** — browse space types and their linked schedules (occupancy, lighting, electric equipment, gas equipment, hot water equipment). Create new schedules or duplicate/unassign existing ones. The **Schedules** tab lists schedules by category (Occupancy, Lighting, Equipment, Hot Water, Diurnal); hot water schedules come from `default_hot_water_equipment_parameters.json`.

**Middle pane** — a D3-style calendar map that colours each day of the year by its assigned day-type profile (Default, Wkdy, Wknd, Mon–Sun, etc.). Clicking a day activates the corresponding profile tab. Profile charts show the ASHRAE standard (grey, step-after) and the expanded parametric curve (coloured) overlaid.

**Right pane** — edit parameters for the active schedule and day-type profile:
- **Timesteps per hour** — controls expansion resolution (shared across all profiles)
- **Building hours override** — optional weekday/weekend start+duration windows that drive st/et for all profiles (weekend profiles — `Wknd`/`Sat`/`Sun` — use the weekend window). Disabled by default so per-profile sliders drive expansion.
- **Load timing offsets** — schedule-set `start_time_offset`/`end_time_offset`, applied to direct-load previews.
- **ASHRAE reference selector** — pick a template + space type; each displayed schedule's grey reference line is loaded from the matching `{template}.spc_typ.json` field (occupancy → `occupancy_schedule`, lighting → `lighting_schedule`, electric/gas equipment → `*_equipment_schedule`, hot water → `service_water_heating_schedule`). When a space type is selected, the space-type list is **pre-filtered** to the closest ASHRAE equivalents for the current template (from `ashrae_space_type_map.json`); tick **Show all** to search every space type in the template.
- **Profile metadata** — rename the day-type token or adjust start/end date ranges for non-Default profiles
- **Occupancy / direct-load sliders** — start time, end time, base fraction, peak fraction (each shows its default value as a reference mark)
- **Expansion** — expander selection (`control points` vs `slope`), adjustment mode (`stretch` / `truncate`), and slope inputs
- **Derived controls** — base, peak, response, and derivation type for derived lighting/equipment schedules; derivation types: `linear`, `exponential`, `exponential-inverse`, `up_down`
- **Base/peak mode** — `absolute` (default) makes base/peak the absolute output endpoints (the occupancy presence is rescaled by the occupancy schedule's own base/peak); `relative` is the legacy behavior where base/peak are applied relative to the occupancy base/peak. Saved as `base_peak_mode` on the derived load's `*_parameters.json` record.
- **Diurnal gate** — for a derived load, pick a `Diurnal` profile (e.g. `sleep awake`), a mode
  (`off_when_asleep` → `gate = 1 − weight·d`, `on_when_asleep` → `gate = weight·d`), and a weight. The gate
  scales occupancy presence before derivation, so the load is suppressed (or boosted) by the time-of-day
  signal; the gate curve is drawn as a faint dashed line on the chart. The `diurnal_profile`,
  `diurnal_mode`, and `diurnal_weight` inputs are saved back to the derived load's `*_parameters.json` record.

### Editing control points

Each occupancy / direct-load chart has an **✎ Edit points** button. It opens a control-point
editor pinned to the schedule's *standard* coordinates (`st_std`/`et_std`/`base_std`/`peak_std`),
where you can:
- **drag** a marker to move a control point (time snaps to whole-hour offsets from `st`/`et`; values are fractional),
- **double-click** the plot or use **＋ Add point** to add a control point,
- **delete** the selected point, and
- edit each point's symbolic expression (anchor / operator / magnitude) directly in the table.

Drags are re-encoded back into the relative `["st+2", "peak*0.87"]` grammar, so edited points still
stretch correctly when `st`/`et`/`base`/`peak` change.

### Categories and direct loads

`default_parametric_schedules.json` holds **Occupancy**, **Lighting**, **Equipment**, and **Diurnal**
records. A schedule-set load slot whose name matches a parametric record of that category is a
**direct** load (expanded from its own control points, badged *direct* in the tree) rather than being
derived from occupancy. The Schedules tab has a category filter for browsing them.

Changes are held in memory as a working copy. Click **Save changes** to write modified data back to the
source JSON files on disk; the writer preserves each file's committed formatting so unchanged records
stay byte-identical.

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
| `ashrae_space_type_map.json` | Generated mapping: each level-1 space type → its closest ASHRAE `{template} building_type - space_type` equivalents (with each one's `service_water_heating_schedule`). Served in `/api/data` and used to pre-filter the reference selector. |
| `generate_ashrae_space_type_map.rb` | Regenerates `ashrae_space_type_map.json` by scanning every `{template}.spc_typ.json` and scoring equivalence (name similarity + `standards_building_type` vs `building_type`). |
| `apply_hot_water_from_map.rb` | One-off: uses the mapping to give level-1 space types (whose closest ASHRAE equivalent defines a `service_water_heating_schedule`) a placeholder hot water param in `default_hot_water_equipment_parameters.json`, linked in `default_parametric_schedule_set.json`. |

### Server endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/data` | Returns all schedule JSON data files as one payload |
| `POST` | `/api/expand_parametric` | Expands schedule control points via `expand_schedule_control_points` |
| `POST` | `/api/expand_slope` | Expands slope-based schedules via `expand_schedule_start_end_slope` |
| `POST` | `/api/evaluate_control_points` | Returns the raw (un-smoothed) control-point anchors via `evaluate_schedule_control_points` |
| `POST` | `/api/derive` | Derives lighting/equipment profiles from occupancy via `derive_values` |
| `POST` | `/api/save` | Atomically writes modified data back to allowed JSON targets on disk (preserving committed formatting) |

### Data files (read from `lib/openstudio-standards/schedules/data/`)

| Key | File |
|---|---|
| `parametric_schedules` | `default_parametric_schedules.json` (Occupancy + Lighting + Equipment + Diurnal) |
| `schedule_sets` | `default_parametric_schedule_set.json` |
| `lighting_params` | `default_lighting_parameters.json` |
| `elec_equip_params` | `default_electric_equipment_parameters.json` |
| `gas_equip_params` | `default_gas_equipment_parameters.json` |
| `hot_water_params` | `default_hot_water_equipment_parameters.json` |
| `ashrae_schedules` | `ashrae_90_1.schedules.json` |
