# Custom Building Types

openstudio-standards can create a complete typical model of a **custom building type**: a named mix of space types with custom area ratios, building form, schedule overrides, and internal load overrides. The space type mix comes in one of two forms:

- **standard (donor) space types** — `BuildingType | SpaceType` pairs from the standards data for the template, which borrow loads, schedules, ventilation, and service water heating from the standard data
- **typical space types** — building-type-agnostic space types from `lib/openstudio-standards/space_type/data/level_1_space_types.json` (e.g. `office`, `classroom/lecture/training`), which build loads from the typical lighting, equipment, and ventilation data

## Concept: donor space types

Every space type in a model carries a `standardsBuildingType` and `standardsSpaceType` pair. That pair is the lookup key for all standards data (internal loads, parametric schedule sets, ventilation, exhaust, service water heating, thermostats). A custom building keeps those keys pointing at *standard* building/space types so all data lookups keep working, and expresses its customization through:

- **custom area ratios** — any mix of `BuildingType | SpaceType` pairs, across building types
- **building form** — floor area, stories, aspect ratio, window-to-wall ratio, story heights
- **schedule overrides** — parametric schedule parameters (base, peak, ...) per space use
- **load overrides** — occupant density, lighting/equipment power density, ventilation rates
- **a name** — a label on the Building object that does not affect any lookup

## Concept: typical space types

Alternatively, the mix can be built directly from the **typical space types** in `lib/openstudio-standards/space_type/data/level_1_space_types.json` by omitting `building_type` from every ratio entry:

```jsonc
"space_type_ratios": [
  { "space_type": "office", "ratio": 0.7, "default": true },
  { "space_type": "corridor", "ratio": 0.2, "circ": true },
  { "space_type": "restroom", "ratio": 0.1 }
]
```

These are the same space type names that `schedule_overrides` and `load_overrides` match on, so one vocabulary describes the whole spec. The generated space types carry the typical name as their `standardsSpaceType` and no standards building type of their own (the OpenStudio SDK reports the Building-level standards building type — the `primary_building_type` — by inheritance), and `create_typical_building_from_model` runs with `space_type_load_method: 'typical'`, which bypasses the standards space type load lookups and instead builds:

- **occupancy** at the template (code version) occupant densities from the standards space types data, resolved through the same validated mapping as ventilation; unmapped space types get no occupancy. The `load_overrides` `people` section overrides the result, either directly or through `keep_standard_design_level` (see the load override fields below).

- **interior lighting** from the InteriorLighting module data (illuminance targets by lighting space type and a lighting technology generation — set `"lighting_generation"` in `typical_options` to change it)
- **electric and gas equipment** from the Equipment module data (when a space type's standards building type has no entry, the median value across building types is used)
- **outdoor air ventilation** at the template (code version) rates from the standards space types data, resolved through a validated mapping of typical space types to standards space types (`lib/openstudio-standards/space_type/data/level_1_standards_space_type_map.json`, covering the ASHRAE 90.1, DOE Ref, and DEER templates; DEER vintages after 2020 resolve to the DEER 2020 rows they share); space types without a mapping fall back to Ventilation module data derived from ASHRAE 62.1 (ASHRAE 170 for health care space types). Either way, the `load_overrides` `ventilation` section overrides the resulting rates.
- **parametric schedules and thermostats** from the schedule set and thermostat data associated with each typical space type

Typical **service water heating** equipment definitions are not created yet. A top-level `primary_building_type` is required in this form, since it drives the building form defaults, construction set, internal mass, and HVAC assumptions and cannot be inferred from the entries. The two entry forms cannot be mixed in one spec.

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
| `primary_building_type` | no* | standard building type driving form defaults, construction set, internal mass, and HVAC assumptions; defaults to the first entry's type (form) and the largest floor area (the rest). *Required when the ratio entries are typical space types |
| `form` | no | bar geometry arguments (see schema for the full list) |
| `schedule_overrides` | no | parametric schedule overrides |
| `load_overrides` | no | internal load overrides |
| `typical_options` | no | extra `create_typical_building_from_model` arguments, e.g. `add_hvac`, `hvac_system_type` |

### Space type ratio entries

Each entry requires `space_type` and `ratio` (all ratios sum to 1.0). With a `building_type`, `space_type` is a standard space type within that building type; without one, it is a typical space type from `level_1_space_types.json` (all entries must use the same form). Optional per-entry keys override the built-in space type metadata:

- `story_height` (ft) — gives the space type its own taller/shorter bar section
- `wwr` — per-space-type window-to-wall ratio (used when the building-level wwr resolves to 0)
- `default` / `circ` — mark one perimeter and one circulation space type per building type to enable double-loaded corridor placement
- `space_type_gen` — set `false` to create the space type without geometry

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
| `people` | `people_per_1000_ft2`, `keep_standard_design_level` |
| `lighting` | `w_per_area` (W/ft²), `w_per_person` |
| `electric_equipment` | `w_per_area` (W/ft²) |
| `gas_equipment` | `btu_per_hr_per_area` (Btu/hr·ft²) |
| `ventilation` | `cfm_per_person`, `cfm_per_area` (cfm/ft²), `ach` |

When an override targets a load the standards data created no instance for (e.g. adding people to a corridor with zero standard occupant density), the load is created.

By default `people_per_1000_ft2` sets the design occupancy level. With `keep_standard_design_level: true`, the design level from the standard input is kept and the space type's **occupancy schedule peak** is adjusted instead, so that the peak occupancy (design level × peak schedule value) matches `people_per_1000_ft2` — useful for modeling partial occupancy without changing the installed density. This only takes effect with the parametric schedule method, and a warning is logged for any derived load schedule (lighting, equipment, ...) whose `base_peak_mode` is `relative`, since those schedules follow the occupancy values and will shift along with the adjusted peak.

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
| `spec.space_type_ratios: entries mix standard ... with typical space types` | some entries have `building_type` and some don't | use one entry form for all entries |
| `'X' is not a typical space type` | typical entry name not in `level_1_space_types.json` | check spelling against the `space_type_name` values in that file |
| `spec.primary_building_type: required when space_type_ratios entries are typical space types` | typical entries with no `primary_building_type` | add a standard `primary_building_type` |
| `No electric equipment space type data for '...' ... Using the median value` (info) | typical space type has no equipment data for the building's standards building type | expected for typical mixes; use `load_overrides` to set a specific value |
