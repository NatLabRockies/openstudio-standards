# User Quick Start Guide

## Create Typical Building

Starting with OpenStudio 3.8.0, the "Create Typical Building from Model" measure is available on BCL and fully uses methods from openstudio-standards.

1. Components & Measures > Find Measures, download Whole Building > Space Types > Create Typical Building from Model
2. Components & Measures > Apply Measure Now > Whole Building > Space Types > Create Typical Building from Model
3. Pick the building type/climate zone/vintage
4. Run

## Parametric Internal Load Schedules

`OpenstudioStandards::Schedules.space_type_apply_parametric_internal_load_schedules`
applies occupancy, lighting and equipment schedules using a space type's `schedule_set`
additional property. It accepts weekday/weekend operating hours and per-load
`schedule_overrides`. For example:

```ruby
space_type.additionalProperties.setFeature('schedule_set', 'office schedule set')
OpenstudioStandards::Schedules.space_type_apply_parametric_internal_load_schedules(
  space_type, wkdy_start_time: 8.0, wkdy_duration: 10.0,
  schedule_overrides: [{ space_type: '*', occupancy: { peak: 0.8 } }]
)
```

The shared engine reads category-specific `default_*_schedules.json` files.
It supports control-point time warping, truncate adjustment, base/peak overrides,
and occupancy-derived load schedules. Existing schedule-set names (such as
`office_open`), legacy profile/derivation datasets and the older
`resolve_load_schedule` call form remain supported. The former `static` adjustment
name is accepted as an alias for `truncate`.

New derivations default to absolute base/peak endpoints. Legacy schedule sets keep
relative occupancy scaling; `base_peak_mode: 'relative'` also selects that behavior
when calling the derivation engine directly.

New schedule sets that explicitly omit a load schedule remove that load's objects
rather than leaving unscheduled loads in the model. Select the corresponding
`set_people`, `set_lights` or equipment flags to control which loads are updated.
Legacy schedule-set names retain their previous null-slot behavior.

## Using OpenStudio-Standards in Measures
**This gem is included with the OpenStudio installer**.  All you need to do is add `require openstudio-standards` to your `measure.rb` file and you will have access to the methods in this gem:

    class MyMeasureName < OpenStudio::Measure::ModelMeasure

     require 'openstudio-standards'
     ...

## Installing OpenStudio-Standards from RubyGems
If you want to install a newer release of this gem from RubyGems.org than what is available in the OpenStudio installer, follow the instructions on the {file:docs/DeveloperInformation.md Developer Information page}.
