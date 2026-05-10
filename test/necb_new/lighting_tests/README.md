# NECB Lighting Requirements Test Suite

## Overview

This test suite validates the lighting power density (LPD) calculations, lighting control requirements, and schedule applications for NECB (National Energy Code of Canada for Buildings) standards across multiple vintages.

## Test File Location

`/workspaces/openstudio-standards/test/necb_new/lighting_tests/test_necb_lighting.rb`

## Target Implementation

Tests the implementation in:
`/workspaces/openstudio-standards/lib/openstudio-standards/standards/necb/NECB2011/lighting.rb` (168 lines)

Also validates behavior across vintages:
- NECB2011
- NECB2015 (includes occupancy sensor control schedules)
- NECB2017
- NECB2020

## Test Coverage

### Test 1: LPD Lookup by Space Type
**Purpose:** Verify that lighting power density values can be retrieved from standards data for various space types across all NECB vintages.

**Space Types Tested:**
- Office - enclosed
- Office - open plan
- Retail - sales
- Warehouse - fine
- Classroom/lecture/training

**Validates:**
- Space type properties are accessible
- LPD values are non-negative
- Different vintages may have different data structures

### Test 2: Occupancy Sensor LPD Reduction
**Purpose:** Verify that specific space types receive a 0.9 reduction factor when occupancy sensors are required per NECB2011 Article 8.4.4.6(3) and 4.2.2.2(2).

**Space Types with Reduction:**
- Classroom/lecture/training
- Conf./meet./multi-purpose
- Washroom-sch-A
- Additional spaces per `reduce_lpd_spaces` array in lighting.rb

**Validates:**
- Base LPD is correctly retrieved
- 0.9 factor is applied to specified space types
- Calculated LPD matches expected value within tolerance

### Test 3: Apply Standard Lights to Space Type
**Purpose:** Verify that lights are properly assigned to space types when applying NECB loads.

**Validates:**
- All space types in a building model receive lights instances
- Lights definitions are created with proper LPD values
- LPD values are positive when defined

### Test 4: Lighting Fractions
**Purpose:** Verify that lighting heat gain fractions are properly set per NECB standards.

**Fractions Tested:**
- Fraction Radiant (typically 0.5 for NECB default)
- Fraction Visible (typically 0.2 for NECB default)
- Return Air Fraction (typically 0.0 for NECB default)

**Validates:**
- Fractions match space_types.json properties
- All three fractions are properly applied to lights definitions

### Test 5: LED vs NECB Default Lighting
**Purpose:** Compare LED lighting to NECB default lighting implementations.

**Validates:**
- Both LED and NECB_Default lights types can be applied
- LED lighting uses different LPD values from led_lighting_data.json
- Both produce valid, positive LPD values
- LED fractions differ from NECB default (per NREL 2014 reference)

### Test 6: Lighting Schedule Application
**Purpose:** Verify that lighting schedules are properly assigned to space types.

**Validates:**
- Default schedule sets receive lighting schedules
- Schedules are ScheduleRuleset objects
- Default day schedules exist
- Schedule names are defined

### Test 7: Lighting Power Scaling
**Purpose:** Verify that the `lights_scale` parameter properly scales LPD values.

**Scale Factors Tested:** 0.8, 1.0, 1.2

**Validates:**
- Scaling is applied correctly to base LPD
- Occupancy sensor reductions are applied before scaling
- Calculated values match expected within tolerance

### Test 8: Multi-Vintage LPD Differences
**Purpose:** Compare LPD values across NECB vintages to verify code evolution.

**Vintages Compared:**
- NECB2011
- NECB2015
- NECB2017
- NECB2020

**Validates:**
- All vintages have LPD values for common space types
- LPD values may differ between vintages
- Logs percentage differences between 2011 and 2020

### Test 9: Additional Lighting Per Area
**Purpose:** Verify that space types with additional lighting receive multiple lights instances.

**Validates:**
- Additional lighting is created when defined in space_types.json
- Multiple lights instances exist for space types with additional lighting
- Additional LPD values are properly applied

### Test 10: NECB2015 Occupancy Sensor Schedules
**Purpose:** Verify NECB2015's occupancy sensor control schedule generation.

**NECB2015 Feature:**
- Spaces with LPD > 8.6 W/m² (0.799 W/ft²) require occupancy sensor controls
- Schedules are modified based on occupancy patterns
- Control factors include `rel_absence_occ`, `personal_control`, and `occ_sense`

**Validates:**
- Lighting schedules are created
- Occupancy sensor schedules include control parameters in name
- Schedules are ScheduleRuleset objects

### Test 11: Lighting Per Person
**Purpose:** Verify support for lighting_per_person (if applicable).

**Note:** Most NECB space types use lighting_per_area, but the code supports lighting_per_person as well.

**Validates:**
- System can handle space types with lighting_per_person
- Watts per person is properly set when defined

## Running the Tests

### Run all lighting tests:
```bash
bundle exec ruby test/necb_new/lighting_tests/test_necb_lighting.rb
```

### Run with verbose output:
```bash
bundle exec ruby test/necb_new/lighting_tests/test_necb_lighting.rb --verbose
```

### Run a specific test:
```bash
bundle exec ruby test/necb_new/lighting_tests/test_necb_lighting.rb --name test_lpd_lookup_by_space_type
```

## Test Results Summary

**Total Tests:** 11
**Total Assertions:** 43+
**Status:** All tests passing

## Key Implementation Details Tested

### Occupancy Sensor LPD Reduction (NECB2011)
From `lighting.rb` lines 150-166:
- Specific space types receive 0.9 factor (10% reduction)
- Applied via `set_lighting_per_area` method
- Logged for verification

### LED Lighting Support
From `lighting.rb` lines 35-51:
- Separate LED data from `led_lighting_data.json`
- Different fractions (return air, radiant, visible) per NREL 2014
- Applied when `lights_type: 'LED'`

### NECB2015 Occupancy Sensor Schedules
From `NECB2015/lighting.rb` lines 10-184:
- LPD threshold: 8.6 W/m²
- Schedule modification based on occupancy patterns
- Complex ruleset generation with multiple day types

## Data Sources

### NECB2011 Data:
- `/lib/openstudio-standards/standards/necb/NECB2011/data/space_types.json`
- `/lib/openstudio-standards/standards/necb/NECB2011/data/led_lighting_data.json`

### NECB2015+ Data:
- `/lib/openstudio-standards/standards/necb/NECB2015/data/space_types.json`
- Includes additional fields: `rel_absence_occ`, `personal_control`, `occ_sense`

## Notes

- Different NECB vintages may use different building_type values in their data
- NECB2011 uses "Space Function" as building_type for many space types
- NECB2015+ may have different data structures for certain space types
- Tests gracefully handle missing space types in certain vintages
- Tolerance of 0.01 W/m² used for floating-point comparisons

## References

- NECB2011: Article 4.2.2.2(2) and 8.4.4.6(3) for occupancy sensor requirements
- NECB2015: Additional occupancy sensor schedule generation (Section 4.2.2)
- LED lighting fractions: NREL (2014), "Proven Energy-Saving Technologies for Commercial Properties", page 142

## Future Enhancements

Potential additional tests:
1. Storage area occupancy sensor requirements (area-dependent)
2. Hospital medical supply area requirements
3. Office enclosed area-based requirements (< 25 m²)
4. Atrium LPD calculations (height-dependent)
5. Daylighting control integration
6. Exterior lighting requirements
7. Exit lighting requirements
8. Lighting schedule type assignments by schedule types (A-I)
