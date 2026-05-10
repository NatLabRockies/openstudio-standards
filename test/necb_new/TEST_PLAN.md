# Complete NECB Test Scope Analysis

## Implementation Inventory

### Total Codebase
- **NECB Implementation**: ~25,500 lines across 44 files
- **Component Standards**: ~20,000 lines across 41 files  
- **Total Code Under Test**: ~45,500 lines

### NECB by Vintage

| Vintage | Files | Lines | Notes |
|---------|-------|-------|-------|
| NECB2011 | 19 | 14,693 | Complete baseline implementation |
| NECB2015 | 4 | 703 | Inherits 2011, adds lighting/HVAC changes |
| NECB2017 | 2 | 125 | Inherits 2015, minimal changes |
| NECB2020 | 3 | 508 | Inherits 2017, adds new envelope/HVAC rules |
| BTAPPRE1980 | 3 | ~500 | Vintage building standards |
| BTAP1980TO2010 | 4 | ~1000 | Vintage building standards |
| Common/BTAP | 3 | 3,390 | Shared NECB utilities |
| ECMS | 6 | 4,562 | Energy conservation measures |

### Component Standards (Inherited by NECB)

**Major Components** (>500 lines each):
- Standards.Model.rb (6,349 lines) - Core model operations
- Standards.AirLoopHVAC.rb (3,939 lines) - Air system rules
- Standards.Space.rb (2,280 lines) - Space-level operations
- Standards.PlantLoop.rb (1,545 lines) - Plant system rules
- Standards.ThermalZone.rb (708 lines) - Zone-level operations
- Standards.SpaceType.rb (581 lines) - Space type operations

**HVAC Equipment** (~3,000 lines):
- Boilers, Chillers, Cooling Towers
- DX Coils (single, two-speed, multi-speed)
- Heat Pumps (air-to-air, water-to-air)
- Fans, Pumps, Motors

**Building Components** (~1,500 lines):
- Surfaces, SubSurfaces, PlanarSurface
- People, Schedules, Ventilation
- Service Water Heating

## Test Requirements by Component

### 1. EQUIPMENT EFFICIENCY RULES (Pure Unit Tests)

#### 1.1 Boilers (Standards.BoilerHotWater.rb - 181 lines)
**Methods to test:**
- `boiler_hot_water_find_capacity()` - Lookup capacity from sizing
- `boiler_hot_water_find_efficiency()` - Efficiency by capacity/fuel/template
- `boiler_hot_water_standard_minimum_thermal_efficiency()` - Min efficiency lookup

**Test requirements:**
- SIZING: NONE (pure lookups)
- Data source: JSON tables (boilers.json)
- Test inputs: Fuel type, capacity range, template
- Assertions: Efficiency values match standard tables

**NECB-specific:**
- NECB2011: NECB Tables 5.2.12.1, 8.4.4.10
- Different thresholds than ASHRAE 90.1
- Thermal efficiency vs. AFUE vs. combustion efficiency conversions

#### 1.2 Chillers (Standards.ChillerElectricEIR.rb - 294 lines)
**Methods to test:**
- `chiller_electric_eir_find_cop()` - COP by type/capacity/condenser
- `chiller_electric_eir_standard_minimum_full_load_efficiency()` - Min COP
- Performance curves by chiller type

**Test requirements:**
- SIZING: NONE (pure lookups)
- Test inputs: Chiller type, capacity, condenser type, template
- Assertions: COP values match standard

**NECB-specific:**
- NECB uses same values as ASHRAE 90.1 for chillers (inherited)
- Test NECB doesn't override inappropriately

#### 1.3 Furnaces (Standards.CoilHeatingGas.rb - 88 lines)
**Methods to test:**
- `coil_heating_gas_find_capacity()` 
- `coil_heating_gas_standard_minimum_thermal_efficiency()` - AFUE lookups

**Test requirements:**
- SIZING: NONE
- Test inputs: Capacity, fuel type
- Assertions: AFUE values per NECB tables

#### 1.4 Cooling Towers (Standards.CoolingTower.rb - 174 lines)
**Methods to test:**
- `cooling_tower_apply_efficiency_and_curves()` - Fan power rules
- `cooling_tower_single_speed_apply_efficiency_and_curves()`
- `cooling_tower_two_speed_apply_efficiency_and_curves()`
- `cooling_tower_variable_speed_apply_efficiency_and_curves()`

**Test requirements:**
- SIZING: NONE for efficiency lookups
- SIZING: PLANT_SIZING for actual fan power calculation
- NECB-specific: Different fan power rules than ASHRAE 90.1

**Split into two tests:**
1. Pure unit: Test efficiency calculation logic
2. Plant test: Test actual tower in plant loop (use fixture)

#### 1.5 DX Equipment (Multiple Standards.CoilCooling/HeatingDX*.rb - ~1,600 lines)
**Methods to test:**
- COP/EER lookups by capacity/type
- Performance curve assignments
- Multi-speed vs single-speed vs two-speed

**Test requirements:**
- SIZING: NONE (efficiency lookups)
- Large test matrix: cooling vs heating × single/two/multi speed × capacities

#### 1.6 Fans & Pumps (Standards.Fan.rb, Standards.Pump.rb - ~800 lines)
**Methods to test:**
- Pressure drop calculations
- Motor efficiency lookups
- Fan power limitations

**Test requirements:**
- SIZING: NONE for motor efficiency
- SIZING: SYSTEM_SIZING for pressure drops (depends on system)

**NECB-specific:**
- Different fan pressure assumptions than ASHRAE 90.1
- Pump power rules

### 2. BUILDING ENVELOPE (Geometry Tests)

#### 2.1 Construction Lookup & Assignment (NECB2011/building_envelope.rb - 1,520 lines)
**Methods to test:**
- `max_u_necb(stype, condition, hdd)` - U-value limits by HDD
- `model_add_constructions()` - Add construction objects
- `apply_standard_construction_properties()` - Apply to surfaces
- `set_necb_external_surface_conductance()` - Set U-values
- `apply_building_default_constructionset()` - Default construction set

**Test requirements:**
- Pure unit: U-value lookups by HDD (NONE)
- Geometry test: Construction assignment (GEOMETRY_ONLY)
- Data: construction_properties.json, construction_sets.json

**NECB-specific:**
- HDD-based lookup (not climate zone)
- Different assemblies than ASHRAE 90.1
- NECB Tables 3.2.1.x

#### 2.2 Window-to-Wall Ratio (building_envelope.rb)
**Methods to test:**
- `max_fwdr(hdd)` - Max FDWR by HDD
- `apply_standard_window_to_wall_ratio()` - Apply FDWR
- `apply_limit_fdwr()` - Enforce limits
- `apply_max_fdwr_nrcan()` - NRCan-specific rules

**Test requirements:**
- Pure unit: `max_fwdr()` lookup (NONE)
- Geometry test: FDWR enforcement (GEOMETRY_ONLY)

**NECB-specific:**
- NECB Table 3.2.1.4
- HDD-based thresholds

#### 2.3 Skylight-to-Roof Ratio (building_envelope.rb)
**Methods to test:**
- `apply_standard_skylight_to_roof_ratio()`
- `apply_max_srr_nrcan()`

**Test requirements:**
- SIZING: GEOMETRY_ONLY

### 3. THERMAL ZONING (Geometry Tests + Logic)

#### 3.1 Auto-Zoning (NECB2011/autozone.rb - 1,656 lines)
**Methods to test:**
- `model_create_thermal_zones()` - Create zones from spaces
- `apply_auto_zoning()` - Automatic zoning logic
- Space conditioning category tagging

**Test requirements:**
- SIZING: Currently calls sizing but SHOULD NOT
- Pure unit: Zoning algorithm (which spaces → which zones)
- Geometry test: Verify zone creation (GEOMETRY_ONLY)

**NECB-specific:**
- Different zoning rules than ASHRAE 90.1
- Perimeter/core zoning by space type
- Conditioning category tagging for QAQC

**Refactoring needed:** Remove sizing dependency from zoning logic

### 4. HVAC SYSTEMS (System Tests - Need Sizing)

#### 4.1 System Type Selection (NECB2011/hvac_systems.rb - 2,456 lines)
**Methods to test:**
- `apply_systems()` - System selection and application
- System selection logic by building type/size

**Test requirements:**
- SIZING: SYSTEM_SIZING (need zones/loads to select system)
- Input: Building parameters
- Output: Correct NECB system type selected

**NECB-specific:**
- 8 NECB system types
- Selection criteria different from ASHRAE 90.1

#### 4.2 Individual System Creation (hvac_system_*.rb - ~2,000 lines)
**System 1 - PTAC/Baseboard:**
- `add_sys1_unitary_ac_baseboard_heating()` (single & multi-speed)
- Electric, gas, or hot water heat

**System 2/5 - VAV:**
- `add_sys2_FPFC_sys5_TPFC()` 
- Multi-zone VAV with reheat

**System 3/8 - Packaged Rooftop:**
- `add_sys3and8_single_zone_packaged_rooftop_unit()` (single & multi-speed)
- With baseboard heating

**System 4 - MAU:**
- `add_sys4_single_zone_make_up_air_unit_with_baseboard_heating()`

**System 6:**
- `add_sys6_multi_zone_built_up_system_with_baseboard_heating()`

**Test requirements:**
- SIZING: SYSTEM_SIZING (need zone loads, airflow rates)
- Test strategy: Load zone-sized fixture, add system, verify configuration
- For each system: Test control logic, equipment sizing, economizers

**NECB-specific:**
- Different system configurations than ASHRAE 90.1
- Specific control sequences
- ERV requirements by climate zone

#### 4.3 HVAC Component Configuration
**Standards.AirLoopHVAC.rb (3,939 lines) - Inherited methods:**
- Economizer settings
- SAT reset controls
- Fan control
- Outdoor air sizing

**Test requirements:**
- Some pure unit (control logic calculations)
- Most need SYSTEM_SIZING (actual air loop)

### 5. PLANT SYSTEMS (Plant Tests - Need Full Sizing)

#### 5.1 Hot Water Plant (Multiple files)
**Methods to test:**
- Boiler staging rules (NECB 8.4.4.10)
  - ≤176 kW: 1 single-stage boiler
  - 176-352 kW: 2 equal boilers
  - >352 kW: 1 modulating boiler
- Pump sizing and control
- Plant configuration

**Test requirements:**
- SIZING: FULL_SIZING (need building loads to determine plant capacity)
- Test various load profiles → verify correct boiler count/staging

**Implementation:** `setup_hw_loop_with_components()` in hvac_system files

#### 5.2 Chilled Water Plant
**Methods to test:**
- Chiller sizing and selection
- Cooling tower configuration
- Condenser water loop
- Primary/secondary pumping

**Test requirements:**
- SIZING: FULL_SIZING

#### 5.3 Plant Loop Controls (Standards.PlantLoop.rb - 1,545 lines)
**Methods to test:**
- Setpoint schedules
- Loop sizing
- Component staging

**Test requirements:**
- Some pure unit (schedule generation)
- Most need FULL_SIZING

### 6. SERVICE WATER HEATING (Component Tests)

#### 6.1 DHW System Creation (NECB2011/service_water_heating.rb - 705 lines)
**Methods to test:**
- `model_add_swh()` - Add DHW system
- `auto_size_shw_capacity()` - Calculate required capacity
- `auto_size_shw_pump_head()` - Pump sizing
- `friction_factor()` - Pipe friction calculations
- `water_heater_mixed_apply_efficiency()` - Heater efficiency

**Test requirements:**
- Pure unit: Calculations (capacity, pump head, friction) - NONE
- Component test: System creation - ZONE_SIZING (need DHW loads)

**NECB-specific:**
- Different sizing methodology
- Recirculation pump requirements

### 7. FUEL TYPE SELECTION (Pure Unit Tests)

#### 7.1 Fuel Logic (NECB2011/system_fuels.rb - 123 lines)
**Methods to test:**
- `set_defaults()` - Default fuels by province/system
- `set_boiler_fuel()` - Boiler fuel selection
- `set_swh_fuel()` - DHW fuel selection
- `set_fuel_to_hvac_system_primary()` - Primary HVAC fuel
- `reset_default_fuel_info()` - Reset to defaults

**Test requirements:**
- SIZING: NONE (pure logic)
- Input: Province code, system type
- Output: Fuel type string

**NECB-specific:**
- Provincial fuel preferences (BC=electricity, AB=gas, etc.)
- System-dependent fuel rules

### 8. LIGHTING & LOADS (Pure Unit + Geometry Tests)

#### 8.1 Lighting Power Density (NECB2011/lighting.rb - 168 lines)
**Methods to test:**
- LPD lookups by space type
- LED vs standard lighting
- Space type determination

**Test requirements:**
- Pure unit: LPD lookup tables - NONE
- Geometry test: LPD assignment - GEOMETRY_ONLY

#### 8.2 Space Types (Standards.Space.rb, Standards.SpaceType.rb - 2,861 lines)
**Methods to test:**
- Space type assignment
- Load densities (people, plug loads, ventilation)
- Schedule assignments

**Test requirements:**
- Pure unit: Lookup/calculation - NONE
- Geometry test: Assignment - GEOMETRY_ONLY

### 9. VINTAGE DIFFERENCES (Inheritance Tests)

#### 9.1 NECB2015 Changes (703 lines)
**Methods to test:**
- Lighting changes (NECB 4.2.1.5)
- HVAC efficiency changes
- Override verification (ensure 2015 properly overrides 2011 where needed)

#### 9.2 NECB2017 Changes (125 lines)
**Methods to test:**
- Minimal changes from 2015
- Verify inheritance works correctly

#### 9.3 NECB2020 Changes (508 lines)
**Methods to test:**
- New envelope requirements
- New HVAC requirements
- Service water heating changes

**Test requirements:**
- Same as base tests, but verify vintage-specific values
- Test inheritance (2020 → 2017 → 2015 → 2011)

### 10. QAQC COMPLIANCE (Integration Tests)

#### 10.1 NECB QAQC (NECB2011/qaqc/necb_qaqc.rb - 1,947 lines)
**Methods to test:**
- Envelope compliance checks
- HVAC compliance checks
- Lighting compliance checks
- Energy target calculations (BEPS path)
- Compliance report generation

**Test requirements:**
- SIZING: FULL_SIZING + ANNUAL SIMULATION
- Input: Complete building model
- Output: Compliance report, pass/fail

### 11. ENERGY CONSERVATION MEASURES (ECMS - 4,562 lines)

#### 11.1 ERV Package (ECMS/erv.rb)
**Methods to test:**
- ERV selection and application
- Effectiveness by climate zone

#### 11.2 Natural Ventilation (ECMS/nv.rb)
**Methods to test:**
- NV control logic
- Opening sizing

#### 11.3 Ground-Mounted PV (ECMS/pv_ground.rb)
**Methods to test:**
- PV system sizing
- Array configuration

**Test requirements:**
- Varies by ECM
- Most need SYSTEM_SIZING or FULL_SIZING

## Test Organization Hierarchy

```
test/necb/
├── pure_unit/                              # ~150 test methods, <2 min
│   ├── test_boiler_efficiency.rb
│   ├── test_chiller_efficiency.rb
│   ├── test_furnace_efficiency.rb
│   ├── test_dx_equipment_efficiency.rb
│   ├── test_cooling_tower_calculations.rb
│   ├── test_fan_motor_efficiency.rb
│   ├── test_pump_efficiency.rb
│   ├── test_envelope_ulookups.rb
│   ├── test_fdwr_limits.rb
│   ├── test_srr_limits.rb
│   ├── test_fuel_selection.rb
│   ├── test_lpd_lookups.rb
│   ├── test_dhw_calculations.rb
│   ├── test_space_type_loads.rb
│   └── test_vintage_inheritance.rb
│
├── geometry_tests/                         # ~50 test methods, <10 min
│   ├── test_constructions.rb
│   ├── test_fdwr_application.rb
│   ├── test_srr_application.rb
│   ├── test_autozone.rb
│   ├── test_lpd_assignment.rb
│   └── test_space_type_assignment.rb
│
├── component_tests/                        # ~40 test methods, <15 min
│   ├── test_dhw_systems.rb
│   ├── test_zone_equipment.rb
│   ├── test_terminal_units.rb
│   └── test_schedules.rb
│
├── system_tests/                           # ~60 test methods, <45 min
│   ├── test_system_1_single_speed.rb
│   ├── test_system_1_multi_speed.rb
│   ├── test_system_2_vav.rb
│   ├── test_system_3_8_single_speed.rb
│   ├── test_system_3_8_multi_speed.rb
│   ├── test_system_4_mau.rb
│   ├── test_system_5_vav.rb
│   ├── test_system_6_built_up.rb
│   ├── test_system_selection.rb
│   ├── test_economizers.rb
│   ├── test_erv_requirements.rb
│   └── test_air_loop_controls.rb
│
├── plant_tests/                            # ~30 test methods, <30 min
│   ├── test_boiler_staging.rb
│   ├── test_hw_plant.rb
│   ├── test_chw_plant.rb
│   ├── test_cooling_tower_plant.rb
│   └── test_plant_controls.rb
│
├── ecm_tests/                              # ~20 test methods, <20 min
│   ├── test_erv_ecm.rb
│   ├── test_nv_ecm.rb
│   └── test_pv_ecm.rb
│
├── vintage_tests/                          # ~40 test methods, <30 min
│   ├── test_necb2015_overrides.rb
│   ├── test_necb2017_overrides.rb
│   ├── test_necb2020_overrides.rb
│   ├── test_btap_pre1980.rb
│   └── test_btap_1980to2010.rb
│
└── integration_tests/                      # ~15 test methods, variable
    ├── test_qaqc_compliance.rb
    ├── test_beps_path.rb
    └── test_prototype_buildings.rb
```

## Testing Statistics

### Expected Test Count
- **Pure unit tests**: ~150 methods
- **Geometry tests**: ~50 methods
- **Component tests**: ~40 methods
- **System tests**: ~60 methods
- **Plant tests**: ~30 methods
- **ECM tests**: ~20 methods
- **Vintage tests**: ~40 methods
- **Integration tests**: ~15 methods
- **TOTAL**: ~405 test methods

### Execution Time Targets
- **Pure unit**: <2 minutes
- **Geometry**: <10 minutes
- **Component**: <15 minutes
- **System**: <45 minutes
- **Plant**: <30 minutes
- **ECM**: <20 minutes
- **Vintage**: <30 minutes
- **Fast suite total** (pure + geometry + component): <27 minutes
- **Full suite without integration**: <2.5 hours
- **Integration tests**: Run nightly (hours)

### Fixture Requirements

**Fixture Types Needed:**
1. **Base geometry** (5 fixtures): No HVAC, for envelope tests
2. **Zone-sized** (10 fixtures): For component tests
3. **System-sized** (25 fixtures): For system tests (8 systems × 3 building types)
4. **Plant-sized** (15 fixtures): For plant tests (various loads)
5. **Complete prototypes** (20 fixtures): For integration tests

**Total Fixtures**: ~75 models

## Implementation Priority

### Phase 1: Foundation (Week 1)
**Goal:** Eliminate the slowest current tests with pure unit tests

1. Create test/necb/pure_unit/ directory structure
2. Implement efficiency lookup tests:
   - test_boiler_efficiency.rb
   - test_chiller_efficiency.rb  
   - test_furnace_efficiency.rb
   - test_cooling_tower_calculations.rb
3. Implement envelope lookup tests:
   - test_envelope_ulookups.rb
   - test_fdwr_limits.rb
4. Implement fuel selection tests:
   - test_fuel_selection.rb

**Impact**: Replace test_necb_boiler_rules.rb (30 min → 5 sec), test_necb_furnace_rules.rb (20 min → 3 sec)

### Phase 2: Geometry (Week 2)
**Goal:** Test envelope and zoning without HVAC

5. Generate base geometry fixtures
6. Create geometry_tests/ directory
7. Implement:
   - test_constructions.rb
   - test_fdwr_application.rb
   - test_autozone.rb

**Impact**: Replace test_necb_activities.rb (60 min → 2 min)

### Phase 3: Components (Week 3)
**Goal:** Test HVAC components with zone-sized fixtures

8. Generate zone-sized fixtures
9. Create component_tests/ directory
10. Implement:
    - test_dhw_systems.rb
    - test_zone_equipment.rb

**Impact**: Proper isolation of component tests

### Phase 4: Systems (Week 4)
**Goal:** Test complete HVAC systems

11. Generate system-sized fixtures
12. Create system_tests/ directory
13. Implement system tests for all 8 NECB systems

**Impact**: Proper HVAC system test coverage

### Phase 5: Plant & Integration (Week 5)
**Goal:** Complete test suite

14. Generate plant-sized fixtures
15. Implement plant_tests/
16. Implement integration_tests/ for QAQC
17. Document and archive old tests

## Success Metrics

**Current State** (estimated):
- 63 test files
- Heavy on integration/simulation
- 4-8 hours total execution
- Hard to debug failures

**Target State**:
- ~405 focused test methods in ~30 files
- 150 pure unit tests (no model)
- Fast suite: <30 minutes
- Full suite: <3 hours
- Integration optional (nightly)
- Failures pinpoint exact issue
- Clear test categories

## Key Insights

1. **Most efficiency lookups don't need models** - Just test the data tables directly
2. **Inheritance is critical** - NECB vintages inherit from each other and from Standards.*
3. **Sizing stages matter** - Different tests need different sizing levels
4. **Current tests are too coarse** - One test file exercises too many features
5. **Fixtures enable speed** - Pre-sized models eliminate redundant sizing runs
6. **Component Standards need testing too** - Not just NECB-specific code
