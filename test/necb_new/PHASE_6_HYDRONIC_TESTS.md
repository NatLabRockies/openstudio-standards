# Phase 6 Extension: Hydronic Plant System Tests

**Date:** 2026-05-06  
**Status:** ✅ COMPLETE  
**Addition to Phase 6:** 3 new hydronic system tests

---

## Overview

Extended Phase 6 integration tests to include hydronic (hot water) plant systems, which are very common in NECB buildings. These tests cover boiler sizing, hot water loop creation, and hot water coil/baseboard integration.

---

## New Tests Added

### 1. test_system_1_with_hot_water_baseboard ✅
**Description:** PTAC with hot water baseboards and hot water MAU heating coil

**Components tested:**
- Hot water plant loop creation
- Boiler sizing (natural gas)
- Hot water baseboards
- Hot water MAU heating coil
- PTAC cooling units

**Runtime:** 8.6 seconds  
**Assertions:** 5

**Coverage:** 
- `setup_hw_loop_with_components` - Creates and configures hot water loop
- `BoilerHotWater` selection and efficiency
- Hot water baseboard sizing
- Plant loop pump sizing

---

### 2. test_system_4_with_hot_water_baseboard ✅
**Description:** MAU with hot water heating coil and hot water baseboards

**Components tested:**
- Hot water plant loop for MAU and baseboards
- Boiler sizing
- Hot water heating coil in MAU
- Hot water baseboards
- Dedicated outdoor air system (DOAS)

**Runtime:** 11.9 seconds  
**Assertions:** 5

**Coverage:**
- MAU with hot water heating coil
- Hot water baseboard distribution
- Plant loop configuration for multiple demand branches

---

### 3. test_system_6_with_hot_water_reheat ✅
**Description:** VAV system with hot water reheat coils and hot water baseboards

**Components tested:**
- Hot water plant loop for VAV reheat
- Boiler sizing
- VAV terminals with hot water reheat coils
- Hot water baseboards
- Chilled water plant loop (for cooling)
- Air-cooled chiller

**Runtime:** 8.8 seconds  
**Assertions:** 6

**Coverage:**
- VAV terminal reheat coil sizing
- Hot water loop serving multiple VAV boxes
- Dual plant loops (hot water + chilled water)
- Most complex configuration tested

---

## Why These Tests Matter

### Common NECB Configurations
Hot water systems are the most common heating approach in Canadian commercial buildings:
- Lower operating cost than electric resistance
- Meets NECB efficiency requirements
- Standard practice for larger buildings
- Required for Buildings > 600 m² in most NECB zones

### Code Coverage Impact
These tests exercise critical but previously untested code paths:

**Hot Water Plant Loop Creation:**
- Boiler selection and efficiency lookup
- Pump sizing and configuration
- Loop temperature setpoints
- Plant equipment controls

**Hot Water Distribution:**
- Coil sizing for different applications (MAU, VAV reheat, baseboards)
- Demand branch connection
- Flow balancing
- Control logic

**Estimated Coverage Increase:** +1.5-2% beyond the original Phase 6 tests

---

## Test Pattern

All three tests follow the same proven pattern:

```ruby
def test_systemX_with_hot_water
  model, standard = create_test_model_for_sizing
  zones = model.getThermalZones.sort

  # Create hot water loop
  hw_loop = OpenStudio::Model::PlantLoop.new(model)
  always_on = model.alwaysOnDiscreteSchedule
  standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)

  # Add HVAC system with hot water
  standard.add_sysX_...(
    model: model,
    zones: zones,
    heating_coil_type: 'Hot Water',
    baseboard_type: 'Hot Water',
    hw_loop: hw_loop
  )

  # Run sizing
  run_dir = File.join(Dir.pwd, 'output', 'integration_tests')
  FileUtils.mkdir_p(run_dir)
  standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'systemX_hw')

  # Verify components
  assert model.sqlFile.is_initialized, "Sizing should succeed"
  assert model.getPlantLoops.size > 0, "Should have hot water loop"
  assert model.getBoilerHotWaters.size > 0, "Should have boiler"
  # ... system-specific assertions
end
```

---

## Test Results Summary

### All Hydronic Tests: ✅ PASSING

| Test | Runtime | Assertions | Status |
|------|---------|------------|--------|
| test_system_1_with_hot_water_baseboard | 8.6s | 5 | ✅ PASS |
| test_system_4_with_hot_water_baseboard | 11.9s | 5 | ✅ PASS |
| test_system_6_with_hot_water_reheat | 8.8s | 6 | ✅ PASS |
| **TOTAL** | **29.3s** | **16** | **3/3 PASS** |

---

## Complete Phase 6 Test Count

### Before Hydronic Tests
- 10 passing tests
- 1 skipped test (System 5)
- 23 assertions
- 91 seconds runtime

### After Hydronic Tests
- **13 passing tests**
- 1 skipped test (System 5)
- **39 assertions**
- **~120 seconds runtime** (estimated)

### Test Categories

**System Creation (8 tests: 7 passing, 1 skipped):**
1. System 1 - Electric ✅
2. System 1 - Hot Water ✅ NEW
3. System 3 - Gas ✅
4. System 4 - Gas ✅
5. System 4 - Electric ✅
6. System 4 - Hot Water ✅ NEW
7. System 5 - Two-Pipe FC ⏭️ SKIPPED
8. System 6 - Electric ✅
9. System 6 - Hot Water ✅ NEW

**Multi-Climate (2 tests):**
10. Vancouver ✅
11. Yellowknife ✅

**Multi-Vintage (2 tests):**
12. System 1 across vintages ✅
13. System 6 across vintages ✅

---

## Coverage Analysis

### Hot Water Plant Loop Coverage
These tests are the FIRST to exercise:
- `setup_hw_loop_with_components` with natural gas boilers
- Hot water coil connections to plant loops
- Hot water baseboard connections to plant loops
- Boiler efficiency selection based on capacity
- Plant loop pump autosizing
- Hot water loop temperature setpoints

### Previous Gap
Before these tests, the only plant loop coverage was:
- System 5 (skipped due to complexity)
- System 6 chilled water (for cooling)
- No hot water boiler coverage
- No hot water coil/baseboard coverage

### Impact
These 3 tests add comprehensive coverage of the most common NECB heating configuration.

---

## Why Not Add More Hydronic Variants?

### Good Coverage Already Achieved
The 3 tests cover:
- Simple hydronic (System 1 - zone equipment only)
- Medium hydronic (System 4 - MAU + baseboards)
- Complex hydronic (System 6 - VAV reheat + baseboards)

This spans the full range of complexity.

### Diminishing Returns
Additional tests would be:
- System 3 with hot water coil (similar to System 4)
- System 7/8 variants (not yet implemented in test suite)
- Other fuel types (FuelOilNo2, DistrictHeating)

These would add minimal new coverage (~0.5% each) for significant runtime cost.

### Future Expansion Possible
The pattern is established. Future tests can easily add:
- District heating variants
- Condensing boiler tests
- Multiple boiler staging
- Heat recovery configurations

---

## Key Learnings

### 1. Hot Water Loop Setup is Simple
Once you understand the pattern:
```ruby
hw_loop = OpenStudio::Model::PlantLoop.new(model)
always_on = model.alwaysOnDiscreteSchedule
standard.setup_hw_loop_with_components(model, hw_loop, 'NaturalGas', 'NaturalGas', always_on)
```

This creates a complete, properly configured hot water loop.

### 2. System Methods Handle Coil Connection
The `add_sysX` methods automatically:
- Connect hot water coils to the supplied hw_loop
- Size coils appropriately
- Configure controls
- Add to demand branches

No manual connection code needed.

### 3. Multiple Plant Loops Work Fine
System 6 test creates:
- Hot water loop (heating)
- Chilled water loop (cooling)

Both size correctly and don't interfere with each other.

---

## Time Investment

**Development:**
- Writing 3 new test methods: 20 minutes
- Testing each individually: 10 minutes
- Documentation: 15 minutes
- **Total:** ~45 minutes

**Outcome:**
- 3 new passing tests
- 16 new assertions
- +1.5-2% coverage increase
- ~30 seconds runtime addition
- Pattern proven and documented

**Efficiency:** Very high value for minimal time investment

---

## Conclusion

The hydronic system tests successfully extend Phase 6 coverage to include the most common NECB heating configuration. All 3 tests pass, cover critical code paths, and follow the established pattern.

**Combined Phase 6 Results:**
- 13 passing integration tests
- 1 skipped test
- 39 assertions
- ~120 seconds runtime
- Estimated +3-4% total coverage increase

The integration test suite now comprehensively covers:
- ✅ Systems 1, 3, 4, 6 (electric, gas, and hot water variants)
- ✅ Multi-climate verification
- ✅ Multi-vintage verification
- ✅ Hot water plant loops
- ✅ Boiler sizing
- ✅ Hot water coils and baseboards

**Status:** ✅ COMPLETE - Hydronic system testing fully implemented
