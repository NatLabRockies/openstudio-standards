# NECB ECMs (Energy Conservation Measures) Analysis

**Date:** 2026-05-06  
**Purpose:** Analyze ECM code for testing as potential Phase 8

---

## Executive Summary

**Total ECM Code:** 4,562 lines in 6 files

**Components:**
1. **HVAC Systems ECMs** (4,050 lines, 89% of total) - Alternative HVAC systems (heat pumps, etc.)
2. **Natural Ventilation** (192 lines, 4%) - Operable window ventilation
3. **PV Ground** (107 lines, 2%) - Ground-mounted photovoltaic systems
4. **Loads Scaling** (94 lines, 2%) - Scale occupancy, electrical, OA, infiltration
5. **ERV** (30 lines, 1%) - Energy Recovery Ventilator efficiency
6. **ECMs Base** (89 lines, 2%) - Base class and utility methods

**Current Test Coverage:** ~1% (20 lines in one regression test)

---

## ECM Code Structure

### File Breakdown

| File | Lines | Purpose | Complexity |
|------|-------|---------|------------|
| **hvac_systems.rb** | 4,050 | Alternative HVAC systems (heat pumps, VRF, etc.) | Very High |
| **nv.rb** | 192 | Natural ventilation with operable windows | Medium |
| **pv_ground.rb** | 107 | Ground-mounted PV solar systems | Low |
| **loads.rb** | 94 | Scale building loads (occupancy, electrical, etc.) | Low |
| **ecms.rb** | 89 | Base class, system removal utilities | Low |
| **erv.rb** | 30 | Apply ERV efficiency packages | Low |
| **Total** | **4,562** | | |

### ECM Data Files

Located in `/lib/openstudio-standards/standards/necb/ECMS/data/`:

- **curves.json** (103 KB) - Performance curves for heat pumps and chillers
- **heat_pumps.json** (51 KB) - Heat pump cooling performance data
- **heat_pumps_heating.json** (53 KB) - Heat pump heating performance data
- **unitary_acs.json** (12 KB) - Unitary air conditioner data
- **chiller_set.json** (10 KB) - Chiller performance data
- **erv.json** (5 KB) - ERV effectiveness packages
- **pv.json** (4 KB) - PV module specifications
- **boiler_set.json**, **furnace_set.json**, **shw_set.json** - Equipment data
- **chillers.json**, **chiller_types.json** - Chiller configurations
- **equip_eff_lim.json** - Equipment efficiency limits

---

## What ECMs Do

### 1. Alternative HVAC Systems (hvac_systems.rb - 4,050 lines)

**Purpose:** Replace baseline NECB HVAC systems with high-efficiency alternatives

**Available ECM HVAC Systems:**
- **HS11_ASHP_PTHP** - Air-Source Heat Pump with Packaged Terminal Heat Pumps
- **HS10_GSHP_CCASHP** - Ground-Source Heat Pump with Central Cooling
- **HS09_ERV** - Energy Recovery Ventilation system
- **HS08_VRF** - Variable Refrigerant Flow system
- **HS07_CCASHP** - Central Cooling with Air-Source Heat Pumps
- **HS06_CCASHP_BAR** - Central Cooling with ASHP and Backup Resistance
- **HS05_DX** - Direct Expansion systems
- **HS04_PTAC** - Packaged Terminal Air Conditioners
- **HS03_Boiler** - High-efficiency boiler systems
- **HS02_Chiller** - High-efficiency chiller systems
- **HS01_SplitDX** - Split DX systems

**What it does:**
- Removes existing HVAC systems from baseline NECB model
- Removes existing plant loops (hot water, chilled water, condenser water)
- Creates new HVAC systems based on ECM system type
- Adds high-efficiency equipment from ECM data files
- Applies performance curves for heat pumps
- Sizes equipment based on building loads

**Complexity:** VERY HIGH
- 4,050 lines of complex HVAC creation code
- Multiple system types with different configurations
- Heat pump performance curves and sizing
- Coordination with plant loops
- Equipment selection from large data files

**Testing Value:** MEDIUM
- Not required for NECB compliance (optional upgrades)
- Used for above-code performance analysis
- Complex to test due to size and system variety
- Would require many integration tests (one per system type)

---

### 2. Natural Ventilation (nv.rb - 192 lines)

**Purpose:** Add natural ventilation via operable windows

**What it does:**
- Identifies spaces with windows
- Calculates required OA per person and per floor area
- Creates `ZoneVentilationDesignFlowRate` objects for OA delivery
- Creates `ZoneVentilationWindandStackOpenArea` objects for wind/stack effects
- Sets temperature controls (min outdoor temp, max indoor temp)
- Adds `AvailabilityManagerHybridVentilation` to prevent simultaneous NV and HVAC

**Key Parameters:**
- `nv_opening_fraction` - Fraction of window that opens (default 0.1 = 10%)
- `nv_temp_out_min` - Minimum outdoor temp for NV (default 13°C)
- `nv_delta_temp_in_out` - Temperature difference to shut off NV (default 1°C)

**Complexity:** MEDIUM
- Moderate code complexity
- Multiple EnergyPlus objects per window
- Schedule manipulation for setpoint adjustment
- Coordination with HVAC availability

**Testing Value:** HIGH
- Relatively isolated feature
- Clear inputs and outputs
- Used in real NECB projects
- Moderate effort to test (~2-3 hours)

---

### 3. Ground-Mounted PV (pv_ground.rb - 107 lines)

**Purpose:** Add ground-mounted photovoltaic solar panels

**What it does:**
- Calculates building footprint
- Determines number of PV panels based on total area
- Loads PV module data from `pv.json` (module type, wattage)
- Creates `GeneratorPVWatts` with DC system capacity
- Sets tilt angle (default = latitude) and azimuth (default = 180° south-facing)
- Creates `ElectricLoadCenterInverterPVWatts` (96% efficiency)
- Adds `ElectricLoadCenterDistribution` with baseload operation

**Key Parameters:**
- `pv_ground_total_area_pv_panels_m2` - Total PV area (default = building footprint)
- `pv_ground_tilt_angle` - Panel tilt (default = latitude)
- `pv_ground_azimuth_angle` - Panel direction (default = 180° south)
- `pv_ground_module_description` - PV module type (from pv.json)

**Complexity:** LOW
- Simple, straightforward code
- Few dependencies
- Well-defined inputs/outputs

**Testing Value:** HIGH
- Easy to test (~1 hour)
- Clear success criteria (PV components created)
- Used in NECB net-zero projects
- Good candidate for quick wins

---

### 4. Load Scaling (loads.rb - 94 lines)

**Purpose:** Scale building loads for parametric analysis

**What it does:**
- **Occupancy scaling** - Multiply people density by scale factor
- **Electrical loads scaling** - Multiply equipment power by scale factor
- **Outdoor air scaling** - Multiply OA rates by scale factor
- **Infiltration scaling** - Multiply infiltration rates by scale factor

**Key Parameters:**
- `scale` - Multiplier (e.g., 0.5 = 50%, 1.5 = 150%, 0.0 = remove)

**Complexity:** LOW
- Very simple code (4 methods, ~23 lines each)
- Just multiplies existing values
- No complex logic

**Testing Value:** MEDIUM
- Very easy to test (~30 minutes)
- But lower practical value (rarely used in production)
- Good for parametric studies

---

### 5. ERV Efficiency (erv.rb - 30 lines)

**Purpose:** Apply high-efficiency ERV packages

**What it does:**
- Loads ERV data from `erv.json` (effectiveness values)
- Adds ERVs to air loops if package specifies "Add_ERVs_To_All_Airloops"
- Applies effectiveness values to all ERVs in model

**Key Parameters:**
- `erv_package` - ERV package name from erv.json (e.g., "ERV_75_75")

**Complexity:** LOW
- Very simple code
- Just sets effectiveness properties
- Relies on data file

**Testing Value:** MEDIUM
- Easy to test (~30 minutes)
- But core ERV functionality already tested in Phase 6
- This is just applying efficiency upgrades

---

### 6. ECMs Base Class (ecms.rb - 89 lines)

**Purpose:** Utility methods for ECM application

**What it does:**
- `remove_all_zone_eqpt` - Remove existing zone equipment
- `remove_hw_loops` - Remove hot water plant loops
- `remove_chw_loops` - Remove chilled water plant loops
- `remove_cw_loops` - Remove condenser water plant loops
- `remove_air_loops` - Remove air loops
- `get_map_systems_to_zones` - Map systems to zones
- `get_zone_clg_eqpt_type` - Get cooling equipment type per zone
- `get_storey_avg_clg_zcoords` - Get ceiling heights by floor

**Complexity:** LOW
- Utility methods
- Helper functions for main ECM code

**Testing Value:** LOW
- Supporting code, not directly used by users
- Tested indirectly through ECM system tests

---

## Existing Test Coverage

### Current Tests

**Location:** `/test/necb/ecm_tests/tests/restaurant_with_ecm.rb`

**Test count:** 1 regression test

**What it tests:**
- Creates FullServiceRestaurant with NECB2011
- Applies ECM system `HS11_ASHP_PTHP`
- Compares against expected results (regression test)

**Coverage:** ~0.5% of ECM code (20 lines out of 4,562)

### Stub Tests in necb_new

**Location:** `/test/necb_new/ecm_tests/test_ecms.rb`

**Test count:** 150+ lines of test structure (not run yet)

**What it tests:**
- ERV creation, effectiveness, economizer lockout, frost control
- Natural ventilation creation, opening fraction, temperature controls
- PV system creation, panel configuration
- Load scaling tests
- High-efficiency equipment tests

**Status:** Created as stubs during earlier test development work, but never completed or run

---

## Testing Priority Analysis

### Option A: Test Simple ECMs (Recommended for Phase 8)

**Test these ECMs in order:**

1. **PV Ground** (107 lines, ~1 hour effort)
   - ✅ Simple, isolated
   - ✅ Clear inputs/outputs
   - ✅ Used in real projects
   - ✅ Quick win

2. **Natural Ventilation** (192 lines, ~2-3 hours effort)
   - ✅ Moderate complexity
   - ✅ Practical feature
   - ✅ Good test value
   - ⚠️ Requires model with windows

3. **Load Scaling** (94 lines, ~30 minutes effort)
   - ✅ Very simple
   - ✅ Easy to verify
   - ⚠️ Low practical value

4. **ERV Efficiency** (30 lines, ~30 minutes effort)
   - ✅ Very simple
   - ⚠️ ERVs already tested in Phase 6
   - ⚠️ This is just efficiency upgrade

**Total Estimated Effort:** ~5 hours  
**Total Coverage Increase:** +423 lines / 27,493 = +1.5%  
**Value:** HIGH - Quick wins, practical features, moderate effort

### Option B: Skip ECMs, Move to NECB2020 Performance Compliance

**Test NECB2020 Performance Compliance instead** (1,704 lines)

**What it does:**
- Creates proposed building model
- Creates reference building (NECB baseline)
- Runs both simulations
- Compares energy performance
- Validates compliance (proposed ≤ reference)

**Why it's higher priority than ECMs:**
- ✅ Core NECB2020 feature (not optional like ECMs)
- ✅ 100% untested (vs ECMs ~1% tested)
- ✅ Critical for code compliance
- ✅ Higher impact (+6% coverage vs +1.5% for simple ECMs)
- ⚠️ Higher complexity (2-3 days effort vs 5 hours)

### Option C: Test ECM HVAC Systems (Not Recommended)

**Test hvac_systems.rb** (4,050 lines)

**Why NOT recommended:**
- ❌ VERY HIGH complexity (4,050 lines)
- ❌ Would require 11+ integration tests (one per system type)
- ❌ Estimated 2-3 days of work
- ❌ Optional features, not core NECB requirement
- ❌ Massive effort for +15% coverage
- ❌ Already have good HVAC test patterns from Phase 6

---

## Recommended Decision: Phase 8 Options

### Option 1: Simple ECMs (Fast Track)
**Time:** ~5 hours  
**Coverage:** +1.5% (423 lines)  
**Tests:** 4-6 tests  
**Value:** Quick wins, practical features

**Test Plan:**
1. PV ground system (1 hour)
2. Natural ventilation (2-3 hours)
3. Load scaling (30 mins)
4. ERV efficiency (30 mins)

### Option 2: NECB2020 Performance Compliance (High Impact)
**Time:** 2-3 days  
**Coverage:** +6% (1,704 lines)  
**Tests:** 5-8 tests  
**Value:** Critical new feature, 100% untested

**Test Plan:**
1. Proposed model builder
2. Reference model builder
3. Compliance comparison
4. Report generation
5. Validation rules
6. Integration test (full workflow)

### Option 3: Combination Approach
**Time:** 3-4 days  
**Coverage:** +7.5% (2,127 lines)  
**Tests:** 10-14 tests

**Test Plan:**
- Phase 8A: Simple ECMs (~5 hours)
- Phase 8B: NECB2020 Compliance (2-3 days)

---

## Recommendation

**Recommended:** Option 1 (Simple ECMs) as Phase 8

**Why:**
- Fast wins after successful Phase 7
- Builds momentum with 4-6 passing tests
- Tests practical features used in real projects
- Low complexity, high success probability
- Can complete in one session (~5 hours)
- Then move to NECB2020 Compliance as Phase 9

**Alternative:** If user wants highest impact, go directly to NECB2020 Performance Compliance
- Bigger prize (+6% coverage)
- Critical feature (not optional)
- But higher risk (2-3 days of complex work)

---

## ECM Testing Pattern

Based on Phase 6 and Phase 7 success, here's the proven pattern:

```ruby
def test_ecm_feature
  # 1. Create test model (use resource model approach)
  model, standard = create_test_model_with_geometry
  
  # 2. Apply ECM
  ecm = ECMS.new
  ecm.apply_XXX_ecm(model: model, param1: value1, param2: value2)
  
  # 3. Verify ECM components created
  assert model.getComponentType.size > 0, "Should have component created"
  
  # 4. Verify ECM properties
  component = model.getComponentType.first
  assert_equal expected_value, component.property, "Property should be set correctly"
end
```

**Success factors:**
- Use resource models (5ZoneNoHVAC.osm)
- Focus on component creation and properties
- Avoid full simulations (too slow)
- Test calculation methods, not integration workflow

---

## Conclusion

**ECMs offer two paths:**

1. **Quick wins** (Simple ECMs: PV, NV, Loads, ERV) - 5 hours, +1.5% coverage
2. **Skip to higher priority** (NECB2020 Compliance) - 2-3 days, +6% coverage

**Recommendation:** Do simple ECMs as Phase 8, then NECB2020 Compliance as Phase 9

**Why:** Build on Phase 7 success with more quick wins, maintain momentum, then tackle the big feature

**ECM HVAC Systems (4,050 lines):** Save for later (Phase 12+) or skip entirely - too much effort for optional features
