# Custom Building Types

openstudio-standards can create a complete typical model of a **custom building type**: a named mix of standard space types with custom area ratios, building form, schedule overrides, and internal load overrides. This is done without adding any new standards data — the custom building borrows loads, schedules, ventilation, and service water heating from standard *donor* space types, then applies your overrides on top.

## Concept: donor space types

Every space type in a model carries a `standardsBuildingType` and `standardsSpaceType` pair. That pair is the lookup key for all standards data (internal loads, parametric schedule sets, ventilation, exhaust, service water heating, thermostats). A custom building keeps those keys pointing at *standard* building/space types so all data lookups keep working, and expresses its customization through:

- **custom area ratios** — any mix of `BuildingType | SpaceType` pairs, across building types
- **building form** — floor area, stories, aspect ratio, window-to-wall ratio, story heights
- **schedule overrides** — parametric schedule parameters (base, peak, ...) per space use
- **load overrides** — occupant density, lighting/equipment power density, ventilation rates
- **a name** — a label on the Building object that does not affect any lookup

## One-call API

```ruby
require 'openstudio-standards'

model = OpenStudio::Model::Model.new
spec = JSON.parse(File.read('my_building.json'), symbolize_names: true) # or a Ruby hash
result = OpenstudioStandards::CreateTypical.create_custom_building_from_spec(model, spec)
```

The spec is validated **before the model is touched**; on failure the method returns `false`, logs every validation error, and leaves the model empty.

### Example specification

```jsonc
{
  "$schema": "./custom_building_spec_schema.json",
  "name": "Mixed Use Campus Hub",
  "template": "90.1-2013",
  "climate_zone": "ASHRAE 169-2013-4A",
  "primary_building_type": "MediumOffice",
  "space_type_ratios": [
    { "building_type": "MediumOffice", "space_type": "Conference", "ratio": 0.2 },
    { "building_type": "PrimarySchool", "space_type": "Corridor", "ratio": 0.125, "circ": true },
    { "building_type": "PrimarySchool", "space_type": "Classroom", "ratio": 0.175, "default": true },
    { "building_type": "Warehouse", "space_type": "Office", "ratio": 0.5 }
  ],
  "form": {
    "total_bldg_floor_area": 50000.0,
    "num_stories_above_grade": 2,
    "ns_to_ew_ratio": 2.0,
    "wwr": 0.3,
    "floor_height": 12.0
  },
  "schedule_overrides": [
    { "space_type": "*", "lighting": { "base": 0.02 } },
    { "space_type": "conference/meeting/multipurpose", "occupancy": { "base": 0.03, "peak": 0.85 } }
  ],
  "load_overrides": [
    { "space_type": "*", "lighting": { "w_per_area": 0.85 } },
    { "space_type": "classroom/lecture/training", "people": { "people_per_1000_ft2": 40.0 } }
  ],
  "typical_options": { "add_hvac": false, "schedule_method": "parametric" }
}
```

More examples live in `lib/openstudio-standards/create_typical/data/examples/`.

### The schema

The full spec structure — every key, type, range, and unit — is documented by the JSON Schema at
`lib/openstudio-standards/create_typical/data/custom_building_spec_schema.json`.

Tip: add a `"$schema"` key pointing at that file (relative or absolute path) to your spec JSON and editors like VS Code will provide autocomplete, hover documentation, and inline validation as you type.

Rules the schema cannot express are checked at runtime against live standards data: the template must be resolvable, each `building_type | space_type` pair must exist in the standards space type data for the template, ratios must sum to 1.0, `primary_building_type` must be a standard building type, and `typical_options` keys must be actual arguments of `create_typical_building_from_model`.

## Spec reference

### Top-level keys

| Key | Required | Meaning |
|---|---|---|
| `template` | yes | OpenStudio Standards template, e.g. `90.1-2013` |
| `climate_zone` | yes | e.g. `ASHRAE 169-2013-4A` |
| `space_type_ratios` | yes | array of space type ratio entries (below) |
| `name` | no | building label; sets the Building name and a `custom_building_type` additional property |
| `primary_building_type` | no | standard building type driving form defaults, construction set, internal mass, and HVAC assumptions; defaults to the first entry's type (form) and the largest floor area (the rest) |
| `form` | no | bar geometry arguments (see schema for the full list) |
| `schedule_overrides` | no | parametric schedule overrides |
| `load_overrides` | no | internal load overrides |
| `typical_options` | no | extra `create_typical_building_from_model` arguments, e.g. `add_hvac`, `hvac_system_type` |

### Space type ratio entries

Each entry requires `building_type`, `space_type`, and `ratio` (all ratios sum to 1.0). Optional per-entry keys override the built-in space type metadata:

- `story_height` (ft) — gives the space type its own taller/shorter bar section
- `wwr` — per-space-type window-to-wall ratio (used when the building-level wwr resolves to 0)
- `default` / `circ` — mark one perimeter and one circulation space type per building type to enable double-loaded corridor placement
- `space_type_gen` — set `false` to create the space type without geometry
- `position` / `orientation` — plan position and facade preference for the perimeter/core division method (see [Positioning and zoning space types](#positioning-and-zoning-space-types))

## Positioning and zoning space types

By default the bar geometry gives every space type exterior walls. To place occupied space
types along the facades and support space types in the interior, set the form key
`bar_division_method` to `"Multiple Space Types - Perimeter and Core Sliced"`. Space types
are then classified as **perimeter** (facades, windows) or **core** (interior, no exterior
exposure), and the floor areas still match the requested ratios exactly.

### How a space type is classified

Precedence, strongest first:

1. **Explicit** — the `position` key on a space type ratio entry (`"perimeter"`, `"core"`,
   or `"any"`).
2. **Circulation flag** — an entry marked `circ: true` is placed in the core.
3. **Name heuristic** — keywords in the standards space type name:

| Position | Example keywords |
|---|---|
| core | corridor, restroom, stair, storage, mechanical, electrical, data center, server, IT closet, refrigeration, walk-in, cooler, freezer, janitor, laundry, locker |
| perimeter | office, classroom, lecture, patient room, guest room, exam, dining, retail, sales, lobby, apartment, ward, daycare, library |

Names matching no keyword are classified by size: types smaller than
`position_size_threshold` (default 0.05 of the building) go to the core, larger ones to the
perimeter. A keyword match always wins over size. When the core-assigned area does not fit
the geometry, area spills between bands (never moving explicit assignments before automatic
ones); the log records each move.

An optional `orientation` array (`["south", "east"]`, …) on a perimeter entry biases it
toward those facades. It is a preference: overflow continues onto adjacent facades.

Depth of the perimeter band is solved from the core area and clamped to
`[perimeter_depth_min, perimeter_depth_max]` (default 8–25 ft); `perimeter_zone_depth`
(default 15 ft) is the target used when there are no core space types.

### Grouping spaces into thermal zones

Independently of position, the form key `zoning_method` controls how spaces become thermal
zones:

- `"Individual Spaces"` (default) — one zone per space.
- `"Perimeter Orientation and Core"` — per story, one zone per facade (N/S/E/W) plus a
  combined core zone; load-distinct types (mechanical, electrical, data center, server,
  kitchen, lab, refrigeration) each get their own zone.
- `"Space Type Groups"` — custom grouping driven by the `zone_groups` form key.

Each `zone_groups` entry has a `name`, a `space_types` list of `"BuildingType|SpaceType"`
keys (a bare space type name matches across building types), a `zone_per` granularity
(`"group"` = one zone per story, `"space"` = one per space, `"facade"` = one per facade run,
`"space_type"` = one per space type), and an optional `position` filter (`"core"` or
`"perimeter"`). Spaces unmatched by any group fall back per `zone_group_default`
(`"heuristic"` or `"individual"`). Grouped zones carry a `zone_group` additional property,
and zone names follow `Zone <story> <label>` (e.g. `Zone Story ground perimeter S`,
`Zone Story ground core support`). When a perimeter multiplier greater than 1 produces two
detached bars, each bar gets its own zones and the second bar's names are auto-suffixed
(`Zone Story ground core 1`) — this is expected, not a duplicate.

```jsonc
"form": {
  "bar_division_method": "Multiple Space Types - Perimeter and Core Sliced",
  "zoning_method": "Space Type Groups",
  "zone_groups": [
    { "name": "core support", "space_types": ["PrimarySchool|Corridor", "PrimarySchool|Restroom"], "zone_per": "group", "position": "core" },
    { "name": "electrical",   "space_types": ["PrimarySchool|Mechanical"], "zone_per": "space" },
    { "name": "classrooms",   "space_types": ["PrimarySchool|Classroom"], "zone_per": "facade" }
  ]
}
```

See `data/examples/custom_perimeter_core_building.json` for a complete spec.

### Override matching

Both override arrays use the same matching rules. Each entry is keyed by one of `space_type`, `schedule_set`, or `standards_space_type` — matched against the space type's `schedule_set` and `standards_space_type` additional properties — or the `"*"` wildcard. The wildcard applies first and a specific entry's fields win over it, field by field.

To discover the matching keys available for your template, build a model and inspect the space types:

```ruby
model.getSpaceTypes.each do |st|
  puts "#{st.name}: schedule_set=#{st.additionalProperties.getFeatureAsString('schedule_set')}, " \
       "standards_space_type=#{st.additionalProperties.getFeatureAsString('standards_space_type')}"
end
```

(e.g. `MediumOffice Conference` resolves to the standards space type `conference/meeting/multipurpose`.)

### Load override fields (IP units)

| Section | Fields |
|---|---|
| `people` | `people_per_1000_ft2` |
| `lighting` | `w_per_area` (W/ft²), `w_per_person` |
| `electric_equipment` | `w_per_area` (W/ft²) |
| `gas_equipment` | `btu_per_hr_per_area` (Btu/hr·ft²) |
| `ventilation` | `cfm_per_person`, `cfm_per_area` (cfm/ft²), `ach` |

When an override targets a load the standards data created no instance for (e.g. adding people to a corridor with zero standard occupant density), the load is created.

## Lower-level APIs

The wrapper composes three calls you can also use directly:

1. `OpenstudioStandards::Geometry.create_bar_from_space_type_ratios(model, args)` — accepts `args[:space_type_ratios]` (array or JSON string) plus form arguments, `args[:primary_building_type]`, and `args[:building_form_defaults]` for non-standard primary types.
2. `OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: ...)`
3. `OpenstudioStandards::CreateTypical.create_typical_building_from_model(model, template, ...)` — accepts `schedule_overrides:`, `load_overrides:`, `primary_building_type:`, and `building_name:` (each override argument takes a Ruby array or JSON string).

`OpenstudioStandards::CreateTypical.validate_custom_building_spec(spec)` returns the validation error list without building anything.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| `spec.space_type_ratios: ratios sum to X, expected 1.0` | ratios don't sum to 1.0 | adjust ratios |
| `'BT \| ST' was not found in the standards space type data` | wrong building/space type name for the template | check spelling against the template's space type data; entries with geometry metadata only warn |
| `spec.primary_building_type: '...' is not a recognized standard building type` | custom name in `primary_building_type` | use a standard type there; put the custom label in `name` |
| `spec.typical_options.X: not an argument of create_typical_building_from_model` | typo or unsupported option | check the method signature |
| `No aspect ratio form default is available for building type '...'` | non-standard primary type at the geometry level without form info | supply `form` values or `form.building_form_defaults` |
| `... entry 'X' did not match any space type's schedule set or standards space type` (warning) | override key matches nothing | inspect the model's space type additional properties for valid keys |
| Space type has no loads/schedules after the run (warning: `... was not found in the standards data`) | space type pair missing from standards data | use a valid donor pair; overrides can adjust its values afterwards |
| `... placed partly in the core to fill the interior` (info) | more perimeter-assigned area than the facades hold | expected for deep floor plates; assign more types to the core or lower the aspect ratio to reduce it |
| `... preferred facades are full; overflow placed on adjacent facades` (warning) | an `orientation` preference could not be fully honored | reduce the type's area or spread the preference across more facades |
| `... perimeter depth reduced below the minimum to fit` (warning) | explicit `core` area exceeds the interior even at the maximum depth | reduce explicit core ratios or raise `perimeter_depth_max` |
| `Bar is too narrow for a meaningful core; using sliced layout instead` (warning) | aspect ratio/width leaves no interior | lower `ns_to_ew_ratio` or increase floor area |
| `Thermal zone ... groups space types with different standards setpoint schedules` (warning) | a zone group mixes types with different setpoints | put the type in its own `zone_groups` entry, or rely on the zone-alone heuristic |
| `... matched multiple zone groups; using the first` (warning) | overlapping `zone_groups` entries | order groups by precedence or make `space_types` lists disjoint |
