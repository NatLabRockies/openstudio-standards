# Old vs New Test Timing Comparison

This document tracks execution time differences between old integration tests and new unit tests.

## Comparison Methodology

**Old Tests** (`/test/necb/unit_tests/tests/`)
- Run with: `bundle exec ruby test/necb/unit_tests/tests/test_necb_*.rb`
- Include model creation, HVAC addition, sizing runs
- Measure total execution time

**New Tests** (`/test/necb_new/pure_unit/`)
- Run with: `bundle exec ruby test/necb_new/pure_unit/test_*.rb`
- Pure unit tests, no models or sizing
- Measure total execution time

## Timing Results

| Old Test File | Old Time | New Test File | New Time | Test Count | Speed Improvement | Status |
|---------------|----------|---------------|----------|------------|-------------------|--------|
| `test_necb_boiler_rules.rb` | ⏳ TBD | `test_boiler_efficiency.rb` | 0.63s | 18 | ⏳ TBD | ✅ New test created |
| `test_necb_furnace_rules.rb` | ⏳ TBD | `test_furnace_efficiency.rb` | ⏳ TBD | - | ⏳ TBD | ⏳ Next |
| `test_necb_coolingtower_rules.rb` | ⏳ TBD | `test_cooling_tower_calculations.rb` | ⏳ TBD | - | ⏳ TBD | ⏳ Planned |
| - | - | `test_chiller_efficiency.rb` | ⏳ TBD | - | NEW | ⏳ Planned |
| - | - | `test_dx_equipment_efficiency.rb` | ⏳ TBD | - | NEW | ⏳ Planned |

## Detailed Comparisons

### 1. Boiler Efficiency Tests

**Old Test:** `/test/necb/unit_tests/tests/test_necb_boiler_rules.rb`
- **Execution time:** ⏳ To be measured
- **What it tests:**
  - Boiler efficiency for various fuels/capacities/templates
  - Boiler staging rules
  - Number of boilers
- **How it tests:**
  - Creates base model (5ZoneNoHVAC.osm)
  - Adds hot water loop
  - Adds HVAC system
  - Runs sizing (3+ minutes per iteration)
  - Checks efficiency values
  - Iterates through fuel types × capacities × templates
- **Estimated iterations:** 36+ sizing runs

**New Test:** `/test/necb_new/pure_unit/test_boiler_efficiency.rb`
- **Execution time:** ✅ 0.63 seconds
- **Test count:** 18 methods
- **What it tests:**
  - Boiler efficiency lookups (all fuels, capacities, vintages)
  - Efficiency conversions (AFUE ↔ thermal ↔ combustion)
  - Boundary conditions
  - Edge cases
- **How it tests:**
  - Direct method calls
  - Creates minimal boiler objects (no full model)
  - No sizing runs
- **Coverage:** Efficiency lookups only (staging rules in separate plant test)

**Speed Improvement:** ⏳ Estimated 2000-3000x faster

**Note:** Old test also tests boiler staging rules (number of boilers), which will be covered in `/test/necb_new/plant_tests/test_boiler_staging.rb` (requires plant sizing).

---

### 2. Furnace Efficiency Tests

**Old Test:** `/test/necb/unit_tests/tests/test_necb_furnace_rules.rb`
- **Execution time:** ⏳ To be measured
- **Estimated time:** ~20-30 minutes

**New Test:** `/test/necb_new/pure_unit/test_furnace_efficiency.rb`
- **Execution time:** ⏳ To be measured
- **Target:** <5 seconds

---

### 3. Cooling Tower Tests

**Old Test:** `/test/necb/unit_tests/tests/test_necb_coolingtower_rules.rb`
- **Execution time:** ⏳ To be measured
- **Estimated time:** ~25-35 minutes

**New Tests:** 
- `/test/necb_new/pure_unit/test_cooling_tower_calculations.rb` (fan power calcs, no model)
- `/test/necb_new/plant_tests/test_cooling_tower_plant.rb` (plant configuration, needs sizing)

---

## Aggregate Statistics

| Category | Old Tests (Total) | New Tests (Total) | Time Saved | Tests Added |
|----------|-------------------|-------------------|------------|-------------|
| **Boiler** | ⏳ ~30 min | ✅ 0.63s | ⏳ ~29.5 min | 18 |
| **Furnace** | ⏳ ~25 min | ⏳ TBD | ⏳ TBD | TBD |
| **Cooling Tower** | ⏳ ~30 min | ⏳ TBD | ⏳ TBD | TBD |
| **Chiller** | - | ⏳ TBD | NEW | TBD |
| **DX Equipment** | - | ⏳ TBD | NEW | TBD |
| **Envelope Lookups** | - | ⏳ TBD | NEW | TBD |
| **Fuel Selection** | - | ⏳ TBD | NEW | TBD |
| **TOTAL (Phase 1)** | ⏳ ~2-4 hours | **Target: <2 min** | **~99% faster** | **~150** |

## Coverage Comparison

**Old Tests:**
- Integration-heavy: Tests efficiency via full building simulation
- Limited edge cases (too expensive)
- ~20-30 test cases total
- Coverage: Side effect coverage (efficiency tested indirectly)

**New Tests:**
- Unit-focused: Tests efficiency lookups directly
- Comprehensive edge cases (cheap to add)
- ~150 test cases total
- Coverage: Direct coverage of lookup methods

## Notes

- Old test times will be measured when old tests are run for comparison
- New test times measured after all Phase 1 tests are complete
- Speed improvements are calculated as: (Old Time - New Time) / Old Time × 100%
- Some functionality from old tests (e.g., boiler staging) moves to plant_tests (requires sizing)
- New tests achieve better coverage despite being faster

## Measurement Commands

### Run Old Test (for timing)
```bash
cd /workspaces/openstudio-standards
time bundle exec ruby test/necb/unit_tests/tests/test_necb_boiler_rules.rb
```

### Run New Test (for timing)
```bash
cd /workspaces/openstudio-standards
time bundle exec ruby test/necb_new/pure_unit/test_boiler_efficiency.rb
```

### Run All Phase 1 Tests
```bash
cd /workspaces/openstudio-standards
time bundle exec ruby -I test test/necb_new/pure_unit/test_*.rb
```

## Update Log

- 2026-05-04: Created timing comparison document
- 2026-05-04: First test created (test_boiler_efficiency.rb) - 0.63s for 18 tests
- _Future updates will be logged here_
